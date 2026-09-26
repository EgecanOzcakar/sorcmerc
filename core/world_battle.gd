# O5 — off-screen battle resolution: when two NON-player parties meet, they
# fight, headless, with no scene and no pause (O4 owns the player's fights;
# this never touches a pair the player is in). The loser is removed from the
# world, the winner marches on.
#
#   WorldBattle.check(world, ENCOUNTER_RADIUS, encounter_spec)   # once per frame
#   WorldBattle.start(world, radius, spec_for)   # just the meetings (check's second half)
#   WorldBattle.settle(world)                    # just the endings (check's first half)
#   WorldBattle.round_of(clash, now)             # which round it is on, for the map's label
#   WorldBattle.other_side(world, clash, band)   # who `band` is fighting
#
# #229 — a battle takes TIME. It used to resolve in the frame the two bands
# touched: one of them simply vanished, ten rounds of fighting in no world
# time at all. Now meeting opens a CLASH (World.clashes, core/world.gd): both
# bands are held where they stand — World.tick() does not walk them,
# WorldAI.update() does not steer them — for as many rounds as the fight
# actually lasted at MINUTES_PER_ROUND each, and only when the clock has run
# through all of them does the loser fall.
#
# The fight itself is still fought ONCE, headless, in the frame they meet; the
# clock only tells it. That is deliberate rather than lazy. Stepping a live
# Combat a round at a time would put a whole Combat — board, statuses, rng —
# into the save, or else lose the fight on every reload; fighting it up front
# puts four fields there instead (winner, outcome, rounds, until), and the
# determinism idiom comes for free: the seed is the pair's own ids, the
# verdict is saved, and reloading mid-battle cannot reroll it. The one thing
# it costs is that the roster each side fields is priced at the moment of
# contact (encounter_spec reads the player's party), which is also when the
# two bands actually squared up.
#
# The player arriving mid-battle: both bands have their hands full, so neither
# stops to deal with the party. scenes/world/world.gd's _check_encounter skips
# a band in a clash, so the party can stand and watch it or walk straight past;
# its figure is not clickable (_band_at), so a click on it is a march to the
# spot; and a band the party was already following into a fight stops the
# march at its edge (_meet) with a line saying who is fighting whom. The
# moment it ends the winner is an ordinary band again: if it is hostile and the
# party is still beside it, the ordinary approach card opens.
# Wading in as a third side is not a thing yet (docs/plan/2026-09-25-band-wars-
# take-time.md, "Still open").
#
# #227 — and it is SILENT. Every sting in combat.gd goes through Combat.audible,
# which this file turns off: the fight is resolved from the map screen, where
# the Audio autoload is live, and every kill and collapse in it used to ring
# out over the campaign map in one frame.
#
# It lives in core/ rather than in scenes/world/world.gd because none of it is
# rendering: it is the same seeded `AI.take_turn` autoplay loop tests/
# test_scaler.gd's sweeps run, so it wants to be testable without a Control.
# What it does NOT own: the faction -> roster mapping, which is O4's
# `encounter_spec()` in the map scene — that comes in as a Callable instead of
# being re-derived here; holding the bands still, which is World.tick()'s and
# WorldAI.update()'s job once a clash names them; saving the clashes
# (core/world_save.gd); and drawing them (scenes/world/world.gd's ground_marks,
# scenes/world/party3d.gd's brawl).
extends RefCounted

const Encounter = preload("res://core/encounter.gd")
const AI = preload("res://core/ai.gd")
const WorldAI = preload("res://core/world_ai.gd")

const MAX_TURNS := 5000     # the same runaway guard test_scaler.gd's sweeps use
# #229: world-minutes one round of a band-vs-band fight holds the two bands.
# Not the party's hour a round (scenes/world/world.gd's MINUTES_PER_ROUND):
# that is a bill on the PARTY's day — the chase, the looting, the binding of
# wounds — and two bands' AI-vs-AI fight runs about twice the rounds a party's
# does, so billed an hour a round the median clash would take two bands off the
# map for ten hours, and the long tail for a day and a half.
# MEASURED 2026-09-25, WorldBattle.fight over every hostile pairing of ten map
# factions (goblinoid beast undead bandit orc gnoll kobold human elf dwarf, two
# seeds each, Presets.party() rosters at "normal", the civilized three on the
# soldier roster as encounter_spec does): 84 fights, ROUNDS MEDIAN 10, MEAN
# 11.6, P90 18, MAX 35, MIN 3. At 10 a round that is a median clash of 1h40 on
# the clock (100 real seconds at 1x, 12 at 8x — long enough to walk up to and
# watch), p90 3h, the longest just under 6h.
# ponytail: a taste number over a measured distribution, not a balance knob —
# nothing wins or loses by it. Re-measure if the AI or the rosters change how
# long a band's fight runs.
const MINUTES_PER_ROUND := 10.0

# One frame's worth: the fights whose time is up end, then any hostile pair
# that has just met starts one. Returns one {winner, loser, outcome, rounds}
# per fight that ENDED this call — the shape the map screen always read, only
# now it arrives when the fight is over instead of when it began.
static func check(world, radius: float, spec_for: Callable) -> Array:
	var done := settle(world)
	start(world, radius, spec_for)
	return done

# Every hostile non-player pair inside `radius`, neither already fighting,
# fights: the verdict is decided now and a clash is opened for it. Returns the
# clashes opened.
# ponytail: O(n^2) over 3-8 parties once a frame, per O1's own "no index yet" note.
static func start(world, radius: float, spec_for: Callable) -> Array:
	var opened: Array = []
	var busy := {}
	for c in world.clashes:
		busy[c["a"]] = true
		busy[c["b"]] = true
	var ps: Array = world.parties.duplicate()
	for i in ps.size():
		var a = ps[i]
		if a.is_player or busy.has(a.id):
			continue
		for j in range(i + 1, ps.size()):
			var b = ps[j]
			# The player's encounters are O4's job — never resolve one here.
			if b.is_player or busy.has(b.id):
				continue
			if a.position.distance_to(b.position) > radius:
				continue
			# Hostility is one-directional (world_ai.gd): either side wanting the
			# other dead is a fight.
			if not (WorldAI.is_hostile(a, b) or WorldAI.is_hostile(b, a)):
				continue
			var c := fight(world, a, b, spec_for)
			world.clashes.append(c)
			opened.append(c)
			busy[a.id] = true
			busy[b.id] = true
			break   # `a` is taken; the rest of its row waits for the winner
	return opened

# Every clash whose last round the clock has now run through ends: the loser
# falls (#142: a monster band comes back) and leaves the map, the winner is
# free. A clash one side of which has left the map some other way meanwhile —
# raids.gd sends home raiders whose lair is gone — ends there, with nobody
# lost: the fight it was telling never finished.
static func settle(world) -> Array:
	var done: Array = []
	if world.clashes.is_empty():
		return done
	var now: float = world.clock.elapsed
	for c in world.clashes.duplicate():
		var a = _party(world, String(c["a"]))
		var b = _party(world, String(c["b"]))
		if a != null and b != null and now < float(c["until"]):
			continue
		world.clashes.erase(c)
		if a == null or b == null:
			continue
		var winner = a if String(c["winner"]) == a.id else b
		var loser = b if winner == a else a
		WorldAI.fell(world, loser)
		world.parties.erase(loser)
		done.append({"winner": winner, "loser": loser, "outcome": String(c["outcome"]),
			"rounds": int(c["rounds"])})
	return done

# Which round a clash is on at `now`, 1-based, never past its last. What the
# map's label says; nothing mechanical reads it.
static func round_of(clash: Dictionary, now: float) -> int:
	var rounds: int = maxi(1, int(clash["rounds"]))
	return clampi(int((now - float(clash["from"])) / MINUTES_PER_ROUND) + 1, 1, rounds)

# The fight between `a` and `b`, fought to the end now, as the clash that will
# tell it. `a` fights as the "party" team (Encounter.build only builds the foe
# side), so a Victory is a's win. Deterministic: the seed is the pair's ids, so
# the same two bands meeting on the same map always resolve the same way.
static func fight(world, a, b, spec_for: Callable) -> Dictionary:
	var spec_a: Dictionary = spec_for.call(a)
	var spec_b: Dictionary = spec_for.call(b).duplicate(true)
	spec_b["seed"] = maxi(1, absi(hash("%s|%s" % [a.id, b.id])))
	var side_a: Array = _spawn_side(spec_a)
	# Both sides fight on the attacker's terrain; one board, one fight.
	var cb = Encounter.build(spec_b, side_a, Encounter.board_for(String(spec_a.get("theme", ""))))
	# T19: neither of these bands is the player's. Nothing in here counts.
	cb.tracked = false
	# #227: and nobody is there to hear it.
	cb.audible = false
	var guard := 0
	while not cb.is_over() and guard < MAX_TURNS:
		var actor = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, actor)
		cb.end_turn()
		guard += 1
	var outcome: String = cb.outcome()
	var a_wins: bool = outcome == "Victory" if outcome != "ongoing" else _ahead(cb)
	var rounds: int = maxi(1, int(cb.round_num))
	var now: float = world.clock.elapsed
	return {"a": a.id, "b": b.id, "winner": a.id if a_wins else b.id, "outcome": outcome,
		"rounds": rounds, "at": (a.position + b.position) * 0.5,
		"from": now, "until": now + rounds * MINUTES_PER_ROUND}

# The band `p` is fighting in `clash`, or null if it has left the map.
static func other_side(world, clash: Dictionary, p):
	return _party(world, String(clash["b"] if String(clash["a"]) == p.id else clash["a"]))

static func _party(world, id: String):
	for p in world.parties:
		if p.id == id:
			return p
	return null

# A fight that hit combat.gd's MAX_ROUNDS is decided on who is left standing,
# then on remaining HP — never on a coin flip, so the result stays seed-stable.
static func _ahead(cb) -> bool:
	var up := {"party": 0, "foe": 0}
	var hp := {"party": 0, "foe": 0}
	for c in cb.combatants:
		if c.conscious():
			up[c.team] += 1
			hp[c.team] += c.hp
	if up["party"] != up["foe"]:
		return up["party"] > up["foe"]
	return hp["party"] >= hp["foe"]

# A roster spec as "party"-team combatants. Encounter.build only spawns the foe
# side, and it places that side away from whatever it is handed — so putting one
# side on the board's first free hexes is enough to keep the two apart.
static func _spawn_side(spec: Dictionary) -> Array:
	var spots: Array = Encounter._foe_spots(
		Encounter.board_for(String(spec.get("theme", ""))), [])
	var out: Array = []
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else Encounter.PARTY_STARTS[0]
			var c = Encounter.spawn(e["id"], mult, "party", pos,
				n + 1 if count > 1 else 0, e.get("features", []))
			if c != null:
				out.append(c)
			i += 1
	return out

# MEASUREMENT SPIKE (2026-09-22) — what a room of depth actually costs, taken
# apart from which faction is standing in it. Not a test, and not part of
# tools/run_tests.sh (the runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_site_depth.gd
#   SEEDS=30 LEVEL=5 godot --headless --path . -s tests/sweep_site_depth.gd
#
# tests/sweep_site_kin.gd reports whether a delve was CLEARED, per faction, and
# that number confounds two things it cannot separate: core/site.gd's depth_for
# gives every faction exactly one depth, so "deeper lairs clear less" and
# "these particular peoples are harder" are the same column. A 6-room dragon
# cave clearing 25% where a 3-room warren clears 80% says nothing about whether
# the six rooms or the dragons did it.
#
# So this measures the CONDITIONAL rate instead: of the parties that reached
# room d at all, how many won room d. That is a per-room number, so rooms at
# the same index from different factions pool together, and the shape of the
# pooled curve is the depth cost with the faction averaged out.
#
# It also reports what the party had left walking in — mean HP as a fraction of
# max, and mean unspent spell slots — because that is the mechanism the whole
# site feature exists to create, and if the curve bends it should bend there.
#
# The last room of every site is the boss (core/site.gd's _boss_room), so its
# column is marked: a boss is meant to be harder than the room before it, and
# the question is by how much rather than whether.
#
# POLICY is the thing to set before trusting a row. core/site.gd's _build puts
# a COMBAT room at picks[0] always — "at least one way on is always a fight" —
# and a rest or a cache can only ever be picks[1] or [2]. So a robot that takes
# opts[0] never rests, never loots, and fights every floor: that is the worst
# case a site can produce and not what a player does.
#   POLICY=fight   take opts[0]. Every floor a fight, no rest ever.
#   POLICY=rest    take a rest room when one is offered, else opts[0].
#   POLICY=support take any support room when offered (rest or cache).
# Run at least `fight` and `rest`; they bracket real play, and the gap between
# them is what a rest room is worth, which is a number nothing else here says.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")

static var _extra := 0
static var _policy := "fight"

# Which way on to take. core/site.gd guarantees picks[0] is a fight, so "fight"
# is the robot that never rests and "rest"/"support" are the ones that do.
func _pick_room(opts: Array) -> int:
	if _policy == "fight":
		return 0
	for i in opts.size():
		var k := String(opts[i].get("kind", ""))
		if k == "rest" or (_policy == "support" and k == "treasure"):
			return i
	return 0

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p = Party.new()
	var roster: Array = Presets.party() if _extra == 0 else [
		_lvl(Presets.vera(), "fighter", _extra), _lvl(Presets.pike(), "rogue", _extra),
		_lvl(Presets.ilsa(), "cleric", _extra)]
	for ch in roster:
		p.add_member(ch)
	return p

func _lvl(ch, class_id: String, extra: int):
	for _i in extra:
		ch.add_level(class_id, -1)
	return ch

func _party_at(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

# What the party is walking in with: HP as a fraction of max, and unspent slots
# as a fraction of the full set. Read off the Characters, so it is the state
# Adapter will hand the next fight.
func _condition(party) -> Array:
	var hp := 0.0
	var mx := 0.0
	var left := 0
	var full := 0
	for ch in party.party_characters():
		var sheet = ch.sheet()
		if sheet == null:
			continue
		mx += float(sheet.max_hp)
		hp += float(ch.hp_current if ch.hp_current >= 0 else sheet.max_hp)
		for n in Adapter.slots_left(ch):
			left += int(n)
		for n in Adapter._full_slots(sheet):
			full += int(n)
	return [hp / maxf(mx, 1.0), float(left) / maxf(float(full), 1.0)]

func _fight(party, spec: Dictionary, seed: int) -> bool:
	var chars: Array = party.party_characters()
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var cb = Encounter.build(sp, _party_at(chars))
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	Adapter.write_back_all(cb.combatants.filter(func(c): return c.team == "party"), chars)
	return cb.outcome() == "Victory"

# One delve. `into` accumulates per-room-index stats across every run.
func _delve(faction: String, seed: int, into: Dictionary) -> void:
	var w := _world()
	var party := _party()
	var lair = w.add_lair(World.Lair.new("dsweep-%s-%d" % [faction, seed], Vector2.ZERO, faction))
	var s = Site.for_lair(lair, party, w)
	var last: int = s.depth_total() - 1
	var guard := 0
	while not s.is_over() and guard < 12:
		guard += 1
		var at: int = s.depth
		var opts: Array = s.options()
		if opts.is_empty():
			break
		var room: Dictionary = s.enter(_pick_room(opts))
		if String(room["kind"]) == "combat":
			var cond: Array = _condition(party)
			var row: Dictionary = into.get(at, {"reached": 0, "won": 0, "hp": 0.0, "slots": 0.0, "boss": 0})
			row["reached"] = int(row["reached"]) + 1
			row["hp"] = float(row["hp"]) + cond[0]
			row["slots"] = float(row["slots"]) + cond[1]
			if at == last:
				row["boss"] = int(row["boss"]) + 1
			var won := _fight(party, s.combat_spec(), seed * 131 + at)
			if won:
				row["won"] = int(row["won"]) + 1
			into[at] = row
			s.finish_combat({"outcome": "Victory" if won else "Defeat", "deaths": [], "downed": []})
		elif String(room["kind"]) == "treasure":
			s.take()
		else:
			s.short_rest()
		if s.state == "wiped":
			break
		s.leave()

func _print(label: String, rows: Dictionary) -> void:
	print("  %s" % label)
	print("    %-6s %8s %8s %7s %8s %8s" % ["room", "reached", "won", "rate", "hp in", "slots in"])
	var keys: Array = rows.keys()
	keys.sort()
	for d in keys:
		var r: Dictionary = rows[d]
		var n: float = maxf(float(r["reached"]), 1.0)
		print("    %-6s %8d %8d %6.1f%% %7.0f%% %7.0f%%%s" % [
			"d%d" % d, int(r["reached"]), int(r["won"]), 100.0 * float(r["won"]) / n,
			100.0 * float(r["hp"]) / n, 100.0 * float(r["slots"]) / n,
			"   <- boss for %d of them" % int(r["boss"]) if int(r["boss"]) > 0 else ""])

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 20
	_extra = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 5
	_policy = OS.get_environment("POLICY") if OS.get_environment("POLICY") != "" else "fight"
	print("seeds per faction: %d, party level 3+%d, policy %s, lair at the origin (band 1.0)" % [
		seeds, _extra, _policy])
	print("")
	# Pooled over every faction: the depth curve with the people averaged out.
	var all := {}
	# ...and over the three DEEPEST factions only, whose sites are all 6 rooms,
	# so every room index in that group is a like-for-like comparison inside one
	# depth rather than across four of them.
	var deep := {}
	for f in Scaler.FACTIONS:
		var rows := {}
		for s in range(1, seeds + 1):
			_delve(f, s, rows)
		for d in rows:
			for bucket in [all, deep] if Site.depth_for(World.Lair.new("x", Vector2.ZERO, f)) == Site.MAX_DEPTH else [all]:
				var r: Dictionary = bucket.get(d, {"reached": 0, "won": 0, "hp": 0.0, "slots": 0.0, "boss": 0})
				for k in ["reached", "won", "boss"]:
					r[k] = int(r[k]) + int(rows[d][k])
				for k in ["hp", "slots"]:
					r[k] = float(r[k]) + float(rows[d][k])
				bucket[d] = r
	_print("every faction pooled — the depth curve, people averaged out", all)
	print("")
	_print("the three 6-room factions only (elemental, construct, dragon)", deep)
	quit(0)

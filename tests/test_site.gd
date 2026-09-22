# D1 — sites: a lair with an interior, several rooms on one set of resources.
# The model only, headless: no scene, no rendering, no UI decision baked in.
# What this proves is the part that must be true whatever a site ends up
# looking like on screen.
#   godot --headless --path . -s tests/test_site.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")
const Party = preload("res://core/party.gd")
const Scaler = preload("res://core/scaler.gd")
const Regions = preload("res://core/regions.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Adapter = preload("res://core/adapter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _lair(faction := "goblinoid", id := "goblin-warren"):
	return World.Lair.new(id, Vector2(100, 100), faction)

# Walks a site to the end by always taking the first option, resolving whatever
# it lands on. Returns the number of rooms actually entered.
func _delve(s, win := true) -> int:
	var entered := 0
	while not s.is_over():
		var opts: Array = s.options()
		if opts.is_empty():
			break
		var room: Dictionary = s.enter(0)
		entered += 1
		match String(room["kind"]):
			"combat":
				s.finish_combat({"outcome": "Victory" if win else "Defeat"})
			"treasure":
				s.take()
			"rest":
				s.short_rest()
		if s.state == "wiped":
			break
		s.leave()
	return entered

func _init() -> void:
	# --- shape ------------------------------------------------------------
	var w := _world()
	var party := _party()
	var lair = _lair()
	var s = Site.for_lair(lair, party, w)

	check(s.depth_total() == Site.depth_for(lair),
		"the site is as deep as depth_for() promised before it was built")
	check(s.depth_total() >= Site.MIN_DEPTH and s.depth_total() <= Site.MAX_DEPTH,
		"...and inside the depth bounds (%d)" % s.depth_total())
	check(Site.depth_for(_lair("dragon", "dragon-cave")) > Site.depth_for(_lair("goblinoid")),
		"a dragon's cave runs deeper than a goblin warren")

	# Every floor but the last offers a real choice, and at least one way on is
	# always a fight — a floor you can tiptoe past entirely never happened.
	for d in s.depth_total() - 1:
		var picks: Array = s.rooms[d]
		check(picks.size() >= Site.PICK_MIN and picks.size() <= Site.PICK_MAX,
			"floor %d offers a choice, not a corridor (%d)" % [d, picks.size()])
		check(picks.any(func(r): return r["kind"] == "combat"),
			"floor %d has at least one fight on it" % d)
	check(s.rooms[-1].size() == 1 and s.rooms[-1][0]["kind"] == "combat",
		"the last room is the boss, alone")
	check(bool(s.rooms[-1][0].get("boss", false)), "...and is marked as one")

	# No room is reused inside one site.
	var seen := {}
	var dupes := 0
	for floor_rooms in s.rooms:
		for r in floor_rooms:
			if seen.has(r["id"]):
				dupes += 1
			seen[r["id"]] = true
	check(dupes == 0, "no room repeats inside one site")

	# Same lair, same interior — including after walking out and coming back.
	var again = Site.for_lair(_lair(), _party(), _world())
	check(again.rooms.size() == s.rooms.size(), "the same lair regenerates the same depth")
	check(String(again.rooms[0][0]["id"]) == String(s.rooms[0][0]["id"]),
		"...and the same rooms, in the same order")

	# --- the rule this whole feature exists for ---------------------------
	# One set of resources: there is no long rest in here, at all.
	var rest_rooms := 0
	for floor_rooms in s.rooms:
		for r in floor_rooms:
			check(r["kind"] != "long-rest", "no room is a long rest")
			if r["kind"] == "rest":
				rest_rooms += 1
	var before: float = w.clock.elapsed
	var long_rest_stamp: float = party.last_long_rest_at
	# Drive a rest room directly if the seed produced one; the point is that the
	# only rest available is the short one and that it costs an hour.
	var rest_found := false
	for d in s.rooms.size():
		for i in s.rooms[d].size():
			if String(s.rooms[d][i]["kind"]) != "rest":
				continue
			rest_found = true
			s.depth = d
			s.state = "picking"
			s.enter(i)
			check(s.short_rest(), "a rest room grants its short rest")
			check(not s.short_rest(), "...exactly once")
			check(is_equal_approx(w.clock.elapsed - before, Visit.SHORT_REST_MINUTES),
				"...and costs an hour of world time, not a free heal")
			check(is_equal_approx(party.last_long_rest_at, long_rest_stamp),
				"...without touching the long-rest clock — slots do not come back in here")
			break
		if rest_found:
			break

	# --- a full delve -----------------------------------------------------
	var w2 := _world()
	var party2 := _party()
	var lair2 = _lair()
	var gold0: int = party2.gold
	var s2 = Site.for_lair(lair2, party2, w2)
	var entered := _delve(s2)
	check(s2.state == "cleared", "winning every room clears the site")
	check(entered == s2.depth_total(), "...having entered one room per floor (%d)" % entered)
	check(lair2.looted, "a cleared lair is spent, and its map marker greys out")
	check(party2.gold > gold0, "...and the delve paid for itself (+%d)" % (party2.gold - gold0))
	check(int(lair2.depth_cleared) >= s2.depth_total(), "the lair remembers it was emptied")

	# --- withdrawing, and coming back -------------------------------------
	var w3 := _world()
	var party3 := _party()
	var lair3 = _lair()
	var s3 = Site.for_lair(lair3, party3, w3)
	# Looking in at the mouth and deciding against it is a legal move, and costs
	# nothing — the lair is untouched.
	check(s3.withdraw(), "a party can look in and turn straight back around")
	check(int(lair3.depth_cleared) == 0 and not lair3.looted, "...having changed nothing")

	s3 = Site.for_lair(lair3, party3, w3)
	s3.enter(0)
	check(not s3.withdraw(), "you cannot back out from inside a room")
	s3.finish_combat({"outcome": "Victory"})
	s3.leave()
	var reached: int = s3.depth
	check(s3.withdraw(), "between rooms, you can walk out")
	check(s3.state == "withdrawn" and not lair3.looted,
		"...and the lair is still standing")
	check(int(lair3.depth_cleared) == reached, "the lair remembers how far in you got")
	var s4 = Site.for_lair(lair3, party3, w3)
	check(s4.depth == reached, "coming back resumes rather than restarting")

	# --- a wipe -----------------------------------------------------------
	var lair5 = _lair()
	var s5 = Site.for_lair(lair5, _party(), _world())
	s5.enter(0)
	s5.finish_combat({"outcome": "Defeat"})
	check(s5.state == "wiped", "losing a room ends the delve")
	check(not lair5.looted, "...and does not hand the party the lair anyway")
	check(s5.options().is_empty(), "a finished site offers nothing further")
	s5.leave()
	check(s5.state == "wiped", "...and cannot be walked on from")

	# --- what a wipe underground costs -------------------------------------
	# Locked with the user: the bag, not the body, and the lair closes up again.
	var lair6 = _lair()
	var party6 := _party()
	for id in ["longsword", "leather", "spell-scroll", "shortbow"]:
		party6.stash_add(id, 2)
	var carried := 0
	for e in party6.stash:
		carried += int(e["quantity"])
	var equipped_before: Array = party6.roster[0].equipped.duplicate()
	lair6.depth_cleared = 2
	var toll: Dictionary = Site.wipe_penalty(party6, lair6)
	var left := 0
	for e in party6.stash:
		left += int(e["quantity"])
	check(toll["count"] > 0, "a wipe costs the party something out of the bag")
	check(left == carried - int(toll["count"]),
		"...exactly what it reported, no more (%d of %d)" % [toll["count"], carried])
	check(left > 0, "...and never the whole bag")
	check(party6.roster[0].equipped == equipped_before,
		"what they were wearing and wielding is untouched")
	check(int(lair6.depth_cleared) == 0, "the lair closes up behind them — progress is gone")
	check(not toll["items"].is_empty(), "the toll names what was taken, never just 'some things'")

	# Seeded off the lair and how deep they got, so it is not a reload lottery.
	var a := _party(); var b := _party()
	for p_ in [a, b]:
		for id in ["longsword", "leather", "spell-scroll", "shortbow"]:
			p_.stash_add(id, 2)
	var la = _lair(); var lb = _lair()
	la.depth_cleared = 2; lb.depth_cleared = 2
	check(Site.wipe_penalty(a, la)["items"] == Site.wipe_penalty(b, lb)["items"],
		"the same wipe takes the same things")

	# An empty bag is not a crash, and still resets the lair.
	var lair7 = _lair()
	lair7.depth_cleared = 1
	var empty_toll: Dictionary = Site.wipe_penalty(_party(), lair7)
	check(int(empty_toll["count"]) == 0 and int(lair7.depth_cleared) == 0,
		"nothing in the bag costs nothing, and the lair still resets")

	# --- what the fight screen is handed -----------------------------------
	var s6 = Site.for_lair(_lair(), _party(), _world())
	s6.enter(0)
	var spec: Dictionary = s6.combat_spec()
	check(not spec.is_empty() and spec.has("theme"), "a combat room yields a real encounter spec")
	check(not spec.get("monsters", []).is_empty(), "...with actual foes in it")
	check(String(spec["theme"]) == Site.theme_for_faction("goblinoid"),
		"...on the board that faction fights on")
	# The boss room reuses campaign.gd's measured BOSS_POOL where one fits the
	# faction's own board, rather than inventing a second unmeasured set.
	var s7 = Site.for_lair(_lair(), _party(), _world())
	s7.depth = s7.depth_total() - 1
	s7.enter(0)
	var boss_spec: Dictionary = s7.combat_spec()
	check(not boss_spec.get("monsters", []).is_empty(), "the boss room builds a roster too")
	check(String(s7.room.get("difficulty", "")) == "hard", "...and the boss is a hard fight")

	# Every faction that can hold a lair must produce a buildable site.
	for f in ["goblinoid", "giant", "undead", "dragon"]:
		var sf = Site.for_lair(_lair(f, "%s-lair" % f), _party(), _world())
		check(sf.depth_total() >= Site.MIN_DEPTH, "%s lairs build" % f)
		sf.depth = sf.depth_total() - 1
		sf.enter(0)
		check(not sf.combat_spec().get("monsters", []).is_empty(), "%s lairs have a boss with a roster" % f)

	# A "bestiary" boss is the creature itself, and it must not show up as plain
	# escort on the floors above it. The giant hold sits in the frontier, so
	# core/regions.gd builds its rooms for a level-6 party whoever walks in — and
	# at that budget the giant pool hands the oni out as a normal pick (found in
	# play: first fight of the giant hold was an oni). Every room, every pick.
	var far = World.Lair.new("giant-hold", Vector2(-520, -260), "giant")
	var s8 = Site.for_lair(far, _party(), _world())
	check(Regions.band_of(_world(), far.position) == "frontier", "the giant hold is frontier country")
	var leaked := false
	for d in s8.depth_total() - 1:
		for i in s8.rooms[d].size():
			s8.depth = d; s8.state = "picking"
			if String(s8.enter(i).get("kind", "")) != "combat":
				continue
			for m in s8.combat_spec()["monsters"]:
				leaked = leaked or String(m["id"]) == "oni"
	check(not leaked, "the oni never turns up before the boss room")
	s8.depth = s8.depth_total() - 1; s8.state = "picking"; s8.enter(0)
	check(s8.combat_spec()["monsters"].any(func(m): return String(m["id"]) == "oni"),
		"...but it is still the boss")

	# A lair is its own people, all the way down — including the ten factions
	# with no board of their own, which used to roll a fresh arbitrary faction
	# per room off the per-room seed (a dragon's cave was six rooms of six
	# peoples; tests/sweep_site_kin.gd has the grid). Scaler.MIX ("snik",
	# "vess", "kritch", "grull") is the documented fallback when nothing in a
	# faction fits the budget and carries no faction of its own, so it is what
	# `kin` skips rather than what it fails on.
	var saw_own := 0
	for f in ["dragon", "orc", "kobold", "cultist", "goblinoid", "undead"]:
		var sk = Site.for_lair(_lair(f, "%s-kin" % f), _party(), _world())
		var kin := {}
		for d in sk.depth_total():
			for i in sk.rooms[d].size():
				sk.depth = d; sk.state = "picking"
				if String(sk.enter(i).get("kind", "")) != "combat":
					continue
				for m in sk.combat_spec()["monsters"]:
					var fac := String(Catalog.monster(String(m["id"])).get("faction", ""))
					if fac != "":
						kin[fac] = true
		check(kin.size() <= 1 and (kin.is_empty() or kin.has(f)),
			"every room of a %s lair draws %s and nothing else (%s)" % [f, f, str(kin.keys())])
		if kin.has(f):
			saw_own += 1
	check(saw_own >= 4, "...and the check is not vacuous: %d of 6 actually fielded their own" % saw_own)

	# ...and something is waiting at the bottom of it. campaign.gd's BOSS_POOL is
	# keyed by THEME and covers five factions, so the other ten used to fall
	# through to a plain hard roster with no lead and the title "WHAT THE LAIR
	# WAS BUILT AROUND" — two thirds of the lairs in the game ending in a
	# slightly bigger version of the room before them. FACTION_BOSS is the
	# other ten, measured in tests/sweep_faction_boss.gd.
	for f in Scaler.FACTIONS:
		var sb = Site.for_lair(_lair(f, "%s-boss" % f), _party(), _world())
		sb.depth = sb.depth_total() - 1
		sb.enter(0)
		var room: Dictionary = sb.room
		var themed: bool = Site.theme_for_faction(f) != ""
		check(String(room.get("title", "")) != "WHAT THE LAIR WAS BUILT AROUND",
			"a %s lair's last room is named, not described" % f)
		check(String(room.get("difficulty", "")) == "hard", "...and is a hard fight (%s)" % f)
		# The one boss with no lead is BOSS itself, the hand-tuned four-archetype
		# shrine fight campaign.gd calls "classic" — deliberate, and measured.
		check(room.has("lead") or String(room.get("archetype", "")) == "classic",
			"...and is built round a lead (%s)" % f)
		var bspec: Dictionary = sb.combat_spec()
		check(not bspec.get("monsters", []).is_empty(), "...with a roster (%s)" % f)
		check(bspec["monsters"].size() > 1 or int(bspec["monsters"][0].get("count", 1)) > 1,
			"...and the boss is not alone in the room (%s: %s)" % [f, str(bspec["monsters"])])
		if not themed:
			var own_boss: Dictionary = Site.FACTION_BOSS[f]
			check(not own_boss.get("lead_features", []).is_empty(),
				"%s's boss carries a special of its own" % f)
			var base: Array = Catalog.monster(String(own_boss["lead"])).get("features", [])
			for feat in own_boss["lead_features"]:
				check(not feat in base,
					"...and %s is not something a plain %s already had" % [feat, own_boss["lead"]])
	# Every lead must be a real creature, and a bestiary lead must be pulled out
	# of the ordinary pool so meeting it is a reveal (_boss_lead_exclusion).
	for f in Site.FACTION_BOSS:
		var fb: Dictionary = Site.FACTION_BOSS[f]
		check(not Catalog.monster(String(fb["lead"])).is_empty(), "%s's lead exists" % f)
		check(String(Catalog.monster(String(fb["lead"])).get("faction", "")) == f,
			"...and is %s's own kin" % f)
	# --- a lair is priced for the party that walked in ---------------------
	# core/rules/power.gd's estimate() reads ehp off max_hp and never off hp, so
	# the only thing the scaler could see about a party's condition was unspent
	# slots — and inside a site that read backwards: spending shrank the next
	# fight and RESTING grew it. Site holds the entry reading and corrects the
	# scale, so what is in a room stops depending on what it cost to get there.
	var pw := _party()
	var lw = _lair("dragon", "held-lair")
	var sw = Site.for_lair(lw, pw, _world())
	sw.depth = sw.depth_total() - 1
	sw.enter(0)
	var fresh: Array = sw.combat_spec()["monsters"]
	check(is_equal_approx(sw._held(), 1.0), "at the mouth the correction is a no-op (%.3f)" % sw._held())
	for state in [[0.49, 0.50], [0.67, 0.0], [0.20, 1.0], [0.05, 0.25]]:
		for ch in pw.party_characters():
			var sheet = ch.sheet()
			ch.hp_current = maxi(1, roundi(sheet.max_hp * float(state[0])))
			var used: Array[int] = []
			for n in Adapter._full_slots(sheet):
				used.append(roundi(int(n) * (1.0 - float(state[1]))))
			ch.slots_used = used
		check(str(sw.combat_spec()["monsters"]) == str(fresh),
			"...and the same room at hp %.0f%%/slots %.0f%% is the same room" % [
				float(state[0]) * 100.0, float(state[1]) * 100.0])
	check(sw._held() > 1.0, "...which it is because the correction moved (%.3f)" % sw._held())
	# Re-entering is a fresh walk in, so the snapshot is re-taken rather than
	# carrying a drained party's reading into the next visit.
	var sw2 = Site.for_lair(lw, pw, _world())
	check(is_equal_approx(sw2._held(), 1.0), "walking back in re-takes the reading (%.3f)" % sw2._held())

	# A content pack's faction this build has never heard of keeps the old shape
	# rather than crashing on a missing table row.
	var pk = Site.for_lair(_lair("moonfolk", "pack-lair"), _party(), _world())
	pk.depth = pk.depth_total() - 1
	pk.enter(0)
	check(String(pk.room.get("title", "")) == "WHAT THE LAIR WAS BUILT AROUND",
		"an unknown faction still gets the plain last room")

	# --- D1: a disturbed lair does not wait forever ------------------------
	# Locked with the user: enter a lair and you have a day or two to finish it.
	# Walk away longer and it resolves without you — somebody else clears it, or
	# whatever lived there moves on. This is what stops "back out, heal up, come
	# back at full strength" from being free and strictly correct.
	const Lairs = preload("res://core/world_lairs.gd")
	var w7 := _world()
	var lair8 = _lair()
	w7.add_lair(lair8)
	check(Lairs.expire(w7, w7.clock.elapsed).is_empty(), "an undisturbed lair never expires")
	w7.clock.elapsed += Lairs.WINDOW * 3.0
	check(Lairs.expire(w7, w7.clock.elapsed).is_empty(),
		"...however long you leave it, if you never went in")

	Lairs.mark_entered(lair8, w7.clock.elapsed)
	var stamped: float = lair8.entered_at
	check(stamped >= 0.0, "going in starts the clock")
	w7.clock.elapsed += 10.0
	Lairs.mark_entered(lair8, w7.clock.elapsed)
	check(is_equal_approx(lair8.entered_at, stamped), "...and going back in does not restart it")
	check(Lairs.window_left(lair8, w7.clock.elapsed) > 0.0, "there is time left on it")
	check(Lairs.expire(w7, w7.clock.elapsed).is_empty(), "a lair inside its window is still there")

	w7.clock.elapsed += Lairs.WINDOW
	var gone: Array = Lairs.expire(w7, w7.clock.elapsed)
	check(gone.size() == 1 and gone[0] == lair8, "past the window it resolves without the party")
	check(lair8.looted, "...and is spent")
	check(lair8.resolved_as in Lairs.OUTCOMES, "...one way or the other (%s)" % lair8.resolved_as)
	check(Lairs.resolution_text(lair8) != "", "...and it can say which, out loud")
	check(is_zero_approx(Lairs.window_left(lair8, w7.clock.elapsed)), "no window left on a spent lair")
	check(Lairs.expire(w7, w7.clock.elapsed).is_empty(), "and it only resolves once")

	# Seeded off the lair, so reloading cannot reroll it into the nicer outcome.
	var w8 := _world(); var w9 := _world()
	var la2 = _lair(); var lb2 = _lair()
	w8.add_lair(la2); w9.add_lair(lb2)
	for pair in [[w8, la2], [w9, lb2]]:
		Lairs.mark_entered(pair[1], 0.0)
		pair[0].clock.elapsed = Lairs.WINDOW + 1.0
		Lairs.expire(pair[0], pair[0].clock.elapsed)
	check(la2.resolved_as == lb2.resolved_as, "the same lair always resolves the same way")

	# A wipe must NOT expire the lair — losing already resets it and leaves it
	# standing (wipe_penalty above); the window is for walking away intact.
	var w10 := _world()
	var lair9 = _lair()
	w10.add_lair(lair9)
	Lairs.mark_entered(lair9, 0.0)
	lair9.depth_cleared = 2
	Site.wipe_penalty(_party(), lair9)
	check(not lair9.looted, "a wipe leaves the lair standing to try again")

	test_objective_rooms()

	print("test_site: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Objectives: a gate room holds, a pens room rescues, and a rescue job can only
# be posted about a lair whose pens the party has not yet fought past.
func test_objective_rooms() -> void:
	var Objectives = load("res://core/objectives.gd")
	var ids: Array = Site.COMBAT_ROOMS.map(func(r): return String(r["id"]))
	check(ids.has("gate") and ids.has("pens"), "the gate and the pens are combat rooms")
	# find a lair id whose interior has a pens room, and one whose has not
	var with_pens = null
	var without = null
	for i in 400:
		var l = World.Lair.new("warren-%d" % i, Vector2(100, 100), "goblinoid")
		if Site.pens_ahead(l):
			if with_pens == null: with_pens = l
		elif without == null:
			without = l
		if with_pens != null and without != null:
			break
	check(with_pens != null and without != null, "some lairs hold captives and some do not")
	var w := _world()
	var p := _party()
	var s = Site.for_lair(with_pens, p, w)
	var pens := {}
	for depth in s.rooms:
		for r in depth:
			if String(r.get("objective", "")) == "rescue": pens = r
	check(not pens.is_empty(), "the pens are in there")
	s.room = pens
	s.state = "combat"
	var spec: Dictionary = s.combat_spec()
	check(spec.get("objective", {}).get("kind", "") == "rescue", "the pens room's spec carries a rescue")

	# gate rooms are their own draw — a lair with pens ahead is not guaranteed to
	# also have one (with_pens above usually does not), so search independently.
	var gate := {}
	var s2
	for i in 400:
		var gl = World.Lair.new("gate-%d" % i, Vector2(100, 100), "goblinoid")
		s2 = Site.for_lair(gl, p, w)
		for depth in s2.rooms:
			for r in depth:
				if String(r.get("objective", "")) == "hold": gate = r
		if not gate.is_empty():
			break
	check(not gate.is_empty(), "some lairs have a gate to hold")
	s2.room = gate
	s2.state = "combat"
	spec = s2.combat_spec()
	check(spec["objective"]["kind"] == "hold" and spec["objective"]["waves"].size() == Objectives.WAVE_ROUNDS.size(),
		"the gate's spec carries a hold with one wave per wave round")
	var waves: Array = spec["objective"]["waves"]
	check(waves.all(func(wave): return wave is Array and not wave.is_empty() and wave.all(func(m): return m is Dictionary and m.has("id"))),
		"every wave is an actual roster, not just a shape")

	# an ordinary combat room of that same site — no hold, no rescue — must not
	# pick up an objective it was never given
	var ordinary := {}
	for depth in s2.rooms:
		for r in depth:
			if ordinary.is_empty() and String(r.get("kind", "")) == "combat" and not r.has("objective"):
				ordinary = r
	s2.room = ordinary
	s2.state = "combat"
	check(not s2.combat_spec().has("objective"), "an ordinary room carries no objective")

	# fought past: a lair whose pens are behind the party no longer qualifies
	var deep: int = 0
	for d in s.rooms.size():
		if s.rooms[d].has(pens):
			deep = d
	with_pens.depth_cleared = deep + 1
	check(not Site.pens_ahead(with_pens), "pens the party has fought past do not count")
	with_pens.depth_cleared = 0

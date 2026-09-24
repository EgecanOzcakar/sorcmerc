# Co-op lockstep across every kit in the game, not just the preset trio.
#
# tests/test_coop.gd proves the co-op seam on Vera, Pike and Ilsa: a fighter, a
# rogue and a cleric, forty seeds. That was the whole of the co-op coverage, so
# a new class feature, a new button kind or a new status could desync the two
# peers and nothing would say so until two players met it. This builds all 48
# (class, subclass) pairs the way a player does (every choice made), deals them
# into four-hero parties at levels 4 and 8, and fights each party in lockstep
# through tests/coop_harness.gd: every hero turn presses every button its bar
# offers, every intent crosses the wire as JSON, and Coop.state_hash — which
# covers the dice, the positions, the economy, the pools and every status's
# payload — must agree after each one.
#
# It also proves the detector itself: a pool or a status payload that differs
# between the peers, and nothing else, must change the hash.
#   godot --headless --path . -s tests/test_coop_kits.gd
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Coop = preload("res://core/coop.gd")
const Harness = preload("res://tests/coop_harness.gd")
const Kits = preload("res://tests/kits.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

const LEVELS := [4, 8]
const TEAM := 4

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_the_detector()
	test_a_refusal_changes_nothing()
	test_a_drained_pool_changes_nothing()
	test_enemy_casters_in_lockstep()
	var seen := {}
	var fights := 0
	for lvl in LEVELS:
		var heroes: Array = []
		for sc in Catalog.all("subclasses.json"):
			heroes.append(build(String(sc["classId"]), String(sc["id"]), lvl))
		for t in range(0, heroes.size(), TEAM):
			var party = Party.new()
			for ch in heroes.slice(t, t + TEAM):
				party.add_member(ch)
			var sd: int = 1000 + lvl * 100 + t
			var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal", {}, "", sd)
			spec["seed"] = sd
			var who := ", ".join(party.party_characters().map(func(c): return c.id))
			var r: Dictionary = Harness.lockstep(party, spec, sd)
			fights += 1
			check(not r["drift"], "L%d [%s]: no drift over %d intents (drifted on %s)" % [lvl, who, r["intents"], r["drifted_on"]])
			check(int(r["intents"]) > 0, "L%d [%s]: the heroes pressed something" % [lvl, who])
			for k in r["seen"]:
				seen[k] = int(seen.get(k, 0)) + int(r["seen"][k])
	check(fights >= 24, "every kit fought (%d parties)" % fights)
	check(seen.size() >= 60, "a wide spread of buttons crossed the codec (%d distinct)" % seen.size())
	print("  distinct intents through the codec: %d" % seen.size())
	print("test_coop_kits: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# A hero built the way the creator builds one (tests/kits.gd).
func build(cid: String, sid: String, lvl: int):
	return Kits.hero(cid, sid, lvl)

# The hash must see what the dice do not: two peers identical but for one
# pool, or for one status's payload, are two different fights.
func test_the_detector() -> void:
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal", {}, "", 5)
	spec["seed"] = 5
	var setup := Harness.wire(Coop.setup_for(5, spec, party))
	var a = Harness.build(setup)
	var b = Harness.build(setup)
	check(Coop.state_hash(a) == Coop.state_hash(b), "detector: two builds of one setup hash alike")
	var ha = a.combatants.filter(func(c): return c.team == "party" and not c.pools.is_empty())[0]
	var hb = Coop.find(b, ha.id)
	var pid: String = ha.pools.keys()[0]
	hb.pools[pid]["cur"] = int(hb.pools[pid]["cur"]) - 1
	check(Coop.state_hash(a) != Coop.state_hash(b), "detector: a pool spent on one peer only is a drift")
	hb.pools[pid]["cur"] = int(ha.pools[pid]["cur"])
	ha.statuses["probe"] = {"bonus": 1, "on": a.combatants[0]}
	hb.statuses["probe"] = {"bonus": 2, "on": b.combatants[0]}
	check(Coop.state_hash(a) != Coop.state_hash(b), "detector: the same status with a different payload is a drift")
	hb.statuses["probe"] = {"bonus": 1, "on": b.combatants[0]}
	check(Coop.state_hash(a) == Coop.state_hash(b),
		"detector: a payload naming the same combatant on each peer is no drift (it is written as its id)")

# The contract the harness leans on — a refused intent changed nothing, so it
# is not sent — made a check of its own. Every kit that holds a bonus-action
# leveled spell casts it, and then every leveled action spell it holds must be
# refused (the 2024 bonus-action spell rule) with its economy and slots
# exactly as they were. perform() used to pay the action first and refuse
# after.
func test_a_refusal_changes_nothing() -> void:
	var Adapter = load("res://core/adapter.gd")
	var Combat = load("res://core/combat.gd")
	var Encounter = load("res://core/encounter.gd")
	var RNG = load("res://core/rng.gd")
	var tried := 0
	for sc in Catalog.all("subclasses.json"):
		var ch = build(String(sc["classId"]), String(sc["id"]), 8)
		var h = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
		var g = Encounter.spawn("ogre", 1.0, "foe", Vector2i(3, 0), 1)
		var cb = Combat.new(RNG.new(9), [h, g], Encounter.board_for("goblin-camp"))
		cb.begin_turn_for(h)
		var bonus: Array = cb.available(h).filter(func(v): return v["kind"] == "spell" \
			and int(v.get("slot_level", 0)) > 0 and String(v.get("cost", "")) == "bonus")
		if bonus.is_empty():
			continue
		var bv: Dictionary = bonus[0]
		var t = g if String(bv.get("targeting", "self")) == "enemy" else (h if String(bv.get("targeting", "self")) in ["self", "ally", "allies"] else g.pos)
		if cb.perform(h, bv, t).has("error"):
			continue
		for v in h.verbs:
			if v["kind"] != "spell" or int(v.get("slot_level", 0)) <= 0 or String(v.get("cost", "")) != "action":
				continue
			var before := var_to_str([h.econ, h.slots, h.pools.keys().map(func(k): return h.pools[k]["cur"])])
			var r: Dictionary = cb.perform(h, v, g)
			tried += 1
			check(r.has("error"), "%s: %s after a bonus-action spell is refused" % [sc["id"], v["id"]])
			check(var_to_str([h.econ, h.slots, h.pools.keys().map(func(k): return h.pools[k]["cur"])]) == before,
				"%s: ...and refusing it spent nothing" % sc["id"])
	check(tried >= 10, "the rule was tried on the kits that can meet it (%d casts)" % tried)

# The same contract for a pool: a sorcerer whose points are gone presses Font
# of Magic's slot-making button (the bar offered it a moment ago, before
# Metamagic spent the points). perform() used to pay the Bonus Action and then
# find the pool empty.
func test_a_drained_pool_changes_nothing() -> void:
	var Adapter = load("res://core/adapter.gd")
	var Combat = load("res://core/combat.gd")
	var Encounter = load("res://core/encounter.gd")
	var RNG = load("res://core/rng.gd")
	var h = Adapter.to_combatant(build("sorcerer", "draconicsorcery", 5), "party", Vector2i(2, 0))
	var g = Encounter.spawn("ogre", 1.0, "foe", Vector2i(3, 0), 1)
	var cb = Combat.new(RNG.new(9), [h, g], Encounter.board_for("goblin-camp"))
	cb.begin_turn_for(h)
	var make: Array = cb.all_verbs(h).filter(func(v): return String(v.get("font", "")) == "to_slot")
	check(not make.is_empty(), "a level-5 sorcerer has Font of Magic's slot-making buttons")
	if make.is_empty():
		return
	for pid in h.pools:
		h.pools[pid]["cur"] = 0
	var before := var_to_str([h.econ, h.slots, h.pools])
	var r: Dictionary = cb.perform(h, make[0], h)
	check(r.has("error"), "with no points left, making a slot is refused (%s)" % r)
	check(var_to_str([h.econ, h.slots, h.pools]) == before, "...and refusing it spent nothing: the Bonus Action is still there")

# Enemy casters (core/enemy_casters.gd) pick their spells on each peer by
# themselves: AI.take_turn runs on host and guest alike and must choose the
# same spell, the same target and the same hex. Every caster the cult fields,
# at every band cap, against the preset party.
func test_enemy_casters_in_lockstep() -> void:
	var EnemyCasters = load("res://core/enemy_casters.gd")
	var ids: Array = EnemyCasters.ids_for("cultist")
	check(ids.size() >= 3, "the cult fields its casters (%s)" % str(ids))
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var n := 0
	for id in ids:
		for cap in [2, 3, 9]:
			var sd: int = 300 + n
			n += 1
			var spec := {"seed": sd, "monsters": [
				{"id": id, "count": 1, "mult": 1.0, "caster": true, "caster_cap": cap},
				{"id": "cultist", "count": 2, "mult": 1.0}]}
			var r: Dictionary = Harness.lockstep(party, spec, sd)
			check(not r["drift"], "a %s casting up to level %d stays in lockstep (drifted on %s)" % [id, cap, r["drifted_on"]])

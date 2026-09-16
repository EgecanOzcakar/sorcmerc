# Utility spells with a hook on the road: a spell the party knows changes a
# roll it already makes (Revivify's pattern), and the healer hires a party
# that carries a restoration spell.
#   godot --headless --path . -s tests/test_road_spells.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Travel = preload("res://core/travel.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Encounter = preload("res://core/encounter.gd")
const Adapter = preload("res://core/adapter.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const RoadSpells = preload("res://core/road_spells.gd")
const WorldSave = preload("res://core/world_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_off_board_pickable()
	test_caster_of()
	test_travel_spell_pass()
	test_pass_without_trace()
	test_talk_advantage()
	test_healer_work()
	test_road_casts()
	print("test_road_spells: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party(ilsa_spells: Array = []) -> Party:
	var p := Party.new()
	for ch in Presets.party():
		if ch.id == "ilsa":
			ch.prepared.append_array(ilsa_spells)
		p.add_member(ch)
	return p

func _force(party, w, want: String) -> Dictionary:
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(party, w, RNG.new(seed_v))
		if String(e.get("id", "")) == want:
			return e
	return {}

# Every spell with a door off the board is one a made character can pick.
func test_off_board_pickable() -> void:
	var Effects = load("res://core/rules/effects.gd")
	var doors: Array = RoadSpells.ROAD.keys() + Visit.TALK_SPELLS + Visit.WORK_SPELLS + [Encounter.PASS_WITHOUT_TRACE]
	for e in Travel.SPELL_PASS.values():
		doors.append_array(e["spells"])
	for sid in doors:
		check(sid in Effects.OFF_BOARD, "%s has a door, so it is on Effects.OFF_BOARD" % sid)
	var picks: Array = []
	for lst in ["druid", "ranger", "wizard", "cleric", "bard", "sorcerer", "warlock"]:
		for lvl in range(1, 6):
			picks.append_array(Effects.pick_pool(lst, lvl))
	for sid in Effects.OFF_BOARD:
		check(sid in picks, "%s can actually be picked by somebody" % sid)

func test_caster_of() -> void:
	var p := _party(["speak-with-animals"])
	check(p.caster_of(["speak-with-animals"]) == p.get_member("ilsa"), "the party finds who knows a spell")
	check(p.caster_of(["fly"]) == null, "...and nobody, when nobody does")
	check(_party().caster_of(["speak-with-animals"]) == null, "a plain party knows none of these")

func test_travel_spell_pass() -> void:
	var w := _world()
	var e := _force(_party(["speak-with-animals"]), w, "tracks")
	check(e.get("ok", false) and e.get("spell", "") == "speak-with-animals" and e["text"].contains("asks the birds"),
		"Speak with Animals reads the tracks without a roll")
	var plain := _force(_party(), _world(), "tracks")
	check(not plain.has("spell"), "without it the scout rolls as before")
	var water := _force(_party(["lesser-restoration"]), _world(), "foul-water")
	check(water.get("ok", false) and not water.has("hurt"), "Lesser Restoration keeps the party well")

func test_pass_without_trace() -> void:
	var chars: Array = Presets.party()
	for ch in chars:
		if ch.id == "ilsa":
			ch.prepared.append("pass-without-trace")
	var cbs: Array = []
	for i in chars.size():
		cbs.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	check("pass-without-trace" in cbs[1].spell_ids or cbs.any(func(c): return "pass-without-trace" in c.spell_ids),
		"the combatant carries the utility spell id")
	var unseen := 0
	for s in [3, 4, 5, 6, 7, 8, 9, 10]:
		var cb = Encounter.build({"monsters": [{"id": "scout", "count": 2}], "seed": s}, cbs.map(func(c):
			return Adapter.to_combatant(chars[cbs.find(c)], "party", c.pos)))
		if Encounter.surprise_check(cb):
			unseen += 1
		check(cb.log.any(func(l): return l.contains("Pass Without Trace")), "the veil is logged (seed %d)" % s)
	check(unseen == 8, "+10 Stealth: unseen every time against scouts (%d/8)" % unseen)

func test_talk_advantage() -> void:
	var p := _party(["detect-thoughts"])
	check(Visit._talk_mode(p.get_member("ilsa"), p) == Dice.ADV, "Detect Thoughts is advantage at the stall")
	check(Visit._talk_mode(_party().get_member("ilsa"), _party()) == Dice.NORMAL, "...only when someone knows it")

func test_healer_work() -> void:
	var s = _world().settlements[0]
	check(not Visit.can_work_healer(_party()), "no restoration spell: no shift on offer")
	var p := _party(["lesser-restoration"])
	check(Visit.can_work_healer(p), "Lesser Restoration opens the door")
	var g0: int = p.gold
	var r := Visit.work_healer(s, p, RNG.new(3))
	check(r["pay"] in [Visit.WORK_PAY, Visit.WORK_PAY_POOR] and p.gold == g0 + int(r["pay"]), "a shift pays (%d gp)" % int(r["pay"]))
	check(r["text"].contains("Lesser Restoration") and r["text"].contains("Medicine"), "the line names the spell and the check")
	check(r["ok"] == (int(r["nat"]) + int(r["bonus"]) >= Visit.WORK_DC), "pay follows the Medicine roll")

func test_road_casts() -> void:
	var p := _party(["clairvoyance", "longstrider", "rope-trick", "alarm"])
	var ilsa = p.get_member("ilsa")
	var known: Array = RoadSpells.known(p, ilsa)
	check(known.size() == 4 and known.filter(func(r): return r["castable"]).size() == 3,
		"Ilsa (cleric 3) sees all four, can cast the three she has slots for — Clairvoyance (3rd) is greyed")
	check(RoadSpells.known(p, p.get_member("vera")).is_empty(), "Vera has no road spells")
	p.world_now = 100.0
	check(Travel.speed_mult(p) == 1.0, "normal pace before")
	var line := RoadSpells.cast(p, ilsa, "longstrider", p.world_now)
	check(line.contains("Longstrider") and p.swift_until == 160.0, "Longstrider: an hour of swift travel (%s)" % line)
	check(Travel.speed_mult(p) == RoadSpells.SWIFT_MULT and Travel.pace_bonus(p) == 0, "...forced-march ground, no road penalty")
	p.world_now = 161.0
	check(Travel.speed_mult(p) == 1.0, "...and it wears off")
	check(ilsa.slots_used[0] == 1, "it cost a 1st-level slot")
	RoadSpells.cast(p, ilsa, "rope-trick", p.world_now)
	RoadSpells.cast(p, ilsa, "alarm", p.world_now)
	check(p.safe_camp and p.alarm_set and ilsa.slots_used[0] == 2 and ilsa.slots_used[1] == 1,
		"Rope Trick and Alarm set their camp flags and spend their slots")
	# a slot of the spell's level or higher, lowest first; none left = no cast
	ilsa.slots_used.assign([4, 2, 0, 0, 0, 0, 0, 0, 0])
	check(RoadSpells.cast(p, ilsa, "alarm", p.world_now) == "", "no slot left, no cast")
	check(not RoadSpells.known(p, ilsa).any(func(r): return r["castable"]), "...and the panel says so")
	# survives a save
	var back = WorldSave._party_from(WorldSave._party_dict(p))
	check(back.safe_camp and back.alarm_set and back.swift_until == 160.0, "the road flags survive a save")

# F1b: every data/bestiary.json entry is monsters.json-shaped and spawns clean.
#   godot --headless --path . -s tests/test_bestiary.gd
#
# 2026-09-25 (the Far Deeps): the CR 10+ entries also have to FIGHT — each one
# is put on a board against a level-15 preset party and autoplayed a few
# rounds, so a statblock the importer (tools/import_srd_monsters.py) got wrong
# fails here rather than in the first Deeps fight that draws it. And each one
# has a figure or falls back to the vector tier cleanly: most of them have no
# model, which is fine, but the lookup must not break on them.
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Dice = preload("res://core/dice.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")
const Figures3D = preload("res://scenes/figures3d.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init():
	var raw := FileAccess.get_file_as_string("res://data/bestiary.json")
	var arr = JSON.parse_string(raw)
	assert(arr is Array and arr.size() > 200, "bestiary.json unparsable or short")
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var need: Array = base[0].keys()
	var seen := {}
	for m in arr:
		for k in need:
			assert(m.has(k), "%s missing %s" % [m["id"], k])
		assert(not seen.has(m["id"]), "duplicate id " + m["id"])
		seen[m["id"]] = true
		var c = Adapter.from_monster(m, "foe", Vector2i.ZERO)
		assert(c.max_hp > 0 and c.hp == c.max_hp, m["id"] + " hp")
		assert(c.ac >= 5 and c.damage != "" and int(Dice.parse(c.damage)["sides"]) >= 0, m["id"] + " numbers")
		assert(c.speed >= 1, m["id"] + " speed")
		for v in c.verbs:
			assert(v.has("kind"), m["id"] + " bad verb")
	print("OK ", arr.size(), " bestiary entries spawn; multiattack verbs resolve")
	_deeps(arr)
	print("test_bestiary: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# Every CR 10+ entry, one at a time against the level-15 ruler party.
func _deeps(arr: Array) -> void:
	var high: Array = arr.filter(func(m): return float(m.get("cr", 0)) >= 10.0)
	check(high.size() >= 25, "the Far Deeps have a bench of CR 10+ statblocks (%d)" % high.size())
	# ...and the Deeps' own peoples have them: every home faction of the Far
	# Deeps that the SRD has anything that big for (it has no fey above CR 3).
	var by_faction := {}
	for m in high:
		by_faction[String(m["faction"])] = int(by_faction.get(String(m["faction"]), 0)) + 1
	for f in ["dragon", "giant", "undead", "elemental", "construct", "monstrosity"]:
		check(Regions.suits("deeps", f) and int(by_faction.get(f, 0)) >= 1,
			"%s, a Deeps people, has a CR 10+ entry (%d)" % [f, int(by_faction.get(f, 0))])
		check(Scaler.FACTIONS.has(f), "%s fields rosters" % f)
	for m in high:
		var id: String = String(m["id"])
		check(String(m.get("habitat", "")) != "", "%s has a habitat" % id)
		# A figure or none, never an error: most of these have no model and
		# draw in the vector tier (figures3d.gd's reset() skips a "" path).
		var path: String = Figures3D.model_path_for(null, id)
		check(path == "" or ResourceLoader.exists(path), "%s: a figure that exists, or none (%s)" % [id, path])
		_fight(id)


func _fight(id: String) -> void:
	var chars: Array = Presets.party_at(15)
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var cb = Encounter.build({"monsters": [{"id": id, "count": 1}], "seed": 7, "theme": ""}, party)
	var foe = null
	for c in cb.combatants:
		if c.team == "foe":
			foe = c
	check(foe != null and foe.src_id == id, "%s takes the board" % id)
	if foe == null:
		return
	var party_hp_before := 0
	for c in party:
		party_hp_before += c.hp
	var foe_turns := 0
	var g := 0
	while not cb.is_over() and g < 60:
		var a = cb.current()
		cb.begin_turn()
		if a == foe:
			foe_turns += 1
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	var party_hp_after := 0
	for c in party:
		party_hp_after += c.hp
	check(foe_turns >= 1 or foe.hp <= 0, "%s gets a turn (or dies first)" % id)
	check(foe.hp < foe.max_hp, "%s can be hurt" % id)
	check(foe_turns == 0 or party_hp_after < party_hp_before or cb.is_over(),
		"%s fights back: the party lost %d HP over %d of its turns" % [id, party_hp_before - party_hp_after, foe_turns])

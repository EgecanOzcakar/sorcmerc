# One runnable check: every bestiary entry spawns into a Combatant cleanly.
extends SceneTree

const Adapter = preload("res://core/adapter.gd")

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
		print(m["id"]); var c = Adapter.from_monster(m, "foe", Vector2i.ZERO)
		assert(c.max_hp > 0 and c.hp == c.max_hp, m["id"] + " hp")
		assert(c.ac >= 5 and c.atk_bonus != 0 and c.damage != "", m["id"] + " numbers")
		assert(c.speed >= 1, m["id"] + " speed")
		for v in c.verbs:
			assert(v.has("kind"), m["id"] + " bad verb")
	print("OK ", arr.size(), " bestiary entries spawn; multiattack verbs resolve")
	quit()

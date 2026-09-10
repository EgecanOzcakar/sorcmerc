# resource-pool grants -> [{id, max, regen, die_size, source}].
# Ported from dnd-maintainer src/lib/resolver/resource-pools.ts.
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")

# Highest satisfied minLevel wins; 0 if none.
static func _step(steps: Array, level: int, key: String) -> int:
	var best := -1
	var value := 0
	for s in steps:
		var m := int(s["minLevel"])
		if level >= m and m > best:
			best = m
			value = int(s[key])
	return value

# {pools: Array, warnings: Array[String]}
static func resolve(bundles: Array) -> Dictionary:
	var warns: Array[String] = []
	var out: Array = []
	for tg in Bundles.of_type(bundles, "resource-pool"):
		var g: Dictionary = tg["grant"]
		var spec: Dictionary = g["max"]
		var mx := 0
		var level := 0
		if spec["mode"] != "fixed":
			level = Bundles.class_level(bundles, spec["classId"])
			if level == 0:
				warns.append("resource-pool \"%s\" names class \"%s\" but no bundles for it were found — max 0" % [
					g["poolId"], spec["classId"]])
		match spec["mode"]:
			"fixed": mx = int(spec["value"])
			"level-steps": mx = _step(spec["steps"], level, "value")
			"proficiency-bonus": mx = 0 if level == 0 else Bundles.proficiency_bonus(level)
			"class-level": mx = level
			"class-level-plus": mx = maxi(0, level + int(spec["offset"]))
			_: assert(false, "unhandled resource-pool max mode: " + str(spec["mode"]))

		var die := 0
		if g.has("dieSizeSteps"):
			if spec["mode"] == "fixed":
				warns.append("resource-pool \"%s\" has dieSizeSteps with a fixed max — no class level to key on, die dropped" % g["poolId"])
			else:
				die = _step(g["dieSizeSteps"], level, "dieSize")

		out.append({"id": g["poolId"], "max": mx, "regen": g["regen"], "die_size": die,
			"source": tg["source"]})
	return {"pools": out, "warnings": warns}

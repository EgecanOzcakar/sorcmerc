# ability-bonus / ability-choice / asi -> the six scores. Cap 20.
# Ported from dnd-maintainer src/lib/resolver/abilities.ts.
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")

const KEYS := ["str", "dex", "con", "int", "wis", "cha"]

# {abilities: {key: {base, total, mod, bonuses: [{value, source}]}}, warnings: [String]}
static func resolve(base: Dictionary, bundles: Array, choices: Dictionary) -> Dictionary:
	var warns: Array[String] = []
	var bonus := {}
	for k in KEYS:
		bonus[k] = []

	for tg in Bundles.of_type(bundles, "ability-bonus"):
		var g: Dictionary = tg["grant"]
		bonus[g["ability"]].append({"value": int(g["bonus"]), "source": tg["source"]})

	for tg in Bundles.of_type(bundles, "ability-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		if d != null and d.get("type") == "ability-choice":
			for a in d["abilities"]:
				bonus[a].append({"value": int(g["bonus"]), "source": tg["source"]})

	for tg in Bundles.of_type(bundles, "asi"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		if d == null or d.get("type") != "asi":
			continue
		var alloc: Dictionary = d["allocation"]
		var total := 0
		for v in alloc.values():
			total += int(v)
		if total > int(g["points"]):
			warns.append("ASI grant \"%s\" over-allocated (%d/%d) — skipping" % [g["key"], total, int(g["points"])])
			continue
		if g["from"] != null:
			var out_of_pool := false
			for a in alloc:
				if int(alloc[a]) > 0 and not a in g["from"]:
					out_of_pool = true
			if out_of_pool:
				warns.append("ASI grant \"%s\" has out-of-pool allocation — skipping" % g["key"])
				continue
		for a in alloc:
			if int(alloc[a]) > 0:
				bonus[a].append({"value": int(alloc[a]), "source": tg["source"]})

	var out := {}
	for k in KEYS:
		var b: int = int(base.get(k, 10))
		var total: int = b
		for x in bonus[k]:
			total += x["value"]
		total = mini(total, 20)
		out[k] = {"base": b, "total": total, "mod": floori((total - 10) / 2.0), "bonuses": bonus[k]}
	return {"abilities": out, "warnings": warns}

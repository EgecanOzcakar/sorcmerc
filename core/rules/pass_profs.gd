# Saves, skills, expertise, and the armor/weapon/tool/language lists.
# Ported from dnd-maintainer src/lib/resolver/proficiencies.ts.
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

# {saves: {a: int}, save_prof: {a: bool}}
static func saves(abilities: Dictionary, bundles: Array, pb: int, choices: Dictionary) -> Dictionary:
	var prof := {}
	for tg in Bundles.of_type(bundles, "proficiency"):
		if tg["grant"]["category"] == "saving-throw":
			prof[tg["grant"]["id"]] = true
	for tg in Bundles.of_type(bundles, "proficiency-choice"):
		var g: Dictionary = tg["grant"]
		if g["category"] != "saving-throw":
			continue
		var d = choices.get(g["key"])
		if d == null or d.get("type") != "saving-throw-choice":
			continue
		var picks: Array = []
		for a in d["savingThrows"]:
			if g["from"] == null or a in g["from"]:
				picks.append(a)
		for a in picks.slice(0, int(g["count"])):
			prof[a] = true

	var out := {}
	var flags := {}
	for a in ABILITIES:
		flags[a] = prof.has(a)
		out[a] = int(abilities[a]["mod"]) + (pb if prof.has(a) else 0)
	return {"saves": out, "save_prof": flags}

# {skills: {id: int}, skill_prof: {id: "none"|"prof"|"expert"}}
static func skills(abilities: Dictionary, bundles: Array, pb: int, choices: Dictionary) -> Dictionary:
	var prof := {}
	for tg in Bundles.of_type(bundles, "proficiency"):
		if tg["grant"]["category"] == "skill":
			prof[tg["grant"]["id"]] = true
	for tg in Bundles.of_type(bundles, "proficiency-choice"):
		var g: Dictionary = tg["grant"]
		if g["category"] != "skill":
			continue
		var d = choices.get(g["key"])
		if d != null and d.get("type") == "skill-choice":
			for s in d["skills"]:
				prof[s] = true

	var expert := {}
	for tg in Bundles.of_type(bundles, "skill-expertise"):
		expert[tg["grant"]["skill"]] = true
	for tg in Bundles.of_type(bundles, "expertise-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		if d == null or d.get("type") != "expertise-choice":
			continue
		var pool: Array = []
		for s in d["skills"]:
			if g["from"] == null or s in g["from"]:
				pool.append(s)
		for s in pool.slice(0, int(g["count"])):
			expert[s] = true

	var check_bonuses := Bundles.of_type(bundles, "ability-check-bonus")

	var out := {}
	var flags := {}
	for sid in Catalog.skills():
		var ability: String = Catalog.skills()[sid]["ability"]
		var is_prof: bool = prof.has(sid)
		var is_expert: bool = is_prof and expert.has(sid)
		var bonus: int = int(abilities[ability]["mod"])
		if is_prof:
			bonus += pb
		if is_expert:
			bonus += pb
		for tg in check_bonuses:
			var g: Dictionary = tg["grant"]
			if not ability in g["abilities"]:
				continue
			if g.get("onlyWhenNotProficient", false) and is_prof:
				continue
			if g["value"] == "half-proficiency":
				bonus += ceili(pb / 2.0)
		out[sid] = bonus
		flags[sid] = "expert" if is_expert else ("prof" if is_prof else "none")
	return {"skills": out, "skill_prof": flags}

# {armor, weapon, tool, language: Array[String], expertise_tools: Array[String], pending: Array}
static func proficiencies(bundles: Array, choices: Dictionary) -> Dictionary:
	var out := {"armor": [], "weapon": [], "tool": [], "language": []}
	var pending: Array = []

	for tg in Bundles.of_type(bundles, "proficiency"):
		var g: Dictionary = tg["grant"]
		if out.has(g["category"]) and not g["id"] in out[g["category"]]:
			out[g["category"]].append(g["id"])

	for tg in Bundles.of_type(bundles, "proficiency-choice"):
		var g: Dictionary = tg["grant"]
		var cat: String = g["category"]
		# skill and saving-throw are handled above; armor/weapon choices are unused by the export
		if cat != "tool" and cat != "language":
			continue
		var want := "tool-choice" if cat == "tool" else "language-choice"
		var d = choices.get(g["key"])
		if d != null and d.get("type") == want:
			for v in d["tools" if cat == "tool" else "languages"]:
				if not v in out[cat]:
					out[cat].append(v)
		else:
			pending.append({"type": want, "key": g["key"], "source": tg["source"],
				"category": cat, "count": int(g["count"]), "from": g["from"]})

	# Tool expertise, filtered by fromTools and capped at count.
	var etools: Array = []
	for tg in Bundles.of_type(bundles, "expertise-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		if d == null or d.get("type") != "expertise-choice":
			continue
		var pool: Array = []
		for t in d["tools"]:
			if t in g["fromTools"]:
				pool.append(t)
		etools.append_array(pool.slice(0, int(g["count"])))

	out["expertise_tools"] = etools
	out["pending"] = pending
	return out

# Every choice-bearing grant that is undecided or invalidly decided -> a pending entry.
# Ported from the pending blocks of dnd-maintainer src/lib/resolver/index.ts.
# bundle-choice is deliberately absent: the creator's Equipment step answers it, and
# pass_gear.gd says why that is not a warning either (#189, spec §2.3).
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Choice = preload("res://core/rules/choice.gd")
const PassGear = preload("res://core/rules/pass_gear.gd")

# {pending: Array, warnings: Array[String]}
static func resolve(bundles: Array, choices: Dictionary, skill_prof: Dictionary,
		weapon_profs: Array, expanded_feats: Dictionary) -> Dictionary:
	var out: Array = []
	var warns: Array[String] = []

	for tg in Bundles.of_type(bundles, "ability-choice"):
		var g: Dictionary = tg["grant"]
		if _undecided(choices, g["key"], "ability-choice"):
			out.append(_p("ability-choice", g, tg, {"count": int(g["count"]), "bonus": int(g["bonus"]),
				"from": g["from"]}))

	for tg in Bundles.of_type(bundles, "proficiency-choice"):
		var g: Dictionary = tg["grant"]
		if g["category"] == "skill" and _undecided(choices, g["key"], "skill-choice"):
			out.append(_p("skill-choice", g, tg, {"category": "skill", "count": int(g["count"]), "from": g["from"]}))
		elif g["category"] == "saving-throw" and _undecided(choices, g["key"], "saving-throw-choice"):
			out.append(_p("saving-throw-choice", g, tg, {"category": "saving-throw",
				"count": int(g["count"]), "from": g["from"]}))

	# ASI <-> feat-choice either-or: satisfying one suppresses the other's pending entry.
	for tg in Bundles.of_type(bundles, "asi"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var valid := false
		if d != null and d.get("type") == "asi":
			var total := 0
			for v in d["allocation"].values():
				total += int(v)
			valid = total == int(g["points"])
			if valid and g["from"] != null:
				for a in d["allocation"]:
					if int(d["allocation"][a]) > 0 and not a in g["from"]:
						valid = false
		if valid:
			if _feat_satisfied(choices, g["key"]):
				warns.append("BUG: both ASI \"%s\" and its companion feat-choice are satisfied" % g["key"])
		elif not _feat_satisfied(choices, g["key"]):
			out.append(_p("asi", g, tg, {"points": int(g["points"]), "from": g["from"]}))

	# A feat grant that survives collect() was never expanded — a bundles.gd bug.
	for tg in Bundles.of_type(bundles, "feat"):
		if not expanded_feats.has(tg["grant"]["featId"]):
			warns.append("BUG: unexpanded feat grant \"%s\" reached the resolver" % tg["grant"]["featId"])

	var all_styles: Array = []
	for tg in Bundles.of_type(bundles, "fighting-style-choice"):
		var d = choices.get(tg["grant"]["key"])
		if d != null and d.get("type") == "fighting-style-choice":
			for s in d["styles"]:
				if s in tg["grant"]["from"]:
					all_styles.append(s)
	for tg in Bundles.of_type(bundles, "fighting-style-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var valid: Array = []
		if d != null and d.get("type") == "fighting-style-choice":
			for s in d["styles"]:
				if s in g["from"]:
					valid.append(s)
		if valid.size() < int(g["count"]):
			out.append(_p("fighting-style-choice", g, tg, {"count": int(g["count"]), "from": g["from"],
				"already_chosen": all_styles}))

	for tg in Bundles.of_type(bundles, "damage-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var valid: Array = []
		if d != null and d.get("type") == "damage-choice":
			for t in d["damageTypes"]:
				if t in g["from"]:
					valid.append(t)
		if valid.size() < int(g["count"]):
			out.append(_p("damage-choice", g, tg, {"count": int(g["count"]), "from": g["from"],
				"featureIdPrefix": g["featureIdPrefix"]}))

	var eligible: Array = []
	for wid in Catalog.index("weapons.json"):
		var w: Dictionary = Catalog.index("weapons.json")[wid]
		if w["mastery"] != null and PassGear.weapon_proficient(w, weapon_profs):
			eligible.append(wid)
	var claimed: Array = []
	for tg in Bundles.of_type(bundles, "weapon-mastery-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var valid: Array = []
		if d != null and d.get("type") == "weapon-mastery-choice":
			for wid in d["weaponIds"]:
				if wid in eligible and not wid in claimed and not wid in valid:
					valid.append(wid)
		if valid.size() < int(g["count"]):
			out.append(_p("weapon-mastery-choice", g, tg, {"count": int(g["count"]), "from": eligible,
				"already_chosen": claimed.duplicate()}))
		claimed.append_array(valid)

	for tg in Bundles.of_type(bundles, "feature-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var ok := false
		if d != null and d.get("type") == "feature-choice":
			for o in g["options"]:
				if o["optionId"] == d["optionId"]:
					ok = true
		if not ok:
			var opts: Array = []
			for o in g["options"]:
				opts.append({"optionId": o["optionId"], "featureId": o["featureId"]})
			out.append(_p("feature-choice", g, tg, {"options": opts}))

	for tg in Bundles.of_type(bundles, "lineage-choice"):
		var g: Dictionary = tg["grant"]
		if _undecided(choices, g["key"], "lineage-choice"):
			out.append(_p("lineage-choice", g, tg, {"speciesId": g["speciesId"], "from": g["from"]}))

	for tg in Bundles.of_type(bundles, "feat-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var ok: bool = d != null and d.get("type") == "feat-choice" \
			and not Catalog.feat_src(d["featId"]).is_empty()
		if not ok and not _asi_satisfied(choices, g["key"]):
			out.append(_p("feat-choice", g, tg, {"from": g["from"], "category": g["category"]}))

	for tg in Bundles.of_type(bundles, "spell-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		# Anything on the list ever chosen stays chosen (a preset's Light, an old
		# save's Guidance); a fresh pick only offers what does something here.
		var pool := Catalog.spell_list(g["spellList"], int(g["spellLevel"]))
		var offered := Effects.pick_pool(g["spellList"], int(g["spellLevel"]))
		var valid: Array = []
		if d != null and d.get("type") == "spell-choice":
			for sid in d["spellIds"]:
				if sid in pool and not sid in valid:
					valid.append(sid)
		# A pool smaller than the grant (a bard's 6th-level picks — the catalog
		# stops at 5th) is satisfied by all of it, not pending forever.
		if valid.size() < mini(int(g["count"]), offered.size()):
			out.append(_p("spell-choice", g, tg, {"count": int(g["count"]), "spellList": g["spellList"],
				"spellLevel": int(g["spellLevel"])}))

	for tg in Bundles.of_type(bundles, "subclass"):
		var g: Dictionary = tg["grant"]
		if _undecided(choices, g["key"], "subclass"):
			out.append(_p("subclass", g, tg, {"classId": g["classId"],
				"from": Catalog.subclasses_of(g["classId"])}))

	for tg in Bundles.of_type(bundles, "expertise-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		var n := 0
		if d != null and d.get("type") == "expertise-choice":
			for s in d["skills"]:
				if skill_prof.get(s, "none") != "none" and (g["from"] == null or s in g["from"]):
					n += 1
			for t in d["tools"]:
				if t in g["fromTools"]:
					n += 1
		if n != int(g["count"]):
			out.append(_p("expertise-choice", g, tg, {"count": int(g["count"]), "from": g["from"],
				"fromTools": g["fromTools"]}))

	return {"pending": out, "warnings": warns}

static func _p(t: String, g: Dictionary, tg: Dictionary, extra: Dictionary) -> Dictionary:
	var d := {"type": t, "key": g["key"], "source": tg["source"]}
	d.merge(extra)
	return d

static func _undecided(choices: Dictionary, key: String, want: String) -> bool:
	var d = choices.get(key)
	return d == null or d.get("type") != want

static func _feat_satisfied(choices: Dictionary, asi_key: String) -> bool:
	var d = choices.get(Choice.companion(asi_key, "feat-choice"))
	return d != null and d.get("type") == "feat-choice" and String(d["featId"]) != ""

static func _asi_satisfied(choices: Dictionary, feat_key: String) -> bool:
	var d = choices.get(Choice.companion(feat_key, "asi"))
	if d == null or d.get("type") != "asi":
		return false
	var total := 0
	for v in d["allocation"].values():
		total += int(v)
	return total > 0

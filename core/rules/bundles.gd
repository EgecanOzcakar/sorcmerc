# Pass 1: build -> a flat, ordered list of {source, grants} bundles.
# Order is load-bearing (class_level() counts class bundles; several passes are
# first-seen-wins), so the sub-passes run in exactly the source's order.
# Ported from dnd-maintainer src/lib/sources/index.ts collectBundles().
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

# {bundles: Array, warnings: Array[String], expanded_feats: Dictionary}
static func collect(ch) -> Dictionary:
	var bundles: Array = []
	var warns: Array[String] = []

	# 1. species
	var species := Catalog.species_src(ch.species_id)
	if species.is_empty():
		warns.append("no source data for species \"%s\" — species grants will be empty" % ch.species_id)
	else:
		bundles.append({"source": {"origin": "species", "id": ch.species_id},
			"grants": species.get("traits", [])})

	# 2. one bundle per class level, classes in first-seen order
	var class_counts := {}
	for l in ch.levels:
		class_counts[l["class_id"]] = int(class_counts.get(l["class_id"], 0)) + 1
	for cid in class_counts:
		var src := Catalog.class_src(cid)
		if src.is_empty():
			warns.append("no source data for class \"%s\" — class grants will be empty" % cid)
			continue
		var table: Array = src["levels"]
		for i in mini(class_counts[cid], table.size()):
			bundles.append({"source": {"origin": "class", "id": cid, "level": i + 1},
				"grants": table[i]})

	# 3. subclass features at or below the class level (retroactive by design)
	for cid in class_counts:
		for g in _of_type(bundles, "subclass"):
			var d = ch.choices.get(g["grant"]["key"])
			if d == null or d.get("type") != "subclass":
				continue
			var sub := Catalog.subclass_src(d["subclassId"])
			if sub.is_empty():
				warns.append("no source data for subclass \"%s\" — subclass features will be empty" % d["subclassId"])
				continue
			if sub["classId"] != cid:
				continue
			for entry in sub["levels"]:
				if int(entry["classLevel"]) <= class_counts[cid]:
					bundles.append({"source": {"origin": "subclass", "id": sub["id"],
						"classId": cid, "level": int(entry["classLevel"])},
						"grants": entry["grants"]})

	# 4. fighting styles
	for tg in _of_type(bundles, "fighting-style-choice"):
		var d = ch.choices.get(tg["grant"]["key"])
		if d == null or d.get("type") != "fighting-style-choice":
			continue
		for sid in d["styles"]:
			var style := Catalog.fighting_style_src(sid)
			if style.is_empty():
				warns.append("no source data for fighting style \"%s\"" % sid)
			else:
				bundles.append({"source": tg["source"], "grants": style["grants"]})

	# 5. damage choices -> a synthesized feature grant "<prefix>-<type>"
	for tg in _of_type(bundles, "damage-choice"):
		var g: Dictionary = tg["grant"]
		var d = ch.choices.get(g["key"])
		if d == null or d.get("type") != "damage-choice":
			continue
		for dt in d["damageTypes"]:
			if not dt in g["from"]:
				continue
			bundles.append({"source": tg["source"], "grants": [
				{"type": "feature", "feature": {"id": "%s-%s" % [g["featureIdPrefix"], dt]}}]})

	# 6. lineages
	for tg in _of_type(bundles, "lineage-choice"):
		var g: Dictionary = tg["grant"]
		var d = ch.choices.get(g["key"])
		if d == null or d.get("type") != "lineage-choice":
			continue
		var found := false
		for lin in Catalog.species_src(g["speciesId"]).get("lineages", []):
			if lin["id"] == d["lineageId"]:
				bundles.append({"source": tg["source"], "grants": lin["grants"]})
				found = true
		if not found:
			warns.append("no grants for lineage \"%s\" of species \"%s\"" % [d["lineageId"], g["speciesId"]])

	# 7. background
	if ch.background_id != "":
		var bg := Catalog.background_src(ch.background_id)
		if bg.is_empty():
			warns.append("no source data for background \"%s\"" % ch.background_id)
		else:
			bundles.append({"source": {"origin": "background", "id": ch.background_id},
				"grants": bg["grants"]})

	# 8. embedded feat grants (background origin feats). Snapshot first — the loop appends.
	var expanded := {}
	var snapshot: int = bundles.size()
	for i in snapshot:
		for g in bundles[i]["grants"]:
			if g["type"] == "feat":
				_expand_feat(g["featId"], bundles, expanded, warns)

	# 9. feats taken outside a feat-choice grant
	for fid in ch.feats:
		_expand_feat(fid, bundles, expanded, warns)

	# 10. decided feat-choices — after 9, so a chosen feat's sub-grants are visible below
	for tg in _of_type(bundles, "feat-choice"):
		var d = ch.choices.get(tg["grant"]["key"])
		if d != null and d.get("type") == "feat-choice":
			_expand_feat(d["featId"], bundles, expanded, warns)

	# 11. item grants — v1 no-op: the export ships no item grants (SCHEMA gaps #1, #2, #6).

	# 12. feature-choices — after all sources, so feat-origin ones are seen.
	# SINGLE-PASS SAFETY: this is not a fixpoint. An option whose own grants contain a
	# `feat`, `lineage-choice` or `feature-choice` would be silently dropped. Safe only
	# because no current option nests one; tests/test_rules.gd asserts that invariant.
	for tg in _of_type(bundles, "feature-choice"):
		var g: Dictionary = tg["grant"]
		var origin: String = tg["source"]["origin"]
		if not origin in ["class", "subclass", "feat"]:
			warns.append("feature-choice \"%s\" has non-class origin \"%s\" — no builder UI exists for it" % [g["key"], origin])
		var d = ch.choices.get(g["key"])
		if d == null or d.get("type") != "feature-choice":
			continue
		var option := {}
		for o in g["options"]:
			if o["optionId"] == d["optionId"]:
				option = o
		if option.is_empty():
			warns.append("feature-choice \"%s\" references unknown option \"%s\"" % [g["key"], d["optionId"]])
			continue
		var grants: Array = [{"type": "feature", "feature": {"id": option["featureId"]}}]
		grants.append_array(option["grants"])
		bundles.append({"source": tg["source"], "grants": grants})

	# 13. spell-choices -> one `spell` grant each. After 12, so Magic Initiate's
	# injected spell-choices resolve.
	for tg in _of_type(bundles, "spell-choice"):
		var g: Dictionary = tg["grant"]
		var d = ch.choices.get(g["key"])
		if d == null or d.get("type") != "spell-choice":
			continue
		var pool := Catalog.spell_list(g["spellList"], int(g["spellLevel"]))
		for sid in d["spellIds"]:
			if not sid in pool:
				warns.append("spell-choice \"%s\" picked \"%s\", not on the %s list at level %d" % [
					g["key"], sid, g["spellList"], int(g["spellLevel"])])
				continue
			bundles.append({"source": tg["source"],
				"grants": [{"type": "spell", "spellId": sid, "alwaysPrepared": false}]})

	# 14. minClassLevel gating, last, so expanded option grants are gated too
	bundles = _gate(bundles, class_counts, warns)

	return {"bundles": bundles, "warnings": warns, "expanded_feats": expanded}

static func _expand_feat(fid: String, bundles: Array, expanded: Dictionary, warns: Array[String]) -> void:
	if expanded.has(fid):
		return
	var f := Catalog.feat_src(fid)
	if f.is_empty():
		warns.append("no source data for feat \"%s\" — feat grants will be empty" % fid)
		return
	bundles.append({"source": {"origin": "feat", "id": fid}, "grants": f["grants"]})
	expanded[fid] = true

# A grant with a minClassLevel above its granting class's level is suppressed.
# A minClassLevel on a non-class origin has nothing to gate against: keep it, warn loudly.
static func _gate(bundles: Array, class_counts: Dictionary, warns: Array[String]) -> Array:
	var out: Array = []
	for b in bundles:
		var src: Dictionary = b["source"]
		var lvl = null
		if src["origin"] == "subclass":
			lvl = class_counts.get(src["classId"])
		elif src["origin"] == "class":
			lvl = class_counts.get(src["id"])
		var kept: Array = []
		for g in b["grants"]:
			if not g.has("minClassLevel"):
				kept.append(g)
			elif lvl == null:
				warns.append("grant with minClassLevel=%d on origin \"%s\" — ignored (no class level to gate against)" % [
					int(g["minClassLevel"]), src["origin"]])
				kept.append(g)
			elif int(lvl) >= int(g["minClassLevel"]):
				kept.append(g)
		out.append(b if kept.size() == b["grants"].size() else {"source": src, "grants": kept})
	return out

# [{grant, source}] for every grant of `t`, in bundle order.
static func of_type(bundles: Array, t: String) -> Array:
	return _of_type(bundles, t)

static func _of_type(bundles: Array, t: String) -> Array:
	var out: Array = []
	for b in bundles:
		for g in b["grants"]:
			if g["type"] == t:
				out.append({"grant": g, "source": b["source"]})
	return out

# Level accounting lives here because class_level() does.
static func proficiency_bonus(level: int) -> int:
	if level < 5: return 2
	if level < 9: return 3
	if level < 13: return 4
	if level < 17: return 5
	return 6

# The highest class level tagged on a class-origin bundle.
#
# This used to COUNT class-origin bundles, on the reading that collect() appends
# exactly one per class level. It does — at step 2. Steps 4, 5, 6, 12 and 13 then
# append DERIVED bundles carrying the source they were derived from, which for a
# class-origin grant is that same {origin: class, id, level} dict: one per chosen
# fighting style, one per chosen damage type, one per decided feature-choice, and
# — the big one — one per spell picked in a class spell-choice. So the count was
# the class level only for a build with nothing decided yet, which is exactly the
# shape every test fixture had. A decided level-4 bard counted 11, a level-4
# sorcerer 12, a level-4 wizard 13, and everything keyed on this number (Bardic
# die and College of Dance AC, sorcery points and Channel Divinity uses, Psi
# Warrior dice, third-caster slots) scaled off a level the character never had.
#
# The level tag is the answer and survives being copied onto a derived bundle, so
# the highest one seen is the class level.
static func class_level(bundles: Array, cid: String) -> int:
	var best := 0
	for b in bundles:
		var s: Dictionary = b["source"]
		if s["origin"] == "class" and s["id"] == cid:
			best = maxi(best, int(s.get("level", 0)))
	return best

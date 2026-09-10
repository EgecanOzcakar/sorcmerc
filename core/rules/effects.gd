# feature id / spell id / condition id -> combat mechanics.
# The export carries none of these (SCHEMA gaps #3, #4, #9), so data/effects/*.json
# is sorcmerc-authored. A feature with no entry is a FLAVOR feature: it shows on the
# sheet and does nothing in combat. That default is what makes 430 feature ids tractable.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const KINDS := ["passive_damage", "self_buff", "ally_buff", "heal_self", "heal_ally",
	"grant_action", "grant_verb", "attacks_per_action", "attack_modifier", "damage_bonus",
	"save_effect", "reaction"]

# castingTime -> action-economy cost. Anything longer than a Reaction is non-combat.
const CASTING_TIME := {"Action": "action", "Bonus Action": "bonus", "Reaction": "reaction"}

static func feature(id: String) -> Dictionary:
	var d = Catalog.all("effects/features.json")
	return d.get(id, {}) if d is Dictionary else {}

static func condition(id: String) -> Dictionary:
	var d = Catalog.all("effects/conditions.json")
	return d.get(id, {}) if d is Dictionary else {}

# spells[].mechanics as the draft, data/effects/spells.json layered over it.
# {} when the spell is not combat-castable.
static func spell(id: String) -> Dictionary:
	var def := Catalog.spell(id)
	var merged := {}
	var draft = def.get("mechanics")
	if draft is Dictionary:
		merged.merge(draft)
	var over = Catalog.all("effects/spells.json")
	if over is Dictionary and over.has(id):
		merged.merge(over[id], true)
	if not merged.has("cost"):
		var t = CASTING_TIME.get(def.get("castingTime", ""))
		if t == null:
			return {}
		merged["cost"] = t
	if merged.get("non_combat", false):
		return {}
	if not (merged.has("damage") or merged.has("heal") or merged.has("healing")
			or merged.has("conditions")):
		return {}
	merged["level"] = int(def.get("level", 0))
	merged["concentration"] = def.get("concentration", false)
	return merged

# {by: "class_level"|"pb"|"ability_mod", class?, ability?, steps?, formula?} -> int.
# A plain number passes through.
static func scale(spec, sheet) -> int:
	if spec is float or spec is int:
		return int(spec)
	if not spec is Dictionary or sheet == null:
		return 0  # a monster has no sheet: its effect entries must carry plain numbers
	var n := 0
	match spec.get("by", ""):
		"class_level": n = sheet.class_level(spec.get("class", ""))
		"pb": n = sheet.proficiency_bonus
		"ability_mod": n = sheet.mod(spec.get("ability", "str"))
		_: return 0
	if spec.has("steps"):
		var best := -1
		var v := 0
		for s in spec["steps"]:
			if n >= int(s["min"]) and int(s["min"]) > best:
				best = int(s["min"])
				v = int(s["value"])
		return v
	match spec.get("formula", ""):
		"ceil_half": return ceili(n / 2.0)
		"floor_half": return floori(n / 2.0)
	return n

# Fully numeric combat verbs for a sheet. Resolved once, at adapter time, so
# combat.gd never re-reads the sheet mid-turn.
static func verbs_for(sheet, feature_ids = null) -> Array:
	var out: Array = []
	for fid in (sheet.features if feature_ids == null else feature_ids):
		var e := feature(fid)
		if e.is_empty():
			continue  # flavor feature
		assert(e["kind"] in KINDS, "unknown effect kind \"%s\" on \"%s\"" % [e.get("kind"), fid])
		var v := {"id": fid, "kind": e["kind"], "cost": e.get("cost", "action"),
			"label": verb_label(fid), "targeting": e.get("targeting", TARGETING.get(e["kind"], "self"))}
		for k in ["trigger", "once_per", "requires", "verbs", "status", "duration", "resist",
				"save", "conditions", "shape", "range_ft", "halve_damage", "self",
				"attacks_against", "extra_attacks", "value"]:
			if e.has(k):
				v[k] = e[k]
		if e.has("dice"):
			var d: Dictionary = e["dice"]
			v["dice_count"] = scale(d.get("count", 1), sheet)
			v["dice_sides"] = int(d.get("sides", 6))
			v["dice_bonus"] = scale(d.get("plus", 0), sheet)
		if e.has("bonus_damage"):
			v["bonus_damage"] = scale(e["bonus_damage"], sheet)
		if e.has("amount"):
			v["amount"] = scale(e["amount"], sheet)
		if e.has("pool"):
			v["pool"] = e["pool"]
			v["uses"] = sheet.pool_max(e["pool"])
		elif e.has("uses"):
			v["pool"] = fid          # synthetic pool: the export grants no pool for this feature
			v["uses"] = scale(e["uses"], sheet)
		out.append(v)
	return out

# Who a verb is pointed at. combat.gd's available()/legal_target() read this.
const TARGETING := {"heal_ally": "ally", "ally_buff": "ally", "save_effect": "enemy"}

# One verb per castable spell, per slot level it can be cast at. Ranges stay in FEET
# here — adapter.gd owns the hex conversion (spec §2.5).
static func spell_verbs_for(sheet, spell_ids: Array) -> Array:
	var out: Array = []
	var sc: Dictionary = sheet.spellcasting
	if sc.is_empty():
		return out
	var slots: Array = sc.get("slots", [])
	var abil_mod: int = sheet.mod(sc.get("ability", "wis"))
	for sid in spell_ids:
		var m := spell(sid)
		if m.is_empty():
			continue
		var base := int(m.get("level", 0))
		var top := base
		if base > 0:                     # cantrips scale with level, not with slots
			for l in range(base, 10):
				if l - 1 < slots.size() and int(slots[l - 1]) > 0:
					top = l
		for lvl in range(base, top + 1):
			out.append(_spell_verb(sid, m, lvl, base, sheet, abil_mod, int(sc.get("save_dc", 0))))
	return out

static func _spell_verb(sid: String, m: Dictionary, lvl: int, base: int, sheet,
		abil_mod: int, dc: int) -> Dictionary:
	var up := lvl - base
	var shape: String = m.get("shape", "single")
	var v := {
		"id": sid if up == 0 else "%s@%d" % [sid, lvl], "spell": sid, "kind": "spell",
		"label": Catalog.spell(sid).get("name", humanize(sid)) + ("" if up == 0 else " ★%d" % lvl),
		"cost": m.get("cost", "action"), "slot_level": lvl, "shape": shape,
		"range_ft": int(m.get("range_ft", 5)), "size_ft": int(m.get("size_ft", 0)),
		"save": m.get("save", ""), "save_dc": dc, "half_on_save": m.get("half_on_save", false),
		"ignores_cover": m.get("ignores_cover", false),
		"concentration": m.get("concentration", false),
	}
	if m.has("attack"):   # a spell attack rolls to hit instead of forcing a save
		v["attack_bonus"] = int(sheet.spellcasting.get("attack_bonus", 0))
	if m.has("damage"):
		var d: Dictionary = m["damage"][0]
		var n := int(d.get("count", 1))
		if up > 0 and m.has("upcast"):
			n += up * int(m["upcast"]["per_level"].get("count", 0))
		if base == 0:
			n = _cantrip_count(m, n, sheet.level)
		v["dice_count"] = n
		v["dice_sides"] = int(d.get("sides", 6))
		v["damage_type"] = d.get("type", "")
	if m.has("heal"):
		var h: Dictionary = m["heal"]
		var n := int(h.get("count", 1))
		if up > 0 and m.has("upcast"):
			n += up * int(m["upcast"]["per_level"].get("count", 0))
		v["heal_count"] = n
		v["heal_sides"] = int(h.get("sides", 8))
		v["heal_bonus"] = abil_mod if h.get("plus", "") == "ability_mod" else int(h.get("plus", 0))
	if shape in ["cone", "line"]:
		v["targeting"] = "direction"
	elif shape in ["sphere", "cube", "cylinder", "radius", "emanation"]:
		v["targeting"] = "hex"
	else:
		v["targeting"] = "ally" if v.has("heal_count") else "enemy"
	return v

static func _cantrip_count(m: Dictionary, n: int, char_level: int) -> int:
	for s in m.get("cantrip_scale", []):
		if char_level >= int(s["min"]):
			n = int(s["count"])
	return n

# Fallback until F1 re-exports feature/pool prose (SCHEMA gap #4).
static func humanize(id: String) -> String:
	return id.replace("-", " ").capitalize()

# Feature ids are "<class>-<name>"; a button says "Second Wind", not "Fighter Second Wind".
static func verb_label(id: String) -> String:
	var p := id.split("-")
	return humanize("-".join(p.slice(1)) if p.size() > 1 else id)

# Validates the three hand-authored files: closed `kind` vocabulary, known ids.
static func validate() -> Array[String]:
	var errs: Array[String] = []
	var f = Catalog.all("effects/features.json")
	if not f is Dictionary:
		return ["effects/features.json did not load"] as Array[String]
	for id in f:
		if id.begins_with("_"):
			continue
		if not f[id].get("kind") in KINDS:
			errs.append("features.json: \"%s\" has unknown kind \"%s\"" % [id, f[id].get("kind")])
	var sp = Catalog.all("effects/spells.json")
	for id in sp:
		if not id.begins_with("_") and Catalog.index("spells.json").get(id) == null:
			errs.append("spells.json: \"%s\" is not in the catalog" % id)
	var cn = Catalog.all("effects/conditions.json")
	for id in cn:
		if not id.begins_with("_") and Catalog.index("conditions.json").get(id) == null:
			errs.append("conditions.json: \"%s\" is not in the catalog" % id)
	return errs

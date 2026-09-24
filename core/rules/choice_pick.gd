# The creator's choice model, UI-free: a pending entry from the resolver becomes
# N picks from a list of options, and a list of picks becomes the decision
# Character.decide() stores. Lifted out of scenes/creator/creator.gd (which keeps
# one-line wrappers, so every Creator.* call in the tests still reads the same)
# the day a core module needed it: core/recruits.gd pre-rolls a hireling's
# skills, languages, tools and mastery through exactly these functions, so a
# recruit's sheet is answered by the same rules as one the player builds — and
# core/ may not preload a scene.
#
#   ChoicePick.options_for(p, sheet)          # [{id, label}] for one pending entry
#   ChoicePick.toggle(p, picks, id)           # one click, never an invalid state
#   ChoicePick.decision_for(p, picks)         # -> ch.decide(p["key"], ...)
#   ChoicePick.unbuilt(p)                     # {id: why} offered but not played
#   ChoicePick.recommended_array(class_id)    # the quick-build standard array
#
# What this does NOT own: which choices exist or whether one is still open
# (core/rules/pass_pending.gd and resolve.gd), the display grouping of merged
# lists and the progression locks (scenes/creator/creator.gd — they are about
# what a screen shows, not about what a pick means), or any drawing.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const PassGear = preload("res://core/rules/pass_gear.gd")
const Effects = preload("res://core/rules/effects.gd")
const Metamagic = preload("res://core/metamagic.gd")

const ABILS := ["str", "dex", "con", "int", "wis", "cha"]
const ABIL_NAME := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}
const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
const PB_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}   # 2024 point buy
const PB_BUDGET := 27

# ponytail: the export has no languages.json (SCHEMA gap) — the PHB standard list,
# hardcoded. Delete this the day F1 exports one.
const LANGUAGES := ["common", "common-sign", "draconic", "dwarvish", "elvish", "giant",
	"gnomish", "goblin", "halfling", "orc", "abyssal", "celestial", "infernal",
	"deep-speech", "primordial", "sylvan", "undercommon", "thieves-cant"]

# =========================================================================
# Choice model — static, UI-free, so tests/test_creator.gd drives the same code.
# A pending entry from the resolver becomes: N picks from a list of options,
# and a list of picks becomes a decision Dictionary for Character.decide().
# =========================================================================

static func pick_count(p: Dictionary) -> int:
	match p["type"]:
		"asi": return int(p["points"])
		"subclass", "lineage-choice", "feature-choice", "feat-choice": return 1
		_: return int(p.get("count", 1))

# asi is the only category where the same option may be picked twice (+2 to one).
static func allows_repeat(p: Dictionary) -> bool:
	return p["type"] == "asi"

static func max_per_option(p: Dictionary) -> int:
	return 2 if p["type"] == "asi" else 1

# [{id, label}] — `sheet` narrows the pools that depend on the current build
# (expertise: only skills you are proficient in). `picks` is what this choice
# has already been answered with; it only matters for expertise, where a pick
# changes the very grade the pool is filtered on — see below.
static func options_for(p: Dictionary, sheet = null, picks: Array = []) -> Array:
	var ids: Array = []
	match p["type"]:
		"skill-choice":
			ids = p["from"] if p["from"] != null else Catalog.skills().keys()
		"saving-throw-choice", "asi", "ability-choice":
			ids = p["from"] if p.get("from") != null else ABILS
		"language-choice":
			ids = p["from"] if p["from"] != null else LANGUAGES
		"tool-choice":
			ids = p["from"] if p["from"] != null else all_tools()
		"expertise-choice":
			if p["from"] != null:
				ids = p["from"].duplicate()
			elif sheet != null:
				# Proficient — or already expert BECAUSE OF THIS CHOICE. Issue
				# #119: pass_profs grades a skill this choice picked "expert",
				# not "prof", so reading only "prof" dropped a decided choice's
				# own two picks off its own row. The heading said "✓ Expertise
				# — pick 2 (2 chosen)" and not one button wore the mark, and
				# clicking any of the rest evicted an invisible pick. A skill
				# some OTHER grant made expert stays off the list: expertise
				# twice over buys nothing.
				for s in sheet.skill_prof:
					if sheet.skill_prof[s] == "prof" \
							or (sheet.skill_prof[s] == "expert" and s in picks):
						ids.append(s)
			else:
				ids = Catalog.skills().keys()
			ids.append_array(p.get("fromTools", []))
		"fighting-style-choice", "weapon-mastery-choice", "damage-choice", "subclass", "lineage-choice":
			for i in p["from"]:
				if not i in p.get("already_chosen", []):
					ids.append(i)
		"spell-choice":
			ids = Effects.pick_pool(p["spellList"], int(p["spellLevel"]))
		"feature-choice":
			for o in p["options"]:
				ids.append(o["optionId"])
		"feat-choice":
			if p["from"] != null:
				ids = p["from"]
			else:
				for f in Catalog.all("feats.json"):
					if f["category"] == p["category"]:
						ids.append(f["id"])
	var out: Array = []
	for i in ids:
		out.append({"id": i, "label": label_for(p, i)})
	return out

static func label_for(p: Dictionary, id: String) -> String:
	match p["type"]:
		"asi", "ability-choice", "saving-throw-choice":
			return ABIL_NAME.get(id, humanize(id))
		"skill-choice":
			return String(Catalog.skills().get(id, {}).get("name", humanize(id)))
		"expertise-choice":
			return String(Catalog.skills().get(id, {}).get("name", humanize(id)))
		"spell-choice":
			return String(Catalog.spell(id).get("name", humanize(id)))
		"feat-choice":
			return String(Catalog.feat_src(id).get("name", humanize(id)))
		"subclass":
			return String(Catalog.subclass_src(id).get("name", humanize(id)))
		"weapon-mastery-choice":
			return String(Catalog.weapon(id).get("name", humanize(id)))
	return humanize(id)

# picks -> the decision Character.decide() stores. Payload keys are the source's
# (spec §2.1); never rename them.
static func decision_for(p: Dictionary, picks: Array) -> Dictionary:
	var t: String = p["type"]
	match t:
		"skill-choice": return {"type": t, "skills": picks.duplicate()}
		"saving-throw-choice": return {"type": t, "savingThrows": picks.duplicate()}
		"tool-choice": return {"type": t, "tools": picks.duplicate()}
		"language-choice": return {"type": t, "languages": picks.duplicate()}
		"ability-choice": return {"type": t, "abilities": picks.duplicate()}
		"fighting-style-choice": return {"type": t, "styles": picks.duplicate()}
		"weapon-mastery-choice": return {"type": t, "weaponIds": picks.duplicate()}
		"damage-choice": return {"type": t, "damageTypes": picks.duplicate()}
		"spell-choice": return {"type": t, "spellIds": picks.duplicate()}
		"subclass": return {"type": t, "subclassId": picks[0] if picks else ""}
		"lineage-choice": return {"type": t, "lineageId": picks[0] if picks else ""}
		"feature-choice": return {"type": t, "optionId": picks[0] if picks else ""}
		"feat-choice": return {"type": t, "featId": picks[0] if picks else ""}
		"expertise-choice":
			var sk: Array = []
			var tl: Array = []
			for i in picks:
				if Catalog.skills().has(i):
					sk.append(i)
				else:
					tl.append(i)
			return {"type": t, "skills": sk, "tools": tl}
		"asi":
			var alloc := {}
			for a in picks:
				alloc[a] = int(alloc.get(a, 0)) + 1
			return {"type": t, "allocation": alloc}
	return {"type": t}

# The inverse: a stored decision -> the pick list the UI toggles.
static func picks_from_decision(p: Dictionary, d) -> Array:
	if d == null or d.get("type") != p["type"]:
		return []
	match p["type"]:
		"skill-choice": return d["skills"].duplicate()
		"saving-throw-choice": return d["savingThrows"].duplicate()
		"tool-choice": return d["tools"].duplicate()
		"language-choice": return d["languages"].duplicate()
		"ability-choice": return d["abilities"].duplicate()
		"fighting-style-choice": return d["styles"].duplicate()
		"weapon-mastery-choice": return d["weaponIds"].duplicate()
		"damage-choice": return d["damageTypes"].duplicate()
		"spell-choice": return d["spellIds"].duplicate()
		"subclass": return [d["subclassId"]]
		"lineage-choice": return [d["lineageId"]]
		"feature-choice": return [d["optionId"]]
		"feat-choice": return [d["featId"]]
		"expertise-choice": return d["skills"] + d["tools"]
		"asi":
			var out: Array = []
			for a in d["allocation"]:
				for _i in int(d["allocation"][a]):
					out.append(a)
			return out
	return []

# Options of `p` a pick would waste, id -> why: picked in another list of the
# same kind, or already had from a grant that asked nothing (a background's
# skills, Common). `group` is p's own display group, whose picks are its own.
static func taken_elsewhere(p: Dictionary, group: Array, points: Array, choices: Dictionary, sheet) -> Dictionary:
	var out := {}
	var chosen := {}   # everything any list of this kind has picked
	for q in points:
		if q["type"] != p["type"]:
			continue
		for id in picks_from_decision(q, choices.get(q["key"])):
			chosen[id] = true
			if not q in group:
				out[id] = "picked in another list"
	if sheet == null:
		return out
	var known: Array = []
	match p["type"]:
		"skill-choice":
			known = sheet.skill_prof.keys().filter(func(k): return sheet.skill_prof[k] in ["prof", "expert"])
		"language-choice":
			known = sheet.proficiencies.get("language", [])
		"tool-choice":
			known = sheet.proficiencies.get("tool", [])
	for id in known:
		if not chosen.has(id) and not out.has(id):
			out[id] = "already known"
	return out

# Options of `p` the book offers and the board does not play, id -> why. They
# stay on the list, greyed with the reason, rather than vanishing: a sorcerer
# who knows the 2024 book should see Distant Spell is missing on purpose, not
# wonder where it went. Today that is the five unbuilt Metamagic options
# (core/metamagic.gd); a picker disables these whatever else it un-greys.
static func unbuilt(p: Dictionary) -> Dictionary:
	var out := {}
	if p["type"] != "feature-choice":
		return out
	for o in p["options"]:
		if not Metamagic.is_built(String(o.get("featureId", ""))):
			out[String(o["optionId"])] = Metamagic.NOT_BUILT
	return out

# Toggle one option: adds it, or removes it when already at its per-option cap.
# Over-picking evicts the oldest, so there is never an invalid state to report.
static func toggle(p: Dictionary, picks: Array, id: String) -> Array:
	var out := picks.duplicate()
	var n := out.count(id)
	if n >= max_per_option(p):
		while out.has(id):
			out.erase(id)
		return out
	out.append(id)
	while out.size() > pick_count(p):
		out.remove_at(0)
	return out

# The few ids whose words are not their meaning: an acronym, a run-together
# subclass, a tool with its apostrophe dropped. Everything else reads fine
# capitalized.
const PLAIN := {
	"asi": "Ability score increase", "asi-choice": "Ability score increase",
	"skill-choice": "Skill", "spell-choice": "Spell", "language-choice": "Language",
	"lineage-choice": "Lineage", "feature-choice": "Feature", "fighting-style-choice": "Fighting style",
	"expertise-choice": "Expertise", "weapon-mastery-choice": "Weapon mastery",
	"cantrip-choice": "Cantrip", "feat-choice": "Feat", "subclass": "Subclass",
	"calligrapherstools": "Calligrapher's tools", "thievestools": "Thieves' tools",
	"artisanstools": "Artisan's tools", "gamingset": "Gaming set", "musicalinstrument": "Musical instrument",
	"handcrossbow": "Hand crossbow", "lightcrossbow": "Light crossbow", "heavycrossbow": "Heavy crossbow",
	"simple": "Simple weapons", "martial": "Martial weapons",
	"light": "Light armor", "medium": "Medium armor", "heavy": "Heavy armor",
	"medium-nonmetal": "Medium armor (non-metal)", "shields-nonmetal": "Shields (non-metal)",
}

# A spell by its catalogue name. Not humanize(): PLAIN is keyed by bare ids from
# every table at once, so the cantrip `light` read as "Light armor".
static func spell_name(id: String) -> String:
	return String(Catalog.spell(id).get("name", id.replace("-", " ").capitalize()))

static func humanize(id: String) -> String:
	if PLAIN.has(id):
		return PLAIN[id]
	return id.replace("-", " ").replace("_", " ").capitalize()

static func all_tools() -> Array:
	var out: Array = []
	for f in ["backgrounds.json", "classes.json"]:
		for r in Catalog.all(f):
			for t in r.get("toolProficiencies", []):
				if not t in out:
					out.append(t)
	return out

# --- abilities ------------------------------------------------------------

static func point_buy_cost(abilities: Dictionary) -> int:
	var c := 0
	for a in ABILS:
		c += int(PB_COST.get(int(abilities[a]), 99))
	return c

# Quick-build order from the class catalog: highest ability gets the 15.
static func recommended_array(class_id: String) -> Dictionary:
	var q: Dictionary = Catalog.class_src(class_id).get("quickBuild", {}) if class_id != "" else {}
	var order: Array = []
	for a in q.get("highestAbility", []):
		order.append(a)
	if q.has("secondaryAbility") and not q["secondaryAbility"] in order:
		order.append(q["secondaryAbility"])
	for a in ABILS:
		if not a in order:
			order.append(a)
	var out := {}
	for i in order.size():
		out[order[i]] = STANDARD_ARRAY[i]
	return out

# --- equipment ------------------------------------------------------------

static func proficient_weapons(sheet) -> Array:
	var profs: Array = sheet.proficiencies["weapon"]
	var out: Array = []
	for wid in Catalog.index("weapons.json"):
		var w: Dictionary = Catalog.index("weapons.json")[wid]
		if PassGear.weapon_proficient(w, profs):
			out.append(wid)
	return out

static func proficient_armor(sheet) -> Array:
	var profs: Array = sheet.proficiencies["armor"]
	var out: Array = []
	for aid in Catalog.index("armor.json"):
		# The sheet's own rule, so the druid's "medium-nonmetal" and
		# "shields-nonmetal" open the shelf the way they open the AC.
		if PassGear.proficient("armor", Catalog.index("armor.json")[aid], profs):
			out.append(aid)
	return out

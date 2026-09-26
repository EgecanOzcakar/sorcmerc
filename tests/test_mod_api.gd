# The modding API contract: what a content pack is allowed to write, frozen,
# so heavy feature work cannot break a mod written against it without saying so.
#
# core/mod/manifest.gd makes a promise in one line: a pack declaring an API level
# at or below this build's "is fine and always will be". Nothing enforced it.
# A rename of an effect kind, a quest kind, a story condition or a data file —
# the kind of thing a big feature does in passing — would load every shipped
# pack (they are fixed in the same commit) and silently strand every pack
# written by someone else. So this holds three things still:
#
#   1. The vocabulary (VOCAB below, read live off the code). It must equal the
#      snapshot in tests/fixtures/mod_api.json. A term that LEAVES is a break:
#      bump core/mod/manifest.gd's API, keep reading the old form (the promise
#      says the lower API still loads), and write the migration into
#      docs/modding.md. A term that ARRIVES is fine but must be documented:
#      every documented group's terms have to appear in docs/modding.md, and
#      the snapshot is regenerated with
#          SNAPSHOT_WRITE=1 godot --headless --path . -s tests/test_mod_api.gd
#   2. The ids a pack can name (IDS below: spells, monsters, items, classes...).
#      Removing one strands every pack that referenced it; adding is free, so
#      only removals are checked, and the snapshot only needs regenerating when
#      one is removed on purpose.
#   3. A canary: tests/fixtures/mods/api-canary, a pack written against API 1
#      the way a third party would, touching the overlays, a feature of several
#      kinds, a monster, a world, a story with every condition and effect key.
#      It must keep loading clean, applying, and playing.
#   godot --headless --path . -s tests/test_mod_api.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Callings = preload("res://core/callings.gd")
const RoadEvents = preload("res://core/road_events.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const Manifest = preload("res://core/mod/manifest.gd")
const PassItems = preload("res://core/rules/pass_items.gd")
const Quest = preload("res://core/quest.gd")
const Regions = preload("res://core/regions.gd")
const Registry = preload("res://core/mod/registry.gd")
const Scaler = preload("res://core/scaler.gd")
const Story = preload("res://core/mod/story.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")

const SNAPSHOT := "res://tests/fixtures/mod_api.json"
const CANARY_ROOT := "res://tests/fixtures/mods"
const DOCS := "res://docs/modding.md"

# Groups whose every term must be written in docs/modding.md. VERB_KEYS and the
# board themes are held (removal still breaks) but not required in the docs:
# they are long, and §5.1 points at the code for them.
const DOCUMENTED := ["manifest.kinds", "manifest.access", "manifest.data_files",
	"effects.kinds", "effects.reaction_triggers", "quest.kinds", "story.beat_kinds",
	"story.condition_keys", "story.effect_keys", "story.quest_states",
	"world.kinds", "world.behaviors", "world.factions", "world.bands", "items.slots", "items.keys",
	"road_events.effects", "road_events.needs", "road_events.roles"]

const ID_FILES := ["spells.json", "bestiary.json", "monsters.json", "magic-items.json",
	"classes.json", "subclasses.json", "species.json", "backgrounds.json", "feats.json",
	"conditions.json", "weapons.json", "armor.json",
	"effects/features.json", "effects/spells.json", "effects/potions.json", "effects/items.json"]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

static func vocab() -> Dictionary:
	var bands: Array = Regions.BANDS.map(func(b): return String(b["id"]))
	var fields: Array = []
	for k in Quest.TARGET_FIELD:
		if not fields.has(Quest.TARGET_FIELD[k]):
			fields.append(String(Quest.TARGET_FIELD[k]))
	return {
		"manifest.kinds": Manifest.KINDS, "manifest.access": Manifest.ACCESS,
		"manifest.data_files": Manifest.DATA_FILES,
		"effects.kinds": Effects.KINDS, "effects.reaction_triggers": Effects.REACTION_TRIGGERS,
		"effects.feature_keys": Effects.VERB_KEYS,
		"quest.kinds": Quest.KINDS, "quest.target_fields": fields,
		"story.beat_kinds": Story.BEAT_KINDS, "story.condition_keys": Story.CONDITION_KEYS,
		"story.effect_keys": Story.EFFECT_KEYS, "story.quest_states": Story.QUEST_STATES,
		"world.kinds": WorldPack.KINDS, "world.behaviors": WorldPack.BEHAVIORS,
		"world.roles": WorldPack.ROLES, "world.factions": Scaler.FACTIONS, "world.bands": bands,
		"encounter.themes": Encounter.THEMES, "callings.done_by": Callings.DONE_BY.keys(),
		"items.slots": PassItems.SLOTS, "items.keys": PassItems.KEYS,
		"road_events.effects": RoadEvents.EFFECTS,
		"road_events.needs": RoadEvents.NEEDS.filter(func(n): return n != ""),
		"road_events.roles": RoadEvents.ROLES.filter(func(n): return n != ""),
	}

static func ids() -> Dictionary:
	var out := {}
	for f in ID_FILES:
		var d = Catalog.all(f)
		var list: Array = []
		if d is Array:
			for r in d:
				if r is Dictionary and r.has("id"):
					list.append(String(r["id"]))
		elif d is Dictionary:
			for k in d:
				if not String(k).begins_with("_"):
					list.append(String(k))
		list.sort()
		out[f] = list
	return out

static func _sorted(a: Array) -> Array:
	var b: Array = a.map(func(x): return String(x))
	b.sort()
	return b

func _init() -> void:
	if OS.get_environment("SNAPSHOT_WRITE") != "":
		write_snapshot()
		quit(0)
		return
	var snap = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	check(snap is Dictionary, "the snapshot loads (%s)" % SNAPSHOT)
	if not snap is Dictionary:
		quit(1)
		return
	test_api_level(snap)
	test_vocabulary(snap)
	test_documented()
	test_ids(snap)
	test_canary()
	print("test_mod_api: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func write_snapshot() -> void:
	var v := vocab()
	var vs := {}
	for k in v:
		vs[k] = _sorted(v[k])
	var d := {"_note": "The modding API as tests/test_mod_api.gd holds it. Regenerate with SNAPSHOT_WRITE=1 (see that file's header) — only after documenting what was added, or bumping core/mod/manifest.gd's API for what was removed.",
		"api": Manifest.API, "vocab": vs, "ids": ids()}
	var f := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ", true) + "\n")
	f.close()
	print("wrote %s: API %d, %d vocabularies, %d id files" % [SNAPSHOT, Manifest.API, vs.size(), d["ids"].size()])

func test_api_level(snap: Dictionary) -> void:
	check(int(snap["api"]) == Manifest.API,
		"the snapshot is of API %d and this build speaks %d — a bump means regenerating it, and the migration in docs/modding.md" % [int(snap["api"]), Manifest.API])

func test_vocabulary(snap: Dictionary) -> void:
	var v := vocab()
	var held: Dictionary = snap["vocab"]
	for group in held:
		check(v.has(group), "vocabulary group %s still exists" % group)
	for group in v:
		var now := _sorted(v[group])
		var was: Array = held.get(group, [])
		var gone: Array = was.filter(func(t): return not now.has(t))
		var new: Array = now.filter(func(t): return not was.has(t))
		check(gone.is_empty(), "%s: nothing a pack can write was removed or renamed (gone: %s) — that breaks every pack using it; bump the API and keep reading the old form" % [group, ", ".join(gone)])
		check(new.is_empty(), "%s: new terms %s — document them in docs/modding.md and regenerate the snapshot (SNAPSHOT_WRITE=1)" % [group, ", ".join(new)])

func test_documented() -> void:
	var docs := FileAccess.get_file_as_string(DOCS)
	check(docs.length() > 1000, "docs/modding.md is there")
	var v := vocab()
	for group in DOCUMENTED:
		for t in v[group]:
			check(docs.contains("`%s`" % t) or docs.contains("\"%s\"" % t),
				"docs/modding.md documents %s `%s`" % [group, t])

func test_ids(snap: Dictionary) -> void:
	var now := ids()
	for f in snap["ids"]:
		var have: Array = now.get(f, [])
		var gone: Array = snap["ids"][f].filter(func(id): return not have.has(id))
		check(gone.is_empty(), "%s: no id a pack may name was removed (gone: %s)" % [f, ", ".join(gone.slice(0, 12))])

# --- the canary ------------------------------------------------------------

func test_canary() -> void:
	var root := ProjectSettings.globalize_path(CANARY_ROOT)
	OS.set_environment("SORCMERC_MODS_DIR", root)
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/modapi-%d-%d" % [OS.get_process_id(), randi()])
	var packs := Registry.scan(true)
	var canary = Registry.find("api-canary")
	check(canary != null, "the canary pack is found under %s" % CANARY_ROOT)
	if canary == null:
		return
	check(canary.errors.is_empty(), "the canary loads clean: %s" % ", ".join(canary.errors))
	check(int(canary.manifest.api) == 1, "the canary is written against API 1")
	Registry.set_enabled("api-canary", true)
	check(canary.live(), "the canary goes live")
	Registry.apply_data()
	# data overlays landed where every system reads them
	check(not Catalog.monster("canary-hexwarden").is_empty(), "its bestiary entry is a monster")
	check(not Effects.spell("canary-hexbolt").is_empty(), "its spell is castable")
	for fid in ["canary-ward", "canary-gloom", "canary-mend", "canary-counterstep"]:
		check(not Effects.feature(fid).is_empty(), "its feature %s has a mechanic" % fid)
	check(Effects.validate().is_empty(), "the merged catalog validates: %s" % ", ".join(Effects.validate()))
	# ...and plays: the canary's monster, carrying the canary's features, fights
	# a preset party to a finish.
	var Presets = load("res://core/presets.gd")
	var AI = load("res://core/ai.gd")
	var party: Array = []
	var chars: Array = Presets.party()
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var cb = Encounter.build({"monsters": [{"id": "canary-hexwarden", "count": 2, "mult": 1.0}], "seed": 7}, party)
	var foe = cb.combatants.filter(func(c): return c.team == "foe")[0]
	check(foe.verbs.any(func(v): return String(v["id"]) == "canary-gloom"), "the monster carries the pack's features as buttons")
	var g := 0
	while not cb.is_over() and g < 3000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	check(cb.is_over(), "a fight against it resolves (%s)" % cb.outcome())
	check(Registry.world_of(canary) != null, "its world builds")
	check(canary.manifest.has_story(), "it carries a story, and the story validated with every condition and effect key")
	# put the world back the way the rest of the suite expects it
	Registry.set_enabled("api-canary", false)
	OS.set_environment("SORCMERC_MODS_DIR", "")
	Registry.scan(true)
	Registry.apply_data()

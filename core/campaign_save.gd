# Campaign autosave. One rolling slot, always overwritten — not a save manager.
#
#   CampaignSave.save(campaign)          # after every state-mutating Campaign method
#   var c = CampaignSave.load_latest()   # null when there is no autosave, or it is junk
#
# user://autosave/campaign.json (or $SORCMERC_SAVE_DIR/campaign.json):
#
# {
#   "format": "sorcmerc-campaign",     // literal, checked on load
#   "version": 1,                      // bump only on an incompatible change
#   "stage": 2,                        // index into the run's generated route
#   "node_id": "hollow-market",        // "" when standing between nodes
#   "state": "picking",                // picking | visiting | combat | won | lost
#   "xp": 400,                         // the run's XP total (the bank is per-character)
#   "short_rests_used": 1,             // capped at Campaign.MAX_SHORT_RESTS per run
#   "long_rests_used": 0,              // capped at Campaign.MAX_LONG_RESTS per run
#   "opportunity_taken": false,        // this node's one Perception/Survival attempt, spent or not
#   "scouted": [],                     // next stage's fights, once a Survival check has read them
#   "node_scouted": false,             // THIS node was scouted: its surprise round is guaranteed
#   "lost_anyone": false,              // somebody died on this road (T19's "everyone came home")
#   "seed": 1234,                      // the run RNG's seed, so loot/quest rolls reproduce
#   "log": ["→ The Hollow Market"],
#   "party": {
#     "roster": [ <core/character_save.gd's to_dict, one per member> ],
#     "active": ["vera", "pike"],      // ids, marching order
#     "gold": 120,
#     "stash": [{"item_id": "dagger", "quantity": 1, "identified": true}],
#     "quests": [ <core/quest.gd dicts, stored verbatim> ]
#   }
# }
#
# Unknown extra keys are ignored and missing keys fall back to defaults, the same
# contract character_save.gd documents.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Party = preload("res://core/party.gd")

const SaveDir = preload("res://core/save_dir.gd")
const FORMAT := "sorcmerc-campaign"
const VERSION := 1

# O17: every godot process on the machine shares user://, so two concurrent runs
# (parallel test drivers, or a test run next to manual play) clobber one slot.
# SORCMERC_SAVE_DIR overrides the directory — same env convention as
# SORCMERC_SEED/_FAST. Read once, on first use, so a driver's _init() can set it.
static var _dir := ""

static func dir() -> String:
	if _dir == "":   # $SORCMERC_SAVE_DIR itself, or <root>/autosave — see core/save_dir.gd
		_dir = SaveDir.root() if OS.get_environment("SORCMERC_SAVE_DIR") != "" else SaveDir.path("autosave")
	return _dir

static func path() -> String:
	return dir() + "/campaign.json"

static func to_dict(campaign) -> Dictionary:
	var roster: Array = []
	for ch in campaign.party.roster:
		roster.append(CharacterSave.to_dict(ch))
	return {
		"format": FORMAT, "version": VERSION,
		"stage": campaign.stage,
		"node_id": String(campaign.node.get("id", "")),
		"state": campaign.state,
		"xp": campaign.xp,
		"short_rests_used": campaign.short_rests_used,
		"long_rests_used": campaign.long_rests_used,
		"opportunity_taken": campaign.opportunity_taken,
		"scouted": campaign.scouted.duplicate(true),
		"node_scouted": campaign.node_scouted,
		"lost_anyone": campaign.lost_anyone,
		"seed": int(campaign.rng.seed_value),
		"log": campaign.log.duplicate(),
		"party": {
			"roster": roster,
			"active": Array(campaign.party.active),
			"gold": campaign.party.gold,
			"stash": campaign.party.stash.duplicate(true),
			"quests": campaign.party.quests.duplicate(true),
		},
	}

# null when the dictionary is not a campaign save.
static func from_dict(d: Dictionary):
	if not d is Dictionary or d.get("format") != FORMAT:
		return null
	var pd: Dictionary = d.get("party", {})
	var party := Party.new()
	for cd in pd.get("roster", []):
		var ch = CharacterSave.from_dict(cd)
		if ch != null:
			party.roster.append(ch)
	party.active.assign(pd.get("active", []))
	party.gold = int(pd.get("gold", 0))
	for e in pd.get("stash", []):
		party.stash_add(String(e["item_id"]), int(e.get("quantity", 1)),
			bool(e.get("identified", true)))
	party.quests = _ints(pd.get("quests", []))

	var campaign := Campaign.new(party, int(d.get("seed", 1)))
	campaign.stage = int(d.get("stage", 0))
	campaign.state = String(d.get("state", "picking"))
	campaign.xp = int(d.get("xp", 0))
	campaign.short_rests_used = int(d.get("short_rests_used", 0))
	campaign.long_rests_used = int(d.get("long_rests_used", 0))
	campaign.opportunity_taken = bool(d.get("opportunity_taken", false))
	campaign.scouted = d.get("scouted", [])
	campaign.node_scouted = bool(d.get("node_scouted", false))
	campaign.lost_anyone = bool(d.get("lost_anyone", false))
	campaign.log.assign(d.get("log", []))
	campaign.node = _node(campaign, String(d.get("node_id", "")))
	return campaign

# JSON gives every number back as a float; quest counters are compared as ints.
static func _ints(quests: Array) -> Array:
	var out: Array = []
	for q in quests:
		var c: Dictionary = q.duplicate(true)
		for k in ["required", "progress"]:
			if c.has(k):
				c[k] = int(c[k])
		if c.get("reward") is Dictionary and c["reward"].has("gold"):
			c["reward"]["gold"] = int(c["reward"]["gold"])
		out.append(c)
	return out

# T12: the route is regenerated from the saved seed, so the stage's nodes are the
# same ones the run offered — look the id up there, not in a fixed table.
static func _node(campaign, node_id: String) -> Dictionary:
	if node_id == "" or campaign.stage < 0 or campaign.stage >= campaign.route.size():
		return {}
	for n in campaign.route[campaign.stage]:
		if n["id"] == node_id:
			return n
	return {}

static func save(campaign) -> void:
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path())
		return
	f.store_string(JSON.stringify(to_dict(campaign), "  "))
	f.close()

# Never crashes on a missing or corrupt file — a bad autosave is just "no autosave".
static func load_latest():
	if not FileAccess.file_exists(path()):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return from_dict(d) if d is Dictionary else null

static func has_save() -> bool:
	return FileAccess.file_exists(path())

static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())

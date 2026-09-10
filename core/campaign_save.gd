# Campaign autosave. One rolling slot, always overwritten — not a save manager.
#
#   CampaignSave.save(campaign)          # after every state-mutating Campaign method
#   var c = CampaignSave.load_latest()   # null when there is no autosave, or it is junk
#
# user://autosave/campaign.json:
#
# {
#   "format": "sorcmerc-campaign",     // literal, checked on load
#   "version": 1,                      // bump only on an incompatible change
#   "stage": 2,                        // index into the run's generated route
#   "node_id": "hollow-market",        // "" when standing between nodes
#   "state": "picking",                // picking | visiting | combat | won | lost
#   "xp": 400,                         // the run's XP total (the bank is per-character)
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

const DIR := "user://autosave"
const PATH := DIR + "/campaign.json"
const FORMAT := "sorcmerc-campaign"
const VERSION := 1

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
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % PATH)
		return
	f.store_string(JSON.stringify(to_dict(campaign), "  "))
	f.close()

# Never crashes on a missing or corrupt file — a bad autosave is just "no autosave".
static func load_latest():
	if not FileAccess.file_exists(PATH):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return from_dict(d) if d is Dictionary else null

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

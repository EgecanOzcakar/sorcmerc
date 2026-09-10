# T9 — quests. Plain dictionaries (the shape locked in the plan doc), a curated
# list, and the four verbs the campaign needs: offer / accept / record / turn in.
# The party owns the log (`party.quests`); nothing here holds state.
#
# Quest shape:
#   id, giver_node_id, title, kind: "kill_count" | "collect_item",
#   target_monster_id, target_item_id + drop_chance (collect_item only),
#   required, progress, state: "offered" | "active" | "complete" | "turned_in",
#   reward: {gold, item_id (optional)}
extends RefCounted

const BIAS_WEIGHT := 2.0   # what an unfulfilled quest is worth to Scaler.roster_for

# Hand-authored, four of them. Monster ids are data/monsters.json's — the bestiary
# is four archetypes deep, so a quest names a foe, not a species.
const CURATED := [
	{
		"id": "goblin-ears", "giver_node_id": "wayside-camp",
		"title": "Bring me 5 goblin ears",
		"kind": "collect_item", "target_monster_id": "snik",
		"target_item_id": "goblin-ear", "drop_chance": 0.5,
		"required": 5, "reward": {"gold": 120},
	},
	{
		"id": "road-clearing", "giver_node_id": "wayside-camp",
		"title": "Clear 3 of Vess's pack from the road",
		"kind": "kill_count", "target_monster_id": "vess",
		"required": 3, "reward": {"gold": 75, "item_id": "shortsword"},
	},
	{
		"id": "kritch-bounty", "giver_node_id": "hollow-market",
		"title": "Bounty: 4 of Kritch's archers",
		"kind": "kill_count", "target_monster_id": "kritch",
		"required": 4, "reward": {"gold": 90},
	},
	{
		"id": "ogre-tusks", "giver_node_id": "hollow-market",
		"title": "Two ogre tusks for the shrine",
		"kind": "collect_item", "target_monster_id": "grull",
		"target_item_id": "ogre-tusk", "drop_chance": 0.6,
		"required": 2, "reward": {"gold": 200, "item_id": "chain-shirt"},
	},
]

static func fresh(id: String) -> Dictionary:
	for q in CURATED:
		if q["id"] == id:
			var out: Dictionary = q.duplicate(true)
			out["progress"] = 0
			out["state"] = "offered"
			return out
	return {}

static func get_quest(party, id: String) -> Dictionary:
	for q in party.quests:
		if q["id"] == id:
			return q
	return {}

# The one quest a merchant node offers: its own, not already in the log.
static func offer_for(party, node_id: String) -> Dictionary:
	for q in CURATED:
		if q["giver_node_id"] == node_id and get_quest(party, q["id"]).is_empty():
			return fresh(q["id"])
	return {}

static func accept(party, quest: Dictionary) -> bool:
	if quest.is_empty() or not get_quest(party, quest["id"]).is_empty():
		return false
	quest["state"] = "active"
	party.quests.append(quest)
	return true

static func active(party) -> Array:
	return party.quests.filter(func(q): return q["state"] in ["active", "complete"])

# What Scaler.roster_for wants: {monster_id: weight} for every unfulfilled quest.
static func bias(party) -> Dictionary:
	var out := {}
	for q in party.quests:
		if q["state"] == "active" and int(q["progress"]) < int(q["required"]):
			out[q["target_monster_id"]] = BIAS_WEIGHT
	return out

# After a fight: `kills` is Encounter.resolve_outcome()'s list of monster ids.
# kill_count counts bodies; collect_item rolls the drop per body and stashes it,
# so "killed 5, got 3 ears" is the intended texture. Returns log lines.
static func record_kills(party, kills: Array, rng) -> Array:
	var lines: Array = []
	for q in party.quests:
		if q["state"] != "active":
			continue
		var n := 0
		for k in kills:
			if k != q["target_monster_id"]:
				continue
			if q["kind"] == "kill_count":
				n += 1
			elif rng.roll_die(100) <= int(round(float(q.get("drop_chance", 0.5)) * 100.0)):
				n += 1
				party.stash_add(q["target_item_id"])
		if n == 0:
			continue
		q["progress"] = mini(int(q["required"]), int(q["progress"]) + n)
		lines.append("%s — %d/%d" % [q["title"], int(q["progress"]), int(q["required"])])
		if int(q["progress"]) >= int(q["required"]):
			q["state"] = "complete"
			lines.append("%s: ready to turn in." % q["title"])
	return lines

static func can_turn_in(quest: Dictionary) -> bool:
	return not quest.is_empty() and quest["state"] in ["active", "complete"] \
		and int(quest["progress"]) >= int(quest["required"])

# Any merchant takes a finished quest, not just the giver (kept deliberately simple).
static func turn_in(party, quest: Dictionary) -> bool:
	if not can_turn_in(quest):
		return false
	var reward: Dictionary = quest.get("reward", {})
	party.add_gold(int(reward.get("gold", 0)))
	if reward.has("item_id"):
		party.stash_add(String(reward["item_id"]))
	if quest["kind"] == "collect_item":
		party.stash_remove(String(quest["target_item_id"]), int(quest["required"]))
	quest["state"] = "turned_in"
	return true

# One line for the quest log panel.
static func describe(quest: Dictionary) -> String:
	var tail := "  ✔ ready to turn in" if quest["state"] == "complete" else ""
	return "%s   %d/%d%s" % [quest["title"], int(quest["progress"]), int(quest["required"]), tail]

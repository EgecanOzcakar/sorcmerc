# T9 — quests. Plain dictionaries (the shape locked in the plan doc), a curated
# list, and the four verbs the campaign needs: offer / accept / record / turn in.
# The party owns the log (`party.quests`); nothing here holds state.
#
# Quest shape:
#   id, giver_node_id, title, kind: "kill_count" | "collect_item" | "hunt_party" |
#     "raid_settlement" | "clear_lair",
#   target_monster_id, target_item_id + drop_chance (collect_item only),
#   target_party_id (hunt_party) / target_settlement_id (raid_settlement) /
#     target_lair_id (clear_lair) — T91, live open-world objects rather than the
#     campaign's own hand-authored monster ids, so these three complete via
#     record_party_defeated/record_settlement_raided/record_lair_cleared instead
#     of record_kills. required is always 1 for them: the target either still
#     exists or it doesn't.
#   required, progress, state: "offered" | "active" | "complete" | "turned_in",
#   reward: {gold, item_id (optional)}
extends RefCounted

const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldAI = preload("res://core/world_ai.gd")

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
	{
		"id": "board-grievance", "giver_node_id": "spice-road-inn",
		"title": "Settle the board: 3 of Snik's lot",
		"kind": "kill_count", "target_monster_id": "snik",
		"required": 3, "reward": {"gold": 85, "item_id": "handaxe"},
	},
	{
		"id": "quay-tusks", "giver_node_id": "salt-quay",
		"title": "The quay wants an ogre's tusk",
		"kind": "collect_item", "target_monster_id": "grull",
		"target_item_id": "ogre-tusk", "drop_chance": 0.6,
		"required": 1, "reward": {"gold": 140},
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
# O7: `opinion` is the giver's faction's opinion of the player (0 = neutral, which
# is every T9 caller and so T9's behavior unchanged). Below QUEST_MIN they have no
# work for you; above QUEST_GENEROUS they will pass you a neighbour's job once
# their own is taken.
static func offer_for(party, node_id: String, opinion := 0.0) -> Dictionary:
	if opinion <= FactionOpinion.QUEST_MIN:
		return {}
	for q in CURATED:
		if q["giver_node_id"] == node_id and get_quest(party, q["id"]).is_empty():
			return fresh(q["id"])
	if opinion >= FactionOpinion.QUEST_GENEROUS:
		for q in CURATED:
			if get_quest(party, q["id"]).is_empty():
				return fresh(q["id"])
	return {}

# T91: eligible live open-world targets for a giver settlement's quests — a
# hostile roaming party, another hostile settlement, or an unlooted lair.
# Shared by world_quest_for (one random pick) and the T9x quest board
# (multiple at once) so there's one place that decides what counts as a
# target, not two.
static func _world_quest_pool(world, giver_settlement) -> Array:
	var pool: Array = []
	for p in world.parties:
		if not p.is_player and WorldAI.is_monster(p.faction):
			pool.append({"kind": "hunt_party", "id": p.id, "name": p.id.capitalize(), "faction": p.faction})
	for s in world.settlements:
		if s.id != giver_settlement.id and WorldAI.is_monster(s.faction):
			pool.append({"kind": "raid_settlement", "id": s.id, "name": s.sname, "faction": s.faction})
	for l in world.lairs:
		if not l.looted:
			pool.append({"kind": "clear_lair", "id": l.id, "name": l.sname, "faction": l.faction})
	return pool

# T9x quest chains: escalating, faction-specific. `tier` is how many
# world-target quests against this faction the party has already turned in
# (see faction_chain_tier below, derived from the log itself — no separate
# save field) — 0 is the first job, each one after reads tougher and pays
# more, same target kinds, just relabeled and better rewarded.
const CHAIN_LABELS := {
	"hunt_party": ["Hunt down the %s band", "Break the %s warband", "End the %s threat"],
	"raid_settlement": ["Raid %s", "Sack %s", "Raze %s for good"],
	"clear_lair": ["Clear out %s", "Purge %s", "Finish %s, once and for all"],
}

static func faction_chain_tier(party, faction: String) -> int:
	if party == null:
		return 0
	var n := 0
	for q in party.quests:
		if q["state"] == "turned_in" and String(q.get("chain_faction", "")) == faction:
			n += 1
	return n

static func _world_quest_from_pick(pick: Dictionary, giver_settlement, party, rng) -> Dictionary:
	var kind := String(pick["kind"])
	var tier: int = mini(2, faction_chain_tier(party, String(pick["faction"])))
	var out := {
		"id": "world:%s:%s:%d" % [kind, pick["id"], tier],
		"giver_node_id": giver_settlement.id, "state": "offered", "progress": 0, "required": 1,
		"kind": kind, "chain_faction": pick["faction"], "chain_tier": tier,
		"reward": {"gold": 80 + tier * 60 + rng.roll_die(120)},
		"title": String(CHAIN_LABELS[kind][tier]) % pick["name"],
	}
	match kind:
		"hunt_party": out["target_party_id"] = pick["id"]
		"raid_settlement": out["target_settlement_id"] = pick["id"]
		"clear_lair": out["target_lair_id"] = pick["id"]
	return out

# A quest targeting a live open-world object instead of a curated monster id —
# offered wherever a settlement can give a quest (core/settlement_visit.gd),
# alongside CURATED. Picks one eligible target at random and returns {} if
# nothing qualifies.
static func world_quest_for(world, giver_settlement, rng) -> Dictionary:
	var pool := _world_quest_pool(world, giver_settlement)
	if pool.is_empty():
		return {}
	return _world_quest_from_pick(pool[rng.roll_die(pool.size()) - 1], giver_settlement, null, rng)

# T9x quest board: every eligible world target at once (not just one random
# pick), for a settlement that shows multiple concurrent job offers instead
# of a single ad-hoc one. `party` is needed here (not in world_quest_for)
# to read each target's chain tier.
static func world_quest_offers(world, giver_settlement, party, rng) -> Array:
	var out: Array = []
	for pick in _world_quest_pool(world, giver_settlement):
		var q := _world_quest_from_pick(pick, giver_settlement, party, rng)
		if get_quest(party, q["id"]).is_empty():
			out.append(q)
	return out

static func accept(party, quest: Dictionary) -> bool:
	if quest.is_empty() or not get_quest(party, quest["id"]).is_empty():
		return false
	quest["state"] = "active"
	party.quests.append(quest)
	return true

static func active(party) -> Array:
	return party.quests.filter(func(q): return q["state"] in ["active", "complete"])

# What Scaler.roster_for wants: {monster_id: weight} for every unfulfilled quest.
# Only the two monster-target kinds have anything to bias toward: T91's
# world-target kinds (and M4's story quests, which are the same shape) name a
# party, a settlement or a lair, and asking those for a monster id they have
# never had used to throw rather than return nothing.
static func bias(party) -> Dictionary:
	var out := {}
	for q in party.quests:
		if q["state"] == "active" and int(q["progress"]) < int(q["required"]) \
				and q.has("target_monster_id"):
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

# T91: the three world-target kinds complete in one shot (required is always
# 1) the moment their target stops existing / is looted — no per-kill tally.
static func _complete_world_target(party, kind: String, field: String, id: String) -> void:
	for q in party.quests:
		if q["state"] == "active" and q["kind"] == kind and String(q.get(field, "")) == id:
			q["progress"] = 1
			q["state"] = "complete"

static func record_party_defeated(party, party_id: String) -> void:
	_complete_world_target(party, "hunt_party", "target_party_id", party_id)

static func record_settlement_raided(party, settlement_id: String) -> void:
	_complete_world_target(party, "raid_settlement", "target_settlement_id", settlement_id)

static func record_lair_cleared(party, lair_id: String) -> void:
	_complete_world_target(party, "clear_lair", "target_lair_id", lair_id)

static func can_turn_in(quest: Dictionary) -> bool:
	return not quest.is_empty() and quest["state"] in ["active", "complete"] \
		and int(quest["progress"]) >= int(quest["required"])

# Any merchant takes a finished quest, not just the giver (kept deliberately simple).
# O7: pass the taker's faction and finishing the job raises their opinion of you;
# the linear campaign has no factions and passes nothing.
static func turn_in(party, quest: Dictionary, faction := "") -> bool:
	if not can_turn_in(quest):
		return false
	if faction != "":
		FactionOpinion.raise(faction, FactionOpinion.QUEST_DONE)
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

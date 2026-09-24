# T9 — quests. Plain dictionaries (the shape locked in the plan doc), a curated
# list, and the four verbs the campaign needs: offer / accept / record / turn in.
# The party owns the log (`party.quests`); nothing here holds state.
#
# Quest shape:
#   id, giver_node_id, title, kind (one of KINDS below),
#   counter — D7: which counter posts it, so a job appears where its business
#     is rather than on one board that has everything (core/quest_posting.gd
#     decides; nothing in this file reads it back).
#   target_monster_id, target_item_id + drop_chance (collect_item only),
#   target_party_id (hunt_party) / target_settlement_id (raid_settlement) /
#     target_lair_id (clear_lair) — T91, live open-world objects rather than the
#     campaign's own hand-authored monster ids, so these three complete via
#     record_party_defeated/record_settlement_raided/record_lair_cleared instead
#     of record_kills. required is always 1 for them: the target either still
#     exists or it doesn't.
#   target_item_id (supply_item) / target_settlement_id (deliver_goods) /
#     target_region_id (scout_region) — D7's three, completing via
#     record_stash/record_settlement_visited/record_region_reached.
#   required, progress, state: "offered" | "active" | "complete" | "turned_in",
#   reward: {gold, item_id (optional)}   — turn-in also pays gold * XP_PER_GOLD in XP
#   issuer, against — contracts (core/contracts.gd): the people who posted it,
#     who are credited at turn-in wherever it is handed in, and the faction it
#     is aimed at ("" for nobody). Absent on a job posted before contracts,
#     which then credits the hand-in town, as every job did.
extends RefCounted

const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Ach = preload("res://core/achievements.gd")
const Ladder = preload("res://core/ladder.gd")
const Contracts = preload("res://core/contracts.gd")
const EnemyNames = preload("res://core/enemy_names.gd")

# A fight pays XP at about 6.7x its gold (core/encounter.gd's XP_PER_POWER /
# GOLD_PER_POWER); a quest pays less per coin because it also hands over gear
# and reputation. 2x puts a 120-gold job at ~4 early open-country fights.
const XP_PER_GOLD := 2

const BIAS_WEIGHT := 2.0   # what an unfulfilled quest is worth to Scaler.roster_for

# Every kind the log can actually track, and the field each one names its target
# in. Kept here as data rather than as prose in three files: core/mod/story.gd
# validates an authored quest against these (its own copy drifted the moment a
# kind was added) and core/quest_posting.gd reads KINDS to know what it may post.
const KINDS := ["kill_count", "collect_item", "hunt_party", "raid_settlement",
	"clear_lair", "supply_item", "deliver_goods", "scout_region", "rescue"]
const TARGET_FIELD := {
	"kill_count": "target_monster_id", "collect_item": "target_monster_id",
	"hunt_party": "target_party_id", "raid_settlement": "target_settlement_id",
	"clear_lair": "target_lair_id", "supply_item": "target_item_id",
	"deliver_goods": "target_settlement_id", "scout_region": "target_region_id",
	"rescue": "target_lair_id",
}
# The subset of those fields that names something standing on the map, so a
# caller holding a world can check the id against it. An item id and a region id
# are not map objects and must not be looked up as if they were.
const WORLD_TARGET_FIELDS := ["target_party_id", "target_settlement_id", "target_lair_id"]

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
# work for you; above QUEST_GENEROUS — or once the ladder calls you Known to their
# people — they will pass you a neighbour's job once their own is taken.
static func offer_for(party, node_id: String, opinion := 0.0, rung := 0) -> Dictionary:
	if opinion <= FactionOpinion.QUEST_MIN:
		return {}
	for q in CURATED:
		if q["giver_node_id"] == node_id and get_quest(party, q["id"]).is_empty():
			return fresh(q["id"])
	if opinion >= FactionOpinion.QUEST_GENEROUS or rung >= Ladder.KNOWN:
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
			pool.append({"kind": "hunt_party", "id": p.id, "name": EnemyNames.band_name(p, world), "faction": p.faction})
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
	"hunt_party": ["Hunt down %s", "Break %s", "See %s off the roads"],
	"raid_settlement": ["Raid %s", "Sack %s", "Break the gate at %s"],
	"clear_lair": ["Clear out %s", "Clear %s out to the last room", "Make sure %s stays empty"],
}

# A lair whose raid stands on the giver's town (core/raids.gd) pays this much
# more for its own job: the town wants it answered, and says so in gold.
const RAID_PREMIUM := 1.5

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
	if "raided_by" in giver_settlement and String(giver_settlement.raided_by) == String(pick["id"]):
		out["reward"]["gold"] = int(int(out["reward"]["gold"]) * RAID_PREMIUM)
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
		var want := String(q.get("target_monster_id", ""))
		if want == "":
			continue      # the kinds that name a place, a band or an item: no bodies to count
		for k in kills:
			if k != want:
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

# rescue — somebody chained in a lair's pens (core/site.gd's pens room, an
# objective in core/objectives.gd). Completes when the rescue objective is done
# in that lair; scenes/world/world.gd calls this off the fight's result.
static func record_rescued(party, lair_id: String) -> void:
	_complete_world_target(party, "rescue", "target_lair_id", lair_id)

# The carter is dead (the escort objective failed), or the party was beaten with
# the crate on the road: every live delivery is lost. Removed from the log rather
# than marked, so the board can post the run again. Returns the titles, for the
# spoils page.
static func fail_deliveries(party) -> Array:
	var lost: Array = []
	for q in party.quests.duplicate():
		if q["kind"] == "deliver_goods" and q["state"] == "active":
			lost.append(String(q["title"]))
			party.quests.erase(q)
	return lost

# --- D7: the three kinds that finish on something other than a body ---------

# deliver_goods — a courier run between two civilized settlements. Walking in
# the destination's gate IS the job, so scenes/world/world.gd calls this from
# _open_visit(). Nothing is carried in the pack: the parcel would need a catalog
# entry, a price and a weight to exist as an item, and all three would be lies.
static func record_settlement_visited(party, settlement_id: String) -> void:
	Ach.collect("settlements", settlement_id)
	_complete_world_target(party, "deliver_goods", "target_settlement_id", settlement_id)

# scout_region — ride out into a band (core/regions.gd's rings) and come back
# able to say what is there. Completes on crossing in, turns in back at the
# giver; scenes/world/world.gd calls this from _check_region().
static func record_region_reached(party, region_id: String) -> void:
	Ach.collect("regions", region_id)
	_complete_world_target(party, "scout_region", "target_region_id", region_id)

# supply_item — a counter wants goods in hand, and does not care how you came by
# them: bought at the next town, looted, or already in the pack when they asked.
# That makes progress a READING of the pack rather than an event, so this
# re-derives it both ways instead of incrementing: buy two and it climbs, sell
# them again and it falls back and the job un-completes, which is the honest
# answer to "do you have them on you". Call it anywhere the number is about to
# be shown (world.gd re-reads it on every redraw of a town screen).
static func record_stash(party) -> void:
	for q in party.quests:
		if not q["kind"] in ["supply_item", "collect_item"] or not q["state"] in ["active", "complete"]:
			continue
		var have: int = party.stash_count(String(q["target_item_id"]))
		# collect_item's tally is what the bodies dropped, so the pack can only
		# pull it DOWN: ears sold at a stall, or lost to a wiped delve's
		# wipe_penalty, are ears no longer in hand to turn in.
		var got: int = have if q["kind"] == "supply_item" else mini(int(q["progress"]), have)
		q["progress"] = mini(int(q["required"]), got)
		q["state"] = "complete" if int(q["progress"]) >= int(q["required"]) else "active"

# #153: where each open job points on the map — [{pos, kind, title, done}].
# A job still being done points at what it names (the band, the lair, the
# town); a job done and not yet paid points back at whoever posted it. The
# fog rules the map draws by hold here too: a lair is only pointed at once it
# is found and a band once it is seen — a job is a name, not a signpost. A
# kind that names nothing standing on the map (a monster, an item, a region)
# has no mark until it is done.
static func map_marks(world, party) -> Array:
	var out: Array = []
	for q in party.quests:
		var state := String(q.get("state", ""))
		if state != "active" and state != "complete":
			continue
		var pos = null
		if state == "complete":
			pos = _position_of(world.settlements, String(q.get("giver_node_id", "")))
		else:
			match String(q.get("kind", "")):
				"hunt_party":
					for p in world.parties:
						if p.id == String(q.get("target_party_id", "")) and world.band_seen(p.position):
							pos = p.position
				"raid_settlement", "deliver_goods":
					pos = _position_of(world.settlements, String(q.get("target_settlement_id", "")))
				"clear_lair", "rescue":
					for l in world.lairs:
						if l.id == String(q.get("target_lair_id", "")) and l.discovered:
							pos = l.position
		if pos != null:
			out.append({"pos": pos, "kind": String(q.get("kind", "")), "title": String(q.get("title", "")),
				"done": state == "complete"})
	return out

static func _position_of(things: Array, id: String):
	for t in things:
		if t.id == id:
			return t.position
	return null

# With a party, the two kinds paid for goods also need the goods in the pack.
# turn_in() used to pay in full and then fail to take ears that had been sold.
static func can_turn_in(quest: Dictionary, party = null) -> bool:
	if quest.is_empty() or not quest["state"] in ["active", "complete"] \
			or int(quest["progress"]) < int(quest["required"]):
		return false
	if party != null and quest["kind"] in ["collect_item", "supply_item"]:
		return party.stash_count(String(quest["target_item_id"])) >= int(quest["required"])
	return true

# Any merchant takes a finished quest, not just the giver (kept deliberately simple).
# O7: pass the taker's faction and finishing the job raises their opinion of you;
# the linear campaign has no factions and passes nothing.
# Contracts (core/contracts.gd): the regard and the deed go to the people who
# POSTED the job (its `issuer`), wherever it is handed in. `faction` is only the
# fallback, for a job posted before jobs carried an issuer.
static func turn_in(party, quest: Dictionary, faction := "") -> bool:
	if not can_turn_in(quest, party):
		return false
	if faction != "" or quest.has("issuer"):
		Contracts.credit(quest, faction)
	var reward: Dictionary = quest.get("reward", {})
	party.add_gold(int(reward.get("gold", 0)))
	# A finished job teaches something too: XP pegged to the purse, split the
	# way a fight's is (load(), not preload — campaign.gd preloads this file).
	load("res://core/campaign.gd").new(party)._split_xp(int(reward.get("gold", 0)) * XP_PER_GOLD)
	if reward.has("item_id"):
		party.stash_add(String(reward["item_id"]))
	# The two kinds that are paid for goods hand the goods over.
	if quest["kind"] in ["collect_item", "supply_item"]:
		party.stash_remove(String(quest["target_item_id"]), int(quest["required"]))
	quest["state"] = "turned_in"
	Ach.bump("quests")
	# A chain is the run of jobs against ONE target faction (chain_faction), so
	# that is what is counted. It used to count the hand-in town's faction, a
	# civilized people no chain is ever against, so the achievement could not
	# be earned in the open world.
	var chain := String(quest.get("chain_faction", ""))
	if chain != "" and faction_chain_tier(party, chain) >= 2:
		Ach.unlock("quest_chain")
	return true

# One line for the quest log panel.
static func describe(quest: Dictionary) -> String:
	var tail := "  ✔ ready to turn in" if quest["state"] == "complete" else ""
	return "%s   %d/%d%s" % [quest["title"], int(quest["progress"]), int(quest["required"]), tail]

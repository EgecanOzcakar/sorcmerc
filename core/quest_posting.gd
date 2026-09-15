# D7 — who posts a job, and where.
#
# Every settlement on the map used to post the same list. One notice board per
# town, and on it: every hostile band on the map, every hostile settlement,
# every unlooted lair, plus whichever curated job the giver-node hash happened
# to land on. Two things were wrong with that. A camp of six charcoal-burners
# was commissioning the sack of a city four days' ride away, and it was the
# same board in every town, so there was never a reason to read the second one.
#
# So a job now has a COUNTER — the person whose business it is — and a REACH:
#
#   Posting.offers(settlement, services, party, world)   # every job, flat
#   Posting.by_counter(offers)                           # {counter: [job, ...]}
#
# The counter is most of the placement rule, because T25 already decides which
# counters a settlement has (core/settlement_visit.gd's KIND_SERVICES: a city
# has all six specialists, a town three, a camp none but the generalist). The
# innkeeper takes bounty and war work, so a camp with no innkeeper has neither
# on offer. Only a city has a librarian, so only a city sends you after a relic.
# The generalist runs the carting everywhere, and out in the small places posts
# the work there is nobody else to post. Nothing here hardcodes "camps are
# poor": it falls out of who is standing behind the counters.
#
# Reach is the other half: a settlement only posts work about things near enough
# to be its problem. Sized against the hand-placed maps, where settlements sit
# 400-900 units apart — the same reasoning (and roughly the same numbers) as
# core/rumors.gd's RANGE, which already decided how far a town's knowledge
# carries.
#
# What this does NOT own: what a quest is or how it progresses (core/quest.gd),
# the market, the inn or the turn-in (core/settlement_visit.gd, which is every
# caller's way in here), or any drawing — scenes/world/world.gd puts each
# counter's jobs on that counter's own page.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Quest = preload("res://core/quest.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const WorldAI = preload("res://core/world_ai.gd")

# One row per kind core/quest.gd can track. Fields:
#   counters — who posts it, best first. The first counter the settlement
#     actually has takes the job; a settlement with none of them does not post
#     the kind at all, which is the whole mechanism. ("generalist" is everywhere,
#     so listing it last reads as "and the small places too".)
#   each     — every listed counter present posts its own job, rather than the
#     first one taking it. Only supply_item wants this: the smith's order and
#     the alchemist's order are two different errands.
#   kinds    — settlement sizes that post it at all; [] means any size that has
#     the counter.
#   reach    — how far the giver's interest carries, in map units. 0.0 means the
#     job names nothing standing on the map, so there is no distance to check.
const PLACEMENT := {
	# The curated jobs (core/quest.gd's CURATED) and the two bounty kinds are
	# the innkeeper's: the common room is where a town's grievances get written
	# down, and a camp does not have one.
	"kill_count": {"counters": ["innkeeper"], "kinds": [], "reach": 0.0},
	"collect_item": {"counters": ["innkeeper"], "kinds": [], "reach": 0.0},
	"hunt_party": {"counters": ["innkeeper"], "kinds": [], "reach": 700.0},
	# Ordering a settlement sacked is a war, not an errand. Only a city posts it.
	"raid_settlement": {"counters": ["innkeeper"], "kinds": ["city"], "reach": 900.0},
	# A lair down the valley is everybody's problem, including a camp's — so
	# where there is no innkeeper the generalist posts it instead.
	"clear_lair": {"counters": ["innkeeper", "generalist"], "kinds": [], "reach": 800.0},
	# One per specialist counter: each of them runs out of its own stock.
	"supply_item": {"counters": ["weaponsmith", "armorsmith", "alchemist", "librarian", "healer"],
		"each": true, "kinds": [], "reach": 0.0},
	"deliver_goods": {"counters": ["generalist"], "kinds": [], "reach": 1100.0},
	# A city does not need to be told what the frontier looks like. The places
	# with their backs to it do.
	"scout_region": {"counters": ["generalist"], "kinds": ["town", "camp"], "reach": 0.0},
}

# --- supply_item: a counter is out of something --------------------------

const SUPPLY_MIN_PRICE := 8      # below this it is not worth anyone's errand
const SUPPLY_MAX_PRICE := 420    # above it they would send their own people. Sized to
                                 # reach the uncommon potions and scrolls (Campaign prices
                                 # rarity, and uncommon lands on 400) without ever asking
                                 # for a rare one, which would be a treasure hunt, not an errand
const SUPPLY_BUDGET := 140       # roughly what they want, in gold, spread over `required`
const SUPPLY_MAX_COUNT := 5
const SUPPLY_MARKUP := 1.7       # they pay over list — that is what the fetching is worth
const SUPPLY_BONUS := 25

# The healer keeps no shelf of their own (Campaign.service_stock_ids returns
# nothing for them), and the thing a healer actually runs out of is potions, so
# they order off the alchemist's list.
const SUPPLY_CATALOG := {"healer": "alchemist"}

# One "%s" each, filled by want() below — so an order for one reads as an order
# for one ("a Chain Mail") rather than as a spreadsheet row ("1 Chain Mail").
const SUPPLY_TITLES := {
	"weaponsmith": "Smith's order: %s",
	"armorsmith": "Armoury commission: %s",
	"alchemist": "Restock the alchemist: %s",
	"librarian": "The library will buy %s",
	"healer": "The healer wants %s",
}

# --- deliver_goods / scout_region ----------------------------------------

const DELIVER_BASE := 40
const DELIVER_PER_UNIT := 10.0   # map units of road per extra gold piece
const SCOUT_BASE := 60
const SCOUT_PER_BAND := 55       # each ring out is worth this much more

# --- what a settlement is posting ----------------------------------------

# O9: Quest.offer_for() keys on a T25 giver node id and a settlement is not one,
# so each settlement stands in for a curated giver, picked off its own id and
# stable for the life of the map. (Lived in core/settlement_visit.gd until D7;
# moved here so everything that decides WHICH job is in one file. Visit still
# exposes it under its old name.)
static func giver_node_id(s) -> String:
	var givers: Array = []
	for q in Quest.CURATED:
		if not givers.has(q["giver_node_id"]):
			givers.append(q["giver_node_id"])
	return String(givers[absi(hash(s.id)) % givers.size()])

# Every job this settlement can post right now, in KINDS order, each stamped
# with the counter that is posting it. `services` is what T25 says stands behind
# the counters here (core/settlement_visit.gd's services()) — passed in rather
# than derived, so this file never has to reach back into the visit module.
static func offers(s, services: Array, party, world = null) -> Array:
	var opinion: float = FactionOpinion.get_opinion(s.faction)
	# O7's floor, applied to the whole settlement rather than just the curated
	# path: if they dislike you this much, nobody here has work for you — the
	# board included, which it was not before.
	if opinion <= FactionOpinion.QUEST_MIN:
		return []
	# The three world-target kinds come out of one pool (Quest's own), rolled
	# once and then filtered per kind, so a settlement's board is the same board
	# however many kinds are read off it.
	var world_jobs: Array = []
	if world != null:
		world_jobs = Quest.world_quest_offers(world, s, party, RNG.new(maxi(1, absi(hash(s.id)))))
	var out: Array = []
	var seen := {}
	for kind in Quest.KINDS:
		for counter in counters_for(s, services, String(kind)):
			for q in _build(String(kind), counter, s, party, world, world_jobs, opinion):
				var id := String(q["id"])
				if seen.has(id) or not Quest.get_quest(party, id).is_empty():
					continue
				seen[id] = true
				q["counter"] = counter
				out.append(q)
	return out

# Which counters here would post this kind — [] when none of them is standing in
# this settlement, which is how a kind stops being available everywhere.
static func counters_for(s, services: Array, kind: String) -> Array:
	var rule: Dictionary = PLACEMENT.get(kind, {})
	if rule.is_empty():
		return []
	var sizes: Array = rule.get("kinds", [])
	if not sizes.is_empty() and not sizes.has(s.kind):
		return []
	var out: Array = []
	for c in rule["counters"]:
		if services.has(c):
			out.append(c)
			if not bool(rule.get("each", false)):
				break
	return out

# {counter: [job, ...]} for an already-built offer list, insertion-ordered, so a
# page can ask "what is posted at this counter" without re-rolling anything.
static func by_counter(job_offers: Array) -> Dictionary:
	var out := {}
	for q in job_offers:
		var c := String(q.get("counter", "generalist"))
		if not out.has(c):
			out[c] = []
		out[c].append(q)
	return out

static func _build(kind: String, counter: String, s, party, world, world_jobs: Array,
		opinion: float) -> Array:
	match kind:
		"kill_count", "collect_item":
			# Both curated kinds resolve to the same single offer; offers()
			# de-duplicates by id, so reading it twice costs nothing.
			var q: Dictionary = Quest.offer_for(party, giver_node_id(s), opinion)
			return [q] if not q.is_empty() else []
		"hunt_party", "raid_settlement", "clear_lair":
			return _world_offers(kind, s, world, world_jobs)
		"supply_item":
			var q: Dictionary = supply_offer(s, counter)
			return [q] if not q.is_empty() else []
		"deliver_goods":
			var q: Dictionary = deliver_offer(s, world)
			return [q] if not q.is_empty() else []
		"scout_region":
			var q: Dictionary = scout_offer(s, world)
			return [q] if not q.is_empty() else []
	return []

# T91's world-target jobs, narrowed to this kind and to what is close enough to
# be this settlement's problem.
static func _world_offers(kind: String, s, world, world_jobs: Array) -> Array:
	if world == null:
		return []
	var reach: float = float(PLACEMENT[kind]["reach"])
	var out: Array = []
	for q in world_jobs:
		if String(q["kind"]) != kind:
			continue
		var pos = _target_position(world, q)
		if pos == null or s.position.distance_to(pos) > reach:
			continue
		out.append(q)
	return out

# Where the thing a world-target job names is standing, or null if it is no
# longer on the map at all.
static func _target_position(world, q: Dictionary):
	match String(q["kind"]):
		"hunt_party":
			for p in world.parties:
				if p.id == String(q.get("target_party_id", "")):
					return p.position
		"raid_settlement":
			for x in world.settlements:
				if x.id == String(q.get("target_settlement_id", "")):
					return x.position
		"clear_lair":
			for l in world.lairs:
				if l.id == String(q.get("target_lair_id", "")):
					return l.position
	return null

# A counter with an order it cannot fill: bring N of something off its own
# catalog and they pay over list for it. Seeded off the settlement and the
# counter, so it is the same order every time you walk back in — an errand that
# re-rolled itself per visit would be a different errand, not a standing one.
static func supply_offer(s, counter: String) -> Dictionary:
	var ids := supply_candidates(counter)
	if ids.is_empty():
		return {}
	var rng = RNG.new(maxi(1, absi(hash("supply|%s|%s" % [s.id, counter]))))
	var item_id := String(ids[rng.roll_die(ids.size()) - 1])
	var price: int = maxi(1, Campaign.item_price(item_id))
	var required: int = clampi(int(SUPPLY_BUDGET / price), 1, SUPPLY_MAX_COUNT)
	return {
		"id": "supply:%s:%s:%s" % [s.id, counter, item_id],
		"giver_node_id": s.id, "kind": "supply_item", "state": "offered",
		"target_item_id": item_id, "required": required, "progress": 0,
		"title": String(SUPPLY_TITLES.get(counter, "Wanted: %s")) % want(
			Campaign.item_name(item_id), required),
		"reward": {"gold": int(round(price * required * SUPPLY_MARKUP)) + SUPPLY_BONUS},
	}

# What the order asks for, in words: "a Chain Mail", "5 Potions of Climbing".
# The plural goes on the head noun, not the tail — the catalog names things
# "<thing> of <something>" often enough that a naive trailing s is wrong on
# sight ("5 Potion of Climbings").
static func want(item_name: String, n: int) -> String:
	if n > 1:
		var cut: int = item_name.find(" of ")
		var head: String = item_name.substr(0, cut) if cut > 0 else item_name
		if head.ends_with("s"):
			return "%d %s" % [n, item_name]
		return "%d %s%s" % [n, head + "s", item_name.substr(cut) if cut > 0 else ""]
	return "%s %s" % ["an" if item_name.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"]
		else "a", item_name]

# What a counter would ask you to fetch: its own stock, priced like stock rather
# than like treasure. Public because the test suite reads it to prove a counter
# that stocks nothing in range posts nothing.
static func supply_candidates(counter: String) -> Array:
	# Campaign.service_stock_ids only consults `node` for the generalist, and no
	# generalist posts a supply job, so a node-less throwaway is enough here.
	var c = Campaign.new(null)
	var out: Array = []
	for id in c.service_stock_ids(String(SUPPLY_CATALOG.get(counter, counter))):
		var price: int = Campaign.item_price(String(id))
		if price >= SUPPLY_MIN_PRICE and price <= SUPPLY_MAX_PRICE:
			out.append(String(id))
	out.sort()
	return out

# A courier run to the nearest other civilized settlement within reach. Nothing
# goes in the pack: a parcel would need a catalog entry, a price and a weight to
# exist as an item, and all three would be lies. Walking in the far gate is the
# job (Quest.record_settlement_visited).
static func deliver_offer(s, world) -> Dictionary:
	if world == null:
		return {}
	var reach: float = float(PLACEMENT["deliver_goods"]["reach"])
	var best = null
	var best_d := INF
	for other in world.settlements:
		if other.id == s.id or WorldAI.is_monster(other.faction):
			continue
		var d: float = s.position.distance_to(other.position)
		if d > reach or d >= best_d:
			continue
		best = other
		best_d = d
	if best == null:
		return {}
	return {
		"id": "deliver:%s:%s" % [s.id, best.id],
		"giver_node_id": s.id, "kind": "deliver_goods", "state": "offered",
		"target_settlement_id": best.id, "required": 1, "progress": 0,
		"title": "Run a crate of goods to %s" % best.sname,
		"reward": {"gold": DELIVER_BASE + int(best_d / DELIVER_PER_UNIT)},
	}

# Ride out one ring further than this settlement stands and come back able to
# say what is out there (core/regions.gd's bands). A settlement already in the
# last band has nothing further to ask about, and posts nothing.
static func scout_offer(s, world) -> Dictionary:
	if world == null:
		return {}
	var i: int = int(Regions.at(world, s.position)["index"]) + 1
	if i >= Regions.BANDS.size():
		return {}
	var band: Dictionary = Regions.BANDS[i]
	var lv: Array = band["levels"]
	return {
		"id": "scout:%s:%s" % [s.id, String(band["id"])],
		"giver_node_id": s.id, "kind": "scout_region", "state": "offered",
		"target_region_id": String(band["id"]), "required": 1, "progress": 0,
		"title": "Ride out into %s and bring word back (levels %d-%d)" % [
			String(band["label"]), int(lv[0]), int(lv[1])],
		"reward": {"gold": SCOUT_BASE + i * SCOUT_PER_BAND},
	}

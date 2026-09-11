# O6 — what happens when the player walks into a settlement: the market it shows,
# the prices on it, and the option to lift something off the stall instead of
# paying. Pure data + math, no scene: scenes/world/world.gd draws the panel, this
# decides what goes in it, so the economy is testable headless.
#
#   var v := SettlementVisit.visit(settlement, party, world)   # stamps last_visited
#   SettlementVisit.buy(v, party, "longsword")
#   SettlementVisit.steal(settlement, party, world)
#   SettlementVisit.mark_battle(world, loser_position, world.clock.elapsed)  # O5 feed
#
# The catalog is NOT reinvented: T25's node_services/service_stock_ids/item_price
# decide *which* items a settlement of this size sells and what they are worth at
# list price. This file only decides which slice of that catalog is on the shelf
# today and what multiplier sits on top.
# ponytail: it reaches that catalog through a throwaway Campaign instance with a
# synthetic merchant `node` (those helpers are instance methods and campaign.gd is
# out of scope to edit). Make them static the day campaign.gd is in scope.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

# World-time is in minutes (scenes/world/world.gd's HUD reads elapsed/60 as hours).
# Calibration knobs — a party crosses the demo map in ~20 world-minutes, so a
# restock step is an hour and a full restock is most of a day of wandering.
const RESTOCK := 60.0             # world-minutes per restock step
const MAX_STEPS := 6              # steps to a full shelf
const SCARCITY_MARKUP := 0.6      # a just-picked-over market costs +60%
const BATTLE_WINDOW := 240.0      # a fight this recent is still felt in the market
const BATTLE_MARKUP := 1.4        # ...and the survivors are not discounting
const BATTLE_STOCK_LOSS := 0.5    # ...with half the shelf gone
const BATTLE_RADIUS := 140.0      # how near a fight has to be to count as "here"
const MIN_STOCK := 2              # even a stripped market has something out
const SELL_RATE := Campaign.SELL_RATE

# Specialists by settlement kind — the T25 vocabulary, sized off Settlement.kind.
# node_services() always prepends the generalist.
const KIND_SERVICES := {
	"city": ["weaponsmith", "armorsmith", "alchemist", "librarian", "healer", "innkeeper"],
	"town": ["weaponsmith", "alchemist", "innkeeper"],
}

# --- stealing (T30's opportunity_check shape) ------------------------------
const STEAL_SKILL := "sleightofhand"
const STEAL_DC := 15
const STEAL_SHARE := 0.05         # of the shelf's list value
const STEAL_GOLD_MIN := 25
const STEAL_GOLD_MAX := 250

# O7 HOOK. Any visit action a faction would resent adds to
# Settlement.pending_opinion_delta; O7's faction-opinion module drains it (per
# settlement.faction) and zeroes it. Nothing in O6 reads it back.
const OPINION_STEAL_SUCCESS := -5.0
const OPINION_STEAL_CAUGHT := -10.0

# The synthetic T25 merchant node a settlement stands in for.
static func node_for(s) -> Dictionary:
	return {"id": s.id, "kind": "merchant", "title": s.sname,
		"services": KIND_SERVICES.get(s.kind, KIND_SERVICES["town"])}

static func services(s) -> Array:
	return Campaign.node_services(node_for(s))

# Every id this settlement could ever sell, at list price, in a stable order.
static func catalog(s) -> Array:
	var c = Campaign.new(null)
	c.node = node_for(s)
	var ids: Array = c.shop_ids().filter(func(id): return Campaign.item_price(id) > 0)
	ids.sort()
	return ids

static func battle_recent(s, now: float) -> bool:
	return s.battle_at >= 0.0 and now - s.battle_at <= BATTLE_WINDOW

# O5 feed: a fight resolved at `at` marks every settlement standing near it.
static func mark_battle(world, at: Vector2, now: float) -> void:
	for s in world.settlements:
		if s.position.distance_to(at) <= BATTLE_RADIUS:
			s.battle_at = now

# The whole market, pure: same (settlement, gap, battle) -> same shelf and prices.
# Shelf grows with the gap since the last visit; a thin shelf is a dear one, and
# a fight nearby halves it again and marks everything up.
static func market(s, gap: float, battle: bool, opinion := 0.0) -> Dictionary:
	var steps := clampi(int(gap / RESTOCK), 0, MAX_STEPS) if gap >= 0.0 else MAX_STEPS
	var full: float = float(steps) / float(MAX_STEPS)
	var markup := 1.0 + SCARCITY_MARKUP * (1.0 - full)
	if battle:
		markup *= BATTLE_MARKUP
	# O7: what they think of you rides on top of the scarcity markup, and past
	# REFUSE_TRADE they clear the stall rather than deal with you at all.
	markup *= 1.0 - FactionOpinion.PRICE_SWING * opinion / FactionOpinion.RANGE
	if opinion <= FactionOpinion.REFUSE_TRADE:
		return {"steps": steps, "markup": markup, "battle": battle, "gap": gap,
			"opinion": opinion, "refused": true, "stock": []}
	var ids := catalog(s)
	var share := 0.25 + 0.75 * full
	if battle:
		share *= BATTLE_STOCK_LOSS
	var keep := clampi(int(ceil(ids.size() * share)), mini(MIN_STOCK, ids.size()), ids.size())
	var rng = RNG.new(maxi(1, absi(hash("%s|%d|%d" % [s.id, steps, int(battle)]))))
	var pool: Array = ids.duplicate()
	var out: Array = []
	while out.size() < keep and not pool.is_empty():
		var id: String = pool.pop_at(rng.roll_die(pool.size()) - 1)
		out.append({"item_id": id, "name": Campaign.item_name(id),
			"price": maxi(1, int(round(Campaign.item_price(id) * markup)))})
	out.sort_custom(func(a, b): return String(a["item_id"]) < String(b["item_id"]))
	return {"steps": steps, "markup": markup, "battle": battle, "gap": gap,
		"opinion": opinion, "refused": false, "stock": out}

# A visit: reads the gap off the world clock, then stamps it, so visiting twice in
# a row is a bare shelf and coming back tomorrow is a full one.
static func visit(s, world) -> Dictionary:
	var now: float = world.clock.elapsed
	var gap: float = now - s.last_visited if s.last_visited >= 0.0 else -1.0
	var m := market(s, gap, battle_recent(s, now), FactionOpinion.get_opinion(s.faction))
	m["settlement"] = s
	m["services"] = services(s)
	s.last_visited = now
	return m

# --- trade ----------------------------------------------------------------

static func price_of(m: Dictionary, item_id: String) -> int:
	for e in m.get("stock", []):
		if e["item_id"] == item_id:
			return int(e["price"])
	return 0

static func buy(m: Dictionary, party, item_id: String) -> bool:
	var price := price_of(m, item_id)
	if price <= 0 or not party.spend_gold(price):
		return false
	party.stash_add(item_id)
	m["stock"] = m["stock"].filter(func(e): return e["item_id"] != item_id)
	return true

# Sell price follows the same market swing the buy price does.
static func sell_price(m: Dictionary, item_id: String) -> int:
	var list := Campaign.item_price(item_id)
	return 0 if list <= 0 else maxi(1, int(round(list * SELL_RATE * float(m.get("markup", 1.0)))))

static func sell(m: Dictionary, party, item_id: String) -> bool:
	var paid := sell_price(m, item_id)
	if paid <= 0 or not party.stash_remove(item_id):
		return false
	party.add_gold(paid)
	return true

# --- steal (T30's opportunity_check, in a market) --------------------------

# d20 + the party's best Sleight of Hand vs STEAL_DC, one roll, narrated the same
# way. Seeded off the settlement and the hour, so the same attempt is the same
# result; pass an rng to pin it in a test. Either way it costs opinion (success is
# quieter than getting caught) via the O7 hook on the settlement.
static func steal(s, party, world, m: Dictionary = {}, rng = null) -> Dictionary:
	var c = Campaign.new(party)
	var char_id: String = c.best_at(STEAL_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("steal|%s|%d" % [s.id, int(world.clock.elapsed)]))))
	var bonus: int = c.skill_bonus(char_id, STEAL_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= STEAL_DC
	var gold := 0
	if ok:
		var value := 0
		for e in m.get("stock", []):
			value += int(e["price"])
		gold = clampi(int(value * STEAL_SHARE), STEAL_GOLD_MIN, STEAL_GOLD_MAX)
		party.add_gold(gold)
	# O7 hook — see OPINION_STEAL_* above.
	s.pending_opinion_delta += OPINION_STEAL_SUCCESS if ok else OPINION_STEAL_CAUGHT
	var line := ("%s lifts %d gp off the stall (Sleight of Hand %d+%d vs DC %d)."
		% [ch.cname, gold, nat, bonus, STEAL_DC]) if ok else (
		"%s is spotted reaching for it (Sleight of Hand %d+%d vs DC %d)."
		% [ch.cname, nat, bonus, STEAL_DC])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": STEAL_DC, "gold": gold,
		"char_id": char_id, "text": line}

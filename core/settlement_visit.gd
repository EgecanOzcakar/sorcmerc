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
const Adapter = preload("res://core/adapter.gd")
const Quest = preload("res://core/quest.gd")

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

# T9x: a room at the inn isn't free — bigger settlement, pricier bed. Only
# charged by the settlement-visit rest path (world.gd's _rest()); the
# camp-kit's out-of-settlement long rest (core/world_camp.gd) already has its
# own cost (the kit price + ambush risk) and isn't staying at anyone's inn.
const INN_COST := {"city": 40, "town": 20, "camp": 10}

static func inn_cost(s) -> int:
	return int(INN_COST.get(s.kind, INN_COST["town"]))

# --- T9x: persuading a hostile market into trading anyway -------------------
const PERSUADE_SKILL := "persuasion"
const PERSUADE_DC := 15

# Only meaningful once market() has already refused (opinion <= REFUSE_TRADE)
# — one attempt per visit, same shape as steal(). The DC climbs with how far
# below the refusal line the faction actually sits: a settlement that merely
# refuses is one thing, one that loathes you is a harder sell.
static func persuade(s, m: Dictionary, party, rng = null) -> Dictionary:
	if not m.get("refused", false):
		return {}
	var c = Campaign.new(party)
	var char_id: String = c.best_at(PERSUADE_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	var dc: int = PERSUADE_DC + maxi(0, int((FactionOpinion.REFUSE_TRADE - float(m.get("opinion", 0.0))) / 10.0))
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("persuade|%s|%d" % [s.id, int(s.last_visited)]))))
	var bonus: int = c.skill_bonus(char_id, PERSUADE_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= dc
	var line := ("%s talks them into it, grudgingly (Persuasion %d+%d vs DC %d)."
		% [ch.cname, nat, bonus, dc]) if ok else (
		"%s can't budge them (Persuasion %d+%d vs DC %d)." % [ch.cname, nat, bonus, dc])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": dc, "char_id": char_id, "text": line}

# A refused market opened up for this visit only — same markup math as any
# other trade at this opinion, just with the outright refusal lifted (still
# priced like the worst possible customer, not a free pass).
static func persuade_into_trading(s, m: Dictionary) -> Dictionary:
	var opened := market(s, float(m.get("gap", -1.0)), bool(m.get("battle", false)),
		FactionOpinion.REFUSE_TRADE + 1.0)
	opened["opinion"] = m.get("opinion", 0.0)   # the faction's real opinion hasn't moved
	opened["settlement"] = s
	opened["services"] = services(s)
	return opened

# --- T9x: investigating a recent battle site --------------------------------
const INVESTIGATE_SKILL := "investigation"
const INVESTIGATE_DC := 13
const INVESTIGATE_GOLD_MIN := 20
const INVESTIGATE_GOLD_MAX := 80

# Only meaningful when market()'s own `battle` flag is set (O5's off-screen
# fights mark every nearby settlement — battle_recent()). One attempt per
# visit, same shape as steal()/persuade().
static func investigate_battle(s, m: Dictionary, party, rng = null) -> Dictionary:
	if not m.get("battle", false):
		return {}
	var c = Campaign.new(party)
	var char_id: String = c.best_at(INVESTIGATE_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("investigate|%s|%d" % [s.id, int(s.battle_at)]))))
	var bonus: int = c.skill_bonus(char_id, INVESTIGATE_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= INVESTIGATE_DC
	var gold := 0
	if ok:
		gold = INVESTIGATE_GOLD_MIN + rng.roll_die(INVESTIGATE_GOLD_MAX - INVESTIGATE_GOLD_MIN + 1) - 1
		party.add_gold(gold)
	var line := ("%s picks the battlefield clean (Investigation %d+%d vs DC %d) — +%d gold."
		% [ch.cname, nat, bonus, INVESTIGATE_DC, gold]) if ok else (
		"%s finds nothing worth taking (Investigation %d+%d vs DC %d)."
		% [ch.cname, nat, bonus, INVESTIGATE_DC])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": INVESTIGATE_DC, "gold": gold,
		"char_id": char_id, "text": line}

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

# --- O9 / T9x: rest (short and long) ----------------------------------------
#
# core/campaign.gd's rest() is an instance method gated on a linear-run rest node
# and a per-run rest budget, neither of which exists out here — so this calls what
# it calls underneath (Adapter.rest) and charges the only currency the open world
# has: time. Eight hours off the clock is eight hours the market restocks in, and
# eight hours a hunting band keeps walking. A short rest is the same idea at RAW's
# smaller scale — an hour, not a full night.
const LONG_REST_MINUTES := 480.0
const SHORT_REST_MINUTES := 60.0
# RAW: a long rest only grants its benefit once per 24h. Nothing enforced that
# before — a settlement visit could spam free full heals with no cost but clock
# time. can_long_rest() below is the gate; T9x's camp-kit rest goes through the
# same rest()/stamp, so it's covered too, not a second rule to keep in sync.
const LONG_REST_COOLDOWN := 1440.0

static func rest(party, world, kind := "long-rest") -> void:
	for ch in party.party_characters():
		Adapter.rest(ch, kind)
	world.clock.elapsed += (LONG_REST_MINUTES if kind == "long-rest" else SHORT_REST_MINUTES)
	if kind == "long-rest":
		party.last_long_rest_at = world.clock.elapsed

static func can_long_rest(party, world) -> bool:
	return world.clock.elapsed - party.last_long_rest_at >= LONG_REST_COOLDOWN

# World-minutes until the party may long-rest again, 0.0 when they already may.
# The inn page shows this rather than an unexplained disabled button — "not
# tired enough" with no number reads as a bug, same lesson as the quick-build
# no-op (commit e3cc910).
static func long_rest_in(party, world) -> float:
	return maxf(0.0, LONG_REST_COOLDOWN - (world.clock.elapsed - party.last_long_rest_at))

# --- T9y: the specialists behind the counter -------------------------------
#
# T25 already sizes which services a settlement has (KIND_SERVICES above), and
# core/campaign.gd already prices the two that sell no goods at all: the
# Healer's flat whole-party patch-up and the Librarian's no-roll identify. The
# open world showed neither — the market was one undifferentiated stock list,
# so a city's healer and librarian existed only as words in the services line.
#
# These are the open-world versions of campaign.gd's own heal_party()/
# identify_for_fee(): same prices, same effects, but a result dict instead of
# say() and NO autosave — campaign.gd's methods write a CampaignSave, which is
# the wrong save slot entirely out here (world.gd autosaves a WorldSave itself
# after the action). Same {"ok", "text", ...} shape every other check in this
# file returns, so the caller can narrate what happened rather than guess.
const HEAL_COST := Campaign.HEALER_GP
const IDENTIFY_COST := Campaign.IDENTIFY_FEE_GP

static func has_service(s, service: String) -> bool:
	return service in services(s)

# {service: [stock rows]} for the shelf `m` is currently showing, so the market
# can be read one counter at a time instead of as one long alphabetical list.
# A specialist claims an id first (weapons to the weaponsmith, potions to the
# alchemist); whatever nobody claims falls to the generalist, which is every
# settlement's own catalog and therefore a superset — matching against it
# first would swallow the lot.
static func stock_by_service(s, m: Dictionary) -> Dictionary:
	var c = Campaign.new(null)
	c.node = node_for(s)
	var out := {}
	var claimed := {}
	for service in services(s):
		if service == "generalist":
			continue
		var ids := {}
		for id in c.service_stock_ids(service):
			ids[String(id)] = true
		var rows: Array = []
		for e in m.get("stock", []):
			var item_id := String(e["item_id"])
			if ids.has(item_id) and not claimed.has(item_id):
				rows.append(e)
				claimed[item_id] = true
		if not rows.is_empty():
			out[service] = rows
	var rest_rows: Array = []
	for e in m.get("stock", []):
		if not claimed.has(String(e["item_id"])):
			rest_rows.append(e)
	out["generalist"] = rest_rows
	return out

# The Healer: everyone standing back to full, flat fee, no clock time and no
# long-rest cooldown — that's what you're paying to skip. Refuses when nobody
# is actually hurt rather than taking the gold for nothing (the silent-no-op
# lesson again); the dead are not the healer's department (Party.REVIVE_COST
# is, and stays where it is).
static func heal(party) -> Dictionary:
	var hurt: Array = []
	for ch in party.roster:
		if ch.dead:
			continue
		var s = ch.sheet()
		if ch.hp_current >= 0 and ch.hp_current < s.max_hp:
			hurt.append(ch)
	if hurt.is_empty():
		return {"ok": false, "cost": 0, "healed": 0,
			"text": "Nobody here needs the healer."}
	if not party.spend_gold(HEAL_COST):
		return {"ok": false, "cost": HEAL_COST, "healed": 0,
			"text": "The healer wants %d gp up front." % HEAL_COST}
	for ch in hurt:
		ch.hp_current = -1     # the sheet's max, the same "-1 means full" convention Party.summary() reads
		ch.dirty()
	return {"ok": true, "cost": HEAL_COST, "healed": hurt.size(),
		"text": "The healer works down the line — %d back on their feet (-%d gp)." % [
			hurt.size(), HEAL_COST]}

# The Librarian: what a scroll of identification does, for a fee and no roll.
# Trance's free nightly attempt (core/trance.gd) is the same job done badly;
# this is the version you pay to be sure of.
static func identify(party, item_id: String) -> Dictionary:
	if party.stash_count(item_id, true) >= party.stash_count(item_id):
		return {"ok": false, "cost": 0,
			"text": "There's nothing unidentified in the pack like that."}
	if not party.spend_gold(IDENTIFY_COST):
		return {"ok": false, "cost": IDENTIFY_COST,
			"text": "The librarian's fee is %d gp." % IDENTIFY_COST}
	party.stash_identify(item_id)
	return {"ok": true, "cost": IDENTIFY_COST,
		"text": "The librarian reads it off in a breath: %s (-%d gp)." % [
			Campaign.item_name(item_id), IDENTIFY_COST]}

# --- O9: quests (T9's verbs, reached from a settlement) ---------------------
#
# Quest.offer_for() keys on a T25 giver node id; a settlement is not one, so each
# settlement stands in for a curated giver, picked off its own id and stable for
# the life of the map. No new quest content — the same six jobs, reachable.
static func giver_node_id(s) -> String:
	var givers: Array = []
	for q in Quest.CURATED:
		if not givers.has(q["giver_node_id"]):
			givers.append(q["giver_node_id"])
	return String(givers[absi(hash(s.id)) % givers.size()])

# T91: a settlement first tries a world-target quest (hunt a hostile band, raid
# a hostile settlement, clear a lair) seeded off its own id — stable across the
# repeated calls one open visit panel makes, and re-checked against the party's
# log the same way CURATED already is, so an accepted/turned-in one doesn't
# reappear. Falls back to the curated giver-node quest when `world` is unset
# (any caller that predates T91) or nothing world-side qualifies right now.
static func quest_offer(s, party, world = null) -> Dictionary:
	if world != null:
		var wq: Dictionary = Quest.world_quest_for(world, s, RNG.new(maxi(1, absi(hash(s.id)))))
		if not wq.is_empty() and Quest.get_quest(party, wq["id"]).is_empty():
			return wq
	return Quest.offer_for(party, giver_node_id(s), FactionOpinion.get_opinion(s.faction))

static func turn_ins(party) -> Array:
	return party.quests.filter(func(q): return Quest.can_turn_in(q))

# T9x quest board: every job this settlement can offer right now, not just
# one — every eligible world target (Quest.world_quest_offers) plus the
# curated giver-node job, whichever of those the party doesn't already have
# logged. Same opinion gate as the single-offer path.
static func quest_offers(s, party, world = null) -> Array:
	var out: Array = []
	if world != null:
		out.append_array(Quest.world_quest_offers(world, s, party, RNG.new(maxi(1, absi(hash(s.id))))))
	var curated := Quest.offer_for(party, giver_node_id(s), FactionOpinion.get_opinion(s.faction))
	if not curated.is_empty():
		out.append(curated)
	return out

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

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
const Posting = preload("res://core/quest_posting.gd")
const Potions = preload("res://core/potions.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Ach = preload("res://core/achievements.gd")
const Party = preload("res://core/party.gd")   # #109: REVIVE_COST, for the healer's raise

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
const FULL_SHELF := 0.5           # a rested market shows this much of its catalog, not all of it
const SELL_RATE := Campaign.SELL_RATE

# Specialists by settlement kind — the T25 vocabulary, sized off Settlement.kind.
# node_services() always prepends the generalist.
# D7: "camp" was missing and fell through to the town list, so a camp of six
# charcoal-burners had a weaponsmith, an alchemist and an inn. Campaign.
# SIZE_SPECIALISTS has always said a camp has none ([0, 0]); this is that, said
# where the open world reads it. The town fallback stays for an unknown kind.
const KIND_SERVICES := {
	"city": ["weaponsmith", "armorsmith", "alchemist", "librarian", "healer", "innkeeper"],
	"town": ["weaponsmith", "alchemist", "innkeeper"],
	"camp": [],
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
# The colder the town, the harder the ask — a point of DC per 10 opinion below the refusal line.
static func persuade_dc(m: Dictionary) -> int:
	return PERSUADE_DC + maxi(0, int((FactionOpinion.REFUSE_TRADE - float(m.get("opinion", 0.0))) / 10.0))

static func persuade(s, m: Dictionary, party, rng = null) -> Dictionary:
	if not m.get("refused", false):
		return {}
	var c = Campaign.new(party)
	var char_id: String = c.best_at(PERSUADE_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	var dc: int = persuade_dc(m)
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("persuade|%s|%d" % [s.id, int(s.last_visited)]))))
	var bonus: int = c.skill_bonus(char_id, PERSUADE_SKILL)
	var nat: int = int(Dice.d20(rng, _talk_mode(ch, party))["nat"])
	var ok: bool = nat + bonus >= dc
	var line := ("%s talks them into it, grudgingly (Persuasion %d+%d vs DC %d)."
		% [ch.cname, nat, bonus, dc]) if ok else (
		"%s can't budge them (Persuasion %d+%d vs DC %d)." % [ch.cname, nat, bonus, dc])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": dc, "char_id": char_id, "text": line}

# A refused market opened up for this visit only — same markup math as any
# other trade at this opinion, just with the outright refusal lifted (still
# priced like the worst possible customer, not a free pass).
static func persuade_into_trading(s, m: Dictionary) -> Dictionary:
	Ach.unlock("persuade_market")
	var opened := market(s, float(m.get("gap", -1.0)), bool(m.get("battle", false)),
		FactionOpinion.REFUSE_TRADE + 1.0)
	opened["opinion"] = m.get("opinion", 0.0)   # the faction's real opinion hasn't moved
	opened["settlement"] = s
	opened["services"] = services(s)
	return opened

# --- T9x: haggling over an already-open market's prices ---------------------
# A Potion of Mind Reading still working, or Detect Thoughts / Suggestion in
# the party's repertoire, is advantage on the talk (core/potions.gd, party.gd).
const TALK_SPELLS := ["detect-thoughts", "suggestion"]
static func _talk_mode(ch, party) -> int:
	if Potions.road_buff(ch, "persuasion_adv", party.world_now) or party.caster_of(TALK_SPELLS) != null:
		return Dice.ADV
	return Dice.NORMAL

# #87: what a check button would roll, before it is pressed — who, with what
# bonus, against what DC, and the odds that gives. The same numbers the
# result line will quote, so nothing on the button is a surprise afterwards.
static func check_preview(party, skill: String, dc: int, adv := false) -> String:
	var c = Campaign.new(party)
	var char_id: String = c.best_at(skill)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return "Nobody in the party can attempt this."
	var bonus: int = c.skill_bonus(char_id, skill)
	var need: int = clampi(dc - bonus, 2, 20)   # a natural 1 always misses; a 20 always lands
	var p: float = (21 - need) / 20.0
	if adv:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	var name: String = String(Catalog.skills().get(skill, {}).get("name", skill.capitalize()))
	return "%s rolls %s %+d vs DC %d — needs %d+ on the d20%s, %d%% to make it." % [
		ch.cname, name, bonus, dc, need, " (advantage)" if adv else "", int(round(p * 100.0))]

const HAGGLE_SKILL := "persuasion"
const HAGGLE_DC := 13
const HAGGLE_DISCOUNT := 0.15   # success: 15% off every price for this visit
const HAGGLE_PENALTY := 0.10    # failure: 10% worse — a bad ask sours the room

# The mirror of persuade(): that one talks a REFUSED market into opening at
# all; this one only makes sense once it's already open, moving the price
# up or down instead of the door. One attempt per visit, same shape as
# persuade()/steal() — apply_haggle() below does the actual repricing so
# this stays a pure roll, same "the caller decides what a result means"
# split search()/loot() already use.
static func haggle(m: Dictionary, party, rng = null) -> Dictionary:
	if m.get("refused", false):
		return {}
	var c = Campaign.new(party)
	var char_id: String = c.best_at(HAGGLE_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	var s = m.get("settlement")
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("haggle|%s|%d" % [String(s.id) if s != null else "", int(m.get("steps", 0))]))))
	var bonus: int = c.skill_bonus(char_id, HAGGLE_SKILL)
	var nat: int = int(Dice.d20(rng, _talk_mode(ch, party))["nat"])
	var ok: bool = nat + bonus >= HAGGLE_DC
	var mult := (1.0 - HAGGLE_DISCOUNT) if ok else (1.0 + HAGGLE_PENALTY)
	if ok:
		Ach.bump("haggles")
	var line := ("%s talks the price down (Persuasion %d+%d vs DC %d) — %d%% off for the rest of this visit."
		% [ch.cname, nat, bonus, HAGGLE_DC, int(HAGGLE_DISCOUNT * 100)]) if ok else (
		"%s oversells it and gets a cold shoulder (Persuasion %d+%d vs DC %d) — prices just got worse."
		% [ch.cname, nat, bonus, HAGGLE_DC])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": HAGGLE_DC, "mult": mult, "char_id": char_id, "text": line}

# Rescales the market's own markup and every already-priced shelf item by
# `mult` — in place, on the live visit dict, not a fresh market() roll (a
# haggle changes what THIS conversation agreed to, not the shelf itself).
static func apply_haggle(m: Dictionary, mult: float) -> void:
	m["markup"] = float(m.get("markup", 1.0)) * mult
	for e in m.get("stock", []):
		e["price"] = maxi(1, int(round(int(e["price"]) * mult)))

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
		Ach.unlock("investigate_battle")
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
	var share := FULL_SHELF * (0.25 + 0.75 * full)
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
	Campaign._note_rarity(item_id)
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
	Ach.record("best_sale", paid)
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
# #86: RAW's adventuring day — two short rests between long rests. Same shape as
# core/campaign.gd's MAX_SHORT_RESTS, but counted per long rest, not per run.
const MAX_SHORT_RESTS := 2

static func rest(party, world, kind := "long-rest") -> void:
	for ch in party.roster:   # #108: the bench sleeps under the same roof
		if not ch.dead:
			Adapter.rest(ch, kind)
	world.clock.elapsed += (LONG_REST_MINUTES if kind == "long-rest" else SHORT_REST_MINUTES)
	if kind == "long-rest":
		party.last_long_rest_at = world.clock.elapsed
		party.short_rests_since_long = 0
	else:
		party.short_rests_since_long += 1

static func can_short_rest(party) -> bool:
	return party.short_rests_since_long < MAX_SHORT_RESTS

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
# lesson again).
# #109: the open world had no way back from death at all — resurrection
# needed a Revivify caster or a scroll, and a party without either was one
# member down for good. The healer does it for the same fee, no caster asked.
static func raise_dead(party, id: String) -> Dictionary:
	var ch = party.get_member(id)
	if ch == null or not ch.dead:
		return {"ok": false, "text": "Nobody by that name needs raising."}
	if not party.spend_gold(Party.REVIVE_COST):
		return {"ok": false, "cost": Party.REVIVE_COST,
			"text": "The healer wants %d ◉ up front to raise %s." % [Party.REVIVE_COST, ch.cname]}
	ch.dead = false
	ch.hp_current = 1
	ch.dirty()
	Ach.bump("resurrections")
	return {"ok": true, "cost": Party.REVIVE_COST,
		"text": "%s draws breath again (-%d ◉). Barely." % [ch.cname, Party.REVIVE_COST]}

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
			"text": "The healer wants %d ◉ up front." % HEAL_COST}
	for ch in hurt:
		ch.hp_current = -1     # the sheet's max, the same "-1 means full" convention Party.summary() reads
		ch.dirty()
	return {"ok": true, "cost": HEAL_COST, "healed": hurt.size(),
		"text": "The healer works down the line — %d back on their feet (-%d ◉)." % [
			hurt.size(), HEAL_COST]}

# Working the healer's counter: a party that carries Lesser or Greater
# Restoration is worth a morning to any healer, paid on a Medicine check. One
# shift per visit, same shape as haggle()/steal(). The spell is the door, the
# skill is the wage: the healer is hiring hands, not miracles.
const WORK_SPELLS := ["lesser-restoration", "greater-restoration"]
const WORK_SKILL := "medicine"
const WORK_DC := 13
const WORK_PAY := 40          # a good morning
const WORK_PAY_POOR := 10     # a clumsy one still gets the floor swept

static func can_work_healer(party) -> bool:
	return party.caster_of(WORK_SPELLS) != null

static func work_healer(s, party, rng = null) -> Dictionary:
	var door: Dictionary = party.caster_and_spell(WORK_SPELLS)
	if door.is_empty():
		return {}
	var caster = door["ch"]
	var spell := spell_name(String(door["spell"]))
	var c = Campaign.new(party)
	var char_id: String = c.best_at(WORK_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else caster
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("work|%s|%d" % [s.id, int(s.last_visited)]))))
	var bonus: int = c.skill_bonus(ch.id, WORK_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= WORK_DC
	var pay: int = WORK_PAY if ok else WORK_PAY_POOR
	party.add_gold(pay)
	Ach.unlock("healer_work")
	var line := ("%s's %s gets them in the door; %s runs the ward all morning (Medicine %d+%d vs DC %d) — %d ◉."
		% [caster.cname, spell, ch.cname, nat, bonus, WORK_DC, pay]) if ok else (
		"%s's %s gets them in the door, but %s is more hindrance than help (Medicine %d+%d vs DC %d) — %d ◉ for the trouble."
		% [caster.cname, spell, ch.cname, nat, bonus, WORK_DC, pay])
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": WORK_DC, "pay": pay, "char_id": ch.id, "text": line}

static func spell_name(sid: String) -> String:
	return String(Catalog.spell(sid).get("name", sid.capitalize()))


# The Librarian: what a scroll of identification does, for a fee and no roll.
# Trance's free nightly attempt (core/trance.gd) is the same job done badly;
# this is the version you pay to be sure of.
static func identify(party, item_id: String) -> Dictionary:
	if party.stash_count(item_id, true) >= party.stash_count(item_id):
		return {"ok": false, "cost": 0,
			"text": "There's nothing unidentified in the pack like that."}
	if not party.spend_gold(IDENTIFY_COST):
		return {"ok": false, "cost": IDENTIFY_COST,
			"text": "The librarian's fee is %d ◉." % IDENTIFY_COST}
	party.stash_identify(item_id)
	Campaign._note_identified(item_id)
	return {"ok": true, "cost": IDENTIFY_COST,
		"text": "The librarian reads it off in a breath: %s (-%d ◉)." % [
			Campaign.item_name(item_id), IDENTIFY_COST]}

# --- O9 / D7: quests (T9's verbs, reached from a settlement) ----------------
#
# WHICH jobs a settlement posts, and at which of its counters, is
# core/quest_posting.gd's question — these are the two lines the visit panel
# calls, kept here because a visit is how the player reaches any of it.
# `services(s)` is passed in rather than looked up over there so the two modules
# stay one-directional: this one knows about postings, that one knows nothing
# about visits.
static func giver_node_id(s) -> String:
	return Posting.giver_node_id(s)

# T9x quest board, D7 placement: every job this settlement can post right now,
# flat and in kind order, each stamped with the counter posting it. The single
# ad-hoc offer quest_offer() used to return is simply the first of them.
static func quest_offers(s, party, world = null) -> Array:
	return Posting.offers(s, services(s), party, world)

# {counter: [job, ...]} — what each counter has up, for the pages that show a
# job where its business is instead of everything on one board.
static func quest_offers_by_counter(s, party, world = null) -> Dictionary:
	return Posting.by_counter(quest_offers(s, party, world))

# The one job a caller that only wants one should show. Kept for the callers
# that predate the board (and for "does this settlement have any work at all").
static func quest_offer(s, party, world = null) -> Dictionary:
	var out := quest_offers(s, party, world)
	return out[0] if not out.is_empty() else {}

static func turn_ins(party) -> Array:
	return party.quests.filter(func(q): return Quest.can_turn_in(q))

# --- steal (T30's opportunity_check, in a market) --------------------------

# d20 + the party's best Sleight of Hand vs STEAL_DC, one roll, narrated the same
# way. Seeded off the settlement and the hour, so the same attempt is the same
# result; pass an rng to pin it in a test. Either way it costs opinion (success is
# quieter than getting caught) via the O7 hook on the settlement.
# After any attempt the stall is watched: no second try here for a day, so
# Leave-and-come-back is not an unlimited gold button either.
const STEAL_COOLDOWN_MINUTES := 24.0 * 60.0

# World-minutes until the stall stops watching, 0 when it isn't.
static func steal_wait(s, world) -> float:
	if s.stolen_at < 0.0:
		return 0.0
	return maxf(0.0, s.stolen_at + STEAL_COOLDOWN_MINUTES - world.clock.elapsed)

static func steal(s, party, world, m: Dictionary = {}, rng = null) -> Dictionary:
	var c = Campaign.new(party)
	var char_id: String = c.best_at(STEAL_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	if steal_wait(s, world) > 0.0:
		return {"ok": false, "watched": true, "gold": 0,
			"text": "They are watching the stall now. Come back another day."}
	s.stolen_at = world.clock.elapsed
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
	Ach.unlock("steal_first" if ok else "steal_caught")
	# O7 hook — see OPINION_STEAL_* above.
	var delta: float = OPINION_STEAL_SUCCESS if ok else OPINION_STEAL_CAUGHT
	s.pending_opinion_delta += delta
	var line := ("%s lifts %d ◉ off the stall (Sleight of Hand %d+%d vs DC %d)."
		% [ch.cname, gold, nat, bonus, STEAL_DC]) if ok else (
		"%s is spotted reaching for it (Sleight of Hand %d+%d vs DC %d)."
		% [ch.cname, nat, bonus, STEAL_DC])
	# The cost is said where it is incurred, not discovered on the next visit.
	line += "  The %s will hear of it: opinion %d." % [String(s.faction).capitalize(), int(delta)]
	return {"ok": ok, "nat": nat, "bonus": bonus, "dc": STEAL_DC, "gold": gold,
		"char_id": char_id, "text": line}

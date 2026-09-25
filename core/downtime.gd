# Downtime — what a company does in town when it is not working. A town today
# is a market, a board, a bed and four one-shot rows, and every one of them
# takes a moment; nothing in a town takes DAYS, so the clocks the road built (a
# raid due in two days, a lair's window, a calling's road) never trade against
# anything. These are the things that take days, from the table 5e keeps for
# exactly this question:
#
#   Downtime.train(party, world, s, ch, "sentinel")   # a feat, five days, once a tier per hero
#   Downtime.carouse(party, world, s)                 # a night on the town: a contact, a lead, or a story
#   Downtime.gamble(party, world, s, 50)              # a stake and a roll; an evening, once a day a town
#   Downtime.craft(party, world, s, "potion-of-speed", m)   # the alchemist's bench / the librarian's desk
#   Downtime.pit_bracket(s, world) / pit_spec / pit_result  # a city's three champions, once a week, one on one
#   Downtime.pit_line_up(party, char_id) / pit_stand_down(party, order)   # the one hero who stands
#   Downtime.carouse_cost(party, s) / carouse_refusal(party, s)   # the whole night's price, and why not
#
# Static, in settlement_visit.gd's row shape — every activity returns {ok,
# nat, bonus, dc, text, ...} and the screen shows it the way it shows
# work_healer(): a line under the row, and a card when there is a
# complication. State lives on party.downtime (saved beside callings):
#   {"trained": [char_id, once per feat], "gambled_day": {s.id: world-day},
#    "crafted": {s.id: {item_id: last_visited}}, "pit": {s.id: {"week", "beaten"}}}
# Days go through spend_days(): the clock moves, the party sleeps, the bed is
# paid. The complication is the anti-grind: a fail is a small story, never
# nothing. docs/superpowers/specs/2026-09-21-downtime-design.md.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Rumors = preload("res://core/rumors.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const EnemyNames = preload("res://core/enemy_names.gd")
const Abilities = preload("res://core/rules/pass_abilities.gd")
const Scaler = preload("res://core/scaler.gd")
const Regions = preload("res://core/regions.gd")

const DAY := 1440.0   # world-minutes

# A feat is a level's worth; five days is two raid clocks.
#
# 2026-09-25 (the design audit §5.1, "sinks that scale with level"): a hero
# used to train once, ever, so the one sink that grew with level was spent by
# level 5 and never offered again. Now a hero may train once per TRAIN_EVERY
# levels from TRAIN_MIN_LEVEL — at 4, 8, 12, 16 and 20, one feat each — and each
# is priced at the hero's level then, so it is a purchase at every tier of the
# run, not one at the start of it. The fee climbs 100 ◉ a level: ESTIMATED
# against an easy open-country purse (Campaign.SELL_RATE's table), the level-4
# feat is 550 ◉ (~26 fights' coin), the level-8 950 (~19), the level-12 1,350
# (~18), the level-16 1,750 (~19), the level-20 2,150 (~17) — the same weight
# each time.
#
# The extra feats are real power, and priced as such: a feat lands on the sheet
# (bundles.gd step 9), so core/rules/power.gd reads its +1 and whatever else it
# grants, and the fights the company is sent grow to match. The general feats
# the trainer finishes (trainable) are the ones with no choice left to make.
const TRAIN_COST_BASE := 150
const TRAIN_COST_PER_LEVEL := 100
const TRAIN_DAYS := 5
const TRAIN_MIN_LEVEL := 4
const TRAIN_EVERY := 4
const TRAIN_CATEGORY := "general"
# A night at the inn, and the drinks. The road's DC; half a job's opinion.
const CAROUSE_COST := {"city": 30, "town": 20, "camp": 10}
const CAROUSE_DC := 13
const CAROUSE_CONTACT := 5.0
const CAROUSE_COIN := 15
const CAROUSE_SKILLS := ["persuasion", "performance"]
# The game. A table in town is a sink with a story in it, not a job: the
# house wins over an evening unless the company's gambler is exceptional, and
# a company sits in once a DAY per town, not once a visit — stepping out of
# the gate and back used to re-arm it (the design audit,
# docs/audit-game-design.md §1.5). The table used to pay 1.5x at DC 12, 2x at
# DC 17 and 3x on a 20, a positive return from +2 up (1.33x at +5, 1.53x at
# +7), so the max stake every visit was the only sensible play.
#
# Now the lowest win only pays the stake back (the owner's call), a total of
# GAMBLE_BIG pays half again, a natural 20 still trebles it, and a natural 1
# always loses whatever the bonus. The skill is the best of Insight, Deception
# and Sleight of Hand in the marching party (best_of).
#
# EV (exact, d20 arithmetic): what comes back per 1 ◉ staked, by bonus —
# sum over the twenty faces of the payout, over 20. Not a sweep: nothing here
# is random but the die, and tests/test_downtime.gd enumerates it.
#   +0 0.500  +1 0.550  +2 0.600  +3 0.650  +4 0.700  +5 0.750
#   +6 0.825  +7 0.900  +8 0.975  +9 1.050  +10 1.125 +11 1.200  +12 1.225
# Below 1 through +8; only a +9 gambler (a level 9+ rogue with Expertise, say)
# breaks even, and past +11 the curve flattens because every face but the 1
# already pays.
const GAMBLE_DC := 13          # the lowest win: the stake comes back
const GAMBLE_BIG := 25         # half again
const GAMBLE_MULT := {"even": 1.0, "big": 1.5, "nat20": 3.0}
const GAMBLE_STAKES := [25, 50, 100, 200]
const GAMBLE_SKILLS := ["insight", "deception", "sleightofhand"]
# Half price for a day.
const CRAFT_RATE := 0.5
const CRAFT_DAYS := 1
# A job, two jobs, a rare item's tenth.
const PIT_PURSE := [60, 120, 240]
# #236: the pit is one on one — one hero the company puts up against one
# champion, not the marching four against a lone foe pumped to take them. The
# champion is priced for a hero of that hero's level (pit_champion, through
# Scaler.duel_for), drawn from PIT_POOL, the people who fight for money in a
# square (no archers: a pit is not a range).
# It used to be the city roster's strongest humanoid at PIT_MULT 1.3/1.7/2.2
# against the whole party, a number nobody had measured (the design audit's
# list of unswept knobs).
#
# PIT_RATIO is what the champion is worth against the ruler's average hero at
# the level (pit_champion). MEASURED 2026-09-25, tests/sweep_pit.gd: each
# preset alone at levels 1, 3, 5, 8, 12 and 16, 40 pinned seeds a cell, both
# sides on the autopilot. Win % per level, then the mean:
#   ratio  fighter                               rogue                   cleric
#   0.6    97.5 92.5 100 100 100 100   98.3      62.5 50 30 7.5 15 7.5   28.8   40 32.5 25 0 0 0  16.3
#   0.9    95 85 92.5 82.5 95 100      91.7      45 25 2.5 0 0 0         12.1   35 10 0 0 0 0     7.5
#   1.2    67.5 50 77.5 30 45 92.5     60.4      17.5 0 0 0 0 0           2.9   10 0 0 0 0 0      1.7
# Set on the FIGHTER's column, the one duellist the presets have: a first bout
# they nearly always take, a second a little harder than a road fight (~85-90%),
# a third they lose four times in ten. The rogue's and the cleric's columns are
# the autopilot's, not the class's — alone, the autopilot cleric never casts, it
# swings its mace (a level-8 cleric against a bandit captain, replayed on
# 2026-09-25: nine rounds of +4 swings and not one spell) —
# so they say "put in your sword-arm", which is the choice the row asks for,
# and they are not a target. Re-run the sweep when the autopilot learns to
# duel (docs/plan/2026-09-25-downtime-nights.md, Still open).
const PIT_RATIO := [0.6, 0.9, 1.2]
const PIT_POOL := ["bandit", "guard", "tribal-warrior", "scout", "thug", "spy", "berserker",
	"veteran", "bandit-captain", "knight", "half-red-dragon-veteran", "gladiator"]
const PIT_WEEK := 7 * DAY
const PIT_BOUTS := 3
const PIT_THEME := "city-square"
# The small stories.
const COMPLICATIONS := ["tab", "brawl", "insult", "bad_lead"]
const TAB_MULT := 2
const INSULT := 5.0

# --- days -----------------------------------------------------------------

# `party` for the lodge's free bed (Visit.inn_cost); without one it is the
# inn's rate, which is every bed but that one.
static func bed_cost(s, days: int, party = null) -> int:
	return Visit.inn_cost(s, party) * days

static func bed_line(s, days: int, party = null) -> String:
	if days == 1:
		return "A day, a night: %d ◉ for the bed." % bed_cost(s, 1, party)
	return "%d days, %d nights: %d ◉ for the bed." % [days, days, bed_cost(s, days, party)]

# The clock moves exactly `days` — Visit.rest() adds its own eight hours, so
# those are taken off first and the long rest is the last night of the stay
# (party.last_long_rest_at lands at the end, which is when they last slept).
# The bed is paid up front; a purse that cannot pays nothing and no day
# passes (-1). Every last_visited/battle_at stamp stays: the market restocks
# on its own clock, and "once a visit" means this visit.
#
# Audit 1.9 (docs/audit-game-design.md): that last night is a long rest only
# when RAW's 24-hour gate allows one (Visit.can_long_rest, read as the night
# begins). A day's work begun the morning after a rest ends with the days gone,
# the bed paid, and nothing refilled — the company slept, but it had already
# had its long rest for the day. It used to refill regardless, so a day's craft
# was a full rest sixteen hours after the last.
static func spend_days(party, world, s, days: int) -> int:
	var bed := bed_cost(s, days, party)
	if days <= 0 or not party.spend_gold(bed):
		return -1
	world.clock.elapsed += days * DAY - Visit.LONG_REST_MINUTES
	if Visit.can_long_rest(party, world):
		Visit.rest(party, world, "long-rest")
	else:
		world.clock.elapsed += Visit.LONG_REST_MINUTES
	Ach.bump("downtime_days", days)
	return bed

# --- training -------------------------------------------------------------

# `trained` holds a hero's id once per feat trained (a save from before
# 2026-09-25 holds it at most once, which reads as the first tier's feat).
static func trained_count(party, ch) -> int:
	return Array(party.downtime.get("trained", [])).count(ch.id) if ch != null else 0

# How many feats a hero of this level may have trained by now: one at
# TRAIN_MIN_LEVEL and one more every TRAIN_EVERY levels after it.
static func trains_allowed(level: int) -> int:
	return 0 if level < TRAIN_MIN_LEVEL else 1 + (level - TRAIN_MIN_LEVEL) / TRAIN_EVERY

static func can_train(party, ch) -> bool:
	return ch != null and trained_count(party, ch) < trains_allowed(ch.level())

static func train_cost(ch) -> int:
	return TRAIN_COST_BASE + TRAIN_COST_PER_LEVEL * ch.level()

# The general-category feats the sheet does not have — neither taken outright
# (ch.feats) nor granted by anything on the build (bundles.gd's expanded
# feats: a background's origin feat, a chosen one) — and that the trainer can
# finish: a feat's +1 is decided here (train()), but a skill, an expertise or
# a feature to pick is the level-up screen's, and a trained feat that lands
# "1 choice left" is no feat at all.
static func trainable(ch) -> Array:
	var have: Dictionary = Bundles.collect(ch)["expanded_feats"]
	var out: Array = []
	for f in Catalog.all("feats.json"):
		var fid := String(f["id"])
		if String(f.get("category", "")) != TRAIN_CATEGORY or fid in ch.feats or have.has(fid):
			continue
		if f.get("grants", []).any(func(g): return String(g["type"]).ends_with("-choice") and String(g["type"]) != "ability-choice"):
			continue
		out.append(fid)
	return out

# The feat's +1, decided for them: the highest of the scores the feat allows
# (all six when it does not say), ties to the first listed. The grant's key is
# the pending entry's key (core/rules/choice.gd). The lodge's yard decides a
# retrained feat the same way (core/lodge.gd).
static func decide_ability(ch, feat_id: String) -> String:
	for g in Catalog.feat_src(feat_id).get("grants", []):
		if String(g["type"]) != "ability-choice":
			continue
		var from: Array = g["from"] if g["from"] != null else Abilities.KEYS
		var best := ""
		for a in from:
			if best == "" or ch.sheet().abilities[a]["total"] > ch.sheet().abilities[best]["total"]:
				best = String(a)
		ch.decide(String(g["key"]), {"type": "ability-choice", "abilities": [best]})
		return best
	return ""

# {} when the trainer will not take them (level, a second feat, a feat that is
# not on the list); {"ok": false} when the purse is short. bundles.gd step 9
# expands the feat at the next resolve — ch.dirty() is that resolve.
static func train(party, world, s, ch, feat_id: String) -> Dictionary:
	if not can_train(party, ch) or not feat_id in trainable(ch):
		return {}
	var fee := train_cost(ch)
	var bed := bed_cost(s, TRAIN_DAYS, party)
	if party.gold < fee + bed:
		return {"ok": false, "cost": fee, "bed": bed,
			"text": "The master-at-arms wants %d ◉, and the bed %d more." % [fee, bed]}
	party.spend_gold(fee)
	ch.feats.append(feat_id)
	ch.dirty()
	decide_ability(ch, feat_id)
	spend_days(party, world, s, TRAIN_DAYS)
	var trained: Array = party.downtime.get("trained", [])
	trained.append(ch.id)
	party.downtime["trained"] = trained
	Ach.bump("trained")
	var feat_name := String(Catalog.feat_src(feat_id).get("name", feat_id.capitalize()))
	return {"ok": true, "feat_name": feat_name, "days": TRAIN_DAYS, "cost": fee, "bed": bed,
		"text": "Five days with a master-at-arms, and %s comes out of it with %s.  %s" % [
			ch.cname, feat_name, bed_line(s, TRAIN_DAYS, party)]}

# --- the roll ---------------------------------------------------------------

# The party's best across several skills — whoever's best skill among them is
# highest. {} when nobody stands. best_at() is per skill; a night on the town
# takes Persuasion or Performance, whichever the company is better at.
static func best_of(party, skills: Array) -> Dictionary:
	var c = Campaign.new(party)
	var out := {}
	for skill in skills:
		var id: String = c.best_at(skill)
		if id == "":
			continue
		var b: int = c.skill_bonus(id, skill)
		if out.is_empty() or b > int(out["bonus"]):
			out = {"char_id": id, "skill": skill, "bonus": b}
	return out

static func _skill_name(skill: String) -> String:
	return String(Catalog.skills().get(skill, {}).get("name", skill.capitalize()))

# --- carousing --------------------------------------------------------------

# #237: what the night costs, all of it — the drinks and the bed the company
# sleeps it off in. The row used to name the drinks alone ("A night on the
# town (30 ◉)"), so a purse that held the 30 and not the 40 for a city bed
# pressed Go out and got a refusal on the log line at the foot of the panel,
# under a list that had just jumped back to its top: nothing happened, as far
# as anyone at the row could see.
static func carouse_cost(party, s) -> Dictionary:
	var drinks := int(CAROUSE_COST.get(s.kind, CAROUSE_COST["town"]))
	var bed := bed_cost(s, 1, party)
	return {"drinks": drinks, "bed": bed, "total": drinks + bed}

# The line for a night the company cannot have; "" when it can. The screen
# greys Go out and puts this under the row, the way gamble_refusal does.
static func carouse_refusal(party, s) -> String:
	if best_of(party, CAROUSE_SKILLS).is_empty():
		return "Nobody in the company is fit for a night out."
	var c := carouse_cost(party, s)
	if party.gold < int(c["total"]):
		return "A night on the town is %d ◉, and the bed %d more: %d ◉ in the purse." % [
			int(c["drinks"]), int(c["bed"]), party.gold]
	return ""

# Pass: a contact — the faction warms, and the common room tells them the
# nearest thing it knows for nothing (or, with nothing left to tell, stands a
# round). Nat 20: the lead and the round both. Fail: a story (`complication`,
# one of the four, drawn by the same die — the card is complication() below,
# and the screen applies it). Nat 1: the story, and the tab on top — that one
# is paid here, so one card is one card.
static func carouse(party, world, s, rng = null) -> Dictionary:
	var who := best_of(party, CAROUSE_SKILLS)
	if who.is_empty():
		return {}
	var ch = party.get_member(who["char_id"])
	var cost := int(CAROUSE_COST.get(s.kind, CAROUSE_COST["town"]))
	var bed := bed_cost(s, 1, party)
	if party.gold < cost + bed:
		return {"ok": false, "cost": cost, "bed": bed, "text": carouse_refusal(party, s)}
	party.spend_gold(cost)
	spend_days(party, world, s, 1)
	# Seeded off the visit and the clock: the day just spent moved it, so each
	# night of a stay is its own roll.
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("carouse|%s|%d|%d" % [s.id, int(s.last_visited), int(world.clock.elapsed)]))))
	var skill := String(who["skill"])
	var bonus := int(who["bonus"])
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat != 1 and (nat == 20 or nat + bonus >= CAROUSE_DC)
	var out := {"ok": ok, "nat": nat, "bonus": bonus, "dc": CAROUSE_DC, "char_id": ch.id, "cost": cost,
		"cname": ch.cname, "skill": skill,
		"contact": ok, "lead": {}, "coin": 0, "complication": "", "tab": 0}
	if ok:
		FactionOpinion.raise(s.faction, CAROUSE_CONTACT)
		Ach.bump("contacts")
		var line := "%s makes friends of half the room (%s %d+%d vs DC %d): a contact among the %s." % [
			ch.cname, _skill_name(skill), nat, bonus, CAROUSE_DC, Ladder.people(s.faction)]
		out["lead"] = Rumors.free_lead(s, party, world)
		if not out["lead"].is_empty():
			line += "  " + String(out["lead"]["text"])
		if nat == 20 or out["lead"].is_empty():
			out["coin"] = CAROUSE_COIN
			party.add_gold(CAROUSE_COIN)
			line += "  The contact stands a round: +%d ◉." % CAROUSE_COIN
		out["text"] = line
		return out
	var line := "%s makes the wrong sort of impression (%s %d+%d vs DC %d)." % [
		ch.cname, _skill_name(skill), nat, bonus, CAROUSE_DC]
	if nat == 1:
		var others: Array = COMPLICATIONS.filter(func(k): return k != "tab")
		out["complication"] = others[rng.roll_die(others.size()) - 1]
		out["tab"] = TAB_MULT * cost
		party.add_gold(-TAB_MULT * cost)
		line += "  The morning brings a bill nobody remembers running up: -%d ◉." % (TAB_MULT * cost)
	else:
		out["complication"] = COMPLICATIONS[rng.roll_die(COMPLICATIONS.size()) - 1]
	out["text"] = line
	return out

# --- once a visit -------------------------------------------------------------

# The bench's "once a visit" is the visit's own last_visited stamp. The
# screen re-reads the shelf mid-visit (a rest, the inn reopening behind a bout
# or a brawl) through Visit.visit(), which stamps it again; the stamps that
# were this visit's move with it, or the rows re-arm. The game is once a DAY
# (gambled_day, below), which no re-read of the visit can move.
static func restamp(party, s, old: float, new: float) -> void:
	var here: Dictionary = party.downtime.get("crafted", {}).get(s.id, {})
	for item in here:
		if is_equal_approx(float(here[item]), old):
			here[item] = new

# --- gambling ---------------------------------------------------------------

# The world-day a game is counted against: midnight to midnight on the world
# clock. The same day index the carouse and the market's clocks count in.
static func world_day(world) -> int:
	return int(floor(world.clock.elapsed / DAY))

# Once a day per town. The stamp is the world-day itself, not the visit's
# last_visited: a visit is re-stamped by walking out of the gate and back, a
# day is not. An old save's once-a-visit stamps ("gambled") are not read.
static func can_gamble(party, world, s) -> bool:
	return int(party.downtime.get("gambled_day", {}).get(s.id, -1)) != world_day(world)

# The line for a table that will not have the company again today; "" when a
# game is on. The screen puts it under the row, where a result would go.
static func gamble_refusal(party, world, s) -> String:
	if can_gamble(party, world, s):
		return ""
	return "Played here today. The tables open to the company again tomorrow."

# The payout for a face of the die at a bonus: GAMBLE_MULT's key, or "" for a
# loss. The whole table in one place, so the EV the header quotes and the test
# enumerates is the rule the game rolls.
static func gamble_tier(nat: int, bonus: int) -> String:
	if nat == 1:
		return ""
	if nat == 20:
		return "nat20"
	if nat + bonus >= GAMBLE_BIG:
		return "big"
	if nat + bonus >= GAMBLE_DC:
		return "even"
	return ""

# What comes back per 1 ◉ staked at `bonus`, averaged over the twenty faces.
static func gamble_ev(bonus: int) -> float:
	var total := 0.0
	for nat in range(1, 21):
		var tier := gamble_tier(nat, bonus)
		total += float(GAMBLE_MULT.get(tier, 0.0))
	return total / 20.0

# No days — an evening. The stake is the cost; `won` is what comes back
# across the table (the purse ends stake down, `won` up). Seeded off the town
# and the day, so a reload replays the same evening.
static func gamble(party, world, s, stake: int, rng = null) -> Dictionary:
	var who := best_of(party, GAMBLE_SKILLS)
	if who.is_empty() or stake <= 0 or not can_gamble(party, world, s) or not party.spend_gold(stake):
		return {}
	var day := world_day(world)
	var gambled: Dictionary = party.downtime.get("gambled_day", {})
	gambled[s.id] = day
	party.downtime["gambled_day"] = gambled
	var ch = party.get_member(who["char_id"])
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("gamble|%s|%d" % [s.id, day]))))
	var skill := String(who["skill"])
	var bonus := int(who["bonus"])
	var nat: int = int(Dice.d20(rng)["nat"])
	var tier := gamble_tier(nat, bonus)
	var mult := float(GAMBLE_MULT.get(tier, 0.0))
	if tier == "nat20":
		Ach.bump("trebles")
	var won := int(round(stake * mult))
	party.add_gold(won)
	var roll := "%s %d+%d vs DC %d" % [_skill_name(skill), nat, bonus, GAMBLE_DC]
	var line: String
	if tier == "nat20":
		line = "%s reads the table (%s), and the table does not see it coming. The stake comes back threefold: +%d ◉." % [
			ch.cname, roll, won - stake]
	elif tier == "big":
		line = "%s reads the table well (%s, against %d for the big pot). The stake comes back half again: +%d ◉." % [
			ch.cname, roll, GAMBLE_BIG, won - stake]
	elif tier == "even":
		line = "%s holds their own (%s). The stake comes back, and nothing with it." % [ch.cname, roll]
	elif nat == 1:
		line = "%s is caught with a card up the sleeve, or near enough (%s) — the stake is gone, and so is the room's goodwill: -%d ◉." % [
			ch.cname, roll, stake]
	else:
		line = "%s loses the thread of it (%s) — the stake is gone: -%d ◉." % [ch.cname, roll, stake]
	return {"ok": mult > 0.0, "nat": nat, "bonus": bonus, "dc": GAMBLE_DC, "char_id": ch.id, "stake": stake,
		"cname": ch.cname, "skill": skill,
		"mult": mult, "won": won, "complication": "insult" if nat == 1 else "", "text": line}

# --- crafting ---------------------------------------------------------------

# The alchemist brews what is on the shelf today (anyone can — the alchemist
# supervises); the librarian scribes their own scrolls to order, shelf or no
# shelf, for a party that has a caster to hold the pen — the two that are a
# scroll of something, not the generic priced by a rarity it does not have.
static func brewable(s, m: Dictionary) -> Array:
	if not Visit.has_service(s, "alchemist"):
		return []
	var potions: Array = Campaign.potion_ids()
	var out: Array = []
	for e in m.get("stock", []):
		if String(e["item_id"]) in potions:
			out.append(String(e["item_id"]))
	return out

static func scribable(s, _m: Dictionary, party) -> Array:
	if not Visit.has_service(s, "librarian"):
		return []
	for ch in party.party_characters():
		if not ch.sheet().spellcasting.is_empty():
			return Campaign.SCROLL_IDS.filter(func(id): return String(Campaign.item_data(id).get("rarity", "")) != "varies")
	return []

static func craft_cost(item_id: String) -> int:
	return maxi(1, int(round(Campaign.item_price(item_id) * CRAFT_RATE)))

# Once per item per visit — the stamp is the visit's, as gamble's is.
static func can_craft(party, s, item_id: String) -> bool:
	return not is_equal_approx(float(party.downtime.get("crafted", {}).get(s.id, {}).get(item_id, -2.0)), s.last_visited)

# Half list price, a day, into the stash identified. Once per item per visit.
static func craft(party, world, s, item_id: String, m: Dictionary) -> Dictionary:
	var brew := item_id in brewable(s, m)
	if not brew and not item_id in scribable(s, m, party):
		return {}
	if not can_craft(party, s, item_id):
		return {}
	var crafted: Dictionary = party.downtime.get("crafted", {})
	var here: Dictionary = crafted.get(s.id, {})
	var cost := craft_cost(item_id)
	var bed := bed_cost(s, CRAFT_DAYS, party)
	if party.gold < cost + bed:
		return {"ok": false, "cost": cost, "bed": bed,
			"text": "The %s is %d ◉ for the day, and the bed %d more." % ["bench" if brew else "desk", cost, bed]}
	party.spend_gold(cost)
	spend_days(party, world, s, CRAFT_DAYS)
	party.stash_add(item_id, 1, true)
	Campaign._note_rarity(item_id)
	here[item_id] = s.last_visited
	crafted[s.id] = here
	party.downtime["crafted"] = crafted
	var name := Campaign.item_name(item_id)
	return {"ok": true, "item_id": item_id, "name": name, "cost": cost, "bed": bed, "days": CRAFT_DAYS,
		"text": "A day at the %s, and %s goes into the pack (-%d ◉).  %s" % [
			"bench" if brew else "desk", name, cost, bed_line(s, CRAFT_DAYS, party)]}

# --- the pit ----------------------------------------------------------------

static func _week(world) -> int:
	return int(world.clock.elapsed / PIT_WEEK)

# Three named champions, seeded off the city and the week — the same three
# all week, a new three next week. Which monster stands under the name is the
# roster's business (pit_spec), not the bracket's.
static func pit_bracket(s, world) -> Dictionary:
	var week := _week(world)
	return {"week": week, "names": _names(s, week)}

static func _names(s, week: int) -> Array:
	var names: Array = []
	for i in PIT_BOUTS:
		var key := "pit|%s|%d|%d" % [s.id, week, i]
		var n := EnemyNames.name_for(s.faction, key)
		var k := 0
		while n in names:   # a bracket of "Ash, Ash and Corr" reads like a bug
			k += 1
			n = EnemyNames.name_for(s.faction, "%s|%d" % [key, k])
		names.append(n)
	return names

# `beaten` is the next bout to fight while the bracket is open: 0..2; 3 when
# the bracket is done; -1 when a loss closed it. A new week is a new bracket.
static func pit_state(party, s, world) -> Dictionary:
	var week := _week(world)
	var e: Dictionary = party.downtime.get("pit", {}).get(s.id, {})
	var beaten: int = int(e.get("beaten", 0)) if int(e.get("week", -1)) == week else 0
	return {"week": week, "beaten": beaten, "open": beaten >= 0 and beaten < PIT_BOUTS}

# Who may stand in the pit: the marching company's own, alive and on their
# feet (hp_current 0 is down; -1 is full). The bench is not at the inn's
# table, and a hero carried out of the last bout at 1 HP may go again — that
# is the player's call to make, not the pit's.
static func pit_fighters(party) -> Array:
	return party.party_characters().filter(func(ch): return not ch.dead and int(ch.hp_current) != 0)

# The champion for a hero of `level`: worth `ratio` of the ruler's average
# hero at that level (Regions.ref_score is the preset trio; a third of it is
# one of them), found by Scaler.duel_for. By the level and not by the hero:
# the house prices a bout the way it would price anyone of that standing, and
# does not know who is good in a duel. Priced by the hero's own reading of
# power.gd, a cleric met a champion sized to every spell on their sheet and
# lost nearly every bout from level 5, while a fighter won nearly every one
# (tests/sweep_pit.gd, the first grid) — the ruler reads a party's caster,
# not a duellist. Priced by level, who goes in is the company's edge to find.
static func pit_champion(level: int, ratio: float) -> Dictionary:
	return Scaler.duel_for(ratio * Regions.ref_score(level) / RULER_HEROES, PIT_POOL)

const RULER_HEROES := 3.0   # Regions.ref_score reads core/presets.gd's three

# One champion against one hero (#236): priced for `fighter`'s level
# (pit_champion at the bout's PIT_RATIO), named for the bracket, on the
# square. `duel` names the hero; the screen fields that hero and nobody else
# (pit_line_up). Encounter.build reads `named` and puts the name on the card.
# {} with nobody to stand.
static func pit_spec(_party, s, world, bout: int, fighter) -> Dictionary:
	if fighter == null:
		return {}
	var b := clampi(bout, 0, PIT_BOUTS - 1)
	var champ: Dictionary = pit_champion(fighter.level(), PIT_RATIO[b])
	if champ.is_empty():
		return {}
	return {"monsters": [champ], "theme": PIT_THEME, "duel": String(fighter.id),
		"named": {String(champ["id"]): pit_bracket(s, world)["names"][b]}}

# The bout's marching order: the one hero, and nobody else. Everything a fight
# reads the company through — the board's starts (Party.to_combatants), what
# the fight writes back, who its XP is split among (Campaign.split_xp), whose
# traits it can earn (Traits.after_fight) — reads party.active, so a hero
# standing alone there is alone in all of them. Returns the order to put back
# with pit_stand_down, which the screen does as soon as the bout is banked.
# Nothing saves mid-fight (world.gd's _autosave never runs under one), so the
# one-hero order never reaches a save.
static func pit_line_up(party, char_id: String) -> Array:
	var order: Array = Array(party.active).duplicate()
	if party.get_member(char_id) != null:
		party.active.clear()
		party.active.append(char_id)
	return order

# The order as it was, less anyone the bout killed: the dead are benched
# (core/fallen.gd), and a hero who died standing alone is no exception.
static func pit_stand_down(party, order: Array) -> void:
	party.active.clear()
	for id in order:
		var ch = party.get_member(String(id))
		if ch != null and not ch.dead:
			party.active.append(String(id))

const ORDINAL := ["first", "second", "third"]

# A win: the bout's purse, a deed with the city's people, the next bout opens;
# the third is the bracket. A loss: the hero is carried out (the screen
# stands the bout's downed up after a lost bout, Party.revive_downed), the house keeps the purse of that bout
# (to zero), and the bracket is closed until next week. `purse` is signed.
# `week` is the bracket's, read before the bout: the fight itself moves the
# clock, and a bout begun on the week's last evening is still that week's.
# `who` is the hero who stood (#236), for the line; "" says "the company".
static func pit_result(party, s, world, bout: int, won: bool, week: int, who := "") -> Dictionary:
	var b := clampi(bout, 0, PIT_BOUTS - 1)
	var name: String = _names(s, week)[b]
	var purse: int = PIT_PURSE[b]
	var beaten: int
	var text: String
	if won:
		party.add_gold(purse)
		Ladder.deed(s.faction)
		beaten = b + 1
		if beaten >= PIT_BOUTS:
			Ach.bump("pit_brackets")
			text = "%s goes down, and the bracket with them: %s, champion%s of the pit this week. The purse is %d ◉." % [
				name, who if who != "" else "the company", "" if who != "" else "s", purse]
		else:
			text = "%s goes down in the %s bout%s. The purse is %d ◉, and the %s will remember the name." % [
				name, ORDINAL[b], (" to " + who) if who != "" else "", purse, Ladder.people(s.faction)]
	else:
		# The coin that moved, not the nominal stake: a purse lighter than the
		# stake gives up what it has, and the line says so. It used to print the
		# signed stake ("keeps its stake: -40 ◉") whatever the party held.
		var taken: int = clampi(purse, 0, party.gold)
		party.add_gold(-taken)
		beaten = -1
		var kept := ("its stake: %d ◉" % taken) if taken == purse \
			else ("all the company had: %d ◉ of a %d ◉ stake" % [taken, purse]) if taken > 0 \
			else "nothing: the company had no coin to lose"
		purse = -taken
		text = "%s is still standing when %s is carried out. The house keeps %s, and the bracket is closed for the week." % [
			name, who if who != "" else "the company", kept]
	var pit: Dictionary = party.downtime.get("pit", {})
	pit[s.id] = {"week": week, "beaten": beaten}
	party.downtime["pit"] = pit
	return {"text": text, "purse": purse, "won": won, "beaten": beaten}

# --- complications ----------------------------------------------------------

const COMPLICATION_TITLE := {"tab": "The tab", "brawl": "A brawl", "insult": "An insult", "bad_lead": "A bad lead"}
const COMPLICATION_LINE := {
	"tab": "The morning brings a bill nobody remembers running up.",
	"brawl": "Somebody's cousin takes exception to the company.",
	"insult": "Something was said that should not have been, and it was heard.",
}

# The card, pure: one line and one consequence, which the screen applies
# (gold and opinion directly, `fight` as a brawl at the inn, `lead` shown as
# a rumour bought for nothing that goes nowhere). `cost` is the activity's —
# the tab is twice it. Art: event-<id>.
static func complication(kind: String, s, cost: int) -> Dictionary:
	if not kind in COMPLICATIONS:
		return {}
	var out := {"id": "downtime-%s" % kind.replace("_", "-"), "title": COMPLICATION_TITLE[kind], "kind": "bad",
		"text": String(COMPLICATION_LINE.get(kind, ""))}
	match kind:
		"tab":
			out["gold"] = -TAB_MULT * cost
			out["text"] += "  %d ◉, and the innkeeper has the tally." % (TAB_MULT * cost)
		"brawl":
			out["fight"] = true
			out["text"] += "  The cousin has friends."
		"insult":
			out["opinion"] = -INSULT
			out["text"] += "  The %s will hear of it: opinion %d." % [Ladder.people(s.faction), -int(INSULT)]
		"bad_lead":
			out["lead"] = Rumors.dud(s)
			out["text"] = String(out["lead"]["text"])
	return out

# --- the save -----------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.downtime.duplicate(true)

# JSON hands every number back as a float; the pit's counters and the game's
# days are compared as ints, the visit stamps as the floats they are. Only the keys the file
# has are written, so an old save (or an empty one) loads as a fresh party.
static func from_dict(party, d) -> void:
	party.downtime = {}
	if not d is Dictionary:
		return
	if d.get("trained") is Array:
		party.downtime["trained"] = Array(d["trained"]).map(func(id): return String(id))
	# "gambled" was the once-a-visit stamp (before 2026-09-24); a visit stamp
	# says nothing about which day it was, so an old save simply has no game
	# played today anywhere.
	if d.get("gambled_day") is Dictionary:
		var g := {}
		for k in d["gambled_day"]:
			g[String(k)] = int(d["gambled_day"][k])
		party.downtime["gambled_day"] = g
	if d.get("crafted") is Dictionary:
		var c := {}
		for sid in d["crafted"]:
			var here := {}
			if d["crafted"][sid] is Dictionary:
				for item in d["crafted"][sid]:
					here[String(item)] = float(d["crafted"][sid][item])
			c[String(sid)] = here
		party.downtime["crafted"] = c
	if d.get("pit") is Dictionary:
		var p := {}
		for sid in d["pit"]:
			var e = d["pit"][sid]
			if e is Dictionary:
				p[String(sid)] = {"week": int(e.get("week", 0)), "beaten": int(e.get("beaten", 0))}
		party.downtime["pit"] = p

# Downtime — what a company does in town when it is not working. A town today
# is a market, a board, a bed and four one-shot rows, and every one of them
# takes a moment; nothing in a town takes DAYS, so the clocks the road built (a
# raid due in two days, a lair's window, a calling's road) never trade against
# anything. These are the things that take days, from the table 5e keeps for
# exactly this question:
#
#   Downtime.train(party, world, s, ch, "sentinel")   # a feat, five days, once per hero
#   Downtime.carouse(party, world, s)                 # a night on the town: a contact, a lead, or a story
#   Downtime.gamble(party, s, 50)                     # a stake and a roll; an evening, once a visit
#   Downtime.craft(party, world, s, "potion-of-speed", m)   # the alchemist's bench / the librarian's desk
#   Downtime.pit_bracket(s, world) / pit_spec / pit_result  # a city's three champions, once a week
#
# Static, in settlement_visit.gd's row shape — every activity returns {ok,
# nat, bonus, dc, text, ...} and the screen shows it the way it shows
# work_healer(): a line under the row, and a card when there is a
# complication. State lives on party.downtime (saved beside callings):
#   {"trained": [char_id], "gambled": {s.id: last_visited},
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

const DAY := 1440.0   # world-minutes

# A feat is a level's worth; five days is two raid clocks.
const TRAIN_COST_BASE := 150
const TRAIN_COST_PER_LEVEL := 50
const TRAIN_DAYS := 5
const TRAIN_MIN_LEVEL := 4
const TRAIN_CATEGORY := "general"
# A night at the inn, and the drinks. The road's DC; half a job's opinion.
const CAROUSE_COST := {"city": 30, "town": 20, "camp": 10}
const CAROUSE_DC := 13
const CAROUSE_CONTACT := 5.0
const CAROUSE_COIN := 15
const CAROUSE_SKILLS := ["persuasion", "performance"]
# A coin flip with skill; a potion to a magic item.
const GAMBLE_DC := 12
const GAMBLE_STAKES := [25, 50, 100, 200]
const GAMBLE_SKILLS := ["insight", "deception", "sleightofhand"]
# Half price for a day.
const CRAFT_RATE := 0.5
const CRAFT_DAYS := 1
# A job, two jobs, a rare item's tenth; each bout harder than a road fight
# (one champion, pumped: core/scaler.gd's mult).
const PIT_PURSE := [60, 120, 240]
const PIT_MULT := [1.3, 1.7, 2.2]
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
static func spend_days(party, world, s, days: int) -> int:
	var bed := bed_cost(s, days, party)
	if days <= 0 or not party.spend_gold(bed):
		return -1
	world.clock.elapsed += days * DAY - Visit.LONG_REST_MINUTES
	Visit.rest(party, world, "long-rest")
	Ach.bump("downtime_days", days)
	return bed

# --- training -------------------------------------------------------------

static func can_train(party, ch) -> bool:
	return ch != null and ch.level() >= TRAIN_MIN_LEVEL and not ch.id in party.downtime.get("trained", [])

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
		return {"ok": false, "cost": cost, "bed": bed,
			"text": "A night on the town is %d ◉, and the bed %d more." % [cost, bed]}
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

# The game's and the bench's "once a visit" is the visit's own last_visited
# stamp. The screen re-reads the shelf mid-visit (a rest, the inn reopening
# behind a bout or a brawl) through Visit.visit(), which stamps it again;
# the stamps that were this visit's move with it, or the rows re-arm.
static func restamp(party, s, old: float, new: float) -> void:
	var g: Dictionary = party.downtime.get("gambled", {})
	if g.has(s.id) and is_equal_approx(float(g[s.id]), old):
		g[s.id] = new
	var here: Dictionary = party.downtime.get("crafted", {}).get(s.id, {})
	for item in here:
		if is_equal_approx(float(here[item]), old):
			here[item] = new

# --- gambling ---------------------------------------------------------------

# Once a visit: the stamp is the visit's own (Visit.visit() writes it), the
# way steal() seeds off it. Approx: a stamp and the settlement's both cross
# the save as JSON floats, and JSON keeps fewer digits than a float has.
static func can_gamble(party, s) -> bool:
	return not is_equal_approx(float(party.downtime.get("gambled", {}).get(s.id, -2.0)), s.last_visited)

# No days — an evening. The stake is the cost; `won` is what comes back
# across the table (the purse ends stake down, `won` up).
static func gamble(party, s, stake: int, rng = null) -> Dictionary:
	var who := best_of(party, GAMBLE_SKILLS)
	if who.is_empty() or stake <= 0 or not can_gamble(party, s) or not party.spend_gold(stake):
		return {}
	var gambled: Dictionary = party.downtime.get("gambled", {})
	gambled[s.id] = s.last_visited
	party.downtime["gambled"] = gambled
	var ch = party.get_member(who["char_id"])
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("gamble|%s|%d" % [s.id, int(s.last_visited)]))))
	var skill := String(who["skill"])
	var bonus := int(who["bonus"])
	var nat: int = int(Dice.d20(rng)["nat"])
	var total := nat + bonus
	var mult := 0.0
	var how := ""
	if nat == 20:
		mult = 3.0
		how = "threefold"
		Ach.bump("trebles")
	elif nat != 1 and total >= GAMBLE_DC + 5:
		mult = 2.0
		how = "doubled"
	elif nat != 1 and total >= GAMBLE_DC:
		mult = 1.5
		how = "half again"
	var won := int(round(stake * mult))
	party.add_gold(won)
	var roll := "%s %d+%d vs DC %d" % [_skill_name(skill), nat, bonus, GAMBLE_DC]
	var line: String
	if mult > 0.0:
		line = "%s reads the table (%s) — the stake comes back %s: +%d ◉." % [ch.cname, roll, how, won - stake]
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

# The screen's ordinary encounter_spec for the city, cut down to one foe: the
# strongest humanoid on that roster (the strongest of whatever came, when
# nothing on it is people), alone, pumped for the bout, named for the bracket.
# Encounter.build reads `named` and puts the name on the card.
static func pit_spec(_party, s, world, bout: int, base_spec: Dictionary) -> Dictionary:
	var best := {}
	var best_key := -1.0
	for e in base_spec.get("monsters", []):
		var m: Dictionary = Catalog.monster(String(e["id"]))
		var key := float(m.get("cr", 0)) + (1000.0 if String(m.get("type", "")) == "humanoid" else 0.0)
		if key > best_key:
			best_key = key
			best = e
	if best.is_empty():
		return {}
	var b := clampi(bout, 0, PIT_BOUTS - 1)
	var id := String(best["id"])
	var spec := base_spec.duplicate(true)
	spec["monsters"] = [{"id": id, "count": 1, "mult": PIT_MULT[b]}]
	spec["theme"] = PIT_THEME
	spec["named"] = {id: pit_bracket(s, world)["names"][b]}
	return spec

const ORDINAL := ["first", "second", "third"]

# A win: the bout's purse, a deed with the city's people, the next bout opens;
# the third is the bracket. A loss: the party is carried out (the screen
# revives everyone after a lost bout), the house keeps the purse of that bout
# (to zero), and the bracket is closed until next week. `purse` is signed.
# `week` is the bracket's, read before the bout: the fight itself moves the
# clock, and a bout begun on the week's last evening is still that week's.
static func pit_result(party, s, world, bout: int, won: bool, week: int) -> Dictionary:
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
			text = "%s goes down, and the bracket with them: champions of the pit, this week. The purse is %d ◉." % [name, purse]
		else:
			text = "%s goes down in the %s bout. The purse is %d ◉, and the %s will remember the name." % [
				name, ORDINAL[b], purse, Ladder.people(s.faction)]
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
		text = "%s is still standing when the company is carried out. The house keeps %s, and the bracket is closed for the week." % [
			name, kept]
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

# JSON hands every number back as a float; the pit's counters are compared
# as ints, the visit stamps as the floats they are. Only the keys the file
# has are written, so an old save (or an empty one) loads as a fresh party.
static func from_dict(party, d) -> void:
	party.downtime = {}
	if not d is Dictionary:
		return
	if d.get("trained") is Array:
		party.downtime["trained"] = Array(d["trained"]).map(func(id): return String(id))
	if d.get("gambled") is Dictionary:
		var g := {}
		for k in d["gambled"]:
			g[String(k)] = float(d["gambled"][k])
		party.downtime["gambled"] = g
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

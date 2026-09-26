# D4 — meeting a band on the road is a decision, not an event.
#
# Until now a hostile party closing to within ENCOUNTER_RADIUS dropped the
# player straight into a fight: the encounter happened TO them. That is Mount &
# Blade's blob-bumps-blob, and it is the thing the 2026-09-13 scope revision set
# out to remove. Now the clock stops and the party picks how to meet them.
#
#   var opts := Approach.options(party, foe)        # what can be tried, and at what DC
#   var out := Approach.resolve(party, foe, "ambush")
#   if out["fight"]: world.gd launches the fight with out's surprise flags
#
# Four ways, and they are a real spread rather than four flavours of "fight":
#
#   engage   no roll, no edge, no risk of a worse one. The baseline.
#   ambush   a gamble for the biggest prize in 5e, the first round. Pass and the
#            party gets the drop; FAIL AND THEY DO. Without that downside ambush
#            would strictly dominate engage and there would be no decision here.
#   avoid    no fight at all, which also means no XP and no loot — that is the
#            cost, and it is why avoiding everything is a choice rather than an
#            exploit. Fail and they catch the party mid-slip, badly.
#   parley   talk past it. Anything that wants something can be offered it —
#            bandits most of all — and the toll is the price of the fight not
#            happening. The mindless are the exception; see MINDLESS below.
#            Fail and it is the fight anyway, and a people that keeps an opinion
#            (WorldAI.CIVILIZED) thinks less of the company for the offer
#            (FactionOpinion.PARLEY_REFUSED; the design audit §3.1). A people
#            that keeps none — bandits, goblins, most of what talks on the road
#            — has nothing to think less with, so it takes the first round
#            instead: they come in while the company is still talking. The
#            same surprise a blown ambush hands over (`forced_ambush`), so a
#            failed parley is never a free roll before Engage (the owner's
#            call on the audit's §3.1 follow-up, 2026-09-25).
#            An empty purse does not make the toll free: they take one thing
#            from the packs instead (toll_item(), seeded, never quest goods;
#            the audit §1.8).
#
# Every one of them runs on machinery that already exists: the surprise flags
# are scenes/main.tscn's own `scouted_ahead`/`forced_ambush` (T39), the skill
# rolls are the same "name the check, name the roll" shape as world_lairs.search
# and world_camp.watch_check, and the standing orders from D3 (core/travel.gd)
# decide who rolls and at what bonus. Nothing new is invented; it is wiring.
#
# #232 (the owner's call, 2026-09-26): a meeting on the road is not only a
# fight to be had or dodged. Four more ways, beside the ones above:
#
#   demand   the other half of a toll: a band the company plainly outclasses
#            can be made to pay to be let go (Intimidation). Fail and it is the
#            fight, plainly. Offered only against a band that has troops and
#            is DEMAND_MARGIN weaker — nobody demands tribute of their betters.
#   trade    a caravan on the road opens its packs: a few things for sale at a
#            road's markup, asked on the road event card (core/road_events.gd
#            — each thing a choice with its price, and "nothing today").
#   news     a patrol or a caravan tells what it has seen: a way on the map to
#            a place the company could not reach (a trail, shown at once), or on
#            a map without roads, the nearest hidden lair.
#   job      somebody wants a crate run to the next town: a real delivery job
#            (core/quest_posting.gd's deliver_goods), taken on the spot, paid at
#            the far gate — and the escort objective it brings to any fight on
#            the way. One road job at a time from any one town.
#
# What this does NOT own: the fight (scenes/main.tscn, unchanged), what a won
# fight pays (world.gd's _bank), or any drawing. Faction opinion only in the
# one place a way's own result moves it — a failed parley's PARLEY_REFUSED; a
# fight's opinion is the world screen's, after the fight.
extends RefCounted
const Traits = preload("res://core/traits.gd")   # #176 step 4

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Travel = preload("res://core/travel.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Ladder = preload("res://core/ladder.gd")

# The DCs. Flat, not scaled to the band: what the party is rolling against is
# noticing and being noticed, which is about ground and care rather than about
# how hard the other side hits. Ambush is the hardest because it asks to be
# unseen while closing, avoid only asks to be unseen while leaving.
const AVOID_DC := 13
const AMBUSH_DC := 15
const PARLEY_DC := 14

# Which standing order does the job, and which skill it rolls. Scout for the
# two that are about reading ground; parley is nobody's standing order, so it
# falls to whoever in the party can actually talk.
# `win` and `lose` are what the card puts on the row, and they are not flavour:
# a row that shows only what a way BUYS makes every way that rolls look better
# than the one that does not, and engage — the only way that cannot go wrong —
# reads as the option with nothing on it. The gamble is the point of this card,
# so both halves of every gamble are stated, in the same words the resolution
# will use. Engage has no `lose` because there is nothing to fail.
const WAYS := {
	"engage": {"label": "Engage", "role": "", "skills": [], "dc": 0,
		"note": "Straight at them. No edge, no surprises.",
		"win": "An even fight, full XP and loot. Nothing can go wrong first."},
	# A civilized band WorldAI.is_hostile() says is not hostile — a faction
	# patrol, most often — never had a card at all: _check_encounter() only
	# ever opened one for a hostile foe, so a friendly band on the road could
	# be stood next to and nothing happened. These two ways are the
	# friendly-band card: no roll, no risk, because there is no fight sitting
	# behind either outcome the way there is for every way above.
	"greet": {"label": "Greet them", "role": "", "skills": [], "dc": 0,
		"note": "A friendly hail. No roll, no cost.",
		"win": "A friendly word exchanged, and the road goes on."},
	"pass": {"label": "Move on", "role": "", "skills": [], "dc": 0,
		"note": "Keep going without stopping to talk.",
		"win": "The company keeps its own road; no words exchanged."},
	"ambush": {"label": "Set an ambush", "role": "scout", "skills": ["stealth", "survival"],
		"dc": AMBUSH_DC, "note": "Take the first round — or hand it to them.",
		"win": "The party takes the first round.",
		"lose": "They take the first round, and the fight happens anyway."},
	"avoid": {"label": "Slip away", "role": "scout", "skills": ["stealth"], "dc": AVOID_DC,
		"note": "No fight, and nothing to show for it.",
		"win": "No fight — and no XP, no loot, nothing.",
		"lose": "Seen mid-slip: they take the first round, and you fight strung out — get everyone to the road at the far edge, or through them."},
	"demand": {"label": "Demand tribute", "role": "", "skills": ["intimidation"], "dc": DEMAND_DC,
		"note": "They are outmatched, and they know it.",
		"win": "They pay to be let go — about %d ◉ — and there is no fight.",
		"lose": "They would rather fight than pay: a plain, even fight."},
	"trade": {"label": "Trade", "role": "", "skills": [], "dc": 0,
		"note": "See what they are carrying.",
		"win": "Their packs are opened: a few things for sale, at the road's prices."},
	"news": {"label": "Ask for news", "role": "", "skills": [], "dc": 0,
		"note": "What have they seen on the road?",
		"win": "They tell what they have seen — maybe a way the company does not know."},
	"job": {"label": "Ask for work", "role": "", "skills": [], "dc": 0,
		"note": "Anything that wants carrying?",
		"win": "A crate for %s, paid at the gate: %d ◉."},
	"parley": {"label": "Parley", "role": "", "skills": ["persuasion", "deception"],
		"dc": PARLEY_DC, "note": "Buy your way past. They will want something.",
		"win": "No fight. The toll is %d ◉, and there is no loot.",
		# A purse with nothing in it: _toll() caps at what the party actually has,
		# so the line has to stop saying "0 ◉" and say what that means.
		"win_broke": "No fight. They take what you are carrying, which is nothing.",
		# A people that keeps no opinion (bandits, goblins) cannot think less of
		# the company, so the offer costs the first round instead.
		"lose": "They take the offer as weakness, and the first round with it.",
		# An empty purse and something in the packs: they take the thing.
		"win_item": "No fight. The purse is empty, so they take the %s from the packs, and there is no loot.",
		# A people that keeps an opinion hears about the offer, and the row
		# says so before the press: the cost of a gamble belongs beside it.
		"lose_opinion": "They take the offer as an insult: a plain, even fight, and the %s think less of the company."},
}
# Order they are offered in: the safe one first, the gamble last, so the list
# reads as an escalation rather than a menu.
const ORDER := ["avoid", "parley", "ambush", "engage"]
# Demand sits after parley when it is offered: the two tolls, side by side.
const DEMAND_AFTER := "parley"
# What a non-hostile band offers instead: no gamble, nothing to roll — and,
# since #232, what they might have to offer (trade and a job need a `world`).
const FRIENDLY_ORDER := ["greet", "trade", "news", "job", "pass"]

# Demand: how much stronger the company must be (its levels against the band's)
# before the offer is on the card, the check's DC, and what the band pays, per
# level of troops. Taste numbers, spike doc §5.
const DEMAND_DC := 14
const DEMAND_MARGIN := 1.5
const TRIBUTE_PER_LEVEL := 6
# Trade: the markup on the road (a caravan is not a market), and how many
# things it has — two, and "nothing today", keeps it to a road card's three.
const CARAVAN_MARKUP := 1.25
const CARAVAN_WARES := 2

# What talking past a band costs. A share of the purse rather than a flat fee —
# a toll that is trivial at 500 gold and impossible at 30 is not a decision.
const TOLL_PCT := 0.12
const TOLL_MIN := 15


# Who can be talked to is NOT the question WorldAI.CIVILIZED answers. That list
# is ["dwarf", "elf", "human"] and it decides whose settlements open their gates
# — by it a bandit is a "monster", and a bandit wanting paid is the most
# obviously bribable thing on the map. Undead and beasts are the ones that
# cannot be offered anything.
#
# So this is its own list, and it is a deny-list: most things that raid you want
# something, so a faction talks unless it is named here. Fey and dragons very
# much negotiate — that is most of what they are for.
const MINDLESS := ["beast", "undead", "monstrosity", "elemental", "construct"]

static func can_parley(foe) -> bool:
	return not MINDLESS.has(foe.faction)

# Whether a failed parley costs this band's people anything with the company:
# only a people that keeps an opinion at all. A monster faction keeps none
# (the rule core/contracts.gd's credit() and world.gd's KILLED_THEIRS follow),
# so a bandit who will not be bought is only the fight.
static func parley_costs_opinion(foe) -> bool:
	return can_parley(foe) and not WorldAI.is_monster(String(foe.faction))


# What this party can try against this band, each with the check it would roll
# and by whom — so the card can show "Vera Kord, Stealth vs DC 13" on the button
# BEFORE it is pressed. A choice you cannot price is not a choice.
static func options(party, foe, hostile := true, world = null) -> Array:
	var out: Array = []
	if not hostile:
		for id in FRIENDLY_ORDER:
			if not _friendly_offers(id, foe, world, party):
				continue
			var w: Dictionary = WAYS[id]
			var o := {"id": id, "label": String(w["label"]), "note": String(w["note"]),
				"dc": 0, "win": String(w["win"])}
			if id == "job":
				var q := job_for(foe, world, party)
				o["win"] = String(w["win"]) % [String(q["dest"]), int(q["quest"]["reward"]["gold"])]
			out.append(o)
		return out
	var order: Array = ORDER.duplicate()
	if can_demand(party, foe):
		order.insert(order.find(DEMAND_AFTER) + 1, "demand")
	for id in order:
		if id == "parley" and not can_parley(foe):
			continue
		var w: Dictionary = WAYS[id]
		var o: Dictionary = {"id": id, "label": String(w["label"]), "note": String(w["note"]),
			"dc": int(w["dc"])}
		if not w["skills"].is_empty():
			var who := _roller(party, w)
			if who.is_empty():
				continue          # nobody can roll it: do not offer it
			var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party) + _way_term(party, String(who["id"]), id)
			o.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
				"bonus": bonus, "named": bool(who["named"]),
				"needs": needs(int(w["dc"]), bonus)}, true)
		# What it buys and what it costs, both, before the press. The toll is the
		# real number the party would actually pay — "they will want something" is
		# not a price anybody can weigh against a fight.
		if id == "parley":
			var toll: int = _toll(party)
			var item := toll_item(party, foe) if toll <= 0 else ""
			if toll > 0:
				o["win"] = String(w["win"]) % toll
			elif item != "":
				o["win"] = String(w["win_item"]) % Campaign.item_name(item)
				o["toll_item"] = item
			else:
				o["win"] = String(w["win_broke"])
		elif id == "demand":
			o["win"] = String(w["win"]) % tribute(foe)
		else:
			o["win"] = String(w.get("win", ""))
		if w.has("lose"):
			o["lose"] = String(w["lose"])
		if id == "parley" and parley_costs_opinion(foe):
			o["lose"] = String(w["lose_opinion"]) % Ladder.people(String(foe.faction))
		if id == "parley":
			o["toll"] = _toll(party)
		out.append(o)
	return out


# #176 step 4: a personality trait's term on this way of meeting them, over and
# above the skill's own (Brave's −2 on slipping away: they would rather not).
static func _way_term(party, char_id: String, way: String) -> int:
	return int(Traits.skill_term(party.get_member(char_id), way, party.here)["n"])


# The face the d20 has to come up, which is the only honest way to show odds in
# a game whose whole vocabulary is d20s. Ability checks have no natural 1/20
# rule in 5.5e, so a bonus big enough really is a certainty and a DC far enough
# out of reach really is impossible — and a card that showed "needs 23" as if it
# could happen would be lying about the only number on it that matters.
#
# 0 means it cannot fail; 21 means it cannot pass.
static func needs(dc: int, bonus: int) -> int:
	return clampi(dc - bonus, 0, 21)


# Take a way. Returns what happened and, crucially, what the fight should be if
# there is one — world.gd passes `scouted_ahead`/`forced_ambush` straight into
# the combat scene, which already knows what to do with them (T39).
#
#   {way, ok, fight, scouted_ahead, forced_ambush, text, + the roll, + toll}
static func resolve(party, foe, way: String, rng = null, world = null) -> Dictionary:
	if not WAYS.has(way):
		return {}
	var w: Dictionary = WAYS[way]
	var out: Dictionary = {"way": way, "fight": true,
		"scouted_ahead": false, "forced_ambush": false}
	if way == "engage":
		out["ok"] = true
		out["text"] = "The company goes straight at them."
		return out
	if way == "greet" or way == "pass":
		out["ok"] = true
		out["fight"] = false
		out["text"] = String(w["win"])
		return out
	if way in ["trade", "news", "job"]:
		out["ok"] = true
		out["fight"] = false
		return _friendly(party, foe, way, world, rng if rng != null else RNG.new(), out)

	var who := _roller(party, w)
	if who.is_empty():
		# Nobody to roll: the attempt is simply not made, and it is a plain
		# fight rather than a silent failure the player cannot account for.
		out["ok"] = false
		out["text"] = "Nobody here can manage that. They are on you anyway."
		return out
	if rng == null:
		rng = RNG.new()
	var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party) + _way_term(party, String(who["id"]), way)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= int(w["dc"])
	out.merge({"ok": ok, "char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
		"nat": nat, "bonus": bonus, "dc": int(w["dc"]), "named": bool(who["named"])}, true)

	match way:
		"avoid":
			out["fight"] = not ok
			out["forced_ambush"] = not ok
			out["text"] = ("%s takes them wide around it. Nobody ever knew they were there."
				% who["cname"]) if ok else (
				"%s is seen. They come in fast, and the company is strung out — the road is the far edge."
				% who["cname"])
		"ambush":
			out["scouted_ahead"] = ok
			out["forced_ambush"] = not ok
			out["text"] = ("%s picks the ground and the company settles in to wait."
				% who["cname"]) if ok else (
				"%s moves too early. They see it coming and turn it around."
				% who["cname"])
		"parley":
			out["fight"] = not ok
			out["forced_ambush"] = false
			if ok:
				var toll: int = _toll(party)
				party.spend_gold(toll)
				out["toll"] = toll
				var item := toll_item(party, foe) if toll <= 0 else ""
				if item != "":
					party.stash_remove(item, 1)
					out["toll_item"] = item
				var paid: String = ("%d ◉" % toll) if toll > 0 else (
					"the %s out of the packs, since the purse was empty" % Campaign.item_name(item) if item != ""
					else "nothing, since the purse was empty")
				out["text"] = "%s talks them down. They take %s to have seen nobody." % [who["cname"], paid]
			elif parley_costs_opinion(foe):
				var faction := String(foe.faction)
				FactionOpinion.lower(faction, FactionOpinion.PARLEY_REFUSED)
				out["opinion"] = -FactionOpinion.PARLEY_REFUSED
				out["text"] = "%s makes the offer, and it is taken as an insult. It comes to a fight anyway, and the %s will hear that the company tried to buy them." % [
					who["cname"], Ladder.people(faction)]
			else:
				# Nobody to think less of the company, so the offer costs the
				# first round: the same surprise a blown ambush hands over.
				out["forced_ambush"] = true
				out["text"] = "%s gets nowhere. They were never going to be talked to, and they come in while the company is still talking." % who["cname"]
		"demand":
			out["fight"] = not ok
			out["forced_ambush"] = false
			if ok:
				var paid: int = tribute(foe)
				party.add_gold(paid)
				out["tribute"] = paid
				out["text"] = "%s tells them what happens next if they do not pay. They pay, %d ◉ of it, and are gone." % [who["cname"], paid]
			else:
				out["text"] = "%s makes the demand. They look at each other, and at the company, and decide to find out." % who["cname"]
	return out

# --- #232: the ways a meeting can go without a fight -------------------------

# The company's levels against the band's: demand is only on the card against a
# band that has troops and is DEMAND_MARGIN weaker, and that can be talked to.
static func can_demand(party, foe) -> bool:
	if not can_parley(foe) or foe.troops.is_empty():
		return false
	var theirs := 0
	for t in foe.troops:
		theirs += int(t.get("level", 1))
	var ours := 0
	for ch in party.party_characters():
		if not ch.dead:
			ours += ch.level()
	return float(ours) >= float(theirs) * DEMAND_MARGIN

static func tribute(foe) -> int:
	var lv := 0
	for t in foe.troops:
		lv += int(t.get("level", 1))
	return maxi(TRIBUTE_PER_LEVEL, lv * TRIBUTE_PER_LEVEL)

# Which of the friendly ways this band has to offer. A caravan trades; anybody
# who walks the roads has news; work needs a town to run it to.
static func _friendly_offers(id: String, foe, world, party) -> bool:
	match id:
		"trade":
			return world != null and String(foe.ai.get("source", "")) == "caravan"
		"news":
			return world != null
		"job":
			return world != null and not job_for(foe, world, party).is_empty()
	return true

# The crate run a band on the road wants done: from the town nearest it to the
# nearest other civilized town (QuestPosting.deliver_offer), priced as the board
# prices it. {} when there is no such run, or the company already has it.
# {quest, dest} otherwise.
static func job_for(foe, world, party) -> Dictionary:
	if world == null:
		return {}
	var QuestPosting = load("res://core/quest_posting.gd")   # load: it preloads this file's neighbours
	var Quest = load("res://core/quest.gd")
	var home = null
	var best := INF
	for s in world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		var d: float = s.position.distance_to(foe.position)
		if d < best:
			best = d
			home = s
	if home == null:
		return {}
	var q: Dictionary = QuestPosting.deliver_offer(home, world)
	if q.is_empty() or not Quest.get_quest(party, String(q["id"])).is_empty():
		return {}
	var dest := ""
	for s in world.settlements:
		if s.id == String(q["target_settlement_id"]):
			dest = s.sname
	return {"quest": q, "dest": dest}

static func _friendly(party, foe, way: String, world, rng, out: Dictionary) -> Dictionary:
	match way:
		"trade":
			out["wares"] = wares(foe, rng)
			out["text"] = "They set down their packs and open them."
		"news":
			var e := {}
			# load: core/landmarks.gd preloads this file, and the road's chain
			# (road_events -> route_travel -> world_routes) preloads landmarks.
			load("res://core/road_events.gd").apply({"trail": {"known": true}}, party, world, rng, e)
			if e.has("trail") and String(e["trail"]) != "":
				out["trail"] = e["trail"]
				out["text"] = "They have come by a way that is on no map: to %s. They show the company where it leaves the road." % e["trail"]
			elif e.has("lair"):
				out["lair"] = e["lair"]
				out["text"] = "They have seen something moving out past the road: %s. It is on the map now." % e["lair"]
			else:
				out["text"] = "Nothing the company does not already know."
		"job":
			var j := job_for(foe, world, party)
			if j.is_empty():
				out["text"] = "They have nothing that wants carrying."
			else:
				var Quest = load("res://core/quest.gd")
				Quest.accept(party, j["quest"], world.clock.elapsed)
				out["quest"] = String(j["quest"]["title"])
				out["text"] = "A crate for %s, and a name to give at the gate. It is in the quest log." % j["dest"]
	return out

# What a caravan has for sale, as a road event the choice card can ask:
# CARAVAN_WARES things at the road's markup, and "nothing today". Seeded off
# the band, so a reload shows the same packs.
const STOCK := ["potions-of-healing", "dagger", "handaxe", "spear", "shortsword", "light-crossbow",
	"leather", "studded-leather", "chain-shirt"]
static func wares(foe, _rng = null) -> Dictionary:
	var pick := RNG.new(maxi(1, absi(hash("wares|%s" % foe.id))))
	var pool: Array = STOCK.duplicate()
	var choices: Array = []
	for i in CARAVAN_WARES:
		if pool.is_empty():
			break
		var item: String = pool.pop_at(pick.roll_die(pool.size()) - 1)
		var price: int = maxi(1, int(round(Campaign.item_price(item) * CARAVAN_MARKUP)))
		choices.append({"id": "buy-%s" % item, "label": "Buy the %s" % Campaign.item_name(item).to_lower(),
			"cost": {"gold": price},
			"then": {"text": "Coin changes hands, and the %s changes packs." % Campaign.item_name(item).to_lower(), "item": item}})
	choices.append({"id": "nothing", "label": "Nothing today",
		"then": {"text": "The packs are tied up again, and the road goes on."}})
	return {"id": "caravan-wares", "title": "A caravan's packs",
		"text": "Bolts of cloth, a keg, and under them the things a road actually wants.",
		"choices": choices}


# A share of what the party is carrying, floored so it is never pocket change.
# Capped at the purse: a band cannot take gold the party does not have, and the
# alternative to paying was a fight they just avoided.
static func _toll(party) -> int:
	return mini(party.gold, maxi(TOLL_MIN, int(round(party.gold * TOLL_PCT))))


# What a band takes when the purse is empty: one thing out of the packs, not
# nothing (the design audit §1.8 — banking every coin in the strongroom made
# the toll free). Never quest goods: an item an open job is collecting or
# supplying stays in the pack, or talking past a band could quietly undo a
# contract. Seeded off the band and the world-minute, so the card can name the
# thing before the press and the resolution takes that same thing; a reload
# does not reroll it. "" when there is nothing they would take.
static func toll_item(party, foe) -> String:
	var keep := {}
	for q in party.quests:
		if String(q.get("state", "")) in ["active", "complete"] and q.has("target_item_id"):
			keep[String(q["target_item_id"])] = true
	var ids: Array = []
	for e in party.stash:
		var id := String(e["item_id"])
		if not keep.has(id) and not ids.has(id) and int(e.get("quantity", 0)) > 0:
			ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	var h := absi(hash("toll|%s|%d" % [String(foe.id), int(party.world_now)]))
	return String(ids[h % ids.size()])


# Who rolls: the standing order for the job if one is set (D3), otherwise the
# party's best at it. `named` says which, so the card can credit the player's
# own order — the same feedback loop core/travel.gd runs on.
static func _roller(party, w: Dictionary) -> Dictionary:
	var c = Campaign.new(party)
	var role := String(w.get("role", ""))
	var ordered := String(Travel.orders(party).get(role, "")) if role != "" else ""
	var best_id := ""
	var best_skill := ""
	var best_bonus := -99
	for skill in w["skills"]:
		if ordered != "":
			var ob: int = c.skill_bonus(ordered, String(skill))
			if ob > best_bonus:
				best_bonus = ob
				best_id = ordered
				best_skill = String(skill)
			continue
		var id: String = c.best_at(String(skill))
		if id == "":
			continue
		var b: int = c.skill_bonus(id, String(skill))
		if b > best_bonus:
			best_bonus = b
			best_id = id
			best_skill = String(skill)
	if best_id == "":
		return {}
	var ch = party.get_member(best_id)
	return {"id": best_id, "cname": ch.cname if ch != null else "Someone",
		"skill": best_skill, "bonus": best_bonus, "named": best_id == ordered and ordered != ""}

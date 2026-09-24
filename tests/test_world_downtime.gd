# Downtime on the world screen: the inn's Downtime section (train, a night on
# the town, a game, the pit), the counters' Brew and Scribe rows, the
# complication card and the brawl behind one, and a bout in the pit with the
# champion's name on the first foe.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_downtime.gd
extends SceneTree

const Downtime = preload("res://core/downtime.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Leveling = preload("res://core/leveling.gd")
const Campaign = preload("res://core/campaign.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Quest = preload("res://core/quest.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(buttons(c))
	return out

func button_named(node: Node, text: String):
	for b in buttons(node):
		if text in String(b.text):
			return b
	return null

func buttons_named(node: Node, text: String) -> Array:
	return buttons(node).filter(func(b): return String(b.text) == text)

# The fight is driven to its outcome by hand, the way test_world_objectives does.
func _finish(main, result: Dictionary) -> void:
	main._combat.result = result
	for i in 8:
		await process_frame

# A visit stamp whose seeded night on the town fails the roll and draws
# `want` as the story — searched, not guessed, the way test_downtime's _rng is.
# The seed takes the clock too (each night of a stay is its own roll), and the
# night moves it by a day before the die is thrown.
# `want` "contact" is a night that passes (not a 20: one card, not a round too).
# How far opinion may drift back toward 0 on its own since `since`: a night
# at the inn runs the world clock now (core/world_rest.gd), and FactionOpinion
# decays DECAY_PER_DAY a day while it does. Well under an insult or a service.
func _drift(w, since: float) -> float:
	return FactionOpinion.DECAY_PER_DAY * maxf(0.0, w.clock.elapsed - since) / FactionOpinion.DAY + 0.001

func _stamp_for(s, party, want: String, world) -> int:
	var bonus := int(Downtime.best_of(party, Downtime.CAROUSE_SKILLS)["bonus"])
	var clock := int(world.clock.elapsed + Downtime.DAY)
	for t in range(1, 200000):
		var r = RNG.new(maxi(1, absi(hash("carouse|%s|%d|%d" % [s.id, t, clock]))))
		var nat := int(Dice.d20(r)["nat"])
		var passes: bool = nat != 1 and (nat == 20 or nat + bonus >= Downtime.CAROUSE_DC)
		if want == "contact":
			if passes and nat != 20:
				return t
			continue
		if nat == 1 or passes:
			continue
		if Downtime.COMPLICATIONS[r.roll_die(Downtime.COMPLICATIONS.size()) - 1] == want:
			return t
	return -1

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	Ladder.reset()
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var party = main.party
	var city = w.settlements[0]          # Riverhold, human city: an inn, an alchemist, a librarian, a pit
	# A long rest runs the world clock for its eight hours (core/world_rest.gd),
	# and a lair left alone that long raids the nearest town and halves its
	# market, the alchemist's potions with it. That is Raids' test, not this
	# one: keep every lair at home while the inn's nights pass.
	for l in w.lairs:
		l.raid_at = 1e9
	w.clock.pause()
	party.gold = 5000
	var hero = party.party_characters()[0]
	Leveling.grant_levels(hero, 4)
	main._open_visit(city)
	main._goto_page("inn")
	await process_frame
	check(said(main, "Downtime"), "the inn has a Downtime section")
	check(said(main, "Train %s in a feat (%d ◉, five days)" % [hero.cname, Downtime.train_cost(hero)]), "the trainer's row names the hero and the fee")
	check(said(main, "A night on the town (%d ◉)" % Downtime.CAROUSE_COST["city"]), "the night on the town")
	check(said(main, "Sit in on a game"), "the game")
	var names: Array = Downtime.pit_bracket(city, w)["names"]
	check(said(main, "The pit: %s, %s and %s stand this week (purse %d ◉)." % [names[0], names[1], names[2], Downtime.PIT_PURSE[0]]), "the pit's three, at a city")
	check(buttons_named(main, "Go").size() == 2, "a Go for the trainer and one for the game (%d)" % buttons_named(main, "Go").size())

	# --- train: the feat on the sheet, five days gone, the fee and the bed paid ---
	var gold_before: int = party.gold
	var clock_before: float = w.clock.elapsed
	var fee: int = Downtime.train_cost(hero) + Downtime.bed_cost(city, Downtime.TRAIN_DAYS)
	var feat: String = Downtime.trainable(hero)[0]
	buttons_named(main, "Go")[0].pressed.emit()
	await process_frame
	check(feat in hero.feats, "the first feat on the list is on the sheet")
	check(party.gold == gold_before - fee, "the fee and five nights' bed are paid (%d)" % (gold_before - party.gold))
	check(is_equal_approx(w.clock.elapsed, clock_before + Downtime.TRAIN_DAYS * Downtime.DAY), "five days passed")
	check("Five days with a master-at-arms" in String(main._visit.get("log", "")), "the row says so: %s" % main._visit.get("log", ""))
	check(not main._visit.is_empty() and main._visit_page == "inn", "...without leaving the inn")
	check(buttons_named(main, "Go").size() == 1, "once: the trainer's row is gone, the game's stays")
	check(main._event_card != null and String(main._event_card._e.get("id", "")) == "downtime-train"
		and String(main._event_card._e.get("title", "")) == "Schooled" and String(main._event_card._e.get("art", "")) == "event-downtime-train",
		"...and Schooled is a card: %s" % (main._event_card._e.get("id", "") if main._event_card != null else "none"))
	check(not hero.sheet().pending.any(func(pe): return (":feat:%s:" % feat) in String(pe["key"])), "the trainer decided the feat's +1")
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._event_card == null and not main._visit.is_empty() and w.clock.is_paused(), "acked: the inn is still up")

	# --- carouse, a contact: a card too -------------------------------------------
	city.last_visited = float(_stamp_for(city, party, "contact", w))
	check(city.last_visited > 0.0, "a stamp whose night passes")
	button_named(main, "Go out").pressed.emit()
	for i in 3:
		await process_frame
	check("makes friends of half the room" in String(main._visit.get("log", "")), "the contact's line: %s" % main._visit.get("log", ""))
	check(main._event_card != null and String(main._event_card._e.get("id", "")) == "downtime-carouse"
		and String(main._event_card._e.get("title", "")) == "A night on the town", "...on a card: %s" % (main._event_card._e.get("id", "") if main._event_card != null else "none"))
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._event_card == null and not main._visit.is_empty(), "acked: the inn is still up")

	# --- carouse: a line under the row; a seeded fail is a card ---------------
	city.last_visited = float(_stamp_for(city, party, "insult", w))
	check(city.last_visited > 0.0, "a stamp whose night fails and draws the insult")
	var opinion_before: float = FactionOpinion.get_opinion(city.faction)
	var opinion_clock: float = w.clock.elapsed   # the night's own drift toward 0 (core/world_rest.gd) is not the insult
	gold_before = party.gold
	button_named(main, "Go out").pressed.emit()
	for i in 3:
		await process_frame
	check("wrong sort of impression" in String(main._visit.get("log", "")), "the night's line: %s" % main._visit.get("log", ""))
	check(party.gold == gold_before - Downtime.CAROUSE_COST["city"] - Downtime.bed_cost(city, 1), "the night and the bed")
	check(main._event_card != null and String(main._event_card._e.get("id", "")) == "downtime-insult", "the story is a card: %s" % (main._event_card._e.get("id", "") if main._event_card != null else "none"))
	check(absf(FactionOpinion.get_opinion(city.faction) - (opinion_before - Downtime.INSULT)) <= _drift(w, opinion_clock),
		"...whose consequence is applied under it (less the night's drift)")
	check(w.clock.is_paused(), "the clock is paused under the card")
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._event_card == null and not main._visit.is_empty() and w.clock.is_paused(), "acked: the inn is still up, and still holds the clock")

	# --- gamble: once a day in a town ------------------------------------------
	gold_before = party.gold
	var go = buttons_named(main, "Go")[0]
	check(not go.disabled, "the game is on")
	go.pressed.emit()
	await process_frame
	check(party.gold != gold_before or String(main._visit.get("log", "")).contains("stake comes back"),
		"the stake moved the purse, or came back even (%d -> %d)" % [gold_before, party.gold])
	check("DC %d" % Downtime.GAMBLE_DC in String(main._visit.get("log", "")), "the roll is said: %s" % main._visit.get("log", ""))
	check(buttons_named(main, "Go")[0].disabled, "...and the game is over for today")
	check(said(main, Downtime.gamble_refusal(party, w, city)) and Downtime.gamble_refusal(party, w, city) != "",
		"...and the row says why: %s" % Downtime.gamble_refusal(party, w, city))
	if main._event_card != null:   # a nat 1's insult is a card too; not the point here
		main._event_card.acknowledged.emit()
		await process_frame
	# a rest re-reads the shelf (a fresh last_visited) and takes the night
	w.clock.elapsed += Visit.LONG_REST_COOLDOWN
	var stamp_before: float = city.last_visited
	main._rest()
	await process_frame
	if main._event_card != null:   # the fireside, when it has something to say
		main._event_card.acknowledged.emit()
		await process_frame
	check(city.last_visited != stamp_before, "the rest stamped the visit afresh")
	# A day on (the rest took one), the table has the company again: once a
	# day per town, and a new world-day re-arms it however the visit went.
	check(Downtime.can_gamble(party, w, city) and not buttons_named(main, "Go")[0].disabled,
		"a day later the game is on again")

	# --- brew at the alchemist, scribe at the librarian -----------------------
	main._goto_page("market")
	await process_frame
	button_named(main, "Alchemist").pressed.emit()
	await process_frame
	var brew: Array = Downtime.brewable(city, main._visit)
	check(not brew.is_empty() and said(main, "Brew %s (%d ◉, a day)" % [Campaign.item_name(brew[0]), Downtime.craft_cost(brew[0])]), "a Brew row per potion on the shelf")
	var had: int = party.stash_count(brew[0], true)
	clock_before = w.clock.elapsed
	button_named(main, "Brew").pressed.emit()
	await process_frame
	check(party.stash_count(brew[0], true) == had + 1, "brewed: one in the pack")
	check(is_equal_approx(w.clock.elapsed, clock_before + Downtime.DAY), "a day at the bench")
	check(buttons(main).any(func(b): return String(b.text) == "Done" and b.disabled), "once per item per visit: the row is spent")
	button_named(main, "Librarian").pressed.emit()
	await process_frame
	var scribe: Array = Downtime.scribable(city, main._visit, party)
	check(not scribe.is_empty() and said(main, "Scribe %s (%d ◉, a day)" % [Campaign.item_name(scribe[0]), Downtime.craft_cost(scribe[0])]), "a Scribe row per scroll of the librarian's own")
	check(not said(main, "Scribe Spell Scroll"), "...not the generic priced by rarity")

	# --- the pit: a bout is a fight with the champion's name on the first foe ---
	main._goto_page("inn")
	await process_frame
	names = Downtime.pit_bracket(city, w)["names"]   # seven days went by above: a new week, a new three
	check(said(main, "The pit: %s, %s and %s stand this week" % [names[0], names[1], names[2]]), "the row names this week's three")
	gold_before = party.gold
	var fight = button_named(main, "Fight")
	check(fight != null, "the pit row's button")
	fight.pressed.emit()
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	check(main._combat != null, "a bout is a fight")
	check(main._visit.is_empty(), "...the visit closed for it")
	var foes: Array = main._combat.cb.team_of("foe") if main._combat != null else []
	check(foes.size() == 1, "one foe in the pit (%d)" % foes.size())
	check(not foes.is_empty() and String(foes[0].cname).begins_with(names[0]), "...the first champion, by name: %s" % (foes[0].cname if not foes.is_empty() else ""))
	check(main._combat != null and main._combat.spec.get("theme", "") == Downtime.PIT_THEME, "in the square")
	var xp_before: int = hero.xp
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": ["dagger"], "kills": [], "deaths": [], "rounds": 2,
		"objective": {"kind": "", "done": false, "xp": 0}})
	check(main._event_card != null and String(main._event_card._e.get("id", "")) == "downtime-pit", "a won bout is a card")
	check(main._event_card != null and int(main._event_card._e.get("gold", 0)) == Downtime.PIT_PURSE[0], "...with the purse on it")
	check(main._event_card != null and int(main._event_card._e.get("xp", 0)) == 30, "...and the fight's XP")
	check(party.gold == gold_before + Downtime.PIT_PURSE[0] + 5, "the purse is paid, and the kill's gold banked")
	check(hero.xp > xp_before and party.stash_count("dagger") >= 1, "the bout banks what a fight banks: XP and loot")
	check(Ladder.deeds(city.faction) == 1, "and a deed with the city's people")
	main._event_card.acknowledged.emit()
	for i in 3:
		await process_frame
	check(not main._visit.is_empty() and main._visit["settlement"] == city, "acked: back at the gate")
	check(not Downtime.can_craft(party, city, brew[0]), "the inn reopened as the same visit: the bench is still spent")
	main._goto_page("inn")
	await process_frame
	check(said(main, "(purse %d ◉)" % Downtime.PIT_PURSE[1]), "the second bout's purse on the row")
	# a loss: carried out, the house keeps its stake, the bracket closes
	gold_before = party.gold
	for ch in party.party_characters():
		ch.hp_current = 1
	button_named(main, "Fight").pressed.emit()
	guard = 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	check(main._combat != null and String(main._combat.cb.team_of("foe")[0].cname).begins_with(names[1]), "the second champion")
	hero.dead = true
	hero.hp_current = 0
	await _finish(main, {"outcome": "Defeat", "xp": 0, "gold": 0, "loot": [], "kills": [], "deaths": [hero.id], "rounds": 3,
		"objective": {"kind": "", "done": false, "xp": 0}})
	check(main._event_card != null and int(main._event_card._e.get("gold", 0)) == -Downtime.PIT_PURSE[1], "a lost bout: the house keeps its stake")
	check(party.gold == gold_before - Downtime.PIT_PURSE[1], "...out of the purse")
	check(not hero.dead and hero.hp_current != 0, "carried out, not buried")
	main._event_card.acknowledged.emit()
	for i in 3:
		await process_frame
	main._goto_page("inn")
	await process_frame
	check(button_named(main, "Fight") == null and said(main, "closed"), "the bracket is closed for the week")

	# --- the brawl: the one story that is a fight, behind the card's button ---
	Quest.accept(party, {"id": "deliver:t:x", "kind": "deliver_goods", "state": "offered",
		"target_settlement_id": "x", "required": 1, "progress": 0,
		"title": "Run a crate of goods to X", "reward": {"gold": 40}})
	var deeds_before: int = Ladder.deeds(city.faction)
	opinion_before = FactionOpinion.get_opinion(city.faction)
	opinion_clock = w.clock.elapsed
	city.last_visited = float(_stamp_for(city, party, "brawl", w))
	button_named(main, "Go out").pressed.emit()
	for i in 3:
		await process_frame
	check(main._event_card != null and String(main._event_card._e.get("id", "")) == "downtime-brawl", "the cousin's card")
	check(not main._visit.is_empty(), "...over the inn, which is still up")
	main._event_card.acknowledged.emit()
	guard = 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	check(main._combat != null and main._visit.is_empty(), "acked: the visit closes and the cousin's friends are a fight")
	check(main._combat != null and main._combat.spec.get("theme", "") == "city-square" and not main._combat.spec.has("objective"),
		"a bandit roster at the inn, no objective — the delivery's carter is not in the common room")
	await _finish(main, {"outcome": "Victory", "xp": 10, "gold": 2, "loot": [], "kills": [], "deaths": [], "rounds": 1,
		"objective": {"kind": "", "done": false, "xp": 0}})
	check(main._spoils_panel != null, "a won brawl is a fight like any other")
	check(absf(FactionOpinion.get_opinion(city.faction) - opinion_before) <= _drift(w, opinion_clock) and Ladder.deeds(city.faction) == deeds_before,
		"...but no service to the town: opinion and the ladder stay")
	check(Quest.get_quest(party, "deliver:t:x")["state"] == "active", "the delivery is still on")
	check(main._visit.is_empty(), "the inn is down while the spoils page is up")
	main._close_spoils()
	for i in 3:
		await process_frame
	check(not main._visit.is_empty() and main._visit["settlement"] == city, "the spoils page closed: the inn reopens behind it")
	print("test_world_downtime: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# tests/drive_completionist.gd — the other kind of player.
#
# tests/drive_random.gd plays like a person: it wanders, it takes what the map
# offers, and over a session it SAMPLES the game. Sampling is the right shape
# for finding the bugs nobody wrote a case for, and the wrong shape for
# answering "does every door in this screen still open?" — a door the sampler
# did not happen to walk past is a door nobody checked.
#
# This one is the completionist. It works a written checklist to the end: every
# control on the HUD, every page of a settlement, every counter behind the
# market, every way of meeting a band, every lair button, every settlement on
# the map. It is not looking for a surprise. It is asking one question of each
# door — does it open, and does what is behind it do what it says — and the run
# is red the moment the answer is no, or the door could not be reached at all.
#
# Two rules keep it from being a second, slower drive_random:
#
#  1. **Every deed asserts its own contract, not just its press.** Buying moves
#     gold AND the pack. A night at the inn spends the fee, eight hours, and the
#     party's wounds. Turning a job in pays and closes it. A second theft in one
#     visit pays nothing. Pressing the button is the setup; the assertion is the
#     test.
#  2. **The ledger is the verdict.** Every deed is listed up front, REQUIRED or
#     OPPORTUNISTIC. A required deed the tour never reached fails the run and is
#     named — which is what catches a door that quietly stopped existing, the
#     one failure a driver that only asserts what it happens to touch can never
#     report.
#
# **What is arranged rather than played for**, all of it here and nowhere else,
# because a test that hides its setup is a test you cannot read:
#
#   * a working purse. Every counter has a price and this is not a test of the
#     economy (core/settlement_visit.gd's own tests are), so the party starts
#     with enough to reach all of them rather than grinding fights for it.
#   * one unidentified trinket in the pack, so the librarian's counter has
#     something to identify. Unidentified loot is a drop, and a drop is a roll.
#   * a scratch on the party before the healer, for the same reason: the healer
#     refuses to take money for nothing, quite rightly.
#   * a job forced to `complete` before it is handed in. Actually finishing a
#     fetch-quest is a second playthrough, not a counter.
#   * bands spawned next to the party when the four ways of meeting one have
#     not all come up. The map ships two hunting bands; there are four ways.
#   * the clock wound on to mid-morning before those meetings. At night a band
#     is on the party before anyone can choose how to meet it unless the watch
#     hears it coming (#85) — which is that rule working, not a door failing.
#   * the long-rest cooldown wound back before the camp kit is used. It is the
#     inn's night that put it there, and a day of walking to re-earn one button
#     press is not what this file is measuring.
#
# Everything else is walked and pressed: the marching orders are real clicks on
# the real map, the buttons are the real buttons, and nothing here writes to the
# model behind a screen to make a screen agree with it.
#
#   godot --headless --path . -s tests/drive_completionist.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldSave = preload("res://core/world_save.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Travel = preload("res://core/travel.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Rumors = preload("res://core/rumors.gd")
const AI = preload("res://core/ai.gd")
const Recruits = preload("res://core/recruits.gd")
const Leveling = preload("res://core/leveling.gd")

const DT := 0.1
const PURSE := 4000          # see the header: enough to reach every counter
const WALK_LIMIT := 1200     # frames before "could not get there" is the answer
const FIGHT_LIMIT := 2500    # frames before a fight is not going to end

# The small map, always. It is the one with four hand-placed settlements — a
# city with all six counters, a town, a camp with none, and a monster faction's
# gate — plus five lairs and two hunting bands, which is one of everything this
# checklist asks about. The large map is the same furniture further apart, so a
# completionist tour of it would cost minutes of walking to prove nothing new.
const MAP := "small"
const CITY := "riverhold"        # human city: every counter, including the two that sell nothing
const TOWN := "greenmarch"       # elf town: weaponsmith, alchemist, inn
const CAMP := "dun-arrow"        # dwarf camp: no specialists at all (D7)
const GATE := "ashfell"          # orc city: never trades, always turns out the guard

# --- the checklist ------------------------------------------------------------
#
# The whole point of the file, in one place. Nothing below adds a deed that is
# not named here, and a REQUIRED deed missing at the end is a failure with its
# own line — including when the tour never got near it.

const REQUIRED := {
	"hud:pause": "Pause stops the world clock, Resume starts it",
	"hud:speed": "the speed button walks 1x -> 2x -> 4x -> 8x -> 1x",
	"hud:pace": "the pace button cycles every marching order",
	"hud:party": "the party screen opens and closes, and gives the clock back",
	"hud:pack": "the shared pack opens and closes",
	"hud:quests": "the quest log opens and closes",
	"hud:menu": "the Esc menu opens and closes",
	"hud:manual": "the manual opens and closes",
	"hud:bugreport": "the bug reporter opens and closes",
	"hud:camera": "the camera zooms to both stops and pans",
	"town:arrive": "walking into a settlement opens its market and pauses the clock",
	"town:hub": "the town square names what is behind each door",
	"town:market": "the market page opens",
	"town:inn": "the inn page opens",
	"town:board": "the notice board opens",
	"town:tabs": "every counter the settlement has can be opened",
	"town:buy": "buying moves gold out and the item into the pack",
	"town:sell": "selling moves the item out of the pack and gold in",
	"town:campkit": "the camp kit can be bought, and lands in the pack",
	"town:heal": "the healer patches the party up for the fee",
	"town:identify": "the librarian identifies an unknown item for the fee",
	"town:steal": "stealing is offered, and only once per visit",
	"town:haggle": "haggling is offered, and is spent once asked",
	"town:sortparty": "the inn opens the party screen",
	"town:hire": "someone looking for work at the inn is settled in and taken on, for the fee",
	"town:rest": "a night at the inn spends the fee, the hours, and the wounds",
	"town:rumor": "a lead bought at the inn puts a lair on the map",
	"town:quest-take": "a posted job can be taken, and lands in the log as active",
	"town:quest-turnin": "a finished job can be handed in, and pays",
	"town:leave": "Leave closes the market and gives the clock back",
	"town:every": "every settlement on the map was walked into",
	"town:camp-has-none": "a camp offers no specialists (D7)",
	"gate:no-market": "a monster faction never opens a market",
	"gate:fight": "...it turns out the guard instead",
	"road:shortrest": "a short rest on the road spends an hour",
	"road:camp": "a camp kit buys a long rest away from a settlement",
	"lair:search": "an undiscovered lair can be searched for",
	"lair:found": "...and is found",
	"lair:enter": "a discovered lair can be entered, quietly or loudly",
	"meet:card": "a band closing on the party asks how to meet it",
	"fight:reached": "a fight reaches the real combat screen",
	"fight:ended": "...and ends, back on a playable map",
	"fight:spoils": "...and pays out on its own page",
}

const OPPORTUNISTIC := {
	"town:workheal": "the ward had a shift going for a restoration caster",
	"meet:engage": "met a band by charging it",
	"meet:ambush": "met a band by ambushing it",
	"meet:parley": "met a band by talking to it",
	"meet:avoid": "met a band by slipping round it",
	"meet:greet": "met a friendly band by hailing it",
	"meet:pass": "met a friendly band by walking on past",
	"lair:sneak": "slipped past a lair's guardians",
	"lair:delve": "kicked a lair's door in and worked the rooms",
	"fight:deploy": "an unseen approach opened on the deployment phase",
	"road:event": "the road threw an event card",
	"road:region": "the party crossed into another country",
	"fight:trait_moment": "a fight left a personality trait on somebody, shown and passed (#176)",
}

var screen
var _fail := 0
var _said := {}
var _ledger := {}
var _frames := 0
var _region0 := ""          # the country the tour started in; a crossing is a different one

func _init() -> void:
	# Which map the tour is of: this file tours the free plane, where bands walk
	# the map (SORCMERC_ROUTES=0); tests/drive_completionist_routes.gd extends
	# it and tours the default route world through the hooks marked below.
	OS.set_environment("SORCMERC_ROUTES", "1" if _routes() else "0")
	# This process's own autosave slots, so a concurrent godot run cannot clobber
	# them — same shape as every other driver here.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	_run()

func _routes() -> bool:
	return false

func fail(msg: String) -> void:
	_fail += 1
	if _said.has(msg):
		return
	_said[msg] = true
	printerr("  FAIL [frame %d]: %s" % [_frames, msg])

func did(deed: String) -> void:
	_ledger[deed] = true

# Tick a deed only when `ok`; otherwise say why, once. The shape most checks
# below take, so a contract and its deed never drift apart.
func check(deed: String, ok: bool, msg: String) -> bool:
	if ok:
		did(deed)
	else:
		fail("%s — %s" % [deed, msg])
	return ok

func _run() -> void:
	WorldSave.clear()
	FactionOpinion.reset()
	screen = load("res://scenes/world/world.tscn").instantiate()
	screen.world_size = MAP
	root.add_child(screen)
	await process_frame
	screen.size = Vector2(1280, 800)
	await process_frame
	if screen.world == null or screen.world.player() == null:
		fail("the map came up with no world to tour")
		_verdict()
		return
	screen.party.add_gold(PURSE)

	await _hud_tour(); _clear_the_screen("_hud_tour")
	await _the_city(); _clear_the_screen("_the_city")
	await _the_road(); _clear_the_screen("_the_road")
	await _the_lair(); _clear_the_screen("_the_lair")
	await _the_meetings(); _clear_the_screen("_the_meetings")
	await _the_rest_of_the_map(); _clear_the_screen("_the_rest_of_the_map")
	_verdict()

# Nothing a chapter opened may still be open when the next one starts: a market,
# a delve or an overlay left up blocks every gate and every march order after it
# (world.gd's _overlay_up), and the cascade of failures that follows says
# nothing about where it began. Reported once, here, and then cleared.
func _clear_the_screen(chapter: String) -> void:
	var left: Array = []
	# A gate that opened as the party walked past is routine — half these
	# chapters end within sight of a town — so it is closed without comment.
	# A delve or an overlay is not: nothing else opens those.
	if not screen._visit.is_empty():
		screen._close_visit()
	if screen._site_screen != null:
		left.append("a delve")
		screen._site_screen.queue_free()
		screen._site_screen = null
		screen._site = null
	if screen._party_overlay != null:
		left.append("the party screen")
		screen._close_party()
	if screen._quest_panel != null:
		left.append("the quest log")
		screen._toggle_quests()
	if screen._inventory_panel != null:
		left.append("the pack")
		screen._toggle_inventory()
	if screen._menu_panel != null:
		left.append("the menu")
		screen._close_menu()
	if not left.is_empty():
		fail("%s left %s open behind it" % [chapter, ", ".join(left)])
	screen._halted_on_arrival = false
	screen.world.clock.resume()

# --- the frame, and what happens without being asked --------------------------

# One frame, plus whatever the map put in the way of it. Every wait in this file
# goes through here, so no chapter has to remember that a road event can land in
# the middle of it.
func _step(n := 1) -> void:
	for i in n:
		screen._process(DT)
		await process_frame
		_frames += 1
		_notice()
		if is_instance_valid(screen._event_card):
			# Three different things come up on this one card — a road event, the
			# outcome of an approach, and a camp's report — and only the first is
			# the deed. They are told apart by the id stamped on the event.
			var card_id := String(screen._event_card._e.get("id", ""))
			if not card_id.begins_with("approach-") and not card_id.begins_with("camp-"):
				did("road:event")
			screen._event_card.acknowledged.emit()
		if screen._spoils_panel != null:
			did("fight:spoils")
			screen._close_spoils()
		if screen._moment != null:
			did("fight:trait_moment")
			screen._moment._skip_or_advance()
		# #118's "somebody can level up" page, when a fight's XP banked a level.
		# Spending it is the party screen's subject, not this tour's, so the
		# robot does what a player putting it off does: "Not now". Left up, it
		# is an overlay (world.gd's _overlay_up), and every march order and
		# every town gate after it is refused — the rest of the tour times out
		# on walks that never start, one run in twenty, whenever the unseeded
		# fights before it happened to pay out a level.
		if screen._levelup_panel != null:
			for b in screen._levelup_panel.find_children("*", "Button", true, false):
				if String(b.text).begins_with("Not now"):
					b.pressed.emit()
					break
		if screen._combat != null:
			_fight_frame()

# Things the tour does not press for and still wants ticked when they happen.
func _notice() -> void:
	# The first country the map names is where the party started, not a
	# crossing; only a second, different one is.
	var here := String(screen._region.get("id", ""))
	if here != "":
		if _region0 == "":
			_region0 = here
		elif here != _region0:
			did("road:region")
	if screen.party.gold < 0:
		fail("the purse went negative: %d" % screen.party.gold)

# The fight itself is drive_random's and drive_ui's subject, not this file's:
# here the party plays itself with the same AI the foes use and the real End
# turn button hands back, exactly as drive_campaign does. What this tour is
# about is the doors around a fight — deployment, the approach, the spoils.
func _fight_frame() -> void:
	var fight = screen._combat
	if not is_instance_valid(fight) or not fight.result.is_empty():
		return
	did("fight:reached")
	var cb = fight.cb
	if cb == null or fight._busy or fight._advancing:
		return
	if fight._mode == "deploy":
		did("fight:deploy")
		_press("Begin", fight._buttons)
		return
	var h = cb.current()
	# Letting the AI move the party goes round the screen rather than through
	# it, so the turn has to be handed back through the real End turn button —
	# including once the last foe is down. The screen only notices a decided
	# fight on its way out of a turn (_after_hero_action / _advance), and this
	# driver never took one the normal way, so nothing else would tell it.
	if cb.is_over():
		_press_last(fight)
		return
	if h == null or h.team != "party":
		return
	if h.conscious():
		AI.take_turn(cb, h)
	_press_last(fight)

# The bar's last live slot is always its own control: End turn, Cancel, or the
# confirm one of those wears when armed (scenes/main.gd's _slotted).
func _press_last(fight) -> void:
	var btns := _buttons(fight._buttons)
	if not btns.is_empty():
		btns[btns.size() - 1].pressed.emit()

# Play whatever fight is up to its end, then let the map come back.
func _see_the_fight_out() -> void:
	var waited := 0
	while screen._combat != null and waited < FIGHT_LIMIT:
		await _step()
		waited += 1
	if screen._combat != null:
		fail("a fight did not end in %d frames" % FIGHT_LIMIT)
		return
	await _step(6)                               # spoils, banking, the map's halt
	while screen._spoils_panel != null or screen._moment != null:
		await _step()
	did("fight:ended")
	if screen.world.player() == null:
		fail("the fight left no player party on the map")

# --- walking ------------------------------------------------------------------

# A march order, given the way a player gives one: put the place on screen and
# click it.
#
# Unless a band the company has already met and parted with is standing on it.
# A click on a band's figure is an order to go and meet that band (world.gd's
# _seek), whatever is under it, and asking for a meeting by name overrides a
# truce and a slip on purpose. A FRESH band on the spot is fine — the wolves
# that hunt the dwarf camp stand on its gate, and meeting them is the road
# doing its job; the click meets them, the meeting resolves, the next click is
# the town. A band already parted with is not: it loiters where it was left
# (its truce keeps it off the company, not off the town), the click meets it
# again, the meeting ends in a halt, the halt keeps the clock stopped, a stopped
# clock keeps the band where it stands, and the next click lands on it again —
# 1200 frames of the same card, and a red run whenever the unseeded fights
# before it happened to leave a band there (one run in nine). A player does the
# obvious thing: lets the clock run, with the HUD's own button, until the band
# has gone about its business, and clicks the town then.
func _order(at: Vector2) -> void:
	if screen._combat != null or not screen._visit.is_empty() or screen._overlay_up():
		return
	screen.center_on(at)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = screen._pix(at)
	# Since the owner's call of 2026-09-26 the map itself lets a click on a
	# PLACE win over a band already parted with (world.gd's _place_at), so the
	# wait is only for a click on open ground, where the band is still what the
	# click names. Waiting on a town instead stalled the tour whenever such a
	# band had stopped on it with the clock already running: nothing ever moved
	# it, and the click was never sent.
	var band = screen._band_at(e.position)
	if band != null and screen._place_at(e.position) == null \
			and (screen._slipped.has(band.id) or WorldAI.in_truce(band, screen.world.clock.elapsed)):
		if screen.world.clock.is_paused():
			screen._toggle_pause()
		return
	screen._gui_input(e)

# Walk to a point. Re-orders after every halt, because arriving, fighting and
# reading a card all stop the party where it stands (#70, #98). A settlement
# gate that opens on the way is walked out of again — this is the version for
# getting SOMEWHERE, and a market is not it.
func _walk_to(at: Vector2, label: String) -> bool:
	screen._set_speed(8.0)
	for i in WALK_LIMIT:
		var p = screen.world.player()
		if p == null:
			fail("no player party while walking to %s" % label)
			return false
		if p.position.distance_to(at) <= 8.0:
			return true
		if not screen._visit.is_empty():
			screen._close_visit()                # passing through, not shopping
		elif screen._combat != null:
			await _see_the_fight_out()
		elif is_instance_valid(screen._approach_card):
			_meet_them()
		elif p.at_goal() or screen.world.clock.is_paused():
			_order(at)
		await _step()
	var p0 = screen.world.player()
	fail("could not walk to %s in %d frames (at %s, goal %s, paused %s, halted %s, card %s)" % [
		label, WALK_LIMIT, p0.position if p0 != null else "-", p0.goal if p0 != null else "-",
		screen.world.clock.is_paused(), screen._halted_on_arrival, is_instance_valid(screen._approach_card)])
	return false

# ...and the version for going to a town: it stops the moment the gate opens,
# which is the thing being tested.
func _walk_into(s, label: String, stop_on_fight := false) -> bool:
	screen._set_speed(8.0)
	# Standing inside the walls with no market up means this gate was just left
	# (world.gd's `_left`), and it will not open again until the party has been
	# out of range — so go out and come back, which is what a player does and
	# what makes "walking in opens the market" a fact rather than a leftover.
	var here = screen.world.player()
	if screen._visit.is_empty() and here != null \
			and here.position.distance_to(s.position) <= screen.VISIT_RADIUS:
		if not await _step_out_of(s, label):
			return false
	for i in WALK_LIMIT:
		# Only this town's gate is the answer. The march can stop inside
		# another town's walls on the way — a fight on the road through it ends
		# with the company halted there, and a halted company has arrived — and
		# that town opening is the map working; it is walked out of again.
		if not screen._visit.is_empty():
			if screen._visit.get("settlement") == s:
				return true
			screen._close_visit()
		var p = screen.world.player()
		if p == null:
			fail("no player party while walking into %s" % label)
			return false
		if screen._combat != null:
			if stop_on_fight:
				return true                      # what came out of the gate IS the answer
			await _see_the_fight_out()
		elif is_instance_valid(screen._approach_card):
			_meet_them()
		elif p.position.distance_to(s.position) <= 2.0:
			return true                          # standing on it; a monster gate never opens one
		elif p.at_goal() or screen.world.clock.is_paused():
			_order(s.position)
		await _step()
	var p0 = screen.world.player()
	fail("could not walk into %s in %d frames (at %s, goal %s, paused %s, halted %s, visit %s, left %s, card %s)" % [
		label, WALK_LIMIT, p0.position if p0 != null else "-", p0.goal if p0 != null else "-",
		screen.world.clock.is_paused(), screen._halted_on_arrival,
		screen._visit.get("settlement").id if screen._visit.get("settlement") != null else "-",
		screen._left.id if screen._left != null else "-", is_instance_valid(screen._approach_card)])
	return false

# --- the hooks a route world tours differently --------------------------------
#
# Everything the free plane does by walking to a bare point on the map. On the
# roads there is no bare point to walk to (the company never leaves the road),
# so tests/drive_completionist_routes.gd overrides exactly these.

# Out of a town's gate, far enough that walking back in opens it again.
func _step_out_of(s, label: String) -> bool:
	return await _walk_to(s.position + Vector2(screen.VISIT_RADIUS + 90.0, 0), "clear of " + label)

# Somewhere away from every settlement, to rest or to be met.
func _into_the_open(at: Vector2) -> bool:
	return await _walk_to(at, "open country")

# A band put in the party's way for one of the four meetings.
func _band_in_the_way(way: String):
	var p = screen.world.player()
	var band = screen.world.add_party(World.RoamingParty.new(
		"tourband-%s" % way, p.position + Vector2(30, 0), "goblinoid"))
	var roster: Array[Dictionary] = [{"role": "light", "level": 1}, {"role": "heavy", "level": 1}]
	band.troops = roster
	WorldAI.hunt(band)
	return band

# Keep moving so the band closes (one frame's order).
func _close_in(p, band) -> void:
	_order(p.position + Vector2(-140, 40))

func _band_gone(band) -> void:
	screen.world.parties.erase(band)

func _settlement(sname: String):
	for s in screen.world.settlements:
		if s.id == sname or s.sname.to_lower().begins_with(sname):
			return s
	return null

# --- buttons ------------------------------------------------------------------

func _buttons(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is Button and c.visible and not c.disabled and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(_buttons(c))
	return out

# A button's name is its text, or — since the skill bar went to icon badges —
# the first line of its tooltip.
func _name(b: Button) -> String:
	var t := String(b.text)
	if t != "":
		return t
	return String(b.tooltip_text).get_slice("\n", 0)

func _find(label: String, under: Node) -> Button:
	for b in _buttons(under if under != null else screen):
		if label in _name(b):
			return b
	return null

func _press(label: String, under: Node = null) -> bool:
	var b := _find(label, under)
	if b == null:
		return false
	b.pressed.emit()
	return true

func _must_press(label: String, under: Node, why: String) -> bool:
	if _press(label, under):
		return true
	fail("no button labelled '%s' %s" % [label, why])
	return false

# --- chapter 1: the HUD -------------------------------------------------------

func _hud_tour() -> void:
	await _step(2)
	var w = screen.world

	# Pause / Resume. The button relabels, so it is found by the label it wears.
	if w.clock.is_paused():
		screen._toggle_pause()
	_must_press("Pause", screen, "on the HUD")
	check("hud:pause", w.clock.is_paused(), "Pause did not stop the clock")
	_must_press("Resume", screen, "once the clock is paused")
	if w.clock.is_paused():
		fail("hud:pause — Resume did not start the clock again")

	# Speed: all four stops, in the order the button walks them.
	var want := [2.0, 4.0, 8.0, 1.0]
	var ok := true
	for target in want:
		screen._speed_btn.pressed.emit()
		if not is_equal_approx(w.clock.speed, target):
			ok = false
			fail("hud:speed — the speed button reached %.0fx, wanted %.0fx" % [w.clock.speed, target])
	check("hud:speed", ok, "the speed button did not walk its own cycle")

	# Pace: every marching order the game has, back to where it started.
	var seen := {}
	for i in Travel.PACES.size():
		screen._pace_btn.pressed.emit()
		seen[String(Travel.orders(screen.party)["pace"])] = true
	check("hud:pace", seen.size() == Travel.PACES.size(),
		"the pace button reached %d of %d orders" % [seen.size(), Travel.PACES.size()])

	# The four screens off the top bar. Each one pauses the map while it is up
	# and has to give the clock back when it closes — the single easiest thing
	# in this screen to ship broken.
	await _overlay("Party", "hud:party", func(): return screen._party_overlay != null,
		func(): screen._close_party())
	await _overlay("Pack", "hud:pack", func(): return screen._inventory_panel != null,
		func(): screen._toggle_inventory())
	await _overlay("Quests", "hud:quests", func(): return screen._quest_panel != null,
		func(): screen._toggle_quests())
	await _overlay("Esc", "hud:menu", func(): return screen._menu_panel != null,
		func(): screen._close_menu(), true)

	# The manual and the bug reporter are plain toggles that the world screen
	# does not track, so they are checked by looking for what they put on screen.
	_must_press("Manual", screen, "on the HUD")
	await _step()
	var manual_up := _find("Close", screen) != null
	_press("Close", screen)
	await _step()
	check("hud:manual", manual_up, "the manual did not open")

	screen.report_bug()
	await _step()
	var bug_up := _find("Close", screen) != null or _find("Cancel", screen) != null
	if not _press("Close", screen):
		_press("Cancel", screen)
	await _step()
	check("hud:bugreport", bug_up, "the bug reporter did not open")

	# The camera: both zoom stops and a drag.
	var at := Vector2(700, 350)
	for i in 60:
		_wheel(at, MOUSE_BUTTON_WHEEL_UP)
	var hit_max := is_equal_approx(screen._zoom, screen.ZOOM_MAX)
	for i in 120:
		_wheel(at, MOUSE_BUTTON_WHEEL_DOWN)
	var hit_min := is_equal_approx(screen._zoom, screen.ZOOM_MIN)
	var pan0: Vector2 = screen._pan
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_RIGHT
	m.position = Vector2(600, 400)
	m.relative = Vector2(-40, 25)
	screen._gui_input(m)
	check("hud:camera", hit_max and hit_min and not screen._pan.is_equal_approx(pan0),
		"zoom stopped at %.3f (max %s, min %s) or the drag did not pan" % [
			screen._zoom, hit_max, hit_min])
	screen.set_zoom(1.0)

# Open a top-bar screen by its button, confirm it is up and holding the clock,
# close it by its own path, confirm both came back.
func _overlay(label: String, deed: String, up: Callable, close: Callable, by_api := false) -> void:
	if by_api:
		screen._toggle_menu()      # the Esc menu has no button of its own on the bar
	elif not _must_press(label, screen, "on the HUD"):
		return
	await _step()
	if not up.call():
		fail("%s — %s did not open" % [deed, label])
		return
	if not screen.world.clock.is_paused():
		fail("%s — %s did not pause the world clock" % [deed, label])
	close.call()
	await _step()
	if up.call():
		fail("%s — %s did not close" % [deed, label])
		return
	if screen.world.clock.is_paused() and not screen._halted_on_arrival:
		fail("%s — closing %s left the world clock paused" % [deed, label])
		return
	did(deed)

func _wheel(at: Vector2, button: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	screen._gui_input(e)

# --- chapter 2: the city, counter by counter ----------------------------------

func _the_city() -> void:
	var s = _settlement(CITY)
	if s == null:
		fail("the %s map has no %s to tour" % [MAP, CITY])
		return
	# Arranged, per the header: a scratch for the healer to treat and something
	# unknown for the librarian to name.
	for ch in screen.party.party_characters():
		ch.hp_current = maxi(1, int(screen.party.summary(ch.id)["max_hp"]) / 2)
	screen.party.stash_add("potion-of-healing", 1, false)

	if not await _walk_into(s, CITY):
		return
	await _step(4)
	if not check("town:arrive", not screen._visit.is_empty(),
			"walking into %s opened no market" % CITY):
		return
	if not screen.world.clock.is_paused():
		fail("town:arrive — the visit did not pause the world clock")

	# The town square, and the three doors off it.
	check("town:hub", screen._visit_page == "hub" and _find("Market", screen._visit_panel) != null
		and _find("Inn", screen._visit_panel) != null and _find("Notice Board", screen._visit_panel) != null,
		"the square is missing one of its doors")

	await _the_market(s)
	await _the_inn(s)
	await _the_board(s)

	_must_press("Leave", screen._visit_panel, "in the settlement panel")
	await _step(2)
	check("town:leave", screen._visit.is_empty() and screen._visit_panel == null,
		"Leave did not close the market")
	# A band waiting at the gate takes the clock straight back, and that is the
	# map working, not Leave failing: since the design audit's §1.7 a night at
	# the inn walks the world, and on a slow machine (the frames also run on
	# real time) a hunter can reach the walls by morning. The walk that follows
	# answers the card (_walk_into's _meet_them).
	# Nor is the road asking the moment the company is out of the gate (#232:
	# the inn's night has run the clock past the road's interval), nor a fight
	# that answer turned into — each stops the clock on purpose.
	if screen.world.clock.is_paused() and not screen._halted_on_arrival \
			and not is_instance_valid(screen._approach_card) and not is_instance_valid(screen._event_card) \
			and screen._combat == null:
		fail("town:leave — Leave did not give the world clock back")

func _goto_page(page: String, label: String, deed: String) -> bool:
	if screen._visit_page != "hub":
		_press("Town Square", screen._visit_panel)
	if not _must_press(label, screen._visit_panel, "on the town square"):
		return false
	return check(deed, screen._visit_page == page,
		"pressing %s opened the %s page" % [label, screen._visit_page])

func _the_market(s) -> void:
	if not _goto_page("market", "Market", "town:market"):
		return
	# One counter at a time. The innkeeper is not one of them — its counter is
	# the notice board, not a stall (core/campaign.gd's SERVICE_ORDER) — and the
	# tab already showing is drawn as a pressed, disabled button, so it counts as
	# opened without a press of its own.
	var counters: Array = screen._visit["services"].filter(
		func(x): return String(x) != "innkeeper")
	var opened := {}
	for service in counters:
		var name_of := _service_name(String(service))
		if screen._market_tab != service:
			_press(name_of, screen._visit_panel)
			await _step()
		if screen._market_tab != service:
			fail("town:tabs — pressing %s left the %s counter open" % [name_of, screen._market_tab])
			continue
		opened[service] = true
		await _counter(String(service))
	check("town:tabs", opened.size() == counters.size(),
		"opened %d of the %d counters %s staffs" % [opened.size(), counters.size(), s.sname])

	# Selling, stealing and haggling are not anybody's counter: they sit under
	# whichever tab is open, so they are done once, at the end.
	await _sell_something()
	await _steal_twice()
	await _haggle_once()

# What is behind one counter. Every settlement staffs a different set, so each
# arm is guarded by "is this counter even here" rather than assumed.
func _counter(service: String) -> void:
	var party = screen.party
	match service:
		"healer":
			# The healer refuses to take money for nothing, quite rightly —
			# hence the arranged scratch at the top of this chapter.
			var gold: int = party.gold
			if _must_press("Heal", screen._visit_panel, "at the healer's counter"):
				await _step()
				var full := true
				for ch in party.party_characters():
					var m: Dictionary = party.summary(ch.id)
					full = full and int(m["hp"]) == int(m["max_hp"])
				check("town:heal", full and party.gold == gold - Visit.HEAL_COST,
					"party full=%s, fee %d (wanted %d)" % [full, gold - party.gold, Visit.HEAL_COST])
			if _find("Work", screen._visit_panel) != null:
				_press("Work", screen._visit_panel)
				await _step()
				did("town:workheal")
		"librarian":
			var gold2: int = party.gold
			if _must_press("Identify", screen._visit_panel, "at the librarian's counter"):
				await _step()
				check("town:identify", party.unidentified().is_empty()
					and party.gold == gold2 - Visit.IDENTIFY_COST,
					"%d unknown left, fee %d (wanted %d)" % [party.unidentified().size(),
						gold2 - party.gold, Visit.IDENTIFY_COST])
		"generalist":
			# The camp kit is a flat price on its own row rather than a catalog
			# entry, and it is what chapter 3 needs to camp on the road.
			var gold3: int = party.gold
			if _must_press("Buy", screen._visit_panel, "for the camp kit"):
				await _step()
				check("town:campkit", party.stash_count(WorldCamp.CAMP_KIT_ITEM) > 0
					and party.gold == gold3 - WorldCamp.CAMP_KIT_PRICE,
					"the kit cost %d and left %d in the pack" % [gold3 - party.gold,
						party.stash_count(WorldCamp.CAMP_KIT_ITEM)])
	# ...and whichever counter has a shelf out sells the one thing this tour
	# buys. A shelf tile is a picture whose tooltip carries the verb the click
	# performs, which is what tells it from the pack tiles under it.
	if not _ledger.has("town:buy"):
		var shelf := _tiles("Click: buy")
		if shelf.is_empty():
			return
		var gold4: int = party.gold
		var pack: int = _pack_size()
		shelf[0].pressed.emit()
		await _step()
		check("town:buy", party.gold < gold4 and _pack_size() > pack,
			"gold %d -> %d, pack %d -> %d" % [gold4, party.gold, pack, _pack_size()])

func _sell_something() -> void:
	var pack := _tiles("Click: sell")
	if pack.is_empty():
		fail("town:sell — nothing in the pack the market would take")
		return
	var gold: int = screen.party.gold
	var held: int = _pack_size()
	pack[0].pressed.emit()
	await _step()
	check("town:sell", screen.party.gold > gold and _pack_size() < held,
		"gold %d -> %d, pack %d -> %d" % [gold, screen.party.gold, held, _pack_size()])

# One theft per visit (O9 item 1). The only way to check "and not a second one"
# is to press twice and watch nothing happen.
func _steal_twice() -> void:
	if not _must_press("Steal", screen._visit_panel, "in the market"):
		return
	await _step()
	var purse: int = screen.party.gold
	var owed: float = screen._visit["settlement"].pending_opinion_delta
	if _press("Steal", screen._visit_panel):
		await _step()
	check("town:steal", screen._visit.get("stolen", false) and screen.party.gold == purse
		and is_equal_approx(screen._visit["settlement"].pending_opinion_delta, owed),
		"a second theft in one visit still moved gold or opinion")

# ...and one ask per visit, which the button says out loud once it is spent.
func _haggle_once() -> void:
	if not _must_press("Haggle", screen._visit_panel, "in the market"):
		return
	await _step()
	check("town:haggle", screen._visit.get("haggled", false),
		"the market did not record the ask")

func _the_inn(s) -> void:
	if not _goto_page("inn", "Inn", "town:inn"):
		return
	var party = screen.party

	# The inn's door back to the roster.
	if _must_press("Sort out the party", screen._visit_panel, "on the inn page"):
		await _step()
		check("town:sortparty", screen._party_overlay != null, "the inn opened no party screen")
		screen._close_party()
		await _step()
		_goto_page("inn", "Inn", "town:inn")

	# The common room (core/recruits.gd): take the first one looking for work,
	# settle them in on their page — every choice the hire left open answered
	# with its first free option, the way a player in a hurry would — and pay.
	var looking: Array = Recruits.offers(s, screen.world, party)
	if looking.is_empty():
		fail("town:hire — nobody at the inn was looking for work")
	else:
		var size0: int = party.roster.size()
		var gold1: int = party.gold
		var fee: int = int(looking[0]["fee"])
		if _must_press("Take them on", screen._visit_panel, "on the inn page"):
			await _step()
			var page = screen._party_overlay.get_child(0) if screen._party_overlay != null else null
			if page == null or not page.has_method("set_recruit"):
				fail("town:hire — Take them on opened no settle-in page")
			else:
				for _i in 60:
					if Leveling.can_finalize(page.character()):
						break
					var key: String = String(Leveling.pending(page.character())[0]["key"])
					var free: Array = _buttons(page).filter(func(b): return _answers(b, key))
					if free.is_empty():
						break
					free[0].pressed.emit()
					await _step()
				if _must_press("Take them on", page, "on the settle-in page"):
					await _step()
					check("town:hire", party.roster.size() == size0 + 1 and party.gold == gold1 - fee
						and screen._party_overlay == null,
						"roster %d -> %d, paid %d (fee %d), page %s" % [size0, party.roster.size(), gold1 - party.gold, fee,
							"closed" if screen._party_overlay == null else "still up"])
		_goto_page("inn", "Inn", "town:inn")

	# A lead on a lair: the second way a lair gets onto the map, and the one the
	# next chapter leans on. The rows are sorted by distance, so the first Buy
	# is the first lead.
	var leads: Array = Rumors.offers(s, screen.world)
	if leads.is_empty():
		fail("town:rumor — the innkeeper had no leads to sell")
	else:
		var named := String(leads[0]["lair_id"])
		var purse: int = party.gold
		if _must_press("Buy", screen._visit_panel, "for a lead at the inn"):
			await _step()
			var l = _lair_by_id(named)
			check("town:rumor", l != null and l.discovered and party.gold < purse,
				"the lead cost %d and %s is %s" % [purse - party.gold, named,
					"still hidden" if l != null and not l.discovered else "gone"])

	# A night: the fee, eight hours, and the wounds.
	for ch in party.party_characters():
		ch.hp_current = 1
	var gold0: int = party.gold
	var clock0: float = screen.world.clock.elapsed
	if _must_press("Rest the night", screen._visit_panel, "on the inn page"):
		await _step()
		var healed := true
		for ch in party.party_characters():
			healed = healed and int(party.summary(ch.id)["hp"]) > 1
		check("town:rest", healed and party.gold == gold0 - Visit.inn_cost(s)
			and screen.world.clock.elapsed >= clock0 + Visit.LONG_REST_MINUTES,
			"healed=%s, fee %d (wanted %d), clock +%.0f (wanted %.0f)" % [healed,
				gold0 - party.gold, Visit.inn_cost(s),
				screen.world.clock.elapsed - clock0, Visit.LONG_REST_MINUTES])

# A settle-in page's option button for choice `key` that is not picked yet,
# and not greyed (taken elsewhere, or not on the board yet).
static func _answers(b: Button, key: String) -> bool:
	return String(b.get_meta("choice_key", "")) == key and not String(b.text).begins_with("●") \
		and not b.disabled

func _the_board(s) -> void:
	if not _goto_page("board", "Notice Board", "town:board"):
		return
	var party = screen.party
	var before: int = party.quests.size()
	if not _must_press("Take", screen._visit_panel, "on the notice board"):
		return
	await _step()
	var active: Array = party.quests.filter(func(q): return String(q["state"]) == "active")
	if not check("town:quest-take", party.quests.size() > before and not active.is_empty(),
			"the job never reached the log as active"):
		return

	# Arranged, per the header: finishing a fetch-quest is a second playthrough.
	var job: Dictionary = active[0]
	job["progress"] = int(job["required"])
	job["state"] = "complete"
	if String(job["kind"]) in ["collect_item", "supply_item"]:   # paid for goods in hand only
		party.stash_add(String(job["target_item_id"]), int(job["required"]))
	screen._goto_page("board")
	await _step()
	var gold0: int = party.gold
	if not _must_press("Turn in", screen._visit_panel, "for a finished job"):
		return
	await _step()
	check("town:quest-turnin", String(job["state"]) == "turned_in" and party.gold > gold0,
		"state=%s, paid %d" % [job["state"], party.gold - gold0])

# Item tiles are Buttons whose tooltip ends in the verb the click performs.
func _tiles(verb: String) -> Array:
	var out: Array = []
	for b in _buttons(screen._visit_panel):
		if verb in String(b.tooltip_text):
			out.append(b)
	return out

func _pack_size() -> int:
	var n := 0
	for e in screen.party.stash:
		n += int(e["quantity"])
	return n

# core/campaign.gd owns the counter names the tab strip draws; reached through
# the world screen rather than preloaded again.
func _service_name(service: String) -> String:
	return String(screen.Campaign.SERVICE_NAMES.get(service, service))

# --- chapter 3: the road ------------------------------------------------------

func _the_road() -> void:
	# Out of the gate first: a rest inside the walls is the inn's business.
	var here: Vector2 = screen.world.player().position
	await _into_the_open(here + Vector2(260, -160))
	await _step(4)

	var clock0: float = screen.world.clock.elapsed
	screen.party.short_rests_since_long = 0
	if _must_press("Short Rest", screen, "on the bottom bar"):
		await _step(2)
		check("road:shortrest",
			screen.world.clock.elapsed >= clock0 + Visit.SHORT_REST_MINUTES,
			"an hour on the road cost %.0f minutes" % (screen.world.clock.elapsed - clock0))

	# The camp kit bought in chapter 2 buys a long rest out here. The cooldown
	# is the inn's night, so it is wound back rather than waited out — a day of
	# walking to re-earn a button press is not what this file is measuring.
	screen.party.last_long_rest_at = -1e12
	for ch in screen.party.party_characters():
		ch.hp_current = 1
	var kits: int = screen.party.stash_count(WorldCamp.CAMP_KIT_ITEM)
	if kits <= 0:
		fail("road:camp — no camp kit in the pack; the market chapter did not buy one")
	elif _must_press("Make Camp", screen, "while carrying a camp kit"):
		# Three nights are possible and all three are the button working: the
		# camp holds (eight hours and the party's wounds), the watch hears them
		# coming, or the camp is jumped in the dark. Which one is on the card,
		# read before anything awaits — _step() dismisses cards by itself.
		var night := ""
		if is_instance_valid(screen._event_card):
			night = String(screen._event_card._e.get("id", ""))
		await _step(4)
		var raided: bool = screen._combat != null
		if raided:
			await _see_the_fight_out()
		var healed := true
		for ch in screen.party.party_characters():
			healed = healed and int(screen.party.summary(ch.id)["hp"]) > 1
		# What is not allowed is the kit being spent on nothing at all.
		check("road:camp", screen.party.stash_count(WorldCamp.CAMP_KIT_ITEM) == kits - 1
			and (healed or raided),
			"the night was '%s': kits %d -> %d, healed=%s, raided=%s" % [night, kits,
				screen.party.stash_count(WorldCamp.CAMP_KIT_ITEM), healed, raided])

# --- chapter 4: the lair ------------------------------------------------------

# How many hidden lairs the search may try before calling it (see _the_lair).
const SEARCH_TRIES := 3

func _the_lair() -> void:
	# Two ways a lair gets onto the map and a completionist uses both: the
	# Survival check out in the field, and the lead bought at the inn last
	# chapter. The search goes first, because it needs a lair nobody has named
	# yet and the lead names one.
	#
	# The lair can be found on the way to it: a road event (core/travel.gd's
	# refugees and lore) names the nearest undiscovered lair, and a walk is long
	# enough for one to fire. Arriving at a lair something else has just put on
	# the map, the button is Enter, not Search, and pressing it walked into the
	# warren — the search "said nothing" and the tour was left inside a delve.
	# That is the map working, not a door failing, so the robot looks again on
	# arrival and moves on to the next hidden lair, a few times at most. Which
	# walk a road event lands in follows the clock, which follows how long the
	# fights before it took: it showed up once the party autopilot started
	# spending its whole turn and those fights got shorter.
	await _search_for_lair()

	var known = _nearest_known_lair()
	if not check("lair:found", known != null,
			"nothing on the map is a discovered, unlooted lair — neither door worked"):
		return
	var which: String = known.id
	if not await _walk_to(known.position, which):
		return
	await _step(4)
	if screen._lair_btn == null or not screen._lair_btn.visible:
		fail("lair:enter — standing on the discovered %s offers no way in" % which)
		return

	# Two doors. The quiet one is only on the table while the warren is quiet,
	# so it is taken when offered and the loud one kicked otherwise.
	if screen._lair_sneak_btn != null and screen._lair_sneak_btn.visible:
		screen._lair_sneak_btn.pressed.emit()
		await _step(4)
		did("lair:sneak")
	if screen._site_screen == null and screen._combat == null and not known.looted:
		screen._lair_btn.pressed.emit()
		await _step(4)
	if screen._site_screen != null:
		did("lair:delve")
		await _work_the_delve()
	if screen._combat != null:
		await _see_the_fight_out()
	check("lair:enter", _ledger.has("lair:sneak") or _ledger.has("lair:delve") or known.looted,
		"neither door into %s opened" % which)

# The Survival check in the field — on the free plane, standing on a hidden lair.
func _search_for_lair() -> void:
	var named_first := 0
	for _try in SEARCH_TRIES:
		var hidden = _nearest_hidden_lair()
		if hidden == null:
			fail("lair:search — every lair on the %s map was already on it" % MAP)
			break
		if not await _walk_to(hidden.position, hidden.id):
			break
		await _step(4)
		if hidden.discovered:
			named_first += 1
			print("  lair:search — %s was put on the map on the way there; trying the next hidden lair" % hidden.id)
			continue
		if screen._lair_btn == null or not screen._lair_btn.visible:
			fail("lair:search — standing on %s offers no lair button" % hidden.id)
			break
		screen._lair_msg.text = ""
		screen._lair_btn.pressed.emit()
		await _step(2)
		# Whether the roll lands is the dice's business. That the button
		# rolls at all, and says what it rolled, is this file's.
		check("lair:search", "Survival" in screen._lair_msg.text,
			"searching %s said '%s'" % [hidden.id, screen._lair_msg.text])
		break
	if named_first == SEARCH_TRIES:
		fail("lair:search — each of %d hidden lairs was put on the map by something else before the party reached it" % SEARCH_TRIES)

func _nearest_hidden_lair():
	return _nearest_lair(func(l): return not l.discovered and not l.looted)

func _nearest_known_lair():
	return _nearest_lair(func(l): return l.discovered and not l.looted)

func _nearest_lair(want: Callable):
	var p = screen.world.player()
	var best = null
	for l in screen.world.lairs:
		if not want.call(l):
			continue
		if best == null or p.position.distance_to(l.position) < p.position.distance_to(best.position):
			best = l
	return best

func _lair_by_id(id: String):
	for l in screen.world.lairs:
		if l.id == id:
			return l
	return null

# The descent screen, played the way it is meant to be: pick a fork, take what
# is in the room, go on, and — two rooms down, because this is a tour and not a
# raid — withdraw and take the way out it offers. Every state of the screen
# (picking, visiting, the outcome) has to hand over a button, and the screen has
# to be gone at the end of it: a delve left mounted blocks every settlement gate
# and every march order for the rest of the run (world.gd's _overlay_up).
const DELVE_DEPTH := 2
func _work_the_delve() -> void:
	for i in 400:
		if screen._site_screen == null:
			return
		if screen._combat != null:
			await _see_the_fight_out()
			continue
		var btns := _buttons(screen._site_screen)
		if btns.is_empty():
			await _step()                      # mid-room: the screen hides itself
			continue
		if _press("Take", screen._site_screen) or _press("Rest an hour", screen._site_screen):
			pass
		elif _press("Go on", screen._site_screen):
			pass
		elif screen._site != null and String(screen._site.state) == "picking":
			if int(screen._site.depth) < DELVE_DEPTH and btns.size() > 1:
				btns[0].pressed.emit()         # a fork; Withdraw is always last
			elif not _press("Withdraw", screen._site_screen):
				fail("lair:delve — no way to withdraw from a delve between rooms")
				break
		else:
			btns[btns.size() - 1].pressed.emit()   # the outcome page's way back
		await _step(2)
	if screen._site_screen != null:
		fail("lair:delve — the descent screen would not close")

# --- chapter 5: the four ways of meeting a band -------------------------------

const WAYS := ["engage", "ambush", "parley", "avoid"]

func _the_meetings() -> void:
	# Out of everyone's way first: a band closing on the party at a town gate
	# means the market opens on top of the card, and a chapter that wanders into
	# a settlement leaves one open behind it.
	await _into_the_open(_open_country())
	for way in WAYS:
		if _ledger.has("meet:" + way):
			continue
		_daylight()
		# Arranged, per the header: the map ships two bands and there are four
		# ways. A band is put on the road in front of the party, which is what
		# the map does by itself, just not four times inside one tour.
		var p = screen.world.player()
		var band = _band_in_the_way(way)
		screen._halted_on_arrival = false
		screen.world.clock.resume()
		var waited := 0
		while not is_instance_valid(screen._approach_card) and waited < 400:
			waited += 1
			_close_in(p, band)                            # walk, so the band closes
			await _step()
			if screen._combat != null:                    # met without being asked
				await _see_the_fight_out()
				break
		if is_instance_valid(screen._approach_card):
			did("meet:card")
			_meet_them(way)
			await _step(4)
			while is_instance_valid(screen._event_card):
				screen._event_card.acknowledged.emit()
				await _step(2)
			if screen._combat != null:
				await _see_the_fight_out()
		_band_gone(band)
	if not _ledger.has("meet:card"):
		fail("meet:card — no band ever asked how the party wanted to meet it")
	_daylight()

# #85: in the dark a hostile band is on the party before anyone can choose how
# to meet it, unless the watch hears them coming — which is that rule working,
# not a door failing to open. So the meetings are held in daylight, the clock
# wound on to mid-morning the way a night at an inn winds it on eight hours.
func _daylight() -> void:
	var clock = screen.world.clock
	for i in 48:
		var h: float = clock.hour_of_day()
		if h >= 8.0 and h <= 16.0:
			return
		clock.elapsed += 60.0

# The point on the map furthest from anything that owns a screen.
func _open_country() -> Vector2:
	var p = screen.world.player()
	var best: Vector2 = p.position
	var far := -1.0
	for step in [Vector2(520, 520), Vector2(-520, 520), Vector2(520, -520), Vector2(-520, -520)]:
		var at: Vector2 = p.position + step
		var near := 1e9
		for s2 in screen.world.settlements:
			near = minf(near, at.distance_to(s2.position))
		if near > far:
			far = near
			best = at
	return best

# Answer the approach card. `prefer` is taken when the card offers it — the card
# decides what is on the table (the mindless do not parley), so an unoffered way
# is not a failure, just a way this tour did not get to tick.
func _meet_them(prefer := "") -> void:
	var card = screen._approach_card
	var picked := ""
	var fallback: Button = null
	for b in card.get_children():
		if not (b is Button) or b.disabled or b.is_queued_for_deletion():
			continue
		var way := String(b.name).get_slice("_", 2)
		if fallback == null:
			fallback = b
		if way == prefer:
			picked = way
			did("meet:" + way)
			b.pressed.emit()
			return
	if fallback != null:
		picked = String(fallback.name).get_slice("_", 2)
		did("meet:" + picked)
		fallback.pressed.emit()

# --- chapter 6: the rest of the map -------------------------------------------

func _the_rest_of_the_map() -> void:
	var visited := {}
	if not screen._visit.is_empty():
		screen._close_visit()
	visited[CITY] = true

	# The elf town, then the dwarf camp — the camp being the one that staffs
	# nobody, which D7 made true and nothing else here would notice.
	for name in [TOWN, CAMP]:
		var s = _settlement(name)
		if s == null:
			fail("the %s map has no %s" % [MAP, name])
			continue
		if not await _walk_into(s, name):
			continue
		await _step(6)
		if screen._visit.is_empty():
			fail("town:every — walking into %s opened no market" % name)
			continue
		visited[name] = true
		if name == CAMP:
			check("town:camp-has-none", Visit.services(s).size() == 1,
				"%s staffs %s" % [name, Visit.services(s)])
		screen._close_visit()
		await _step(2)
		# Out of range, so the gate does not swallow the next march order.
		await _step_out_of(s, name)

	# ...and the gate that never trades.
	var gate = _settlement(GATE)
	if gate == null:
		fail("the %s map has no %s" % [MAP, GATE])
	elif await _walk_into(gate, GATE, true):
		visited[GATE] = true
		check("gate:no-market", screen._visit.is_empty(), "%s ran a friendly market" % GATE)
		if check("gate:fight", screen._combat != null, "%s did not turn out the guard" % GATE):
			await _see_the_fight_out()

	check("town:every", visited.size() == screen.world.settlements.size(),
		"walked into %d of the map's %d settlements" % [visited.size(), screen.world.settlements.size()])

# --- the verdict --------------------------------------------------------------

func _verdict() -> void:
	var missed: Array = []
	for deed in REQUIRED:
		if not _ledger.has(deed):
			missed.append(deed)
			fail("%s — never reached: %s" % [deed, REQUIRED[deed]])
	var skipped: Array = []
	for deed in OPPORTUNISTIC:
		if not _ledger.has(deed):
			skipped.append(deed)
	print("%s: %d frames, %d/%d required, %d/%d opportunistic — %s" % [
		"drive_completionist_routes" if _routes() else "drive_completionist", _frames, REQUIRED.size() - missed.size(), REQUIRED.size(),
		OPPORTUNISTIC.size() - skipped.size(), OPPORTUNISTIC.size(),
		"OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	var ticked: Array = _ledger.keys()
	ticked.sort()
	for deed in ticked:
		if not REQUIRED.has(deed) and not OPPORTUNISTIC.has(deed):
			fail("'%s' was ticked but is on neither list — the checklist has drifted" % deed)
	print("  ticked: ", ticked)
	if not skipped.is_empty():
		print("  not offered this run (never a failure): ", skipped)
	if not missed.is_empty():
		printerr("  MISSED: ", missed)
	WorldSave.clear()
	quit(1 if _fail > 0 else 0)

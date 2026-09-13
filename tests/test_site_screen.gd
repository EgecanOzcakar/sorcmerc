# D1 — the site's descent diagram (scenes/world/site_screen.gd), driven through
# its real button tree the way tests/test_world_visit_pages.gd drives a visit.
# What this proves is the seam: the screen reports, the model is driven from
# outside it, and the two in-room actions (a cache, an hour) are the only things
# it touches for itself. The look is checked by eye with a shot script; what is
# checked here is that each state puts up the right controls and that pressing
# them neither lies to the world screen nor edits the site behind its back.
#   godot --headless --path . -s tests/test_site_screen.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")
const Party = preload("res://core/party.gd")
const SiteScreen = preload("res://scenes/world/site_screen.gd")

var _pass := 0
var _fail := 0

# Signal tallies. Members rather than captured locals: a lambda closes over a
# copy of a local, so a counter incremented inside one would never be seen here.
var _picked := -99
var _picks := 0
var _withdrew := 0
var _advanced := 0
var _done := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func has_button(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text:
			return true
	return false

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text and not b.disabled:
			b.pressed.emit()
			return true
	return false

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _lair(id := "goblin-warren", faction := "goblinoid"):
	return World.Lair.new(id, Vector2(100, 100), faction)

func _screen(site, party) -> Control:
	var s = SiteScreen.new()
	s.site = site
	s.party = party
	root.add_child(s)
	s.room_chosen.connect(_on_room_chosen)
	s.withdrew.connect(func(): _withdrew += 1)
	s.advanced.connect(func(): _advanced += 1)
	s.done.connect(func(): _done += 1)
	s.refresh()
	return s

func _on_room_chosen(index: int) -> void:
	_picked = index
	_picks += 1

# The first depth of a site is generated, so which kinds of room it offers
# depends on the lair's id. Walk ids until one opens with the kind wanted, and
# return [site, index of that room].
func _site_opening_with(kind: String, party, w) -> Array:
	for i in 200:
		var site = Site.for_lair(_lair("lair-%d" % i), party, w)
		var opts: Array = site.options()
		for j in opts.size():
			if String(opts[j]["kind"]) == kind:
				return [site, j]
	return []

func _index_of_kind(site, kind: String) -> int:
	var opts: Array = site.options()
	for j in opts.size():
		if String(opts[j]["kind"]) == kind:
			return j
	return -1

func _init() -> void:
	var w := _world()
	var party := _party()

	# --- a screen with nothing in it -------------------------------------
	# The world screen builds this thing before it has anything to show, and a
	# headless test builds it with no model at all: neither may throw.
	var empty = SiteScreen.new()
	root.add_child(empty)
	empty.refresh()
	check(buttons(empty).is_empty(), "a screen with no site offers nothing to press")
	check(empty._rows().size() == 1, "...and still has a layout rather than a divide by zero")
	empty.queue_free()

	# --- picking: the fork ------------------------------------------------
	var site = Site.for_lair(_lair(), party, w)
	var screen := _screen(site, party)
	var opts: Array = site.options()
	check(screen.visible, "the diagram is up while there is a choice to make")
	check(screen._rows().size() == site.depth_total(), "one row per depth, boss included")
	check(screen._xs(site.depth).size() == opts.size(), "the live row forks once per option")
	check(screen._xs(site.depth_total() - 1).size() == 1, "the bottom of the shaft is one room")
	for r in opts:
		check(has_button(screen, String(r["title"])), "every way on is a button: %s" % r["title"])
	check(has_button(screen, "Withdraw"), "you can get out from between rooms")
	check(buttons(screen).size() == opts.size() + 1, "and nothing else is offered here")

	# Clicking a fork reports it and touches nothing.
	var want: int = mini(1, opts.size() - 1)
	check(press(screen, String(opts[want]["title"])), "a fork can actually be clicked")
	check(_picked == want and _picks == 1, "...and reports the index it was given")
	check(site.state == "picking" and site.depth == 0 and site.room.is_empty(),
		"...without entering the room itself — that is the world screen's move")

	check(press(screen, "Withdraw"), "Withdraw is a live button")
	check(_withdrew == 1, "...and says so")
	check(site.state == "picking", "...but does not walk out on its own either")

	# --- combat: the screen gets out of the way ---------------------------
	var fight: int = _index_of_kind(site, "combat")
	site.enter(fight)
	screen.refresh()
	check(site.state == "combat", "the test is standing in for the world screen here")
	check(not screen.visible, "the diagram hides itself while the fight is on")
	check(buttons(screen).is_empty(), "...and leaves no button behind to catch a click")

	# A fight survived puts the fork back up.
	site.finish_combat({"outcome": "Victory"})
	site.leave()
	screen.refresh()
	check(screen.visible and has_button(screen, "Withdraw"),
		"and the diagram comes back, one room deeper")
	check(site.depth == 1, "...on the depth the model moved to")
	screen.queue_free()

	# --- visiting a cache -------------------------------------------------
	var found := _site_opening_with("treasure", party, w)
	check(not found.is_empty(), "some lair opens on a cache (fixture sanity)")
	if not found.is_empty():
		var t_site = found[0]
		_advanced = 0
		var t_screen := _screen(t_site, party)
		t_site.enter(int(found[1]))
		t_screen.refresh()
		check(t_site.state == "visiting", "a cache is walked into, not fought")
		check(has_button(t_screen, "Take"), "a cache offers the one thing a cache is")
		check(not has_button(t_screen, "Withdraw"),
			"you cannot back out of the lair from inside a room")
		var before: int = party.gold
		check(press(t_screen, "Take"), "Take is live")
		check(party.gold > before, "...and the gold is really banked (%d -> %d)" % [before, party.gold])
		check(bool(t_site.room.get("taken", false)), "...and the room knows it is empty")
		check(not press(t_screen, "Take"), "a spent cache is not a button that shrugs")
		check(press(t_screen, "Go on"), "and there is a way on out of the room")
		check(_advanced == 1, "...which asks the world screen to leave the room")
		check(t_site.state == "visiting", "...rather than leaving it itself")
		t_screen.queue_free()

	# --- visiting an hour -------------------------------------------------
	var rested := _site_opening_with("rest", party, w)
	check(not rested.is_empty(), "some lair opens on somewhere to sit down (fixture sanity)")
	if not rested.is_empty():
		var r_site = rested[0]
		var r_screen := _screen(r_site, party)
		r_site.enter(int(rested[1]))
		r_screen.refresh()
		check(has_button(r_screen, "Rest an hour"), "a rest room offers the only rest in here")
		check(press(r_screen, "Rest an hour"), "...and it can be taken")
		check(bool(r_site.room.get("rested", false)), "...once")
		check(not press(r_screen, "Rest"), "...and only once")
		r_screen.queue_free()

	# --- the three ways a site ends ---------------------------------------
	# Each reached the way the model really reaches it, not by poking `state`.
	var out_site = Site.for_lair(_lair("quiet-hole"), party, w)
	out_site.withdraw()
	var out_screen := _screen(out_site, party)
	check(not has_button(out_screen, "Withdraw"), "a site you already left cannot be left again")
	check(press(out_screen, "Back to the map"), "withdrawing puts up a way back to the map")
	check(_done == 1, "...and acknowledging it hands control back")
	out_screen.queue_free()

	var dead_site = Site.for_lair(_lair("bad-hole"), party, w)
	dead_site.enter(_index_of_kind(dead_site, "combat"))
	dead_site.finish_combat({"outcome": "Defeat"})
	var dead_screen := _screen(dead_site, party)
	check(dead_site.state == "wiped", "a lost fight wipes the party (fixture sanity)")
	check(dead_screen.visible, "a wipe is shown, not hidden with the combat screen")
	check(buttons(dead_screen).size() == 1, "a terminal state offers exactly one button")
	check(press(dead_screen, "Drag them out"), "...and it is the way out")
	check(_done == 2, "...which is the same acknowledgement signal")
	dead_screen.queue_free()

	var won_site = Site.for_lair(_lair("done-hole"), party, w)
	while not won_site.is_over():
		var room: Dictionary = won_site.enter(0)
		if room.is_empty():
			break
		match String(room["kind"]):
			"combat": won_site.finish_combat({"outcome": "Victory"})
			"treasure": won_site.take()
			"rest": won_site.short_rest()
		won_site.leave()
	check(won_site.state == "cleared", "walking the whole thing clears it (fixture sanity)")
	var won_screen := _screen(won_site, party)
	check(won_screen._rows().size() == won_site.depth_total(),
		"the shaft is still drawn once it is over — that is how deep it was")
	check(not has_button(won_screen, "Withdraw"), "there is nothing left to withdraw from")
	check(press(won_screen, "Back to the map"), "a cleared site says so, with a way out")
	check(_done == 3, "...through the same door")
	won_screen.queue_free()

	# --- a party that isn't there -----------------------------------------
	var lonely = Site.for_lair(_lair("lonely-hole"), party, w)
	var lonely_screen = SiteScreen.new()
	lonely_screen.site = lonely
	root.add_child(lonely_screen)
	lonely_screen.refresh()
	check(not buttons(lonely_screen).is_empty(), "a null party still leaves a usable diagram")
	lonely_screen.queue_free()

	print("test_site_screen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

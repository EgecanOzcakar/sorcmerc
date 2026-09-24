# T9x: the Party screen's "Map figure" picker (core/party.gd's
# overworld_figure) — drives the real scene's OptionButton, not just the
# data field, so a broken wire (wrong metadata, item order) would show up.
# Options are the ACTIVE party's own members, one row per person — so picking
# Vera sets overworld_figure to "vera", two members of the same class are two
# rows that each stick, and nobody outside the active four is offered at all.
#
# D3: and the standing-orders row under it — pace, scout, watch. Same idea,
# same reason: the orders are what resolve everything that happens on the road
# (core/travel.gd), so a picker that writes the display name instead of the id,
# or keeps showing a benched scout, is a silent wrong answer out there.
#   godot --headless --path . -s tests/test_party_screen.gd
extends SceneTree

const Travel = preload("res://core/travel.gd")
const Leveling = preload("res://core/leveling.gd")   # #118: the roster row's Level up
const PartyOpinion = preload("res://core/party_opinion.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The row carrying this member id, or -1.
func index_of(ob: OptionButton, member_id: String) -> int:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == member_id:
			return i
	return -1

# The footer holds four pickers now, so address them by name rather than by
# "the first OptionButton in the tree" — which would silently start testing a
# different control the day somebody reorders the footer. Anything already
# queue_free()d is skipped on principle; it is never the one we mean.
func node_named(node: Node, want: String) -> Node:
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if String(c.name) == want:
			return c
		var hit := node_named(c, want)
		if hit != null:
			return hit
	return null

func picker(node: Node, want: String) -> OptionButton:
	return node_named(node, want) as OptionButton

# What a picker currently reads as: the member id / pace behind its selection.
func chosen(ob: OptionButton) -> String:
	return String(ob.get_item_metadata(ob.selected))

func labels_of(ob: OptionButton) -> String:
	var out := ""
	for i in ob.item_count:
		out += ob.get_item_text(i) + "|"
	return out

func _init() -> void:
	var screen = load("res://scenes/party/party.tscn").instantiate()
	root.add_child(screen)
	await process_frame

	var ob := picker(screen, "FigurePicker")
	check(ob != null, "the map-figure picker exists")
	if ob == null:
		quit(1); return

	# The demo roster's active four: Vera (fighter), Pike (rogue), Ilsa
	# (cleric), Thrun (barbarian) — Gera (the 5th, a barbarian) is benched
	# and should NOT be offered.
	check(ob.item_count == screen.party.active.size() + 1,
		"one entry per ACTIVE member, plus the default (got %d)" % ob.item_count)
	check(String(ob.get_item_metadata(0)) == "", "the first entry is the default (no figure)")
	check(ob.selected == 0, "a fresh party starts on the default")
	var names := labels_of(ob)
	check("Vera Kord" in names, "an active member is offered by name")
	check(not "Gera" in names, "a benched member is not offered")

	# Pick a real, active member and confirm the field updates — with their
	# id, the character, not "fighter", the class.
	var vera_idx := index_of(ob, "vera")
	check(vera_idx >= 0, "Vera is one of the offered figures, by her own id")
	ob.select(vera_idx)
	ob.item_selected.emit(vera_idx)
	check(screen.party.overworld_figure == "vera", "picking one actually sets overworld_figure")

	# Re-opening the screen with that party should show the pick already made.
	var screen2 = load("res://scenes/party/party.tscn").instantiate()
	screen2.party = screen.party
	root.add_child(screen2)
	await process_frame
	var ob2 := picker(screen2, "FigurePicker")
	check(ob2 != null and chosen(ob2) == "vera",
		"reopening the screen shows the previously chosen figure selected")

	# Two members of the same class are two rows, and each one sticks: swap
	# the benched Gera (barbarian) in for Ilsa and the active four hold two
	# barbarians, Gera and Thrun.
	check(screen.party.swap("ilsa", "gera"), "swap Gera in for Ilsa")
	screen._refresh()
	await process_frame          # the previous picker is only queue_free()d
	ob = picker(screen, "FigurePicker")
	var gera_idx := index_of(ob, "gera")
	var thrun_idx := index_of(ob, "thrun")
	check(gera_idx >= 0 and thrun_idx >= 0 and gera_idx != thrun_idx,
		"two barbarians are two separate, individually selectable rows")
	for who in ["gera", "thrun"]:
		ob.select(index_of(ob, who))
		ob.item_selected.emit(index_of(ob, who))
		check(screen.party.overworld_figure == who, "picking %s sets exactly %s" % [who, who])
		screen._refresh()
		await process_frame
		ob = picker(screen, "FigurePicker")
		check(chosen(ob) == who, "and %s is still the one shown selected" % who)

	# Back-compat: a save written before the switch holds a class id. The
	# picker resolves it the old way — the first active member of that class,
	# Gera here — and core/party.gd migrates the field to her id.
	screen.party.overworld_figure = "barbarian"
	screen._refresh()
	await process_frame
	ob = picker(screen, "FigurePicker")
	check(chosen(ob) == "gera",
		"an old save's class id opens on the member it resolves to")
	check(screen.party.overworld_figure == "gera", "...and the field is migrated to that member's id")

	# --- D3: standing orders ------------------------------------------------
	#
	# Active party from here on: Vera (fighter), Pike (rogue), Gera and Thrun
	# (both barbarians). Ilsa is on the bench.
	var pace_ob := picker(screen, "PacePicker")
	var scout_ob := picker(screen, "ScoutPicker")
	var watch_ob := picker(screen, "WatchPicker")
	check(pace_ob != null and scout_ob != null and watch_ob != null,
		"the pace, scout and watch pickers all exist")
	if pace_ob == null or scout_ob == null or watch_ob == null:
		print("test_party_screen: %d passed, %d failed" % [_pass, _fail])
		quit(1); return

	check(pace_ob.item_count == Travel.PACES.size(),
		"one entry per pace (got %d)" % pace_ob.item_count)
	check(labels_of(pace_ob) == "Careful|Normal|Forced march|",
		"the paces are labelled by travel.gd (got %s)" % labels_of(pace_ob))
	check(chosen(pace_ob) == "normal", "a party with no orders yet opens on the default pace")

	var offered := labels_of(scout_ob)
	check(scout_ob.item_count == screen.party.active.size() + 1,
		"scout offers every ACTIVE member over 'whoever is best' (got %d)" % scout_ob.item_count)
	check(String(scout_ob.get_item_metadata(0)) == "",
		"...and that first entry is the empty order, not a person")
	check(scout_ob.selected == 0, "nobody is named until the player names somebody")
	check("Vera Kord" in offered and "Pike Sallow" in offered,
		"the active party is offered by name (got %s)" % offered)
	check(not "Ilsa" in offered, "a benched member cannot be given a job")
	check(watch_ob.item_count == scout_ob.item_count, "watch offers exactly the same people")

	# Pace: writes through, and travel.gd reads the trade off it.
	var careful := index_of(pace_ob, "careful")
	pace_ob.select(careful)
	pace_ob.item_selected.emit(careful)
	await process_frame
	check(String(Travel.orders(screen.party)["pace"]) == "careful", "picking a pace writes through")
	check(is_equal_approx(Travel.speed_mult(screen.party), 0.70), "...travel marches at 0.70x for it")
	check(Travel.pace_bonus(screen.party) == 2, "...and rolls +2 on the road")
	screen._refresh()
	await process_frame
	pace_ob = picker(screen, "PacePicker")
	check(chosen(pace_ob) == "careful", "the pace is still the one shown after a _refresh()")

	# The note is the whole reason the trade is visible without reading source.
	var note := node_named(screen, "PaceNote") as Label
	check(note != null and Travel.pace_note("careful") in note.text,
		"the note under the picker is the selected pace's own")
	check(note != null and "0.70" in note.text and "+2" in note.text,
		"...and it spells the trade out in numbers (got %s)" % (note.text if note != null else ""))
	var forced := index_of(pace_ob, "forced")
	pace_ob.select(forced)
	pace_ob.item_selected.emit(forced)
	await process_frame
	note = node_named(screen, "PaceNote") as Label
	check(note != null and Travel.pace_note("forced") in note.text and "-2" in note.text,
		"changing the pace changes the note under it")

	# Scout: the order is a member id, not the display name on the row.
	scout_ob = picker(screen, "ScoutPicker")
	var pike_row := index_of(scout_ob, "pike")
	check(pike_row > 0, "Pike is offered for the job by her own id")
	scout_ob.select(pike_row)
	scout_ob.item_selected.emit(pike_row)
	await process_frame
	check(String(Travel.orders(screen.party)["scout"]) == "pike",
		"naming a scout writes the member id, not 'Pike Sallow'")
	check(String(Travel.orders(screen.party)["pace"]) == "forced",
		"...and writes the other standing orders back untouched beside it")

	# Two barbarians are two people, and each one sticks — the same thing the
	# figure picker guarantees above, for a setting travel.gd rolls against.
	watch_ob = picker(screen, "WatchPicker")
	check(index_of(watch_ob, "gera") > 0 and index_of(watch_ob, "thrun") > 0
		and index_of(watch_ob, "gera") != index_of(watch_ob, "thrun"),
		"two members of one class are two separately nameable rows")
	for who in ["gera", "thrun"]:
		watch_ob = picker(screen, "WatchPicker")
		var row := index_of(watch_ob, who)
		watch_ob.select(row)
		watch_ob.item_selected.emit(row)
		await process_frame
		check(String(Travel.orders(screen.party)["watch"]) == who, "the watch is exactly %s" % who)
		screen._refresh()
		await process_frame
		check(chosen(picker(screen, "WatchPicker")) == who, "and %s is the one still shown" % who)

	# Bench the named scout: an order naming somebody who is not marching is
	# not an order, and the control has to say so rather than show a stale name.
	check(screen.party.bench("pike"), "bench the named scout")
	screen._refresh()
	await process_frame
	scout_ob = picker(screen, "ScoutPicker")
	check(scout_ob.selected == 0 and chosen(scout_ob) == "",
		"benching the named scout drops the picker back to 'whoever is best'")
	check(not "Pike" in labels_of(scout_ob), "...she is not offered for the job any more")
	check(String(Travel.orders(screen.party)["scout"]) == "", "...and travel agrees nobody is named")
	check(String(Travel.orders(screen.party)["watch"]) == "thrun",
		"...while the watch, still marching, keeps their job")

	await _level_up_per_character(screen)
	await _bench_first(screen)
	await _relations(screen)
	print("test_party_screen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Issue #118: a level is spent per character, so the roster row is where the
# button that spends it belongs — live for whoever has the XP, greyed with the
# reason for everyone else. And the profile it opens draws its way out inside
# its own header, because a Button floated in the top-right corner landed on
# top of that screen's Level up.
func _level_up_per_character(screen) -> void:
	screen._refresh()
	await process_frame
	var rows := _buttons_named(screen._roster_col, "Level up")
	check(rows.size() == screen.party.roster.size(),
		"one Level up button per roster row (%d for %d)" % [rows.size(), screen.party.roster.size()])
	check(rows.all(func(b): return b.disabled),
		"nobody in a fresh demo party has the XP, so every one of them is greyed")
	check(rows.all(func(b): return b.tooltip_text.contains("XP") or b.tooltip_text.contains("dead")),
		"...and each says why")

	var who = screen.party.roster[0]
	who.xp = Leveling.xp_for_level(who.level() + 1)
	screen._refresh()
	await process_frame
	rows = _buttons_named(screen._roster_col, "Level up")
	var live: Array = rows.filter(func(b): return not b.disabled)
	check(live.size() == 1, "banking a level lights exactly one row's button (%d)" % live.size())
	if live.is_empty():
		return
	check(live[0].tooltip_text.contains("level %d" % (who.level() + 1)),
		"and it names the level waiting (%s)" % live[0].tooltip_text)

	# Pressing it is the profile plus the level-up page, in one press.
	live[0].pressed.emit()
	await process_frame
	var prof = _node_with_method(screen, "level_up")
	check(prof != null, "the row's button opens that character's profile")
	if prof == null:
		return
	check(prof.character() == who, "...the right character's")
	check(_node_with_method(prof, "commit") != null, "...with the level-up page already on it")
	# The way out is a control in the header, not a floating button over it.
	check(String(prof.exit_label) != "", "the profile was handed a way out")
	var ex = prof._fields.get("exit_btn")
	var lvl = prof._fields.get("level_up_btn")
	check(ex != null and lvl != null, "both the exit and Level up are laid out controls")
	if ex == null or lvl == null:
		return
	check(ex.get_parent() == lvl.get_parent(),
		"and they share the header row, so neither can be drawn over the other")

func _buttons_named(node: Node, text: String) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and String(c.text) == text and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(_buttons_named(c, text))
	return out

func _node_with_method(node: Node, m: String):
	for c in node.get_children():
		if c.has_method(m) and not c.is_queued_for_deletion():
			return c
		var hit = _node_with_method(c, m)
		if hit != null:
			return hit
	return null

# The roster column leads with the bench, under its own head, so a substitute
# is the first thing on the left rather than below the marching four; the
# marching party follows under theirs, in marching order. A substitute's To
# party is the primary button while a slot is free. The Relations web has a
# card of its own under the marching column, as wide as it; the standing
# orders are a short strip along the bottom.
func _bench_first(screen) -> void:
	var p = screen.party
	var out: String = p.active[p.active.size() - 1]
	p.bench(out)
	screen._refresh()
	await process_frame
	var kids: Array = screen._roster_col.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var benched: Array = p.roster.filter(func(ch): return not p.is_active(ch.id))
	check(kids.size() > 0 and String(kids[0].get_meta("group", "")) == "On the bench",
		"the column opens with the bench's head (%s)" % (str(kids[0].get_meta("group", kids[0].name)) if kids.size() > 0 else "nothing"))
	if kids.size() < 3 + benched.size():
		check(false, "the column holds both heads and every row (%d)" % kids.size())
		return
	check(_all_labels(kids[0]) == ["On the bench · %d" % benched.size()], "...which counts them: %s" % str(_all_labels(kids[0])))
	var names_after_head: Array = []
	for k in range(1, 1 + benched.size()):
		names_after_head.append(_all_labels(kids[k])[0])
	check(benched.all(func(ch): return names_after_head.any(func(t): return ch.cname in t)),
		"...and the substitutes come straight after it: %s" % str(names_after_head))
	var mhead = kids[1 + benched.size()]
	check(String(mhead.get_meta("group", "")) == "Marching" and _all_labels(mhead) == ["Marching · %d" % p.active.size()],
		"then the marching party's head")
	var first_marching: Array = _all_labels(kids[2 + benched.size()])
	check(p.get_member(p.active[0]).cname in first_marching[0], "...in marching order: %s" % first_marching[0])
	var to_party := _buttons_named(kids[1], "To party")
	check(to_party.size() == 1 and to_party[0].theme_type_variation == "Primary",
		"a substitute's To party is the primary button while a slot is free")
	var card = node_named(screen, "RelationsCard")
	var marching: Control = screen._slot_col.get_parent().get_parent()   # the column: head, scroll, slots
	check(card != null and card.visible and card.get_parent() == marching.get_parent(),
		"the relations sit in a card of their own, under the marching column")
	await process_frame
	if card != null:
		check(absf(card.size.x - marching.size.x) < 1.0,
			"...as wide as it (%d and %d)" % [card.size.x, marching.size.x])
	var note := node_named(screen, "PaceNote") as Label
	check(note != null and note.autowrap_mode == TextServer.AUTOWRAP_OFF and note.tooltip_text == note.text,
		"the orders strip keeps the pace note to one line, the whole of it on hover")
	p.activate(out)
	screen._refresh()
	await process_frame

# The Relations block beside the standing orders: a caption and a drawn web
# (scenes/party/relations_web.gd) with one line per active pair, each line's
# band the pair's band() and its hover the pair's describe(), so the words are
# still one mouse-over away. A party of one has nobody to get on with, and
# shows nothing.
func _relations(screen) -> void:
	var p = screen.party
	var a: String = p.active[0]
	var b: String = p.active[1]
	PartyOpinion.set_score(p, a, b, -44.0)
	screen._refresh()
	await process_frame
	var row = node_named(screen, "RelationsRow")
	var lines := _label_texts(row)
	check(lines == ["Relations"], "the block is captioned, and says nothing else in words (%s)" % str(lines))
	var web = node_named(screen, "RelationsWeb")
	check(web != null, "the relations are drawn as a web")
	if web == null:
		return
	web.size = web.custom_minimum_size
	var es: Array = web.edges()
	check(es.size() == PartyOpinion.active_pairs(p).size(),
		"one line per active pair (%d for %d)" % [es.size(), PartyOpinion.active_pairs(p).size()])
	var first: Dictionary = es[0]
	check(first["a"] == a and first["b"] == b and first["band"] == "rivals" and int(first["score"]) == -44,
		"the soured pair's line is a rivals line: %s" % str(first))
	# Hovering the middle of that line says it in words, as describe() does.
	var pos: Array = web.face_positions()
	var mid: Vector2 = (pos[0] + pos[1]) * 0.5
	var want := PartyOpinion.describe(p, a, b)
	check(web.edge_at(mid) == 0, "the mouse on the line finds it")
	check("rivals (-44)" in want and web.tooltip_at(mid) == want, "...and its tooltip is describe(): %s" % web.tooltip_at(mid))
	# Over a face: every line that person is on.
	var mine: String = web.tooltip_at(pos[0])
	check(mine.split("\n").size() == p.active.size() - 1 and want in mine,
		"a face's tooltip lists each of its pairs (%d lines)" % mine.split("\n").size())
	check(web.tooltip_at(Vector2(2, 2)) == "", "empty space says nothing")
	for id in p.active.duplicate():
		if id != a:
			p.bench(id)
	screen._refresh()
	await process_frame
	check(_label_texts(node_named(screen, "RelationsRow")).is_empty() and node_named(screen, "RelationsWeb") == null,
		"a party of one shows no block at all")

# Every Label under a node, depth first — a roster row's name sits a few
# containers down.
func _all_labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(_all_labels(c))
	return out

func _label_texts(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c.text)
	return out

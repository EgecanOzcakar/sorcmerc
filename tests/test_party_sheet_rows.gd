# Issue #27: "need a party page with the skills and inventories, equipped items
# shown", and "the party management screen in terms of benching getting new
# characters should only work at an inn".
#
# The party page listed a name, a class, a level, an AC and an HP bar, and
# everything about what somebody actually carries or is good at was one click
# deeper, one character at a time. And the roster reshuffled anywhere: the HUD
# button on the open world opened the same screen, so a party could swap its
# people around standing in a field with a hostile band closing in.
#
#   godot --headless --path . -s tests/test_party_sheet_rows.gd
extends SceneTree

const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(labels(c))
	return out

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func find_button(node: Node, text: String) -> Button:
	for b in buttons(node):
		if text in b.text:
			return b
	return null

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])

	# --- the data the page is built from ---------------------------------
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	var rogue = null
	for ch in party.roster:
		if ch.class_id() == "rogue":
			rogue = ch
	check(rogue != null, "the demo roster has a rogue in it")

	var sm: Dictionary = party.summary(rogue.id)
	check(sm.has("skills") and sm.has("equipped"), "a summary carries skills and gear")
	check(not (sm["skills"] as Array).is_empty(), "the rogue has trained skills (%d)" % (sm["skills"] as Array).size())
	check((sm["skills"] as Array).size() < 18, "...and only the trained ones, not all eighteen")
	var expert := false
	for s in sm["skills"]:
		check(String(s["prof"]) in ["prof", "expert"], "every listed skill is one they are trained in")
		if String(s["prof"]) == "expert":
			expert = true
	check(expert, "the thief's expertise shows as expertise")
	# Best first is the order the page reads them in.
	var mods: Array = (sm["skills"] as Array).map(func(s): return int(s["mod"]))
	var sorted: Array = mods.duplicate()
	sorted.sort()
	sorted.reverse()
	check(mods == sorted, "trained skills come back best first (%s)" % str(mods))
	check(not (sm["equipped"] as Array).is_empty(), "and what they are wearing is listed")
	for it in sm["equipped"]:
		check(it.has("id") and it.has("kind") and it.has("quantity"), "each piece of gear names itself")

	# --- ...and shows up on the rows -------------------------------------
	var screen = load("res://scenes/party/party.tscn").instantiate()
	screen.party = party
	root.add_child(screen)
	for i in 4:
		await process_frame

	var rows: Array = labels(screen._roster_col)
	var gear: Array = rows.filter(func(l): return l.name.begins_with("RowGear"))
	var skills: Array = rows.filter(func(l): return l.name.begins_with("RowSkills"))
	check(gear.size() == party.roster.size(), "every roster row says what that person carries (%d of %d)"
		% [gear.size(), party.roster.size()])
	check(skills.size() == party.roster.size(), "...and what they are trained in")
	check(gear.any(func(l): return "Leather" in l.text or "Armor" in l.text or "armor" in l.text),
		"the gear line names armour (%s)" % str(gear.map(func(l): return l.text)))
	check(skills.any(func(l): return "Stealth" in l.text),
		"the skills line names skills (%s)" % str(skills.map(func(l): return l.text)))
	check(skills.any(func(l): return "+" in l.text or "-" in l.text), "...with their modifiers")

	# The marching slots on the right have to grow for the lines too. A Button
	# does not size itself to a child laid out by anchors, so the 56px height
	# that used to be hard-coded there was a bet that a summary would never be
	# taller than two lines — and these rows made it four, which stacked all
	# four slots on top of each other. (Caught by the screenshot, not the suite,
	# which is why it is in the suite now.)
	var slots: Array = screen._slot_col.get_children()
	check(slots.size() == Party.MAX_ACTIVE, "there is a slot per marching place")
	for i in slots.size():
		var b = slots[i]
		if b.get_child_count() == 0:
			continue          # an empty slot is one line of text
		var inner: Control = b.get_child(0)
		check(b.size.y >= inner.get_combined_minimum_size().y,
			"slot %d is tall enough for what is in it (%.0f vs %.0f)" % [
				i, b.size.y, inner.get_combined_minimum_size().y])
		if i > 0:
			var prev = slots[i - 1]
			check(b.position.y >= prev.position.y + prev.size.y - 1.0,
				"slot %d starts below slot %d instead of overlapping it" % [i, i - 1])

	# --- the lock ---------------------------------------------------------
	check(not screen.roster_locked, "a screen opened with nothing said is unlocked")
	var bench := find_button(screen._roster_col, "Bench")
	check(bench != null and not bench.disabled, "benching works when it is not locked")
	var active0: int = party.active.size()
	bench.pressed.emit()
	await process_frame
	check(party.active.size() == active0 - 1, "...and actually benches somebody")

	screen.roster_locked = true
	screen._refresh()
	await process_frame
	check(find_button(screen._roster_col, "Bench").disabled, "locked: Bench is greyed")
	check(find_button(screen._roster_col, "To party").disabled, "locked: so is recruiting")
	check(find_button(screen, "Create new").disabled, "locked: and making a new character")
	check(screen._hint.text.contains("inn"), "...and the screen says where to do it (%s)" % screen._hint.text)

	# A slot click must not be the way around it.
	var benched := ""
	for ch in party.roster:
		if not party.is_active(ch.id):
			benched = ch.id
			break
	check(benched != "", "somebody is on the bench")
	screen._selected = benched
	var before: Array = party.active.duplicate()
	screen._on_slot(0)
	await process_frame
	check(party.active == before, "a marching slot does not recruit around the lock")

	# Marching ORDER is not roster management: it still works locked.
	if party.active.size() >= 2:
		screen._selected = party.active[1]
		screen._on_slot(0)
		await process_frame
		check(party.active[0] == before[1] and party.active[1] == before[0],
			"...but reordering who walks first still does")

	print("test_party_sheet_rows: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Issues #25 / #26: the open world had no Esc and no Space. Every other screen
# in the game answers those two keys — the fight has F1 settings and Esc-cancel,
# a settlement visit backs out a page at a time — but out on the map the only
# way to Settings was the title screen, which costs you the map, and the only
# way to pause was the button in the corner.
#
# Drives the real scene and feeds it real InputEventKeys.
#   godot --headless --path . -s tests/test_world_menu.gd
extends SceneTree

var _pass := 0
var _fail := 0

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

func key(main, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	main._unhandled_key_input(ev)

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	# --- #26: space is the Pause button ---------------------------------
	check(not main.world.clock.is_paused(), "the map starts running")
	key(main, KEY_SPACE)
	check(main.world.clock.is_paused(), "space pauses the world")
	check(main._pause_btn.text == "Resume", "the HUD button agrees it is paused")
	key(main, KEY_SPACE)
	check(not main.world.clock.is_paused(), "space again resumes it")
	check(main._pause_btn.text == "Pause", "and the button goes back")

	# --- #25: Esc opens a pause menu with Settings on it -----------------
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._menu_panel != null, "Esc opens the menu")
	check(main.world.clock.is_paused(), "the menu holds the clock")
	check(has_button(main._menu_panel, "Resume"), "Resume is on it")
	check(has_button(main._menu_panel, "Settings"), "Settings is on it")
	check(has_button(main._menu_panel, "Field manual"), "the manual is on it")
	check(has_button(main._menu_panel, "Report a bug"), "the bug reporter is on it")
	check(has_button(main._menu_panel, "title screen"), "and the way out")

	# The settings overlay opens from it, parented to the screen rather than to
	# the menu, so it outlives a menu that closes underneath it.
	check(press(main._menu_panel, "Settings"), "Settings presses")
	await process_frame
	check(main.get_node_or_null("SettingsOverlay") != null, "the settings overlay is up")
	main.get_node("SettingsOverlay").queue_free()
	await process_frame

	# Esc again closes the menu and lets the world run.
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._menu_panel == null, "Esc closes the menu")
	check(not main.world.clock.is_paused(), "and the world runs again")

	# Space closes it too, rather than pausing a world the menu already paused.
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._menu_panel != null, "menu reopens")
	key(main, KEY_SPACE)
	await process_frame
	check(main._menu_panel == null, "space closes the menu")
	check(not main.world.clock.is_paused(), "and does not leave the clock stopped")

	# The Pause button must not fight the menu for the clock.
	key(main, KEY_ESCAPE)
	await process_frame
	main._toggle_pause()
	check(main.world.clock.is_paused(), "the Pause button is inert while the menu owns the clock")
	key(main, KEY_ESCAPE)
	await process_frame

	# --- Esc backs out of the light panels before it opens the menu -------
	main._toggle_quests()
	await process_frame
	check(main._quest_panel != null, "quest log opens")
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._quest_panel == null, "Esc closes the quest log")
	check(main._menu_panel == null, "...without also opening the menu")

	main._open_party()
	await process_frame
	check(main._party_overlay != null, "party screen opens")
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._party_overlay == null, "Esc closes the party screen")
	check(main._menu_panel == null, "...without also opening the menu")

	# --- and stays out of the settlement's way ---------------------------
	var s = main.world.settlements[0]
	main.world.player().position = s.position
	main._check_visit()
	await process_frame
	check(not main._visit.is_empty(), "a visit opens")
	key(main, KEY_SPACE)
	check(main._menu_panel == null, "space does not open the map menu inside the gates")
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._visit.is_empty(), "Esc still leaves the settlement")
	check(main._menu_panel == null, "...and does not open the menu on the way out")

	print("test_world_menu: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

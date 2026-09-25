# Dev-only: the pictures for the board-legibility pass (#195, #239, #242,
# #243). Needs a display (it renders 3D); not part of run_tests.sh.
#
#   SORCMERC_SEED=424242 godot --path . --resolution 1280x800 -s tests/shot_board_legibility.gd
#     -> shots_legibility/
#        legibility_height.png   #242: a hero at the foot of the shrine's shelf,
#                                so the move field runs behind it, up onto it and
#                                in front of it — one wash per tile, the lower
#                                tile's never showing through the raised one.
#                                #239: the active ring and every token's shadow
#                                under the figure they belong to after the zoom
#        legibility_ash.png      #243: the goblin camp's rough, the ash, close
#        legibility_hud.png      #195: the party panned onto the board's left
#                                edge, so a bar that is not clipped to the board
#                                lands on the log, the action line and the bar
#   SHOT_ONLY=height|ash|hud takes just the one. Each view is its own fight.
#
# The zoom and the pan go through Board._zoom_at and main.pan_by, the same two
# calls the mouse wheel and a drag make, so a picture here is a view a player
# can reach.
extends SceneTree

const Settings = preload("res://core/settings.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Hex = preload("res://core/hex.gd")


func _init() -> void:
	Settings.current().reaction_prompts = false   # nobody here to answer one
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_legibility"))
	var only := OS.get_environment("SHOT_ONLY")
	if only in ["", "height"]:
		await _height()
	if only in ["", "ash"]:
		await _ash()
	if only in ["", "hud"]:
		await _hud()
	quit()


func _shoot(path: String) -> void:
	for _i in 30:
		await process_frame
	await create_timer(0.5).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_legibility/%s" % path)
	print("wrote shots_legibility/%s" % path)


# A fight past deployment and on a hero's turn, on `theme` ("" is the demo's).
func _open(theme: String):
	var main = load("res://scenes/main.tscn").instantiate()
	if theme != "":
		main.spec = Scaler.roster_for(Presets.party(), "normal", {}, theme, 7, 1.0, [], "")
		main.spec["theme"] = theme
	root.add_child(main)
	for _i in 30:
		await process_frame
	var guard := 0
	while guard < 900:
		await process_frame
		guard += 1
		if main.cb == null or main.cb.is_over() or main._busy:
			continue
		if main._mode == "deploy":
			for b in main._buttons.get_children():
				if b is Button and not b.disabled and "Begin" in b.text:
					b.pressed.emit()
					break
			continue
		var cur = main.cb.current()
		if main._mode == "idle" and cur != null and cur.team == "party" and cur.conscious():
			break
	main._cam_follow = false
	main._board._auto_fit = false
	for _i in 5:
		await process_frame
	return main


func _frame(main, at: Vector2i, zoom: float) -> void:
	var b = main._board
	b._zoom_at(b.size * 0.5, zoom)
	for _i in 5:
		await process_frame
	main.pan_by(b.size * 0.5 - b._pix(at))


func _close(main) -> void:
	main.queue_free()
	await process_frame
	await process_frame


# #242: the hero is set down two hexes from the middle of the biggest shelf, on
# the ground, so the move field covers ground behind a raised tile, the raised
# tile itself and the ground in front of it.
func _height() -> void:
	var main = await _open("")
	var cb = main.cb
	var hs: Dictionary = cb.board.get("height", {})
	var mid := Vector2i.ZERO
	var best := -1
	for hx in hs:
		var n := 0
		for h2 in hs:
			if Hex.distance(hx, h2) <= 2:
				n += 1
		if n > best:
			best = n
			mid = hx
	var cur = cb.current()
	for hx in Hex.within(mid, 3):
		if hx in cb.board["hexes"] and not hs.has(hx) and cb.passable(hx) \
				and Hex.distance(hx, mid) >= 2 \
				and cb.combatants.all(func(c): return c.pos != hx):
			cur.pos = hx
			main._board._tok.erase(cur.id)
			break
	await _frame(main, mid, 1.9)
	await _shoot("legibility_height.png")
	await _close(main)


func _ash() -> void:
	var main = await _open("goblin-camp")
	var rough: Array = main.cb.board.get("rough", [])
	await _frame(main, rough[0] if not rough.is_empty() else main.cb.current().pos, 2.2)
	await _shoot("legibility_ash.png")
	await _close(main)


func _hud() -> void:
	var main = await _open("")
	var b = main._board
	var cur = main.cb.current()
	b._zoom_at(b.size * 0.5, 1.6)
	for _i in 5:
		await process_frame
	# the hero on the board's left edge, so half the party is off it
	main.pan_by(Vector2(b.size.x * 0.06, b.size.y * 0.5) - b._pix(cur.pos))
	await _shoot("legibility_hud.png")
	await _close(main)

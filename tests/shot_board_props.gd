# Dev-only: the pictures for this pass. Needs a display (it renders 3D); not
# part of run_tests.sh.
#
#   godot --path . --resolution 1400x900 -s tests/shot_board_props.gd
#     -> props_gallery.png   every prop kind, named, in rows
#     -> board_downs.png     the downs board with its furniture and the card
#     -> board_marsh.png     the marsh board, the same
#     -> combat_card.png     the character card and the resized log, in a fight
#
# The gallery is its own tiny 3D scene rather than a board with one of
# everything on it: a board can only show the props its own palette names, and
# the point of the gallery is to see all twenty side by side.
extends SceneTree

const BoardProps = preload("res://scenes/board_props.gd")
const Settings = preload("res://core/settings.gd")
const Icons = preload("res://core/ui_icons.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")

const COLS := 7
const SPACING := 3.4
const ROW_GAP := 5.8      # taller than SPACING: a label must clear the row below it


func _init() -> void:
	Settings.current().reaction_prompts = false   # nobody here to answer one
	await _gallery()
	await _fight("downs", "board_downs.png")
	await _fight("marsh", "board_marsh.png")
	await _fight("", "combat_card.png")
	quit()


func _shoot(path: String) -> void:
	for _i in 30:
		await process_frame
	await create_timer(0.4).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://%s" % path)
	print("wrote %s" % path)


# --- the gallery ------------------------------------------------------------

func _gallery() -> void:
	var holder := Node3D.new()
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("17130f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("6a6a60")
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	world.add_child(sun)

	var kinds: Array = BoardProps.kinds()
	kinds.sort()
	var rows: int = int(ceil(float(kinds.size()) / COLS))
	for i in kinds.size():
		var n := BoardProps.build(String(kinds[i]), i + 1)
		n.position = Vector3((i % COLS - (COLS - 1) / 2.0) * SPACING, 0.0,
			(i / COLS - (rows - 1) / 2.0) * ROW_GAP)
		world.add_child(n)
		var tag := Label3D.new()
		tag.text = String(kinds[i])
		tag.font_size = 44
		tag.pixel_size = 0.006
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Icons.COL_GOLD
		tag.position = n.position + Vector3(0, 0.12, 1.75)
		world.add_child(tag)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# The HEIGHT of an orthogonal view, so it is the rows that set it — sizing it
	# off the column count put twenty props in the middle third of the frame.
	cam.size = rows * ROW_GAP * 1.12
	world.add_child(cam)
	# look_at_from_position, not position-then-look_at: look_at needs the node in
	# the tree and the first run of this printed exactly that error.
	cam.look_at_from_position(Vector3(0, 9.0, 11.0), Vector3(0, 0.7, 0), Vector3.UP)
	cam.current = true

	await _shoot("props_gallery.png")
	world.queue_free()
	holder.queue_free()
	await process_frame


# --- a real fight, on a named board -----------------------------------------
#
# `theme` "" takes whatever the standalone demo builds, which is the shot the
# character card wants: a fight with somebody worth reading on the board.

func _fight(theme: String, out: String) -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	if theme != "":
		var habitat := ""
		for b in Scaler.BIOME_HABITAT:
			if String(Scaler.BIOME_BOARD[b]) == theme:
				habitat = String(Scaler.BIOME_HABITAT[b])
		main.spec = Scaler.roster_for(Presets.party(), "normal", {}, theme, 7, 1.0, [], habitat)
		main.spec["theme"] = theme
	root.add_child(main)
	for _i in 30:
		await process_frame

	# Past deployment: the board is not laid out until somebody has acted.
	var guard := 0
	while guard < 900:
		await process_frame
		guard += 1
		if main.cb == null or main.cb.is_over() or main._busy:
			continue
		if main._mode == "deploy":
			# "Begin", not the first enabled button — the first is "Swap <hero>",
			# and pressing that in a loop photographs the deployment screen
			# forever, which is what the first run of this did.
			for b in main._buttons.get_children():
				if b is Button and not b.disabled and "Begin" in b.text:
					b.pressed.emit()
					break
			continue
		var cur = main.cb.current()
		if main._mode == "idle" and cur != null and cur.team == "party" and cur.conscious():
			break

	# #173: fill the card off a real hover, rather than by calling show_who —
	# the picture should prove the path a player actually walks.
	for c in main.cb.combatants:
		if c.team == "foe" and not c.is_dead():
			main.board_hex_hovered(c.pos)
			break
	main._cam_follow = false
	main._board._auto_fit = true
	main._pan = Vector2.ZERO
	await _shoot(out)
	main.queue_free()
	await process_frame

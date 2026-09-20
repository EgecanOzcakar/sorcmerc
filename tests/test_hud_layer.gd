# T-hud: HP bar + condition tags paint on a CanvasLayer above Board and
# Figures3D, instead of inline in Board._draw() — a figure standing in front
# of another hex used to be able to cover that hex's HP bar, since Figures3D
# (a Board child) draws after Board's own _draw() runs.
#   godot --headless --path . -s tests/test_hud_layer.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 20:
		await process_frame

	check(main._hud_layer != null and main._hud_overlay != null, "the HUD CanvasLayer and its overlay exist")
	check(main._hud_layer.layer > 0, "the HUD layer sits above the default layer 0 (Board + Figures3D)")
	check(main._hud_overlay.get_parent() == main._hud_layer, "the overlay draws inside that layer, not under Board")

	# The actual occlusion bug can't be read back from pixels headless, but the
	# structural claim — HP bars no longer live inside Board._draw() — is
	# checkable: Board no longer calls the old per-tier _draw_token_hud, and
	# the static paint function it now uses accepts an explicit canvas instead
	# of always drawing onto Board itself.
	check(not main._board.has_method("_draw_token_hud"),
		"the old Board-bound _draw_token_hud is gone, not just unused")

	# T26 barks went the same way, and for a worse case of the same bug: they
	# sit lower over a hex than the HP bar or the odds chip, so a tall rig (the
	# ranger's) stood squarely in front of what its neighbour was saying.
	check("_barks" in main._board, "Board still owns the bark dict the overlay reads")
	# _centered_on lives on Board beside _paint_token_hud rather than on the
	# outer script: Board's own statics have to reach it (_paint_reveal does),
	# and an inner class cannot see the outer script's.
	check(main._board.has_method("_centered_on"), "and the overlay can centre text on its own canvas")
	var src: String = (load("res://scenes/main.gd") as GDScript).source_code
	if src != "":
		var board_draw := src.find("\tfunc _draw() -> void:")
		var board_draw_end := src.find("\n\tfunc ", board_draw + 1)
		check(board_draw > 0 and not "_barks" in src.substr(board_draw, board_draw_end - board_draw),
			"Board._draw no longer paints them")
		var overlay := src.find("func _draw_hud_overlay")
		check(overlay > 0 and "_barks" in src.substr(overlay, src.find("\nfunc ", overlay + 1) - overlay),
			"_draw_hud_overlay does")

	# T-dmg: the damage numbers and the roll reveal are the fourth and fifth
	# readouts to make this move, and the reveal is the one that needed it most
	# — its dice row sits lowest of any of them, right at a tall rig's chest.
	check("_floats" in main._board, "Board still owns the damage-number list the overlay reads")
	check(main._board.has_method("_paint_reveal"),
		"and the reveal paints through a canvas-agnostic static, like the HP bar")
	if src != "":
		var bdraw := src.find("\tfunc _draw() -> void:")
		var bend := src.find("\n\tfunc ", bdraw + 1)
		var body := src.substr(bdraw, bend - bdraw)
		var ov := src.find("func _draw_hud_overlay")
		var ovbody := src.substr(ov, src.find("\nfunc ", ov + 1) - ov)
		check(not "draw_string(ThemeDB.fallback_font, f.pos" in body,
			"Board._draw no longer paints the damage numbers")
		check("_board._floats" in ovbody, "_draw_hud_overlay does")
		check(not "_reveal.head" in body, "Board._draw no longer paints the roll reveal")
		check("_paint_reveal" in ovbody, "_draw_hud_overlay does")

	# The two names _draw_hud_overlay now reaches across for, read here the same
	# way it reads them: a rename on either side is a runtime error that only
	# fires while somebody happens to be talking, which is easy to ship.
	check(float(main._board.BARK_TTL) > 0.0, "the bark lifetime is readable off Board")
	main._board._barks["anyone"] = {"text": "Well struck!", "age": 0.0}
	check(main._board._barks.size() == 1, "and a bark can be put where the overlay looks for it")
	main._hud_overlay.queue_redraw()
	await process_frame
	main._board._barks.clear()

	main._board.queue_redraw()
	main._hud_overlay.queue_redraw()
	for i in 3:
		await process_frame

	# Issue #121: the same CanvasLayer that puts the HP bars over Figures3D put
	# them over the field manual too — it is above layer 0, and a full-screen
	# overlay is an ordinary child on layer 0. The layer stands down while one
	# of the shared overlays is up.
	check(main._hud_layer.visible, "the HUD layer is visible with nothing over the board")
	check(not main._overlay_up(), "...and nothing is over it")
	var man = main.ManualOverlay.toggle(main)
	check(man != null and main._overlay_up(), "the manual opens and is seen as an overlay")
	for i in 3:
		await process_frame
	check(not main._hud_layer.visible, "HP bars, barks and damage numbers are off while it is open")
	main.ManualOverlay.toggle(main)
	for i in 3:
		await process_frame
	check(not main._overlay_up(), "closing it puts the screen back")
	check(main._hud_layer.visible, "...and the HUD comes back with it")
	# Every overlay this screen can raise, not just the one that was reported.
	for n in main.OVERLAY_NODES:
		check(n in ["ManualOverlay", "SettingsOverlay", "BugReportOverlay"],
			"the overlay list holds only the shared full-screen overlays (%s)" % n)

	print("test_hud_layer: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

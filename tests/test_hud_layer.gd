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

	main._board.queue_redraw()
	main._hud_overlay.queue_redraw()
	for i in 3:
		await process_frame
	print("test_hud_layer: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

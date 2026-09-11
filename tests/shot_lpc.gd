# Dev-only: drop the composed LPC merc on a hex of the real combat board and
# save a PNG. Preview only - nothing here touches the combat flow (T47 step 6).
#   godot --path . -s tests/shot_lpc.gd          (non-headless; headless hangs
#                                                 on viewport capture here)
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame

	# Same hex the first combatant stands on, placed with the board's own _pix.
	var hx: Vector2i = main.cb.combatants[0].pos
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = load("res://assets/generated/merc_01.tres")
	spr.animation = "slash_right"
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2.ONE * (main.hex_px / 26.0)
	spr.offset = Vector2(0, -22)          # feet sit near the frame's bottom edge
	spr.position = main._board._pix(hx)
	main._board.add_child(spr)
	spr.play()
	await create_timer(0.34).timeout       # mid-swing frame
	spr.pause()

	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://lpc_spike.png")
	print("saved lpc_spike.png %dx%d  frame %d on hex %s"
		% [img.get_width(), img.get_height(), spr.frame, hx])
	quit()

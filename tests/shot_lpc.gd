# Dev-only: drop the composed LPC units (humanoid + creatures) on hexes of the
# real combat board and save a PNG. Preview only - nothing here touches the
# combat flow (T47 step 6).
#   godot --path . -s tests/shot_lpc.gd          (non-headless; headless hangs
#                                                 on viewport capture here)
extends SceneTree

# unit id -> animation to hold, in hex order along the board.
const UNITS := [["merc_01", "slash_right"], ["bat", "attack_right"],
	["ghost", "attack_right"], ["slime", "attack_right"]]

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame

	var sprites: Array[AnimatedSprite2D] = []
	for n in UNITS.size():
		var hx: Vector2i = main.cb.combatants[n].pos
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = load("res://assets/generated/%s.tres" % UNITS[n][0])
		spr.animation = UNITS[n][1]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2.ONE * (main.hex_px / 26.0)
		spr.offset = Vector2(0, -22)      # feet/shadow sit near the frame's bottom
		spr.position = main._board._pix(hx)
		main._board.add_child(spr)
		spr.play()
		sprites.append(spr)

	await create_timer(0.4).timeout
	for spr in sprites:
		# Hold mid-animation: the pose that shows the attack, not the rest frame.
		spr.pause()
		spr.frame = spr.sprite_frames.get_frame_count(spr.animation) / 2 + 1
		print("  %s visible=%s pos=%s frame=%d" % [spr.animation, spr.visible, spr.position, spr.frame])

	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://lpc_spike.png")
	var where := ""
	for n in UNITS.size():
		where += "  %s %s frame %d" % [UNITS[n][0], UNITS[n][1], sprites[n].frame]
	print("saved lpc_spike.png %dx%d %s" % [img.get_width(), img.get_height(), where])
	quit()

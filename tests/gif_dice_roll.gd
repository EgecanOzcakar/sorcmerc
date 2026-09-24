# Dev-only: the frames for docs/shots/live-roll.gif — the live die over a
# darkened shop, three rolls back to back: one made, one missed, a natural 20.
# Needs a display; not part of run_tests.sh. The die's clock is stepped by hand
# (DiceRoll._advance) rather than left to run, so every frame is exactly 1/25 s
# of the show however slowly a virtual display draws it.
#
#   godot --path . --resolution 1400x900 -s tests/gif_dice_roll.gd
#     -> shots_tmp/gif/NNNN.png (216 frames). Then, with Pillow:
#   python3 -c 'from PIL import Image; import glob
#   fs = [Image.open(f).convert("RGB").crop((350, 120, 1050, 690)).resize((440, 358))
#         .quantize(64, dither=Image.Dither.NONE) for f in sorted(glob.glob("shots_tmp/gif/*.png"))]
#   fs[0].save("docs/shots/live-roll.gif", save_all=True, append_images=fs[1:], duration=40, loop=0, optimize=True)'
# It reads docs/shots/live-roll-town-landed.png for the shop behind the die, so
# run tests/shot_live_roll_town.gd first.
extends SceneTree

const DiceRoll = preload("res://scenes/dice_roll.gd")

const FPS := 25.0
const ROLLS := [
	{"nat": 16, "bonus": 3, "dc": 13, "ok": true, "label": "Persuasion — Ilsa Vane"},
	{"nat": 6, "bonus": 5, "dc": 14, "ok": false, "label": "Sleight of Hand — Pike Rook"},
	{"nat": 20, "bonus": 4, "dc": 15, "ok": true, "label": "Survival — Vera Kord"},
]

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "")
	var bg := TextureRect.new()
	bg.texture = ImageTexture.create_from_image(
		Image.load_from_file(ProjectSettings.globalize_path("res://docs/shots/live-roll-town-landed.png")))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp/gif"))
	var n := 0
	for r in ROLLS:
		var d := DiceRoll.new()
		d.size = Vector2(700, DiceRoll.HEIGHT)
		d.position = Vector2((1400 - 700) * 0.5, (900 - DiceRoll.HEIGHT) * 0.5)
		root.add_child(d)
		d.play(r)
		d._tween.kill()   # the clock is ours: one step per frame
		var t := 0.0
		while t <= DiceRoll.T_TOTAL:
			d._advance(t)
			await _save(n)
			n += 1
			t += 1.0 / FPS
		d.finish()
		for _i in 8:   # a beat on the finished roll before the next
			await _save(n)
			n += 1
		d.queue_free()
		await process_frame
	print("wrote %d frames" % n)
	quit()

func _save(i: int) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://shots_tmp/gif/%04d.png" % i))

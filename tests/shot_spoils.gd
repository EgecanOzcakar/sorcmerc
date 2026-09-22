# Dev-only: three frames of the after-action page's sequence, side by side, so
# a PR can show an animation in one still. Needs a display (it renders); not
# part of run_tests.sh.
#   godot --path . --resolution 900x700 -s tests/shot_spoils.gd
#   -> spoils_sequence.png
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Spoils = preload("res://scenes/world/spoils.gd")

const ROWS := [
	["+400 XP,  +50 gold", Icons.COL_GOLD, "tally"],
	["Taken from the dead: Handaxe, Potion of Healing ×2", Icons.COL_TEXT],
	["The bandits' camp is burned out — the job is done.", Icons.COL_GOLD],
	["Vera Kord did not get up.", Icons.COL_FOE],
]

# Where in the sequence each panel is taken, as a fraction of the whole.
const AT := [0.14, 0.52, 1.0]

func _init() -> void:
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var page = Spoils.new()
	root.add_child(page)
	page.build("Victory", ROWS,
		Icons.scene_art("summary-victory", null),
		"Tip: the high ground is +2 to hit anything below you.",
		func(): pass)
	page._done = true          # driven by hand, frame by frame

	var strip: Image = null
	for i in AT.size():
		page._t = page._end * float(AT[i])
		page._apply()
		for _f in 3:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		if strip == null:
			strip = Image.create_empty(img.get_width() * AT.size(), img.get_height(), false, img.get_format())
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(img.get_width() * i, 0))
	strip.save_png("res://spoils_sequence.png")
	print("saved spoils_sequence.png  %dx%d" % [strip.get_width(), strip.get_height()])
	quit()

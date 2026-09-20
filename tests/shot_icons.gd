# Dev-only: render the whole icon sheet (classes, schools, the action bar's drawn
# marks, conditions, the rarity ramp) to a PNG so it can be eyeballed without
# opening the editor.
#   godot --path . -s tests/shot_icons.gd     ->  icon_sheet.png
# A glyph that comes out as a hollow box is tofu in the default font: pick another.
# An action-bar mark that comes out as a glyph instead of drawn art has no SVG in
# assets/icons/ yet — add a recipe to tools/gen_action_icons.py.
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")

class Sheet extends Control:
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Icons.COL_BG)
		var y := 34.0
		var head := func(t: String, yy: float) -> void:
			draw_string(f, Vector2(24, yy), t, HORIZONTAL_ALIGNMENT_LEFT, -1,
				Icons.FS_HEAD, Icons.COL_GOLD)

		head.call("C L A S S E S", y)
		y += 26
		var x := 24.0
		for cid in Icons.CLASS_GLYPHS:
			draw_circle(Vector2(x + 20, y + 12), 20, Icons.COL_PARTY)
			draw_string(f, Vector2(x + 12, y + 20), Icons.class_glyph(cid),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Icons.COL_INK)
			draw_string(f, Vector2(x, y + 48), cid, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)
			x += 90
		y += 84

		# Each school twice: the drawn badge the bar uses, and the glyph behind it.
		head.call("S P E L L   S C H O O L S", y)
		y += 26
		x = 24.0
		for s in Icons.SCHOOL_GLYPHS:
			var stex: Texture2D = Icons.school_icon(s)
			if stex != null:
				draw_texture_rect(stex, Rect2(x, y - 4, 30, 30), false)
			draw_string(f, Vector2(x + 34, y + 18), Icons.school_glyph(s),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Icons.school_color(s))
			draw_string(f, Vector2(x, y + 40), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)
			x += 130
		y += 76

		# The action bar itself: one mark per verb kind, plus its own controls.
		head.call("A C T I O N   B A R", y)
		y += 26
		var marks: Array = Icons.VERB_GLYPHS.keys() + Icons.BAR_ICONS
		for i in marks.size():
			var id: String = String(marks[i])
			var mx := 24.0 + (i % 10) * 116.0
			var my := y + int(i / 10.0) * 62.0
			var tex: Texture2D = Icons.verb_icon(id)
			if tex != null:
				draw_texture_rect(tex, Rect2(mx, my, 30, 30), false)
			else:
				draw_string(f, Vector2(mx + 3, my + 20), Icons.verb_glyph(id),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Icons.COL_GOLD)
			draw_string(f, Vector2(mx, my + 44), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Icons.COL_BODY)
		y += 62 * ceil(marks.size() / 10.0) + 18

		head.call("C O N D I T I O N S", y)
		y += 26
		x = 24.0
		for i in Icons.CONDITION_ORDER.size():
			var id: String = Icons.CONDITION_ORDER[i]
			var cx := 24.0 + (i % 10) * 116.0
			var cy := y + int(i / 10.0) * 56.0
			draw_string(f, Vector2(cx + 8, cy + 18), Icons.condition_glyph(id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e6c15a"))
			draw_string(f, Vector2(cx, cy + 38), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)
		y += 56 * ceil(Icons.CONDITION_ORDER.size() / 10.0) + 20

		head.call("R A R I T Y", y)
		y += 26
		x = 24.0
		for r in Icons.RARITY_COLORS:
			draw_rect(Rect2(x, y, 150, 22), Icons.rarity_color(r))
			draw_string(f, Vector2(x, y + 40), "%s  %s" % [r, Icons.rarity_color(r).to_html(false)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.rarity_color(r))
			x += 170

func _init() -> void:
	var s := Sheet.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)
	for _i in 5:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://icon_sheet.png")
	print("saved icon_sheet.png")
	quit()

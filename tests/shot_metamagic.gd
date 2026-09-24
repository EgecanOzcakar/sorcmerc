# Dev-only: the level-up page of a sorcerer going to level 2, where the two
# Metamagic picks open. All ten of the book's options are drawn; the five the
# board does not play yet (core/metamagic.gd) are greyed, with "Not on the
# board yet" as their tooltip.
#
#   xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . -s tests/shot_metamagic.gd   ->  shots_tmp/metamagic_picker.png
extends SceneTree

const Character = preload("res://core/character.gd")
const Leveling = preload("res://core/leveling.gd")
const Icons = preload("res://core/ui_icons.gd")

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp"))
	root.theme = Icons.dark_theme()
	var ch := Character.new()
	ch.id = ""   # nothing to write into the barracks
	ch.cname = "Maren Ashvale"
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	Leveling.grant_levels(ch, 1, "sorcerer")
	var scr = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(scr)
	scr.set_character(ch)
	scr.commit()
	# One pick made, so a live option shows as picked beside the greyed ones.
	scr._pick(_point(ch, "feature-choice:class:sorcerer:0"), "quickened-spell")
	for i in 30:
		await process_frame
	# Scroll the Metamagic rows into view.
	for b in _buttons_of(scr._body):
		if String(b.get_meta("choice_key", "")) == "feature-choice:class:sorcerer:0":
			var sc := _scroll_of(b)
			if sc != null:
				sc.ensure_control_visible(b)
			break
	for i in 10:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_tmp/metamagic_picker.png")
	print("saved shots_tmp/metamagic_picker.png")
	quit()

func _point(ch, key: String) -> Dictionary:
	for p in ch.sheet().choice_points:
		if String(p["key"]) == key:
			return p
	return {}

func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	return p

func _buttons_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons_of(c))
	return out

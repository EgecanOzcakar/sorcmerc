# What the climb looks like (scenes/creator/climb_view.gd): a rogue at 5 with
# the Thief taken, so the shot has all three rung states in it at once —
# behind, next, and veiled — plus the fork at 3 with one branch lit.
#
# Not headless — the capture hangs without a real rendering driver:
#   godot --path . -s tests/shot_climb.gd
extends SceneTree

const Climb = preload("res://core/climb.gd")
const Icons = preload("res://core/ui_icons.gd")

func _init() -> void:
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var host := Control.new()
	host.theme = Icons.dark_theme()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.offset_left = 24; host.offset_top = 20
	host.offset_right = -24; host.offset_bottom = -20
	root.add_child(host)

	var view = load("res://scenes/creator/climb_view.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	await process_frame

	for spot in [{"cls": "rogue", "sub": "thief", "at": 5, "file": "climb_rogue5"},
			{"cls": "barbarian", "sub": "berserker", "at": 12, "file": "climb_barbarian12"},
			{"cls": "wizard", "sub": "evoker", "at": 0, "file": "climb_wizard_pick"}]:
		view.show_track(Climb.build(spot["cls"], spot["sub"], spot["at"]),
			Climb.paths_for(spot["cls"]), spot["sub"] if spot["at"] > 0 else "")
		await _shoot("res://%s.png" % spot["file"])
		print("%s %s at %d: %d rungs" % [spot["cls"], spot["sub"], spot["at"],
			Climb.build(spot["cls"], spot["sub"], spot["at"]).size()])
	view.queue_free()
	await process_frame
	await _levelup()
	await _creator_step()
	await _emblems()
	await _path_emblems()
	quit()


# The creator's Class step with a class picked, which is the other screen the
# climb was built for and the one it reached second. Level 0, so every rung past
# the first is veiled and the whole question on the page is where the class
# GOES — which is what somebody choosing one is actually asking.
func _creator_step() -> void:
	var page = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(page)
	for _i in 12:
		await process_frame
	page.ch.species_id = "human"
	page._set_class("monk")
	page._jump(1)
	await _shoot("res://climb_creator.png")
	page.queue_free()
	await process_frame


# The real level-up page with the climb under its card: a rogue standing on 4,
# looking at 5. Proves the integration rather than the widget.
func _levelup() -> void:
	var Character = load("res://core/character.gd")
	var ch = Character.new()
	ch.cname = "Vesna"
	for i in 4:
		ch.add_level("rogue")
	# Answer whatever key the resolver actually asks for rather than guessing one.
	for pend in ch.sheet().pending:
		if String(pend["type"]) == "subclass":
			ch.decide(String(pend["key"]),
				load("res://scenes/creator/creator.gd").decision_for(pend, ["thief"]))
	var page = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(page)
	page.persist = false
	page.set_character(ch)
	await _shoot("res://climb_levelup.png")

func _shoot(path: String) -> void:
	for i in 8:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("  -> %s" % path)


# The twelve class emblems in a row (tools/gen_action_icons.py's "classes"
# group), at the size the ladder's fork and the class step draw them.
func _emblems() -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var wrap := HFlowContainer.new()
	wrap.theme = Icons.dark_theme()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.offset_left = 40; wrap.offset_top = 120
	wrap.offset_right = -40; wrap.offset_bottom = -40
	wrap.add_theme_constant_override("h_separation", 26)
	wrap.add_theme_constant_override("v_separation", 22)
	root.add_child(wrap)
	for c in load("res://core/rules/catalog.gd").all("classes.json"):
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(col)
		var art := TextureRect.new()
		art.texture = load("res://assets/icons/classes/%s.svg" % c["id"])
		art.custom_minimum_size = Vector2(88, 88)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(art)
		var l := Label.new()
		l.text = String(c["name"])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	await _shoot("res://climb_emblems.png")


# All forty-eight path emblems, grouped by class the way the fork shows them:
# four at a time, which is the only comparison that matters.
func _path_emblems() -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.theme = Icons.dark_theme()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 30; grid.offset_top = 24
	grid.offset_right = -30; grid.offset_bottom = -24
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	var Catalog = load("res://core/rules/catalog.gd")
	for s in Catalog.all("subclasses.json"):
		var col := VBoxContainer.new()
		grid.add_child(col)
		var art := TextureRect.new()
		art.texture = Icons.path_icon(String(s["id"]))
		art.custom_minimum_size = Vector2(56, 56)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(art)
		var l := Label.new()
		l.theme_type_variation = "Small"
		l.text = String(s["name"]).replace("Path of the ", "").replace("College of ", "") \
			.replace("Circle of the ", "").replace("Warrior of the ", "").replace("Warrior of ", "") \
			.replace("Oath of the ", "").replace("Oath of ", "").replace("School of ", "") \
			.replace("The ", "").replace(" Patron", "").replace(" Sorcery", "").replace(" Domain", "")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = 56
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	await _shoot("res://climb_paths.png")

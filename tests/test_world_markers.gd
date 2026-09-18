# T9y: the two things that tell the player where they are when the map is
# mostly fog — the off-screen settlement chevrons, and the "can I see this
# right now, or am I only remembering it" colour split on everything standing
# on the ground.
#
# Drives the real world scene: the chevron *choice* and the colour maths are
# split out of the draw calls precisely so they can be checked here (what a
# headless test cannot do is look at the pixels, which is what tests/shot_world.gd
# is for).
#   godot --headless --path . -s tests/test_world_markers.gd
extends SceneTree

const World = preload("res://core/world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _transparency_of(holder: Node3D) -> float:
	for m in holder.find_children("*", "GeometryInstance3D", true, false):
		return m.transparency
	return 0.0

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	var w = main.world
	var p = w.player()

	# --- off-screen chevrons ---------------------------------------------
	# A settlement the camera is already showing must not also get a chevron:
	# the marker exists to point at what you cannot see.
	main._pan = Vector2.ZERO
	main.set_zoom(1.0)
	main._layout()
	var frame: Rect2 = main._marker_frame()
	check(frame.size.x > 0.0 and frame.size.y > 0.0, "the marker frame has an inside to pin to")
	for s in main._offscreen_settlements(frame, p.position):
		check(not frame.has_point(main._pix(s.position)),
			"%s is off screen, which is why it has a chevron" % s.sname)

	# Panned well off the inhabited part of the map, so every settlement is off
	# screen and the cap is what bites. Kept to a few thousand pixels and put
	# back afterwards: the draw runs every frame, and a pan far enough to
	# overflow float precision makes the renderer complain about the polygons,
	# which is the test's doing, not the map's.
	main._pan = Vector2(6000, 6000)
	main._layout()
	var picked: Array = main._offscreen_settlements(main._marker_frame(), p.position)
	check(picked.size() == mini(main.OFFSCREEN_MARKERS, w.settlements.size()),
		"at most three settlements are marked, however many are off screen")
	# ...and they are the three nearest the party, not the first three in the list.
	var best: Array = w.settlements.duplicate()
	best.sort_custom(func(a, b):
		return p.position.distance_squared_to(a.position) < p.position.distance_squared_to(b.position))
	var want: Array = best.slice(0, picked.size())
	var same := true
	for i in picked.size():
		if picked[i] != want[i]:
			same = false
	check(same, "the three marked are the three nearest the party")
	main._pan = Vector2.ZERO
	main._layout()

	# A world with no settlements at all must not be a crash — every other
	# fallback in this scene is written that way, and a procedural map is
	# allowed to be strange.
	var empty := World.new()
	empty.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var was = main.world
	main.world = empty
	main._draw_offscreen_markers(Vector2.ZERO)
	main.world = was
	check(true, "an empty world draws no markers rather than failing")

	# --- remembered vs. live ----------------------------------------------
	var gold: Color = main.Icons.COL_GOLD
	check(main._remembered(gold, true) == gold, "something in sight keeps its own colour")
	var faded: Color = main._remembered(gold, false)
	check(faded != gold, "something only remembered does not")
	check(faded.a < gold.a, "...it is drawn thinner")
	check(Color(faded.r, faded.g, faded.b).get_luminance() < gold.get_luminance(),
		"...and dimmer, toward the fog it sits in")

	# The live/remembered split must be the fog's own current-visibility rule,
	# not a second rule that can drift away from the ground it is drawn on.
	var near_pos: Vector2 = p.position + Vector2(World.VISION_RADIUS * 0.5, 0.0)
	var far_pos: Vector2 = p.position + Vector2(World.VISION_RADIUS * 4.0, 0.0)
	check(w.is_visible_now(near_pos, p.position), "a point inside the vision radius is live")
	check(not w.is_visible_now(far_pos, p.position), "a point well outside it is only remembered")

	# --- the same split, one layer up in 3D -------------------------------
	# A settlement's body on screen is its diorama, not the 2D ring under it,
	# so the fade has to reach the model or the whole distinction is decorative.
	var s3d = main._settlements3d
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	holder.add_child(mesh)
	s3d._fade(holder, true)
	check(mesh.transparency > 0.0, "a remembered diorama is faded back")
	s3d._fade(holder, false)
	check(is_zero_approx(mesh.transparency), "one in sight is drawn solid")
	holder.free()

	# And the layer really applies it as the party moves — models only load
	# where the GLBs are importable, so this asserts through a real diorama
	# when there is one rather than pretending there always is.
	var town = w.settlements[0]
	var diorama: Node3D = s3d._dioramas.get(town.id)
	if diorama != null:
		p.position = town.position + Vector2(10, 10)
		s3d.reposition()
		check(_transparency_of(diorama) == 0.0, "standing in town, the town is solid")
		p.position = town.position + Vector2(World.VISION_RADIUS * 5.0, 0.0)
		s3d.reposition()
		check(_transparency_of(diorama) > 0.0, "walked away, the town is a memory")

	# A chevron quotes travel time, and the map's clock runs in minutes: at
	# World.SPEED (40 units a world-minute) every settlement on the small map
	# is minutes away, so an hours-only formatter would label them all alike.
	check(main._travel_time(6.5) == "7 min", "a short march is quoted in minutes")
	check(main._travel_time(0.2) == "1 min", "...and never rounds down to nothing")
	check(main._travel_time(95.0) == "1h35", "a long one crosses into hours")
	check(main._hours(30.0) == "an hour", "the rest cooldown still rounds up to whole hours")

	print("test_world_markers: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

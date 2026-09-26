# T-party3d: RoamingParty.troops/highest_troop(), and Party3D's model pick
# off them — a race-troop band (human/dwarf/elf/orc) with a roster gets the
# role figure, a monster-faction band with no race counterpart (goblinoid,
# undead, ...) falls back to figures3d.gd's single FOE_MODELS figure for
# that faction, and only a band with neither (no troops, no faction
# coverage) falls through to the 3D pawn Party3D builds out of primitives. T9x: the player is the
# same — no figure by default (keeps the pawn), but naming one of the active
# party in core/party.gd's overworld_figure gets them that character's
# figure. Plus the layer's procedural walk (party3d.gd's GAIT_* block):
# moving bobs, stopping settles.
#   godot --headless --path . -s tests/test_party3d.gd
extends SceneTree

const Party3D = preload("res://scenes/world/party3d.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "0")   # the free plane, where bands walk the map (#231: routes are the default)
	const World = preload("res://core/world.gd")
	var p := World.RoamingParty.new("test", Vector2.ZERO, "human")
	check(p.highest_troop().is_empty(), "no troops, no highest troop")
	p.troops = [{"role": "heavy", "level": 2}, {"role": "light", "level": 5}, {"role": "spellcaster", "level": 3}]
	check(String(p.highest_troop().get("role", "")) == "light", "highest_troop picks the max level, not the first")
	p.troops = [{"role": "heavy", "level": 4}, {"role": "light", "level": 4}]
	check(String(p.highest_troop().get("role", "")) in ["heavy", "light"], "a tie still returns one of them, not empty")

	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	check(main._party3d != null, "Party3D is wired into the live scene")

	var patrol = null
	var player = null
	var goblins = null
	for party in main.world.parties:
		if party.id == "patrol": patrol = party
		if party.is_player: player = party
		if party.id == "goblins": goblins = party
	check(patrol != null and main._party3d.has_model(patrol),
		"patrol (human, heavy troop we generated) gets a figure")
	check(player != null and main._party3d.has_model(player),
		"by default the player wears their highest-level member's figure, not the pawn")
	check(goblins != null and main._party3d.has_model(goblins),
		"goblinoid has no race counterpart, but gets the FOE_MODELS figure combat uses")

	# T9x: picking a figure on the Party screen (core/party.gd's
	# overworld_figure) gets the player a real Party3D model too — but the
	# pick is a person, and only counts while that person is still marching.
	# The demo roster's active four are Vera/Pike/Ilsa/Thrun (Party.
	# demo_roster()'s first four via add_member's auto-activate).
	main.party.overworld_figure = "vera"      # Vera Kord, fighter, active by default
	main._party3d.reset(main.world)
	check(main._party3d.has_model(player), "picking an active member gives the player their figure")
	main.party.bench("vera")
	main._party3d.reset(main.world)
	check(main._party3d.has_model(player) and main.party.overworld_pick() == null,
		"benching the character you picked drops the pick; the default marcher stands in")
	main.party.activate("vera")
	main._party3d.reset(main.world)
	check(main.party.overworld_pick() != null, "bringing them back brings the pick back")
	main.party.overworld_figure = "not-a-real-class"
	main._party3d.reset(main.world)
	check(main._party3d.has_model(player), "an id that matches nobody falls back to the default, not a crash")
	for id in main.party.active.duplicate():
		main.party.bench(id)
	main._party3d.reset(main.world)
	check(not main._party3d.has_model(player), "nobody marching is the pawn")
	for id in ["vera", "pike", "ilsa", "thrun"]:
		main.party.activate(id)

	# Back-compat: a save written before the switch holds a CLASS id here.
	# It still resolves (against the active party, the way the old code read
	# it) and is migrated to that member's id on the first look.
	main.party.overworld_figure = "fighter"
	main._party3d.reset(main.world)
	check(main._party3d.has_model(player), "an old save's class id still puts a figure on the map")
	check(main.party.overworld_figure == "vera",
		"...and is rewritten to the member it resolved to, so it only happens once")
	main.party.overworld_figure = "wizard"    # an old save naming a class nobody active has
	main._party3d.reset(main.world)
	check(main.party.overworld_pick() == null, "an old save's unmatched class id is no pick")
	check(main.party.overworld_figure == "wizard", "and is left alone — there is nothing to migrate it to")

	# T9x: the procedural walk. The clock is paused so nothing else on the
	# map moves and neither an encounter nor a settlement visit can fire
	# (both bail while paused); the player is stepped by hand instead, one
	# REF_SPEED-second's worth of travel per frame.
	main.party.overworld_figure = "vera"
	main._party3d.reset(main.world)
	main.world.clock.pause()
	var fig: Node3D = main._party3d._figs[player.id]
	var bob := 0.0
	var sway := 0.0
	for i in 40:
		player.position += Vector2(Party3D.REF_SPEED / 60.0, 0.0)
		await process_frame
		bob = maxf(bob, absf(fig.position.y))
		sway = maxf(sway, absf(fig.rotation.z))
	check(bob > 0.0 and bob <= Party3D.BOB_HEIGHT,
		"a moving party bobs, by a fraction of a unit and no more (%.3f)" % bob)
	check(sway > 0.0 and sway <= Party3D.SWAY_RAD, "and sways as the weight shifts (%.4f rad)" % sway)
	var lean := fig.rotation.x
	check(lean > 0.0, "and leans into the direction of travel")

	# Stop: it must ease out, not snap.
	#
	# Driven through _gait_pose() with fixed deltas rather than off a real frame.
	# The gait decays by GAIT_RAMP * dt, so the whole ease-out takes 0.25s — and
	# "still leaning on the very next frame" is therefore only true when that
	# frame was SHORTER than 0.25s. It always is on a developer machine; on a
	# loaded CI runner one headless frame can be longer, move_toward lands on
	# exactly the idle pose, and this reported a snap that had not happened.
	# Measured: at dt 0.2 the lean is 0.007, at dt 0.25 it is exactly 0.
	#
	# _gait_pose is split out of _reposition() precisely so a headless test can
	# hand it a delta ("driven with fixed deltas by a headless test", scenes/
	# world/party3d.gd) — so the assertion uses that seam and stops depending on
	# how busy the machine was.
	# Spun up and eased down on fixed deltas, so nothing here reads a wall clock:
	# not how long a frame took, and not whatever weight the loop above happened
	# to leave behind. GAIT_RAMP is per second, so a full ramp is 1.0/GAIT_RAMP
	# and a step of a fifth of that has to come down over five frames.
	const STOP_DT := 1.0 / (Party3D.GAIT_RAMP * 5.0)     # a fifth of the ramp
	for i in 10:
		main._party3d._gait_pose(player.id, Party3D.REF_SPEED, STOP_DT)   # walking, at full weight
	var walking: float = main._party3d._gait_pose(player.id, Party3D.REF_SPEED, STOP_DT).z
	check(is_equal_approx(walking, Party3D.LEAN_RAD),
		"the walk reaches full lean before it is asked to stop (%.5f)" % walking)

	var eased: Array = []
	for i in 5:
		eased.append(main._party3d._gait_pose(player.id, 0.0, STOP_DT).z)
	check(eased[0] > 0.0 and eased[0] < walking,
		"a party that stops eases out of the walk instead of snapping (%.5f, was %.5f)"
			% [eased[0], walking])
	var still_easing := true
	for i in range(1, eased.size() - 1):
		still_easing = still_easing and eased[i] > 0.0 and eased[i] < eased[i - 1]
	check(still_easing, "and keeps easing, a fifth of the ramp at a time (%s)"
		% str(eased.map(func(v): return "%.5f" % v)))
	check(is_zero_approx(eased[eased.size() - 1]),
		"reaching exactly the idle pose at the end of the ramp, not near it (%.5f)"
			% eased[eased.size() - 1])
	var settled := false
	for i in 120:
		await process_frame
		if is_zero_approx(fig.position.y) and is_zero_approx(fig.rotation.x) \
				and is_zero_approx(fig.rotation.z):
			settled = true
			break
	check(settled, "and settles back to exactly the idle pose, not near it")
	main.world.clock.resume()

	print("test_party3d: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# #167 — the furniture on a combat board (scenes/board_props.gd).
#
# The plans are pure data and allocate nothing, so all of this runs headless:
# what a prop IS can be checked without a viewport, and that is the half worth
# checking. The other half — whether it looks like a tree — is
# tests/shot_board_props.gd's gallery and nobody's assertion.
#
#   godot --headless --path . -s tests/test_board_props.gd
extends SceneTree

const BoardProps = preload("res://scenes/board_props.gd")
const KitParts = preload("res://scenes/world/kit_parts.gd")
const Encounter = preload("res://core/encounter.gd")
const Props3D = preload("res://scenes/world/props3d.gd")

# One hex radius is one world unit and a hero stands 1.5 tall (figures3d.gd's
# FIGURE_SCALE), so these two numbers are the words "cover" and "rough" written
# down. Rough costs movement and blocks nothing: a player who mistakes it for
# something to stand behind has been lied to by the picture, which is the exact
# failure tests/test_cover_readable.gd exists to prevent on the 2D tier.
const ROUGH_MAX_H := 0.55
const COVER_MIN_H := 1.2
# A kit's whole claim against a GLB's ~82k. A board fields up to ~20 of these.
const TRIS_MAX := 420

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _init() -> void:
	test_every_kind_builds()
	test_rough_is_never_cover()
	test_cover_is_worth_hiding_behind()
	test_every_board_is_covered()
	test_seed_varies_and_repeats()
	test_models_keep_the_kit_promises()
	print("test_board_props: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# The top of every prop, in world units: the highest part's centre plus half its
# height. Parts rest relative to y=0 the way kit_parts.gd's plan format says.
func top_of(kind: String, seed_v := 0) -> float:
	var top := 0.0
	for part in BoardProps.plan(kind, seed_v):
		top = maxf(top, float(part["pos"].y) + float(part["size"].y) * 0.5)
	return top


func test_every_kind_builds() -> void:
	for kind in BoardProps.kinds():
		var parts: Array = BoardProps.plan(kind, 1)
		check(not parts.is_empty(), "%s builds something" % kind)
		for part in parts:
			check(String(part["part"]) in KitParts.PARTS,
				"%s: '%s' is a primitive kit_parts knows" % [kind, part["part"]])
			check(BoardProps.PALETTE.has(String(part["role"])),
				"%s: role '%s' is in the palette" % [kind, part["role"]])
			check(float(part["size"].y) > 0.0, "%s: every part has height" % kind)
		check(BoardProps.triangles(kind) <= TRIS_MAX,
			"%s costs %d triangles, want <= %d" % [kind, BoardProps.triangles(kind), TRIS_MAX])


# The claim rough makes about itself, across every seed it can be built with —
# a prop that is knee-high on average and waist-high on one board's seed would
# be a lie told occasionally, which is worse than one told always.
func test_rough_is_never_cover() -> void:
	for pal in BoardProps.ROUGH:
		var kind: String = BoardProps.rough_kind(String(pal))
		for s in range(0, 24):
			var h := top_of(kind, s)
			check(h <= ROUGH_MAX_H,
				"%s rough (%s) stands %.2f, want <= %.2f" % [pal, kind, h, ROUGH_MAX_H])


func test_cover_is_worth_hiding_behind() -> void:
	for pal in BoardProps.COVER:
		var kind: String = BoardProps.cover_kind(String(pal))
		for s in range(0, 24):
			var h := top_of(kind, s)
			check(h >= COVER_MIN_H,
				"%s cover (%s) stands %.2f, want >= %.2f" % [pal, kind, h, COVER_MIN_H])


# Every palette a board can carry names its own cover and its own rough, and
# every object type any board places has a plan of its own. The fallback box is
# there so a typo draws something visibly wrong instead of crashing a fight, and
# this is what keeps it from quietly becoming the shipping state.
func test_every_board_is_covered() -> void:
	var known: Array = BoardProps.kinds()
	for theme in Encounter.THEMES:
		var board: Dictionary = Encounter.board_for(theme)
		var pal := String(board.get("palette", "shrine"))
		check(BoardProps.COVER.has(pal), "%s: palette '%s' names its cover" % [theme, pal])
		check(BoardProps.ROUGH.has(pal), "%s: palette '%s' names its rough" % [theme, pal])
		for o in board.get("objects", []):
			check(String(o["type"]) in known,
				"%s: object '%s' has a prop of its own" % [theme, o["type"]])


func test_seed_varies_and_repeats() -> void:
	var a: Array = BoardProps.plan("tree", 11)
	var b: Array = BoardProps.plan("tree", 12)
	check(str(a) == str(BoardProps.plan("tree", 11)), "the same seed builds the same tree")
	check(str(a) != str(b), "a different seed builds a different one")
	# A prop with no jitter in it at all would pass the line above by accident if
	# it ever gained some, so check the one that must not vary: the fallback.
	check(str(BoardProps.plan("no-such-prop", 3)) == str(BoardProps.plan("no-such-prop", 3)),
		"an unknown kind is stable too")


# A converted download under assets/board/ replaces the kit's look, never its
# claims: the same height rules as the plans above, and inside one hex across.
# Skips any kind with no model, which is the kit and already covered above.
func test_models_keep_the_kit_promises() -> void:
	var models := 0
	for kind in BoardProps.kinds():
		if not ResourceLoader.exists(BoardProps.MODEL_DIR % kind):
			continue
		models += 1
		var m: Node3D = BoardProps.build(kind, 3).get_child(0)
		var size: Vector3 = Props3D._bounds(m).size * m.scale
		if kind in BoardProps.ROUGH.values():
			check(size.y <= ROUGH_MAX_H, "%s model stands %.2f, want <= %.2f" % [kind, size.y, ROUGH_MAX_H])
		if kind in BoardProps.COVER.values():
			check(size.y >= COVER_MIN_H, "%s model stands %.2f, want >= %.2f" % [kind, size.y, COVER_MIN_H])
		check(maxf(size.x, size.z) <= BoardProps.HEX_SPAN + 0.01,
			"%s model spans %.2f, want <= %.2f" % [kind, maxf(size.x, size.z), BoardProps.HEX_SPAN])
		m.get_parent().free()
	print("  %d board props drawn from a model" % models)

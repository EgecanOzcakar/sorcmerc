# "cover in combat map should be more obvious."
#
# Half cover is +2 AC and +2 on Dex saves (core/combat.gd's effective_ac and
# _saving_throw) — the difference between a 55% swing against you and a 45%
# one. It was announced by a slab two shades off the ordinary floor and the
# word "cover" in 10px grey-teal at the bottom-left corner of the hex, under
# the foliage that always grows on a cover hex, over a textured floor, at any
# zoom.
#
# The drawing itself is a picture and a test cannot look at it, so this covers
# the parts that are decidable: the palette really is distinct, the chip states
# the number the rules give rather than a noun, and the rim survives a zoom
# that drops the text.
#
#   godot --headless --path . -s tests/test_cover_readable.gd
extends SceneTree

const Board = preload("res://scenes/main.gd").Board
const Main = preload("res://scenes/main.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# How far apart two colours read, roughly — enough to tell "a different thing"
# from "the same thing in a different light".
func apart(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)

func _init() -> void:
	# The rim has to be a colour nothing else on the board wears, or it says
	# "selected" instead of "cover".
	var rim: Color = Main.COL_COVER_EDGE
	for other in [Main.COL_HEX, Main.COL_HEX_EDGE, Main.COL_COVER, Main.COL_PROP,
			Main.COL_BRAZIER]:
		check(apart(rim, other) > 0.35,
			"the cover rim is distinct from %s (%.2f apart)" % [other.to_html(false), apart(rim, other)])
	check(rim.get_luminance() > Main.COL_COVER.get_luminance() + 0.25,
		"the rim is markedly lighter than the slab it rims (%.2f vs %.2f)" % [
			rim.get_luminance(), Main.COL_COVER.get_luminance()])
	# ...and the slab is no longer near-identical to the plain floor.
	check(apart(Main.COL_COVER, Main.COL_HEX) > 0.08,
		"a cover slab reads as different ground from plain floor (%.2f)" % apart(Main.COL_COVER, Main.COL_HEX))

	# The chip says what cover is worth, not what it is called. +2 is the
	# number core/combat.gd actually applies.
	check(Board.COVER_CHIP.contains("2"), "the chip carries the number (%s)" % Board.COVER_CHIP)
	check(not Board.COVER_CHIP.to_lower().contains("cover"),
		"...rather than repeating the word (%s)" % Board.COVER_CHIP)
	check(Board.COVER_RIM_W > 1.5, "the rim is thicker than an ordinary hex seam (%.1f)" % Board.COVER_RIM_W)

	# And it is the rules' own number: bump a combatant into cover and the AC
	# the engine reports has to move by exactly what the chip claims.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var cover_hex = null
	for hx in main.cb.board["hexes"]:
		if main.cb.is_cover(hx):
			cover_hex = hx
			break
	check(cover_hex != null, "the board has cover on it")
	var open_hex = null
	for hx in main.cb.board["hexes"]:
		if not main.cb.is_cover(hx) and main.cb.object_at(hx).is_empty():
			open_hex = hx
			break
	if cover_hex != null and open_hex != null:
		var c = main.cb.combatants[0]
		var was: Vector2i = c.pos
		c.pos = open_hex
		var bare: int = main.cb.effective_ac(c)
		c.pos = cover_hex
		var covered: int = main.cb.effective_ac(c)
		c.pos = was
		check(covered - bare == int(Board.COVER_CHIP),
			"the chip is the AC the engine gives (%d vs chip %s)" % [covered - bare, Board.COVER_CHIP])

	print("test_cover_readable: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

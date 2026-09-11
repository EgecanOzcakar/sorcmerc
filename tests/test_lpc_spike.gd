# The one check behind tools/lpc_compose.py: the generated SpriteFrames loads
# and slash_right is the 6 64x64 frames of LPC's slash-e row.
#   godot --headless --path . -s tests/test_lpc_spike.gd
extends SceneTree

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var sf = load("res://assets/generated/merc_01.tres")
	check(sf is SpriteFrames, "merc_01.tres loads as SpriteFrames")
	if sf is SpriteFrames:
		check(sf.has_animation("slash_right"), "has slash_right")
		check(sf.get_frame_count("slash_right") == 6, "slash_right has 6 frames")
		for i in sf.get_frame_count("slash_right"):
			var t: Texture2D = sf.get_frame_texture("slash_right", i)
			check(t != null and t.get_size() == Vector2(64, 64), "frame %d is 64x64" % i)

	print("test_lpc_spike: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

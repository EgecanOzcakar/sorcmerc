# The check behind tools/lpc_compose.py: every loadout in data/lpc/ produced a
# SpriteFrames whose animations match what the loadout declared - humanoid
# (merc_01, one 8-layer slash row) and creature (bat/ghost/slime, four
# monster-sheet attack rows) alike, so the generalized pipeline is what's
# tested, not one hand-written case.
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
	var dir := DirAccess.open("res://data/lpc")
	var names := dir.get_files()
	names.sort()
	check(names.size() >= 4, "found the loadouts (%d)" % names.size())

	for file in names:
		var loadout: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/lpc/" + file))
		var id: String = loadout["id"]
		var frame: int = loadout.get("frame", 64)
		var sf = load("res://assets/generated/%s.tres" % id)
		check(sf is SpriteFrames, "%s.tres loads as SpriteFrames" % id)
		if not (sf is SpriteFrames):
			continue
		check(sf.get_animation_names().size() == loadout["animations"].size(),
			"%s has %d animations" % [id, loadout["animations"].size()])
		for anim in loadout["animations"]:
			var name: String = anim["name"]
			check(sf.has_animation(name), "%s has %s" % [id, name])
			if not sf.has_animation(name):
				continue
			check(sf.get_frame_count(name) == int(anim["frames"]),
				"%s/%s has %d frames" % [id, name, anim["frames"]])
			for i in sf.get_frame_count(name):
				var t: Texture2D = sf.get_frame_texture(name, i)
				var region: Rect2 = t.region if t is AtlasTexture else Rect2()
				check(t != null and t.get_size() == Vector2(frame, frame),
					"%s/%s frame %d is %dx%d" % [id, name, i, frame, frame])
				# The row the loadout asked for is the row that got sliced.
				check(region.position == Vector2(i * frame, int(anim["row"]) * frame),
					"%s/%s frame %d slices row %d col %d" % [id, name, i, anim["row"], i])

	print("test_lpc_spike: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

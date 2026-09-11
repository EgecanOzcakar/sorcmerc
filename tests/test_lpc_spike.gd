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

	_check_mapping()
	print("test_lpc_spike: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Only `sheet` and `src_id` decide which sheet a combatant gets, so the mapping
# is testable without building a whole encounter.
class FakeCombatant:
	var sheet = null
	var src_id := ""
	func _init(s, id: String) -> void:
		sheet = s
		src_id = id

func _check_mapping() -> void:
	var LpcArt = load("res://core/lpc_art.gd")
	var cases := {
		"bat": "bat", "giant-bat": "bat",
		"ghost": "ghost", "specter": "ghost", "shadow": "ghost", "will-o-wisp": "ghost",
		"gray-ooze": "slime", "ochre-jelly": "slime", "black-pudding": "slime",
		"goblin": "merc_01", "hobgoblin": "merc_01",     # humanoid type -> the one humanoid loadout
		"worg": "", "wolf": "", "red-dragon-wyrmling": "", "stone-golem": "",  # vector token
	}
	for id in cases:
		check(LpcArt.loadout_for(FakeCombatant.new(null, id)) == cases[id],
			"%s -> %s" % [id, cases[id] if cases[id] != "" else "(vector token)"])
	check(LpcArt.loadout_for(FakeCombatant.new({}, "")) == "merc_01", "heroes -> merc_01")
	check(LpcArt.loadout_for(FakeCombatant.new(null, "")) == "", "blank src_id -> vector token")

	# Facing: the projected delta picks the row, and merc_01's missing rows mirror.
	check(LpcArt.facing_between(Vector2.ZERO, Vector2(40, 5)) == "right", "facing right")
	check(LpcArt.facing_between(Vector2.ZERO, Vector2(-40, 5)) == "left", "facing left")
	check(LpcArt.facing_between(Vector2.ZERO, Vector2(2, 40)) == "down", "facing down")
	check(LpcArt.facing_between(Vector2.ZERO, Vector2(2, -40)) == "up", "facing up")
	var merc: SpriteFrames = LpcArt.frames("merc_01")
	check(LpcArt.row_for(merc, "right") == ["slash_right", false], "merc faces right unmirrored")
	check(LpcArt.row_for(merc, "left") == ["slash_right", true], "merc faces left mirrored")
	var bat: SpriteFrames = LpcArt.frames("bat")
	check(LpcArt.row_for(bat, "left") == ["attack_left", false], "creatures have their own rows")
	check(LpcArt.frames("") == null, "no loadout, no frames")

	# The credits screen's file must exist and name every artist (license duty).
	var credits := FileAccess.get_file_as_string("res://assets/generated/credits.txt")
	check(credits.length() > 400, "credits.txt is present")
	for who in ["bagzie", "bluecarrot16", "Charles Sanchez (CharlesGabriel)",
			"Johannes Sjölund (wulax)", "Stephen Challener (Redshrike)"]:
		check(credits.contains(who), "credits name %s" % who)
	var artists := credits.substr(credits.find("ARTISTS"), credits.find("PARTS USED") - credits.find("ARTISTS"))
	check(artists.count("bluecarrot16") == 1, "the artist list is deduplicated")
	check(not artists.contains("Sj?lund"), "upstream's mojibake spelling is normalised away")
	for f in ["res://LICENSES/CC-BY-SA-3.0.txt", "res://LICENSES/GPL-3.0.txt"]:
		check(FileAccess.get_file_as_string(f).length() > 5000, "%s is the full text" % f)

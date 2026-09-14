# T-actionicons: the action bar's drawn marks (assets/icons/*.svg) against the
# verbs that ask for one. The failure this exists to catch is silent: add a verb
# kind, forget the icon, and the bar quietly falls back to a font glyph on that
# one button — which looks like a rendering bug, not a missing file.
#   godot --headless --path . -s tests/test_action_icons.gd
#
# Reads the .svg sources off disk rather than load()ing them: file_exists is
# true from a source checkout whether or not the assets have been imported yet,
# so this run says something useful on a clean clone. The load path is checked
# too, but only when the import actually exists (see the tail).
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Combat = preload("res://core/combat.gd")

const ACTION_DIR := "res://assets/icons/actions"
const SCHOOL_DIR := "res://assets/icons/schools"

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# An icon is only usable if the art and the .import Godot reads it through are
# both there — a committed .svg with no sidecar imports at whatever the
# defaults are, which is not what tools/gen_action_icons.py chose.
func _icon_ok(path: String, label: String) -> void:
	check(FileAccess.file_exists(path), "%s: %s exists" % [label, path])
	check(FileAccess.file_exists(path + ".import"), "%s: %s has its .import" % [label, path])
	if not FileAccess.file_exists(path):
		return
	var body := FileAccess.get_file_as_string(path)
	check(body.begins_with("<svg"), "%s: %s is an svg" % [label, path])
	check(body.contains('viewBox="0 0 64 64"'), "%s: %s is on the 64x64 grid" % [label, path])
	check(not body.contains("<style") and not body.contains("Gradient"),
		"%s: %s sticks to what ThorVG renders" % [label, path])

func _init() -> void:
	# Every verb the combat engine can offer as a button carries a mark.
	var kinds: Array = []
	for b in Combat.BASIC:
		if not kinds.has(b["kind"]):
			kinds.append(String(b["kind"]))
	for k in Combat.OFFERABLE:
		# "spell" is the one kind with no icon of its own on purpose: a spell
		# button is marked by its school instead (scenes/main.gd _build_hero_menu).
		if k != "spell" and not kinds.has(k):
			kinds.append(String(k))
	check(kinds.size() >= 12, "found the verb kinds to check (%d)" % kinds.size())
	for k in kinds:
		check(Icons.VERB_GLYPHS.has(k), "verb kind %s has a fallback glyph" % k)
		_icon_ok("%s/%s.svg" % [ACTION_DIR, k], "verb " + k)

	# ...and so does every kind the glyph table knows about, even if no BASIC
	# entry currently uses it.
	for k in Icons.VERB_GLYPHS:
		_icon_ok("%s/%s.svg" % [ACTION_DIR, k], "glyphed verb " + String(k))

	# The eight schools, and the bar's own controls.
	for s in Icons.SCHOOL_GLYPHS:
		_icon_ok("%s/%s.svg" % [SCHOOL_DIR, s], "school " + String(s))
	for n in Icons.BAR_ICONS:
		_icon_ok("%s/%s.svg" % [ACTION_DIR, n], "bar control " + String(n))

	# Nothing left over: a renamed verb should take its icon with it rather than
	# leaving an orphan behind that nothing on the bar will ever draw.
	for f in DirAccess.get_files_at(ACTION_DIR):
		if not f.ends_with(".svg"):
			continue
		var id := f.get_basename()
		check(Icons.VERB_GLYPHS.has(id) or Icons.BAR_ICONS.has(id),
			"actions/%s is still wired to something" % f)
	for f in DirAccess.get_files_at(SCHOOL_DIR):
		if f.ends_with(".svg"):
			check(Icons.SCHOOL_GLYPHS.has(f.get_basename()),
				"schools/%s is still a school" % f)

	# The lookups themselves. Only meaningful once the project has been
	# imported — on a clean clone there is no .ctex yet and the bar is supposed
	# to fall back to glyphs rather than break, so that case is a skip, not a
	# failure.
	if ResourceLoader.exists("%s/attack.svg" % ACTION_DIR):
		check(Icons.verb_icon("attack") != null, "verb_icon('attack') loads")
		check(Icons.school_icon("evocation") != null, "school_icon('evocation') loads")
		check(Icons.verb_icon("no_such_verb") != null,
			"an unknown verb kind falls back to the generic mark, not to nothing")
		var btn := Button.new()
		Icons.icon_button(btn, Icons.verb_icon("dash"))
		check(btn.icon != null, "icon_button hangs the badge on the button")
		check(btn.get_theme_constant("icon_max_width", "Button") == Icons.ICON_PX,
			"icon_button sizes it for the bar")
		check(not btn.has_theme_color_override("icon_normal_color"),
			"and leaves the colour alone — the badge carries its own")
		btn.free()
	else:
		print("  (icons not imported in this checkout — load path skipped)")

	print("test_action_icons: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

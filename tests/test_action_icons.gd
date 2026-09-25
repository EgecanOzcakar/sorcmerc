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
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")

const ACTION_DIR := "res://assets/icons/actions"
const SCHOOL_DIR := "res://assets/icons/schools"
const SKILL_DIR := "res://assets/icons/skills"

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

	# --- one badge per skill, not one per kind -----------------------------
	# The bar names nothing any more: the badge is the whole button and the
	# name lives in the tooltip. So every skill that can BE a button needs art
	# of its own, or two different spells become the same square.
	var spells := 0
	for sid in Catalog.index("spells.json"):
		if Effects.spell(sid).is_empty():
			continue          # not combat-castable: it never reaches the bar
		spells += 1
		_icon_ok("%s/%s.svg" % [SKILL_DIR, sid], "spell " + String(sid))
	check(spells >= 50, "found the castable spells to check (%d)" % spells)

	var feats := 0
	var fdata = Catalog.all("effects/features.json")
	for fid in fdata:
		if String(fid).begins_with("_") or not fdata[fid] is Dictionary:
			continue
		if not fdata[fid].get("kind", "") in Combat.OFFERABLE:
			continue          # passive: folded into a roll, never a button
		feats += 1
		_icon_ok("%s/%s.svg" % [SKILL_DIR, fid], "feature " + String(fid))
	check(feats >= 20, "found the button features to check (%d)" % feats)

	# Shove is one kind with three choices, and the choice is the verb.
	for b in Combat.BASIC:
		if String(b["kind"]) == "shove":
			_icon_ok("%s/%s.svg" % [SKILL_DIR, b["id"]], "shove " + String(b["id"]))

	# Nothing in skills/ that nothing offers.
	for f in DirAccess.get_files_at(SKILL_DIR):
		if not f.ends_with(".svg"):
			continue
		var id := f.get_basename()
		var known: bool = Catalog.index("spells.json").has(id) or (fdata is Dictionary and fdata.has(id))
		if not known:
			for b in Combat.BASIC:
				if b["id"] == id:
					known = true
		check(known, "skills/%s is still something the bar can offer" % f)

	# Two skills sharing a badge is the failure this whole layer exists to
	# prevent, and it is invisible on screen — the buttons just look alike.
	var seen := {}
	for f in DirAccess.get_files_at(SKILL_DIR):
		if not f.ends_with(".svg"):
			continue
		var body := FileAccess.get_file_as_string("%s/%s" % [SKILL_DIR, f])
		check(not seen.has(body), "skills/%s has art of its own (matches %s)" % [f, seen.get(body, "")])
		seen[body] = f

	# The lookups themselves. Only meaningful once the project has been
	# imported — on a clean clone there is no .ctex yet and the bar is supposed
	# to fall back to glyphs rather than break, so that case is a skip, not a
	# failure.
	if ResourceLoader.exists("%s/attack.svg" % ACTION_DIR):
		check(Icons.verb_icon("attack") != null, "verb_icon('attack') loads")
		check(Icons.school_icon("evocation") != null, "school_icon('evocation') loads")
		check(Icons.verb_icon("no_such_verb") != null,
			"an unknown verb kind falls back to the generic mark, not to nothing")
		# skill_icon walks id -> spell -> school -> kind -> generic, and has to
		# see through the two decorations an id can arrive with.
		check(Icons.skill_icon({"id": "fire-bolt", "spell": "fire-bolt", "kind": "spell"}) != null,
			"skill_icon finds a spell's own badge")
		check(Icons.skill_icon({"id": "fighter-second-wind", "kind": "heal_self"})
			== Icons.skill_icon({"id": "fighter-second-wind", "kind": "heal_self"}),
			"and caches it rather than re-loading per frame")
		check(Icons.skill_icon({"id": "burning-hands@2", "spell": "burning-hands", "kind": "spell"})
			== Icons.skill_icon({"id": "burning-hands", "spell": "burning-hands", "kind": "spell"}),
			"an upcast tier wears the same badge as the spell it upcasts")
		check(Icons.skill_icon({"id": "monk-flurry-of-blows:attack", "kind": "attack"})
			== Icons.verb_icon("attack"),
			"a granted verb resolves to the basic verb it grants")
		check(Icons.skill_icon({"id": "nothing-like-this", "kind": "dodge"})
			== Icons.verb_icon("dodge"),
			"a skill with no art of its own falls back to its kind")
		# #241: the Attack button wears the weapon it will swing, the off-hand
		# swing its own, and a thrown javelin is still the javelin. Real builds,
		# so a change to how pass_gear ids an attack shows up here.
		var Adapter = load("res://core/adapter.gd")
		var Presets = load("res://core/presets.gd")
		var vera = Adapter.to_combatant(Presets.vera(), "party", Vector2i.ZERO)   # longsword
		var atk := {"id": "attack", "kind": "attack"}
		check(Icons.weapon_icon("longsword") != null, "the longsword has item art to wear")
		check(Icons.skill_icon(atk, vera) == Icons.weapon_icon(String(vera.attacks[0]["id"])),
			"Vera's Attack wears her %s" % vera.attacks[0]["id"])
		check(Icons.skill_icon(atk, vera) != Icons.verb_icon("attack"), "...not the generic sword")
		check(Icons.skill_icon(atk) == Icons.verb_icon("attack"),
			"with nobody to ask, Attack keeps the generic badge")
		if Adapter.set_main_attack(vera, "handaxe"):
			check(Icons.skill_icon(atk, vera) == Icons.weapon_icon("handaxe"),
				"swapping the main hand swaps the badge")
		var pike = Adapter.to_combatant(Presets.pike(), "party", Vector2i.ZERO)   # shortbow
		check(Icons.skill_icon(atk, pike) == Icons.item_art("shortbow"), "Pike's Attack wears the shortbow")
		check(Icons.weapon_icon("javelin-thrown") == Icons.weapon_icon("javelin")
			and Icons.weapon_icon("javelin") != null, "a thrown javelin is the javelin")
		check(Icons.weapon_icon("unarmed-strike") == null and Icons.weapon_icon("") == null,
			"no weapon, no art: the caller keeps its badge")
		check(Icons.skill_icon({"id": "offhand_attack", "kind": "offhand_attack", "weapon": "dagger"})
			== Icons.item_art("dagger"), "the off-hand swing wears the off-hand weapon")
		check(Icons.skill_icon({"id": "monk-flurry-of-blows:attack", "kind": "attack"}, vera)
			== Icons.verb_icon("attack"), "a granted attack keeps its own badge, not the main hand's")
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

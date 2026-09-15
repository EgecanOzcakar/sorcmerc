# scenes/world/lair_kit.gd — the modular lair dioramas.
#   godot --headless --path . -s tests/test_lair_kit.gd
#
# Same shape as tests/test_settlement_kit.gd: everything asserts on plan(), the
# pure-data half, so this runs headless with no viewport. build() gets one smoke
# test at the bottom.
extends SceneTree

const Kit = preload("res://scenes/world/lair_kit.gd")
const KitParts = preload("res://scenes/world/kit_parts.gd")
const Lairs3D = preload("res://scenes/world/lairs3d.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)


func _init() -> void:
	var ids: Array = Kit.LAIRS.keys()

	# --- coverage: every lair the game can place, and the two with no GLB -----
	check(ids.size() == 5, "five lairs planned (got %d)" % ids.size())
	for entry in ProceduralWorld.LAIRS:
		check(Kit.has(String(entry[0])),
			"%s — a lair the generator places — is covered" % entry[0])
	for id in Lairs3D.MODELS.keys():
		check(Kit.has(id), "%s, named in Lairs3D.MODELS, is covered" % id)
	# The gap this was written for: these two are in MODELS but have no file,
	# so today they draw as World._draw_lair()'s glyph.
	for id in ["sunken-ruins", "zombie-graveyard"]:
		check(not ResourceLoader.exists(String(Lairs3D.MODELS[id])),
			"%s still has no GLB, so the kit is its only 3D source" % id)
	check(not Kit.has("wyvern-nest"), "an unknown lair says so")
	check(Kit.plan("wyvern-nest").is_empty(), "and plans nothing for it")

	# --- determinism ---------------------------------------------------------
	for id in ids:
		check(_same(Kit.plan(id), Kit.plan(id)), "%s is identical across two calls" % id)
	check(not _same(Kit.plan("sunken-ruins"), Kit.plan("zombie-graveyard")),
		"two lairs are two different places")

	# --- footprint, height, ground plane -------------------------------------
	# Lairs3D positions a diorama at the lair's map pixel and never scales a kit
	# one, so these bounds ARE the on-screen size.
	for id in ids:
		var parts: Array = Kit.plan(id)
		check(not parts.is_empty(), "%s plans something" % id)
		var top := 0.0
		var reach := 0.0
		var buried := ""
		for part in parts:
			var pos: Vector3 = part["pos"]
			var size: Vector3 = part["size"]
			top = maxf(top, pos.y + size.y * 0.5)
			reach = maxf(reach, Vector2(pos.x, pos.z).length() + maxf(size.x, size.z) * 0.5)
			if pos.y + size.y * 0.5 < 0.4:
				buried = String(part["part"])
		check(absf(top - Kit.HEIGHT) < Kit.HEIGHT * 0.3,
			"%s tops out near HEIGHT %.1f (got %.1f)" % [id, Kit.HEIGHT, top])
		# Not "nothing below y=0", which is the settlement invariant: a lair
		# buries things on purpose — the dragon-cave mound is a dome, so its
		# sphere's lower half is under the ground by design, and a giant's
		# boulders are half-sunk because a boulder resting on a flat floor looks
		# like a dropped ball. What IS a bug is a part nobody can see, so the
		# check is that every part still breaks the surface.
		check(buried == "", "%s has no part buried out of sight (a %s is)" % [id, buried])
		check(reach < Kit.RADIUS * 1.6,
			"%s stays inside its footprint (reach %.1f, radius %.1f)" % [id, reach, Kit.RADIUS])
		# Same height as the tier it sits beside, so switching source changes how
		# a lair looks and not how big it is.
		check(is_equal_approx(Kit.HEIGHT, float(Lairs3D.TARGET_HEIGHT)),
			"HEIGHT matches Lairs3D.TARGET_HEIGHT")

	# --- every role a plan asks for exists in that lair's palette -------------
	# KitParts paints an unknown role magenta rather than crashing, which is the
	# right runtime behaviour and exactly the kind of thing a test should catch
	# before it reaches a gallery.
	for id in ids:
		var palette: Dictionary = Kit.LAIRS[id]
		var missing := {}
		for part in Kit.plan(id):
			if not palette.has(String(part["role"])):
				missing[String(part["role"])] = true
			check(KitParts.PARTS.has(String(part["part"])),
				"%s uses a known primitive (%s)" % [id, part["part"]])
		check(missing.is_empty(), "%s asks for no colour it lacks (missing %s)"
			% [id, str(missing.keys())])

	# --- budget --------------------------------------------------------------
	for id in ids:
		var tris: int = Kit.triangles(id)
		check(tris < 3000, "%s is under 3k triangles (got %d)" % [id, tris])
		check(tris > 200, "%s is not suspiciously empty (got %d)" % [id, tris])

	# The three that DO have a GLB, for the comparison this is here to enable.
	for id in ["goblin-warren", "giant-hold", "dragon-cave"]:
		check(ResourceLoader.exists(String(Lairs3D.MODELS[id])),
			"%s has a GLB to compare the kit against" % id)

	# --- enclosures have a gate ----------------------------------------------
	# Counted by position on the ring, not by role — the warren's centre totem is
	# a wooden post too, and keying on the role silently counted it as a stake.
	var stakes := 0
	for part in Kit.plan("goblin-warren"):
		if String(part["part"]) == "post" \
				and Vector2(part["pos"].x, part["pos"].z).length() > Kit.RADIUS * 0.5:
			stakes += 1
	check(stakes == 24, "the warren's stockade has a 2-stake gate gap (got %d of 26)" % stakes)
	var rails := 0
	for part in Kit.plan("zombie-graveyard"):
		if String(part["role"]) == "iron":
			rails += 1
	check(rails == 22, "the graveyard's railings have a 2-post gate gap (got %d of 24)" % rails)

	# --- the cave mouth is a hole, not a smudge ------------------------------
	# It has to sit inside the mound's own footprint or it is a black box parked
	# next to a rock.
	var mouth_ok := false
	var mound := 0.0
	for part in Kit.plan("dragon-cave"):
		if String(part["part"]) == "rock" and String(part["role"]) == "stone":
			mound = maxf(mound, float(part["size"].x) * 0.5)
		if String(part["role"]) == "dark":
			var d: float = Vector2(part["pos"].x, part["pos"].z).length()
			mouth_ok = d < mound
	check(mouth_ok, "the cave mouth sits inside the mound it is cut into")

	# --- build(): the nodes come out -----------------------------------------
	var node: Node3D = Kit.build("sunken-ruins")
	check(node != null and node.get_child_count() == Kit.plan("sunken-ruins").size(),
		"one MeshInstance3D per planned part")
	var meshed := true
	for child in node.get_children():
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null \
				or (child as MeshInstance3D).material_override == null:
			meshed = false
	check(meshed, "every part has a mesh and a material")
	var other: Node3D = Kit.build("sunken-ruins")
	check(other.get_child(0).mesh == node.get_child(0).mesh,
		"two builds share mesh resources")
	# A lair's "stone" and a settlement's "stone" are different colours, so the
	# shared material cache has to be namespaced per kit.
	var Settlement = load("res://scenes/world/settlement_kit.gd")
	var lair_stone := KitParts.material_for("sunken-ruins", "stone", Kit.LAIRS["sunken-ruins"], 1)
	var town_stone := KitParts.material_for("human_town", "stone", Settlement.PROFILES["human"], 1)
	check(lair_stone != town_stone and lair_stone.albedo_color != town_stone.albedo_color,
		"kits do not share each other's materials through the cache")
	node.free()
	other.free()

	check(Lairs3D.source == "kit", "the kit is the default source")

	print("test_lair_kit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		for key in ["part", "role", "shade", "yaw", "tilt"]:
			if a[i][key] != b[i][key]:
				return false
		if not (a[i]["pos"] as Vector3).is_equal_approx(b[i]["pos"]):
			return false
		if not (a[i]["size"] as Vector3).is_equal_approx(b[i]["size"]):
			return false
	return true

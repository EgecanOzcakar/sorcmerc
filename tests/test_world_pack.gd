# M3 — a map written as JSON builds the same World a hand-placed builder does,
# and a map that is wrong says so instead of loading half of itself.
#   godot --headless --path . -s tests/test_world_pack.gd
extends SceneTree

const WorldPack = preload("res://core/mod/world_pack.gd")
const Regions = preload("res://core/regions.gd")
const Registry = preload("res://core/mod/registry.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_build()
	test_start()
	test_water()
	test_rejects()
	test_warnings()
	test_shipped_map_is_banded()
	test_landmarks()
	print("test_world_pack: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _src(extra := {}) -> Dictionary:
	var d := {"format": "sorcmerc-world", "version": 1, "name": "Test Vale",
		"settlements": [
			{"id": "hold", "name": "The Hold", "position": [0, 0], "faction": "human", "kind": "city"},
			{"id": "copse", "position": [300, -100], "faction": "elf", "kind": "camp"}],
		"lairs": [{"id": "warren", "position": [180, 140], "faction": "goblinoid"},
			{"id": "cairn", "name": "The Cairn", "position": [-400, 300], "faction": "undead",
			 "discovered": true}],
		"parties": [
			{"id": "raiders", "position": [-200, -150], "faction": "bandit",
			 "troops": [{"role": "heavy", "level": 3}], "ai": {"behavior": "hunt"}},
			{"id": "wardens", "position": [120, 60], "faction": "human",
			 "ai": {"behavior": "patrol", "waypoints": ["hold", "copse", [120, 60]]}},
			{"id": "foragers", "position": [200, 180], "faction": "goblinoid",
			 "ai": {"behavior": "wander", "home": "warren", "radius": 90, "seed": 3}},
			{"id": "rock", "position": [-50, 400], "faction": "beast", "ai": {"behavior": "idle"}}],
		"start": {"at": "hold", "offset": [40, 40]}}
	d.merge(extra, true)
	return d

func test_build() -> void:
	var w = WorldPack.build(_src(), "testpack", 11)
	check(w != null, "a valid world builds")
	check(w.settlements.size() == 2 and w.lairs.size() == 2, "everything placed is there")
	check(w.settlements[0].sname == "The Hold", "a named settlement keeps its name")
	check(w.settlements[1].sname == "Copse", "an unnamed one derives it, like every builder does")
	check(w.lairs[1].discovered, "a lair may start already known")
	check(not w.lairs[0].discovered, "...and one that does not say so does not")
	check(String(w.origin["kind"]) == "pack:testpack" and int(w.origin["seed"]) == 11,
		"the map records the pack that made it")
	check(w.player() != null and w.player().is_player, "there is exactly one player party")
	var ids: Array = []
	for p in w.parties:
		ids.append(p.id)
	check(ids.has("raiders") and ids.has("wardens") and ids.has("foragers"), "bands are placed")
	var raiders = _party(w, "raiders")
	check(raiders.troops.size() == 1 and int(raiders.troops[0]["level"]) == 3, "troops survive")
	check(String(raiders.ai.get("behavior", "")) == "hunt", "hunt")
	var wardens = _party(w, "wardens")
	check(String(wardens.ai.get("behavior", "")) == "patrol", "patrol")
	check(wardens.ai["waypoints"].size() == 3, "...with every waypoint")
	check(wardens.ai["waypoints"][0] == Vector2(0, 0),
		"a waypoint may name a settlement instead of a point")
	var foragers = _party(w, "foragers")
	check(String(foragers.ai.get("behavior", "")) == "wander", "wander")
	check(foragers.ai["home"] == Vector2(180, 140), "...anchored on a named lair")
	check(_party(w, "rock").goal == _party(w, "rock").position, "idle stands still")

func _party(w, id):
	for p in w.parties:
		if p.id == id:
			return p
	return null

func test_start() -> void:
	var w = WorldPack.build(_src(), "p")
	check(w.player().position == Vector2(40, 40), "start is a settlement plus an offset")
	var at_point = WorldPack.build(_src({"start": {"position": [500, 500]}}), "p")
	check(at_point.player().position == Vector2(500, 500), "...or a bare point")
	var none = WorldPack.build(_src({"start": {}}), "p")
	check(none.player().position == Vector2(0, 0), "with no start, the first settlement")

func test_water() -> void:
	var w = WorldPack.build(_src({"waters": [
		{"position": [-600, 0], "radius": 80},
		{"river": [[0, -500], [0, -400], [0, -300]], "radius": 40}]}), "p")
	check(w.waters.size() == 1 + 2 * WorldPack.RIVER_BLOBS + 1,
		"a river is stamped as a chain of blobs, one lake aside")
	check(w.is_water(Vector2(-600, 0)), "the lake is wet")
	check(w.is_water(Vector2(0, -450)), "so is the middle of a river segment")
	# The start sits in a lake: nobody may begin the game swimming.
	var wet = WorldPack.build(_src({"start": {"position": [0, 0]},
		"waters": [{"position": [0, 0], "radius": 120}]}), "p")
	check(not wet.is_water(wet.player().position), "a start inside water is snapped to the bank")

func test_rejects() -> void:
	check(_errs({"format": "nope"}).size() > 0, "the format is checked")
	check(_errs(_src({"settlements": []})).size() > 0, "a world needs a settlement")
	check(_errs(_src({"settlements": [{"id": "a", "position": [0, 0], "faction": "human",
		"kind": "metropolis"}]})).size() > 0, "settlement kinds are closed")
	check(_errs(_src({"settlements": [{"id": "a", "position": [0, 0], "faction": "nope"}]})).size() > 0,
		"unknown factions are caught")
	check(_errs(_src({"lairs": [{"id": "l", "position": [0, 0], "faction": "human"}]})).size() > 0,
		"a lair's faction has to be one the bestiary can fill a fight from")
	check(_errs(_src({"parties": [{"id": "player", "position": [0, 0], "faction": "human"}]})).size() > 0,
		"a pack may not place the player party itself")
	check(_errs(_src({"lairs": [{"id": "hold", "position": [9, 9], "faction": "undead"}]})).size() > 0,
		"ids are unique across every kind of thing on the map")
	check(_errs(_src({"parties": [{"id": "p", "position": [0, 0], "faction": "bandit",
		"ai": {"behavior": "loiter"}}]})).size() > 0, "behaviors are closed")
	check(_errs(_src({"parties": [{"id": "p", "position": [0, 0], "faction": "bandit",
		"ai": {"behavior": "patrol", "waypoints": [[0, 0]]}}]})).size() > 0,
		"a patrol with one waypoint is not a patrol")
	check(_errs(_src({"waters": [{"position": [0, 0]}]})).size() > 0, "water needs a radius")
	check(_errs(_src({"start": {"at": "nowhere"}})).size() > 0, "the start has to be a real place")
	check(_errs(_src({"settlements": [{"position": [0, 0], "faction": "human"}]})).size() > 0,
		"everything needs an id")
	check(WorldPack.build({"format": "nope"}) == null, "a world that does not validate does not build")

func test_warnings() -> void:
	var report := WorldPack.validate(_src({"waters": [{"position": [0, 0], "radius": 200}]}))
	check(report["errors"].is_empty(), "a settlement in a lake is a design problem, not a parse error")
	check(report["warnings"].size() >= 1, "...and it is reported as a warning")
	check("water" in String(report["warnings"][0]), "the warning says what is wrong")

# The shipped campaign's map is banded by core/regions.gd exactly like a
# built-in one, with no region data in the pack at all: an author gets the
# level curve by placing things, which is the whole promise of M3.
func test_shipped_map_is_banded() -> void:
	OS.set_environment("SORCMERC_MODS_DIR", "user://nonexistent-mods")
	var pack = Registry.find("ashen-road")
	check(pack != null, "the shipped campaign is installed")
	if pack == null:
		return
	var w = Registry.world_of(pack)
	check(w != null, "its map builds")
	check(Regions.band_of(w, _lair(w, "ash-warren").position) == "heartland",
		"the goblin warren is in the country a level 1-3 party can work")
	check(Regions.band_of(w, _lair(w, "barrow-of-kings").position) == "frontier",
		"the barrow is two countries out")
	check(Regions.within(w, _lair(w, "wyrmscar").position, "deeps"),   # either half of the Far Deeps
		"and the dragon is at the end of the map")

func _lair(w, id):
	for l in w.lairs:
		if l.id == id:
			return l
	return null

func _errs(src) -> Array:
	return WorldPack.validate(src)["errors"]

func test_landmarks() -> void:
	var src := _src({"landmarks": [
		{"id": "chapel", "kind": "shrine", "position": [200, 40], "name": "the Broken Chapel"},
		{"id": "ring", "kind": "stones", "position": [-200, 90]}]})
	check(WorldPack.validate(src)["errors"].is_empty(), "two landmarks validate")
	var w = WorldPack.build(src)
	check(w.landmarks.size() == 2 and w.landmark("chapel").sname == "the Broken Chapel"
		and w.landmark("ring").kind == "stones" and w.landmark("ring").sname != "", "...and are built, named when no name is given")
	var bad := _src({"landmarks": [{"id": "x", "kind": "pyramid", "position": [1, 1]}]})
	var errs: Array = WorldPack.validate(bad)["errors"]
	check(errs.any(func(e): return "pyramid" in String(e)), "an unknown kind is a scan-time error: %s" % str(errs))
	var dup := _src({"landmarks": [{"id": "hold", "kind": "ruins", "position": [1, 1]}]})
	check(not WorldPack.validate(dup)["errors"].is_empty(), "a landmark cannot reuse a settlement's id")

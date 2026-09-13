# T-worlds: small (World._small_world, the original 4-settlement map),
# large (LargeWorld.build(), 8 settlements/2 per race + more of everything
# else), or procedural (ProceduralWorld.build(), seeded, one settlement per
# race) — picked via World.world_size before _ready() builds one. All three
# use every mechanic added this session (Settlements3D/Lairs3D/Party3D,
# lairs, faction-scoped quests) unmodified — this only checks the content
# differs and the picker actually routes to the right builder.
#   godot --headless --path . -s tests/test_world_sizes.gd
extends SceneTree

const LargeWorld = preload("res://scenes/world/large_world.gd")
const WorldAI = preload("res://core/world_ai.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var w := LargeWorld.build()
	check(w.settlements.size() == 8, "large world has 8 settlements (got %d)" % w.settlements.size())
	check(w.lairs.size() == 5, "large world has all 5 named lairs (got %d)" % w.lairs.size())
	check(w.player() != null, "large world has a player party")
	var races := {}
	for s in w.settlements:
		races[s.faction] = int(races.get(s.faction, 0)) + 1
	check(races.size() == 4 and races.values().all(func(n): return n == 2),
		"exactly 2 settlements per race (dwarf/elf/human/orc), got %s" % races)
	for s in w.settlements:
		check(not WorldAI.is_monster(s.faction) or s.faction == "orc",
			"every large-world settlement's faction is civilized or orc, not a stray")

	var small = load("res://scenes/world/world.tscn").instantiate()
	small.world_size = "small"
	root.add_child(small)
	for i in 10:
		await process_frame
	check(small.world.settlements.size() == 4, "world_size='small' still builds the original 4-settlement map")

	var large = load("res://scenes/world/world.tscn").instantiate()
	large.world_size = "large"
	root.add_child(large)
	for i in 10:
		await process_frame
	check(large.world.settlements.size() == 8, "world_size='large' routes to LargeWorld, not the small map")
	check(large._settlements3d != null and large._lairs3d != null and large._party3d != null,
		"the large world gets the same 3D layers as the small one")

	var proc = load("res://scenes/world/world.tscn").instantiate()
	proc.world_size = "procedural"
	root.add_child(proc)
	for i in 10:
		await process_frame
	check(proc.world.settlements.size() == 4, "world_size='procedural' routes to ProceduralWorld, not the small map")
	check(proc._settlements3d != null and proc._lairs3d != null and proc._party3d != null,
		"the procedural world gets the same 3D layers as the other two")

	print("test_world_sizes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

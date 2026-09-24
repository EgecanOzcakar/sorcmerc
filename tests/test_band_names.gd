# The design audit §6.1 (docs/audit-game-design.md): a roaming band is named
# to the player by EnemyNames.band_name, never by its id. The model only,
# headless — the seed, the save, a pack's own name, the respawn, the raiders,
# and the lines that used to print "Goblin Raiders 3".
#   godot --headless --path . -s tests/test_band_names.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBands = preload("res://core/world_bands.gd")
const WorldSave = preload("res://core/world_save.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")
const EnemyNames = preload("res://core/enemy_names.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const Quest = preload("res://core/quest.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/band-names-%d-%d" % [OS.get_process_id(), randi()])
	test_seeded()
	test_save_and_respawn()
	test_pack_name()
	test_raiders()
	test_lines()
	print("test_band_names: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _band(w, id: String, faction: String, at := Vector2(300, 0)):
	return w.add_party(World.RoamingParty.new(id, at, faction))

# --- the name itself ----------------------------------------------------------

func test_seeded() -> void:
	var w := ProceduralWorld.build(5)
	var names := {}
	for p in w.parties:
		if p.is_player:
			continue
		var n := EnemyNames.band_name(p, w)
		names[n] = true
		check(n != "" and n == EnemyNames.band_name(p, w), "%s: named, and the same twice (%s)" % [p.id, n])
		check(n != p.id.capitalize() and not n.contains(p.id) and not n.contains(p.id.capitalize()),
			"%s: the name is not the id (%s)" % [p.id, n])
		check(not n.right(1).is_valid_int(), "%s: no trailing number (%s)" % [p.id, n])
	check(names.size() >= 4, "a map's bands are not all called the same thing (%d names)" % names.size())

	# The world's seed is part of it: the same id on another map is somebody else.
	var a = _band(World.new(), "goblin-raiders-3", "goblinoid")
	var differ := 0
	for s in 12:
		var ws := World.new()
		ws.origin = {"kind": "procedural", "seed": s}
		var b = _band(ws, "goblin-raiders-3", "goblinoid")
		if EnemyNames.band_name(b, ws) != EnemyNames.band_name(b, World.new()):
			differ += 1
	check(differ >= 6, "the world seed moves the name (%d of 12 seeds differ from seed 0)" % differ)
	check(EnemyNames.band_name(a) == EnemyNames.band_name(a, World.new()), "no world is seed 0")

	# Faction words: a pack of wolves is named for a place, never a leader; a
	# people's band ends in its own plural.
	var wb := World.new()
	for i in 20:
		var beasts = _band(wb, "beast-pack-%d" % i, "beast")
		var n := EnemyNames.band_name(beasts, wb)
		check(n.begins_with("the ") and n.ends_with(" beasts"), "beasts are named for a place: %s" % n)
		var gnolls = _band(wb, "gnoll-pack-%d" % i, "gnoll")
		check(EnemyNames.band_name(gnolls, wb).ends_with(" gnolls"), "gnolls are gnolls: %s" % EnemyNames.band_name(gnolls, wb))
	var leaders := 0
	for i in 20:
		var n := EnemyNames.band_name(_band(wb, "bandit-gang-%d" % i, "bandit"), wb)
		if not n.begins_with("the "):   # "the Shepherd's Cross bandits" is a place
			leaders += 1
			check(EnemyNames.NAMES["bandit"].has(n.get_slice("'s ", 0)), "a bandit leader is a bandit's name: %s" % n)
	check(leaders > 0 and leaders < 20, "bandits are sometimes named for a leader, sometimes a place (%d of 20)" % leaders)
	var caravan = _band(wb, "caravan-1", "human")
	caravan.ai["kind"] = "caravan"
	check(EnemyNames.band_name(caravan, wb).ends_with(" wagons"), "a caravan is wagons: %s" % EnemyNames.band_name(caravan, wb))

	check(EnemyNames.upper_first("the Low Fen gnolls") == "The Low Fen gnolls", "upper_first capitalises the head")
	check(EnemyNames.upper_first("Ribsnap's goblins") == "Ribsnap's goblins" and EnemyNames.upper_first("") == "",
		"...and leaves the rest alone")
	check(not EnemyNames.NAMES["soldier"].has("Dresden") and EnemyNames.NAMES["soldier"].has("Dresk"), "Dresden is Dresk")
	var seen := {}
	var dupes: Array = []
	for f in EnemyNames.NAMES:
		for n in EnemyNames.NAMES[f]:
			if seen.has(n) and n != "Sable":   # Sable is GENERIC's too; not a people's clash
				dupes.append(n)
			seen[n] = true
	check(dupes.is_empty(), "no first name belongs to two peoples: %s" % [dupes])

# --- it outlives a reload and a death -----------------------------------------

func test_save_and_respawn() -> void:
	var w := ProceduralWorld.build(9)
	var before := {}
	for p in w.parties:
		before[p.id] = EnemyNames.band_name(p, w)
	var w2 = WorldSave.from_dict(WorldSave.to_dict(w))["world"]
	for p in w2.parties:
		check(EnemyNames.band_name(p, w2) == before.get(p.id, "?"), "%s reads the same after a reload" % p.id)

	# Beaten, it waits in the fallen list and comes back as itself.
	var band = null
	for p in w2.parties:
		if not p.is_player and WorldAI.is_monster(p.faction):
			band = p
			break
	var was := EnemyNames.band_name(band, w2)
	WorldAI.fell(w2, band)
	w2.parties.erase(band)
	check(EnemyNames.band_name(w2.fallen[-1], w2) == was, "the fallen record names it the same")
	var w3 = WorldSave.from_dict(WorldSave.to_dict(w2))["world"]
	var lines: Array = WorldAI.respawn(w3, w3.clock.elapsed + WorldAI.BAND_RESPAWN + 1.0)
	var back = null
	for p in w3.parties:
		if p.id == band.id:
			back = p
	check(back != null and EnemyNames.band_name(back, w3) == was, "back on the roads under the same name")
	check(lines.any(func(l): return String(l).begins_with(EnemyNames.upper_first(was) + " are on the roads again")),
		"the respawn line says who, not which id: %s" % [lines])

	# An old save — no sname anywhere — loads with every band seeded.
	var d: Dictionary = WorldSave.to_dict(w)
	for pd in d["parties"]:
		pd.erase("sname")
	var old = WorldSave.from_dict(d)["world"]
	check(old.parties.all(func(p): return p.sname == ""), "an old save loads with no authored names")
	for p in old.parties:
		check(EnemyNames.band_name(p, old) == before.get(p.id, "?"), "...and names %s as it always would have" % p.id)

# --- a pack's own name wins -----------------------------------------------------

func test_pack_name() -> void:
	var src := {"format": WorldPack.FORMAT, "version": 1, "name": "Test", "settlements": [
			{"id": "town", "name": "Town", "position": [0, 0], "faction": "human", "kind": "town"}],
		"parties": [
			{"id": "red-hand", "name": "The Red Hand", "position": [300, 0], "faction": "bandit"},
			{"id": "nameless", "position": [-300, 0], "faction": "bandit"}]}
	var w = WorldPack.build(src, "test-pack", 3)
	check(w != null, "the pack builds")
	var red = null
	var other = null
	for p in w.parties:
		if p.id == "red-hand": red = p
		if p.id == "nameless": other = p
	check(red.sname == "The Red Hand" and EnemyNames.band_name(red, w) == "The Red Hand", "a pack's name is the name")
	check(other.sname == "" and EnemyNames.band_name(other, w) != "Nameless", "an unnamed pack band is seeded")
	var w2 = WorldSave.from_dict(WorldSave.to_dict(w))["world"]
	for p in w2.parties:
		if p.id == "red-hand":
			check(EnemyNames.band_name(p, w2) == "The Red Hand", "...and survives the save")
			WorldAI.fell(w2, p)
	check(EnemyNames.band_name(w2.fallen[-1], w2) == "The Red Hand", "...and the grave")

# --- raiders are named for their lair --------------------------------------------

func test_raiders() -> void:
	var w := World.new()
	w.add_lair(World.Lair.new("vale-warren", Vector2(200, 0), "goblinoid", "The Vale Warren"))
	var r = _band(w, "vale-warren-raiders", "goblinoid")
	WorldAI.raid(r, Vector2.ZERO, "town", "vale-warren")
	check(EnemyNames.band_name(r, w) == "the raiders out of The Vale Warren", "raiders: %s" % EnemyNames.band_name(r, w))

# --- the lines that used to print an id ---------------------------------------------

func test_lines() -> void:
	var w := World.new()
	w.origin = {"kind": "procedural", "seed": 17}
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var giver = w.add_settlement(World.Settlement.new("town", Vector2(50, 0), "human", "town"))
	var b = _band(w, "goblin-raiders-3", "goblinoid")
	var q: Dictionary = Quest.world_quest_for(w, giver, RNG.new(4))
	check(q.get("kind", "") == "hunt_party", "the only target is the band")
	check(String(q.get("title", "")) == "Hunt down %s" % EnemyNames.band_name(b, w),
		"the posting names it: %s" % q.get("title", ""))
	check(not ("Goblin Raiders 3" in String(q.get("title", ""))) and not (" band" in String(q.get("title", ""))),
		"...never by its id")
	for kind in Quest.CHAIN_LABELS:
		for label in Quest.CHAIN_LABELS[kind]:
			check(not ("Raze" in label or "Purge" in label or "once and for all" in label or "threat" in label),
				"the chain speaks plainly: %s" % label)

	# The refill line, when a band turns up near the party, says who.
	var wf := ProceduralWorld.build(5)
	var said := ""
	var rng := RNG.new(11)
	for i in 400:
		for p in wf.parties.duplicate():
			if not p.is_player:
				wf.parties.erase(p)
		wf.bands_refilled_at = -1e9
		said = WorldBands.refill(wf, float(i) * WorldBands.REFILL_MINUTES, rng)
		if said != "":
			break
	check(said != "", "a refill lands near the party within 400 tries")
	if said != "":
		var nb = wf.parties[-1]
		check(said.begins_with("Word on the road: %s," % EnemyNames.band_name(nb, wf)), "the refill line names the band: %s" % said)

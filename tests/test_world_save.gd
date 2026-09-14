# O13 — the open-world autosave slot: a World + faction opinion + the player's
# party round-trip through JSON with every field intact.
#   godot --headless --path . -s tests/test_world_save.gd
extends SceneTree

const Travel = preload("res://core/travel.gd")

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldSave = preload("res://core/world_save.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _world() -> World:
	var w := World.new()
	var s := w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "soldier", "city"))
	s.last_visited = 120.0
	s.battle_at = 66.5
	s.pending_opinion_delta = -3.5
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "cultist", "city", "Ashfell"))
	var p := w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "soldier", true))
	w.set_goal(p, Vector2(300, -40))
	WorldAI.hunt(w.add_party(World.RoamingParty.new("bandits", Vector2(-250, -120), "bandit")))
	WorldAI.patrol(w.add_party(World.RoamingParty.new("patrol", Vector2(-120, 380), "soldier")),
		[Vector2(-120, 380), Vector2(0, 0)])
	# wander() reads `home.position`, so it wants a settlement, not a point.
	WorldAI.wander(w.add_party(World.RoamingParty.new("elk", Vector2(40, 40), "goblinoid")),
		w.settlements[0], 90.0, 4242)
	w.parties[1].troops = [{"role": "heavy", "level": 3}, {"role": "light", "level": 5}]
	var l := w.add_lair(World.Lair.new("goblin-warren", Vector2(560, 60), "goblinoid"))
	l.discovered = true
	w.add_lair(World.Lair.new("dragon-cave", Vector2(680, -400), "dragon", "Dragon's Cave"))
	# T-water: a lake and two river blobs — terrain the resumed world has to
	# still be wet, now that it also blocks movement.
	w.add_water(Vector2(-190, -70), 100.0)
	w.add_water(Vector2(-110, -20), 40.0)
	w.add_water(Vector2(-40, 100), 40.0)
	w.origin = {"kind": "procedural", "seed": 4242}
	w.clock.elapsed = 742.5
	return w

func _party() -> Party:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.add_gold(137)
	p.stash_add("potion-of-healing", 2)
	p.overworld_figure = "wizard"
	return p

func _init() -> void:
	# O17: this process's own autosave slots, so a concurrent godot run cannot
	# clobber them. randi() as well as the pid: under a sandboxed (flatpak)
	# godot every process sees pid 3, so the pid alone is not unique.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	WorldSave.clear()
	check(WorldSave.load_latest() == null, "no autosave, no world")
	check(not WorldSave.has_save(), "cleared slot reports no save")

	var w := _world()
	var party := _party()
	FactionOpinion.reset()
	FactionOpinion.set_opinion("soldier", -12.5)
	FactionOpinion.set_opinion("cultist", 30.0)
	# Advance the wander RNG before saving: restoring the seed alone would rewind it.
	var elk = _find(w, "elk")
	elk.ai["rng"].roll_die(100)

	WorldSave.save(w, party)
	check(WorldSave.has_save(), "save() writes the slot")
	FactionOpinion.reset()

	var got = WorldSave.load_latest()
	if got == null:
		check(false, "the slot did not load back")
		_done()
		return
	var w2 = got["world"]
	var p2 = got["party"]

	check(is_equal_approx(w2.clock.elapsed, 742.5), "the world clock survives")
	check(FactionOpinion.get_opinion("soldier") == -12.5
		and FactionOpinion.get_opinion("cultist") == 30.0, "faction opinion is re-applied")

	# --- settlements ---------------------------------------------------------
	check(w2.settlements.size() == 2, "both settlements came back")
	var s = w2.settlements[0]
	check(s.id == "riverhold" and s.sname == "Riverhold" and s.kind == "city"
		and s.faction == "soldier" and s.position == Vector2(0, 0), "settlement identity")
	check(s.last_visited == 120.0 and s.battle_at == 66.5
		and s.pending_opinion_delta == -3.5, "settlement visit/battle/opinion state")
	check(w2.settlements[1].position == Vector2(160, 470), "the second settlement's place")

	# --- parties -------------------------------------------------------------
	check(w2.parties.size() == 4, "every party came back")
	var pl = w2.player()
	check(pl != null and pl.id == "player" and pl.is_player, "the player party is still the player")
	check(pl.position == Vector2(80, 120) and pl.goal == Vector2(300, -40), "position and goal")
	check(pl.speed == World.SPEED, "party speed")

	check(_find(w2, "bandits").ai.get("behavior", "") == "hunt", "hunt state")
	var pat = _find(w2, "patrol")
	check(pat.ai.get("behavior", "") == "patrol" and pat.ai["waypoints"].size() == 2
		and pat.ai["waypoints"][1] == Vector2(0, 0), "patrol waypoints are Vector2s again")
	check(int(pat.ai.get("index", -1)) == 0, "the patrol's place in its route")
	var elk2 = _find(w2, "elk")
	check(elk2.ai.get("behavior", "") == "wander" and elk2.ai["home"] == Vector2(0, 0)
		and is_equal_approx(float(elk2.ai["radius"]), 90.0), "wander home/radius")
	check(elk2.ai["rng"].roll_die(100) == elk.ai["rng"].roll_die(100),
		"the wander RNG resumes mid-sequence, not from its seed")
	check(elk2.ai["rng"].seed_value == 4242, "…and the seed itself is kept too")
	check(_find(w2, "bandits").troops.size() == 2
		and int(_find(w2, "bandits").highest_troop().get("level", -1)) == 5,
		"a party's flavour troop roster survives, highest-level troop intact")

	# --- lairs (T91 -- didn't exist when this format was designed) -----------
	check(w2.lairs.size() == 2, "both lairs came back")
	var gw = w2.lairs[0]
	check(gw.id == "goblin-warren" and gw.sname == "Goblin Warren" and gw.faction == "goblinoid"
		and gw.position == Vector2(560, 60) and gw.discovered and not gw.looted,
		"a lair's identity and discovery state")
	check(w2.lairs[1].sname == "Dragon's Cave", "a lair's custom display name survives, not just its id")

	# --- water (T-water -- likewise newer than the format) --------------------
	check(w2.waters.size() == 3, "every water blob came back (got %d)" % w2.waters.size())
	check(w2.waters[0]["position"] == Vector2(-190, -70)
		and is_equal_approx(float(w2.waters[0]["radius"]), 100.0), "the lake keeps its place and size")
	check(w2.is_water(Vector2(-190, -70)) and w2.water_depth(Vector2(-40, 100)) < 0.0,
		"the restored map is still wet where it was wet")
	check(not w2.is_water(Vector2(500, 500)), "...and still dry where it was dry")

	# --- provenance ----------------------------------------------------------
	check(String(w2.origin.get("kind", "")) == "procedural"
		and int(w2.origin.get("seed", -1)) == 4242, "the world remembers which builder made it")

	# --- a save from before either key existed -------------------------------
	var old_save: Dictionary = WorldSave.to_dict(_world(), null)
	old_save.erase("waters")
	old_save.erase("origin")
	var old_world = WorldSave.from_dict(old_save)["world"]
	check(old_world.waters.is_empty(), "an old save with no \"waters\" loads dry, not broken")
	check(String(old_world.origin.get("kind", "")) == "small"
		and int(old_world.origin.get("seed", -1)) == 0, "...and with no \"origin\" reads as the small map")

	# --- the player's own party ----------------------------------------------
	check(p2.roster.size() == party.roster.size(), "the roster came back")
	check(Array(p2.active) == Array(party.active), "marching order")
	check(p2.gold == 137, "the purse")
	check(p2.stash_count("potion-of-healing") == 2, "the stash")
	check(p2.overworld_figure == "wizard", "the chosen map figure")

	# --- the world still runs ------------------------------------------------
	w2.tick(0.1)
	check(not pl.position.is_equal_approx(Vector2(80, 120)), "a loaded world ticks and moves")

	# --- junk is not a save --------------------------------------------------
	check(WorldSave.from_dict({"format": "nope"}) == null, "a foreign file is not a world")
	check(WorldSave.from_dict({}) == null, "an empty dict is not a world")
	WorldSave.clear()
	check(not WorldSave.has_save(), "clear() removes the slot")
	check(WorldSave.load_latest() == null, "…and nothing loads afterwards")
	FactionOpinion.reset()
	_done()

func _find(w, id: String):
	for p in w.parties:
		if p.id == id:
			return p
	return null

func _done() -> void:
	# D3: standing orders are a marching decision, so they have to survive a
	# reload — a party that comes back from a save marching at a pace it was
	# never set to is the same bug class as the figure picker's stale class id.
	var wo := World.new()
	wo.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var po := _party()
	Travel.set_orders(po, "careful", String(po.active[0]), String(po.active[1]))
	var back_o = WorldSave.from_dict(WorldSave.to_dict(wo, po))
	var ro: Dictionary = Travel.orders(back_o["party"])
	check(String(ro["pace"]) == "careful", "the marching pace survives a save")
	check(String(ro["scout"]) == String(po.active[0]), "...and who was scouting")
	check(String(ro["watch"]) == String(po.active[1]), "...and who had the watch")
	check(Travel.speed_mult(back_o["party"]) < 1.0, "...and it still moves the party's speed")

	# An old save has no orders at all and must simply march at the default.
	var d_old: Dictionary = WorldSave.to_dict(wo, _party())
	d_old["party"].erase("travel_orders")
	var back_old = WorldSave.from_dict(d_old)
	check(String(Travel.orders(back_old["party"])["pace"]) == "normal",
		"a save from before standing orders marches at the default")

		# O13+: the title screen has to be able to say what is in the slot without
	# rebuilding a World, say that there is only one of them, and clear it.
	# "Resume the open world" on its own told the player none of that.
	var Game = load("res://scenes/game/game.gd")
	WorldSave.clear()
	check(WorldSave.summary().is_empty(), "no slot, no summary")

	var w2 := World.new()
	w2.origin = {"kind": "procedural", "seed": 42}
	w2.clock.elapsed = 1440.0 + 14 * 60.0 + 5.0        # Day 2, 14:05
	var p2 := Party.new()
	for ch in Presets.party():
		p2.add_member(ch)
	p2.add_gold(275)
	WorldSave.save(w2, p2)

	var slot: Dictionary = WorldSave.summary()
	check(not slot.is_empty(), "a written slot summarises")
	check(WorldSave.day_clock(float(slot["elapsed"])) == "Day 2  14:05",
		"the summary reads the same clock the map does (got %s)"
			% WorldSave.day_clock(float(slot["elapsed"])))
	check(String(slot["map"]) == "procedural", "and names the map it was built from")
	check(int(slot["gold"]) == 275, "and the purse")
	check(not slot["party"].is_empty(), "and who was standing")
	check(int(slot["written_at"]) > 0, "and when it was written")

	var line: String = Game.slot_line(slot)
	for bit in ["Day 2  14:05", "procedural", "275 gp"]:
		check(line.contains(bit), "the title line says %s (got %s)" % [bit, line])

	WorldSave.clear()
	check(WorldSave.summary().is_empty(), "and the slot can be cleared from the title")

	print("test_world_save: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

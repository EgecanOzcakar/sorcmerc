# The road home (core/world_road_home.gd) and the walk-home curve it switches
# on in core/world_threat.gd: set when a company comes out of a site, lapses at
# dawn or at the end of a long rest (whichever first), survives a save, and an
# old save with no key loads as nobody walking home. Headless, the model only.
#   godot --headless --path . -s tests/test_world_road_home.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldRoadHome = preload("res://core/world_road_home.gd")
const WorldThreat = preload("res://core/world_threat.gd")
const WorldSave = preload("res://core/world_save.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

# Every member at `frac` of max HP, every slot spent: the company a lair lets out.
func _drained(p: Party, frac: float) -> Party:
	for id in p.active:
		var ch = p.get_member(id)
		ch.slots_used = Adapter._full_slots(ch.sheet())
		ch.hp_current = maxi(1, int(round(float(p.summary(id)["max_hp"]) * frac)))
		ch.dirty()
	return p

# The world clock set so the hour on its face is `hour` of day `day` (0-based).
func _at(w: World, day: int, hour: float) -> void:
	w.clock.elapsed = day * 1440.0 + (hour - w.clock.START_HOUR) * 60.0

func _init() -> void:
	test_not_walking_by_default()
	test_set_and_lapse_at_dawn()
	test_lapses_at_long_rest()
	test_rest_before_the_delve_does_not_end_it()
	test_survives_save_and_old_saves_load()
	test_curve_is_gentler_and_never_harsher()
	test_assess_reads_the_clock()
	print("test_world_road_home: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_not_walking_by_default() -> void:
	var w := _world()
	var p := _party()
	check(float(w.walk_home_from) < 0.0, "a new world has nobody walking home")
	check(not WorldRoadHome.active(w, p), "so the clock is off")
	check(WorldRoadHome.ends_at(w) < 0.0, "and has no end to report")
	check(WorldRoadHome.hud_note(w, p) == "", "and the bar says nothing")
	check(not WorldRoadHome.active(null, p), "no world is no walk home")

func test_set_and_lapse_at_dawn() -> void:
	var w := _world()
	var p := _party()
	_at(w, 2, 21.5)   # out of the lair at half past nine at night
	WorldRoadHome.set_out(w)
	check(WorldRoadHome.active(w, p), "set when the company comes out of a site")
	check(WorldRoadHome.hud_note(w, p) == WorldRoadHome.HUD_NOTE, "and the bar says so")
	var dawn := 3 * 1440.0 + (WorldRoadHome.DAWN_HOUR - w.clock.START_HOUR) * 60.0
	check(is_equal_approx(WorldRoadHome.ends_at(w), dawn),
		"it ends at the next dawn (%.1f, want %.1f)" % [WorldRoadHome.ends_at(w), dawn])
	w.clock.elapsed = dawn - 1.0
	check(WorldRoadHome.active(w, p), "still on a minute before dawn")
	w.clock.elapsed = dawn
	check(not WorldRoadHome.active(w, p), "and off when the sun is up")
	check(WorldRoadHome.hud_note(w, p) == "", "the bar goes quiet with it")
	# Out in the morning: the next dawn is tomorrow's, not a minute away.
	_at(w, 4, 9.0)
	WorldRoadHome.set_out(w)
	check(is_equal_approx(WorldRoadHome.ends_at(w), 5 * 1440.0 + (WorldRoadHome.DAWN_HOUR - w.clock.START_HOUR) * 60.0),
		"out at nine in the morning, the walk runs to tomorrow's dawn")
	_at(w, 6, WorldRoadHome.DAWN_HOUR)
	WorldRoadHome.set_out(w)
	check(is_equal_approx(WorldRoadHome.ends_at(w) - w.clock.elapsed, 1440.0),
		"out on the stroke of dawn, the next dawn is a day off")

func test_lapses_at_long_rest() -> void:
	var w := _world()
	var p := _party()
	_at(w, 1, 10.0)
	WorldRoadHome.set_out(w)
	p.last_long_rest_at = -1e12   # the gate is open
	Visit.rest(p, w, "short-rest")
	check(WorldRoadHome.active(w, p), "a short rest does not end the walk")
	Visit.rest(p, w, "long-rest")
	check(w.clock.elapsed < WorldRoadHome.ends_at(w), "(the night ended before the dawn it was running to)")
	check(not WorldRoadHome.active(w, p), "a long rest does, before dawn comes")

func test_rest_before_the_delve_does_not_end_it() -> void:
	var w := _world()
	var p := _party()
	_at(w, 1, 12.0)
	p.last_long_rest_at = w.clock.elapsed   # slept at the door, went straight in; the clock stands still below
	WorldRoadHome.set_out(w)
	check(WorldRoadHome.active(w, p), "a night that ended on the minute the delve began was before it, not after")

func test_survives_save_and_old_saves_load() -> void:
	var w := _world()
	var p := _party()
	_at(w, 3, 20.0)
	WorldRoadHome.set_out(w)
	var d: Dictionary = WorldSave.to_dict(w, p)
	check(d.has("walk_home_from"), "the world save carries the clock")
	var back: Dictionary = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))
	var w2 = back["world"]
	var p2 = back["party"]
	check(is_equal_approx(float(w2.walk_home_from), float(w.walk_home_from)), "and it comes back as it went")
	check(WorldRoadHome.active(w2, p2), "so a reload mid-walk is still mid-walk")
	check(is_equal_approx(WorldRoadHome.ends_at(w2), WorldRoadHome.ends_at(w)), "ending at the same dawn")
	d.erase("walk_home_from")
	var old: Dictionary = WorldSave.from_dict(d)
	check(old != null, "a save from before the key loads")
	check(float(old["world"].walk_home_from) < 0.0 and not WorldRoadHome.active(old["world"], old["party"]),
		"as nobody walking home")

func test_curve_is_gentler_and_never_harsher() -> void:
	for i in 21:
		var f := float(i) / 20.0
		check(WorldThreat.power_scale(f, true) <= WorldThreat.power_scale(f) + 1e-6,
			"the walk home is never harsher than the road (hp %.2f)" % f)
		check(WorldThreat.power_scale(f, true) >= WorldThreat.WILDERNESS_SCALE * WorldThreat.WALK_HOME_FLOOR - 1e-6,
			"and never under its own floor (hp %.2f)" % f)
	check(WorldThreat.power_scale(0.5, true) < WorldThreat.power_scale(0.5),
		"at half HP it is gentler (%.3f vs %.3f)" % [WorldThreat.power_scale(0.5, true), WorldThreat.power_scale(0.5)])
	check(is_equal_approx(WorldThreat.power_scale(1.0, true), WorldThreat.SCALE_MAX),
		"and an unhurt company meets the road's own fight: the walk reads wounds, not slots")
	check(is_equal_approx(WorldThreat.power_scale(0.5), WorldThreat.curve(0.5, WorldThreat.HURT_AT, WorldThreat.CONDITION_FLOOR)),
		"the road's curve is the shared shape at the road's knobs")

func test_assess_reads_the_clock() -> void:
	var w := _world()
	var p := _drained(_party(), 0.5)
	var road := WorldThreat.assess(p, w)
	check(not bool(road["walking_home"]), "not walking home: the road's own reading")
	check(is_equal_approx(float(road["power_scale"]), float(WorldThreat.assess(p)["power_scale"])),
		"which is what a caller with no world gets")
	WorldRoadHome.set_out(w)
	var home := WorldThreat.assess(p, w)
	check(bool(home["walking_home"]), "fresh out of a site: the walk home")
	check(float(home["power_scale"]) < float(road["power_scale"]),
		"a thinner fight for the same wounds (%.3f vs %.3f)" % [float(home["power_scale"]), float(road["power_scale"])])
	check(is_equal_approx(float(home["slot_hold"]), float(road["slot_hold"])),
		"and the spent slots are held exactly as on the road — they never buy the easier fight")
	check(is_equal_approx(float(home["power_scale"]),
		WorldThreat.power_scale(float(home["hp_frac"]), true) * float(home["slot_hold"])),
		"power_scale is the walk-home curve times the hold")

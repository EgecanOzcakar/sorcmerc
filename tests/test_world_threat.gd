# T92: core/world_threat.gd — the wilderness baseline, the wounded-party budget
# scale and the floor under it, checked through real Scaler.roster_for() calls
# rather than only against the returned number.
#   godot --headless --path . -s tests/test_world_threat.gd
extends SceneTree

const WorldThreat = preload("res://core/world_threat.gd")
const Scaler = preload("res://core/scaler.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

# hp_current = -1 is the codebase's "full"; anything >= 0 is a real wound.
func _hurt(p: Party, frac: float) -> Party:
	for id in p.active:
		var ch = p.get_member(id)
		ch.hp_current = maxi(1, int(round(float(p.summary(id)["max_hp"]) * frac)))
	return p

func _spec_power(spec: Dictionary) -> float:
	var roster: Array = []
	for e in spec["monsters"]:
		for i in int(e["count"]):
			roster.append(Encounter.spawn(e["id"], float(e["mult"]), "foe", Vector2i.ZERO))
	return Power.team_score(roster)

func _total(spec: Dictionary) -> int:
	var n := 0
	for e in spec["monsters"]:
		n += int(e["count"])
	return n

func _init() -> void:
	test_fresh_party_is_untouched()
	test_baseline_is_easy()
	test_hurt_party_gets_a_thinner_roster()
	test_flat_wilderness_discount()
	test_floor_holds()
	test_monotone_in_health()
	test_never_scales_up()
	test_short_handed_is_not_hurt()
	test_spent_slots_do_not_shrink_the_fight()
	test_pressing_on_hurt_costs()
	print("test_world_threat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The whole feature has to be invisible to a party that hasn't been hurt yet:
# exactly 1.0, so Scaler._budget()'s multiply is an identity.
func test_fresh_party_is_untouched() -> void:
	var t := WorldThreat.assess(_party())
	check(t["hp_frac"] == 1.0, "an unwounded party reads as full HP (got %.3f)" % float(t["hp_frac"]))
	check(t["power_scale"] == WorldThreat.SCALE_MAX,
		"and gets the kindest scale there is, no condition discount (got %.6f)" % float(t["power_scale"]))
	check(int(t["counted"]) == 3, "the preset party is pooled from its 3 active members")
	# A fresh party is no longer a no-op through the scaler, and that is
	# deliberate: WILDERNESS_SCALE is a flat discount the road gets whatever
	# shape the party is in. What must still hold is that the knob itself is an
	# identity at 1.0, so nothing that does not opt in is affected.
	var chars := Presets.party()
	# str(), not ==: two Dictionaries built separately are not the same object,
	# and what matters is that the contents came out identical.
	check(str(Scaler.roster_for(chars, t["difficulty"], {}, "", 5, 1.0))
		== str(Scaler.roster_for(chars, t["difficulty"], {}, "", 5)),
		"the scale knob is still an exact identity at 1.0")
	# Asked across seeds, not on one. A discount of a tenth does not move every
	# roster — the budget buys whole monsters, so on a seed where the cut lands
	# inside a rounding step the spec comes out identical, which is arithmetic
	# rather than the knob failing. Pinned to seed 5 alone this read as a
	# regression the first time a TIER re-tune shifted which seeds those were
	# (T-classes-b: 28 of 30 seeds differ, and 5 stopped being one of them).
	var moved := 0
	for seed_value in range(1, 11):
		if str(Scaler.roster_for(chars, t["difficulty"], {}, "", seed_value, t["power_scale"])) \
				!= str(Scaler.roster_for(chars, t["difficulty"], {}, "", seed_value)):
			moved += 1
	check(moved >= 7, "...and the flat wilderness discount really does change the roster (%d of 10 seeds)" % moved)

func test_baseline_is_easy() -> void:
	check(WorldThreat.BASELINE == "easy", "the wilderness baseline is easy, not normal — sites are the hard content")
	check(WorldThreat.assess(_party())["difficulty"] == WorldThreat.BASELINE,
		"assess() hands the caller that baseline")
	check(Scaler.TIER.has(WorldThreat.BASELINE), "and it is a tier Scaler actually knows")

# The point of the whole exercise, measured where it lands: the roster itself.
func test_hurt_party_gets_a_thinner_roster() -> void:
	var chars := Presets.party()
	var fresh := WorldThreat.assess(_party())
	var beaten := WorldThreat.assess(_hurt(_party(), 0.3))
	check(float(beaten["hp_frac"]) < 0.4, "a party at 30%% HP reads as hurt (%.3f)" % float(beaten["hp_frac"]))
	check(float(beaten["power_scale"]) < WorldThreat.SCALE_MAX,
		"and asks for a smaller budget than an unhurt party (%.3f)" % float(beaten["power_scale"]))
	# Pooled over seeds, not one: scaler.gd's own TUNING header calls the mult
	# knob lumpy, and a single seed really can land on the same roster either
	# side of a budget cut this size. What has to be true is that the beaten
	# party faces less across the distribution it will actually meet.
	var a := 0.0
	var b := 0.0
	var thinner := 0
	for seed_v in range(1, 41):
		var pa := _spec_power(Scaler.roster_for(chars, fresh["difficulty"], {}, "", seed_v, fresh["power_scale"]))
		var pb := _spec_power(Scaler.roster_for(chars, beaten["difficulty"], {}, "", seed_v, beaten["power_scale"]))
		a += pa
		b += pb
		if pb < pa:
			thinner += 1
		check(pb <= pa, "seed %d: a beaten party never faces MORE than a fresh one" % seed_v)
	check(b < a, "pooled over 40 seeds the beaten party's rosters are weaker (%.1f vs %.1f)" % [b, a])
	check(thinner >= 20, "and it bites on most of them, not a lucky few (%d/40)" % thinner)
	check(b > 0.0, "but it is still a fight")

# The user's own ask, and the half of the scale that is not about condition:
# open-world bands are flatly some percent easier than the tier alone. Pinned
# here because it is a design decision, not an implementation detail.
func test_flat_wilderness_discount() -> void:
	check(WorldThreat.SCALE_MAX < 1.0, "a fresh party still gets a kinder road than the bare tier")
	check(WorldThreat.SCALE_MAX == WorldThreat.WILDERNESS_SCALE, "...by exactly the flat discount")
	# Over a spread of seeds, not one: the mult knob is 0.05-lumpy, so a single
	# seed can land on the same roster either side of the discount.
	var chars := Presets.party()
	var thinner := 0
	var fatter := 0
	for s in range(1, 11):
		var bare := _spec_power(Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", s))
		var road := _spec_power(Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", s, WorldThreat.SCALE_MAX))
		if road < bare:
			thinner += 1
		elif road > bare:
			fatter += 1
	check(thinner > 0 and fatter == 0, "and it really reaches the roster (%d/10 thinner, %d fatter)" % [thinner, fatter])

func test_floor_holds() -> void:
	check(WorldThreat.power_scale(0.0) == WorldThreat.SCALE_FLOOR, "zero HP bottoms out at the floor exactly")
	check(WorldThreat.power_scale(-1.0) == WorldThreat.SCALE_FLOOR, "and nothing below zero goes under it")
	var dying := WorldThreat.assess(_hurt(_party(), 0.0))   # maxi(1, ...) -> 1 hp each
	check(float(dying["power_scale"]) >= WorldThreat.SCALE_FLOOR,
		"1 hp each never dips below the floor (%.3f)" % float(dying["power_scale"]))
	check(float(dying["power_scale"]) < WorldThreat.SCALE_FLOOR + 0.05,
		"and sits right on it (%.3f)" % float(dying["power_scale"]))
	# The floor's real job: the roster it buys still exists.
	var chars := Presets.party()
	for seed_v in range(1, 21):
		var spec := Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", seed_v, WorldThreat.SCALE_FLOOR)
		check(_total(spec) >= 1, "seed %d: the floor still buys at least one body" % seed_v)
	# even for a party the budget formula barely registers at all
	check(_total(Scaler.roster_for([], WorldThreat.BASELINE, {}, "", 1, WorldThreat.SCALE_FLOOR)) >= 1,
		"an empty party at the floor still gets a roster")

func test_monotone_in_health() -> void:
	var prev := -1.0
	for i in range(0, 21):
		var s := WorldThreat.power_scale(float(i) / 20.0)
		check(s >= prev, "scale never falls as the party gets healthier (%.3f -> %.3f)" % [prev, s])
		prev = s
	check(WorldThreat.power_scale(1.0) > WorldThreat.power_scale(0.0), "and it really does move across the range")
	check(WorldThreat.power_scale(WorldThreat.HURT_AT) == WorldThreat.SCALE_MAX,
		"at the hurt threshold the condition discount is already gone")
	check(WorldThreat.power_scale(WorldThreat.HURT_AT - 0.01) < WorldThreat.SCALE_MAX,
		"just under it, the condition discount has started")
	# monotone through real parties too, not just the bare curve
	var prev_p := -1.0
	for i in range(0, 11):
		var s: float = float(WorldThreat.assess(_hurt(_party(), float(i) / 10.0))["power_scale"])
		check(s >= prev_p, "a healthier party never asks for an easier fight (%.3f -> %.3f)" % [prev_p, s])
		prev_p = s

# This can only ever make the world kinder — there is no input that hands the
# wilderness a bigger budget than the baseline.
func test_never_scales_up() -> void:
	for i in range(0, 31):
		var s := WorldThreat.power_scale(float(i) / 20.0)   # 0.0 .. 1.5, deliberately past full
		check(s <= 1.0, "scale never exceeds 1.0 (frac %.2f -> %.3f)" % [float(i) / 20.0, s])
		check(s >= WorldThreat.SCALE_FLOOR, "scale never drops under the floor (frac %.2f -> %.3f)" % [float(i) / 20.0, s])

# Losing someone must not read as "hurt": Scaler already prices the roster
# against the survivors, so counting a corpse (or a benched reserve) here would
# discount the same loss twice.
func test_short_handed_is_not_hurt() -> void:
	var p := _party()
	var fallen = p.get_member(p.active[0])
	fallen.dead = true
	fallen.hp_current = 0
	var t := WorldThreat.assess(p)
	check(float(t["hp_frac"]) == 1.0, "a dead member does not drag the pooled fraction (%.3f)" % float(t["hp_frac"]))
	check(float(t["power_scale"]) == WorldThreat.SCALE_MAX, "so two healthy survivors still read as unhurt")
	check(int(t["counted"]) == 2, "and the count says who was actually read")

	var p2 := _party()
	var reserve = Presets.party()[0]
	reserve.id = "reserve"
	p2.add_member(reserve)
	p2.bench("reserve")
	reserve.hp_current = 1
	check(float(WorldThreat.assess(p2)["hp_frac"]) == 1.0, "a benched member's wounds are not the marching party's")

	# The degenerate end: nobody readable at all is not a discount.
	var empty := Party.new()
	check(float(WorldThreat.assess(empty)["power_scale"]) == WorldThreat.SCALE_MAX,
		"an empty party reads as unhurt rather than as dying")
	check(int(WorldThreat.assess(empty)["counted"]) == 0, "and reports that it read nobody")

# Every slot spent, the way a party walks out of a lair.
func _drained(p: Party) -> Party:
	for id in p.active:
		var ch = p.get_member(id)
		ch.slots_used = Adapter._full_slots(ch.sheet())
		ch.dirty()
	return p

# Wounds thin a fight; spent slots do not (2026-09-24). Power.estimate reads the
# slots left, so without slot_hold() a drained party bought itself a smaller
# road fight — asked here through real rosters, against the same party fresh.
func test_spent_slots_do_not_shrink_the_fight() -> void:
	var fresh := WorldThreat.assess(_party())
	check(float(fresh["slot_hold"]) == 1.0, "nothing spent: the hold is exactly 1.0 (got %.6f)" % float(fresh["slot_hold"]))
	var dp := _drained(_party())
	var drained := WorldThreat.assess(dp)
	check(float(drained["slot_hold"]) > 1.0, "every slot spent: the hold prices them back (got %.3f)" % float(drained["slot_hold"]))
	check(float(drained["hp_frac"]) == 1.0, "spending slots is not a wound")
	var chars := Presets.party()
	var dchars: Array = dp.party_characters()
	var same := 0
	var shrank := 0
	for s in range(1, 11):
		var want := _spec_power(Scaler.roster_for(chars, fresh["difficulty"], {}, "", s, fresh["power_scale"]))
		var got := _spec_power(Scaler.roster_for(dchars, drained["difficulty"], {}, "", s, drained["power_scale"]))
		var unheld := _spec_power(Scaler.roster_for(dchars, drained["difficulty"], {}, "", s,
			WorldThreat.power_scale(float(drained["hp_frac"]))))
		if is_equal_approx(got, want):
			same += 1
		if unheld < want:
			shrank += 1
	check(same == 10, "a drained party meets the fight it would have met fresh (%d of 10 seeds)" % same)
	check(shrank >= 5, "...where without the hold it met a smaller one (%d of 10 seeds)" % shrank)
	# Wounds still count: a drained AND hurt party gets the hurt discount, and
	# only that one.
	var both := WorldThreat.assess(_hurt(_drained(_party()), 0.3))
	check(is_equal_approx(float(both["power_scale"]),
		WorldThreat.power_scale(float(both["hp_frac"])) * float(both["slot_hold"])),
		"a drained, hurt party is thinned by its wounds alone")
	check(float(both["power_scale"]) < float(drained["power_scale"]), "...and that is still a smaller fight than the unhurt one")

# The owner's call on the design audit §3.2: pressing on hurt carries a real
# risk. Above half HP the road does not thin a fight for wounds at all (a
# half-HP company meets the fresh company's roster, body for body), and below it
# the curve bottoms out near three quarters of the flat discount, not a third.
# tests/sweep_wounds.gd measured what that costs: 99.0 / 93.0 / 86.5 / 74.5%
# at 100 / 70 / 50 / 30% HP, level-3 presets (core/world_threat.gd's header).
func test_pressing_on_hurt_costs() -> void:
	check(WorldThreat.HURT_AT <= 0.5, "the condition discount waits for half HP (HURT_AT %.2f)" % WorldThreat.HURT_AT)
	check(WorldThreat.SCALE_FLOOR >= 0.7, "and never thins a fight below 0.7 (floor %.3f)" % WorldThreat.SCALE_FLOOR)
	var chars := Presets.party()
	var fresh := WorldThreat.assess(_party())
	var half := WorldThreat.assess(_hurt(_party(), 0.5))
	check(is_equal_approx(float(half["power_scale"]), float(fresh["power_scale"])),
		"a company at half HP is asked for the fresh company's fight (%.3f vs %.3f)" % [
			float(half["power_scale"]), float(fresh["power_scale"])])
	for seed_v in range(1, 11):
		var a := Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", seed_v, float(fresh["power_scale"]))
		var b := Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", seed_v, float(half["power_scale"]))
		check(str(a["monsters"]) == str(b["monsters"]), "seed %d: the same bands, body for body" % seed_v)
	var low := WorldThreat.assess(_hurt(_party(), 0.3))
	check(float(low["power_scale"]) < float(fresh["power_scale"]) and float(low["power_scale"]) > 0.75,
		"at 30%% HP the fight is thinned, but only a little (%.3f)" % float(low["power_scale"]))

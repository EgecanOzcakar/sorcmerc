# T9x: foraging (core/world_forage.gd) — an ambient Survival-or-Nature check,
# same "best of the party rolls once" shape as every other overworld check
# this round. world.gd's own cadence gating (_check_forage) isn't exercised
# here — that's a thin wrapper over this module's pure math.
#   godot --headless --path . -s tests/test_world_forage.gd
extends SceneTree

const WorldForage = preload("res://core/world_forage.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")

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

func _init() -> void:
	check(WorldForage.check(Party.new()).is_empty(), "an empty roster has nobody to forage")

	var party := _party()
	var saw_ok := false
	var saw_fail := false
	for seed_v in range(40):
		var roll: Dictionary = WorldForage.check(party, RNG.new(seed_v + 1))
		check(not roll.is_empty(), "a real party always gets a roll")
		check(roll["dc"] == WorldForage.DC, "uses the documented DC")
		if roll["ok"]:
			saw_ok = true
			check(roll["gold"] >= WorldForage.GOLD_MIN and roll["gold"] <= WorldForage.GOLD_MAX,
				"a success pays gold in the documented range")
		else:
			saw_fail = true
			check(roll["gold"] == 0, "a failure pays nothing")
	check(saw_ok and saw_fail, "both outcomes reachable across seeds (got ok=%s fail=%s)" % [saw_ok, saw_fail])

	print("test_world_forage: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

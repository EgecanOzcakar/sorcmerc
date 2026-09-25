# MEASUREMENT (2026-09-25) — what a road fight costs a party that is already
# hurt, and what core/world_threat.gd's wounds curve does about it. Not a test,
# and not part of tools/run_tests.sh (the runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_wounds.gd
#   PART=grid HPS=1.0,0.5 SCALES=1.0,0.6 SEEDS=100 godot ... -s tests/sweep_wounds.gd
#   PART=curve LEVEL=8 godot ... -s tests/sweep_wounds.gd
#
# world_threat.gd's header carried a grid taken 2026-09-13 with a throwaway
# harness that was never committed, under TIER easy 0.96 / CURVE 0.90, before
# the swing fix, the cover fix, RAW death saves and the autopilot that spends
# its whole turn. This is that harness, committed, so the grid can be re-run.
#
# Every hero starts the fight at `hp` of max (hp_current, the way a party walks
# off a lair), every slot back unless SLOTS=spent. The roster is
# Scaler.roster_for(party, "easy", ..., scale), the road's own call: easy is
# WorldThreat.BASELINE, and `scale` is the power_scale world.gd passes (the
# country's scale is 1.0 inside the party's band, the common case, and left out).
# One roster per seed, each its own faction, fight seed pinned — the shape of
# tests/test_scaler.gd's _sweep.
#
#   PART=grid   win% by hp (rows) and a fixed budget scale (columns): what the
#               curve has to choose from.
#   PART=curve  win% by hp at the scale the shipped curve picks
#               (WorldThreat.power_scale), with every slot back and with every
#               slot spent (WorldThreat.assess, slot_hold and all): what a
#               player pressing on actually meets.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const WorldThreat = preload("res://core/world_threat.gd")

func _init() -> void:
	var seeds := _env_i("SEEDS", 200)
	var level := _env_i("LEVEL", 3)
	var part := OS.get_environment("PART") if OS.get_environment("PART") != "" else "curve"
	var hps := _env_f("HPS", [1.0, 0.7, 0.5, 0.3])
	if part == "grid":
		var scales := _env_f("SCALES", [1.0, 0.9, 0.75, 0.6, 0.5, 0.4])
		print("level-%d presets, %s, %d seeds a cell, fight seed pinned, every slot back" % [level, WorldThreat.BASELINE, seeds])
		var head := "  hp%  "
		for sc in scales:
			head += "   x%.2f" % sc
		print(head)
		for hp in hps:
			var line := "  %3d%% " % int(round(hp * 100))
			var p := _party(level, hp, false)
			for sc in scales:
				var r := _sweep(p.party_characters(), float(sc), seeds)
				line += "  %5.1f%%" % r["rate"]
			print(line)
	else:
		print("level-%d presets, the shipped curve (HURT_AT %.2f, floor %.2f, x%.2f fresh), %d seeds a cell" % [
			level, WorldThreat.HURT_AT, WorldThreat.SCALE_FLOOR, WorldThreat.SCALE_MAX, seeds])
		print("  hp%    scale  foes   win%  rounds   | slots spent: scale  foes   win%")
		for hp in hps:
			var full := _party(level, hp, false)
			var t := WorldThreat.assess(full)
			var a := _sweep(full.party_characters(), float(t["power_scale"]), seeds)
			var spent := _party(level, hp, true)
			var t2 := WorldThreat.assess(spent)
			var b := _sweep(spent.party_characters(), float(t2["power_scale"]), seeds)
			print("  %3d%%   x%.3f  %4.1f  %5.1f%%  %5.1f   |              x%.3f  %4.1f  %5.1f%%" % [
				int(round(hp * 100)), float(t["power_scale"]), a["foes"], a["rate"], a["rounds"],
				float(t2["power_scale"]), b["foes"], b["rate"]])
	quit(0)

func _env_i(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.get_environment(k) != "" else d

func _env_f(k: String, d: Array) -> Array:
	if OS.get_environment(k) == "":
		return d
	return Array(OS.get_environment(k).split(",")).map(func(x): return float(x))

# The preset party at `level`, every member at `hp` of max, every slot spent
# when `spent` (the walk home from a lair) or every one back.
func _party(level: int, hp: float, spent: bool) -> Party:
	var p := Party.new()
	for ch in Presets.party_at(level):
		p.add_member(ch)
	for id in p.active:
		var ch = p.get_member(id)
		if spent:
			ch.slots_used = Adapter._full_slots(ch.sheet())
		if hp < 1.0:
			ch.hp_current = maxi(1, int(round(float(p.summary(id)["max_hp"]) * hp)))
		ch.dirty()
	return p

func _sweep(chars: Array, scale: float, seeds: int) -> Dictionary:
	var wins := 0
	var foes := 0
	var rounds := 0
	for s in range(1, seeds + 1):
		var spec: Dictionary = Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", s, scale)
		for e in spec["monsters"]:
			foes += int(e["count"])
		var sp: Dictionary = spec.duplicate(true)
		sp["seed"] = s
		var team: Array = []
		for i in chars.size():
			team.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(sp, team)
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		rounds += cb.round_num
		if cb.outcome() == "Victory":
			wins += 1
	return {"rate": 100.0 * wins / seeds, "foes": float(foes) / seeds, "rounds": float(rounds) / seeds}

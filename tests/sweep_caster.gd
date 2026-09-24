# MEASUREMENT (2026-09-24) — what a caster elite does to a cult warband's fight,
# priced by core/rules/power.gd and bought out of the same budget. Not a test,
# and not part of tools/run_tests.sh (the runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_caster.gd
#   SEEDS=100 LEVELS=3,8 godot --headless --path . -s tests/sweep_caster.gd
#
# Every seed is pinned to the cultist faction (Scaler.pin_faction) — the only
# faction with a caster block — and fought twice on the same seed, the roll
# forced off and forced on (Scaler.caster_chance_override), preset party at the
# level, both sides autoplayed, fight seed pinned: the shape of
# tests/test_scaler.gd's _sweep. The question is whether power.gd prices a
# caster honestly: if it does, the forced column wins about what the off column
# does, on fewer bodies, because the budget the caster costs is budget the
# escort did not get.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var levels: Array = [3, 5, 8]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("cultist rosters, preset party, %d seeds a cell, fight seed pinned" % seeds)
	print("  level  tier      off: foes  win%  rounds    forced: caster  foes  win%  rounds  slots")
	for L in levels:
		for tier in ["easy", "normal", "hard"]:
			Scaler.caster_chance_override = 0.0
			var a := _sweep(L, tier, seeds)
			Scaler.caster_chance_override = 1.0
			var b := _sweep(L, tier, seeds)
			print("  %5d  %-6s    %4.1f  %5.1f%%  %5.1f     %5.0f%%  %4.1f  %5.1f%%  %5.1f  %5.1f" % [L, tier,
				a["foes"], a["rate"], a["rounds"], b["casters"], b["foes"], b["rate"], b["rounds"], b["slots"]])
	Scaler.caster_chance_override = -1.0
	quit(0)

func _sweep(L: int, tier: String, seeds: int) -> Dictionary:
	var wins := 0
	var foes := 0
	var rounds := 0
	var with_caster := 0
	var spent := 0
	for s in range(1, seeds + 1):
		var seed_v: int = Scaler.pin_faction(s * 7919, "cultist")
		var chars: Array = Presets.party_at(L)
		var spec: Dictionary = Scaler.roster_for(chars, tier, {}, "", seed_v)
		spec["seed"] = s
		for e in spec["monsters"]:
			foes += int(e["count"])
		var party: Array = []
		for i in chars.size():
			party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(spec, party)
		var casters: Array = cb.combatants.filter(func(c): return c.caster)
		var full: Array = casters.map(func(c): return Array(c.slots).reduce(func(x, y): return x + y, 0))
		if not casters.is_empty():
			with_caster += 1
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		for i in casters.size():
			spent += int(full[i]) - Array(casters[i].slots).reduce(func(x, y): return x + y, 0)
		rounds += cb.round_num
		if cb.outcome() == "Victory":
			wins += 1
	return {"rate": 100.0 * wins / seeds, "foes": float(foes) / seeds, "rounds": float(rounds) / seeds,
		"casters": 100.0 * with_caster / seeds, "slots": float(spent) / maxi(1, with_caster)}

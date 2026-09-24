# MEASUREMENT (2026-09-24) — what a road fight costs a party that has spent its
# spell slots, before and after core/world_threat.gd's slot_hold(). Not a test,
# and not part of tools/run_tests.sh (the runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_spent_slots.gd
#   SEEDS=100 godot --headless --path . -s tests/sweep_spent_slots.gd
#
# core/rules/power.gd reads the slots a party has LEFT and never its current
# HP, so before slot_hold() a party that had cast everything was priced as a
# weaker party and sent a smaller road fight. The owner's call (2026-09-24):
# wounds thin a fight, spent slots do not. This sweeps the level-3 preset party
# through the wilderness baseline (easy, times WorldThreat's condition curve)
# at four conditions, and prices each one both ways:
#   unheld  WorldThreat.power_scale(hp) alone — exactly what master passed
#   held    WorldThreat.assess()["power_scale"] — the curve times slot_hold()
# A party with every slot left reads the same both ways (the hold is 1.0), so
# those rows are the control. One roster per seed, each its own faction, fight
# seed pinned — the same shape as tests/test_scaler.gd's _sweep.
#
# MEASURED 2026-09-24, 200 seeds a cell, SORCMERC_FAST=1:
#   slots  hp     hold    unheld: foes  win%     held: foes  win%
#    100%  100%  x1.000      4.0   99.5%           4.0   99.5%
#      0%  100%  x1.429      3.3  100.0%           4.0   94.5%
#    100%   50%  x1.000      3.5   95.0%           3.5   95.0%
#      0%   50%  x1.429      3.2   99.5%           3.5   90.0%
# Unheld, a party with nothing left to cast won MORE often than the same party
# fresh (100% against 99.5%): the budget the slots handed back outweighed the
# spells themselves. Held, the drained party meets the fresh party's roster
# body for body, and what spending the slots costs is visible at last.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const WorldThreat = preload("res://core/world_threat.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	print("level-3 presets, wilderness baseline (%s), %d seeds a cell, fight seed pinned" % [WorldThreat.BASELINE, seeds])
	print("  slots  hp     hold    unheld: foes  win%     held: foes  win%")
	for cond in [[1.0, 1.0], [0.0, 1.0], [1.0, 0.5], [0.0, 0.5]]:
		var p := _party(cond[0], cond[1])
		var t := WorldThreat.assess(p)
		var chars: Array = p.party_characters()
		var a := _sweep(chars, WorldThreat.power_scale(float(t["hp_frac"])), seeds)
		var b := _sweep(chars, float(t["power_scale"]), seeds)
		print("  %4d%%  %3d%%  x%.3f     %4.1f  %5.1f%%          %4.1f  %5.1f%%" % [
			int(cond[0] * 100), int(cond[1] * 100), float(t["slot_hold"]),
			a["foes"], a["rate"], b["foes"], b["rate"]])
	quit(0)

# The preset party with `slots` of its spell slots left (all or none) and every
# member at `hp` of max.
func _party(slots: float, hp: float) -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	for id in p.active:
		var ch = p.get_member(id)
		if slots < 1.0:
			ch.slots_used = Adapter._full_slots(ch.sheet())
		if hp < 1.0:
			ch.hp_current = maxi(1, int(round(float(p.summary(id)["max_hp"]) * hp)))
		ch.dirty()
	return p

func _sweep(chars: Array, scale: float, seeds: int) -> Dictionary:
	var wins := 0
	var foes := 0
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
		if cb.outcome() == "Victory":
			wins += 1
	return {"rate": 100.0 * wins / seeds, "foes": float(foes) / seeds}

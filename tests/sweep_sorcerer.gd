# MEASUREMENT (2026-09-24) — what Innate Sorcery and Font of Magic are worth
# to a party, taken apart from everything else a sorcerer is. Not a test, and
# not part of tools/run_tests.sh (the runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_sorcerer.gd
#   SEEDS=100 LEVELS=5 godot --headless --path . -s tests/sweep_sorcerer.gd
#
# The preset trio has no sorcerer (fighter, rogue, cleric), so tests/test_scaler
# and tests/sweep_tier.gd cannot see this pass at all. Here the cleric's seat is
# a sorcerer built the way tests/sweep_built.gd builds a hero (every choice
# made, ability increases into CHA, the rest the first legal options), beside
# the preset fighter and rogue at the same level. Each seed is fought twice,
# the same roster both times:
#   without  the sorcerer's Innate Sorcery and Font of Magic buttons stripped —
#            exactly what master fields, where both are catalogue text
#   with     the buttons as shipped; the autopilot presses Innate Sorcery as
#            its self-buff and makes a slot from points once it has none
# core/rules/power.gd prices neither (a self_buff with no bonus_damage, a kind
# it has no arm for), so the budget is the same in both columns and the gap is
# the features' whole unpriced worth. Easy tier, fight seed pinned.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const Built = preload("res://tests/sweep_built.gd")

const NEW := ["sorcerer-innate-sorcery", "sorcerer-font-of-magic"]

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var levels: Array = [3, 10]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("preset fighter + rogue + a built sorcerer, easy, %d seeds a cell, fight seed pinned" % seeds)
	print("  level   without: win%  rounds     with: win%  rounds")
	for L in levels:
		var a := _sweep(L, seeds, false)
		var b := _sweep(L, seeds, true)
		print("  %5d        %5.1f%%   %5.1f          %5.1f%%   %5.1f" % [L, a["rate"], a["rounds"], b["rate"], b["rounds"]])
	quit(0)

func _sorcerer(L: int) -> Character:
	var ch := Character.new()
	ch.id = "sorc"
	ch.cname = "Sorc"
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 15}
	for i in L:
		ch.add_level("sorcerer", -1)
	Built.build(ch)
	return ch

func _sweep(L: int, seeds: int, with_new: bool) -> Dictionary:
	var wins := 0
	var rounds := 0
	for s in range(1, seeds + 1):
		var trio: Array = Presets.party_at(L)
		var chars: Array = [trio[0], trio[1], _sorcerer(L)]
		var spec: Dictionary = Scaler.roster_for(chars, "easy", {}, "", s, 1.0)
		spec["seed"] = s
		var party: Array = []
		for i in chars.size():
			var c = Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i])
			if not with_new:
				c.verbs = c.verbs.filter(func(v): return not NEW.any(func(f): return String(v["id"]).begins_with(f)))
			party.append(c)
		var cb = Encounter.build(spec, party)
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
	return {"rate": 100.0 * wins / seeds, "rounds": float(rounds) / seeds}

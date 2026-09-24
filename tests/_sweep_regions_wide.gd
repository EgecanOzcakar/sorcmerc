# MEASUREMENT — the win-rate table in core/regions.gd's header, re-runnable.
# Not a test, and not part of tools/run_tests.sh (the runner globs test_* and
# drive_*). The table was first measured 2026-09-13 with no script committed;
# this is that method, written down so the claim can be re-run rather than
# re-argued:
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_regions.gd
#   SEEDS=40 godot --headless --path . -s tests/sweep_regions.gd
#
# Per cell: the preset trio at the party's level (Presets.party_at), a roster
# from Scaler.roster_for at wilderness tier `easy` (what core/world_threat.gd
# sends into open country) with the band's power_scale for content at the
# content's level — Scaler.held_at(score(C), score(P)), which is what
# Regions.power_scale computes when the party is the ruler — and the fight seed pinned (spec["seed"] = s). Autoplayed both
# sides, the way tests/sweep_tier.gd does.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")

# [party level, content level] — the six rows of the published table
const CELLS := [[3, 3], [5, 5], [6, 6], [8, 8], [10, 10], [12, 12], [15, 15], [6, 3], [10, 3], [3, 6], [3, 10]]

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 80
	print("party  content   scale   win   (%d seeds a cell, tier easy)" % seeds)
	for cell in CELLS:
		var p: int = cell[0]
		var c: int = cell[1]
		var scale: float = 1.0 if p == c else Scaler.held_at(Regions.ref_score(c), Regions.ref_score(p))
		var wins := 0
		for s in range(1, seeds + 1):
			var chars: Array = Presets.party_at(p)
			var spec: Dictionary = Scaler.roster_for(chars, "easy", {}, "", s, scale)
			spec["seed"] = s
			var party: Array = []
			for i in chars.size():
				party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
			var cb = Encounter.build(spec, party)
			var g := 0
			while not cb.is_over() and g < 5000:
				var a = cb.current()
				cb.begin_turn()
				AI.take_turn(cb, a)
				cb.end_turn()
				g += 1
			if cb.outcome() == "Victory":
				wins += 1
		print("lvl %-3d lvl %-3d  x%.2f  %5.1f%%" % [p, c, scale, 100.0 * wins / seeds])
	quit(0)

# MEASUREMENT (2026-09-25) — what core/encounter.gd's per-mult stat bumps
# (AC_PER_MULT 3, ATK_PER_MULT 4, DMG_PER_MULT 4) do to a fight against a foe
# pumped high: a boss lead, the one place the generator reaches mult 2-3 (up to
# +6 AC and +8 to hit at BOSS_MULT_MAX). The design audit §7.3 found them with
# no named sweep. Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_mult.gd
#   SEEDS=40 LEVEL=8 godot ... -s tests/sweep_mult.gd
#
# Every boss in core/campaign.gd's BOSS_POOL that has a lead, built by
# Scaler.boss_for for the preset trio exactly as the game builds it, fight seed
# pinned. For each: the lead's mean mult, what that mult bought on the lead
# (AC, to hit and HP over the plain statblock), the win rate and fight length.
# The bumps are consts, so a variant is measured by running this file in a copy
# of the tree with them edited. core/rules/power.gd prices the SCALED
# combatant, so a smaller bump is answered by a bigger mult (more HP) at the
# same budget: the question is not "how strong is the boss" — the budget fixes
# that — but whether the bumps spend it on something the ruler prices right.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Campaign = preload("res://core/campaign.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3
	var chars: Array = Presets.party_at(level)
	print("AC/ATK/DMG_PER_MULT %d/%d/%d, level-%d presets, %d seeds a boss, fight seed pinned" % [
		Encounter.AC_PER_MULT, Encounter.ATK_PER_MULT, Encounter.DMG_PER_MULT, level, seeds])
	print("  boss               mult   +AC  +hit   xHP   win%  rounds")
	var wins := 0
	var fights := 0
	for boss in Campaign.BOSS_POOL:
		if not boss.has("lead"):
			continue
		var w := 0
		var rounds := 0
		var mult := 0.0
		for s in range(1, seeds + 1):
			var sp: Dictionary = Scaler.boss_for(chars, boss, s)
			mult += float(sp["monsters"][0]["mult"])
			sp["seed"] = s
			sp["theme"] = boss["theme"]
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
				w += 1
		var m := mult / seeds
		var plain = Encounter.spawn(String(boss["lead"]), 1.0, "foe", Vector2i.ZERO, 0)
		var pumped = Encounter.spawn(String(boss["lead"]), m, "foe", Vector2i.ZERO, 0)
		print("  %-17s  x%.2f  %+3d   %+3d   %.2f  %5.1f%%  %5.1f" % [boss["id"], m, pumped.ac - plain.ac,
			pumped.atk_bonus - plain.atk_bonus, float(pumped.max_hp) / plain.max_hp, 100.0 * w / seeds,
			float(rounds) / seeds])
		wins += w
		fights += seeds
	print("  pool overall %.1f%%" % (100.0 * wins / fights))
	quit(0)

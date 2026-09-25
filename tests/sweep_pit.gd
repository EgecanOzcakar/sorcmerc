# MEASUREMENT (2026-09-25, #236) — what one hero against one pit champion
# comes to, by the ratio the champion is priced at (Downtime.pit_champion: the
# champion worth `ratio` of the ruler's average hero at the level, on
# core/rules/power.gd's scale). Not a test, and not part of tools/run_tests.sh (the
# runner globs test_* and drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_pit.gd
#   SEEDS=100 LEVELS=3,8 RATIOS=0.6,0.8,1.0 godot --headless --path . -s tests/sweep_pit.gd
#
# Each preset (fighter, rogue, cleric; core/presets.gd at the level) stands
# alone against the champion Downtime.PIT_POOL gives it at the ratio, on the
# pit's own board (Downtime.PIT_THEME), fight seed pinned, both sides on the
# autopilot: the shape of tests/test_scaler.gd's _sweep with a party of one.
# The pooled column is the three classes together — a pit bout is whichever
# hero the player puts up, and the player picks. Downtime.PIT_RATIO's header
# quotes the grid this prints.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const Downtime = preload("res://core/downtime.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 40
	var levels: Array = [1, 3, 5, 8, 12]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	var ratios: Array = [0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2]
	if OS.get_environment("RATIOS") != "":
		ratios = Array(OS.get_environment("RATIOS").split(",")).map(func(x): return float(x))
	print("one hero against one pit champion, %d seeds a cell, fight seed pinned" % seeds)
	var pooled_by_ratio := {}
	for L in levels:
		var heroes: Array = Presets.party_at(L)
		if OS.get_environment("ONLY") != "":   # ONLY=fighter: one class's column
			heroes = heroes.filter(func(h): return h.class_id() == OS.get_environment("ONLY"))
		print("  level %d" % L)
		print("    ratio   %s   pooled   rounds" % "   ".join(heroes.map(func(h): return "%-22s" % h.class_id())))
		for r in ratios:
			var cells: Array = []
			var wins := 0
			var rounds := 0
			for h in heroes:
				var champ: Dictionary = Downtime.pit_champion(L, r)
				var w := 0
				for s in range(1, seeds + 1):
					var res := _bout(h, champ, s)
					w += 1 if res[0] else 0
					rounds += int(res[1])
				wins += w
				cells.append("%5.1f%% %-10s x%.2f" % [100.0 * w / seeds, String(champ["id"]).left(10), float(champ["mult"])])
			var pooled := 100.0 * wins / (seeds * heroes.size())
			pooled_by_ratio[r] = pooled_by_ratio.get(r, []) + [pooled]
			print("    %4.2f   %s   %5.1f%%  %5.1f" % [r, "   ".join(cells), pooled, float(rounds) / (seeds * heroes.size())])
	print("  every level, pooled:")
	for r in ratios:
		var a: Array = pooled_by_ratio[r]
		var t := 0.0
		for x in a:
			t += float(x)
		print("    %4.2f   %5.1f%%" % [r, t / a.size()])
	quit(0)

func _bout(h, champ: Dictionary, s: int) -> Array:
	var sp := {"monsters": [champ], "theme": Downtime.PIT_THEME, "seed": s}
	var board: Dictionary = Encounter.board_for(Downtime.PIT_THEME, s)
	var starts: Array = Encounter.starts_for(sp, board, s)
	var cb = Encounter.build(sp, [Adapter.to_combatant(h, "party", starts[0])], board)
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return [cb.outcome() == "Victory", cb.round_num]

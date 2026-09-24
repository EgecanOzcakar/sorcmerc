# MEASUREMENT — the preset trio as a ruler versus the same trio built the way a
# player builds it. Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_built.gd
#   SEEDS=30 LEVELS=10 godot --headless --path . -s tests/sweep_built.gd
#
# Presets.party_at(L) leaves every choice above level 3 unmade (its own
# ponytail: it is a ruler, not a party), so a sweep on it never sees the kit a
# real level-10 party carries. "built" makes every pending choice (ability
# increases into the class's main ability, the rest the first legal options)
# and fills a prepared caster's list, highest level first. Same harness as
# tests/sweep_tier.gd: easy tier, fight seed pinned, both sides autoplayed.
# Found the 2026-09-24 level-10 gap: a built level-10 party won 6.7% at easy
# before Power.estimate stopped stacking a spell list.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Power = preload("res://core/rules/power.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Prepare = preload("res://scenes/party/prepare.gd")
const PRIMARY := {"fighter": "str", "rogue": "dex", "cleric": "wis"}

static func build(ch) -> void:
	for _step in 60:
		var pend: Array = ch.sheet().pending
		if pend.is_empty():
			break
		var p: Dictionary = pend[0]
		var picks: Array = []
		if p["type"] == "asi":
			for i in Creator.pick_count(p):
				picks.append(PRIMARY.get(ch.class_id(), "con"))
		else:
			var opts := Creator.options_for(p, ch.sheet())
			var i := 0
			while picks.size() < Creator.pick_count(p) and i < opts.size() * 3 and not opts.is_empty():
				picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
				i += 1
		ch.decide(p["key"], Creator.decision_for(p, picks))
		ch.dirty()
	if Prepare.prepares(ch):
		var pool: Array = Prepare.pool(ch).duplicate()
		pool.sort_custom(func(a, b): return int(Catalog.spell(a).get("level", 0)) > int(Catalog.spell(b).get("level", 0)))
		for sid in pool:
			if Prepare.chosen(ch).size() >= Prepare.limit(ch):
				break
			Prepare.toggle(ch, sid)
		ch.dirty()

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 60
	var levels: Array = [3, 10]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	for L in levels:
		for built in [false, true]:
			var wins := 0; var foes := 0; var rounds := 0; var score := 0.0; var locks := 0
			for s in range(1, seeds + 1):
				var chars: Array = Presets.party_at(L)
				if built:
					for ch in chars:
						build(ch)
				var spec: Dictionary = Scaler.roster_for(chars, "easy", {}, "", s, 1.0)
				spec["seed"] = s
				for e in spec["monsters"]:
					foes += int(e["count"])
				var party: Array = []
				for i in chars.size():
					party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
				if s == 1:
					score = Power.team_score(party)
				var cb = Encounter.build(spec, party)
				var g := 0
				while not cb.is_over() and g < 5000:
					var a = cb.current()
					cb.begin_turn()
					AI.take_turn(cb, a)
					cb.end_turn()
					g += 1
				rounds += cb.round_num
				for c in cb.combatants:
					if c.team == "party" and c.has("concentrating"):
						locks += 1
				if cb.outcome() == "Victory":
					wins += 1
			print("L%-2d %-5s score %6.1f  foes %.1f  rounds %4.1f  win %5.1f%%  (holding a lock at the end: %d/%d fights)" % [
				L, "built" if built else "raw", score, float(foes) / seeds, float(rounds) / seeds,
				100.0 * wins / seeds, locks, seeds])
	quit()

# MEASUREMENT (2026-09-25) — three things a hero can carry into a fight that
# core/rules/power.gd does not price (the design audit §7.4): weapon mastery,
# a potion drunk on the road and still running, and a bond between two
# companions (core/party_opinion.gd: +1 AC shoulder to shoulder, a rally when a
# partner drops). The owner's call was to price each in power.gd IF a sweep
# shows it above noise. Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_unpriced.gd
#   SEEDS=100 LEVEL=8 DIFF=normal godot ... -s tests/sweep_unpriced.gd
#
# The preset trio (Vera: longsword, Sap; Pike: shortbow, Vex; Ilsa), at
# LEVEL and DIFF, one roster per seed, fight seed pinned, the fight told whose
# company it is (cb.party, as the world screen does, so the opinion hooks
# run). Every variant fights the SAME rosters: none of the three is priced, so
# the budget does not move and each row's gap from the baseline is that
# thing's whole unpriced worth:
#   baseline        the trio as shipped: its masteries, no potion, the
#                   opinions its backgrounds start it on (nobody bonded)
#   no mastery      every hero's weapon mastery taken off
#   heroism x3      each hero fought under a Potion of Heroism drunk on the road
#                   (+2 to hit, +2 to saves; Potions.buff, the adapter's road door)
#   giant str Vera  the fighter under a Potion of Giant Strength (STR 21)
#   all bonded      every pair bonded (PartyOpinion.BONDED)
# Hard by default: at 81.5% it is the tier with the most room either way.
# ONLY=<prefix> runs the baseline and the rows it begins; PRICED=1 buys each
# row's roster for the company carrying it (see _fight).
#
# MEASURED 2026-09-25 (the build log, "The measured pass"), moves from the
# baseline, unpriced / priced:
#   level 3, 200 seeds (baseline 81.5%): no mastery -2.5; Heroism x3 +8.0 /
#     +3.5; Giant Strength +8.0 / +0.0; all bonded +8.0 / +5.5
#   level 8, 150 seeds (78.0%): Heroism +4.0 / +3.3; Giant Strength +4.0 /
#     +0.7;  300 seeds (75.7%): no mastery -4.3; all bonded +4.3 / +1.0
# The prices are core/rules/power.gd's road_buffs and core/regions.gd's
# fresh_score (SHOULDER_SHARE); mastery is left unpriced (power.gd's header).
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Potions = preload("res://core/potions.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")
const WorldThreat = preload("res://core/world_threat.gd")

const VARIANTS := ["baseline", "no mastery", "heroism x3", "giant str Vera", "all bonded"]

var _priced := false

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3
	var diff := OS.get_environment("DIFF") if OS.get_environment("DIFF") != "" else "hard"
	var only := OS.get_environment("ONLY")
	_priced = OS.get_environment("PRICED") == "1"
	print("level-%d presets, %s, %d seeds a row, fight seed pinned, %s" % [level, diff, seeds,
		"each row's roster bought for the company carrying it (PRICED)" if _priced else "the same rosters every row"])
	print("  %-16s  win%%    move  rounds  downs   foes" % "variant")
	var base := -1.0
	for v in VARIANTS:
		if only != "" and v != "baseline" and not String(v).begins_with(only):
			continue
		var wins := 0
		var rounds := 0
		var downs := 0
		var foes := 0
		for s in range(1, seeds + 1):
			var r := _fight(String(v), level, diff, s)
			foes += int(r["foes"])
			wins += 1 if r["won"] else 0
			rounds += int(r["rounds"])
			downs += int(r["downs"])
		var rate := 100.0 * wins / seeds
		if base < 0.0:
			base = rate
		print("  %-16s %5.1f%%  %+5.1f  %6.2f  %5.2f  %5.2f" % [v, rate, rate - base, float(rounds) / seeds,
			float(downs) / seeds, float(foes) / seeds])
	quit(0)

func _fight(variant: String, level: int, diff: String, s: int) -> Dictionary:
	var p := Party.new()
	for ch in Presets.party_at(level):
		p.add_member(ch)
	var chars: Array = p.party_characters()
	# Unpriced (the default): the roster is bought before any variant touches
	# the party, so every row meets the same bands — the thing's whole worth.
	# PRICED=1: the variant first, then the road's own purchase (WorldThreat's
	# slot_hold, which is where a bond is priced; potions and Quickened are in
	# the heroes' own readings) — what the game sends a company carrying it.
	var spec := {}
	if not _priced:
		spec = Scaler.roster_for(chars, diff, {}, "", s)
	match variant:
		"heroism x3":
			for ch in chars:
				ch.buffs["potion-of-heroism"] = {"status": Potions.buff("potion-of-heroism", RNG.new(s), ch.sheet())}
		"giant str Vera":
			chars[0].buffs["potion-of-giant-strength"] = {
				"status": Potions.buff("potion-of-giant-strength", RNG.new(s), chars[0].sheet())}
		"all bonded":
			var ids: Array = p.active.duplicate()
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					PartyOpinion.set_score(p, ids[i], ids[j], PartyOpinion.BONDED)
	if _priced:
		spec = Scaler.roster_for(chars, diff, {}, "", s, WorldThreat.slot_hold(p))
	spec["seed"] = s
	var team: Array = []
	for i in chars.size():
		var c = Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i])
		if variant == "no mastery":
			for a in c.attacks:
				a.erase("mastery")
		team.append(c)
	var cb = Encounter.build(spec, team)
	cb.party = p
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	var bodies := 0
	for e in spec["monsters"]:
		bodies += int(e["count"])
	return {"won": cb.outcome() == "Victory", "rounds": cb.round_num, "downs": cb.downed.size(), "foes": bodies}

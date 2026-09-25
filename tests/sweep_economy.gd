# ESTIMATE — the economy tables in the coin-and-xp pass (2026-09-25), re-runnable.
# Not a test, and not part of tools/run_tests.sh (the runner globs test_* and
# drive_*). Arithmetic on the numbers a fight is built and paid from, not a
# measurement of play: no fight is autoplayed, so nothing here says who wins.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_economy.gd
#   SEEDS=50 godot --headless --path . -s tests/sweep_economy.gd
#
# Three tables, each quoted in the file that owns the number:
#
#   1. Coin and loot per easy open-country fight, by level (Campaign.SELL_RATE).
#      The ruler trio at level L (Presets.party_at), SEEDS rosters from
#      Scaler.roster_for at tier "easy" (seed pinned), Loot.for_kills on each
#      roster's bodies with an RNG seeded off the roster's seed, list prices
#      summed. Coin is the roster's budget x Encounter.GOLD_PER_POWER, which
#      is what a fight's purse is before the purse multiplier.
#   2. Fights to the next level, before and after the late-level pace
#      (Leveling.LATE_LEVEL): Regions.fight_xp(L) split three ways against the
#      step, and the old step (100 x L) beside it.
#   3. What a quest pays in XP by kind and level (Quest.XP_FIGHTS), beside the
#      old purse rate for a middling 200 ◉ job.
extends SceneTree

const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Loot = preload("res://core/loot.gd")
const Campaign = preload("res://core/campaign.gd")
const Leveling = preload("res://core/leveling.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

const LEVELS := [1, 3, 6, 8, 10, 15, 19]

func _init() -> void:
	var seeds: int = int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	print("1. coin and loot per easy fight, %d rosters a row; SELL_RATE %.2f" % [seeds, Campaign.SELL_RATE])
	print("   level  coin  loot list  sold at 0.5   sold at SELL_RATE   raise (fights of coin)")
	for L in LEVELS:
		var party: Array = Presets.party_at(L)
		var coin: float = _budget(L) * Encounter.GOLD_PER_POWER
		var list := 0.0
		for s in range(1, seeds + 1):
			var r: Dictionary = Scaler.roster_for(party, "easy", {}, "", s)
			var kills: Array = []
			for m in r["monsters"]:
				for i in int(m.get("count", 1)):
					kills.append(String(m["id"]))
			for id in Loot.for_kills(kills, RNG.new(s * 7919 + 1)):
				list += Campaign.item_price(String(id))
		list /= seeds
		print("   %5d %5.0f %10.0f %6.0f (%.1fx) %10.0f (%.1fx) %12d (%.1f)" % [L, coin, list,
			list * 0.5, list * 0.5 / coin, list * Campaign.SELL_RATE, list * Campaign.SELL_RATE / coin,
			Party.REVIVE_PER_LEVEL * L, Party.REVIVE_PER_LEVEL * L / coin])

	print("\n2. fights to the next level (easy fight XP split three ways)")
	print("   level  fight XP  old step  old fights  step  fights")
	var old_total := 0.0
	var new_total := 0.0
	for L in range(1, 20):
		var per: float = Regions.fight_xp(L) / 3.0
		var old_step: int = Leveling.XP_PER_LEVEL * L
		var step: int = Leveling.xp_for_level(L + 1) - Leveling.xp_for_level(L)
		if L >= 10:
			old_total += old_step / per
			new_total += step / per
		print("   %5d %9d %9d %11.1f %5d %7.1f" % [L, Regions.fight_xp(L), old_step, old_step / per, step, step / per])
	print("   levels 10-20: %.0f fights before, %.0f after" % [old_total, new_total])

	print("\n3. quest XP by kind (fights x Regions.fight_xp), against a 200 ◉ job's old 400")
	var head := "   kind              "
	for L in LEVELS:
		head += "%7s" % ("L%d" % L)
	print(head)
	for kind in Quest.XP_FIGHTS:
		var row := "   %-18s" % kind
		for L in LEVELS:
			row += "%7d" % Quest.xp_for(String(kind), Regions.fight_xp(L))
		print(row)
	quit(0)

static func _budget(level: int) -> float:
	return Scaler.REF_SCORE * pow(Regions.ref_score(level) / Scaler.REF_SCORE, Scaler.CURVE) \
		* float(Scaler.TIER["easy"])

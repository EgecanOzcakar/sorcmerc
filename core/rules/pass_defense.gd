# Hit points, speed, armor class. Ported from dnd-maintainer src/lib/resolver/combat.ts.
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")

# L1 = max die + CON; L2+ = the roll (or die/2+1) + CON; then hp-bonus x level.
# hp_rolls is indexed by level row; index 0 (level 1) is ignored. -1 = average.
static func hp(bundles: Array, hp_rolls: Array, con_mod: int, level: int) -> int:
	if level == 0:
		return 0
	var dice := Bundles.of_type(bundles, "hit-die")
	if dice.is_empty():
		return 0
	# First hit die wins — multiclass per-class HP is out for v1 (spec §5).
	var die: int = int(dice[0]["grant"]["die"])
	var total: int = die + con_mod
	for i in range(1, level):
		var roll: int = int(hp_rolls[i]) if i < hp_rolls.size() else -1
		total += (roll if roll > 0 else die / 2 + 1) + con_mod
	for tg in Bundles.of_type(bundles, "hp-bonus"):
		total += int(tg["grant"]["perLevel"]) * level
	return maxi(1, total)

# {mode: ft}. Highest per mode wins; walk-equivalent resolves in a second pass.
static func speed(bundles: Array) -> Dictionary:
	var best := {}
	var equiv := {}
	for tg in Bundles.of_type(bundles, "speed"):
		var g: Dictionary = tg["grant"]
		if g["value"] is String:
			equiv[g["mode"]] = true
			continue
		var v := int(g["value"])
		if v > int(best.get(g["mode"], -1)):
			best[g["mode"]] = v
	if best.has("walk"):
		for mode in equiv:
			if mode != "walk" and int(best["walk"]) > int(best.get(mode, -1)):
				best[mode] = best["walk"]
	return best

# An Unarmored Defense that needs both hands free as well as a bare chest. The
# barbarian's is the odd one out — RAW it is the only one that still works with a
# Shield in hand.
const NO_SHIELD_FORMULAS := ["monk", "dance"]

# {ac: int, breakdown: Array}. Highest calculation base + every bonus.
static func ac(bundles: Array, abilities: Dictionary, armor_ac) -> Dictionary:
	var dex: int = int(abilities["dex"]["mod"])
	# "While you aren't wearing armor" is half of every Unarmored Defense's text
	# and none of it was read: a barbarian in padded armor took max(11 + DEX,
	# 10 + DEX + CON) and kept the unarmored number while wearing armor.
	var wearing_body: bool = armor_ac != null and armor_ac["totalBase"] != null
	var using_shield: bool = armor_ac != null and (int(armor_ac["shieldBonus"]) > 0
		or bool(armor_ac["non_proficient_shield"]))
	var calcs: Array = []
	for tg in Bundles.of_type(bundles, "armor-class"):
		var c: Dictionary = tg["grant"]["calculation"]
		var base := 0
		match c["mode"]:
			"armored":
				base = int(armor_ac["totalBase"]) if wearing_body else 10 + dex
			"natural":
				base = int(c["baseAc"])
			"unarmored":
				if wearing_body:
					continue
				if c["formula"] in NO_SHIELD_FORMULAS and using_shield:
					continue
				base = 10 + dex
				match c["formula"]:
					"barbarian": base += int(abilities["con"]["mod"])
					"monk": base += int(abilities["wis"]["mod"])
					# Dazzling Footwork is 10 + DEX + CHA. This used to add the
					# BARDIC INSPIRATION DIE SIZE instead — a number that belongs
					# in no AC at all — computed by a bardic_inspiration() helper
					# here that existed for this one line and is now gone. The die
					# itself is authored in data/effects/features.json and keyed
					# off the sheet's class level, which is where the verb that
					# rolls it has always read it from.
					"dance": base += int(abilities["cha"]["mod"])
					_: assert(false, "unhandled unarmored AC formula: " + str(c["formula"]))
			_:
				assert(false, "unhandled AC calculation mode: " + str(c["mode"]))
		calcs.append({"mode": c["mode"], "base": base, "source": tg["source"]})
	# Barbarian and monk are granted an `unarmored` calculation and NO `armored`
	# one (the export emits it only for the ten classes with no Unarmored
	# Defense), so with the gate above a barbarian in chain mail would have had
	# no calculation left at all and fallen back to 10 + DEX — armor ignored.
	# Wearing armor is a thing every class can do; the calculation is implicit.
	if wearing_body and not calcs.any(func(c): return c["mode"] == "armored"):
		calcs.append({"mode": "armored", "base": int(armor_ac["totalBase"]),
			"source": {"origin": "item", "id": "armor"}})

	var bonuses: Array = []
	for tg in Bundles.of_type(bundles, "ac-bonus"):
		bonuses.append({"bonus": int(tg["grant"]["bonus"]), "source": tg["source"]})
	if armor_ac != null and int(armor_ac["shieldBonus"]) > 0:
		bonuses.append({"bonus": int(armor_ac["shieldBonus"]), "source": {"origin": "item", "id": "shield"}})

	var total := 10 + dex
	if not calcs.is_empty():
		total = int(calcs[0]["base"])
		for c in calcs:
			total = maxi(total, int(c["base"]))
	for b in bonuses:
		total += int(b["bonus"])
	var breakdown: Array = calcs.duplicate()
	breakdown.append_array(bonuses)
	return {"ac": total, "breakdown": breakdown}

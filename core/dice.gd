# d20 with advantage/disadvantage, dice-notation rolls, crit doubling.
extends RefCounted

enum { NORMAL, ADV, DIS }

# Returns {"nat": int, "dice": [rolls]} — nat is the die that counts.
static func d20(rng, mode: int = NORMAL) -> Dictionary:
	var a: int = rng.roll_die(20)
	if mode == NORMAL:
		return {"nat": a, "dice": [a]}
	var b: int = rng.roll_die(20)
	var nat: int = (a if a >= b else b) if mode == ADV else (a if a <= b else b)
	return {"nat": nat, "dice": [a, b]}

# "2d6+3" / "d20" / "1d8-1" -> {"count": int, "sides": int, "mod": int}
# A bare number ("1", "-2") is a flat modifier with no dice — the resolver's plain
# unarmed strike used to emit one, and a nonsense string must not kill a fight.
static func parse(notation: String) -> Dictionary:
	var n := notation.strip_edges().to_lower()
	if n.is_valid_int():
		return {"count": 0, "sides": 0, "mod": int(n)}
	var re = RegEx.new()
	re.compile("^(\\d*)d(\\d+)([+-]\\d+)?$")
	var m = re.search(n)
	if m == null:
		push_error("bad dice notation: " + notation)
		return {"count": 0, "sides": 0, "mod": 0}
	var cs = m.get_string(1)
	var ms = m.get_string(3)
	return {
		"count": int(cs) if cs != "" else 1,
		"sides": int(m.get_string(2)),
		"mod": int(ms) if ms != "" else 0,
	}

# crit=true rolls the dice portion twice (not the modifier) — 5e RAW.
static func roll(rng, notation: String, crit: bool = false) -> int:
	return roll_detailed(rng, notation, crit)["total"]

# Same roll, keeping the individual dice — so a hit roll ("d20[13]+5 = 18") and
# its damage roll can both show their own breakdown in the log instead of
# damage collapsing into one flat number that looks like it might just be
# reusing the to-hit bonus. {"sides": int, "rolls": [each die], "mod": int,
# "total": int} — "rolls" is empty for a flat/no-dice notation (an unarmed
# strike's "1", say), so the caller can fall back to a plain number.
static func roll_detailed(rng, notation: String, crit: bool = false) -> Dictionary:
	var p = parse(notation)
	var n: int = p.count * (2 if crit else 1)
	var rolls: Array[int] = []
	var total: int = p.mod
	for i in n:
		var r: int = rng.roll_die(p.sides)
		rolls.append(r)
		total += r
	return {"sides": p.sides, "rolls": rolls, "mod": p.mod, "total": maxi(0, total)}

static func combine(adv: bool, dis: bool) -> int:
	if adv and not dis:
		return ADV
	if dis and not adv:
		return DIS
	return NORMAL

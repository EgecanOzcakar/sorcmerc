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
static func parse(notation: String) -> Dictionary:
	var re = RegEx.new()
	re.compile("^(\\d*)d(\\d+)([+-]\\d+)?$")
	var m = re.search(notation.strip_edges().to_lower())
	assert(m != null, "bad dice notation: " + notation)
	var cs = m.get_string(1)
	var ms = m.get_string(3)
	return {
		"count": int(cs) if cs != "" else 1,
		"sides": int(m.get_string(2)),
		"mod": int(ms) if ms != "" else 0,
	}

# crit=true rolls the dice portion twice (not the modifier) — 5e RAW.
static func roll(rng, notation: String, crit: bool = false) -> int:
	var p = parse(notation)
	var n: int = p.count * (2 if crit else 1)
	var total: int = p.mod
	for i in n:
		total += rng.roll_die(p.sides)
	return maxi(0, total)

static func combine(adv: bool, dis: bool) -> int:
	if adv and not dis:
		return ADV
	if dis and not adv:
		return DIS
	return NORMAL

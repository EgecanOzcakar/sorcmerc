# The turn resolver. Pure logic, no nodes. Mutates combatant state, appends to `log`.
# Straight-line functions only — no reaction prompts (combat-design.md §2).
extends RefCounted

const Dice = preload("res://core/dice.gd")
const Hex = preload("res://core/hex.gd")

const MAX_ROUNDS := 60  # safety guard; a real fight ends in ~4-6

var rng
var combatants: Array = []
var board: Dictionary = {}
var order: Array = []
var turn_idx: int = 0
var round_num: int = 1
var log: Array[String] = []

# per-turn resource state (combat-design.md §10 risk 3 — model it explicitly)
var move_left: int = 0        # move points remaining this turn
var action_used = false
var bonus_used = false
var _sneak_used_turn = false

func _init(_rng, _combatants: Array, _board: Dictionary) -> void:
	rng = _rng
	combatants = _combatants
	board = _board
	_roll_initiative()

# --- board -----------------------------------------------------------

func passable(p: Vector2i) -> bool:
	return p in board["hexes"]

func is_cover(p: Vector2i) -> bool:
	return p in board["cover"]

func _rough() -> Array:
	return board.get("rough", [])

func region_at(p: Vector2i) -> String:
	var f = board.get("region_at")
	return f.call(p) if f is Callable else ""

func _blockers(mover) -> Array:
	return combatants.filter(func(c): return c != mover and c.conscious()).map(func(c): return c.pos)

func _hex_free(p: Vector2i, ignore = null) -> bool:
	for c in combatants:
		if c != ignore and c.conscious() and c.pos == p:
			return false
	return true

func adjacent_to_brazier(c) -> bool:
	return Hex.distance(c.pos, board["brazier"]) <= 1

func _roll_initiative() -> void:
	for c in combatants:
		c.init_roll = Dice.d20(rng).nat + c.init_mod
	order = combatants.duplicate()
	order.sort_custom(_init_before)
	var names: Array = []
	for c in order:
		names.append("%s(%d)" % [c.cname, c.init_roll])
	log.append("Initiative: " + ", ".join(names))

func _init_before(a, b) -> bool:
	if a.init_roll != b.init_roll:
		return a.init_roll > b.init_roll
	if a.init_mod != b.init_mod:
		return a.init_mod > b.init_mod
	return a.team == "party"

# --- turn lifecycle -------------------------------------------------------

func current():
	return order[turn_idx]

func begin_turn() -> void:
	var c = current()
	move_left = c.speed
	action_used = false
	bonus_used = false
	_sneak_used_turn = false
	c.statuses.erase("dodging")
	c.statuses.erase("reacted")
	c.statuses.erase("helped")  # granted advantage expires if unused by your turn
	if c.is_down():
		_death_save(c)

func begin_turn_for(c) -> void:
	# test/tooling helper: prime this turn's move points for an arbitrary combatant.
	move_left = c.speed

func end_turn() -> void:
	current().has_acted = true
	for _i in order.size() + 1:
		turn_idx += 1
		if turn_idx >= order.size():
			turn_idx = 0
			round_num += 1
		var c = current()
		if c.is_dead() or c.is_stable():
			continue
		return

func is_over() -> bool:
	return round_num > MAX_ROUNDS or _team_out("party") or _team_out("foe")

func _team_out(team: String) -> bool:
	for c in combatants:
		if c.team == team and c.conscious():
			return false
	return true

func outcome() -> String:
	if _team_out("foe"):
		return "Victory"
	if _team_out("party"):
		return "Defeat"
	return "ongoing"

# --- queries used by UI and AI ------------------------------------------

func team_of(team: String) -> Array:
	return combatants.filter(func(c): return c.team == team)

func enemies_of(c) -> Array:
	return combatants.filter(func(o): return o.team != c.team and o.conscious())

func allies_of(c) -> Array:
	return combatants.filter(func(o): return o.team == c.team and o != c and o.conscious())

func adjacent_enemy(c) -> bool:
	for o in enemies_of(c):
		if Hex.distance(o.pos, c.pos) <= 1:
			return true
	return false

# Can `attacker` reach `target` with a weapon attack right now?
func in_reach(attacker, target) -> bool:
	var d := Hex.distance(attacker.pos, target.pos)
	if attacker.ranged:
		return d <= attacker.atk_range
	return d <= int(board.get("reach_melee", 1))

func effective_ac(c) -> int:
	var ac: int = c.ac
	if is_cover(c.pos):
		ac += 2  # half cover
	return ac

func hit_chance(attacker, target, opts := {}) -> float:
	var mode = _attack_mode(attacker, target, opts)
	var need: int = effective_ac(target) - attacker.atk_bonus
	var p: float = clampf((21.0 - need) / 20.0, 0.05, 0.95)
	if mode == Dice.ADV:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	elif mode == Dice.DIS:
		p = p * p
	return p

# Probability `target` FAILS a DC `dc` DEX save (what a caster wants). UI-only.
func save_fail_chance(target, dc: int, ignore_cover := false) -> float:
	var bonus: int = target.dex_save
	if is_cover(target.pos) and not ignore_cover:
		bonus += 2
	var p_make: float = clampf((21.0 - (dc - bonus)) / 20.0, 0.0, 1.0)
	if target.has("dodging"):
		p_make = 1.0 - (1.0 - p_make) * (1.0 - p_make)
	return 1.0 - p_make

# Probability a Shove by `attacker` beats `target`'s contest (ties lose). UI-only.
func shove_chance(attacker, target) -> float:
	var am: int = attacker.athletics
	var dm: int = maxi(target.athletics, target.acro)
	var wins := 0
	for a in range(1, 21):
		for d in range(1, 21):
			if a + am > d + dm:
				wins += 1
	return wins / 400.0

# --- attack ------------------------------------------------------------

func _attack_mode(attacker, target, opts := {}) -> int:
	var adv = false
	var dis = false
	if attacker.ranged and adjacent_enemy(attacker):
		dis = true
	if target.has("prone"):
		if attacker.ranged:
			dis = true
		else:
			adv = true
	if target.has("dodging"):
		dis = true
	if attacker.has("hidden"):
		adv = true
	if attacker.has("helped"):
		adv = true
	if opts.get("advantage", false):
		adv = true
	return Dice.combine(adv, dis)

func _sneak_ok(attacker, target, mode: int) -> bool:
	if attacker.sneak_attack == "" or _sneak_used_turn or mode == Dice.DIS:
		return false
	if mode == Dice.ADV:
		return true
	for a in allies_of(attacker):
		if Hex.distance(a.pos, target.pos) <= 1:
			return true
	return false

func resolve_attack(attacker, target, opts := {}) -> Dictionary:
	if not opts.get("opportunity", false) and not in_reach(attacker, target):
		return {"error": "out of range"}
	if not opts.get("opportunity", false):
		action_used = true   # a weapon attack is the Action; OAs are free
	var notation: String = opts.get("damage", attacker.damage)
	var mode = _attack_mode(attacker, target, opts)
	var r = Dice.d20(rng, mode)
	var nat: int = r.nat
	var total: int = nat + attacker.atk_bonus
	var ac = effective_ac(target)
	var crit: bool = nat >= attacker.crit_range
	var hit: bool = crit or (nat != 1 and total >= ac)
	var out = {
		"attacker": attacker.cname, "target": target.cname,
		"nat": nat, "dice": r.dice, "bonus": attacker.atk_bonus, "total": total, "ac": ac,
		"hit": hit, "crit": crit, "damage": 0, "sneak": 0, "surprise": 0, "mode": mode,
	}
	if hit:
		var dmg = Dice.roll(rng, notation, crit)
		if _sneak_ok(attacker, target, mode):
			out.sneak = Dice.roll(rng, attacker.sneak_attack, crit)
			dmg += out.sneak
			_sneak_used_turn = true
		if attacker.surprise_attack != "" and not target.has_acted:
			out.surprise = Dice.roll(rng, attacker.surprise_attack, crit)
			dmg += out.surprise
		out.damage = dmg
	attacker.statuses.erase("hidden")
	if not opts.get("opportunity", false):
		attacker.statuses.erase("helped")  # the granted advantage is spent
	_log_attack(out, opts.get("opportunity", false))
	if hit:
		_apply_damage(target, out.damage)
	return out

func _log_attack(o: Dictionary, oa: bool) -> void:
	var dice_s = str(o.dice[0]) if o.dice.size() == 1 else "%d̶%d" % [o.dice[0], o.dice[1]]
	var tag = "OA " if oa else ""
	var roll_s = "d20[%s]%+d = %d vs AC %d" % [dice_s, o.bonus, o.total, o.ac]
	if not o.hit:
		if o.nat == 1:
			var flavs := [
				"the blow sails wide.", "a clumsy swing finds only air.",
				"the strike fumbles at the last inch.", "%s twists clear untouched." % o.target,
			]
			var pick: int = (str(o.attacker).hash() + round_num) % flavs.size()
			log.append("%s%s misses %s badly — nat 1, %s" % [tag, o.attacker, o.target, flavs[pick]])
		else:
			log.append("%s%s attacks %s — %s, misses." % [tag, o.attacker, o.target, roll_s])
		return
	var extra = ""
	if o.sneak > 0:
		extra += " +%d sneak" % o.sneak
	if o.surprise > 0:
		extra += " +%d surprise" % o.surprise
	var word = "CRITS" if o.crit else "hits"
	log.append("%s%s %s %s — %s, %d damage%s." % [tag, o.attacker, word, o.target, roll_s, o.damage, extra])

# --- damage / death --------------------------------------------------

func _apply_damage(target, dmg: int) -> void:
	if target.is_down():
		target.death_f += 1 if dmg > 0 else 0
		if target.death_f >= 3:
			_kill(target)
		return
	var before: int = target.hp
	target.hp -= dmg
	if target.hp <= 0:
		var overkill: int = -target.hp
		target.hp = 0
		if target.team == "foe" or overkill >= target.max_hp:
			_kill(target)
		else:
			target.statuses["down"] = true
			target.statuses.erase("prone")
			target.death_s = 0
			target.death_f = 0
			log.append("%s falls unconscious." % target.cname)

func _kill(c) -> void:
	c.statuses["dead"] = true
	c.statuses.erase("down")
	c.hp = 0
	log.append("%s is dead." % c.cname)

func _death_save(c) -> void:
	var r = Dice.d20(rng)
	if r.nat == 20:
		c.statuses.erase("down")
		c.death_s = 0
		c.death_f = 0
		c.hp = 1
		log.append("%s's eyes snap open — nat 20, up at 1 HP!" % c.cname)
		return
	if r.nat == 1:
		c.death_f += 2
	elif r.nat >= 10:
		c.death_s += 1
	else:
		c.death_f += 1
	if c.death_f >= 3:
		_kill(c)
	elif c.death_s >= 3:
		c.statuses["stable"] = true
		log.append("%s stabilises, still unconscious." % c.cname)
	else:
		log.append("%s death save: rolled %d  [%d ok / %d fail]" % [c.cname, r.nat, c.death_s, c.death_f])

func heal(c, amount: int) -> void:
	if c.is_dead():
		return
	var revived = c.is_down()
	if revived:
		c.statuses.erase("down")
		c.statuses.erase("stable")
		c.death_s = 0
		c.death_f = 0
	c.hp = mini(c.max_hp, maxi(c.hp, 0) + amount)
	log.append("%s %s — %d HP (%d/%d)." % [c.cname, "revives" if revived else "is healed", amount, c.hp, c.max_hp])

# --- movement -------------------------------------------------------

# Hexes reachable by `mover` with the move points left this turn.
func move_field(mover) -> Dictionary:
	return Hex.reachable(passable, mover.pos, move_left, _blockers(mover), _rough())

# The shortest route `mover` would walk to `dest`.
func move_path(mover, dest: Vector2i) -> Array:
	return Hex.path_to(passable, mover.pos, dest, _blockers(mover), _rough())

# Hostiles that get an opportunity attack somewhere along `mover`'s walk to `dest`.
func provokers_for(mover, dest: Vector2i) -> Array:
	var path := move_path(mover, dest)
	var out: Array = []
	for f in enemies_of(mover):
		if f.has("reacted") or f in out:
			continue
		for i in range(path.size() - 1):
			if Hex.distance(f.pos, path[i]) <= 1 and Hex.distance(f.pos, path[i + 1]) > 1:
				out.append(f)
				break
	return out

func move_to(mover, dest: Vector2i, disengage := false) -> void:
	if dest == mover.pos:
		return
	var field := move_field(mover)
	if not field.has(dest):
		return  # out of range / blocked — UI never offers this; guard for AI + tests
	var from: Vector2i = mover.pos
	if not disengage:
		for f in provokers_for(mover, dest):
			f.statuses["reacted"] = true
			resolve_attack(f, mover, {"opportunity": true})
			if mover.is_down() or mover.is_dead():
				return
	var before_region := region_at(from)
	mover.pos = dest
	move_left -= field[dest]
	if region_at(dest) != before_region:
		log.append("%s moves to the %s." % [mover.cname, region_at(dest)])

# --- actions -------------------------------------------------------

func act_dodge(c) -> void:
	c.statuses["dodging"] = true
	action_used = true
	log.append("%s takes the Dodge action." % c.cname)

# Help: the named ally's next attack roll (before your next turn) has advantage.
func act_help(helper, ally) -> void:
	action_used = true
	ally.statuses["helped"] = true
	log.append("%s helps %s — advantage on their next attack." % [helper.cname, ally.cname])

# Hide: Stealth vs the best enemy passive Perception. On success you're hidden
# (attacks against you have disadvantage; your next attack has advantage).
func act_hide(c) -> bool:
	bonus_used = true
	var dc: int = 0
	for e in enemies_of(c):
		dc = maxi(dc, e.passive_perception)
	var roll: int = Dice.d20(rng).nat + c.stealth
	if roll >= dc:
		c.statuses["hidden"] = true
		log.append("%s slips out of sight — Stealth %d vs %d." % [c.cname, roll, dc])
		return true
	log.append("%s fails to hide — Stealth %d vs %d." % [c.cname, roll, dc])
	return false

# Cunning Action: a bonus-action Dash (Rogue).
func act_cunning_dash(c) -> void:
	bonus_used = true
	move_left += c.speed
	log.append("%s darts ahead — Cunning Action Dash." % c.cname)

func act_shove(attacker, target, choice: String) -> Dictionary:
	action_used = true
	var a = Dice.d20(rng).nat + attacker.athletics
	var d = Dice.d20(rng).nat + maxi(target.athletics, target.acro)
	if a <= d:
		log.append("%s tries to shove %s — %d vs %d, fails." % [attacker.cname, target.cname, a, d])
		return {"success": false}
	match choice:
		"prone":
			target.statuses["prone"] = true
			log.append("%s shoves %s prone (%d vs %d)." % [attacker.cname, target.cname, a, d])
		"push":
			var dest = target.pos + Hex.direction_to(attacker.pos, target.pos)
			if passable(dest) and _hex_free(dest, target):
				target.pos = dest
				log.append("%s shoves %s back into the %s." % [attacker.cname, target.cname, region_at(dest)])
			else:
				target.statuses["prone"] = true
				log.append("%s shoves %s — no room to push, %s falls prone." % [attacker.cname, target.cname, target.cname])
		"brazier":
			if not adjacent_to_brazier(target):
				return {"success": true}
			var burn = Dice.roll(rng, "2d6")
			log.append("%s shoves %s into the brazier — 2d6 = %d fire." % [attacker.cname, target.cname, burn])
			_apply_damage(target, burn)
	return {"success": true}

func act_second_wind(c) -> void:
	if c.second_wind == "" or c.used_second_wind:
		return
	c.used_second_wind = true
	bonus_used = true
	var amt = Dice.roll(rng, c.second_wind)
	log.append("%s uses Second Wind." % c.cname)
	heal(c, amt)

func cast_healing_word(caster, target, level := 1) -> void:
	if not "healing_word" in caster.spells:
		return
	if level >= 2 and caster.slots2 > 0:
		caster.slots2 -= 1
	elif caster.slots1 > 0:
		caster.slots1 -= 1
		level = 1
	else:
		return
	bonus_used = true
	var amt = Dice.roll(rng, "1d4+3") + (level - 1) * Dice.roll(rng, "1d4")
	log.append("%s casts Healing Word on %s." % [caster.cname, target.cname])
	heal(target, amt)

func cast_burning_hands(caster, dir: Vector2i, level := 1) -> void:
	if not "burning_hands" in caster.spells:
		return
	if level >= 2 and caster.slots2 > 0:
		caster.slots2 -= 1
	elif caster.slots1 > 0:
		caster.slots1 -= 1
		level = 1
	else:
		return
	action_used = true
	var notation = "%dd6" % (2 + level)
	var wedge := Hex.cone(caster.pos, dir, int(board.get("cone_burning_hands", 2)))
	log.append("%s casts Burning Hands — a cone of flame, DC %d save." % [caster.cname, caster.save_dc])
	for c in combatants:
		if c == caster or not c.conscious() or not (c.pos in wedge):
			continue
		var dmg = Dice.roll(rng, notation)
		var saved = _saving_throw(c, caster.save_dc)
		var final = (dmg / 2) if saved else dmg
		log.append("  %s %s the save — %d fire." % [c.cname, "makes" if saved else "fails", final])
		_apply_damage(c, final)

func cast_sacred_flame(caster, target) -> void:
	if not "sacred_flame" in caster.spells:
		return
	action_used = true
	var dmg = Dice.roll(rng, "1d8")
	var saved = _saving_throw(target, caster.save_dc, true)
	log.append("%s calls Sacred Flame on %s — %s the save%s." % [
		caster.cname, target.cname, "makes" if saved else "fails",
		"" if saved else ", %d radiant" % dmg,
	])
	if not saved:
		_apply_damage(target, dmg)

func _saving_throw(c, dc: int, ignore_cover := false) -> bool:
	var bonus: int = c.dex_save
	if is_cover(c.pos) and not ignore_cover:
		bonus += 2
	var mode = Dice.ADV if c.has("dodging") else Dice.NORMAL
	return Dice.d20(rng, mode).nat + bonus >= dc

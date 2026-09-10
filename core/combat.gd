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
	c.new_turn()   # action/bonus/reaction/move + turn-long statuses (spec §7)
	if c.is_down():
		_death_save(c)

func begin_turn_for(c) -> void:
	# test/tooling helper: give an arbitrary combatant a fresh turn's economy.
	c.new_turn()

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

# Probability `target` FAILS a DC `dc` save (what a caster wants). UI-only.
func save_fail_chance(target, dc: int, ability := "dex", ignore_cover := false) -> float:
	var bonus: int = int(target.saves.get(ability, 0))
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

# --- action economy + verbs (spec §6/§7) -------------------------------
#
# Everything a combatant can do is a verb: the core actions below, plus the
# feature- and spell-derived verbs adapter.gd resolved onto `actor.verbs`.
# Nothing in this file names a hero, a class or a spell.

const BASIC := [
	{"id": "attack", "label": "Attack", "kind": "attack", "cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_prone", "label": "Shove → prone", "kind": "shove", "choice": "prone",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_push", "label": "Shove → back", "kind": "shove", "choice": "push",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_brazier", "label": "Shove → brazier", "kind": "shove", "choice": "brazier",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "help", "label": "Help an ally", "kind": "help", "cost": "action", "targeting": "ally", "range": 1},
	{"id": "dodge", "label": "Dodge", "kind": "dodge", "cost": "action", "targeting": "self"},
	{"id": "dash", "label": "Dash", "kind": "dash", "cost": "action", "targeting": "self"},
	{"id": "disengage", "label": "Disengage", "kind": "disengage", "cost": "action", "targeting": "self"},
	{"id": "hide", "label": "Hide", "kind": "hide", "cost": "action", "targeting": "self"},
]

# Feature kinds that are a button. The rest are passive: passive_damage folds into
# resolve_attack, attacks_per_action into new_turn(), reaction fires on its trigger.
const OFFERABLE := ["heal_self", "heal_ally", "self_buff", "ally_buff", "grant_action",
	"attack_modifier", "save_effect", "spell"]

func _basic(id: String) -> Dictionary:
	for b in BASIC:
		if b["id"] == id:
			return b
	return {}

# Every verb `actor` can use right now (spec §6). scenes/main.gd renders this list;
# ai.gd scores it.
func available(actor) -> Array:
	var out: Array = []
	for b in BASIC:
		if _offerable(actor, b):
			out.append(b.duplicate())
	for v in actor.verbs:
		if v["kind"] == "grant_verb":
			for name in v.get("verbs", []):
				var g: Dictionary = _basic(name).duplicate()
				if g.is_empty():
					continue
				g["id"] = "%s:%s" % [v["id"], name]
				g["cost"] = v["cost"]
				if v.has("pool"):
					g["pool"] = v["pool"]
				if _offerable(actor, g):
					out.append(g)
		elif v["kind"] in OFFERABLE and _offerable(actor, v):
			out.append(v.duplicate())
	return out

func can_spend(actor, cost: String) -> bool:
	return cost in ["free", "none", ""] or int(actor.econ.get(cost, 0)) > 0

func _spend(actor, cost: String) -> bool:
	if not can_spend(actor, cost):
		return false
	if cost in ["action", "bonus", "reaction"]:
		actor.econ[cost] = int(actor.econ[cost]) - 1
	return true

func _offerable(actor, v: Dictionary) -> bool:
	if not actor.conscious():
		return false
	if not can_spend(actor, v.get("cost", "action")):
		return false
	if v.get("once_per", "") == "turn" and actor.econ.get("used", {}).has(v["id"]):
		return false
	if v.has("pool") and actor.pool_left(v["pool"]) <= 0:
		return false
	var slot := int(v.get("slot_level", 0))
	if slot > 0:
		if slot > actor.slots.size() or actor.slots[slot - 1] <= 0:
			return false
		# a bonus-action leveled spell forbids a leveled spell with your action (§7)
		if v["cost"] == "action" and actor.econ.get("cast_bonus_spell", false):
			return false
	match v["kind"]:
		"hide": return not actor.has("hidden")
		"dodge": return not actor.has("dodging")
		"disengage": return not actor.has("disengaged")
		"dash": return true
		"self_buff": return not actor.has(v.get("status", v["id"]))
		"attack_modifier", "grant_action": return true
		"shove": if actor.athletics <= 0: return false
	match v.get("targeting", "self"):
		"enemy": return enemies_of(actor).any(func(e): return legal_target(actor, v, e))
		"ally": return combatants.any(func(a): return a != actor and legal_target(actor, v, a))
		"direction": return not enemies_of(actor).is_empty()
	return true

# Is `c` a legal target for `v` cast/swung by `actor` right now?
func legal_target(actor, v: Dictionary, c) -> bool:
	match v.get("targeting", "self"):
		"enemy":
			if c.team == actor.team or not c.conscious():
				return false
			if v["kind"] == "attack":
				return in_reach(actor, c)
			if v.get("choice", "") == "brazier" and not adjacent_to_brazier(c):
				return false
			return Hex.distance(actor.pos, c.pos) <= int(v.get("range", 1))
		"ally":
			if c.team != actor.team or c == actor or c.is_dead():
				return false
			if not (v.has("heal_count") or v["kind"] in ["heal_ally", "ally_buff"]) and not c.conscious():
				return false
			return Hex.distance(actor.pos, c.pos) <= int(v.get("range", 1))
		"self":
			return c == actor
	return false

# Run a verb. `target` is a Combatant, a direction (Vector2i) or null.
func perform(actor, v: Dictionary, target = null) -> Dictionary:
	var kind: String = v["kind"]
	if kind != "attack" and not _spend(actor, v.get("cost", "action")):
		return {"error": "no %s left" % v.get("cost", "action")}
	if v.get("once_per", "") == "turn":
		actor.econ["used"][v["id"]] = true
	if v.has("pool"):
		if actor.pool_left(v["pool"]) <= 0:
			return {"error": "pool empty"}
		actor.pools[v["pool"]]["cur"] = actor.pool_left(v["pool"]) - 1
	match kind:
		"attack": return resolve_attack(actor, target)
		"shove": return act_shove(actor, target, v.get("choice", "prone"))
		"help": act_help(actor, target)
		"dodge": act_dodge(actor)
		"hide": act_hide(actor)
		"dash":
			actor.econ["move_left"] = int(actor.econ.get("move_left", 0)) + actor.speed
			log.append("%s dashes — +%d move." % [actor.cname, actor.speed])
		"disengage":
			actor.statuses["disengaged"] = true
			log.append("%s disengages." % actor.cname)
		"heal_self", "heal_ally":
			var who = actor if kind == "heal_self" else target
			log.append("%s uses %s." % [actor.cname, v["label"]])
			heal(who, Dice.roll(rng, "%dd%d+%d" % [int(v.get("dice_count", 1)),
				int(v.get("dice_sides", 10)), int(v.get("dice_bonus", 0))]))
		"self_buff":
			actor.statuses[v.get("status", v["id"])] = {
				"bonus_damage": int(v.get("bonus_damage", 0)), "resist": v.get("resist", [])}
			log.append("%s — %s!" % [actor.cname, v["label"]])
		"attack_modifier":
			actor.statuses["reckless"] = true
			log.append("%s attacks recklessly." % actor.cname)
		"grant_action":
			actor.econ["action"] = int(actor.econ["action"]) + int(v.get("amount", 1))
			actor.econ["attacks_left"] = int(actor.econ["attacks_left"]) + int(v.get("extra_attacks", 0))
			log.append("%s — %s!" % [actor.cname, v["label"]])
		"save_effect": return _save_effect(actor, v, target)
		"spell": return cast(actor, v, target)
	return {}

func _save_effect(actor, v: Dictionary, target) -> Dictionary:
	var saved := _saving_throw(target, actor.save_dc, v.get("save", "dex"))
	log.append("%s uses %s on %s — %s the save." % [
		actor.cname, v["label"], target.cname, "makes" if saved else "fails"])
	if not saved:
		for cond in v.get("conditions", []):
			target.statuses[cond] = true
	return {"saved": saved}

# --- spells ------------------------------------------------------------

# `target` is a Combatant (single / ally) or a direction (cone).
func cast(caster, v: Dictionary, target) -> Dictionary:
	var lvl := int(v.get("slot_level", 0))
	if lvl > 0:
		if lvl > caster.slots.size() or caster.slots[lvl - 1] <= 0:
			return {"error": "no slot"}
		caster.slots[lvl - 1] -= 1
		if v["cost"] == "bonus":
			caster.econ["cast_bonus_spell"] = true
	if v.has("heal_count"):
		log.append("%s casts %s on %s." % [caster.cname, v["label"], target.cname])
		heal(target, Dice.roll(rng, "%dd%d+%d" % [int(v["heal_count"]), int(v["heal_sides"]),
			int(v.get("heal_bonus", 0))]))
		return {}
	if not v.has("dice_count"):
		return {}
	var notation := "%dd%d" % [int(v["dice_count"]), int(v["dice_sides"])]
	var dc := int(v.get("save_dc", caster.save_dc))
	if v.get("targeting", "") == "direction":
		var wedge := Hex.cone(caster.pos, target, int(v.get("radius", 2)))
		log.append("%s casts %s — DC %d save." % [caster.cname, v["label"], dc])
		for c in combatants:
			if c == caster or not c.conscious() or not (c.pos in wedge):
				continue
			_spell_hit(c, v, notation, dc)
		return {}
	log.append("%s casts %s on %s." % [caster.cname, v["label"], target.cname])
	return _spell_hit(target, v, notation, dc)

func _spell_hit(c, v: Dictionary, notation: String, dc: int) -> Dictionary:
	if v.has("attack_bonus"):
		var r = Dice.d20(rng)
		var crit: bool = r.nat == 20
		var hit: bool = crit or (r.nat != 1 and r.nat + int(v["attack_bonus"]) >= effective_ac(c))
		var d := Dice.roll(rng, notation, crit) if hit else 0
		log.append("  d20[%d]%+d vs AC %d — %s%s." % [r.nat, int(v["attack_bonus"]), effective_ac(c),
			"hit for %d" % d if hit else "miss", " (CRIT)" if crit else ""])
		if hit:
			_apply_damage(c, d, v.get("damage_type", ""))
		return {"hit": hit, "damage": d}
	var dmg := Dice.roll(rng, notation)
	var saved := false
	if v.get("save", "") != "":
		saved = _saving_throw(c, dc, v["save"], v.get("ignores_cover", false))
		if saved:
			dmg = (dmg / 2) if v.get("half_on_save", false) else 0
	log.append("  %s %s the save — %d %s." % [c.cname, "makes" if saved else "fails", dmg,
		v.get("damage_type", "damage")])
	if dmg > 0:
		_apply_damage(c, dmg, v.get("damage_type", ""))
	return {"saved": saved, "damage": dmg}

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
	if attacker.has("reckless") or target.has("reckless"):
		adv = true
	if opts.get("advantage", false):
		adv = true
	return Dice.combine(adv, dis)

# The `requires` vocabulary of a passive_damage verb (data/effects/features.json).
func _requires_met(attacker, target, mode: int, reqs: Array) -> bool:
	for r in reqs:
		match r:
			"not_disadvantage":
				if mode == Dice.DIS:
					return false
			"target_has_not_acted":
				if target.has_acted:
					return false
			"advantage_or_ally_adjacent":
				if mode != Dice.ADV and not allies_of(attacker).any(
						func(a): return Hex.distance(a.pos, target.pos) <= 1):
					return false
	return true

# Extra dice a hit adds — Sneak Attack, a goblin's Surprise Attack. [{label, amount}]
func _passive_damage(attacker, target, mode: int, crit: bool) -> Array:
	var out: Array = []
	for v in attacker.verbs:
		if v["kind"] != "passive_damage" or v.get("trigger", "") != "on_weapon_hit":
			continue
		if v.get("once_per", "") == "turn" and attacker.econ.get("used", {}).has(v["id"]):
			continue
		if not _requires_met(attacker, target, mode, v.get("requires", [])):
			continue
		if v.get("once_per", "") == "turn":
			attacker.econ["used"][v["id"]] = true
		out.append({"label": v["label"], "amount": Dice.roll(rng,
			"%dd%d" % [int(v["dice_count"]), int(v["dice_sides"])], crit)})
	return out

# Damage a held buff adds to a melee swing (Rage).
func _buff_damage(attacker) -> int:
	var n := 0
	for s in attacker.statuses.values():
		if s is Dictionary:
			n += int(s.get("bonus_damage", 0))
	return n

func resolve_attack(attacker, target, opts := {}) -> Dictionary:
	var oa: bool = opts.get("opportunity", false)
	if not oa and not in_reach(attacker, target):
		return {"error": "out of range"}
	if not oa:
		# the Attack action buys `attacks_per_action` swings; OAs are free (§7)
		if int(attacker.econ.get("attacks_left", 0)) > 0:
			attacker.econ["attacks_left"] = int(attacker.econ["attacks_left"]) - 1
		elif _spend(attacker, "action"):
			attacker.econ["attacks_left"] = int(attacker.econ.get("attacks_per_action", 1)) - 1
		else:
			return {"error": "no action left"}
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
		"hit": hit, "crit": crit, "damage": 0, "extras": [], "mode": mode,
	}
	if hit:
		var dmg = Dice.roll(rng, notation, crit)
		out.extras = _passive_damage(attacker, target, mode, crit)
		for e in out.extras:
			dmg += int(e["amount"])
		if not attacker.ranged:
			dmg += _buff_damage(attacker)
		out.damage = dmg
	attacker.statuses.erase("hidden")
	if not oa:
		attacker.statuses.erase("helped")  # the granted advantage is spent
	_log_attack(out, oa)
	if hit:
		_apply_damage(target, out.damage, _damage_type(attacker))
	return out

func _damage_type(attacker) -> String:
	return str(attacker.attacks[0].get("damage_type", "")) if not attacker.attacks.is_empty() else ""

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
	for e in o.extras:
		extra += " +%d %s" % [int(e["amount"]), str(e["label"]).to_lower()]
	var word = "CRITS" if o.crit else "hits"
	log.append("%s%s %s %s — %s, %d damage%s." % [tag, o.attacker, word, o.target, roll_s, o.damage, extra])

# --- damage / death --------------------------------------------------

func _resists(c, dtype: String) -> bool:
	if dtype == "":
		return false
	for s in c.statuses.values():
		if s is Dictionary and dtype in s.get("resist", []):
			return true
	return false

func _apply_damage(target, dmg: int, dtype := "") -> void:
	if _resists(target, dtype):
		dmg = dmg / 2
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
	return Hex.reachable(passable, mover.pos, int(mover.econ.get("move_left", 0)),
		_blockers(mover), _rough())

# The shortest route `mover` would walk to `dest`.
func move_path(mover, dest: Vector2i) -> Array:
	return Hex.path_to(passable, mover.pos, dest, _blockers(mover), _rough())

# Hostiles that get an opportunity attack somewhere along `mover`'s walk to `dest`.
func provokers_for(mover, dest: Vector2i) -> Array:
	var path := move_path(mover, dest)
	var out: Array = []
	for f in enemies_of(mover):
		if not can_spend(f, "reaction") or f in out:
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
	if not disengage and not mover.has("disengaged"):
		for f in provokers_for(mover, dest):
			_spend(f, "reaction")
			resolve_attack(f, mover, {"opportunity": true})
			if mover.is_down() or mover.is_dead():
				return
	var before_region := region_at(from)
	mover.pos = dest
	mover.econ["move_left"] = int(mover.econ.get("move_left", 0)) - field[dest]
	if region_at(dest) != before_region:
		log.append("%s moves to the %s." % [mover.cname, region_at(dest)])

# --- actions -------------------------------------------------------

func act_dodge(c) -> void:
	c.statuses["dodging"] = true
	log.append("%s takes the Dodge action." % c.cname)

# Help: the named ally's next attack roll (before your next turn) has advantage.
func act_help(helper, ally) -> void:
	ally.statuses["helped"] = true
	log.append("%s helps %s — advantage on their next attack." % [helper.cname, ally.cname])

# Hide: Stealth vs the best enemy passive Perception. On success you're hidden
# (attacks against you have disadvantage; your next attack has advantage).
func act_hide(c) -> bool:
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

func act_shove(attacker, target, choice: String) -> Dictionary:
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

func _saving_throw(c, dc: int, ability := "dex", ignore_cover := false) -> bool:
	var bonus: int = int(c.saves.get(ability, 0))
	if is_cover(c.pos) and not ignore_cover:
		bonus += 2
	var mode = Dice.ADV if c.has("dodging") else Dice.NORMAL
	return Dice.d20(rng, mode).nat + bonus >= dc

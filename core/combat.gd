# The turn resolver. Pure logic, no nodes. Mutates combatant state, appends to `log`.
# Straight-line functions only — no reaction prompts (combat-design.md §2).
extends RefCounted

const Dice = preload("res://core/dice.gd")
const Hex = preload("res://core/hex.gd")
const Effects = preload("res://core/rules/effects.gd")
const Ach = preload("res://core/achievements.gd")
const Barks = preload("res://core/barks.gd")
const Rng = preload("res://core/rng.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const FT_PER_HEX := 6  # adapter.gd's convention

# Engine-only states that behave like conditions but aren't the official 15, so
# they can't live in data/effects/conditions.json (validated against the catalog).
const ENGINE_CONDS := {
	"dodging": {"attacks_against": "dis"},
	"hidden": {"own_attacks": "adv"},
	"helped": {"own_attacks": "adv"},
	"reckless": {"own_attacks": "adv", "attacks_against": "adv"},
	"sapped": {"own_attacks": "dis"},    # weapon mastery Sap
	"slowed": {"speed_penalty_ft": 10},  # weapon mastery Slow
}

const MAX_ROUNDS := 60  # safety guard; a real fight ends in ~4-6

var rng
var combatants: Array = []
var board: Dictionary = {}
var order: Array = []
var turn_idx: int = 0
var round_num: int = 1
var log: Array[String] = []
# T19: party combatant ids that hit 0 HP at any point this fight. Read back out by
# encounter.resolve_outcome() so campaign.gd can tell a flawless hard win from a
# messy one; "down" itself is erased the moment someone gets back up.
var downed: Dictionary = {}

# T26 barks: a cosmetic side channel. Entries are {"id": combatant id, "text": line};
# the board scene drains it each frame. Nothing in this file reads it back.
var barks: Array = []
const BARK_QUEUE_MAX := 8   # nobody draining (headless, campaign) must not grow it
var _bark_rng = null         # null under SORCMERC_FAST — barks skipped entirely

func _init(_rng, _combatants: Array, _board: Dictionary) -> void:
	rng = _rng
	combatants = _combatants
	board = _board
	# Own stream, seeded off the combat seed: reproducible per seed, and a fast/headless
	# run (which skips barks) still rolls the *fight* identically to a played one.
	if OS.get_environment("SORCMERC_FAST") == "":
		_bark_rng = Rng.new((rng.seed_value ^ 0x5EEDBA12) & 0xFFFFFFFF)
	_roll_initiative()

# Fire a bark for `c` on `trigger` ("hit" | "crit" | "kill" | "low_hp" | "down" |
# "victory"). Cosmetic: never gates, never touches the combat RNG, never fails loudly.
func bark(c, trigger: String) -> void:
	if _bark_rng == null or c == null:
		return
	var faction := ""
	if c.team != "party" and c.src_id != "":
		faction = String(Catalog.monster(c.src_id).get("faction", ""))
	var text := Barks.line(_bark_rng, c.team, faction, trigger)
	if text == "":
		return
	barks.append({"id": c.id, "text": text})
	if barks.size() > BARK_QUEUE_MAX:
		barks.pop_front()

# --- board -----------------------------------------------------------

func passable(p: Vector2i) -> bool:
	return p in board["hexes"] and not object_at(p).get("blocks_movement", false)

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

# --- interactables (T11) ---------------------------------------------
# board["objects"]: [{type, pos, hazard?: {dice, damage_type}, hp?, blocks_movement?,
# explosive?}]. The Sunken Shrine's brazier is one of these.

func objects() -> Array:
	return board.get("objects", [])

func object_at(p: Vector2i) -> Dictionary:
	for o in objects():
		if o["pos"] == p:
			return o
	return {}

# The hazard `c` is standing next to — the brazier, a campfire. {} if none.
func adjacent_hazard(c) -> Dictionary:
	for o in objects():
		if o.has("hazard") and Hex.distance(c.pos, o["pos"]) <= 1:
			return o
	return {}

func adjacent_to_hazard(c) -> bool:
	return not adjacent_hazard(c).is_empty()

# A destructible neighbour (barrel, crate). {} if none.
func smashable_near(c) -> Dictionary:
	for o in objects():
		if int(o.get("hp", 0)) > 0 and Hex.distance(c.pos, o["pos"]) <= 1:
			return o
	return {}

func destroy_object(o: Dictionary) -> void:
	var arr: Array = objects()
	for i in arr.size():
		if arr[i]["pos"] == o["pos"]:
			arr.remove_at(i)
			break
	if not o.get("explosive", false):
		return
	var h: Dictionary = o.get("hazard", {})
	var dmg := Dice.roll(rng, String(h.get("dice", "2d6")))
	log.append("The %s bursts — %d %s to everything beside it." % [o["type"], dmg,
		h.get("damage_type", "fire")])
	for c in combatants:
		if c.conscious() and Hex.distance(c.pos, o["pos"]) <= 1:
			_apply_damage(c, dmg, String(h.get("damage_type", "")))

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
	begin_turn_for(c)
	if c.is_down():
		_death_save(c)

func begin_turn_for(c) -> void:
	c.new_turn()   # action/bonus/reaction/move + turn-long statuses (spec §7)
	_expire_conditions(c)
	_regenerate(c)
	_auto_stand(c)

# A condition applied with duration "round" lasts until the bearer's next turn:
# one lost turn, never a permanent lockout (nothing else in the engine ends them).
func _expire_conditions(c) -> void:
	for id in c.statuses.keys():
		var s = c.statuses[id]
		if s is Dictionary and s.has("until_tick") and _tick() > int(s["until_tick"]):
			c.statuses.erase(id)
			log.append("%s shakes off %s." % [c.cname, id])

func _tick() -> int:
	return round_num * maxi(1, order.size()) + turn_idx

# Trolls and friends: a heal_self verb with trigger start_of_turn, no button.
func _regenerate(c) -> void:
	if not c.conscious():
		return
	for v in c.verbs:
		if v["kind"] == "heal_self" and v.get("trigger", "") == "start_of_turn" and c.hp < c.max_hp:
			heal(c, int(v.get("amount", 0)))

# Standing up from prone is free-ish and automatic at the top of your own turn
# (no "spend your whole move lying there" busywork) but still costs half your
# speed, per RAW — deducted from this turn's move budget before anything else
# touches it. A feature can shrink the cost via a data-driven multiplier
# (stand_cost_mult on the feature's effects.json entry); nothing grants one
# yet, so the discount is 0% until something does.
func _auto_stand(c) -> void:
	if not c.has("prone"):
		return
	c.statuses.erase("prone")
	var mult := 1.0
	for fid in c.features:
		var e := Effects.feature(fid)
		if e.has("stand_cost_mult"):
			mult = minf(mult, float(e["stand_cost_mult"]))
	var cost: int = int(c.speed * 0.5 * mult)
	c.econ["move_left"] = maxi(0, int(c.econ.get("move_left", 0)) - cost)
	log.append("%s scrambles up off the ground (-%d move)." % [c.cname, cost])

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
	{"id": "smash", "label": "Smash it", "kind": "smash", "cost": "action", "targeting": "object", "range": 1},
	{"id": "help", "label": "Help an ally", "kind": "help", "cost": "action", "targeting": "ally", "range": 1},
	{"id": "dodge", "label": "Dodge", "kind": "dodge", "cost": "action", "targeting": "self"},
	{"id": "dash", "label": "Dash", "kind": "dash", "cost": "action", "targeting": "self"},
	{"id": "disengage", "label": "Disengage", "kind": "disengage", "cost": "action", "targeting": "self"},
	{"id": "hide", "label": "Hide", "kind": "hide", "cost": "action", "targeting": "self"},
]

# Feature kinds that are a button. The rest are passive: passive_damage folds into
# resolve_attack, attacks_per_action into new_turn(), reaction fires on its trigger.
const OFFERABLE := ["heal_self", "heal_ally", "self_buff", "ally_buff", "grant_action",
	"attack_modifier", "save_effect", "spell", "offhand_attack"]

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
	if cost in ["free", "none", ""]:
		return true
	return not _no_economy(actor, cost) and int(actor.econ.get(cost, 0)) > 0

func _spend(actor, cost: String) -> bool:
	if not can_spend(actor, cost):
		return false
	if cost in ["action", "bonus", "reaction"]:
		actor.econ[cost] = int(actor.econ[cost]) - 1
	return true

func _offerable(actor, v: Dictionary) -> bool:
	if not actor.conscious():
		return false
	if v.get("trigger", "") in ["passive", "start_of_turn"] \
			or (v.get("trigger", "") == "on_weapon_hit" and v["kind"] == "save_effect" and not v.has("pool")):
		return false   # fires from resolve_attack / begin_turn, never a button
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
		"object": return not smashable_near(actor).is_empty()
	return true

# Is `c` a legal target for `v` cast/swung by `actor` right now?
func legal_target(actor, v: Dictionary, c) -> bool:
	match v.get("targeting", "self"):
		"enemy":
			if c.team == actor.team or not c.conscious():
				return false
			if _source_of(actor, "cannot_target_source") == c:
				return false  # charmed
			if v["kind"] == "attack" or (v["kind"] == "offhand_attack" and int(v.get("range", 1)) <= 1):
				return in_reach(actor, c)
			if v.get("choice", "") == "brazier" and not adjacent_to_hazard(c):
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
		"offhand_attack":
			# Costs its own bonus action (or nothing, with Nick) — never an Attack-action
			# swing, so it rides the same "free" path Cleave's second swing uses. Mastery
			# is read off the main hand, so the off-hand swing carries none.
			return resolve_attack(actor, target, {"free": true, "no_mastery": true,
				"damage": v["damage"], "atk_bonus": int(v["to_hit"])})
		"shove": return act_shove(actor, target, v.get("choice", "prone"))
		"smash": return act_smash(actor)
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
		"ally_buff":
			target.statuses[v.get("status", v["id"])] = {"dice_sides": int(v.get("dice_sides", 6))}
			log.append("%s inspires %s." % [actor.cname, target.cname])
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
	var dmg := 0
	if int(v.get("dice_count", 0)) > 0:
		dmg = Dice.roll(rng, "%dd%d" % [int(v["dice_count"]), int(v["dice_sides"])])
		if saved:
			dmg = dmg / 2 if v.get("halve_damage", false) else 0
	if not saved:
		for cond in v.get("conditions", []):
			apply_condition(target, cond, actor, v.get("duration", ""))
	if dmg > 0:
		_apply_damage(target, dmg, v.get("damage_type", ""))
	return {"saved": saved, "damage": dmg}

# save_effect verbs that ride a weapon hit (a poison bite, a ghoul's paralysis).
# Pooled ones (Stunning Strike) stay a button — the pool is the player's to spend.
func _hit_riders(attacker, target) -> void:
	for v in attacker.verbs:
		if v["kind"] == "save_effect" and v.get("trigger", "") == "on_weapon_hit" and not v.has("pool"):
			_save_effect(attacker, v, target)

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
	if v.get("concentration", false):
		if caster.has("concentrating"):
			log.append("%s drops concentration on their earlier spell." % caster.cname)
		caster.statuses["concentrating"] = v["spell"]
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

# --- conditions (data/effects/conditions.json) --------------------------
#
# One reader; every resolution point below asks it instead of naming a status.
# exhaustion is the odd shape: {"level": N} with per-level numbers, scaled here.

func _cond_effects(c) -> Array:
	var out: Array = []
	for id in c.statuses:
		var e: Dictionary = Effects.condition(id)
		if e.is_empty():
			e = ENGINE_CONDS.get(id, {})
		if e.is_empty():
			continue
		if e.has("per_level"):
			var lvl := exhaustion_level(c)
			if lvl <= 0:
				continue
			var scaled := {}
			for k in e["per_level"]:
				scaled[k] = int(e["per_level"][k]) * lvl
			out.append(scaled)
		else:
			out.append(e)
	return out

func hexes_from_ft(ft: int) -> int:
	return roundi(float(ft) / FT_PER_HEX)

func exhaustion_level(c) -> int:
	var s = c.statuses.get("exhaustion", {})
	return int(s.get("level", 0)) if s is Dictionary else 0

# Every d20 the creature rolls: attacks and saves (this engine has no other checks).
func _d20_penalty(c) -> int:
	var p := 0
	for e in _cond_effects(c):
		p += int(e.get("d20_penalty", 0))
	return p

# The one entry point that inflicts exhaustion. Level `max_level` kills.
func gain_exhaustion(c, levels := 1) -> int:
	var lvl := exhaustion_level(c) + levels
	c.statuses["exhaustion"] = {"level": lvl}
	log.append("%s gains exhaustion (level %d)." % [c.cname, lvl])
	if lvl >= int(Effects.condition("exhaustion").get("max_level", 6)):
		log.append("%s collapses, spent." % c.cname)
		_kill(c)
	return lvl

# Apply a named condition. charmed/frightened remember who caused them.
func apply_condition(target, cond: String, source = null, duration := "") -> void:
	if cond == "exhaustion":
		gain_exhaustion(target)
		return
	var e := Effects.condition(cond)
	var s := {}
	if source != null and (e.get("cannot_target_source", false) or e.get("cannot_approach_source", false)):
		s["source"] = source
	if duration == "round":
		s["until_tick"] = _tick()
	target.statuses[cond] = s if not s.is_empty() else true

func _source_of(c, key: String):
	for id in c.statuses:
		if Effects.condition(id).get(key, false) and c.statuses[id] is Dictionary:
			return c.statuses[id].get("source")
	return null

# Movement left this turn after speed-zeroing conditions and exhaustion.
func move_left(c) -> int:
	var mv := int(c.econ.get("move_left", 0))
	for e in _cond_effects(c):
		if e.has("speed") and int(e["speed"]) == 0:
			return 0
		mv -= hexes_from_ft(int(e.get("speed_penalty_ft", 0)))
	return maxi(0, mv)

func _no_economy(actor, cost: String) -> bool:
	var key: String = {"action": "no_action", "bonus": "no_bonus", "reaction": "no_reaction"}.get(cost, "")
	if key == "":
		return false
	for e in _cond_effects(actor):
		if e.get(key, false):
			return true
	return false

# --- attack ------------------------------------------------------------

func _attack_mode(attacker, target, opts := {}) -> int:
	var adv = false
	var dis = false
	if attacker.ranged and adjacent_enemy(attacker):
		dis = true
	for e in _cond_effects(target):
		var a = e.get("attacks_against", "")
		if a is Dictionary:
			a = a.get("ranged" if attacker.ranged else "melee", "")
		adv = adv or a == "adv"
		dis = dis or a == "dis"
	for e in _cond_effects(attacker):
		var o = e.get("own_attacks", "")
		adv = adv or o == "adv"
		dis = dis or o == "dis"
	var vx = attacker.statuses.get("vex")
	if vx is Dictionary and vx.get("target") == target:
		adv = true   # weapon mastery Vex
	if opts.get("advantage", false):
		adv = true
	# passive attack_modifier: Pack Tactics and friends, no button, no action
	for v in attacker.verbs:
		if v["kind"] == "attack_modifier" and v.get("trigger", "") == "passive" \
				and v.get("self", "") == "adv" and _requires_met(attacker, target, Dice.combine(adv, dis), v.get("requires", [])):
			adv = true
	return Dice.combine(adv, dis)

# Paralyzed/unconscious: any melee hit from within reach is a crit.
func _auto_crit(attacker, target) -> bool:
	if attacker.ranged:
		return false
	for e in _cond_effects(target):
		var ft := int(e.get("auto_crit_within_ft", 0))
		if ft > 0 and Hex.distance(attacker.pos, target.pos) <= hexes_from_ft(ft):
			return true
	return false

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
			"ally_adjacent_to_target":
				if not allies_of(attacker).any(func(a): return Hex.distance(a.pos, target.pos) <= 1):
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

# Reactions stay auto-resolved with zero prompts (spec §7). Returns the damage
# after any reaction that modifies it. One trigger is authored today; another is
# a features.json entry plus a call site.
func _react(c, trigger: String, dmg: int) -> int:
	for v in c.verbs:
		if v["kind"] != "reaction" or v.get("trigger", "") != trigger:
			continue
		if not _spend(c, "reaction"):
			continue
		if v.get("halve_damage", false):
			dmg = dmg / 2
			log.append("%s — %s, halving the blow." % [c.cname, v["label"]])
	return dmg

# Damage a held buff adds to a melee swing (Rage).
func _buff_damage(attacker) -> int:
	var n := 0
	for s in attacker.statuses.values():
		if s is Dictionary:
			n += int(s.get("bonus_damage", 0))
	return n

func resolve_attack(attacker, target, opts := {}) -> Dictionary:
	var oa: bool = opts.get("opportunity", false)
	var free: bool = oa or opts.get("free", false)   # Cleave's second swing costs nothing
	if _no_economy(attacker, "action" if not free else "reaction"):
		return {"error": "cannot act"}   # ai.gd swings without asking available()
	if _source_of(attacker, "cannot_target_source") == target:
		return {"error": "charmed"}
	if not free and not in_reach(attacker, target):
		return {"error": "out of range"}
	if not free:
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
	var insp: int = _consume_inspired(attacker)
	var atk_bonus: int = int(opts.get("atk_bonus", attacker.atk_bonus)) + insp - _d20_penalty(attacker)
	var total: int = nat + atk_bonus
	var ac = effective_ac(target)
	var crit: bool = nat >= attacker.crit_range
	var hit: bool = crit or (nat != 1 and total >= ac)
	if hit and not crit and _auto_crit(attacker, target):
		crit = true
	var out = {
		"attacker": attacker.cname, "target": target.cname,
		"nat": nat, "dice": r.dice, "bonus": atk_bonus, "total": total, "ac": ac,
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
	if hit:
		out.damage = _react(target, "hit_by_attack", out.damage)
	attacker.statuses.erase("hidden")
	attacker.statuses.erase("sapped")   # Sap is spent on the next roll, hit or miss
	var vx = attacker.statuses.get("vex")
	if vx is Dictionary and vx.get("target") == target:
		attacker.statuses.erase("vex")
	if not free:
		attacker.statuses.erase("helped")  # the granted advantage is spent
	_log_attack(out, oa)
	if hit:
		_apply_damage(target, out.damage, _damage_type(attacker))
		if target.conscious():
			_hit_riders(attacker, target)
		bark(attacker, "kill" if target.is_dead() else ("crit" if crit else "hit"))
	if not opts.get("no_mastery", false):
		_mastery_rider(attacker, target, hit)
	return out

# --- weapon mastery (2024 PHB) ----------------------------------------
#
# pass_gear.gd already wrote the mastery id onto the attack only if the wielder
# knows it ("" otherwise), so this is one reader off attacks[0] — the same
# attack combat.gd swings with everywhere else. Auto-applied, no prompt (§2),
# same call T14's conditions made. Nick rides no hit at all: adapter.gd reads the
# main hand's mastery when it builds the off-hand verb and prices that verb "free"
# + once-per-turn, folding it into the Attack action (T24).

func _mastery(c) -> String:
	return str(c.attacks[0].get("mastery", "")) if not c.attacks.is_empty() else ""

# The weapon's damage modifier (Graze's damage, the part Cleave's second swing drops).
func _weapon_mod(c) -> int:
	return int(c.attacks[0].get("dmg_bonus", 0)) if not c.attacks.is_empty() else 0

func _weapon_dice(c) -> String:
	if c.attacks.is_empty():
		return c.damage
	var a: Dictionary = c.attacks[0]
	return "%dd%d" % [int(a.get("dice_count", 1)), int(a.get("dice_sides", 6))]

# No weapon carries a save DC of its own; a proficient wielder's atk_bonus is
# already ability mod + proficiency, so 8 + atk_bonus is the RAW formula.
func _weapon_dc(c) -> int:
	return 8 + c.atk_bonus

# Statuses that should survive the bearer's next turn expire a full cycle out —
# _expire_conditions only runs at the bearer's own begin_turn, so "round" (this
# tick) would clear them before they ever bite.
func _next_round_tick() -> int:
	return _tick() + maxi(1, order.size())

func _mastery_rider(attacker, target, hit: bool) -> void:
	var m := _mastery(attacker)
	if m == "" or hit == (m == "graze"):
		return   # graze rides a miss, every other mastery rides a hit
	match m:
		"graze":
			var dmg := _weapon_mod(attacker)
			if dmg > 0:
				log.append("%s grazes %s for %d." % [attacker.cname, target.cname, dmg])
				_apply_damage(target, dmg, _damage_type(attacker))
		"cleave":
			for o in enemies_of(attacker):
				if o != target and Hex.distance(o.pos, target.pos) <= 1 and in_reach(attacker, o):
					log.append("%s cleaves on into %s." % [attacker.cname, o.cname])
					resolve_attack(attacker, o, {"free": true, "no_mastery": true,
						"damage": _weapon_dice(attacker)})
					break
		"push":
			# ponytail: Huge+ shrug it off; bestiary size is the only size model here.
			if target.conscious() and not target.size in ["Huge", "Gargantuan"]:
				if _push_away(attacker, target, hexes_from_ft(10)) > 0:
					log.append("%s drives %s back." % [attacker.cname, target.cname])
		"sap":
			if target.conscious():
				target.statuses["sapped"] = {"until_tick": _next_round_tick()}
				log.append("%s saps %s — disadvantage on its next attack." % [attacker.cname, target.cname])
		"slow":
			if target.conscious():
				target.statuses["slowed"] = {"until_tick": _next_round_tick()}   # refresh, never stack
				log.append("%s slows %s — -10 ft of speed." % [attacker.cname, target.cname])
		"topple":
			if target.conscious():
				var dc := _weapon_dc(attacker)
				if _saving_throw(target, dc, "con"):
					log.append("%s keeps its feet (DC %d CON)." % [target.cname, dc])
				else:
					apply_condition(target, "prone")
					log.append("%s topples %s prone (DC %d CON)." % [attacker.cname, target.cname, dc])
		"vex":
			if target.conscious():
				attacker.statuses["vex"] = {"target": target, "until_tick": _next_round_tick()}
				log.append("%s has %s's measure — advantage on the next swing." % [attacker.cname, target.cname])

func _push_away(attacker, target, hexes: int) -> int:
	var moved := 0
	for _i in hexes:
		var dest: Vector2i = target.pos + Hex.direction_to(attacker.pos, target.pos)
		if not passable(dest) or not _hex_free(dest, target):
			break
		target.pos = dest
		moved += 1
	return moved

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
	for e in _cond_effects(c):
		if e.get("resist_all", false):
			return true
	if dtype == "":
		return false
	for s in c.statuses.values():
		if s is Dictionary and dtype in s.get("resist", []):
			return true
	return false

func _apply_damage(target, dmg: int, dtype := "") -> void:
	if _resists(target, dtype):
		dmg = dmg / 2
	if dmg > 0 and target.has("concentrating"):
		if not _saving_throw(target, maxi(10, dmg / 2), "con"):
			log.append("%s loses concentration." % target.cname)
			target.statuses.erase("concentrating")
	if target.is_down():
		target.death_f += 1 if dmg > 0 else 0
		if target.death_f >= 3:
			_kill(target)
		return
	var before: int = target.hp
	target.hp -= dmg
	# bark only on the crossing into the last quarter, not every hit below it
	if target.hp > 0 and before * 4 >= target.max_hp and target.hp * 4 < target.max_hp:
		bark(target, "low_hp")
	if target.hp <= 0:
		var overkill: int = -target.hp
		target.hp = 0
		if target.team == "party":
			downed[target.id] = true
		if target.team == "foe" or overkill >= target.max_hp:
			_kill(target)
		else:
			target.statuses["down"] = true
			target.statuses.erase("prone")
			target.death_s = 0
			target.death_f = 0
			log.append("%s falls unconscious." % target.cname)
			bark(target, "down")

func _kill(c) -> void:
	c.statuses["dead"] = true
	c.statuses.erase("down")
	c.hp = 0
	log.append("%s is dead." % c.cname)
	bark(c, "down")
	if _team_out(c.team):   # that was the last of them — the winners get a word in
		for w in combatants:
			if w.team != c.team and w.conscious():
				bark(w, "victory")
				break

func _death_save(c) -> void:
	var r = Dice.d20(rng)
	if r.nat == 20:
		c.statuses.erase("down")
		c.death_s = 0
		c.death_f = 0
		c.hp = 1
		log.append("%s's eyes snap open — nat 20, up at 1 HP!" % c.cname)
		_survived_down(c)
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
		_survived_down(c)
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
	if revived:
		_survived_down(c)

# T19: a hero who went to 0 HP and came back — stabilised, nat-20'd, or healed.
func _survived_down(c) -> void:
	if c.team == "party":
		Ach.unlock("death_save")

# --- movement -------------------------------------------------------

# Hexes reachable by `mover` with the move points left this turn.
func move_field(mover) -> Dictionary:
	var field := Hex.reachable(passable, mover.pos, move_left(mover), _blockers(mover), _rough())
	# frightened: you can never end a step closer to what scares you
	var fear = _source_of(mover, "cannot_approach_source")
	if fear != null:
		var d0 := Hex.distance(mover.pos, fear.pos)
		for h in field.keys():
			if Hex.distance(h, fear.pos) < d0:
				field.erase(h)
	return field

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
			var haz := adjacent_hazard(target)
			if haz.is_empty():
				return {"success": true}
			var notation: String = String(haz["hazard"].get("dice", "2d6"))
			var burn = Dice.roll(rng, notation)
			log.append("%s shoves %s into the %s — %s = %d fire." % [attacker.cname, target.cname,
				haz["type"], notation, burn])
			_apply_damage(target, burn)
	return {"success": true}

# A barrel or crate: one action, no roll, the hex clears. Explosive ones burst.
func act_smash(actor) -> Dictionary:
	var o := smashable_near(actor)
	if o.is_empty():
		return {"error": "nothing to smash"}
	log.append("%s smashes the %s apart." % [actor.cname, o["type"]])
	destroy_object(o)
	return {"smashed": o["type"]}

func _saving_throw(c, dc: int, ability := "dex", ignore_cover := false) -> bool:
	var adv: bool = c.has("dodging")
	var dis := false
	for e in _cond_effects(c):
		if ability in e.get("auto_fail_saves", []):
			log.append("%s can't resist — the %s save fails automatically." % [c.cname, ability.to_upper()])
			return false
		dis = dis or e.get("saves", {}).get(ability, "") == "dis"
	var bonus: int = int(c.saves.get(ability, 0)) + _consume_inspired(c) - _d20_penalty(c)
	if is_cover(c.pos) and not ignore_cover:
		bonus += 2
	return Dice.d20(rng, Dice.combine(adv, dis)).nat + bonus >= dc

# Bardic Inspiration (and anything shaped like it): a one-shot die added to the
# bearer's own next attack or save, auto-applied — this engine has no reaction
# prompts (combat-design.md §2), so "would you like to use it?" isn't a question.
func _consume_inspired(c) -> int:
	if not c.has("inspired"):
		return 0
	var sides: int = int(c.statuses["inspired"].get("dice_sides", 6))
	c.statuses.erase("inspired")
	var bonus: int = rng.roll_die(sides)
	log.append("%s's inspiration adds %d." % [c.cname, bonus])
	return bonus

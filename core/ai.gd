# Monster AI = the literal priority list from combat-design.md §7, on the hex grid.
# Also a simple auto-pilot for the party, used by headless playthrough / demo mode.
extends RefCounted

const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Dice = preload("res://core/dice.gd")

# combat-design.md §7 rule 5: foes won't execute a downed PC while they could
# instead engage a conscious one this turn. The difference between tense and
# feels-bad — flip to false to let monsters finish people off.
const MERCY := true

# A coroutine, but only on paper: the only thing below that can suspend is
# cb.offer_reactions(), and that returns without ever reaching an await unless
# somebody installed a reaction decider (scenes/main.gd does, when the player
# asked for prompts). It returns void precisely so the callers that don't —
# the whole headless suite, autoplay — can go on calling it as a bare statement
# and get the same straight-through turn they always got.
static func take_turn(cb, actor) -> void:
	if not actor.conscious():
		return
	if actor.team == "foe":
		await _foe_turn(cb, actor)
	else:
		_party_auto(cb, actor)

# --- hex movement helpers --------------------------------------------

static func _nearest(from: Vector2i, list: Array):
	var best = null
	var best_d := 1 << 30
	for c in list:
		var d: int = Hex.distance(from, c.pos)
		if d < best_d:
			best_d = d
			best = c
	return best

# Step as far as this turn's move points allow toward `goal`; returns nothing,
# mutates via cb.move_to. `score` picks the destination among reachable hexes.
# A hex inside a Wall of Fire or a Web costs this much score — a few hexes'
# worth, so a monster routes around a cloud and steps out of one it woke up in,
# but still wades through when the only way to its prey runs through it.
const ZONE_PENALTY := 4.0
# #156: a level of height is +2 to hit from, so every destination is worth this
# much per level before its own score is read.
#
# STRICTLY LESS THAN ONE, and that is the whole of the reasoning: every score
# callable below is in HEXES (-distance to the goal, or distance from what is
# chasing you), so a draw of 1.0 or more buys the high ground at the price of a
# hex of approach — permanently, since the monster re-scores from up there next
# turn and the shelf still wins. At 1.5 that is exactly what happened: monsters
# climbed the nearest shelf and stayed on it, fights stopped converging, and
# tests/drive_completionist.gd ran out of frames walking between towns with
# unfinished fights behind it. Below one it can only ever decide between hexes
# that are otherwise equally good, which is what it is for.
const HIGH_GROUND_DRAW := 0.35

static func _spot(cb, up: Dictionary, m, score: Callable, h: Vector2i) -> float:
	return score.call(h) - (ZONE_PENALTY if cb.zone_hurts(m, h) else 0.0) \
		+ HIGH_GROUND_DRAW * float(up.get(h, 0))

static func _move_by(cb, m, score: Callable, disengage := false) -> void:
	var field: Dictionary = cb.move_field(m)
	var up: Dictionary = cb.heights()   # once, not once per candidate hex
	var best: Vector2i = m.pos
	var best_s: float = _spot(cb, up, m, score, m.pos)
	for h in field:
		var s: float = _spot(cb, up, m, score, h)
		if s > best_s:
			best_s = s
			best = h
	if best != m.pos:
		cb.move_to(m, best, disengage)

# Could `m` land an attack on `c` this turn (already in range, or by moving)?
static func _can_engage(cb, m, c) -> bool:
	if cb.in_reach(m, c):
		return true
	for h in cb.move_field(m):
		var d: int = Hex.distance(h, c.pos)
		if m.ranged:
			if d > 1 and d <= m.atk_range:
				return true
		elif d <= m.reach:
			return true
	return false

# --- verb helpers: the AI shops the same list the UI renders ----------

static func _pick(cb, m, test: Callable) -> Dictionary:
	for v in cb.available(m):
		if test.call(v):
			return v
	return {}

static func _kind(cb, m, kind: String) -> Dictionary:
	return _pick(cb, m, func(v): return v["kind"] == kind)

# A cheap self-buff (Rage) and a heal at low HP: the whole of the AI's kit use.
static func _use_kit(cb, m) -> void:
	var buff := _kind(cb, m, "self_buff")
	if not buff.is_empty():
		cb.perform(m, buff)
	if m.hp * 2 <= m.max_hp:
		var sw := _kind(cb, m, "heal_self")
		if not sw.is_empty():
			cb.perform(m, sw)

# Don't web the already-webbed: a target carrying every condition a verb inflicts
# gains nothing from a second helping of it.
static func _redundant(c, v: Dictionary) -> bool:
	var conds: Array = v.get("conditions", [])
	return not conds.is_empty() and conds.all(func(cond): return c.has(cond))

# T21: a breath weapon / gaze / web is worth more than one swing, so a foe leads with
# an offensive verb off its own statblock instead of plain-attacking whenever one is
# legal. The whole rule, deliberately dumb (combat-design.md §10 risk 2 — no AI creep):
# available() already hides what's unaffordable or spent, condition-inflicting verbs
# go first, then first-eligible wins, aimed at the softest legal target.
# The BASIC verbs available() also offers (Shove &c.) stay out of it — that's tactics,
# not a special attack, and the party autopilot doesn't use them either.
static func _use_special(cb, m, targets: Array) -> bool:
	var verbs: Array = cb.available(m).filter(func(v):
		return v.get("targeting", "self") == "enemy" and not m.verb(v["id"]).is_empty())
	verbs.sort_custom(func(a, b):
		return a.get("conditions", []).size() > b.get("conditions", []).size())
	for v in verbs:
		var legal: Array = targets.filter(func(c):
			return cb.legal_target(m, v, c) and not _redundant(c, v))
		if legal.is_empty():
			continue
		legal.sort_custom(func(a, b): return a.hp < b.hp)
		await cb.offer_reactions(m, v, legal[0])
		cb.perform(m, v, legal[0])
		return true
	return false

# Hit `targets` (already in the caller's preference order) — the special first,
# the plain swing at the head of the list otherwise.
#
# The offer goes immediately before the blow, not after it: the resolver cannot
# stop to ask (see combat.gd's "being asked first"), so the moment before the
# action is committed is the last one at which the question can be put. The
# answer is therefore given against the hit chance rather than against the
# damage — and nothing is spent if the swing misses.
#
# One _strike is one Attack ACTION, which is however many swings
# attacks_per_action buys — a hobgoblin's Multiattack, a fighter's Extra Attack,
# the two a monk's Flurry banked. Taking one swing and returning left every one
# of those on the table: the resolver banked the rest in `attacks_left` and the
# turn ended with them unspent, so every multiattack monster in the bestiary
# fought as a single-attack monster.
#
# Re-targeted between swings rather than pounded into the same body: the second
# swing of a Multiattack should not be thrown at a corpse. The loop stops when
# the resolver says the economy is out, which is the same answer it gives the
# action bar.
static func _strike(cb, m, targets: Array) -> void:
	if await _use_special(cb, m, targets):
		return
	for _swing in MAX_SWINGS:
		var live: Array = targets.filter(func(c): return c.conscious() and cb.in_reach(m, c))
		if live.is_empty() or not m.conscious():
			return
		live.sort_custom(func(a, b): return a.hp < b.hp)
		await cb.offer_reactions(m, cb.attack_verb(), live[0])
		if cb.resolve_attack(m, live[0]).has("error"):
			return

# A guard on the loop above, not a rule: nothing in the game grants more than
# four swings, and a runaway would be an infinite turn rather than a wrong one.
const MAX_SWINGS := 6

# Walking distance to `goal`, not hex distance: a tree or a pillar between
# the two is a wall now (Encounter.SOLID_COVER), and scoring by the straight
# line parks a monster against it for the rest of the fight. Flooded once
# outward from the goal; a hex the flood never reached (walled off, or past
# the budget) falls back to the straight line, a long way behind.
static func _toward(cb, goal: Vector2i) -> Callable:
	var walk: Dictionary = Hex.reachable(cb.passable, goal, WALK_BUDGET, [], cb._rough(), cb.heights())
	return func(h: Vector2i) -> float:
		return -float(walk.get(h, WALK_BUDGET + Hex.distance(h, goal))) \
			+ (SIGHT_DRAW if cb.has_line_of_sight(h, goal) else 0.0)

const WALK_BUDGET := 99   # longer than any board is wide, many times over
# A line to the goal is worth a step and a half of walking. Walls made a hex
# one step nearer on foot and blind the common case: a web-spitter stopped at
# (5,0), a step closer than (4,1) and with its line running off the board, and
# never used the web (test_ai). Under two steps, so a monster never walks the
# long way round only to look.
const SIGHT_DRAW := 1.5

static func _away(threats: Array) -> Callable:
	return func(h: Vector2i) -> float:
		var m := 1 << 30
		for t in threats:
			m = mini(m, Hex.distance(h, t.pos))
		return float(m)

# The aim for an area verb that catches the most foes net of allies — every
# enemy's hex (and, for a corner circle, each corner of it) is a candidate.
# null unless some aim nets at least two.
static func _best_area(cb, h, v: Dictionary):
	var best = null
	var best_net := 1
	var cands: Array = []
	for f in cb.enemies_of(h):
		if not f.conscious():
			continue
		if v["targeting"] == "corner":
			for k in 6:
				cands.append(Hex.corner(f.pos, k))
		else:
			cands.append(f.pos)
	for aim in cands:
		if not cb.legal_area(h, v, aim):
			continue
		var hexes: Array = cb.area_hexes(h, v, aim)
		var net: int = cb.enemies_of(h).filter(func(c): return c.conscious() and c.pos in hexes).size() \
			- cb.allies_of(h).filter(func(c): return c.conscious() and c.pos in hexes).size()
		if net > best_net:
			best_net = net
			best = aim
	return best

# The direction for a cone verb whose wedge catches the most foes net of allies,
# or ZERO unless some direction nets at least two. The cone half of _best_area,
# shared by the party autopilot and a foe caster.
static func _best_cone(cb, h, v: Dictionary) -> Vector2i:
	var best_dir := Vector2i.ZERO
	var best_net := 1
	for d in Hex.DIRS:
		var wedge := Hex.cone(h.pos, d, int(v.get("radius", 2)))
		var f: int = cb.enemies_of(h).filter(func(c): return c.pos in wedge).size()
		var a: int = cb.allies_of(h).filter(func(c): return c.pos in wedge).size()
		if f - a > best_net:
			best_net = f - a
			best_dir = d
	return best_dir

# --- foes ------------------------------------------------------------

# A shooter with an enemy adjacent fires at disadvantage. If one move can reach a
# hex that is clear of every PC and still within range of one, take it (eating
# the opportunity attack — a bow at full effect is worth more than a free swing
# avoided) and report true so the caller shoots instead of swinging point-blank.
# `reach` is how far it can still hit from: the bow's range for an archer (the
# default), the longest spell's for a caster.
static func _step_clear(cb, m, pcs: Array, reach := -1) -> bool:
	var best := Vector2i.ZERO
	var best_d := -1
	var r: int = m.atk_range if reach < 0 else reach
	for h in cb.move_field(m):
		var near := 1 << 30
		for c in pcs:
			near = mini(near, Hex.distance(h, c.pos))
		if near <= 1 or near > r:
			continue
		if near > best_d:   # the farthest still-in-range hex: the most room before they close again
			best_d = near
			best = h
	if best_d < 0:
		return false
	cb.move_to(m, best)
	return m.conscious()

static func _foe_turn(cb, m) -> void:
	# `illusion` (Invoke Duplicity's double) is out of the list rather than
	# merely unhittable. A foe that only refused the swing would still pick the
	# double first — it has 1 hp and the list sorts on hp — and lose its whole
	# turn to it, which makes the double far stronger than RAW's "Advantage
	# against creatures within 5 feet" and reads as the AI being broken.
	var pcs: Array = cb.combatants.filter(func(c): return c.team == "party" \
		and c.conscious() and not c.has("illusion") and not c.has("captive"))
	if pcs.is_empty():
		return
	if m.has("quarry") and _quarry_runs(cb, m, pcs):
		return
	_use_kit(cb, m)
	if m.caster and await _caster_turn(cb, m, pcs):
		return

	var adj: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= m.reach)
	if not adj.is_empty() and m.ranged and _step_clear(cb, m, pcs):
		adj = []   # an archer with someone in its face backs off first, then shoots (falls through)
	if not m.conscious():
		return     # the opportunity attack on the way out dropped it
	if not adj.is_empty():
		adj.sort_custom(func(a, b): return a.hp < b.hp if a.hp != b.hp else a.ac < b.ac)
		await _strike(cb, m, adj)
		if m.hp * 2 <= m.max_hp:
			# Nimble Escape and friends: a bonus-action Disengage, then back off
			var esc := _pick(cb, m, func(v): return v["kind"] == "disengage" and v["cost"] == "bonus")
			if not esc.is_empty():
				cb.perform(m, esc)
				_move_by(cb, m, _away(pcs), true)
		return

	# no conscious PC adjacent — a downed neighbour gets finished only if we
	# couldn't have engaged a conscious PC this turn (mercy rule, §7 rule 5)
	var downed_adj: Array = cb.combatants.filter(func(c):
		return c.team == "party" and c.is_down() and Hex.distance(c.pos, m.pos) <= m.reach)
	if not downed_adj.is_empty():
		if not MERCY or not pcs.any(func(c): return _can_engage(cb, m, c)):
			await cb.offer_reactions(m, cb.attack_verb(), downed_adj[0])
			cb.resolve_attack(m, downed_adj[0])
			return

	if m.ranged:
		# Kritch: keep clear, stay in range, shoot the softest target.
		# A target it can see, not only one in range: behind a wall is out of
		# the fight until somebody moves, and that somebody is the archer.
		var sees := func(c): return Hex.distance(c.pos, m.pos) <= m.atk_range \
			and Hex.distance(c.pos, m.pos) > 1 and cb.has_line_of_sight(m.pos, c.pos)
		var near = _nearest(m.pos, pcs)
		var d := Hex.distance(m.pos, near.pos)
		if d <= 1:
			_move_by(cb, m, _away(pcs), true)
		elif not pcs.any(sees):
			_move_by(cb, m, _toward(cb, near.pos))
		var shootable: Array = pcs.filter(sees)
		if not shootable.is_empty():
			shootable.sort_custom(func(a, b): return a.hp < b.hp)
			await _strike(cb, m, shootable)
		return

	# melee, nobody adjacent: close on the nearest PC, then swing if we arrived
	var target = _nearest(m.pos, pcs)
	_move_by(cb, m, _toward(cb, target.pos))
	var now: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= m.reach and c.conscious())
	if not m.conscious():
		return
	if not now.is_empty():
		now.sort_custom(func(a, b): return a.hp < b.hp)
		await _strike(cb, m, now)
	else:
		await _use_special(cb, m, pcs)   # closed, but not close enough to swing — a gaze still reaches

# --- the enemy caster (core/enemy_casters.gd) ----------------------------
#
# A statblock with real slots fights like one, in this order, and falls through
# to the melee logic below only if it cast nothing:
#   1. an enemy in its face: an area or cone that nets two or more is still the
#      best thing to do; failing that, a caster whose swing is worth more than
#      its best single-target spell (a cult fanatic's two blades) fights in
#      melee like the statblock it is — measured 2026-09-24, one that stepped
#      back to cast Command every turn fought worse than the plain fanatic —
#      and one whose swing is not (the mage's dagger) steps clear first, to a
#      hex still in spell range (the archer's _step_clear, the longest spell's
#      reach);
#   2. an area or a cone that nets two or more heroes (the autopilot's aims);
#   3. a control spell, unless it is already holding one — casting a second
#      concentration spell would only drop the first;
#   4. the spell that does the most damage on a legal target.
# Higher slots are tried first, so the fireball goes before the magic missile —
# the same order core/rules/power.gd prices a caster's casts in. Nothing legal
# from where it stands: walk the nearest hero's way until a spell reaches — no
# further (_keep_range, 2026-09-25) — and try once more.
static func _caster_turn(cb, m, pcs: Array) -> bool:
	var spells: Array = _castable(cb, m)
	if spells.is_empty():
		return false
	var reach := 1
	for v in spells:
		reach = maxi(reach, int(v.get("range", 1)))
	if pcs.any(func(c): return Hex.distance(c.pos, m.pos) <= m.reach):
		if _cast_area(cb, m, spells):
			return true
		if _swing_value(cb, m) >= _best_single(cb, m, spells):
			return false   # the melee logic below takes it from here
		_step_clear(cb, m, pcs, reach)
		if not m.conscious():
			return true
	if await _cast_best(cb, m):
		return true
	# walk until a spell reaches, not up to arm's length (_keep_range): the
	# longest single-target spell's range, the longest of any if it knows none
	var aim := 0
	for v in cb.all_verbs(m):   # the bar hides a spell with no hero in reach
		if v["kind"] == "spell" and v.get("targeting", "") == "enemy" and _payable(cb, m, v):
			aim = maxi(aim, int(v.get("range", 1)))
	_keep_range(cb, m, aim if aim > 1 else reach, pcs)
	if not m.conscious():
		return true
	return await _cast_best(cb, m)

static func _castable(cb, m) -> Array:
	var out: Array = cb.available(m).filter(func(v): return v["kind"] == "spell")
	out.sort_custom(func(a, b): return int(a.get("slot_level", 0)) > int(b.get("slot_level", 0)))
	return out

# An area or a cone that nets two or more, highest slot first; true if cast.
static func _cast_area(cb, m, spells: Array) -> bool:
	for v in spells:
		if not v.has("dice_count"):
			continue
		if v.get("targeting", "") in ["hex", "corner", "line"]:
			var aim = _best_area(cb, m, v)
			if aim != null:
				cb.perform(m, v, aim)
				return true
		elif v.get("targeting", "") == "direction":
			var dir := _best_cone(cb, m, v)
			if dir != Vector2i.ZERO:
				cb.perform(m, v, dir)
				return true
	return false

static func _avg_dmg(v: Dictionary) -> float:
	return (int(v["dice_count"]) * (int(v.get("dice_sides", 6)) + 1) / 2.0 + int(v.get("dice_bonus", 0))) \
		* int(v.get("rays", 1))

# The most a single-target damage spell it can cast right now would deal.
static func _best_single(cb, m, spells: Array) -> float:
	var best := 0.0
	for v in spells:
		if v.get("targeting", "") == "enemy" and v.has("dice_count"):
			best = maxf(best, _avg_dmg(v))
	return best

# What its Attack action is worth: every swing Multiattack buys, at the
# statblock's own damage.
static func _swing_value(cb, m) -> float:
	var swings := 1
	for v in m.verbs:
		if v["kind"] == "attacks_per_action":
			swings = maxi(swings, int(v.get("value", 1)))
	var p: Dictionary = Dice.parse(String(m.damage))
	return swings * (int(p["count"]) * (int(p["sides"]) + 1) / 2.0 + int(p["mod"]))

static func _cast_best(cb, m) -> bool:
	var spells: Array = _castable(cb, m)
	if _cast_area(cb, m, spells):
		return true
	var foes: Array = cb.enemies_of(m).filter(func(c): return c.conscious())
	foes.sort_custom(func(a, b): return a.hp < b.hp)
	for v in spells:
		if v.get("targeting", "") != "enemy" or v.get("conditions", []).is_empty():
			continue
		if v.get("concentration", false) and m.has("concentrating"):
			continue
		for t in foes:
			if cb.legal_target(m, v, t) and not _redundant(t, v):
				await cb.offer_reactions(m, v, t)
				cb.perform(m, v, t)
				return true
	var best := {}
	var best_d := 0.0
	for v in spells:
		if v.get("targeting", "") != "enemy" or not v.has("dice_count"):
			continue
		var d: float = _avg_dmg(v)
		if d > best_d and foes.any(func(t): return cb.legal_target(m, v, t)):
			best_d = d
			best = v
	if best.is_empty():
		return false
	for t in foes:
		if cb.legal_target(m, best, t):
			await cb.offer_reactions(m, best, t)
			cb.perform(m, best, t)
			return true
	return false

# hunt: the quarry runs for the far edge unless a hero is close enough that
# running is the worse choice — then it fights this turn like anybody else.
# Ending a turn on the edge is the escape (combat.gd's end_turn).
static func _quarry_runs(cb, m, pcs: Array) -> bool:
	if cb.objective_kind() != "hunt" or m.has("escaped"):
		return false
	for c in pcs:
		if Hex.distance(c.pos, m.pos) <= Objectives.QUARRY_CORNERED:
			return false
	var exit: Array = cb.objective.get("exit", [])
	if exit.is_empty():
		return false
	var away := _away(pcs)
	var score := func(h: Vector2i) -> float:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(h, e))
		return -3.0 * float(d) + float(away.call(h))
	_move_by(cb, m, score)
	return true

# --- party autopilot (demo / test only) ----------------------------

static func _party_auto(cb, h) -> void:
	if cb.enemies_of(h).is_empty():
		return
	_use_kit(cb, h)
	_font_up(cb, h)
	_heal_downed(cb, h)
	_party_action(cb, h)
	if h.conscious() and not cb.is_over():
		_bonus_after(cb, h)

# A downed ally in range comes first. A Bonus Action heal (Healing Word,
# Healing Light) before an action one, so the action is still there to swing.
static func _heal_downed(cb, h) -> void:
	var heals: Array = cb.available(h).filter(func(v): return v.has("heal_count") or v["kind"] == "heal_ally")
	heals.sort_custom(func(a, b): return _is_bonus(a) and not _is_bonus(b))
	for c in cb.combatants:
		if c.team != h.team or not c.is_down():
			continue
		for heal in heals:
			if _can_aim(cb, h, heal, c) and not cb.perform(h, heal, c).has("error"):
				return

# Whether `v` reaches ally `c`: an "allies" verb (Mass Healing Word) by its
# range — legal_target() speaks for one chosen creature, not a burst — a self
# one only its caster, anything else by legal_target().
static func _can_aim(cb, h, v: Dictionary, c) -> bool:
	match String(v.get("targeting", "ally")):
		"allies": return Hex.distance(h.pos, c.pos) <= int(v.get("range", 1))
		"self": return c == h
	return cb.legal_target(h, v, c)

static func _is_bonus(v: Dictionary) -> bool:
	return String(v.get("cost", "")) == "bonus"

# The action: where to stand, then the one thing the turn is for.
static func _party_action(cb, h) -> void:
	var foes: Array = cb.enemies_of(h)
	# the objective's one rule for where to stand (spec §7), before any chasing
	var moved := _objective_move(cb, h)
	var walking: bool = cb.objective_kind() == "breakout"

	# a caster keeps its distance (see _caster_bolt); anyone else closes if
	# nothing is in reach and it is not a shooter
	var bolt := _caster_bolt(cb, h)
	var reach: Array = foes.filter(func(c): return cb.in_reach(h, c))
	if not bolt.is_empty() and not moved and not walking:
		_keep_range(cb, h, int(bolt.get("range", 1)), foes)
		if not h.conscious():
			return
		reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))
	elif reach.is_empty() and not h.ranged and not moved:
		var t = _nearest(h.pos, foes)
		_move_by(cb, h, _toward(cb, t.pos))
		reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))
		# still short: a Bonus Action Dash (Cunning Action, Step of the Wind)
		# buys the rest of the way, and the action is still there to swing
		if reach.is_empty() and _bonus_basic(cb, h, "dash"):
			t = _nearest(h.pos, cb.enemies_of(h))
			if t != null:
				_move_by(cb, h, _toward(cb, t.pos))
			reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))

	# Metamagic: a leveled spell quickened onto the Bonus Action from wherever the
	# move above has put the caster; the action then goes on below exactly as it
	# would have, and combat keeps it off a second leveled spell (_quicken).
	if not walking and _quicken(cb, h):
		foes = cb.enemies_of(h)
		reach = foes.filter(func(c): return cb.in_reach(h, c))
		if not h.conscious() or cb.is_over() or foes.is_empty():
			return   # the Quickened spell finished it, or finished its caster

	# caster: an area spell (a hex, a corner circle, a line) where it nets 2+ foes
	# ...that actually hurts: Faerie Fire and friends are the player's call, not a nuke
	var area := _pick(cb, h, func(v): return v.get("targeting", "") in ["hex", "corner", "line"] and v.has("dice_count"))
	if not area.is_empty() and not walking:   # a breakout doesn't stop to nuke what it's walking past
		var aim = _best_area(cb, h, area)
		if aim != null:
			cb.perform(h, area, aim)
			return

	# caster: a cone spell if the wedge catches 2+ foes and no ally
	var cone := _pick(cb, h, func(v): return v.get("targeting", "") == "direction" and v.has("dice_count"))
	if not cone.is_empty() and not walking:   # same rule: no stopping to cast on the way out
		var best_dir := _best_cone(cb, h, cone)
		if best_dir != Vector2i.ZERO:
			cb.perform(h, cone, best_dir)
			return

	var targets: Array = reach if not reach.is_empty() else foes
	if targets.is_empty():
		return
	if cb.objective_kind() == "breakout" and reach.is_empty():
		return   # heading for the road: swing only at what is already in the way
	if cb.objective_kind() == "hunt":
		var q: Array = reach.filter(func(c): return c.has("quarry"))
		if not q.is_empty():
			targets = q
	targets.sort_custom(func(a, b): return a.hp < b.hp)
	# a caster casts: at the weakest foe the spell reaches (the quarry first on a
	# hunt), whether or not a fist would reach one too
	if not bolt.is_empty():
		var aimed: Array = foes.filter(func(c): return c.conscious() and cb.legal_target(h, bolt, c))
		aimed.sort_custom(func(a, b): return a.hp < b.hp)
		if cb.objective_kind() == "hunt":
			var q: Array = aimed.filter(func(c): return c.has("quarry"))
			if not q.is_empty():
				aimed = q
		if not aimed.is_empty():
			_twin(cb, h, bolt, foes)
			cb.perform(h, bolt, aimed[0])
			return
	if cb.in_reach(h, targets[0]):
		_swing_all(cb, h, targets)
		return
	# no weapon reach: a single-target attack spell (a cantrip needs no slot)
	bolt = _pick(cb, h, func(v): return v["kind"] == "spell" and v.get("targeting", "") == "enemy" and v.has("dice_count"))
	if not bolt.is_empty() and cb.legal_target(h, bolt, targets[0]):
		_twin(cb, h, bolt, foes)
		cb.perform(h, bolt, targets[0])

# --- casters keep their distance (2026-09-25) ---------------------------
#
# Before this the autopilot closed on anything that was not a shooter, so a
# sorcerer with no bow walked up to the nearest foe and ended its spell turns
# punching it: the bolt was thrown only when the walk fell short. Every caster
# sweep read a caster weaker than a player plays one (the measured pass's Still
# open, docs/plan/2026-09-25-measured-pass.md).
#
# A CASTER, for this purpose, is a hero whose best option this turn is a spell
# with range: the single-target damage spell the autopilot would throw (the
# first one on the bar that reaches past arm's length, as it always picked)
# deals more on average than its whole Attack action does — every swing Extra
# Attack buys, plus the once-a-turn riders a hit carries (Sneak Attack, a
# Dreadful Strike), so a rogue or a paladin stays at the front. Averages, not
# odds: a save-for-nothing Sacred Flame and a to-hit mace are compared as dice.
# A tie goes to the swing, so a level-3 cleric with a mace fights as before, and
# the same cleric at level 5, whose cantrip has doubled, stands back.
#
# A caster then (_keep_range): stands where the spell reaches a foe it can see,
# as far from the nearest foe as that allows, and never pays an opportunity
# attack to get there. Pinned in a foe's reach it stays and casts — spell
# attacks carry no penalty for a foe beside you in this engine, so a free swing
# is all a step would buy — unless a Bonus Action Disengage is on its bar
# (Cunning Action), which buys the step for nothing. Out of range of everything
# it walks the nearest foe's way, and stops at the first hex the spell reaches
# from rather than at arm's length. And it casts at the weakest foe the spell
# reaches instead of swinging at whatever is beside it.
#
# The enemy caster (_caster_turn) walks in the same way when nothing it knows
# reaches from where it stands. Misty Step is not spent on it: it would cost a
# slot and, under the 2024 rule, the turn's leveled spell.

# The spell `h` would throw this turn if it is a caster (above), or {}. Read
# off every verb it could pay for, not cb.available(): the bar hides a spell
# with no foe in reach, and a caster out of range is exactly the one that has
# to know what its range is before it walks.
static func _caster_bolt(cb, h) -> Dictionary:
	for v in cb.all_verbs(h):
		if v["kind"] == "spell" and v.get("targeting", "") == "enemy" and v.has("dice_count") \
				and not v.has("heal_count") and String(v.get("cost", "")) == "action" \
				and int(v.get("range", 1)) > 1 and _payable(cb, h, v):
			return v if _avg_dmg(v) > _swing_value(cb, h) + _rider_value(h) else {}
	return {}

# Everything combat._offerable asks of a spell except that a foe be in reach:
# a button, affordable, its slot payable and allowed this turn.
static func _payable(cb, h, v: Dictionary) -> bool:
	var cv: Dictionary = cb._cast_view(h, v)
	if not cb.is_button(h, cv) or not cb.can_afford(h, cv) or cb._buff_flag(h, "no_attack"):
		return false
	if cv.has("pool") and h.pool_left(cv["pool"]) <= 0:
		return false
	return int(cv.get("slot_level", 0)) <= 0 or (cb.can_pay_spell(h, cv) and cb._leveled_spell_allowed(h, cv))

# The once-a-turn dice a weapon hit adds (combat._passive_damage's list), at
# their average: Sneak Attack, a goblin's Surprise Attack, Dreadful Strike.
static func _rider_value(h) -> float:
	var out := 0.0
	for v in h.verbs:
		if v["kind"] == "passive_damage" and String(v.get("trigger", "")) == "on_weapon_hit":
			out += int(v.get("dice_count", 0)) * (int(v.get("dice_sides", 6)) + 1) / 2.0 + int(v.get("dice_bonus", 0))
	return out

# Stand where a spell of range `r` reaches one of `foes` it can see, as far from
# the nearest of them as that allows, without provoking. `foes` is the caller's
# list of who counts (the party's enemies, or a foe caster's heroes). Ties keep
# the hex it stands on, then the move field's own order, so the same board
# walks the same way on both co-op peers.
static func _keep_range(cb, m, r: int, foes: Array) -> void:
	var live: Array = foes.filter(func(c): return c.conscious())
	if live.is_empty():
		return
	var sees := func(x: Vector2i) -> bool:
		return live.any(func(f): return Hex.distance(x, f.pos) <= r and cb.has_line_of_sight(x, f.pos))
	var up: Dictionary = cb.heights()
	var room := _away(live)
	var here: float = _spot(cb, up, m, room, m.pos) if sees.call(m.pos) else -INF
	var field: Dictionary = cb.move_field(m)
	var cands: Array = []   # [score, flood order, hex]
	var i := 0
	for x in field:
		if sees.call(x):
			var s: float = _spot(cb, up, m, room, x)
			if s > here:
				cands.append([s, i, x])
		i += 1
	if cands.is_empty():
		if here == -INF:   # nowhere in this walk reaches: head for the nearest foe
			_move_by(cb, m, _toward(cb, _nearest(m.pos, live).pos))
		return
	cands.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var pinned: bool = not m.has("disengaged") and not m.has("hidden") and live.any(func(f): \
		return Hex.distance(f.pos, m.pos) <= f.reach and cb.can_spend(f, "reaction"))
	if pinned:
		# Every hex that is better is out of the pinning foe's reach: only a
		# free Disengage buys the step.
		if _bonus_basic(cb, m, "disengage"):
			cb.move_to(m, cands[0][2], true)
		return
	for c in cands:
		if cb.provokers_for(m, c[2]).is_empty():
			cb.move_to(m, c[2])
			return

# --- Metamagic (the design audit §7.4) --------------------------------
#
# The autopilot arms two of the five options core/metamagic.gd's BUILT lists,
# so a sweep can see what they are worth: before this nothing armed any, and
# Quickened is exactly the action-economy lever core/scaler.gd's header ranks
# first. Careful, Subtle and Seeking are left to a player.
#   Quickened  a leveled damage spell that can be aimed this turn goes out as
#              the Bonus Action, cast from wherever _party_action's move has put
#              the caster, and the action then does what it would have done
#              anyway — the swing or the cantrip, since combat refuses a second
#              leveled spell, as 2024 does. The turn's movement and the action's
#              rules are untouched, so what a sweep sees is the option and
#              nothing else. Armed only when that spell is cast straight after,
#              so the points never ride a cantrip. Innate Sorcery's Bonus Action
#              (_use_kit) comes first on the turn it is pressed.
#   Twinned    armed just before a single-target spell that upcasts for another
#              target, with a second foe standing (_party_action's bolt). Every
#              such spell in data/effects/spells.json today is a control spell
#              (Hold Person, Command, the charms), which the autopilot never
#              casts, so under autoplay it is inert; it is here so that the day
#              a damage spell twins, or the autopilot throws a lock, it is used.
# An option armed and not taken is refunded at the turn's end
# (combat._refund_metamagic), so neither can waste a point.
static func _quicken(cb, h) -> bool:
	if int(h.econ.get("bonus", 0)) <= 0 or h.econ.get("cast_leveled_spell", false):
		return false
	var arm := _metamagic(cb, h, "quickened")
	if arm.is_empty():
		return false
	var foes: Array = cb.enemies_of(h)
	var leveled: Array = cb.available(h).filter(func(v): return v["kind"] == "spell" \
		and int(v.get("slot_level", 0)) > 0 and String(v.get("cost", "")) == "action" and v.has("dice_count"))
	# _party_action's own order: an area that nets two, a cone that does, and
	# only then one foe — so the points never turn a Burning Hands into an Orb.
	for shape in [["hex", "corner", "line"], ["direction"], ["enemy"]]:
		for v in leveled:
			if not String(v.get("targeting", "")) in shape:
				continue
			var aim = _aim(cb, h, v, foes)
			if aim == null:
				continue
			if cb.perform(h, arm).has("error"):
				return false
			return not cb.perform(h, v, aim).has("error")
	return false

static func _twin(cb, h, v: Dictionary, foes: Array) -> void:
	if cb._twin_step(v) <= 0 or foes.filter(func(c): return c.conscious()).size() < 2:
		return
	var arm := _metamagic(cb, h, "twinned")
	if not arm.is_empty():
		cb.perform(h, arm)

# The Metamagic button for `option`, {} if this hero cannot press it now
# (not known, points short, one already armed).
static func _metamagic(cb, h, option: String) -> Dictionary:
	return _pick(cb, h, func(v): return v["kind"] == "metamagic" and String(v.get("option", "")) == option)

# Where `v` would go this turn by _party_action's own rules, null if nowhere is
# worth it: an area where it nets two foes, a cone likewise, else the weakest
# foe it can legally reach.
static func _aim(cb, h, v: Dictionary, foes: Array):
	match String(v.get("targeting", "")):
		"hex", "corner", "line":
			return _best_area(cb, h, v)
		"direction":
			var d := _best_cone(cb, h, v)
			return d if d != Vector2i.ZERO else null
		"enemy":
			var ok: Array = foes.filter(func(c): return c.conscious() and cb.legal_target(h, v, c))
			ok.sort_custom(func(a, b): return a.hp < b.hp)
			return ok[0] if not ok.is_empty() else null
	return null

# Every swing the economy holds, re-targeted between them — the Attack action's
# Extra Attack, and whatever a Bonus Action banked on top (Flurry of Blows, War
# Priest). One resolve_attack and a return used to leave all of those unswung:
# a level-5 fighter fought as a level-4 one. `targets` is the preference order
# (quarry, then the weakest); only the ones still standing in reach are swung at.
static func _swing_all(cb, h, targets: Array) -> void:
	for _swing in MAX_SWINGS:
		if not h.conscious() or cb.is_over():
			return
		var live: Array = targets.filter(func(c): return c.conscious() and cb.in_reach(h, c))
		if live.is_empty():
			live = cb.enemies_of(h).filter(func(c): return c.conscious() and cb.in_reach(h, c))
			live.sort_custom(func(a, b): return a.hp < b.hp)
		if live.is_empty():
			return
		if cb.resolve_attack(h, live[0]).has("error"):
			return

# --- the Bonus Action --------------------------------------------------
#
# The autopilot's second thing each turn, wherever one is reasonable. Before
# this it only ever spent one by accident of _use_kit (Rage, Second Wind): a
# monk never flurried, a rogue never hid, a cleric never put up Shield of Faith,
# a bard never inspired anyone. The rules, first that applies:
#
#   1. more swings — Flurry of Blows, War Priest, an off-hand attack — when a
#      foe is still in reach to take them
#   2. a heal on an ally at a third of their HP or less
#   3. a Bonus Action spell that lasts (Shield of Faith, Magic Weapon, Hunter's
#      Mark, Spiritual Weapon) when it is not already up and would not end a
#      concentration already held; a smite-like one (Ensnaring Strike) on a foe
#      in reach
#   4. Bardic Inspiration on an ally in the thick of it; a summon (Invoke
#      Duplicity) when none stands
#   5. getting out: at a third of HP or less with a foe adjacent — Misty Step
#      away, or Disengage and walk, or Patient Defense's Dodge
#   6. a rogue out of reach of everything hides, for Advantage next turn
#
# Every one comes off cb.available(), the list the bar renders, so the 2024
# rule that a Bonus Action spell and a leveled action spell never share a turn
# is the resolver's to enforce, not this function's.
const BONUS_TRIES := 4

static func _bonus_after(cb, h) -> void:
	for _try in BONUS_TRIES:
		if int(h.econ.get("bonus", 0)) <= 0 or not h.conscious() or cb.is_over():
			return
		if not _one_bonus(cb, h):
			return

static func _one_bonus(cb, h) -> bool:
	var bonus: Array = cb.available(h).filter(_is_bonus)
	if bonus.is_empty():
		return false
	var foes: Array = cb.enemies_of(h)
	var in_reach: Array = foes.filter(func(c): return c.conscious() and cb.in_reach(h, c))
	var adjacent: Array = foes.filter(func(c): return c.conscious() and Hex.distance(h.pos, c.pos) <= 1)
	var low: bool = h.hp * 3 <= h.max_hp
	# 1. more swings
	if not in_reach.is_empty() and not low:
		for v in bonus:
			if v["kind"] == "grant_action" and int(v.get("extra_attacks", 0)) > 0:
				if not cb.perform(h, v).has("error"):
					_swing_all(cb, h, in_reach)
					return true
			if v["kind"] == "offhand_attack":
				var t = _weakest(in_reach.filter(func(c): return cb.legal_target(h, v, c)))
				if t != null and not cb.perform(h, v, t).has("error"):
					return true
	# 2. a heal on someone badly hurt (the downed were seen to before the action)
	for v in bonus:
		if not (v.has("heal_count") or v["kind"] in ["heal_ally", "heal_self"]):
			continue
		var who = _hurt_ally(cb, h, v)
		if who != null and not cb.perform(h, v, who).has("error"):
			return true
	# 3. a spell that lasts, or a smite-like one on a foe in reach
	for v in bonus:
		if v["kind"] != "spell":
			continue
		if String(v.get("targeting", "")) == "enemy":
			if v.has("heal_count"):
				continue
			var t = _weakest(in_reach.filter(func(c): return cb.legal_target(h, v, c) and not _redundant(c, v)))
			if t != null and not cb.perform(h, v, t).has("error"):
				return true
			continue
		if not (v.has("buff") or v.has("summon") or v.has("temp_count")):
			continue   # a heal is rule 2's, when someone needs it; nothing else lasts
		if v.get("concentration", false) and h.has("concentrating"):
			continue   # would end the spell already held
		var t = _buff_target(cb, h, v)
		if t == null:
			continue
		if not cb.perform(h, v, t).has("error"):
			return true
	# 4. inspiring an ally, a summon
	for v in bonus:
		if v["kind"] == "ally_buff":
			var t = _buff_target(cb, h, v)
			if t != null and not cb.perform(h, v, t).has("error"):
				return true
		if v["kind"] == "summon" and not foes.is_empty():
			if not cb.perform(h, v).has("error"):
				return true
	# 5. getting out
	if low and not adjacent.is_empty():
		for v in bonus:
			if v["kind"] == "spell" and v.get("teleport", false):
				var dest = _escape_hex(cb, h, v, foes)
				if dest != null and not cb.perform(h, v, dest).has("error"):
					return true
		if _bonus_basic(cb, h, "disengage"):
			_move_by(cb, h, _away(foes), true)
			return true
		if _bonus_basic(cb, h, "dodge"):
			return true
	# 6. a rogue with nothing in reach of it hides for next turn's Advantage
	if adjacent.is_empty() and _bonus_basic(cb, h, "hide"):
		return true
	return false

# A basic verb (dash, disengage, dodge, hide) at Bonus Action cost, performed.
static func _bonus_basic(cb, h, kind: String) -> bool:
	for v in cb.available(h):
		if v["kind"] == kind and _is_bonus(v):
			return not cb.perform(h, v).has("error")
	return false

static func _weakest(list: Array):
	var best = null
	for c in list:
		if best == null or c.hp < best.hp:
			best = c
	return best

# The ally (or self, for heal_self) at a third of their HP or less that `v`
# can reach, the worst off first.
static func _hurt_ally(cb, h, v: Dictionary):
	if v["kind"] == "heal_self":
		return h if h.hp * 3 <= h.max_hp else null
	var best = null
	for c in cb.combatants:
		if c.team != h.team or not c.conscious() or c.hp * 3 > c.max_hp:
			continue
		if not _can_aim(cb, h, v, c):
			continue
		if best == null or float(c.hp) / c.max_hp < float(best.hp) / best.max_hp:
			best = c
	return best

# Who a lasting buff goes on: yourself for a self spell; else the ally in the
# thick of it (the most foes beside them), not already wearing it.
static func _buff_target(cb, h, v: Dictionary):
	var tgt: String = String(v.get("targeting", "self"))
	var status: String = String(v.get("status", "spell:" + String(v.get("spell", v["id"]))))
	if tgt in ["self", "allies"]:
		return h if not h.has(status) else null
	var best = null
	var best_n := -1
	for c in cb.combatants:
		if c.team != h.team or not c.conscious() or c.has(status) or c.has("summoned"):
			continue
		if not cb.legal_target(h, v, c):
			continue
		var n: int = cb.enemies_of(c).filter(func(e): return e.conscious() and Hex.distance(c.pos, e.pos) <= 1).size()
		if n > best_n:
			best_n = n
			best = c
	return best

# Where a Misty Step goes to get out: the free hex in range furthest from every
# foe, or null if none is further than where they stand now.
static func _escape_hex(cb, h, v: Dictionary, foes: Array):
	var best = null
	var best_d := Hex.distance(h.pos, _nearest(h.pos, foes).pos)
	var r: int = int(v.get("range", 6))
	for q in range(-r, r + 1):
		for rr in range(-r, r + 1):
			var hx: Vector2i = h.pos + Vector2i(q, rr)
			if Hex.distance(h.pos, hx) > r or cb._cast_refusal(h, v, hx) != "":
				continue   # the resolver's own test for a teleport's landing
			var d: int = Hex.distance(hx, _nearest(hx, foes).pos)
			if d > best_d:
				best_d = d
				best = hx
	return best

# Font of Magic, the autopilot's one use of it: a sorcerer with no slot left at
# all and the points for one makes the biggest it can afford, so the sweeps see
# the points as the spells they become. Burning slots into points is left to a
# player — the autopilot would only ever be turning a spell into a smaller one.
static func _font_up(cb, h) -> void:
	for n in h.slots:
		if int(n) > 0:
			return
	var best := {}
	for v in cb.available(h):
		if String(v.get("font", "")) == "to_slot" and int(v["make_slot"]) > int(best.get("make_slot", 0)):
			best = v
	if not best.is_empty():
		cb.perform(h, best)

# One movement preference per kind — not to make the autopilot good, but so
# the sweep in tests/test_objectives.gd measures a party that is trying.
# Returns true if it spent the move, so the caller does not chase as well.
static func _objective_move(cb, h) -> bool:
	match cb.objective_kind():
		"rescue":
			var cap = cb.with_status("captive")
			if cap == null or cap.has("freed") or cap.is_dead():
				return false
			if _nearest(cap.pos, cb.heroes()) != h or Hex.distance(h.pos, cap.pos) <= 1:
				return false
			_move_by(cb, h, _toward(cb, cap.pos))
			return true
		"breakout":
			var exit: Array = cb.objective.get("exit", [])
			if exit.is_empty() or h.pos in exit:
				return false
			var goal: Vector2i = exit[0]
			for e in exit:
				if Hex.distance(h.pos, e) < Hex.distance(h.pos, goal):
					goal = e
			_move_by(cb, h, _toward(cb, goal))
			return true
		"escort":
			var car = cb.with_status("carter")
			if car == null or car.is_dead() or Hex.distance(h.pos, car.pos) <= 2:
				return false
			_move_by(cb, h, _toward(cb, car.pos))
			return true
	return false

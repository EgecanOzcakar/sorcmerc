# Monster AI = the literal priority list from combat-design.md §7, on the hex grid.
# Also a simple auto-pilot for the party, used by headless playthrough / demo mode.
extends RefCounted

const Hex = preload("res://core/hex.gd")

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

static func _move_by(cb, m, score: Callable, disengage := false) -> void:
	var field: Dictionary = cb.move_field(m)
	var best: Vector2i = m.pos
	var best_s: float = score.call(m.pos) - (ZONE_PENALTY if cb.zone_hurts(m, m.pos) else 0.0)
	for h in field:
		var s: float = score.call(h) - (ZONE_PENALTY if cb.zone_hurts(m, h) else 0.0)
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

static func _toward(goal: Vector2i) -> Callable:
	return func(h: Vector2i) -> float: return -float(Hex.distance(h, goal))

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

# --- foes ------------------------------------------------------------

# A shooter with an enemy adjacent fires at disadvantage. If one move can reach a
# hex that is clear of every PC and still within range of one, take it (eating
# the opportunity attack — a bow at full effect is worth more than a free swing
# avoided) and report true so the caller shoots instead of swinging point-blank.
static func _step_clear(cb, m, pcs: Array) -> bool:
	var best := Vector2i.ZERO
	var best_d := -1
	for h in cb.move_field(m):
		var near := 1 << 30
		for c in pcs:
			near = mini(near, Hex.distance(h, c.pos))
		if near <= 1 or near > m.atk_range:
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
		and c.conscious() and not c.has("illusion"))
	if pcs.is_empty():
		return
	_use_kit(cb, m)

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
		var near = _nearest(m.pos, pcs)
		var d := Hex.distance(m.pos, near.pos)
		if d <= 1:
			_move_by(cb, m, _away(pcs), true)
		elif d > m.atk_range:
			_move_by(cb, m, _toward(near.pos))
		var shootable: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= m.atk_range and Hex.distance(c.pos, m.pos) > 1)
		if not shootable.is_empty():
			shootable.sort_custom(func(a, b): return a.hp < b.hp)
			await _strike(cb, m, shootable)
		return

	# melee, nobody adjacent: close on the nearest PC, then swing if we arrived
	var target = _nearest(m.pos, pcs)
	_move_by(cb, m, _toward(target.pos))
	var now: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= m.reach and c.conscious())
	if not m.conscious():
		return
	if not now.is_empty():
		now.sort_custom(func(a, b): return a.hp < b.hp)
		await _strike(cb, m, now)
	else:
		await _use_special(cb, m, pcs)   # closed, but not close enough to swing — a gaze still reaches

# --- party autopilot (demo / test only) ----------------------------

static func _party_auto(cb, h) -> void:
	var foes: Array = cb.enemies_of(h)
	if foes.is_empty():
		return
	_use_kit(cb, h)

	# healer: a downed ally in range comes first
	var heal := _pick(cb, h, func(v): return v.has("heal_count") or v["kind"] == "heal_ally")
	if not heal.is_empty():
		for c in cb.combatants:
			if c.team == h.team and c.is_down() and cb.legal_target(h, heal, c):
				cb.perform(h, heal, c)
				break

	# close distance if nothing is in reach and we're not a shooter
	var reach: Array = foes.filter(func(c): return cb.in_reach(h, c))
	if reach.is_empty() and not h.ranged:
		var t = _nearest(h.pos, foes)
		_move_by(cb, h, _toward(t.pos))
		reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))

	# caster: an area spell (a hex, a corner circle, a line) where it nets 2+ foes
	# ...that actually hurts: Faerie Fire and friends are the player's call, not a nuke
	var area := _pick(cb, h, func(v): return v.get("targeting", "") in ["hex", "corner", "line"] and v.has("dice_count"))
	if not area.is_empty():
		var aim = _best_area(cb, h, area)
		if aim != null:
			cb.perform(h, area, aim)
			return

	# caster: a cone spell if the wedge catches 2+ foes and no ally
	var cone := _pick(cb, h, func(v): return v.get("targeting", "") == "direction" and v.has("dice_count"))
	if not cone.is_empty():
		var best_dir := Vector2i.ZERO
		var best_net := 1
		for d in Hex.DIRS:
			var wedge := Hex.cone(h.pos, d, int(cone.get("radius", 2)))
			var f: int = cb.enemies_of(h).filter(func(c): return c.pos in wedge).size()
			var a: int = cb.allies_of(h).filter(func(c): return c.pos in wedge).size()
			if f - a > best_net:
				best_net = f - a
				best_dir = d
		if best_dir != Vector2i.ZERO:
			cb.perform(h, cone, best_dir)
			return

	var targets: Array = reach if not reach.is_empty() else foes
	if targets.is_empty():
		return
	targets.sort_custom(func(a, b): return a.hp < b.hp)
	if cb.in_reach(h, targets[0]):
		cb.resolve_attack(h, targets[0])
		return
	# no weapon reach: a single-target attack spell (a cantrip needs no slot)
	var bolt := _pick(cb, h, func(v): return v["kind"] == "spell" and v.get("targeting", "") == "enemy" and v.has("dice_count"))
	if not bolt.is_empty() and cb.legal_target(h, bolt, targets[0]):
		cb.perform(h, bolt, targets[0])

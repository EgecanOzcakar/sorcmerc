# Monster AI = the literal priority list from combat-design.md §7, on the hex grid.
# Also a simple auto-pilot for the party, used by headless playthrough / demo mode.
extends RefCounted

const Hex = preload("res://core/hex.gd")

# combat-design.md §7 rule 5: foes won't execute a downed PC while they could
# instead engage a conscious one this turn. The difference between tense and
# feels-bad — flip to false to let monsters finish people off.
const MERCY := true

static func take_turn(cb, actor) -> void:
	if not actor.conscious():
		return
	if actor.team == "foe":
		_foe_turn(cb, actor)
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
static func _move_by(cb, m, score: Callable, disengage := false) -> void:
	var field: Dictionary = cb.move_field(m)
	var best: Vector2i = m.pos
	var best_s: float = score.call(m.pos)
	for h in field:
		var s: float = score.call(h)
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
		elif d <= 1:
			return true
	return false

static func _toward(goal: Vector2i) -> Callable:
	return func(h: Vector2i) -> float: return -float(Hex.distance(h, goal))

static func _away(threats: Array) -> Callable:
	return func(h: Vector2i) -> float:
		var m := 1 << 30
		for t in threats:
			m = mini(m, Hex.distance(h, t.pos))
		return float(m)

# --- foes ------------------------------------------------------------

static func _foe_turn(cb, m) -> void:
	var pcs: Array = cb.combatants.filter(func(c): return c.team == "party" and c.conscious())
	if pcs.is_empty():
		return

	var adj: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= 1)
	if not adj.is_empty():
		adj.sort_custom(func(a, b): return a.hp < b.hp if a.hp != b.hp else a.ac < b.ac)
		cb.resolve_attack(m, adj[0])
		if m.nimble_escape and m.hp * 2 <= m.max_hp:
			_move_by(cb, m, _away(pcs), true)  # Nimble Escape = bonus Disengage
		return

	# no conscious PC adjacent — a downed neighbour gets finished only if we
	# couldn't have engaged a conscious PC this turn (mercy rule, §7 rule 5)
	var downed_adj: Array = cb.combatants.filter(func(c):
		return c.team == "party" and c.is_down() and Hex.distance(c.pos, m.pos) <= 1)
	if not downed_adj.is_empty():
		if not MERCY or not pcs.any(func(c): return _can_engage(cb, m, c)):
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
			cb.resolve_attack(m, shootable[0])
		return

	# melee, nobody adjacent: close on the nearest PC, then swing if we arrived
	var target = _nearest(m.pos, pcs)
	_move_by(cb, m, _toward(target.pos))
	var now: Array = pcs.filter(func(c): return Hex.distance(c.pos, m.pos) <= 1 and c.conscious())
	if not now.is_empty() and m.conscious():
		now.sort_custom(func(a, b): return a.hp < b.hp)
		cb.resolve_attack(m, now[0])

# --- party autopilot (demo / test only) ----------------------------

static func _party_auto(cb, h) -> void:
	var foes: Array = cb.enemies_of(h)
	if foes.is_empty():
		return

	# healer: revive a downed ally first (bonus action, still attack after)
	if "healing_word" in h.spells and h.slots1 + h.slots2 > 0:
		var downed: Array = cb.combatants.filter(func(c): return c.team == "party" and c.is_down())
		if not downed.is_empty():
			cb.cast_healing_word(h, downed[0])

	# close distance if nothing is in reach and we're not a shooter
	var reach: Array = foes.filter(func(c): return cb.in_reach(h, c))
	if reach.is_empty() and not h.ranged:
		var t = _nearest(h.pos, foes)
		_move_by(cb, h, _toward(t.pos))
		reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))

	# caster: burning hands if a cone catches 2+ foes and no ally
	if "burning_hands" in h.spells and h.slots1 + h.slots2 > 0:
		var best_dir := Vector2i.ZERO
		var best_net := 1
		for d in Hex.DIRS:
			var wedge := Hex.cone(h.pos, d, 2)
			var f: int = cb.enemies_of(h).filter(func(c): return c.pos in wedge).size()
			var a: int = cb.allies_of(h).filter(func(c): return c.pos in wedge).size()
			if f - a > best_net:
				best_net = f - a
				best_dir = d
		if best_dir != Vector2i.ZERO:
			cb.cast_burning_hands(h, best_dir)
			return

	var targets: Array = reach if not reach.is_empty() else foes
	if targets.is_empty():
		return
	targets.sort_custom(func(a, b): return a.hp < b.hp)
	if cb.in_reach(h, targets[0]):
		cb.resolve_attack(h, targets[0])
	elif "sacred_flame" in h.spells:
		cb.cast_sacred_flame(h, targets[0])

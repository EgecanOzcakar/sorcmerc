# Monster AI = the literal priority list from combat-design.md §7.
# Also a simple auto-pilot for the party, used by headless playthrough / demo mode.
extends RefCounted

const Dice = preload("res://core/dice.gd")

static func take_turn(cb, actor) -> void:
	if not actor.conscious():
		return
	if actor.team == "foe":
		_foe_turn(cb, actor)
	else:
		_party_auto(cb, actor)

# --- foes ---------------------------------------------------------------

static func _foe_turn(cb, m) -> void:
	var pcs: Array = cb.combatants.filter(func(c): return c.team == "party" and c.conscious())
	if pcs.is_empty():
		return

	var here: Array = pcs.filter(func(c): return c.zone == m.zone)
	if not here.is_empty():
		here.sort_custom(func(a, b): return a.hp < b.hp if a.hp != b.hp else a.ac < b.ac)
		cb.resolve_attack(m, here[0])
		if m.nimble_escape and m.hp * 2 <= m.max_hp:
			var dir = _away_from(m, here[0])
			if dir != 0:
				cb.move_to(m, m.zone + dir, true)  # Nimble Escape = bonus Disengage
		return

	if m.ranged:
		pcs.sort_custom(func(a, b): return a.hp < b.hp)
		cb.resolve_attack(m, pcs[0])
		return

	# move one zone toward the nearest zone holding a conscious PC, then swing if arrived
	pcs.sort_custom(func(a, b): return absi(a.zone - m.zone) < absi(b.zone - m.zone))
	var step = signi(pcs[0].zone - m.zone)
	if step != 0:
		cb.move_to(m, m.zone + step)
	var now: Array = pcs.filter(func(c): return c.zone == m.zone and c.conscious())
	if not now.is_empty() and m.conscious():
		now.sort_custom(func(a, b): return a.hp < b.hp)
		cb.resolve_attack(m, now[0])

static func _away_from(m, threat) -> int:
	if m.zone == threat.zone:
		if m.zone == 0:
			return 1
		if m.zone == 2:
			return -1
		return 1
	return signi(m.zone - threat.zone)

# --- party autopilot (demo / test only) --------------------------------

static func _party_auto(cb, h) -> void:
	var foes: Array = cb.enemies_of(h)
	if foes.is_empty():
		return

	# healer: revive a downed ally first (bonus action, still attack after)
	if "healing_word" in h.spells and h.slots1 + h.slots2 > 0:
		var downed: Array = cb.combatants.filter(func(c): return c.team == "party" and c.is_down())
		if not downed.is_empty():
			cb.cast_healing_word(h, downed[0])

	# close distance if nobody to hit here and not a ranged attacker
	var here: Array = foes.filter(func(c): return c.zone == h.zone)
	if here.is_empty() and not h.ranged:
		foes.sort_custom(func(a, b): return absi(a.zone - h.zone) < absi(b.zone - h.zone))
		var step = signi(foes[0].zone - h.zone)
		if step != 0:
			cb.move_to(cb, h) if false else cb.move_to(h, h.zone + step)
		here = cb.enemies_of(h).filter(func(c): return c.zone == h.zone)

	# caster: burning hands if it catches 2+ foes and no ally in zone
	if "burning_hands" in h.spells and h.slots1 + h.slots2 > 0:
		var foes_here = cb.enemies_of(h).filter(func(c): return c.zone == h.zone)
		var allies_here = cb.allies_of(h).filter(func(c): return c.zone == h.zone)
		if foes_here.size() >= 2 and allies_here.is_empty():
			cb.cast_burning_hands(h)
			return

	var targets: Array = here if not here.is_empty() else foes
	if targets.is_empty():
		return
	targets.sort_custom(func(a, b): return a.hp < b.hp)
	if h.ranged or not here.is_empty():
		cb.resolve_attack(h, targets[0])
	elif "sacred_flame" in h.spells:
		cb.cast_sacred_flame(h, targets[0])

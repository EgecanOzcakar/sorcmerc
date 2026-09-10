# ResolvedCharacter -> Combatant, and the HP/pools/slots trip back.
# `Character` owns the build, `Combatant` owns the fight (spec §3); this is the seam.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")
const Effects = preload("res://core/rules/effects.gd")

# The two calibration knobs. Feet are the rules' unit; hexes are the board's.
# Changing either re-tunes every encounter — re-run the seed sweep in
# tests/test_combat.gd when you do.
const FT_PER_HEX := 6      # 30 ft -> 5 hexes
const RANGE_CAP := 8       # ranged attacks clamped to this many hexes

static func hexes(ft: int) -> int:
	return maxi(1, roundi(float(ft) / FT_PER_HEX))

static func to_combatant(ch, team: String, pos: Vector2i):
	var s = ch.sheet()
	var c = Combatant.new()
	c.id = ch.id
	c.cname = ch.cname
	c.team = team
	c.pos = pos
	c.sheet = s

	c.ac = s.ac
	c.max_hp = s.max_hp
	c.hp = ch.hp_current if ch.hp_current >= 0 else s.max_hp
	c.init_mod = s.initiative
	c.speed = hexes(int(s.speeds.get("walk", 30)))

	c.attacks = s.attacks.duplicate(true)
	if not s.attacks.is_empty():
		var a: Dictionary = s.attacks[0]
		c.atk_bonus = int(a["to_hit"])
		c.damage = a["notation"]
		c.ranged = a["range"] == "ranged"
		c.atk_range = mini(RANGE_CAP, hexes(int(a["normal_ft"]))) if c.ranged else 1
	c.crit_range = 19 if s.has_feature("champion-improved-critical") else 20

	c.saves = s.saves.duplicate()
	c.save_dc = int(s.spellcasting.get("save_dc", 0))
	c.athletics = int(s.skills.get("athletics", 0))
	c.acro = int(s.skills.get("acrobatics", 0))
	c.stealth = int(s.skills.get("stealth", 0))
	c.passive_perception = s.passive_perception

	for fid in s.features:
		c.features[fid] = true
	for p in s.pools:
		c.pools[p["id"]] = {"cur": int(ch.pools.get(p["id"], p["max"])), "max": int(p["max"]),
			"regen": p["regen"]}
	var slots: Array[int] = []
	for n in s.spellcasting.get("slots", []):
		slots.append(int(n))
	while slots.size() < 9:
		slots.append(0)
	c.slots = slots

	var castable: Array[String] = []
	for sid in s.spellcasting.get("cantrips", []):
		castable.append(sid)
	for sid in s.spellcasting.get("always_prepared", []):
		castable.append(sid)
	for sid in ch.prepared:
		if not sid in castable:
			castable.append(sid)
	c.spell_ids = castable

	c.verbs = Effects.verbs_for(s)
	_legacy_kit(c, s)
	return c

# F3 replaces all of this with verbs off data/effects/features.json (spec §6).
# Until then the adapter fills the flat kit flags combat.gd still reads, so a
# sheet-built party fights exactly like the hand-authored one.
static func _legacy_kit(c, s) -> void:
	var rogue: int = s.class_level("rogue")
	if s.has_feature("rogue-sneak-attack") and rogue > 0:
		c.sneak_attack = "%dd6" % ceili(rogue / 2.0)
	c.cunning_action = s.has_feature("rogue-cunning-action")
	c.nimble_escape = s.has_feature("goblin-nimble-escape")
	var fighter: int = s.class_level("fighter")
	if s.has_feature("fighter-second-wind"):
		c.second_wind = "1d10+%d" % fighter
	c.action_surge = s.has_feature("fighter-action-surge")
	# cure-wounds stands in for healing_word: healing-word is absent from the export.
	const LEGACY_SPELLS := {"burning-hands": "burning_hands", "cure-wounds": "healing_word",
		"sacred-flame": "sacred_flame"}
	for sid in c.spell_ids:
		if LEGACY_SPELLS.has(sid):
			c.spells.append(LEGACY_SPELLS[sid])

static func from_monster(m: Dictionary, team: String, pos: Vector2i):
	var c = Combatant.new()
	for k in m:
		if k in ["attacks", "features", "pools", "saves", "spells"]:
			continue
		c.set(k, m[k])
	c.team = team
	c.pos = pos
	c.max_hp = int(m["max_hp"])
	c.hp = int(m.get("hp", m["max_hp"]))
	c.saves = m.get("saves", {}).duplicate()
	c.attacks = m.get("attacks", []).duplicate(true)
	for fid in m.get("features", []):
		c.features[fid] = true
	c.spells = m.get("spells", []).duplicate()
	return c

# What T7 persists when a fight ends: HP, spent slots, spent pool uses.
# Statuses and position belong to the fight and are dropped.
static func write_back(c, ch) -> void:
	ch.hp_current = c.hp
	for pid in c.pools:
		ch.pools[pid] = int(c.pools[pid]["cur"])
	ch.dirty()

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
	for i in mini(9, ch.slots_used.size()):
		slots[i] = maxi(0, slots[i] - int(ch.slots_used[i]))
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
	c.verbs.append_array(Effects.spell_verbs_for(s, castable))
	_finish_verbs(c, ch.pools)
	return c

# Feet -> hexes for every verb, and a pool for the features the export grants none
# (Second Wind, Action Surge — effects.gd keys those on the feature id).
static func _finish_verbs(c, saved_pools: Dictionary) -> void:
	var keep: Array = []
	for v in c.verbs:
		if v.has("range_ft"):
			v["range"] = mini(RANGE_CAP, hexes(int(v["range_ft"])))
		if int(v.get("size_ft", 0)) > 0:
			v["radius"] = area_hexes(int(v["size_ft"]))
		if v.has("pool") and not c.pools.has(v["pool"]):
			var n := int(v.get("uses", 1))
			c.pools[v["pool"]] = {"cur": int(saved_pools.get(v["pool"], n)), "max": n,
				"regen": "short-rest"}
		# ponytail: hex-targeted areas (fireball) need an aiming mode no shipping
		# build uses yet — drop them rather than offer a verb the UI can't point.
		if v.get("targeting", "") != "hex":
			keep.append(v)
	c.verbs = keep

# Areas floor rather than round: a 15 ft cone stays the 2-hex wedge the room was
# tuned around, where roundi() would widen it to 3.
static func area_hexes(ft: int) -> int:
	return maxi(1, ft / FT_PER_HEX)

static func from_monster(m: Dictionary, team: String, pos: Vector2i):
	var c = Combatant.new()
	for k in m:
		if k in ["attacks", "features", "pools", "saves"]:
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
	c.verbs = Effects.verbs_for(null, c.features.keys())
	_finish_verbs(c, {})
	return c

# Short/long rest: refill the pools that regain on it, all spell slots on a long
# rest, and HP on a long rest. T6's rest node is the caller.
static func rest(ch, kind: String) -> void:
	var s = ch.sheet()
	for p in s.pools:
		if kind == "long-rest" or p["regen"] == "short-rest":
			ch.pools[p["id"]] = int(p["max"])
	for v in Effects.verbs_for(s):
		if v.has("pool") and s.pool_max(v["pool"]) == 0:
			ch.pools[v["pool"]] = int(v.get("uses", 1))   # synthetic pool, short-rest
	if kind == "long-rest":
		ch.slots_used.clear()
		ch.hp_current = -1
	ch.dirty()

# What T7 persists when a fight ends: HP, spent slots, spent pool uses.
# Statuses and position belong to the fight and are dropped.
static func write_back(c, ch) -> void:
	ch.hp_current = c.hp
	for pid in c.pools:
		ch.pools[pid] = int(c.pools[pid]["cur"])
	var full: Array = c.sheet.spellcasting.get("slots", []) if c.sheet else []
	var used: Array[int] = []
	for i in full.size():
		used.append(maxi(0, int(full[i]) - int(c.slots[i])))
	ch.slots_used = used
	ch.dirty()

# The batch T7 calls when a fight ends: match combatants to Characters by id.
static func write_back_all(combatants: Array, characters: Array) -> void:
	var by_id := {}
	for ch in characters:
		by_id[ch.id] = ch
	for c in combatants:
		if by_id.has(c.id):
			write_back(c, by_id[c.id])

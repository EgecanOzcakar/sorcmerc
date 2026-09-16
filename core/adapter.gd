# ResolvedCharacter -> Combatant, and the HP/pools/slots trip back.
# `Character` owns the build, `Combatant` owns the fight (spec §3); this is the seam.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")
const Effects = preload("res://core/rules/effects.gd")
const Potions = preload("res://core/potions.gd")
const PassGear = preload("res://core/rules/pass_gear.gd")

# The two calibration knobs. Feet are the rules' unit; hexes are the board's.
# Changing either re-tunes every encounter — re-run the seed sweep in
# tests/test_combat.gd when you do.
const FT_PER_HEX := 6      # 30 ft -> 5 hexes
# 12 hexes is BG3's 18 m / 60 ft grammar. Measured 2026-09-15 on the grown
# boards (tests/sweep_range_detail.gd, 150 seeds): 8 -> 12 frees 17 of Pike's
# ~740 shots past 8 hexes, moves no win rate, and the bestiary's archers never
# reach it (atk_range is authored in hexes, not capped here) — so the cap now
# only separates a longbow from a shortbow, which is the point of having one.
const RANGE_CAP := 12      # ranged attacks clamped to this many hexes
const AREA_ONE_HEX_FT := 16   # a radius up to ~5 m is one hex; bigger is a corner circle

static func hexes(ft: int) -> int:
	return maxi(1, roundi(float(ft) / FT_PER_HEX))

# Warlock Pact Magic slots are a single-level pool (all slots cast at
# `slotLevel`), so they slot cleanly into the normal 9-level slots array at
# that index rather than needing a parallel tracking field. `pass_spells.gd`
# leaves `slots` all-zero for a warlock and reports `pact` separately — this
# is where the two get merged back into one array for combat to spend from.
static func _full_slots(s) -> Array[int]:
	var slots: Array[int] = []
	for n in s.spellcasting.get("slots", []):
		slots.append(int(n))
	while slots.size() < 9:
		slots.append(0)
	var pact: Dictionary = s.spellcasting.get("pact", {})
	if not pact.is_empty():
		var lvl := int(pact.get("slotLevel", 1))
		if lvl >= 1 and lvl <= 9:
			slots[lvl - 1] = int(pact.get("count", 0))
	return slots

static func _is_warlock(s) -> bool:
	return s.spellcasting.get("class_id", "") == "warlock" and not s.spellcasting.get("pact", {}).is_empty()

# Features the export gives no resource-pool grant for (SCHEMA gap #4) default
# to short-rest in _finish_verbs/rest() below, which is RAW-correct for Second
# Wind, Action Surge, Channel Divinity and Wild Shape. wizard-arcane-recovery is
# always long-rest; bard-bardic-inspiration is long-rest until level 5's Font of
# Inspiration flips it to short-rest — _synthetic_regen() below is where that
# one feature-specific exception lives, everything else uses the flat default.
const LONG_REST_ONLY_FEATURES := ["bard-bardic-inspiration", "wizard-arcane-recovery"]
const FONT_OF_INSPIRATION_LEVEL := 5

static func _synthetic_regen(pool_id: String, sheet) -> String:
	if pool_id == "bard-bardic-inspiration" and sheet != null and sheet.class_level("bard") >= FONT_OF_INSPIRATION_LEVEL:
		return "short-rest"
	return "long-rest" if pool_id in LONG_REST_ONLY_FEATURES else "short-rest"

# Arcane Recovery doesn't fit the combat-verb effect system at all (it's
# explicitly out-of-combat), so it isn't a data/effects/features.json entry —
# it's modelled directly here as its own small mechanic, same numbers as both
# 2024 RAW and BG3 ("charges" == "sum of restored slot levels", same formula):
# ceil(wizard level / 2) charges, 1 per slot level restored, capped at slot 5,
# refills on a long rest, spendable once per day (== between long rests).
const ARCANE_RECOVERY_POOL := "wizard-arcane-recovery"
const ARCANE_RECOVERY_MAX_SLOT := 5

static func arcane_recovery_max(ch) -> int:
	var lvl: int = ch.sheet().class_level("wizard")
	return ceili(lvl / 2.0) if lvl > 0 else 0

# `restore_levels`: which slot levels to refund, e.g. [1, 1, 2] = two 1st- and
# one 2nd-level slot (cost 4 charges). Refuses and changes nothing if the party
# can't afford it, a level is above the cap, or the character has no slot of
# that level to refund in the first place.
static func arcane_recovery(ch, restore_levels: Array) -> bool:
	var cost := 0
	for lvl in restore_levels:
		cost += int(lvl)
	if cost <= 0 or cost > int(ch.pools.get(ARCANE_RECOVERY_POOL, 0)):
		return false
	var full := _full_slots(ch.sheet())
	var remaining := full.duplicate()
	for i in mini(9, ch.slots_used.size()):
		remaining[i] = maxi(0, remaining[i] - int(ch.slots_used[i]))
	var refund := {}
	for lvl in restore_levels:
		var i: int = int(lvl) - 1
		if i < 0 or i >= 9 or int(lvl) > ARCANE_RECOVERY_MAX_SLOT:
			return false
		refund[i] = int(refund.get(i, 0)) + 1
		if remaining[i] + refund[i] > full[i]:
			return false   # no spent slot of this level left to refund
	while ch.slots_used.size() < 9:
		ch.slots_used.append(0)
	for i in refund:
		ch.slots_used[i] = maxi(0, int(ch.slots_used[i]) - refund[i])
	ch.pools[ARCANE_RECOVERY_POOL] = int(ch.pools[ARCANE_RECOVERY_POOL]) - cost
	ch.dirty()
	return true

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
	# A character who was stabilised (not healed) at 0 HP in a previous fight
	# carries that 0 into this one — combat.gd's death-save loop only fires off
	# the "down" status, never off hp alone, so without this they'd stand and
	# act as if fully conscious at 0 HP. Rest (adapter.rest) is the real fix —
	# a stable creature regains 1 HP after an hour, RAW — this is the backstop
	# for any path that hands over a 0-HP character without an intervening rest.
	if c.hp <= 0:
		c.hp = 0
		c.statuses["down"] = true
	c.init_mod = s.initiative
	c.speed = hexes(int(s.speeds.get("walk", 30)))
	for pid in ch.buffs:   # Potions drunk on the road, still in effect (core/potions.gd)
		var b: Dictionary = ch.buffs[pid]
		if b.has("status"):
			c.statuses[Potions.STATUS_PREFIX + String(pid)] = b["status"].duplicate()
		if b.has("condition"):
			c.statuses[String(b["condition"])] = {}

	c.attacks = s.attacks.duplicate(true)
	var offhand := _take_offhand(c.attacks, ch.offhand)   # main hand must stay attacks[0]
	_apply_main_attack(c)
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
	var full_slots := _full_slots(s)
	var slots := full_slots.duplicate()
	for i in mini(9, ch.slots_used.size()):
		slots[i] = maxi(0, slots[i] - int(ch.slots_used[i]))
	c.slots = slots

	var castable: Array[String] = []
	for sid in s.spellcasting.get("cantrips", []):
		castable.append(sid)
	for sid in s.spellcasting.get("always_prepared", []):
		castable.append(sid)
	# Every slot-costing spell the character knows — the spellbook for a
	# prepared caster (wizard/cleric/...), the known list for a sorcerer/
	# bard/warlock. Nothing in this project ever offers a daily-prep screen
	# to whittle this down to ch.prepared, so without this line a player-made
	# prepared caster's ch.prepared stayed empty forever and every leveled
	# spell they knew was simply invisible in combat.
	for k in s.spellcasting.get("known", []):
		var sid: String = String(k["id"])
		if not sid in castable:
			castable.append(sid)
	for sid in ch.prepared:
		if not sid in castable:
			castable.append(sid)
	c.spell_ids = castable

	c.verbs = Effects.verbs_for(s)
	c.verbs.append_array(Effects.spell_verbs_for(s, castable, full_slots))
	var twf := _offhand_verb(offhand, c.attacks, s)
	if not twf.is_empty():
		c.verbs.append(twf)
	_finish_verbs(c, ch.pools)
	return c

# Every derived attack stat combat.gd swings with comes off attacks[0], so
# "which weapon am I using" is just "which attack is first" — one writer here.
static func _apply_main_attack(c) -> void:
	if c.attacks.is_empty():
		return
	var a: Dictionary = c.attacks[0]
	c.atk_bonus = int(a["to_hit"])
	c.damage = a["notation"]
	c.ranged = a["range"] == "ranged"
	c.atk_range = mini(RANGE_CAP, hexes(int(a["normal_ft"]))) if c.ranged else 1

# T29: the melee/ranged toggle. Moves the named attack to the front and
# recomputes; false if this combatant has no such attack.
# ponytail: if the chosen weapon is also the off-hand one the off-hand verb
# still exists (built once, at adapter time) — a cosmetic duplicate at worst.
static func set_main_attack(c, attack_id: String) -> bool:
	for i in c.attacks.size():
		if String(c.attacks[i].get("id", "")) == attack_id:
			if i > 0:
				c.attacks.insert(0, c.attacks.pop_at(i))
			_apply_main_attack(c)
			return true
	return false

# --- two-weapon fighting (T24) ----------------------------------------
#
# `attacks` already carries one entry per equipped weapon (pass_gear.gd); the
# off-hand one just has to stop being attacks[0], which is the main hand
# everywhere else in combat.gd. Returns it (and leaves it last), {} if there is
# no second weapon to swing.
const TWF_STYLE := "two-weapon-fighting"

static func _take_offhand(attacks: Array, offhand_id: String) -> Dictionary:
	if offhand_id == "":
		return {}
	for i in attacks.size():
		if String(attacks[i]["id"]) == offhand_id:
			var a: Dictionary = attacks[i]
			attacks.remove_at(i)
			attacks.append(a)
			return a
	return {}

# The 2024 rule: the off-hand swing drops the ability modifier from its damage,
# unless the Two-Weapon Fighting style puts it back. Nick (main hand) makes the
# swing free and part of the Attack action instead of a bonus action.
static func _offhand_verb(offhand: Dictionary, attacks: Array, s) -> Dictionary:
	if offhand.is_empty() or attacks.is_empty():
		return {}
	var main: Dictionary = attacks[0]
	if String(main["id"]) == String(offhand["id"]) or String(main["id"]) == "unarmed-strike":
		return {}   # no main-hand weapon: not dual-wielding
	var dmg := int(offhand["dmg_bonus"]) if TWF_STYLE in s.fighting_styles else 0
	var nick: bool = String(main.get("mastery", "")) == "nick"
	var reach := 1
	if offhand["range"] == "ranged":
		reach = mini(RANGE_CAP, hexes(int(offhand["normal_ft"])))
	return {
		"id": "offhand_attack", "label": "Off-hand: %s" % offhand["name"],
		"kind": "offhand_attack", "cost": "free" if nick else "bonus",
		"once_per": "turn", "targeting": "enemy", "range": reach,
		"to_hit": int(offhand["to_hit"]),
		"damage": PassGear.notation(int(offhand["dice_count"]), int(offhand["dice_sides"]), dmg),
	}

# Feet -> hexes for every verb, and a pool for the features the export grants none
# (Second Wind, Action Surge — effects.gd keys those on the feature id).
static func _finish_verbs(c, saved_pools: Dictionary) -> void:
	var keep: Array = []
	for v in c.verbs:
		if v.has("range_ft"):
			v["range"] = mini(RANGE_CAP, hexes(int(v["range_ft"])))
		if int(v.get("size_ft", 0)) > 0:
			v["radius"] = area_hexes(int(v["size_ft"]))
		if v.get("targeting", "") == "area":
			# Areas on this board: up to a 5 m radius is one hex; anything bigger
			# is anchored on a hex corner and covers the hexes around it.
			# ponytail: one corner ring for every 6-9 m area — the ring count is
			# the knob if a 9 m circle should read bigger than a 6 m one.
			if int(v["size_ft"]) <= AREA_ONE_HEX_FT:
				v["targeting"] = "hex"
			else:
				v["targeting"] = "corner"
				v["ring"] = 0
		if v.get("targeting", "") == "line":
			v["length"] = mini(RANGE_CAP, area_hexes(int(v.get("size_ft", 0))))
		if v.has("pool") and not c.pools.has(v["pool"]):
			var n := int(v.get("uses", 1))
			var regen := _synthetic_regen(v["pool"], c.sheet)
			c.pools[v["pool"]] = {"cur": int(saved_pools.get(v["pool"], n)), "max": n, "regen": regen}
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
			if kind == "long-rest" or _synthetic_regen(v["pool"], s) == "short-rest":
				ch.pools[v["pool"]] = int(v.get("uses", 1))   # synthetic pool
	if kind == "long-rest":
		ch.pools[ARCANE_RECOVERY_POOL] = arcane_recovery_max(ch)
		ch.slots_used.clear()
		ch.hp_current = -1
	else:
		if _is_warlock(s):
			ch.slots_used.clear()   # Pact Magic: slots also come back on a short rest
		# ponytail: RAW short-rest healing is "spend Hit Dice you choose to
		# spend" — this project tracks no Hit Dice pool/UI for that, so a short
		# rest instead restores half of missing HP outright (rounded up), full
		# HP staying a long-rest-only thing. Covers the 0-HP/stable case too
		# (half of a nonzero gap is always >= 1) without a separate special case.
		var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
		var missing: int = s.max_hp - cur
		if missing > 0:
			ch.hp_current = cur + ceili(missing / 2.0)
	ch.dirty()

# What T7 persists when a fight ends: HP, spent slots, spent pool uses.
# Statuses and position belong to the fight and are dropped.
static func write_back(c, ch) -> void:
	ch.hp_current = c.hp
	for pid in c.pools:
		ch.pools[pid] = int(c.pools[pid]["cur"])
	var full: Array = _full_slots(c.sheet) if c.sheet else []
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

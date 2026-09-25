# ResolvedCharacter -> Combatant, and the HP/pools/slots trip back.
# `Character` owns the build, `Combatant` owns the fight (spec §3); this is the seam.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")
const Effects = preload("res://core/rules/effects.gd")
const Potions = preload("res://core/potions.gd")
const PassGear = preload("res://core/rules/pass_gear.gd")
const Traits = preload("res://core/traits.gd")

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
const LONG_REST_ONLY_FEATURES := ["bard-bardic-inspiration", "wizard-arcane-recovery",
	"beastmaster-primal-companion",   # RAW: the beast's uses come back on a long rest
	"lightdomain-warding-flare", "warrioropenhand-wholeness-of-body",   # 2024: Long Rest
	"gloomstalker-dread-ambusher",    # Dreadful Strike: WIS-mod uses per Long Rest
	"sorcerer-innate-sorcery"]        # 2024: two uses per Long Rest
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

# The charges left. A key never written (a wizard who has not long-rested since
# the build was made) reads as full, the same "missing means full" every pool
# on the build uses (to_combatant's `ch.pools.get(id, max)`).
static func arcane_recovery_left(ch) -> int:
	return int(ch.pools.get(ARCANE_RECOVERY_POOL, arcane_recovery_max(ch)))

# `restore_levels`: which slot levels to refund, e.g. [1, 1, 2] = two 1st- and
# one 2nd-level slot (cost 4 charges). Refuses and changes nothing if the party
# can't afford it, a level is above the cap, or the character has no slot of
# that level to refund in the first place.
static func arcane_recovery(ch, restore_levels: Array) -> bool:
	var cost := 0
	for lvl in restore_levels:
		cost += int(lvl)
	if cost <= 0 or cost > arcane_recovery_left(ch):
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
	ch.pools[ARCANE_RECOVERY_POOL] = arcane_recovery_left(ch) - cost
	ch.dirty()
	return true

# 4.2 of the design audit (docs/audit-game-design.md): the feature existed and
# nothing called it. RAW 2024 is one use per long rest, at the end of a short
# rest, choosing spent slots whose levels add up to no more than half the
# wizard level (rounded up), none above 5th. The game picks for the player,
# greedily and highest first: a spent 3rd is worth more than three spent 1sts
# to anyone about to walk back into a fight, and it is the pick a player makes
# nine times in ten. Used up the first time it restores anything; a short rest
# with nothing spent leaves it for a later one. Returns the levels restored,
# highest first ([] when it did nothing).
# ponytail: no picker. A player who would rather have two 1sts than a 2nd gets
# the 2nd; add a choice to the rest's message if anyone ever asks for one.
static func arcane_recovery_auto(ch) -> Array:
	var budget := arcane_recovery_left(ch)
	if budget <= 0 or arcane_recovery_max(ch) <= 0:
		return []
	var full := _full_slots(ch.sheet())
	var left := slots_left(ch)
	var pick: Array = []
	for lvl in range(mini(ARCANE_RECOVERY_MAX_SLOT, budget), 0, -1):
		var spent := maxi(0, full[lvl - 1] - left[lvl - 1])
		while spent > 0 and lvl <= budget:
			pick.append(lvl)
			budget -= lvl
			spent -= 1
	if pick.is_empty() or not arcane_recovery(ch, pick):
		return []
	ch.pools[ARCANE_RECOVERY_POOL] = 0   # once per long rest, whatever budget is left over
	return pick

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
	# Champion: Improved Critical at 3 (19-20), Superior Critical at 15 (18-20).
	c.crit_range = 18 if s.has_feature("champion-superior-critical") \
		else (19 if s.has_feature("champion-improved-critical") else 20)
	c.str_mod = s.mod("str")
	c.pb = s.proficiency_bonus

	c.saves = s.saves.duplicate()
	# #176: a dwarf's poison, a tiefling's fire, a dragonborn's breath-kin, the
	# few subclasses that grant one. The sheet has always resolved them
	# (resolve.gd's "resistance" grants) and the profile page has always shown
	# them, but nothing copied them onto the Combatant, so combat.gd's
	# _damage_after_defenses never saw them and a hero took every one in full.
	# from_monster does the same for a statblock. The presets are all human, so
	# Regions.ref_score and every sweep anchored on them do not move.
	for t in s.resistances:
		if not String(t).to_lower() in c.resist:
			c.resist.append(String(t).to_lower())
	for t in s.immunities:
		if not String(t).to_lower() in c.immune:
			c.immune.append(String(t).to_lower())
	c.save_dc = int(s.spellcasting.get("save_dc", 0))
	c.athletics = int(s.skills.get("athletics", 0))
	c.acro = int(s.skills.get("acrobatics", 0))
	c.stealth = int(s.skills.get("stealth", 0))
	c.passive_perception = s.passive_perception

	c.traits = Traits.ids(ch)   # #176: stamped where the fight is, by Encounter.build
	for fid in s.features:
		c.features[fid] = true
		if String(fid).contains("darkvision"):
			c.darkvision = true   # #85: the species trait, by its feature id
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
	c.init_adv = c.verbs.any(func(v): return v.get("init_adv", false))   # Assassinate, Dread Ambusher
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
	c.reach = 2 if "reach" in a.get("properties", []) else 1   # a glaive threatens 10 ft

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
	var reach := 2 if "reach" in offhand.get("properties", []) else 1
	if offhand["range"] == "ranged":
		reach = mini(RANGE_CAP, hexes(int(offhand["normal_ft"])))
	return {
		"id": "offhand_attack", "label": "Off-hand: %s" % offhand["name"],
		"weapon": String(offhand["name"]),   # #245: the log names the blade that landed
		"kind": "offhand_attack", "cost": "free" if nick else "bonus",
		"once_per": "turn", "targeting": "enemy", "range": reach,
		"to_hit": int(offhand["to_hit"]),
		"damage": PassGear.notation(int(offhand["dice_count"]), int(offhand["dice_sides"]), dmg),
		# #241: which weapon swings, so the bar can draw it (Icons.skill_icon).
		# Display only — resolve_attack reads the damage and to_hit above.
		"weapon": String(offhand["id"]),
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
		if k in ["attacks", "features", "pools", "saves",
				"resist", "immune", "vulnerable", "cond_immune"]:
			continue
		c.set(k, m[k])
	c.team = team
	c.pos = pos
	c.max_hp = int(m["max_hp"])
	c.hp = int(m.get("hp", m["max_hp"]))
	c.saves = m.get("saves", {}).duplicate()
	# An immunity behind a weapon clause comes back as RESISTANCE, not immunity
	# — see _damage_types_split for why that is the honest reading and not a
	# softening.
	var im: Dictionary = _damage_types_split(m.get("immune", []))
	c.immune = im["plain"]
	c.resist = _damage_types(m.get("resist", []))
	for t in im["qualified"]:
		if not t in c.resist:
			c.resist.append(t)
	c.vulnerable = _damage_types(m.get("vulnerable", []))
	c.cond_immune = Array(m.get("cond_immune", []).duplicate())
	c.attacks = m.get("attacks", []).duplicate(true)
	for fid in m.get("features", []):
		c.features[fid] = true
	c.darkvision = m.get("senses", {}).has("darkvision")   # #85
	# The Unarmed Strike DC (Shove / Grapple, 2024): STR off the statblock's
	# abilities and a proficiency bonus off its CR, the way the MM tables do.
	c.str_mod = floori((int(m.get("abilities", {}).get("str", 10)) - 10) / 2.0)
	c.pb = 2 + maxi(0, ceili(float(m.get("cr", 0)) / 4.0) - 1)
	c.verbs = Effects.verbs_for(null, c.features.keys())
	c.init_adv = c.verbs.any(func(v): return v.get("init_adv", false))
	_finish_verbs(c, {})
	return c

# T94 — bestiary.json's damage lists are SRD prose, not ids. 55 of the 316
# entries carry a type list plus a weapon clause:
#   "bludgeoning, piercing, and slashing from nonmagical weapons"
#   "... from nonmagical weapons that aren't silvered" / "... adamantine"
# Until 2026-09-25 nothing in this game handed out a magical, silvered or
# adamantine weapon. A +N weapon now works on the sheet (core/rules/
# pass_items.gd: to hit and damage), but its attacks are not marked magical,
# so the clause is still always satisfied and a +1 sword is still halved by a
# wraith. ponytail: marking an item-enchanted attack magical, and letting it
# past these lists, is the next step for magic weapons (the coin-and-xp entry's
# Still open); this is the one function that has to learn the difference.
#
# "Always satisfied" reads differently on the two lists, and reading them the
# same way was a bug rather than a simplification. On a RESISTANCE (32 entries:
# specters, wraiths, elementals, most of the devils) it means the halving always
# applies, which is a hard fight and nothing worse. On an IMMUNITY it means the
# creature cannot be hurt by a weapon AT ALL, ever, by any party in this game —
# and 23 entries carry one: all nineteen lycanthropes, the couatl, and all three
# golems. A level-3 trio put in a room with a flesh golem swung at AC 8 for six
# rounds, logged "is immune to slashing — 0 damage" every time, and lost 40 of
# 40 seeds (tests/sweep_faction_boss.gd, before this).
#
# So a qualified immunity is demoted to a resistance. That is the honest reading
# of the same sentence rather than a softening of it: the creature shrugs a
# mundane weapon, which is what this engine's `resist` means, and RAW's own
# answer to the golem is a weapon the party is allowed to go and find. "Immune"
# here would be a statement the rules never make — that no weapon works —
# because the qualifier the SRD uses to make it false is not modelled. When
# magic weapons become gear, the qualified list moves back to `immune` for
# anyone still swinging plain steel and this note goes with it.
const NONMAGICAL_CLAUSE := " from nonmagical weapon"

# The damage types a prose list names, split by whether the entry carried a
# weapon clause. `plain` holds unconditionally; `qualified` holds only while the
# party's weapons are mundane, which in this game is always.
static func _damage_types_split(list) -> Dictionary:
	var plain: Array = []
	var qualified: Array = []
	for entry in list:
		var s := String(entry).to_lower()
		var cut := s.find(NONMAGICAL_CLAUSE)
		var into: Array = plain
		if cut >= 0:
			s = s.substr(0, cut)
			into = qualified
		for part in s.replace(" and ", ", ").split(","):
			var t := part.strip_edges()
			if t != "" and not t in into:
				into.append(t)
	return {"plain": plain, "qualified": qualified}

static func _damage_types(list) -> Array:
	var d: Dictionary = _damage_types_split(list)
	var out: Array = d["plain"]
	for t in d["qualified"]:
		if not t in out:
			out.append(t)
	return out

# Unspent slots per level, the sheet's full set less slots_used.
static func slots_left(ch) -> Array[int]:
	var left := _full_slots(ch.sheet())
	for i in mini(9, ch.slots_used.size()):
		left[i] = maxi(0, left[i] - int(ch.slots_used[i]))
	return left

# 4.1 of the design audit: the one reading of a caster's slots that every screen
# shows (the sheet, the party page's rows and the combat pips), so the price of
# a spell is the same number wherever the player looks. One row per slot level
# the build has: {level, left, max, pact}. `max` is the SHEET's maximum, never
# the count a fight started with, so a slot spent three fights ago is an empty
# pip rather than a pip that is not there, and a level with none left is still
# a row. `left` can pass `max`: a slot Font of Magic made and did not spend is
# carried as a negative slots_used (write_back below), and it is a real slot
# until the long rest. `pact` marks the warlock's Pact Magic level, which
# _full_slots() folds into the same array.
static func slot_rows(full: Array, left: Array, pact_level := 0) -> Array:
	var out: Array = []
	for i in mini(9, full.size()):
		var mx := int(full[i])
		var l := int(left[i]) if i < left.size() else 0
		if mx <= 0 and l <= 0:
			continue
		out.append({"level": i + 1, "left": l, "max": mx, "pact": i + 1 == pact_level})
	return out

static func _pact_level(s) -> int:
	if s == null or not "spellcasting" in s:
		return 0
	var pact: Dictionary = s.spellcasting.get("pact", {})
	return int(pact.get("slotLevel", 0)) if not pact.is_empty() else 0

# A Character between fights: the sheet's maximum against slots_used.
static func slot_table(ch) -> Array:
	var s = ch.sheet()
	return slot_rows(_full_slots(s), slots_left(ch), _pact_level(s))

# A Combatant mid-fight: its sheet's maximum against the slots it has left. A
# foe built from the bestiary has no sheet, so `fallback` (what it walked on
# with) is its maximum; nobody spent a monster's slots before this fight.
static func combat_slot_table(c, fallback: Array = []) -> Array:
	var has_sheet: bool = c.sheet != null and "spellcasting" in c.sheet
	var full: Array = _full_slots(c.sheet) if has_sheet else fallback
	if full.is_empty():
		full = c.slots
	return slot_rows(full, c.slots, _pact_level(c.sheet) if has_sheet else 0)

# A row as pips: ● a slot left, ○ one spent. The combat actor line and the party
# page both draw it with this, so the two agree at a glance.
static func slot_pips(row: Dictionary) -> String:
	var l := int(row["left"])
	return "L%d %s%s" % [int(row["level"]), "●".repeat(l), "○".repeat(maxi(0, int(row["max"]) - l))]

# Short/long rest: refill the pools that regain on it, all spell slots on a long
# rest, and HP on a long rest. T6's rest node is the caller.
# Returns the slot levels a short rest's Arcane Recovery brought back ([] for
# everyone else, and for every long rest), so the rest's message can say so.
static func rest(ch, kind: String) -> Array:
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
		return arcane_recovery_auto(ch)   # RAW: "when you finish a Short Rest"
	ch.dirty()
	return []

# What T7 persists when a fight ends: HP, spent slots, spent pool uses.
# Statuses and position belong to the fight and are dropped.
static func write_back(c, ch) -> void:
	# #107: somebody down but stable when the fight ends comes to at 1 HP —
	# RAW's "a stable creature regains 1 HP after 1d4 hours", spent on the walk
	# out. Otherwise they started the NEXT fight unconscious on the ground.
	ch.hp_current = c.hp if c.is_dead() else maxi(1, c.hp)
	for pid in c.pools:
		ch.pools[pid] = int(c.pools[pid]["cur"])
	# Not floored at zero: a slot Font of Magic made in the fight and did not
	# spend is carried out as a NEGATIVE entry — one more than the sheet's full
	# set — and every reader already works in "full less used". A long rest
	# clears slots_used, which is RAW's "vanishes when you finish a Long Rest".
	var full: Array = _full_slots(c.sheet) if c.sheet else []
	var used: Array[int] = []
	for i in full.size():
		used.append(int(full[i]) - int(c.slots[i]))
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

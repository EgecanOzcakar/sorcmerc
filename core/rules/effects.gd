# feature id / spell id / condition id -> combat mechanics.
# The export carries none of these (SCHEMA gaps #3, #4, #9), so data/effects/*.json
# is sorcmerc-authored. A feature with no entry is a FLAVOR feature: it shows on the
# sheet and does nothing in combat. That default is what makes 430 feature ids tractable.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const KINDS := ["passive_damage", "self_buff", "ally_buff", "heal_self", "heal_ally",
	"grant_action", "grant_verb", "attacks_per_action", "attack_modifier", "damage_bonus",
	"save_effect", "reaction",
	# T94. None of the three is ever a button: `save_modifier` and `keen_senses`
	# are passives combat.gd reads where it already computes a save or a hide DC,
	# and `survive_damage` fires from _apply_damage on the blow that would drop
	# its owner. See OFFERABLE / is_button in core/combat.gd.
	"save_modifier", "survive_damage", "keen_senses",
	# T-classes-c. `aura` is a standing fact about a piece of the board rather
	# than anything anyone presses — combat.aura_bonus() reads it at the moment a
	# number is needed, and it is deliberately NOT in combat.gd's OFFERABLE, so
	# it never reaches the action bar and needs no badge.
	"aura",
	# T-summon. A second token on the board, run by whoever runs its owner's
	# side. `summon` is {id, illusion?}; `mult` scales the stat block off the
	# owner's level, `rounds` puts a clock on it. combat.summon() does the work.
	"summon",
	# Font of Magic (2024). One authored entry, expanded by verbs_for() into a
	# button per slot level each way — see _font_verbs and combat._font_of_magic.
	"font_of_magic",
	# Metamagic (2024): arms the next spell (combat._cast_view / _take_metamagic).
	"metamagic"]

# castingTime -> action-economy cost. Anything longer than a Reaction is non-combat.
const CASTING_TIME := {"Action": "action", "Bonus Action": "bonus", "Reaction": "reaction"}

# The trigger vocabulary a reaction can hang off. combat.gd fires every one of
# these and resolves the answer with no prompt (combat-design.md §2); this list
# is here rather than there so validate() can refuse a trigger nothing fires.
# T94 adds "would_be_hit": fired from resolve_attack once a swing is known to
# land but before it does, which is the moment Parry's "against one melee attack
# that would hit it" describes.
const REACTION_TRIGGERS := ["hit_by_attack", "damaged_by_attack", "spell_cast", "would_be_hit"]

static func feature(id: String) -> Dictionary:
	var d = Catalog.all("effects/features.json")
	return d.get(id, {}) if d is Dictionary else {}

static func condition(id: String) -> Dictionary:
	var d = Catalog.all("effects/conditions.json")
	return d.get(id, {}) if d is Dictionary else {}

# spells[].mechanics as the draft, data/effects/spells.json layered over it.
# {} when the spell is not combat-castable.
static func spell(id: String) -> Dictionary:
	var def := Catalog.spell(id)
	var merged := {}
	var draft = def.get("mechanics")
	if draft is Dictionary:
		merged.merge(draft)
	var over = Catalog.all("effects/spells.json")
	if over is Dictionary and over.has(id):
		merged.merge(over[id], true)
	if not merged.has("cost"):
		var t = CASTING_TIME.get(def.get("castingTime", ""))
		if t == null:
			return {}
		merged["cost"] = t
	if merged.get("non_combat", false):
		return {}
	# The regex draft writes damage as {"dice": "8d6"}; the verb builder reads
	# count/sides. An unauthored damage entry used to fall through as 1d6 —
	# a 5th-level Flame Strike doing a dagger's worth. Now it is no damage at
	# all, and the spell is not castable until someone authors it.
	if merged.has("damage") and not _authored_damage(merged["damage"]):
		merged.erase("damage")
	if not (merged.has("damage") or merged.has("heal") or merged.has("healing")
			or merged.has("conditions") or merged.has("buff") or merged.has("teleport")
			or merged.has("summon") or merged.has("reaction")   # a reaction block is a mechanic too (Counterspell)
			or merged.has("temp_hp")):
		return {}
	merged["level"] = int(def.get("level", 0))
	merged["concentration"] = def.get("concentration", false)
	# The export's "range" is prose ("60 feet", "Touch", "Self (15-foot cone)");
	# an authored range_ft wins, otherwise read it off the prose so Hold Person
	# is not a touch spell. Self-origin shapes stay 5: the size is the cone.
	if not merged.has("range_ft"):
		merged["range_ft"] = range_ft(String(def.get("range", "")))
	return merged

static func _authored_damage(d) -> bool:
	return d is Array and not d.is_empty() and d[0] is Dictionary and d[0].has("count") and d[0].has("sides")

# Spells with a door off the board — cast on the road (core/road_spells.gd)
# or changing a roll the party already makes (travel.gd SPELL_PASS,
# settlement_visit.gd TALK_SPELLS / WORK_SPELLS, encounter.gd Pass Without
# Trace). Listed here rather than read from those files so this one has no
# preload of the modules that preload it; tests/test_road_spells.gd checks
# the list against them.
const OFF_BOARD := ["clairvoyance", "arcane-eye", "fly", "longstrider", "rope-trick", "alarm",
	"speak-with-animals", "pass-without-trace", "detect-thoughts",
	"suggestion", "lesser-restoration", "greater-restoration"]

# Spells a character may pick at creation / level-up: the ones that do
# something on the board or have a door off it. A utility spell with neither
# would be a slot spent on nothing.
static func pick_pool(list: String, level: int) -> Array:
	return Catalog.spell_list(list, level).filter(func(id): return id in OFF_BOARD or not spell(id).is_empty())

static func range_ft(prose: String) -> int:
	var t := prose.split(" ")
	if t.size() >= 2 and t[1] == "feet":
		return int(t[0])
	if t.size() >= 2 and t[1] == "mile":
		return 5280
	return 5   # Touch, Self, Self (...), Unlimited

# {by: "class_level"|"pb"|"ability_mod", class?, ability?, steps?, formula?} -> int.
# A plain number passes through.
static func scale(spec, sheet) -> int:
	if spec is float or spec is int:
		return int(spec)
	if not spec is Dictionary or sheet == null:
		return 0  # a monster has no sheet: its effect entries must carry plain numbers
	var n := 0
	match spec.get("by", ""):
		"class_level": n = sheet.class_level(spec.get("class", ""))
		"pb": n = sheet.proficiency_bonus
		"ability_mod": n = sheet.mod(spec.get("ability", "str"))
		_: return 0
	if spec.has("steps"):
		var best := -1
		var v := 0
		for s in spec["steps"]:
			if n >= int(s["min"]) and int(s["min"]) > best:
				best = int(s["min"])
				v = int(s["value"])
		return v
	match spec.get("formula", ""):
		"ceil_half": return ceili(n / 2.0)
		"floor_half": return floori(n / 2.0)
	return n

# Fully numeric combat verbs for a sheet. Resolved once, at adapter time, so
# combat.gd never re-reads the sheet mid-turn.
static func verbs_for(sheet, feature_ids = null) -> Array:
	var out: Array = []
	for fid in (sheet.features if feature_ids == null else feature_ids):
		var e := feature(fid)
		if e.is_empty():
			continue  # flavor feature
		var v := _verb_from(String(fid), e, sheet)
		if e.has("slot_dice") and sheet != null:
			# Divine Smite: one button per slot level the paladin can spend,
			# base dice plus one per level above the first — a spell's upcast.
			var sd: Dictionary = e["slot_dice"]
			var slots: Array = sheet.spellcasting.get("slots", [])
			for lvl in range(1, 10):
				if lvl - 1 >= slots.size() or int(slots[lvl - 1]) <= 0:
					continue
				var s := v.duplicate(true)
				s["slot_level"] = lvl
				s["dice_count"] = int(sd.get("base", 2)) + int(sd.get("per_level", 1)) * (lvl - 1)
				if lvl > 1:
					s["id"] = "%s@%d" % [fid, lvl]
					s["label"] = "%s ★%d" % [v["label"], lvl]
				out.append(s)
		elif e.has("font") and sheet != null:
			out.append_array(_font_verbs(String(fid), v, e["font"], sheet))
		else:
			out.append(v)
		# A feature that is two mechanics at once (Assassinate: advantage AND a
		# damage rider) authors the second under `also`, keyed off the same id.
		var i := 0
		for sub in e.get("also", []):
			i += 1
			out.append(_verb_from("%s#%d" % [fid, i], sub, sheet))
	return out

# Font of Magic, one button per slot level each way (2024 PHB):
#   "<id>-burn@L"  spend a level-L slot for L sorcery points. No action.
#   "<id>@slotL"   spend `cost` points for a level-L slot, a Bonus Action, once
#                  the sorcerer is `min` levels in. The table tops out at 5th,
#                  as RAW does.
# A slot level the sheet has none of offers no conversion out of it; the
# creation table is read at the sorcerer's own level, not the character's.
# The burn buttons carry an id of their own on purpose: Icons.skill_icon finds
# no skills/ badge for it and falls to the font_of_magic kind's, so the two
# directions are two different pictures on the bar. The ★ ends the label, which
# is where the bar reads a button's corner tier from (scenes/main.gd).
static func _font_verbs(fid: String, base: Dictionary, font: Dictionary, sheet) -> Array:
	var out: Array = []
	var title: String = String(base["label"])
	var slots: Array = sheet.spellcasting.get("slots", [])
	for l in range(1, 10):
		if l - 1 >= slots.size() or int(slots[l - 1]) <= 0:
			continue
		var v := base.duplicate(true)
		v.erase("pool")
		v.erase("uses")
		v["id"] = "%s-burn@%d" % [fid, l]
		v["font"] = "to_points"
		v["from_slot"] = l
		v["cost"] = "free"
		v["label"] = "%s: burn a slot for %d SP ★%d" % [title, l, l]
		out.append(v)
	var lvl: int = sheet.class_level(String(font.get("class", "sorcerer")))
	for row in font.get("create", []):
		if lvl < int(row["min"]):
			continue
		var v := base.duplicate(true)
		var l := int(row["level"])
		v["id"] = "%s@slot%d" % [fid, l]
		v["font"] = "to_slot"
		v["make_slot"] = l
		v["pool_cost"] = int(row["cost"])
		v["cost"] = "bonus"
		v["label"] = "%s: %d SP for a slot ★%d" % [title, int(row["cost"]), l]
		out.append(v)
	return out

# The keys a data/effects/features.json entry may carry that are copied onto the
# verb as they are. Public vocabulary: a content pack writes these (docs/
# modding.md §5.1), and tests/test_mod_api.gd holds a snapshot of the list, so
# a key cannot be dropped or renamed without the modding API saying so.
const VERB_KEYS := ["trigger", "once_per", "requires", "verbs", "status", "duration", "resist",
	"save", "conditions", "shape", "range_ft", "halve_damage", "self",
	"attacks_against", "extra_attacks", "value", "damage_type",
	# T94: save_modifier / survive_damage / keen_senses / Parry
	"vs", "ac_bonus", "dc", "dc_plus_damage", "except", "max_damage",
	"relies_on", "passive_bonus", "magical",
	# T-classes-c: a reaction that imposes Disadvantage rather than
	# adding AC (Warding Flare), the aura payloads, and `once` —
	# the flag that separates a Smite from a Rage.
	"disadvantage", "cond_immune", "once", "aura_resist",
	# T-summon
	"summon", "rounds",
	# 2026-09-19 (2024 PHB pass): advantage on initiative, Ambusher's
	# Leap, Hand of Healing's Flurry swap, Stunning Strike's made-save
	# rider, Parry's melee-only clause, Rage's own clock
	"init_adv", "first_round_speed_ft", "flurry_swap", "on_save_vex", "melee_only",
	# Innate Sorcery (2024): +1 spell save DC, Advantage on spell attacks
	"spell_dc_bonus", "spell_attack_adv",
	# Metamagic: which option, and its sorcery-point price
	"option", "pool_cost"]

static func _verb_from(fid: String, e: Dictionary, sheet) -> Dictionary:
		assert(e["kind"] in KINDS, "unknown effect kind \"%s\" on \"%s\"" % [e.get("kind"), fid])
		# An authored `label` wins: "monster-relentless-10" is the id that keeps the
		# three SRD thresholds apart, but the log should just say "Relentless".
		var v := {"id": fid, "kind": e["kind"], "cost": e.get("cost", "action"),
			"label": String(e.get("label", verb_label(fid.get_slice("#", 0)))),
			"targeting": e.get("targeting", TARGETING.get(e["kind"], "self"))}
		for k in VERB_KEYS:
			if e.has(k):
				v[k] = e[k]
		if e.has("max_dice"):   # Healing Light: up to CHA-mod dice in one use
			v["max_dice"] = maxi(1, scale(e["max_dice"], sheet))
		if e.has("dice"):
			var d: Dictionary = e["dice"]
			v["dice_count"] = scale(d.get("count", 1), sheet)
			v["dice_sides"] = scale(d.get("sides", 6), sheet)
			v["dice_bonus"] = scale(d.get("plus", 0), sheet)
		if e.has("bonus_damage"):
			v["bonus_damage"] = scale(e["bonus_damage"], sheet)
		if e.has("save_bonus"):          # an aura's payload; CHA mod for a paladin
			v["save_bonus"] = maxi(1, scale(e["save_bonus"], sheet))
		if e.has("mult_pct"):
			# A summon's stat block scaled off its owner. Authored as whole
			# percent because `scale` deals in ints and steps: the ranger's beast
			# is meant to grow with the ranger, and 70/90/110 is that curve
			# written where the rest of the curves already live.
			v["mult"] = maxi(10, scale(e["mult_pct"], sheet)) / 100.0
		if e.has("amount"):
			v["amount"] = scale(e["amount"], sheet)
		if e.has("pool"):
			v["pool"] = e["pool"]
			v["uses"] = sheet.pool_max(e["pool"])
			# A named pool the sheet was granted none of. The Cleric's Channel
			# Divinity is the case: the export emits the `resource-pool` grant for
			# the paladin's and not for the cleric's (SCHEMA gap #4), so the button
			# was built with 0 uses, adapter.gd synthesized a 0-max pool from it,
			# and the feature has been on the bar greyed out and unpressable ever
			# since. An authored `uses` is the fallback when the export has none.
			if int(v["uses"]) == 0 and e.has("uses"):
				v["uses"] = _uses(e["uses"], sheet)
		elif e.has("uses"):
			v["pool"] = fid          # synthetic pool: the export grants no pool for this feature
			v["uses"] = _uses(e["uses"], sheet)
		return v

# An authored `uses`, floored at one. Several are sized off an ability modifier
# and RAW says "a minimum of once" every time (Warding Flare, Divine Smite);
# without the floor a cleric who dumped WIS would carry the button and never be
# able to press it — the 0-max-pool bug T-classes fixed once from the other end.
static func _uses(spec, sheet) -> int:
	return maxi(1, scale(spec, sheet))

# Who a verb is pointed at. combat.gd's available()/legal_target() read this.
const TARGETING := {"heal_ally": "ally", "ally_buff": "ally", "save_effect": "enemy",
	"summon": "self"}   # it arrives in the free hex nearest its owner; there is nothing to aim

# One verb per castable spell, per slot level it can be cast at. Ranges stay in FEET
# here — adapter.gd owns the hex conversion (spec §2.5).
static func spell_verbs_for(sheet, spell_ids: Array, slots_override: Array = []) -> Array:
	var out: Array = []
	var sc: Dictionary = sheet.spellcasting
	if sc.is_empty():
		return out
	# Pact Magic slots live in `pact`, not `slots` (spec §2.5 / adapter._full_slots
	# merges them for combat) — a warlock with no override here would see 0 slots
	# at every level and get no cast verbs at all.
	var slots: Array = slots_override if not slots_override.is_empty() else sc.get("slots", [])
	var abil_mod: int = sheet.mod(sc.get("ability", "wis"))
	for sid in spell_ids:
		var m := spell(sid)
		if m.is_empty():
			continue
		var base := int(m.get("level", 0))
		var top := base
		if base > 0:                     # cantrips scale with level, not with slots
			for l in range(base, 10):
				if l - 1 < slots.size() and int(slots[l - 1]) > 0:
					top = l
		if m.has("reaction") and not m.has("upcast"):
			top = base   # a bigger slot counters exactly what the smallest one does
		if m.has("summon") and not m.has("upcast"):
			# #123: and a bigger slot calls exactly the same creature. The tier
			# picker offering ★3/★4/★5 that resolve to one stat block is a row
			# of buttons for spending a better slot on nothing.
			top = base
		for lvl in range(base, top + 1):
			out.append(_spell_verb(sid, m, lvl, base, sheet, abil_mod, int(sc.get("save_dc", 0))))
	return out

static func _spell_verb(sid: String, m: Dictionary, lvl: int, base: int, sheet,
		abil_mod: int, dc: int) -> Dictionary:
	var up := lvl - base
	var shape: String = m.get("shape", "single")
	var v := {
		"id": sid if up == 0 else "%s@%d" % [sid, lvl], "spell": sid, "kind": "spell",
		"label": Catalog.spell(sid).get("name", humanize(sid)) + ("" if up == 0 else " ★%d" % lvl),
		"cost": m.get("cost", "action"), "slot_level": lvl, "shape": shape,
		"range_ft": int(m.get("range_ft", 5)), "size_ft": int(m.get("size_ft", 0)),
		"save": m.get("save", ""), "save_dc": dc, "half_on_save": m.get("half_on_save", false),
		"ignores_cover": m.get("ignores_cover", false),
		"concentration": m.get("concentration", false),
	}
	if m.get("spare_allies", false):
		v["spare_allies"] = true
	if m.get("zone", false):       # lingers on its hexes (combat.gd zones)
		v["zone"] = true
		v["rounds"] = int(m.get("rounds", 10))
	if m.get("teleport", false):   # Misty Step: aim a free hex, arrive there, provoke nothing
		v["teleport"] = true
	if m.has("summon"):            # Summon Beast: a bestiary creature on the caster's side
		v["summon"] = m["summon"]
		v["text"] = String(m.get("text", ""))
		# Issue #123: every summon spell before Spiritual Weapon was held by
		# concentration, so combat.summon()'s other clock — `rounds` — was
		# never handed one. A summon with neither stands on the board until the
		# fight ends, which is not what "1 minute" means.
		if not v["concentration"] and m.has("rounds"):
			v["rounds"] = int(m["rounds"])
	if m.has("buff"):     # Bless, Haste, Bane: a status the target wears (combat.gd _apply_buff)
		v["buff"] = m["buff"]
		v["rounds"] = int(m.get("rounds", 10))
		v["text"] = String(m.get("text", ""))
	if m.has("attack"):   # a spell attack rolls to hit instead of forcing a save
		v["attack_bonus"] = int(sheet.spellcasting.get("attack_bonus", 0))
	if m.has("reaction"):
		# Not a button (combat.is_button refuses anything costing a reaction) —
		# combat.gd fires `trigger` and casts this itself.
		var rx: Dictionary = m["reaction"]
		v["trigger"] = rx.get("trigger", "")
		v["counter"] = rx.get("counter", false)
		v["min_level"] = int(rx.get("min_level", 0))
		if rx.has("ac_bonus"):   # Shield: +5 AC against the blow that would have hit
			v["ac_bonus"] = int(rx["ac_bonus"])
	if m.has("conditions"):
		# A save-or-suffer spell. Default "round" (until the target's next turn):
		# apply_condition's other duration is "forever", and nothing in the engine
		# ends a concentration spell, so an unauthored duration would be a lockout.
		v["conditions"] = m["conditions"]
		# A concentration spell's conditions last while the caster holds it (up
		# to combat.gd's CONCENTRATION_ROUNDS); the target repeats its save as
		# `repeat_save` says — end of its turn by default, "on_damage", or
		# "damage_ends" (any damage breaks it), "none" for the full duration.
		v["duration"] = m.get("duration", "concentration" if m.get("concentration", false) else "round")
		v["repeat_save"] = m.get("repeat_save", "end_turn")
		# Charm/Hold Person and kin: one more creature per slot level above base.
		if up > 0 and m.has("upcast") and int(m["upcast"]["per_level"].get("targets", 0)) > 0:
			v["targets"] = 1 + up * int(m["upcast"]["per_level"]["targets"])
	if m.has("rays"):     # Scorching Ray: several independent attack rolls, one cast
		var rays := int(m["rays"])
		if up > 0 and m.has("upcast"):
			rays += up * int(m["upcast"]["per_level"].get("rays", 0))
		if base == 0:     # Eldritch Blast: one beam more at 5, 11 and 17
			rays = _cantrip_scale(m, rays, sheet.level, "rays")
		v["rays"] = rays
	if m.has("damage"):
		var d: Dictionary = m["damage"][0]
		var n := int(d.get("count", 1))
		var plus := int(d.get("plus", 0))   # Magic Missile's +1 a dart
		if up > 0 and m.has("upcast"):
			n += up * int(m["upcast"]["per_level"].get("count", 0))
			plus += up * int(m["upcast"]["per_level"].get("plus", 0))
		if base == 0:
			n = _cantrip_count(m, n, sheet.level)
		v["dice_count"] = n
		v["dice_sides"] = int(d.get("sides", 6))
		v["damage_type"] = d.get("type", "")
		if plus != 0:
			v["dice_bonus"] = plus
	if m.has("temp_hp"):  # False Life, Heroism: temporary hit points, never a heal
		var t: Dictionary = m["temp_hp"]
		v["temp_count"] = int(t.get("count", 0)) + (up * int(m["upcast"]["per_level"].get("temp_count", 0)) if up > 0 and m.has("upcast") else 0)
		v["temp_sides"] = int(t.get("sides", 4))
		v["temp_bonus"] = (abil_mod if str(t.get("plus", "")) == "ability_mod" else int(t.get("plus", 0))) \
			+ (up * int(m["upcast"]["per_level"].get("temp_plus", 0)) if up > 0 and m.has("upcast") else 0)
	if m.has("heal"):
		var h: Dictionary = m["heal"]
		var n := int(h.get("count", 1))
		if up > 0 and m.has("upcast"):
			n += up * int(m["upcast"]["per_level"].get("count", 0))
		v["heal_count"] = n
		v["heal_sides"] = int(h.get("sides", 8))
		v["heal_bonus"] = abil_mod if str(h.get("plus", "")) == "ability_mod" else int(h.get("plus", 0))
	if m.get("teleport", false):
		v["targeting"] = "hex"
	elif m.has("summon"):
		v["targeting"] = "self"
	elif shape == "cone":
		v["targeting"] = "direction"
	elif shape == "line":
		v["targeting"] = "line"          # aimed at a hex, runs its full length through it
	elif shape == "emanation":
		v["targeting"] = "self_area"     # everything within size_ft of the caster
	elif shape in ["sphere", "cube", "cylinder", "radius"]:
		v["targeting"] = "area"          # adapter.gd sizes it: one hex, or a corner-anchored circle
	elif shape == "self":
		v["targeting"] = "self"
	elif shape == "allies":
		v["targeting"] = "allies"        # everyone on the caster's side within range, caster included
	else:
		v["targeting"] = "ally" if (v.has("heal_count") or v.has("temp_count") or (v.has("buff") and v.get("save", "") == "" \
			and not m.has("attack"))) else "enemy"
	return v

static func _cantrip_count(m: Dictionary, n: int, char_level: int) -> int:
	return _cantrip_scale(m, n, char_level, "count")

# cantrip_scale: [{min, count}] for dice, [{min, rays}] for beams (Eldritch Blast).
static func _cantrip_scale(m: Dictionary, n: int, char_level: int, key: String) -> int:
	for s in m.get("cantrip_scale", []):
		if char_level >= int(s["min"]) and s.has(key):
			n = int(s[key])
	return n

# Fallback until F1 re-exports feature/pool prose (SCHEMA gap #4).
#
# capitalize() title-cases every word, which is right until an id has a small
# word in it: "rogue-stroke-of-luck" came back "Stroke Of Luck" and
# "zealot-rage-of-the-gods" came back "Rage Of The Gods". Sentence case with
# the joining words left down reads as a name instead of a headline, and the
# level ladder (core/climb.gd) puts a great many of these on one screen.
const SMALL_WORDS := ["of", "the", "and", "a", "an", "to", "in", "on", "or", "at", "from", "with"]

static func humanize(id: String) -> String:
	var words: PackedStringArray = id.replace("-", " ").capitalize().split(" ")
	for i in range(1, words.size()):
		if words[i].to_lower() in SMALL_WORDS:
			words[i] = words[i].to_lower()
	return " ".join(words)

# Feature ids are "<class>-<name>"; a button says "Second Wind", not "Fighter Second Wind".
static func verb_label(id: String) -> String:
	var p := id.split("-")
	return humanize("-".join(p.slice(1)) if p.size() > 1 else id)

# Where a feature came from, as a sheet would caption it: "Cleric", "Feat",
# "Light Domain", "Elf". The id's first segment, looked up where it is a
# subclass (whose ids run words together: "lightdomain").
static func feature_source(id: String) -> String:
	var head := id.get_slice("-", 0)
	var sub: Dictionary = Catalog.subclass_src(head)
	if not sub.is_empty():
		return String(sub.get("name", head))
	return humanize(head)

# Validates the three hand-authored files: closed `kind` vocabulary, known ids.
static func validate() -> Array[String]:
	var errs: Array[String] = []
	var f = Catalog.all("effects/features.json")
	if not f is Dictionary:
		return ["effects/features.json did not load"] as Array[String]
	for id in f:
		if id.begins_with("_"):
			continue
		if not f[id].get("kind") in KINDS:
			errs.append("features.json: \"%s\" has unknown kind \"%s\"" % [id, f[id].get("kind")])
		# A reaction nothing fires is a feature that silently does nothing.
		if f[id].get("cost", "") == "reaction" and not f[id].get("trigger", "") in REACTION_TRIGGERS:
			errs.append("features.json: \"%s\" is a reaction with no fired trigger (\"%s\")"
				% [id, f[id].get("trigger", "")])
		# An aura with no reach is a fact about nowhere, and one with no payload
		# is a fact about nothing — combat.aura_bonus() would read neither.
		if f[id].get("kind", "") == "aura":
			if int(f[id].get("range_ft", 0)) <= 0:
				errs.append("features.json: aura \"%s\" has no range_ft" % id)
			if not f[id].has("save_bonus") and not f[id].has("cond_immune") \
					and not f[id].has("aura_resist"):
				errs.append("features.json: aura \"%s\" carries no payload" % id)
		# A summon naming a stat block nobody exported is a button that spends a
		# use of Channel Divinity and stands nothing up.
		if f[id].get("kind", "") == "summon":
			var mid := String(f[id].get("summon", {}).get("id", ""))
			if mid == "" or Catalog.monster(mid).is_empty():
				errs.append("features.json: summon \"%s\" names no stat block (\"%s\")" % [id, mid])
	var sp = Catalog.all("effects/spells.json")
	for id in sp:
		if id.begins_with("_"):
			continue
		if Catalog.index("spells.json").get(id) == null:
			errs.append("spells.json: \"%s\" is not in the catalog" % id)
		if sp[id].has("damage") and not _authored_damage(sp[id]["damage"]):
			errs.append("spells.json: \"%s\" damage needs count/sides" % id)
		# Same rule from the other side: a reaction-cost spell with no reaction
		# block is never a button and never fires — it is simply unreachable.
		if sp[id].get("cost", "") == "reaction":
			var trig = sp[id].get("reaction", {}).get("trigger", "")
			if not trig in REACTION_TRIGGERS:
				errs.append("spells.json: \"%s\" is a reaction with no fired trigger (\"%s\")"
					% [id, trig])
	var cn = Catalog.all("effects/conditions.json")
	for id in cn:
		if not id.begins_with("_") and Catalog.index("conditions.json").get(id) == null:
			errs.append("conditions.json: \"%s\" is not in the catalog" % id)
	return errs

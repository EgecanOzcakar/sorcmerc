# Level-up: append a level, re-resolve, hand the new pending choices to the UI.
# Thin by design (spec §4) — every grant a level brings (subclass at 3, ASI/feat,
# new spells, a bigger pool) already arrives through resolve.gd's `pending` list,
# so there is no level-up rule engine here, only the loop around it.
#
#   Leveling.add_level(ch)            # +1 in the character's own class
#   for p in Leveling.pending(ch): ...  # render with creator.gd's choice statics
#   Leveling.decide(ch, p["key"], d)
#   Leveling.can_finalize(ch)
extends RefCounted

const Save = preload("res://core/character_save.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")

# hp_roll sentinel: the resolver substitutes die/2+1 (spec §4, save format's -1).
const AVERAGE := -1

# The 5e cumulative XP table: XP_TABLE[n] is the total XP needed to reach level n+1.
const XP_TABLE := [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
	85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000]
const MAX_LEVEL := 20

static func xp_for_level(level: int) -> int:
	return int(XP_TABLE[clampi(level, 1, MAX_LEVEL) - 1])

static func can_level_up(ch) -> bool:
	return ch.level() < MAX_LEVEL and int(ch.xp) >= xp_for_level(ch.level() + 1)

# 0 when already eligible (or at the cap) — the UI shows "need N more XP" while > 0.
static func xp_to_next(ch) -> int:
	if can_level_up(ch) or ch.level() >= MAX_LEVEL:
		return 0
	return xp_for_level(ch.level() + 1) - int(ch.xp)

static func add_level(ch, class_id := "", hp_roll := AVERAGE) -> void:
	ch.add_level(class_id if class_id != "" else ch.class_id(), hp_roll)
	milestones(ch)

static func pending(ch) -> Array:
	return ch.sheet().pending

static func decide(ch, key: String, decision: Dictionary) -> void:
	ch.decide(key, decision)
	milestones(ch)   # a spell picked here can be the 5th-level one

# T19: the achievements a character's own sheet can prove. Idempotent, so every
# mutating entry point here can call it. preview() deliberately does NOT — it
# levels a throwaway clone, and looking at level 5 is not reaching it.
static func milestones(ch) -> void:
	var lvl: int = ch.level()
	if lvl >= 5:
		Ach.unlock("level_5")
	if lvl >= MAX_LEVEL:
		Ach.unlock("level_20")
	if _knows_high_spell(ch):
		Ach.unlock("spell_5th")

# Both halves of the split: a known-caster's `known` list carries its own level,
# a prepared caster (cleric/wizard) only ever names ids, so those cost a lookup.
static func _knows_high_spell(ch) -> bool:
	var sc: Dictionary = ch.sheet().spellcasting
	if sc.is_empty():
		return false
	for k in sc.get("known", []):
		if int(k.get("level", 0)) >= 5:
			return true
	var spells: Dictionary = Catalog.index("spells.json")
	for id in Array(sc.get("always_prepared", [])) + Array(ch.prepared):
		if int(spells.get(id, {}).get("level", 0)) >= 5:
			return true
	return false

static func can_finalize(ch) -> bool:
	return ch.sheet().pending.is_empty()

# What one more level would grant, without touching `ch`: the sheet diff against a
# save-round-trip clone. Drives the level-up screen's "here's what you get" panel.
static func preview(ch, class_id := "") -> Dictionary:
	var probe = Save.from_dict(Save.to_dict(ch))
	probe.add_level(class_id if class_id != "" else probe.class_id(), AVERAGE)   # not add_level(): no milestones off a preview
	return gains(ch.sheet(), probe.sheet())

# before/after are Resolved sheets. Only the things a player reads on level-up.
static func gains(before, after) -> Dictionary:
	var feats: Array = []
	for id in after.features:
		if not before.features.has(id):
			feats.append(id)
	var pools: Array = []
	for p in after.pools:
		if before.pool_max(p["id"]) < int(p["max"]):
			pools.append({"id": p["id"], "from": before.pool_max(p["id"]), "to": int(p["max"])})
	var slots: Array = []
	var was: Array = before.spellcasting.get("slots", [])
	var now: Array = after.spellcasting.get("slots", [])
	for i in now.size():
		var b := int(was[i]) if i < was.size() else 0
		if int(now[i]) > b:
			slots.append({"level": i + 1, "from": b, "to": int(now[i])})
	var styles: Array = []
	for s in after.fighting_styles:
		if not s in before.fighting_styles:
			styles.append(s)
	var subclass := ""
	for cid in after.subclasses:
		if not before.subclasses.has(cid):
			subclass = after.subclasses[cid]
	return {
		"level": after.level,
		"hp": after.max_hp - before.max_hp,
		"proficiency_bonus": after.proficiency_bonus - before.proficiency_bonus,
		"features": feats, "pools": pools, "slots": slots, "styles": styles,
		"subclass": subclass,
		"choices": after.pending.size() - before.pending.size(),
	}

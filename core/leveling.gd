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

# hp_roll sentinel: the resolver substitutes die/2+1 (spec §4, save format's -1).
const AVERAGE := -1

static func add_level(ch, class_id := "", hp_roll := AVERAGE) -> void:
	ch.add_level(class_id if class_id != "" else ch.class_id(), hp_roll)

static func pending(ch) -> Array:
	return ch.sheet().pending

static func decide(ch, key: String, decision: Dictionary) -> void:
	ch.decide(key, decision)

static func can_finalize(ch) -> bool:
	return ch.sheet().pending.is_empty()

# What one more level would grant, without touching `ch`: the sheet diff against a
# save-round-trip clone. Drives the level-up screen's "here's what you get" panel.
static func preview(ch, class_id := "") -> Dictionary:
	var probe = Save.from_dict(Save.to_dict(ch))
	add_level(probe, class_id)
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

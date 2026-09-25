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

# Total XP to reach a level. Not the 5e table: that assumes medium fights for
# a party of four, and open country here pays "easy" fights split three ways
# (measured 2026-09-17 with a throwaway harness that was never committed: 18
# XP each at L1, 39 at L3, 78 at L5, 115 at L8). Against the 5e table that was
# 17 fights to level 2 and 46 to level 4. Each level here costs XP_PER_LEVEL
# more than the last, up to LATE_LEVEL, so a level is six to nine
# open-country fights all the way to 10; sites and quests pay on top of that.
#
# MEASURED 2026-09-25 (tests/sweep_xp.gd, the harness committed; the design
# audit §7.3): the preset trio at each level, fresh, the road's own roster
# (easy x0.90), 60 pinned fights a level, paid by Encounter.resolve_outcome
# and split three ways. XP a hero a fight, and road fights to the next level:
#
#   level      1    2    3    4    5    6    7    8    9   10
#   XP/hero   15   22   39   44   71   87   97  104  118  130
#   fights   6.8  9.1  7.8  9.2  7.1  6.9  7.2  7.7  7.6  7.7
#   level     11   12   13   14   15   16   17   18   19
#   XP/hero  145  154  169  174  181  190  209  226  234
#   fights   6.9  6.5  5.9  5.7  5.5  5.3  4.8  4.4  4.3
#
# A played fight pays 5-10% under the estimate below (the road's x0.90, and a
# foe that runs or outlives a lost fight pays nothing). By country, road
# fights to cross its levels: the Heartland (1-3) 24, the Marches (4-6) 23,
# the Frontier (7-9) 23, the Far Deeps (10-14) 33, the Unmapped (15-19) 24 —
# about 126 road fights from 1 to 20. With one three-fight job
# (Quest.XP_FIGHTS' clear_lair) turned in every four road fights it is about
# 70: 13, 13, 12, 18 and 13. No country is a grind any more; the Deeps are the
# longest, as the deepest country should be.
#
# LATE_LEVEL (2026-09-25, the design audit §5.4): past level 10 every level
# costs what level 10 did, a flat 1,000. With the step still climbing, the Far
# Deeps (levels 10-20) held ~73 of a run's fights against the Heartland's ~15
# — most of the game spent in one country, clearing the same lairs. A flat
# step lets fight XP (which keeps growing with the party) shorten each level.
# ESTIMATED, an easy open-country fight's XP (Regions.fight_xp) split three
# ways, fights to the next level (tests/sweep_economy.gd):
#
#   level    1   3   5   8  10  12  14  16  18  19   total 10->20
#   before  6.2 7.4 6.6 7.0 7.3 7.3 7.3 7.7 7.2 7.3      ~73
#   after   6.2 7.4 6.6 7.0 7.3 6.0 5.2 4.8 4.0 3.8      ~52
#
# Levels 1-10 are untouched (xp_for_level is the same there), so every banked
# XP total below level 11 reads as the level it always did; a hero past 11 on
# an old save simply finds a level-up waiting.
const XP_PER_LEVEL := 100
const LATE_LEVEL := 10
const MAX_LEVEL := 20
# Where a class stops being something a character dabbled in: the subclass is
# in, the signature feature is on the sheet, and the build reads as that class
# rather than as a dip. Same number milestones() already calls level_5 at.
const VETERAN_LEVEL := 5

# Total XP to reach `level`: the sum of the steps below it, each step
# XP_PER_LEVEL x min(level, LATE_LEVEL).
static func xp_for_level(level: int) -> int:
	var l: int = clampi(level, 1, MAX_LEVEL)
	var early: int = mini(l, LATE_LEVEL + 1)
	return XP_PER_LEVEL * early * (early - 1) / 2 + XP_PER_LEVEL * LATE_LEVEL * (l - early)

static func can_level_up(ch) -> bool:
	return ch.level() < MAX_LEVEL and int(ch.xp) >= xp_for_level(ch.level() + 1)

# 0 when already eligible (or at the cap) — the UI shows "need N more XP" while > 0.
static func xp_to_next(ch) -> int:
	if can_level_up(ch) or ch.level() >= MAX_LEVEL:
		return 0
	return xp_for_level(ch.level() + 1) - int(ch.xp)

static func add_level(ch, class_id := "", hp_roll := AVERAGE) -> void:
	ch.add_level(class_id if class_id != "" else ch.class_id(), hp_roll)
	# Here rather than in milestones(): decide() calls that one again for a
	# choice made after the fact, and a spell picked late is not a second level.
	Ach.bump("levels")
	milestones(ch)

# Catch-up levels for a character joining a party that is already several levels
# in (scenes/creator/creator.gd's start_level): append levels in `class_id` until
# the build sits at `target_level`, and bank exactly the XP that level costs so
# the new arrival is not instantly owed another one.
#
# These levels are a gift, not a haul, so nothing here touches core/progression.gd:
# lifetime XP — and the species/class unlocks it buys — only ever counts XP the
# company EARNED: a fight's, a finished job's and a landmark's, all banked by
# core/campaign.gd's split_xp (the owner kept quests and landmarks counting,
# 2026-09-24; this comment used to say "only fight XP", which was never true).
# Milestone achievements stay out for the same reason: being handed level 5 is
# not reaching level 5.
static func grant_levels(ch, target_level: int, class_id := "") -> void:
	var cid: String = class_id if class_id != "" else ch.class_id()
	if cid == "":
		return
	var target: int = clampi(target_level, 1, MAX_LEVEL)
	while ch.level() < target:
		ch.add_level(cid, AVERAGE, true)
	ch.xp = maxi(int(ch.xp), xp_for_level(ch.level()))

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
	if lvl >= 10:
		Ach.unlock("level_10")
	if lvl >= 15:
		Ach.unlock("level_15")
	if lvl >= MAX_LEVEL:
		Ach.unlock("level_20")
	if _knows_high_spell(ch):
		Ach.unlock("spell_5th")
	# What this character is made of, for the profile-wide tallies: every class
	# they hold a level in, every class they hold FIVE in, and every species
	# that has ever been fielded.
	#
	# Two things the "every class" achievement turns on, and it needs both.
	#
	# FIVE IN ONE CLASS, not level five. A fighter 3 / rogue 2 is a level-5
	# character and a veteran of neither trade.
	#
	# EARNED, not handed over. The creator mints a recruit at the party's own
	# level (scenes/creator/creator.gd's start_level), so at a level-5 party a
	# brand new character arrives with five levels in a class nobody has played
	# a round of. grant_levels() does not come through here at all, so those
	# five never tick anything by themselves — but the next level that IS played
	# calls this, and without the `granted` flag it would look back at a full
	# five and hand over the class for one level's work. Counting only what was
	# earned is what makes the achievement mean what it says.
	var classes := {}
	var earned := {}
	for l in ch.levels:
		var cid := String(l["class_id"])
		classes[cid] = true
		Ach.collect("classes", cid)
		if not bool(l.get("granted", false)):
			earned[cid] = int(earned.get(cid, 0)) + 1
	for cid in earned:
		if int(earned[cid]) >= VETERAN_LEVEL:
			Ach.collect("classes_5", String(cid))
	Ach.collect("species", String(ch.species_id))
	if classes.size() >= 2:
		Ach.unlock("multiclass")
	if classes.size() >= 3:
		Ach.unlock("multiclass_3")

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

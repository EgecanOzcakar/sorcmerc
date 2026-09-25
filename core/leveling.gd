# Level-up: append a level, re-resolve, hand the new pending choices to the UI.
# Thin by design (spec §4) — every grant a level brings (subclass at 3, ASI/feat,
# new spells, a bigger pool) already arrives through resolve.gd's `pending` list,
# so there is no level-up rule engine here, only the loop around it.
#
#   Leveling.add_level(ch)            # +1 in the character's own class
#   for p in Leveling.pending(ch): ...  # render with creator.gd's choice statics
#   Leveling.decide(ch, p["key"], d)
#   Leveling.can_finalize(ch)
#   Leveling.left_to_choose(ch)       # the open choices, in words, for a page that will not close
extends RefCounted

const Save = preload("res://core/character_save.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const ChoicePick = preload("res://core/rules/choice_pick.gd")

# hp_roll sentinel: the resolver substitutes die/2+1 (spec §4, save format's -1).
const AVERAGE := -1

# Total XP to reach a level. Not the 5e table: that assumes medium fights for
# a party of four, and open country here pays "easy" fights split three ways
# (measured 2026-09-17, tests/_tmp_xp sweep: 18 XP each at L1, 39 at L3, 78 at
# L5, 115 at L8). Against the 5e table that was 17 fights to level 2 and 46 to
# level 4. Each level here costs XP_PER_LEVEL more than the last, up to
# LATE_LEVEL, so a level is six or seven open-country fights all the way to
# 10; sites and quests pay on top of that.
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

# #235 ("wht choice is left"): what is still open on the build, one short
# name each, in the resolver's order — "Cleric cantrips (pick 3)", "Fighter
# subclass". The level-up and settle-in pages used to refuse Confirm with
# "2 choice(s) still unmade." and nothing else: a count, and a page that
# scrolls past a card and a 430-pixel climb before the rows it meant. Named,
# the refusal says where to look, and the page lists them over the rows.
static func left_to_choose(ch) -> Array[String]:
	var sheet = ch.sheet()
	var open := {}
	for pe in sheet.pending:
		open[String(pe["key"])] = true
	var out: Array[String] = []
	for p in sheet.choice_points:
		if open.has(String(p["key"])):
			out.append(choice_name(p))
	return out

static func choice_name(p: Dictionary) -> String:
	var src := ChoicePick.humanize(String(p.get("source", {}).get("id", "")))
	var n := ChoicePick.pick_count(p)
	var what: String
	match String(p["type"]):
		"spell-choice":
			what = "cantrips" if int(p.get("spellLevel", 1)) == 0 else "level %d spells" % int(p.get("spellLevel", 1))
		"subclass": what = "subclass"
		"asi": what = "ability score increase"
		"feat-choice": what = "feat"
		"feature-choice": what = "option"
		"fighting-style-choice": what = "fighting style"
		"weapon-mastery-choice": what = "weapon masteries"
		"skill-choice": what = "skills"
		"expertise-choice": what = "expertise"
		"language-choice": what = "languages"
		"tool-choice": what = "tools"
		_: what = ChoicePick.humanize(String(p["type"])).to_lower()
	var name := ("%s %s" % [src, what]).strip_edges()
	return name + ("  (pick %d)" % n if n > 1 and p["type"] != "asi" else "")

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

# Rare, named enemy casters: a bestiary statblock fielded with a real spell
# list and real slots rather than the one limited-use innate bolt every
# ordinary spellcaster in the bestiary carries (the owner's call, 2026-09-24:
# "enemy magic is rare and named — an enemy caster is an event").
#
#   EnemyCasters.has("mage")                       # is there a caster block for it?
#   EnemyCasters.ids_for("cultist")                # which of a faction's statblocks can be one
#   EnemyCasters.give_spells(c, "mage", mult)      # turn a spawned Combatant into the caster
#
# The block lives in data/effects/casters.json, keyed by the base bestiary id.
# Everything the fight needs is already on a Combatant — `slots`, `spell_ids`,
# `save_dc`, `verbs` — and core/combat.gd's cast() reads only the verb and the
# caster's slots, never a sheet, so a monster spends and casts exactly as a hero
# does. The one piece that expected a hero is Effects.spell_verbs_for, which
# reads five things off a Resolved sheet; _Sheet below is those five and no
# more, so a statblock gets its buttons from the same builder a hero's come
# from rather than from a second copy of it.
#
# Pricing needs nothing here: core/rules/power.gd already prices spell_ids,
# slots and save_dc on any combatant with the party's own rule (each slot one
# cast of the best spell it pays for, at most ROUNDS casts, the best spell's
# control), so a caster is bought with the budget it is worth.
#
# It does NOT own: when a caster appears (core/scaler.gd's caster elite and
# core/site.gd's cultist boss), what one does on its turn (core/ai.gd's
# _caster_turn), or the "... is a spellcaster" line (core/encounter.gd build).
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Adapter = preload("res://core/adapter.gd")

const FILE := "effects/casters.json"

# How far up the spell levels an enemy caster reaches, by the country it is met
# in (the owner's call, 2026-09-24: "caster tiers by band"). core/rules/power.gd
# prices a caster's slots as at most ROUNDS casts of its best spell and its
# score as sqrt(damage x toughness), which is blind to a glass cannon: a Magister
# with Cone of Cold flattens a level-8 party from range while scoring like a
# modest bruiser — priced as its plain statblock it won 90-98% of level 5-8
# fights (tests/sweep_caster.gd). So what the ruler cannot price is not handed
# out: a caster met in the Heartland or the Marches casts nothing above 2nd
# level, the Frontier 3rd, the Far Deeps anything it knows. Keyed by
# core/regions.gd's band ids; SLOT_CAP_BY_LEVEL is the same table read off a
# party level, for a fight with no map under it (a sweep, the linear route).
const SLOT_CAP := {"heartland": 2, "marches": 2, "frontier": 3, "deeps": 9, "unmapped": 9}
const SLOT_CAP_BY_LEVEL := [[6, 2], [9, 3], [99, 9]]   # [top party level, cap]

# The least tier at which a caster is fielded at all. MEASURED 2026-09-24
# (tests/sweep_caster.gd, tests/sweep_faction_boss.gd, cultist rows, 150-200
# pinned seeds): with the tiers above, the power ruler still misprices a caster
# in both directions — a capped one (2nd-level spells) above its worth, so it
# costs its warband bodies and the fight got EASIER (level-3 lair boss 73.5% ->
# 91.0%, level-5 hard warband 56% -> 86%); a Frontier one with Fireball below
# its worth (level-8 hard warband 54% -> 27%). The one case that measured in
# line is the cult's lair boss at the Frontier tier (tests/sweep_caster_boss.gd,
# 150 seeds: level 6 79.3% -> 63.3%, level 8 72.7% -> 60.0% — a harder climax,
# inside the 15-85% band and beside BOSS_POOL's own low-60s). So a caster is
# only fielded from the Frontier tier up, and below it the statblock fights as
# it always did; the warband roll ships off (Scaler.CASTER_ELITE_CHANCE).
# ponytail: lower this when core/rules/power.gd can price a glass cannon (its
# sqrt(dpr x ehp) and ROUNDS cap are the blind spot).
const MIN_FIELD_CAP := 3

static func fielded(cap: int) -> bool:
	return cap >= MIN_FIELD_CAP

static func cap_for_band(band_id: String) -> int:
	return int(SLOT_CAP.get(band_id, 9))

static func cap_for_level(level: int) -> int:
	for row in SLOT_CAP_BY_LEVEL:
		if level <= int(row[0]):
			return int(row[1])
	return 9
# Encounter._scale's own rate: a scaled caster's spells get harder to shrug off
# at the pace its swings get harder to dodge.
const DC_PER_MULT := 4.0

# The five things Effects.spell_verbs_for and _spell_verb read off a sheet.
class _Sheet:
	var spellcasting: Dictionary
	var level: int
	var abil_mod: int
	func mod(_ability: String) -> int:
		return abil_mod

static func block(id: String) -> Dictionary:
	var d = Catalog.all(FILE)
	if not d is Dictionary or String(id).begins_with("_"):
		return {}
	return d.get(id, {})

static func has(id: String) -> bool:
	return not block(id).is_empty()

# The statblocks of `faction` that can be fielded as a caster, strongest first
# (by CR, then by save DC — a priest and a cult fanatic are both CR 2, and the
# priest's DC 13 and third-level slots are the stronger caster), so a caller
# picking "the best one the budget allows" walks it in order.
static func ids_for(faction: String) -> Array:
	var d = Catalog.all(FILE)
	var out: Array = []
	if not d is Dictionary:
		return out
	for id in d:
		if String(id).begins_with("_"):
			continue
		var m: Dictionary = Catalog.monster(String(id))
		if not m.is_empty() and String(m.get("faction", "")) == faction:
			out.append(String(id))
	out.sort_custom(func(a, b):
		var ca := float(Catalog.monster(a).get("cr", 0))
		var cb := float(Catalog.monster(b).get("cr", 0))
		if ca != cb:
			return ca > cb
		return int(d[a].get("save_dc", 0)) > int(d[b].get("save_dc", 0)))
	return out

# The features the caster block supersedes, for spawn() to strip before the
# statblock is built.
static func replaced(id: String) -> Array:
	return block(id).get("replaces", [])

# Slots, spell ids, the save DC and the spell verbs, on an already spawned (and
# already scaled) Combatant. `mult` is the spawn's stat multiplier, read here
# for the DC the way Encounter._scale reads it for the swing. `cap` is the
# highest spell level it may cast (cap_for_band): slots above it are gone and
# so are the spells that would need them; cantrips always stay.
static func give_spells(c, id: String, mult: float = 1.0, cap := 9) -> void:
	var b := block(id)
	if b.is_empty():
		return
	var dc: int = int(b.get("save_dc", 10)) + roundi((mult - 1.0) * DC_PER_MULT)
	var level: int = maxi(1, int(b.get("level", 1)))
	var pb: int = 2 + (level - 1) / 4
	var slots: Array[int] = []
	for n in b.get("slots", []):
		slots.append(int(n) if slots.size() < cap else 0)
	while slots.size() < 9:
		slots.append(0)
	var sheet := _Sheet.new()
	sheet.level = level
	sheet.abil_mod = dc - 8 - pb
	sheet.spellcasting = {"ability": String(b.get("ability", "int")), "save_dc": dc,
		"attack_bonus": dc - 8, "slots": slots}
	var ids: Array = []
	for sid in b.get("spells", []):
		if int(Catalog.spell(String(sid)).get("level", 0)) <= cap:
			ids.append(String(sid))
	var fresh: Array = Effects.spell_verbs_for(sheet, ids, slots)
	# Feet to hexes, areas to hex shapes: the adapter's pass, run on the new
	# verbs alone so the statblock's own (already finished) ones are untouched.
	var own: Array = c.verbs
	c.verbs = fresh
	Adapter._finish_verbs(c, {})
	c.verbs = own + c.verbs
	c.slots = slots
	c.spell_ids.assign(ids)
	c.save_dc = dc
	c.cname = "%s the %s" % [c.cname.get_slice(" the ", 0), String(b.get("title", "Caster"))] \
		if c.cname.contains(" the ") else "%s, %s" % [c.cname, String(b.get("title", "Caster"))]
	c.caster = true

# Every subclass feature, against the 2024 PHB — what it is, when it lands,
# and (where the engine implements it) what it does on the board.
#
# tests/test_class_abilities.gd builds all 48 subclasses at levels 4 and 8 and
# presses every button. This file is the other half of that claim, feature by
# feature rather than build by build:
#
#   1. the catalog is sane   — a subclass's features arrive on the levels the
#                              2024 PHB gives its class (3/6/10/14 for most),
#                              every id is prefixed by its subclass, and no
#                              authored mechanic in data/effects/features.json
#                              names a feature nothing grants
#   2. level gating           — each authored subclass feature is absent one
#                              level before it lands and present on the level
#   3. the numbers are RAW    — each authored feature's dice, uses, range,
#                              cost and rider, at the levels where they change
#   4. the inventory          — every subclass feature that has NO mechanic,
#                              with one line of what the PHB says it does and
#                              a tag: [C] a combat mechanic the board is
#                              missing, [S] spell-list/prep (works if the
#                              spells do), [P] partly covered by the sheet or
#                              another mechanic, [O] out of combat / flavor
#
# 1-3 are assertions. 4 is printed, never asserted: it is the list of what is
# left, per subclass, so "nothing left" can be checked by reading it — and the
# [C] rows are the ones to author next. `note` lines are questions about the
# features that ARE authored, where the engine's reading and the book's
# differ and nothing in the repo says which was meant.
#
#   godot --headless --path . -s tests/test_subclass_features.gd
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const Leveling = preload("res://core/leveling.gd")
const Adapter = preload("res://core/adapter.gd")
const Effects = preload("res://core/rules/effects.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0
var _notes: Array = []
var _flavor := {}      # subclass id -> [feature ids with no mechanic]
# Mechanics that live in the engine rather than data/effects/features.json.
const ENGINE_WIRED := ["champion-improved-critical", "champion-superior-critical"]   # adapter.to_combatant: crit_range 19 / 18
var _live := {}        # subclass id -> [feature ids with one]

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func note(text: String) -> void:
	_notes.append(text)

func _init() -> void:
	test_catalog_ladder()
	test_ids_are_prefixed()
	test_no_orphaned_mechanics()
	test_every_subclass_at_three()
	test_frenzy()
	test_valor_extra_attack()
	test_warding_flare()
	test_invoke_duplicity()
	test_war_priest()
	test_hand_of_healing()
	test_wholeness_of_body()
	test_aura_of_devotion()
	test_aura_of_warding()
	test_primal_companion()
	test_dread_ambusher()
	test_colossus_slayer()
	test_assassinate()
	test_healing_light()
	test_improved_critical()
	report()
	print("test_subclass_features: %d passed, %d failed, %d questions" % [_pass, _fail, _notes.size()])
	quit(1 if _fail > 0 else 0)

# --- building (the same loop tests/test_class_abilities.gd drives) --------

func autopick(p: Dictionary, sheet, prefer := "") -> Array:
	var opts := Creator.options_for(p, sheet)
	if opts.is_empty():
		return []
	for o in opts:
		if o["id"] == prefer:
			return [prefer]
	var picks: Array = []
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3:
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

var _built := {}

func build(cid: String, sid: String, lvl: int):
	var key := "%s/%s/%d" % [cid, sid, lvl]
	if _built.has(key):
		return _built[key]
	var ch = Creator.new_character()
	ch.id = key
	ch.cname = "%s/%s" % [cid, sid]
	ch.species_id = "human"
	ch.background_id = String(Catalog.class_src(cid).get("quickBuild", {}).get("suggestedBackground", "soldier"))
	ch.base_abilities = Creator.recommended_array(cid)
	Leveling.grant_levels(ch, lvl, cid)
	for _step in 160:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			break
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet, sid if p["type"] == "subclass" else "")
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	_built[key] = ch
	return ch

func combatant(cid: String, sid: String, lvl: int):
	return Adapter.to_combatant(build(cid, sid, lvl), "party", Vector2i(2, 0))

func verb(c, id: String) -> Dictionary:
	for v in c.verbs:
		if String(v["id"]) == id:
			return v
	return {}

func pool_max(c, id: String) -> int:
	return int(c.pools.get(id, {}).get("max", 0))

# The subclass-feature levels of each class, 2024 PHB.
const LADDER := {
	"barbarian": [3, 6, 10, 14], "bard": [3, 6, 14], "cleric": [3, 6, 17], "druid": [3, 6, 10, 14],
	"fighter": [3, 7, 10, 15, 18], "monk": [3, 6, 11, 17], "paladin": [3, 7, 15, 20], "ranger": [3, 7, 11, 15],
	"rogue": [3, 9, 13, 17], "sorcerer": [3, 6, 14, 18], "warlock": [3, 6, 10, 14], "wizard": [3, 6, 10, 14],
}

# [level, grant] pairs of a subclass's feature grants (plain features and choices).
func _feature_grants(sub: Dictionary) -> Array:
	var out: Array = []
	for L in sub.get("levels", []):
		for g in L.get("grants", []):
			if g.get("type", "") in ["feature", "feature-choice"]:
				out.append([int(L["classLevel"]), g])
	return out

func _granted_ids(sub: Dictionary) -> Array:
	var out: Array = []
	for pair in _feature_grants(sub):
		var g: Dictionary = pair[1]
		if g["type"] == "feature":
			out.append(String(g["feature"]["id"]))
		else:
			for o in g.get("options", []):
				out.append(String(o["featureId"]))
	return out

# --- 1. the catalog ----------------------------------------------------------

func test_catalog_ladder() -> void:
	var subs: Array = Catalog.all("subclasses.json")
	check(subs.size() == 48, "48 subclasses (got %d)" % subs.size())
	for sub in subs:
		var cid := String(sub["classId"])
		var ladder: Array = LADDER.get(cid, [])
		check(not ladder.is_empty(), "%s: class %s has a known ladder" % [sub["id"], cid])
		var levels := {}
		for pair in _feature_grants(sub):
			levels[int(pair[0])] = true
		for lvl in levels:
			check(int(lvl) in ladder, "%s: a feature lands on level %d, which is not on %s's 2024 ladder %s" % [sub["id"], lvl, cid, str(ladder)])
		check(levels.has(3), "%s: the subclass lands at level 3 with a feature" % sub["id"])
		var granted := _granted_ids(sub)
		var seen := {}
		for fid in granted:
			check(not seen.has(fid), "%s grants %s once" % [sub["id"], fid])
			seen[fid] = true

func test_ids_are_prefixed() -> void:
	for sub in Catalog.all("subclasses.json"):
		for fid in _granted_ids(sub):
			check(String(fid).begins_with(String(sub["id"]) + "-"), "%s: feature id %s carries the subclass prefix" % [sub["id"], fid])

# An authored mechanic for "<subclass>-something" that no subclass grants is a
# feature that will never reach a sheet — the quiet way a whole authoring
# effort goes to waste.
func test_no_orphaned_mechanics() -> void:
	var granted := {}
	for sub in Catalog.all("subclasses.json"):
		for fid in _granted_ids(sub):
			granted[fid] = true
	var class_granted := {}
	var class_ids := {}
	for c in Catalog.all("classes.json"):
		class_ids[String(c["id"])] = true
		for L in c.get("levels", []):
			for g in L:
				if g.get("type", "") == "feature":
					class_granted[String(g["feature"]["id"])] = true
				# a class's own pick-list (Metamagic, Eldritch Invocations...):
				# its options are named for the list, not the class
				for o in g.get("options", []):
					if o.has("featureId"):
						class_granted[String(o["featureId"])] = true
	var sub_ids := {}
	for sub in Catalog.all("subclasses.json"):
		sub_ids[String(sub["id"])] = true
	var f = Catalog.all("effects/features.json")
	for id in f:
		var sid := String(id)
		if sid.begins_with("_") or sid.begins_with("monster-") or sid.begins_with("goblin-"):
			continue
		var prefix := sid.split("-")[0]
		if sub_ids.has(prefix):
			check(granted.has(sid), "features.json authors %s but no subclass grants it" % sid)
		elif class_ids.has(prefix):
			check(class_granted.has(sid), "features.json authors %s but the class never grants it" % sid)
		else:
			check(class_granted.has(sid), "features.json: %s is neither a class, a subclass, a class option nor a monster template" % sid)
	check(Effects.validate().is_empty(), "Effects.validate(): %s" % str(Effects.validate()))

# --- every subclass, the level it lands ------------------------------------

func test_every_subclass_at_three() -> void:
	for c in Catalog.all("classes.json"):
		var cid := String(c["id"])
		for sid in Catalog.subclasses_of(cid):
			var ch = build(cid, sid, 3)
			var s = ch.sheet()
			var who := "%s/%s L3" % [cid, sid]
			check(s.pending.is_empty(), "%s: resolves with nothing pending" % who)
			check(String(s.subclasses.get(cid, "")) == sid, "%s: the sheet knows its subclass" % who)
			var sub: Dictionary = {}
			for x in Catalog.all("subclasses.json"):
				if String(x["id"]) == sid:
					sub = x
			for pair in _feature_grants(sub):
				if int(pair[0]) > 3:
					continue
				var g: Dictionary = pair[1]
				if g["type"] == "feature":
					check(s.has_feature(String(g["feature"]["id"])), "%s: has %s" % [who, g["feature"]["id"]])
				else:
					var picked := 0
					for o in g.get("options", []):
						if s.has_feature(String(o["featureId"])):
							picked += 1
					check(picked == 1, "%s: exactly one option of %s is on the sheet (%d)" % [who, g["key"], picked])
			var cb = combatant(cid, sid, 3)
			check(cb.max_hp > 0 and cb.ac >= 10, "%s: reaches the board" % who)
			for v in cb.verbs:
				check(String(v["kind"]) in Effects.KINDS or String(v["kind"]) in ["spell", "offhand_attack"],
					"%s: verb %s has a known kind (%s)" % [who, v["id"], v["kind"]])
			# the inventory, off the FULL grant list, not just level 3
			for fid in _granted_ids(sub):
				var bucket: Dictionary = _live if (not Effects.feature(fid).is_empty() or fid in ENGINE_WIRED) else _flavor
				if not bucket.has(sid):
					bucket[sid] = []
				bucket[sid].append(fid)

# --- 2-3. the authored ones -------------------------------------------------

func test_frenzy() -> void:
	check(verb(combatant("barbarian", "berserker", 2), "berserker-frenzy").is_empty(), "no Frenzy before level 3")
	var v := verb(combatant("barbarian", "berserker", 3), "berserker-frenzy")
	check(v.get("kind", "") == "passive_damage" and v.get("trigger", "") == "on_weapon_hit", "Frenzy rides a weapon hit")
	check("while_raging" in v.get("requires", []) and v.get("once_per", "") == "turn", "...while raging, once per turn (2024)")
	check(int(v.get("dice_count", 0)) == 2 and int(v.get("dice_sides", 0)) == 6, "L3: extra damage is 2d6 (the Rage bonus in d6s)")
	var v9 := verb(combatant("barbarian", "berserker", 9), "berserker-frenzy")
	check(int(v9.get("dice_count", 0)) == 3, "L9: Rage Damage +3, so Frenzy is 3d6")
	check(int(verb(combatant("barbarian", "berserker", 9), "barbarian-rage").get("bonus_damage", 0)) == 3, "...and Rage itself is +3 at 9")

func test_valor_extra_attack() -> void:
	check(combatant("bard", "collegevalor", 5).verbs.filter(func(v): return v["kind"] == "attacks_per_action").is_empty(),
		"College of Valor: no Extra Attack at 5")
	var c = combatant("bard", "collegevalor", 6)
	var ea: Array = c.verbs.filter(func(v): return v["kind"] == "attacks_per_action")
	check(ea.size() == 1 and int(ea[0]["value"]) == 2, "...two attacks per action at 6")

func test_warding_flare() -> void:
	check(verb(combatant("cleric", "lightdomain", 2), "lightdomain-warding-flare").is_empty(), "no Warding Flare before 3")
	var c = combatant("cleric", "lightdomain", 3)
	var v := verb(c, "lightdomain-warding-flare")
	check(v.get("cost", "") == "reaction" and v.get("trigger", "") == "would_be_hit" and v.get("disadvantage", false),
		"Warding Flare: a reaction that imposes disadvantage on an attack that would hit")
	check(pool_max(c, "lightdomain-warding-flare") == maxi(1, c.sheet.mod("wis")), "uses = WIS modifier, minimum 1")
	check(c.pools["lightdomain-warding-flare"]["regen"] == "long-rest", "...back on a Long Rest (2024)")

func test_invoke_duplicity() -> void:
	check(verb(combatant("cleric", "trickerydomain", 2), "trickerydomain-invoke-duplicity").is_empty(), "no Invoke Duplicity before 3")
	var c = combatant("cleric", "trickerydomain", 3)
	var v := verb(c, "trickerydomain-invoke-duplicity")
	check(v.get("kind", "") == "summon" and v.get("cost", "") == "bonus", "Invoke Duplicity: a bonus action summon")
	check(v.get("pool", "") == "channel-divinity" and pool_max(c, "channel-divinity") == 2, "...spending Channel Divinity (2 uses at 3)")
	check(String(v.get("summon", {}).get("id", "")) == "trickery-duplicate" and v.get("summon", {}).get("illusion", false),
		"the double is an illusion, not a creature")
	check(int(v.get("rounds", 0)) == 10, "it lasts a minute (10 rounds)")

func test_war_priest() -> void:
	check(verb(combatant("cleric", "wardomain", 2), "wardomain-war-priest").is_empty(), "no War Priest before 3")
	var c = combatant("cleric", "wardomain", 3)
	var v := verb(c, "wardomain-war-priest")
	check(v.get("cost", "") == "bonus" and int(v.get("extra_attacks", 0)) == 1 and int(v.get("amount", 1)) == 0,
		"War Priest: a bonus-action weapon attack, no extra Action")
	check(v.get("pool", "") == "war-priest" and pool_max(c, "war-priest") == maxi(1, c.sheet.mod("wis")),
		"...WIS-modifier uses, minimum 1 (2024)")
	check(c.pools["war-priest"]["regen"] == "short-rest", "...back on a Short Rest")
	check(c.sheet.pools.all(func(p): return String(p["id"]) != "war-priest"), "the export's PB-sized pool grant is gone")

func test_hand_of_healing() -> void:
	check(verb(combatant("monk", "warriorofmercy", 2), "warriorofmercy-hand-of-healing").is_empty(), "no Hand of Healing before 3")
	for lvl in [3, 5]:
		var c = combatant("monk", "warriorofmercy", lvl)
		var v := verb(c, "warriorofmercy-hand-of-healing")
		check(v.get("kind", "") == "heal_ally" and v.get("cost", "") == "bonus" and v.get("pool", "") == "focus-points",
			"L%d Hand of Healing: bonus action, a Focus Point" % lvl)
		check(int(v.get("dice_sides", 0)) == (6 if lvl < 5 else 8) and int(v.get("dice_count", 0)) == 1,
			"L%d: heals a Martial Arts die (d%d)" % [lvl, 6 if lvl < 5 else 8])
		check(int(v.get("dice_bonus", -99)) == c.sheet.mod("wis"), "L%d: ...plus WIS" % lvl)
		check(int(v.get("range", 0)) == 1, "L%d: touch" % lvl)
		check(v.get("flurry_swap", false), "L%d: may stand in for a Flurry of Blows strike" % lvl)
	# ...and on the board: after a Flurry, one heal costs no Focus Point and no bonus action
	var m = combatant("monk", "warriorofmercy", 5)
	var mate = combatant("rogue", "thief", 5)
	mate.id = "mate"; mate.pos = Vector2i(3, 0); mate.hp = 1
	var cb = Combat.new(RNG.new(2), [m, mate], Encounter.board_for("sunken-shrine"))
	cb.begin_turn_for(m)
	var focus0: int = m.pool_left("focus-points")
	cb.perform(m, verb(m, "monk-flurry-of-blows"))
	check(m.econ["bonus"] == 0 and m.econ["attacks_left"] == 2 and m.pool_left("focus-points") == focus0 - 1, "Flurry: the bonus action and a point, two strikes banked")
	var hoh := verb(m, "warriorofmercy-hand-of-healing")
	check(cb._offerable(m, hoh), "Hand of Healing is still on offer with the bonus action gone")
	cb.perform(m, hoh, mate)
	check(mate.hp > 1 and m.pool_left("focus-points") == focus0 - 1 and m.econ["attacks_left"] == 1,
		"...it took one of the Flurry strikes and no Focus Point")
	m.econ["attacks_left"] = 0
	check(not cb._offerable(m, hoh), "with the strikes spent and the bonus action gone, it is off")

func test_wholeness_of_body() -> void:
	check(verb(combatant("monk", "warrioropenhand", 5), "warrioropenhand-wholeness-of-body").is_empty(), "no Wholeness of Body before 6")
	var c = combatant("monk", "warrioropenhand", 6)
	var v := verb(c, "warrioropenhand-wholeness-of-body")
	check(v.get("kind", "") == "heal_self" and v.get("cost", "") == "bonus", "Wholeness of Body: bonus action self-heal (2024)")
	check(int(v.get("dice_sides", 0)) == 8 and int(v.get("dice_bonus", -99)) == c.sheet.mod("wis"), "...Martial Arts die (d8 at 6) + WIS")
	check(pool_max(c, "warrioropenhand-wholeness-of-body") == Bundles.proficiency_bonus(6), "PB uses")
	check(c.pools["warrioropenhand-wholeness-of-body"]["regen"] == "long-rest", "...per Long Rest (2024)")

func test_aura_of_devotion() -> void:
	check(verb(combatant("paladin", "oathofdevotion", 6), "oathofdevotion-aura-of-devotion").is_empty(), "no Aura of Devotion before 7")
	var c = combatant("paladin", "oathofdevotion", 7)
	var v := verb(c, "oathofdevotion-aura-of-devotion")
	check(v.get("kind", "") == "aura" and "charmed" in v.get("cond_immune", []), "Aura of Devotion: you and allies in it cannot be Charmed")
	check(int(v.get("range", 0)) == Adapter.hexes(10), "...10 ft (2 hexes)")
	check(not verb(c, "paladin-aura-of-protection").is_empty(), "the base aura arrived at 6 as well")

func test_aura_of_warding() -> void:
	check(verb(combatant("paladin", "oathofancients", 6), "oathofancients-aura-of-warding").is_empty(), "no Aura of Warding before 7")
	var v := verb(combatant("paladin", "oathofancients", 7), "oathofancients-aura-of-warding")
	var want := ["necrotic", "psychic", "radiant"]
	check(v.get("kind", "") == "aura" and want.all(func(t): return t in v.get("aura_resist", [])) and v.get("aura_resist", []).size() == 3,
		"Aura of Warding: resistance to necrotic, psychic and radiant, nothing else (2024)")
	check(int(v.get("range", 0)) == Adapter.hexes(10), "...10 ft")

func test_primal_companion() -> void:
	check(verb(combatant("ranger", "beastmaster", 2), "beastmaster-primal-companion").is_empty(), "no Primal Companion before 3")
	var c = combatant("ranger", "beastmaster", 3)
	var v := verb(c, "beastmaster-primal-companion")
	check(v.get("kind", "") == "summon" and v.get("cost", "") == "action", "Primal Companion: an action to call")
	check(String(v.get("summon", {}).get("id", "")) == "dire-wolf", "...a dire wolf stands in for the Beast of the Land")
	check(is_equal_approx(float(v.get("mult", 0.0)), 0.7), "L3: the beast is scaled to 70%%")
	check(is_equal_approx(float(verb(combatant("ranger", "beastmaster", 5), "beastmaster-primal-companion").get("mult", 0.0)), 0.9), "L5: 90%%")
	check(pool_max(c, "beastmaster-primal-companion") == Bundles.proficiency_bonus(3) and c.pools["beastmaster-primal-companion"]["regen"] == "long-rest",
		"PB uses per long rest (the revive count, RAW)")

func test_dread_ambusher() -> void:
	check(verb(combatant("ranger", "gloomstalker", 2), "gloomstalker-dread-ambusher").is_empty(), "no Dread Ambusher before 3")
	var c = combatant("ranger", "gloomstalker", 3)
	var v := verb(c, "gloomstalker-dread-ambusher")
	check(v.get("kind", "") == "passive_damage" and int(v.get("dice_count", 0)) == 2 and int(v.get("dice_sides", 0)) == 6
		and v.get("label", "") == "Dreadful Strike", "Dreadful Strike (2024): +2d6 on a weapon hit")
	check(not "first_round" in v.get("requires", []) and v.get("once_per", "") == "turn", "...any round, once per turn")
	check(v.get("pool", "") == "gloomstalker-dread-ambusher" and pool_max(c, "gloomstalker-dread-ambusher") == maxi(1, c.sheet.mod("wis"))
		and c.pools["gloomstalker-dread-ambusher"]["regen"] == "long-rest", "...WIS-mod uses per Long Rest")
	check(c.init_adv, "Dread Ambusher: advantage on Initiative")
	check(int(v.get("first_round_speed_ft", 0)) == 10, "Ambusher's Leap: +10 ft on the first turn")
	var cb = Combat.new(RNG.new(2), [c], Encounter.board_for("sunken-shrine"))
	cb.begin_turn_for(c)
	check(c.econ["move_left"] == c.speed + 2, "...which is two hexes more to move in round 1")
	cb.round_num = 2; cb.begin_turn_for(c)
	check(c.econ["move_left"] == c.speed, "...and only in round 1")

func test_colossus_slayer() -> void:
	var c = combatant("ranger", "hunter", 3)
	var v := verb(c, "hunter-hunters-prey-colossus-slayer")
	check(c.sheet.has_feature("hunter-hunters-prey-colossus-slayer"), "Hunter's Prey: the build picked Colossus Slayer")
	check(v.get("kind", "") == "passive_damage" and int(v.get("dice_count", 0)) == 1 and int(v.get("dice_sides", 0)) == 8,
		"Colossus Slayer: +1d8")
	check("target_damaged" in v.get("requires", []) and v.get("once_per", "") == "turn", "...against a creature missing HP, once per turn")
	check(Effects.feature("hunter-hunters-prey-horde-breaker").is_empty(), "(Horde Breaker, the other option, has no mechanic — see the inventory)")

func test_assassinate() -> void:
	check(verb(combatant("rogue", "assassin", 2), "assassin-assassinate").is_empty(), "no Assassinate before 3")
	var v := verb(combatant("rogue", "assassin", 3), "assassin-assassinate")
	check(v.get("kind", "") == "attack_modifier" and v.get("trigger", "") == "passive" and v.get("self", "") == "adv"
		and "target_has_not_acted" in v.get("requires", []) and "first_round" in v.get("requires", []),
		"Assassinate (2024): advantage in round 1 against anything that has not acted yet")
	var c = combatant("rogue", "assassin", 3)
	check(c.init_adv, "...advantage on Initiative")
	var ss := verb(c, "assassin-assassinate#1")
	check(ss.get("kind", "") == "passive_damage" and int(ss.get("dice_count", 0)) == 0 and int(ss.get("dice_bonus", 0)) == 3
		and "first_round" in ss.get("requires", []) and "target_has_not_acted" in ss.get("requires", []),
		"Surprising Strikes: extra damage equal to the Rogue level (3) in round 1 vs a creature that has not acted")
	check(int(verb(combatant("rogue", "assassin", 5), "assassin-assassinate#1").get("dice_bonus", 0)) == 5, "...5 at level 5")

func test_healing_light() -> void:
	check(verb(combatant("warlock", "celestialpatron", 2), "celestialpatron-healing-light").is_empty(), "no Healing Light before 3")
	var c = combatant("warlock", "celestialpatron", 3)
	var v := verb(c, "celestialpatron-healing-light")
	check(v.get("kind", "") == "heal_ally" and v.get("cost", "") == "bonus", "Healing Light: a bonus action")
	check(int(v.get("dice_count", 0)) == 1 and int(v.get("dice_sides", 0)) == 6, "...one d6 per use")
	check(int(v.get("range", 0)) == Adapter.hexes(60), "...60 ft")
	check(pool_max(c, "healing-light") == 4, "L3: the pool is 1 + warlock level = 4 d6s")
	check(pool_max(combatant("warlock", "celestialpatron", 6), "healing-light") == 7, "L6: 7")
	check(int(v.get("max_dice", 0)) == maxi(1, c.sheet.mod("cha")), "up to CHA-mod dice in one use")
	# a badly hurt ally draws several dice from the pool in one bonus action
	var mate = combatant("rogue", "thief", 3)
	mate.id = "mate"; mate.pos = Vector2i(3, 0); mate.hp = 1
	var cb = Combat.new(RNG.new(2), [c, mate], Encounter.board_for("sunken-shrine"))
	cb.begin_turn_for(c)
	cb.perform(c, v, mate)
	var spent: int = pool_max(c, "healing-light") - c.pool_left("healing-light")
	check(spent == int(v["max_dice"]) and mate.hp > 1, "a wound that calls for it spends the full CHA-mod dice (%d)" % spent)
	mate.hp = mate.max_hp - 1
	cb.begin_turn_for(c)
	var before: int = c.pool_left("healing-light")
	cb.perform(c, v, mate)
	check(before - c.pool_left("healing-light") == 1, "a scratch spends one")

func test_improved_critical() -> void:
	check(combatant("fighter", "champion", 2).crit_range == 20, "a fighter 2 crits on a 20")
	check(combatant("fighter", "champion", 3).crit_range == 19, "Champion 3: Improved Critical, crits on 19-20")
	check(combatant("fighter", "battlemaster", 3).crit_range == 20, "...and only the Champion")
	check(combatant("fighter", "champion", 14).crit_range == 19 and combatant("fighter", "champion", 15).crit_range == 18,
		"Champion 15: Superior Critical, crits on 18-20")

# --- 4. the inventory --------------------------------------------------------
#
# What the 2024 PHB says each un-authored subclass feature does, in one line,
# and whether the board is missing a mechanic for it. Read this, not the code,
# to see how much of a subclass is still prose.
const RAW_NOTES := {
	# choice options that are the CHOICE, not a mechanic of their own
	"circleland-land-arid": "[S] Circle of the Land: the Arid spell list (Blur, Burning Hands, Fire Bolt...)",
	"circleland-land-polar": "[S] Circle of the Land: the Polar spell list (Fog Cloud, Hold Person, Ray of Frost...)",
	"circleland-land-temperate": "[S] Circle of the Land: the Temperate spell list (Misty Step, Shocking Grasp, Sleep...)",
	"circleland-land-tropical": "[S] Circle of the Land: the Tropical spell list (Acid Splash, Ray of Sickness, Web...)",
	"draconicsorcery-dragon-ancestor-black": "[O] ancestry: acid — the type Elemental Affinity (6) keys off",
	"draconicsorcery-dragon-ancestor-blue": "[O] ancestry: lightning",
	"draconicsorcery-dragon-ancestor-brass": "[O] ancestry: fire",
	"draconicsorcery-dragon-ancestor-bronze": "[O] ancestry: lightning",
	"draconicsorcery-dragon-ancestor-copper": "[O] ancestry: acid",
	"draconicsorcery-dragon-ancestor-gold": "[O] ancestry: fire",
	"draconicsorcery-dragon-ancestor-green": "[O] ancestry: poison",
	"draconicsorcery-dragon-ancestor-red": "[O] ancestry: fire",
	"draconicsorcery-dragon-ancestor-silver": "[O] ancestry: cold",
	"draconicsorcery-dragon-ancestor-white": "[O] ancestry: cold",
	# barbarian
	"berserker-mindless-rage": "[C] while raging: immune to Charmed and Frightened (a rage-scoped cond_immune)",
	"berserker-retaliation": "[C] reaction: melee attack against a creature within 5 ft that just damaged you",
	"berserker-intimidating-presence": "[C] bonus action: 30-ft cone, WIS save or Frightened for a minute; WIS-mod uses",
	"wildheart-rage-of-the-wilds": "[C] on Rage: Bear (resist all but force/necrotic/psychic/radiant) / Eagle (bonus Disengage+Dash) / Wolf (allies have advantage on melee vs enemies within 5 ft of you)",
	"wildheart-aspect-of-the-wilds": "[O] Owl darkvision / Panther climb / Salmon swim",
	"worldtree-vitality-of-the-tree": "[C] on Rage: temp HP = barbarian level; each turn while raging, temp HP = 1d6+? to an ally within 10 ft",
	"worldtree-branches-of-the-tree": "[C] reaction on a creature you see starting its turn within 30 ft: STR save or pulled to you, speed 0",
	"worldtree-battering-roots": "[C] +10 ft reach with heavy/versatile weapons; on hit, Push or Topple mastery in addition",
	"zealot-warrior-of-the-gods": "[C] pool of 4 d12s (5 at 6, 6 at 12) to heal yourself as a bonus action; long rest",
	"zealot-fanatical-focus": "[C] once per Rage: reroll a failed save with +2",
	"zealot-zealous-presence": "[C] bonus action: up to 10 creatures within 60 ft gain advantage on attacks and saves until your next turn; 1/long rest",
	# bard
	"collegedance-inspirational-dance": "[C] bonus action Bardic Inspiration: you and allies within 30 ft gain temp HP and may move (reaction moves later)",
	"collegedance-unarmored-defense": "[P] AC 10 + DEX + CHA when unarmored — the sheet already computes it (test_class_abilities)",
	"collegedance-frolicking-steps": "[P] +10 ft speed while unarmored — a `speed` grant; check the sheet",
	"collegedance-dance-of-victory": "[C] a used Inspiration die also adds to your damage; Leading Evasion for allies",
	"collegeglamour-mantle-of-inspiration": "[C] bonus action: allies within 60 ft gain temp HP (2d6+?) and a free move that provokes nothing",
	"collegeglamour-enthralling-performance": "[O] charm after a performance, out of combat",
	"collegeglamour-mantle-of-majesty": "[C] bonus action Command without a slot, each turn for a minute, advantage vs the Charmed",
	"collegelore-cutting-words": "[C] reaction: subtract a Bardic Inspiration die from an enemy's attack roll or ability check within 60 ft",
	"collegelore-magical-secrets": "[S] spells from the cleric/druid/wizard lists",
	"collegevalor-combat-inspiration": "[C] the Inspiration die can be added to a damage roll or to AC against one attack",
	# cleric
	"lifedomain-disciple-of-life": "[C] healing spells heal +2 + slot level extra",
	"lifedomain-preserve-life": "[C] Channel Divinity: heal 5 x cleric level, split among creatures within 30 ft, none above half HP",
	"lifedomain-blessed-healer": "[C] when you heal another creature, you heal 2 + slot level",
	"lightdomain-radiance-of-the-dawn": "[C] Channel Divinity: 30-ft emanation, 2d10 + cleric level radiant, CON save for half; dispels magical darkness",
	"lightdomain-improved-warding-flare": "[C] Warding Flare also on allies within 30 ft, and the target gets temp HP = 2d6 + WIS",
	"trickerydomain-blessing-of-the-trickster": "[O] advantage on Stealth checks for one creature",
	"trickerydomain-tricksters-transposition": "[C] bonus action: swap places with your Duplicity double",
	"wardomain-guided-strike": "[C] Channel Divinity: +10 to an attack roll you (or, at 6, an ally within 30 ft) just made",
	"wardomain-war-gods-blessing": "[C] Guided Strike on allies; cast Shield of Faith / Spiritual Weapon once per long rest without a slot",
	# druid
	"circleland-lands-aid": "[C] spend a Wild Shape use: 10-ft sphere within 60 ft, CON save, 2d6 necrotic (half), and one creature inside regains 2d6",
	"circleland-natural-recovery": "[S] recover spell slots on a short rest, cast a Land spell free once per long rest",
	"circleland-natures-ward": "[C] immune to Poisoned; resistance to the land's damage type",
	"circlemoon-circle-forms": "[C] Wild Shape into CR-1/3 beasts, AC 13 + WIS in form, temp HP = 3 x level — Wild Shape is not modelled at all",
	"circlemoon-improved-wild-shape": "[C] Wild Shape as a bonus action; Cure Wounds castable in beast form",
	"circlemoon-improved-circle-forms": "[C] beast attacks count as magical and may deal radiant; Moonbeam free",
	"circlemoon-elemental-wild-shape": "[C] resistance to acid/cold/fire/lightning/thunder in form",
	"circlesea-wrath-of-the-sea": "[C] spend a Wild Shape use: 5-ft emanation for 10 min; each turn as a bonus action 1d6 cold (scales) to one creature inside, CON save or pushed 15 ft",
	"circlesea-aquatic-affinity": "[O] swim speed",
	"circlesea-stormborn": "[C] while Wrath of the Sea is up: fly speed, resistance to lightning and thunder",
	"circlestars-star-map": "[S] Guiding Bolt prepared and castable PB times without a slot",
	"circlestars-starry-form": "[C] spend a Wild Shape use as a bonus action: Archer (bonus 1d8+WIS radiant ranged spell attack) / Chalice (heal 1d8+WIS when you cast a healing spell) / Dragon (minimum 10 on CON saves for concentration)",
	"circlestars-cosmic-omen": "[C] reaction: add or subtract 1d6 from a roll within 30 ft; PB uses",
	"circlestars-twinkling-constellations": "[C] Starry Form dice become 2d8; Dragon form grants fly 20 ft",
	# fighter
	"champion-remarkable-athlete": "[C] advantage on Initiative; after a critical hit, move half speed without provoking",
	"champion-survivor": "[C] regain 5 + CON at the start of each turn while below half HP; advantage on death saves",
	"battlemaster-combat-superiority": "[C] 4 superiority d8s, 3 maneuvers (Trip Attack, Riposte, Precision Attack, Menacing Attack...) — the whole Battle Master kit",
	"battlemaster-know-your-enemy": "[O] learn a creature's immunities/resistances/vulnerabilities",
	"battlemaster-improved-combat-superiority": "[C] superiority dice become d10s",
	"battlemaster-relentless": "[C] regain a superiority die when you roll Initiative with none left",
	"battlemaster-superior-combat-superiority": "[C] superiority dice become d12s",
	"eldritchknight-spellcasting": "[S] third-caster spellcasting — a `spellcasting` grant; the sheet's slots are the test",
	"eldritchknight-war-magic": "[C] after casting a cantrip, one weapon attack as a bonus action",
	"eldritchknight-eldritch-strike": "[C] a creature you hit has disadvantage on the next save against your spell this turn",
	"eldritchknight-arcane-charge": "[C] teleport 30 ft when you use Action Surge",
	"eldritchknight-improved-war-magic": "[C] War Magic with a 1st/2nd-level spell",
	"psiwarrior-psionic-power": "[C] Psionic Energy dice: Protective Field (reaction, reduce damage by die + INT), Psionic Strike (+die + INT force on a hit), Telekinetic Movement",
	"psiwarrior-telekinetic-adept": "[C] Psi-Powered Leap (bonus fly), Telekinetic Thrust (Psionic Strike target: STR save or prone / pushed 10 ft)",
	"psiwarrior-guarded-mind": "[C] resistance to psychic; end Charmed/Frightened on yourself for a die",
	"psiwarrior-bulwark-of-force": "[C] bonus action: half cover to PB creatures within 30 ft for a minute",
	"psiwarrior-telekinetic-master": "[C] Telekinesis without a slot, weapon attacks while concentrating on it",
	# monk
	"warriorofmercy-implements-of-mercy": "[O] Insight and Medicine proficiency, a healer's kit",
	"warriorofmercy-hand-of-harm": "[C] spend a Focus Point on an unarmed hit: + Martial Arts die necrotic; once per turn",
	"warriorofmercy-physicians-touch": "[C] Hand of Healing also ends Blinded/Deafened/Paralyzed/Poisoned/Stunned; Hand of Harm also Poisons",
	"warriorofshadow-shadow-arts": "[C] Darkness for a Focus Point (you see through it), Darkvision 60, Minor Illusion",
	"warriorofshadow-shadow-step": "[C] bonus action teleport 60 ft dim light to dim light; advantage on the next melee attack",
	"warriorofelements-elemental-attunement": "[C] +10 ft reach on unarmed strikes, their damage type becomes acid/cold/fire/lightning/thunder, and on a hit STR save or push/pull 10 ft",
	"warriorofelements-manipulate-elements": "[O] the Elementalism cantrip",
	"warriorofelements-elemental-burst": "[C] 2 Focus Points: 20-ft sphere within 120 ft, DEX save, 3 x Martial Arts die of an element (half on save)",
	"warrioropenhand-open-hand-technique": "[C] each Flurry of Blows hit: Addle (no reactions), Push (STR save or 15 ft), or Topple (DEX save or Prone)",
	# paladin
	"oathofdevotion-sacred-weapon": "[C] Channel Divinity, bonus action: +CHA to attack rolls with one weapon for 10 min, it sheds light",
	"oathofdevotion-smite-of-protection": "[C] when you Divine Smite, allies in your aura get half cover until your next turn",
	"oathofdevotion-holy-nimbus": "[C] bonus action: 30-ft emanation of radiant damage to enemies at the start of their turns; advantage on saves vs fiends and undead",
	"oathofglory-peerless-athlete": "[O] Channel Divinity: advantage on Athletics/Acrobatics, longer jumps for an hour",
	"oathofglory-inspiring-smite": "[C] Channel Divinity after a Divine Smite: distribute 2d8 + paladin level temp HP among creatures within 30 ft",
	"oathofglory-aura-of-alacrity": "[C] +10 ft speed for you; allies who start their turn within 5 ft of you (10 at 18) get it too",
	"oathofglory-glorious-defense": "[C] reaction when a creature you see hits you or an ally within 10 ft: +CHA AC, and if that makes it miss, a weapon attack against it",
	"oathofglory-living-legend": "[C] bonus action for a minute: advantage on CHA checks, turn one miss per turn into a hit, reroll a failed save",
	"oathofancients-natures-wrath": "[C] Channel Divinity: 15-ft emanation, STR save or Restrained for a minute (repeat at end of turn)",
	"oathofancients-undying-sentinel": "[C] when reduced to 0 HP but not killed outright, drop to 1 instead; 1/long rest. Also: no aging",
	"oathofancients-elder-champion": "[C] bonus action for a minute: regain 10 HP at the start of each turn, cast paladin spells as a bonus action, enemies within 10 ft have disadvantage on saves vs your spells and Channel Divinity",
	"oathofvengeance-vow-of-enmity": "[C] Channel Divinity, bonus action: advantage on attack rolls against one creature within 30 ft for a minute (transfers on its death, 2024)",
	"oathofvengeance-relentless-avenger": "[C] after an opportunity attack hits, move up to half speed without provoking",
	"oathofvengeance-soul-of-vengeance": "[C] reaction: a weapon attack against your Vow target when it attacks",
	"oathofvengeance-avenging-angel": "[C] bonus action for 10 min: fly 60 ft, and a 30-ft aura that Frightens on a failed WIS save",
	# ranger
	"beastmaster-exceptional-training": "[C] the beast attacks as your bonus action; its attacks deal force; it can Dash/Disengage/Help on command",
	"feywanderer-dreadful-strikes": "[C] +1d4 psychic on a weapon hit (1d6 at 11), once per turn per creature",
	"feywanderer-otherworldly-glamour": "[O] +WIS to CHA checks, one CHA skill proficiency",
	"feywanderer-beguiling-twist": "[C] advantage on saves vs Charmed/Frightened; reaction when a creature within 120 ft saves against them: redirect the condition to another creature",
	"gloomstalker-umbral-sight": "[C] darkvision +60 ft; while in Darkness you are Invisible to creatures relying on darkvision",
	"gloomstalker-iron-mind": "[P] WIS save proficiency (INT/CHA at 7) — a `proficiency` grant; the sheet is the test",
	"hunter-hunters-lore": "[O] know a creature's immunities/resistances/vulnerabilities (Hunter's Mark target)",
	"hunter-hunters-prey-horde-breaker": "[C] once per turn, when you attack, one extra weapon attack against a different creature within 5 ft of the first",
	"hunter-defensive-tactics-escape-the-horde": "[C] opportunity attacks against you have disadvantage",
	"hunter-defensive-tactics-multiattack-defense": "[C] after a creature hits you, +4 AC against its further attacks this turn",
	# rogue
	"thief-fast-hands": "[P] bonus action: Use an Object / Sleight of Hand / thieves' tools — a potion as a bonus action would be the on-board half",
	"thief-second-story-work": "[O] climb speed, longer jumps",
	"thief-supreme-sneak": "[C] Cunning Strike option: stay hidden after a Sneak Attack (Stealth Attack)",
	"assassin-infiltration-expertise": "[O] disguises, false identities",
	"arcanetrickster-mage-hand-legerdemain": "[O] an invisible Mage Hand that picks pockets",
	"arcanetrickster-magical-ambush": "[C] a creature you are hidden from has disadvantage on the save against your spell",
	"soulknife-psionic-power": "[O] Psi-Bolstered Knack (add a die to a failed check), Psychic Whispers (telepathy)",
	"soulknife-psychic-blades": "[C] 1d6 psychic finesse melee/thrown weapon; a second 1d4 blade as a bonus action after attacking",
	"soulknife-soul-blades": "[C] Homing Strikes (add a Psionic die to a missed blade attack), Psychic Teleportation (bonus action teleport)",
	# sorcerer
	"aberrantsorcery-telepathic-speech": "[O] telepathy",
	"aberrantsorcery-psionic-sorcery": "[S] cast Aberrant spells with Sorcery Points instead of slots",
	"aberrantsorcery-psychic-defenses": "[C] resistance to psychic; advantage on saves vs Charmed and Frightened",
	"aberrantsorcery-revelation-in-flesh": "[C] 1+ Sorcery Points: fly, swim, see invisible, squeeze",
	"aberrantsorcery-warping-implosion": "[C] teleport 120 ft; each creature within 30 ft of where you left takes 3d10 force (STR save) and is pulled",
	"clockworksorcery-restore-balance": "[C] reaction: cancel advantage and disadvantage on a roll you see; PB uses",
	"clockworksorcery-bastion-of-law": "[C] spend 1-5 Sorcery Points: a ward of that many d8s on a creature that absorbs damage",
	"clockworksorcery-trance-of-order": "[C] bonus action for a minute: attacks against you cannot have advantage; treat any d20 roll of 9 or lower as a 10",
	"clockworksorcery-clockwork-cavalcade": "[C] 30-ft cube: restore 100 HP split among creatures, repair objects, end every spell of 6th level or lower",
	"draconicsorcery-elemental-affinity": "[C] +CHA to one damage roll of your ancestry's type per spell; resistance to that type",
	"draconicsorcery-dragon-wings": "[C] bonus action: fly speed 60 ft for an hour",
	"draconicsorcery-dragon-companion": "[S] Summon Dragon without a slot once per long rest, no concentration",
	"wildmagicsorcery-wild-magic-surge": "[C] after a leveled spell, the DM may ask for a d20; on a 20 (2024: on a 1) roll on the Wild Magic table",
	"wildmagicsorcery-tides-of-chaos": "[C] advantage on one d20 roll; the next leveled spell then surges",
	"wildmagicsorcery-bend-luck": "[C] reaction, 1 Sorcery Point: +/-1d4 to a creature's attack, check or save within 60 ft",
	"wildmagicsorcery-controlled-chaos": "[C] roll twice on the surge table and pick",
	"wildmagicsorcery-tamed-surge": "[C] once per long rest, choose the surge result instead of rolling",
	# warlock
	"archfeypatron-steps-of-the-fey": "[C] Misty Step without a slot, CHA-mod uses; on arrival: Refreshing Step (1d10 temp HP to a creature within 10 ft) or Taunting Step (creatures within 5 ft of where you left have disadvantage on attacks not aimed at you)",
	"archfeypatron-misty-escape": "[C] reaction when damaged: Misty Step (free use) and Invisible until your next turn; Disappearing/Dreadful Step",
	"archfeypatron-beguiling-defenses": "[C] immune to Charmed; reaction when a creature you see forces a save: Charm it instead (WIS save)",
	"archfeypatron-bewitching-magic": "[C] after casting an Enchantment or Illusion spell with a slot, a free Misty Step",
	"celestialpatron-radiant-soul": "[C] resistance to radiant; once per turn, +CHA to one radiant or fire damage roll of a spell",
	"celestialpatron-celestial-resilience": "[C/O] temp HP = warlock level + CHA to you (half to 5 allies) on a Magical Cunning or a rest",
	"celestialpatron-searing-vengeance": "[C] when you would make a death save at the start of your turn: instead regain half HP, stand, and each creature within 30 ft takes 2d8 + CHA radiant and is Blinded; 1/long rest",
	"fiendpatron-dark-ones-blessing": "[C] when you reduce a hostile to 0 HP, temp HP = CHA + warlock level",
	"fiendpatron-dark-ones-own-luck": "[C] +1d10 to an ability check or save after rolling, CHA-mod uses per long rest",
	"fiendpatron-fiendish-resilience": "[C] on a rest, pick a damage type: resistance to it (not magical/silvered weapons in 2014; any in 2024)",
	"fiendpatron-hurl-through-hell": "[C] once per long rest when you hit: the target is banished until your next turn and takes 8d10 psychic (10d10 in 2024) if not a fiend",
	"greatoldonepatron-awakened-mind": "[O] telepathy",
	"greatoldonepatron-clairvoyant-combatant": "[C] bonus action: one creature you see has disadvantage on attacks against you and you have advantage against it for a minute; Hex/PB uses",
	"greatoldonepatron-eldritch-hex": "[S] Hex always prepared and castable without a slot; the target also has disadvantage on saves of the chosen ability",
	"greatoldonepatron-create-thrall": "[S] Summon Aberration without a slot; the summon deals +psychic damage",
	# wizard
	"abjurer-abjuration-savant": "[S] two free Abjuration spells in the spellbook",
	"abjurer-arcane-ward": "[C] casting an Abjuration spell raises a ward of 2 x wizard level + INT HP that absorbs damage before you take it",
	"abjurer-projected-ward": "[C] reaction: the ward absorbs damage for a creature within 30 ft",
	"abjurer-spellbreaker": "[C] Counterspell and Dispel Magic prepared, cast once each without a slot per long rest, +INT to the check (2024: advantage)",
	"abjurer-spell-resistance": "[C] advantage on saves vs spells; resistance to spell damage",
	"diviner-divination-savant": "[S] two free Divination spells",
	"diviner-portent": "[C] roll 2 d20s after a long rest; replace any attack roll, check or save you see with one of them",
	"diviner-expert-divination": "[S] casting a Divination spell of 2nd+ level recovers a lower slot",
	"diviner-the-third-eye": "[O] Darkvision / See Invisibility / read any language for a minute",
	"diviner-greater-portent": "[C] three Portent dice",
	"evoker-evocation-savant": "[S] two free Evocation spells",
	"evoker-potent-cantrip": "[C] a creature that saves against (2024: or is missed by) your cantrip still takes half damage",
	"evoker-sculpt-spells": "[C] up to 1 + spell level allies inside your Evocation area auto-succeed and take no damage — `spare_allies` exists for Spirit Guardians and could carry this",
	"evoker-empowered-evocation": "[C] +INT to one damage roll of any Evocation spell you cast",
	"evoker-overchannel": "[C] once per long rest deal maximum damage with a 1st-5th level spell (then necrotic backlash)",
	"illusionist-illusion-savant": "[S] two free Illusion spells",
	"illusionist-improved-illusions": "[O] cast Illusion spells without Verbal components; Minor Illusion is free and better",
	"illusionist-phantasmal-creatures": "[S] Summon Beast / Summon Fey as illusions, once each without a slot",
	"illusionist-illusory-self": "[C] reaction when hit: the attack misses instead; 1/short rest (2024: once per short rest, or a slot)",
	"illusionist-illusory-reality": "[O] make one object of an Illusion spell real for a minute",
	# --- the tiers restored by tools/fill_levels.py (2026-09-22) ----------------
	# Every path below was short of its late milestones: the catalog carried
	# 3/6/10 where the book says 3/6/10/14, and the rogue's paths stopped at 9.
	# docs/audit-class-levels.md counted them; none of them has a mechanic yet.
	# barbarian
	"wildheart-animal-speaker": "[P] Beast Sense and Speak with Animals as rituals, no slot — nothing on the board reads either",
	"wildheart-nature-speaker": "[P] Commune with Nature as a ritual, no slot — a worldmap answer, not a combat one",
	"wildheart-power-of-the-wilds": "[C] entering Rage grants a movement mode (flight, or a swim speed) — Rage has no movement-mode hook",
	"worldtree-travel-along-the-tree": "[C] bonus action: teleport 60 ft, and once per Rage a 30-ft portal that carries allies with you",
	"zealot-divine-fury": "[C] first hit each turn while raging: +1d6 + half barbarian level, necrotic or radiant",
	"zealot-rage-of-the-gods": "[C] once per long rest while raging: fly, resist everything but force, and spend your own HP to raise a downed ally",
	# bard
	"collegedance-tandem-footwork": "[C] on rolling initiative, you and allies within 30 ft add your Bardic Inspiration die — initiative takes no modifiers here",
	"collegeglamour-unbreakable-majesty": "[C] bonus action for a minute: an attacker must pass a CHA save or lose the attack and cannot target you that turn",
	"collegelore-peerless-skill": "[C] spend a Bardic Inspiration die to add it to a check or attack that already failed",
	"collegevalor-battle-magic": "[C] after casting a spell with your action, one weapon attack as a bonus action",
	# cleric
	"lifedomain-supreme-healing": "[C] healing dice are maximised rather than rolled",
	"lightdomain-corona-of-light": "[C] action for a minute: 60 ft of bright light, and foes in it save at disadvantage against radiant and fire",
	"trickerydomain-improved-duplicity": "[C] the Duplicity double heals or lends advantage to allies beside it each turn",
	"wardomain-avatar-of-battle": "[P] resistance to bludgeoning, piercing and slashing from nonmagical attacks — the sheet can carry this one",
	# druid
	"circleland-natures-sanctuary": "[C] a 15-ft emanation for a minute: half cover for allies in it, and resistance to the Land's damage type",
	"circlemoon-lunar-form": "[C] Wild Shape adds radiant damage once a turn and shares Moonlight Step with an ally",
	"circlesea-oceanic-gift": "[C] Wrath of the Sea can ride on an ally instead of you, and its emanation doubles",
	"circlestars-full-of-stars": "[P] while in Starry Form, resistance to bludgeoning, piercing and slashing",
	# monk
	"warriorofmercy-flurry-of-healing-and-harm": "[C] Flurry of Blows: swap each unarmed strike for a Hand of Healing, spending no Focus",
	"warriorofmercy-hand-of-ultimate-mercy": "[C] once per long rest: return a creature dead under 24 hours, with HP and its conditions cleared",
	"warriorofshadow-improved-shadow-step": "[C] Shadow Step also grants advantage on the first unarmed strike that follows it",
	"warriorofshadow-cloak-of-shadows": "[C] spend Focus to go Invisible for a minute, ending the moment you attack",
	"warriorofelements-stride-of-the-elements": "[C] Elemental Attunement adds a swim and a fly speed while it lasts",
	"warriorofelements-elemental-epitome": "[C] while attuned: resistance to a chosen type, +10 ft speed, and extra elemental damage once a turn",
	"warrioropenhand-fleet-step": "[C] any bonus action that is not already Step of the Wind also takes Step of the Wind",
	"warrioropenhand-quivering-palm": "[C] spend Focus on an unarmed strike, then an action forces a CON save for 10d12 or 0 HP",
	# ranger
	"beastmaster-bestial-fury": "[C] the Primal Companion attacks twice on its Attack action, with force damage added",
	"beastmaster-share-spells": "[C] a spell you target yourself with also reaches the companion within 30 ft",
	"feywanderer-fey-reinforcements": "[C] Summon Fey always prepared, and once per long rest without a slot",
	"feywanderer-misty-wanderer": "[C] Misty Step WIS-mod times per long rest without a slot, carrying an ally with you",
	"gloomstalker-stalkers-flurry": "[C] once a turn on a miss: a second attack, or a WIS save against being Frightened",
	"gloomstalker-shadowy-dodge": "[C] reaction: disadvantage on an attack against you, and teleport up to 30 ft",
	"hunter-superior-hunters-prey": "[C] Hunter\'s Prey damage also lands on a second creature near the target",
	"hunter-superior-hunters-defense": "[C] reaction: halve one attack\'s damage and take resistance to that type",
	# rogue
	"thief-use-magic-device": "[C] attune to four items, read any spell scroll, and reroll a magic item\'s expended charges",
	"thief-thiefs-reflexes": "[C] two turns in the first round, the second of them at initiative minus 10 — the tracker takes one turn per combatant",
	"assassin-envenom-weapons": "[C] poison from a Poisoner\'s Kit deals 2d6 more and is saved against your DC",
	"assassin-death-strike": "[C] against a surprised creature, a hit doubles its damage unless the target passes a CON save",
	"arcanetrickster-versatile-trickster": "[C] Mage Hand lends advantage on attacks against a creature within 5 ft of it",
	"arcanetrickster-spell-thief": "[C] once per long rest: a failed save takes the spell off its caster for eight hours",
	"soulknife-psychic-veil": "[C] once per long rest: Invisible for an hour, and silent while it holds",
	"soulknife-rend-mind": "[C] a Sneak Attack with a Psychic Blade forces a WIS save or Stunned for a minute",
}

func report() -> void:
	print("\n--- subclass features on the board vs in prose ---")
	var subs: Array = Catalog.all("subclasses.json")
	var live_n := 0
	var flavor_n := 0
	var combat_gaps := 0
	var missing_note: Array = []
	for sub in subs:
		var sid := String(sub["id"])
		var live: Array = _live.get(sid, [])
		var flavor: Array = _flavor.get(sid, [])
		live_n += live.size()
		flavor_n += flavor.size()
		print("  %-20s %d mechanical, %d prose" % [sid, live.size(), flavor.size()])
		for fid in live:
			print("      + %s" % fid)
		for fid in flavor:
			var n := String(RAW_NOTES.get(fid, ""))
			if n == "":
				missing_note.append(fid)
				n = "[?] (no note)"
			if n.begins_with("[C]") or n.begins_with("[C/"):
				combat_gaps += 1
			print("      - %-52s %s" % [fid, n])
	print("  TOTAL %d mechanical, %d prose — %d of the prose ones are combat mechanics the board does not have ([C])" % [live_n, flavor_n, combat_gaps])
	check(missing_note.is_empty(), "every un-authored subclass feature has an inventory note: %s" % ", ".join(missing_note))
	var stale: Array = []
	for fid in RAW_NOTES:
		var found := false
		for sid in _flavor:
			if fid in _flavor[sid]:
				found = true
		for sid in _live:
			if fid in _live[sid]:
				found = true
		if not found:
			stale.append(fid)
	check(stale.is_empty(), "no inventory note names a feature the catalog no longer grants: %s" % ", ".join(stale))
	if not _notes.is_empty():
		print("\n--- questions about the authored ones ---")
		for n in _notes:
			print("  ", n)

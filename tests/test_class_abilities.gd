# Every class and every subclass, built for real and played for real.
#
# The suite had class coverage only where a preset happened to have it: three
# heroes, three subclasses, and every rules test that needed a character used
# one of them or a bare `_build("sorcerer", 5)` with nothing decided. That left
# the whole rules engine unexercised on 45 of the 48 subclasses, and — worse —
# unexercised on the one thing that separates a real character from a fixture:
# DECISIONS. Half the resolver's inputs only exist once a build has answered its
# choice points, so a bug that only shows up on a decided build was invisible.
# (core/rules/bundles.gd class_level() was exactly that bug.)
#
# So: the 48 (class, subclass) pairs are dealt into twelve four-hero TEAMS, each
# team is built at level 4 and again at level 8 — the two rungs where the
# subclass has landed and the class's second tier of features has (Extra Attack,
# the 2024 level-5/6/7 subclass features) — and then every one of them is put on
# a board and made to press every button their kit offers.
#
# Four kinds of claim:
#   1. the build resolves     — no pending choices, no warnings, sane numbers
#   2. the level is the level — Bundles.class_level agrees with Character.level()
#   3. the kit is coherent    — no duplicate spells/verbs, pools within RAW
#   4. the buttons work       — every offered verb performs and leaves a trace
#
# and one REPORT, printed rather than asserted: which class and subclass features
# reach combat at all. A feature with no data/effects/features.json entry is a
# flavor feature by design (see core/rules/effects.gd) — the report is how you
# see, at a glance, how much of a subclass is currently flavor.
#
#   godot --headless --path . -s tests/test_class_abilities.gd
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const Leveling = preload("res://core/leveling.gd")
const Adapter = preload("res://core/adapter.gd")
const Effects = preload("res://core/rules/effects.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const RNG = preload("res://core/rng.gd")

const LEVELS := [4, 8]
const TEAM_SIZE := 4

# The one warning a finished build is still allowed to carry: the export ships no
# starting-equipment bundles, so barbarian/fighter/rogue's `bundle-choice` grants
# can never resolve (SCHEMA gap #2). Gear is picked off the creator's own lists
# instead, which is what a player does.
const ALLOWED_WARNING := "starting-equipment bundles are not exported"

var _pass := 0
var _fail := 0
var _feature_seen := {}      # feature id -> does it have a data/effects entry
var _pool_spendable := {}    # pool id -> bool
var _verb_kinds := {}

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var teams := deal_teams()
	check(teams.size() == 12, "48 subclasses deal into 12 teams of 4 (got %d)" % teams.size())
	for lvl in LEVELS:
		for t in teams.size():
			var party: Array = []
			for pair in teams[t]:
				party.append(build(pair[0], pair[1], lvl))
			for ch in party:
				audit_build(ch, lvl)
			play(party, lvl, t)
	test_unarmored_defense()
	test_known_pool_sizes()
	test_scaled_abilities()
	report()
	print("test_class_abilities: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- the teams -----------------------------------------------------------
#
# Dealt round-robin rather than sliced, so a team is four different classes
# instead of four subclasses of the same one: team t gets pairs t, t+12, t+24,
# t+36. A fight between one barbarian, one fighter, one ranger and one wizard
# exercises more of the resolver's interactions than four barbarians would.
func deal_teams() -> Array:
	var pairs: Array = []
	for c in Catalog.all("classes.json"):
		for sid in Catalog.subclasses_of(c["id"]):
			pairs.append([c["id"], sid])
	check(pairs.size() == 48, "12 classes x 4 subclasses = 48 builds (got %d)" % pairs.size())
	var n: int = ceili(pairs.size() / float(TEAM_SIZE))
	var teams: Array = []
	for t in n:
		var team: Array = []
		for k in TEAM_SIZE:
			var i: int = t + k * n
			if i < pairs.size():
				team.append(pairs[i])
		teams.append(team)
	return teams

# --- building ------------------------------------------------------------
#
# The creator's own static choice model, driven exactly the way tests/
# test_creator.gd drives it: resolve, take the first pending choice, pick off
# its option list, re-resolve. `prefer` is how the subclass choice is steered to
# the one this build is for; everything else takes the head of the list, which
# is deterministic and (deliberately) not always the smart pick — a build nobody
# would make must still resolve.
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

func build(cid: String, sid: String, lvl: int):
	var ch = Creator.new_character()
	ch.id = "%s-%s-%d" % [cid, sid, lvl]
	ch.cname = "%s/%s" % [cid, sid]
	ch.species_id = "human"
	ch.background_id = String(Catalog.class_src(cid).get("quickBuild", {}).get("suggestedBackground", "soldier"))
	ch.base_abilities = Creator.recommended_array(cid)
	Leveling.grant_levels(ch, lvl, cid)
	for _step in 120:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			break
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet, sid if p["type"] == "subclass" else "")
		check(not picks.is_empty(), "%s L%d: %s (%s) offers options" % [ch.cname, lvl, p["type"], p["key"]])
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	equip_best(ch)
	return ch

# The creator's gear step, headless: the best weapon and the best body armor the
# build is actually proficient with, plus a shield when it can hold one. Armor
# matters to this test beyond AC — "is this character wearing armor" is an input
# to Unarmored Defense, and a build that never equips anything never asks.
func equip_best(ch) -> void:
	var sheet = ch.sheet()
	var eq: Array = []
	var best_w := ""
	var best_dmg := -1
	for wid in Creator.proficient_weapons(sheet):
		var dice := String(Catalog.weapon(wid).get("damageDice", "1d4")).split("d")
		var d: int = int(dice[0]) * int(dice[1]) if dice.size() == 2 else 0
		if d > best_dmg:
			best_dmg = d
			best_w = wid
	if best_w != "":
		eq.append(best_w)
	var best_a := ""
	var best_ac := -1
	for aid in Creator.proficient_armor(sheet):
		if aid == "shield":
			continue
		var a := Catalog.armor(aid)
		if int(a.get("baseAc", 0)) > best_ac:
			best_ac = int(a["baseAc"])
			best_a = aid
	if best_a != "":
		eq.append(best_a)
	if "shield" in Creator.proficient_armor(sheet):
		eq.append("shield")
	ch.equipped.assign(eq)
	ch.dirty()

# --- 1-3. the build, the level, the kit ----------------------------------

func audit_build(ch, lvl: int) -> void:
	var s = ch.sheet()
	var who := "%s L%d" % [ch.cname, lvl]
	check(s.pending.is_empty(), "%s: every choice is made (%d left: %s)" % [who, s.pending.size(),
		", ".join(s.pending.map(func(p): return String(p["type"])))])
	for w in s.warnings:
		check(w.contains(ALLOWED_WARNING), "%s: unexpected resolver warning — %s" % [who, w])

	# 2. the level is the level. Every number a class feature scales by is read
	# off one of these two, and they are computed by different code.
	var b: Array = Bundles.collect(ch)["bundles"]
	var cid: String = ch.class_id()
	check(Bundles.class_level(b, cid) == lvl,
		"%s: Bundles.class_level says %d" % [who, Bundles.class_level(b, cid)])
	check(s.class_level(cid) == lvl, "%s: the sheet's class level says %d" % [who, s.class_level(cid)])
	check(s.proficiency_bonus == Bundles.proficiency_bonus(lvl), "%s: proficiency bonus" % who)

	# 3. sane sheet numbers. Wide bands on purpose — this catches an order-of-
	# magnitude slip (an AC keyed off a die size, an HP total off a bad hit die),
	# not a point of tuning.
	check(s.max_hp >= lvl * 4 and s.max_hp <= lvl * 14,
		"%s: %d HP is in range for level %d" % [who, s.max_hp, lvl])
	check(s.ac >= 10 and s.ac <= 21, "%s: AC %d is a number a character can have" % [who, s.ac])
	check(s.abilities["str"]["total"] <= 20, "%s: no ability over 20" % who)

	var sc: Dictionary = s.spellcasting
	if not sc.is_empty():
		var ids: Array = []
		ids.append_array(sc.get("cantrips", []))
		ids.append_array(sc.get("always_prepared", []))
		for k in sc.get("known", []):
			ids.append(String(k["id"]))
		var seen := {}
		for sid in ids:
			check(not seen.has(sid), "%s: knows %s once, not twice" % [who, sid])
			seen[sid] = true

	for fid in s.features:
		var sub := String(s.subclasses.get(cid, ""))
		if fid.begins_with(cid) or (sub != "" and fid.begins_with(sub)):
			_feature_seen[fid] = not Effects.feature(fid).is_empty()
	# Seen here, marked spendable in play() — so a pool no verb ever names is
	# still in the tally, which is the only way it can be reported.
	for p in s.pools:
		if not _pool_spendable.has(p["id"]):
			_pool_spendable[String(p["id"])] = false

# --- 4. the buttons ------------------------------------------------------
#
# A fight, and then every verb the action bar would offer, pressed. The turn is
# reset before each press (and the actor put back beside a foe) so that pressing
# one button cannot be what makes the next one untestable — this is a sweep of
# the kit, not a simulation of a turn.
func play(chars: Array, lvl: int, t: int) -> void:
	var board: Dictionary = Encounter.board_for("sunken-shrine")
	var all_c: Array = []
	for i in chars.size():
		all_c.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var spots: Array = Encounter._foe_spots(board, all_c)
	for i in 3:
		var m = Encounter.spawn("ogre" if i == 0 else "goblin", 1.0, "foe",
			spots[i] if i < spots.size() else Vector2i(6, 6), i + 1)
		if m != null:
			all_c.append(m)
	var cb = Combat.new(RNG.new(4000 + t * 31 + lvl), all_c, board)
	var foe = all_c.filter(func(c): return c.team == "foe")[0]

	# The actor stays on its start hex and the two things a verb can be pointed
	# at are brought to IT: one foe and one ally, parked adjacent for the length
	# of the sweep and put back after. Walking the actor to the foe instead (the
	# obvious way round) silently costs coverage twice over — the hero ends up
	# far from its own party, so nothing ally-targeted is ever offered, and the
	# hexes beside the foe fill up with heroes who came before.
	for a in all_c:
		if a.team != "party":
			continue
		var who := "%s L%d" % [a.cname, lvl]
		var mate = all_c.filter(func(c): return c.team == "party" and c != a)[0]
		var was := {foe: foe.pos, mate: mate.pos}
		foe.pos = free_beside(cb, a, foe)
		mate.pos = free_beside(cb, a, mate)
		check(Hex.distance(a.pos, foe.pos) == 1, "%s: a foe stands within reach" % who)
		check(Hex.distance(a.pos, mate.pos) == 1, "%s: an ally stands within reach" % who)
		var kit: Array = cb.all_verbs(a)
		check(not kit.is_empty(), "%s: has at least one button" % who)
		var ids := {}
		for v in kit:
			check(not ids.has(v["id"]), "%s: %s is on the bar once, not twice" % [who, v["id"]])
			ids[v["id"]] = true
		for v in kit:
			if v.has("pool"):
				_pool_spendable[String(v["pool"])] = true
				# A button whose pool holds nothing is a button that can never be
				# pressed — not "spent", EMPTY, for the whole life of the
				# character. That is what the Cleric's Channel Divinity was: the
				# export grants the pool to the paladin only, so the cleric's verb
				# was built with 0 uses and adapter.gd made it a 0-max pool.
				var pool: Dictionary = a.pools.get(v["pool"], {})
				check(int(pool.get("max", 0)) > 0, "%s: %s spends \"%s\", which has %d uses"
					% [who, v["id"], v["pool"], int(pool.get("max", 0))])
			press(cb, a, v, foe, who)
		for c in was:
			c.pos = was[c]

func press(cb, a, v: Dictionary, foe, who: String) -> void:
	cb.begin_turn_for(a)
	a.hp = a.max_hp / 2                       # so a heal has somewhere to go
	# The dummy is put back on its feet between presses. Without this the first
	# few heroes of a team kill it outright and every hero after them is testing
	# their melee kit against a corpse, which offers no enemy-targeted verb at
	# all — the coverage vanishes silently rather than failing.
	foe.hp = foe.max_hp
	foe.statuses.erase("down")
	if not cb._offerable(a, v):
		return
	var target = target_for(cb, a, v, foe)
	if target == null:
		return
	var log_before: int = cb.log.size()
	var r: Dictionary = cb.perform(a, v, target)
	_verb_kinds[String(v["kind"])] = int(_verb_kinds.get(v["kind"], 0)) + 1
	check(not r.has("error"), "%s: %s (%s) performs — %s" % [who, v["id"], v["kind"], r.get("error", "")])
	# A verb that returns nothing AND writes nothing to the log did nothing at
	# all: the press was swallowed. Every kind in the engine either resolves to a
	# result dictionary or narrates itself.
	check(not (r.is_empty() and cb.log.size() == log_before),
		"%s: %s (%s) left a trace" % [who, v["id"], v["kind"]])

# A passable, unoccupied hex next to `anchor` — melee verbs need reach, and a
# combatant standing inside a wall is not a fair test of anything.
func free_beside(cb, anchor, mover) -> Vector2i:
	for d in Hex.DIRS:
		var p: Vector2i = anchor.pos + d
		if cb.passable(p) and cb._hex_free(p, mover):
			return p
	return mover.pos

func target_for(cb, a, v: Dictionary, foe):
	match v.get("targeting", "self"):
		"enemy":
			for e in cb.enemies_of(a):
				if cb.legal_target(a, v, e):
					return e
			return null
		"ally":
			for c in cb.combatants:
				if cb.legal_target(a, v, c):
					return c
			return null
		"object":
			var o: Dictionary = cb.smashable_near(a)
			return null if o.is_empty() else foe
		"self", "self_area", "allies":
			return a
		"hex", "corner", "line":
			# An area or a teleport is aimed at a hex, and a teleport's has to be
			# free — the foe is standing in its own.
			return foe.pos if not v.get("teleport", false) else free_beside(cb, a, a)
		"direction":
			return Hex.DIRS[0]
	return foe

# --- the three Unarmored Defenses ----------------------------------------
#
# Each is "10 + DEX + <something>, while you aren't wearing armor" and the rider
# is as load-bearing as the formula. Built here rather than swept above because
# the claim is about a specific pair of numbers, armored and not.
func test_unarmored_defense() -> void:
	var cases := [
		# class, subclass, the ability that tops up 10 + DEX, may hold a shield
		["barbarian", "berserker", "con", true],
		["monk", "warrioropenhand", "wis", false],
		["bard", "collegedance", "cha", false],
	]
	for c in cases:
		var ch = build(c[0], c[1], 8)
		ch.equipped.assign([])                # bare
		ch.dirty()
		var s = ch.sheet()
		var want: int = 10 + s.mod("dex") + s.mod(c[2])
		check(s.ac == want, "%s unarmored: AC %d, want 10 + DEX + %s = %d"
			% [c[1], s.ac, String(c[2]).to_upper(), want])

		# Armor turns the Unarmored Defense off — and is not thereby ignored.
		# Barbarian and monk are granted no `armored` calculation at all, so this
		# is also the check that the implicit one exists.
		var armor := "chain-mail" if c[0] == "barbarian" else "leather"
		ch.equipped.assign([armor])
		ch.dirty()
		var armored = ch.sheet()
		var a := Catalog.armor(armor)
		var cap = a["maxDexBonus"]
		var dex: int = armored.mod("dex") if cap == null else clampi(armored.mod("dex"), 0, int(cap))
		check(armored.ac == int(a["baseAc"]) + dex,
			"%s in %s: AC %d is the armor's, not the bare formula's" % [c[1], armor, armored.ac])

		# RAW, the barbarian's Unarmored Defense is the only one of the three that
		# survives a Shield, and it is also the only one of the three whose class
		# is proficient with shields — a monk or a dancer can't pick one up in the
		# creator at all, so the other half of that rule is unreachable today and
		# there is nothing here to assert about it.
		if not bool(c[3]):
			continue
		ch.equipped.assign(["shield"])
		ch.dirty()
		var shielded = ch.sheet()
		check(shielded.ac == want + 2, "%s with a shield: AC %d, want %d"
			% [c[1], shielded.ac, want + 2])

# --- resource pools against the rules ------------------------------------
#
# Every one of these is scaled off a class level by data/classes.json, so they
# are the cheapest possible smoke test that the class level is the class level.
# Numbers are 2024 RAW at the two levels this file plays.
func test_known_pool_sizes() -> void:
	var want := {
		"barbarian/berserker":    {4: {"rage": 3}, 8: {"rage": 4}},
		"sorcerer/wildmagicsorcery": {4: {"sorcery-points": 4}, 8: {"sorcery-points": 8}},
		"paladin/oathofdevotion": {4: {"channel-divinity": 2}, 8: {"channel-divinity": 3}},
		"monk/warrioropenhand":   {4: {"focus-points": 4}, 8: {"focus-points": 8}},
		"fighter/psiwarrior":     {4: {"psionic-energy": 4}, 8: {"psionic-energy": 6}},
		"cleric/wardomain":       {4: {"war-priest": 2}, 8: {"war-priest": 3}},
	}
	for key in want:
		var parts: PackedStringArray = String(key).split("/")
		for lvl in want[key]:
			var ch = build(parts[0], parts[1], lvl)
			var have := {}
			for p in ch.sheet().pools:
				have[String(p["id"])] = int(p["max"])
			for pid in want[key][lvl]:
				check(int(have.get(pid, -1)) == int(want[key][lvl][pid]),
					"%s L%d: %s is %s, want %d" % [key, lvl, pid, str(have.get(pid, "absent")),
						int(want[key][lvl][pid])])

# --- the numbers a class feature scales by -------------------------------
#
# Every one of these is read out of data/effects/features.json through
# Effects.scale(by: "class_level"), which is the OTHER path a class level takes
# through the engine (the pools above are the first). Named, RAW, at both rungs.
func test_scaled_abilities() -> void:
	for lvl in LEVELS:
		var bard = Adapter.to_combatant(build("bard", "collegelore", lvl), "party", Vector2i.ZERO)
		var insp := verb(bard, "bard-bardic-inspiration")
		check(int(insp.get("dice_sides", 0)) == (6 if lvl < 5 else 8),
			"bard L%d: Bardic Inspiration is a d%d" % [lvl, int(insp.get("dice_sides", 0))])
		# 60 feet, not "whoever I am standing on". An ally_buff with no authored
		# range_ft fell through to adapter.gd's 5 ft default and the bard had to
		# be in melee to inspire anyone.
		check(int(insp.get("range", 0)) == Adapter.hexes(60),
			"bard L%d: Bardic Inspiration reaches %d hexes, want %d"
				% [lvl, int(insp.get("range", 0)), Adapter.hexes(60)])

		var cleric = Adapter.to_combatant(build("cleric", "lightdomain", lvl), "party", Vector2i.ZERO)
		var cd := verb(cleric, "cleric-channel-divinity")
		check(not cd.is_empty(), "cleric L%d: Channel Divinity is on the bar" % lvl)
		check(int(cleric.pools.get("channel-divinity", {}).get("max", 0)) == (2 if lvl < 6 else 3),
			"cleric L%d: Channel Divinity has %d uses" % [lvl,
				int(cleric.pools.get("channel-divinity", {}).get("max", 0))])

		var barb = Adapter.to_combatant(build("barbarian", "berserker", lvl), "party", Vector2i.ZERO)
		check(int(verb(barb, "barbarian-rage").get("bonus_damage", 0)) == 2,
			"barbarian L%d: Rage damage is +2 below level 9" % lvl)

		var rog = Adapter.to_combatant(build("rogue", "thief", lvl), "party", Vector2i.ZERO)
		check(int(verb(rog, "rogue-sneak-attack").get("dice_count", 0)) == ceili(lvl / 2.0),
			"rogue L%d: Sneak Attack is %dd6" % [lvl, ceili(lvl / 2.0)])

		# Martial Arts is not a verb — it is the unarmed strike's own die.
		var monk = Adapter.to_combatant(build("monk", "warrioropenhand", lvl), "party", Vector2i.ZERO)
		var unarmed: Array = monk.attacks.filter(func(x): return String(x["id"]) == "unarmed-strike")
		check(not unarmed.is_empty() and int(unarmed[0]["dice_sides"]) == (6 if lvl < 5 else 8),
			"monk L%d: Martial Arts die" % lvl)

func verb(c, id: String) -> Dictionary:
	for v in c.verbs:
		if String(v["id"]) == id:
			return v
	return {}

# --- the report ----------------------------------------------------------
#
# Not assertions. A feature with no data/effects/features.json entry shows on the
# sheet and does nothing in a fight, which is the documented default (430 feature
# ids, 65 authored) — this is the inventory of what that default currently costs,
# per class, so the next person to author a subclass's mechanics can see which
# ones are still prose.
func report() -> void:
	var by_class := {}
	for fid in _feature_seen:
		var cid: String = fid.split("-")[0]
		var row: Dictionary = by_class.get_or_add(cid, {"live": [], "flavor": []})
		row["live" if _feature_seen[fid] else "flavor"].append(fid)
	print("\n--- class & subclass features that reach combat ---")
	var live := 0
	var flavor := 0
	for cid in by_class:
		var row: Dictionary = by_class[cid]
		live += row["live"].size()
		flavor += row["flavor"].size()
		print("  %-20s %d mechanical, %d flavor" % [cid, row["live"].size(), row["flavor"].size()])
		if not row["flavor"].is_empty():
			print("      flavor: %s" % ", ".join(row["flavor"]))
	print("  TOTAL %d mechanical, %d flavor (%d%% of the features these builds carry do nothing in a fight)"
		% [live, flavor, roundi(100.0 * flavor / maxi(1, live + flavor))])

	# A pool nothing can spend is a resource bar the player watches and never
	# uses — the same gap as a flavor feature, one level up.
	var dead: Array = []
	for pid in _pool_spendable:
		if not _pool_spendable[pid]:
			dead.append(pid)
	dead.sort()
	print("\n--- resource pools these builds carry ---")
	print("  %d spendable by some verb, %d with no verb to spend them:" % [
		_pool_spendable.size() - dead.size(), dead.size()])
	print("      %s" % ", ".join(dead))

	print("\n--- verb kinds exercised ---")
	var kinds: Array = _verb_kinds.keys()
	kinds.sort()
	for k in kinds:
		print("  %-18s x%d" % [k, int(_verb_kinds[k])])

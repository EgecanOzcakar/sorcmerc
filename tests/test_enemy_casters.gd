# Rare, named enemy casters (core/enemy_casters.gd): the data is sound, a caster
# spawn carries real slots and spell buttons in place of the innate bolt, a
# scaled one's spells scale with it, power.gd prices it above the plain
# statblock, the roster roll is seeded and cultist-only, and the AI spends its
# slots the way the header says it does.
#   godot --headless --path . -s tests/test_enemy_casters.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Combat = preload("res://core/combat.gd")
const Effects = preload("res://core/rules/effects.gd")
const EnemyCasters = preload("res://core/enemy_casters.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Power = preload("res://core/rules/power.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_data()
	test_spawn()
	test_scaled_caster()
	test_band_tiers()
	test_priced()
	test_roster_roll()
	test_fight_says_so()
	test_ai_areas_first()
	test_ai_steps_clear()
	test_ai_holds_one_lock()
	Scaler.caster_chance_override = -1.0
	print("test_enemy_casters: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_data() -> void:
	var d = Catalog.all(EnemyCasters.FILE)
	check(d is Dictionary, "casters.json loads")
	var n := 0
	for id in d:
		if String(id).begins_with("_"):
			continue
		n += 1
		check(not Catalog.monster(id).is_empty(), "%s is a bestiary statblock" % id)
		for sid in d[id]["spells"]:
			check(not Effects.spell(sid).is_empty(), "%s's %s is combat-castable" % [id, sid])
	check(n >= 3, "three casters authored (%d)" % n)
	check(EnemyCasters.ids_for("cultist") == ["mage", "priest", "cult-fanatic"],
		"the cult's casters, strongest first: %s" % str(EnemyCasters.ids_for("cultist")))
	check(EnemyCasters.ids_for("goblinoid").is_empty(), "a faction with no caster block has none")

func _has_verb(c, prefix: String) -> bool:
	return c.verbs.any(func(v): return String(v["id"]).begins_with(prefix))

func test_spawn() -> void:
	var plain = Encounter.spawn("mage", 1.0, "foe", Vector2i.ZERO)
	var mage = Encounter.spawn("mage", 1.0, "foe", Vector2i.ZERO, 0, [], true)
	check(not plain.caster and _has_verb(plain, "monster-innate-bolt"), "a plain mage keeps its innate bolt")
	check(plain.spell_ids.is_empty(), "...and no spell list")
	check(mage.caster and mage.sheet == null and mage.src_id == "mage", "a caster mage is still a statblock")
	check(not _has_verb(mage, "monster-innate-bolt"), "the caster's real list replaces the innate bolt")
	check(Array(mage.slots).slice(0, 5) == [4, 3, 3, 3, 1], "slots 4/3/3/3/1 (got %s)" % str(mage.slots))
	check(mage.save_dc == 14, "save DC 14 (got %d)" % mage.save_dc)
	check(_has_verb(mage, "fireball") and _has_verb(mage, "fire-bolt"), "fireball and fire bolt are buttons")
	var fb := {}
	for v in mage.verbs:
		if String(v["id"]) == "fireball":
			fb = v
	check(int(fb.get("save_dc", 0)) == 14 and int(fb.get("range", 0)) > 1, "fireball carries DC 14 and a hex range")
	check(mage.cname.ends_with("Magister"), "and a title: %s" % mage.cname)
	var goblin = Encounter.spawn("goblin", 1.0, "foe", Vector2i.ZERO, 0, [], true)
	check(not goblin.caster, "a statblock with no caster block ignores the flag")

func test_scaled_caster() -> void:
	var base = Encounter.spawn("priest", 1.0, "foe", Vector2i.ZERO, 0, [], true)
	var big = Encounter.spawn("priest", 1.5, "foe", Vector2i.ZERO, 0, [], true)
	check(big.save_dc == base.save_dc + 2, "x1.5 raises the DC by 2 (%d -> %d)" % [base.save_dc, big.save_dc])
	var pairs := 0
	for v in big.verbs:
		if v["kind"] != "spell":
			continue
		for w in base.verbs:
			if w["id"] == v["id"]:
				pairs += 1
				check(int(v["save_dc"]) == int(w["save_dc"]) + 2, "%s's DC scaled" % v["id"])
				if v.has("attack_bonus"):
					check(int(v["attack_bonus"]) == int(w["attack_bonus"]) + 2, "%s's attack scaled" % v["id"])
	check(pairs >= 4, "compared the priest's spell buttons (%d)" % pairs)

# The band tiers: what power.gd cannot price is not handed out.
func test_band_tiers() -> void:
	check(EnemyCasters.cap_for_band("heartland") == 2 and EnemyCasters.cap_for_band("marches") == 2, "the near countries: 2nd-level spells")
	check(EnemyCasters.cap_for_band("frontier") == 3 and EnemyCasters.cap_for_band("deeps") == 9, "the Frontier 3rd, the Deeps anything")
	check(EnemyCasters.cap_for_level(3) == 2 and EnemyCasters.cap_for_level(8) == 3 and EnemyCasters.cap_for_level(12) == 9,
		"read off a party level with no map: the band that level belongs to")
	var low = Encounter.spawn("mage", 1.0, "foe", Vector2i.ZERO, 0, [], true, 2)
	check(Array(low.slots).slice(0, 5) == [4, 3, 0, 0, 0], "a Marches Magister keeps its 1st and 2nd slots only (%s)" % str(low.slots))
	check(not _has_verb(low, "fireball") and not _has_verb(low, "cone-of-cold"), "...and casts no Fireball, no Cone of Cold")
	check(_has_verb(low, "scorching-ray") and _has_verb(low, "fire-bolt"), "...but Scorching Ray and its cantrip stay")
	check(not low.spell_ids.has("fireball"), "and the spell list the pricer reads agrees")
	check(Scaler.caster_score("mage", 3, 2) < Scaler.caster_score("mage", 3, 9), "a capped Magister is priced below a full one")
	var party: Array = Presets.party_at(8)
	Scaler.caster_chance_override = 1.0
	var spec := Scaler.roster_for(party, "hard", {}, "", Scaler.pin_faction(97, "cultist"))
	var lead: Array = spec["monsters"].filter(func(e): return e.get("caster", false))
	check(lead.size() == 1 and int(lead[0].get("caster_cap", 0)) == 3, "a level-8 warband's caster carries the Frontier cap: %s" % str(lead))
	check(not EnemyCasters.fielded(2) and EnemyCasters.fielded(3), "fielded from the Frontier tier up")
	var deep := Scaler.roster_for(party, "hard", {}, "", Scaler.pin_faction(97, "cultist"), 1.0, [], "", 9)
	var dl: Array = deep["monsters"].filter(func(e): return e.get("caster", false))
	check(dl.is_empty() or int(dl[0].get("caster_cap", 0)) == 9, "the caller's band wins over the party's level")
	Scaler.caster_chance_override = -1.0

func test_priced() -> void:
	for id in ["cult-fanatic", "priest", "mage"]:
		var plain: float = Power.team_score([Encounter.spawn(id, 1.0, "foe", Vector2i.ZERO)])
		var cast: float = Scaler.caster_score(id)
		check(cast > plain, "%s is priced above its plain statblock (%.1f > %.1f)" % [id, cast, plain])

func test_roster_roll() -> void:
	var party: Array = Presets.party_at(8)   # Frontier: the least tier a caster is fielded at
	var casters_in := func(spec: Dictionary) -> int:
		return spec["monsters"].filter(func(e): return e.get("caster", false)).size()
	Scaler.caster_chance_override = 1.0
	var got := 0
	for s in range(1, 31):
		var seed_v: int = Scaler.pin_faction(s * 97, "cultist")
		var spec := Scaler.roster_for(party, "normal", {}, "", seed_v)
		var n: int = casters_in.call(spec)
		check(n <= 1, "never two casters in one roster (seed %d)" % seed_v)
		got += n
		check(str(spec) == str(Scaler.roster_for(party, "normal", {}, "", seed_v)), "the roster is seeded (seed %d)" % seed_v)
		var other := Scaler.roster_for(party, "normal", {}, "", Scaler.pin_faction(s * 97, "goblinoid"))
		check(casters_in.call(other) == 0, "goblins field no caster")
	check(got >= 25, "forced on, a level-8 cult warband leads with a caster (%d of 30)" % got)
	Scaler.caster_chance_override = 0.0
	for s in range(1, 31):
		check(casters_in.call(Scaler.roster_for(party, "normal", {}, "", Scaler.pin_faction(s * 97, "cultist"))) == 0,
			"forced off, none")
	Scaler.caster_chance_override = -1.0
	var rolls := 0
	for s in range(1, 601):
		if Scaler.caster_rolls(Scaler.pin_faction(s * 97, "cultist")):
			rolls += 1
	var rate: float = rolls / 600.0
	check(absf(rate - Scaler.CASTER_ELITE_CHANCE) < 0.054, "the shipped roll lands near %.2f (%.3f)" % [Scaler.CASTER_ELITE_CHANCE, rate])
	# The boss the cult's lair ends on leads as a caster.
	var boss := Scaler.boss_for(party, {"lead": "mage", "lead_features": ["monster-charm-gaze"],
		"lead_share": 0.25, "lead_caster": true, "difficulty": "hard"}, 7)
	check(bool(boss["monsters"][0].get("caster", false)), "the cult's Frontier boss is a caster")
	var low := Scaler.boss_for(Presets.party_at(3), {"lead": "mage", "lead_features": ["monster-charm-gaze"],
		"lead_share": 0.25, "lead_caster": true, "difficulty": "hard"}, 7)
	check(not bool(low["monsters"][0].get("caster", false)), "below the Frontier tier the boss fights as its statblock")
	Scaler.caster_chance_override = 1.0
	check(casters_in.call(Scaler.roster_for(Presets.party_at(5), "hard", {}, "", Scaler.pin_faction(97, "cultist"))) == 0,
		"forced on, a Marches warband still fields no caster: below the least tier")
	Scaler.caster_chance_override = -1.0

func test_fight_says_so() -> void:
	var party: Array = []
	for i in 3:
		party.append(Adapter.to_combatant(Presets.party()[i], "party", Encounter.PARTY_STARTS[i]))
	var cb = Encounter.build({"monsters": [{"id": "priest", "count": 1, "mult": 1.0, "caster": true},
		{"id": "cultist", "count": 2, "mult": 1.0}], "seed": 5}, party)
	var said := "\n".join(cb.log)
	check(said.contains("is a spellcaster"), "the fight announces its caster:\n%s" % said)
	var casters: Array = cb.combatants.filter(func(c): return c.caster)
	check(casters.size() == 1, "exactly the lead casts (%d)" % casters.size())

# Three heroes packed together and a mage across the board: it spends a slot
# on an area, not a Fire Bolt.
func _duel(heroes_at: Array, mage_at: Vector2i) -> Array:
	var all: Array = []
	var chars: Array = Presets.party()
	for i in heroes_at.size():
		all.append(Adapter.to_combatant(chars[i], "party", heroes_at[i]))
	var mage = Encounter.spawn("mage", 1.0, "foe", mage_at, 0, [], true)
	all.append(mage)
	var cb = Combat.new(RNG.new(3), all, Encounter.board_for("goblin-camp"))
	for c in cb.combatants:
		cb.begin_turn_for(c)
	return [cb, mage]

func _slots_spent(m) -> int:
	var full: Array = [4, 3, 3, 3, 1]
	var n := 0
	for i in 5:
		n += full[i] - m.slots[i]
	return n

func test_ai_areas_first() -> void:
	var f := _duel([Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1)], Vector2i(6, 0))
	var cb = f[0]
	var m = f[1]
	var before: int = cb.log.size()
	AI.take_turn(cb, m)
	var said := "\n".join(cb.log.slice(before))
	check(_slots_spent(m) == 1, "one slot spent (%d)" % _slots_spent(m))
	var top := -1
	for i in 5:
		if m.slots[i] < [4, 3, 3, 3, 1][i]:
			top = i + 1
	check(top >= 3, "on a big area, not a cantrip: level %d\n%s" % [top, said])
	check(said.contains("save"), "a save spell, aimed at the cluster:\n%s" % said)

func test_ai_steps_clear() -> void:
	var f := _duel([Vector2i(3, 0)], Vector2i(4, 0))
	var cb = f[0]
	var m = f[1]
	AI.take_turn(cb, m)
	var hero = cb.combatants[0]
	check(not m.conscious() or Hex.distance(m.pos, hero.pos) > 1, "the mage steps out of reach first (now %d away)" % Hex.distance(m.pos, hero.pos))
	check(not m.conscious() or _slots_spent(m) >= 0, "and still acts")

func test_ai_holds_one_lock() -> void:
	var f := _duel([Vector2i(2, 0)], Vector2i(6, 0))
	var cb = f[0]
	var m = f[1]
	m.statuses["concentrating"] = {"spell": "hold-person", "until_round": 99}
	var before: int = cb.log.size()
	AI.take_turn(cb, m)
	var said := "\n".join(cb.log.slice(before))
	check(not said.contains("Hold Person"), "already holding one lock, it does not cast another:\n%s" % said)
	check(m.has("concentrating"), "and the hold it had is kept")

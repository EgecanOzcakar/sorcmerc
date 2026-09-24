# The sorcerer's own two features, as the 2024 PHB has them: Innate Sorcery
# (+1 spell save DC and Advantage on spell attacks for a minute, twice per long
# rest) and Font of Magic (a slot for its level in sorcery points, no action;
# points for a slot, a Bonus Action, on the Creating Spell Slots table). Until
# this pass both were catalogue text — data/effects/features.json had no entry,
# so the sheet listed them and the board never saw them.
#   godot --headless --path . -s tests/test_sorcerer.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Combat = preload("res://core/combat.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")

const INNATE := "sorcerer-innate-sorcery"
const FONT := "sorcerer-font-of-magic"
const POINTS := "sorcery-points"

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_authored()
	test_font_buttons_by_level()
	test_innate_sorcery()
	test_font_of_magic()
	test_made_slot_outlives_the_fight()
	test_innate_sorcery_comes_back_on_a_long_rest()
	test_autopilot_makes_a_slot()
	print("test_sorcerer: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _sorcerer(n: int) -> Character:
	var ch := Character.new()
	ch.id = "sorc"
	ch.cname = "Sorc"
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	for i in n:
		ch.add_level("sorcerer", -1)
	ch.prepared.assign(["fire-bolt", "burning-hands", "hold-person"])
	return ch

# A sorcerer at (2, 0) and one goblin at `foe_at`, every turn begun.
func _fight(ch: Character, foe_at := Vector2i(4, 0)) -> Array:
	var s = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
	var g = Encounter.spawn("goblin", 1.0, "foe", foe_at, 1)
	var cb := Combat.new(RNG.new(11), [s, g], Encounter.board_for("goblin-camp"))
	for c in cb.combatants:
		cb.begin_turn_for(c)
	return [cb, s, g]

func _verb(c, id: String) -> Dictionary:
	for v in c.verbs:
		if String(v["id"]) == id:
			return v
	return {}

func _spell(c, sid: String) -> Dictionary:
	for v in c.verbs:
		if String(v.get("spell", "")) == sid and not String(v["id"]).contains("@"):
			return v
	return {}

func test_authored() -> void:
	check(not Effects.feature(INNATE).is_empty(), "Innate Sorcery has a mechanic")
	check(not Effects.feature(FONT).is_empty(), "Font of Magic has a mechanic")
	check(Effects.validate().is_empty(), "features.json validates: %s" % str(Effects.validate()))
	check(Combat.OFFERABLE.has("font_of_magic"), "Font of Magic is a button kind")

# The Creating Spell Slots table is read at the sorcerer's level: a 1st-level
# slot from 2, 2nd from 3, 3rd from 5, 4th from 7, 5th from 9 — and a slot can
# only be burned at a level the sheet has slots of.
func test_font_buttons_by_level() -> void:
	var one = Adapter.to_combatant(_sorcerer(1), "party", Vector2i.ZERO)
	check(_verb(one, FONT + "@slot1").is_empty() and _verb(one, FONT + "-burn@1").is_empty(),
		"sorcerer 1 has no Font of Magic yet")
	check(not _verb(one, INNATE).is_empty(), "sorcerer 1 has Innate Sorcery")
	for pair in [[2, 1, 1], [3, 2, 2], [5, 3, 3], [7, 4, 4], [9, 5, 5]]:
		var c = Adapter.to_combatant(_sorcerer(pair[0]), "party", Vector2i.ZERO)
		var made := 0
		var burned := 0
		for l in range(1, 10):
			if not _verb(c, "%s@slot%d" % [FONT, l]).is_empty():
				made = l
			if not _verb(c, "%s-burn@%d" % [FONT, l]).is_empty():
				burned = l
		check(made == pair[1], "sorcerer %d makes slots up to %d (got %d)" % [pair[0], pair[1], made])
		check(burned == pair[2], "sorcerer %d burns slots up to %d (got %d)" % [pair[0], pair[2], burned])
	var nine = Adapter.to_combatant(_sorcerer(9), "party", Vector2i.ZERO)
	var costs := []
	for l in range(1, 6):
		costs.append(int(_verb(nine, "%s@slot%d" % [FONT, l])["pool_cost"]))
	check(costs == [2, 3, 5, 6, 7], "slot costs are the 2024 table (got %s)" % str(costs))
	check(String(_verb(nine, FONT + "@slot1")["cost"]) == "bonus", "making a slot is a Bonus Action")
	check(String(_verb(nine, FONT + "-burn@1")["cost"]) == "free", "burning a slot costs no action")

func test_innate_sorcery() -> void:
	var f := _fight(_sorcerer(5))
	var cb = f[0]
	var s = f[1]
	var hold := _spell(s, "hold-person")
	var base: int = Combat.spell_dc(s, hold)
	check(base == s.save_dc, "no buff, the sheet's DC (%d)" % base)
	var r: Dictionary = cb.perform(s, _verb(s, INNATE))
	check(not r.has("error"), "Innate Sorcery performs (%s)" % r.get("error", ""))
	check(s.has("innate-sorcery"), "and the sorcerer wears it")
	check(int(s.econ["bonus"]) == 0, "it cost the Bonus Action")
	check(s.pool_left(INNATE) == 1, "one of its two uses is spent")
	check(Combat.spell_dc(s, hold) == base + 1, "+1 to the spell save DC (%d)" % Combat.spell_dc(s, hold))
	var atk: Dictionary = {"kind": "attack", "save_dc": base}
	check(Combat.spell_dc(s, atk) == base, "...and only a spell's")
	check(not cb._offerable(s, _verb(s, INNATE)), "it cannot be stacked on itself")
	# The DC a cast rolls against is the buffed one, stamped at the cast.
	cb.begin_turn_for(s)
	var burn := _spell(s, "burning-hands")
	var before: int = cb.log.size()
	cb.perform(s, burn, Vector2i(1, 0))
	var said := "\n".join(cb.log.slice(before))
	check(said.contains("DC %d save" % (base + 1)), "Burning Hands is cast at DC %d: %s" % [base + 1, said])
	# Advantage on a spell attack: the same Fire Bolt against the same AC,
	# with and without the buff, over enough rolls to see the gap.
	var bolt := _spell(s, "fire-bolt")
	var g = f[2]
	var plain := _hits(cb, s, g, bolt, false)
	var sharp := _hits(cb, s, g, bolt, true)
	check(sharp > plain + 30, "Advantage lands more Fire Bolts (%d vs %d of 300)" % [sharp, plain])
	# A minute is ten rounds; past it the buff lapses on its own.
	s.statuses["innate-sorcery"] = {"spell_dc_bonus": 1, "spell_attack_adv": true,
		"until_tick": cb._tick() + 10 * Combat.TICK_STRIDE}
	cb.round_num += 10
	cb._expire_conditions(s)
	check(s.has("innate-sorcery"), "still up at the end of the tenth round")
	cb.round_num += 1
	cb._expire_conditions(s)
	check(not s.has("innate-sorcery"), "gone a round after that")

func _hits(cb, s, g, bolt: Dictionary, buffed: bool) -> int:
	s.statuses.erase("innate-sorcery")
	if buffed:
		s.statuses["innate-sorcery"] = {"spell_dc_bonus": 1, "spell_attack_adv": true}
	cb.rng = RNG.new(99)
	g.ac = 20
	var n := 0
	for i in 300:
		g.hp = 999
		g.max_hp = 999
		var r: Dictionary = cb._spell_hit(g, bolt, "1d10", 0, s)
		if r.get("hit", false):
			n += 1
	return n

func test_font_of_magic() -> void:
	var f := _fight(_sorcerer(5))
	var cb = f[0]
	var s = f[1]
	check(s.slots.slice(0, 3) == [4, 3, 2], "sorcerer 5 starts on 4/3/2")
	check(s.pool_left(POINTS) == 5, "and 5 sorcery points")
	check(not cb._offerable(s, _verb(s, FONT + "-burn@1")), "a full pool burns nothing: the points would be lost")
	var r: Dictionary = cb.perform(s, _verb(s, FONT + "@slot1"))
	check(not r.has("error"), "2 points make a 1st-level slot (%s)" % r.get("error", ""))
	check(s.slots[0] == 5 and s.pool_left(POINTS) == 3, "slot 5/3/2, points 3 (got %s, %d)" % [str(s.slots.slice(0, 3)), s.pool_left(POINTS)])
	check(int(s.econ["bonus"]) == 0, "it took the Bonus Action")
	check(not cb._offerable(s, _verb(s, FONT + "@slot1")), "so a second one waits for the next turn")
	check(cb._offerable(s, _verb(s, FONT + "-burn@2")), "burning a slot needs no action")
	r = cb.perform(s, _verb(s, FONT + "-burn@2"))
	check(not r.has("error") and s.slots[1] == 2 and s.pool_left(POINTS) == 5,
		"a 2nd-level slot burns into 2 points (slots %s, points %d)" % [str(s.slots.slice(0, 3)), s.pool_left(POINTS)])
	check(not cb._offerable(s, _verb(s, FONT + "-burn@1")), "full again: nothing more to burn into")
	cb.begin_turn_for(s)
	s.pools[POINTS]["cur"] = 4
	check(not cb._offerable(s, _verb(s, FONT + "@slot3")), "4 points do not buy a 3rd-level slot")
	s.pools[POINTS]["cur"] = 5
	check(cb._offerable(s, _verb(s, FONT + "@slot3")), "5 do")

# RAW: a slot you make vanishes when you finish a long rest — not when the
# fight ends. write_back carries it out as a negative slots_used entry.
func test_made_slot_outlives_the_fight() -> void:
	var ch := _sorcerer(5)
	var f := _fight(ch)
	var cb = f[0]
	var s = f[1]
	cb.perform(s, _verb(s, FONT + "@slot1"))
	Adapter.write_back(s, ch)
	check(int(ch.slots_used[0]) == -1, "the unspent made slot leaves as -1 used (got %s)" % str(ch.slots_used))
	check(Adapter.slots_left(ch)[0] == 5, "five 1st-level slots on the road")
	check(ch.pools[POINTS] == 3, "and 3 points")
	var again = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	check(again.slots[0] == 5, "the next fight starts with it")
	Adapter.rest(ch, "short-rest")
	check(Adapter.slots_left(ch)[0] == 5, "a short rest keeps it")
	Adapter.rest(ch, "long-rest")
	check(Adapter.slots_left(ch)[0] == 4, "a long rest takes it back to the sheet's 4")
	check(int(ch.pools[POINTS]) == 5, "and refills the points")

func test_innate_sorcery_comes_back_on_a_long_rest() -> void:
	var ch := _sorcerer(3)
	var f := _fight(ch)
	var cb = f[0]
	var s = f[1]
	check(String(s.pools[INNATE]["regen"]) == "long-rest", "two uses per LONG rest (got %s)" % s.pools[INNATE]["regen"])
	cb.perform(s, _verb(s, INNATE))
	Adapter.write_back(s, ch)
	check(int(ch.pools[INNATE]) == 1, "one use left after the fight")
	Adapter.rest(ch, "short-rest")
	check(int(ch.pools[INNATE]) == 1, "a short rest does not bring it back")
	Adapter.rest(ch, "long-rest")
	check(int(ch.pools[INNATE]) == 2, "a long rest does")

func test_autopilot_makes_a_slot() -> void:
	var f := _fight(_sorcerer(5))
	var cb = f[0]
	var s = f[1]
	s.slots.assign([0, 0, 0, 0, 0, 0, 0, 0, 0])
	AI._font_up(cb, s)
	check(s.slots[2] == 1 and s.pool_left(POINTS) == 0,
		"out of slots, the autopilot spends 5 points on a 3rd-level one (slots %s, points %d)" % [str(s.slots.slice(0, 3)), s.pool_left(POINTS)])
	var g := _fight(_sorcerer(5))
	var s2 = g[1]
	AI._font_up(g[0], s2)
	check(s2.pool_left(POINTS) == 5, "with slots in hand it leaves the points alone")

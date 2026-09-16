# The reaction layer: combat.gd's trigger dispatcher, and Counterspell as the
# spell that exercises all of it — it is the only reaction that has to reach
# into somebody else's turn, spend a slot, and stop a spell that was already
# under way.
#   godot --headless --path . -s tests/test_reactions.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Character = preload("res://core/character.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Effects = preload("res://core/rules/effects.gd")
const Catalog = preload("res://core/rules/catalog.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_the_data_declares_a_trigger_that_fires()
	test_a_reaction_is_never_a_button()
	test_counterspell_unravels_the_spell()
	test_a_made_save_carries_the_spell_through()
	test_the_dc_is_ten_plus_the_spells_level()
	test_out_of_range_answers_nothing()
	test_a_hidden_caster_cannot_be_answered()
	test_an_ally_is_never_counterspelled()
	test_a_cantrip_is_not_worth_a_slot()
	test_a_spent_reaction_answers_nothing()
	test_no_slot_no_counter()
	test_the_incapacitated_hold_no_reaction()
	test_counterspell_can_itself_be_counterspelled()
	test_the_dispatcher_still_carries_the_feature_reactions()
	test_a_blow_is_answered_after_it_lands()
	print("test_reactions: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------

# A level-5 wizard with exactly `prepared` castable: two 3rd-level slots, which
# is one Counterspell plus one of something else. Nothing here relies on the
# spellbook the class grants, so the verb list is the list below and no other.
func _mage(id: String, team: String, p: Vector2i, prepared: Array):
	var ch = Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 10, "dex": 14, "con": 14, "int": 16, "wis": 12, "cha": 10}
	for i in 5:
		ch.add_level("wizard", -1)
	ch.equipped = ["quarterstaff"] as Array[String]
	var prep: Array[String] = []
	for sid in prepared:
		prep.append(String(sid))
	ch.prepared = prep
	return Adapter.to_combatant(ch, team, p)

# One caster on each side, ten hexes apart at most — inside Counterspell's 60 ft.
# `atk` casts, `def` answers. Seeds are pinned but nothing below leans on a roll:
# a save is forced either way by handing the caster an absurd CON bonus.
func _duel(atk_spells := ["guiding-bolt"], def_spells := ["counterspell"], seed := 11) -> Array:
	var atk = _mage("mage", "foe", Vector2i(4, 1), atk_spells)
	var def = _mage("sel", "party", Vector2i(6, 1), def_spells)
	var cb = Combat.new(RNG.new(seed), [atk, def], Encounter.board())
	cb.begin_turn_for(atk)
	cb.begin_turn_for(def)
	return [cb, atk, def]

const ALWAYS_FAILS := -100   # a CON save bonus no DC can be met with
const ALWAYS_MAKES := 100

func _log_has(cb, needle: String) -> bool:
	for line in cb.log:
		if needle in line:
			return true
	return false

# --- the data -----------------------------------------------------------

func test_the_data_declares_a_trigger_that_fires() -> void:
	var m := Effects.spell("counterspell")
	check(not m.is_empty(), "Counterspell is combat-castable — a reaction block is a mechanic")
	check(m["cost"] == "reaction", "and it costs a reaction")
	check(m["reaction"]["trigger"] == "spell_cast", "hung off the spell_cast trigger")
	check(m["reaction"]["trigger"] in Effects.REACTION_TRIGGERS,
		"which is a trigger combat.gd actually fires")
	check(Effects.validate().is_empty(),
		"no authored reaction names a trigger nothing fires: %s" % [Effects.validate()])

# --- the shape of a reaction --------------------------------------------

func test_a_reaction_is_never_a_button() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var def = d[2]
	check(not def.verb("counterspell").is_empty(), "the wizard knows Counterspell")
	check(not cb.all_verbs(def).any(func(v): return v["id"] == "counterspell"),
		"it is not a slot on the action bar")
	check(not cb.available(def).any(func(v): return v["id"] == "counterspell"),
		"and never a button — it fires on its trigger (combat-design.md §2)")
	check(cb.reaction_verb(def, "spell_cast")["spell"] == "counterspell",
		"the dispatcher finds it by trigger instead")
	check(cb.reaction_verb(def, "hit_by_attack").is_empty(),
		"and only for the trigger it answers")
	var forms: Array = def.verbs.filter(func(v): return v.get("spell", "") == "counterspell")
	check(forms.size() == 1,
		"one form only — upcasting a counter buys nothing, so there is no ★4 variant")

# --- counterspell ------------------------------------------------------

func test_counterspell_unravels_the_spell() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	var hp_before: int = def.hp
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(res.get("countered", false), "the spell is countered")
	check(res.get("by") == def, "and the log knows who answered")
	check(def.hp == hp_before, "nothing of it reaches the target")
	check(atk.slots[0] == 4, "the countered caster keeps the slot")
	check(atk.econ["action"] == 0, "the action it was cast with is spent all the same")
	check(def.econ["reaction"] == 0, "answering cost the reaction")
	check(def.slots[2] == 1, "and one of the two 3rd-level slots")
	check(_log_has(cb, "answers Guiding Bolt with Counterspell"), "the answer is in the log")
	check(_log_has(cb, "unravels"), "and so is what it did")

func test_a_made_save_carries_the_spell_through() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_MAKES
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "the caster holds the spell together")
	check(atk.slots[0] == 3, "so the slot is spent, as any cast would spend it")
	check(def.econ["reaction"] == 0 and def.slots[2] == 1,
		"a failed answer still costs the answerer its reaction and its slot")
	check(_log_has(cb, "holds Guiding Bolt together"), "the log says the counter missed")

func test_the_dc_is_ten_plus_the_spells_level() -> void:
	# The DC is read off the spell being stopped, so a bigger spell is a bigger
	# target: Counterspell's own description, "(DC 10 + the spell's level)".
	# ALWAYS_MAKES keeps the roll out of it — only the printed DC is asserted.
	for pair in [["guiding-bolt", 11], ["hold-person", 12], ["guiding-bolt@3", 13]]:
		var d := _duel([String(pair[0]).split("@")[0]])
		var cb: Combat = d[0]
		var atk = d[1]
		atk.saves["con"] = ALWAYS_MAKES
		cb.perform(atk, atk.verb(String(pair[0])), d[2])
		check(_log_has(cb, "(DC %d)" % int(pair[1])),
			"%s is countered at DC %d" % [pair[0], int(pair[1])])

func test_out_of_range_answers_nothing() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	def.pos = Vector2i(16, 1)   # 12 hexes — past Counterspell's 60 ft
	check(cb.reactors_for("spell_cast", {"caster": atk, "level": 1}).is_empty(),
		"nobody in range holds an answer")
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "so the spell goes off")
	check(def.econ["reaction"] == 1, "and the reaction is still there to spend")

func test_a_hidden_caster_cannot_be_answered() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	atk.statuses["hidden"] = true
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "you cannot counter what you cannot see")
	check(def.econ["reaction"] == 1, "the reaction is not spent on a guess")

func test_an_ally_is_never_counterspelled() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	atk.team = def.team
	var res := cb.perform(atk, atk.verb("guiding-bolt"), atk)
	check(not res.get("countered", false), "your own side's spell is not your business")
	check(def.econ["reaction"] == 1, "no reaction spent on it")

func test_a_cantrip_is_not_worth_a_slot() -> void:
	var d := _duel(["fire-bolt"])
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	var res := cb.perform(atk, atk.verb("fire-bolt"), def)
	check(not res.get("countered", false), "a 3rd-level slot does not swat a cantrip")
	check(def.econ["reaction"] == 1 and def.slots[2] == 2, "min_level kept both intact")

func test_a_spent_reaction_answers_nothing() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	def.econ["reaction"] = 0
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "one reaction between your turns, and it is gone")
	check(def.slots[2] == 2, "no slot spent on a counter that could not be made")

func test_no_slot_no_counter() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	def.slots[2] = 0
	check(cb.reaction_verb(def, "spell_cast").is_empty(), "no slot, no answer to hold")
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "so the spell goes off")
	check(def.econ["reaction"] == 1, "and the reaction is not spent on nothing")

func test_the_incapacitated_hold_no_reaction() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	def.statuses["stunned"] = true   # conditions.json: no_action, no_bonus, no_reaction
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "a stunned caster counters nothing")
	check(def.slots[2] == 2, "and spends nothing trying")

func test_counterspell_can_itself_be_counterspelled() -> void:
	# The whole reason the dispatcher nests: A casts, B answers, A answers the
	# answer. B fails the save A's counter forces, so B's Counterspell unravels
	# and A's spell — never having rolled a save of its own — goes off.
	var d := _duel(["guiding-bolt", "counterspell"], ["counterspell"])
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS   # never rolled: A's spell is never reached
	def.saves["con"] = ALWAYS_FAILS
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(not res.get("countered", false), "the counter to the counter saves the spell")
	check(atk.slots[0] == 3, "which then spends its own slot like any cast")
	check(atk.econ["reaction"] == 0 and atk.slots[2] == 1, "A paid a reaction and a slot")
	check(def.econ["reaction"] == 0, "B paid its reaction")
	check(def.slots[2] == 2, "but keeps the slot its countered Counterspell would have cost")
	check(cb._reaction_depth == 0, "the nesting unwinds")

# --- the triggers the dispatcher already carried -------------------------

func test_the_dispatcher_still_carries_the_feature_reactions() -> void:
	var ch = Character.new()
	ch.id = "sly"
	ch.cname = "Sly"
	ch.species_id = "human"
	ch.background_id = "criminal"
	ch.base_abilities = {"str": 10, "dex": 16, "con": 12, "int": 12, "wis": 10, "cha": 12}
	for i in 5:
		ch.add_level("rogue", -1)
	ch.equipped = ["dagger", "studded-leather"] as Array[String]
	var sly = Adapter.to_combatant(ch, "party", Vector2i(4, 1))
	var grull = Adapter.from_monster(Catalog.all("monsters.json")[0], "foe", Vector2i(5, 1))
	var cb = Combat.new(RNG.new(3), [sly, grull], Encounter.board())
	cb.begin_turn_for(grull)
	check(cb.reaction_verb(sly, "hit_by_attack")["id"] == "rogue-uncanny-dodge",
		"a feature reaction goes through the same lookup a spell does")
	check(cb.reactors_for("hit_by_attack", {"attacker": grull, "target": sly}).size() == 1,
		"and the same eligibility pass")
	check(cb.reactors_for("hit_by_attack", {"attacker": grull, "target": grull}).is_empty(),
		"a blow to somebody else is not yours to halve")
	var out := cb.fire_reactions("hit_by_attack",
		{"attacker": grull, "target": sly, "damage": 11})
	check(out["damage"] == 5, "Uncanny Dodge halves the blow")
	check(sly.econ["reaction"] == 0, "and spends the reaction doing it")

func test_a_blow_is_answered_after_it_lands() -> void:
	# Hellish Rebuke is the other half of a hit: not damage reduction but an
	# answer, so it fires on damaged_by_attack, once the damage is in.
	var d := _duel(["guiding-bolt"], ["hellish-rebuke"])
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.pos = Vector2i(5, 1)
	atk.atk_bonus = 100        # this test is about the reaction, not the d20
	atk.damage = "1d4"
	def.saves["dex"] = ALWAYS_FAILS
	var hp_before: int = atk.hp
	check(cb.reaction_verb(def, "damaged_by_attack")["spell"] == "hellish-rebuke",
		"the rebuke hangs off the after-the-damage trigger")
	var res := cb.resolve_attack(atk, def)
	check(res["hit"], "the swing lands")
	check(def.econ["reaction"] == 0, "which the rebuke answers with its reaction")
	check(def.slots[0] == 3, "spending a 1st-level slot")
	check(atk.hp < hp_before, "and the attacker burns for it")

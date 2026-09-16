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
	test_nobody_is_asked_unless_a_decider_is_installed()
	test_only_a_reaction_that_costs_something_asks()
	test_holding_the_reaction_spends_nothing()
	test_saying_yes_spends_it()
	test_an_answer_is_good_for_one_trigger_only()
	test_the_offer_predicts_what_the_action_will_fire()
	test_the_foe_side_is_never_asked()
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

# --- being asked first --------------------------------------------------
#
# A reaction that spends a slot is the player's call, so combat.gd can be given
# a decider and will not spend one without an answer. It still cannot stop to
# ask from inside the resolver (GDScript cannot block, combat-design.md §2), so
# the question is put one step earlier — offer_reactions(), the only suspending
# function in the engine — and read back synchronously when the trigger fires.

# Records every question it is asked and answers them all the same way.
class Decider:
	extends RefCounted
	var answer: bool
	var asked: Array = []
	func _init(a: bool) -> void:
		answer = a
	func decide(reactor, v: Dictionary, trigger: String, _ctx: Dictionary) -> bool:
		asked.append("%s:%s:%s" % [reactor.id, v["id"], trigger])
		return answer

func test_nobody_is_asked_unless_a_decider_is_installed() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	check(cb.pending_reactions(atk, atk.verb("guiding-bolt"), def).is_empty(),
		"with no decider there is nobody to ask")
	cb.offer_reactions(atk, atk.verb("guiding-bolt"), def)   # returns without suspending
	check(cb.reaction_intent.is_empty(), "so no answer is recorded")
	var res := cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(res.get("countered", false),
		"and the reaction fires by itself, exactly as it did before any of this")

func test_only_a_reaction_that_costs_something_asks() -> void:
	# Uncanny Dodge spends no slot and no pool, so it is never a question —
	# there is one sensible answer to "halve this for free" and it is yes. The
	# same trigger with a slot on it IS a question, which is what makes the test
	# about the cost rather than about the trigger.
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	var dec := Decider.new(false)
	cb.reaction_decider = dec.decide
	var free_verb := {"id": "rogue-uncanny-dodge", "kind": "reaction", "cost": "reaction",
		"label": "Uncanny Dodge", "trigger": "hit_by_attack", "halve_damage": true}
	check(not cb.reaction_costs_resource(free_verb), "a feature reaction costs no resource")
	check(cb.reaction_costs_resource(def.verb("counterspell")), "Counterspell costs a slot")
	def.verbs.append(free_verb)
	check(cb.reactors_for("hit_by_attack", {"attacker": atk, "target": def}).size() == 1,
		"the free reaction is eligible for this swing")
	cb.offer_reactions(atk, cb.attack_verb(), def)
	check(dec.asked.is_empty(), "eligible, and still never offered — it costs nothing")
	var out := cb.fire_reactions("hit_by_attack", {"attacker": atk, "target": def, "damage": 10})
	check(out["damage"] == 5 and def.econ["reaction"] == 0,
		"and it fires on its own, unasked")

	# Same trigger, same moment, but a slot behind it: now it is asked.
	var d2 := _duel()
	var cb2: Combat = d2[0]
	var dec2 := Decider.new(false)
	cb2.reaction_decider = dec2.decide
	var paid := {"id": "shield", "kind": "spell", "cost": "reaction", "label": "Shield",
		"trigger": "hit_by_attack", "slot_level": 1, "halve_damage": true}
	d2[2].verbs.append(paid)
	cb2.offer_reactions(d2[1], cb2.attack_verb(), d2[2])
	check(dec2.asked == ["sel:shield:hit_by_attack"], "a slot on the same trigger is a question")

func test_holding_the_reaction_spends_nothing() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	var dec := Decider.new(false)
	cb.reaction_decider = dec.decide
	var bolt: Dictionary = atk.verb("guiding-bolt")
	cb.offer_reactions(atk, bolt, def)
	check(dec.asked == ["sel:counterspell:spell_cast"], "the answerer is asked, once")
	var res := cb.perform(atk, bolt, def)
	check(not res.get("countered", false), "a held reaction stops nothing")
	check(def.econ["reaction"] == 1 and def.slots[2] == 2, "and costs neither reaction nor slot")
	check(atk.slots[0] == 3, "the spell went off, so its own slot is spent")
	check(_log_has(cb, "holds their reaction"), "the log says the choice was made")

func test_saying_yes_spends_it() -> void:
	var d := _duel()
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	var dec := Decider.new(true)
	cb.reaction_decider = dec.decide
	var bolt: Dictionary = atk.verb("guiding-bolt")
	cb.offer_reactions(atk, bolt, def)
	var res := cb.perform(atk, bolt, def)
	check(res.get("countered", false), "a yes counters the spell")
	check(def.econ["reaction"] == 0 and def.slots[2] == 1, "paying the reaction and the slot")
	check(atk.slots[0] == 4, "and the countered caster keeps its own")

func test_an_answer_is_good_for_one_trigger_only() -> void:
	# A yes is given to a question about one spell. The next cast is a new
	# question, and if nobody asked it the engine must not reuse the old answer.
	var d := _duel(["guiding-bolt"], ["counterspell"])
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.saves["con"] = ALWAYS_FAILS
	var dec := Decider.new(true)
	cb.reaction_decider = dec.decide
	cb.offer_reactions(atk, atk.verb("guiding-bolt"), def)
	check(cb.reaction_intent.size() == 1, "the answer is on the books")
	cb.perform(atk, atk.verb("guiding-bolt"), def)
	check(cb.reaction_intent.is_empty(), "and consumed by the trigger it was given for")
	cb.begin_turn_for(def)
	cb.offer_reactions(atk, atk.verb("guiding-bolt"), def)
	cb.begin_turn_for(def)
	check(cb.reaction_intent.is_empty(), "an answer to something that never happened is dropped")

func test_the_offer_predicts_what_the_action_will_fire() -> void:
	# The whole design rests on this: the trigger predicted before the action is
	# the trigger the resolver actually fires, or the answer belongs to the
	# wrong question.
	var d := _duel(["guiding-bolt"], ["hellish-rebuke"])
	var cb: Combat = d[0]
	var atk = d[1]
	var def = d[2]
	atk.pos = Vector2i(5, 1)
	var dec := Decider.new(false)
	cb.reaction_decider = dec.decide
	check(cb.reaction_triggers_for(atk, atk.verb("guiding-bolt"), def)[0][0] == "spell_cast",
		"a cast is predicted as spell_cast")
	var swing: Array = cb.reaction_triggers_for(atk, cb.attack_verb(), def)
	# T94 put a third moment in front of the other two: "would_be_hit" fires once
	# the roll is known to land and before it does, which is where Parry answers.
	check(swing.map(func(t): return t[0]) == ["would_be_hit", "hit_by_attack", "damaged_by_attack"],
		"a swing is predicted as all three of its moments, in the order they fire")
	check(cb.reaction_triggers_for(atk, cb._basic("dodge"), null).is_empty(),
		"and Dodge fires nothing at all")
	# The swing: asked before the d20, so a miss costs the answerer nothing.
	cb.offer_reactions(atk, cb.attack_verb(), def)
	check(dec.asked == ["sel:hellish-rebuke:damaged_by_attack"], "the rebuke is the question")
	atk.atk_bonus = 100
	atk.damage = "1d4"
	var hp_before: int = atk.hp
	cb.resolve_attack(atk, def)
	check(def.econ["reaction"] == 1 and def.slots[0] == 4, "held: nothing spent")
	check(atk.hp == hp_before, "and the attacker takes nothing back")

func test_the_foe_side_is_never_asked() -> void:
	# The decider speaks for one side. A monster's reaction is the engine's to
	# resolve, and a fight must not stop to ask the player about it.
	var d := _duel(["guiding-bolt"], ["counterspell"])
	var cb: Combat = d[0]
	var dec := Decider.new(false)
	cb.reaction_decider = dec.decide
	cb.reaction_decider_team = "foe"          # the answerer is now on the other side
	cb.offer_reactions(d[1], d[1].verb("guiding-bolt"), d[2])
	check(dec.asked.is_empty(), "a party reaction is not this decider's to answer")
	check(not cb.asks_first(d[2], d[2].verb("counterspell")), "asks_first agrees")
	cb.reaction_decider_team = "party"
	check(cb.asks_first(d[2], d[2].verb("counterspell")), "and the other way round")

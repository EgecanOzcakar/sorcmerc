# T-summon: the two subclass features that put a second token on the board —
# Beast Master's Primal Companion and Trickery Domain's Invoke Duplicity — and
# the initiative rule they both ride on.
#
# The design call this test pins is that a summon ROLLS ITS OWN INITIATIVE
# rather than acting on its owner's count. Everything in the first section is
# about the one thing that can go wrong when it does: `order` is indexed by
# `turn_idx`, so a creature landing at or above the live index slides the
# current actor down a slot, and the fight quietly continues as somebody else.
#   godot --headless --path . -s tests/test_summons.gd
extends SceneTree

const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Effects = preload("res://core/rules/effects.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Leveling = preload("res://core/leveling.gd")
const Dice = preload("res://core/dice.gd")
const Hex = preload("res://core/hex.gd")
const AI = preload("res://core/ai.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_the_vocabulary_is_sound()
	test_it_rolls_its_own_initiative()
	test_the_live_turn_survives_the_arrival()
	test_primal_companion()
	test_the_companion_grows_with_the_ranger()
	test_invoke_duplicity()
	test_the_double_is_not_a_creature()
	test_the_double_fades()
	test_the_double_does_not_prop_up_a_lost_fight()
	test_spiritual_weapon()
	await test_the_ai_copes_with_it()
	print("test_summons: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- building -------------------------------------------------------------
#
# The creator's own choice model, the way tests/test_class_abilities.gd drives it.
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
	ch.id = "sum-%s-%s-%d" % [cid, sid, lvl]
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
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	return ch

# A hero of `cid`/`sid` at `lvl`, a friend beside them, and `foes` goblins.
func fight(cid: String, sid: String, lvl: int, seed := 7, foes := [Vector2i(4, 0)]) -> Array:
	var hero = Adapter.to_combatant(build(cid, sid, lvl), "party", Vector2i(2, 0))
	var friend = Adapter.to_combatant(Presets.vera(), "party", Vector2i(2, 1))
	var all: Array = [hero, friend]
	var n := 0
	for g in foes:
		n += 1
		all.append(Encounter.spawn("goblin", 1.0, "foe", g, n))
	var cb := Combat.new(RNG.new(seed), all, Encounter.board_for("goblin-camp"))
	for c in cb.combatants:
		cb.begin_turn_for(c)
	return [cb, hero, friend]

func verb(c, id: String) -> Dictionary:
	for v in c.verbs:
		if String(v["id"]) == id:
			return v
	return {}

# --- the vocabulary -------------------------------------------------------

func test_the_vocabulary_is_sound() -> void:
	var errs := Effects.validate()
	check(errs.is_empty(), "data/effects/*.json validates: %s" % str(errs))
	check("summon" in Effects.KINDS and "summon" in Combat.OFFERABLE,
		"`summon` is a known kind and reaches the action bar")
	# The stat block a feature names has to exist, which is what the new
	# validate() rule above is for — assert it from the other side too.
	check(not Catalog.monster("trickery-duplicate").is_empty(), "the double has a stat block")
	check(not Catalog.monster("dire-wolf").is_empty(), "the companion has a stat block")

# --- initiative -----------------------------------------------------------

func test_it_rolls_its_own_initiative() -> void:
	var f := fight("ranger", "beastmaster", 8)
	var cb = f[0]; var hero = f[1]
	var before: int = cb.order.size()
	var beast = cb.summon(hero, {"summon": {"id": "dire-wolf"}})
	check(beast != null, "the beast stands up")
	if beast == null:
		return
	check(cb.order.size() == before + 1 and cb.order.count(beast) == 1,
		"it is in the order exactly once")
	check(beast.init_roll >= 1 + beast.init_mod and beast.init_roll <= 20 + beast.init_mod,
		"it rolled a d20 of its own (%d, mod %+d)" % [beast.init_roll, beast.init_mod])
	# The order is still sorted, which is the only thing that makes an index
	# into it mean "who goes next".
	var sorted := true
	for i in range(cb.order.size() - 1):
		if cb._init_before(cb.order[i + 1], cb.order[i]):
			sorted = false
	check(sorted, "the order is still in initiative order")
	# Not pinned to the caster's slot any more — that was the old rule.
	check(cb.order.find(beast) != cb.order.find(hero) + 1 or beast.init_roll <= hero.init_roll,
		"where it lands is its roll's business, not its owner's")

# Thirty seeds, because the bug this guards against only shows on the seeds
# where the summon rolls high enough to land at or above the live index.
func test_the_live_turn_survives_the_arrival() -> void:
	var above := 0
	var below := 0
	for s in range(30):
		var f := fight("ranger", "beastmaster", 8, s, [Vector2i(4, 0), Vector2i(5, 1)])
		var cb = f[0]
		cb.turn_idx = 2 if cb.order.size() > 3 else 0
		var live = cb.current()
		var beast = cb.summon(live, {"summon": {"id": "dire-wolf"}})
		if beast == null:
			continue
		var at: int = cb.order.find(beast)
		if at <= cb.order.find(live):
			above += 1
		else:
			below += 1
		check(cb.current() == live,
			"seed %d: the turn is still %s after the beast arrives at slot %d" % [s, live.cname, at])
	check(above > 0 and below > 0,
		"both sides of the live index were exercised (%d above, %d below)" % [above, below])

# --- Primal Companion -----------------------------------------------------

func test_primal_companion() -> void:
	var f := fight("ranger", "beastmaster", 8)
	var cb = f[0]; var ranger = f[1]
	var v := verb(ranger, "beastmaster-primal-companion")
	check(not v.is_empty(), "the Beast Master carries the button")
	if v.is_empty():
		return
	check(v["kind"] == "summon" and v["cost"] == "action" and v["targeting"] == "self",
		"it is an action, aimed at nothing")
	check(int(ranger.pool_left("beastmaster-primal-companion")) == ranger.sheet.proficiency_bonus,
		"its uses are the ranger's proficiency bonus (%d)" % ranger.pool_left("beastmaster-primal-companion"))
	check(cb.available(ranger).any(func(x): return x["id"] == v["id"]), "and it is offered")

	var n0: int = cb.combatants.size()
	var r: Dictionary = cb.perform(ranger, v)
	check(r.has("summoned") and cb.combatants.size() == n0 + 1, "pressing it stands a beast up (%s)" % str(r))
	if not r.has("summoned"):
		return
	var beast = r["summoned"]
	check(beast.team == "party" and beast.cname.begins_with(ranger.cname.get_slice(" ", 0)),
		"on the ranger's side and hers by name (%s)" % beast.cname)
	check(not cb.all_verbs(beast).filter(func(x): return x["kind"] == "attack").is_empty(),
		"and it can swing")

	# One beast, not a wall of them: the button greys out while it stands and
	# comes back when it falls.
	ranger.econ["action"] = 1
	check(not cb.available(ranger).any(func(x): return x["id"] == v["id"]),
		"a second press is refused while the first beast is up")
	beast.hp = 0
	beast.statuses["dead"] = true
	check(cb.available(ranger).any(func(x): return x["id"] == v["id"]),
		"...and offered again once it falls")

func test_the_companion_grows_with_the_ranger() -> void:
	var small = _companion_at(4)
	var big = _companion_at(8)
	check(small != null and big != null, "a beast at both levels")
	if small == null or big == null:
		return
	check(big.max_hp > small.max_hp, "the level-8 beast is tougher (%d hp vs %d)" % [big.max_hp, small.max_hp])
	check(big.atk_bonus >= small.atk_bonus, "and hits at least as well (%+d vs %+d)"
		% [big.atk_bonus, small.atk_bonus])
	# Scaled off the block, not replaced by a different one: the same creature
	# grows, which is what keeps one bestiary entry serving every level.
	check(big.src_id == small.src_id, "it is the same creature at both levels (%s)" % big.src_id)

func _companion_at(lvl: int):
	var f := fight("ranger", "beastmaster", lvl)
	var cb = f[0]; var ranger = f[1]
	var v := verb(ranger, "beastmaster-primal-companion")
	if v.is_empty():
		return null
	var r: Dictionary = cb.perform(ranger, v)
	return r.get("summoned")

# --- Invoke Duplicity -----------------------------------------------------

func test_invoke_duplicity() -> void:
	var f := fight("cleric", "trickerydomain", 8)
	var cb = f[0]; var cleric = f[1]
	var v := verb(cleric, "trickerydomain-invoke-duplicity")
	check(not v.is_empty(), "the Trickery cleric carries the button")
	if v.is_empty():
		return
	check(v["cost"] == "bonus" and String(v.get("pool", "")) == "channel-divinity",
		"a bonus action out of Channel Divinity")
	var before: int = cleric.pool_left("channel-divinity")
	check(before > 0, "with uses to spend (%d)" % before)
	var r: Dictionary = cb.perform(cleric, v)
	check(r.has("summoned"), "the double appears (%s)" % str(r))
	check(cleric.pool_left("channel-divinity") == before - 1,
		"and it came out of the same pool the cleric's other Channel Divinity spends")
	if not r.has("summoned"):
		return
	var dbl = r["summoned"]
	check(dbl.has("illusion"), "it is marked as an illusion")
	check(Hex.distance(dbl.pos, cleric.pos) <= 3, "standing near the cleric")

	# The point of it: a foe beside the double is attacked at Advantage.
	var gob = cb.combatants.filter(func(c): return c.team == "foe")[0]
	var plain: int = cb._attack_mode(cleric, gob)
	dbl.pos = gob.pos + Vector2i(1, 0)
	var flanked: int = cb._attack_mode(cleric, gob)
	check(plain != Dice.ADV and flanked == Dice.ADV,
		"Advantage while the double is beside the goblin (%d -> %d)" % [plain, flanked])
	# Only while it lives, and only next to it.
	dbl.pos = gob.pos + Vector2i(4, 0)
	check(cb._attack_mode(cleric, gob) != Dice.ADV, "...and not from across the board")

func test_the_double_is_not_a_creature() -> void:
	var f := fight("cleric", "trickerydomain", 8)
	var cb = f[0]; var cleric = f[1]
	var r: Dictionary = cb.perform(cleric, verb(cleric, "trickerydomain-invoke-duplicity"))
	if not r.has("summoned"):
		check(false, "the double appears")
		return
	var dbl = r["summoned"]
	var gob = cb.combatants.filter(func(c): return c.team == "foe")[0]
	gob.pos = dbl.pos + Vector2i(1, 0)
	cb.begin_turn_for(gob)
	check(not cb.legal_target(gob, cb.attack_verb(), dbl),
		"nothing swings at it, even from reach")
	check(not cb.available(gob).any(func(x): return x["kind"] == "attack" \
		and cb.legal_target(gob, x, dbl)), "...and it is on nobody's target list")
	# It is a decoy, not a second fighter.
	cb.begin_turn_for(dbl)
	check(not cb.available(dbl).any(func(x): return x["kind"] in ["attack", "offhand_attack", "spell"]),
		"and it does not swing back")
	check(cb.available(dbl).any(func(x): return x["id"] == "dodge"),
		"...though it still has a turn to take")

func test_the_double_fades() -> void:
	var f := fight("cleric", "trickerydomain", 8)
	var cb = f[0]; var cleric = f[1]
	var r: Dictionary = cb.perform(cleric, verb(cleric, "trickerydomain-invoke-duplicity"))
	if not r.has("summoned"):
		check(false, "the double appears")
		return
	var dbl = r["summoned"]
	check(not dbl.is_dead(), "it is up on the round it arrives")
	cb.round_num += 9
	cb.begin_turn_for(dbl)
	check(not dbl.is_dead(), "still up nine rounds in")
	cb.round_num += 2
	cb.begin_turn_for(dbl)
	check(dbl.is_dead() and dbl in cb.order,
		"gone after its minute — a corpse in the order, like any faded summon")

# The double cannot be attacked, so anything that treats "somebody on this side
# is still up" as "the fight goes on" would run to MAX_ROUNDS with nothing on
# the board able to end it.
func test_the_double_does_not_prop_up_a_lost_fight() -> void:
	var f := fight("cleric", "trickerydomain", 8)
	var cb = f[0]; var cleric = f[1]; var friend = f[2]
	var r: Dictionary = cb.perform(cleric, verb(cleric, "trickerydomain-invoke-duplicity"))
	if not r.has("summoned"):
		check(false, "the double appears")
		return
	var dbl = r["summoned"]
	for c in [cleric, friend]:
		c.hp = 0
		c.statuses["dead"] = true
	check(not dbl.is_dead(), "the double is the only thing on its side still up")
	check(cb.is_over() and cb.outcome() == "Defeat",
		"...and the fight is lost anyway (%s)" % cb.outcome())

# A foe walking past the double must not be swung at by it, and the AI must not
# jam on a token it can see and cannot touch.
func test_the_ai_copes_with_it() -> void:
	var f := fight("cleric", "trickerydomain", 8, 11, [Vector2i(4, 0), Vector2i(4, 1)])
	var cb = f[0]; var cleric = f[1]
	var r: Dictionary = cb.perform(cleric, verb(cleric, "trickerydomain-invoke-duplicity"))
	if not r.has("summoned"):
		check(false, "the double appears")
		return
	var dbl = r["summoned"]
	var foes: Array = cb.combatants.filter(func(c): return c.team == "foe")
	var walker = foes[0]
	dbl.pos = walker.pos + Vector2i(1, 0)
	cb.begin_turn_for(walker)
	check(cb._provocations(walker, walker.pos + Vector2i(-1, 0)).filter(
		func(p): return p[0] == dbl).is_empty(), "the double readies no opportunity attack")
	# And a whole AI turn against a board whose nearest party token is the
	# double resolves rather than spinning.
	for c in cb.combatants:
		if c.team == "party" and c != dbl:
			c.pos = Vector2i(0, 2)
	var log0: int = cb.log.size()
	await AI.take_turn(cb, foes[1])
	check(cb.log.size() >= log0, "the AI takes its turn with an untouchable token in front of it")
	check(not dbl.is_dead(), "...and the double is still standing")
	# Refused at the choke point too, whoever asks and however they got there.
	check(cb.resolve_attack(foes[1], dbl).has("error"),
		"a swing aimed straight at it is refused")


# --- issue #123: Spiritual Weapon -----------------------------------------
#
# The reporter asked whether the cleric's Spiritual Weapon makes a minion the
# player drives. It did not: it was modelled as a one-shot melee spell attack
# at 60 ft, costing an Action. The 2024 spell is a weapon that keeps standing
# there and swings where you send it, which in this engine is a summon on the
# caster's team — and a summon on the party's team is driven from the action
# bar like any hero (scenes/main.gd dispatches on team).
#
# It is also the first summon in the game that concentration does not hold, so
# the other half of combat.summon()'s clock — `rounds` — had to start reaching
# the verb at all.
func test_spiritual_weapon() -> void:
	var ilsa = Presets.ilsa(8)
	if not "spiritual-weapon" in ilsa.prepared:
		ilsa.prepared.append("spiritual-weapon")
	var caster = Adapter.to_combatant(ilsa, "party", Vector2i(2, 0))
	var foe = Encounter.spawn("goblin", 1.0, "foe", Vector2i(3, 0), 1)
	var cb := Combat.new(RNG.new(7), [caster, foe], Encounter.board_for("goblin-camp"))
	for c in cb.combatants:
		cb.begin_turn_for(c)
	cb.turn_idx = cb.order.find(caster)

	var tiers: Array = cb.available(caster).filter(
		func(v): return String(v.get("spell", "")) == "spiritual-weapon")
	check(tiers.size() == 1,
		"one entry on the bar, not a tier per slot — a bigger slot calls the same weapon (%d)"
		% tiers.size())
	if tiers.is_empty():
		return
	var v: Dictionary = tiers[0]
	check(String(v.get("cost", "")) == "bonus", "it costs a Bonus Action, as the spell says")
	check(not bool(v.get("concentration", false)), "2024 dropped its concentration")
	check(int(v.get("rounds", 0)) == 10, "and its minute reaches the verb as ten rounds")

	var w = cb.perform(caster, v, null).get("summoned")
	check(w != null, "casting it puts a weapon on the board")
	if w == null:
		return
	check(w.team == caster.team, "on the caster's side — which is what makes it the player's to drive")
	check(cb.order.has(w), "it takes a place in the turn order of its own")
	var held = w.statuses.get("summoned")
	check(held is Dictionary and held.get("by") == caster, "it is stamped as this caster's")
	check(int(held.get("fades_tick", 0)) > 0 and not held.has("held_by"),
		"held by a clock rather than by concentration (%s)" % str(held))

	# The whole point of it: it swings.
	cb.begin_turn_for(w)
	var bar: Array = cb.available(w).map(func(x): return String(x["id"]))
	check("attack" in bar, "its own bar offers an attack, with a foe in reach (%s)" % str(bar))
	if not "attack" in bar:
		return
	var hp0: int = foe.hp
	var res := cb.resolve_attack(w, foe)
	check(not res.has("error"), "it can be aimed at a foe (%s)" % str(res.get("error", "")))
	check(bool(res.get("hit", false)) == (foe.hp < hp0), "and the swing lands or misses honestly")
	check(String(w.damage).contains("d8"), "it deals the spell's d8 (%s)" % w.damage)

	# Not an illusion: it is a real token, and the engine has no way to make
	# something both untouchable and able to swing.
	check(not w.has("illusion"), "it is not flagged as an illusion")
	check(not cb.resolve_attack(foe, w).has("error"), "so a foe can strike back at it")

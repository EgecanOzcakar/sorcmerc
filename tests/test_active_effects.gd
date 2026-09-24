# The action bar's effect strip and button marks (core/active_effects.gd).
#
# Three things. The families said right: a Hide is an edge on the next swing
# and puts ADV on the attack button, Poisoned puts DIS there, both at once is a
# plain d20, a Bless from a friend helps and a Bane from a foe hurts, an armed
# Quickened Spell marks exactly the spells it will ride. Every self-buff button
# in the game, pressed, gives a chip named for the button. And the sweep: every
# kit fights, and every status id that turns up on anyone must be one the strip
# has words for (a family, or HIDDEN on purpose) — a new mechanic cannot add a
# buff the bar is silent about.
#   godot --headless --path . -s tests/test_active_effects.gd
extends SceneTree

const Active = preload("res://core/active_effects.gd")
const Adapter = preload("res://core/adapter.gd")
const AI = preload("res://core/ai.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Combat = preload("res://core/combat.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const Kits = preload("res://tests/kits.gd")
const Party = preload("res://core/party.gd")
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
	test_families()
	test_metamagic()
	test_innate_and_smite()
	test_every_self_buff_button()
	test_sweep()
	print("test_active_effects: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# A hero and an ogre on a board, the hero's turn begun.
func duel(ch):
	var h = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
	var g = Encounter.spawn("ogre", 1.0, "foe", Vector2i(3, 0), 1)
	var cb = Combat.new(RNG.new(9), [h, g], Encounter.board_for("goblin-camp"))
	cb.begin_turn_for(h)
	return [cb, h, g]

func chip(cb, c, id: String) -> Dictionary:
	for x in Active.of(cb, c):
		if x["id"] == id:
			return x
	return {}

func attack_marks(cb, h) -> Array:
	for v in cb.all_verbs(h):
		if v["kind"] == "attack":
			return Active.marks(cb, h, v).map(func(m): return m["text"])
	return []

func test_families() -> void:
	var d = duel(Presets.party()[0])
	var cb = d[0]; var h = d[1]; var g = d[2]
	check(Active.of(cb, h).is_empty(), "a fresh hero carries no chips")
	check(attack_marks(cb, h).is_empty(), "...and the attack button no mark")

	h.statuses["hidden"] = true
	var c := chip(cb, h, "hidden")
	check(c.get("label") == "Hidden" and c.get("tone") == Active.EDGE and c.get("clock") == "next attack",
		"Hidden is an edge on the next attack: %s" % c)
	check(attack_marks(cb, h) == ["ADV"], "...and the attack button says ADV (%s)" % str(attack_marks(cb, h)))

	cb.apply_condition(h, "poisoned")
	c = chip(cb, h, "poisoned")
	check(c.get("family") == "condition" and c.get("tone") == Active.HINDRANCE and c.get("label") == "Poisoned",
		"Poisoned is a condition that hurts: %s" % c)
	check(String(c.get("detail", "")).contains("disadvantage"), "...in the SRD's own words")
	check(attack_marks(cb, h) == ["±"], "Hidden and Poisoned together: the marks cancel to a plain d20 (%s)" % str(attack_marks(cb, h)))
	h.statuses.erase("hidden")
	check(attack_marks(cb, h) == ["DIS"], "Poisoned alone: DIS (%s)" % str(attack_marks(cb, h)))
	var why: String = Active.marks(cb, h, cb.all_verbs(h).filter(func(v): return v["kind"] == "attack")[0])[0]["why"]
	check(why.contains("Poisoned"), "...and the mark says why: %s" % why)
	h.statuses.erase("poisoned")
	var order := Active.of(cb, h)
	check(order.is_empty(), "cleared, the strip is empty again")

	# Bless from a friend, Bane from the ogre, a concentration held
	h.statuses["spell:bless"] = {"bonus_to_hit": 2, "bonus_save": 2, "until_tick": cb._tick() + 10 * cb.TICK_STRIDE, "held_by": h}
	h.statuses["spell:bane"] = {"bonus_to_hit": -2, "bonus_save": -2, "until_tick": cb._tick() + 3 * cb.TICK_STRIDE, "held_by": g}
	h.statuses["concentrating"] = {"spell": "bless", "until_round": cb.round_num + 9}
	var bless := chip(cb, h, "spell:bless")
	var bane := chip(cb, h, "spell:bane")
	check(bless.get("label") == "Bless" and bless.get("tone") == Active.EDGE and String(bless.get("detail")).contains("+2 to hit"),
		"Bless from a friend helps, with its numbers: %s" % bless)
	check(bless.get("clock") == "10 rounds", "...and its clock (%s)" % bless.get("clock"))
	check(bane.get("tone") == Active.HINDRANCE and String(bane.get("detail")).contains("-2 to hit"), "Bane from a foe hurts: %s" % bane)
	var conc := chip(cb, h, "concentrating")
	check(conc.get("label") == "Concentrating: Bless" and conc.get("tone") == Active.HOLD, "concentration is held: %s" % conc)
	var tones: Array = Active.of(cb, h).map(func(x): return x["tone"])
	check(tones == [Active.EDGE, Active.HOLD, Active.HINDRANCE], "edges first, then what is held, then what hurts (%s)" % str(tones))

	# weapon mastery Vex names its target; bookkeeping never shows
	h.statuses["vex"] = {"target": g, "until_tick": cb._tick() + cb.TICK_STRIDE}
	check(String(chip(cb, h, "vex").get("detail")).contains(g.cname), "Vex names who it is against")
	var am: Array = Active.marks(cb, h, cb.all_verbs(h).filter(func(v): return v["kind"] == "attack")[0])
	check(not am.is_empty() and String(am[0]["why"]).contains(g.cname), "...and so does the ADV it puts on the attack")
	for id in Active.HIDDEN:
		h.statuses[id] = true
		check(chip(cb, h, id).is_empty(), "%s is bookkeeping, not a chip" % id)
		h.statuses.erase(id)

# An armed option marks the spells it will ride and nothing else.
func test_metamagic() -> void:
	var d = duel(Kits.hero("sorcerer", "draconicsorcery", 5))
	var cb = d[0]; var h = d[1]
	h.statuses["metamagic"] = {"option": "quickened", "sp": 2, "label": "Quickened Spell"}
	var c := chip(cb, h, "metamagic")
	check(c.get("label") == "Quickened Spell" and c.get("clock") == "next spell", "the armed option is a chip: %s" % c)
	check(String(c.get("detail")).contains("Bonus Action"), "...that says what it does")
	var marked := 0
	for v in cb.all_verbs(h):
		var m: Array = Active.marks(cb, h, v).map(func(x): return x["text"])
		var rides: bool = v["kind"] == "spell" and String(v.get("cost", "")) == "action"
		check(("✦" in m) == rides, "%s: marked ✦ exactly when Quickened would ride it (%s)" % [v["id"], str(m)])
		if "✦" in m:
			marked += 1
	check(marked >= 3, "Quickened marks the sorcerer's action spells (%d)" % marked)
	h.econ["cast_leveled_spell"] = true
	var leveled_marked: Array = cb.all_verbs(h).filter(func(v): return int(v.get("slot_level", 0)) > 0 \
		and "✦" in Active.marks(cb, h, v).map(func(x): return x["text"]))
	check(leveled_marked.is_empty(), "after a leveled spell this turn, no leveled spell is offered Quickened")
	h.econ["cast_leveled_spell"] = false
	h.statuses["metamagic"] = {"option": "seeking", "sp": 1, "label": "Seeking Spell"}
	for v in cb.all_verbs(h):
		if v["kind"] == "spell":
			check(("✦" in Active.marks(cb, h, v).map(func(x): return x["text"])) == v.has("attack_bonus"),
				"Seeking rides %s only if it is a spell attack" % v["id"])

func test_innate_and_smite() -> void:
	var d = duel(Kits.hero("sorcerer", "draconicsorcery", 5))
	var cb = d[0]; var h = d[1]
	for v in h.verbs:
		if v["id"] == "sorcerer-innate-sorcery":
			cb.perform(h, v)
	var c := chip(cb, h, "innate-sorcery")
	check(c.get("label") == "Innate Sorcery" and c.get("clock") == "10 rounds", "Innate Sorcery is named for its button: %s" % c)
	check(String(c.get("detail")).contains("+1 spell save DC") and String(c.get("detail")).contains("Advantage on spell attacks"),
		"...and says both halves: %s" % c.get("detail"))
	var atk_spells: Array = cb.all_verbs(h).filter(func(v): return v["kind"] == "spell" and v.has("attack_bonus"))
	check(not atk_spells.is_empty(), "the sorcerer has spell attacks")
	for v in atk_spells:
		check("ADV" in Active.marks(cb, h, v).map(func(x): return x["text"]), "%s: ADV under Innate Sorcery" % v["id"])

	d = duel(Kits.hero("paladin", "oathofdevotion", 5))
	cb = d[0]; h = d[1]
	for v in h.verbs:
		if v["id"] == "paladin-divine-smite":
			cb.perform(h, v)
	c = chip(cb, h, "divine-smite")
	check(c.get("clock") == "next hit" and String(c.get("detail")).contains("2d8"), "a Smite is dice on the next hit: %s" % c)
	check("+2d8" in attack_marks(cb, h), "...and the attack button shows the dice (%s)" % str(attack_marks(cb, h)))

# Every self_buff and ally_buff button in every kit, pressed: the chip it
# leaves is named, and never the generic fallback.
func test_every_self_buff_button() -> void:
	var tried := 0
	var named := {}
	for lvl in [5, 11]:
		for ch in Kits.all(lvl):
			var d = duel(ch)
			var cb = d[0]; var h = d[1]
			for v in cb.all_verbs(h):
				var buff_spell: bool = v["kind"] == "spell" and Effects.spell(String(v.get("spell", ""))).has("buff") \
					and String(v.get("targeting", "")) in ["self", "ally", "allies"]
				if not v["kind"] in ["self_buff", "ally_buff"] and not buff_spell:
					continue
				var before: Array = h.statuses.keys()
				h.econ["action"] = 1; h.econ["bonus"] = 1
				h.econ["cast_leveled_spell"] = false; h.econ["cast_bonus_spell"] = false
				for i in h.slots.size():
					h.slots[i] = maxi(h.slots[i], 1)
				var r: Dictionary = cb.perform(h, v, h)
				if r.has("error"):
					continue
				tried += 1
				for id in h.statuses:
					if id in before:
						continue
					var x := Active.describe(cb, h, String(id))
					check(not x.is_empty() and x["family"] != "unknown" and String(x["label"]) != "",
						"%s: %s leaves a chip the bar can name (%s)" % [ch.id, v["id"], x])
					if not x.is_empty():
						named[String(x["family"])] = int(named.get(String(x["family"]), 0)) + 1
	check(tried >= 20, "the buff buttons were pressed (%d)" % tried)
	print("  buff buttons pressed: %d, chips by family: %s" % [tried, str(named)])
	check(named.has("spell"), "a buff spell cast on yourself leaves a spell chip")

# Real fights, every kit: whatever status turns up on anyone, the strip knows it.
func test_sweep() -> void:
	var families := {}
	var ids := {}
	for lvl in [3, 8]:
		var heroes: Array = Kits.all(lvl)
		for t in range(0, heroes.size(), 4):
			var party = Party.new()
			for ch in heroes.slice(t, t + 4):
				party.add_member(ch)
			var sd: int = 700 + lvl * 100 + t
			var spec: Dictionary = Scaler.roster_for(party.party_characters(), "hard", {}, "", sd)
			spec["seed"] = sd
			var board: Dictionary = Encounter.board_for(String(spec.get("theme", "")), sd)
			var cb = Encounter.build(spec, party.to_combatants(Encounter.starts_for(spec, board, sd)), board)
			cb.party = party
			var g := 0
			while not cb.is_over() and g < 400:
				var a = cb.current()
				cb.begin_turn()
				AI.take_turn(cb, a)
				cb.end_turn()
				g += 1
				for c in cb.combatants:
					for id in c.statuses:
						var x := Active.describe(cb, c, String(id))
						var fam := "hidden" if x.is_empty() else String(x["family"])
						families[fam] = int(families.get(fam, 0)) + 1
						if not ids.has(id):
							ids[id] = fam
							check(fam != "unknown", "status %s has words on the bar (it fell through to the generic chip)" % id)
	print("  statuses seen: %s" % str(ids))
	for fam in ["engine", "condition", "feature", "hidden"]:
		check(families.has(fam), "the sweep met the %s family" % fam)

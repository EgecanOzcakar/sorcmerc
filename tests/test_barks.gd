# Party barks by temperament, and the one that names a partner (the design
# audit, docs/audit-game-design.md §2.3; core/barks.gd). Cosmetic lines, so
# this asserts the pools and the queue, never a rule:
#   - every temperament the data holds has a line for every trigger, its own or
#     the shared pool's, and one it does not know falls back to the shared pool;
#   - only partner_down lines name anybody, and a named line with nobody to
#     name is never said;
#   - in a real fight, a hero whose bonded partner goes down says so, by the
#     partner's name, and the same seed says the same thing.
#   godot --headless --path . -s tests/test_barks.gd
extends SceneTree

const Barks = preload("res://core/barks.gd")
const Traits = preload("res://core/traits.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")

const TRIGGERS := ["hit", "crit", "kill", "low_hp", "down", "victory", "partner_down"]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_every_temperament_has_every_trigger()
	test_named_lines()
	test_temperament_of()
	test_partner_down_in_a_fight()
	print("test_barks: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_every_temperament_has_every_trigger() -> void:
	var tempers: Array = Traits.of_family("temperament")
	check(tempers.size() == 8, "the data holds the eight temperaments (%d)" % tempers.size())
	for t in tempers:
		check(Barks.PARTY_TEMPER.has(t), "%s has its own pools" % t)
		for trig in TRIGGERS:
			var pool: Array = Barks.pool_for("party", "", trig, t)
			check(not pool.is_empty(), "%s has a %s line, its own or the shared one" % [t, trig])
			var own: Array = Barks.PARTY_TEMPER.get(t, {}).get(trig, [])
			check(own.is_empty() or pool == own, "%s speaks from its own %s pool when it has one" % [t, trig])
	for trig in TRIGGERS:
		check(not Barks.PARTY[trig].is_empty(), "the shared pool covers %s" % trig)
		check(Barks.pool_for("party", "", trig, "") == Barks.PARTY[trig], "no temperament: the shared %s pool" % trig)
		check(Barks.pool_for("party", "", trig, "moody") == Barks.PARTY[trig],
			"a temperament a pack added, with no lines: the shared %s pool" % trig)
	# Two temperaments are two voices, not the same pool twice.
	check(Barks.pool_for("party", "", "kill", "brave") != Barks.pool_for("party", "", "kill", "craven"),
		"Brave and Craven do not say the same things")
	# Foes never read a temperament.
	check(Barks.pool_for("foe", "goblinoid", "hit", "brave") == Barks.FOE["goblinoid"]["hit"],
		"a foe's pool ignores any temperament")

func test_named_lines() -> void:
	var pools: Array = [Barks.PARTY]
	for t in Barks.PARTY_TEMPER:
		pools.append(Barks.PARTY_TEMPER[t])
	var ok_named := true
	var ok_other := true
	for pool in pools:
		for trig in pool:
			for ln in pool[trig]:
				var named: bool = Barks.ALLY in String(ln)
				if trig == "partner_down" and not named:
					ok_named = false
				if trig != "partner_down" and named:
					ok_other = false
	check(ok_named, "every partner_down line names the partner")
	check(ok_other, "no other trigger's line names anyone")
	# line() fills the name, and says nothing when it has none to give.
	var said := ""
	for s in range(1, 40):
		said = Barks.line(RNG.new(s), "party", "", "partner_down", "calm", "Vera")
		if said != "":
			break
	check(said != "" and "Vera" in said and not "{" in said, "a partner line says the partner's name: %s" % said)
	var blank := true
	for s in range(1, 40):
		if Barks.line(RNG.new(s), "party", "", "partner_down", "calm", "") != "":
			blank = false
	check(blank, "a named line with nobody to name is never said")
	check(Barks.CHANCE_BY_TRIGGER.get("partner_down", 0) == 100, "a partner going down always gets its line")

func test_temperament_of() -> void:
	check(Barks.temperament(["marsh-bred", "wrathful"]) == "wrathful", "the temperament among a hero's traits")
	check(Barks.temperament(["marsh-bred"]) == "", "no temperament held: none")
	check(Barks.temperament([]) == "", "a monster: none")

# The presets: Vera, Pike, Ilsa. Vera and Ilsa bonded; Ilsa goes down.
func _fight(seed_v: int):
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	Traits.set_family(p.get_member("vera"), "temperament", "brave")
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.BONDED)
	var spec := {"theme": "sunken-shrine", "seed": 7, "monsters": [{"id": "goblin", "count": 2}]}
	var cb = Encounter.build(spec, p.to_combatants(Encounter.PARTY_STARTS))
	cb.party = p
	cb._bark_rng = RNG.new(seed_v)
	return cb

func _c(cb, id: String):
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

func test_partner_down_in_a_fight() -> void:
	var had := OS.get_environment("SORCMERC_FAST")
	OS.set_environment("SORCMERC_FAST", "")
	var cb = _fight(5)
	var ilsa = _c(cb, "ilsa")
	cb._apply_damage(ilsa, ilsa.hp)   # to 0, not past max: down, not dead
	check(ilsa.has("down"), "Ilsa is down")
	var line: Dictionary = {}
	for b in cb.barks:
		if b["id"] == "vera":
			line = b
	check(not line.is_empty(), "Vera, bonded to her, says something (%s)" % str(cb.barks))
	var first := String(ilsa.cname).get_slice(" ", 0)
	check(first in String(line.get("text", "")), "...and names her: %s" % line.get("text", ""))
	var brave: Array = Barks.PARTY_TEMPER["brave"]["partner_down"].map(func(l): return String(l).replace(Barks.ALLY, first))
	check(String(line.get("text", "")) in brave, "...in a Brave hero's words")
	for b in cb.barks:
		check(b["id"] != "pike", "Pike, who is not close to her, says nothing about it")
	# Nobody names a hero who is not in this fight: the name is the fallen's.
	var names: Array = cb.combatants.map(func(c): return String(c.cname).get_slice(" ", 0))
	for b in cb.barks:
		if b["id"] == "vera":
			var hit := false
			for n in names:
				if n in String(b["text"]):
					hit = true
			check(hit, "the named line names somebody really in the fight")
	# Same seed, same words.
	var again = _fight(5)
	var ilsa2 = _c(again, "ilsa")
	again._apply_damage(ilsa2, ilsa2.hp)
	check(again.barks == cb.barks, "the same seed says the same thing")
	OS.set_environment("SORCMERC_FAST", had)

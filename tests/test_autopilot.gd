# The party autopilot spends its whole turn: every swing the Attack action
# buys, and a Bonus Action wherever one is reasonable (core/ai.gd,
# _swing_all and _bonus_after).
#
# Scenes first, one rule each, on a hero and an ogre: Extra Attack swung, a
# monk's Flurry, a rogue's Dash to reach and Hide after shooting, Bardic
# Inspiration on the ally in the thick of it, a held concentration left alone,
# a downed ally lifted by a Bonus Action heal with the action still free, and
# the two ways out at a third of HP (Misty Step, Disengage-and-walk). Then every
# kit at levels 3 and 8: the fights finish, the same seed plays the same fight,
# and a kit with a Bonus Action on offer spends it on a fair share of its turns.
#   godot --headless --path . -s tests/test_autopilot.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const AI = preload("res://core/ai.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Kits = preload("res://tests/kits.gd")
const Party = preload("res://core/party.gd")
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
	test_extra_attack()
	test_flurry()
	test_rogue_dash_and_hide()
	test_inspiration_goes_to_the_engaged()
	test_concentration_is_kept()
	test_bonus_heal_keeps_the_action()
	test_ways_out()
	test_every_kit()
	print("test_autopilot: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# `heroes` at their positions against one ogre at `foe_at`, the first hero's
# turn begun. The ogre is fattened so a scene is never cut short by a kill.
func scene(heroes: Array, foe_at: Vector2i, mult := 4.0) -> Array:
	var cs: Array = []
	for pair in heroes:
		cs.append(Adapter.to_combatant(pair[0], "party", pair[1]))
	var g = Encounter.spawn("ogre", mult, "foe", foe_at, 1)
	cs.append(g)
	var cb = Combat.new(RNG.new(11), cs, Encounter.board_for("goblin-camp"))
	cb.begin_turn_for(cs[0])
	return [cb, cs, g]

func log_since(cb, n: int) -> String:
	return "\n".join(cb.log.slice(n))

func swings(text: String, who: String) -> int:
	var n := 0
	for line in text.split("\n"):
		if line.begins_with(who + " hits ") or line.begins_with(who + " attacks ") or line.begins_with(who + " CRITS "):
			n += 1
	return n

func test_extra_attack() -> void:
	var s := scene([[Kits.hero("fighter", "champion", 8), Vector2i(2, 0)]], Vector2i(3, 0))
	var cb = s[0]; var h = s[1][0]
	var n0: int = cb.log.size()
	AI.take_turn(cb, h)
	var t := log_since(cb, n0)
	check(swings(t, h.cname) == 2, "a level-8 fighter swings twice, not once (%d):\n%s" % [swings(t, h.cname), t])
	check(int(h.econ["attacks_left"]) == 0, "...and leaves no swing banked")

func test_flurry() -> void:
	var s := scene([[Kits.hero("monk", "warrioropenhand", 8), Vector2i(2, 0)]], Vector2i(3, 0))
	var cb = s[0]; var h = s[1][0]
	var n0: int = cb.log.size()
	AI.take_turn(cb, h)
	var t := log_since(cb, n0)
	check(t.contains("Flurry of Blows"), "a monk with a foe in reach flurries:\n%s" % t)
	check(swings(t, h.cname) >= 4, "...and swings what it bought: two from the action, two from the flurry (%d)" % swings(t, h.cname))
	check(int(h.econ["bonus"]) == 0, "...the Bonus Action is spent")

func test_rogue_dash_and_hide() -> void:
	# Too far to walk to: Cunning Action's Dash covers the rest, then the swing.
	var s := scene([[Kits.hero("rogue", "thief", 5), Vector2i(0, 0)]], Vector2i(8, 0))
	var cb = s[0]; var h = s[1][0]; var g = s[2]
	check(Hex.distance(h.pos, g.pos) > h.speed + 1, "the scene: the ogre is out of a walk's reach")
	var n0: int = cb.log.size()
	AI.take_turn(cb, h)
	var t := log_since(cb, n0)
	check(t.contains("dashes"), "a rogue too far to walk dashes as a Bonus Action:\n%s" % t)
	check(cb.in_reach(h, g) and swings(t, h.cname) >= 1, "...and still swings with the action it kept")
	# A shooter with nothing beside them: shoot, then hide for next turn's Advantage.
	s = scene([[Kits.hero("rogue", "thief", 5), Vector2i(0, 0)]], Vector2i(4, 0))
	cb = s[0]; h = s[1][0]
	h.ranged = true
	h.atk_range = 16
	n0 = cb.log.size()
	AI.take_turn(cb, h)
	t = log_since(cb, n0)
	check(swings(t, h.cname) >= 1 and (t.contains("slips out of sight") or t.contains("fails to hide")),
		"a rogue shooting from range hides after the shot:\n%s" % t)

func test_inspiration_goes_to_the_engaged() -> void:
	var s := scene([[Kits.hero("bard", "collegelore", 5), Vector2i(0, 0)],
		[Kits.hero("fighter", "champion", 5), Vector2i(2, 0)],
		[Kits.hero("wizard", "evoker", 5), Vector2i(0, 2)]], Vector2i(3, 0))
	var cb = s[0]; var bard = s[1][0]; var fighter = s[1][1]; var wizard = s[1][2]
	AI.take_turn(cb, bard)
	check(fighter.has("inspired"), "Bardic Inspiration goes on the ally with the ogre beside them")
	check(not wizard.has("inspired"), "...not on the one standing clear")

func test_concentration_is_kept() -> void:
	var s := scene([[Kits.hero("cleric", "wardomain", 5), Vector2i(2, 0)]], Vector2i(3, 0))
	var cb = s[0]; var h = s[1][0]
	h.statuses["concentrating"] = {"spell": "bless", "until_round": cb.round_num + 9}
	var n0: int = cb.log.size()
	AI.take_turn(cb, h)
	var t := log_since(cb, n0)
	check(String(h.statuses.get("concentrating", {}).get("spell", "")) == "bless",
		"a cleric holding Bless casts no concentration Bonus Action spell over it:\n%s" % t)
	# not concentrating, the same cleric puts one up (or swings a War Priest's extra)
	s = scene([[Kits.hero("cleric", "wardomain", 5), Vector2i(2, 0)]], Vector2i(3, 0))
	cb = s[0]; h = s[1][0]
	AI.take_turn(cb, h)
	check(int(h.econ["bonus"]) == 0, "a War cleric spends the Bonus Action it has on offer")

func test_bonus_heal_keeps_the_action() -> void:
	var s := scene([[Kits.hero("bard", "collegelore", 8), Vector2i(1, 0)],
		[Kits.hero("fighter", "champion", 8), Vector2i(2, 0)]], Vector2i(3, 0))
	var cb = s[0]; var bard = s[1][0]; var fighter = s[1][1]
	fighter.hp = 0
	fighter.statuses["down"] = true
	var heals: Array = cb.available(bard).filter(func(v): return v.has("heal_count") and String(v.get("cost", "")) == "bonus")
	check(not heals.is_empty(), "the scene: a level-8 bard has a Bonus Action heal")
	var n0: int = cb.log.size()
	AI.take_turn(cb, bard)
	var t := log_since(cb, n0)
	check(fighter.conscious(), "a downed ally is lifted:\n%s" % t)
	check(int(bard.econ["action"]) == 0 and int(bard.econ["bonus"]) == 0,
		"...by the Bonus Action heal, with the action still spent on the fight (%s)" % bard.econ)

func test_ways_out() -> void:
	var s := scene([[Kits.hero("warlock", "archfeypatron", 5), Vector2i(2, 0)]], Vector2i(3, 0))
	var cb = s[0]; var h = s[1][0]; var g = s[2]
	h.hp = h.max_hp / 4
	var steps: Array = cb.available(h).filter(func(v): return v.get("teleport", false) and String(v.get("cost", "")) == "bonus")
	check(not steps.is_empty(), "the scene: an Archfey warlock has Misty Step")
	var n0: int = cb.log.size()
	AI.take_turn(cb, h)
	check(Hex.distance(h.pos, g.pos) > 1, "at a quarter of HP with the ogre beside them, Misty Step away:\n%s" % log_since(cb, n0))
	s = scene([[Kits.hero("rogue", "thief", 5), Vector2i(2, 0)]], Vector2i(3, 0))
	cb = s[0]; h = s[1][0]; g = s[2]
	h.hp = h.max_hp / 4
	var hp0: int = h.hp
	n0 = cb.log.size()
	AI.take_turn(cb, h)
	var t := log_since(cb, n0)
	check(t.contains("disengages") and Hex.distance(h.pos, g.pos) > 1 and h.hp == hp0,
		"a hurt rogue Disengages and walks, and the ogre gets no swing on the way out:\n%s" % t)

# Every kit, levels 3 and 8, a normal roster: the fight ends, plays the same
# twice, and the Bonus Action is spent on a fair share of the turns it is on
# offer. FAIR is not a target — just the line under which the autopilot has
# stopped trying. MEASURED 2026-09-24 on this sweep: master spent it on 60 of
# 340 offered turns (18%), this change on 119 of 263 (45%; fewer turns, as the
# fights end sooner).
const FAIR := 0.35

func test_every_kit() -> void:
	var had := 0
	var spent := 0
	for lvl in [3, 8]:
		var heroes: Array = Kits.all(lvl)
		for t in range(0, heroes.size(), 4):
			var logs: Array = []
			for run in 2:
				var party = Party.new()
				for ch in heroes.slice(t, t + 4):
					party.add_member(ch)
				var sd: int = 900 + lvl * 10 + t
				var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal", {}, "", sd)
				spec["seed"] = sd
				var board: Dictionary = Encounter.board_for(String(spec.get("theme", "")), sd)
				var cb = Encounter.build(spec, party.to_combatants(Encounter.starts_for(spec, board, sd)), board)
				cb.party = party
				var g := 0
				while not cb.is_over() and g < 600:
					var a = cb.current()
					cb.begin_turn()
					var offered: bool = run == 0 and a.team == "party" and a.conscious() \
						and cb.available(a).any(func(v): return String(v.get("cost", "")) == "bonus")
					AI.take_turn(cb, a)
					if offered and a.conscious():
						had += 1
						if int(a.econ.get("bonus", 1)) <= 0:
							spent += 1
					cb.end_turn()
					g += 1
				if run == 0:
					check(cb.is_over(), "L%d kits %d-%d: the fight ends (%d turns)" % [lvl, t, t + 3, g])
				logs.append("\n".join(cb.log))
			check(logs[0] == logs[1], "L%d kits %d-%d: the same seed plays the same fight" % [lvl, t, t + 3])
	var share := float(spent) / maxf(1.0, float(had))
	print("  Bonus Action spent on %d of %d turns it was on offer (%.0f%%)" % [spent, had, 100.0 * share])
	check(share >= FAIR, "the autopilot spends a Bonus Action on a fair share of the turns it has one (%.0f%%)" % (100.0 * share))

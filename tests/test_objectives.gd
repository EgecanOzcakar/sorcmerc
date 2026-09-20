# Encounter objectives — the same fight, asked a different question.
#   docs/superpowers/specs/2026-09-20-encounter-objectives-design.md
#   godot --headless --path . -s tests/test_objectives.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_bystander()
	test_make_and_brief()
	test_placement()
	test_hold()
	test_rescue()
	test_breakout()
	test_hunt()
	test_escort()
	test_quarry_runs()
	test_autopilot_rules()
	test_rewards()
	print("test_objectives: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# A fight from a spec, the way scenes/main.gd builds one: board from the theme
# and seed, starts from the objective, presets at level 3 for the party.
func _fight(spec: Dictionary, seed: int) -> Combat:
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), seed)
	var starts: Array = Encounter.starts_for(sp, board, seed)
	var chars: Array = Presets.party()
	var party_c: Array = []
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", starts[i]))
	return Encounter.build(sp, party_c, board)

func _autoplay(cb: Combat) -> void:
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1

func _goblins(n: int) -> Dictionary:
	return {"monsters": [{"id": "snik", "count": n}], "theme": "goblin-camp"}

# Walk the order until `who` is current, beginning turns and letting the AI
# take everyone else's. Returns false if the fight ended first.
func _until_turn_of(cb: Combat, who) -> bool:
	var g := 0
	while not cb.is_over() and g < 200:
		var a = cb.current()
		cb.begin_turn()
		if a == who:
			return true
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return false

# Nobody moves and nobody dies: for the rule tests that place tokens by hand.
func _freeze(cb: Combat) -> void:
	for c in cb.combatants:
		if not c.has("bystander"):
			c.speed = 0
			c.max_hp = 100000
			c.hp = 100000

func _rounds_until_over(cb: Combat, cap := 40) -> int:
	while not cb.is_over() and cb.round_num <= cap:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
	return cb.round_num

# --- Task 1: the contract and the bystanders --------------------------------

func test_bystander() -> void:
	var cb := _fight(_goblins(2), 5)
	check(cb.objective.is_empty() and cb.objective_kind() == "", "no objective on the spec = rout")
	check(cb.order.size() == cb.combatants.size(), "rout: everybody who is in the fight has a turn")

	var car = Objectives.carter(Vector2i(0, 1), 3)
	check(car.team == "party" and car.has("bystander") and car.hp == 12 and car.ac == 11,
		"a carter is a party-side bystander with 6 + 2/level HP")
	var cap = Objectives.captive(Vector2i(8, 0))
	check(cap.has("bystander") and cap.has("captive") and cap.hp == 4, "a captive is a bystander that is also a captive")

	# Stood in a fight: never in the order, never a target for a foe, no death saves.
	var party_c: Array = []
	var chars: Array = Presets.party()
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	party_c.append(car)
	party_c.append(cap)
	var foe = Encounter.spawn("snik", 1.0, "foe", Vector2i(7, 0))
	var cb2 = Combat.new(RNG.new(3), party_c + [foe], Encounter.board())
	check(cb2.order.size() == 4, "the two bystanders are not in the initiative order (%d)" % cb2.order.size())
	check(cb2.with_status("carter") == car and cb2.with_status("captive") == cap, "with_status finds them")
	check(cb2.heroes().size() == 3, "heroes() is the conscious party without bystanders")
	check(not cb2.enemies_of(foe).has(cap), "a captive is never an enemy for a foe")
	check(cb2.enemies_of(foe).has(car), "...but a carter is fair game")
	check(not cb2.legal_target(foe, cb2.attack_verb(), cap), "legal_target refuses the captive")
	cb2._apply_damage(car, 50)
	check(car.is_dead() and not car.is_down(), "a bystander at 0 HP is dead, not down")
	check(not cb2.downed.has("carter"), "...and is not in the downed list")
	check(cb2.objective_failed, "a dead bystander fails the objective")

	# car's overkill (38) alone satisfies the pre-existing massive-damage clause
	# (overkill >= max_hp) no matter the target, so that death doesn't pin the
	# bystander rule specifically. Zero-overkill damage on the captive does:
	# only target.has("bystander") explains this kill.
	cb2._apply_damage(cap, cap.max_hp)
	check(cap.is_dead() and not cap.is_down(), "a bystander dies at 0 HP with no overkill too")

	for h in cb2.heroes():
		cb2._apply_damage(h, 500)
	check(cb2._team_out("party"), "a party with only a bystander standing is out")
	check(cb2.is_over() and cb2.outcome() == "Defeat", "...and that is a defeat")

# --- Task 2: placement --------------------------------------------------

func test_make_and_brief() -> void:
	var h := Objectives.make("hold")
	check(h["kind"] == "hold" and int(h["rounds"]) == Objectives.HOLD_ROUNDS and h["waves"] == [], "hold has its defaults")
	check(int(Objectives.make("rescue")["deadline"]) == Objectives.RESCUE_DEADLINE, "rescue has its deadline")
	check(Objectives.make("hold", {"rounds": 9})["rounds"] == 9, "extra overrides a default")
	for k in Objectives.KINDS:
		check(Objectives.brief(Objectives.make(k)) != "", "%s has a brief" % k)
	check(Objectives.brief({}) == "", "rout has no brief")

func test_placement() -> void:
	# rescue: the captive is the deepest free hex, and foes are not on top of it
	var cb := _fight(_goblins(3).merged({"objective": Objectives.make("rescue")}), 7)
	var cap = cb.with_status("captive")
	check(cap != null and cap.pos in cb.board["hexes"], "rescue puts a captive on the board")
	var nearest := 99
	for h in cb.heroes():
		nearest = mini(nearest, Hex.distance(h.pos, cap.pos))
	check(nearest >= Encounter.SPAWN_GAP, "...well beyond the party (%d)" % nearest)
	check(cb.combatants.filter(func(c): return c.pos == cap.pos).size() == 1, "...on a hex of its own")
	check(cb.log[cb.log.size() - 1] == Objectives.brief(cb.objective) or cb.log.has(Objectives.brief(cb.objective)),
		"the brief is in the log")

	# escort: the carter is in among the party
	cb = _fight(_goblins(3).merged({"objective": Objectives.make("escort")}), 7)
	var car = cb.with_status("carter")
	var far := 0
	for h in cb.heroes():
		far = maxi(far, Hex.distance(h.pos, car.pos))
	check(car != null and far <= 3, "escort puts the carter in among the party (farthest hero %d)" % far)
	check(car.max_hp == Objectives.CARTER_HP_BASE + Objectives.CARTER_HP_PER_LEVEL * 3, "...with HP for a level-3 party")
	check(cb.combatants.filter(func(c): return c.pos == car.pos).size() == 1, "...on a hex of its own")

	# breakout: the party in the middle, foes both sides, the exit at the far edge and free of foes
	cb = _fight(_goblins(6).merged({"objective": Objectives.make("breakout")}), 7)
	var exit: Array = cb.objective.get("exit", [])
	check(exit.size() == Objectives.EXIT_W, "breakout has %d exit hexes" % Objectives.EXIT_W)
	var max_q := -99
	for h in cb.board["hexes"]:
		max_q = maxi(max_q, h.x)
	check(exit.all(func(e): return e.x >= max_q - 2), "...at the far (high-q) edge")
	check(cb.team_of("foe").all(func(f): return not (f.pos in exit)), "...and nobody spawns on the road")
	var qs: Array = cb.heroes().map(func(h): return h.pos.x)
	var lo: int = cb.team_of("foe").filter(func(f): return f.pos.x < qs.min()).size()
	var hi: int = cb.team_of("foe").filter(func(f): return f.pos.x > qs.max()).size()
	check(lo > 0 and hi > 0, "foes stand on both sides of the party (%d behind, %d ahead)" % [lo, hi])

	# hunt: the strongest foe is the quarry and it starts nearest the party — it has the whole board to cross
	cb = _fight({"monsters": [{"id": "snik", "count": 3}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}, 7)
	var q = cb.with_status("quarry")
	check(q != null and q.src_id == "grull", "the quarry is the strongest foe")
	check(cb.objective.get("exit", []).size() == Objectives.EXIT_W, "hunt has an escape edge")
	check(cb.team_of("foe").all(func(f): return not (f.pos in cb.objective["exit"])), "no foe starts on the treeline")
	var qd := 99
	for h in cb.heroes():
		qd = mini(qd, Hex.distance(h.pos, q.pos))
	for f in cb.team_of("foe"):
		var fd := 99
		for h in cb.heroes():
			fd = mini(fd, Hex.distance(h.pos, f.pos))
		check(fd >= qd, "no foe starts nearer the party than the quarry (%s %d vs %d)" % [f.cname, fd, qd])

	# starts_for: breakout is the only kind that moves the party
	var board: Dictionary = Encounter.board_for("goblin-camp", 7)
	check(Encounter.starts_for(_goblins(3), board, 7) == Encounter.party_starts(board, 7), "rout starts where it always did")
	check(Encounter.starts_for({"objective": Objectives.make("hunt")}, board, 7) == Encounter.party_starts(board, 7), "so does a hunt")
	check(Encounter.starts_for({"objective": Objectives.make("breakout")}, board, 7) != Encounter.party_starts(board, 7), "a breakout starts elsewhere")
	check(not _fight(_goblins(1).merged({"objective": Objectives.make("escort")}), 7).objective.has("exit"), "only breakout and hunt carry an exit")

# --- Task 3: the rules of each kind, inside the fight ------------------

func test_hold() -> void:
	# An unkillable wall of goblins: the only way this ends is the clock.
	var spec := {"monsters": [{"id": "snik", "count": 2, "mult": 6.0}], "theme": "goblin-camp",
		"objective": Objectives.make("hold", {"rounds": 3, "waves": [[{"id": "snik", "count": 2}], [{"id": "snik", "count": 1}]]})}
	var cb := _fight(spec, 11)
	var opening: int = cb.team_of("foe").size()
	_freeze(cb)   # nothing dies either way: only the clock can end this
	_rounds_until_over(cb, 10)
	check(cb.round_num == 4, "hold ends at the top of round rounds + 1 (%d)" % cb.round_num)
	check(cb.outcome() == "Victory" and cb.objective_done, "...and it is a victory with foes standing")
	check(cb.team_of("foe").size() == opening + 3, "two waves arrived (%d foes)" % cb.team_of("foe").size())
	check(cb.team_of("foe").any(func(f): return f.id.begins_with("w2-")), "wave ids are prefixed by their round")
	check(cb.objective_result(), "the deed is done")
	check(cb.objective_line().begins_with("Hold — round"), "HUD: %s" % cb.objective_line())

func test_rescue() -> void:
	var spec := _goblins(1).merged({"objective": Objectives.make("rescue", {"deadline": 2})})
	var cb := _fight(spec, 13)
	var cap = cb.with_status("captive")
	_freeze(cb)   # nobody can walk to the captive, so the deadline is what happens
	check(cb.objective_line() == "Captive — 2 rounds left", "HUD counts down: %s" % cb.objective_line())
	_rounds_until_over(cb, 4)
	check(cap.is_dead() and cb.objective_failed, "unfreed at the top of round deadline + 1, the captive is killed")
	check(not cb.is_over(), "...and the fight goes on")
	check(cb.objective_line() == "Captive — lost", "HUD says so")

	# freed by adjacency, no action needed, before the deadline
	cb = _fight(spec, 13)
	cap = cb.with_status("captive")
	_freeze(cb)
	var h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "it is a hero's turn")
	h.pos = Hex.neighbors(cap.pos)[0]
	cb.end_turn()
	check(cap.has("freed") and not cb.objective_failed, "ending a turn adjacent frees the captive")
	check(cb.objective_result(), "...which is the deed")
	for i in 6:
		cb.begin_turn(); cb.end_turn()
	check(not cap.is_dead(), "the deadline no longer applies")

func test_breakout() -> void:
	var spec := _goblins(2).merged({"objective": Objectives.make("breakout")})
	var cb := _fight(spec, 17)
	var exit: Array = cb.objective["exit"]
	_freeze(cb)
	var heroes: Array = cb.heroes()
	check(cb.objective_line() == "Road — 0 of %d heroes there" % heroes.size(), "HUD: %s" % cb.objective_line())
	check(_until_turn_of(cb, heroes[0]), "a hero's turn")
	heroes[0].pos = exit[0]
	cb.end_turn()
	check(not cb.is_over(), "one hero on the road is not a breakout")
	for i in heroes.size():
		heroes[i].pos = exit[i]
	cb._objective_touch(heroes[1])
	check(cb.objective_done and cb.is_over() and cb.outcome() == "Victory", "everyone on the road ends it, a victory, foes standing")

func test_hunt() -> void:
	var spec := {"monsters": [{"id": "snik", "count": 2}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	var cb := _fight(spec, 19)
	_freeze(cb)
	var q = cb.with_status("quarry")
	var exit: Array = cb.objective["exit"]
	check(_until_turn_of(cb, q), "the quarry's turn")
	q.pos = exit[0]
	cb.end_turn()
	check(q.has("escaped") and q.is_dead() and cb.objective_failed, "ending its turn on the far edge, the quarry is gone")
	check(not cb.is_over(), "...and the escort is still there to fight")
	check(cb.objective_line() == "Quarry — gone", "HUD: %s" % cb.objective_line())

	cb = _fight(spec, 19)
	q = cb.with_status("quarry")
	cb._apply_damage(q, 999)
	check(q.is_dead() and cb.objective_done and cb.is_over() and cb.outcome() == "Victory",
		"the quarry down ends the fight as a victory with the escort standing")
	check(cb.objective_result(), "...and the deed is done")

func test_escort() -> void:
	var spec := _goblins(2).merged({"objective": Objectives.make("escort")})
	var cb := _fight(spec, 23)
	var car = cb.with_status("carter")
	check(cb.objective_line() == "Carter — %d HP" % car.hp, "HUD: %s" % cb.objective_line())
	check(cb.objective_result(), "alive = the deed, so far")
	cb._apply_damage(car, 99)
	check(car.is_dead() and cb.objective_failed and not cb.is_over(), "the carter dead fails the objective and the fight goes on")
	check(not cb.objective_result() and cb.objective_line() == "Carter — dead", "HUD: %s" % cb.objective_line())

# --- Task 4: the AI — the quarry runs, and the autopilot tries --------------

func test_quarry_runs() -> void:
	var spec := {"monsters": [{"id": "snik", "count": 1}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	var cb := _fight(spec, 29)
	var q = cb.with_status("quarry")
	var exit: Array = cb.objective["exit"]
	var far := func(p: Vector2i) -> int:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(p, e))
		return d
	# nobody near (the party starts SPAWN_GAP away, past QUARRY_CORNERED): it runs, and swings at nobody
	for c in cb.combatants:
		if c.team == "party":
			c.speed = 0   # the heroes stay put, so it is the quarry's own choice being tested
	check(_until_turn_of(cb, q), "the quarry's turn")
	var before: int = far.call(q.pos)
	var hp_before: Array = cb.heroes().map(func(h): return h.hp)
	AI.take_turn(cb, q)
	check(far.call(q.pos) < before, "with nobody within %d, the quarry runs for the treeline (%d -> %d)" % [Objectives.QUARRY_CORNERED, before, far.call(q.pos)])
	check(cb.heroes().map(func(h): return h.hp) == hp_before, "...and attacks nobody")
	# a hero on its heels: it fights
	cb = _fight(spec, 29)
	q = cb.with_status("quarry")
	check(_until_turn_of(cb, q), "the quarry's turn again")
	var h = cb.heroes()[0]
	h.pos = Hex.neighbors(q.pos)[0]
	var at: Vector2i = q.pos
	var log_n: int = cb.log.size()
	AI.take_turn(cb, q)
	check(cb.log.size() > log_n and (q.pos == at or Hex.distance(q.pos, h.pos) <= 1),
		"cornered, it stands and fights (%s)" % str(cb.log.slice(log_n)))

func test_autopilot_rules() -> void:
	# rescue: the hero nearest the captive closes on it before anything else
	var cb := _fight(_goblins(1).merged({"objective": Objectives.make("rescue")}), 31)
	var cap = cb.with_status("captive")
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var runner = AI._nearest(cap.pos, cb.heroes())
	check(_until_turn_of(cb, runner), "the runner's turn")
	var d0: int = Hex.distance(runner.pos, cap.pos)
	AI.take_turn(cb, runner)
	check(Hex.distance(runner.pos, cap.pos) < d0, "rescue: the nearest hero moves toward the captive (%d -> %d)" % [d0, Hex.distance(runner.pos, cap.pos)])

	# breakout: heroes head for the road and do not chase
	cb = _fight(_goblins(2).merged({"objective": Objectives.make("breakout")}), 31)
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var exit: Array = cb.objective["exit"]
	var near_exit := func(p: Vector2i) -> int:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(p, e))
		return d
	var h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "a hero's turn")
	var e0: int = near_exit.call(h.pos)
	var foes: Array = cb.team_of("foe")
	var hp0: Array = foes.map(func(f): return f.hp)
	AI.take_turn(cb, h)
	check(near_exit.call(h.pos) < e0, "breakout: a hero moves toward the road (%d -> %d)" % [e0, near_exit.call(h.pos)])
	check(foes.map(func(f): return f.hp) == hp0, "...and does not chase: no foe takes damage")
	check(foes.all(func(f): return Hex.distance(h.pos, f.pos) > 1), "...nor ends adjacent to one")

	# escort: a hero that has drifted comes back to the carter
	cb = _fight(_goblins(1).merged({"objective": Objectives.make("escort")}), 31)
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var car = cb.with_status("carter")
	h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "a hero's turn")
	h.pos = Encounter.far_hexes(cb.board, cb.combatants.map(func(c): return c.pos), 1)[0]
	var c0: int = Hex.distance(h.pos, car.pos)
	AI.take_turn(cb, h)
	check(Hex.distance(h.pos, car.pos) < c0, "escort: a hero more than 2 away closes on the carter (%d -> %d)" % [c0, Hex.distance(h.pos, car.pos)])

	# hunt: the quarry and a weaker foe are both in reach — the hero swings at the quarry
	cb = _fight({"monsters": [{"id": "snik", "count": 1}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}, 31)
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var q = cb.with_status("quarry")
	var goblin = cb.team_of("foe").filter(func(c): return not c.has("quarry"))[0]
	h = cb.heroes().filter(func(c): return not c.ranged)[0]
	check(_until_turn_of(cb, h), "a melee hero's turn")
	# only now, on h's own turn, weaken and place them — an earlier hero's turn
	# during the walk above must not get first crack at the softened goblin
	goblin.hp = 1000   # far below the quarry's: the old lowest-HP rule would swing here instead
	h.atk_bonus = 100   # the swing cannot miss
	var nbrs: Array = Hex.neighbors(h.pos)
	goblin.pos = nbrs[0]
	q.pos = nbrs[1]
	var qhp0: int = q.hp
	AI.take_turn(cb, h)
	check(q.hp < qhp0 and goblin.hp == 1000, "hunt: reach prefers the quarry over the lower-HP goblin (%d -> %d)" % [qhp0, q.hp])

# --- Task 5: rewards — the objective row and the deed's XP ------------------

func test_rewards() -> void:
	# rout: the row is there and empty
	var cb := _fight(_goblins(1), 37)
	for f in cb.team_of("foe"):
		cb._apply_damage(f, 999)
	var res: Dictionary = Encounter.resolve_outcome(cb, Presets.party())
	check(res["objective"] == {"kind": "", "done": false, "xp": 0}, "rout: an empty objective row")

	# hunt won: the escort's power counts for the bonus though it never died
	var spec := {"monsters": [{"id": "snik", "count": 2}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	cb = _fight(spec, 37)
	var q = cb.with_status("quarry")
	cb._apply_damage(q, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	var roster := 0.0
	for f in cb.team_of("foe"):
		roster += float(Encounter.Power.estimate(f)["score"])
	var quarry_xp: int = roundi(float(Encounter.Power.estimate(q)["score"]) * Encounter.XP_PER_POWER)
	var bonus: int = roundi(roster * Encounter.XP_PER_POWER * Objectives.BONUS_XP_SHARE)
	check(res["outcome"] == "Victory" and res["objective"]["done"], "the hunt is won")
	check(int(res["objective"]["xp"]) == bonus and bonus > 0, "the bonus is half the whole roster's worth (%d)" % bonus)
	check(int(res["xp"]) == quarry_xp + bonus, "xp = the kill + the bonus (%d = %d + %d)" % [res["xp"], quarry_xp, bonus])
	check(res["kills"] == ["grull"], "only the dead are kills")

	# hunt lost to an escape: no kill, no loot, no bonus for the one that got away
	cb = _fight(spec, 37)
	q = cb.with_status("quarry")
	cb._quarry_escape(q)
	for f in cb.team_of("foe"):
		if f != q:
			cb._apply_damage(f, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	check(res["outcome"] == "Victory" and not res["objective"]["done"] and int(res["objective"]["xp"]) == 0,
		"escort routed, quarry gone: a victory with the objective failed and no bonus")
	check(not res["kills"].has("grull"), "the escaped quarry is not a kill")

	# a dead bystander is not a death
	cb = _fight(_goblins(1).merged({"objective": Objectives.make("escort")}), 37)
	cb._apply_damage(cb.with_status("carter"), 99)
	for f in cb.team_of("foe"):
		cb._apply_damage(f, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	check(res["deaths"] == [] and not res["downed"].has("carter"), "the carter is in neither deaths nor downed")
	check(not res["objective"]["done"], "...and the escort failed")

	check(Objectives.spoils_line({"kind": "hunt", "done": true, "xp": 40}) == "Objective — the quarry is down  (+40 XP)", "spoils line, done")
	check(Objectives.spoils_line({"kind": "escort", "done": false, "xp": 0}) == "Objective — the carter is dead", "spoils line, failed")

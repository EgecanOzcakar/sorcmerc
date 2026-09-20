# Co-op spike: two peers running the same fight in lockstep from the same
# setup, only intents crossing (as JSON), state hashes equal after every one —
# and a third peer that joins late, rebuilds from the setup and replays the
# log to the same hash (that is what a rejoin is).
#   godot --headless --path . -s tests/test_coop.gd
extends SceneTree

const Coop = preload("res://core/coop.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const AI = preload("res://core/ai.gd")
const Hex = preload("res://core/hex.gd")
const Leveling = preload("res://core/leveling.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Character = preload("res://core/character.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const SEEDS := 40

var _pass = 0
var _fail = 0
var _seen := {}   # intent kind / verb id -> how many crossed the codec

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var code := Coop.room_code()
	check(code.length() == 6, "room code is six characters")
	check(not ("0" in code or "O" in code or "1" in code or "I" in code), "room code avoids 0/O/1/I")
	for sd in range(1, SEEDS + 1):
		lockstep_fight(sd)
	# The same, with reaction prompts on: the reactor's owner decides, the
	# answer crosses the wire and the other peer consumes it in order (what
	# scenes/main.gd's _coop_decide does). Ilsa's Warding Flare is the prompt.
	_asked = 0
	_said_no = 0
	for sd in range(1, 11):
		lockstep_fight(sd, true)
	check(_asked > 0 and _said_no > 0, "prompted: %d reactions asked, %d refused" % [_asked, _said_no])
	test_the_wire_keeps_a_party_whole()
	await guest_levelup()
	test_intify()
	print("  through the codec: ", JSON.stringify(_seen))
	print("test_coop: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The same steps scenes/main.gd takes, so the guest builds what the host built.
static func build(setup: Dictionary):
	return build_with(Coop.party_from(setup), setup)

# The host's own version of it: the same board and the same spec, from the party
# object the road has been playing rather than from its JSON.
static func build_with(party, setup: Dictionary):
	var sp: Dictionary = setup["spec"]
	var sd := int(setup["seed"])
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), sd)
	var cb = Encounter.build(sp, party.to_combatants(Encounter.party_starts(board, sd)), board)
	cb.party = party
	return cb

# Over the wire and back: what the other peer actually receives.
static func wire(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))

var _asked := 0
var _said_no := 0

func lockstep_fight(sd: int, prompted := false) -> void:
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal")
	spec["seed"] = sd
	var setup := wire(Coop.setup_for(sd, spec, party))
	check(setup["owners"].size() == 3 and setup["owners"].values().count("guest") == 1,
		"seed %d: heroes alternate host/guest" % sd)
	var host = build(setup)
	var guest = build(setup)
	check(Coop.state_hash(host) == Coop.state_hash(guest), "seed %d: same setup, same fight" % sd)
	var log: Array = []      # what the relay would have kept
	var answers: Array = []  # reaction answers, host's decider -> the wire -> guest's decider
	var answer_log: Array = []   # every answer, in order: what the relay would replay to a rejoiner
	if prompted:
		host.reaction_decider = func(_r, _v, _t, _c) -> bool:
			_asked += 1
			var yes: bool = _asked % 3 != 0   # refuse every third, so a "no" is exercised
			if not yes:
				_said_no += 1
			answers.append(wire(Coop.reaction(yes)))
			answer_log.append(yes)
			return yes
		guest.reaction_decider = func(_r, _v, _t, _c) -> bool:
			check(not answers.is_empty(), "seed %d: an answer was there when the guest asked" % sd)
			return bool(answers.pop_front()["yes"]) if not answers.is_empty() else true
	var intents := 0
	var drift := false
	while not host.is_over() and host.round_num < 30 and not drift:
		var h = host.current()
		host.begin_turn()
		guest.begin_turn()
		if h.is_dead() or h.is_stable():
			host.end_turn(); guest.end_turn()
			continue
		if h.team == "foe" or h.is_down():
			AI.take_turn(host, h)
			AI.take_turn(guest, Coop.find(guest, h.id))
			host.end_turn(); guest.end_turn()
			if Coop.state_hash(host) != Coop.state_hash(guest):
				drift = true
			continue
		for i in choose_turn(host, h):   # the owning peer presses; both apply
			var m := wire(i)
			if Coop.apply(host, m).get("error", "") != "":
				continue   # the resolver refused it: nothing changed, nothing to send
			log.append(m)
			var key: String = String(m.get("verb", m["t"]))
			_seen[key] = int(_seen.get(key, 0)) + 1
			Coop.apply(guest, m)
			intents += 1
			if host.is_over():
				break
			if Coop.state_hash(host) != Coop.state_hash(guest):
				drift = true
				printerr("  seed %d drifted on %s" % [sd, JSON.stringify(m)])
				break
	check(not drift, "seed %d: no drift over %d intents, %d rounds" % [sd, intents, host.round_num])
	check(host.is_over(), "seed %d: fight resolved (%s)" % [sd, host.outcome()])
	# The late joiner: setup + log, nothing else.
	var late = build(setup)
	if prompted:
		late.reaction_decider = func(_r, _v, _t, _c) -> bool:
			return bool(answer_log.pop_front()) if not answer_log.is_empty() else true
	var k := 0
	while not late.is_over():
		var h = late.current()
		late.begin_turn()
		if h.is_dead() or h.is_stable():
			late.end_turn()
			continue
		if h.team == "foe" or h.is_down():
			AI.take_turn(late, h)
			late.end_turn()
			continue
		if k >= log.size():
			break   # a hero's turn and nothing logged yet: this is where a rejoiner waits
		while k < log.size():
			var m: Dictionary = log[k]
			k += 1
			Coop.apply(late, m)
			if m["t"] == "end_turn" or late.is_over():
				break
	check(Coop.state_hash(late) == Coop.state_hash(host), "seed %d: rejoin replays to the same state" % sd)

# A hero's turn as a list of intents: step toward the nearest foe, then every
# verb the bar would offer that has a legal target, then end. The intents are
# only *chosen* here — lockstep_fight applies them, host first, and drops the
# ones the resolver refuses. Wide rather than clever: the point is to push as
# many verbs through the codec as possible.
func choose_turn(cb, h) -> Array:
	var out: Array = []
	var foes: Array = cb.enemies_of(h)
	if not foes.is_empty() and h.econ["move_left"] > 0:
		var near = foes[0]
		for f in foes:
			if Hex.distance(h.pos, f.pos) < Hex.distance(h.pos, near.pos):
				near = f
		var best: Vector2i = h.pos
		for hx in cb.move_field(h):
			if Hex.distance(hx, near.pos) < Hex.distance(best, near.pos):
				best = hx
		if best != h.pos:
			out.append(Coop.move(h, best))
	var verbs: Array = cb.available(h)
	verbs.reverse()   # spells and class features before the basic attack, so they get the action
	for v in verbs:
		var t = pick_target(cb, h, v)
		if t == null and v.get("targeting", "self") != "self":
			continue
		out.append(Coop.perform(h, v, t))
	out.append({"t": "end_turn", "hero": h.id})
	return out

func pick_target(cb, h, v: Dictionary):
	match v.get("targeting", "self"):
		"enemy", "ally":
			var want := int(v.get("targets", 1))
			var picked: Array = []
			for c in cb.combatants:
				if cb.legal_target(h, v, c):
					picked.append(c)
					if picked.size() == want:
						break
			if picked.is_empty():
				return null
			return picked[0] if want == 1 else picked
		"direction":
			for d in Hex.DIRS:
				var wedge: Array = Hex.cone(h.pos, d, int(v.get("radius", 2)))
				if cb.enemies_of(h).any(func(c): return c.pos in wedge):
					return d
			return null
		"hex", "line":
			for c in cb.enemies_of(h):
				if cb.legal_area(h, v, c.pos):
					return c.pos
			return null
		"corner":
			for c in cb.enemies_of(h):
				for k in 6:
					if cb.legal_area(h, v, Hex.corner(c.pos, k)):
						return Hex.corner(c.pos, k)
			return null
	return null

# A guest levels their hero on the real level-up screen, against a mirrored
# copy; the steps it records, sent as JSON, make the host's copy identical.
func guest_levelup() -> void:
	var mine = Presets.ilsa()
	mine.xp = Leveling.xp_for_level(4)
	var theirs = CharacterSave.from_dict(CharacterSave.to_dict(mine))   # the host's real one
	check(Leveling.can_level_up(mine), "levelup: the copy has a level waiting")
	var overlay = load("res://scenes/creator/levelup.tscn").instantiate()
	var steps: Array = []
	overlay.persist = false
	overlay.on_step = func(step: Dictionary): steps.append(step)
	root.add_child(overlay)
	overlay.set_character(mine)
	overlay.commit()
	var picked := 0
	for _round in 6:   # a choice can open another (a subclass, its features): go until none is left
		if Leveling.pending(mine).is_empty():
			break
		for p in Leveling.pending(mine):
			var opts: Array = Creator.options_for(p, mine.sheet(), [])
			for i in mini(Creator.pick_count(p), opts.size()):
				overlay._pick(p, String(opts[i]["id"]))
				picked += 1
	check(Leveling.can_finalize(mine), "levelup: every choice made on the copy (%d picks, %s left)" % [picked,
		str(Leveling.pending(mine).map(func(p): return p["key"]))])
	var done := [false]   # a lambda copies a bool; it shares an Array
	overlay.finished.connect(func(_ok): done[0] = true)
	overlay._on_confirm()
	check(done[0], "levelup: the screen finished")
	overlay.queue_free()
	var m := wire(Coop.levelup(mine.id, steps))
	check(m["steps"].size() == 1 + picked, "levelup: %d steps crossed the wire" % m["steps"].size())
	for step in m["steps"]:   # what scenes/world/world.gd's _apply_guest_levelup does
		match String(step["op"]):
			"add_level": Leveling.add_level(theirs)
			"decide": Leveling.decide(theirs, String(step["key"]), Coop.intify(step["decision"]))
	check(theirs.level() == 4 and mine.level() == 4, "levelup: both copies are level 4")
	check(CharacterSave.to_dict(theirs) == CharacterSave.to_dict(mine), "levelup: the host's sheet equals the guest's")

func test_intify() -> void:
	var d = Coop.intify(JSON.parse_string(JSON.stringify({"a": 3, "b": 2.5, "c": [1, 2, {"d": 7}], "e": "x"})))
	check(d["a"] is int and d["a"] == 3, "intify: whole floats become ints")
	check(d["b"] is float and d["b"] == 2.5, "intify: real floats stay")
	check(d["c"][2]["d"] is int, "intify: nested")
	check(d["e"] == "x", "intify: strings untouched")

# --- the party that crossed the wire -----------------------------------------
#
# Lockstep's oldest assumption, and the one nothing above can check: the HOST
# builds its fight from the party object the road has been playing, and the
# guest builds the same fight from that party's JSON. Every check further up
# builds both sides with Coop.party_from(), so anything CharacterSave quietly
# drops is dropped identically on both and stays invisible — while in a real
# room it would be two different boards before a die is rolled, which is a
# desync with nothing to reconcile (#132).
#
# So: one party per class, three species deep, every choice the build opens
# answered, hit points spent and a spell list prepared — then one fight built
# each way, and the same state hash out of both.
func test_the_wire_keeps_a_party_whole() -> void:
	var sd := 0
	for cid in Catalog.index("classes.json").keys():
		sd += 1
		var party = Party.new()
		var i := 0
		for species in ["human", "elf", "dwarf"]:
			party.add_member(_grown(String(cid), species, 5, i))
			i += 1
		party.gold = 425
		party.stash_add("potion-of-healing", 2, true)
		party.stash_add("potion-of-healing", 1, false)   # the same item, unidentified: a second stack
		var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal")
		spec["seed"] = sd
		var setup := wire(Coop.setup_for(sd, spec, party))
		for ch in party.party_characters():
			var there := CharacterSave.to_dict(ch)
			var back := CharacterSave.to_dict(CharacterSave.from_dict(there))
			check(back == there, "%s: %s survives the wire whole" % [cid, ch.id])
		var mirrored = Coop.party_from(setup)
		check(mirrored.gold == party.gold and mirrored.stash == party.stash,
			"%s: the purse and the shelf cross too" % cid)
		check(Coop.state_hash(build_with(party, setup)) == Coop.state_hash(build(setup)),
			"%s: the host's party and the guest's build the same fight" % cid)

# A character of `cid` at `levels`, with every choice the build opens answered
# the way the creator would answer it, and then roughed up the way a day on the
# road roughs one up — hit points gone, a pool spent, a level's worth of XP
# banked. All of it is state CharacterSave has to carry.
func _grown(cid: String, species_id: String, levels: int, idx: int):
	var ch = Character.new()
	ch.id = "%s-%s-%d" % [cid, species_id, idx]
	ch.cname = "%s %d" % [Creator.humanize(cid), idx]
	ch.species_id = species_id
	ch.background_id = "soldier"
	ch.base_abilities = {"str": 15, "dex": 14, "con": 14, "int": 12, "wis": 13, "cha": 10}
	for _n in levels:
		ch.add_level(cid, -1)
	for _round in 8:            # a choice can open another (a subclass, its features)
		var pending: Array = ch.sheet().pending
		if pending.is_empty():
			break
		for p in pending:
			var picks: Array = _autopick(p, ch.sheet())
			if not picks.is_empty():
				ch.decide(String(p["key"]), Creator.decision_for(p, picks))
	ch.xp = Leveling.xp_for_level(levels)
	ch.hp_current = maxi(1, ch.sheet().max_hp - 3 - idx)
	for pid in ch.pools:
		ch.pools[pid] = 0       # every per-rest use spent
		break
	# A caster who has already cast today. This is the one the wire used to drop.
	var slots: Array = ch.sheet().spellcasting.get("slots", [])
	for i in slots.size():
		ch.slots_used.append(1 if int(slots[i]) > 1 else 0)
	return ch

# The creator's own toggle, pressed until the choice is full: an ASI that takes
# the same ability twice and a skill list that will not are both answered the
# way a player answering them would be.
func _autopick(p: Dictionary, sheet) -> Array:
	var picks: Array = []
	var opts: Array = Creator.options_for(p, sheet, picks)
	for _k in Creator.pick_count(p):
		for o in opts:
			var t: Array = Creator.toggle(p, picks, String(o["id"]))
			if t.size() > picks.size():
				picks = t
				break
		opts = Creator.options_for(p, sheet, picks)
	return picks

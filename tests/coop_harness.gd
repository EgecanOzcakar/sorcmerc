# The lockstep co-op harness the co-op tests share (not a test: the runner
# globs test_* and drive_*). Two peers build the same Combat from the same
# setup, a hero's turn is chosen as intents, every intent crosses the wire as
# JSON and is applied on both, and Coop.state_hash must agree after each one —
# which is scenes/main.gd's co-op loop without the socket.
#
#   Harness.build(setup)                   # a peer's Combat, from the setup alone
#   Harness.wire(d)                        # d as the other peer receives it
#   Harness.choose_turn(cb, hero)          # a turn, as intents: move, every verb, end
#   Harness.lockstep(party, spec, seed)    # a whole fight on two peers -> a report
extends RefCounted

const AI = preload("res://core/ai.gd")
const Coop = preload("res://core/coop.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")

# The same steps scenes/main.gd takes, so the guest builds what the host built.
static func build(setup: Dictionary):
	return build_with(Coop.party_from(setup), setup)

static func build_with(party, setup: Dictionary):
	var sp: Dictionary = setup["spec"]
	var sd := int(setup["seed"])
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), sd)
	var cb = Encounter.build(sp, party.to_combatants(Encounter.starts_for(sp, board, sd)), board)
	cb.party = party
	return cb

# Over the wire and back: what the other peer actually receives.
static func wire(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))

# A whole fight on two peers, no prompts: {drift, drifted_on, intents, rounds,
# over, seen: {verb id or intent kind: count}}. `drift` is the first intent (or
# foe turn) after which the two hashes differed.
static func lockstep(party, spec: Dictionary, sd: int, max_rounds := 30) -> Dictionary:
	var setup := wire(Coop.setup_for(sd, spec, party))
	var host = build(setup)
	var guest = build(setup)
	var out := {"drift": Coop.state_hash(host) != Coop.state_hash(guest), "drifted_on": "setup",
		"intents": 0, "rounds": 0, "over": false, "seen": {}}
	while not out["drift"] and not host.is_over() and host.round_num < max_rounds:
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
				out["drift"] = true
				out["drifted_on"] = "%s's turn (AI)" % h.id
			continue
		for i in choose_turn(host, h):
			var m := wire(i)
			if Coop.apply(host, m).get("error", "") != "":
				continue
			var key: String = String(m.get("verb", m["t"]))
			out["seen"][key] = int(out["seen"].get(key, 0)) + 1
			Coop.apply(guest, m)
			out["intents"] = int(out["intents"]) + 1
			if Coop.state_hash(host) != Coop.state_hash(guest):
				out["drift"] = true
				out["drifted_on"] = JSON.stringify(m)
				break
			if host.is_over():
				break
	out["rounds"] = host.round_num
	out["over"] = host.is_over()
	return out

# A hero's turn as a list of intents: step toward the nearest foe, then every
# verb the bar would offer that has a legal target, then end. The intents are
# only *chosen* here — lockstep_fight applies them, host first, and drops the
# ones the resolver refuses. Wide rather than clever: the point is to push as
# many verbs through the codec as possible.
static func choose_turn(cb, h) -> Array:
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

static func pick_target(cb, h, v: Dictionary):
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


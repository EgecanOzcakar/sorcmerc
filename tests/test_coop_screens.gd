# Two REAL combat screens, one process, no relay: the host's scenes/main.tscn and
# the guest's, wired to each other through a stand-in for tools/coop-relay that
# obeys the same rules the Worker does (stamp `from`, a host-only setup cuts the
# log, a hero's presses come only from its owner, the ephemeral kinds are
# forwarded and never logged). Then a robot presses buttons on whichever peer
# owns the hero that is up, exactly as tests/drive_coop.gd does against the real
# relay — and the fight has to come out the same on both screens.
#
#   godot --headless --path . -s tests/test_coop_screens.gd
#
# Why this exists next to tests/test_coop.gd: that one drives two Combat objects
# straight, through Coop.apply(). It cannot see anything scenes/main.gd itself
# decides — and the screen decides plenty. #132's desync was one of those: the
# host opened the fight with a surprise round its map had already rolled
# (`scouted_ahead`) and the guest, who is told the seed, the spec and the party
# but was never told THAT, rolled its own Stealth check and opened an ordinary
# one. Same seed, same party, two different fights from the first turn.
#
# tools/coop_smoke.sh remains the end-to-end proof over a real socket. This is
# the part of it that can run in CI, every pull request, in a few seconds.
extends SceneTree

const Coop = preload("res://core/coop.gd")
const Hex = preload("res://core/hex.gd")

const MAX_PRESSES := 500
const MAX_FRAMES := 6000

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# --- the relay, in memory ---------------------------------------------------

# tools/coop-relay/worker.js, minus the Durable Object: one room, two seats, a
# log that a setup cuts back, and messages that reach the other seat only.
class Relay extends RefCounted:
	const EPHEMERAL := ["hover", "map", "world", "visit", "levelup"]
	var log: Array = []
	var owners: Dictionary = {}
	var inbox := {"host": [], "guest": []}

	func say(from: String, msg: Dictionary) -> void:
		msg = JSON.parse_string(JSON.stringify(msg))   # the wire: ints become floats, objects copies
		msg["from"] = from
		match String(msg.get("t", "")):
			"setup":
				if from != "host":
					return
				owners = msg.get("owners", {})
				log = []
			"swap", "go":
				if from != "host":
					return
			"perform", "move":
				if String(owners.get(msg.get("hero", ""), "")) != from:
					return
		var other := "guest" if from == "host" else "host"
		if not EPHEMERAL.has(String(msg.get("t", ""))):
			log.append(msg)
		inbox[other].append(msg)

	# What a socket is handed the moment it connects.
	func replay_for(role: String) -> void:
		inbox[role].append({"t": "replay", "log": log.duplicate(true)})

# core/coop.gd's Link, over the Relay above instead of a WebSocketPeer. Same
# surface scenes/main.gd uses: send/take/pump/open/other_here/close.
class FakeLink extends RefCounted:
	var role: String
	var code := "TESTRM"
	var relay
	var arrivals := 1
	var world_pending: Dictionary = {}
	var map_latest: Dictionary = {}
	var visit_latest: Dictionary = {}
	var owners_latest: Dictionary = {}

	func _init(r, as_role: String) -> void:
		relay = r
		role = as_role

	func send(msg: Dictionary) -> void:
		relay.say(role, msg)

	func open() -> bool:
		return true

	func other_here() -> bool:
		return true

	func close() -> void:
		pass

	func pump() -> void:
		var keep: Array = []
		for m in relay.inbox[role]:
			match String(m.get("t", "")):
				"world":
					world_pending = m["save"]
					owners_latest = m.get("owners", {})
				"map":
					map_latest = m
				"visit":
					visit_latest = m
				_:
					keep.append(m)
		relay.inbox[role] = []
		_taken.append_array(keep)

	var _taken: Array = []

	func take() -> Array:
		pump()
		var out := _taken
		_taken = []
		return out

# --- one fight, two screens -------------------------------------------------

func _init() -> void:
	OS.set_environment("SORCMERC_FAST", "1")
	for sd in [11, 23, 37]:
		await one_fight(sd, {})
	# #132: the two ways the road opens a fight the guest is never told about.
	# Either one used to give the peers different first rounds.
	# Seed 21 is one whose own Stealth check FAILS, so a guest left to roll it
	# opens an ordinary fight where the host opens an unseen one — the two
	# halves of #132 that only differ when the dice disagree.
	await one_fight(21, {"scouted_ahead": true})
	await one_fight(53, {"forced_ambush": true})
	print("test_coop_screens: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func one_fight(sd: int, host_flags: Dictionary) -> void:
	OS.set_environment("SORCMERC_SEED", str(sd))
	var relay = Relay.new()
	var host = await _peer(relay, "host", host_flags)
	var guest = await _peer(relay, "guest", {})
	Coop.link = null
	Coop.split = {}
	var label := "seed %d%s" % [sd, "" if host_flags.is_empty() else " (%s)" % ",".join(host_flags.keys())]

	var presses := 0
	var frames := 0
	while frames < MAX_FRAMES and presses < MAX_PRESSES:
		await process_frame
		frames += 1
		if host.cb != null and host.cb.is_over() and guest.cb != null and guest.cb.is_over():
			break
		for p in [host, guest]:
			if _ready_to_press(p):
				_act(p, presses)
				presses += 1
	for _i in 20:            # let the last messages land on both ends
		await process_frame

	check(host.cb != null and host.cb.is_over(), "%s: the host's fight resolved" % label)
	check(guest.cb != null and guest.cb.is_over(), "%s: the guest's fight resolved" % label)
	var hl := "\n".join(host.cb.log) if host.cb != null else ""
	var gl := "\n".join(guest.cb.log) if guest.cb != null else ""
	check(not hl.contains("DESYNC"), "%s: the host saw no desync" % label)
	check(not gl.contains("DESYNC"), "%s: the guest saw no desync" % label)
	if host.cb != null and guest.cb != null:
		check(Coop.state_hash(host.cb) == Coop.state_hash(guest.cb),
			"%s: both screens end in the same state" % label)
		check(host.cb.outcome() == guest.cb.outcome(),
			"%s: one verdict (%s / %s)" % [label, host.cb.outcome(), guest.cb.outcome()])
		check(host.cb.round_num == guest.cb.round_num,
			"%s: the same number of rounds (%d / %d)" % [label, host.cb.round_num, guest.cb.round_num])
		# #132 itself: how the fight OPENED, which is what the two flags above
		# decide and what the setup now carries.
		check(host.cb.unseen == guest.cb.unseen,
			"%s: both opened %s" % [label, "unseen" if host.cb.unseen else "seen"])
		check(host.cb.ambushed == guest.cb.ambushed,
			"%s: both opened %s" % [label, "ambushed" if host.cb.ambushed else "on even terms"])
		# #134: the dead are dead on both screens.
		var hd: Array = host.cb.combatants.filter(func(c): return c.is_dead()).map(func(c): return c.id)
		var gd: Array = guest.cb.combatants.filter(func(c): return c.is_dead()).map(func(c): return c.id)
		check(hd == gd, "%s: the same dead (%s / %s)" % [label, str(hd), str(gd)])
	host.queue_free()
	guest.queue_free()
	await process_frame

# One peer's combat screen, with a link already in hand — scenes/main.gd reads
# Coop.link in _ready(), so it is set for exactly that long.
func _peer(relay, role: String, flags: Dictionary):
	relay.replay_for(role)
	Coop.link = FakeLink.new(relay, role)
	var m = load("res://scenes/main.tscn").instantiate()
	for k in flags:
		m.set(String(k), flags[k])
	root.add_child(m)
	await process_frame   # _ready() reads Coop.link; it must still be this peer's
	return m

# --- the robot (tests/drive_coop.gd's, for whichever screen is waiting) ------

func _ready_to_press(main) -> bool:
	if main.cb == null or main.cb.is_over() or main._busy or main._coop_waiting:
		return false
	if main._mode == "split":
		return true    # the host's "who plays whom", then Begin
	if main._mode == "deploy":
		return main._coop.role == "host"
	var cur = main.cb.current()
	return cur != null and cur.team == "party" and main._mine(cur)

func _act(main, presses: int) -> void:
	if main._mode in ["cone", "target", "area"]:
		_board_click(main)
	elif main._mode == "idle" and presses % 3 == 0 and main.cb.current().econ["move_left"] > 0:
		_move_click(main)
	else:
		var btns := _buttons(main)
		if not btns.is_empty():
			_press(btns, presses)

func _board_click(main) -> void:
	var cb = main.cb
	var h = cb.current()
	if main._mode == "cone":
		var foes: Array = cb.enemies_of(h)
		if foes.is_empty():
			main.board_cancel()
		else:
			main.board_hex_clicked(foes[0].pos)
		return
	for c in cb.combatants:
		if main._valid_target(h, c):
			main.board_hex_clicked(c.pos)
			return
	main.board_cancel()

func _move_click(main) -> void:
	var cb = main.cb
	var h = cb.current()
	var foes: Array = cb.enemies_of(h)
	if foes.is_empty():
		return
	var goal: Vector2i = h.pos
	for hx in cb.move_field(h):
		if Hex.distance(hx, foes[0].pos) < Hex.distance(goal, foes[0].pos):
			goal = hx
	if goal != h.pos:
		main.board_hex_clicked(goal)

func _name(b: Button) -> String:
	var tip := String(b.tooltip_text)
	return tip.get_slice("\n", 0) if tip != "" else String(b.text)

func _buttons(main) -> Array:
	var out: Array = []
	for b in main._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion() and not b.disabled:
			out.append(b)
	return out

func _press(btns: Array, presses: int) -> void:
	var wanted := ["Attack", "Sacred Flame", "Attack", "Cure Wounds", "Second Wind", "Attack", "Dodge", "End turn"]
	var verb: String = wanted[presses % wanted.size()]
	var pick: Button = null
	for b in btns:
		if verb in _name(b):
			pick = b
			break
	if pick == null:
		pick = btns[-1]   # End turn / Begin / Begin the ambush sits last
	pick.pressed.emit()

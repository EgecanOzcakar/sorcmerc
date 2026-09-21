# Co-op spike (docs/spike-coop.md). Two players, one party, one fight: each hero
# is owned by one peer, and the peer whose hero is up acts while the other
# watches. Nothing here is engine state — this is the seam between a
# scenes/main.gd press and the wire.
#
# Lockstep: both peers build the identical Combat from the same setup (seed,
# encounter spec, party) and apply the same intents in the same order, so the
# only things that cross the wire are the handful of calls main.gd already
# makes — perform / move_to / end_turn / a deployment swap — as small JSON.
# Foe turns run core/ai.gd on both sides from the shared rng. `state_hash`
# after every end_turn is how a drift would be caught; a mismatch is a bug in
# determinism somewhere, not something to reconcile.
#
# The relay (tools/coop-relay) is a dumb pipe with a memory: it appends every
# message to the room's log and sends the whole log to anyone who connects,
# so a fresh join and a rejoin are the same thing — rebuild from the setup and
# replay.
extends RefCounted

const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O/1/I to read out loud
const CharacterSave = preload("res://core/character_save.gd")
const Party = preload("res://core/party.gd")
const WorldSave = preload("res://core/world_save.gd")
const BugReport = preload("res://core/bug_report.gd")   # the build stamp: both peers must run the same game
const PartyOpinion = preload("res://core/party_opinion.gd")
const Callings = preload("res://core/callings.gd")

# Where tools/coop-relay is deployed. SORCMERC_RELAY overrides it for one run
# (a local `wrangler dev` is ws://127.0.0.1:8787). Not a secret: a public
# endpoint that relays only what a room code lets you into.
const RELAY_URL := "wss://sorcmerc-coop-relay.egecanozcakar.workers.dev"

# The session: one link for the whole run, from the lobby (scenes/game/game.gd)
# through every fight the host's world puts up. Null is single player.
static var link = null
# The host's choice of who plays whom, hero id -> "host" | "guest", kept across
# fights so it is asked once. A hero not in it alternates (setup_for).
static var split := {}

static func relay_url() -> String:
	var env := OS.get_environment("SORCMERC_RELAY")
	return env if env != "" else RELAY_URL

static func room_code() -> String:
	var s := ""
	for i in 6:
		s += ALPHABET[randi() % ALPHABET.length()]
	return s

static func valid_code(code: String) -> bool:
	if code.length() != 6:
		return false
	for ch in code:
		if not ALPHABET.contains(ch):
			return false
	return true

# A link from the env var, for the bare combat scene and the headless drivers
# (SORCMERC_COOP=host | CODE | host:CODE — see scenes/main.gd); null without it.
static func from_env():
	var room := OS.get_environment("SORCMERC_COOP")
	if room == "":
		return null
	var role := "host" if room.begins_with("host") else "guest"
	var code := room.trim_prefix("host:") if room != "host" else room_code()
	return Link.new(relay_url(), code, role)

# --- setup: what the guest needs to build the same fight -------------------

# Who plays whom: the host's `split` where it has said, otherwise alternating
# in party order (host, guest, host, ...) so neither waits through two friendly
# turns in a row more often than initiative makes them anyway.
static func owners_for(party) -> Dictionary:
	var owners := {}
	var i := 0
	for ch in party.party_characters():
		owners[ch.id] = split.get(ch.id, "host" if i % 2 == 0 else "guest")
		i += 1
	return owners

# Whether this peer plays `id` — on the road as in the fight. Always yes in
# single player.
static func mine(party, id: String) -> bool:
	return link == null or owners_for(party).get(id, "host") == link.role

# Lockstep needs the same code on both ends: same game build, same engine.
static func build_stamp() -> String:
	return "%s / Godot %s" % [BugReport.version(), Engine.get_version_info()["string"]]

# JSON has no ints. Anything that came over the wire and is a whole number
# goes back to being one, so `%d`, `range()` and `int == float` all behave.
static func intify(v):
	if v is float and v == floorf(v):
		return int(v)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = intify(v[k])
		return d
	if v is Array:
		return v.map(intify)
	return v

# `opening` is how the host's screen is about to START this fight — see
# scenes/main.gd's _opening(). Issue #132: the seed, the spec and the party
# build the same BOARD on both ends, but the first round is decided by three
# flags that live on the combat screen rather than in the encounter, and the
# road sets them on the host alone. A scouted node opened unseen for the host
# while the guest rolled its own Stealth check and opened an ordinary fight; a
# camp ambush gave the host's foes a free round the guest never gave them.
# Same seed, same party, two different fights from turn one — and lockstep has
# nothing to reconcile with, so every hash after it mismatched.
static func setup_for(seed: int, spec: Dictionary, party, opening := {}) -> Dictionary:
	assert(seed > 0, "seed 0 means 'roll one from the clock' — the peers would differ")
	var roster: Array = []
	for ch in party.roster:
		roster.append(CharacterSave.to_dict(ch))
	# T2 fix round 1: relations now feed the fight itself (shoulder_bonus,
	# bicker_penalty, rally all read party.relations off the Combatant's team),
	# so the guest needs the host's copy or its rolls draw from the rng in a
	# different order — a rally alone burns an extra d20 the host's side never
	# spent. Callings aren't read mid-fight, but they ride along the same way
	# so the guest's party page shows what the host's does.
	return {"t": "setup", "seed": seed, "spec": spec, "owners": owners_for(party), "build": build_stamp(),
		"opening": opening,
		"party": {"roster": roster, "active": Array(party.active), "gold": party.gold,
			"stash": party.stash.duplicate(true), "relations": PartyOpinion.to_dict(party),
			"callings": Callings.to_dict(party)}}

static func party_from(setup: Dictionary):
	var pd: Dictionary = setup["party"]
	var party = Party.new()
	for cd in pd["roster"]:
		var ch = CharacterSave.from_dict(cd)
		if ch != null:
			party.roster.append(ch)
	party.active.assign(pd["active"])
	party.gold = int(pd.get("gold", 0))
	for e in pd.get("stash", []):
		party.stash_add(String(e["item_id"]), int(e.get("quantity", 1)), bool(e.get("identified", true)))
	PartyOpinion.from_dict(party, pd.get("relations", {}))
	Callings.from_dict(party, pd.get("callings", {}))
	return party

# --- intents ----------------------------------------------------------------

static func perform(h, v: Dictionary, target) -> Dictionary:
	var i := {"t": "perform", "hero": h.id, "verb": String(v["id"])}
	if target is Object:
		i["c"] = target.id
	elif target is Vector2i:
		i["hex"] = [target.x, target.y]
	elif target is Array and not target.is_empty() and target[0] is Vector2i:   # a corner
		i["hexes"] = target.map(func(h): return [h.x, h.y])
	elif target is Array:
		i["cs"] = target.map(func(c): return c.id)
	return i

static func move(h, dest: Vector2i) -> Dictionary:
	return {"t": "move", "hero": h.id, "hex": [dest.x, dest.y]}

# Sent after cb.end_turn(): the hash is of the state the other peer must be in
# once it has applied this.
static func end_turn(cb) -> Dictionary:
	return {"t": "end_turn", "hash": state_hash(cb)}

static func swap(a, b) -> Dictionary:
	return {"t": "swap", "a": a.id, "b": b.id}

# The answer to a reaction prompt, from the reactor's owner. Consumed in order:
# both peers reach the same prompts in the same order.
static func reaction(yes: bool) -> Dictionary:
	return {"t": "reaction", "yes": yes}

# What the acting peer is pointing at — the hex under the cursor and the verb
# in hand, so the watcher sees the swing coming. Forwarded by the relay, never
# logged.
static func hover(hex: Vector2i, verb: Dictionary) -> Dictionary:
	return {"t": "hover", "hex": [hex.x, hex.y], "verb": String(verb.get("id", ""))}

# --- the road (scenes/world/world.gd) ---------------------------------------
#
# The host's map, mirrored: the whole save when the guest arrives and whenever
# the host autosaves (a fight banked, a town visited — anything structural),
# and between those a small delta twice a second: the clock and where every
# party stands. The guest's map does not tick; it is drawn from these. Both
# are forwarded by the relay and never logged.
static func world_full(world, party, story) -> Dictionary:
	return {"t": "world", "save": WorldSave.to_dict(world, party, story), "owners": owners_for(party)}

# The settlement the host is in, as the host's screen has it: the page, the
# counter, the market dict (minus the settlement object — its id goes) and
# the purse and shelf, which move on every buy without an autosave.
static func visit(world_screen) -> Dictionary:
	if world_screen._visit.is_empty():
		return {"t": "visit", "closed": true}
	var m: Dictionary = world_screen._visit.duplicate(true)
	var s = m["settlement"]
	m.erase("settlement")
	return {"t": "visit", "sid": s.id, "page": world_screen._visit_page, "tab": world_screen._market_tab,
		"m": m, "gold": world_screen.party.gold, "stash": world_screen.party.stash.duplicate(true)}

# A level the guest took on their own hero, as the steps the level-up screen
# made on their mirrored copy; the host makes the same steps on the real one.
static func levelup(hero_id: String, steps: Array) -> Dictionary:
	return {"t": "levelup", "hero": hero_id, "steps": steps}

static func map_delta(world) -> Dictionary:
	var at := {}
	for p in world.parties:
		at[p.id] = [p.position.x, p.position.y]
	return {"t": "map", "elapsed": world.clock.elapsed, "paused": world.clock.is_paused(), "at": at}

static func find(cb, id: String):
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

# Replays one intent on this peer's Combat. Returns what the resolver returned
# (perform's result dictionary), or {} for the rest.
static func apply(cb, i: Dictionary) -> Dictionary:
	match String(i["t"]):
		"perform":
			var h = find(cb, String(i["hero"]))
			var target = null
			if i.has("c"):
				target = find(cb, String(i["c"]))
			elif i.has("hex"):
				target = Vector2i(int(i["hex"][0]), int(i["hex"][1]))
			elif i.has("hexes"):
				target = i["hexes"].map(func(h): return Vector2i(int(h[0]), int(h[1])))
			elif i.has("cs"):
				target = i["cs"].map(func(id): return find(cb, String(id)))
			for v in cb.all_verbs(h):
				if String(v["id"]) == String(i["verb"]):
					return cb.perform(h, v, target)
			push_error("coop: %s has no verb %s" % [i["hero"], i["verb"]])
		"move":
			cb.move_to(find(cb, String(i["hero"])), Vector2i(int(i["hex"][0]), int(i["hex"][1])))
		"end_turn":
			cb.end_turn()
		"swap":
			var a = find(cb, String(i["a"]))
			var b = find(cb, String(i["b"]))
			var p: Vector2i = a.pos
			a.pos = b.pos
			b.pos = p
	return {}

# Everything a desync would show up in, cheapest first: the rng state alone
# catches nearly all of them, the rest says where.
static func state_hash(cb) -> int:
	var parts: Array = [cb.rng._state, cb.turn_idx, cb.round_num, cb.zones.size()]
	for c in cb.combatants:
		parts.append([c.id, c.pos, c.hp, c.temp_hp, c.econ, c.statuses.keys(), c.slots, c.init_roll])
	return var_to_str(parts).hash()

# --- the wire ---------------------------------------------------------------

# A WebSocket to one room on the relay. pump() it every frame (scenes/game/
# game.gd does, and so does the combat screen — twice is harmless); what the
# room said lands in `inbox` for whichever screen owns the fight to take().
class Link extends RefCounted:
	var ws := WebSocketPeer.new()
	var role: String
	var code: String
	var inbox: Array = []      # parsed messages, oldest first, not yet taken
	var peers: Array = []      # roles connected right now, per the relay
	var arrivals := 0          # times the other seat went from empty to taken; the host resends the map on each
	var world_pending: Dictionary = {}   # the latest full map save received (guest), until a screen takes it
	var map_latest: Dictionary = {}      # the latest map delta received (guest), until the map applies it
	var visit_latest: Dictionary = {}    # the latest settlement page received (guest), until the map shows it
	var owners_latest: Dictionary = {}   # who plays whom, per the last full save; game.gd copies it into Coop.split
	var _pending: Array = []   # said before the socket opened; sent on the first pump after
	var _url: String
	var _retry_at := 0        # msec; a dropped socket is reopened, and the relay replays what we missed
	var _closed := false
	var _reconnects := 0

	func _init(url: String, room: String, as_role: String) -> void:
		role = as_role
		code = room
		_url = "%s/room/%s?role=%s" % [url.trim_suffix("/"), room, as_role]
		ws.connect_to_url(_url)

	func close() -> void:
		_closed = true
		ws.close()

	func send(msg: Dictionary) -> void:
		msg["from"] = role
		_pending.append(JSON.stringify(msg))
		if open():
			flush()

	func flush() -> void:
		for m in _pending:
			ws.send_text(m)
		_pending.clear()

	func open() -> bool:
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func pump() -> void:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _closed:
			if Time.get_ticks_msec() >= _retry_at:   # a hiccup, a sleep, a relay restart: come back
				_retry_at = Time.get_ticks_msec() + 2000
				_reconnects += 1
				ws = WebSocketPeer.new()
				ws.connect_to_url(_url)
			return
		if open():
			flush()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if not m is Dictionary:
				continue
			match String(m.get("t", "")):
				"peers":
					var was := other_here()
					peers = m["roles"]
					if other_here() and not was:
						arrivals += 1
				"world":
					world_pending = m["save"]
					owners_latest = m.get("owners", {})
				"map":
					map_latest = m
				"visit":
					visit_latest = m
				_:
					if m.get("t", "") == "replay":
						m["reconnect"] = _reconnects > 0   # not the first: whoever is fighting resyncs from it
					inbox.append(m)

	func other_here() -> bool:
		return peers.has("guest" if role == "host" else "host")

	# Everything received since the last take, oldest first.
	func take() -> Array:
		pump()
		var out := inbox
		inbox = []
		return out

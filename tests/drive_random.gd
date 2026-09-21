# tests/drive_random.gd — the robot that has not been told what to do.
#
# Every other drive_*.gd in here walks a script: press this, assert that, press
# the next thing. Between them they cover the paths somebody thought to write
# down — and a run of this game is not a path. It is a few hundred small
# decisions about where to walk, what to buy, whether to charge a band of
# goblins or slip round them, and which spell to burn on the third round of a
# fight that is going badly. The bugs that survive a scripted suite live in the
# joins between those decisions: a market that opened over a card, a clock left
# paused by an overlay nobody closed, a fight that ended while the map was
# already walking again.
#
# So this one decides for itself. It is a monkey with taste: every choice is a
# weighted roll, but the weights are read off the game state the way a player
# reads them. It rests when it is hurt, shops when it is rich, parleys with a
# band it cannot take, browses the notice board because it is in town anyway,
# and aims an area spell at the hex that catches the most foes. It gives orders
# the way a player gives them — a real click on the real map, a real press of a
# real button — never by writing to the model behind them.
#
# Two things keep it a test rather than a demo:
#
#  1. It asserts INVARIANTS, never outcomes. "The party won" is not a fact about
#     this build — the fight is a dice game and it is allowed to lose. "The
#     purse never went negative", "the clock never jumped back further than
#     travel.gd can refund", "nothing was left paused with no way to unpause it"
#     and "something changed in the last three hundred frames" are facts about
#     this build, and every one of them is checked on every frame.
#  2. Every decision comes out of one seeded RNG of its own (core/rng.gd, never
#     the game's own streams, so nothing here can perturb a roll), which means a
#     red run replays exactly. The seed is the first thing it prints and the
#     first thing it prints again when it fails.
#
#   godot --headless --path . -s tests/drive_random.gd
#   SORCMERC_SEED=91 godot --headless --path . -s tests/drive_random.gd   # replay that one
#   SORCMERC_RANDOM_RUNS=20 godot --headless --path . -s tests/drive_random.gd   # a soak
#
# Unseeded it plays a different game every time, which is the point of it.
# tools/run_tests.sh pins SORCMERC_SEED before it gets here, so CI walks one
# fixed session and a red CI is reproducible; a soak is something you point at
# it on purpose, on a branch, before you believe a systems change.
extends SceneTree

const RNG = preload("res://core/rng.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldSave = preload("res://core/world_save.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Party = preload("res://core/party.gd")
const Travel = preload("res://core/travel.gd")
const Ladder = preload("res://core/ladder.gd")
const Callings = preload("res://core/callings.gd")
const Downtime = preload("res://core/downtime.gd")

# One driver frame. The same 0.1 tests/drive_world.gd drives the map with —
# headless deltas are microseconds, so world time has to be handed over by
# hand or nothing on the map ever moves. Long marches are covered by turning
# the game clock up (2x/4x/8x), which is what a player does, rather than by
# taking bigger bites out of the simulation than the game ever takes.
const DT := 0.1
const TICKS := 2200          # driver frames in one session
const WEDGE := 300           # frames of NOTHING changing before we call it stuck
const MAX_ROUNDS := 60       # a fight longer than this is not a fight any more
const TOWN_PATIENCE := 24    # errands in one visit before the player gets bored
const DEPLOY_PATIENCE := 6   # fiddles with the marching order before "just start"
const DRAIN := 1200          # extra frames, past the budget, to finish a fight in progress

# How long the player sits before the next deliberate act, per situation. A
# person is quick inside a fight (the decision was made while the dice were
# rolling), slower in a market, slowest staring at the map.
const THINK_FIGHT := [1, 5]
const THINK_TOWN := [2, 9]
const THINK_MAP := [3, 26]

# Verbs read by what they are for, not by who has them: the bar is built from
# whatever the character happens to own, and this file knows nothing about
# classes. A name that matches nothing at all is still pressed sometimes — that
# is the monkey half, and it is how a verb added next month gets exercised here
# without anybody editing this list.
const HEAL_WORDS := ["Cure Wounds", "Healing Word", "Lay on Hands", "Second Wind",
	"Prayer of Healing", "Goodberry", "Heal", "Channel Divinity"]
const GUARD_WORDS := ["Dodge", "Disengage", "Hide", "Shield", "Sanctuary", "Protection"]
const BROWSE_WORDS := ["Spells", "Bonus actions", "Features", "Help & Shove", "More"]

var screen
var _rng
var _me: Dictionary = {}     # the persona this session is playing

var _fail := 0
var _said := {}              # one line per distinct complaint, however often it recurs
var _seed := 0
var _tick_no := 0
var _acts := 0               # deliberate presses/clicks — the "did anything happen" counter
var _fights := 0
var _in_fight := false
var _saw := {}               # coverage: everything this session actually touched
var _wait := 0               # frames left of the current pause for thought
var _dest = null             # the world point the last order pointed at, or null
var _dest_age := 0
var _ordered_from := Vector2.ZERO   # where the party stood when that order was given
var _town_beats := 0
var _deploy_beats := 0
var _paused_at := -1         # the frame WE paused the clock on, or -1
var _clock0 := 0.0
var _last_clock := -1.0
var _stamp := ""
var _still := 0
var _deeds_seen := 0         # Ladder.renown(), watched for the one direction it may move
var _callings_done := {}     # char_id -> true once their calling was seen done (and its heirloom checked)

func _init() -> void:
	# This process's own autosave slots, so a concurrent godot run cannot clobber
	# them — the same reason, and the same shape, as drive_world/drive_campaign.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	_play()

func _play() -> void:
	var base := int(OS.get_environment("SORCMERC_SEED"))
	if base <= 0:
		base = int(Time.get_unix_time_from_system()) & 0x7FFFFFF
	var runs: int = maxi(1, int(OS.get_environment("SORCMERC_RANDOM_RUNS")))
	for i in runs:
		# Widely spaced rather than base+1: consecutive seeds on an xorshift
		# open with visibly similar streams, and a soak wants twenty different
		# games, not twenty variations on one.
		await _session(base + i * 7919)
	_done()

func fail(msg: String) -> void:
	# Deduped: a broken invariant is usually broken on every one of the next
	# two thousand frames, and two thousand identical lines bury the one line
	# that says which seed to replay.
	_fail += 1
	if _said.has(msg):
		return
	_said[msg] = true
	printerr("  FAIL [seed %d, frame %d]: %s" % [_seed, _tick_no, msg])

# --- one session -------------------------------------------------------------

func _session(sd: int) -> void:
	_seed = sd
	_rng = RNG.new(sd)
	_me = _roll_persona()
	_saw = {}
	_said = {}
	_tick_no = 0
	_acts = 0
	_fights = 0
	_in_fight = false
	_wait = 0
	_dest = null
	_dest_age = 0
	_ordered_from = Vector2.ZERO
	_town_beats = 0
	_deploy_beats = 0
	_paused_at = -1
	_last_clock = -1.0
	_stamp = ""
	_still = 0
	_deeds_seen = 0
	_callings_done = {}
	WorldSave.clear()
	FactionOpinion.reset()
	Ladder.reset()
	# The map's own generators read this (a procedural world, a campaign route).
	# Set per session so a soak gets twenty maps, not one map twenty times.
	OS.set_environment("SORCMERC_SEED", str(sd))

	screen = load("res://scenes/world/world.tscn").instantiate()
	# Which map, before _ready() reads it. Both hand-authored maps carry the
	# same furniture (four-plus settlements, one of them a monster faction,
	# roaming bands, five lairs) at different scales, so either is a fair game.
	screen.world_size = "large" if _chance(30) else "small"
	root.add_child(screen)
	await process_frame
	screen.size = Vector2(1280, 800)
	await process_frame
	if screen.world == null or screen.world.player() == null:
		fail("the map came up with no world to play")
		screen.queue_free()      # a live map left mounted keeps ticking under the next session
		screen = null
		await process_frame
		return
	print("drive_random: seed=%d  map=%s  %s" % [sd, screen.world_size, _persona_line()])
	_clock0 = screen.world.clock.elapsed

	while _tick_no < TICKS:
		screen._process(DT)
		await process_frame
		_tick_no += 1
		_watch()
		_react()

	# The budget ran out. A fight still in progress is not a bug — the session is
	# a fixed number of frames and it is allowed to end anywhere — so the driver
	# plays it out instead of asserting about where the clock stopped. Only a
	# fight that will not end even then is worth a red run.
	var drain := 0
	while screen._combat != null and drain < DRAIN:
		screen._process(DT)
		await process_frame
		drain += 1
		_tick_no += 1
		_react()
	if screen._combat != null:
		fail("a fight would not finish in %d frames of playing it out" % DRAIN)
	_final_checks()
	_report()
	screen.queue_free()
	screen = null
	await process_frame

# --- who is playing ----------------------------------------------------------
#
# Five dials, rolled off the seed, that every weight below reads. They are what
# makes two seeds two different players rather than the same player with
# different dice: a bold, greedy, incurious one charges every band and buys the
# shelf bare; a careful, nosy one parleys, searches for lairs and sleeps at
# every inn. Both are people who exist.

func _roll_persona() -> Dictionary:
	return {
		"bold": _d(100),     # charge, ambush, hunt — versus parley and avoid
		"greed": _d(100),    # buy, sell, steal, loot, take every job
		"care": _d(100),     # rest, heal, guard, retreat while ahead
		"nosy": _d(100),     # open panels, search for lairs, wander off the road
		"fidget": _d(100),   # pause, re-speed, re-zoom, check the pack again
	}

func _persona_line() -> String:
	return "bold %d / greedy %d / careful %d / curious %d / fidgety %d" % [
		_me["bold"], _me["greed"], _me["care"], _me["nosy"], _me["fidget"]]

func _d(sides: int) -> int:
	return _rng.roll_die(sides)

func _chance(pct: int) -> bool:
	return _d(100) <= pct

func _pick(a: Array):
	return a[_d(a.size()) - 1] if not a.is_empty() else null

# A weighted pick over [[weight, thing], ...]; null when nothing has any weight.
func _weighted(rows: Array):
	var total := 0
	for r in rows:
		total += maxi(0, int(r[0]))
	if total <= 0:
		return null
	var roll := _d(total)
	for r in rows:
		roll -= maxi(0, int(r[0]))
		if roll <= 0:
			return r[1]
	return rows[rows.size() - 1][1]

# The pause between deliberate acts. Returns true while the player is still
# thinking, which is how every beat below says "not this frame".
func _hold(span: Array) -> bool:
	if _wait > 0:
		_wait -= 1
		return true
	_wait = span[0] + _d(maxi(1, span[1] - span[0]))
	return false

# --- what is true on every frame, whatever is on screen -----------------------

func _watch() -> void:
	var w = screen.world
	if w == null:
		return fail("the map lost its world")
	var p = w.player()
	if p == null:
		return fail("the player party is no longer on the map")
	var party = screen.party
	if party.gold < 0:
		fail("the purse went negative: %d" % party.gold)
	var r := Ladder.renown()
	if r < _deeds_seen:
		fail("renown went down: %d -> %d" % [_deeds_seen, r])
	_deeds_seen = r
	if party.active.size() > Party.MAX_ACTIVE:
		fail("%d characters are in an active party of %d" % [party.active.size(), Party.MAX_ACTIVE])
	if party.party_characters().is_empty():
		fail("the active party emptied itself mid-run")
	# A calling just done paid its heirloom into the stash (core/callings.gd's
	# complete). Checked the frame it turns done, not forever after — the
	# stash is the player's to sell.
	for id in party.callings:
		if String(party.callings[id]["state"]) == "done" and not _callings_done.has(id):
			_callings_done[id] = true
			_saw["calling:done"] = true
			var item := String(Callings.templates()[party.callings[id]["id"]]["item"])
			if party.stash_count(item) < 1:
				fail("%s's calling is done and its heirloom (%s) is not in the stash" % [id, item])
	for ch in party.party_characters():
		var s: Dictionary = party.summary(ch.id)
		if int(s["hp"]) < 0 or int(s["hp"]) > int(s["max_hp"]):
			fail("%s is at %d/%d hp" % [ch.cname, s["hp"], s["max_hp"]])
		var seen_feats := {}
		for f in ch.feats:
			if seen_feats.has(f):
				fail("%s has %s twice in their feats" % [ch.cname, f])
			seen_feats[f] = true
	# The clock is deliberately NOT monotonic: core/travel.gd pays the party for
	# a good day's road (and for finding a waystone) by winding it back, so
	# "never backwards" is not the invariant — "never backwards by more than the
	# largest saving the game can hand out" is. That still catches a reset to
	# zero, a double-applied saving, and a rewind nobody announced.
	var now: float = w.clock.elapsed
	if _last_clock >= 0.0 and now < _last_clock - Travel.WAYSTONE_SAVED - 1.0:
		fail("the clock jumped back %.0f minutes, past anything travel.gd can refund: %.2f -> %.2f"
			% [_last_clock - now, _last_clock, now])
	_last_clock = now
	var fighting: bool = screen._combat != null
	if fighting and not _in_fight:
		_fights += 1
	_in_fight = fighting
	# Objectives: a bystander (a captive, a carter) is never given a turn.
	if fighting and screen._combat.cb != null and not screen._combat.cb.order.is_empty():
		var cur = screen._combat.cb.current()
		if cur != null and cur.has("bystander"):
			fail("a bystander (%s) was given a turn" % cur.cname)
	# Two screens that own the world cannot both own it.
	if screen._combat != null and not screen._visit.is_empty():
		fail("a market was open while a fight was on")
	if screen._combat != null and not w.clock.is_paused():
		fail("the world clock kept running under a fight")
	if not screen._visit.is_empty() and screen._visit_panel == null:
		fail("a settlement visit is open with no panel to close it")
	if screen._site != null and screen._site_screen == null:
		fail("a delve is in progress with no screen on it")
	# A spent landmark never offers a card.
	if screen._place_open != null and screen._place_open.spent:
		fail("the card is up for a spent landmark: %s" % screen._place_open.sname)
	for s in w.settlements:
		if s.id.begins_with("way-"):
			for l in w.lairs:
				if l.id == s.id.trim_prefix("way-"):
					fail("%s stands on a lair that is still on the map" % s.sname)
	if not screen._visit.is_empty():
		var vs = screen._visit.get("settlement")
		if vs != null and vs.raided_by != "" and not bool(screen._visit.get("battle", false)):
			fail("a raided town's market is not the halved shelf")
	_wedge_check(p)

# The one check that catches a class of bug no assertion can name in advance:
# the game stopped responding to a player who is still pressing things. The
# fingerprint is everything a frame is allowed to change — if none of it moves
# for WEDGE frames, the run is stuck, and the fingerprint itself says where.
func _wedge_check(p) -> void:
	var here := "map"
	var extra := 0
	if screen._combat != null and is_instance_valid(screen._combat):
		here = "fight"
		var cb = screen._combat.cb
		extra = (cb.log.size() * 100 + cb.round_num) if cb != null else 0
	elif not screen._visit.is_empty():
		here = "town:" + screen._visit_page
	elif screen._site_screen != null:
		here = "delve"
	var fp := "%s|%d|%d,%d|%s|%d|%d|%d|%d" % [here, int(screen.world.clock.elapsed),
		int(p.position.x), int(p.position.y), screen.world.clock.is_paused(),
		_acts, _fights, screen.party.gold, extra]
	if fp == _stamp:
		_still += 1
		if _still == WEDGE:
			fail("wedged for %d frames — nothing moved at [%s]" % [WEDGE, fp])
	else:
		_stamp = fp
		_still = 0

# --- what the player does about it -------------------------------------------
#
# Strict priority, because a person has one pair of hands: a card in the face
# comes before a fight, a fight before the town it walked into, the town before
# the road. Everything below is reached only when nothing above it is asking.

func _react() -> void:
	if _cards():
		return
	if screen._combat != null:
		_fight_beat()
		return
	if screen._site_screen != null:
		_delve_beat()
		return
	if screen._spoils_panel != null:
		if _hold(THINK_TOWN):
			return
		_saw["spoils"] = true
		screen._close_spoils()
		_acts += 1
		return
	if not screen._visit.is_empty():
		_town_beat()
		return
	if _overlay_open():
		if _hold(THINK_MAP):
			return
		_close_overlays()
		return
	_map_beat()

# --- the cards that stop everything ------------------------------------------

func _cards() -> bool:
	if is_instance_valid(screen._approach_card):
		if _hold(THINK_MAP):
			return true
		_meet_them()
		return true
	if is_instance_valid(screen._event_card):
		if _hold(THINK_TOWN):
			return true
		_saw["event-card"] = true
		if String(screen._event_card._e.get("id", "")).begins_with("calling-"):
			_saw["calling:card"] = true    # a telling or a resolution: acked like any other
		# The signal, not the plain handler: an outcome card can carry a bound
		# follow-up (the fight an ambush just started), and freeing the card by
		# hand would drop it. Same reason drive_world does it this way.
		screen._event_card.acknowledged.emit()
		_acts += 1
		return true
	if is_instance_valid(screen.story_card):
		if _hold(THINK_TOWN):
			return true
		_saw["story-card"] = true
		if not _press_one(screen.story_card):
			fail("a story beat is up with nothing on it to answer")
		return true
	return false

# D4's approach card: how to meet the band that just closed on us. The one
# decision in the game that most reads a player's character, so it is the one
# most worth reading the persona off. Every option is a real button on the real
# card — its name carries the way, which is how the weights below find it.
func _meet_them() -> void:
	var card = screen._approach_card
	var rows: Array = []
	for b in card.get_children():
		if b is Button and not b.disabled and not b.is_queued_for_deletion():
			var way := String(b.name).get_slice("_", 2)
			rows.append([_way_weight(way), b])
	if rows.is_empty():
		fail("the approach card offered no way to meet them")
		screen._on_approach_chosen("engage")
		return
	var b: Button = _weighted(rows)
	_saw["approach:" + String(b.name).get_slice("_", 2)] = true
	if screen._place_open != null:   # the same card, asked by a landmark: say so in the coverage
		_saw["place:" + String(b.name).get_slice("_", 2)] = true
	_acts += 1
	b.pressed.emit()

func _way_weight(way: String) -> int:
	var fit := int(_health() * 100.0)
	match way:
		"engage": return 20 + _me["bold"] / 2 + fit / 3
		"ambush": return 10 + _me["bold"] / 3 + _me["nosy"] / 3
		"parley": return 10 + (100 - _me["bold"]) / 3
		"avoid":  return 5 + _me["care"] / 3 + (100 - fit) / 2
		"greet":  return 30 + _me["nosy"] / 3
		"pass":   return 20
		# The fireside's courtship (world.gd's _fireside), on the same card: a
		# careful player says yes, anyone else lets it lie.
		"accept":  return 100 if _me["care"] >= 70 else 0
		"decline": return 0 if _me["care"] >= 70 else 100
	return 8   # something new on the card: try it now and then

# --- the fight ----------------------------------------------------------------

func _fight_beat() -> void:
	var fight = screen._combat
	if not is_instance_valid(fight) or not fight.result.is_empty():
		return                     # the world screen is tearing it down this frame
	var cb = fight.cb
	if cb == null:
		return
	if not _saw.has("fight"):
		_saw["fight"] = true
	if is_instance_valid(fight._reaction_card):
		if _hold(THINK_FIGHT):
			return
		_saw["reaction"] = true
		if not _press_one(fight._reaction_card):
			fail("a reaction was asked for with no way to answer it")
		return
	# Deployment first, before the over/busy gate below: a fight can open already
	# decided (an ambush on a party that has nothing left standing), and then the
	# only thing on screen is "Begin the ambush" — which a player presses, and
	# which is the whole way out. Gating it behind is_over() left the robot
	# staring at a one-button screen until its budget ran out.
	if fight._mode == "deploy":
		_deploy_beat(fight)
		return
	if cb.is_over() or fight._busy or fight._advancing:
		return
	if cb.round_num > MAX_ROUNDS:
		# Not a hang — the loop is live, it is just never going to end. Called
		# out and then conceded, so the session carries on and the map gets its
		# defeat path walked instead of the whole run dying here.
		fail("a fight reached round %d without resolving" % cb.round_num)
		fight.result = {"outcome": "Defeat", "xp": 0, "gold": 0, "rounds": cb.round_num}
		return
	var h = cb.current()
	if h == null or h.team != "party":
		return                     # the foes' turn; the screen runs it on its own timer
	if not h.conscious():
		# The acting hero went down DURING their own turn — walked into an
		# opportunity attack, most often. The screen leaves their bar up (they
		# still have an action they can no longer spend), so the only live thing
		# on it is End turn behind its "action unspent!" confirm. A player sees
		# one button and presses it, twice; so does this. Without this branch the
		# robot politely waits for an unconscious character to do something.
		if _hold(THINK_FIGHT):
			return
		_saw["downed-actor"] = true
		if not _press_last(fight):
			fail("%s went down mid-turn and the bar offers no way to end it" % h.cname)
		return
	if _hold(THINK_FIGHT):
		return
	match fight._mode:
		"target": _aim_at_somebody(fight, h)
		"cone": _aim_cone(fight, h)
		"area": _aim_area(fight, h)
		_:
			# Nothing this hero owns can reach anybody from where they stand: so
			# walk, which on this board is a plain click on an empty hex and the
			# first thing a player learns to do. Without this the robot pressed
			# buttons all fight and every melee character swung at air.
			if h.econ["move_left"] > 0 and not _can_reach_anyone(cb, h):
				_walk_closer(fight, h)
			else:
				_pick_verb(fight, h)

# T39's deployment phase: shuffle the marching order a bit, then start. The
# patience cap is the human bit — nobody rearranges four heroes forever.
func _deploy_beat(fight) -> void:
	if _hold(THINK_FIGHT):
		return
	_saw["deploy"] = true
	_deploy_beats += 1
	var btns := _live_buttons(fight._buttons)
	if btns.is_empty():
		fail("the deployment phase came up with no buttons")
		return
	var begin: Button = null
	var swaps: Array = []
	for b in btns:
		if "Begin" in _btn_name(b):
			begin = b
		else:
			swaps.append(b)
	if begin == null:
		fail("the deployment phase has no way to begin the fight")
		return
	_acts += 1
	if not swaps.is_empty() and _deploy_beats < DEPLOY_PATIENCE and _chance(_me["nosy"] / 2):
		_pick(swaps).pressed.emit()
		return
	_deploy_beats = 0
	begin.pressed.emit()

# Can this hero do anything to anybody from where they stand? Asked of the real
# rules — every verb they actually have, against every foe still standing —
# which is the whole difference between a fighter who closes and one who does not.
func _can_reach_anyone(cb, h) -> bool:
	var foes: Array = cb.enemies_of(h).filter(func(c): return c.conscious())
	if foes.is_empty():
		return true                       # nobody to close on; let the bar decide
	for v in cb.available(h):
		var aim := String(v.get("targeting", "self"))
		for c in foes:
			if aim == "enemy" and cb.legal_target(h, v, c):
				return true
			if aim in ["hex", "line"] and cb.legal_area(h, v, c.pos):
				return true
	return false

# The hex within reach that puts them closest to the nearest foe. Clicked, not
# moved: an empty-hex click IS the move order, and that is the path being tested.
func _walk_closer(fight, h) -> void:
	var cb = fight.cb
	var foes: Array = cb.enemies_of(h).filter(func(c): return c.conscious())
	if foes.is_empty():
		_pick_verb(fight, h)
		return
	foes.sort_custom(func(a, b): return _hex_gap(h, a) < _hex_gap(h, b))
	var mark = foes[0]
	var goal: Vector2i = h.pos
	var best := 1 << 30
	for hx in cb.move_field(h):
		var d := int(abs(hx.x - mark.pos.x) + abs(hx.y - mark.pos.y)
			+ abs(hx.x + hx.y - mark.pos.x - mark.pos.y)) / 2
		if d < best:
			best = d
			goal = hx
	if goal == h.pos:
		_pick_verb(fight, h)      # boxed in: spend the turn on something else
		return
	_saw["move"] = true
	_acts += 1
	var from: Vector2i = h.pos
	_click_board(fight, goal)
	# Not "did they reach the hex": a walk can be cut short legitimately, and
	# usually is — an opportunity attack on the way out can drop the walker
	# mid-step. What must never happen is the click being swallowed whole.
	if h.pos == from and h.conscious():
		fail("a click on a hex in %s's own move field moved them nowhere" % h.cname)

# One hero's turn, chosen the way a player chooses it: look at who is hurt, look
# at what is on the bar, press the thing that fits. Nothing here knows a class
# or a spell list — it reads the bar the build actually produced.
func _pick_verb(fight, h) -> void:
	var btns := _live_buttons(fight._buttons)
	if btns.is_empty():
		return
	var cb = fight.cb
	var worst := _worst_ally(cb)
	var mine := float(h.hp) / maxf(1.0, float(h.max_hp))
	var rows: Array = []
	for b in btns:
		rows.append([_verb_weight(_btn_name(b), h, worst, mine), b])
	var pick: Button = _weighted(rows)
	if pick == null:
		pick = btns[btns.size() - 1]
	var name := _btn_name(pick)
	_saw["verb:" + name.get_slice(" ", 0)] = true
	_acts += 1
	pick.pressed.emit()

func _verb_weight(name: String, h, worst: float, mine: float) -> int:
	if name.begins_with("End turn") or name.begins_with("✓ Confirm: End turn"):
		# Never while the action is unspent unless there is genuinely nothing
		# else, and always the moment there is nothing left to spend.
		return 3 if h.econ["action"] > 0 else 400
	if name == "Back":
		return 2
	if _any_word(name, BROWSE_WORDS):
		return 25 + _me["nosy"] / 3        # open the list and look at what is in it
	if _any_word(name, HEAL_WORDS):
		if worst < 0.35:
			return 120 + _me["care"]
		if worst < 0.7:
			return 25 + _me["care"] / 3
		return 4
	if _any_word(name, GUARD_WORDS):
		return 60 + _me["care"] / 2 if mine < 0.35 else 8
	if name.begins_with("Attack") or name.begins_with("Wield"):
		return 45 + _me["bold"] / 3
	if name.begins_with("Dash"):
		return 12
	# Everything else on the bar is this character's own kit — a spell, a
	# feature, a shove. Worth reaching for early, when the slots are still full.
	return 30 + _me["bold"] / 4

# Aiming a single-target verb: heals go to whoever needs one, everything else
# goes to the foe closest to falling over. The click is a real board click.
func _aim_at_somebody(fight, h) -> void:
	var cb = fight.cb
	var heal := _is_heal(fight._tgt_verb)
	var best = null
	var best_score := -1.0
	for c in cb.combatants:
		if not fight._valid_target(h, c):
			continue
		var frac := float(c.hp) / maxf(1.0, float(c.max_hp))
		var score := 0.0
		if heal:
			if c.team != "party":
				continue
			score = 100.0 if c.is_down() else (1.0 - frac) * 10.0
		else:
			score = 10.0 - frac * 5.0 - float(_hex_gap(h, c)) * 0.2
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		# Nothing this verb can legally reach. Backing out is what a player does,
		# and it must always be possible — a targeting mode with no exit is the
		# bug this branch exists to catch.
		_saw["aim-cancel"] = true
		fight.board_cancel()
		_acts += 1
		if fight._mode != "idle":
			fail("cancelling out of %s aiming left the board in %s" % [fight._tgt_verb.get("kind", "?"), fight._mode])
		return
	_saw["aim:" + String(fight._tgt_verb.get("kind", "?"))] = true
	_acts += 1
	_click_board(fight, best.pos)

func _aim_cone(fight, h) -> void:
	var foes: Array = fight.cb.enemies_of(h).filter(func(c): return c.conscious())
	if foes.is_empty():
		fight.board_cancel()
		_acts += 1
		return
	foes.sort_custom(func(a, b): return _hex_gap(h, a) < _hex_gap(h, b))
	_saw["aim:cone"] = true
	_acts += 1
	_click_board(fight, foes[0].pos)

# An area spell is the one place a player really does arithmetic: hover the
# hexes, count who is under each, cast on the best one. So does this — and if
# no hex is legal from here, it backs out rather than milling in aim mode.
func _aim_area(fight, h) -> void:
	var cb = fight.cb
	var v: Dictionary = fight._tgt_verb
	var best := Vector2i(9999, 9999)
	var best_hit := -1
	for c in cb.combatants:
		if not c.conscious():
			continue
		for hx in [c.pos, h.pos]:
			_hover_board(fight, hx)
			var target = fight._board.aim_target(v.get("targeting", "hex"))
			if target == null or not cb.legal_area(h, v, target):
				continue
			var swept: Array = cb.area_hexes(h, v, target)
			var caught := 0
			for other in cb.combatants:
				if other.conscious() and other.pos in swept:
					caught += 1 if other.team != h.team else -2
			if caught > best_hit:
				best_hit = caught
				best = hx
	if best_hit <= 0:
		_saw["aim-cancel"] = true
		fight.board_cancel()
		_acts += 1
		return
	_saw["aim:area"] = true
	_acts += 1
	_hover_board(fight, best)
	_click_board(fight, best)

func _is_heal(v: Dictionary) -> bool:
	return v.has("heal_count") or String(v.get("kind", "")) in ["heal_self", "heal_ally"]

func _hex_gap(a, b) -> int:
	return int(abs(a.pos.x - b.pos.x) + abs(a.pos.y - b.pos.y) + abs(a.pos.x + a.pos.y - b.pos.x - b.pos.y)) / 2

# The worst-off conscious hero, as a fraction of their max. 1.0 when everybody
# is fine, 0.0 when somebody is down.
func _worst_ally(cb) -> float:
	var worst := 1.0
	for c in cb.team_of("party"):
		if c.is_dead():
			continue
		if c.is_down():
			return 0.0
		worst = minf(worst, float(c.hp) / maxf(1.0, float(c.max_hp)))
	return worst

# A real mouse over a real board: hover sets both the hex and the sub-hex point
# a corner-aimed spell reads, exactly as a moving mouse would.
func _hover_board(fight, hx: Vector2i) -> void:
	var m := InputEventMouseMotion.new()
	m.position = fight._board._pix(hx)
	fight._board._gui_input(m)

func _click_board(fight, hx: Vector2i) -> void:
	_hover_board(fight, hx)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = fight._board._pix(hx)
	fight._board._gui_input(e)

# --- the delve ----------------------------------------------------------------

func _delve_beat() -> void:
	if _hold(THINK_TOWN):
		return
	_saw["delve"] = true
	if not _press_one(screen._site_screen):
		fail("the delve screen offered nothing to press")

# --- a settlement -------------------------------------------------------------
#
# In town the player has errands, and the errands are what the weights are: take
# the work, hand in the work, buy what the purse allows, sleep if hurt, and then
# — because nobody browses a market forever — leave.

func _town_beat() -> void:
	if _hold(THINK_TOWN):
		return
	_saw["settlement"] = true
	_saw["town:" + screen._visit_page] = true
	_town_beats += 1
	var panel = screen._visit_panel
	if panel == null:
		return
	var btns := _live_buttons(panel)
	if btns.is_empty():
		fail("a settlement panel came up with no buttons at all")
		screen._close_visit()
		return
	for b in btns:
		if "Seek an audience" in _btn_name(b) and _chance(80):
			_saw["audience"] = true
			_acts += 1
			b.pressed.emit()
			return
	if _downtime_beat(panel):
		return
	var leave: Button = null
	var rows: Array = []
	for b in btns:
		var name := _btn_name(b)
		if name.begins_with("Leave"):
			leave = b
			continue
		rows.append([_town_weight(name), b])
	if _town_beats > TOWN_PATIENCE and leave != null:
		_town_beats = 0
		_acts += 1
		_saw["town:left"] = true
		leave.pressed.emit()
		return
	var pick: Button = _weighted(rows)
	if pick == null:
		if leave == null:
			fail("a settlement panel has no way out of it")
			screen._close_visit()
			return
		_town_beats = 0
		_saw["town:left"] = true
		pick = leave
	_saw["town-press:" + _btn_name(pick).get_slice(" ", 0).get_slice(".", 0)] = true
	_acts += 1
	pick.pressed.emit()

func _town_weight(name: String) -> int:
	var purse: int = screen.party.gold
	var fit := _health()
	if name.begins_with("Accept:") or name.begins_with("Turn in:"):
		return 140 + _me["greed"] / 2          # work is the loop; always worth a look
	if name.begins_with("Buy"):
		return 12 + _me["greed"] / 2 + (60 if purse > 200 else 0)
	if name.begins_with("Sell"):
		return 10 + (50 if purse < 60 else 0)
	if name.begins_with("Market"):
		return 60 + _me["greed"] / 3
	if name.begins_with("Notice Board"):
		return 70 + _me["nosy"] / 3
	if name.begins_with("Inn"):
		return 40 + int((1.0 - fit) * 120.0)
	if "rest" in name.to_lower() or "room" in name.to_lower():
		return 20 + int((1.0 - fit) * 200.0 * _me["care"] / 100.0)
	if name.begins_with("Steal"):
		return 2 + _me["greed"] / 8            # rare, and it costs you the town
	if name.begins_with("Haggle") or name.begins_with("Persuade"):
		return 20 + _me["greed"] / 4
	if name.begins_with("Investigate"):
		return 30 + _me["nosy"] / 3
	if name.begins_with("Heal") or name.begins_with("Treat"):
		return 15 + int((1.0 - fit) * 150.0)
	if name.begins_with("←"):
		return 25                              # back to the square, to try another door
	return 12                                  # anything new behind a counter

# --- downtime (core/downtime.gd): the inn's rows that take days ---------------
#
# Train's and the game's own "Go" buttons read the same as each other by name
# alone, so these rows are found by shape — the label that names the row, and
# the button beside or after it — the way the fight beat finds End turn by
# position rather than by trusting its text. Each row gets its own weighted
# chance, ahead of the generic press above, so it is worth walking to town for
# and not just one more thing in the bucket with "anything new behind a
# counter". A card the roll turns up (a tab, a brawl, an insult, a bad lead)
# is acked like any other event card — _cards() above already does that.
func _downtime_beat(panel: Node) -> bool:
	if screen._visit_page == "inn":
		if _chance(20) and _press_downtime_row(panel, "A night on the town"):
			_saw["downtime:carouse"] = true
			return true
		if _chance(15) and _gamble_beat(panel):
			_saw["downtime:gamble"] = true
			return true
		if _chance(_me["care"]) and _train_beat(panel):
			_saw["downtime:train"] = true
			return true
		if _chance(_me["nosy"] / 2) and _press_downtime_row(panel, "The pit:"):
			_saw["downtime:pit"] = true
			return true
	elif screen._visit_page == "market" and _chance(15) and _press_downtime_row(panel, "Brew "):
		_saw["downtime:brew"] = true
		return true
	return false

# A row built by world.gd's _trade_row: a label naming it, its own HBoxContainer,
# the action button last in it. Found by the label's text rather than the
# button's — "Go" is not a name, "A night on the town" is — and only when that
# label sits in a row of its own (a closed pit says "The pit: ..." too, in a
# plain Label with nothing to press). The pit's own row carries a sub-line
# (world.gd's _trade_row `sub`), which wraps the label one level deeper in a
# VBoxContainer of its own — so the row is the label's parent, or the parent
# of that when the label came with a caption.
func _downtime_row_button(panel: Node, prefix: String) -> Button:
	var lbl := _find_label(panel, func(t): return t.begins_with(prefix))
	if lbl == null:
		return null
	var row := lbl.get_parent()
	if row != null and not (row is HBoxContainer):
		row = row.get_parent()
	if not (row is HBoxContainer) or row.get_child_count() == 0:
		return null
	var b = row.get_child(row.get_child_count() - 1)
	return b if b is Button and not b.disabled and b.visible else null

func _press_downtime_row(panel: Node, prefix: String) -> bool:
	var b := _downtime_row_button(panel, prefix)
	if b == null:
		return false
	_acts += 1
	b.pressed.emit()
	return true

func _find_label(node: Node, pred: Callable) -> Label:
	if node is Label and pred.call(String(node.text)):
		return node
	for c in node.get_children():
		var found := _find_label(c, pred)
		if found != null:
			return found
	return null

# "Sit in on a game": a label, a stake OptionButton, a Go button, all in one
# row — the smallest stake the purse can cover is the one the picker opens on
# (world.gd builds the list low to high, capped at the purse), so the only
# thing to do here is press Go.
func _gamble_beat(panel: Node) -> bool:
	var lbl := _find_label(panel, func(t): return t == "Sit in on a game")
	if lbl == null:
		return false
	var row := lbl.get_parent()
	if not (row is HBoxContainer):
		return false
	var stake: OptionButton = null
	var go: Button = null
	for c in row.get_children():
		if c is OptionButton:
			stake = c
		elif c is Button:
			go = c
	if stake == null or go == null or go.disabled or stake.item_count == 0:
		return false
	stake.select(0)
	_acts += 1
	go.pressed.emit()
	return true

# The trainer's row is a label ("Train %s in a feat...") sitting just above its
# own HBoxContainer (a hero picker, a feat picker, Go) rather than inside it —
# world.gd adds the label and the row as two separate children of the same
# list. Go never disables itself on the purse (the trainer just turns you away
# with a line under the row), so the purse is checked here instead of wasting
# the act on a hero who cannot afford the five days.
func _train_beat(panel: Node) -> bool:
	var lbl := _find_label(panel, func(t): return t.begins_with("Train "))
	if lbl == null:
		return false
	var parent := lbl.get_parent()
	var i := lbl.get_index()
	if parent == null or i + 1 >= parent.get_child_count():
		return false
	var row := parent.get_child(i + 1)
	if not (row is HBoxContainer):
		return false
	var go: Button = null
	for c in row.get_children():
		if c is Button and not (c is OptionButton):
			go = c
	if go == null or go.disabled:
		return false
	var pupils: Array = screen.party.party_characters().filter(func(ch): return Downtime.can_train(screen.party, ch))
	if pupils.is_empty():
		return false
	var ch = pupils[0]
	var s = screen._visit.get("settlement")
	var bed: int = Downtime.bed_cost(s, Downtime.TRAIN_DAYS)
	if screen.party.gold < Downtime.train_cost(ch) + bed:
		return false
	_acts += 1
	go.pressed.emit()
	return true

# --- the road -----------------------------------------------------------------

func _map_beat() -> void:
	if _hold(THINK_MAP):
		return
	var w = screen.world
	var p = w.player()
	_dest_age += 1

	# A clock we paused ourselves gets un-paused again — and if it does not, the
	# map has swallowed a press, which is worth knowing. Anything else that
	# un-paused it in the meantime (a card, an arrival, a fight ending) clears
	# the mark: from here on the pause is the game's, not ours.
	if not w.clock.is_paused():
		_paused_at = -1
	elif _paused_at >= 0 and _tick_no - _paused_at > 12:
		screen._toggle_pause()
		_paused_at = -1
		_acts += 1
		if w.clock.is_paused():
			fail("Resume did not un-pause the world clock")
		return

	# The small things a player does while the party walks.
	if _chance(10 + _me["fidget"] / 3):
		_fidget()
		return

	# A lair under the party's nose: search for it, sneak into it, or kick the
	# door. All three are one button away and all three are worth walking.
	if screen._lair_btn != null and screen._lair_btn.visible and _chance(30 + _me["nosy"] / 2):
		if screen._lair_sneak_btn.visible and _chance(_me["care"]):
			_saw["lair:sneak"] = true
			_acts += 1
			screen._lair_sneak_btn.pressed.emit()
		else:
			_saw["lair:" + ("attack" if _lair_known() else "search")] = true
			_acts += 1
			screen._lair_btn.pressed.emit()
		return

	# A cleared lair under the party's feet, for sale: a careful robot buys it.
	if screen._lair_settle_btn != null and screen._lair_settle_btn.visible \
			and not screen._lair_settle_btn.disabled and _chance(20 + _me["care"] / 2):
		_saw["lair:settle"] = true
		_acts += 1
		screen._lair_settle_btn.pressed.emit()
		return

	# A landmark under the party's nose: visit it (and answer the first row the
	# card offers), or search the ground for a hidden one.
	if screen._place_btn != null and screen._place_btn.visible and _chance(40 + _me["nosy"] / 2):
		_saw["place:" + ("visit" if "Visit" in screen._place_btn.text else "search")] = true
		_acts += 1
		screen._place_btn.pressed.emit()
		return

	# Hurt, out in the open: a breather, or a camp if the party is carrying a kit.
	if _health() < 0.6 and _chance(_me["care"] / 2):
		if screen._camp_btn != null and screen._camp_btn.visible and _chance(50):
			_saw["camp"] = true
			_acts += 1
			screen._camp_btn.pressed.emit()
		else:
			_saw["short-rest"] = true
			_acts += 1
			screen._short_rest()
		return

	# Somewhere to be. A player re-decides when they arrive, when something
	# interrupts them, or when they simply get bored of the road they are on.
	if _dest == null or p.at_goal() or (w.clock.is_paused() and _paused_at < 0) \
			or _dest_age > _patience():
		_choose_destination()
		return

	# ...and an order that was given has to be being carried out. A party that
	# is unpaused, not at its goal and has not moved a unit since the order is
	# a party nothing can ever un-stick, which is the worst shape a map screen
	# can be left in and the hardest to notice from a screenshot.
	if not w.clock.is_paused() and not p.at_goal() and _dest_age > 30:
		if p.position.distance_to(_ordered_from) < 1.0:
			fail("the party has not moved in %d frames since being sent to %v" % [_dest_age, _dest])
			_dest = null   # reported once per order; pick somewhere else and carry on

func _patience() -> int:
	return 20 + (100 - _me["fidget"]) / 2

func _lair_known() -> bool:
	return screen._lair_target != null and screen._lair_target.discovered

# Every destination worth walking to, weighted by who is playing and what the
# party needs — with two deliberate exceptions, taken first, below.
func _choose_destination() -> void:
	var w = screen.world
	var p = w.player()
	var rows: Array = []
	# The two nudges. They are not randomness with a thumb on the scale — they
	# are a decision, the way a player who has been wandering all afternoon
	# decides they are going to town now and stops re-considering it every time
	# they crest a hill. Without that, a fidgety persona on the large map can
	# spend a whole session almost going somewhere.
	if _tick_no > TICKS / 4 and not _saw.has("settlement"):
		var town = _nearest_settlement(false)
		if town != null:
			return _march_to(town.position, "town")
	if _tick_no > TICKS / 2 and not _saw.has("fight"):
		# A monster faction's gate is the one place on this map where a fight is
		# a certainty rather than a hope: they never open a market, they always
		# turn out the guard. Marching on it is a thing players do.
		var gate = _nearest_settlement(true)
		if gate != null:
			return _march_to(gate.position, "monster-town")

	for s in w.settlements:
		var monster: bool = WorldAI.is_monster(s.faction)
		var far: float = p.position.distance_to(s.position)
		var weight := 40 + int(clampf(700.0 - far * 0.35, 0.0, 700.0)) / 6
		if monster:
			weight = 6 + _me["bold"] / 6
		else:
			weight += int((1.0 - _health()) * 90.0)     # an inn, a healer, a bed
			weight += _me["greed"] / 4
		if _dest != null and s.position.distance_to(_dest) < 1.0:
			weight = weight / 4                          # just came from there
		rows.append([weight, [s.position, "town" if not monster else "monster-town"]])

	for l in w.lairs:
		if l.looted:
			continue
		rows.append([8 + _me["nosy"] / 4 + (20 if l.discovered else 0),
			[l.position, "lair"]])

	for band in w.parties:
		if band.is_player:
			continue
		if not WorldAI.is_monster(band.faction):
			continue
		rows.append([6 + _me["bold"] / 5, [band.position, "band"]])

	# ...and plain wandering, which is how a map gets explored at all.
	var roam: Vector2 = p.position + Vector2(_d(900) - 450, _d(900) - 450)
	rows.append([25 + _me["nosy"] / 3, [roam, "wander"]])

	var choice = _weighted(rows)
	if choice == null:
		return
	_march_to(choice[0], String(choice[1]))

func _nearest_settlement(monster: bool):
	var p = screen.world.player()
	var best = null
	for s2 in screen.world.settlements:
		if WorldAI.is_monster(s2.faction) != monster:
			continue
		if best == null or p.position.distance_to(s2.position) < p.position.distance_to(best.position):
			best = s2
	return best

# An order, given the way a player gives one: put the place on screen, then
# click it. Which makes the camera maths part of the test — if _pix and _unpix
# ever stop being inverses, every click in the game lands somewhere else, and
# this is the assertion that says so.
func _march_to(at: Vector2, tag: String) -> void:
	screen.center_on(at)
	var sp: Vector2 = screen._pix(at)
	var read_back: Vector2 = screen._unpix(sp)
	if read_back.distance_to(at) > 1.0:
		fail("a click does not land where it was aimed: %v read back as %v" % [at, read_back])
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = sp
	screen._gui_input(e)
	# Nobody watches a party cross a continent at 1x. A long march is what the
	# speed button is for, so the driver reaches for it the way a player does —
	# which also keeps the session's frame budget spent on playing rather than
	# on walking.
	var far: float = screen.world.player().position.distance_to(at)
	var want: float = 8.0 if far > 900.0 else (4.0 if far > 300.0 else 1.0)
	for i in 3:
		if screen.world.clock.speed >= want:
			break
		_saw["speed"] = true
		screen._cycle_speed()
	_dest = at
	_dest_age = 0
	_ordered_from = screen.world.player().position
	_acts += 1
	_saw["walk"] = true
	_saw["go:" + tag] = true

# The fiddling: pause to look at something, change the speed, zoom, drag the
# map, check the pack for the third time. Cosmetic to the player, and the
# richest source of "opened X over Y" bugs in the whole screen.
func _fidget() -> void:
	_acts += 1
	match _d(8):
		1:
			if not screen.world.clock.is_paused():
				_saw["pause"] = true
				screen._toggle_pause()
				_paused_at = _tick_no
				if not screen.world.clock.is_paused():
					fail("Pause did not pause the world clock")
		2:
			_saw["speed"] = true
			screen._cycle_speed()
		3:
			_saw["pace"] = true
			screen._cycle_pace()
		4:
			_saw["party-screen"] = true
			screen._open_party()
		5:
			_saw["quest-log"] = true
			screen._toggle_quests()
		6:
			_saw["pack"] = true
			screen._toggle_inventory()
		7:
			_saw["menu"] = true
			screen._toggle_menu()
		_:
			_saw["camera"] = true
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_UP if _chance(50) else MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = true
			e.position = Vector2(_d(1200), _d(700))
			screen._gui_input(e)
			var m := InputEventMouseMotion.new()
			m.button_mask = MOUSE_BUTTON_MASK_RIGHT
			m.position = Vector2(600, 400)
			m.relative = Vector2(_d(80) - 40, _d(80) - 40)
			screen._gui_input(m)
			if screen._zoom < screen.ZOOM_MIN - 0.001 or screen._zoom > screen.ZOOM_MAX + 0.001:
				fail("the camera zoomed outside its own limits: %.3f" % screen._zoom)

func _overlay_open() -> bool:
	return screen._party_overlay != null or screen._quest_panel != null \
		or screen._inventory_panel != null or screen._menu_panel != null \
		or screen._story_panel != null

# Everything the fidget above can open, closed the way its own button closes it.
# The clock has to come back with them: an overlay that leaks a pause is a run
# that has quietly stopped, and it is the single easiest bug to ship here.
func _close_overlays() -> void:
	_acts += 1
	if screen._party_overlay != null:
		screen._close_party()
	elif screen._quest_panel != null:
		screen._toggle_quests()
	elif screen._inventory_panel != null:
		screen._toggle_inventory()
	elif screen._menu_panel != null:
		screen._close_menu()
	elif screen._story_panel != null:
		screen._close_story()
	if not _overlay_open() and screen._combat == null and screen._visit.is_empty() \
			and screen.world.clock.is_paused() and _paused_at < 0 \
			and not screen._halted_on_arrival:
		fail("closing an overlay left the world clock paused")

# --- buttons ------------------------------------------------------------------

# Only what a player could actually press. `pressed.emit()` does not honour
# Button.disabled the way a real click does, so without this the robot fires
# greyed verbs and spends its session in states the game never lets anyone into.
func _live_buttons(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is Button and not c.disabled and not c.is_queued_for_deletion() and c.visible:
			out.append(c)
		out.append_array(_live_buttons(c))
	return out

# Since the skill bar went to icon badges a button's name is the first line of
# its tooltip; the text is what a build with no imported icons still draws.
func _btn_name(b: Button) -> String:
	var tip := String(b.tooltip_text)
	return tip.get_slice("\n", 0) if tip != "" else String(b.text)

func _any_word(name: String, words: Array) -> bool:
	for w in words:
		if w in name:
			return true
	return false

# The bar's last slot is always its own control — End turn, Cancel, or the
# confirm those two wear once armed. See scenes/main.gd's _slotted().
func _press_last(fight) -> bool:
	var btns := _live_buttons(fight._buttons)
	if btns.is_empty():
		return false
	_acts += 1
	btns[btns.size() - 1].pressed.emit()
	return true

func _press_one(under: Node) -> bool:
	var btns := _live_buttons(under)
	if btns.is_empty():
		return false
	_acts += 1
	_pick(btns).pressed.emit()
	return true

# --- how the party is doing ---------------------------------------------------

func _health() -> float:
	var chars: Array = screen.party.party_characters()
	if chars.is_empty():
		return 0.0
	var hp := 0.0
	var top := 0.0
	for ch in chars:
		var s: Dictionary = screen.party.summary(ch.id)
		hp += float(s["hp"])
		top += maxf(1.0, float(s["max_hp"]))
	return clampf(hp / top, 0.0, 1.0)

# --- the verdict --------------------------------------------------------------

# A session is allowed to end anywhere — that is what randomized means. What it
# is not allowed to do is end having played nothing: these are the things the
# driver steers at hard enough that missing one means the road to it is broken,
# not that the dice went the other way.
func _final_checks() -> void:
	if screen.world.clock.elapsed <= _clock0:
		fail("the world clock never advanced in %d frames" % TICKS)
	if not _saw.has("walk"):
		fail("the party never took a single order")
	if not _saw.has("settlement"):
		fail("never reached a settlement, with %d frames and a nudge at a quarter of them" % TICKS)
	if not _saw.has("fight"):
		fail("never reached a fight, with %d frames and a nudge at halfway" % TICKS)
	if _acts < 40:
		fail("only %d deliberate acts in %d frames — the driver found nothing to do" % [_acts, TICKS])
	if not WorldSave.has_save():
		fail("a whole session of play wrote no world autosave")
	# The map has to be left playable, whatever happened on it.
	if screen.world.player() == null:
		fail("the session ended with no player party on the map")

func _report() -> void:
	var keys: Array = _saw.keys()
	keys.sort()
	print("  %d frames, %d acts, %d fights, %d callings done, %d gp, day-clock %.0f -> %.0f  %s" % [
		_tick_no, _acts, _fights, _callings_done.size(), screen.party.gold, _clock0, screen.world.clock.elapsed,
		"OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	print("  exercised: ", keys)
	if _fail > 0:
		printerr("  replay it with: SORCMERC_SEED=%d godot --headless --path . -s tests/drive_random.gd" % _seed)

func _done() -> void:
	WorldSave.clear()
	print("drive_random: %s" % ["OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)

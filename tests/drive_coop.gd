# One co-op peer, headless: loads the real combat screen under SORCMERC_COOP and
# presses real buttons whenever one of its own heroes is up, waits otherwise.
# Prints the fight's final state hash so two of these can be compared. Run by
# tools/coop_smoke.sh, which starts the relay and both peers.
#   SORCMERC_COOP=host:ABCDEF SORCMERC_RELAY=ws://127.0.0.1:8799 godot --headless --path . -s tests/drive_coop.gd
#   SORCMERC_COOP_QUIT_AFTER=N   quit (exit 3) after N presses — a peer's "crash"
#   SORCMERC_COOP_DROP_AT=N      close the socket under the game after N presses
#                                (a hiccup, not a crash): the link reconnects and
#                                resyncs from the relay's replay
#   SORCMERC_COOP_VIA=game       come in through the front door instead: the
#                                title's Play together → Join, and the guest's
#                                waiting screen puts the fight up (game.gd)
#   SORCMERC_COOP_VIA=map        no fight: the host walks the open world for
#                                20 s, the guest watches the mirror; both print
#                                where the party stands at the end
extends SceneTree

const Coop = preload("res://core/coop.gd")
const Hex = preload("res://core/hex.gd")
const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Leveling = preload("res://core/leveling.gd")
const Creator = preload("res://scenes/creator/creator.gd")

const MAX_PRESSES = 400
const PATIENCE := 60.0   # seconds of nothing to press before giving up on the other peer

var main
var game = null   # the front door, under SORCMERC_COOP_VIA=game
var _presses = 0
var _quit_after: int = int(OS.get_environment("SORCMERC_COOP_QUIT_AFTER")) if OS.get_environment("SORCMERC_COOP_QUIT_AFTER") != "" else -1
var _drop_at: int = int(OS.get_environment("SORCMERC_COOP_DROP_AT")) if OS.get_environment("SORCMERC_COOP_DROP_AT") != "" else -1

func _init() -> void:
	# This is not a solo robot like its drive_* siblings: it is ONE PEER, and it
	# needs a relay and a partner sitting on the same room code. tools/run_tests.sh
	# sweeps `ls tests/drive_*.gd`, so it picks this up too — and bare, with no
	# SORCMERC_COOP in the environment, main.gd's `Coop.from_env()` returns null,
	# _run()'s first frame dereferences the null Link, and because a script error
	# does not quit the SceneTree the loop then spins until the harness kills it at
	# TEST_TIMEOUT. That one hang was ~900s of a ~1300s suite. Say so and stop.
	if OS.get_environment("SORCMERC_COOP") == "" and OS.get_environment("SORCMERC_COOP_VIA") == "":
		print("drive_coop: skipped — needs a relay and two peers; run tools/coop_smoke.sh")
		quit()
		return
	OS.set_environment("SORCMERC_FAST", "1")
	if OS.get_environment("SORCMERC_COOP_VIA") == "map":
		_map_mirror()
		return
	if OS.get_environment("SORCMERC_COOP_VIA") == "game":
		game = load("res://scenes/game/game.tscn").instantiate()
		root.add_child(game)
		await process_frame
		Coop.link = Coop.Link.new(Coop.relay_url(), OS.get_environment("SORCMERC_COOP"), "guest")
		game.show_coop_guest()
	else:
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
	_run()

func _run() -> void:
	var waited_since := Time.get_ticks_msec()
	while _presses < MAX_PRESSES:
		await process_frame
		if game != null:
			main = game._guest_combat
			if main == null:
				if Time.get_ticks_msec() - waited_since > PATIENCE * 1000:
					print("*** guest waited %ds on the front door — wedged ***" % PATIENCE)
					quit(1)
					return
				continue
		if main.cb != null and main.cb.is_over():
			break
		if main.cb == null or main._busy or (main._mode == "deploy" and main._coop != null and main._coop.role == "guest"):
			if Time.get_ticks_msec() - waited_since > PATIENCE * 1000:
				print("*** %s waited %ds for the other peer — wedged ***" % [OS.get_environment("SORCMERC_COOP"), PATIENCE])
				quit(1)
				return
			continue
		waited_since = Time.get_ticks_msec()
		if _presses == _quit_after:
			print("%s: quitting on purpose after %d presses" % [main._coop.role, _presses])
			quit(3)
			return
		if _presses == _drop_at:
			print("%s: dropping the socket on purpose after %d presses" % [main._coop.role, _presses])
			_drop_at = -1
			main._coop.ws.close()
		_act()
	await create_timer(1.0).timeout   # let the last message leave
	var cb = main.cb
	print("%s: seed=%d room=%s presses=%d rounds=%d outcome=%s hash=%d" % [
		main._coop.role, main._seed, main._coop.code, _presses, cb.round_num, cb.outcome(), Coop.state_hash(cb)])
	quit(0 if cb.is_over() else 1)

# One press on `main`, whatever its mode wants.
func _act() -> void:
	if main._mode == "cone" or main._mode == "target":
		_board_click()
	elif main._mode == "idle" and _presses % 3 == 0 and main.cb.current().econ["move_left"] > 0:
		_move_click()
	else:
		var btns := _buttons()
		if not btns.is_empty():
			_press(btns)

func _board_click() -> void:
	_presses += 1
	var cb = main.cb
	var h = cb.current()
	if main._mode == "cone":
		var foes = cb.enemies_of(h)
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

func _move_click() -> void:
	_presses += 1
	var cb = main.cb
	var h = cb.current()
	var foes = cb.enemies_of(h)
	if foes.is_empty():
		return
	var goal = h.pos
	for hx in cb.move_field(h):
		if Hex.distance(hx, foes[0].pos) < Hex.distance(goal, foes[0].pos):
			goal = hx
	if goal != h.pos:
		main.board_hex_clicked(goal)

func _name(b: Button) -> String:
	var tip := String(b.tooltip_text)
	return tip.get_slice("\n", 0) if tip != "" else String(b.text)

func _buttons() -> Array:
	var out: Array = []
	for b in main._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion() and not b.disabled:
			out.append(b)
	return out

func _press(btns: Array) -> void:
	var wanted = ["Attack", "Sacred Flame", "Attack", "Cure Wounds", "Second Wind", "Attack", "Dodge", "End turn"]
	var verb = wanted[_presses % wanted.size()]
	var pick: Button = null
	for b in btns:
		if verb in _name(b):
			pick = b
			break
	if pick == null:
		pick = btns[-1]   # End turn / Begin the ambush sits last
	_presses += 1
	pick.pressed.emit()

# The road, mirrored, with a fight in the middle: the host's game.tscn shows
# the demo world, a hunting band is set on the party at 8x so a fight comes
# within seconds, both peers play it, and afterwards both should be back on
# the same map with the party in the same place.
func _map_mirror() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/coop-%d" % randi())   # nobody's real slot
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var room := OS.get_environment("SORCMERC_COOP")
	var role := "host" if room.begins_with("host") else "guest"
	Coop.link = Coop.Link.new(Coop.relay_url(), room.trim_prefix("host:"), role)
	var fought := false
	var t0 := Time.get_ticks_msec()
	if role == "host":
		game.show_world(null)     # the demo roster and the small map
		var screen = game._screen
		await create_timer(3.0).timeout   # the guest sits down, gets the map
		var w = screen.world
		var p = w.player()
		w.set_goal(p, p.position + Vector2(20000, 0))   # a long march: never arrives, never halts
		var hound = w.add_party(World.RoamingParty.new("hound", p.position - Vector2(40, 0), "goblinoid"))
		WorldAI.hunt(hound)
		w.clock.set_speed(8.0)
		w.clock.resume()
		while Time.get_ticks_msec() - t0 < 60000:
			await process_frame
			if screen._event_card != null:
				screen._event_card.acknowledged.emit()
			if screen._approach_card != null:
				screen._on_approach_chosen("engage")
			if screen._spoils_panel != null:
				screen._close_spoils()
			if screen._combat != null and screen._combat.cb != null and screen._combat.result.is_empty():
				main = screen._combat
				fought = true
				if not main._busy and not main.cb.is_over():
					_act()
			elif fought and screen._combat == null:
				break   # the fight is over and the map is back
		await create_timer(4.0).timeout   # an autosave's full map reaches the guest
		# The road's other screens: a counter, then a level on the guest's hero.
		screen._open_visit(w.settlements[0])
		screen._goto_page("market")
		await create_timer(3.0).timeout
		screen._close_visit()
		var theirs = screen.party.party_characters()[1]   # alternating split: the second hero is the guest's
		var was: int = theirs.level()
		theirs.xp = Leveling.xp_for_level(was + 1)
		screen._autosave()
		var t1 := Time.get_ticks_msec()
		while theirs.level() == was and Time.get_ticks_msec() - t1 < 30000:
			await process_frame
		var q = screen.world.player()
		print("host: fought=%s party=(%.0f, %.0f) %s=%d->%d" % [str(fought), q.position.x, q.position.y, theirs.cname, was, theirs.level()])
	else:
		game.show_coop_guest()
		while Time.get_ticks_msec() - t0 < 70000:
			await process_frame
			if game._guest_combat != null and game._guest_combat.cb != null and game._guest_combat.result.is_empty():
				main = game._guest_combat
				fought = true
				if not main._busy and not (main._mode == "deploy") and not main.cb.is_over():
					_act()
			elif fought and game._guest_on_map:
				break
		await create_timer(1.0).timeout
		if not game._guest_on_map:
			print("*** guest is not on the map (fought=%s) — wedged ***" % str(fought))
			quit(1)
			return
		# The counter, mirrored: the host's market page, every button greyed.
		var visit := ""
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 15000:
			await process_frame
			var sc = game._screen
			if sc != null and "_visit_page" in sc and sc._visit_page == "market" and sc._visit_panel != null:
				visit = "market:%s:%s" % [sc._visit["settlement"].id, "greyed" if _all_disabled(sc._visit_panel) else "LIVE"]
				break
		while game._screen != null and "_visit" in game._screen and not game._screen._visit.is_empty():
			await process_frame   # the host leaves; the panel goes
		# The level: the #118 panel names our hero; take it on the real screen.
		var leveled := ""
		t0 = Time.get_ticks_msec()
		while leveled == "" and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
			var sc = game._screen
			if sc == null or not ("_levelup_panel" in sc):
				continue
			if sc._levelup_overlay != null:
				var ov = sc._levelup_overlay
				var ch = ov.character()
				ov.commit()
				for _round in 6:
					for p in Leveling.pending(ch):
						var opts: Array = Creator.options_for(p, ch.sheet(), [])
						for i in mini(Creator.pick_count(p), opts.size()):
							ov._pick(p, String(opts[i]["id"]))
				ov._on_confirm()
				leveled = "%s->%d" % [ch.cname, ch.level()]
			elif sc._levelup_panel != null:
				for b in _buttons_under(sc._levelup_panel):
					if b.text.begins_with("Level up"):
						b.pressed.emit()
						break
		await create_timer(2.0).timeout
		var q = game._screen.world.player()
		print("guest: fought=%s party=(%.0f, %.0f) spectator=%s visit=%s leveled=%s" % [str(fought), q.position.x, q.position.y, str(game._screen.spectator), visit, leveled])
	quit(0)

func _buttons_under(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons_under(c))
	return out

func _all_disabled(n: Node) -> bool:
	return _buttons_under(n).all(func(b): return b.disabled)

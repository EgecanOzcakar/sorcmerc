# O2/O4 — scene-driver smoke test for the open-world map screen: it renders, the
# clock runs, a right-click moves the player party, pause stops it, the camera
# pans/zooms without crashing, and closing on a hostile party hands off to a real
# scenes/main.tscn fight that freezes the map until it is won.
#   godot --headless --path . -s tests/drive_world.gd
extends SceneTree

var screen
var _fail := 0

func _init() -> void:
	# O17: this process's own autosave slots, so a concurrent godot run cannot
	# clobber them. randi() as well as the pid: under a sandboxed (flatpak)
	# godot every process sees pid 3, so the pid alone is not unique.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

func click(button: int, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	screen._gui_input(e)

# The scene's own _process runs too, but headless deltas are tiny — drive time
# explicitly so the assertions below are about movement, not frame pacing.
func step(n: int, dt := 0.1) -> void:
	for i in n:
		screen._process(dt)
		await process_frame

func _run() -> void:
	await process_frame
	screen.size = Vector2(1280, 800)
	await step(2)

	var p = screen.world.player()
	if p == null:
		fail("the scene has no player party")
		return _done()
	if screen.world.settlements.size() < 2 or screen.world.parties.size() < 3:
		fail("the scene has nothing to render: %d settlements, %d parties"
			% [screen.world.settlements.size(), screen.world.parties.size()])

	# --- right-click sets a goal and the party actually walks there ---------
	var start: Vector2 = p.position
	click(MOUSE_BUTTON_RIGHT, Vector2(1000, 600))
	if p.goal.is_equal_approx(start):
		fail("right-click did not set a goal away from the party")
	await step(5)
	if p.position.is_equal_approx(start):
		fail("the player party never moved toward the clicked point")
	if p.position.distance_to(p.goal) >= start.distance_to(p.goal):
		fail("the player party moved, but not toward its goal")

	# --- pause freezes it, resume unfreezes --------------------------------
	screen._toggle_pause()
	if not screen.world.clock.is_paused():
		fail("the pause button did not pause the clock")
	var held: Vector2 = p.position
	await step(5)
	if not p.position.is_equal_approx(held):
		fail("the party kept moving while paused")
	screen._toggle_pause()
	await step(5)
	if p.position.is_equal_approx(held):
		fail("resuming did not start the party moving again")

	# --- speed button cycles 1x/2x/4x/8x and actually speeds movement up ----
	var slow_step: Vector2 = p.position
	await step(1)
	slow_step = p.position - slow_step
	screen._cycle_speed()
	if screen.world.clock.speed != 2.0:
		fail("the speed button did not move the clock to 2x")
	var fast_step: Vector2 = p.position
	await step(1)
	fast_step = p.position - fast_step
	if fast_step.length() <= slow_step.length() * 1.5:
		fail("2x did not noticeably speed up movement (%s vs %s)" % [fast_step, slow_step])
	screen._cycle_speed(); screen._cycle_speed(); screen._cycle_speed()
	if screen.world.clock.speed != 1.0:
		fail("cycling four times did not wrap back to 1x")

	# --- camera: drag-pan and scroll-zoom ----------------------------------
	var pan0: Vector2 = screen._pan
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.position = Vector2(600, 400)
	m.relative = Vector2(-40, 25)
	screen._gui_input(m)
	if screen._pan.is_equal_approx(pan0):
		fail("drag did not pan the camera")

	# Zoom keeps the world point under the cursor put, and clamps at both ends.
	var at := Vector2(700, 350)
	var under: Vector2 = screen._unpix(at)
	click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._unpix(at).distance_to(under) > 1.0:
		fail("zoom did not keep the point under the cursor fixed")
	for i in 40:
		click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._zoom > screen.ZOOM_MAX:
		fail("zoom exceeded ZOOM_MAX")
	for i in 80:
		click(MOUSE_BUTTON_WHEEL_DOWN, at)
	if screen._zoom < screen.ZOOM_MIN:
		fail("zoom fell below ZOOM_MIN")
	await step(2)     # a frame at min zoom, to exercise the far-out ground path
	await _encounter_handoff(p)
	await _offscreen_battle(p)
	await _settlement_visit(p)
	await _hostile_settlement(p)
	await _pursuit_at_8x(p)
	await _party_and_quests()
	_exit_to_title()
	_done()

# --- party/profile/inventory + quest log HUD buttons -------------------
func _party_and_quests() -> void:
	screen._open_party()
	if screen._party_overlay == null:
		fail("Party did not open an overlay")
	elif not screen.world.clock.is_paused():
		fail("opening Party did not pause the clock")
	screen._close_party()
	if screen._party_overlay != null:
		fail("closing Party left the overlay up")
	if screen.world.clock.is_paused():
		fail("closing Party did not resume the clock")

	screen._toggle_quests()
	if screen._quest_panel == null:
		fail("Quests did not open a panel")
	elif not screen.world.clock.is_paused():
		fail("opening Quests did not pause the clock")
	screen._toggle_quests()   # toggles closed
	if screen._quest_panel != null:
		fail("toggling Quests again did not close it")
	if screen.world.clock.is_paused():
		fail("closing Quests did not resume the clock")

# --- O9 item 3: a chase at 8x still catches ---------------------------------
# Pursuer and quarry move at the same World.SPEED, so a pursuit holds its gap
# forever; at 8x a tick moves both 32 units, which used to step clean over the
# fixed 24-unit trigger and the fight never happened.
func _pursuit_at_8x(p) -> void:
	var World = load("res://core/world.gd")
	var WorldAI = load("res://core/world_ai.gd")
	var open_country := Vector2(9000, 9000)
	p.position = open_country
	screen.world.set_goal(p, open_country + Vector2(20000, 0))     # a long flight
	var chaser = screen.world.add_party(
		World.RoamingParty.new("hound", open_country - Vector2(32, 0), "goblinoid"))
	WorldAI.hunt(chaser)
	screen.world.clock.set_speed(8.0)
	var gap0: float = chaser.position.distance_to(p.position)
	await step(30)
	if screen._combat == null:
		fail("a hunting party at 8x never caught the player (gap %.1f -> %.1f)"
			% [gap0, chaser.position.distance_to(p.position)])
	else:
		screen._combat.result = {"outcome": "Victory", "xp": 40, "gold": 30}
		await step(4)
	screen.world.clock.set_speed(1.0)
	screen.world.parties.erase(chaser)

# --- O9 item 2 / O13: the way out, and what persists a run -------------------
func _exit_to_title() -> void:
	var CharacterSave = load("res://core/character_save.gd")
	var FactionOpinion = load("res://core/faction_opinion.gd")
	var WorldSave = load("res://core/world_save.gd")
	# O13: play itself autosaves — markets, fights and overlays have opened and
	# closed above, and each teardown writes the slot. Cleared here so the checks
	# below are about _leave_world's own save.
	if not WorldSave.has_save():
		fail("nothing during play wrote a world autosave")
	WorldSave.clear()
	FactionOpinion.set_opinion("soldier", -20.0)
	var p = screen.world.player()
	var where: Vector2 = p.position
	var elapsed: float = screen.world.clock.elapsed
	screen.party.add_gold(77)
	var purse: int = screen.party.gold
	screen._leave_world()
	if not FactionOpinion.all().is_empty():
		fail("leaving the world did not clear per-run faction opinion")
	for ch in screen.party.roster:
		if not FileAccess.file_exists(CharacterSave.path_for(ch.id)):
			fail("%s was not saved to the barracks on the way out" % ch.id)

	# O13: ...and the map itself, opinion included, is in the slot.
	if not WorldSave.has_save():
		fail("leaving the world wrote no world autosave")
		return
	var saved = WorldSave.load_latest()
	if saved == null:
		fail("the world autosave did not load back")
		return
	var loaded_p = saved["world"].player()
	if loaded_p == null or not loaded_p.position.is_equal_approx(where):
		fail("the saved world lost the player's position")
	if not is_equal_approx(saved["world"].clock.elapsed, elapsed):
		fail("the saved world lost the clock")
	if saved["world"].settlements.size() != screen.world.settlements.size():
		fail("the saved world lost settlements")
	if saved["party"].gold != purse:
		fail("the saved world lost the party's purse")
	if FactionOpinion.get_opinion("soldier") != -20.0:
		fail("loading the world did not re-apply faction opinion")
	FactionOpinion.reset()
	WorldSave.clear()

# --- O6: walking into a settlement opens the market, Leave closes it --------
func _settlement_visit(p) -> void:
	var s = screen.world.settlements[0]
	p.position = s.position + Vector2(screen.VISIT_RADIUS + 12.0, 0)
	screen.world.set_goal(p, s.position)
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("the market opened while the party was still outside the walls")
		return
	await step(5)
	if screen._visit.is_empty():
		fail("walking into the settlement did not open the market")
		return
	if not screen.world.clock.is_paused():
		fail("the visit did not pause the world clock")
	if screen._visit_panel == null or screen._visit["stock"].is_empty():
		fail("the market panel came up with nothing on it")
		return

	# Buy the first thing on the shelf through the panel's own path.
	screen.party.gold = 100000
	var id: String = String(screen._visit["stock"][0]["item_id"])
	var price: int = screen._visit["stock"][0]["price"]
	var gold0: int = screen.party.gold
	screen._buy(id)
	if screen.party.gold != gold0 - price or screen.party.stash_count(id) != 1:
		fail("buying from the market panel did not move gold/stash")
	if screen._visit["stock"].any(func(e): return e["item_id"] == id):
		fail("the bought item is still on the shelf")

	# Steal: narrated, and it queues the O7 opinion delta on the settlement.
	var opinion0: float = s.pending_opinion_delta
	screen._steal()
	if s.pending_opinion_delta >= opinion0:
		fail("stealing did not queue an opinion delta for O7")
	if screen._visit_log == null or screen._visit_log.text == "":
		fail("the theft was not narrated in the panel")

	# O9 item 1: one attempt per visit. The clock is paused, so a second press
	# would re-roll the identical (possibly winning) result forever.
	var opinion1: float = s.pending_opinion_delta
	var purse: int = screen.party.gold
	screen._steal()
	if screen.party.gold != purse:
		fail("a second Steal in the same visit still paid out")
	if s.pending_opinion_delta != opinion1:
		fail("a second Steal in the same visit still moved opinion")
	if not screen._visit.get("stolen", false):
		fail("the visit was not marked as already stolen from")

	# O9 item 2: the inn — a long rest, paid for in world-time.
	var clock0: float = screen.world.clock.elapsed
	var ch = screen.party.party_characters()[0]
	ch.hp_current = 1
	screen._rest()
	if screen.world.clock.elapsed <= clock0:
		fail("resting did not spend any world-time")
	if ch.hp_current == 1:
		fail("the long rest did not heal the party")
	if not screen._visit.get("stolen", false):
		fail("resting cleared the one-theft-per-visit mark")

	# O9 item 4: a settlement offers work, and a finished job can be handed in.
	var Quest = load("res://core/quest.gd")
	var offer: Dictionary = screen.Visit.quest_offer(s, screen.party)
	if offer.is_empty():
		fail("a neutral settlement offered no work at all")
	else:
		screen._take_quest(offer)   # T9x: _take_quest now takes the exact board row
		var taken: Dictionary = Quest.get_quest(screen.party, offer["id"])
		if taken.is_empty() or taken["state"] != "active":
			fail("taking the offered job did not put it in the log")
		else:
			taken["progress"] = int(taken["required"])
			taken["state"] = "complete"
			if screen.Visit.turn_ins(screen.party).is_empty():
				fail("a finished job is not offered for turn-in")
			var gold0b: int = screen.party.gold
			screen._turn_in(taken)
			if taken["state"] != "turned_in" or screen.party.gold <= gold0b:
				fail("turning the job in did not pay")

	# O9 item 7: the HUD's pause/speed buttons are inert while the panel is open.
	screen._toggle_pause()
	screen._cycle_speed()
	if not screen.world.clock.is_paused() or screen.world.clock.speed != 1.0:
		fail("the pause/speed buttons still fired during a settlement visit")

	screen._close_visit()
	if not screen._visit.is_empty() or screen._visit_panel != null:
		fail("Leave did not close the market")
	if screen.world.clock.is_paused():
		fail("Leave did not resume the world clock")
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("the market reopened on the spot after Leave")
	# ...and it opens again once the party has left the walls and come back.
	var away: Vector2 = s.position + Vector2(screen.VISIT_RADIUS + 60.0, 0)
	screen.world.set_goal(p, away)
	await step(30)
	if not screen._visit.is_empty():
		fail("the market stayed open while the party walked out")
		return
	screen.world.set_goal(p, s.position)
	await step(30)
	if screen._visit.is_empty():
		fail("coming back to the settlement did not open the market again")
	else:
		screen._close_visit()

# --- O7: at a low enough opinion the gate guards come out instead of the market --
func _hostile_settlement(p) -> void:
	var FactionOpinion = load("res://core/faction_opinion.gd")
	var s = screen.world.settlements[0]

	# O9 item 5: the three bands are all reachable now. Past HOSTILE their parties
	# hunt you but the gate is still open; past REFUSE_TRADE the stall is bare;
	# only past GUARDS_ATTACK do the guards come out.
	FactionOpinion.set_opinion(s.faction, FactionOpinion.HOSTILE - 1.0)
	screen._left = null
	p.position = s.position
	screen.world.set_goal(p, s.position)
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a merely hostile settlement refused to open its gate")
	elif screen._visit.get("refused", false):
		fail("a merely hostile settlement already refused to trade")
	else:
		screen._close_visit()
	FactionOpinion.set_opinion(s.faction, FactionOpinion.REFUSE_TRADE - 1.0)
	screen._left = null
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a trade-refusing settlement fought instead of refusing")
	elif not screen._visit.get("refused", false):
		fail("REFUSE_TRADE is still unreachable: the market traded normally")
	else:
		screen._close_visit()

	# O9 item 6: a monster faction's town never opens a market, whatever it thinks.
	var monster_town = null
	for st in screen.world.settlements:
		if load("res://core/world_ai.gd").is_monster(st.faction):
			monster_town = st
			break
	if monster_town == null:
		fail("the demo map has no monster-faction settlement to test")
	else:
		screen._left = null
		p.position = monster_town.position
		screen.world.set_goal(p, monster_town.position)
		screen._check_visit()
		if not screen._visit.is_empty():
			fail("a monster-faction settlement ran a friendly market")
			screen._close_visit()
		elif screen._combat == null:
			fail("walking into a monster-faction settlement did nothing at all")
		else:
			screen._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5}
			await step(4)

	FactionOpinion.set_opinion(s.faction, FactionOpinion.GUARDS_ATTACK - 1.0)
	screen._left = null
	p.position = s.position
	screen.world.set_goal(p, s.position)
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("a hostile settlement still opened its market")
	if screen._combat == null:
		fail("walking into a hostile settlement did not trigger a fight")
		FactionOpinion.reset()
		return
	if not screen.world.clock.is_paused():
		fail("the guard fight did not pause the world clock")
	# Win it: the garrison is not a map party, so the map just carries on.
	var n: int = screen.world.parties.size()
	screen._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5}
	await step(4)
	if screen._combat != null:
		fail("the guard fight scene was never torn down")
	if screen.world.parties.size() != n:
		fail("beating the garrison removed a party from the map")
	if FactionOpinion.get_opinion(s.faction) >= FactionOpinion.GUARDS_ATTACK - 1.0:
		fail("killing their garrison did not lower the faction further")
	# Back to friendly terms: the same walk-in opens the market again.
	FactionOpinion.set_opinion(s.faction, 0.0)
	screen._left = null
	screen.world.clock.resume()
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a settlement at neutral opinion did not open its market")
	else:
		screen._close_visit()
	FactionOpinion.reset()

# --- O5: two NPC parties meeting resolve off-screen, no scene, no pause -----
func _offscreen_battle(p) -> void:
	var World = load("res://core/world.gd")
	var away: Vector2 = p.position + Vector2(4000, 4000)     # nowhere near the player
	var a = screen.world.add_party(World.RoamingParty.new("raid-band", away, "bandit"))
	var b = screen.world.add_party(World.RoamingParty.new("garrison", away + Vector2(40, 0), "human"))
	a.goal = b.position
	b.goal = b.position
	var n: int = screen.world.parties.size()
	await step(6)     # 0.6s x 40 u/s closes the 40-unit gap into the radius
	if screen.world.parties.size() != n - 1:
		fail("the NPC meeting did not resolve to exactly one dead party (%d -> %d)"
			% [n, screen.world.parties.size()])
	if screen.world.parties.has(a) == screen.world.parties.has(b):
		fail("exactly one of the two bands should be left standing")
	if screen._combat != null:
		fail("an NPC-vs-NPC battle launched a combat scene")
	if screen.world.clock.is_paused():
		fail("an NPC-vs-NPC battle paused the world clock")
	if screen.world.player() == null:
		fail("the player was caught up in an off-screen battle")

# --- O4: proximity triggers a real fight, winning clears the party ------
func _encounter_handoff(p) -> void:
	# "soldier" was the pre-T90 civilized faction name — a stale check here
	# (T90 moved the civilized/monster split to the four playable races and
	# missed this file) happened to still work by accident, since nothing in
	# the demo world uses "soldier" any more. WorldAI.is_monster() is the
	# actual, current rule.
	var WorldAI = load("res://core/world_ai.gd")
	var foe = null
	for q in screen.world.parties:
		if not q.is_player and WorldAI.is_monster(q.faction):
			foe = q
			break
	if foe == null:
		fail("no hostile party in the demo world to be ambushed by")
		return

	# Walk them together: just outside the radius, then inside it. Out in open
	# country — standing on a settlement would open O6's market instead.
	var open_country := Vector2(3000, -3000)
	p.position = open_country
	screen.world.set_goal(p, open_country)
	foe.position = open_country + Vector2(screen.ENCOUNTER_RADIUS + 10.0, 0)
	foe.goal = open_country
	screen._check_encounter()
	if screen._combat != null:
		fail("combat launched while the parties were still apart")
		return
	await step(4)     # 0.4s x 40 u/s closes the last 10 units and then some
	if screen._combat == null:
		fail("closing inside ENCOUNTER_RADIUS did not launch a fight")
		return

	# A real scenes/main.tscn with a real roster and a live Encounter behind it.
	if screen._combat.spec.get("monsters", []).is_empty():
		fail("the fight got an empty spec: %s" % [screen._combat.spec])
	if screen._combat.cb == null or screen._combat.cb.combatants.is_empty():
		fail("no live combat (Encounter-built Combat) inside the combat scene")
	else:
		var foes: Array = screen._combat.cb.combatants.filter(func(c): return c.team == "foe")
		if foes.is_empty():
			fail("the live combat has no foes from the encountered party")
	if not screen.world.clock.is_paused():
		fail("the world clock kept running during the fight")
	var frozen: Vector2 = foe.position
	await step(5)
	if not foe.position.is_equal_approx(frozen):
		fail("parties kept moving on the map during the fight")

	# Win it the way scenes/main.gd's _finish() does — fill `result`.
	# O9 item 2: the haul has to actually land on the party.
	var gold0: int = screen.party.gold
	var xp0: int = screen.party.party_characters()[0].xp
	screen._combat.result = {"outcome": "Victory", "xp": 400, "gold": 50,
		"loot": ["handaxe"], "kills": []}
	await step(4)
	if screen.party.gold != gold0 + 50:
		fail("winning an open-world fight paid no gold (%d -> %d)" % [gold0, screen.party.gold])
	if screen.party.party_characters()[0].xp <= xp0:
		fail("winning an open-world fight banked no XP")
	if screen.party.stash_count("handaxe") < 1:
		fail("the loot from an open-world fight never reached the stash")
	if screen._combat != null:
		fail("the combat scene was never torn down after the fight")
	if screen.world.parties.has(foe):
		fail("the defeated party is still on the map")
	if screen.world.clock.is_paused():
		fail("the world clock did not resume after the fight")

	# A faction with no board of its own still gets a roster and a board.
	var World = load("res://core/world.gd")
	var spec: Dictionary = screen.encounter_spec(
		World.RoamingParty.new("cult", Vector2.ZERO, "cultist"))
	if spec.get("monsters", []).is_empty() or spec.get("theme", "") != screen.DEFAULT_THEME:
		fail("themeless faction got no usable spec: %s" % [spec])

	# ...and the map still runs: the player marches again.
	var back: Vector2 = p.position
	screen.world.set_goal(p, back + Vector2(200, 0))
	await step(5)
	if p.position.is_equal_approx(back):
		fail("the map is not playable again after combat")

func _done() -> void:
	print("drive_world: %s" % ["OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)

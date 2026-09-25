# Dev-only: the proof shots for docs/plan/2026-09-25-choices-with-teeth.md. Needs
# a display (the world and the board render 3D); not part of run_tests.sh. One
# shot per run, picked by SHOT:
#
#   SHOT=parley   xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --resolution 1600x1000 -s tests/shot_choices_teeth.gd
#   SHOT=deadline ...   SHOT=finished ...   SHOT=leave ...
#     -> docs/shots/choices-with-teeth-parley.png    a goblin band's card: parley's first round on the row
#     -> docs/shots/choices-with-teeth-deadline.png  the notice board: a bounty with its days
#     -> docs/shots/choices-with-teeth-finished.png  the company is finished: the closing screen
#     -> docs/shots/choices-with-teeth-leave.png     the edge tinted, Leave the field on the bar
extends SceneTree

const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Defeat = preload("res://core/defeat.gd")

func _init() -> void:
	await process_frame
	if OS.get_environment("SHOT") != "leave":   # the bar's hover card wants the real tooltip timing
		OS.set_environment("SORCMERC_FAST", "1")
	match OS.get_environment("SHOT"):
		"parley": await _parley()
		"deadline": await _deadline()
		"finished": await _finished()
		"leave": await _leave()
		_: printerr("SHOT=parley|deadline|finished|leave")
	quit()

func _world():
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()
	return s

func _parley() -> void:
	var s = await _world()
	s.party.gold = 200
	var p = s.world.player()
	var foe = World.RoamingParty.new("goblins-shot", p.position + Vector2(8, 0), "goblinoid")
	s.world.add_party(foe)
	s._open_approach(foe)
	for _i in 10:
		await process_frame
	await _save("docs/shots/choices-with-teeth-parley.png")

func _deadline() -> void:
	var s = await _world()
	s.party.gold = 300
	s._open_visit(s.world.settlements[0])
	s._goto_page("board")
	for _i in 12:
		await process_frame
	await _save("docs/shots/choices-with-teeth-deadline.png")

func _finished() -> void:
	var g = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(g)
	for _i in 10:
		await process_frame
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	for ch in party.roster:
		ch.dead = true
	var w := World.new()
	w.clock.elapsed = 11.4 * Defeat.DAY
	var last: Array = [party.active[0], party.active[1]]
	g.show_company_end(Defeat.ending(party, w, last))
	for _i in 10:
		await process_frame
	await _save("docs/shots/choices-with-teeth-finished.png")

func _leave() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	var cb = main.cb
	cb.can_withdraw = true
	var hero = cb.current() if cb.is_hero(cb.current()) else cb.heroes()[0]
	var taken: Array = cb.combatants.map(func(c): return c.pos)
	var foes: Array = cb.team_of("foe")
	var best: Vector2i = hero.pos
	var best_d := 1 << 30
	for e in cb.edge_hexes():   # the free edge hex nearest the hero, not beside a foe
		if e in taken or foes.any(func(f): return f.pos.distance_to(e) < 3):
			continue
		var d: int = abs(e.x - hero.pos.x) + abs(e.y - hero.pos.y)
		if d < best_d:
			best_d = d
			best = e
	hero.pos = best
	# make it their turn, so the board tints the edge for them
	for i in cb.order.size():
		if cb.order[i] == hero:
			cb.turn_idx = i
	hero.new_turn()
	hero.econ["move_left"] = 0   # they have walked to the edge already; what is left is the step off it
	main._busy = false
	main._mode = "idle"        # past the deployment phase: an ordinary turn
	main._deploy_pick = ""
	main._refresh()
	main._build_hero_menu(hero)
	print("hero ", hero.cname, " at ", hero.pos, " on edge: ", cb.on_edge(hero.pos), " refusal: '", cb.leave_refusal(hero), "'")
	for _i in 6:
		await process_frame
	var btn: Control = null
	for b in main._buttons.get_children():
		if String(b.get("tooltip_text")).begins_with("Leave the field"):
			btn = b
			print("leave button at index ", b.get_index(), " disabled: ", b.get("disabled"))
	if btn != null:
		# The bar's own hover card (scenes/skill_card.gd), built the way the
		# engine's tooltip builds it and stood over the badge — a pushed mouse
		# motion does not reach the tooltip timer under xvfb at this resolution.
		var card: Control = btn._make_custom_tooltip(btn.tooltip_text)
		var layer := CanvasLayer.new()
		layer.layer = 100
		root.add_child(layer)
		var holder := PanelContainer.new()
		holder.add_child(card)
		layer.add_child(holder)
		await process_frame
		holder.position = btn.get_global_rect().position + Vector2(0, -holder.size.y - 8)
		main._hover_verb = main.cb.all_verbs(hero).filter(func(v): return v["id"] == "leave_field")[0]
		main._board.queue_redraw()
	else:
		printerr("no Leave the field button on the bar")
	for _i in 4:
		await process_frame
	await _save("docs/shots/choices-with-teeth-leave.png")

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

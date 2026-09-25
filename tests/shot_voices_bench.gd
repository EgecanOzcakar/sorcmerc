# Dev-only: the pictures for voices-and-the-bench (the design audit §2.3, §2.4,
# §2.6; docs/plan/2026-09-25-voices-and-bench.md). Needs a display (the faces
# are 3D busts); not part of run_tests.sh.
#
#   godot --path . --resolution 1400x900 -s tests/shot_voices_bench.gd
#     -> docs/shots/voices-and-bench-relations.png   the web with the bench in a row, one restless
#     -> docs/shots/voices-and-bench-hover.png       a benched face hovered: their lines lift
#     -> docs/shots/voices-and-bench-restless.png    the warning card, on the live map
#     -> docs/shots/voices-and-bench-leaves.png      the leaving card, on the live map
#     -> docs/shots/voices-and-bench-fire.png        an inn's fire with a benched merc in the pair
extends SceneTree

const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Traits = preload("res://core/traits.gd")
const Bench = preload("res://core/bench.gd")
const Icons = preload("res://core/ui_icons.gd")
const RNG = preload("res://core/rng.gd")

const OUT := "res://docs/shots/voices-and-bench-%s.png"

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-bench-%d" % randi())
	OS.set_environment("SORCMERC_SEED", "7")
	OS.set_environment("SORCMERC_FAST", "")
	root.theme = Icons.dark_theme()
	await process_frame

	# 1. The party page: four marching, two on the bench, one of them restless.
	var screen = load("res://scenes/party/party.tscn").instantiate()
	root.add_child(screen)
	for _i in 10:
		await process_frame
	var p = screen.party
	for ch in p.roster:
		ch.traits_offered = true   # the one-time offer would cover the page
	var ids: Array = Array(p.active).duplicate()
	var bench: Array = p.bench_list().map(func(ch): return String(ch.id))
	if bench.size() < 2:
		p.bench(ids[3])
		bench = p.bench_list().map(func(ch): return String(ch.id))
		ids = Array(p.active).duplicate()
	var sets := [[ids[0], ids[1], -30.0], [ids[0], ids[2], 44.0], [ids[1], ids[2], 12.0],
		[bench[0], ids[0], 58.0], [bench[0], ids[1], -46.0], [bench[1], ids[2], 26.0]]
	for s in sets:
		PartyOpinion.set_score(p, s[0], s[1], s[2])
	Bench.sync(p, 0.0)
	p.world_now = 12.0 * Bench.DAY
	Bench.tick(p, p.world_now)   # the first of the bench has sat out long enough: warned
	screen._refresh()
	for _i in 40:
		await process_frame
	await _save("relations")
	var web = _find(screen, "RelationsWeb")
	if web != null:
		var i: int = web.ids().find(bench[0])
		web._set_hover(web.face_positions()[i])
		for _i in 4:
			await process_frame
		await _save("hover")
	screen.queue_free()
	await process_frame

	# 2. The live map: a company of five, Gera on the bench long enough.
	var party := Party.new()
	for ch in Party.demo_roster():
		ch.traits_offered = true
		party.add_member(ch)
	for pair in [["vera", "brave"], ["pike", "cautious"], ["ilsa", "generous"], ["thrun", "wrathful"], ["gera", "curious"]]:
		Traits.set_family(party.get_member(pair[0]), "temperament", pair[1])
	var game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await _settle()
	game.show_world(party)
	await _settle(1.5)
	var w = game._screen
	var now: float = w.world.clock.elapsed
	party.bench_clock = {"gera": {"since": now - Bench.RESTLESS_DAYS * Bench.DAY, "warned": false}}
	await _settle(0.8)   # _check_bench puts the warning up the first clear frame
	await _save("restless")
	if w._event_card != null:
		w._event_card.acknowledged.emit()
	await _settle()
	# ...and a morning she goes: the first day past the grace that says yes.
	var t := now + Bench.DAY
	while not Bench.leaves_today("gera", t):
		t += Bench.DAY
	w.world.clock.elapsed = t
	party.bench_clock["gera"]["since"] = t - (Bench.RESTLESS_DAYS + Bench.LEAVE_AFTER_DAYS) * Bench.DAY
	await _settle(0.8)
	await _save("leaves")
	if w._event_card != null:
		w._event_card.acknowledged.emit()
	await _settle()

	# 3. An inn's fire, with a benched merc in the pair. Put Gera back, benched.
	var gera = Party._demo_barbarian("gera", "Gera Ashvein", "human")
	gera.traits_offered = true
	Traits.set_family(gera, "temperament", "curious")
	party.roster.append(gera)
	party.bench_clock = {}
	PartyOpinion.set_score(party, "gera", "ilsa", 30.0)
	var m: Dictionary = {}
	for s in range(1, 500):
		var probe := party.relations.duplicate(true)
		m = PartyOpinion.camp_moment(party, RNG.new(s), true)
		if not m.is_empty() and not (m.get("benched", []) as Array).is_empty() and m["kind"] == "warming":
			break
		party.relations = probe
	w._camp_card("fireside", "At the fire", "good", String(m.get("text", "")), w._on_event_ack, "camp-night")
	await _settle(0.8)
	await _save("fire")
	quit()

func _settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func _find(n: Node, want: String) -> Node:
	for c in n.get_children():
		if String(c.name) == want:
			return c
		var hit := _find(c, want)
		if hit != null:
			return hit
	return null

func _save(what: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT % what)
	print("wrote ", OUT % what)

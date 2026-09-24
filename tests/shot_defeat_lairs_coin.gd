# Dev-only: the proof shots for docs/plan/2026-09-24-defeat-lairs-coin.md — the
# map's line after a lost fight (the dead stay dead), the inn's game once it has
# been played today (the result line and the refusal under the row), and a
# human band's approach card and failed parley (the opinion it costs). Needs a
# display (the world renders 3D); not part of run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 2800x1200x24" godot --path . --resolution 2800x1200 -s tests/shot_defeat_lairs_coin.gd
#   (wide: the map's bottom bar is one unwrapped row, and at 1400 the line runs off it)
#     -> docs/shots/defeat-lairs-coin-defeat.png        the map's line after the retreat
#     -> docs/shots/defeat-lairs-coin-gamble.png        the result line, and the refusal under Go
#     -> docs/shots/defeat-lairs-coin-parley-card.png   a human patrol's card: parley's cost on the row
#     -> docs/shots/defeat-lairs-coin-parley-failed.png the failed parley's line
extends SceneTree

const Approach = preload("res://core/approach.gd")
const Downtime = preload("res://core/downtime.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const RNG = preload("res://core/rng.gd")
const World = preload("res://core/world.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()

	# --- a lost fight: one of the marchers died in it ---------------------------
	s.party.gold = 400
	var fell: String = s.party.active[0]
	s.party.get_member(fell).dead = true
	s.party.bench(fell)
	s._retreat([fell])
	s.world.clock.pause()
	for _i in 4:
		await process_frame
	if not s._visit.is_empty():   # woke at the gate: the town opens over the map
		s._close_visit()
		s.world.clock.pause()
	for _i in 10:
		await process_frame
	await _save("docs/shots/defeat-lairs-coin-defeat.png")

	# --- the game, played today -------------------------------------------------
	var home = s.world.settlements[0]
	s.party.gold = 500
	s._open_visit(home)
	s._goto_page("inn")
	for _i in 10:
		await process_frame
	s._gamble(50)
	for _i in 10:
		await process_frame
	if s._event_card != null:   # a natural 1's insult is a card of its own
		s._event_card.acknowledged.emit()
		for _i in 6:
			await process_frame
	# The Downtime rows sit below the fold of the inn's page: bring the refusal
	# note (and the game's row above it) into view.
	for l in s.find_children("*", "Label", true, false):
		if String(l.text) == Downtime.gamble_refusal(s.party, s.world, home):
			for sc in s.find_children("*", "ScrollContainer", true, false):
				if sc.is_ancestor_of(l):
					sc.scroll_vertical = maxi(0, int(l.global_position.y - sc.global_position.y) + sc.scroll_vertical - 260)
	for _i in 4:
		await process_frame
	await _save("docs/shots/defeat-lairs-coin-gamble.png")
	s._close_visit()
	s.world.clock.pause()
	for _i in 6:
		await process_frame

	# --- a human patrol that has turned on the company --------------------------
	FactionOpinion.set_opinion("human", FactionOpinion.HOSTILE - 5.0)
	var p = s.world.player()
	var foe = World.RoamingParty.new("human-patrol", p.position + Vector2(8, 0), "human")
	s.world.add_party(foe)
	s._open_approach(foe)
	for _i in 10:
		await process_frame
	await _save("docs/shots/defeat-lairs-coin-parley-card.png")
	s._close_approach()
	# A roll that misses, found by seed; the card is the one world.gd shows.
	var r: Dictionary = {}
	for seed_v in range(1, 400):
		var before := FactionOpinion.get_opinion("human")
		r = Approach.resolve(s.party, foe, "parley", RNG.new(seed_v))
		if not bool(r.get("ok", true)):
			break
		FactionOpinion.set_opinion("human", before)
	s._event_card = load("res://scenes/world/event_card.gd").new()
	s.add_child(s._event_card)
	s._event_card.show_event(s._approach_event(r, "human"))
	for _i in 10:
		await process_frame
	await _save("docs/shots/defeat-lairs-coin-parley-failed.png")
	quit()

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

# Dev-only: the proof shots for docs/plan/2026-09-25-far-deeps.md — a new
# people's lair on the small map (the cult's chapel, drawn as its faction's
# kit), the crossing card into the Unmapped, and a fight against a CR 10+
# Deeps statblock with no figure of its own. Needs a display (the world renders
# 3D); not part of run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 -s tests/shot_far_deeps.gd
#     -> docs/shots/far-deeps-cult-lair.png       the Quiet Chapel, found, on the small map
#     -> docs/shots/far-deeps-unmapped.png        riding out into the Unmapped: the card and the bar
#     -> docs/shots/far-deeps-dragon-fight.png    a level 15 company against an adult dragon and a djinni
extends SceneTree

const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()

	# --- a new people's lair: the cult's, found ---------------------------------
	var chapel = null
	for l in s.world.lairs:
		if l.faction == "cultist":
			chapel = l
	chapel.discovered = true
	var p = s.world.player()
	var at: Vector2 = chapel.position + Vector2(-40, 30)
	p.position = at
	p.goal = at
	s.world.clock.resume()
	for _i in 12:
		await process_frame
	s.world.clock.pause()
	if s._event_card != null:            # the frontier's crossing card; not this shot
		s._event_card.acknowledged.emit()
	for _i in 6:
		await process_frame
	s.center_on(chapel.position + Vector2(-20, 15))
	s._check_lairs()
	for _i in 10:
		await process_frame
	await _save("docs/shots/far-deeps-cult-lair.png")

	# --- the Unmapped ------------------------------------------------------------
	var inner: Array = Regions.ring(s.world, "deeps")
	var outer: Array = Regions.ring(s.world, "unmapped")
	var dir := Vector2(0.2, 1.0).normalized()
	await _stand(s, Regions.anchor(s.world) + dir * (float(inner[0]) + 15.0))
	if s._event_card != null:
		s._event_card.acknowledged.emit()
	await _stand(s, Regions.anchor(s.world) + dir * ((float(outer[0]) + float(outer[1])) * 0.5))
	for _i in 10:
		await process_frame
	await _save("docs/shots/far-deeps-unmapped.png")
	s.queue_free()
	for _i in 4:
		await process_frame

	# --- a Deeps fight: CR 10+ statblocks, drawn without a figure -------------
	var main = load("res://scenes/main.tscn").instantiate()
	var party = Party.new()
	for ch in Presets.party_at(15):
		party.add_member(ch)
	main.party = party
	main.spec = {"monsters": [{"id": "adult-red-dragon", "count": 1}, {"id": "djinni", "count": 1}],
		"theme": "frozen-cave", "seed": 11}
	root.add_child(main)
	for _i in 60:
		await process_frame
	await create_timer(0.8).timeout
	await _save("docs/shots/far-deeps-dragon-fight.png")
	quit()

func _stand(s, pos: Vector2) -> void:
	var p = s.world.player()
	p.position = pos
	p.goal = pos
	s.world.clock.resume()
	for _i in 6:
		await process_frame
	s.world.clock.pause()
	s.center_on(pos)
	for _i in 4:
		await process_frame

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

# Dev-only: the party page's Relations web (scenes/party/relations_web.gd) —
# four marching, six pairs, one of every band, and a Brave and a Craven so a
# trait's spark shows on their line. Then the same page with the mouse on one
# face, which lifts that person's lines and dims the rest. Needs a display (the
# faces are 3D busts); not part of run_tests.sh.
#
#   godot --path . --resolution 1400x900 -s tests/shot_relations_web.gd
#     -> docs/shots/relations-web.png        every band at once
#     -> docs/shots/relations-web-hover.png  what everyone thinks of the second face
extends SceneTree

const PartyOpinion = preload("res://core/party_opinion.gd")
const Traits = preload("res://core/traits.gd")

func _init() -> void:
	await process_frame
	var screen = load("res://scenes/party/party.tscn").instantiate()
	root.add_child(screen)
	for _i in 10:
		await process_frame
	var p = screen.party
	var ids: Array = Array(p.active)
	for ch in p.party_characters():
		ch.traits_offered = true   # the one-time offer would cover the page
	Traits.set_family(p.get_member(ids[0]), "temperament", "brave")
	Traits.set_family(p.get_member(ids[1]), "temperament", "craven")
	var sets := [[0, 1, -52.0, ""], [0, 2, 38.0, ""], [0, 3, 74.0, "lovers"],
		[1, 2, -22.0, ""], [1, 3, 4.0, ""], [2, 3, 61.0, ""]]
	for s in sets:
		p.relations[PartyOpinion.key(ids[s[0]], ids[s[1]])] = {"score": s[2], "status": s[3]}
	screen._refresh()
	for _i in 40:   # the busts render once, a frame or two after they are asked for
		await process_frame
	await _save("docs/shots/relations-web.png")
	var web = _find(screen, "RelationsWeb")
	web._set_hover(web.face_positions()[1])
	for _i in 4:
		await process_frame
	await _save("docs/shots/relations-web-hover.png")
	quit()

func _find(n: Node, want: String) -> Node:
	for c in n.get_children():
		if String(c.name) == want:
			return c
		var hit := _find(c, want)
		if hit != null:
			return hit
	return null

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

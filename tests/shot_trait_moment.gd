# Dev-only: the pictures for #176's trait moment. Needs a display (the hero's
# figure is rendered 3D); not part of run_tests.sh.
#
#   SORCMERC_FAST=1 godot --path . --resolution 1400x900 -s tests/shot_trait_moment.gd
#     -> docs/shots/trait-moment-scar.png        a WIS save failed: Burn-shy
#     -> docs/shots/trait-moment-resilience.png  the same event's WIS save, a nat 20: Fire-tempered
#     -> docs/shots/trait-moment-triumph.png     no save, chance: Delver
# SORCMERC_FAST lands each one in its end state; without it the capture would
# catch the show halfway.
extends SceneTree

const TraitMoment = preload("res://scenes/world/trait_moment.gd")
const Presets = preload("res://core/presets.gd")
const Figures3D = preload("res://scenes/figures3d.gd")
const Icons = preload("res://core/ui_icons.gd")

func _init() -> void:
	# The main loop is not this tree yet while _init runs, and the portrait
	# renderer parks its viewport on Engine.get_main_loop().root.
	await process_frame
	var chars := {}
	for ch in Presets.party():
		chars[ch.id] = ch
	var bg := ColorRect.new()   # what the world would be behind it
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	await _shot({"cname": "Pike Sallow", "figure": _fig(chars["pike"]), "kind": "scar",
		"event": "Downed by the fire giant in the Ashen Hollow.",
		"save": {"ability": "wis", "dc": 18, "nat": 7, "bonus": 3},
		"trait": {"name": "Burn-shy", "text": "Pike still smells it. Anything that carries fire, he watches instead of fighting.",
			"effects": ["−1 to hit against anything that deals fire"],
			"cure": "down a fire-dealer yourself, then make this save again"},
		"line": "He got up. Something in him stayed down."}, "docs/shots/trait-moment-scar.png")
	await _shot({"cname": "Vera Kord", "figure": _fig(chars["vera"]), "kind": "resilience",
		"event": "Downed by the fire giant in the Ashen Hollow.",
		"save": {"ability": "wis", "dc": 18, "nat": 20, "bonus": 1},
		"trait": {"name": "Fire-tempered", "text": "The burn healed hard and white, and she is not afraid of the next one. Fire finds less of her to take now.",
			"effects": ["3 less fire damage from every hit"]},
		"line": "She came back from the fire tempered by it."}, "docs/shots/trait-moment-resilience.png")
	await _shot({"cname": "Ilsa Vane", "figure": _fig(chars["ilsa"]), "kind": "triumph",
		"event": "The Bloodfang warren is empty. She was first through every door.",
		"trait": {"name": "Delver", "text": "Knows how a lair breathes, and where it keeps its knives.",
			"effects": ["+1 to hit on a lair's boards", "+2 to search a lair's rooms"]}},
		"docs/shots/trait-moment-triumph.png")
	quit()

func _fig(ch) -> String:
	return Figures3D.model_path_for(ch.sheet(), "")

func _shot(m: Dictionary, path: String) -> void:
	var tm := TraitMoment.new()
	root.add_child(tm)
	tm.show_moments([m])
	for _i in 40:   # the portrait renders on a later frame (scenes/portraits.gd)
		await process_frame
	await create_timer(0.5).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
	tm.queue_free()
	await process_frame

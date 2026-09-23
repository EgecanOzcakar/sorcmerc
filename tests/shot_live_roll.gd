# Dev-only: the pictures for live rolls — a road check rolled in front of the
# player before the card says what happened. Needs a display; not part of
# run_tests.sh. Run WITHOUT SORCMERC_FAST, or there is no roll to catch:
#
#   godot --path . --resolution 1400x900 -s tests/shot_live_roll.gd
#     -> docs/shots/live-roll-tumbling.png   the die in the air, the outcome held back
#     -> docs/shots/live-roll-landed.png     the die down, the tally and the verdict
#     -> docs/shots/live-roll-open.png       the card opened on what happened
extends SceneTree

const EventCard = preload("res://scenes/world/event_card.gd")
const Icons = preload("res://core/ui_icons.gd")

const ROAD := {"id": "ford", "title": "A river in spate", "kind": "bad", "ok": true,
	"text": "Vera finds the old ford under the brown water and walks the party across it, rope to rope. Nobody goes under.",
	"char_id": "vera", "cname": "Vera Kord", "skill": "athletics", "nat": 16, "bonus": 5, "dc": 13,
	"named": true, "minutes": 30.0}

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "")
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var c := EventCard.new()
	root.add_child(c)
	c.show_event(ROAD)
	# mid-tumble
	for _i in 12:
		await process_frame
	await _save("docs/shots/live-roll-tumbling.png")
	# landed: finish the die but hold the card closed long enough to see it
	c._dice.landed.disconnect(c._reveal)   # hold the roll stage up for the picture: the landed die, before the card opens
	c._dice.finish()
	c._dice.queue_redraw()
	for _i in 4:
		await process_frame
	await _save("docs/shots/live-roll-landed.png")
	c._reveal()
	for _i in 6:
		await process_frame
	await _save("docs/shots/live-roll-open.png")
	quit()

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

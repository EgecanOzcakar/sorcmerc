# Dev-only: the pictures for the names-and-voice pass (the design audit §6,
# docs/plan/2026-09-24-names-and-voice.md). Needs a display; not part of
# run_tests.sh. Run WITHOUT SORCMERC_FAST, or the die has no roll to land:
#
#   godot --path . --resolution 1400x860 -s tests/shot_names_voice.gd
#     -> docs/shots/names-and-voice-title.png      the title screen, no debug door
#     -> docs/shots/names-and-voice-board.png      a town's board: hunts name the band
#     -> docs/shots/names-and-voice-approach.png   the approach card, titled with the name
#     -> docs/shots/names-and-voice-toast.png      an achievement card, renamed
#     -> docs/shots/names-and-voice-verdict.png    a landed die, said and not shouted
extends SceneTree

const EventCard = preload("res://scenes/world/event_card.gd")
const Icons = preload("res://core/ui_icons.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Ach = preload("res://core/achievements.gd")

const OUT := "res://docs/shots/names-and-voice-%s.png"

const ROAD := {"id": "ford", "title": "A river in spate", "kind": "bad", "ok": true,
	"text": "Vera finds the old ford under the brown water and walks the company across it, rope to rope. Nobody goes under.",
	"char_id": "vera", "cname": "Vera Kord", "skill": "athletics", "nat": 20, "bonus": 5, "dc": 13,
	"named": true, "minutes": 30.0}

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-voice-%d" % randi())
	OS.set_environment("SORCMERC_SEED", "7")
	OS.set_environment("SORCMERC_FAST", "")
	OS.set_environment("SORCMERC_DEBUG", "")
	root.theme = Icons.dark_theme()

	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var c := EventCard.new()
	root.add_child(c)
	c.show_event(ROAD)
	for _i in 6:
		await process_frame
	c._dice.landed.disconnect(c._reveal)   # hold the roll stage up: the landed die, before the card opens
	c._dice.finish()
	c._dice.queue_redraw()
	for _i in 4:
		await process_frame
	await shot("verdict")
	c.queue_free()
	bg.queue_free()
	await settle()

	var game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.show_title()
	await shot("title")

	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	var s = w.world.settlements[0]
	w._open_visit(s)
	w._goto_page("board")
	await shot("board")
	w._close_visit()
	await settle()

	var foe = null
	for q in w.world.parties:
		if not q.is_player and WorldAI.is_monster(q.faction) and not q.troops.is_empty():
			foe = q
			break
	w._open_approach(foe)
	await shot("approach")
	w._close_approach()
	await settle()

	var toasts = root.get_node_or_null("AchievementToasts")
	if toasts != null:
		toasts._show(Ach.find("explosive"))
		await settle(0.9)
		await shot("toast")
	quit()

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT % name)
	print("saved ", OUT % name)

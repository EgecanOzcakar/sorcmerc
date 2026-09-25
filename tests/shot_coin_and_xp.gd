# Dev-only: the proof shots for docs/plan/2026-09-25-coin-and-xp.md — a sheet
# with magic items on it (the AC and the swing move), the market's pack priced
# at a fifth of list by a neutral town and again by a friendly one, and the
# notice board quoting each job's XP beside its purse. Needs a display (the
# world renders 3D); not part of run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 2100x1000x24" godot --path . --resolution 2100x1000 -s tests/shot_coin_and_xp.gd
#   (wide: at 1600 the sheet's fourth column, the attacks, scrolls off the right)
#     -> docs/shots/coin-and-xp-sheet.png          Vera in a +1 shield, a +1 sword and a cloak of protection
#     -> docs/shots/coin-and-xp-sell.png           the pack at a stranger's price
#     -> docs/shots/coin-and-xp-sell-friendly.png  the same pack where the company is liked
#     -> docs/shots/coin-and-xp-board.png          jobs that pay XP by the country's fights
extends SceneTree

const FactionOpinion = preload("res://core/faction_opinion.gd")
const Icons = preload("res://core/ui_icons.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

const GOODS := ["plate", "weapon-1", "cloak-of-protection", "gauntlets-of-ogre-power",
	"potions-of-healing", "scroll-of-identification", "longsword"]

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	root.theme = Icons.dark_theme()

	# --- the sheet: the items are on it -----------------------------------------
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	var vera = party.get_member("vera")
	vera.equipped.assign(["longsword", "chain-mail", "shield-1", "weapon-1", "cloak-of-protection"])
	vera.dirty()
	for id in ["gauntlets-of-ogre-power", "ring-of-protection", "armor-1"]:
		party.stash_add(id)
	var prof = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(prof)
	prof.set_party(party)
	prof.set_character(vera)
	for _i in 20:
		await process_frame
	await _save("docs/shots/coin-and-xp-sheet.png")
	prof.queue_free()
	await process_frame

	# --- the market: what the pack sells for ------------------------------------
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()
	for id in GOODS:
		s.party.stash_add(id)
	var home = s.world.settlements[0]
	FactionOpinion.set_opinion(home.faction, 0.0)
	s._open_visit(home)
	s._goto_page("market")
	await _to_pack(s)
	await _save("docs/shots/coin-and-xp-sell.png")
	s._close_visit()
	s.world.clock.pause()
	FactionOpinion.set_opinion(home.faction, 80.0)
	s._open_visit(home)
	s._goto_page("market")
	await _to_pack(s)
	await _save("docs/shots/coin-and-xp-sell-friendly.png")

	# --- the board: XP beside the purse -----------------------------------------
	s._goto_page("board")
	for _i in 10:
		await process_frame
	await _save("docs/shots/coin-and-xp-board.png")
	quit()

# The pack sits under every counter's rows: scroll it into view.
func _to_pack(s) -> void:
	for _i in 10:
		await process_frame
	for l in s.find_children("*", "Label", true, false):
		if String(l.text) == "Your pack":
			for sc in s.find_children("*", "ScrollContainer", true, false):
				if sc.is_ancestor_of(l):
					sc.scroll_vertical = maxi(0, int(l.global_position.y - sc.global_position.y) + sc.scroll_vertical - 120)
	for _i in 4:
		await process_frame

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)

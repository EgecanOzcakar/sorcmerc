# Dev-only: the pictures for #176 step 1 — personality traits on every page they
# show on. Needs a display (the fight renders 3D); not part of run_tests.sh.
#
#   SORCMERC_FAST=1 SORCMERC_SEED=5 godot --path . --resolution 1400x900 -s tests/shot_traits.gd
#     -> docs/shots/traits-creator.png   the background step's two new rows
#     -> docs/shots/traits-offer.png     an older hero offered the pick once (party page)
#     -> docs/shots/traits-profile.png   the profile's Personality traits panel
#     -> docs/shots/traits-combat.png    a fight: the card's row and the log's line
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Settings = preload("res://core/settings.gd")
const Icons = preload("res://core/ui_icons.gd")


func _init() -> void:
	await process_frame
	root.theme = Icons.dark_theme()
	Settings.current().reaction_prompts = false
	await _creator()
	await _offer()
	await _profile()
	await _combat()
	quit()


func _shoot(path: String, frames := 30) -> void:
	for _i in frames:
		await process_frame
	await create_timer(0.4).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)


func _hero(id: String, name: String, bg: String) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = name
	ch.species_id = "human"
	ch.background_id = bg
	ch.add_level("fighter", -1)
	return ch


func _creator() -> void:
	var cre = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(cre)
	await process_frame
	cre.ch = Creator.new_character()
	cre.ch.cname = "Brenna Tide"
	cre._set_species("dwarf")
	cre._set_class("fighter")
	cre._set_background("sailor")
	cre._goto(3)
	await _shoot("docs/shots/traits-creator.png")
	cre.queue_free()
	await process_frame


func _offer() -> void:
	var p := Party.new()
	p.add_member(_hero("owen", "Owen Marsh", "farmer"))   # a save from before traits
	var page = load("res://scenes/party/party.tscn").instantiate()
	page.party = p
	root.add_child(page)
	await _shoot("docs/shots/traits-offer.png")
	page.queue_free()
	await process_frame


func _profile() -> void:
	var ch := _hero("brenna", "Brenna Tide", "sailor")
	Traits.fill_defaults(ch)
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_character(ch)
	await _shoot("docs/shots/traits-profile.png")
	p.queue_free()
	await process_frame


# The demo fight on the frozen cave, the presets given traits for the picture:
# Pike a Cave-dweller (counts here), Vera Brave and Downs-rider (only Brave's
# words, nothing that counts on this board).
func _combat() -> void:
	var party := Party.new()
	for ch in Presets.party():
		match ch.id:
			"pike":
				Traits.set_family(ch, "origin", "cave-dweller")
				Traits.set_family(ch, "temperament", "cautious")
			"vera":
				Traits.set_family(ch, "origin", "downs-rider")
				Traits.set_family(ch, "temperament", "brave")
			"ilsa":
				Traits.set_family(ch, "temperament", "calm")
				Traits.set_family(ch, "origin", "night-owl")
		party.add_member(ch)
	var Scaler = load("res://core/scaler.gd")
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = party
	main.spec = Scaler.roster_for(party.party_characters(), "normal", {}, "frozen-cave")
	main.spec["theme"] = "frozen-cave"
	root.add_child(main)
	var guard := 0
	while guard < 900:
		await process_frame
		guard += 1
		if main.cb == null or main.cb.is_over() or main._busy:
			continue
		if main._mode == "deploy":
			for b in main._buttons.get_children():
				if b is Button and not b.disabled and "Begin" in b.text:
					b.pressed.emit()
					break
			continue
		var cur = main.cb.current()
		if main._mode == "idle" and cur != null and cur.team == "party" and cur.conscious():
			break
	for c in main.cb.combatants:
		if c.id == "pike":
			main.board_hex_hovered(c.pos)
			break
	main._cam_follow = false
	main._board._auto_fit = true
	await _shoot("docs/shots/traits-combat.png")
	main.queue_free()
	await process_frame

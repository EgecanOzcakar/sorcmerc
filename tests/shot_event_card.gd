# Dev-only: one PNG per road event, under res://shots_tmp/ — the proof shot for
# anything that changes what core/travel.gd deals or what the card says about it.
#
#   godot --path . -s tests/shot_event_card.gd          # NOT --headless: the
#                                                       # capture hangs there,
#                                                       # same as shot_world.gd
#   SHOT_ONLY=shrine godot --path . -s tests/shot_event_card.gd    # just one
#
# Every card here is a REAL Travel.check() result, found by scanning seeds for
# the event and the side of its roll that is worth looking at, then handed
# straight to the card. Hand-built dicts would prove the card draws; these prove
# the two halves still agree about what the road deals.
extends SceneTree

const EventCard = preload("res://scenes/world/event_card.gd")
const Icons = preload("res://core/ui_icons.gd")
const Party = preload("res://core/party.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const Travel = preload("res://core/travel.gd")
const World = preload("res://core/world.gd")

# id -> [do we want the check passed, how far out the party is standing]. The
# fraction picks the D6 country, which is what decides whether an event is even
# on the table (EVENTS' `bands`): a wreck wants the marches, a toll post wants
# settled ground.
const WANTED := {
	"shrine": [true, 0.1], "carter": [true, 0.1], "toll": [false, 0.1],
	"waystone": [true, 0.1], "ford": [false, 0.1], "storm": [false, 0.1],
	"snare": [false, 0.1], "wreck": [true, 0.6], "tracks": [true, 0.6],
}
const FRAMES := 20        # let the Control lay itself out before the capture


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp"))
	root.theme = Icons.dark_theme()
	var only := OS.get_environment("SHOT_ONLY")
	for id in WANTED:
		if only != "" and only != id:
			continue
		var want: Array = WANTED[id]
		var e := _real_event(String(id), bool(want[0]), float(want[1]))
		if e.is_empty():
			printerr("no %s event found to render" % id)
			continue
		var card = EventCard.new()
		root.add_child(card)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.show_event(e)
		for i in FRAMES:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://shots_tmp/event_%s.png" % id)
		print("event_%s.png — %s" % [id, String(e.get("text", ""))])
		card.queue_free()
		await process_frame
	quit()


# A party wounded (so the shrine is on the table), a purse worth robbing, a map
# with a town and a lair on it, and the party standing `frac` of the way out.
func _real_event(id: String, want_ok: bool, frac: float) -> Dictionary:
	for seed_v in range(1, 2000):
		var p = _party()
		var w = _world(frac)
		var e: Dictionary = Travel.check(p, w, RNG.new(seed_v))
		if String(e.get("id", "")) == id and bool(e.get("ok", false)) == want_ok:
			return e
	return {}


func _party():
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.gold = 500
	for ch in p.party_characters():
		ch.hp_current = maxi(1, int(ch.sheet().max_hp * 0.5))
	return p


func _world(frac: float):
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_lair(World.Lair.new("blackfen-barrow", Vector2(300, 120), "undead"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.player().position = Vector2(Regions.extent(w) * frac, 0.0)
	return w

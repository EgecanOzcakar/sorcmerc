# O2 — the open-world map screen: draws core/world.gd's free 2D map in the same
# dimetric projection the combat board uses, with a drag-pan / scroll-zoom camera,
# a pause button on the WorldClock, and right-click-to-move for the player party.
# All state lives in core/world.gd; this only draws it and feeds it goals.
#
# Run standalone:  godot --path . scenes/world/world.tscn
#
# The projection math below is a copy of scenes/main.gd's Board._iso/_ring/_fan/
# _soft_shadow (~25 lines). It is duplicated rather than shared because those
# helpers are methods of main.gd's nested `Board extends Control` — they call
# draw_* on themselves and read Board._origin/main.hex_px — so factoring them out
# would mean editing scenes/main.gd, which this phase may not touch. The numbers
# (yaw/squash/gain, light direction) are the contract; keep them equal if either
# side ever changes. ponytail: a shared `core/iso.gd` is the upgrade path, and is
# cheap to do the day main.gd is in scope for edits.
extends Control

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBattle = preload("res://core/world_battle.gd")
const Settlements3D := preload("res://scenes/world/settlements3d.gd")
const Lairs3D := preload("res://scenes/world/lairs3d.gd")
const Party3D := preload("res://scenes/world/party3d.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")
const Visit = preload("res://core/settlement_visit.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Campaign = preload("res://core/campaign.gd")   # T25 item names/prices, and _split_xp
const Sound = preload("res://core/audio.gd")
const Quest = preload("res://core/quest.gd")
const RNG = preload("res://core/rng.gd")
const CharacterSave = preload("res://core/character_save.gd")
const WorldSave = preload("res://core/world_save.gd")

const COMBAT_SCENE := "res://scenes/main.tscn"
# O4 trigger distance, in world units. A party token draws at 9-11px before the
# projection's ISO_GAIN, i.e. ~6 world units of radius, so 24 is "the two tokens
# are visibly on top of each other" (~2 token diameters) at 1x, where a tick moves
# a party 4 units.
# O9 item 3: that "comfortably wider than a tick" reasoning only held at 1x. At 4x
# /8x a tick moves 16-32 units, so a pursuer matching the player's speed could sit
# a fixed 32 units behind forever and never trip a 24-unit trigger. _trigger() is
# the floor, widened to whatever the tick actually travelled.
const ENCOUNTER_RADIUS := 24.0
const ENCOUNTER_DIFFICULTY := "normal"
# O6 visit distance. Deliberately wider than ENCOUNTER_RADIUS: a settlement is a
# fixed landmark drawn at ~26 world units of radius (a city footprint) rather than
# a 6-unit token, so "close enough to walk in through the gate" is its own number.
# It is NOT widened by speed the way the encounter trigger is: a settlement is
# something you steer into on purpose, and marching past one at 8x without the
# market opening is the player's own choice, not a missed ambush.
const VISIT_RADIUS := 34.0
# The board an ambush happens on when the encountered faction has no theme of
# its own in Scaler.THEME_FACTION — open country, which is where the map is.
const DEFAULT_THEME := "forest-clearing"

const ISO_YAW := 35.0
const ISO_SQUASH := 0.38
const ISO_GAIN := 1.85
const LIGHT := Vector2(-0.30, -0.34)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
# O12: was 90, which read as a handful of huge diamonds at the default camera
# distance; 50 was picked by rendering tests/shot_world.gd at both (and at 60,
# still coarse) and looking.
# T-tiles: dropped hard, to 15 — much smaller tiles read as a smoother, less
# obviously-diamond-tiled field on the current (Screaming Brain Studios
# Overworld) pack this stayed on; the SBS Floor Pack spike (SORCMERC_ALT_TILES
# =sbs) was tried and set aside, not adopted. That's (50/15)^2 ~= 11.1x as many
# cells at any given zoom, so MAX_CELLS is scaled by the same factor to keep
# the same "give up and flat-fill" zoom threshold rather than tripping it
# sooner. MAX_CELLS is still not a free number: this viewport needs 783 cells
# at zoom 1.0 at CELL 50 (it needed 255 at CELL 90), and the old 900 was
# exactly "still paint at zoom 0.5, give up below it".
const CELL := 15.0          # ground patch size, in world units
const MAX_CELLS := 32000    # cap the ground loop when zoomed far out
# T-tiles: same terrain-variant pick clusters over a TILE_CLUSTER x TILE_CLUSTER
# block of cells instead of re-rolling every single one — large patches of one
# texture instead of a different tile every neighbour. Doubled from 4 to 8
# alongside CELL's halving so a patch still covers the same ~120x120 world
# units, not a smaller, choppier-looking one. The shoreline's own per-cell
# dither (_rand(cell, 9) below) is deliberately left alone — that's what frays
# the bank into an organic edge instead of a hard tile-aligned line,
# clustering it would make the water's edge blocky instead.
const TILE_CLUSTER := 8

# Ground: O11's Screaming Brain Studios Isometric Tiles Overworld pack, CC0.
# Buildings: O12's rubberduck isometric medieval buildings 1+2, CC0 — the Town
# pack they replace read as a modern city. See assets/world/README.md for
# provenance and the edits made to the files.
const TerrainTex := preload("res://assets/world/overworld/terrain.png")
const ForestTex := preload("res://assets/world/overworld/forest.png")
const BuildingTex := preload("res://assets/world/town/buildings.png")
# T-tiles spike: SORCMERC_ALT_TILES ("kenney" | "sbs") swaps in an
# alternate ground sheet instead of the Screaming Brain Studios Overworld one
# above. Neither is the new default — a comparison render is the point of a
# spike, not a swap.
#   "kenney" — Kenney's "Isometric Tiles Landscape" (CC0). See
#     assets/world/overworld_alt/PROVENANCE.md: Kenney's isometric line is
#     all raised-block art, so the top face is cropped out and reused flat,
#     which leaves a thin dirt sliver at each tile's front corner the
#     original flat pack never had.
#   "sbs" — Screaming Brain Studios' *other* free pack, "Isometric Floor
#     Pack" (also CC0, same author as the current terrain — see
#     assets/world/overworld_sbs/PROVENANCE.md). Genuine flat photo-textured
#     diamonds already at the exact 256x128/3-column layout this file
#     expects, no cropping workaround needed — the realistic-with-colour-pop
#     option (grass detail, floral accents, vivid water).
const TerrainTexAlt := preload("res://assets/world/overworld_alt/terrain_alt.png")
const ForestTexAlt := preload("res://assets/world/overworld_alt/forest_alt.png")
const WaterTexAlt := preload("res://assets/world/overworld_alt/water_alt.png")
const TerrainTexSbs := preload("res://assets/world/overworld_sbs/terrain_sbs.png")
const ForestTexSbs := preload("res://assets/world/overworld_sbs/forest_sbs.png")
const WaterTexSbs := preload("res://assets/world/overworld_sbs/water_sbs.png")

const TILE := Vector2(256, 128)   # one ground diamond in the Overworld sheets
const TILE_COLS := 3              # both sheets are 3x6 tiles
# The subsets of each 18-tile sheet the ground draws from. Both are deliberately
# narrow: the cell a tile lands in is picked by hash, with no terrain data behind
# it, so anything outside one colour family (the sheets' sand, bare rock and clay
# rows) tiles as a loud checkerboard instead of as one meadow. Forest is the one
# break in family, and is supposed to read as one.
const GRASS := [0, 1, 2, 9, 10]
const FOREST := [0, 1, 2, 3, 4, 5]
const WOODED := 0.78              # above this, a cell draws from FOREST
# O15: the Water sheet's left column — its blue-water pair. The other 15 tiles are
# the pack's swamp, ice and shallow-sand families, which next to grass read as
# three different lakes rather than one, the same reason GRASS/FOREST are narrow.
const WaterTex := preload("res://assets/world/overworld/water.png")
const WATER := [0, 3]
# Half-width of the shoreline band, in world units (~0.7 of a CELL either side).
# Across it a cell's chance of being water falls from 1 to 0, so the bank frays
# into the grass over a tile or so instead of ending on a cell boundary — the
# WOODED threshold's trick, with the noise compared against terrain rather than
# against a constant.
const SHORE := 35.0

# O12: one cell of the sheet tools/pack_buildings.py lays out — 5 columns (the
# pack's 5 medieval buildings, at their true relative sizes) by 4 rows (the
# camera rotations each ships). Each cell is pasted so the building's near
# ground corner sits on BUILDING_ANCHOR, which is what `base` means below.
const BUILDING := Vector2(128, 120)
const BUILDING_ANCHOR := Vector2(64, 112)
const BUILDING_STYLES := 5        # sheet columns: which building
const BUILDING_PAIRS := 4         # sheet rows: which way it faces

# O14: Kenney's Board Game Pack pawn, cropped to its own silhouette. Its art is
# flat near-white (243,243,243) with a darker rim, so one file tints to every
# faction — no per-colour sheet variant needed. PAWN.y/PAWN.x is its aspect.
const PawnTex := preload("res://assets/world/tokens/pawn.png")
const PAWN := Vector2(30, 53)

var world: World
var party: Party            # injected by whoever opens the map, or a demo roster
var _combat = null          # the live scenes/main.tscn instance, while fighting
var _combat_overlay: Control = null
var _pan := Vector2.ZERO
var _zoom := 1.0
var _origin := Vector2.ZERO
var _pause_btn: Button
var _speed_btn: Button
var _clock_lbl: Label
var _visit: Dictionary = {}      # the open market, or {}
var _visit_panel: Control = null
var _visit_log: Label = null
var _left: Object = null         # the settlement just left; no re-entry until out of range
var _party_overlay: Control = null   # T3's party/profile/inventory screen, full-screen
var _quest_panel: Control = null     # inline quest-log overlay, T9's Quest.active/describe
var _lair_btn: Button                # T91: "Search for a lair" / "Attack the lair", or hidden
var _lair_target: World.Lair = null  # whichever lair _check_lairs() last found in range
var _lair_msg: Label                 # the last search/loot outcome — persists past the
                                      # button's own text, which _check_lairs() overwrites every frame
var _settlements3d
var _lairs3d
var _party3d
# T-tiles spike: which ground sheets _draw_ground() actually samples — set once
# in _ready() from SORCMERC_ALT_TILES, since preload() can't be conditional on
# an env var the way a plain assignment can.
var _terrain_tex: Texture2D
var _forest_tex: Texture2D
var _water_tex: Texture2D
var world_size := "small"   # "small" | "large" — which built-in map _ready() falls back to
                             # when nobody injected a `world` (a fresh start, not O13's resume)

func _ready() -> void:
	match OS.get_environment("SORCMERC_ALT_TILES"):
		"kenney":
			_terrain_tex = TerrainTexAlt; _forest_tex = ForestTexAlt; _water_tex = WaterTexAlt
		"sbs":
			_terrain_tex = TerrainTexSbs; _forest_tex = ForestTexSbs; _water_tex = WaterTexSbs
		_:
			_terrain_tex = TerrainTex; _forest_tex = ForestTex; _water_tex = WaterTex
	if world == null:
		world = _large_world() if world_size == "large" else _small_world()
	if party == null:               # same demo roster scenes/campaign/campaign.gd falls back to
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
	_settlements3d = Settlements3D.new()
	_settlements3d.world_map = self
	add_child(_settlements3d)
	_settlements3d.reset(world)
	_lairs3d = Lairs3D.new()
	_lairs3d.world_map = self
	add_child(_lairs3d)
	_lairs3d.reset(world)
	_party3d = Party3D.new()
	_party3d.world_map = self
	add_child(_party3d)
	_party3d.reset(world)
	set_process(true)
	_build_hud()

# Hand-placed stand-ins so the scene has something to render and move. Real
# spawning is a later phase's job (O3 onward).
const LargeWorld = preload("res://scenes/world/large_world.gd")

func _large_world() -> World:
	return LargeWorld.build()

# T90: one settlement per playable race — dwarf/elf/human/orc, "for now" per
# the brief. Orc is the hostile one (world_ai.gd CIVILIZED), same role
# "cultist" had; the other three are the friendly, tradeable factions.
# T-worlds: kept as the small map once _large_world() existed to contrast it
# with — same content it always had, just renamed and no longer the only one.
func _small_world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "dwarf", "camp"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "orc", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "human", true))
	var bandits := w.add_party(World.RoamingParty.new("bandits", Vector2(-250, -120), "bandit"))
	# T-party3d: flavour rosters, for the overworld headcount label and Party3D's
	# model pick (highest-leveled troop) -- not combat stats, those still come
	# from Scaler.roster_for(faction). "goblins" has no dwarf/elf/human/orc
	# counterpart to model, so it keeps a roster (for the headcount) but reads
	# as no-model to Party3D and stays the plain PawnTex icon.
	bandits.troops = [{"role": "heavy", "level": 3}, {"role": "light", "level": 5}]
	WorldAI.hunt(bandits)
	var goblins := w.add_party(World.RoamingParty.new("goblins", Vector2(380, 300), "goblinoid"))
	goblins.troops = [{"role": "heavy", "level": 1}, {"role": "heavy", "level": 1}, {"role": "light", "level": 2}]
	WorldAI.hunt(goblins)
	var patrol := w.add_party(World.RoamingParty.new("patrol", Vector2(-120, 380), "human"))
	patrol.troops = [{"role": "heavy", "level": 2}, {"role": "heavy", "level": 2}]
	WorldAI.patrol(patrol, [Vector2(-120, 380), Vector2(-360, 260), Vector2(0, 0)])
	# O15 terrain: one lake northwest of Riverhold, and the river it drains into —
	# which runs past Riverhold's west wall and down to Ashfell, so the town's name
	# is finally standing next to something. World.waters only knows circles, so the
	# river is blobs stamped along a polyline; spacing is well under the radius, so
	# they merge into one band with a scalloped (not machined) bank.
	w.add_water(Vector2(-190, -70), 100.0)
	var river := PackedVector2Array([Vector2(-110, -20), Vector2(-40, 100),
		Vector2(-10, 210), Vector2(60, 320), Vector2(140, 400)])
	for i in river.size() - 1:
		for t in 5:
			w.add_water(river[i].lerp(river[i + 1], t / 5.0), 40.0)
	w.add_water(river[-1], 40.0)

	# T91: five hidden monster lairs — the initial roster the brief named. Hidden
	# until a Survival check finds them (WorldLairs.DISCOVER_RADIUS), then
	# attackable like a hostile settlement's guard for their own stash.
	w.add_lair(World.Lair.new("goblin-warren", Vector2(560, 60), "goblinoid"))
	w.add_lair(World.Lair.new("giant-hold", Vector2(-520, -260), "giant"))
	w.add_lair(World.Lair.new("sunken-ruins", Vector2(-280, -340), "undead", "Sunken Ruins"))
	w.add_lair(World.Lair.new("zombie-graveyard", Vector2(300, 620), "undead", "Zombie Graveyard"))
	w.add_lair(World.Lair.new("dragon-cave", Vector2(680, -400), "dragon", "Dragon's Cave"))
	return w

# World.tick() advances the clock itself and gates movement on it, so one call
# per frame is the whole update.
func _process(delta: float) -> void:
	# O7: the clock's own advance (0 while paused) both drains O6's queued opinion
	# deltas off the settlements and runs the slow drift back toward neutral.
	var dt := world.tick(delta)
	FactionOpinion.tick(world, dt)
	WorldAI.update(world, delta)
	_check_encounter(dt)
	# O5: NPC-vs-NPC meetings resolve instantly, no scene, no pause — but not
	# while the player's own fight has the map frozen.
	if _combat == null and not world.clock.is_paused():
		# O6 feeds off the outcome: a settlement near the corpses reads differently
		# on the next visit. O5's resolution itself is untouched.
		for r in WorldBattle.check(world, _trigger(dt), encounter_spec):
			Visit.mark_battle(world, r["loser"].position, world.clock.elapsed)
	_check_visit()
	_check_lairs()
	if _clock_lbl != null:
		_clock_lbl.text = "Day %d  %02d:%02d" % [
			int(world.clock.elapsed / 1440.0) + 1,
			int(world.clock.elapsed / 60.0) % 24, int(world.clock.elapsed) % 60]
	queue_redraw()

# --- HUD ---------------------------------------------------------------
func _build_hud() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	_pause_btn = Button.new()
	_pause_btn.text = "Pause"
	_pause_btn.pressed.connect(_toggle_pause)
	bar.add_child(_pause_btn)
	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.pressed.connect(_cycle_speed)
	bar.add_child(_speed_btn)
	_clock_lbl = Label.new()
	_clock_lbl.add_theme_color_override("font_color", Icons.COL_GOLD)
	bar.add_child(_clock_lbl)
	var party_btn := Button.new()
	party_btn.text = "Party"
	party_btn.pressed.connect(_open_party)
	bar.add_child(party_btn)
	var quests_btn := Button.new()
	quests_btn.text = "Quests"
	quests_btn.pressed.connect(_toggle_quests)
	bar.add_child(quests_btn)
	var title := Button.new()
	title.text = "←  Title"
	title.pressed.connect(_leave_world)
	bar.add_child(title)
	_lair_btn = Button.new()
	_lair_btn.visible = false
	_lair_btn.pressed.connect(_lair_action)
	bar.add_child(_lair_btn)
	var hint := Label.new()
	hint.text = "right-click: march here   ·   drag: pan   ·   wheel: zoom"
	hint.add_theme_color_override("font_color", Icons.COL_MUTED)
	bar.add_child(hint)
	_lair_msg = Label.new()
	_lair_msg.add_theme_color_override("font_color", Icons.COL_ACCENT)
	bar.add_child(_lair_msg)

# O9 item 2: the only way out of the open world. The characters go to the barracks
# (what the title screen's count reads); O13: the map, the party's purse/stash/quests
# and faction opinion go to core/world_save.gd's slot, which the title screen's
# "Resume the open world" reads back. Opinion is process-global, so it is still
# cleared here once saved — the next thing to run must not inherit this run's.
func _leave_world() -> void:
	for ch in party.roster:
		CharacterSave.save(ch)
	WorldSave.save(world, party)
	FactionOpinion.reset()
	# Duck-typed so world.tscn still runs standalone (godot --path . scenes/world/
	# world.tscn), where the parent is the scene root and has no title screen.
	var host := get_parent()
	if host != null and host.has_method("show_title"):
		host.show_title()

# O9 item 7: both are no-ops while a market panel is open. The visit owns the
# clock (it paused it); letting the button resume the world underneath an open
# panel desynced the label and set the map running behind it.
func _toggle_pause() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null:
		return
	if world.clock.is_paused():
		world.clock.resume()
	else:
		world.clock.pause()
	_pause_btn.text = "Resume" if world.clock.is_paused() else "Pause"

func _cycle_speed() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null:
		return
	world.clock.cycle_speed()
	_speed_btn.text = "%dx" % int(world.clock.speed)   # every WorldClock.SPEEDS entry is a whole number

# --- party / profile / inventory ----------------------------------------
#
# Reuses T3's scenes/party/party.tscn as-is (per-character profile/inventory is
# already one click deeper from there) — same overlay shape campaign.gd's own
# _open_party() uses. Pauses the clock while open: browsing gear shouldn't cost
# world-time or let a hunt close in behind the menu.

const PARTY_SCENE := "res://scenes/party/party.tscn"

func _open_party() -> void:
	if _combat != null or not _visit.is_empty() or _party_overlay != null:
		return
	world.clock.pause()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_party_overlay = overlay
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	overlay.add_child(screen)
	var back := Button.new()
	back.text = "←  Back to the map"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -220; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(_close_party)
	overlay.add_child(back)

func _close_party() -> void:
	if _party_overlay != null:
		_party_overlay.queue_free()
		_party_overlay = null
	world.clock.resume()
	_pause_btn.text = "Pause"

# --- quest log ------------------------------------------------------------
#
# Same data campaign.gd's own quest panel reads (Quest.active/describe) — an
# inline toggle rather than a full-screen overlay, since it's just a list.

func _toggle_quests() -> void:
	if _quest_panel != null:
		_close_quests()
		return
	if _combat != null or not _visit.is_empty() or _party_overlay != null:
		return
	world.clock.pause()
	_build_quest_panel()

func _close_quests() -> void:
	if _quest_panel != null:
		_quest_panel.queue_free()
		_quest_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _build_quest_panel() -> void:
	if _quest_panel != null:
		_quest_panel.queue_free()
	var panel := PanelContainer.new()
	# No anchor preset: default anchors are top-left (0), so `position` is a plain
	# pixel offset from the parent's origin — set_anchors_preset(PRESET_CENTER)
	# used to also be called here, which re-centers the control on its OWN anchor
	# point and resets the offsets, so this same centering math then applied a
	# second time on top of it and shoved the panel off-screen.
	panel.position = size * 0.5 - Vector2(200, 160)
	panel.custom_minimum_size = Vector2(400, 320)
	add_child(panel)
	_quest_panel = panel
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "Quest log"
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 240)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	var live: Array = Quest.active(party)
	if live.is_empty():
		var none := Label.new()
		none.text = "No quests. Settlements have work."
		none.add_theme_color_override("font_color", Icons.COL_MUTED)
		rows.add_child(none)
	for q in live:
		var l := Label.new()
		l.text = Quest.describe(q)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color",
			Icons.COL_GOLD if q["state"] == "complete" else Icons.COL_PARTY)
		rows.add_child(l)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_quests)
	box.add_child(close)

# --- O4: encounter trigger + combat hand-off ---------------------------

# O9 item 3: the trigger distance for this tick — never below ENCOUNTER_RADIUS,
# but at least as wide as the ground two parties covered in it, so a pursuit at a
# stable gap still closes at 4x/8x. Same number for the player's trigger and O5's
# NPC-vs-NPC one, since both are "two tokens met between two frames".
# ponytail: assumes every party moves at World.SPEED (RoamingParty.speed's default).
# Take the pair's own speeds the day a party moves at its own rate.
func _trigger(dt: float) -> float:
	return maxf(ENCOUNTER_RADIUS, World.SPEED * 2.0 * dt)

# ponytail: linear scan over 3-8 parties once a frame, same as world_ai.gd's hunt.
func _check_encounter(dt := 0.0) -> void:
	if _combat != null or world.clock.is_paused():
		return
	var p := world.player()
	if p == null:
		return
	var reach := _trigger(dt)
	for q in world.parties:
		if q == p or not WorldAI.is_hostile(q, p):
			continue
		if q.position.distance_to(p.position) <= reach:
			_launch_combat(q)
			return

# The roster the encountered party fights with. Scaler takes a *theme*, not a
# faction, so: THEME_FACTION reversed gives a matching board for the factions
# that have one; for the rest (soldier/orc/cultist/...) there is no theme, and
# _faction_order's other documented route — FACTIONS[seed % size] — is snapped
# onto this faction instead. Seeded off the party id, so meeting the same band
# twice is the same band.
func encounter_spec(foe) -> Dictionary:
	var theme := ""
	for t in Scaler.THEME_FACTION:
		if String(Scaler.THEME_FACTION[t]) == foe.faction:
			theme = String(t)
			break
	var seed_v: int = absi(hash(foe.id))
	if theme == "":
		var idx: int = Scaler.FACTIONS.find(foe.faction)
		if idx >= 0:
			seed_v = seed_v - seed_v % Scaler.FACTIONS.size() + idx
	var spec: Dictionary = Scaler.roster_for(
		party.party_characters(), ENCOUNTER_DIFFICULTY, {}, theme, seed_v)
	spec["theme"] = theme if theme != "" else DEFAULT_THEME
	return spec

# The same hand-off scenes/campaign/campaign.gd's _launch_combat() does: the map
# freezes, scenes/main.tscn runs the fight unchanged, `result` comes back.
func _launch_combat(foe) -> Dictionary:
	world.clock.pause()
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	_combat.spec = encounter_spec(foe)
	_combat.difficulty = ENCOUNTER_DIFFICULTY
	_combat_overlay.add_child(_combat)

	while _combat != null and _combat.result.is_empty():
		await get_tree().process_frame
	if _combat == null:
		return {}
	var result: Dictionary = _combat.result
	_combat = null
	_combat_overlay.queue_free()
	_combat_overlay = null
	if String(result.get("outcome", "")) == "Victory":
		_bank(result)
		world.parties.erase(foe)      # beaten; O5 will do the same for NPC-vs-NPC
		# T91: a no-op for the settlement-guard/lair-raid stand-ins below (their
		# synthetic ids never match a live hunt_party quest's target), correct
		# for an actual hostile roaming party from _check_encounter.
		Quest.record_party_defeated(party, foe.id)
		# O7 raise/lower event: putting down a monster band is a favour to whoever
		# lives near the bodies; putting down a faction's own band is not.
		if WorldAI.is_monster(foe.faction):
			FactionOpinion.credit_fight(world, foe.position, FactionOpinion.FOUGHT_FOR, foe.faction)
		else:
			FactionOpinion.lower(foe.faction, FactionOpinion.KILLED_THEIRS)
	else:
		_retreat()
	world.clock.resume()
	WorldSave.save(world, party)   # O13 autosave: a fight is the biggest thing that
	                               # happens to a run — never re-fight it after a crash
	return result

# O9 item 2: a won fight has to actually pay, or the run is a dead end. The same
# four things core/campaign.gd's finish_combat() banks, minus the linear run's own
# bookkeeping (node gold, achievements, autosave, the journal):
#   XP  — Campaign._split_xp(), which is the even split *plus* T22's lifetime/class
#         progression and the level-up chime. It only touches `party`, so a bare
#         Campaign.new(party) is enough to reach it.
#         ponytail: it is an instance method on a file O9 may not edit. Make it
#         static (and drop the throwaway) the day campaign.gd is in scope.
#   gold, loot, quest progress — party-level calls, made directly.
func _bank(result: Dictionary) -> void:
	Campaign.new(party)._split_xp(int(result.get("xp", 0)))
	party.add_gold(int(result.get("gold", 0)))
	for item in result.get("loot", []):
		party.stash_add(String(item))
	# Without this an accepted quest can never reach "complete", so O9 item 4's
	# turn-in row would have nothing to turn in.
	Quest.record_kills(party, result.get("kills", []),
		RNG.new(maxi(1, int(world.clock.elapsed) + 1)))

# Defeat/retreat, deliberately the cheapest thing that keeps the map playable:
# the party falls back to the nearest settlement and stops there. No losses, no
# gold, no wound state — a real defeat-consequences system is O7's business once
# faction opinion exists to hang it on.
func _retreat() -> void:
	var p := world.player()
	if p == null or world.settlements.is_empty():
		return
	var safe: Vector2 = world.settlements[0].position
	for s in world.settlements:
		if p.position.distance_squared_to(s.position) < p.position.distance_squared_to(safe):
			safe = s.position
	p.position = safe
	world.set_goal(p, safe)

# --- O6: settlement visit ----------------------------------------------
# Same shape as _check_encounter above, against the settlement list instead of
# the party list. `_left` stops the panel reopening on the frame after Leave —
# it clears once the player is actually outside the radius again.
func _check_visit() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		return
	var p := world.player()
	if p == null:
		return
	for s in world.settlements:
		if s.position.distance_to(p.position) > VISIT_RADIUS:
			if s == _left:
				_left = null
			continue
		if s == _left:
			continue
		# O7 effect 3: past FactionOpinion.GUARDS_ATTACK the gate guards come out
		# instead of the market opening — O4's encounter path, with the garrison
		# standing in as the party (it is not on the map, so beating it just ends
		# the fight).
		# O9 item 5: that used to fire at HOSTILE, above REFUSE_TRADE, so the market's
		# refusal branch could never be reached. It has its own lower floor now.
		# O9 item 6: and a monster faction's town never trades at any opinion — its
		# own bands attack the player on sight (WorldAI.is_hostile), so its gate does
		# too. Same gate _check_encounter() uses.
		if WorldAI.is_monster(s.faction) or FactionOpinion.guards_attack(s.faction):
			_left = s
			_settlement_guard_fight(s)
			return
		_open_visit(s)
		return

# --- T91: monster lairs -------------------------------------------------
# Same "one button, updated every frame the player is in range" shape as the
# visit gate above, but two states instead of one: undiscovered offers a
# Survival check, discovered-and-unlooted offers the fight. A looted lair (or
# nothing in range) hides the button — there is nothing left to do there.
func _check_lairs() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		_lair_btn.visible = false
		return
	var p := world.player()
	if p == null:
		_lair_btn.visible = false
		return
	var undiscovered = WorldLairs.nearby_undiscovered(world, p.position)
	var target = undiscovered
	if target == null:
		for l in world.lairs:
			if l.discovered and not l.looted and l.position.distance_to(p.position) <= WorldLairs.DISCOVER_RADIUS:
				target = l
				break
	_lair_target = target
	if target == null:
		_lair_btn.visible = false
		return
	_lair_btn.visible = true
	_lair_btn.text = ("Search for a hidden lair (Survival)" if not target.discovered
		else "Attack %s" % target.sname)

func _lair_action() -> void:
	var l: World.Lair = _lair_target
	if l == null or _combat != null:
		return
	if not l.discovered:
		var roll := WorldLairs.search(l, party)
		if roll.is_empty():
			return
		if roll["ok"]:
			_lair_msg.text = "%s finds the tracks — %s is here (Survival %d+%d vs DC %d)." % [
				roll["cname"], l.sname, roll["nat"], roll["bonus"], roll["dc"]]
		else:
			_lair_msg.text = "Nothing this time (Survival %d+%d vs DC %d)." % [
				roll["nat"], roll["bonus"], roll["dc"]]
		return
	var result: Dictionary = await _launch_combat(World.RoamingParty.new("%s-raid" % l.id, l.position, l.faction))
	if String(result.get("outcome", "")) == "Victory":
		var loot: Dictionary = WorldLairs.loot(l)
		party.add_gold(int(loot.get("gold", 0)))
		Quest.record_lair_cleared(party, l.id)
		_lair_msg.text = "%s is cleared out — +%d gold from its stash." % [l.sname, int(loot.get("gold", 0))]

# T91: split out of _check_visit so it can await the fight — the stand-in id
# ("%s-guard") never matches a hunt_party quest's target, so raid_settlement
# is recorded here with the settlement's own id rather than in _launch_combat.
func _settlement_guard_fight(s) -> void:
	var result: Dictionary = await _launch_combat(World.RoamingParty.new("%s-guard" % s.id, s.position, s.faction))
	if String(result.get("outcome", "")) == "Victory":
		Quest.record_settlement_raided(party, s.id)

func _open_visit(s) -> void:
	world.clock.pause()
	world.set_goal(world.player(), world.player().position)   # stop at the gate
	_visit = Visit.visit(s, world)
	_build_visit_panel()

func _close_visit() -> void:
	_left = _visit.get("settlement")
	_visit = {}
	if _visit_panel != null:
		_visit_panel.queue_free()
		_visit_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	WorldSave.save(world, party)   # O13 autosave: the purse and the shelf both moved

func _buy(item_id: String) -> void:
	if Visit.buy(_visit, party, item_id):
		Sound.play_sfx("buy")
		_build_visit_panel()
	else:
		_say("Not enough gold.")

func _sell(item_id: String) -> void:
	if Visit.sell(_visit, party, item_id):
		_build_visit_panel()

# O9 item 1: one attempt per visit. The steal roll is seeded off (settlement, hour)
# and the clock is paused for the whole visit, so every press rolled the identical
# result — a nat 20 was an unlimited gold button. The mark lives on `_visit`, so
# Leave and come back is a fresh attempt (at a fresh hour).
func _steal() -> void:
	if _visit.get("stolen", false):
		_say("They are watching the stall now. Come back another day.")
		return
	var r: Dictionary = Visit.steal(_visit["settlement"], party, world, _visit)
	_visit["stolen"] = true
	if bool(r.get("ok", false)):
		Sound.play_sfx("pickup")
	_build_visit_panel()
	_say(String(r.get("text", "Nobody here has the hands for it.")))

# O9 item 2: the inn. Time is the cost — see SettlementVisit.rest — and the extra
# hours restock the shelf, so the market is re-read afterwards.
func _rest() -> void:
	var s = _visit["settlement"]
	var stolen: bool = _visit.get("stolen", false)
	Visit.rest(party, world)
	Sound.play_sfx("rest")
	_visit = Visit.visit(s, world)
	_visit["stolen"] = stolen
	_build_visit_panel()
	_say("The party takes a long rest. Eight hours pass and the stalls fill up again.")

# O9 item 4: T9's quest verbs, reached from a settlement at last.
func _take_quest() -> void:
	var q: Dictionary = Visit.quest_offer(_visit["settlement"], party, world)
	if Quest.accept(party, q):
		_build_visit_panel()
		_say("Job taken: %s" % q["title"])
	else:
		_say("No work here just now.")

func _turn_in(quest: Dictionary) -> void:
	var reward: int = int(quest.get("reward", {}).get("gold", 0))
	if Quest.turn_in(party, quest, _visit["settlement"].faction):
		Sound.play_sfx("buy")
		_build_visit_panel()
		_say("%s — paid, +%d gp. They will remember it." % [quest["title"], reward])

# The panel is rebuilt after every action, so the last line has to live on the
# visit rather than on the Label that just got freed.
func _say(text: String) -> void:
	if not _visit.is_empty():
		_visit["log"] = text
	if _visit_log != null:
		_visit_log.text = text

func _build_visit_panel() -> void:
	if _visit_panel != null:
		_visit_panel.queue_free()
	var s = _visit["settlement"]
	var panel := PanelContainer.new()
	# Default (top-left) anchors: `position` is a plain pixel offset from the
	# parent's origin. set_anchors_preset(PRESET_CENTER) used to be called here
	# too, which re-centers on its own and resets the offsets — this same
	# centering math then applied again on top of that shoved the panel
	# off-screen (see the same fix in _build_quest_panel just above).
	panel.position = size * 0.5 - Vector2(230, 230)
	panel.custom_minimum_size = Vector2(460, 460)
	add_child(panel)
	_visit_panel = panel
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "%s — %s" % [s.sname, ", ".join(_visit["services"])]
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	box.add_child(title)
	var mood := Label.new()
	mood.text = "Shelves %d/%d · prices x%.2f%s%s · your purse: %d gp" % [
		_visit["steps"], Visit.MAX_STEPS, _visit["markup"],
		"  (fighting nearby)" if _visit["battle"] else "",
		"  (they will not trade with you)" if _visit.get("refused", false) else "",
		party.gold]
	mood.add_theme_color_override("font_color", Icons.COL_MUTED)
	box.add_child(mood)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 320)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	for e in _visit["stock"]:
		_trade_row(rows, "%s — %d gp" % [e["name"], e["price"]], "Buy",
			_buy.bind(String(e["item_id"])))
	for entry in party.stash:
		var id := String(entry["item_id"])
		var paid := Visit.sell_price(_visit, id)
		if paid <= 0:
			continue
		_trade_row(rows, "%s x%d — sells for %d gp" % [
			Campaign.item_name(id), int(entry["quantity"]), paid], "Sell", _sell.bind(id))

	# O9 item 4: one offer, one row per finished job. Quest.offer_for()/turn_in() as
	# they stand; nothing here decides anything about quests.
	var offer: Dictionary = Visit.quest_offer(s, party, world)
	if not offer.is_empty():
		_trade_row(rows, "Job: %s — %d gp" % [
			offer["title"], int(offer.get("reward", {}).get("gold", 0))], "Take", _take_quest)
	for q in Visit.turn_ins(party):
		_trade_row(rows, "✔ %s" % Quest.describe(q), "Turn in", _turn_in.bind(q))

	_visit_log = Label.new()
	_visit_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_visit_log.custom_minimum_size = Vector2(440, 34)
	box.add_child(_visit_log)
	_visit_log.text = String(_visit.get("log", ""))
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var rest_btn := Button.new()
	rest_btn.text = "Rest the night"
	rest_btn.pressed.connect(_rest)
	bar.add_child(rest_btn)
	var steal_btn := Button.new()
	var spent: bool = _visit.get("stolen", false)
	steal_btn.text = "Stole from the market" if spent else "Steal from the market"
	steal_btn.disabled = spent
	steal_btn.pressed.connect(_steal)
	bar.add_child(steal_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_close_visit)
	bar.add_child(leave)

func _trade_row(rows: VBoxContainer, text: String, action: String, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(330, 0)
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = action
	btn.pressed.connect(on_press)
	row.add_child(btn)
	rows.add_child(row)

# --- projection (see header) -------------------------------------------
func _iso(v: Vector2) -> Vector2:
	var r := v.rotated(deg_to_rad(ISO_YAW)) * ISO_GAIN
	return Vector2(r.x, r.y * ISO_SQUASH)

func _iso_inv(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y / ISO_SQUASH).rotated(-deg_to_rad(ISO_YAW)) / ISO_GAIN

# world point -> screen point
func _pix(w: Vector2) -> Vector2:
	return _origin + _iso(w) * _zoom

# screen point -> world point, the inverse of _pix
func _unpix(sp: Vector2) -> Vector2:
	return _iso_inv((sp - _origin) / _zoom)

func _ring(center: Vector2, r: float, flat := true, closed := false, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var v := Vector2(cos(TAU * i / segs), sin(TAU * i / segs)) * r
		pts.append(center + (_iso(v) if flat else v))
	if closed:
		pts.append(pts[0])
	return pts

func _fan(apex: Vector2, rim: PackedVector2Array, inner: Color, outer: Color) -> void:
	var n := rim.size()
	var cols := PackedColorArray([inner, outer, outer])
	var uv := PackedVector2Array()
	for i in n:
		draw_primitive(PackedVector2Array([apex, rim[i], rim[(i + 1) % n]]), cols, uv)

func _soft_shadow(at: Vector2, r: float, strength := 1.0) -> void:
	for i in 3:
		draw_colored_polygon(_ring(at, r * (1.0 + 0.26 * i)),
			Color(0.02, 0.01, 0.04, strength * (0.20 - 0.05 * i)))

# Stable per-cell noise: same cell, same salt -> same value, every frame.
static func _rand(c: Vector2i, salt: int) -> float:
	var n: int = hash(Vector3i(c.x, c.y, salt))
	return float(n % 4096) / 4096.0 if n >= 0 else float(-n % 4096) / 4096.0

# Quantizes a cell to its TILE_CLUSTER x TILE_CLUSTER block so every cell in
# that block feeds _rand() the same coordinate — one texture roll per patch of
# ground instead of one per tile. floor(), not int(), because cell indices run
# negative in every direction from the origin and int()'s truncation-toward-
# zero would put -1 and -4 in the same "cluster" as 0..3.
static func _cluster(c: Vector2i, n: int) -> Vector2i:
	return Vector2i(int(floor(float(c.x) / n)), int(floor(float(c.y) / n)))

# A faction's colour, straight off its name's hash so no table needs maintaining
# as core/scaler.gd's FACTIONS list grows.
static func faction_color(faction: String, is_player := false) -> Color:
	if is_player:
		return Icons.COL_PARTY
	return Color.from_hsv(float(absi(hash(faction)) % 360) / 360.0, 0.52, 0.78)

# --- camera ------------------------------------------------------------
func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)

func pan_by(d: Vector2) -> void:
	_pan += d

# zoom keeping the world point under `sp` fixed
func zoom_at(sp: Vector2, factor: float) -> void:
	var anchor := _unpix(sp)
	set_zoom(_zoom * factor)
	_layout()
	pan_by(sp - _pix(anchor))
	_layout()      # _origin follows _pan; keep them in step for the next _unpix

func _layout() -> void:
	_origin = size * 0.5 + _pan

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			pan_by(e.relative)
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(e.position, 1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(e.position, 1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var p := world.player()
			if p != null:
				world.set_goal(p, _unpix(e.position))
		queue_redraw()

# --- drawing -----------------------------------------------------------
func _draw() -> void:
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Icons.COL_BG)
	_draw_ground()
	var p := world.player()
	if p != null and not p.at_goal():
		draw_polyline(_ring(_pix(p.goal), 9.0 * _zoom, true, true, 18), Icons.COL_GOLD, 1.5, true)

	# One painter's-order pass over everything standing on the ground.
	var props: Array = []
	for s in world.settlements:
		props.append({"at": _pix(s.position), "s": s})
	for l in world.lairs:
		if l.discovered:   # T91: undiscovered lairs draw nothing — that's the point
			props.append({"at": _pix(l.position), "l": l})
	for q in world.parties:
		if q.is_player and not _visit.is_empty():
			continue   # inside the gates for the duration of the visit, not standing on the map
		props.append({"at": _pix(q.position), "p": q})
	props.sort_custom(func(a, b): return a["at"].y < b["at"].y)
	for d in props:
		if d.has("s"):
			_draw_settlement(d["s"], d["at"])
		elif d.has("l"):
			_draw_lair(d["l"], d["at"])
		else:
			_draw_party(d["p"], d["at"])

# O11: one Overworld Pack tile per ground cell, on the same grid the procedural
# patches used. ISO_YAW is 35°, not the 45° the art is drawn for, so a cell lands
# on screen as a sheared parallelogram rather than a 2:1 diamond — the tile is
# mapped onto it by an affine transform (its diamond's corners to the cell's
# corners) instead of being blitted upright. The projection stays the contract;
# the art bends to it, so tiles line up with the camera and click-to-move math.
func _draw_ground() -> void:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var w := _unpix(corner)
		mn = mn.min(w); mx = mx.max(w)
	var i0 := int(floor(mn.x / CELL)); var i1 := int(ceil(mx.x / CELL))
	var j0 := int(floor(mn.y / CELL)); var j1 := int(ceil(mx.y / CELL))
	if (i1 - i0 + 1) * (j1 - j0 + 1) > MAX_CELLS:   # far-out zoom: don't paint the world
		draw_rect(Rect2(Vector2.ZERO, size), Color("4a5333"))   # the tiles' own average
		return
	# The cell's two projected edges. _iso is linear, so these are the same for
	# every cell and the whole grid is one transform plus a translation per tile.
	var ex := _iso(Vector2(CELL, 0)) * _zoom
	var ey := _iso(Vector2(0, CELL)) * _zoom
	draw_set_transform_matrix(Transform2D((ex + ey) / TILE.x, (ey - ex) / TILE.y, _origin))
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var cell := Vector2i(i, j)
			var cl := _cluster(cell, TILE_CLUSTER)
			# 1.0 deep in a lake, 0.0 well inland, a ramp across the bank between.
			var wet := 0.5 - world.water_depth(Vector2(i + 0.5, j + 0.5) * CELL) / (SHORE * 2.0)
			var tex := _terrain_tex
			var pool: Array = GRASS
			# Left un-clustered on purpose: this per-cell dither is what frays the
			# bank into an organic edge (see TILE_CLUSTER's own comment above).
			if _rand(cell, 9) < wet:
				tex = _water_tex
				pool = WATER
			elif _rand(cl, 5) > WOODED:
				tex = _forest_tex
				pool = FOREST
			var idx: int = pool[int(_rand(cl, 1) * pool.size()) % pool.size()]
			draw_texture_rect_region(tex,
				Rect2(Vector2(i + j, j - i - 1) * TILE * 0.5, TILE),
				Rect2(Vector2(idx % TILE_COLS, idx / TILE_COLS) * TILE, TILE))
	draw_set_transform_matrix(Transform2D.IDENTITY)

# O11/O12: a medieval building on each footprint the blocks stood on — a city
# gets three, a town two, painter-sorted among themselves. The footprint ring
# stays: every faction's walls are the same stone, and faction is the one thing
# the map still has to read at a glance.
# T91: a discovered lair. Grey once looted, faction-tinted red while there's
# still a fight in it, so a glance says which lairs are done. Tier 0: a 3D
# diorama in the Lairs3D layer above this map, same contract as Settlements3D
# — it replaces the "☠" glyph only; shadow, ring and name label stay shared.
func _draw_lair(l, at: Vector2) -> void:
	var col := Icons.COL_MUTED if l.looted else Icons.COL_FOE
	var r := 14.0 * _zoom
	_soft_shadow(at, r * 0.85)
	_fan(at + _iso(LIGHT) * r * 0.5, _ring(at, r), col.darkened(0.35), col.darkened(0.62))
	draw_polyline(_ring(at, r, true, true), col.darkened(0.15), 1.5, true)
	if not (_lairs3d and _lairs3d.has_model(l)):
		var fs := int(18 * _zoom)
		draw_string(ThemeDB.fallback_font, at - Vector2(fs * 0.35, -fs * 0.3), "☠",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Icons.COL_HEAD)
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), l.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)

func _draw_settlement(s, at: Vector2) -> void:
	var col := faction_color(s.faction)
	var big: bool = s.kind == "city"
	# T90: "camp" is the smallest tier (one lean-to, no ring flourish scale-up) —
	# everything below city was "town" before there were three sizes.
	var small: bool = s.kind == "camp"
	var r := (26.0 if big else (12.0 if small else 17.0)) * _zoom
	_soft_shadow(at, r * 0.9)
	_fan(at + _iso(LIGHT) * r * 0.5, _ring(at, r), col.darkened(0.35), col.darkened(0.62))
	draw_polyline(_ring(at, r, true, true), col.darkened(0.15), 1.5, true)
	# Style off the faction so a faction's towns look like each other, pair off the
	# id so two of its towns are not the same building twice.
	var style: int = absi(hash(s.faction))
	var pair: int = absi(hash(s.id))
	var blocks := [Vector2(0, 0), Vector2(-0.5, 0.35), Vector2(0.5, 0.3)] if big \
		else ([Vector2(0, 0)] if small else [Vector2(0, 0), Vector2(0.45, 0.3)])
	var h := r * (3.2 if big else (2.4 if small else 2.8))
	# BUILDING_ANCHOR sits near the sprite's bottom (112 of 120px tall), so a house
	# drawn at `base` reads as mostly-above it — a cluster whose bases sit on the
	# ring reads as pushed toward the ring's back half. Nudge every base down by
	# the gap between the anchor and the sprite's true vertical centre so the
	# cluster's visual mass, not its ground corner, is what centres on the ring.
	var vcenter := Vector2(0.0, (BUILDING_ANCHOR.y - BUILDING.y * 0.5) * 0.3 * h / BUILDING.y)
	# Tier 0: a 3D diorama in the Settlements3D layer above this map. Same
	# contract as Figures3D on the combat board — it replaces the building
	# blocks only; shadow, ring and name label above/below stay shared.
	if not (_settlements3d and _settlements3d.has_model(s)):
		var bases: Array = []
		for b in blocks:
			bases.append(at + _iso(b * r) + vcenter)
		bases.sort_custom(func(a, b): return a.y < b.y)
		for k in bases.size():
			_draw_building(bases[k], h, style + k, pair + k)
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), s.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)

# One building: a whole house in one cell now (the old Town Pack's modular
# left/right wall halves are gone with it). `base` is the house's near ground
# corner, i.e. the point it stands on; `h` scales the cell, whose own 128x120
# proportions are kept so the five buildings stay at their relative sizes.
func _draw_building(base: Vector2, h: float, style: int, pair: int) -> void:
	var cell := BUILDING * (h / BUILDING.y)
	var src := Vector2(style % BUILDING_STYLES, pair % BUILDING_PAIRS) * BUILDING
	draw_texture_rect_region(BuildingTex,
		Rect2(base - BUILDING_ANCHOR * (h / BUILDING.y), cell), Rect2(src, BUILDING))

# O14: a board-game pawn standing on the party's position, tinted to its faction.
# `at` is the ground point, so the sprite hangs above it rather than centring on
# it, the way a building sits on its near corner. Sizes are the old ball token's
# radii kept as the token's half-width, so parties read at the same scale as before.
func _draw_party(p, at: Vector2) -> void:
	var col := faction_color(p.faction, p.is_player)
	var rad := (11.0 if p.is_player else 9.0) * _zoom
	var h := rad * 2.0 * PAWN.y / PAWN.x
	_soft_shadow(at, rad * 0.8)
	if p.is_player:   # under the sprite, so the ring's far arc reads as behind the pawn
		draw_polyline(_ring(at, rad * 1.7), Icons.COL_GOLD, 1.5, true)
	# Tier 0: a 3D troop figure in the Party3D layer above this map, picked from
	# the band's highest-leveled troop — same contract as Settlements3D/Lairs3D,
	# replaces the PawnTex icon (and its faction tint) only.
	if not (_party3d and _party3d.has_model(p)):
		draw_texture_rect(PawnTex, Rect2(at - Vector2(rad, h - rad * 0.22),
			Vector2(rad * 2.0, h)), false, col)
	# T-party3d: name + headcount, floating below the token — same label
	# treatment World._draw_settlement()/_draw_lair() already use. The player's
	# own headcount comes off the real Party (active roster), everyone else's
	# off their troops[] flavour roster (RoamingParty.highest_troop's source).
	var count: int = party.active.size() if p.is_player else p.troops.size()
	var label: String = "You" if p.is_player else p.id.capitalize()
	draw_string(ThemeDB.fallback_font, at + Vector2(-rad * 1.3, rad * 1.3 + 12.0),
		"%s (%d)" % [label, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)

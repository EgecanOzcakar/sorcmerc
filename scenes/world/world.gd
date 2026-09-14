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
const Minimap := preload("res://scenes/world/minimap.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")
const Visit = preload("res://core/settlement_visit.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Rumors = preload("res://core/rumors.gd")
const Site = preload("res://core/site.gd")
const SiteScreen = preload("res://scenes/world/site_screen.gd")
const WorldThreat = preload("res://core/world_threat.gd")
const Regions = preload("res://core/regions.gd")
const Travel = preload("res://core/travel.gd")
const EventCard = preload("res://scenes/world/event_card.gd")
const Approach = preload("res://core/approach.gd")
const ApproachCard = preload("res://scenes/world/approach_card.gd")
const StoryCard = preload("res://scenes/world/story_card.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const Trance = preload("res://core/trance.gd")
const WorldForage = preload("res://core/world_forage.gd")
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
# D1: what the open country throws at you is no longer a fixed tier. Sites are
# the hard content now (core/site.gd), and a party walking out of a cleared lair
# at a third of its HP has to be able to reach a town — so the wilderness reads
# the party's condition and scales down toward a floor (core/world_threat.gd).
# It can only ever scale DOWN, and a weaker roster pays proportionally less XP
# (encounter.gd's xp = power * XP_PER_POWER), so nothing is gained by staying
# hurt. The old flat "normal" is what world_threat.gd's BASELINE replaces.
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
# T9x: two fog tiers. Never explored is flat and near-black (opaque — there's
# no tile underneath to show). Explored-but-not-currently-visible is a
# translucent dark tint OVER the real tile (drawn on top of it, not instead
# of it), so the shape and color of ground you've already seen still reads,
# just dimmed — distinct from both full fog and full daylight.
const FOG_UNKNOWN := Color(0.03, 0.03, 0.045)
const FOG_REMEMBERED := Color(0.05, 0.05, 0.09, 0.55)

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
# T9x: which settlement screen is showing — "hub" (the town square, where
# you pick a place to go), "market", "inn", or "board" (the notice board,
# T9x's quest board). Reset to "hub" every time a new visit opens; each
# action handler's _build_visit_panel() call just re-renders whichever page
# is current, same as before the split.
var _visit_page := "hub"
# T9y: which counter the Market page is showing — MARKET_TAB_ALL, or one of
# the settlement's own Campaign.SERVICE_ORDER services. Scene-local like
# _visit_page, and reset with it: which stall you were last standing at is
# not worth a save-format field.
var _market_tab := MARKET_TAB_ALL
var _visit_panel: Control = null
var _visit_log: Label = null
var _left: Object = null         # the settlement just left; no re-entry until out of range
var _party_overlay: Control = null   # T3's party/profile/inventory screen, full-screen
var _quest_panel: Control = null     # inline quest-log overlay, T9's Quest.active/describe
var _lair_btn: Button                # T91: "Search for a lair" / "Attack the lair", or hidden
var _lair_sneak_btn: Button          # T9x: "Slip past the guardians" — visible once discovered, unlooted
var _lair_target: World.Lair = null  # whichever lair _check_lairs() last found in range
var _site = null                     # D1: the delve in progress (core/site.gd), or null
# D3: last road-event roll, and the card showing one. Scene-local like the
# forage stamp — a reload just restarts the cadence, which is not worth a
# save-format field for something that fires every six world-hours anyway.
var _last_travel_at: float = 0.0
var _event_card: Control = null
# D4: the band the player is deciding how to meet, and the card asking. Bands
# slipped past go on `_slipped` so walking away does not immediately re-trigger
# the same meeting — the settlement gate's `_left` does the same job.
var _approach_foe = null
var _approach_card: Control = null
var _slipped := {}
var _pace_btn: Button
var _site_screen: Control = null     # ...and the descent screen drawing it
# D6: the country the party is standing in, and the label that says so. `_region`
# is last frame's band — a crossing is the only thing anybody wants to be told
# about, and you cannot notice one without remembering where you were.
var _region: Dictionary = {}
var _warned_bands := {}              # bands already warned about; a seam you step over
                                     # twice is not news twice
var _region_lbl: Label
var _region_msg: Label               # the last crossing, same "persists" contract as _lair_msg

var _lair_msg: Label                 # the last search/loot outcome — persists past the
                                      # button's own text, which _check_lairs() overwrites every frame
var _camp_msg: Label                 # T9x: last short-rest/camp outcome, same "persists" contract as _lair_msg
var _camp_btn: Button                # T9x: "Make camp" — visible only while the party owns a camp kit
# T9x: last WorldForage.check() cadence stamp — scene-local, not saved. A
# reload just resets the four-hour clock; harmless, not worth a save-format
# field for an ambient bonus this small.
var _last_forage_at: float = 0.0
var _settlements3d
var _lairs3d
var _party3d
var _minimap: Control = null   # T9y: the corner map inset, see _layout_minimap()
# T-tiles spike: which ground sheets _draw_ground() actually samples — set once
# in _ready() from SORCMERC_ALT_TILES, since preload() can't be conditional on
# an env var the way a plain assignment can.
var _terrain_tex: Texture2D
var _forest_tex: Texture2D
var _water_tex: Texture2D
# M7: the content pack's story, mid-telling — a core/mod/story_runtime.gd
# injected by scenes/game/game.gd alongside the map it belongs to, or null for
# every run on a built-in map. Everything below treats null as "no story", so a
# normal run costs one `if` per frame and nothing else.
var story = null
var story_card: Control = null       # the beat being shown, or null
var _story_panel: Control = null     # the journal overlay, toggled off the HUD
var _story_btn: Button

var world_size := "small"   # "small" | "large" — which built-in map _ready() falls back to
                             # when nobody injected a `world` (a fresh start, not O13's resume)

func _ready() -> void:
	theme = Icons.dark_theme()   # standalone runs; under game.gd it is the same theme inherited
	match OS.get_environment("SORCMERC_ALT_TILES"):
		"kenney":
			_terrain_tex = TerrainTexAlt; _forest_tex = ForestTexAlt; _water_tex = WaterTexAlt
		"sbs":
			_terrain_tex = TerrainTexSbs; _forest_tex = ForestTexSbs; _water_tex = WaterTexSbs
		_:
			_terrain_tex = TerrainTex; _forest_tex = ForestTex; _water_tex = WaterTex
	if world == null:
		match world_size:
			"large": world = _large_world()
			"procedural": world = ProceduralWorld.build(int(OS.get_environment("SORCMERC_SEED")))
			_: world = _small_world()
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
	_last_forage_at = world.clock.elapsed   # T9x: start the cadence from load time, not zero
	_last_travel_at = world.clock.elapsed   # D3: same, for road events
	set_process(true)
	_build_hud()
	_refresh_pace_btn()

# Hand-placed stand-ins so the scene has something to render and move. Real
# spawning is a later phase's job (O3 onward).
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

func _large_world() -> World:
	return LargeWorld.build()

# T90: one settlement per playable race — dwarf/elf/human/orc, "for now" per
# the brief. Orc is the hostile one (world_ai.gd CIVILIZED), same role
# "cultist" had; the other three are the friendly, tradeable factions.
# T-worlds: kept as the small map once _large_world() existed to contrast it
# with — same content it always had, just renamed and no longer the only one.
func _small_world() -> World:
	var w := World.new()
	w.origin = {"kind": "small", "seed": 0}   # which builder made this map; survives a save (core/world_save.gd)
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "dwarf", "camp"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "orc", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "human", true))
	# T9y: was (-250, -120), which is 22 units deep in the lake stamped below —
	# invisible while water was cosmetic, a band standing in a lake the moment
	# water became terrain. Moved to the same corner, 70 units clear of the bank.
	var bandits := w.add_party(World.RoamingParty.new("bandits", Vector2(-320, -180), "bandit"))
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
	# D6.1: was (560, 60) — frac 0.71, out in the Frontier, which is two countries
	# from a goblinoid's own (Regions.HOMES). That left the Heartland holding
	# Riverhold and nothing else: the band built for levels 1-3 had no destination
	# in it at all, and the first thing a new party could walk to was Marches
	# content built for level 3-6. Pulled in to frac 0.45, clear of every
	# settlement, both banks of the river, and the lake.
	w.add_lair(World.Lair.new("goblin-warren", Vector2(330, 130), "goblinoid"))
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
	var p0 := world.player()
	if p0 != null:
		world.reveal(p0.position)   # T9x fog of war: permanent once seen
		# D3: the marching order IS the speed, re-read every frame so changing
		# it on the party screen takes effect the moment you back out.
		p0.speed = World.SPEED * Travel.speed_mult(party)
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
	_check_story()
	_check_lairs()
	_check_expired_lairs()
	_check_forage()
	_check_travel()
	_check_region()
	if _camp_btn != null:
		_camp_btn.visible = party.stash_count(WorldCamp.CAMP_KIT_ITEM) > 0
	_layout_minimap()   # this Control resizes with the window; the inset follows the corner
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
	_clock_lbl.theme_type_variation = "Stat"
	_clock_lbl.add_theme_color_override("font_color", Icons.COL_GOLD)
	bar.add_child(_clock_lbl)
	# D6: which country this is and who it is for, always on. A band that only
	# announced itself at the seam would be invisible to a player who saved in
	# the frontier and came back a week later.
	_region_lbl = Label.new()
	_region_lbl.theme_type_variation = "Dim"
	bar.add_child(_region_lbl)
	var party_btn := Button.new()
	party_btn.text = "Party"
	party_btn.pressed.connect(_open_party)
	bar.add_child(party_btn)
	var quests_btn := Button.new()
	quests_btn.text = "Quests"
	quests_btn.pressed.connect(_toggle_quests)
	bar.add_child(quests_btn)
	# M7: only a run that is telling a story has a story to read.
	_story_btn = Button.new()
	_story_btn.text = "Story"
	_story_btn.visible = story != null
	_story_btn.pressed.connect(_toggle_story)
	bar.add_child(_story_btn)
	var title := Button.new()
	title.text = "Title"
	title.theme_type_variation = "Quiet"
	title.pressed.connect(_leave_world)
	bar.add_child(title)
	_lair_btn = Button.new()
	_lair_btn.visible = false
	_lair_btn.pressed.connect(_lair_action)
	bar.add_child(_lair_btn)
	_lair_sneak_btn = Button.new()
	_lair_sneak_btn.text = "Slip past the guardians (Animal Handling)"
	_lair_sneak_btn.visible = false
	_lair_sneak_btn.pressed.connect(_lair_sneak_action)
	bar.add_child(_lair_sneak_btn)
	# T9x: short rest works anywhere (when safe) — always visible, _short_rest()
	# itself says why not rather than the button toggling in and out.
	_pace_btn = Button.new()
	_pace_btn.pressed.connect(_cycle_pace)
	bar.add_child(_pace_btn)
	var shortrest_btn := Button.new()
	shortrest_btn.text = "Short Rest"
	shortrest_btn.pressed.connect(_short_rest)
	bar.add_child(shortrest_btn)
	_camp_btn = Button.new()
	_camp_btn.text = "Make Camp"
	_camp_btn.visible = false   # only while the party owns a camp kit — see _process()
	_camp_btn.pressed.connect(_make_camp)
	bar.add_child(_camp_btn)
	var hint := Label.new()
	hint.text = "Right-click marches there.  Drag pans, wheel zooms."
	hint.theme_type_variation = "Dim"
	bar.add_child(hint)
	_region_msg = Label.new()
	_region_msg.theme_type_variation = "Serif"
	_region_msg.add_theme_color_override("font_color", Icons.COL_ACCENT)
	bar.add_child(_region_msg)
	_lair_msg = Label.new()
	_lair_msg.theme_type_variation = "Serif"
	_lair_msg.add_theme_color_override("font_color", Icons.COL_ACCENT)
	bar.add_child(_lair_msg)
	_camp_msg = Label.new()
	_camp_msg.theme_type_variation = "Serif"
	_camp_msg.add_theme_color_override("font_color", Icons.COL_ACCENT)
	bar.add_child(_camp_msg)
	# T9y: the map inset. Added last so it sits above the 2D map but below the
	# visit/party/quest overlays, which are added later still; it places itself
	# nowhere, so _layout_minimap() below owns the corner it lives in.
	_minimap = Minimap.new()
	_minimap.world_map = self
	add_child(_minimap)
	_layout_minimap()

# Bottom-right, inside the same 12px gutter the top-left button bar uses, and
# re-run every frame because this Control resizes with the window.
const MINIMAP_GUTTER := 12.0
func _layout_minimap() -> void:
	if _minimap == null:
		return
	var want: Vector2 = Minimap.DEFAULT_SIZE
	# Never let the inset eat the map on a small window: a third of the shorter
	# side is the ceiling, and below MINIMAP_MIN it is not worth drawing at all.
	var cap: float = minf(size.x, size.y) / 3.0
	if cap < MINIMAP_MIN:
		_minimap.visible = false
		return
	_minimap.visible = true
	var side: float = minf(want.x, cap)
	_minimap.size = Vector2(side, side * want.y / want.x)
	_minimap.position = size - _minimap.size - Vector2(MINIMAP_GUTTER, MINIMAP_GUTTER)
const MINIMAP_MIN := 96.0

# O9 item 2: the only way out of the open world. The characters go to the barracks
# (what the title screen's count reads); O13: the map, the party's purse/stash/quests
# and faction opinion go to core/world_save.gd's slot, which the title screen's
# "Resume the open world" reads back. Opinion is process-global, so it is still
# cleared here once saved — the next thing to run must not inherit this run's.
# M7: one place that knows what an autosave carries, now that it also carries
# how far into its story a run is. Every call site used to spell out
# `WorldSave.save(world, party)`; there were twelve of them.
func _autosave() -> void:
	WorldSave.save(world, party, story)

func _leave_world() -> void:
	for ch in party.roster:
		CharacterSave.save(ch)
	_autosave()
	FactionOpinion.reset()
	# Duck-typed so world.tscn still runs standalone (godot --path . scenes/world/
	# world.tscn), where the parent is the scene root and has no title screen.
	var host := get_parent()
	if host != null and host.has_method("show_title"):
		host.show_title()

# O9 item 7: both are no-ops while a market panel is open. The visit owns the
# clock (it paused it); letting the button resume the world underneath an open
# panel desynced the label and set the map running behind it. M7's beat card
# and journal own it the same way, for the same reason.
func _toggle_pause() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null \
			or _story_panel != null or story_card != null:
		return
	if world.clock.is_paused():
		world.clock.resume()
	else:
		world.clock.pause()
	_pause_btn.text = "Resume" if world.clock.is_paused() else "Pause"

func _cycle_speed() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null \
			or _story_panel != null or story_card != null:
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
	_party3d.reset(world)   # T9x: picking a new overworld figure only takes effect on rebuild

# --- quest log ------------------------------------------------------------
#
# Same data campaign.gd's own quest panel reads (Quest.active/describe) — an
# inline toggle rather than a full-screen overlay, since it's just a list.

func _toggle_quests() -> void:
	if _quest_panel != null:
		_close_quests()
		return
	if _combat != null or not _visit.is_empty() or _party_overlay != null \
			or _story_panel != null or story_card != null:
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
	panel.theme_type_variation = "Gilt"
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
	title.theme_type_variation = "Head"
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
		none.theme_type_variation = "Dim"
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

# --- M7: the story ---------------------------------------------------------
#
# Polled, once a frame, exactly like the lair/forage/travel checks above it —
# core/mod/story_runtime.gd asks the live world and party what is true and
# hands back whatever just became eligible. Nothing publishes an event and
# nothing subscribes, which is why a content pack can tell a story about
# systems that have never heard of it.

func _check_story() -> void:
	if story == null or story_card != null:
		return
	# A beat interrupts the map, so it waits its turn behind anything else that
	# already has: a fight, a market, the party screen, the quest log, a road
	# event, a band asking to be dealt with.
	if _combat != null or not _visit.is_empty() or _party_overlay != null \
			or _quest_panel != null or _story_panel != null \
			or _event_card != null or _approach_card != null or _site_screen != null:
		return
	var pending: Array = story.pending(world, party)
	if pending.is_empty():
		if not story.advance(world, party).is_empty():
			_autosave()
		return
	var beat: Dictionary = pending[0]
	var lines: Array = story.fire(beat, world, party)
	# A beat with nothing to show (a `note` that only set a flag) must not
	# stop a map at 8x for a blank card.
	if beat.get("lines", []).is_empty() and lines.is_empty() \
			and beat.get("choices", []).is_empty():
		story.advance(world, party)
		_autosave()
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	story_card = StoryCard.new()
	add_child(story_card)
	story_card.chosen.connect(_on_story_choice.bind(beat))
	story_card.show_beat(story, beat, lines, world, party)

func _on_story_choice(choice_id: String, beat: Dictionary) -> void:
	if choice_id != "":
		story.choose(beat, choice_id, world, party)
	story.advance(world, party)
	if story_card != null:
		story_card.queue_free()
		story_card = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	# A beat can hand over a quest, move the purse and put a lair on the map:
	# everything an autosave exists to remember.
	_autosave()

# The journal: the synopsis, where the story has got to, and every line it has
# written down. Same inline-overlay shape as the quest log next to it.
func _toggle_story() -> void:
	if _story_panel != null:
		_close_story()
		return
	if story == null or _combat != null or not _visit.is_empty() \
			or _party_overlay != null or _quest_panel != null or story_card != null:
		return
	world.clock.pause()
	_build_story_panel()

func _close_story() -> void:
	if _story_panel != null:
		_story_panel.queue_free()
		_story_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _build_story_panel() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.position = size * 0.5 - Vector2(230, 190)
	panel.custom_minimum_size = Vector2(460, 380)
	add_child(panel)
	_story_panel = panel
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = story.story.title
	title.theme_type_variation = "Head"
	box.add_child(title)

	var chapter := Label.new()
	var c: Dictionary = story.story.chapter(story.chapter)
	chapter.text = "Finished." if story.done else String(c.get("title", "—"))
	chapter.theme_type_variation = "Dim"
	chapter.add_theme_color_override("font_color", Icons.COL_ACCENT)
	box.add_child(chapter)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 290)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var lines: Array = story.journal
	if lines.is_empty():
		lines = [story.story.synopsis]
	for line in lines:
		var l := Label.new()
		l.text = String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		l.theme_type_variation = "Serif"
		rows.add_child(l)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_story)
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
	if _approach_card != null:
		return
	var reach := _trigger(dt)
	for q in world.parties:
		if q == p:
			continue
		# A hostile band (raiders, monsters — WorldAI.is_hostile() makes every
		# monster faction hostile to the player unconditionally) gets the
		# fight/parley/ambush card; a civilized one that ISN'T hostile — a
		# faction patrol, most often — used to be skipped here entirely and
		# could never be met at all. It now gets the same card with the
		# friendly-only ways (T9z).
		var hostile: bool = WorldAI.is_hostile(q, p)
		var near: bool = q.position.distance_to(p.position) <= reach
		# A band already slipped past stays slipped until it is genuinely out of
		# range again, or the player would be asked the same question every frame
		# for as long as they stand next to it.
		if _slipped.has(q.id):
			if not near:
				_slipped.erase(q.id)
			continue
		if near:
			_open_approach(q, hostile)
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
	var threat: Dictionary = WorldThreat.assess(party)
	# D6: the two knobs compose, and they answer different questions. The band
	# says how dangerous this country is (1.0 while the party is inside its level
	# range, which is the common case); the party's condition still thins whatever
	# the country sends, in the same proportion it always did.
	var spec: Dictionary = Scaler.roster_for(
		party.party_characters(), String(threat["difficulty"]), {}, theme, seed_v,
		float(threat["power_scale"]) * Regions.power_scale(world, foe.position, party))
	spec["theme"] = theme if theme != "" else DEFAULT_THEME
	return spec

# The same hand-off scenes/campaign/campaign.gd's _launch_combat() does: the map
# freezes, scenes/main.tscn runs the fight unchanged, `result` comes back.
# `scouted_ahead`/`forced_ambush` are T9x's camp-ambush outcomes (see
# _make_camp() below) — both default false for every other caller, same
# no-op they'd get from a plain Combat scene.
# One fight, start to finish: put scenes/main.tscn up over the map, wait for it,
# tear it down, hand back the result. Split out of _launch_combat() so a site
# room (core/site.gd) can run a fight with its own pre-built spec without also
# inheriting the roaming-band aftermath below — erasing a party that was never
# on the map, crediting faction opinion for a room in a cave.
func _run_combat(spec: Dictionary, difficulty: String,
		scouted_ahead := false, forced_ambush := false) -> Dictionary:
	world.clock.pause()
	Sound.set_combat(true)    # T27: campaign.gd did this for run fights; map fights were silent
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	_combat.spec = spec
	_combat.difficulty = difficulty
	_combat.scouted_ahead = scouted_ahead
	_combat.forced_ambush = forced_ambush
	_combat_overlay.add_child(_combat)

	while _combat != null and _combat.result.is_empty():
		await get_tree().process_frame
	if _combat == null:
		Sound.set_combat(false)   # torn down mid-fight; the layer must not outlive it
		return {}
	var result: Dictionary = _combat.result
	_combat = null
	Sound.set_combat(false)
	if _combat_overlay != null:
		_combat_overlay.queue_free()
		_combat_overlay = null
	return result


func _launch_combat(foe, scouted_ahead := false, forced_ambush := false) -> Dictionary:
	var threat: Dictionary = WorldThreat.assess(party)
	var result: Dictionary = await _run_combat(encounter_spec(foe),
		String(threat["difficulty"]), scouted_ahead, forced_ambush)
	if result.is_empty():
		return {}
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
	_apply_deaths(result)
	world.clock.resume()
	_autosave()   # O13 autosave: a fight is the biggest thing that
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
	var taken: Array = result.get("loot", [])
	for item in taken:
		party.stash_add(String(item))
	# Said out loud, on the same label the lair outcomes use. The combat screen
	# lists it in the fight log, but that log is gone by the time the map comes
	# back, and loot that lands silently in the stash is loot nobody knows they
	# picked up.
	if not taken.is_empty():
		var names: Array = []
		for item in taken:
			names.append(Campaign.item_name(String(item)))
		_lair_msg.text = "Taken from the dead: %s." % ", ".join(names)
	# Without this an accepted quest can never reach "complete", so O9 item 4's
	# turn-in row would have nothing to turn in.
	Quest.record_kills(party, result.get("kills", []),
		RNG.new(maxi(1, int(world.clock.elapsed) + 1)))

# A death is a death regardless of who won — encounter.gd always fills
# `deaths`, campaign.gd's linear run already benches+marks them the same way;
# the open world just never read the field. Applied once here for both
# outcomes rather than duplicated per-branch.
func _apply_deaths(result: Dictionary) -> void:
	for id in result.get("deaths", []):
		var fallen = party.get_member(id)
		if fallen != null:
			fallen.dead = true
		party.bench(id)

# Real stakes for a lost fight, but a soft landing — not a death spiral. A
# world-map encounter is scaled to whatever band you stumbled into, not the
# curated early-game jobs Party.REVIVE_COST (300gp) was priced against, so
# charging that per fallen character on top of the retreat tax could leave a
# beaten party unable to ever afford getting back to full strength. The dead
# are still handled above (dead + benched, so they can't act, and a party
# that wins with someone down still pays the normal paid-resurrection price —
# only a run-ending loss is this forgiving, same "the dead come back for
# free" rule campaign.gd's own run-ending loss already uses). What actually
# costs here: no XP/loot/quest progress from the fight, lost time, and the
# gold the bandits loot off whoever's still standing.
const DEFEAT_GOLD_LOSS_PCT := 0.15
func _retreat() -> void:
	var p := world.player()
	if p == null or world.settlements.is_empty():
		return
	party.spend_gold(roundi(party.gold * DEFEAT_GOLD_LOSS_PCT))
	Party.auto_revive_all(party)
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
		_lair_sneak_btn.visible = false
		return
	var p := world.player()
	if p == null:
		_lair_btn.visible = false
		_lair_sneak_btn.visible = false
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
		_lair_sneak_btn.visible = false
		return
	_lair_btn.visible = true
	# D6: what country it is in, on the button that walks into it. A lair is the
	# one thing on this map a party can commit to before finding out what is in
	# it, so the level band belongs here rather than one screen further in.
	var band: Dictionary = Regions.at(world, target.position)
	var lv: Array = band["levels"]
	_lair_btn.text = ("Search for a hidden lair (Survival)" if not target.discovered
		else "Attack %s — %s, levels %d-%d" % [target.sname, String(band["label"]),
			int(lv[0]), int(lv[1])])
	# The quiet way is only on the table while the warren is still quiet: once
	# the party has been through that door (or tried the quiet way and failed
	# into the fight below), the guardians are up and stay up — see
	# core/world_lairs.gd's alerted().
	_lair_sneak_btn.visible = WorldLairs.can_sneak(target)

# D1: a lair the party walked away from resolves without them after
# WorldLairs.WINDOW — somebody else clears it, or its tenants move on. Said out
# loud when it happens: a landmark going grey with no explanation reads as a bug.
func _check_expired_lairs() -> void:
	if _combat != null or _site != null:
		return
	for l in WorldLairs.expire(world, world.clock.elapsed):
		_lair_msg.text = WorldLairs.resolution_text(l)
		_autosave()

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
	await _delve(l)

# T9x: the quiet alternative to _lair_action()'s attack — a pass loots the
# lair with no fight; a fail falls straight through to the normal attack
# (the guardians are alerted either way now, so there's no third attempt).
func _lair_sneak_action() -> void:
	var l: World.Lair = _lair_target
	if l == null or _combat != null:
		return
	var roll := WorldLairs.sneak_past(l, party)
	if roll.is_empty():
		# The one refusal worth saying out loud: they have already been in there,
		# so there is nobody left to talk past. (An empty roll otherwise means a
		# party with no one to make the check, which the button being up already
		# implies is not the case.)
		if WorldLairs.alerted(l):
			_lair_msg.text = "%s is already roused — the quiet way is gone." % l.sname
		return
	if roll["ok"]:
		var loot: Dictionary = WorldLairs.loot(l)
		party.add_gold(int(loot.get("gold", 0)))
		Quest.record_lair_cleared(party, l.id)
		_lair_msg.text = "%s +%d gold." % [String(roll["text"]), int(loot.get("gold", 0))]
	else:
		_lair_msg.text = String(roll["text"])
		# Roused by the attempt itself, not as a side effect of the fight it
		# falls into: that is what makes this one attempt rather than one per
		# visit, and it is the moment the D1 window should start counting from.
		WorldLairs.mark_entered(l, world.clock.elapsed)
		await _lair_action()

# --- D1: the delve --------------------------------------------------------
#
# A lair is a place you go INTO now, not a single fight with a gold number
# attached (core/site.gd). This drives the model: the descent screen offers the
# rooms, the player picks one, a combat room runs through the same unchanged
# scenes/main.tscn hand-off every other fight uses, and the loop repeats until
# the party clears it, walks out, or goes down in there.
#
# The clock stays paused for the whole delve — the world does not move while
# you are underground, same rule a settlement visit already follows.
func _delve(l) -> void:
	if _site != null:
		return
	world.clock.pause()
	WorldLairs.mark_entered(l, world.clock.elapsed)   # D1: kicking the door starts the window
	_site = Site.for_lair(l, party, world)
	_site_screen = SiteScreen.new()
	_site_screen.site = _site
	_site_screen.party = party
	add_child(_site_screen)
	_site_screen.room_chosen.connect(_on_site_room_chosen)
	_site_screen.withdrew.connect(_on_site_withdrew)
	_site_screen.advanced.connect(_on_site_advanced)
	_site_screen.done.connect(_on_site_done)
	_site_screen.refresh()

func _on_site_room_chosen(i: int) -> void:
	if _site == null or _site.state != "picking":
		return
	var room: Dictionary = _site.enter(i)
	if room.is_empty():
		return
	_site_screen.refresh()
	if String(room.get("kind", "")) != "combat":
		return
	# The fight itself is the unchanged combat scene; the site only says what is
	# in the room. Its difficulty is the room's own — a site never scales down
	# with the party's condition the way open country does (core/world_threat.gd),
	# because a lair that got easier the worse you were doing would be no gamble.
	var result: Dictionary = await _run_combat(_site.combat_spec(),
		String(_site.room.get("difficulty", "normal")))
	if _site == null:
		return
	if not result.is_empty():
		if String(result.get("outcome", "")) == "Victory":
			_bank(result)
		_apply_deaths(result)
		_site.finish_combat(result)
	if _site.state == "wiped":
		_site_wiped()
	elif not _site.is_over():
		_site.leave()
	_site_screen.refresh()
	_autosave()

func _on_site_advanced() -> void:
	if _site == null or _site.is_over():
		return
	_site.leave()
	_site_screen.refresh()
	_autosave()

func _on_site_withdrew() -> void:
	if _site == null:
		return
	_site.withdraw()
	_site_screen.refresh()

# Locked with the user: harder than a lost fight on the road, softer than losing
# people. The map's own soft landing still applies (gold tax, free revival, wake
# at the nearest settlement) and on top of it the bag is lightened and the lair
# closes up again — see core/site.gd's wipe_penalty() for why it is the stash
# and never the equipped gear.
func _site_wiped() -> void:
	var toll: Dictionary = Site.wipe_penalty(party, _site.lair)
	_retreat()
	var names: Array = []
	for item_id in toll.get("items", {}):
		names.append("%s x%d" % [Campaign.item_name(String(item_id)), int(toll["items"][item_id])])
	var lost: String = ("They lost %s from the packs. " % ", ".join(names)) if not names.is_empty() else ""
	_lair_msg.text = "The party is dragged out of %s. %sThe way in has closed up behind them." % [
		_site.lair.sname, lost]

func _on_site_done() -> void:
	if _site == null:
		return
	var l = _site.lair
	if _site.state == "cleared":
		Quest.record_lair_cleared(party, l.id)
		_lair_msg.text = "%s is cleared out, all the way to the bottom." % l.sname
	elif _site.state == "withdrawn":
		_lair_msg.text = "%s is still down there — %d of %d rooms behind you." % [
			l.sname, int(l.depth_cleared), Site.depth_for(l)]
	_site = null
	if _site_screen != null:
		_site_screen.queue_free()
		_site_screen = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	_autosave()

# T91: split out of _check_visit so it can await the fight — the stand-in id
# ("%s-guard") never matches a hunt_party quest's target, so raid_settlement
# is recorded here with the settlement's own id rather than in _launch_combat.
func _settlement_guard_fight(s) -> void:
	var result: Dictionary = await _launch_combat(World.RoamingParty.new("%s-guard" % s.id, s.position, s.faction))
	if String(result.get("outcome", "")) == "Victory":
		Quest.record_settlement_raided(party, s.id)

# T9x: foraging — an ambient reward for time spent traveling, not a button.
# Rolls once every WorldForage.INTERVAL world-minutes actually spent out on
# the map; a hit narrates the skill and roll like every other overworld
# check, a miss says nothing (no point spamming "found nothing" every four
# hours of a long march).
func _check_forage() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		return
	if world.clock.elapsed - _last_forage_at < WorldForage.INTERVAL:
		return
	_last_forage_at = world.clock.elapsed
	var roll := WorldForage.check(party, RNG.new(maxi(1, absi(hash("forage|%d" % int(world.clock.elapsed))))))
	if roll.get("ok", false):
		party.add_gold(int(roll["gold"]))
		_camp_msg.text = "%s forages along the way (%s %d+%d vs DC %d) — +%d gold." % [
			roll["cname"], String(roll["skill"]).capitalize(), roll["nat"], roll["bonus"], roll["dc"], int(roll["gold"])]

# --- D4: how the party meets a band ---------------------------------------
#
# A hostile band closing in used to drop the player straight into a fight — the
# encounter happened TO them, which is the blob-bumps-blob shape the scope
# revision set out to remove. Now the clock stops and they choose: slip away,
# parley, set an ambush, or go straight at it (core/approach.gd owns the rules
# and the rolls; this only runs the flow).
func _open_approach(foe, hostile := true) -> void:
	if _approach_card != null:
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_approach_foe = foe
	_approach_card = ApproachCard.new()
	add_child(_approach_card)
	_approach_card.chosen.connect(_on_approach_chosen)
	_approach_card.show_approach(Approach.options(party, foe, hostile),
		"%s (%d)" % [foe.id.capitalize(), foe.troops.size()])

func _on_approach_chosen(way: String) -> void:
	var foe = _approach_foe
	if foe == null:
		return
	var r: Dictionary = Approach.resolve(party, foe, way,
		RNG.new(maxi(1, absi(hash("%s|%s|%d" % [foe.id, way, int(world.clock.elapsed)])))))
	_close_approach()
	# The outcome is reported on the same card the road events use — it is the
	# same kind of thing, and a second card style would be a second thing to
	# learn for no reason.
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_approach_reported.bind(foe, r))
	_event_card.show_event(_approach_event(r))

# core/approach.gd's result, in the shape event_card.gd already draws.
func _approach_event(r: Dictionary) -> Dictionary:
	var e: Dictionary = r.duplicate(true)
	e["id"] = "approach-%s" % String(r.get("way", ""))
	e["title"] = String(Approach.WAYS.get(String(r.get("way", "")), {}).get("label", "The meeting"))
	# "good" is not the same as "the roll passed": walking into a fight you
	# meant to walk into is not a setback, and a blown ambush is.
	e["kind"] = "bad" if bool(r.get("forced_ambush", false)) else "good"
	if r.has("toll"):
		e["gold"] = -int(r["toll"])
	return e

func _on_approach_reported(foe, r: Dictionary) -> void:
	_on_event_ack()
	if not bool(r.get("fight", true)):
		# No fight: the band is still out there, just not met. Mark it slipped so
		# standing next to it does not re-open the question every frame.
		_slipped[foe.id] = true
		world.clock.resume()
		return
	await _launch_combat(foe, bool(r.get("scouted_ahead", false)),
		bool(r.get("forced_ambush", false)))

func _close_approach() -> void:
	if _approach_card != null:
		_approach_card.queue_free()
		_approach_card = null
	_approach_foe = null

# D3 — the other half of keeping a 1x-8x fast-forward honest. Travel used to be
# empty, so 8x was a way to skip the game; now the road rolls an event every
# Travel.EVENT_INTERVAL of actual travel and the clock STOPS for it. That is the
# whole bargain: nothing is asked of the player while nothing is happening, and
# nothing is missed when something is.
#
# The event arrives already resolved — standing orders set on the party screen
# decided who rolled and at what bonus (core/travel.gd), hours before this
# fired. The card reports; it does not ask. Same gates as every other _check_*:
# not mid-fight, not in a settlement, not underground, not already paused.
func _check_travel() -> void:
	if _combat != null or not _visit.is_empty() or _site != null or world.clock.is_paused():
		return
	if _event_card != null:
		return          # one card at a time; the clock is stopped behind it anyway
	if world.clock.elapsed - _last_travel_at < Travel.EVENT_INTERVAL:
		return
	_last_travel_at = world.clock.elapsed
	var e: Dictionary = Travel.check(party, world,
		RNG.new(maxi(1, absi(hash("road|%d" % int(world.clock.elapsed))))))
	if e.is_empty():
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event(e)
	_autosave()   # an event can move gold, HP, the clock and the map

# The plain handler for a road event's card. Note it FREES the card without
# emitting `acknowledged`, so anything that needs a bound follow-up to run
# (D4's _on_approach_reported, which launches the fight) must emit the signal
# instead of calling this. A driver that called this directly is exactly how
# that was found.
func _on_event_ack() -> void:
	if _event_card != null:
		_event_card.queue_free()
		_event_card = null
	world.clock.resume()
	_pause_btn.text = "Pause"

# D6: which country the party is in, and the one moment it is worth saying so
# out loud. Runs every frame because the label has to be right every frame; the
# rest of it only happens on a seam.
#
# The clock stops for exactly one case: riding OUT into a band whose floor is
# above the party's level. That is the case where the map is about to build
# fights the party cannot win (core/regions.gd's measured grid: one band out is
# 37.5%, two is 27.5%), and it is the only warning the game can give that is not
# a wall. Riding back in is good news and never interrupts anything.
func _check_region() -> void:
	var p0 = world.player()
	if p0 == null:
		return
	var band: Dictionary = Regions.at(world, p0.position)
	var lv: Array = band["levels"]
	# T27+D6: the map's own ambient bed. The overworld used to be the one screen
	# with SFX but no music at all — campaign.gd set a bed for every node of a
	# linear run, and the open world, which is where most of a session is spent,
	# played nothing. The band id IS the theme id (tools/gen_audio.py BEDS), so
	# riding out of the heartland is audible a beat before the label says so.
	# Called every frame: Audio._set_environment() early-returns on an unchanged
	# theme, so this is a string compare, and coming out of a town restores the
	# right country's bed without _close_visit() having to know which one it was.
	Sound.set_environment("settlement" if not _visit.is_empty() else String(band["id"]))
	if _region_lbl != null:
		# Short form: this bar already carries nine controls and a hint, and the
		# long form lives on the lair button, the inn's leads and the crossing card.
		_region_lbl.text = "%s, levels %d to %d" % [String(band["label"]), int(lv[0]), int(lv[1])]
	if _region.is_empty():
		_region = band          # first frame: the party is simply somewhere
		return
	if String(band["id"]) == String(_region["id"]):
		return
	var was: Dictionary = _region
	_region = band
	if _region_msg != null:
		_region_msg.text = Regions.crossing_text(was, band)
	var deeper: bool = int(band["index"]) > int(was["index"])
	var over_head: bool = Regions.party_level(party) < int(lv[0])
	if not (deeper and over_head):
		return
	# Once per band. A party working a seam — a lair just over it, a town just
	# back — would otherwise be stopped every few minutes to be told something it
	# already decided to ignore. The HUD label never stops saying it.
	if _warned_bands.has(String(band["id"])):
		return
	_warned_bands[String(band["id"])] = true
	# Same gates every other _check_* uses: not mid-fight, not in a settlement,
	# not underground, not already stopped, and never a second card over the first.
	if _combat != null or not _visit.is_empty() or _site != null or world.clock.is_paused():
		return
	if _event_card != null:
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event({
		"id": "crossing", "kind": "border",
		"title": "Into %s" % String(band["label"]),
		"text": "%s  This is country for levels %d-%d, and the party is level %d." % [
			String(band["blurb"]), int(lv[0]), int(lv[1]), Regions.party_level(party)]})

# D3: the quick version of the party screen's standing orders — the one order
# worth changing mid-march, on the HUD where the clock speed already is.
func _cycle_pace() -> void:
	var o: Dictionary = Travel.orders(party)
	var i: int = Travel.PACES.find(String(o["pace"]))
	var next: String = Travel.PACES[(i + 1) % Travel.PACES.size()]
	Travel.set_orders(party, next, String(o["scout"]), String(o["watch"]))
	_refresh_pace_btn()

func _refresh_pace_btn() -> void:
	if _pace_btn == null:
		return
	var pace: String = String(Travel.orders(party)["pace"])
	_pace_btn.text = Travel.pace_label(pace)
	_pace_btn.tooltip_text = Travel.pace_note(pace)

func _open_visit(s) -> void:
	world.clock.pause()
	world.set_goal(world.player(), world.player().position)   # stop at the gate
	_visit = Visit.visit(s, world)
	_visit_page = "hub"
	_market_tab = MARKET_TAB_ALL
	_build_visit_panel()

func _goto_page(page: String) -> void:
	_visit_page = page
	if page == "market":
		_market_tab = MARKET_TAB_ALL   # every visit to the stalls starts at the whole shelf
	_build_visit_panel()

const MARKET_TAB_ALL := "all"

func _goto_market_tab(service: String) -> void:
	_market_tab = service
	_build_visit_panel()

# T9y: a settlement is four screens now, and the only way between them was the
# mouse. Esc backs out one level (counter -> page -> town square -> the map),
# which is the one binding a player will try without being told; the initials
# jump straight to a building from anywhere inside the gates.
func _unhandled_key_input(event: InputEvent) -> void:
	if _visit.is_empty() or _combat != null or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _visit_page == "market" and _market_tab != MARKET_TAB_ALL:
				_goto_market_tab(MARKET_TAB_ALL)
			elif _visit_page != "hub":
				_goto_page("hub")
			else:
				_close_visit()
		KEY_M: _goto_page("market")
		KEY_I: _goto_page("inn")
		KEY_B: _goto_page("board")
		KEY_T: _goto_page("hub")
		_: return
	accept_event()

func _close_visit() -> void:
	_left = _visit.get("settlement")
	_visit = {}
	if _visit_panel != null:
		_visit_panel.queue_free()
		_visit_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	_autosave()   # O13 autosave: the purse and the shelf both moved

func _buy(item_id: String) -> void:
	if Visit.buy(_visit, party, item_id):
		Sound.play_sfx("buy")
		_build_visit_panel()
	else:
		_say("Not enough gold.")

func _sell(item_id: String) -> void:
	if Visit.sell(_visit, party, item_id):
		_build_visit_panel()

# T9y: the Healer and the Librarian — T25 services that a settlement has
# always been able to advertise but never actually staff (see
# core/settlement_visit.gd's heal()/identify()). Neither takes clock time,
# so neither re-reads the market; both autosave, same as every other purse
# movement in this file.
# D5: a lead costs gold and puts a real lair on the map — the same `discovered`
# flag a Survival check sets, so a place found by asking behaves exactly like
# one found by walking into it. There is no second kind of found.
func _buy_rumor(lead: Dictionary) -> void:
	var r: Dictionary = Rumors.buy(lead, party, world)
	if bool(r.get("ok", false)):
		Sound.play_sfx("quest")
		_autosave()
	_build_visit_panel()
	_say(String(r.get("text", "")))

func _heal() -> void:
	var r: Dictionary = Visit.heal(party)
	if bool(r.get("ok", false)):
		Sound.play_sfx("heal")
		_autosave()
	_build_visit_panel()
	_say(String(r.get("text", "")))

func _identify(item_id: String) -> void:
	var r: Dictionary = Visit.identify(party, item_id)
	if bool(r.get("ok", false)):
		Sound.play_sfx("identify")
		_autosave()
	_build_visit_panel()
	_say(String(r.get("text", "")))

# T9x: flat price, unlimited stock — see the row comment in _build_visit_panel.
func _buy_camp_kit() -> void:
	if party.spend_gold(WorldCamp.CAMP_KIT_PRICE):
		party.stash_add(WorldCamp.CAMP_KIT_ITEM)
		Sound.play_sfx("buy")
		_build_visit_panel()
		_say("%s bought." % WorldCamp.CAMP_KIT_NAME)
	else:
		_say("Not enough gold.")

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

# T9x: one attempt per visit, same shape as _steal(). Only shown when the
# market actually refused to trade (see _build_visit_panel).
# T9x: steal/persuade/investigate/haggle are one-attempt-per-visit flags
# that live only on this UI's own _visit dict — Visit.visit()/market()/
# persuade_into_trading() know nothing about them, so any spot that
# replaces _visit wholesale (a rest's fresh shelf roll, a successful
# persuade reopening the market) has to carry them forward explicitly or
# they silently reset, re-enabling an action that was supposed to be spent
# for the price of pressing a different button.
func _carry_visit_flags(from: Dictionary, to: Dictionary) -> void:
	for k in ["stolen", "persuaded", "investigated", "haggled"]:
		to[k] = from.get(k, false)

func _persuade() -> void:
	if _visit.get("persuaded", false):
		_say("They've made up their mind for today.")
		return
	var r: Dictionary = Visit.persuade(_visit["settlement"], _visit, party)
	_visit["persuaded"] = true
	if bool(r.get("ok", false)):
		var before := _visit
		_visit = Visit.persuade_into_trading(_visit["settlement"], _visit)
		_carry_visit_flags(before, _visit)
	_build_visit_panel()
	_say(String(r.get("text", "Nobody here will hear you out.")))

# T9x: haggling — the mirror of persuade(), for a market that's already
# open. One attempt per visit; moves this visit's prices for better or
# worse depending on the roll, doesn't touch the underlying faction opinion.
func _haggle() -> void:
	if _visit.get("haggled", false):
		_say("They won't budge on price again today.")
		return
	var r: Dictionary = Visit.haggle(_visit, party)
	_visit["haggled"] = true
	if not r.is_empty():
		Visit.apply_haggle(_visit, float(r["mult"]))
		if bool(r["ok"]):
			Sound.play_sfx("buy")
	_build_visit_panel()
	_say(String(r.get("text", "Nobody here is in the mood to talk price.")))

# T9x: one attempt per visit. Only shown when a fight resolved near this
# settlement recently (market()'s own `battle` flag).
func _investigate() -> void:
	if _visit.get("investigated", false):
		_say("The battlefield's already been picked over.")
		return
	var r: Dictionary = Visit.investigate_battle(_visit["settlement"], _visit, party)
	_visit["investigated"] = true
	if bool(r.get("ok", false)):
		Sound.play_sfx("pickup")
	_build_visit_panel()
	_say(String(r.get("text", "There's nobody here who'd know where to look.")))

# O9 item 2: the inn. Time is the cost — see SettlementVisit.rest — and the extra
# hours restock the shelf, so the market is re-read afterwards.
# T9x: gated to once per in-game day (Visit.can_long_rest) — RAW's own rule,
# never enforced before, so a settlement visit could spam free full heals.
func _rest() -> void:
	if not Visit.can_long_rest(party, world):
		_say("The party isn't tired enough for another long rest yet.")
		return
	var s = _visit["settlement"]
	var cost := Visit.inn_cost(s)
	if not party.spend_gold(cost):
		_say("Can't afford a room here (%d gp)." % cost)
		return
	var before := _visit
	Visit.rest(party, world, "long-rest")
	Sound.play_sfx("rest")
	var trance: Dictionary = Trance.apply_rest_bonus(party, world, s.position)
	_visit = Visit.visit(s, world)
	_carry_visit_flags(before, _visit)
	_build_visit_panel()
	_say("The party takes a long rest (%d gp for the room). Eight hours pass and the stalls fill up again.%s" % [
		cost, _trance_note(trance)])

# T9x: names the check and its result explicitly, same convention every
# other overworld roll in this file uses — never just "something happened".
func _trance_note(trance: Dictionary) -> String:
	if trance.is_empty():
		return ""
	var note := "  Someone didn't need the sleep: the party gets a short rest on top, and the ground nearby is scouted."
	var id: Dictionary = trance.get("identify", {})
	if not id.is_empty():
		if id["ok"]:
			note += "  They also puzzle out the %s while they're at it (Arcana %d+%d vs DC %d)." % [
				Campaign.item_name(id["item_id"]), id["nat"], id["bonus"], id["dc"]]
		else:
			note += "  They also take a crack at identifying an item, no luck (Arcana %d+%d vs DC %d)." % [
				id["nat"], id["bonus"], id["dc"]]
	return note

# T9x: a short rest works anywhere on the map, not just a settlement — but
# only when it's actually safe: mid-fight, paused, or a hostile band close
# enough to notice all say no, same radius _check_encounter() uses to decide
# whether a band has closed in enough to trigger a fight.
func _hostile_nearby() -> bool:
	var p := world.player()
	if p == null:
		return false
	for q in world.parties:
		if q != p and WorldAI.is_hostile(q, p) and q.position.distance_to(p.position) <= ENCOUNTER_RADIUS:
			return true
	return false

func _short_rest() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		return
	if _hostile_nearby():
		_camp_msg.text = "Too dangerous to rest here — something hostile is close."
		return
	Visit.rest(party, world, "short-rest")
	Sound.play_sfx("rest")
	_camp_msg.text = "The party takes a short rest. An hour passes."

# T9x: the camp-kit item (bought at any settlement, see _build_visit_panel)
# lets the party long-rest away from town — for a price already paid at
# purchase, and a small risk paid here: AMBUSH_CHANCE_PCT odds of being
# jumped in the night. A failed watch (whoever's best at Survival or
# Perception) costs the party the enemy's surprise round; a passed one
# means they heard it coming and get the same swap-places deployment edge
# a stealthy approach into a fight would earn them (core/world_camp.gd).
# Either way an interrupted night grants no rest — same as RAW, and the
# reason to gate this on can_long_rest() first: no point risking an ambush
# for a rest that wouldn't grant its benefit yet regardless.
func _make_camp() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		return
	if not Visit.can_long_rest(party, world):
		_camp_msg.text = "The party isn't tired enough for another long rest yet."
		return
	if party.stash_count(WorldCamp.CAMP_KIT_ITEM) < 1:
		return
	party.stash_remove(WorldCamp.CAMP_KIT_ITEM, 1)
	var p := world.player()
	var rng := RNG.new(WorldCamp.camp_seed(world.clock.elapsed, p.position))
	if not WorldCamp.ambush_roll(rng):
		Visit.rest(party, world, "long-rest")
		Sound.play_sfx("rest")
		var trance: Dictionary = Trance.apply_rest_bonus(party, world, p.position)
		_camp_msg.text = "The camp holds through the night. Eight hours pass.%s" % _trance_note(trance)
		return
	var watch: Dictionary = WorldCamp.watch_check(party, rng)
	var foe := World.RoamingParty.new("camp-ambush-%d" % int(world.clock.elapsed), p.position, WorldCamp.AMBUSH_FACTION)
	# T9x: name the check and the roll, not just the outcome — same
	# "Skill nat+bonus vs DC" shape every other overworld check in this file uses.
	var skill_name: String = String(watch.get("skill", "")).capitalize()
	if watch["ok"]:
		_camp_msg.text = "%s hears them coming (%s %d+%d vs DC %d) — the party gets the drop first." % [
			watch.get("cname", "Someone"), skill_name, watch["nat"], watch["bonus"], watch["dc"]]
		await _launch_combat(foe, true, false)
	else:
		var who: String = watch.get("char_id", "")
		_camp_msg.text = ("%s doesn't catch it in time (%s %d+%d vs DC %d) — the camp is jumped in the night!" % [
			watch.get("cname", ""), skill_name, watch["nat"], watch["bonus"], watch["dc"]]) if who != "" \
			else "Nobody's keeping watch — the camp is jumped in the night!"
		await _launch_combat(foe, false, true)

# O9 item 4 / T9x quest board: `q` is the exact offer row the player clicked
# (the board can show several at once now), not re-rolled here.
func _take_quest(q: Dictionary) -> void:
	if Quest.accept(party, q):
		_build_visit_panel()
		_say("Job taken: %s" % q["title"])
	else:
		_say("No work here just now.")

func _turn_in(quest: Dictionary) -> void:
	var reward: int = int(quest.get("reward", {}).get("gold", 0))
	if Quest.turn_in(party, quest, _visit["settlement"].faction):
		Sound.play_sfx("buy")
		# D5: a job well done is how a town decides you are worth telling things
		# to. The board's second payout, and the one that is not gold.
		var lead: Dictionary = Rumors.free_lead(_visit["settlement"], party, world)
		_build_visit_panel()
		_say("%s — paid, +%d gp. They will remember it.%s" % [
			quest["title"], reward,
			("  " + String(lead["text"])) if not lead.is_empty() else ""])
		_autosave()

# The panel is rebuilt after every action, so the last line has to live on the
# visit rather than on the Label that just got freed.
func _say(text: String) -> void:
	if not _visit.is_empty():
		_visit["log"] = text
	if _visit_log != null:
		_visit_log.text = text

# T9x: a settlement is a set of separate screens now (town square / market /
# inn / notice board), not one panel with everything stacked in it — this is
# just the shell (frame, title, footer) and the page dispatch; each _build_*
# below only owns its own content between the title and the footer.
func _build_visit_panel() -> void:
	if _visit_panel != null:
		_visit_panel.queue_free()
	var s = _visit["settlement"]
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
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
	title.text = "%s, %s" % [s.sname, String(PAGE_TITLES.get(_visit_page, "")).to_lower()]
	title.theme_type_variation = "Head"
	box.add_child(title)

	match _visit_page:
		"market": _build_market_page(box, s)
		"inn": _build_inn_page(box, s)
		"board": _build_board_page(box, s)
		_: _build_hub_page(box, s)

	_visit_log = Label.new()
	_visit_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_visit_log.custom_minimum_size = Vector2(440, 34)
	box.add_child(_visit_log)
	_visit_log.text = String(_visit.get("log", ""))

	var bar := HBoxContainer.new()
	box.add_child(bar)
	if _visit_page != "hub":
		var back := Button.new()
		back.text = "← Town Square"
		back.pressed.connect(_goto_page.bind("hub"))
		bar.add_child(back)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_close_visit)
	bar.add_child(leave)

const PAGE_TITLES := {"hub": "Town Square", "market": "Market", "inn": "Inn", "board": "Notice Board"}

# The town square: where to go, plus the one thing that belongs to no single
# building — picking over a battlefield nearby.
# T9y: every door now says what is behind it before you open it. The split
# into separate screens (34300bb) left the hub with three unlabelled buttons,
# so the only way to find out whether the board had work — or whether the
# shelves were bare — was to walk in and look. All three counts are read off
# state the page already had to compute anyway.
func _build_hub_page(box: VBoxContainer, s) -> void:
	var mood := Label.new()
	mood.text = "%s%s%d gp in the purse." % [
		"Fighting nearby. " if _visit.get("battle", false) else "",
		"They will not trade with you. " if _visit.get("refused", false) else "",
		party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var places := VBoxContainer.new()
	box.add_child(places)
	var stock: Array = _visit.get("stock", [])
	var market_btn := Button.new()
	market_btn.text = ("Market.  They will not trade with you" if _visit.get("refused", false)
		else "Market.  %d on the shelves" % stock.size())
	market_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	market_btn.pressed.connect(_goto_page.bind("market"))
	places.add_child(market_btn)
	var counters := Label.new()
	counters.text = "      %s" % ", ".join(_visit["services"].map(
		func(x): return String(Campaign.SERVICE_NAMES.get(x, x))))
	counters.theme_type_variation = "Dim"
	places.add_child(counters)

	var inn_btn := Button.new()
	var wait: float = Visit.long_rest_in(party, world)
	inn_btn.text = ("Inn.  A night is %d gp" % Visit.inn_cost(s) if wait <= 0.0
		else "Inn.  Rested recently, a room does nothing for %s yet" % _hours(wait))
	inn_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	inn_btn.pressed.connect(_goto_page.bind("inn"))
	places.add_child(inn_btn)

	var board_btn := Button.new()
	var offers: int = Visit.quest_offers(s, party, world).size()
	var ready: int = Visit.turn_ins(party).size()
	board_btn.text = ("Notice Board.  Nothing posted" if offers == 0 and ready == 0
		else "Notice Board.  %d posted, %d ready to turn in" % [offers, ready])
	board_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	board_btn.pressed.connect(_goto_page.bind("board"))
	places.add_child(board_btn)

	if _visit.get("battle", false):
		var investigate_btn := Button.new()
		var investigated: bool = _visit.get("investigated", false)
		investigate_btn.text = "Investigated the battlefield" if investigated else "Investigate the battlefield"
		investigate_btn.disabled = investigated
		investigate_btn.pressed.connect(_investigate)
		places.add_child(investigate_btn)

# T9y: one counter at a time. T25 sizes a settlement's specialists and the
# hub line names them, but the shelf itself was one alphabetical list with no
# hint of who was selling what — and the two services that stock no goods
# (Healer, Librarian) had nowhere to exist at all, so a city's own services
# line was advertising people the player could never talk to. A tab strip
# across the top picks the counter; "All" keeps the old single list, grouped
# under headers rather than shuffled together.
func _build_market_page(box: VBoxContainer, s) -> void:
	var mood := Label.new()
	mood.text = "Shelves %d of %d, prices x%.2f%s.  %d gp in the purse." % [
		_visit["steps"], Visit.MAX_STEPS, _visit["markup"],
		"  (they will not trade with you)" if _visit.get("refused", false) else "",
		party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var groups: Dictionary = Visit.stock_by_service(s, _visit)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for t in [MARKET_TAB_ALL] + Array(_visit["services"]):
		var name_of: String = ("All" if t == MARKET_TAB_ALL
			else String(Campaign.SERVICE_NAMES.get(t, t)))
		# Innkeeper is the quest-giver role (see campaign.gd's SERVICE_ORDER
		# comment); its counter is the Notice Board, not a stall here.
		if t == "innkeeper":
			continue
		var btn := Button.new()
		btn.text = name_of
		btn.disabled = (_market_tab == t)   # the open tab, shown as pressed rather than as a live button
		btn.pressed.connect(_goto_market_tab.bind(String(t)))
		tabs.add_child(btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 250)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	var showing_all: bool = _market_tab == MARKET_TAB_ALL
	for service in _visit["services"]:
		if service == "innkeeper":
			continue
		if not showing_all and _market_tab != service:
			continue
		var shelf: Array = groups.get(service, [])
		var actions: bool = service in ["healer", "librarian"]
		if shelf.is_empty() and not actions:
			continue
		if showing_all:
			_section(rows, String(Campaign.SERVICE_NAMES.get(service, service)))
		for e in shelf:
			_trade_row(rows, "%s — %d gp" % [e["name"], e["price"]], "Buy",
				_buy.bind(String(e["item_id"])))
		if service == "healer":
			_trade_row(rows, "Patch up the whole party — %d gp (no rest, no waiting)" % Visit.HEAL_COST,
				"Heal", _heal)
		elif service == "librarian":
			var mystery: Array = party.unidentified()
			if mystery.is_empty():
				_note(rows, "Nothing in the pack needs identifying.")
			for entry in mystery:
				var mid := String(entry["item_id"])
				_trade_row(rows, "Identify the unknown %s — %d gp" % [
					Campaign.item_name(mid), Visit.IDENTIFY_COST], "Identify", _identify.bind(mid))
	# The generalist's own counter also outfits you: the camp kit is a flat
	# price and never runs out, so it is not part of the T25 shelf/restock
	# catalog (T9x) and gets its own row rather than a fake catalog entry.
	if showing_all or _market_tab == "generalist":
		_trade_row(rows, "%s — %d gp (lets you long-rest away from a settlement)" % [
			WorldCamp.CAMP_KIT_NAME, WorldCamp.CAMP_KIT_PRICE], "Buy", _buy_camp_kit)
	# Selling is not a counter — whoever is behind it takes the whole pack —
	# so it stays out of the tabs and sits under everything, on every tab.
	var sellable := 0
	for entry in party.stash:
		var id := String(entry["item_id"])
		var paid := Visit.sell_price(_visit, id)
		if paid <= 0:
			continue
		if sellable == 0:
			_section(rows, "Your pack")
		sellable += 1
		_trade_row(rows, "%s x%d — sells for %d gp" % [
			Campaign.item_name(id), int(entry["quantity"]), paid], "Sell", _sell.bind(id))

	var bar := HBoxContainer.new()
	box.add_child(bar)
	var steal_btn := Button.new()
	var spent: bool = _visit.get("stolen", false)
	steal_btn.text = "Stole from the market" if spent else "Steal from the market"
	steal_btn.disabled = spent
	steal_btn.pressed.connect(_steal)
	bar.add_child(steal_btn)
	if _visit.get("refused", false):
		var persuade_btn := Button.new()
		var persuaded: bool = _visit.get("persuaded", false)
		persuade_btn.text = "Tried persuasion" if persuaded else "Persuade them to trade"
		persuade_btn.disabled = persuaded
		persuade_btn.pressed.connect(_persuade)
		bar.add_child(persuade_btn)
	else:
		# T9x: haggle only makes sense on a market that's actually open —
		# persuade (above) is what opens a refused one in the first place.
		var haggle_btn := Button.new()
		var haggled: bool = _visit.get("haggled", false)
		haggle_btn.text = "Haggled already" if haggled else "Haggle over prices (Persuasion)"
		haggle_btn.disabled = haggled
		haggle_btn.pressed.connect(_haggle)
		bar.add_child(haggle_btn)

# T9y: the inn was one button and a purse. Resting is the one action here
# whose whole value is the state it changes, so the page now shows that state:
# who is hurt, what a night costs, and — when the once-a-day cooldown says no
# — how long until it says yes. A disabled button with a number beside it is
# an answer; a button that shrugs is the silent-no-op bug again (e3cc910).
func _build_inn_page(box: VBoxContainer, s) -> void:
	var cost := Visit.inn_cost(s)
	var mood := Label.new()
	mood.text = "A %s bed is %d gp a night.  %d gp in the purse." % [s.kind, cost, party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var rows := VBoxContainer.new()
	box.add_child(rows)
	_section(rows, "Around the table")
	for id in party.active:
		var m: Dictionary = party.summary(id)
		if m.is_empty():
			continue
		var line := Label.new()
		var hurt: bool = int(m["hp"]) < int(m["max_hp"])
		line.text = "%s, %s %d, %d/%d hp%s" % [m["name"], m["class_name"], m["level"],
			m["hp"], m["max_hp"], "" if not hurt else "   (hurt)"]
		line.add_theme_color_override("font_color", Icons.COL_FOE if hurt else Icons.COL_BODY)
		rows.add_child(line)

	var wait: float = Visit.long_rest_in(party, world)
	var rest_btn := Button.new()
	rest_btn.text = "Rest the night (%d gp)" % cost
	rest_btn.disabled = wait > 0.0 or party.gold < cost
	rest_btn.pressed.connect(_rest)
	box.add_child(rest_btn)
	if wait > 0.0:
		_note(box, "They rested less than a day ago — another night does nothing for %s." % _hours(wait))
		# The healer is the paid way past this wall, and only a settlement that
		# has one can offer it: say so where the player hits the wall, not only
		# on the counter they would have to guess to open.
		if Visit.has_service(s, "healer"):
			_note(box, "The healer will patch everyone up regardless, for %d gp." % Visit.HEAL_COST)
	elif party.gold < cost:
		_note(box, "Not enough gold for a room.")
	else:
		_note(box, "Eight hours: everyone back to full, spells and abilities back, and the stalls restock while you sleep.")

	# D5: the other half of what an inn is for. Until now a lair was found by
	# walking close enough to one you had no reason to think existed — discovery
	# by collision. This is where you hear about it instead, which is what makes
	# a town worth walking back to.
	var leads: Array = Rumors.offers(s, world)
	_section(box, "Word in the common room")
	if leads.is_empty():
		_note(box, "Nothing anybody here has not already told you.")
		return
	var lead_rows := VBoxContainer.new()   # `rows` is the party-status list above
	box.add_child(lead_rows)
	for lead in leads:
		_trade_row(lead_rows, "%s  (%s) — %d gp" % [
			lead["text"], String(lead.get("where", "")), int(lead["price"])],
			"Buy", _buy_rumor.bind(lead))

func _build_board_page(box: VBoxContainer, s) -> void:
	var mood := Label.new()
	mood.text = "%s posts the work here.  %d gp in the purse." % [
		Campaign.SERVICE_NAMES.get("innkeeper", "The innkeeper") if Visit.has_service(s, "innkeeper")
		else "A town elder", party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 300)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	# T9x quest board: every job this settlement can offer right now, one row
	# each — not the old single ad-hoc offer. A world-target row also shows
	# its chain tier once it's escalated past the first job.
	for offer in Visit.quest_offers(s, party, world):
		var tier: int = int(offer.get("chain_tier", 0))
		var tag := "  (tier %d)" % (tier + 1) if tier > 0 else ""
		_trade_row(rows, "Job: %s%s — %d gp" % [
			offer["title"], tag, int(offer.get("reward", {}).get("gold", 0))],
			"Take", _take_quest.bind(offer))
	for q in Visit.turn_ins(party):
		_trade_row(rows, "✔ %s" % Quest.describe(q), "Turn in", _turn_in.bind(q))
	if rows.get_child_count() == 0:
		var none := Label.new()
		none.text = "Nothing posted right now."
		none.add_theme_color_override("font_color", Icons.COL_MUTED)
		rows.add_child(none)

# A counter's heading inside a page's scroll list, and a muted aside. Both
# exist so a page can explain itself without every builder re-deriving the
# same Label boilerplate.
func _section(rows: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Caption"
	rows.add_child(l)

func _note(rows: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(430, 0)
	l.theme_type_variation = "Dim"
	rows.add_child(l)

# World-minutes as something a person would say out loud. Under an hour is
# still "an hour" — the long-rest cooldown is a day-scale number and false
# precision on it ("in 3 minutes") would read as a bug, not as detail.
static func _hours(minutes: float) -> String:
	var h := int(ceil(minutes / 60.0))
	return "an hour" if h <= 1 else "%d hours" % h

# The same clock at the other end of its range. A march is a minutes-scale
# number — World.SPEED is 40 units per world-minute, so crossing the whole
# small map is about 25 of them — and rounding that to hours the way _hours()
# does would print "an hour" for every settlement on the map.
static func _travel_time(minutes: float) -> String:
	if minutes < 60.0:
		return "%d min" % maxi(1, int(round(minutes)))
	return "%dh%02d" % [int(minutes / 60.0), int(minutes) % 60]

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
	# T9x: settlements are landmarks, always drawn regardless of fog — the
	# whole point of the beacon is to give the player something to walk
	# toward on a still-dark map. Lairs and roaming parties stay fog-gated:
	# those are meant to be found, not signposted.
	# T9y: "live" is the same currently-visible tier _draw_ground() dims the
	# ground with — a prop the party can actually see right now draws in full
	# colour, one they are only remembering draws washed out. Without it a
	# settlement visited two days ago looked exactly like the one you are
	# standing in, which threw away the distinction the three-tier fog had
	# just bought.
	var ppos: Vector2 = p.position if p != null else Vector2.ZERO
	var props: Array = []
	for s in world.settlements:
		props.append({"at": _pix(s.position), "s": s, "live": world.is_visible_now(s.position, ppos)})
	for l in world.lairs:
		if l.discovered and world.is_explored(l.position):   # T91: undiscovered lairs draw nothing — that's the point
			props.append({"at": _pix(l.position), "l": l, "live": world.is_visible_now(l.position, ppos)})
	for q in world.parties:
		if q.is_player and not _visit.is_empty():
			continue   # inside the gates for the duration of the visit, not standing on the map
		if not q.is_player and not world.is_explored(q.position):
			continue
		# A roaming band is the one prop whose remembered position is a lie —
		# it has walked on since. Drawn at its live position either way (the
		# map has no last-known-position memory to draw instead), but washed
		# out, which is the honest reading: "they were around here".
		props.append({"at": _pix(q.position), "p": q,
			"live": q.is_player or world.is_visible_now(q.position, ppos)})
	props.sort_custom(func(a, b): return a["at"].y < b["at"].y)
	for d in props:
		if d.has("s"):
			_draw_settlement(d["s"], d["at"], d["live"])
		elif d.has("l"):
			_draw_lair(d["l"], d["at"], d["live"])
		else:
			_draw_party(d["p"], d["at"], d["live"])
	_draw_offscreen_markers(ppos)

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
	# T9x: three fog tiers, not two. Currently-visible (near the player right
	# now) draws clean; explored-but-not-visible ("remembered") draws the
	# real tile with a translucent dark tint over it so the shape still
	# reads; never-explored draws as flat, opaque, darker fog. Only one
	# live-position check needed — is_explored() already folds in the
	# settlement-beacon radius (world.gd's near_settlement()).
	var p := world.player()
	var ppos: Vector2 = p.position if p != null else Vector2.ZERO
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var cell := Vector2i(i, j)
			var center := Vector2(i + 0.5, j + 0.5) * CELL
			var rect := Rect2(Vector2(i + j, j - i - 1) * TILE * 0.5, TILE)
			# ponytail: an O(cells x waypoints) distance scan every frame, fine at
			# this map's scale (screen-visible cells, a few hundred waypoints);
			# a spatial grid is the upgrade if a very long walk makes it drag.
			if not world.is_explored(center):
				draw_rect(rect, FOG_UNKNOWN)
				continue
			var cl := _cluster(cell, TILE_CLUSTER)
			# 1.0 deep in a lake, 0.0 well inland, a ramp across the bank between.
			var wet := 0.5 - world.water_depth(center) / (SHORE * 2.0)
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
			draw_texture_rect_region(tex, rect,
				Rect2(Vector2(idx % TILE_COLS, idx / TILE_COLS) * TILE, TILE))
			if not world.is_visible_now(center, ppos):
				draw_rect(rect, FOG_REMEMBERED)
	draw_set_transform_matrix(Transform2D.IDENTITY)

# T9y: the one place the "you can see it now" vs "you only remember it"
# distinction turns into a colour. Desaturate toward the fog's own blue-black
# and drop the alpha rather than simply darkening: a darkened faction colour
# still reads as that faction's colour at full confidence, which is exactly
# the claim a remembered prop must not make. FOG_REMEMBERED is the ground
# tint doing the same job one layer down; these numbers are tuned to sit
# with it, not independently.
const REMEMBERED_FADE := 0.55     # how far toward the fog colour a remembered prop goes
const REMEMBERED_ALPHA := 0.72
func _remembered(col: Color, live: bool) -> Color:
	if live:
		return col
	var faded := col.lerp(Color(FOG_REMEMBERED, 1.0), REMEMBERED_FADE)
	faded.a = col.a * REMEMBERED_ALPHA
	return faded

# T9y: the map is thousands of units across and the camera shows a few hundred
# of them, so a settlement that is not on screen may as well not exist — the
# fog's settlement beacons (32c4c88) gave the player something to walk toward
# only while it happened to be in frame. These are the same beacons, pinned to
# the edge of the frame when they fall outside it: the nearest few, each a
# chevron pointing the way with its name and how far off it is.
#
# Three, not all of them: on the large and procedural maps every settlement is
# off screen most of the time, and a rim of chevrons is no more use than none.
# The nearest three are the ones a party could plausibly be heading for.
const OFFSCREEN_MARKERS := 3
const OFFSCREEN_MARGIN := 26.0    # how far in from the viewport edge a chevron sits
const OFFSCREEN_SIZE := 9.0
func _marker_frame() -> Rect2:
	return Rect2(Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN),
		size - Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN) * 2.0)

# Which settlements earn a chevron: the ones not currently on screen, nearest
# first, capped. Split out of the draw so the choice is testable without a
# viewport — the drawing itself is the part a test can only look at.
func _offscreen_settlements(frame: Rect2, ppos: Vector2) -> Array:
	var off: Array = []
	for s in world.settlements:
		if frame.has_point(_pix(s.position)):
			continue
		off.append(s)
	off.sort_custom(func(a, b):
		return ppos.distance_squared_to(a.position) < ppos.distance_squared_to(b.position))
	return off.slice(0, OFFSCREEN_MARKERS)

func _draw_offscreen_markers(ppos: Vector2) -> void:
	if world.settlements.is_empty():
		return
	var frame := _marker_frame()
	if frame.size.x <= 0.0 or frame.size.y <= 0.0:
		return      # a viewport too small to have an inside; nothing to pin to
	for s in _offscreen_settlements(frame, ppos):
		_draw_offscreen_marker(s, frame, ppos)

func _draw_offscreen_marker(s, frame: Rect2, ppos: Vector2) -> void:
	var center := frame.position + frame.size * 0.5
	var to := _pix(s.position) - center
	if to.length() < 0.001:
		return
	# Push out along the direction until one axis hits the frame, then take the
	# nearer hit — the standard "clamp a ray to a box" trick, in screen space so
	# the chevron points where the eye would travel, not where the world's own
	# axes go.
	var scale_x: float = (frame.size.x * 0.5) / maxf(absf(to.x), 0.001)
	var scale_y: float = (frame.size.y * 0.5) / maxf(absf(to.y), 0.001)
	var at := center + to * minf(scale_x, scale_y)
	var dir := to.normalized()
	var col := faction_color(s.faction)
	var tip := at + dir * OFFSCREEN_SIZE
	var side := Vector2(-dir.y, dir.x) * OFFSCREEN_SIZE * 0.62
	draw_colored_polygon(PackedVector2Array([tip, at - dir * OFFSCREEN_SIZE * 0.5 + side,
		at - dir * OFFSCREEN_SIZE * 0.5 - side]), col)
	# World units read as nothing to a player; the clock is the map's real
	# currency, so the distance is quoted as the travel time it costs at the
	# party's own speed (World.SPEED is units per world-minute).
	var p := world.player()
	var speed: float = p.speed if p != null and p.speed > 0.0 else World.SPEED
	var mins: float = ppos.distance_to(s.position) / speed
	var label := "%s  %s" % [s.sname, _travel_time(mins)]
	var w := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	# Keep the text inside the frame whichever edge the chevron landed on. On a
	# side edge the plain clamp is not enough on its own: centring the label on
	# a chevron 26px from the edge puts half of it off screen, and clamping
	# that back shoves the text under the chevron it belongs to. So on those
	# edges the label is pinned strictly inboard of its own arrow first, and
	# only then clamped.
	var text_at := at - dir * (OFFSCREEN_SIZE + 4.0)
	text_at.x -= w * 0.5
	const SIDEWAYS := 0.3       # |dir.x| past this and the chevron is on a left/right edge
	if dir.x < -SIDEWAYS:
		text_at.x = maxf(text_at.x, at.x + OFFSCREEN_SIZE + 4.0)
	elif dir.x > SIDEWAYS:
		text_at.x = minf(text_at.x, at.x - OFFSCREEN_SIZE - 4.0 - w)
	text_at.x = clampf(text_at.x, 2.0, maxf(2.0, size.x - w - 2.0))
	text_at.y = clampf(text_at.y, 12.0, maxf(12.0, size.y - 4.0))
	# A one-pixel drop shadow: the label is faction-coloured (that is how you
	# tell whose town it is) and the edge of the frame is wherever the party
	# happens to be looking, so it has to stay readable over bright water and
	# pale roofs as well as over the dark fog.
	draw_string(ThemeDB.fallback_font, text_at + Vector2(1, 1), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.75))
	draw_string(ThemeDB.fallback_font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# O11/O12: a medieval building on each footprint the blocks stood on — a city
# gets three, a town two, painter-sorted among themselves. The footprint ring
# stays: every faction's walls are the same stone, and faction is the one thing
# the map still has to read at a glance.
# T91: a discovered lair. Grey once looted, faction-tinted red while there's
# still a fight in it, so a glance says which lairs are done. Tier 0: a 3D
# diorama in the Lairs3D layer above this map, same contract as Settlements3D
# — it replaces the "☠" glyph only; shadow, ring and name label stay shared.
func _draw_lair(l, at: Vector2, live := true) -> void:
	var col := _remembered(Icons.COL_MUTED if l.looted else Icons.COL_FOE, live)
	var r := 14.0 * _zoom
	_soft_shadow(at, r * 0.85)
	_fan(at + _iso(LIGHT) * r * 0.5, _ring(at, r), col.darkened(0.35), col.darkened(0.62))
	draw_polyline(_ring(at, r, true, true), col.darkened(0.15), 1.5, true)
	if not (_lairs3d and _lairs3d.has_model(l)):
		var fs := int(18 * _zoom)
		draw_string(ThemeDB.fallback_font, at - Vector2(fs * 0.35, -fs * 0.3), "☠",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _remembered(Icons.COL_HEAD, live))
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), l.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _remembered(Icons.COL_BODY, live))

func _draw_settlement(s, at: Vector2, live := true) -> void:
	var col := _remembered(faction_color(s.faction), live)
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
			_draw_building(bases[k], h, style + k, pair + k, live)
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), s.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _remembered(Icons.COL_BODY, live))

# One building: a whole house in one cell now (the old Town Pack's modular
# left/right wall halves are gone with it). `base` is the house's near ground
# corner, i.e. the point it stands on; `h` scales the cell, whose own 128x120
# proportions are kept so the five buildings stay at their relative sizes.
func _draw_building(base: Vector2, h: float, style: int, pair: int, live := true) -> void:
	var cell := BUILDING * (h / BUILDING.y)
	var src := Vector2(style % BUILDING_STYLES, pair % BUILDING_PAIRS) * BUILDING
	draw_texture_rect_region(BuildingTex,
		Rect2(base - BUILDING_ANCHOR * (h / BUILDING.y), cell), Rect2(src, BUILDING),
		_remembered(Color.WHITE, live))

# O14: a board-game pawn standing on the party's position, tinted to its faction.
# `at` is the ground point, so the sprite hangs above it rather than centring on
# it, the way a building sits on its near corner. Sizes are the old ball token's
# radii kept as the token's half-width, so parties read at the same scale as before.
func _draw_party(p, at: Vector2, live := true) -> void:
	var col := _remembered(faction_color(p.faction, p.is_player), live)
	var rad := (11.0 if p.is_player else 9.0) * _zoom
	var h := rad * 2.0 * PAWN.y / PAWN.x
	_soft_shadow(at, rad * 0.8)
	if p.is_player:
		# T9x: a layered glow, not just a thin outline — needs to read as
		# "this one is you" regardless of which hero figure is showing, now
		# that the player can pick any of them from the Party screen. Drawn
		# under the sprite so the ring's far arc reads as behind the pawn.
		# (the old single ring was also never actually closed — draw_polyline's
		# 3rd arg is antialiasing, not _ring()'s own `closed`, so it was
		# missing one segment; fixed here too.)
		for i in 3:
			draw_colored_polygon(_ring(at, rad * (1.5 + 0.35 * i)),
				Color(Icons.COL_GOLD, 0.18 - 0.05 * i))
		draw_polyline(_ring(at, rad * 1.7, true, true), Icons.COL_GOLD, 2.5, true)
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
		"%s (%d)" % [label, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		_remembered(Icons.COL_BODY, live))

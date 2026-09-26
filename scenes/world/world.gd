# O2 — the open-world map screen: core/world.gd's map, drawn as a real 3D world
# you can turn, tilt, pan and zoom, with a pause button on the WorldClock and
# click-to-move for the player party. All state lives in core/world.gd; this
# only shows it and feeds it goals.
#
# Run standalone:  godot --path . scenes/world/world.tscn
#
# THE MAP IS 3D NOW. It used to be a painting with models taped on: a
# canvas_item shader painted the ground by projecting every screen pixel back to
# a world position, props were sorted 2D sprites drawn over it, and three
# separate transparent SubViewports — settlements, lairs, parties — each carried
# a private camera and a private copy of the projection so their models would
# land on the right pixels. Nothing in any of those four layers could occlude
# anything in any other.
#
# There is one 3D world now (scenes/world/world_view3d.gd): one viewport, one
# camera, one sun. The ground is a mesh, the woods are trees, the towns and
# lairs and marching bands are models standing on it, footprints are decals
# lying on it, and the depth buffer decides what is in front of what — which is
# the only reason the camera can be turned at all.
#
# WHAT DID NOT CHANGE, and why. The old projection was `_iso()`: rotate by
# ISO_YAW, scale by ISO_GAIN, squash y by ISO_SQUASH. That is not an
# approximation of an orthographic camera at yaw ISO_YAW and pitch
# asin(ISO_SQUASH) — it IS one. So the yaw and the pitch stopped being constants
# and became camera state, and every mechanism built on `_pix()` / `_unpix()`
# came through untouched: click-to-move, the ground mask's visible-cell box, the
# off-screen chevrons, the minimap's view rectangle. See world_view3d.gd's
# header for why the camera stays orthographic rather than becoming perspective.
#
# WHAT THIS CONTROL STILL DRAWS IN 2D. Three things, all of them annotation
# rather than scenery: the marching route and its goal ring, the name label
# under each landmark, and the chevrons pinned to the frame for settlements that
# are off screen. Everything that stands on the ground, or lies on it, is
# geometry in the view.
#
# ponytail: scenes/main.gd's combat Board still carries its own copy of the
# dimetric helpers (_iso/_ring/_fan/_soft_shadow) — a shared `core/iso.gd` was
# always the upgrade path and is still not taken, because the board's camera is
# fixed and this one no longer is; they are no longer the same function.
extends Control

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBattle = preload("res://core/world_battle.gd")
const Settlements3D := preload("res://scenes/world/settlements3d.gd")
const Lairs3D := preload("res://scenes/world/lairs3d.gd")
const Landmarks3D := preload("res://scenes/world/landmarks3d.gd")
const Party3D := preload("res://scenes/world/party3d.gd")
const Minimap := preload("res://scenes/world/minimap.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Potions = preload("res://core/potions.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const Rumors = preload("res://core/rumors.gd")
const Site = preload("res://core/site.gd")
const SiteScreen = preload("res://scenes/world/site_screen.gd")
const WorldThreat = preload("res://core/world_threat.gd")
const WorldRoadHome = preload("res://core/world_road_home.gd")
const Regions = preload("res://core/regions.gd")
const EnemyCasters = preload("res://core/enemy_casters.gd")
const Travel = preload("res://core/travel.gd")
const EventCard = preload("res://scenes/world/event_card.gd")
const DiceRoll = preload("res://scenes/dice_roll.gd")
const Settings = preload("res://core/settings.gd")
const Approach = preload("res://core/approach.gd")
const ApproachCard = preload("res://scenes/world/approach_card.gd")
const StoryCard = preload("res://scenes/world/story_card.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const Trance = preload("res://core/trance.gd")
const WorldForage = preload("res://core/world_forage.gd")
const WorldChase = preload("res://core/world_chase.gd")
const WorldFlee = preload("res://core/world_flee.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Campaign = preload("res://core/campaign.gd")   # T25 item names/prices, split_xp and bank_win
const Dice = preload("res://core/dice.gd")
const ManualOverlay = preload("res://scenes/manual/manual.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")
const BugReportOverlay = preload("res://scenes/bugreport/bug_report.gd")
const BugReport = preload("res://core/bug_report.gd")
const Sound = preload("res://core/audio.gd")
const Quest = preload("res://core/quest.gd")
const Tips = preload("res://core/tips.gd")   # #151
const Objectives = preload("res://core/objectives.gd")
const Spoils = preload("res://scenes/world/spoils.gd")   # #157: the after-action page
const Traits = preload("res://core/traits.gd")            # #176 step 3: what a fight leaves on the people in it
const TraitMoment = preload("res://scenes/world/trait_moment.gd")
const Figures3D = preload("res://scenes/figures3d.gd")
const Ach = preload("res://core/achievements.gd")
const Leveling = preload("res://core/leveling.gd")   # #118: who is owed a level
const Ladder = preload("res://core/ladder.gd")
const Defeat = preload("res://core/defeat.gd")   # audit 1.8: what a loss costs past the purse, and the end of a company
const Combat = preload("res://core/combat.gd")   # audit 3.5: its WITHDRAWN outcome and the line for it
const Callings = preload("res://core/callings.gd")
const Bench = preload("res://core/bench.gd")
const EnemyNames = preload("res://core/enemy_names.gd")   # a band's name, never its id
const Downtime = preload("res://core/downtime.gd")
const Lodge = preload("res://core/lodge.gd")   # the company's house: the square's door, the lodge page
const Recruits = preload("res://core/recruits.gd")   # who is looking for work at the inn, and the fee
const Fallen = preload("res://core/fallen.gd")       # audit 2.1: the one door a death comes through, and the roll
const Service = preload("res://core/service.gd")     # audit 2.2/2.5: who struck the blow, a veteran's record
const ChoicePick = preload("res://core/rules/choice_pick.gd")   # humanize(), for a hireling's species and class
const Catalog = preload("res://core/rules/catalog.gd")   # the trainer's feat names
const Posting = preload("res://core/quest_posting.gd")
const Contracts = preload("res://core/contracts.gd")
const Loot = preload("res://core/loot.gd")
const RNG = preload("res://core/rng.gd")
const CharacterSave = preload("res://core/character_save.gd")
const WorldSave = preload("res://core/world_save.gd")
const RouteTravel = preload("res://core/route_travel.gd")   # #231: the roads, when this is a route world
const Grudges = preload("res://core/grudges.gd")

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
# Since 2026-09-25 the walk out of a site has a gentler floor of its own until
# dawn or a long rest (core/world_road_home.gd), which is why both assess()
# calls below pass the world.
# O6 visit distance. Deliberately wider than ENCOUNTER_RADIUS: a settlement is a
# fixed landmark drawn at ~26 world units of radius (a city footprint) rather than
# a 6-unit token, so "close enough to walk in through the gate" is its own number.
# It is NOT widened by speed the way the encounter trigger is: a settlement is
# something you steer into on purpose, and marching past one at 8x without the
# market opening is the player's own choice, not a missed ambush.
const VISIT_RADIUS := 34.0
# The board an ambush happens on when the encountered faction has no theme of
# its own in Scaler.THEME_FACTION — open country, which is where the map is.
# O-biome: only the fallback of a fallback now — Scaler.BIOME_BOARD answers
# for every biome the map actually has, so this is what a position outside every
# biome disc gets, which on a built map is nothing.
const DEFAULT_THEME := "forest-clearing"
# core/world_bands.gd's KINDS ids, for the ones carrying more than their kit.
const PURSE := {"caravan": 2.0}

# The camera the map opens on, and the numbers the projection is quoted
# against. ISO_YAW and ISO_SQUASH are no longer the projection — they are its
# starting point, because the camera turns now — but they are still the
# contract every asset in scenes/world/ is sized to (settlement_kit.gd,
# lair_kit.gd and their gallery shots all measure themselves against them), so
# they keep their names and their values.
const ISO_YAW := 35.0
const ISO_SQUASH := 0.38
# The pitch ISO_SQUASH always was. A squash of s on the depth axis is exactly
# what an orthographic camera at elevation asin(s) does; writing it down as the
# angle is the whole of what let the camera start tilting.
const ISO_PITCH := rad_to_deg(asin(ISO_SQUASH))
const ISO_GAIN := 1.85
const LIGHT := Vector2(-0.30, -0.34)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
# How far the camera may be tilted. Not to the horizon and not to straight
# down: at 0 the ground is edge-on and the map is a line, and past ~82 the
# footprint rings stop reading as ground and the models stop having a side.
const PITCH_MIN := 12.0
const PITCH_MAX := 82.0
const YAW_STEP := 15.0                   # one keypress of turn — a twelfth of the way round
const PITCH_STEP := 6.0
# Degrees per pixel of drag, for the orbit. Tuned so a drag across half the
# window is about a quarter turn, which is as much as anyone wants to do in one
# gesture.
const ORBIT_SENS := Vector2(0.32, 0.22)
# The ground is a shader over a cell-resolution mask (see _update_ground):
# CELL is the mask's grain in world units, and the memory (world.explored) is
# rasterised at the same grain.
const CELL := 15.0          # ground cell, in world units
# A forest stands or falls over a TILE_CLUSTER x TILE_CLUSTER block of cells
# (~120x120 world units) rather than per cell, so the woods come as woods.
const TILE_CLUSTER := 8
# T9x: two fog tiers, both the ground shader's. Never explored is flat and
# near-black; explored-but-not-currently-visible is a translucent dark tint over
# the real ground, so the shape of ground you've already seen still reads, just
# dimmed. Declared with the view, which needs them first — see _view below.

const WOODED := 0.78              # a cell block whose hash lands above this is forest
# O-biome: the threshold is per biome now, and WOODED above is the fallback for
# a kind this build does not know (an old save, a content pack). The map used
# to be one uniform 22 % speckle of wood everywhere; the discs in
# core/world.gd's `biomes` decide the KIND of ground and these decide how
# densely that kind grows, so a wood now comes as a wood and the downs between
# them read as open country instead of the same speckle at the same rate.
#
# These are a LOOK, not a balance number — nothing in a fight reads them (see
# docs/expansion-plan.md's biome note for the knobs that would be, and why they
# are deferred). Tune them by looking at tests/shot_world.gd.
const WOODED_BY_BIOME := {
	"downs": 0.88,   # 12 %: copses and windbreaks, not woods
	"woods": 0.32,   # 68 %: closed canopy with clearings in it
	"marsh": 0.90,   # 10 %: a few drowned stands
}
# What share of explored ground scatter3d.gd should BUDGET trees for. It used
# to read `1.0 - WOODED` (0.22), which was the forest fraction back when one
# threshold covered the whole map; with the table above the real fraction
# depends on how much of the map is wood, so the estimate is named instead of
# derived. It only sizes the thinning loop — quantised to powers of two, then
# corrected for by `grow` — so it wants to be roughly right and never zero.
# Over-estimating is the safe direction: it thins sooner and plants fewer.
const FOREST_FRACTION_EST := 0.34
# What a biome is called in the HUD bar. Keyed loosely (`.get(kind, kind)`) so
# a kind this build has never heard of — an old save, a content pack — prints
# its own name rather than vanishing or crashing the bar.
const BIOME_LABEL := {"woods": "woodland", "marsh": "marshland"}
# Half-width of the shoreline band, in world units (~0.7 of a CELL either side).
# Across it a cell's chance of being water falls from 1 to 0, so the bank frays
# into the grass over a tile or so instead of ending on a cell boundary — the
# WOODED threshold's trick, with the noise compared against terrain rather than
# against a constant.
const SHORE := 35.0

# How big a landmark's footprint is, in world units — the ring around a town,
# the disc under a lair, the shadow under a marching band. These are the map's
# own long-standing radii; they only look different because they used to be
# written as screen pixels scaled by the zoom, which is the same numbers said
# the long way round.
#
# They are FLOORS now rather than the answer. The ring used to be painted over
# the map after the buildings were, so a ring the same size as the town it
# encircled still read. It lies on the ground now and the town stands in front
# of it, so a ring inside the walls is a ring nobody sees — and the ring is how
# you tell whose town it is at a glance. What a footprint ends up as is
# whichever is larger: the floor here, or the model's own measured span grown
# by FOOTPRINT_CLEARANCE. See _footprint().
const SETTLEMENT_RADIUS := {"city": 26.0, "town": 17.0, "camp": 12.0}
const LAIR_RADIUS := 14.0
const LANDMARK_RADIUS := 10.0
const PLAYER_RADIUS := 11.0
const BAND_RADIUS := 9.0
# #229: the ring round two bands locked in a clash. They met no further apart
# than ENCOUNTER_RADIUS (a fast clock can stretch _trigger() past it, but not by
# more than the bands' own footprints), and the ring sits on the midpoint, so
# half of that plus one band's footprint takes both of them in.
const CLASH_RADIUS := ENCOUNTER_RADIUS * 0.5 + BAND_RADIUS
# How far the ring stands off the model inside it. Just past the square root of
# two, and that is the whole of the reason for the number: footprint_of()
# measures the model's half-span on its widest axis, and a settlement diorama's
# base is a slab, so its CORNERS reach 1.41 half-spans out. A ring inside that
# is a ring under the town — which is what the first pass shipped, with one
# violet sliver showing past the near edge of Ashfell and nothing anywhere else.
const FOOTPRINT_CLEARANCE := 1.45
# The ring around a footprint, as a fraction of its radius, and how far the
# player's own gold halo reaches past their band.
const RING_WIDTH := 0.11
const HALO_SCALE := 2.0
# How strongly the ground inside the ring is tinted. The flat map painted this
# disc solid, because the disc WAS the settlement — the buildings were sprites
# standing on it. There is a real town on it now, so a solid disc is a coloured
# pond around the walls; what the ground wants instead is a tint that says
# whose country this is and then gets out of the way.
const SETTLEMENT_FILL := 0.34

var world: World
var party: Party            # injected by whoever opens the map, or a demo roster
var _combat = null          # the live scenes/main.tscn instance, while fighting
var _combat_overlay: Control = null
var _pan := Vector2.ZERO
var _zoom := 1.0
var _yaw := ISO_YAW          # which way is north on screen; the camera turns, the world does not
var _pitch := ISO_PITCH      # how far the camera is tilted up off the ground
var _origin := Vector2.ZERO
var _pause_btn: Button
var _gold_lbl: Label
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
var _inventory_panel: Control = null # the shared pack, as tiles — see _toggle_inventory
var _menu_panel: Control = null      # the Esc pause menu, or null — see _toggle_menu()
var _spoils_panel: Control = null    # issue #30's after-action page, or null
var _levelup_panel: Control = null   # issue #118's "somebody can level up" page, or null
var _levelup_told: Dictionary = {}   # character id -> the level it was announced at
var _delve_haul: Dictionary = {}     # what the delve in progress has paid so far; {} outside one
var _quest_news: Array = []          # quest progress the last _bank() made, for that page
var _lair_btn: Button                # T91: "Search for a lair" / "Attack the lair", or hidden
var _lair_sneak_btn: Button          # T9x: "Slip past the guardians" — visible once discovered, unlooted
var _lair_target: World.Lair = null  # whichever lair _check_lairs() last found in range
var _route_search := false           # #231: the lair button is the Survival check at a fork (RouteTravel.searchable)
var _lair_settle_btn: Button
var _settle_target: World.Lair = null   # a cleared lair in range the party could settle (core/raids.gd)
var _place_btn: Button                # landmarks: "Visit the Nine Sisters" / "Search the ground (Survival)", or hidden
var _place_target: World.Landmark = null   # whichever landmark _check_places() last found in range
var _place_open: World.Landmark = null     # the one whose card is up
var _site = null                     # D1: the delve in progress (core/site.gd), or null
# D3: last road-event roll, and the card showing one. Scene-local like the
# forage stamp — a reload just restarts the cadence, which is not worth a
# save-format field for something that fires every six world-hours anyway.
var _last_travel_at: float = 0.0
var _event_card: Control = null
# #70: the map halts when the party reaches where it was sent, and runs again
# the moment it is sent somewhere else — arriving is not a reason to keep the
# clock burning while nobody is giving orders.
var _was_travelling := false
var _halted_on_arrival := false
# D4: the band the player is deciding how to meet, and the card asking. Bands
# slipped past go on `_slipped` so walking away does not immediately re-trigger
# the same meeting — the settlement gate's `_left` does the same job.
var _approach_foe = null
var _approach_card: Control = null
var _slipped := {}
# The band the player clicked on and is marching to meet (see _seek()), and the
# point the march was last aimed at — the order is the player's only while the
# party's destination is still that point. "" when nobody is being sought.
var _meet_id := ""
var _meet_name := ""   # what the HUD calls it, kept for the line after it is gone
var _meet_aim := Vector2.INF
# A chase the party cannot win on legs alone (core/world_chase.gd): when it may
# next roll to run the band down, and how many of those rolls it has missed.
var _chase_next_at := 0.0
var _chase_misses := 0
# When core/world_flee.gd last sized every band up against the party. -INF so
# the first frame gauges; after that every GAUGE_MINUTES of world time, which
# is soon enough to catch a level-up or a band that has walked into a new
# country, and far cheaper than pricing the party every frame.
var _gauged_at := -INF
var _pace_btn: Button
var _bottom_bar: HBoxContainer       # the road actions and their messages; _layout_minimap seats it
var _site_screen: Control = null     # ...and the descent screen drawing it
# D6: the country the party is standing in, and the label that says so. `_region`
# is last frame's band — a crossing is the only thing anybody wants to be told
# about, and you cannot notice one without remembering where you were.
var _region: Dictionary = {}
var _warned_bands := {}              # bands already warned about; a seam you step over
                                     # twice is not news twice
var _region_lbl: Label
var _region_msg: Label               # the last crossing, same "persists" contract as _lair_msg

var _ladder_title_seen := 0          # the last renown title _check_ladder() said; set on load
var _rungs_seen: Dictionary = {}     # faction -> the last rung _check_ladder() said; set on load
var _moment_queue: Array = []         # #176: trait_moment dicts earned while a screen was up; _check_moments() shows them
var _moment: Control = null            # the moment on screen, or null
var _trait_news: Array = []            # #176: one line per trait gained or lost in the last fight, for the spoils page
var _calling_queue: Array = []        # [char_id, complete()'s result] pairs paid on the road while a screen was up; _check_callings() shows them
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
var _landmarks3d
var _party3d
var _minimap: Control = null   # T9y: the corner map inset, see _layout_minimap()
# M7: the content pack's story, mid-telling — a core/mod/story_runtime.gd
# injected by scenes/game/game.gd alongside the map it belongs to, or null for
# every run on a built-in map. Everything below treats null as "no story", so a
# normal run costs one `if` per frame and nothing else.
var story = null
# Co-op (docs/spike-coop.md §7). The guest's copy of the host's map: nothing
# here ticks, nothing is ordered, nothing is saved — positions and the clock
# come off the wire (Coop.link.map_latest), the whole save when something
# structural changed. The host's screen is the ordinary one, plus _coop_share.
const Coop = preload("res://core/coop.gd")
var spectator := false
var _map_share_t := 0.0      # host: seconds since the last map delta went out
const MAP_SHARE_EVERY := 0.5   # host: how often a delta leaves; the guest paces itself off this
var _synced_arrival := 0     # host: Coop.link.arrivals the full save was last sent for
# Issue #133: the guest used to write each delta straight onto the map, which
# made the road two frames a second — a party that jumped a step, stood still
# for half a second, jumped again. What crosses the wire is the right amount
# (positions twice a second is nothing to send and nothing to lose); the frames
# in between are this screen's to draw. A delta is a TARGET now, and _spectate()
# walks the map toward it over the interval the last two arrived in, so the
# mirror moves at the speed the host's party is actually moving and is never
# drawn anywhere the host has not been.
var _mirror_from := {}       # guest: party id -> where it stood when the last delta landed
var _mirror_to := {}         # guest: party id -> where the host says it stands
var _mirror_clock := Vector2.ZERO   # guest: the same for world.clock.elapsed — [from, to]
var _mirror_span := MAP_SHARE_EVERY # guest: seconds between the last two deltas
var _mirror_age := 0.0       # guest: seconds since the last one
var _mirror_seen := false    # guest: the first delta snaps; every one after it glides
var story_card: Control = null       # the beat being shown, or null
var _story_panel: Control = null     # the journal overlay, toggled off the HUD
var _story_btn: Button

var world_size := "small"   # "small" | "large" — which built-in map _ready() falls back to
                             # when nobody injected a `world` (a fresh start, not O13's resume)

# The 3D map itself — viewport, camera, sun, ground mesh, woods, footprints,
# and the four layers of landmarks. It draws behind this control, so what this
# control still paints reads as annotation on the map rather than as scenery in
# it. _update_ground() hands it the fog mask; everything else it works out from
# the camera state above.
const WorldView3D := preload("res://scenes/world/world_view3d.gd")
var _view: WorldView3D
# The fog's two colours live on the view (the ground shader and the 3D
# background both need them before this screen has said anything) and are named
# here so the rest of the map — remembered props, the minimap — reads one copy.
const FOG_UNKNOWN := WorldView3D.FOG_UNKNOWN
const FOG_REMEMBERED := WorldView3D.FOG_REMEMBERED
var _mask_tex: ImageTexture
var _mask_key: Array = []

func _ready() -> void:
	theme = Icons.dark_theme()   # standalone runs; under game.gd it is the same theme inherited
	if world == null:
		match world_size:
			"large": world = _large_world()
			"procedural": world = ProceduralWorld.build(int(OS.get_environment("SORCMERC_SEED")))
			_: world = _small_world()
		# #231 phase 1: a map built while SORCMERC_ROUTES=1 is set is born a
		# route world — roads only, nobody on the map but the company. Only a map
		# built here: a resumed save is what it already was (core/route_travel.gd
		# says why), and a pack's world is adopted where game.gd builds it.
		if RouteTravel.flag_on():
			RouteTravel.adopt(world)
	RouteTravel.clear_met(world)   # #231: a road meeting the game was closed on ended with it
	if party == null:               # same demo roster scenes/campaign/campaign.gd falls back to
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
	# The map opens on the party — a resumed save left them wherever they were,
	# and the centre of the world is not it.
	if world.player() != null:
		center_on(world.player().position)
	# The 3D map, and the four layers of landmarks standing in it. They are
	# children of the view's world now rather than of this Control: one
	# viewport, one camera, one depth buffer, so a figure can walk behind a
	# town wall. add_layer() is the whole of their wiring.
	_view = WorldView3D.new()
	_view.world_map = self
	add_child(_view)
	_settlements3d = Settlements3D.new()
	_view.add_layer(_settlements3d)
	_settlements3d.reset(world)
	_lairs3d = Lairs3D.new()
	_view.add_layer(_lairs3d)
	_lairs3d.reset(world)
	_ladder_title_seen = Ladder.title_index()   # a loaded save's title is not news
	for f in WorldAI.CIVILIZED:                  # ...nor its rungs
		_rungs_seen[f] = Ladder.rung(f)
	_landmarks3d = Landmarks3D.new()
	_view.add_layer(_landmarks3d)
	_landmarks3d.reset(world)
	_party3d = Party3D.new()
	_view.add_layer(_party3d)
	_party3d.reset(world)
	_last_forage_at = world.clock.elapsed   # T9x: start the cadence from load time, not zero
	_last_travel_at = world.clock.elapsed   # D3: same, for road events
	set_process(true)
	_build_hud()
	_refresh_pace_btn()
	if spectator:
		_spectator_hud()

# Hand-placed stand-ins so the scene has something to render and move. Real
# spawning is a later phase's job (O3 onward).
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const Landmarks = preload("res://core/landmarks.gd")
const WorldBands = preload("res://core/world_bands.gd")
const WorldHomes = preload("res://core/world_homes.gd")
var _bands_rng := RNG.new()   # #163: refills are not replayable; a live clock is the seed

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
	# counterpart to model, so it keeps a roster (for the headcount) and takes
	# the single figure per faction combat already uses (figures3d.gd's
	# FOE_MODELS) rather than a role model.
	bandits.troops = [{"role": "heavy", "level": 3}, {"role": "light", "level": 5}]
	WorldAI.hunt(bandits)
	var goblins := w.add_party(World.RoamingParty.new("goblins", Vector2(380, 300), "goblinoid"))
	goblins.troops = [{"role": "heavy", "level": 1}, {"role": "heavy", "level": 1}, {"role": "light", "level": 2}]
	WorldAI.hunt(goblins)
	# A beast pack, now that assets/beasts/ covers the faction: fights it as a
	# forest-clearing roster (Scaler.THEME_FACTION), so the models get seen.
	var wolves := w.add_party(World.RoamingParty.new("wolves", Vector2(-150, 180), "beast"))
	wolves.troops = [{"role": "light", "level": 1}, {"role": "light", "level": 1}, {"role": "light", "level": 2}]
	WorldAI.hunt(wolves)
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
	# O-biome: what KIND of country each part of the map is (core/world.gd's
	# `biomes`). Hand-placed for the same reason the water is — four towns and
	# one river is a map you can read off the page — and stamped after it,
	# because the marsh wants to sit on the river's lower reach.
	#
	# Greenmarch is the elf town, so the wood is its country; the river goes
	# soft where it flattens out before Ashfell. Everything no disc claims is
	# World.DEFAULT_BIOME, which is most of the map and is the point: the downs
	# are the ground the woods are an exception to.
	w.add_biome(Vector2(420, -180), 260.0, "woods")   # Greenmarch's forest
	w.add_biome(Vector2(-330, 250), 190.0, "woods")   # the stands above Dun-Arrow
	w.add_biome(Vector2(110, 360), 170.0, "marsh")    # where the river slows

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
	# 2026-09-25: was (300, 620), frac 0.87 — a hair past the frontier's seam, so the
	# undead had no lair in their own country (Regions.HOMES) and core/world_homes.gd
	# would have dug them a second graveyard. Twenty units in, frac 0.84.
	w.add_lair(World.Lair.new("zombie-graveyard", Vector2(290, 600), "undead", "Zombie Graveyard"))
	w.add_lair(World.Lair.new("dragon-cave", Vector2(680, -400), "dragon", "Dragon's Cave"))
	Landmarks.place(w, 41)   # a fixed seed: the small map is hand-placed, and so are its landmarks
	WorldHomes.fill(w, 41)   # a lair for every people, after the landmarks (core/world_homes.gd)
	WorldBands.seed(w, 41)   # #163: fill the roads to the cap, around the bands above
	return w

# World.tick() advances the clock itself and gates movement on it, so one call
# per frame is the whole update.
func _process(delta: float) -> void:
	if spectator:
		_spectate(delta)
		_render()
		return
	# #231: where the company stood before the frame's move — the road's
	# odometer counts what it walked (_check_routes).
	var route_from: Vector2 = world.player().position if world.player() != null else Vector2.ZERO
	# O7: the clock's own advance (0 while paused) both drains O6's queued opinion
	# deltas off the settlements and runs the slow drift back toward neutral.
	var dt := world.tick(delta)
	party.world_now = world.clock.elapsed
	# #176 step 4: where the party is, for the road's trait terms — the same
	# ground, country and kind of place a fight here would be stamped with.
	var hp := world.player()
	party.here = {} if hp == null else {"biome": world.biome_at(hp.position),
		"band": Regions.band_of(world, hp.position), "night": world.clock.is_night(),
		"site": "town" if not _visit.is_empty() else ("lair" if _site != null else "road")}
	for ch in party.roster:
		Potions.expire(ch, party.world_now)
		# #176: Emboldened runs out, a wound heals with time — said on the HUD
		# line, since nothing is happening to put a whole screen up for.
		for gone in Traits.expire(ch, party.world_now):
			_lair_msg.text = "%s is no longer %s." % [ch.cname, gone]
	var p0 := world.player()
	if p0 != null:
		world.reveal(p0.position)   # T9x fog of war: permanent once seen
		_follow_meet(p0, dt)        # before the arrival halt, which would pause the clock under it
		_check_arrival(p0)
		# D3: the marching order IS the speed, re-read every frame so changing
		# it on the party screen takes effect the moment you back out.
		p0.speed = World.SPEED * Travel.speed_mult(party)
	FactionOpinion.tick(world, dt)
	Grudges.tick(dt)   # #231: the monster peoples' side, cooling at the same rate
	PartyOpinion.decay(party, dt)   # spike-party-opinions §7: a paused clock drifts nothing, same contract
	if world.clock.elapsed >= _gauged_at + WorldFlee.GAUGE_MINUTES:
		world.band_strength = WorldFlee.gauge(world, party)
		_gauged_at = world.clock.elapsed
	WorldAI.update(world, delta)
	_check_encounter(dt)
	# O5: NPC-vs-NPC meetings, no scene, no pause — but not while the player's
	# own fight has the map frozen. #229: a meeting now locks the two bands in
	# a clash for the fight's rounds on the clock, and what comes back here is
	# the fights that have just ENDED, not the ones that just began.
	if _combat == null and not world.clock.is_paused():
		# O6 feeds off the outcome: a settlement near the corpses reads differently
		# on the next visit. O5's resolution itself is untouched.
		for r in WorldBattle.check(world, _trigger(dt), encounter_spec):
			Visit.mark_battle(world, r["loser"].position, world.clock.elapsed)
	_check_visit()
	_check_story()
	_check_lairs()
	_check_places()
	_check_expired_lairs()
	_check_raids()
	_check_ladder()
	_check_moments()
	_check_callings()
	_check_bench()
	_check_raided_visit()
	_check_forage()
	_check_travel()
	_check_routes(route_from)
	_check_region()
	_check_level_ready()
	if _camp_btn != null:
		_camp_btn.visible = party.stash_count(WorldCamp.CAMP_KIT_ITEM) > 0 or party.safe_camp or party.hollow_camp
	_coop_share(delta)
	_render()

# The view, from whatever the model now says: the host's after a tick, the
# guest's after a delta.
func _render() -> void:
	_layout_minimap()   # this Control resizes with the window; the inset follows the corner
	if _clock_lbl != null:
		_clock_lbl.text = WorldSave.day_clock(world.clock.elapsed)
		_gold_lbl.text = "%d ◉" % party.gold
	# The fog mask first, then the 3D map, then this Control's own annotation —
	# all from the same camera state in the same frame. A view rebuilt from last
	# frame's numbers is a map whose labels sit beside the things they name.
	_update_ground()
	if _view != null:
		_view.sync()
	queue_redraw()

# --- co-op: the host shares the road, the guest watches it -------------------

func _coop_share(delta: float) -> void:
	var link = Coop.link
	if link == null or link.role != "host" or _combat != null:
		return
	if link.arrivals != _synced_arrival:   # a guest just sat down (or came back): the whole map
		_synced_arrival = link.arrivals
		link.send(Coop.world_full(world, party, story))
	_map_share_t += delta
	if _map_share_t >= MAP_SHARE_EVERY:
		_map_share_t = 0.0
		link.send(Coop.map_delta(world))
	for m in link.take():   # between fights the road owns the inbox; only one thing on it is for the host
		if m.get("t", "") == "levelup":
			_apply_guest_levelup(m)

func _coop_share_visit() -> void:
	if Coop.link != null and Coop.link.role == "host":
		Coop.link.send(Coop.visit(self))

# A guest's level on their own hero: the same steps their screen made on the
# mirrored copy, made here on the real one, then saved and mirrored back.
func _apply_guest_levelup(m: Dictionary) -> void:
	var ch = party.get_member(String(m.get("hero", "")))
	if ch == null or Coop.mine(party, ch.id):
		return   # not theirs to level
	for step in m.get("steps", []):
		match String(step.get("op", "")):
			"add_level":
				if Leveling.can_level_up(ch):
					Leveling.add_level(ch)
			"decide":
				Leveling.decide(ch, String(step["key"]), Coop.intify(step["decision"]))
	ch.dirty()
	CharacterSave.save(ch)
	_levelup_told[ch.id] = ch.level()
	_autosave()

# Apply what the host last said. A party in the delta the map does not know
# yet waits for the next full save; one the delta no longer names is stale
# until then, which is at most a few seconds — the host autosaves on every
# structural change and each autosave is a full save on the wire.
#
# #133: a delta arriving is one event and drawing the map is another. The
# arrival aims this screen at where the host is; every frame after it moves the
# screen a little further along, so the guest watches the same journey the host
# is watching instead of a slide show of it.
func _spectate(delta: float) -> void:
	var link = Coop.link
	if link == null:
		return
	if not link.map_latest.is_empty():
		_aim_mirror(link.map_latest)
		link.map_latest = {}
		if not link.visit_latest.is_empty():
			var v: Dictionary = link.visit_latest
			link.visit_latest = {}
			_mirror_visit(v)
		_check_level_ready()   # a level on one of OUR heroes is ours to take (see _ready_to_level)
	_mirror_age += delta
	_draw_mirror()

# A delta just landed: keep where the map is DRAWN right now as the start of the
# next glide, and take the host's numbers as its end. The span is how long the
# last two took to arrive rather than the nominal half second, so a slow link
# stretches the motion instead of stuttering through it; a fast one is capped
# so a burst cannot make the map lurch. The first delta on a fresh screen has
# nothing to glide from and snaps.
func _aim_mirror(m: Dictionary) -> void:
	_mirror_span = clampf(_mirror_age, 0.1, 2.0) if _mirror_seen else 0.0
	_mirror_age = 0.0
	_mirror_from.clear()
	for p in world.parties:
		_mirror_from[p.id] = p.position
	_mirror_to.clear()
	var at: Dictionary = m["at"]
	for id in at:
		_mirror_to[id] = Vector2(float(at[id][0]), float(at[id][1]))
	_mirror_clock = Vector2(world.clock.elapsed if _mirror_seen else float(m["elapsed"]),
		float(m["elapsed"]))
	_mirror_seen = true
	if _pause_btn != null:
		_pause_btn.text = "Paused" if bool(m.get("paused", false)) else "Travelling"

# One frame of the glide. Clamped at 1, so a delta that never comes leaves the
# map standing on the last place the host actually was rather than sliding on
# past it.
func _draw_mirror() -> void:
	if not _mirror_seen:
		return
	var t: float = 1.0 if _mirror_span <= 0.0 else clampf(_mirror_age / _mirror_span, 0.0, 1.0)
	for p in world.parties:
		if not _mirror_to.has(p.id):
			continue
		var to: Vector2 = _mirror_to[p.id]
		p.position = (_mirror_from.get(p.id, to) as Vector2).lerp(to, t)
		p.goal = p.position
		p.route.clear()
	world.clock.elapsed = lerpf(_mirror_clock.x, _mirror_clock.y, t)
	party.world_now = world.clock.elapsed
	var p0 := world.player()
	if p0 != null:
		world.reveal(p0.position)

# The host's counter, on our screen: the same panel, from their market dict,
# with every button greyed. The purse and the shelf ride along because a buy
# moves them without an autosave.
func _mirror_visit(v: Dictionary) -> void:
	if bool(v.get("closed", false)):
		_visit = {}
		if _visit_panel != null:
			_visit_panel.queue_free()
			_visit_panel = null
		return
	var s = null
	for cand in world.settlements:
		if cand.id == String(v["sid"]):
			s = cand
	if s == null:
		return
	_visit = Coop.intify(v["m"])
	_visit["settlement"] = s
	_visit_page = String(v["page"])
	_market_tab = String(v["tab"])
	party.gold = int(v.get("gold", party.gold))
	party.stash.assign(Coop.intify(v.get("stash", party.stash)))   # typed Array: assign, not replace
	_build_visit_panel()

# Whether a rebuild from the host's next full save would pull the rug: the
# guest is choosing a level, and the choice is not finished.
func mirror_busy() -> bool:
	return _levelup_overlay != null

# The guest's HUD: the clock and the purse stay, every order goes, and the one
# button is the way out of the room.
func _spectator_hud() -> void:
	for bar in get_children():
		if not (bar is BoxContainer):
			continue
		for c in bar.get_children():
			if c is Button and c != _pause_btn:
				c.visible = false
			elif c is Label and String(c.text).begins_with("Click marches"):
				c.text = "Your host's road — you watch, they order.  Right-drag pans, middle-drag or Q/E turns, R/F tilts, wheel zooms, Home resets."
	if _pause_btn != null:
		_pause_btn.disabled = true
		_pause_btn.text = "Travelling"
	var leave := Button.new()
	leave.text = "Leave the room"
	leave.theme_type_variation = "Quiet"
	leave.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -200; leave.offset_top = 12; leave.offset_right = -16; leave.offset_bottom = 48
	leave.pressed.connect(func():
		Coop.link.close()
		Coop.link = null
		var host := get_parent()
		if host != null and host.has_method("show_coop"):
			host.show_coop())
	add_child(leave)

# #70: pause on reaching the goal; a new goal (a click, or anything else that
# moves it) resumes. Never over a fight, a market, a delve or a card — each of
# those owns the clock already.
func _check_arrival(p0) -> void:
	if _halted_on_arrival:
		if not p0.at_goal():
			_halted_on_arrival = false
			world.clock.resume()
			_pause_btn.text = "Pause"
	elif _was_travelling and p0.at_goal() and _combat == null and _visit.is_empty() \
			and _site == null and _event_card == null and not world.clock.is_paused():
		_halt()
	_was_travelling = not p0.at_goal()

# Stop the party where it stands and the clock with it, until the next order.
# #98: also what a fight's end does — the map used to run on the moment the
# spoils closed, and could walk straight into the next band before the player
# had touched anything.
func _halt() -> void:
	var p := world.player()
	if p != null:
		world.set_goal(p, p.position)
	_halted_on_arrival = true
	_was_travelling = false
	world.clock.pause()
	_pause_btn.text = "Resume"

# Pin a text control's minimum width to what `sample` needs, so live text
# under that width cannot move its neighbours (#94).
static func _hold_width(c: Control, sample: String) -> void:
	var was: String = c.text
	c.text = sample
	c.custom_minimum_size.x = c.get_combined_minimum_size().x
	c.text = was

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
	_gold_lbl = Label.new()
	_gold_lbl.theme_type_variation = "Stat"
	_gold_lbl.add_theme_color_override("font_color", Icons.COL_GOLD)
	bar.add_child(_gold_lbl)
	# D6: which country this is and who it is for, always on. A band that only
	# announced itself at the seam would be invisible to a player who saved in
	# the frontier and came back a week later.
	_region_lbl = Label.new()
	_region_lbl.theme_type_variation = "Dim"
	bar.add_child(_region_lbl)
	# #94: the face has proportional digits, so "08:11" is not the width of
	# "08:10" and every button to the right of the clock crept a pixel each
	# minute. Each live label is held at the width of its widest reading.
	_hold_width(_pause_btn, "Resume")
	_hold_width(_speed_btn, "8x")
	_hold_width(_clock_lbl, "Day 999  23:59")
	_hold_width(_gold_lbl, "99999 ◉")
	var party_btn := Button.new()
	party_btn.text = "Party"
	party_btn.pressed.connect(_open_party)
	bar.add_child(party_btn)
	var pack_btn := Button.new()
	pack_btn.text = "Pack"
	pack_btn.pressed.connect(_toggle_inventory)
	bar.add_child(pack_btn)
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
	var manual := Button.new()
	manual.text = "Manual"
	manual.theme_type_variation = "Quiet"
	manual.pressed.connect(func(): ManualOverlay.toggle(self))
	bar.add_child(manual)
	var bug := Button.new()
	bug.text = "Report a bug  [F3]"
	bug.theme_type_variation = "Quiet"
	bug.pressed.connect(report_bug)
	bar.add_child(bug)
	var title := Button.new()
	title.text = "Title"
	title.theme_type_variation = "Quiet"
	title.pressed.connect(_leave_world)
	bar.add_child(title)
	# Two bars: the state of the run along the top — clock, screens, the way
	# out — and what the party can do where it stands along the bottom, with
	# the messages those actions leave. One row was outrunning the window.
	_bottom_bar = HBoxContainer.new()
	_bottom_bar.add_theme_constant_override("separation", 12)
	add_child(_bottom_bar)
	bar = _bottom_bar
	_lair_btn = Button.new()
	_lair_btn.visible = false
	_lair_btn.pressed.connect(_lair_action)
	bar.add_child(_lair_btn)
	_place_btn = Button.new()
	_place_btn.visible = false
	_place_btn.pressed.connect(_place_action)
	bar.add_child(_place_btn)
	_lair_sneak_btn = Button.new()
	_lair_sneak_btn.text = "Slip past the guardians (Animal Handling)"
	_lair_sneak_btn.visible = false
	_lair_sneak_btn.pressed.connect(_lair_sneak_action)
	bar.add_child(_lair_sneak_btn)
	_lair_settle_btn = Button.new()
	_lair_settle_btn.visible = false
	_lair_settle_btn.pressed.connect(_lair_settle_action)
	bar.add_child(_lair_settle_btn)
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
	# #231: on the roads a click is a place, not ground. Same opening words, which
	# the co-op guest's HUD finds this label by (_spectator_hud).
	hint.text = ("Click marches to a known place, by road." if RouteTravel.on(world) else "Click marches.") + "  Right-drag pans, middle-drag or Q/E turns, R/F tilts, wheel zooms, Home resets.  Space pauses, 1/2/4/8 speed, P party, I pack, Esc menu."
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
	if _bottom_bar != null:
		_bottom_bar.position = Vector2(MINIMAP_GUTTER, size.y - _bottom_bar.size.y - MINIMAP_GUTTER)
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
	if spectator:
		return   # the host's world is not ours to write over our own slot
	WorldSave.save(world, party, story)
	if Coop.link != null and Coop.link.role == "host":
		Coop.link.send(Coop.world_full(world, party, story))   # something structural changed: the guest's map follows
		_coop_share_visit()   # a full save rebuilds the guest's screen; the counter has to be put back on it

# Closing the window mid-march is a quit too. The menu's "Save and quit" goes
# through _leave_world and saves; the title bar's X went through nothing.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null and _combat == null and not spectator:
		for ch in party.roster:
			CharacterSave.save(ch)
		_autosave()

func _leave_world() -> void:
	if spectator:
		return   # nothing of the host's gets written here; the guest leaves through _spectator_hud's button
	for ch in party.roster:
		CharacterSave.save(ch)
	_autosave()
	FactionOpinion.reset()
	Ladder.reset()   # process-global like opinion: the next new game starts as strangers
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
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null or _inventory_panel != null \
			or _story_panel != null or story_card != null or _menu_panel != null \
			or _spoils_panel != null:
		return
	_halted_on_arrival = false
	if world.clock.is_paused():
		world.clock.resume()
	else:
		world.clock.pause()
	_pause_btn.text = "Resume" if world.clock.is_paused() else "Pause"

func _cycle_speed() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null or _inventory_panel != null \
			or _story_panel != null or story_card != null or _menu_panel != null \
			or _spoils_panel != null:
		return
	world.clock.cycle_speed()
	_speed_btn.text = "%dx" % int(world.clock.speed)   # every WorldClock.SPEEDS entry is a whole number

func _set_speed(mult: float) -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null or _inventory_panel != null \
			or _story_panel != null or story_card != null or _menu_panel != null \
			or _spoils_panel != null:
		return
	world.clock.set_speed(mult)
	_speed_btn.text = "%dx" % int(world.clock.speed)

# --- the pause menu -------------------------------------------------------
#
# Esc on the map. The combat screen has had F1 settings since T29 and the title
# screen has its own footer, but the open world had neither: the only way to
# reach Settings mid-run was to walk back to the title and lose the map. It
# holds the clock the same way a market visit does — the world does not move
# behind an open menu — and every entry on it is something that was already
# reachable from the HUD bar, gathered behind the one key a player will try.

func _toggle_menu() -> void:
	if _menu_panel != null:
		_close_menu()
		return
	# Anything that has already taken the screen owns the moment; the menu is
	# the map's own. (_unhandled_key_input has closed the light panels first,
	# so reaching here means nothing else is up.)
	if _combat != null or not _visit.is_empty() or _site != null \
			or _event_card != null or _approach_card != null or story_card != null \
			or _party_overlay != null or _quest_panel != null or _inventory_panel != null or _story_panel != null \
			or _spoils_panel != null:
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_build_menu_panel()

func _close_menu() -> void:
	if _menu_panel != null:
		_menu_panel.queue_free()
		_menu_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _build_menu_panel() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Eat clicks: the map must not accept a march order through the menu.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_menu_panel = overlay

	var dim := ColorRect.new()
	dim.color = Color(Icons.COL_BG.r, Icons.COL_BG.g, Icons.COL_BG.b, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(centre)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(320, 0)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = "Head"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var when := Label.new()
	when.theme_type_variation = "Dim"
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	when.text = "%s — %s" % [WorldSave.day_clock(world.clock.elapsed, ", "),
		String(_region.get("label", "the road"))]
	box.add_child(when)

	var add := func(label: String, fn: Callable, quiet := false) -> void:
		var b := Button.new()
		b.text = label
		if quiet:
			b.theme_type_variation = "Quiet"
		b.pressed.connect(fn)
		box.add_child(b)

	add.call("Resume  [Esc]", _close_menu)
	# The settings overlay parents itself to this screen, not to the menu, so
	# it survives the menu closing underneath it — and its own Esc closes it
	# before this one's ever sees the key.
	add.call("Settings", func(): SettingsOverlay.toggle(self))
	add.call("Field manual", func(): ManualOverlay.toggle(self), true)
	add.call("Report a bug  [F3]", func(): report_bug(), true)
	add.call("Save and quit to the title screen", func():
		_close_menu()
		_leave_world(), true)

# --- party / profile / inventory ----------------------------------------
#
# Reuses T3's scenes/party/party.tscn as-is (per-character profile/inventory is
# already one click deeper from there) — same overlay shape campaign.gd's own
# _open_party() uses. Pauses the clock while open: browsing gear shouldn't cost
# world-time or let a hunt close in behind the menu.

const PARTY_SCENE := "res://scenes/party/party.tscn"

# Issue #27: `at_inn` is what unlocks benching and recruiting. The HUD button
# opens this out in open country, where a party does not reshuffle itself, so
# it opens locked; the inn's own entrance (_build_inn_page) opens it unlocked.
# Everything else on the screen — marching order, standing orders, the map
# figure, reading a character's gear and skills — works either way.
func _open_party(at_inn := false) -> void:
	if _combat != null or _party_overlay != null or (not at_inn and not _visit.is_empty()):
		return
	world.clock.pause()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_party_overlay = overlay
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	screen.roster_locked = not at_inn
	screen.locked_note = "Benching and recruiting happen at an inn — find one and ask at the counter."
	screen.exit_label = "←  Back to the inn" if at_inn else "←  Back to the map"
	screen.exit_requested.connect(_close_party)
	overlay.add_child(screen)

func _close_party() -> void:
	if _party_overlay != null:
		_party_overlay.queue_free()
		_party_overlay = null
	# A visit owns the clock for its whole duration (see _close_visit) — backing
	# out of the party screen at the inn's counter must not set the map running
	# underneath the still-open settlement panel.
	if _visit.is_empty():
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
	# Issue #28. The panel used to place itself by arithmetic — position at
	# half the screen minus half its own guessed size — which is right only
	# while the guess is. A CenterContainer centres whatever the panel actually
	# measures, so nothing hangs off an edge when the content is taller than the
	# 320 it was told to expect.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_quest_panel = centre
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(400, 320)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "Quest log"
	title.theme_type_variation = "Head"
	box.add_child(title)

	var scroll := _scroll_column(Vector2(380, 240))
	box.add_child(scroll)
	var rows: VBoxContainer = scroll.get_child(0)
	var live: Array = Quest.active(party)
	if live.is_empty():
		var none := Label.new()
		none.text = "Nothing taken on yet. Every settlement's notice board has work — walk in and read it."
		none.theme_type_variation = "Dim"
		rows.add_child(none)
	for q in live:
		var l := Label.new()
		l.text = Quest.describe(q, world.clock.elapsed)   # with its days left, if it has a deadline
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color",
			Icons.COL_GOLD if q["state"] == "complete" else Icons.COL_PARTY)
		rows.add_child(l)
	# Standing (core/ladder.gd): the company's name across the map, then its
	# rung with each people that has a settlement here — deeds never drift, so
	# this is the one page where a number is worth reading.
	_section(rows, "Standing")
	var t := Ladder.title_index()
	var renown := Label.new()
	renown.text = "%s — %d deeds%s" % [Ladder.title_cap(), Ladder.renown(),
		", %s at %d" % [String(Ladder.TITLES[t + 1]), int(Ladder.TITLE_AT[t + 1])] if t + 1 < Ladder.TITLES.size() else ""]
	renown.theme_type_variation = "Dim"
	rows.add_child(renown)
	var seen := {}
	for s in world.settlements:
		if WorldAI.is_monster(s.faction) or seen.has(s.faction):
			continue
		seen[s.faction] = true
		var r: int = Ladder.rung(s.faction)
		var l := Label.new()
		l.text = "%s: %s, %d deeds%s" % [String(s.faction).capitalize(), Ladder.rung_name(s.faction), Ladder.deeds(s.faction),
			", %s at %d" % [String(Ladder.RUNGS[r + 1]), int(Ladder.RUNG_AT[r + 1])] if r + 1 < Ladder.RUNGS.size() else ""]
		l.theme_type_variation = "Dim"
		rows.add_child(l)
	# Callings (core/callings.gd): each active hero's, once told — the same
	# line the party page carries, so the log is the one place both are read.
	var callings: Array = []
	for id in party.active:
		var line: String = Callings.describe(party, String(id))
		if line != "":
			callings.append("%s — %s" % [party.get_member(id).cname, line])
	if not callings.is_empty():
		_section(rows, "Callings")
		for line in callings:
			var l := Label.new()
			l.text = String(line)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.theme_type_variation = "Dim"
			rows.add_child(l)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_quests)
	box.add_child(close)

# --- the pack -------------------------------------------------------------
#
# The shared stash as the same tiles the market shows — art, rarity colour,
# the hover card, Shift to compare with what the party wears. View only: gear
# is equipped and potions drunk from a character's profile, which is where the
# body that wears or drinks it is.
func _toggle_inventory() -> void:
	if _inventory_panel != null:
		_close_inventory()
		return
	if _combat != null or not _visit.is_empty() or _party_overlay != null \
			or _quest_panel != null or _story_panel != null or story_card != null:
		return
	world.clock.pause()
	_build_inventory_panel()

func _close_inventory() -> void:
	if _inventory_panel != null:
		_inventory_panel.queue_free()
		_inventory_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _build_inventory_panel() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_inventory_panel = centre
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(520, 320)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "The pack"
	title.theme_type_variation = "Head"
	box.add_child(title)
	var purse := Label.new()
	purse.text = "%d ◉.  Equip and drink from a character's profile (P, then View)." % party.gold
	purse.theme_type_variation = "Dim"
	box.add_child(purse)

	var scroll := _scroll_column(Vector2(500, 240))
	box.add_child(scroll)
	var rows: VBoxContainer = scroll.get_child(0)
	if party.stash.is_empty():
		_note(rows, "Nothing in the pack. Loot from a fight, a stall's shelf and a job's pay all land here.")
	else:
		var grid := _item_grid(rows)
		for entry in party.stash:
			var id := String(entry["item_id"])
			var kd: Array = Icons.item_def(id)
			var known: bool = Party.is_identified(entry)
			var tip: String = ("Unidentified item (%s)" % Icons.rarity_of(id)) if not known \
				else Icons.item_tooltip(id, kd[1], kd[0])
			var qty := int(entry["quantity"])
			grid.add_child(Icons.item_tile(id, tip, "",
				Icons.ITEM_ART_PX, Icons.party_compare(kd[0], party, kd[1]) if known else "", qty))

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_inventory)
	box.add_child(close)

# A scrolling column that wraps instead of growing sideways. Issue #28: a
# ScrollContainer that allows horizontal scrolling hands its child the child's
# own MINIMUM width, and an autowrapping Label's minimum width is one pixel —
# so eight quests came out as eight 1px-wide, 570px-tall columns of stacked
# single characters, 4096px of scroll for text that fits in eight lines.
# Turning horizontal scrolling off is what makes the container stretch the
# column to its own width, which is the width the labels then wrap at. Every
# other list in the game (the campaign journal, the manual, the party screen,
# the mod browser) was already built this way; the four in this file were not.
func _scroll_column(min_size: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = min_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return scroll

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
			or _quest_panel != null or _inventory_panel != null or _story_panel != null or _menu_panel != null \
			or _spoils_panel != null \
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
			or _party_overlay != null or _quest_panel != null or _inventory_panel != null or story_card != null:
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
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_story_panel = centre
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(460, 380)
	centre.add_child(panel)
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

	var scroll := _scroll_column(Vector2(440, 290))
	box.add_child(scroll)
	var rows: VBoxContainer = scroll.get_child(0)
	var lines: Array = story.journal
	if lines.is_empty():
		lines = [story.story.synopsis]
	for line in lines:
		var l := Label.new()
		l.text = String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# #231: on the roads nobody closes on the company across the map — the road
	# sends what it sends (_check_routes), and the band it sent is met at once.
	if _combat != null or world.clock.is_paused() or RouteTravel.on(world):
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
		# fight/parley/ambush card the moment it closes: it came for you, and
		# the card is how you answer. A band that ISN'T hostile — a faction
		# patrol, most often — is never met by bumping into it. It used to be:
		# T9z gave it the friendly-only card and opened it on contact, so a
		# party marching past a patrol on the road was stopped to be asked
		# whether it wanted to stop. Now it is met only when the player clicks
		# it (_seek() below); standing next to one does nothing.
		var hostile: bool = WorldAI.is_hostile(q, p)
		var near: bool = q.position.distance_to(p.position) <= reach
		# A band already slipped past stays slipped until it is genuinely out of
		# range again, or the player would be asked the same question every frame
		# for as long as they stand next to it.
		if _slipped.has(q.id):
			if not near:
				_slipped.erase(q.id)
			continue
		if not hostile:
			continue   # met by clicking it, never by standing next to it
		if WorldAI.in_truce(q, world.clock.elapsed):
			continue   # met and parted without blood: they want nothing from you for a while
		# #229: locked in a fight with another band — it has its hands full, and
		# the party may stand and watch or walk on by. When the fight ends the
		# winner is an ordinary band again, and this loop meets it as one.
		if not world.clash_of(q).is_empty():
			continue
		if near:
			_meet(q, hostile)
			return

# The card, or — for a hostile band in the dark — whatever the watch makes of it.
func _meet(q, hostile: bool) -> void:
	# #229: a band locked in a fight with another (core/world_battle.gd) is met
	# by nobody until it is over. Its figure cannot be clicked (_band_at), but a
	# band the party was already following or chasing can fall into a clash
	# before the party reaches it — then the march stops at the edge of the
	# fight. The winner can be met like any band afterwards.
	var clash: Dictionary = world.clash_of(q)
	if not clash.is_empty():
		var other = WorldBattle.other_side(world, clash, q)
		_camp_msg.text = "%s are locked in a fight%s — nobody will stop to talk until it's over." % [
			EnemyNames.upper_first(EnemyNames.band_name(q, world)),
			"" if other == null else " with " + EnemyNames.band_name(other, world)]
		return
	if hostile and world.clock.is_night() and not _night_jump(q):
		return
	_open_approach(q, hostile)

# --- meeting a band on purpose ------------------------------------------
#
# A click on a band's figure is an order to go and meet it: the party marches at
# it, follows it if it moves, and the approach card opens when the two are in
# reach — at once if they already are. It is the only way to meet a band that
# is not hostile, and for a hostile one it overrides the two things that
# otherwise keep a card shut (a slip or parley's truce, and _slipped): asking
# for a meeting by name is asking. A click on the ground calls it off, and so
# does anything else that sends the party somewhere (_follow_meet() checks).

# The band whose figure is under screen point `sp`, or null. Only the bands the
# map is drawing (Party3D hides the rest under the fog), and the nearest when
# two figures overlap.
func _band_at(sp: Vector2):
	var p := world.player()
	var best = null
	var best_d := INF
	var h: float = Party3D.TARGET_HEIGHT * ISO_GAIN * _zoom
	for q in world.parties:
		if q == p or q.is_player or not world.band_seen(q.position):
			continue
		# #229: a band locked in a clash is not a thing to meet, so its figure is
		# not a thing to click — a click on it is a click on the ground there,
		# and the party marches up to watch.
		if not world.clashes.is_empty() and not world.clash_of(q).is_empty():
			continue
		var at := _pix(q.position)
		if _in_model_box(sp, at, h):
			var d := sp.distance_to(at)
			if d < best_d:
				best = q; best_d = d
	return best

func _seek(band) -> void:
	var p := world.player()
	if p == null or band == null or _combat != null or _approach_card != null:
		return
	_slipped.erase(band.id)
	if band.position.distance_to(p.position) <= ENCOUNTER_RADIUS:
		_met_sought(p, band)
		return
	_meet_id = band.id
	_meet_name = EnemyNames.band_name(band, world)
	_chase_next_at = world.clock.elapsed + WorldChase.INTERVAL
	_chase_misses = 0
	_aim_meet(p, band)
	_camp_msg.text = MEET_MSG % _meet_name

# The HUD line an errand puts up, and takes down again when it ends however it
# ends — met, called off, or lost in the fog — so it never outlives the march.
const MEET_MSG := "Marching to meet %s. Click the ground to call it off."
func _drop_meet() -> void:
	if _meet_id != "" and _camp_msg != null and _camp_msg.text == MEET_MSG % _meet_name:
		_camp_msg.text = ""
	_meet_id = ""

func _aim_meet(p, band) -> void:
	world.set_goal(p, band.position)
	_meet_aim = _destination(p)

# Where the party is ultimately going: the last corner of a routed march, or
# the goal of a straight one.
static func _destination(p) -> Vector2:
	return p.route[-1] if not p.route.is_empty() else p.goal

# One frame of the march: drop the order if the band is gone, out of sight, or
# the party has been sent somewhere else; meet it if it is in reach; roll to run
# it down if it is getting away (_chase); otherwise re-aim at it once it has
# drifted far enough to matter (set_goal routes round water, which is not a
# thing to do every frame).
func _follow_meet(p, dt: float) -> void:
	if _meet_id == "" or _combat != null or _approach_card != null or world.clock.is_paused():
		return
	var band = null
	for q in world.parties:
		if q.id == _meet_id:
			band = q
			break
	if band == null or not world.band_seen(band.position):
		var who := _meet_name
		_drop_meet()
		_camp_msg.text = "Lost sight of %s." % who
		return
	if _destination(p) != _meet_aim:
		_drop_meet()
		return
	if band.position.distance_to(p.position) <= _trigger(dt):
		_met_sought(p, band)
		return
	if _chase(p, band):
		return
	if band.position.distance_to(_meet_aim) > ENCOUNTER_RADIUS * 0.5:
		_aim_meet(p, band)

# A band as fast as the party or faster is never caught by following it, so
# while it is still in sight the party gets a roll every WorldChase.INTERVAL to
# run it down. True when the chase ended this frame, caught or lost.
func _chase(p, band) -> bool:
	if not WorldChase.outpaced(band.speed, p.speed) \
			or band.position.distance_to(p.position) > world.sight_radius():
		return false
	if world.clock.elapsed < _chase_next_at:
		return false
	_chase_next_at = world.clock.elapsed + WorldChase.INTERVAL
	var r: Dictionary = WorldChase.check(party, band.speed, p.speed,
		RNG.new(maxi(1, absi(hash("chase|%s|%d" % [band.id, int(world.clock.elapsed)])))))
	if r.is_empty():
		return false
	var who: String = EnemyNames.band_name(band, world)
	var tally := "%s %d+%d vs DC %d" % [String(r["skill"]).capitalize(), r["nat"], r["bonus"], r["dc"]]
	if r["ok"]:
		var caught := "runs %s down" if WorldAI.is_hostile(band, p) else "catches up with %s"
		_met_sought(p, band, r, "%s %s (%s)." % [r["cname"], caught % who, tally])
		return true
	_chase_misses += 1
	if _chase_misses >= WorldChase.MAX_TRIES:
		_drop_meet()
		_map_roll(r, _camp_msg, "%s cannot close the gap (%s). %s get away." % [r["cname"], tally, EnemyNames.upper_first(who)])
		return true
	_map_roll(r, _camp_msg, "%s cannot close the gap yet (%s). %s keep their lead." % [r["cname"], tally, EnemyNames.upper_first(who)])
	return false

# The party got where it was going, so it stops there the way #70 stops any
# arrival — a meeting that ends without a fight hands back a halted map
# (_on_approach_reported), not one that runs on with nobody giving orders.
# `roll` is the chase roll that caught the band, if one did: the card waits
# for its die to land, with the map held still under it.
func _met_sought(p, band, roll := {}, text := "") -> void:
	_drop_meet()
	world.set_goal(p, p.position)
	_halted_on_arrival = true
	_was_travelling = false
	var hostile: bool = WorldAI.is_hostile(band, p)
	if roll.is_empty():
		_meet(band, hostile)
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_map_roll(roll, _camp_msg, text, "", func(): _meet(band, hostile))

# #85: in the dark a hostile band is on the party before anyone can choose how
# to meet it — unless someone on watch hears them coming. The same check and the
# same two outcomes a camp ambush has (core/world_camp.gd): heard, and the card
# is offered as by day; missed, and they take the first round. Returns true when
# the card should still open.
func _night_jump(foe) -> bool:
	var rng := RNG.new(maxi(1, absi(hash("night|%s|%d" % [foe.id, int(world.clock.elapsed)]))))
	var watch: Dictionary = WorldCamp.watch_check(party, rng)
	if watch["ok"]:
		return true
	var skill_name: String = String(watch.get("skill", "")).capitalize()
	var who: String = watch.get("char_id", "")
	var them := EnemyNames.upper_first(EnemyNames.band_name(foe, world))
	_camp_msg.text = ("%s does not catch it in the dark (%s %d+%d vs DC %d). %s are on the company before anyone can draw." % [
		watch.get("cname", ""), skill_name, watch["nat"], watch["bonus"], watch["dc"], them]) if who != "" \
		else "Nobody is watching the dark. %s are on the company before anyone can draw." % them
	var rolled: Dictionary = _watch_roll(watch)
	_camp_card("jumped", "Jumped in the dark", "bad",
		"%s does not catch it in the dark. %s are on the company before anyone can draw." % [watch.get("cname", ""), them] if not rolled.is_empty() else _camp_msg.text,
		func(): _on_event_ack(); await _launch_combat(foe, false, true, "dark"), "", rolled)
	return false

# The roster the encountered party fights with. Scaler takes a *theme*, not a
# faction, so: THEME_FACTION reversed gives a matching board for the factions
# that have one; for the rest (soldier/orc/cultist/...) there is no theme, and
# _faction_order's other documented route — FACTIONS[seed % size] — is snapped
# onto this faction instead. Seeded off the party id, so meeting the same band
# twice is the same band.
#
# O-biome: and the GROUND is read here too, which is the seam the biome layer
# was built for and shipped without. It does two things, both of them narrow.
# It picks the board for a fight that had none of its own — that is what killed
# DEFAULT_THEME, which used to draw a moor, a marsh and open downs all as the
# same wood. And it names one habitat out of the bestiary's vocabulary, which
# filters the roster to what lives on that ground: the marsh is the one that
# pays, because its 18 aquatic beasts were unreachable while forest-clearing
# was the only board that ever drew beasts. The ring (core/regions.gd) still
# owns how DANGEROUS the country is; these two axes stay orthogonal.
func encounter_spec(foe, difficulty := "") -> Dictionary:
	var biome: String = world.biome_at(foe.position)
	var habitat: String = String(Scaler.BIOME_HABITAT.get(biome, ""))
	# The map's peoples are not roster factions. data/bestiary.json has no
	# human/elf/dwarf — `soldier` is its settled power — so pin_faction() found
	# no index for "human", handed the seed straight back, and a town patrol
	# fielded FACTIONS[seed % 15]: whatever that landed on, reproducibly,
	# because the seed is the band's own id. A caravan inherits its home town's
	# faction and came through the same hole.
	var faction: String = Scaler.CIVILIZED_ROSTER if WorldAI.CIVILIZED.has(foe.faction) \
		else String(foe.faction)
	var theme := ""
	for t in Scaler.THEME_FACTION:
		if String(Scaler.THEME_FACTION[t]) == faction:
			theme = String(t)
			break
	var seed_v: int = absi(hash(foe.id))
	if theme == "":
		seed_v = Scaler.pin_faction(seed_v, faction)
	var threat: Dictionary = WorldThreat.assess(party, world)   # world: the road home's clock
	var band_id := String(Regions.at(world, foe.position)["id"])
	# D6: the two knobs compose, and they answer different questions. The band
	# says how dangerous this country is (1.0 while the party is inside its level
	# range, which is the common case); the party's condition still thins whatever
	# the country sends, in the same proportion it always did. The band's id rides
	# along too: this country's casters, and the Far Deeps' big one
	# (Scaler.BIG_CHANCE), which changes what the fight is made of, not its price.
	var spec: Dictionary = Scaler.roster_for(
		party.party_characters(), difficulty if difficulty != "" else String(threat["difficulty"]),
		{}, theme, seed_v,
		float(threat["power_scale"]) * Regions.power_scale(world, foe.position, party), [], habitat,
		EnemyCasters.cap_for_band(band_id), band_id)
	spec["theme"] = theme if theme != "" else String(Scaler.BIOME_BOARD.get(biome, DEFAULT_THEME))
	# What this band is worth robbing for. A caravan is carrying its cargo; a
	# patrol, a warband and a beast pack are carrying what they stand up in.
	# ponytail: a taste number, not a measured one — gold is not in the win-rate
	# band tests/test_scaler.gd sweeps, so there is nothing here to sweep. Re-cut
	# it against the economy if a caravan ever becomes the only thing worth
	# hunting, which at 2x it should not be.
	var purse: float = float(PURSE.get(String(foe.ai.get("kind", "")), 1.0))
	if purse != 1.0:
		spec["purse"] = purse
	# The board a fight is drawn on is not always the roster's own kin, and the
	# stamp above is lossy on purpose: a faction with no board of its own
	# (orc/gnoll/kobold/...) fights on DEFAULT_THEME while `theme` stays "" so
	# that _faction_order takes the faction off the seed instead. Anything that
	# has to build a SECOND roster for this same fight — the gate hold's waves —
	# needs that pair back, or it reads "forest-clearing" off the spec and sends
	# beasts to an orc siege. core/site.gd never had this one — both are still
	# in scope where it builds its waves — but it has the sibling, and the
	# expansion plan's "Two the road got wrong" entry says why that one waits.
	# Out here the spec is the only thing that crosses between the two rosters,
	# so the pair rides along under names of its own.
	# NOT `spec["seed"]`: that is core/encounter.gd's board seed and
	# scenes/main.gd overwrites it with the fight's own seed before the board
	# is built, so a wave roster hung on it would be drawn off whatever the
	# clock said.
	spec["roster_theme"] = theme
	spec["roster_seed"] = seed_v
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
# #229: NOT the rate a band-vs-band clash is told at — that is
# WorldBattle.MINUTES_PER_ROUND, and its comment says why the two differ.
const MINUTES_PER_ROUND := 60.0

func _run_combat(spec: Dictionary, difficulty: String,
		scouted_ahead := false, forced_ambush := false, site := "road") -> Dictionary:
	world.clock.pause()
	Sound.set_combat(true)    # T27: campaign.gd did this for run fights; map fights were silent
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	spec = spec.duplicate()
	spec["night"] = world.clock.is_night()   # #85: fought by torchlight (core/combat.gd lit())
	# #176: where this is, for the heroes' personality traits (core/traits.gd):
	# the ground under the company, the country it is in, and what kind of place.
	var here: Vector2 = world.player().position if world.player() != null else Vector2.ZERO
	spec["where"] = {"biome": world.biome_at(here), "band": Regions.band_of(world, here), "site": site}
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
	_earn_from_fight(result, difficulty, site)
	# A fight costs daylight: an hour a round, so a long brawl eats the afternoon
	# and a two-round ambush barely dents it. The clock is paused through the
	# fight itself, so this is the whole bill.
	world.clock.elapsed += int(result.get("rounds", 0)) * MINUTES_PER_ROUND
	if _combat_overlay != null:
		_combat_overlay.queue_free()
		_combat_overlay = null
	return result


# The objective a road fight carries, by precedence: jumped in the dark (camp,
# night road) or seen mid-slip is a breakout whatever else is going on; a band
# a job names is a hunt; a delivery on the road makes every fight an escort.
# {} is today's fight.
func _road_objective(foe, jumped: String) -> Dictionary:
	if jumped != "":
		return Objectives.make("breakout")
	# Raiders on their way to a town, or standing at its gate: the town is
	# behind you and more are coming. Anywhere else on the road they are a
	# band like any other (or a hunt, if the job is taken).
	if Raids.turnable(foe):
		var target = Raids.settlement_of(world, String(foe.ai.get("target", "")))
		if target != null and foe.position.distance_to(target.position) <= Visit.BATTLE_RADIUS:
			return Objectives.make("hold")
	for q in party.quests:
		if q["state"] == "active" and q["kind"] == "hunt_party" and String(q.get("target_party_id", "")) == foe.id:
			return Objectives.make("hunt")
	for q in party.quests:
		if q["state"] == "active" and q["kind"] == "deliver_goods":
			return Objectives.make("escort")
	return {}

# Hold the line at a town's gate: the waves the objective is built on, drawn
# the way a site's gate room draws them (core/site.gd), at the same power the
# band itself was rostered at (encounter_spec's own product). Without them
# combat.gd's hold is done at round HOLD_ROUNDS + 1 whatever stands.
#
# Off `roster_theme`/`roster_seed`, never the stamped `theme`: those are the
# pair the band's own roster was drawn with, so the waves are the raiders' own
# kin. Read off `theme` this used to send beasts (forest-clearing's faction) at
# any raid whose faction has no board of its own.
func _hold_waves(foe, spec: Dictionary, threat: Dictionary) -> Array:
	return Objectives.waves_for(party.party_characters(), String(spec.get("roster_theme", "")),
		int(spec.get("roster_seed", absi(hash(foe.id)))),
		float(threat["power_scale"]) * Regions.power_scale(world, foe.position, party), [], foe.faction)

# `jumped` is "" for no breakout, "seen" for a slip caught mid-flight (the
# threat roster — the approach card priced it that way), "dark" for jumped in
# the dark at camp or on the night road (the hard roster: not a fight you are
# meant to win by standing). `difficulty` names the roster outright when the
# caller knows it — the inn's brawl (_show_complication), easy, is the only
# one — and a fight named that way is not the road's: no objective rides on
# it (a delivery's carter is not in the common room) and winning it is no
# service to the town (no opinion, no deed).
func _launch_combat(foe, scouted_ahead := false, forced_ambush := false, jumped := "", difficulty := "") -> Dictionary:
	if party.scouted_next:   # Potion of Clairvoyance, spent on this fight
		scouted_ahead = true
		party.scouted_next = false
	var threat: Dictionary = WorldThreat.assess(party, world)   # world: the road home's clock
	var named: bool = difficulty != ""
	var objective: Dictionary = {} if named else _road_objective(foe, jumped)
	var kind := String(objective.get("kind", ""))
	var spec: Dictionary = encounter_spec(foe, "hard" if jumped == "dark" else difficulty)
	# The design audit §3.5: out here a hero may walk off the board's edge
	# (core/combat.gd). A site's room, the pit and the linear run do not set it.
	spec["withdraw"] = true
	if kind == "hold":
		objective["waves"] = _hold_waves(foe, spec, threat)
	if kind != "":
		spec["objective"] = objective
	var raid_target = Raids.settlement_of(world, String(foe.ai.get("target", ""))) if Raids.turnable(foe) else null
	var result: Dictionary = await _run_combat(spec,
		String(threat["difficulty"]), scouted_ahead, forced_ambush, "camp" if jumped == "dark" else "road")
	if result.is_empty():
		return {}
	var obj: Dictionary = result.get("objective", {})
	var got_away: bool = String(obj.get("kind", "")) == "hunt" and not bool(obj.get("done", false))
	var beat_band := false
	if String(result.get("outcome", "")) == "Victory":
		_bank(result)
		if got_away:
			# The band is beaten but its chief is not: it stays on the map, breaks
			# off a day's march, and the job that named it stays open.
			_slipped[foe.id] = true
			WorldAI.truce(foe, world.player(), world.clock.elapsed)
			_quest_news.append("Their leader got away — the job is still open.")
		else:
			if not RouteTravel.on(world):
				WorldAI.fell(world, foe)  # #142: it comes back in two days (not on the roads: the road sends the next)
			world.parties.erase(foe)      # beaten; O5 will do the same for NPC-vs-NPC
			# T91: a no-op for the settlement-guard/lair-raid stand-ins below (their
			# synthetic ids never match a live hunt_party quest's target), correct
			# for an actual hostile roaming party from _check_encounter.
			Quest.record_party_defeated(party, foe.id)
			beat_band = true   # the calling waits for _apply_deaths, below
			if raid_target != null:
				# A raid turned before it landed: TURNED_FOR (two bands' worth) on
				# top of the FOUGHT_FOR every monster band already earns at that
				# town below, so a turned raid is worth three bands put down there.
				# raids.gd resets the lair's clock on its next poll when it finds
				# the band gone.
				FactionOpinion.credit_fight(world, raid_target.position, Raids.TURNED_FOR, foe.faction)
				Ach.bump("raids_turned")
				_quest_news.append("The raid on %s is turned." % raid_target.sname)
				Sound.play_sting("music_deed")
		# O7 raise/lower event: putting down a monster band is a favour to whoever
		# lives near the bodies; putting down a faction's own band is not. A
		# brawl at the inn is neither.
		if not named and WorldAI.is_monster(foe.faction):
			FactionOpinion.credit_fight(world, foe.position, FactionOpinion.FOUGHT_FOR, foe.faction)
			Grudges.add(foe.faction, Grudges.BAND)   # #231: and its own people remember
		elif not named:
			FactionOpinion.lower(foe.faction, FactionOpinion.KILLED_THEIRS)
	elif String(result.get("outcome", "")) == Combat.WITHDRAWN:
		# The design audit §3.5: every hero still standing walked off the board's
		# edge (core/combat.gd). Not a win — no XP, no loot, no quest progress,
		# nothing banked — and not a defeat: no gold tax, no lost day, no wound
		# roll, nobody moved to a town. The band is still on the map where the
		# fight was; it is marked slipped and given a truce, the way a band that
		# was slipped past is, so the card does not open again this frame. Anyone
		# left lying on the field when the last one walked off is dead, and that
		# is applied like any fight's deaths.
		_apply_deaths(result)
		_slipped[foe.id] = true
		WorldAI.truce(foe, world.player(), world.clock.elapsed)
		_lair_msg.text = Combat.withdrawal_line(result.get("deaths", []).map(
			func(id): return party.get_member(String(id)).cname if party.get_member(String(id)) != null else String(id)))
	else:
		# Deaths before the retreat, the same order a site wipe uses: the dead
		# are dead when revive_downed runs, so it cannot stand them up.
		_apply_deaths(result)
		_retreat(result.get("deaths", []), result.get("downed", []))
		# The band that beat them is still where the fight was. Left un-slipped
		# it would ask "fight/parley/ambush?" again the frame the map came back
		# whenever the nearest settlement was inside its trigger radius — the
		# same card the beaten party had just answered. And since the company now
		# lies a day where it fell (core/defeat.gd), the band may have walked off
		# and back by the morning, which clears a slip: the victors' truce keeps
		# them from coming straight back for the beaten, the same truce a band
		# that was slipped past gives.
		_slipped[foe.id] = true
		WorldAI.truce(foe, world.player(), world.clock.elapsed)
		if not party.finished.is_empty():
			_end_company()   # nobody is left: the run ends here, not on the map
			return result
	# #231: a band the road sent was only ever this meeting; win, withdraw or
	# lose, it is gone with it.
	_route_forget(foe)
	# The carter dead, or the party beaten with the crate on the road: the
	# delivery is lost either way, and the board can post the run again.
	if String(obj.get("kind", "")) == "escort" and not bool(obj.get("done", false)):
		for title in Quest.fail_deliveries(party):
			_quest_news.append("%s — the delivery is lost with the carter." % title)
	_apply_deaths(result)   # a second call on a defeat changes nothing: already dead, already benched
	# After the deaths, not before them: core/callings.gd already refuses to
	# complete a dead hero's past ("the bond and the line are theirs to have"),
	# but nobody in this fight was dead yet when the check ran up in the victory
	# branch, so the one hero who fell putting their own band down was paid
	# anyway. The same reorder hands the bond to a living leader — bench() has
	# taken the fallen out of `active` by now, so _leader() and Callings._closest
	# both read the party that walked away. Still ahead of the autosave, so the
	# save the fight makes carries the completion (tests/test_world_callings.gd).
	if beat_band:
		_calling_check("band_beaten", foe.id, _leader())   # shown after the spoils page
	world.clock.resume()
	_autosave()   # O13 autosave: a fight is the biggest thing that
	                               # happens to a run — never re-fight it after a crash
	_show_spoils(result)
	return result

# O9 item 2: a won fight has to actually pay, or the run is a dead end. The rule
# is core/campaign.gd's bank_win — XP split, the purse with Greedy's cut
# (rewriting result["gold"] to what was banked, for the spoils page), the loot
# into the stash. What stays here is this screen's: the delve's running total,
# the line that says what was taken, and the quest news the spoils page shows.
func _bank(result: Dictionary) -> void:
	Campaign.bank_win(party, result)
	var taken: Array = result.get("loot", [])
	# Issue #30: a delve is several fights on one set of resources, so what it
	# paid is a running total, not the last room's.
	if not _delve_haul.is_empty():
		_delve_haul["xp"] = int(_delve_haul.get("xp", 0)) + int(result.get("xp", 0))
		(_delve_haul["loot"] as Array).append_array(taken)
		_delve_haul["fights"] = int(_delve_haul.get("fights", 0)) + 1
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
	_quest_news = Quest.record_kills(party, result.get("kills", []),
		RNG.new(maxi(1, int(world.clock.elapsed) + 1)))
	if not _delve_haul.is_empty():
		(_delve_haul["quests"] as Array).append_array(_quest_news)

# --- issue #30: the spoils page -------------------------------------------
#
# A won fight on the map used to pay in silence. The combat screen writes its
# own after-action lines — "+400 XP, +50 ◉", "Taken from the dead: a
# handaxe" — but out here the screen is torn down the frame `result` is filled,
# so nobody ever read them; all that survived was one line on the HUD's lair
# label, which the next frame's button text could overwrite. The linear
# campaign never had this problem: it holds the fight screen up behind a "Back
# to the road" button and the player reads the log. This is the map's version
# of that button, as a page of its own rather than a lingering board, since the
# map has a lair delve to summarise as well as a single fight.
#
# A delve is several fights on one set of resources (core/site.gd), so its
# page totals the whole descent instead of firing per room.

func _show_spoils(result: Dictionary) -> void:
	if result.is_empty() or _spoils_panel != null:
		return
	var won: bool = String(result.get("outcome", "")) == "Victory"
	var rows: Array = []
	if won:
		# "tally": #157 — the one row worth counting up rather than simply
		# arriving, because it is the number the fight was fought for.
		# #157's reference: the company that fought, each with the HP they have
		# left and how far to the next level; then who fell to them, with what
		# each was worth; then the tally; then the haul as tiles, not a list.
		rows.append(_spoils_company())
		var fallen := _spoils_fallen(result)
		if fallen != null:
			rows.append(fallen)
		rows.append(["+%d XP,  +%d ◉" % [int(result.get("xp", 0)), int(result.get("gold", 0))],
			Icons.COL_GOLD, "tally"])
		var counts := {}   # a count on a repeat — "×2", not the same tile twice
		for item in result.get("loot", []):
			counts[String(item)] = int(counts.get(String(item), 0)) + 1
		if counts.is_empty():
			rows.append(["Nothing worth carrying off the bodies.", Icons.COL_MUTED])
		else:
			var haul := HFlowContainer.new()   # wraps when the haul is long
			haul.add_theme_constant_override("h_separation", 6)
			haul.custom_minimum_size.y = Icons.ITEM_ART_PX + 30
			for item in counts:
				var kd := Icons.item_def(item)
				# A tile with no art is already its name; captioning it says it twice.
				var tile := Icons.item_tile(item, Icons.item_tooltip(item, kd[1], kd[0]),
					Campaign.item_name(item) if Icons.item_art(item) != null else "",
					Icons.ITEM_ART_PX, "", counts[item])
				tile.custom_minimum_size.x = 118   # room for "Potion of Healing" under the art
				tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				haul.add_child(tile)
			rows.append(haul)
	var obj: Dictionary = result.get("objective", {})
	if String(obj.get("kind", "")) != "":
		rows.append([Objectives.spoils_line(obj), Icons.COL_GOLD if bool(obj.get("done", false)) else Icons.COL_FOE])
	for line in _quest_news:
		rows.append([String(line), Icons.COL_ACCENT])
	_quest_news = []
	_trait_rows(rows)
	for id in result.get("deaths", []):
		var fallen = party.get_member(id)
		rows.append(["%s did not get up." % (fallen.cname if fallen != null else id), Icons.COL_FOE])
	# The retreat's own accounting (gold tax, where they woke up) is already
	# written; a lost fight's page is that line, not an empty spoils list.
	if not won and _lair_msg != null and _lair_msg.text != "":
		rows.append([_lair_msg.text, Icons.COL_FOE])
	# A withdrawal (the audit's §3.5) is its own heading: not a win, and not the
	# defeat page either, since nothing a defeat costs was paid.
	var withdrew: bool = String(result.get("outcome", "")) == Combat.WITHDRAWN
	_build_spoils_panel("Victory" if won else ("Withdrawn" if withdrew else "Defeat"), rows)

# The company on the after-action page: a card each for the ones who marched —
# glyph, name, the HP they walked out with and how far to the next level.
func _spoils_company() -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.custom_minimum_size.y = 62
	for id in party.active:
		var ch = party.get_member(id)
		if ch == null:
			continue
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		card.custom_minimum_size.x = 118
		var name := Label.new()
		name.text = "%s %s" % [Icons.class_glyph(ch.class_id()), ch.cname]
		name.clip_text = true
		name.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		name.add_theme_color_override("font_color", Icons.COL_FOE if ch.dead else Icons.COL_HEAD)
		card.add_child(name)
		var max_hp: int = maxi(1, int(ch.sheet().max_hp))
		var hp: int = 0 if ch.dead else (max_hp if ch.hp_current < 0 else ch.hp_current)
		card.add_child(_spoils_bar(hp, max_hp, Icons.COL_FOE, "%d/%d" % [hp, max_hp]))
		var need: int = Leveling.xp_for_level(ch.level() + 1)
		card.add_child(_spoils_bar(int(ch.xp), need, Icons.COL_GOLD, "%d xp" % int(ch.xp)))
		strip.add_child(card)
	return strip

func _spoils_bar(have: int, goal: int, ink: Color, caption: String) -> Control:
	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = have
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.tooltip_text = caption
	bar.add_theme_stylebox_override("background", Icons.box(Icons.COL_INK, Icons.COL_EDGE, 2, 0, 0))
	bar.add_theme_stylebox_override("fill", Icons.box(ink, Color(0, 0, 0, 0), 2, 0, 0))
	var l := Label.new()
	l.text = caption
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL - 2)
	l.add_theme_color_override("font_color", Icons.COL_HEAD)
	bar.add_child(l)
	return bar

# Who fell to them — one chip per kind, a count on a repeat, what the
# bestiary says each was worth, and who struck the blow (audit 2.2: the
# fight's credit knew, and the page never said). Null when nothing died (a
# rout, an escort). The lines are core/service.gd's kill_lines.
func _spoils_fallen(result: Dictionary) -> Control:
	var lines: Array = Service.kill_lines(result, party)
	if lines.is_empty():
		return null
	var strip := HFlowContainer.new()   # wraps: a credited chip is two lines and wider
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 4)
	strip.alignment = FlowContainer.ALIGNMENT_CENTER
	strip.custom_minimum_size.y = 40
	for k in lines:
		var chip := Label.new()
		chip.text = "%s%s  %d xp" % [String(k["name"]), " ×%d" % int(k["count"]) if int(k["count"]) > 1 else "", int(k["xp"])]
		if String(k["by"]) != "":
			chip.text += "\nstruck by %s" % String(k["by"])
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		chip.add_theme_color_override("font_color", Icons.COL_FOE)
		chip.add_theme_stylebox_override("normal", Icons.box(Icons.COL_INK, Icons.COL_FOE, 3, 8, 3))
		strip.add_child(chip)
	return strip

# What the whole descent paid, once the party is back out on the map.
func _show_delve_spoils(l, cleared: bool) -> void:
	if _delve_haul.is_empty():
		return
	var haul: Dictionary = _delve_haul
	_delve_haul = {}
	var rows: Array = []
	rows.append(["%d of %d rooms behind them" % [int(l.depth_cleared), Site.depth_for(l)],
		Icons.COL_TEXT])
	rows.append(["+%d XP over %d fight%s%s" % [int(haul.get("xp", 0)), int(haul.get("fights", 0)),
		"" if int(haul.get("fights", 0)) == 1 else "s",
		"" if not haul.has("cleared_xp") else ", %d of it for reaching the bottom" % int(haul["cleared_xp"])],
		Icons.COL_GOLD])
	rows.append(["+%d ◉" % maxi(0, party.gold - int(haul.get("gold0", party.gold))),
		Icons.COL_GOLD, "tally"])
	var loot: Array = haul.get("loot", [])
	if loot.is_empty():
		rows.append(["Nothing came out of there but coin.", Icons.COL_MUTED])
	else:
		var names: Array = []
		for item in loot:
			names.append(Campaign.item_name(String(item)))
		rows.append(["Carried out: %s" % ", ".join(names), Icons.COL_TEXT])
	for line in haul.get("quests", []):
		rows.append([String(line), Icons.COL_ACCENT])
	_trait_rows(rows)   # every room's, gathered — the moments themselves come after this page
	_build_spoils_panel(
		"%s is cleared out" % l.sname if cleared else "Out of %s" % l.sname, rows)

# #157: the page itself is scenes/world/spoils.gd now — the same rows, in the
# same order, dealt out instead of printed all at once. Everything that is
# about the MAP rather than about the page stays here: stopping the clock,
# and agreeing with the HUD button about it.
func _build_spoils_panel(heading: String, rows: Array) -> void:
	world.clock.pause()
	_pause_btn.text = "Resume"
	var page = Spoils.new()
	add_child(page)
	_spoils_panel = page
	page.build(heading,
		rows,
		Icons.scene_art({"Victory": "summary-victory", "Defeat": "summary-defeat"}.get(heading, ""), null),
		Tips.pick(),
		_close_spoils)

func _close_spoils() -> void:
	if _spoils_panel != null:
		_spoils_panel.queue_free()
		_spoils_panel = null
	_halt()   # #98: wait for an order

# --- issue #118: somebody can level up ----------------------------------
#
# A level used to arrive as one chime (campaign.gd's split_xp) and a number on
# a screen two clicks away, so parties walked around owing themselves levels
# for hours. It gets the after-action page's own treatment instead: the map
# stops, a gilt panel says who is ready, and its button is the trip to the
# party screen where the sheets are.
#
# WHERE IT CANNOT APPEAR: over a fight. This runs off the map's own _process,
# which does not tick while combat owns the screen, and _overlay_up() covers
# the spoils page, a road event, a delve and the rest — so the announcement
# waits for open country with nothing else on it, which is exactly where
# somebody is free to go and spend the level.
#
# ONCE PER LEVEL, PER CHARACTER: _levelup_told remembers who was told and at
# what level, so backing out with "Not now" does not put the panel straight
# back up, and the next level says so again.
# Co-op: a hero levels up on the screen of whoever plays them, so each peer
# is only told about its own.
func _ready_to_level() -> Array:
	var out: Array = []
	for ch in party.roster:
		if not ch.dead and Leveling.can_level_up(ch) and Coop.mine(party, ch.id):
			out.append(ch)
	return out

func _check_level_ready() -> void:
	if _combat != null or _overlay_up() or not _visit.is_empty():
		return
	var who: Array = _ready_to_level().filter(
		func(ch): return int(_levelup_told.get(ch.id, -1)) != ch.level())
	if who.is_empty():
		return
	for ch in who:
		_levelup_told[ch.id] = ch.level()
	_build_levelup_panel(who)

func _build_levelup_panel(who: Array) -> void:
	world.clock.pause()
	_pause_btn.text = "Resume"
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_levelup_panel = overlay

	var dim := ColorRect.new()
	dim.color = Color(Icons.COL_BG.r, Icons.COL_BG.g, Icons.COL_BG.b, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(centre)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(480, 0)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Level up" if who.size() == 1 else "Level up  ×%d" % who.size()
	title.theme_type_variation = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	box.add_child(title)

	for ch in who:
		var l := Label.new()
		l.text = "%s  —  %s %d  →  %d" % [ch.cname,
			Icons.class_glyph(ch.class_id()), ch.level(), ch.level() + 1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.theme_type_variation = "Head"
		box.add_child(l)

	var note := Label.new()
	note.text = "There is a level waiting on the party screen — pick it up there, per character." if not spectator \
		else "Your merc, your choices — take the level here; your host's sheet follows."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Icons.COL_MUTED)
	box.add_child(note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var go := Button.new()
	go.text = "Open the party  [Enter]" if not spectator else "Level up %s  [Enter]" % who[0].cname
	go.theme_type_variation = "Primary"
	go.pressed.connect(func():
		_close_levelup()
		if spectator:
			_guest_levelup(who[0])
		else:
			_open_party())
	row.add_child(go)
	var later := Button.new()
	later.text = "Not now  [Esc]"
	later.theme_type_variation = "Quiet"
	later.pressed.connect(_close_levelup)
	row.add_child(later)
	go.grab_focus()

func _close_levelup() -> void:
	if _levelup_panel != null:
		_levelup_panel.queue_free()
		_levelup_panel = null

const LEVELUP_SCENE := "res://scenes/creator/levelup.tscn"
var _levelup_overlay = null   # the guest's level-up screen, while one is up

# The guest takes a level on their mirrored copy of the hero — the same
# screen the profile opens — and every step it makes goes to the host as one
# message on Confirm. Nothing is saved here; the host's save comes back as the
# next full map.
func _guest_levelup(ch) -> void:
	var overlay = load(LEVELUP_SCENE).instantiate()
	var steps: Array = []
	overlay.persist = false
	overlay.on_step = func(step: Dictionary): steps.append(step)
	add_child(overlay)
	_levelup_overlay = overlay
	overlay.set_character(ch)
	overlay.finished.connect(func(_leveled):
		overlay.queue_free()
		_levelup_overlay = null
		if not steps.is_empty() and Coop.link != null:
			Coop.link.send(Coop.levelup(ch.id, steps)))

# A death is a death regardless of who won — encounter.gd always fills
# `deaths`, campaign.gd's linear run already benches+marks them the same way;
# the open world just never read the field. Applied once here for both
# outcomes rather than duplicated per-branch.
# Since the design audit (§2.1) it goes through core/fallen.gd, the one door a
# death comes through: marked and benched as before, and now counted (the
# "deaths" achievement), written on the roll of the fallen, grieved by whoever
# was close to them (their moments queued like any earned trait's, their lines
# on this fight's spoils page) and felt in the relations web. A second call on
# the same fight finds everyone already dead and changes nothing. `where` is
# the place for the roll; the road's is worked out here.
func _apply_deaths(result: Dictionary, where := "") -> void:
	if where == "":
		where = ("in %s" % _site.lair.sname) if _site != null else _road_where()
	var r: Dictionary = Fallen.apply(party, result, {"now": world.clock.elapsed, "where": where})
	_trait_news.append_array(r["lines"])
	_queue_moments(r["moments"])

# "on the road near Riverhold": the nearest settlement to where the company
# stands, for the roll of the fallen.
func _road_where() -> String:
	var p := world.player()
	if p == null or world.settlements.is_empty():
		return ""
	var near = world.settlements[0]
	for s in world.settlements:
		if p.position.distance_squared_to(s.position) < p.position.distance_squared_to(near.position):
			near = s
	return "on the road near %s" % near.sname

# Real stakes for a lost fight, but not a death spiral. What a loss costs: no
# XP/loot/quest progress from the fight, lost time, the gold the victors take
# off whoever is still breathing — and the dead. Since the design audit
# (docs/audit-game-design.md §1.2, 2026-09-24) only the DOWNED come to here
# (Party.revive_downed); the dead stay dead and benched, and come back only the
# paid way, a healer's raise or Revivify. It used to stand the whole roster up
# for free, the benched dead of earlier fights included, which made conceding a
# fight the cheapest resurrection in the game. Every caller applies the
# fight's deaths FIRST (_apply_deaths), so this fight's dead are already dead
# when it runs — the road and a site wipe used to do it in opposite orders.
# `fell` is the fight's own `deaths`, for the line only. Returns the line, which
# is also put on the map.
#
# The design audit §1.8 (2026-09-25): the gold is not the whole price any more,
# because the strongroom can keep a purse out of its reach. core/defeat.gd adds
# a floor the purse cannot touch — the company comes to Defeat.DAYS_LOST later,
# the world walking through the time (core/world_rest.gd, with this screen's
# off-screen battles), and every hero the fight put down (`downed`, the
# result's own list) rolls for a wound. And if nobody at all is left alive, the
# company is finished: party.finished takes the record, and the caller ends
# the run (_end_company) instead of showing a map.
const DEFEAT_GOLD_LOSS_PCT := 0.15
func _retreat(fell: Array = [], downed: Array = []) -> String:
	var p := world.player()
	if p == null or world.settlements.is_empty():
		return ""
	var lost: int = roundi(party.gold * DEFEAT_GOLD_LOSS_PCT)
	party.spend_gold(lost)
	var revived: Dictionary = Party.revive_downed(party)
	if bool(revived.get("finished", false)):
		party.finished = Defeat.ending(party, world, fell)
		_lair_msg.text = party.defeat_line(revived, fell, "", lost)
		return _lair_msg.text
	var safe = world.settlements[0]
	for s in world.settlements:
		if p.position.distance_squared_to(s.position) < p.position.distance_squared_to(safe.position):
			safe = s
	p.position = safe.position
	world.set_goal(p, safe.position)
	_after_night({"lines": Defeat.lose_time(world, party, _night_step)})
	var hurt: Dictionary = Defeat.injure(party, downed, world.clock.elapsed)
	_trait_news.append_array(hurt["lines"])
	_queue_moments(hurt["moments"])
	_lair_msg.text = party.defeat_line(revived, fell, safe.sname, lost, Defeat.DAYS_LOST)
	return _lair_msg.text

# The company is finished (core/defeat.gd): the whole roster died. The living
# (there may be none) go to the barracks and the dead are kept out of it, the
# slot is written one last time with its record, so the title screen lists it
# as over and will not resume it, and the closing screen takes over. The same
# process-global resets as leaving the map, so the next run starts as strangers.
func _end_company() -> void:
	if party.finished.is_empty():
		return
	Defeat.to_barracks(party)
	_autosave()
	FactionOpinion.reset()
	Ladder.reset()
	var host := get_parent()
	if host != null and host.has_method("show_company_end"):
		host.show_company_end(party.finished)

# --- O6: settlement visit ----------------------------------------------
# Same shape as _check_encounter above, against the settlement list instead of
# the party list. `_left` stops the panel reopening on the frame after Leave —
# it clears once the player is actually outside the radius again.
# #89: "paused" is not the gate — the halt on arriving (#70) and after a fight
# (#98) is a pause too, and a party stopped on top of a lair still has to see
# "Attack" / "Slip past". What these gates are really about is a card or panel
# owning the screen.
func _overlay_up() -> bool:
	return _event_card != null or _approach_card != null or _spoils_panel != null \
		or _levelup_panel != null \
		or _site != null or _party_overlay != null or _quest_panel != null or _inventory_panel != null \
		or _story_panel != null or story_card != null or _menu_panel != null or _moment != null

func _check_visit() -> void:
	if _combat != null or not _visit.is_empty() or _overlay_up():
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
		# #231: on the roads, a town the march only passes through is passed
		# through — roads run town to town, and every trip across the map would
		# otherwise stop at every market on the way. The town at the end opens.
		if RouteTravel.on(world) and not p.at_goal() and _destination(p).distance_to(s.position) > VISIT_RADIUS:
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
	if _combat != null or not _visit.is_empty() or _overlay_up():
		_lair_btn.visible = false
		_lair_sneak_btn.visible = false
		_lair_settle_btn.visible = false
		return
	var p := world.player()
	if p == null:
		_lair_btn.visible = false
		_lair_sneak_btn.visible = false
		_lair_settle_btn.visible = false
		return
	# #231: on the roads a hidden lair is found at the fork its track leaves
	# from (RouteTravel.searchable), not by standing near the lair itself — the
	# company cannot stand anywhere a road does not go.
	_route_search = RouteTravel.on(world) and not RouteTravel.searchable(world).is_empty()
	var undiscovered = null if RouteTravel.on(world) else WorldLairs.nearby_undiscovered(world, p.position)
	var target = undiscovered
	if target == null:
		for l in world.lairs:
			if l.discovered and not l.looted and l.position.distance_to(p.position) <= WorldLairs.DISCOVER_RADIUS:
				target = l
				break
	_lair_target = target
	# A cleared lair the party is standing on, inside the respawn's day, on
	# settled ground: it can be bought into a camp (core/raids.gd). Its own
	# button, since _lair_btn is already two-state and hides on a looted lair.
	_settle_target = null
	for l in world.lairs:
		if l.looted and l.position.distance_to(p.position) <= WorldLairs.DISCOVER_RADIUS \
				and Raids.settle_cost(world, l) > 0:
			_settle_target = l
			break
	_lair_settle_btn.visible = _settle_target != null
	if target == null and _route_search:
		_lair_target = null
		_lair_btn.visible = true
		_lair_btn.text = "Search the ground (Survival)"
		_lair_sneak_btn.visible = false
		return
	if _settle_target != null:
		var cost := Raids.settle_cost(world, _settle_target)
		_lair_settle_btn.text = "Settle it (%d ◉)" % cost
		_lair_settle_btn.disabled = party.gold < cost
		_lair_settle_btn.tooltip_text = "" if party.gold >= cost else "not enough gold"
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
	# The design audit §3.4: a bounty or a rescue past its day fails, and says
	# so — a job quietly gone from the log reads as a bug, like a grey lair.
	for title in Quest.expire(party, world.clock.elapsed):
		_lair_msg.text = "Too late: %s. The job is gone, and the board may post it again." % title
		_autosave()
	for l in WorldLairs.expire(world, world.clock.elapsed):
		_lair_msg.text = WorldLairs.resolution_text(l)
		_autosave()
	# ...and the other direction: a day after a lair was emptied, something has
	# moved into it. Said out loud for the same reason the expiry is — a grey
	# landmark going red again with no explanation reads as a bug.
	for l in WorldLairs.respawn(world, world.clock.elapsed):
		_lair_msg.text = WorldLairs.respawn_text(l)
		_autosave()
	# #231: a route world keeps no bands on the map, so none come back and none
	# are refilled; the road decides who is out there — and the towns price the
	# bands that stand on their roads (phase 2, core/route_pins.gd), which the
	# boards post as bounties.
	if RouteTravel.on(world):
		RouteTravel.tick(world, world.clock.elapsed)
		return
	# #142: and the bands the party put down, two days on, out of those lairs.
	var back: Array = WorldAI.respawn(world, world.clock.elapsed)
	for line in back:
		_lair_msg.text = String(line)
	# #163: and a map under its cap gets a fresh band every half day, out of sight.
	var word: String = WorldBands.refill(world, world.clock.elapsed, _bands_rng)
	if word != "":
		_lair_msg.text = word
	if not back.is_empty() or world.bands_refilled_at == world.clock.elapsed:
		_party3d.reset(world)   # a figure is only built on reset (party3d.gd)
		_autosave()

# Raids (core/raids.gd): the clock every lair in the settled country runs
# against the nearest town. Said out loud as it happens, like the expiry and
# the respawn are; a landing can add a lair to the map, so the dioramas are
# rebuilt whenever the poll had anything to say.
func _check_raids() -> void:
	# #231 phase 2: on a route world the same clock runs, and the band stands
	# pinned at the town's gate instead of walking to it (core/raids.gd).
	if _combat != null or _site != null:
		return
	var lines: Array = Raids.tick(world, world.clock.elapsed)
	if lines.is_empty():
		return
	for line in lines:
		_lair_msg.text = String(line)
	_lairs3d.reset(world)
	_autosave()

# A rung gained and renown's title, each said once when it rises — deeds are
# credited in five places, none of which is this screen, so the screen watches
# the numbers. The two high-water marks the achievements read are recorded
# here for the same reason.
const RUNG_LINES := {Ladder.KNOWN: "Known among the %s now.",
	Ladder.TRUSTED: "Trusted among the %s now.", Ladder.SWORN: "Sworn to the %s now."}

func _check_ladder() -> void:
	var lines: Array = []
	var best := 0
	for f in WorldAI.CIVILIZED:
		var r: int = Ladder.rung(f)
		best = maxi(best, r)
		if r > int(_rungs_seen.get(f, 0)):
			lines.append(String(RUNG_LINES[r]) % Ladder.people(f))
		_rungs_seen[f] = r
	Ach.record("best_rung", best)
	var t := Ladder.title_index()
	Ach.record("renown_title", t)
	if t > _ladder_title_seen:
		lines.append("The company is spoken of now: %s." % Ladder.title())
	_ladder_title_seen = t
	# Appended, not set: the deed that earned it may have just said its own
	# line here (a raid lifted, a lair settled), and that is not news to lose.
	for line in lines:
		_lair_msg.text = (_lair_msg.text + "  " + String(line)).strip_edges()

# --- callings: the past each hero's background hands them (core/callings.gd) ---
#
# Dealt here every frame rather than at creation, recruit and load: assign()
# is one loop over the active four that returns early for anyone already
# holding one, and a map with no target for a hero yet (no shrine, no band)
# tries again the frame one appears. Told at the fire (_fireside), done and
# paid on the road (_calling_check at the landmark, the lair, the fight, the
# gate, the hall), and said on a card of its own — shown the frame the map is
# clear, since the doing always happens under something (an outcome card, the
# spoils page, a visit) that a second card must not come down over.
func _check_callings() -> void:
	Callings.assign(party, world)
	if _calling_queue.is_empty() or _combat != null or not _visit.is_empty() or _overlay_up():
		return
	var q: Array = _calling_queue.pop_front()
	# Over a map that was standing still — #98's halt after the spoils page,
	# or the player's own pause — the ack leaves it standing, not running on.
	var still: bool = world.clock.is_paused()
	_calling_done(String(q[0]), q[1], func(): _on_event_ack(); if still: _halt())

# --- the bench (core/bench.gd; the design audit's §2.4) ---------------------
#
# A merc left out of the marching order too long says so, once, on a card —
# and if they are still left out, one morning they are gone, on another. The
# clocks are kept every frame (a merc benched under the party page starts
# counting then, not when the page closes); the beat waits for a clear map the
# way a calling's card does, which is also what keeps it out of a fight, a
# site and a visit. A leaver goes back to the barracks file, where an inn may
# offer them again one day as a veteran (core/recruits.gd).
# A raid can land on the town the company is standing in: the days of a
# downtime row, or a defeat's lost day, run the world clock (core/world_rest.gd)
# with the visit still open. The shelf on screen was read before the raiders
# came, so it is read again — halved, as a raided town's always is — the frame
# the raid is there. Only the market's own keys: the log, the page and the
# visit's stamp stay this visit's.
func _check_raided_visit() -> void:
	if _visit.is_empty():
		return
	var vs = _visit.get("settlement")
	if vs == null or vs.raided_by == "" or bool(_visit.get("battle", false)):
		return
	var m: Dictionary = Visit.market(vs, float(_visit.get("gap", -1.0)), true, float(_visit.get("opinion", 0.0)))
	for k in m:
		_visit[k] = m[k]
	if is_instance_valid(_visit_panel):
		_build_visit_panel()

func _check_bench() -> void:
	Bench.sync(party, world.clock.elapsed)
	if _combat != null or not _visit.is_empty() or _overlay_up() or DiceRoll.in_air():
		return
	var b: Dictionary = Bench.tick(party, world.clock.elapsed)
	if b.is_empty():
		return
	var gone := String(b["kind"]) == "leaves"
	if gone:
		CharacterSave.save(b["ch"])
		_lair_msg.text = "%s has left the company." % String(b["name"])
	_autosave()   # the warning is a mark too: a reload must not tell it twice
	var still: bool = world.clock.is_paused()
	_card({"id": "bench-" + String(b["kind"]), "title": "Gone" if gone else "Restless",
		"kind": "bad", "text": String(b["text"]), "art": "camp-night"},
		func(): _on_event_ack(); if still: _halt())

# The screen saying what just happened, in callings.gd's one shape; `who` is
# the member who did it — the row's roller, the fight's leader, the visit's —
# and is the bond the resolution pays. Paid here and now (core/callings.gd's
# complete: the XP split, the heirloom into the stash, the bond, the state),
# so the autosave the doing always makes next carries it — the shrine is
# spent in that same save, and a quit at the outcome card must not lose the
# past that spent it. Only the card waits: see above.
func _calling_check(kind: String, id: String, who: String) -> void:
	for char_id in Callings.check(party, world, {"kind": kind, "id": id}):
		var r: Dictionary = Callings.complete(party, world, String(char_id), who)
		if not r.is_empty():
			_calling_queue.append([String(char_id), r])

# --- #176 step 3: personality traits, earned -------------------------------
#
# What a fight or a cleared lair did to the people in it (core/traits.gd's
# after_fight / after_lair — rolled there, seeded, already on the sheets when
# this returns). Each change is one line for the after-action page and one
# full-screen moment (scenes/world/trait_moment.gd), queued like a calling's
# card: the doing happens under the spoils page, the showing waits for the map
# to be clear, and every moment in the queue plays back to back, one hero at a
# time, before anything else comes up. SORCMERC_FAST lands each in its end
# state, so the robots walk through them.
func _earn_from_fight(result: Dictionary, difficulty: String, site: String) -> void:
	if result.is_empty():
		return
	# Audit 2.1: whoever was close to one of this fight's dead grieves through
	# Fallen.apply (in _apply_deaths), guaranteed and harder, so after_fight
	# leaves them out of the witness's fifty-fifty. Read now, while the dead
	# are still on the roster as they were.
	var grieving: Array = []
	for id in result.get("deaths", []):
		grieving.append_array(PartyOpinion.close_to(party, String(id)))
	var earned: Dictionary = Traits.after_fight(party.party_characters(), result,
		{"now": world.clock.elapsed, "difficulty": difficulty, "site": site, "grieving": grieving})
	_trait_news.append_array(earned["lines"])
	_queue_moments(earned["moments"])

func _earn_from_lair() -> void:
	var standing: Array = party.party_characters().filter(func(ch): return not ch.dead and int(ch.hp_current) != 0)
	var earned: Dictionary = Traits.after_lair(standing, world.clock.elapsed)
	_trait_news.append_array(earned["lines"])
	_queue_moments(earned["moments"])

func _queue_moments(moments: Array) -> void:
	for m in moments:
		var ch = party.get_member(String(m.get("char_id", "")))
		if ch != null:
			m["figure"] = Figures3D.model_path_for(ch.sheet(), "")
		_moment_queue.append(m)

func _trait_rows(rows: Array) -> void:
	for line in _trait_news:
		rows.append([String(line), Icons.COL_GOLD])
	_trait_news = []

func _check_moments() -> void:
	if _moment_queue.is_empty() or _combat != null or not _visit.is_empty() or _overlay_up() or DiceRoll.in_air():
		return
	var still: bool = world.clock.is_paused()
	world.clock.pause()
	_moment = TraitMoment.new()
	_moment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_moment)
	_moment.finished.connect(func():
		_moment.queue_free()
		_moment = null
		if still:
			_halt()
		else:
			world.clock.resume())
	var batch := _moment_queue
	_moment_queue = []
	_moment.show_moments(batch)

# The party's leader: the first of the march, or nobody.
func _leader() -> String:
	return String(party.active[0]) if not party.active.is_empty() else ""

# The rewards already paid (`r` is complete()'s receipt), said — the done
# line, the chips.
func _calling_done(char_id: String, r: Dictionary, then: Callable) -> void:
	var t: Dictionary = Callings.template_for(party.callings[char_id])
	Sound.play_sfx("quest_complete")
	_autosave()
	_card({"id": "calling-" + String(party.callings[char_id]["id"]), "title": String(t["title"]),
		"kind": "good", "ok": true, "text": String(r["text"]), "xp": int(r["xp"]),
		"item": String(r["item"]), "item_name": String(r["item_name"]), "thanks": ""}, then)

# --- landmarks: places on the map that are not a fight -----------------------
# The lair button's shape again: one button, two states. A found place offers a
# visit; a hidden one in range offers the same Survival search a lair does.
func _check_places() -> void:
	# #231: on the roads a landmark is found by its path (RouteTravel), not by
	# the fog coming off it, and a hidden one by the search at its fork.
	for l in ([] if RouteTravel.on(world) else Landmarks.found_on_explore(world)):
		_lair_msg.text = "%s — a landmark, on the map now." % l.sname
		Sound.play_sfx("landmark_found")
	if _combat != null or not _visit.is_empty() or _overlay_up():
		_place_btn.visible = false
		return
	var p := world.player()
	if p == null:
		_place_btn.visible = false
		return
	var open = Landmarks.nearest_open(world, p.position)
	var hidden = Landmarks.nearby_hidden(world, p.position) if open == null and not RouteTravel.on(world) else null
	_place_target = open if open != null else hidden
	if _place_target == null:
		_place_btn.visible = false
		return
	_place_btn.visible = true
	_place_btn.text = ("Visit %s" % open.sname) if open != null else "Search the ground (Survival)"

func _place_action() -> void:
	var l = _place_target
	if l == null or _combat != null:
		return
	if not l.found:
		var roll: Dictionary = Landmarks.search(l, party)
		if roll.is_empty():
			return
		_map_roll(roll, _lair_msg, ("%s finds it — %s is here (Survival %d+%d vs DC %d)." % [
			roll["cname"], l.sname, roll["nat"], roll["bonus"], roll["dc"]]) if roll["ok"] else (
			"Nothing this time (Survival %d+%d vs DC %d)." % [roll["nat"], roll["bonus"], roll["dc"]]),
			"search_found" if roll["ok"] else "search_nothing")
		return
	_open_place(l)

func _open_place(l) -> void:
	if _approach_card != null:
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_place_open = l
	_approach_card = ApproachCard.new()
	_approach_card.caption = "A   P L A C E   O N   T H E   R O A D"
	_approach_card.glyph = "◆"
	_approach_card.hint = "Choose what to do here"
	_approach_card.art_stem = "landmark-" + l.kind
	add_child(_approach_card)
	_approach_card.chosen.connect(_on_place_chosen)
	_approach_card.show_approach(Landmarks.options(l, party, world), l.sname)
	Sound.play_sfx("landmark_open")

func _on_place_chosen(id: String) -> void:
	var l = _place_open
	_place_open = null
	_close_approach()
	if l == null:
		return
	var e: Dictionary = Landmarks.resolve(l, id, party, world,
		RNG.new(maxi(1, absi(hash("%s|%s|%d" % [l.id, id, int(world.clock.elapsed)])))))
	if e.is_empty():   # leave, or nothing to do
		world.clock.resume()
		_pause_btn.text = "Pause"
		return
	_calling_check("landmark_answered", l.id, String(e.get("char_id", "")))   # shown after this card
	_autosave()
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event(e)

func _lair_action() -> void:
	if _route_search and _lair_target == null and _combat == null:
		_route_search_action()
		return
	var l: World.Lair = _lair_target
	if l == null or _combat != null:
		return
	if not l.discovered:
		var roll := WorldLairs.search(l, party)
		if roll.is_empty():
			return
		_map_roll(roll, _lair_msg, ("%s finds the tracks — %s is here (Survival %d+%d vs DC %d)." % [
			roll["cname"], l.sname, roll["nat"], roll["bonus"], roll["dc"]]) if roll["ok"] else (
			"Nothing this time (Survival %d+%d vs DC %d)." % [roll["nat"], roll["bonus"], roll["dc"]]),
			"search_found" if roll["ok"] else "search_nothing")
		return
	await _delve(l)

# #231: the Survival check at a fork — a lair's track, a hut's or a tower's path.
func _route_search_action() -> void:
	var roll: Dictionary = RouteTravel.search(world, party)
	if roll.is_empty():
		return
	var names: Array = roll.get("places", [])
	_map_roll(roll, _lair_msg, ("%s finds a way off the road — to %s (Survival %d+%d vs DC %d)." % [
		roll["cname"], " and ".join(names) if not names.is_empty() else "somewhere", roll["nat"], roll["bonus"], roll["dc"]]) if roll["ok"] else (
		"Nothing this time (Survival %d+%d vs DC %d)." % [roll["nat"], roll["bonus"], roll["dc"]]),
		"search_found" if roll["ok"] else "search_nothing")

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
		var loot: Dictionary = WorldLairs.loot(l, world.clock.elapsed)
		party.add_gold(int(loot.get("gold", 0)))
		Quest.record_lair_cleared(party, l.id)
		_calling_check("lair_cleared", l.id, _leader())
		_earn_from_lair()
		_map_roll(roll, _lair_msg, "%s +%d ◉." % [String(roll["text"]), int(loot.get("gold", 0))])
	else:
		# Roused by the attempt itself, not as a side effect of the fight it
		# falls into: that is what makes this one attempt rather than one per
		# visit, and it is the moment the D1 window should start counting from.
		WorldLairs.mark_entered(l, world.clock.elapsed)
		# The delve waits for the die: it is how the roll went.
		_map_roll(roll, _lair_msg, String(roll["text"]), "", func(): _lair_action())

func _lair_settle_action() -> void:
	var l: World.Lair = _settle_target
	if l == null:
		return
	var home = Raids.settlers_from(world, l.position)  # before settle(): afterwards the nearest civilized settlement is the camp itself
	var s = Raids.settle(world, l, party, world.clock.elapsed)
	if s == null:
		return
	_lair_msg.text = "Settlers from %s put up the first roof at %s." % [home.sname, s.sname]
	Sound.play_sfx("settle")
	Sound.play_sting("music_founding")
	# The party stands on the new camp: without this _check_visit opens its
	# page next frame, over the line above and the camp appearing on the map.
	# `_left` is the visit gate's own "just left, no re-entry until out of
	# range" — walk out and back in to go inside.
	_left = s
	_settle_target = null
	_lair_target = null
	_settlements3d.reset(world)
	_lairs3d.reset(world)
	_autosave()

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
	# Issue #30: the running total the delve's own spoils page is built from.
	# gold0 rather than a counter, because a site pays from three places (room
	# caches, the boss hoard, the fights themselves) and only the purse sees all
	# of them.
	_delve_haul = {"gold0": party.gold, "xp": 0, "fights": 0, "loot": [], "quests": []}
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
		String(_site.room.get("difficulty", "normal")), false, false, "lair")
	if _site == null:
		return
	if not result.is_empty():
		if String(result.get("outcome", "")) == "Victory":
			_bank(result)
		_apply_deaths(result)
		_site.finish_combat(result)
		var obj: Dictionary = result.get("objective", {})
		if String(obj.get("kind", "")) != "":
			_site.say(Objectives.spoils_line(obj))
		if String(obj.get("kind", "")) == "rescue" and bool(obj.get("done", false)):
			Quest.record_rescued(party, _site.lair.id)
			var line := "The captive is out of %s." % _site.lair.sname
			_site.say(line)
			if not _delve_haul.is_empty():
				(_delve_haul["quests"] as Array).append(line)
	if _site.state == "wiped":
		_site_wiped(result.get("deaths", []), result.get("downed", []))
		if not party.finished.is_empty():
			# Nobody came out of the lair at all: the run ends here. The site
			# screen goes first, so nothing of it outlives the map.
			_site = null
			if _site_screen != null:
				_site_screen.queue_free()
				_site_screen = null
			_end_company()
			return
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
# people. The map's own landing still applies (gold tax, the downed come to and
# the dead stay dead, wake at the nearest settlement — the fight's deaths were
# applied before this, the road's order too) and on top of it the bag is lightened and the lair
# closes up again — see core/site.gd's wipe_penalty() for why it is the stash
# and never the equipped gear.
func _site_wiped(fell: Array = [], downed: Array = []) -> void:
	var toll: Dictionary = Site.wipe_penalty(party, _site.lair)
	var came_to: String = _retreat(fell, downed)
	var names: Array = []
	for item_id in toll.get("items", {}):
		names.append("%s x%d" % [Campaign.item_name(String(item_id)), int(toll["items"][item_id])])
	var lost: String = ("They lost %s from the packs. " % ", ".join(names)) if not names.is_empty() else ""
	_lair_msg.text = "The company is dragged out of %s. %sThe way in has closed up behind them.  %s" % [
		_site.lair.sname, lost, came_to]

func _on_site_done() -> void:
	if _site == null:
		return
	var l = _site.lair
	var ending: String = _site.state
	var cleared: bool = ending == "cleared"
	if cleared:
		Quest.record_lair_cleared(party, l.id)
		_calling_check("lair_cleared", l.id, _leader())   # shown after the spoils page
		_earn_from_lair()                                  # ...and so is what it did to them
		# Reaching the bottom is worth something of its own. Every room on the
		# way down already paid its own XP; this is the part that was missing,
		# and it is why a delve is now worth more than the same fights strung
		# out on the road rather than less. Banked through the same split every
		# other XP award uses, and counted into the delve's own page below.
		var bonus: int = Site.clear_xp(l)
		Campaign.split_xp(party, bonus)
		if not _delve_haul.is_empty():
			_delve_haul["xp"] = int(_delve_haul.get("xp", 0)) + bonus
			_delve_haul["cleared_xp"] = bonus
		_lair_msg.text = "%s is cleared out, all the way to the bottom. +%d XP." % [l.sname, bonus]
	elif _site.state == "withdrawn":
		# core/site.gd: walking out undoes the descent; the next entry is the mouth.
		_lair_msg.text = "%s is still down there. %d of %d rooms were behind you, and they will fill in again before you are back." % [
			l.sname, int(l.depth_cleared), Site.depth_for(l)]
	# The road home (core/world_road_home.gd): out of a site on their feet, the
	# company has until dawn or a night's sleep on the gentler walk-home curve.
	# A wipe does not start it — the defeat's landing has already carried them in.
	if ending in ["cleared", "withdrawn"]:
		WorldRoadHome.set_out(world)
		_lair_msg.text += "  " + WorldRoadHome.EXIT_LINE
	_site = null
	if _site_screen != null:
		_site_screen.queue_free()
		_site_screen = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	_autosave()
	# Issue #30: what the whole descent paid, once they are back out in the air.
	# Not on a wipe — _site_wiped() has already said what that cost, and a page
	# headed with a haul is the wrong thing to show a party that was dragged out.
	if ending in ["cleared", "withdrawn"]:
		_show_delve_spoils(l, cleared)
	else:
		_delve_haul = {}

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
		_map_roll(roll, _camp_msg, "%s forages along the way (%s %d+%d vs DC %d) — +%d ◉." % [
			roll["cname"], String(roll["skill"]).capitalize(), roll["nat"], roll["bonus"], roll["dc"], int(roll["gold"])])

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
	_approach_card.foe_faction = String(foe.faction)
	var kind := String(_road_objective(foe, "").get("kind", ""))
	_approach_card.show_approach(Approach.options(party, foe, hostile),
		"%s (%d)%s" % [EnemyNames.upper_first(EnemyNames.band_name(foe, world)), foe.troops.size(), ("  ·  " + Objectives.title(kind)) if kind != "" else ""])

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
	_event_card.show_event(_approach_event(r, String(foe.faction)))

# core/approach.gd's result, in the shape event_card.gd already draws. The
# picture is the band's own faction's when that way has been painted for it.
func _approach_event(r: Dictionary, faction := "") -> Dictionary:
	var e: Dictionary = r.duplicate(true)
	e["id"] = "approach-%s" % String(r.get("way", ""))
	e["art"] = Icons.scene_stem("event-" + e["id"], faction, r.get("ok") if r.has("ok") else null)
	e["title"] = String(Approach.WAYS.get(String(r.get("way", "")), {}).get("label", "The meeting"))
	# "good" is not the same as "the roll passed": walking into a fight you
	# meant to walk into is not a setback, and a blown ambush is.
	# A parley that cost the company its standing with a people is a setback too.
	e["kind"] = "bad" if bool(r.get("forced_ambush", false)) or r.has("opinion") else "good"
	if r.has("toll"):
		e["gold"] = -int(r["toll"])
	return e

# Which approach outcome is a breakout, and at what roster: seen mid-slip is
# caught in the open, at the threat roster the card already showed; a blown
# ambush attempt is just the ordinary fight its card promised — THEY take the
# first round, nothing more.
static func _jumped_for(r: Dictionary) -> String:
	return "seen" if String(r.get("way", "")) == "avoid" and bool(r.get("forced_ambush", false)) else ""

func _on_approach_reported(foe, r: Dictionary) -> void:
	_on_event_ack()
	if not bool(r.get("fight", true)):
		# No fight: the band is still out there, just not met. Mark it slipped so
		# standing next to it does not re-open the question every frame, and
		# call a truce so a hunting band breaks off instead of closing again
		# the moment you step out of reach.
		_slipped[foe.id] = true
		WorldAI.truce(foe, world.player(), world.clock.elapsed)
		_route_forget(foe)   # #231: a band the road sent goes its way, and is not seen again
		if _halted_on_arrival:
			_halt()   # a band the party walked up to on purpose: it arrived, and waits for orders
		else:
			world.clock.resume()
		return
	await _launch_combat(foe, bool(r.get("scouted_ahead", false)),
		bool(r.get("forced_ambush", false)), _jumped_for(r))

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
# #231 phase 1 — the road, once a frame on a route world: a path seen leaving it
# (said on the HUD line, like a landmark coming into view), or what the road
# sent (RouteTravel.step: one roll per RouteEncounters.STEP walked). A threat is
# met the way a band closing on the company always was — the approach card, or
# the watch's roll in the dark (_meet) — and a meeting gets the friendly card.
# The march is not called off: a meeting that ends without a fight walks on.
# Same gates as the road's events: nothing while a fight, a town, a site or a
# card is up, or with the clock stopped.
func _check_routes(from: Vector2) -> void:
	if not RouteTravel.on(world) or _combat != null or not _visit.is_empty() or _site != null \
			or _approach_card != null or _event_card != null or world.clock.is_paused():
		return
	for ev in RouteTravel.step(world, from):
		match String(ev["kind"]):
			"noticed":
				var names: Array = ev["places"]
				_lair_msg.text = ("A way leaves the road here — to %s." % " and ".join(names)) if not names.is_empty() \
					else "A way leaves the road here."
				Sound.play_sfx("landmark_found")
			"threat", "meet":
				# What the road sent, or a band pinned on it (phase 2) that the
				# company just walked up to — already on the map for its meeting.
				var band = ev["band"] if ev.has("band") else RouteTravel.band_for(world, ev["spec"])
				_party3d.reset(world)   # a figure is only built on reset (party3d.gd)
				if ev["kind"] == "threat":
					_meet(band, bool(ev["hostile"]))
				else:
					_open_approach(band, false)
				return

# A met band is gone when its meeting is, however that ended (RouteTravel.forget).
func _route_forget(band) -> void:
	if RouteTravel.on(world):
		RouteTravel.forget(world, band)
		_party3d.reset(world)

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
	# D7: a scouting job is done the moment the party is standing in the band it
	# was sent to look at — the riding back is the turn-in, not the job. Read off
	# where they ARE rather than off a crossing: a job taken in a town that sits
	# just inside the seam would otherwise need the party to leave the band and
	# come back before it would tick.
	Quest.record_region_reached(party, String(band["id"]))
	# T27+D6: the map's own ambient bed. The overworld used to be the one screen
	# with SFX but no music at all — campaign.gd set a bed for every node of a
	# linear run, and the open world, which is where most of a session is spent,
	# played nothing. The band id IS the theme id (tools/gen_audio.py BEDS), so
	# riding out of the heartland is audible a beat before the label says so.
	# Called every frame: Audio._set_environment() early-returns on an unchanged
	# theme, so this is a string compare, and coming out of a town restores the
	# right country's bed without _close_visit() having to know which one it was.
	# A sub-band plays its country's bed: the Unmapped has no track of its own and
	# is the Far Deeps' outer half (Regions.country_of).
	Sound.set_environment("settlement" if not _visit.is_empty() else Regions.country_of(String(band["id"])))
	if _region_lbl != null:
		# Short form: this bar already carries nine controls and a hint, and the
		# long form lives on the lair button, the inn's leads and the crossing card.
		_region_lbl.text = "%s, levels %d to %d" % [String(band["label"]), int(lv[0]), int(lv[1])]
		# O-biome: which COUNTRY the party is in and what KIND of ground it is
		# are two different questions, and the bar answers them in that order.
		# The downs are the default and go unsaid — naming the absence of a
		# biome on nine maps out of ten is noise, not information.
		var ground: String = world.biome_at(p0.position)
		if ground != World.DEFAULT_BIOME:
			_region_lbl.text += " · %s" % BIOME_LABEL.get(ground, ground)
		if Ladder.title_index() > 0:
			_region_lbl.text += " · %s" % Ladder.title()
		# The road home's clock, while it runs: said here because it is about
		# where the company is walking, and gone the moment dawn or a bed ends it.
		var home_note: String = WorldRoadHome.hud_note(world, party)
		if home_note != "":
			_region_lbl.text += " · %s" % home_note
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
	# D7: walking in this gate IS a courier job's delivery. Before the panel is
	# built, so the crate is already handed over on the screen that opens.
	Quest.record_settlement_visited(party, s.id)
	_calling_check("visited", s.id, _leader())   # shown when the visit closes
	_visit = Visit.visit(s, world)
	_visit_page = "hub"
	_visit_list_v.clear()
	_market_tab = MARKET_TAB_ALL
	Sound.play_sfx("settlement")   # the gate, once, on arriving — not on every page
	# Home: the garden's potions and the map room's marks, gathered on the step
	# — before the build, which records the stash and shares the visit (its log
	# line included) with a co-op guest.
	if Lodge.at(party, s):
		var c: Dictionary = Lodge.collect(party, world)
		if String(c["text"]) != "":
			_say(String(c["text"]))
	_build_visit_panel()

func _goto_page(page: String) -> void:
	_visit_page = page
	_visit_list_v.erase(page)   # a page walked into starts at its top (#228)
	if page == "market":
		_market_tab = _first_counter()   # every visit to the stalls starts at the first counter
		Sound.play_sfx("shop")         # the shop door, over the button's own click
	_build_visit_panel()

# Kept as the fallback for a settlement with no counters at all; the "All"
# tab itself is gone — one counter at a time, the way the stalls are drawn.
const MARKET_TAB_ALL := "all"

func _first_counter() -> String:
	for t in _visit.get("services", []):
		if t != "innkeeper":
			return String(t)
	return MARKET_TAB_ALL

func _goto_market_tab(service: String) -> void:
	_market_tab = service
	_build_visit_panel()

# T9y: a settlement is four screens now, and the only way between them was the
# mouse. Esc backs out one level (counter -> page -> town square -> the map),
# which is the one binding a player will try without being told; the initials
# jump straight to a building from anywhere inside the gates.
func _unhandled_key_input(event: InputEvent) -> void:
	# `echo` is the key repeat: a held Space used to re-toggle the pause every
	# repeat, so the clock ran only while the key was down. One press, one toggle.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# The one binding that works everywhere on the map, in a town or out of it:
	# a bug you can only report from the town square is a bug you lose.
	if event.keycode == KEY_F3 and _combat == null:
		accept_event()
		report_bug()
		return
	if spectator:   # the camera keys, and nothing that gives an order
		match event.keycode:
			KEY_Q: orbit_by(-YAW_STEP)
			KEY_E: orbit_by(YAW_STEP)
			KEY_R: tilt_by(PITCH_STEP)
			KEY_F: tilt_by(-PITCH_STEP)
			KEY_HOME: reset_view()
			_: return
		accept_event()
		return
	if _combat != null:
		return
	# A town's die in the air: Enter, Space or Esc lands it (and never leaves
	# the town under it).
	if is_instance_valid(_visit_dice) and _visit_dice.is_playing() \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		accept_event()
		_visit_dice.finish()
		return
	# #106: the party screen opened at the inn's counter sits OVER the visit.
	# Esc there used to fall through to the visit's own bindings underneath —
	# town square, then Leave — so "Back to the inn" put the party on the map
	# outside town, where the night had bands waiting.
	if _party_overlay != null and not _visit.is_empty():
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			accept_event()
			_close_party()
		return
	# Out on the map, before the settlement bindings below: the two keys every
	# player presses first. Esc backs out of whatever panel is up and otherwise
	# opens the pause menu; space is the Pause button without the trip to the
	# corner. Neither existed here, though both do in the fight (scenes/main.gd).
	if _visit.is_empty():
		# The spoils page is modal and has one way on: any of the three keys a
		# player reaches for takes it.
		if _spoils_panel != null:
			if event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				accept_event()
				_close_spoils()
			return
		# #118's level-up page is modal the same way, with two answers rather
		# than one: Enter goes to the party screen, Esc leaves it for later.
		if _levelup_panel != null:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				accept_event()
				_close_levelup()
				_open_party()
			elif event.keycode in [KEY_ESCAPE, KEY_SPACE]:
				accept_event()
				_close_levelup()
			return
		match event.keycode:
			KEY_ESCAPE:
				# A delve, a road event, a band closing in and a story beat each
				# own the screen and have their own way out; Esc is not it.
				if _site != null or _event_card != null or _approach_card != null \
						or story_card != null:
					return
				if _party_overlay != null:
					_close_party()
				elif _quest_panel != null:
					_close_quests()
				elif _inventory_panel != null:
					_close_inventory()
				elif _story_panel != null:
					_close_story()
				else:
					_toggle_menu()
			KEY_SPACE:
				if _menu_panel != null:
					_close_menu()
				else:
					_toggle_pause()
			# The clock's four speeds by their own numbers, the party screen by
			# its letter — the HUD buttons without the trip to the bar.
			KEY_1, KEY_KP_1: _set_speed(1.0)
			KEY_2, KEY_KP_2: _set_speed(2.0)
			KEY_4, KEY_KP_4: _set_speed(4.0)
			KEY_8, KEY_KP_8: _set_speed(8.0)
			KEY_P:
				if _party_overlay != null:
					_close_party()
				else:
					_open_party()
			KEY_I: _toggle_inventory()
			# The camera, from the keyboard. Q/E turn it, R/F tilt it, Home puts
			# it back — the same three things middle-drag and the scroll wheel
			# do, for players who would rather not hold a button down. Home is
			# the one that has to exist: once a view can be turned it can be
			# lost, and finding the angle you started at by hand is not a game.
			KEY_Q: orbit_by(-YAW_STEP)
			KEY_E: orbit_by(YAW_STEP)
			KEY_R: tilt_by(PITCH_STEP)
			KEY_F: tilt_by(-PITCH_STEP)
			KEY_HOME: reset_view()
			_: return
		accept_event()
		return
	# The inn's fireside (or the approach card under a courtship) sits over a
	# visit that is still open; the page keys must not act through it, or
	# Leave (Esc) can close the visit out from under the card still showing.
	if _event_card != null or _approach_card != null:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _visit_page != "hub":
				_goto_page("hub")
			else:
				_close_visit()
		KEY_M: _goto_page("market")
		KEY_I: _goto_page("inn")
		KEY_B: _goto_page("board")
		KEY_T: _goto_page("hub")
		_: return
	accept_event()

# Everything a report wants to know about a run in progress, read live. Ordered:
# the overlay and the issue body both render it in this order.
func report_bug() -> void:
	BugReportOverlay.toggle(self, bug_context())

func bug_context() -> Dictionary:
	var ctx := {"Screen": "the open world (%s map)" % String(world.origin.get("kind", world_size))}
	if not _visit.is_empty():
		var s = _visit.get("settlement")
		ctx["In a settlement"] = "%s, %s page" % [
			s.sname if s != null else "?", _visit_page]
	ctx["When"] = WorldSave.day_clock(world.clock.elapsed, ", ")
	if not _region.is_empty():
		ctx["Region"] = String(_region.get("label", _region.get("id", "?")))
	var p0 = world.player()
	if p0 != null:
		ctx["Position"] = "%d, %d" % [int(p0.position.x), int(p0.position.y)]
	var who: Array = []
	for ch in (party.party_characters() if party != null else []):
		# hp_current is -1 for "never been hurt" (core/character.gd), not zero.
		var state := "down" if ch.dead else (
			"full hp" if ch.hp_current < 0 else "%d hp" % ch.hp_current)
		who.append("%s (%s)" % [ch.cname, state])
	ctx["Party"] = ", ".join(who) if not who.is_empty() else "nobody standing"
	if party != null:
		ctx["Gold"] = "%d ◉" % party.gold
	if story != null:
		ctx["Story"] = "%s, chapter %s" % [story.pack_id,
			story.chapter if story.chapter != "" else "(finished)"]
	ctx["Paused"] = "yes" if world.clock.is_paused() else "no"
	return ctx

func _close_visit() -> void:
	_flush_visit_roll()   # the popup is the world's child, not the panel's: it would outlive the town
	_left = _visit.get("settlement")
	_visit = {}
	if _visit_panel != null:
		_visit_panel.queue_free()
		_visit_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"
	# The shrine: the blessing is taken on the way out, once a visit, and said
	# on the map since the panel that would have said it is gone.
	if _left != null and Lodge.at(party, _left):
		var b: Dictionary = Lodge.bless(party, world)
		if not b.is_empty():
			_lair_msg.text = String(b["text"])
	_autosave()   # O13 autosave: the purse and the shelf both moved
	_coop_share_visit()

func _buy(item_id: String) -> void:
	if Visit.buy(_visit, party, item_id):
		Sound.play_sfx("buy")
		_cheer()
		_build_visit_panel()
	else:
		_say("Not enough gold.")

func _sell(item_id: String) -> void:
	if Visit.sell(_visit, party, item_id):
		_cheer()
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
		Sound.play_sfx("rumour_bought")
		_autosave()
	_build_visit_panel()
	_say(String(r.get("text", "")))

func _raise_dead(id: String) -> void:
	var r: Dictionary = Visit.raise_dead(party, id)
	if bool(r.get("ok", false)):
		Sound.play_sfx("heal")
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

# O9 item 1: one attempt per visit, and the stall is watched for a day after
# (Visit.steal_wait). The steal roll is seeded off (settlement, hour)
# and the clock is paused for the whole visit, so every press rolled the identical
# result — a nat 20 was an unlimited gold button. The mark lives on `_visit`, so
# Leave and come back is a fresh attempt (at a fresh hour).
func _steal() -> void:
	var r: Dictionary = Visit.steal(_visit["settlement"], party, world, _visit)
	_visit["stolen"] = true
	_build_visit_panel()
	_say_rolled(r, String(r.get("text", "Nobody here has the hands for it.")), "pickup")

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
	# Both sides added a flag here, and the comment above is exactly why both have
	# to stay: "worked" is this branch's healer shift, "sour" is the moods work's
	# soured face. Either one dropped from this list resets itself the next time
	# anything replaces _visit.
	for k in ["stolen", "persuaded", "investigated", "haggled", "worked", "sour"]:
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
	_say_rolled(r, String(r.get("text", "Nobody here will hear you out.")))

# T9x: haggling — the mirror of persuade(), for a market that's already
# open. One attempt per visit; moves this visit's prices for better or
# worse depending on the roll, doesn't touch the underlying faction opinion.
func _work_healer() -> void:
	if _visit.get("worked", false):
		return
	var r: Dictionary = Visit.work_healer(_visit["settlement"], party)
	_visit["worked"] = true
	_autosave()
	_build_visit_panel()
	_say_rolled(r, String(r.get("text", "The healer has no work for you.")), "buy")

func _haggle() -> void:
	if _visit.get("haggled", false):
		_say("They will not budge on price again today.")
		return
	var r: Dictionary = Visit.haggle(_visit, party)
	_visit["haggled"] = true
	_build_visit_panel()
	# The new prices wait for the die: a shelf already reading "x0.85" says how
	# the roll went before it has landed.
	_say_rolled(r, String(r.get("text", "Nobody here is in the mood to talk price.")), "buy", func():
		if r.is_empty():
			return
		Visit.apply_haggle(_visit, float(r["mult"]))
		if bool(r["ok"]):
			_cheer()
		else:
			_visit["sour"] = true   # a bad ask sours the room, and the face, for the visit
		_build_visit_panel())

# T9x: one attempt per visit. Only shown when a fight resolved near this
# settlement recently (market()'s own `battle` flag).
func _investigate() -> void:
	if _visit.get("investigated", false):
		_say("The battlefield's already been picked over.")
		return
	var r: Dictionary = Visit.investigate_battle(_visit["settlement"], _visit, party)
	_visit["investigated"] = true
	_build_visit_panel()
	_say_rolled(r, String(r.get("text", "There is nobody here who would know where to look.")), "pickup")

# O9 item 2: the inn. Time is the cost — see SettlementVisit.rest — and the extra
# hours restock the shelf, so the market is re-read afterwards.
# T9x: gated to once per in-game day (Visit.can_long_rest) — RAW's own rule,
# never enforced before, so a settlement visit could spam free full heals.
func _rest() -> void:
	if not Visit.can_long_rest(party, world):
		_say("The party is not tired enough for another long rest yet.")
		return
	var s = _visit["settlement"]
	var cost := Visit.inn_cost(s, party)
	if not party.spend_gold(cost):
		_say("The purse cannot cover a room here (%d ◉)." % cost)
		return
	var before := _visit
	var stamp: float = s.last_visited
	var night: Dictionary = Visit.rest(party, world, "long-rest", _night_step)
	_after_night(night)
	Sound.play_sfx("rest")
	var trance: Dictionary = Trance.apply_rest_bonus(party, world, s.position)
	_visit = Visit.visit(s, world)
	_carry_visit_flags(before, _visit)
	Downtime.restamp(party, s, stamp, s.last_visited)   # the bench is still this visit's (the game counts days)
	Lodge.restamp(party, s, stamp, s.last_visited)      # ...and the yard's swap and the shrine's blessing
	_cheer()
	_build_visit_panel()
	# #176: a night in a bed mends a Wounded hero; a city's healers mend Maimed.
	var mended: Array = []
	for ch in party.party_characters():
		for n in Traits.heal_rest(ch, String(s.kind) == "city"):
			mended.append("%s is no longer %s." % [ch.cname, n])
	_say("The company takes a long rest (%s). Eight hours pass and the stalls fill up again.%s%s%s" % [
		"on the house" if cost == 0 else "%d ◉ for the room" % cost, Visit.rest_note(night), _trance_note(trance),
		(" " + " ".join(mended)) if not mended.is_empty() else ""])
	# The same fire as a camp's, over the inn page; the panel under it has
	# already said what the night cost.
	_fireside(RNG.new(maxi(1, absi(hash("inn|%s|%d" % [s.id, int(world.clock.elapsed)])))), _on_inn_card_ack, true)
	# A past told at this very inn can name this very town — the charlatan's
	# old mark, the noble's envoy. The gate's check ran before it was told;
	# asked again, it is done, and the card comes down as the party leaves.
	_calling_check("visited", s.id, _leader())

# The inn's fireside card comes down over a visit that is still holding the
# clock, so its ack cannot be the plain one — that would set the map running
# behind the market. But the visit can have been closed out from under the
# card already (Leave, while the card was still up); re-pausing then would
# leave the map stuck paused with nothing left to hold it.
func _on_inn_card_ack() -> void:
	_on_event_ack()
	if not _visit.is_empty():
		world.clock.pause()
		_pause_btn.text = "Resume"

# T9x: names the check and its result explicitly, same convention every
# other overworld roll in this file uses — never just "something happened".
# Audit 4.3: the trance no longer tops the party up the moment it wakes (when
# nobody needed it); it banks a short rest for later in the day.
func _trance_note(trance: Dictionary) -> String:
	if trance.is_empty():
		return ""
	var note := "  Someone did not need the sleep: the ground nearby is scouted%s." % (
		", and the trance banks a short rest for later today that does not count against the day's two" if trance.get("banked", false) else "")
	var id: Dictionary = trance.get("identify", {})
	if not id.is_empty():
		if id["ok"]:
			note += "  They also puzzle out the %s while they are at it (Arcana %d+%d vs DC %d)." % [
				Campaign.item_name(id["item_id"]), id["nat"], id["bonus"], id["dc"]]
		else:
			note += "  They also take a crack at identifying an item, no luck (Arcana %d+%d vs DC %d)." % [
				id["nat"], id["bonus"], id["dc"]]
	return note

# T9x: a short rest works anywhere on the map, not just a settlement — but
# only when it's actually safe: mid-fight, paused, or a hostile band close
# enough to notice all say no, same radius _check_encounter() uses to decide
# whether a band has closed in enough to trigger a fight. Audit 1.7: making
# camp asks the same question (core/world_camp.gd owns it now).
func _hostile_nearby() -> bool:
	return WorldCamp.hostile_near(world, ENCOUNTER_RADIUS)

# Audit 1.7: one step of a long rest's night, from core/world_rest.gd — the
# part of _process() that is the world's but needs this screen's
# encounter_spec(): bands that meet in the dark fight it out off-screen.
func _night_step(dt: float) -> void:
	for r in WorldBattle.check(world, _trigger(dt), encounter_spec):
		Visit.mark_battle(world, r["loser"].position, world.clock.elapsed)

# The night is over: say what the raids did in it, and rebuild the figures the
# night added or took away (a raid band out, a band beaten off-screen).
func _after_night(night: Dictionary) -> void:
	for line in night.get("lines", []):
		_lair_msg.text = String(line)
	if _party3d != null:
		_party3d.reset(world)
	if _lairs3d != null:
		_lairs3d.reset(world)

func _short_rest() -> void:
	if _combat != null or not _visit.is_empty() or _overlay_up():
		return
	if _hostile_nearby():
		_camp_msg.text = "Too dangerous to rest here — something hostile is close."
		return
	if not Visit.can_short_rest(party, world):
		_camp_msg.text = "The party has rested enough for one day — only a long rest will do now."
		return
	var r: Dictionary = Visit.rest(party, world, "short-rest")
	Sound.play_sfx("rest")
	_camp_msg.text = "The company takes a short rest. An hour passes.%s" % Visit.rest_note(r)

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
# The whole decision — the gate, a hostile band in reach, the kit or the Rope
# Trick, the roll, the night — is WorldCamp.make_camp(); this draws it.
func _make_camp() -> void:
	if _combat != null or not _visit.is_empty() or _overlay_up():
		return
	# #231: a camp anywhere on a road is as risky as its stretch of road.
	var pct: int = RouteTravel.camp_ambush_pct(world, world.player().position) if RouteTravel.on(world) and world.player() != null \
		else WorldCamp.AMBUSH_CHANCE_PCT
	var r: Dictionary = WorldCamp.make_camp(party, world, ENCOUNTER_RADIUS, _night_step, pct)
	if not bool(r["ok"]):
		_camp_msg.text = String(r["text"])
		return
	var p := world.player()
	var rng: RNG = r["rng"]
	if not bool(r["ambush"]):
		_after_night(r["rest"])
		Sound.play_sfx("rest")
		var trance: Dictionary = Trance.apply_rest_bonus(party, world, p.position)
		_camp_msg.text = "%s Eight hours pass.%s%s" % [
			"Nothing finds the hermit's hollow in the night." if bool(r.get("hollow", false))
				else "The camp holds through the night.",
			Visit.rest_note(r["rest"]), _trance_note(trance)]
		if not _fireside(rng, _on_event_ack):
			_camp_card("night", "The camp holds", "good", _camp_msg.text, _on_event_ack)
		return
	var watch: Dictionary = r["watch"]
	var foe := World.RoamingParty.new("camp-ambush-%d" % int(world.clock.elapsed), p.position, WorldCamp.AMBUSH_FACTION)
	# T19: earned for the night itself, not for the fight — losing it ends the
	# save's road anyway, and being woken by bandits is the achievement.
	Ach.unlock("camp_ambush")
	# T9x: name the check and the roll, not just the outcome — same
	# "Skill nat+bonus vs DC" shape every other overworld check in this file uses.
	var skill_name: String = String(watch.get("skill", "")).capitalize()
	# The card rolls the watch live (scenes/dice_roll.gd): it gets the roll as
	# keys and says the rest in words; the HUD line keeps the numbers.
	var rolled: Dictionary = _watch_roll(watch)
	if watch["ok"]:
		_camp_msg.text = "%s hears them coming (%s %d+%d vs DC %d). The company gets the drop on them." % [
			watch.get("cname", "Someone"), skill_name, watch["nat"], watch["bonus"], watch["dc"]]
		_camp_card("watch", "Something in the dark", "good",
			"%s hears them coming. The company gets the drop on them." % watch.get("cname", "Someone") if not rolled.is_empty() else _camp_msg.text,
			func(): _on_event_ack(); await _launch_combat(foe, true, false), "", rolled)
	else:
		var who: String = watch.get("char_id", "")
		_camp_msg.text = ("%s does not catch it in time (%s %d+%d vs DC %d). They are in the camp before anyone can draw." % [
			watch.get("cname", ""), skill_name, watch["nat"], watch["bonus"], watch["dc"]]) if who != "" \
			else "Nobody is watching the dark. They are in the camp before anyone can draw."
		_camp_card("jumped", "The camp is jumped", "bad",
			"%s does not catch it in time. They are in the camp before anyone can draw." % watch.get("cname", "") if not rolled.is_empty() else _camp_msg.text,
			func(): _on_event_ack(); await _launch_combat(foe, false, true, "dark"), "", rolled)

# The night, on the same card the road uses: what the camp did, pictured
# (assets/generated/camp-<night|watch|jumped>.png — or `art`, for a card that
# has no picture of its own: the fireside and the courtship wear the night),
# and — for an ambush — the fight waits behind the button rather than under
# the label.
func _camp_card(id: String, title: String, kind: String, text: String, then: Callable, art := "", roll := {}) -> void:
	var e := {"id": "camp-" + id, "title": title, "kind": kind, "text": text, "art": art if art != "" else "camp-" + id}
	e.merge(roll)   # a watch's roll: the card rolls it live before it says what happened
	_card(e, then)

# The keys a card rolls live from (scenes/world/event_card.gd), off a watch
# check — or none, when nobody rolled: nobody on watch, or the Alarm spell
# that woke them whatever the dice said.
func _watch_roll(watch: Dictionary) -> Dictionary:
	if String(watch.get("char_id", "")) in ["", "alarm"]:
		return {}
	var out := {}
	for k in ["ok", "char_id", "cname", "skill", "nat", "bonus", "dc"]:
		if watch.has(k):
			out[k] = watch[k]
	return out

# The road's card over a paused map, `then` its ack. The camp's night wears
# it, and so do a calling's telling and resolution — those pictured by the
# background (assets/generated/event-calling-<background>.png) rather than
# by the night, since a calling is the hero's, not the camp's.
func _card(e: Dictionary, then: Callable) -> void:
	world.clock.pause()
	_pause_btn.text = "Resume"
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(then)
	_event_card.show_event(e)

# spike-party-opinions §9 row 6: the fire after a long rest. One beat, half the
# nights (core/party_opinion.gd's camp_moment): a warming or a quarrel, already
# resolved, on the night's card in place of the plain one — or a courtship,
# the one beat in the game that ASKS, and it asks on the approach card the way
# a landmark does, so nothing is applied until the player answers. Returns
# false when the fire has nothing to say and the caller shows its own night.
# `then` is the outcome card's ack: the camp's resumes the clock, the inn's
# leaves it to the visit. `bench` is the inn's and the lodge's: under a roof the
# benched are at the same fire, and can be the pair (the audit's §2.4b).
func _fireside(rng: RNG, then: Callable, bench := false) -> bool:
	# A calling outranks a warming: the telling first, once per hero, ever —
	# beat() marks the target as it speaks, and the map's layers re-read
	# found/discovered every frame, so the mark is on the map under the card.
	# Then a resolution the road could not show (the inn's: done at this very
	# gate, and the visit is still up), then the moment. One card a night.
	# The dead before any of it (audit 2.1): the first fire after a death
	# speaks of them, once — a mourner's line when one is at the fire, the
	# company's when nobody there was close to them.
	var fb: Dictionary = Fallen.camp_beat(party, world.clock.elapsed)
	if not fb.is_empty():
		_camp_card("fallen", "At the fire", "bad", String(fb["text"]), then, "camp-night")
		return true
	var b: Dictionary = Callings.beat(party, world)
	if not b.is_empty():
		_card({"id": "calling-" + String(b["id"]), "title": String(b["title"]), "kind": "good", "ok": true,
			"text": String(b["text"])}, then)
		return true
	if not _calling_queue.is_empty():
		var q: Array = _calling_queue.pop_front()
		_calling_done(String(q[0]), q[1], then)
		return true
	# #176 step 4: a trait somebody earned since the last fire, said once —
	# "Pike sits well back from the fire tonight, and doesn't eat."
	var tb: Dictionary = Traits.camp_beat(party.party_characters(), world.clock.elapsed)
	if not tb.is_empty():
		_camp_card("fireside", "At the fire", String(tb["kind"]), String(tb["text"]), then, "camp-night")
		return true
	var m: Dictionary = PartyOpinion.camp_moment(party, rng, bench)
	if m.is_empty():
		return false
	var kind := String(m["kind"])
	if kind != "courtship":
		_camp_card("fireside", "At the fire", "bad" if kind == "quarrel" else "good", String(m["text"]), then, "camp-night")
		return true
	world.clock.pause()
	_pause_btn.text = "Resume"
	_approach_card = ApproachCard.new()
	_approach_card.caption = "A T   T H E   F I R E"
	_approach_card.glyph = "♥"
	# The line is the hint, not the title: the title wraps twice at headline
	# size and the line is a sentence, so it would lose its second half.
	_approach_card.hint = String(m["text"]).trim_suffix(".")
	_approach_card.art_stem = "camp-night"
	add_child(_approach_card)
	_approach_card.chosen.connect(_on_courtship_chosen.bind(String(m["a"]), String(m["b"]), then))
	_approach_card.show_approach([
		{"id": "accept", "label": "Say yes", "dc": 0,
			"win": "Lovers, and %d warmer for it." % int(PartyOpinion.COURTSHIP_ACCEPTED)},
		{"id": "decline", "label": "Let it lie", "dc": 0,
			"lose": "Awkward around the fire for a while (-%d), and never asked again." % int(PartyOpinion.COURTSHIP_DECLINED)}],
		"%s and %s" % [String(m["a_name"]), String(m["b_name"])])
	return true

# The answer. answer_courtship applies it and says nothing, so the line is
# this file's; `a` asked, `b` was asked.
func _on_courtship_chosen(id: String, a: String, b: String, then: Callable) -> void:
	_close_approach()
	var accepted := id == "accept"
	PartyOpinion.answer_courtship(party, a, b, accepted)
	var an: String = party.get_member(a).cname
	var bn: String = party.get_member(b).cname
	var line := ("%s and %s come back to the fire together. Nobody says anything, and everybody knows." % [an, bn]) if accepted \
		else "%s lets it lie, as kindly as it can be done. It is awkward around the fire for a while." % bn
	_camp_card("courtship", "At the fire", "good" if accepted else "bad", line, then, "camp-night")

# O9 item 4 / T9x quest board: `q` is the exact offer row the player clicked
# (the board can show several at once now), not re-rolled here.
func _take_quest(q: Dictionary) -> void:
	if not Quest.accept(party, q, world.clock.elapsed):
		_say("No work here just now.")
		return
	Sound.play_sfx("quest")
	# D7: being told where it is IS the job. A lair the party has not found yet
	# (core/world_lairs.gd's Survival check, D5's bought leads) does not draw on
	# the map, so a clear_lair job about one used to be a contract with no way to
	# reach the thing it named.
	var note := ""
	if String(q["kind"]) in ["clear_lair", "rescue"]:
		for l in world.lairs:
			if l.id == String(q.get("target_lair_id", "")) and not l.discovered:
				l.discovered = true
				note = "  They mark %s on your map." % l.sname
	_build_visit_panel()
	_say("Job taken: %s%s" % [q["title"], note])

func _turn_in(quest: Dictionary) -> void:
	var reward: int = int(quest.get("reward", {}).get("gold", 0))
	if Quest.turn_in(party, quest, _visit["settlement"].faction):
		Sound.play_sfx("buy")
		Sound.play_sting("music_deed")
		# D5: a job well done is how a town decides you are worth telling things
		# to. The board's second payout, and the one that is not gold.
		var lead: Dictionary = Rumors.free_lead(_visit["settlement"], party, world)
		_build_visit_panel()
		var who := String(quest.get("issuer", _visit["settlement"].faction))
		_say("%s — paid, +%d ◉, +%d XP. The %s will remember it.%s" % [
			quest["title"], reward, Quest.xp_reward(quest), Ladder.people(who),
			("  " + String(lead["text"])) if not lead.is_empty() else ""])
		_autosave()

# The panel is rebuilt after every action, so the last line has to live on the
# visit rather than on the Label that just got freed (and a line said before
# the panel is built — _open_visit's — finds the last visit's Label gone).
func _say(text: String) -> void:
	BugReport.note(text)
	if not _visit.is_empty():
		_visit["log"] = text
	if is_instance_valid(_visit_log):
		_visit_log.text = text

# Live rolls in town (scenes/dice_roll.gd): the action has already happened —
# core/ rolled it and moved the gold — and this is the telling. The die rolls
# in a popup over the darkened page (the owner: "a dice popup in shop screen
# rather than moving the elements in the shop page" — it first rolled inline,
# in the line's place, and the page jumped under it; see _dice_popup). The
# panel's buttons wait, and when it lands the popup goes, the line is said,
# the success sting plays and `then` runs (a card that would otherwise give the roll away before it
# landed). A result with no roll, and every run under SORCMERC_FAST, says it
# at once, exactly as _say always did.
var _visit_dice: Control = null
var _visit_die_popup: Control = null
var _visit_pending: Dictionary = {}

func _say_rolled(r: Dictionary, text: String, sfx := "", then := Callable()) -> void:
	if not r.has("nat") or Settings.anim() >= Settings.FAST or not is_instance_valid(_visit_log):
		if sfx != "" and bool(r.get("ok", false)):
			Sound.play_sfx(sfx)
		_say(text)
		if then.is_valid():
			then.call()
		return
	_visit_pending = {"text": text, "sfx": sfx, "then": then, "ok": bool(r.get("ok", false))}
	_say("")
	var pop: Array = _dice_popup(true)
	var overlay: Control = pop[0]
	var d = pop[1]
	_visit_die_popup = overlay
	_visit_dice = d
	if is_instance_valid(_visit_panel):
		_disable_all(_visit_panel)   # one thing at a time: the room is watching the dice
	d.landed.connect(_visit_landed)
	var skill := String(r.get("skill", ""))
	d.play({"nat": int(r.get("nat", 1)), "bonus": int(r.get("bonus", 0)), "dc": int(r.get("dc", 10)),
		"ok": bool(r.get("ok", false)), "dice": r.get("dice", []), "mode": String(r.get("mode", "")),
		"label": "%s — %s" % [String(Catalog.skills().get(skill, {}).get("name", skill.capitalize())),
			String(r.get("cname", ""))]})

# The town's live-roll popup: no frame and no panel of its own — the whole
# screen darkened, and only the die and its tally left bright in the middle
# (the owner: "no background color, only darken everything except the dice and
# result"). `block`: the overlay takes every click, so a click anywhere lands
# the die and none reaches a button under it (the map's die is its own thing —
# see _map_roll). Returns [overlay, die]; the caller frees the overlay.
const DICE_DIM := 0.7

func _dice_popup(block: bool) -> Array:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, DICE_DIM)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(centre)
	var d = DiceRoll.new()
	d.custom_minimum_size = Vector2(560, DiceRoll.HEIGHT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d.tooltip_text = "Click to land it"
	centre.add_child(d)
	var land := func(e):
		if e is InputEventMouseButton and e.pressed:
			d.finish()
	d.gui_input.connect(land)
	if block:
		overlay.gui_input.connect(land)
	return [overlay, d]

# The map's own quick checks — a lair's or a landmark's search, sneaking past
# a lair, a forage on the march — report on the HUD bar, not on a card. Their
# die is not the town's popup: the owner, "in the campaign map, the background
# darkening shouldnt work, and the dice should be more to the bottom, popping
# up, showing the result, and disappearing after 2-3 seconds by fading". So it
# pops up over the map just above the HUD bar with nothing darkened, rolls, and
# the line (and its sting, and `then`) is said when it lands; the die stays up
# with its verdict for MAP_LINGER, then fades out on its own over MAP_FADE —
# about 2.5 s of result in all. Nothing here pauses the clock or takes the
# mouse — a forage rolls on the march, and a click on the map still marches;
# a click on the die lands it. One at a time — a second check lands the first
# and takes its place at once. SORCMERC_FAST says the line at once, as the HUD
# always did.
const MAP_POP := 0.25          # seconds at anim() == 1: up from the bottom
const MAP_LINGER := 0.9        # after `landed` (itself 0.9 s after the tally)...
const MAP_FADE := 0.6          # ...then gone
const MAP_BOTTOM := 64.0       # clear of the HUD bar

var _map_die: Control = null   # the die's box: what pops, fades and is freed
var _map_dice: Control = null  # the DiceRoll in it
var _map_pending: Dictionary = {}

func _map_roll(roll: Dictionary, label: Label, text: String, sfx := "", then := Callable()) -> void:
	_land_map_roll()
	if is_instance_valid(_map_die):
		_map_die.queue_free()   # a die still fading gives way to the new one
	_map_die = null
	_map_dice = null
	if not roll.has("nat") or Settings.anim() >= Settings.FAST:
		label.text = text
		if sfx != "":
			Sound.play_sfx(sfx)
		if then.is_valid():
			then.call()
		return
	label.text = ""
	var k := 1.0 / maxf(Settings.anim(), 0.01)
	var d = DiceRoll.new()
	d.drop_in = false
	d.size = Vector2(560, DiceRoll.HEIGHT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d.tooltip_text = "Click to land it"
	d.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			d.finish())
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = d.size
	box.position = Vector2((size.x - box.size.x) * 0.5, size.y - box.size.y - MAP_BOTTOM)
	box.pivot_offset = Vector2(box.size.x * 0.5, box.size.y)
	box.add_child(d)
	add_child(box)
	box.scale = Vector2(0.4, 0.4)
	box.modulate.a = 0.0
	var pop := box.create_tween().set_parallel()
	pop.tween_property(box, "scale", Vector2.ONE, MAP_POP * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(box, "modulate:a", 1.0, MAP_POP * 0.6 * k)
	_map_die = box
	_map_dice = d
	_map_pending = {"label": label, "text": text, "sfx": sfx, "then": then}
	d.landed.connect(_land_map_roll)
	var skill := String(roll.get("skill", "survival"))
	d.play({"nat": int(roll["nat"]), "bonus": int(roll.get("bonus", 0)), "dc": int(roll.get("dc", 10)),
		"ok": bool(roll.get("ok", false)), "dice": roll.get("dice", []), "mode": String(roll.get("mode", "")),
		"label": "%s — %s" % [String(Catalog.skills().get(skill, {}).get("name", skill.capitalize())),
			String(roll.get("cname", ""))]})

# The held line said, and the die left to linger and fade — on landing, or
# when another quick check comes along before this one has.
func _land_map_roll() -> void:
	if _map_pending.is_empty():
		return
	var p := _map_pending
	_map_pending = {}
	if is_instance_valid(_map_die):
		var box := _map_die
		var k := 1.0 / maxf(Settings.anim(), 0.01)
		var out := box.create_tween()
		out.tween_interval(MAP_LINGER * k)
		out.tween_property(box, "modulate:a", 0.0, MAP_FADE * k)
		out.tween_callback(box.queue_free)
	var label: Label = p["label"]
	if is_instance_valid(label):
		label.text = String(p["text"])
	if String(p["sfx"]) != "":
		Sound.play_sfx(String(p["sfx"]))
	var then: Callable = p["then"]
	if then.is_valid():
		then.call_deferred()

func _visit_landed() -> void:
	_flush_visit_roll()
	if not _visit.is_empty():
		_build_visit_panel()   # the buttons back, and the line the die was holding

# The held line said, its sting and its follow-up run, and the popup gone — on
# landing, or when anything rebuilds or closes the panel under a die still in
# the air (what it was about to say must not go with it).
func _flush_visit_roll() -> void:
	if _visit_pending.is_empty():
		return
	var p := _visit_pending
	_visit_pending = {}
	if is_instance_valid(_visit_dice) and _visit_dice.landed.is_connected(_visit_landed):
		_visit_dice.landed.disconnect(_visit_landed)
	_visit_dice = null
	if is_instance_valid(_visit_die_popup):
		_visit_die_popup.queue_free()
	_visit_die_popup = null
	BugReport.note(String(p["text"]))
	if not _visit.is_empty():
		_visit["log"] = String(p["text"])
	if String(p["sfx"]) != "" and bool(p["ok"]):
		Sound.play_sfx(String(p["sfx"]))
	var then: Callable = p["then"]
	if then.is_valid():
		then.call_deferred()

# T9x: a settlement is a set of separate screens now (town square / market /
# inn / notice board), not one panel with everything stacked in it — this is
# just the shell (frame, title, footer) and the page dispatch; each _build_*
# below only owns its own content between the title and the footer.
func _build_visit_panel() -> void:
	_flush_visit_roll()   # a die still in the air says its line before its panel goes
	if _visit_panel != null:
		_visit_panel.queue_free()
	# D7: a supply_item job's progress is a reading of the pack, not an event,
	# so it is re-read here — every buy, sell and turn-in rebuilds this panel,
	# which makes this the one place that cannot show a stale count.
	Quest.record_stash(party)
	var s = _visit["settlement"]
	# Issue #33: this used to place itself by arithmetic — half the screen minus
	# half the 460x460 it was told to expect — and then measure whatever its
	# content actually came to. A board with jobs on it comes to more than that
	# in both directions, so the panel sat off-centre and, on a short window,
	# hung off the bottom. A CenterContainer centres what it measures; the max
	# width keeps a long line wrapping inside the panel rather than widening it.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_visit_panel = centre
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(460, 460)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = VISIT_PANEL_W
	panel.add_child(box)

	var title := Label.new()
	title.text = "%s, %s" % [s.sname, String(PAGE_TITLES.get(_visit_page, "")).to_lower()]
	title.theme_type_variation = "Head"
	box.add_child(title)

	# #201: a page is as long as what the town has — a city's square with every
	# counter open, a lodge, a battlefield to pick over — and the lists inside a
	# page were the only part that scrolled. The page body scrolls as a whole
	# now, capped at what the window has left, so Leave is always on screen.
	#
	# #228: except a page whose head is the part you read and whose list is the
	# part you work through — the inn (the bed, who is hurt) and the lodge (the
	# house's bed). Scrolled as a whole, the inn's head went up and out of sight
	# with the list, and the list scrolled again inside it: two scrollbars, one
	# inside the other. On those pages the head is pinned, and the one list under
	# it takes whatever height the window has left (_fit_visit_list).
	var pinned: bool = _visit_page in PINNED_PAGES
	_visit_list = null
	var body_scroll: ScrollContainer = null
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if pinned:
		body.custom_minimum_size.x = VISIT_PANEL_W
		box.add_child(body)
	else:
		body_scroll = ScrollContainer.new()
		body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_scroll.custom_minimum_size = Vector2(VISIT_PANEL_W, _visit_body_h)
		body_scroll.add_child(body)
		box.add_child(body_scroll)
	match _visit_page:
		"market": _build_market_page(body, s)
		"inn": _build_inn_page(body, s)
		"board": _build_board_page(body, s)
		"lodge": _build_lodge_page(body, s)
		_: _build_hub_page(body, s)
	if body_scroll != null:
		_fit_visit_body(body_scroll, body)
	elif _visit_list != null:
		_fit_visit_list(_visit_list, body)

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
	if spectator:
		_disable_all(centre)   # the guest reads the counter; the host runs it
	else:
		_coop_share_visit()

static func _disable_all(n: Node) -> void:
	for c in n.get_children():
		if c is Button:
			c.disabled = true
		_disable_all(c)

# How this settlement's people feel about the party, in a phrase: the faction
# opinion the prices and the gate already read, said once where it can be read.
func _standing_line(s) -> String:
	var op: float = FactionOpinion.get_opinion(s.faction)
	if FactionOpinion.guards_attack(s.faction):
		return "The guards would sooner fight you than let you in."
	if FactionOpinion.refuses_trade(s.faction):
		return "Nobody here will deal with you."
	# The ladder (core/ladder.gd): what the party has DONE here outranks how
	# they feel this week — unless the guards are already out.
	var tail := ""   # the fourth title (Asked For by Name) or better rides on the end of every line
	if Ladder.title_index() >= 3:
		tail = "  %s, they say." % Ladder.title_cap()
	match Ladder.rung(s.faction):
		Ladder.SWORN: return "Sworn to this people. Their doors are yours." + tail
		Ladder.TRUSTED: return "Trusted here — the back room is open to you." + tail
		Ladder.KNOWN: return "Known here — they will pass you a neighbour's work." + tail
	if op >= FactionOpinion.QUEST_GENEROUS:
		return "They are glad to see you — there is work here for the asking." + tail
	if op >= FactionOpinion.QUEST_DONE:
		return "They think well of you." + tail
	if op <= FactionOpinion.HOSTILE:
		return "Their bands hunt you on the road; the gate is open, barely." + tail
	if op <= FactionOpinion.QUEST_MIN:
		return "They have heard things. No work for you here." + tail
	return "Strangers here, for now." + tail

# The settlement panel's column width. Every list inside it is sized against
# this, so one long job title wraps instead of widening the whole counter.
const VISIT_PANEL_W := 440.0
# How much of the panel is not the list: title, mood line, portrait, the log
# line and the buttons under it. A page's list gets what the window has left
# after that, so a short window trims the list instead of running the whole
# counter off the bottom of the screen (issue #33).
const VISIT_CHROME_H := 320.0

func _page_scroll_h(want: float) -> float:
	return clampf(size.y - VISIT_CHROME_H, 120.0, want)

# What the settlement panel keeps for itself around the page body: the title
# above it, the log line and the Leave bar below, and the panel's own margins.
const VISIT_BODY_CHROME_H := 170.0
# The body's last fitted height. A page is rebuilt on every click, so starting
# the new one at the old one's height keeps the panel from jumping a frame.
var _visit_body_h := 360.0

# A container cannot measure an autowrapped label before it has a width, so the
# body is fitted a frame after it is built: as tall as its content, and never
# taller than the window can show.
func _fit_visit_body(body_scroll: ScrollContainer, body: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(body_scroll) or not is_instance_valid(body):
		return
	var cap: float = maxf(160.0, size.y - VISIT_BODY_CHROME_H)
	_visit_body_h = minf(body.get_combined_minimum_size().y, cap)
	body_scroll.custom_minimum_size.y = _visit_body_h

# #228: the pages whose head stays put while the list under it scrolls.
const PINNED_PAGES := ["inn", "lodge"]
# The list a pinned page scrolls ("Looking for work" and everything under it,
# at the inn), set by the page's builder; null on every other page.
var _visit_list: ScrollContainer = null
# The shortest the list gets under a head too tall for the window: a few rows
# still show, and the panel runs past the bottom rather than the list
# vanishing. A guard, not a case the game meets: the project stretches the
# canvas to "expand" from 1280x800, so the screen is never under 800 high,
# and the inn's head is about 430 of the 630 that leaves the body.
const VISIT_LIST_MIN_H := 150.0
# The list's last fitted height, and where it was scrolled to, by page. A page
# is rebuilt on every click, and every rebuild used to throw the list back to
# its top: a row pressed far down it (a night on the town, #237) answered from
# a list that had jumped away from under the pointer. Cleared on changing page
# and on opening a visit, so a new page starts at its top.
var _visit_list_h := 300.0
var _visit_list_v := {}

# The pinned page's list, fitted the frame after it is built (a wrapped label
# has no height before then): whatever the window leaves under the head, and
# no taller than the list itself. Then scrolled back to where it was.
func _fit_visit_list(scroll: ScrollContainer, body: Control) -> void:
	var page := _visit_page
	var keep: float = float(_visit_list_v.get(page, 0.0))   # read before the new bar can report its own 0
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not is_instance_valid(body):
		return
	var cap: float = maxf(160.0, size.y - VISIT_BODY_CHROME_H)
	var head: float = body.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	var content: float = (scroll.get_child(0) as Control).get_combined_minimum_size().y
	_visit_list_h = maxf(minf(content, cap - head), minf(content, VISIT_LIST_MIN_H))
	scroll.custom_minimum_size.y = _visit_list_h
	if keep > 0.0:
		await get_tree().process_frame   # the bar's range is the new height's only after a layout
		if not is_instance_valid(scroll):
			return
		scroll.scroll_vertical = int(keep)
	scroll.get_v_scroll_bar().value_changed.connect(func(v: float): _visit_list_v[page] = v)

const PAGE_TITLES := {"hub": "Town Square", "market": "Market", "inn": "Inn", "board": "Notice Board", "lodge": "Your Lodge"}

# The town square: where to go, plus the one thing that belongs to no single
# building — picking over a battlefield nearby.
# T9y: every door now says what is behind it before you open it. The split
# into separate screens (34300bb) left the hub with three unlabelled buttons,
# so the only way to find out whether the board had work — or whether the
# shelves were bare — was to walk in and look. All three counts are read off
# state the page already had to compute anyway.
func _build_hub_page(box: VBoxContainer, s) -> void:
	# The place in a line before the doors: what it is, whose, and how they
	# feel about you — the square used to open on the purse and nothing else.
	var where := Label.new()
	where.text = "%s %s.  %s" % [String(s.faction).capitalize(), s.kind, _standing_line(s)]
	where.theme_type_variation = "Serif"
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_theme_color_override("font_color", Icons.COL_BODY)
	box.add_child(where)
	var mood := Label.new()
	mood.text = "%s%s%d ◉ in the purse." % [
		"Fighting nearby. " if _visit.get("battle", false) else "",
		"They will not trade with you. " if _visit.get("refused", false) else "",
		party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var places := VBoxContainer.new()
	box.add_child(places)
	# D7: jobs are split across the counters now, so each door has to carry its
	# own count — otherwise the smith's standing order is a thing you find only
	# by opening every tab.
	var jobs: Dictionary = _counter_offers(s)
	var counter_jobs := 0
	for key in jobs:
		if key != "board":
			counter_jobs += jobs[key].size()
	var wanted := ""
	if counter_jobs == 1:
		wanted = ",  one counter wants something fetched"
	elif counter_jobs > 1:
		wanted = ",  %d counters want something fetched" % counter_jobs
	var stock: Array = _visit.get("stock", [])
	var market_btn := Button.new()
	market_btn.text = ("Market.  They will not trade with you" if _visit.get("refused", false)
		else "Market.  %d on the shelves%s" % [stock.size(), wanted])
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
	var cost := Visit.inn_cost(s, party)
	inn_btn.text = (("Inn.  On the house." if cost == 0 else "Inn.  A night is %d ◉" % cost) if wait <= 0.0
		else "Inn.  Rested recently, a room does nothing for %s yet" % _hours(wait))
	# The door has to say there are people behind it: on a new run the inn is
	# the only place the company grows (core/recruits.gd).
	var looking: int = Recruits.offers(s, world, party).size()
	if looking > 0:
		inn_btn.text += ",  %d looking for work" % looking
	inn_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	inn_btn.pressed.connect(_goto_page.bind("inn"))
	places.add_child(inn_btn)
	if Posting.is_patron(s, world) and Ladder.rung(s.faction) >= Ladder.SWORN and not Ladder.audience_held(s.faction):
		var aud_btn := Button.new()
		aud_btn.text = "Seek an audience with the lord"
		aud_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		aud_btn.pressed.connect(_audience_action)
		places.add_child(aud_btn)

	var board_btn := Button.new()
	var offers: int = jobs.get("board", []).size()
	var ready: int = Visit.turn_ins(party).size()
	board_btn.text = ("Notice Board.  Nothing posted" if offers == 0 and ready == 0
		else "Notice Board.  %d posted, %d ready to turn in" % [offers, ready])
	board_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	board_btn.pressed.connect(_goto_page.bind("board"))
	places.add_child(board_btn)

	# The lodge (core/lodge.gd): the company's own door once it has one here, a
	# house for sale where the town knows the company (the price shown and the
	# button disabled while the purse is short — a shrug is the e3cc910 bug),
	# and at any other town a line pointing home.
	if Lodge.at(party, s):
		var lodge_btn := Button.new()
		var n: int = Lodge.rooms_built(party)
		lodge_btn.text = "Your lodge.  %s" % ("The house alone" if n == 0
			else "Every room built" if n == Lodge.ROOMS.size() else "The house and %d room%s" % [n, "" if n == 1 else "s"])
		lodge_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lodge_btn.pressed.connect(_goto_page.bind("lodge"))
		places.add_child(lodge_btn)
	elif Lodge.for_sale(party, s):
		var buy_btn := Button.new()
		buy_btn.text = "Buy a lodge here (%d ◉)" % Lodge.HOUSE_COST
		buy_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buy_btn.disabled = not Lodge.can_buy(party, world, s)
		buy_btn.pressed.connect(_buy_lodge)
		places.add_child(buy_btn)
	elif not party.lodge.is_empty():
		var home = Lodge.settlement(party, world)
		if home != null:
			_note(places, "The company's lodge is at %s." % home.sname)

	if _visit.get("battle", false):
		var investigate_btn := Button.new()
		var investigated: bool = _visit.get("investigated", false)
		investigate_btn.text = "Investigated the battlefield" if investigated else "Investigate the battlefield"
		investigate_btn.disabled = investigated
		investigate_btn.tooltip_text = Visit.check_preview(party, Visit.INVESTIGATE_SKILL, Visit.INVESTIGATE_DC)   # #87
		investigate_btn.pressed.connect(_investigate)
		places.add_child(investigate_btn)

# The audience: once per people, at its chief settlement, for a Sworn company.
# A rare item and a milestone's worth of XP, on the event card, art
# event-audience-<faction>.
const AUDIENCE_XP := 200

func _audience_action() -> void:
	var s = _visit.get("settlement")
	if s == null or Ladder.audience_held(s.faction):
		return
	var pool: Array = Loot.items_of_rarity("rare")
	var gift := String(pool[absi(hash("audience|%s" % s.faction)) % pool.size()]) if not pool.is_empty() else ""
	if gift != "":
		party.stash_add(gift)
		Campaign._note_rarity(gift)
	Campaign.split_xp(party, AUDIENCE_XP)
	Ladder.hold_audience(s.faction)
	Ach.collect("audiences", s.faction)
	_calling_check("audience", s.faction, _leader())   # shown after the audience's own card
	var e := {"id": "audience-%s" % s.faction, "title": "An audience with the lord", "kind": "good", "ok": true,
		"text": "The hall is cleared for you. The lord speaks of what the company has done for %s's people, and of what a lord owes such a company." % String(s.faction).capitalize(),
		"xp": AUDIENCE_XP, "thanks": s.sname}
	if gift != "":
		e["item"] = gift
		e["item_name"] = Campaign.item_name(gift)
	_close_visit()   # autosaves, and resumes the clock — which the card stops again
	world.clock.pause()
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event(e)

# T9y: one counter at a time. T25 sizes a settlement's specialists and the
# hub line names them, but the shelf itself was one alphabetical list with no
# hint of who was selling what — and the two services that stock no goods
# (Healer, Librarian) had nowhere to exist at all, so a city's own services
# line was advertising people the player could never talk to. A tab strip
# across the top picks the counter, opening on the first one; the old "All"
# list survives only as the fallback for a place with no counters.
func _build_market_page(box: VBoxContainer, s) -> void:
	var mood := Label.new()
	mood.text = "Shelves %d of %d, prices x%.2f%s.  %d ◉ in the purse." % [
		_visit["steps"], Visit.MAX_STEPS, _visit["markup"],
		"  (they will not trade with you)" if _visit.get("refused", false) else "",
		party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var groups: Dictionary = Visit.stock_by_service(s, _visit)
	if _market_tab == "backroom" and not groups.has("backroom"):
		_market_tab = _first_counter()   # the last back-room item bought: the tab is gone with it
	# D7: each specialist posts its own order, and it hangs at its own counter.
	var jobs: Dictionary = _counter_offers(s)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for t in _visit["services"]:
		var name_of: String = String(Campaign.SERVICE_NAMES.get(t, t))
		# Innkeeper is the quest-giver role (see campaign.gd's SERVICE_ORDER
		# comment); its counter is the Notice Board, not a stall here.
		if t == "innkeeper":
			continue
		var btn := Button.new()
		btn.text = name_of
		btn.disabled = (_market_tab == t)   # the open tab, shown as pressed rather than as a live button
		btn.pressed.connect(_goto_market_tab.bind(String(t)))
		tabs.add_child(btn)
	# The back room (core/ladder.gd's Trusted door): the smith's own tab, after
	# the counters the town advertises.
	var counters: Array = _visit["services"].filter(func(x): return x != "innkeeper")
	if groups.has("backroom"):
		var back := Button.new()
		back.text = "Back room"
		back.disabled = (_market_tab == "backroom")
		back.pressed.connect(_goto_market_tab.bind("backroom"))
		tabs.add_child(back)
		counters.append("backroom")
	if _market_tab != MARKET_TAB_ALL:
		_portrait(box, s.faction, ("armorsmith" if Visit.has_service(s, "armorsmith") else "weaponsmith") if _market_tab == "backroom" else _market_tab)

	var scroll := _scroll_column(Vector2(VISIT_PANEL_W, _page_scroll_h(250.0)))
	box.add_child(scroll)
	var rows: VBoxContainer = scroll.get_child(0)
	var showing_all: bool = _market_tab == MARKET_TAB_ALL
	for service in counters:
		if not showing_all and _market_tab != service:
			continue
		var shelf: Array = groups.get(service, [])
		var posted: Array = jobs.get(service, [])
		var actions: bool = service in ["healer", "librarian"]
		if shelf.is_empty() and posted.is_empty() and not actions:
			continue
		if showing_all or service == "backroom":
			_section(rows, "The back room" if service == "backroom" else String(Campaign.SERVICE_NAMES.get(service, service)))
		# T9a: a shelf is a row of pictures; the name, numbers and prose are
		# the hover text, the price the caption, the click the purchase.
		var shelf_grid := _item_grid(rows)
		for e in shelf:
			var iid := String(e["item_id"])
			var kd: Array = Icons.item_def(iid)
			var tile := Icons.item_tile(iid, Icons.item_tooltip(iid, kd[1], kd[0])
				+ "\n\nClick: buy for %d ◉" % int(e["price"]), "%d ◉" % int(e["price"]),
				Icons.ITEM_ART_PX, Icons.party_compare(kd[0], party, kd[1]))
			tile.pressed.connect(_buy.bind(iid))
			shelf_grid.add_child(tile)
		for offer in posted:
			_job_row(rows, offer)
		if service == "healer":
			_trade_row(rows, "Patch up the whole party — %d ◉ (no rest, no waiting)" % Visit.HEAL_COST,
				"Heal", _heal)
			for ch in party.roster:   # #109
				if ch.dead:
					_trade_row(rows, "Raise %s from the dead — %d ◉" % [ch.cname, Party.revive_cost(ch)],
						"Raise", _raise_dead.bind(ch.id), party.gold < Party.revive_cost(ch))
			if Visit.can_work_healer(party):
				var worked: bool = _visit.get("worked", false)
				_trade_row(rows, "Work a shift in the ward — your restoration spell opens the door, Medicine sets the wage",
					"Done" if worked else "Work", _work_healer, worked)
		elif service == "librarian":
			var mystery: Array = party.unidentified()
			if mystery.is_empty():
				_note(rows, "Nothing in the pack needs identifying.")
			for entry in mystery:
				var mid := String(entry["item_id"])
				_trade_row(rows, "Identify the unknown %s — %d ◉" % [
					Campaign.item_name(mid), Visit.IDENTIFY_COST], "Identify", _identify.bind(mid))
			for iid in Downtime.scribable(s, _visit, party):
				_craft_row(rows, "Scribe", iid, s)
		elif service == "alchemist":
			for iid in Downtime.brewable(s, _visit):
				_craft_row(rows, "Brew", iid, s)
	# The generalist's own counter also outfits you: the camp kit is a flat
	# price and never runs out, so it is not part of the T25 shelf/restock
	# catalog (T9x) and gets its own row rather than a fake catalog entry.
	if showing_all or _market_tab == "generalist":
		_trade_row(rows, "%s — %d ◉ (lets you long-rest away from a settlement)" % [
			WorldCamp.CAMP_KIT_NAME, WorldCamp.CAMP_KIT_PRICE], "Buy", _buy_camp_kit)
	# Selling is not a counter — whoever is behind it takes the whole pack —
	# so it stays out of the tabs and sits under everything, on every tab.
	var pack: GridContainer = null
	for entry in party.stash:
		var id := String(entry["item_id"])
		var paid := Visit.sell_price(_visit, id, party)
		if paid <= 0:
			continue
		if pack == null:
			_section(rows, "Your pack")
			pack = _item_grid(rows)
		var kd: Array = Icons.item_def(id)
		var tip: String = ("Unidentified item (%s)" % Icons.rarity_of(id) if not Party.is_identified(entry)
			else Icons.item_tooltip(id, kd[1], kd[0]))
		var qty := int(entry["quantity"])
		var tile := Icons.item_tile(id, tip + "\n\nClick: sell one for %d ◉" % paid,
			"%d ◉" % paid,
			Icons.ITEM_ART_PX, Icons.party_compare(kd[0], party, kd[1]) if Party.is_identified(entry) else "", qty)
		tile.pressed.connect(_sell.bind(id))
		pack.add_child(tile)

	var bar := HBoxContainer.new()
	box.add_child(bar)
	var steal_btn := Button.new()
	var wait: float = Visit.steal_wait(_visit["settlement"], world)
	var spent: bool = _visit.get("stolen", false) or wait > 0.0
	steal_btn.text = ("Stall watched — %dh" % maxi(1, ceili(wait / 60.0))) if wait > 0.0 else "Steal from the market"
	steal_btn.disabled = spent
	steal_btn.tooltip_text = Visit.check_preview(party, Visit.STEAL_SKILL, Visit.STEAL_DC)   # #87
	steal_btn.pressed.connect(_steal)
	bar.add_child(steal_btn)
	if _visit.get("refused", false):
		var persuade_btn := Button.new()
		var persuaded: bool = _visit.get("persuaded", false)
		persuade_btn.text = "Tried persuasion" if persuaded else "Persuade them to trade"
		persuade_btn.disabled = persuaded
		persuade_btn.tooltip_text = Visit.check_preview(party, Visit.PERSUADE_SKILL, Visit.persuade_dc(_visit), _talk_adv())
		persuade_btn.pressed.connect(_persuade)
		bar.add_child(persuade_btn)
	else:
		# T9x: haggle only makes sense on a market that's actually open —
		# persuade (above) is what opens a refused one in the first place.
		var haggle_btn := Button.new()
		var haggled: bool = _visit.get("haggled", false)
		haggle_btn.text = "Haggled already" if haggled else "Haggle over prices (Persuasion)"
		haggle_btn.disabled = haggled
		haggle_btn.tooltip_text = Visit.check_preview(party, Visit.HAGGLE_SKILL, Visit.HAGGLE_DC, _talk_adv())
		haggle_btn.pressed.connect(_haggle)
		bar.add_child(haggle_btn)

# The bench and the desk (core/downtime.gd): half list price, a day, once per
# item per visit — spent, the row says Done the way the ward's shift does.
func _craft_row(rows: VBoxContainer, verb: String, item_id: String, s) -> void:
	var can: bool = Downtime.can_craft(party, s, item_id)
	_trade_row(rows, "%s %s (%d ◉, a day)" % [verb, Campaign.item_name(item_id), Downtime.craft_cost(item_id)],
		verb if can else "Done", _craft.bind(item_id), not can)

# T9y: the inn was one button and a purse. Resting is the one action here
# whose whole value is the state it changes, so the page now shows that state:
# who is hurt, what a night costs, and — when the once-a-day cooldown says no
# — how long until it says yes. A disabled button with a number beside it is
# an answer; a button that shrugs is the silent-no-op bug again (e3cc910).
func _build_inn_page(box: VBoxContainer, s) -> void:
	var cost := Visit.inn_cost(s, party)
	var mood := Label.new()
	mood.text = "A %s bed is %s a night.  %d ◉ in the purse." % [s.kind, "on the house" if cost == 0 else "%d ◉" % cost, party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)

	var room := Icons.scene_art("inn-" + String(s.faction), null)
	if room != null:
		var pic := TextureRect.new()
		pic.texture = room
		pic.custom_minimum_size = Vector2(440, 160)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.clip_contents = true
		box.add_child(pic)
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

	# Issue #27: the one place a party reshuffles itself. Out on the road the
	# party screen opens with its roster half locked; here it opens unlocked,
	# because this is where the people who might join you are.
	var manage := Button.new()
	manage.text = "Sort out the party (bench, recruit, marching order)"
	manage.pressed.connect(func(): _open_party(true))
	box.add_child(manage)
	if party.roster.size() <= Party.MAX_ACTIVE:
		_note(box, "Everyone you have is marching. New faces are hired here, from whoever is looking for work." if Recruits.hire_only(party)
			else "Everyone you have is marching. New faces are made here too, or hired from whoever is looking for work.")

	var wait: float = Visit.long_rest_in(party, world)
	var rest_btn := Button.new()
	rest_btn.text = "Rest the night (%s)" % ("on the house" if cost == 0 else "%d ◉" % cost)
	rest_btn.disabled = wait > 0.0 or party.gold < cost
	rest_btn.pressed.connect(_rest)
	box.add_child(rest_btn)
	if wait > 0.0:
		_note(box, "They rested less than a day ago — another night does nothing for %s." % _hours(wait))
		# The healer is the paid way past this wall, and only a settlement that
		# has one can offer it: say so where the player hits the wall, not only
		# on the counter they would have to guess to open.
		if Visit.has_service(s, "healer"):
			_note(box, "The healer will patch everyone up regardless, for %d ◉." % Visit.HEAL_COST)
	elif party.gold < cost:
		_note(box, "Not enough gold for a room.")
	else:
		_note(box, "Eight hours: everyone back to full, spells and abilities back, and the stalls restock while you sleep.")

	# Under the bed, one scrolling list: the things that take days
	# (core/downtime.gd — the trainer, a night out, a game, at a city the pit),
	# and D5's rumours, the other half of what an inn is for. Until D5 a lair
	# was found by walking close enough to one you had no reason to think
	# existed — discovery by collision. This is where you hear about it
	# instead, which is what makes a town worth walking back to. Five rumours
	# under the art and the table ran the panel off the bottom of a 900 px
	# screen before the Downtime rows came, so the list scrolls — and since #228
	# it is the only thing on the page that does: everything above "Looking for
	# work" stays put, and the list takes the height the window has left
	# (_fit_visit_list; PINNED_PAGES).
	var scroll := _scroll_column(Vector2(VISIT_PANEL_W, _visit_list_h))
	box.add_child(scroll)
	_visit_list = scroll
	var list: VBoxContainer = scroll.get_child(0)   # `rows` is the party-status list above
	_hiring_rows(list, s)
	_section(list, "Downtime")
	_downtime_rows(list, s)
	var leads: Array = Rumors.offers(s, world)
	_section(list, "Word in the common room")
	if leads.is_empty():
		_note(list, "Nothing anybody here has not already told you.")
	for lead in leads:
		_trade_row(list, String(lead["text"]), "Buy  %d ◉" % int(lead["price"]), _buy_rumor.bind(lead),
			false, null, String(lead.get("where", "")))

# --- Looking for work (core/recruits.gd): today's common room ----------------
# One row per chair: who they are in a line, what they are like under it, and
# the fee on the button. A row the company cannot take says why in its second
# line — the roster is full for a company of this name, or the purse is short —
# rather than greying a button and leaving the player to guess.
func _hiring_rows(rows: VBoxContainer, s) -> void:
	_section(rows, "Looking for work")
	var offers: Array = Recruits.offers(s, world, party)
	if offers.is_empty():
		_note(rows, "Nobody here will sign with a company this town will not deal with." if FactionOpinion.refuses_trade(s.faction)
			else "Nobody else here is looking for work today.")
		return
	for offer in offers:
		var ch = Recruits.build(offer)
		if ch == null:
			continue
		var why: String = Recruits.why_not(party, offer)
		var vet: bool = String(offer["veteran"]) != ""
		var what := "%s, %s %s %d%s" % [ch.cname, ChoicePick.humanize(ch.species_id).to_lower(),
			ChoicePick.humanize(ch.class_id()).to_lower(), ch.level(), "  (a veteran)" if vet else ""]
		var traits: Array = Traits.ids(ch).map(func(t): return Traits.name_of(t).to_lower())
		# Audit 2.5: who they are in a line (Recruits.intro), and for a veteran
		# what they did in the runs before this one (Service.veteran_line),
		# over the background and traits — or the reason they cannot sign.
		var lines: Array = [Recruits.intro(ch)]
		if vet:
			lines.append(Service.veteran_line(ch))
		lines.append(why if why != "" else "%s background%s" % [ChoicePick.humanize(ch.background_id),
			", " + ", ".join(traits) if not traits.is_empty() else ""])
		var sub := "\n".join(lines.filter(func(l): return String(l) != ""))
		_trade_row(rows, what, "Take them on (%d ◉)" % int(offer["fee"]), _open_settle_in.bind(s, offer),
			why != "", null, sub)

# The settle-in page (scenes/creator/levelup.gd's recruit mode): the choices the
# hire leaves to the company, then the fee. It sits where the party screen does
# over the counter — in _party_overlay, so Esc and every "is something up"
# guard already treat it as the full-screen page it is — and Cancel hires nobody.
func _open_settle_in(s, offer: Dictionary) -> void:
	if _party_overlay != null or spectator:
		return
	var ch = Recruits.build(offer)
	if ch == null:
		_say("They have gone.")
		_build_visit_panel()
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_party_overlay = overlay
	var page = load(LEVELUP_SCENE).instantiate()
	overlay.add_child(page)
	page.hire_check = func() -> String: return Recruits.hire(party, world, s, offer, ch)
	page.set_recruit(ch, int(offer["fee"]))
	page.finished.connect(func(hired: bool):
		_close_party()
		if hired:
			_say("%s signs on, for %d ◉." % [ch.cname, int(offer["fee"])])
			_autosave()
		_build_visit_panel())

# --- Downtime (core/downtime.gd): the rows in town that take days ------------
# The trainer, the night out, the game, and at a city the pit. The purse, the
# days and the roll are the module's; this is the picker. Every result is the
# line under the row (_downtime_done) and, when the night went wrong, a card
# (_complicate).
func _downtime_rows(rows: VBoxContainer, s) -> void:
	# A hero with no feat left the trainer can finish is not offered: their row
	# was an empty picker beside a Go that answered "will not take them".
	var pupils: Array = party.party_characters().filter(
		func(ch): return Downtime.can_train(party, ch) and not Downtime.trainable(ch).is_empty())
	if not pupils.is_empty():
		_train_row(rows, pupils)
	# #237: the row names the whole night (the drinks and the bed), is grey with
	# the reason under it when the purse cannot cover it, and keeps the last
	# night's line under it, so a press is answered where it was made.
	var night: Dictionary = Downtime.carouse_cost(party, s)
	var no_night: String = Downtime.carouse_refusal(party, s)
	_trade_row(rows, "A night on the town (%d ◉, and %d ◉ for the bed)" % [int(night["drinks"]), int(night["bed"])],
		"Go out", _carouse, no_night != "", null, no_night if no_night != "" else String(_visit.get("carouse_line", "")))
	# The game: a stake the purse can cover, once a day in this town.
	var row := HBoxContainer.new()
	rows.add_child(row)
	var lbl := Label.new()
	lbl.text = "Sit in on a game"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var stake := OptionButton.new()
	for st in Downtime.GAMBLE_STAKES:
		if int(st) <= party.gold:
			stake.add_item("%d ◉" % int(st), int(st))
	row.add_child(stake)
	var go := Button.new()
	go.text = "Go"
	go.disabled = not Downtime.can_gamble(party, world, s) or stake.item_count == 0
	go.pressed.connect(func(): _gamble(stake.get_selected_id()))
	row.add_child(go)
	var refused: String = Downtime.gamble_refusal(party, world, s)
	if refused != "":
		_note(rows, refused)   # why Go is grey: once a day a town, not once a visit
	if s.kind == "city":
		_pit_row(rows, s)

# The trainer: whoever is picked sets the fee, and the feats on offer.
func _train_row(rows: VBoxContainer, pupils: Array) -> void:
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(430, 0)
	rows.add_child(line)
	var row := HBoxContainer.new()
	rows.add_child(row)
	var who := OptionButton.new()
	for ch in pupils:
		who.add_item(ch.cname)
	row.add_child(who)
	var what := OptionButton.new()
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(what)
	var pick := func(i: int) -> void:
		var ch = pupils[i]
		line.text = "Train %s in a feat (%d ◉, five days)" % [ch.cname, Downtime.train_cost(ch)]
		what.clear()
		for fid in Downtime.trainable(ch):
			what.add_item(String(Catalog.feat_src(fid).get("name", fid)))
			what.set_item_metadata(what.item_count - 1, fid)
	who.item_selected.connect(pick)
	pick.call(0)
	var go := Button.new()
	go.text = "Go"
	go.pressed.connect(func(): _train(pupils[who.selected],
		String(what.get_item_metadata(what.selected)) if what.selected >= 0 else ""))
	row.add_child(go)

# The pit's row: the week's three and the next bout's purse; a closed bracket says why.
func _pit_row(rows: VBoxContainer, s) -> void:
	var names: Array = Downtime.pit_bracket(s, world)["names"]
	var st: Dictionary = Downtime.pit_state(party, s, world)
	var b: int = int(st["beaten"])
	if st["open"]:
		# #236: one on one. The row asks who goes in — the marching company's
		# own, on their feet (Downtime.pit_fighters) — between the bracket and
		# the Fight button, which stays the row's last child (the drive robots
		# find a row by its label and press what ends it).
		var fighters: Array = Downtime.pit_fighters(party)
		var who := OptionButton.new()
		who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for ch in fighters:
			who.add_item("%s, %s %d" % [ch.cname, ChoicePick.humanize(ch.class_id()).to_lower(), ch.level()])
		who.tooltip_text = "Who goes in. One hero against one champion; the rest of the company watches."
		_trade_row(rows, "The pit: %s, %s and %s stand this week (purse %d ◉)." % [names[0], names[1], names[2], Downtime.PIT_PURSE[b]],
			"Fight", func(): _pit_bout(String(fighters[who.selected].id) if who.selected >= 0 else ""),
			fighters.is_empty(), null,
			("%s stands next, one on one." % names[b]) if not fighters.is_empty()
				else "%s stands next, and nobody in the company is on their feet to meet them." % names[b])
		var row: HBoxContainer = rows.get_child(rows.get_child_count() - 1)
		row.add_child(who)
		row.move_child(who, row.get_child_count() - 2)
		for c in row.get_children():   # the label's floor gives the picker room inside the panel
			if c is VBoxContainer:
				for l in c.get_children():
					(l as Control).custom_minimum_size.x = 220
	elif b < 0:
		_note(rows, "The pit: carried out this week. The bracket is closed until the next.")
	else:
		_note(rows, "The pit: champions of the bracket this week. A new three stand next week.")

# Five days and a feat are a card (Schooled), the way a night that went
# wrong is; a contact made is one too. The game and the bench stay lines.
func _train(ch, feat_id: String) -> void:
	var r: Dictionary = Downtime.train(party, world, _visit["settlement"], ch, feat_id)
	_downtime_done(r, "The master-at-arms will not take them.")
	if bool(r.get("ok", false)):
		_card({"id": "downtime-train", "title": "Schooled", "kind": "good", "ok": true,
			"text": String(r["text"]), "art": "event-downtime-train"}, _on_inn_card_ack)

func _carouse() -> void:
	var r: Dictionary = Downtime.carouse(party, world, _visit["settlement"])
	var c: Dictionary = _complicate(String(r.get("complication", "")), int(r.get("cost", 0)))
	# The night's card (a contact) or its story (a complication) waits for the
	# die: it would say how the roll went before the roll had landed. So does
	# the line the row keeps (#237), put under it once the die is down.
	_downtime_done(r, "Nobody in the company is fit for a night out.", "rest", func():
		if r.has("nat") and not _visit.is_empty():
			_visit["carouse_line"] = "Last night: " + String(r["text"])
			_build_visit_panel()
		if bool(r.get("contact", false)):
			_card({"id": "downtime-carouse", "title": "A night on the town", "kind": "good", "ok": true,
				"text": String(r["text"]), "gold": int(r.get("coin", 0)), "art": "event-downtime-carouse"}, _on_inn_card_ack)
		_show_complication(c))

func _gamble(stake: int) -> void:
	var s = _visit["settlement"]
	var refused: String = Downtime.gamble_refusal(party, world, s)
	var r: Dictionary = Downtime.gamble(party, world, s, stake)
	var c: Dictionary = _complicate(String(r.get("complication", "")), stake)
	_downtime_done(r, refused if refused != "" else "There is no game on tonight.", "buy", func(): _show_complication(c))

func _craft(item_id: String) -> void:
	_downtime_done(Downtime.craft(party, world, _visit["settlement"], item_id, _visit), "Nobody here will let you at the bench.")

# The row's answer, the way _work_healer gives its own: a save (a lost stake
# and a failed night move the purse as surely as a won one), the panel again,
# the line under the row.
func _downtime_done(r: Dictionary, fallback: String, sfx := "rest", then := Callable()) -> void:
	if not r.is_empty():
		_autosave()
	_build_visit_panel()
	_say_rolled(r, String(r.get("text", fallback)), sfx, then)

# A story (Downtime.complication): the consequence lands before the panel
# under the card is rebuilt — the tab's gold, the insult's opinion; the bad
# lead is only the card — and the brawl waits behind the card's button: the
# visit closes and an easy bandit roster is the cousin's friends, fought the
# way a road fight is (a loss is _retreat's). {} when there is no story.
func _complicate(kind: String, cost: int) -> Dictionary:
	if kind == "":
		return {}
	var s = _visit["settlement"]
	var c: Dictionary = Downtime.complication(kind, s, cost)
	if c.has("gold"):
		party.add_gold(int(c["gold"]))
	if c.has("opinion"):
		FactionOpinion.lower(s.faction, float(c["opinion"]))
	return c

func _show_complication(c: Dictionary) -> void:
	if c.is_empty():
		return
	var s = _visit["settlement"]
	if c.get("fight", false):
		_card(c, func(): _on_event_ack(); _close_visit(); await _brawl(s))
	else:
		_card(c, _on_inn_card_ack)

# The cousin's friends: an easy bandit roster fought the way a road fight is
# (a loss is _retreat's), with the road's own rules kept off it
# (_launch_combat's `difficulty`). Its spoils page is its ack; the inn reopens
# behind it, the way it does behind the pit's card.
func _brawl(s) -> void:
	var result: Dictionary = await _launch_combat(
		World.RoamingParty.new("%s-brawl" % s.id, s.position, "bandit"), false, false, "", "easy")
	if result.is_empty():
		return   # torn down mid-fight
	while _spoils_panel != null:
		await get_tree().process_frame
	_reopen_visit(s)

# The inn again after a fight closed the visit: Visit.visit() stamps
# last_visited afresh, and the once-a-visit rows keep their stamp with it.
func _reopen_visit(s) -> void:
	var stamp: float = s.last_visited
	_open_visit(s)
	Downtime.restamp(party, s, stamp, s.last_visited)
	Lodge.restamp(party, s, stamp, s.last_visited)

# A bout in the pit: one hero the company puts in against one champion priced
# for that hero (Downtime.pit_spec, #236 — it was the whole marching party
# against a lone pumped foe), fought in the square with none of the road's
# aftermath — no band erased, no opinion moved, no spoils page: a win banks
# what a fight banks (_bank: XP, the kill's gold, loot, quest progress), then
# the purse and the deed are pit_result's, all on one card, and the visit
# reopens behind it. A loss is carried out, not buried — _retreat's revive
# without its gold or its walk; the house's stake is the purse. For the bout
# the hero is the whole marching order (Downtime.pit_line_up), so the board,
# the XP and a trait earned are theirs alone; the order is put back as soon as
# the bout is banked, torn down or not.
func _pit_bout(char_id: String) -> void:
	var s = _visit["settlement"]
	var st: Dictionary = Downtime.pit_state(party, s, world)
	if not st["open"]:
		return
	var bout: int = int(st["beaten"])
	var fighter = party.get_member(char_id)
	if fighter == null or not fighter in Downtime.pit_fighters(party):
		_say("Nobody in the company is fit to go in.")
		return
	var spec: Dictionary = Downtime.pit_spec(party, s, world, bout, fighter)
	if spec.is_empty():
		_say("Nobody stands in the pit tonight.")
		return
	_close_visit()
	var order: Array = Downtime.pit_line_up(party, char_id)
	var result: Dictionary = await _run_combat(spec, "normal", false, false, "town")
	if result.is_empty():
		Downtime.pit_stand_down(party, order)
		return   # torn down mid-fight
	var won: bool = String(result.get("outcome", "")) == "Victory"
	if won:
		_bank(result)
		_apply_deaths(result, "in the pit at %s" % s.sname)
	else:
		# The pit is not a death match: a lost bout's fallen are carried out,
		# not buried (no _apply_deaths on a loss), and come to here. The dead
		# of earlier fights are not the pit's to give back.
		Party.revive_downed(party, result.get("deaths", []))
	Downtime.pit_stand_down(party, order)
	var r: Dictionary = Downtime.pit_result(party, s, world, bout, won, int(st["week"]), fighter.cname)
	_autosave()
	# The quest news a spoils page would have carried rides the card instead.
	var text: String = String(r["text"])
	for line in _quest_news:
		text += "  " + String(line)
	_quest_news = []
	_card({"id": "downtime-pit", "title": "The pit", "kind": "good" if won else "bad", "ok": won,
		"text": text, "gold": int(r["purse"]), "xp": int(result.get("xp", 0)) if won else 0},
		func(): _on_event_ack(); _reopen_visit(s))

# --- The lodge (core/lodge.gd): the company's own house -----------------------
# A visit page like the inn's: the house's line, the bed (free), and per room
# its Build row or its use — the strongroom's deposit and withdraw, the yard's
# retrain pickers, and a line each for the rooms that work while the party is
# away (the garden and the map room are collected on arriving, _open_visit;
# the shrine's blessing is taken on leaving, _close_visit).
const DEPOSIT_STEPS := [50, 100, 200]

func _build_lodge_page(box: VBoxContainer, s) -> void:
	var mood := Label.new()
	mood.text = "The company's house at %s.  %d ◉ in the purse." % [s.sname, party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)
	var house := Icons.scene_art("event-lodge-house", null)
	if house != null:
		var pic := TextureRect.new()
		pic.texture = house
		pic.custom_minimum_size = Vector2(440, 160)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.clip_contents = true
		box.add_child(pic)
	var wait: float = Visit.long_rest_in(party, world)
	var rest_btn := Button.new()
	rest_btn.text = "Rest at the lodge (free)"
	rest_btn.disabled = wait > 0.0
	rest_btn.pressed.connect(_rest)
	box.add_child(rest_btn)
	if wait > 0.0:
		_note(box, "They rested less than a day ago — another night does nothing for %s." % _hours(wait))
	var scroll := _scroll_column(Vector2(VISIT_PANEL_W, _visit_list_h))   # pinned, as the inn's is (#228)
	box.add_child(scroll)
	_visit_list = scroll
	var rows: VBoxContainer = scroll.get_child(0)
	_section(rows, "The rooms")
	for room in Lodge.ROOMS:   # the order the map builds them in (SettlementKit.LODGE_ROOMS)
		var title := String(Lodge.ROOMS[room]["title"])
		var cap := title[0].to_upper() + title.substr(1)
		if not Lodge.has(party, room):
			_trade_row(rows, "Build %s (%d ◉)" % [title, int(Lodge.ROOMS[room]["cost"])], "Build",
				_build_room.bind(room), not Lodge.can_build(party, room), Icons.scene_art("event-lodge-" + room, null))
			continue
		match room:
			"strongroom":
				_note(rows, "The strongroom holds %d ◉ — gold the road cannot take." % Lodge.stored(party))
				_purse_row(rows, "Deposit", party.gold, _deposit)
				if Lodge.stored(party) > 0:
					_purse_row(rows, "Withdraw", Lodge.stored(party), _withdraw)
			"yard":
				var pupils: Array = party.party_characters().filter(func(ch): return Lodge.can_retrain(party, world, ch))
				if pupils.is_empty():
					_note(rows, "%s: one general feat put down for another, %d ◉ and three days; once a visit, and nobody is ready for it now." % [cap, Lodge.RETRAIN_COST])
				else:
					_retrain_row(rows, pupils)
			"garden":
				_note(rows, "%s: a potion of healing every %d days the company is away, up to %d, on the step when it comes home." % [cap, Lodge.GARDEN_DAYS, Lodge.GARDEN_CAP])
			"shrine":
				_note(rows, "%s: the company carries its blessing onto the road when it leaves." % cap)
			"maproom":
				_note(rows, "%s: a new mark on the wall every %d days the company is away, up to %d." % [cap, Lodge.MAPROOM_DAYS, Lodge.MAPROOM_CAP])
	# Audit 2.1: the roll of the fallen (core/fallen.gd), cut into the wall of
	# the company's own house, newest first — the one place the dead are
	# listed with where they fell and to what.
	_section(rows, "The roll of the fallen")
	var roll: Array = Fallen.roll(party)
	if roll.is_empty():
		_note(rows, "No names on the wall yet.")
	for i in range(roll.size() - 1, -1, -1):
		_note(rows, Fallen.line(roll[i], party))

# A picker of DEPOSIT_STEPS the sum covers, and "all" (id -1) for the sum itself.
func _purse_row(rows: VBoxContainer, verb: String, have: int, on_go: Callable) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var lbl := Label.new()
	lbl.text = verb
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var pick := OptionButton.new()
	for n in DEPOSIT_STEPS:
		if int(n) <= have:
			pick.add_item("%d ◉" % int(n), int(n))
	pick.add_item("all (%d ◉)" % have, -1)
	row.add_child(pick)
	var go := Button.new()
	go.text = "Go"
	go.disabled = have <= 0
	go.pressed.connect(func(): on_go.call(have if pick.get_selected_id() == -1 else pick.get_selected_id()))
	row.add_child(go)

# The yard's pickers: who, which of their general feats, and what for — the
# trainer's row (_train_row) with the old feat between.
func _retrain_row(rows: VBoxContainer, pupils: Array) -> void:
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(430, 0)
	rows.add_child(line)
	var row := HBoxContainer.new()
	rows.add_child(row)
	var who := OptionButton.new()
	for ch in pupils:
		who.add_item(ch.cname)
	row.add_child(who)
	var old := OptionButton.new()
	row.add_child(old)
	var new := OptionButton.new()
	new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(new)
	var pick := func(i: int) -> void:
		var ch = pupils[i]
		line.text = "Retrain %s in the yard (%d ◉, three days)" % [ch.cname, Lodge.RETRAIN_COST]
		old.clear()
		for fid in ch.feats:
			if Lodge.general(fid):
				old.add_item(String(Catalog.feat_src(fid).get("name", fid)))
				old.set_item_metadata(old.item_count - 1, fid)
		new.clear()
		for fid in Downtime.trainable(ch):
			new.add_item(String(Catalog.feat_src(fid).get("name", fid)))
			new.set_item_metadata(new.item_count - 1, fid)
	who.item_selected.connect(pick)
	pick.call(0)
	var go := Button.new()
	go.text = "Go"
	go.pressed.connect(func(): _retrain(pupils[who.selected],
		String(old.get_item_metadata(old.selected)) if old.selected >= 0 else "",
		String(new.get_item_metadata(new.selected)) if new.selected >= 0 else ""))
	row.add_child(go)

# The deed, then the map: the house stands beside the town from this moment.
func _buy_lodge() -> void:
	var r: Dictionary = Lodge.buy(party, world, _visit["settlement"])
	if r.is_empty():
		_say("Not enough gold.")
		return
	Sound.play_sfx("buy")
	_cheer()
	_settlements3d.reset(world)
	_autosave()
	_build_visit_panel()
	_say(String(r["text"]))

func _build_room(room: String) -> void:
	var r: Dictionary = Lodge.build(party, world, room)
	if r.is_empty():
		_say("Not enough gold.")
		return
	Sound.play_sfx("buy")
	_settlements3d.reset(world)
	_autosave()
	_build_visit_panel()
	_say(String(r["text"]))

# A transfer either way: the coin sound, a save (the purse moved), the line.
# The pickers only offer what the purse or the strongroom holds, so a refusal
# is the module's own bounds and reads as one.
func _deposit(n: int) -> void:
	_moved(Lodge.deposit(party, n), "%d ◉ into the strongroom" % n)

func _withdraw(n: int) -> void:
	_moved(Lodge.withdraw(party, n), "%d ◉ out of the strongroom" % n)

func _moved(ok: bool, text: String) -> void:
	if ok:
		Sound.play_sfx("buy")
		_autosave()
	_build_visit_panel()
	_say("%s; it holds %d." % [text, Lodge.stored(party)] if ok else "The strongroom's door stays shut.")

func _retrain(ch, old_feat: String, new_feat: String) -> void:
	_downtime_done(Lodge.retrain(party, world, ch, old_feat, new_feat), "The yard will not take them.")

func _build_board_page(box: VBoxContainer, s) -> void:
	var has_inn: bool = Visit.has_service(s, "innkeeper")
	var mood := Label.new()
	mood.text = "%s posts the work here.  %d ◉ in the purse." % [
		Campaign.SERVICE_NAMES.get("innkeeper", "The innkeeper") if has_inn
		else "A town elder", party.gold]
	mood.theme_type_variation = "Dim"
	box.add_child(mood)
	if Posting.is_patron(s, world):
		var patron := Label.new()
		patron.text = "The patron's table: word of work from all over."
		patron.theme_type_variation = "Dim"
		box.add_child(patron)
	if Ladder.title_index() > 0:
		var pay := Label.new()
		pay.text = "%s — work pays +%d %%." % [Ladder.title_cap(), int(round(Ladder.PAY_PER_TITLE * 100 * Ladder.title_index()))]
		pay.theme_type_variation = "Dim"
		box.add_child(pay)
	# Contracts: what this people's regard is worth on the purse, when it is
	# worth anything (core/contracts.gd pay_mult).
	var regard: int = int(round((Contracts.pay_mult(s.faction) - 1.0) * 100.0))
	if regard != 0:
		var liked := Label.new()
		liked.text = "The %s' regard — their work pays %+d %%." % [Ladder.people(s.faction), regard]
		liked.theme_type_variation = "Dim"
		box.add_child(liked)
	# Contracts they will not hand you yet, and why — up here with the other
	# standing lines, where a scrolled list cannot hide it, and as a note rather
	# than a greyed Take: the robots press the first "Take" they find, and a job
	# you cannot take is not a job on the board. Only the board's own kinds; a
	# specialist's order would say so at its own counter.
	var here: Array = Visit.services(s)
	for c in Posting.closed(s, here):
		if not Posting.counters_for(s, here, String(c["kind"])).any(func(k): return BOARD_COUNTERS.has(k)):
			continue
		var note := Label.new()
		note.text = String(c["why"])
		note.theme_type_variation = "Dim"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(VISIT_PANEL_W - 40, 0)
		box.add_child(note)
	if s.raided_by != "":
		var raider = Raids.lair_of(world, s.raided_by)
		var hit := Label.new()
		hit.text = "Raiders from %s hit the town on %s. The market is half what it was." % [
			raider.sname if raider != null else "the hills", WorldSave.day_clock(s.raided_at).split("  ")[0]]
		hit.theme_type_variation = "Serif"
		hit.add_theme_color_override("font_color", Icons.COL_FOE)
		hit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hit)
	if has_inn:
		_portrait(box, s.faction, "innkeeper")
	var scroll := _scroll_column(Vector2(VISIT_PANEL_W, _page_scroll_h(300.0)))
	box.add_child(scroll)
	var rows: VBoxContainer = scroll.get_child(0)
	# T9x quest board, D7 placement: the board carries what the settlement posts
	# in public — bounty and war work where there is an innkeeper to take it,
	# carting and scouting everywhere. The specialists' own orders are at their
	# own counters (see _build_market_page), not here.
	for offer in _counter_offers(s).get("board", []):
		_job_row(rows, offer)
	for q in Visit.turn_ins(party):
		_trade_row(rows, "✔ %s" % Quest.describe(q, world.clock.elapsed), "Turn in", _turn_in.bind(q))
	if rows.get_child_count() == 0:
		var none := Label.new()
		none.text = ("Nothing posted right now." if has_inn
			else "Nothing posted right now — and no innkeeper here to hear of more.")
		none.add_theme_color_override("font_color", Icons.COL_MUTED)
		rows.add_child(none)

# A counter's heading inside a page's scroll list, and a muted aside. Both
# exist so a page can explain itself without every builder re-deriving the
# same Label boilerplate.
# The face behind the counter reads the visit: a moment's smile after a sale,
# a purchase or a haggle that went your way (CHEER_S seconds, then back), and
# a frown for the rest of the visit once a haggle went badly.
const CHEER_S := 2.5
var _cheer_until := 0.0     # Time.get_ticks_msec()/1000 the smile lasts to
var _portrait_pic: TextureRect = null
var _portrait_of := ["", ""]

func _mood() -> String:
	if Time.get_ticks_msec() / 1000.0 < _cheer_until:
		return "happy"
	return "frown" if _visit.get("sour", false) else ""

func _portrait(box: Control, faction: String, service: String) -> void:
	var pic := Icons.portrait_rect(faction, service, 160, _mood())
	if pic != null:
		box.add_child(pic)
	_portrait_pic = pic
	_portrait_of = [faction, service]

func _cheer() -> void:
	_cheer_until = Time.get_ticks_msec() / 1000.0 + CHEER_S
	_refresh_portrait()
	get_tree().create_timer(CHEER_S + 0.05).timeout.connect(_refresh_portrait)

func _refresh_portrait() -> void:
	if _portrait_pic != null and is_instance_valid(_portrait_pic):
		_portrait_pic.texture = Icons.portrait(_portrait_of[0], _portrait_of[1], _mood())

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

func _item_grid(rows: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	rows.add_child(g)
	return g

# D7: where each job this settlement is posting belongs on screen. The counter
# core/quest_posting.gd stamped on the offer IS the answer, with one fold: the
# innkeeper and the generalist both post in public, so both land on the notice
# board (a camp has no innkeeper, and its board is the generalist's). Every
# specialist keeps its own orders at its own counter in the market.
const BOARD_COUNTERS := ["innkeeper", "generalist"]

func _counter_offers(s) -> Dictionary:
	var by_counter: Dictionary = Visit.quest_offers_by_counter(s, party, world)
	var out := {}
	for counter in by_counter:
		var key: String = "board" if BOARD_COUNTERS.has(counter) else String(counter)
		if not out.has(key):
			out[key] = []
		out[key].append_array(by_counter[counter])
	return out

# One posted job, ready to take. A world-target row also shows its chain tier
# once it has escalated past the first job.
func _job_row(rows: VBoxContainer, offer: Dictionary) -> void:
	var tier: int = int(offer.get("chain_tier", 0))
	var tag := "  (tier %d)" % (tier + 1) if tier > 0 else ""
	var who := String(offer.get("issuer", ""))
	_trade_row(rows, "%s%s" % [offer["title"], tag], "Take", _take_quest.bind(offer), false,
		Icons.scene_art("quest-" + String(offer.get("kind", "")), null),
		("For the %s · " % Ladder.people(who) if who != "" else "")
		+ "Pays %d ◉ and %d XP" % [int(offer.get("reward", {}).get("gold", 0)), Quest.xp_reward(offer)]
		# the audit's 3.4: a bounty or a rescue says how long it gives you, before it is taken
		+ (" · %s" % Quest.time_left(offer, world.clock.elapsed) if int(offer.get("deadline_days", 0)) > 0 else ""))

# Issue #33: the label wraps. Without that its minimum width is the whole
# string, and a job with a long title pushed the row — and with it the counter,
# and with it the whole settlement panel — out past the edge of the screen. 330
# stays as the column width short rows line up on; it is a floor now rather
# than the only width the row can have.
# `sub` is a dim second line under the text — where a rumour points, what a
# job pays — so the thing itself reads as one line of prose and the numbers
# sit under it instead of in the middle of it.
func _trade_row(rows: VBoxContainer, text: String, action: String, on_press: Callable, disabled := false,
		tile: Texture2D = null, sub := "") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tile != null:   # the job's kind, as a tile (assets/generated/quest-<kind>.png)
		var pic := TextureRect.new()
		pic.texture = tile
		pic.custom_minimum_size = Vector2(48, 48)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(330, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if sub == "":
		row.add_child(lbl)
	else:
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stack.add_child(lbl)
		var cap := Label.new()
		cap.text = sub
		cap.theme_type_variation = "Dim"
		cap.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # a recruit's intro is a sentence or two
		cap.custom_minimum_size = Vector2(330, 0)
		stack.add_child(cap)
		row.add_child(stack)
	var btn := Button.new()
	btn.text = action
	btn.disabled = disabled
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(on_press)
	row.add_child(btn)
	rows.add_child(row)

# #87: whether the party's talker rolls with advantage right now (a potion or
# a talk spell) — the same test Visit's own rolls make.
func _talk_adv() -> bool:
	var talker = party.get_member(Campaign.new(party).best_at(Visit.PERSUADE_SKILL))
	return talker != null and Visit._talk_mode(talker, party) == Dice.ADV

# --- projection (see header) -------------------------------------------
# The map's camera, written as the function it has always been. `_iso()` maps a
# point on the ground to its screen offset, and it is exactly what an
# orthographic camera at yaw `_yaw` and pitch `_pitch` does: turn the ground
# under the camera, then foreshorten the depth axis by sin(pitch). The only
# thing the 3D refactor changed is that the two angles are now variables —
# which is why click-to-move, the ground mask, the chevrons and the minimap all
# came through it untouched.
#
# scenes/world/world_view3d.gd builds the real Camera3D from the same two
# angles and the same ISO_GAIN, so there is one camera and two ways of asking
# it questions, not two cameras.
func _iso(v: Vector2) -> Vector2:
	var r := v.rotated(deg_to_rad(_yaw)) * ISO_GAIN
	return Vector2(r.x, r.y * sin(deg_to_rad(_pitch)))

func _iso_inv(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y / sin(deg_to_rad(_pitch))).rotated(-deg_to_rad(_yaw)) / ISO_GAIN

# world point -> screen point
func _pix(w: Vector2) -> Vector2:
	return _origin + _iso(w) * _zoom

# screen point -> world point, the inverse of _pix
func _unpix(sp: Vector2) -> Vector2:
	return _iso_inv((sp - _origin) / _zoom)

# A circle on the GROUND, as the polygon it projects to. Still an ellipse, but
# one whose tilt and squash follow the camera rather than two fixed constants —
# used now only by the goal marker at the end of the marching route, since every
# other ring on the map became a decal lying in the 3D world
# (scenes/world/ground_marks3d.gd).
func _ring(center: Vector2, r: float, flat := true, closed := false, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var v := Vector2(cos(TAU * i / segs), sin(TAU * i / segs)) * r
		pts.append(center + (_iso(v) if flat else v))
	if closed:
		pts.append(pts[0])
	return pts

# How tall a footprint of world radius `r` stands on screen: the semi-minor
# axis of the ellipse _ring() would draw. What a name label is pushed down by,
# so it clears the landmark it names at any tilt. Floored, because at a shallow
# pitch the ellipse collapses and a label with no clearance sits on the model.
func _footprint_drop(r: float) -> float:
	return maxf(r * ISO_GAIN * _zoom * sin(deg_to_rad(_pitch)), 3.0)

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

# O-biome — THE forest rule, in one place. _build_mask() paints the ground from
# it and scenes/world/scatter3d.gd grows its trees from it; that file's header
# is explicit that a second copy of this rule is a wood standing on grass, and
# now that the threshold varies with the biome under the block there is more of
# a rule to keep in step than there was.
#
# Takes a BLOCK (a TILE_CLUSTER-quantised cell, what _cluster returns), not a
# cell, which is what lets both callers keep memoising per block: one biome
# lookup and one hash per 64 cells rather than per cell. That matters — zoomed
# out, scatter walks tens of thousands of cells per replant, and biome_at() is
# a scan over every disc on the map.
func block_wooded(block: Vector2i) -> bool:
	var centre := (Vector2(block) * float(TILE_CLUSTER)
		+ Vector2(TILE_CLUSTER, TILE_CLUSTER) * 0.5) * CELL
	var kind: String = world.biome_at(centre) if world != null else World.DEFAULT_BIOME
	return _rand(block, 5) > float(WOODED_BY_BIOME.get(kind, WOODED))

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

func yaw() -> float:
	return _yaw

func pitch() -> float:
	return _pitch

# Turn the camera about the point it is looking at, not about the world's
# origin: a map that slides sideways as you turn it is a map you cannot turn on
# purpose. The ground point under the middle of the screen is read first, and
# put back under the middle afterwards, which is the same trick zoom_at() plays
# with the point under the cursor.
func orbit_by(d: float) -> void:
	var anchor := _unpix(size * 0.5)
	_yaw = fposmod(_yaw + d, 360.0)
	center_on(anchor)

# Tilt, between edge-on and nearly overhead. Same "hold the middle" rule as the
# turn, and for the same reason — at a shallow pitch a degree of tilt moves the
# ground a very long way.
func tilt_by(d: float) -> void:
	var anchor := _unpix(size * 0.5)
	_pitch = clampf(_pitch + d, PITCH_MIN, PITCH_MAX)
	center_on(anchor)

# Back to the view the map opens on, keeping whatever is in the middle of the
# screen in the middle of the screen. The one binding that has to exist once a
# camera can be turned: having got lost, you must be able to get un-lost
# without hunting for the angle you started at.
func reset_view() -> void:
	var anchor := _unpix(size * 0.5)
	_yaw = ISO_YAW
	_pitch = ISO_PITCH
	set_zoom(1.0)
	center_on(anchor)

# Put world point `w` in the middle of the view.
func center_on(w: Vector2) -> void:
	_pan = -_iso(w) * _zoom
	_layout()

# zoom keeping the world point under `sp` fixed
func zoom_at(sp: Vector2, factor: float) -> void:
	var anchor := _unpix(sp)
	set_zoom(_zoom * factor)
	_layout()
	pan_by(sp - _pix(anchor))
	_layout()      # _origin follows _pan; keep them in step for the next _unpix

func _layout() -> void:
	_origin = size * 0.5 + _pan

# Right-drag pans, middle-drag orbits. They used to do the same thing, which
# was fine while there was nothing to orbit; the split keeps the gesture every
# player already knows on the button they already use it with, and puts the new
# one on the button that was duplicating it. Q/E/R/F and Home do the same from
# the keyboard — see _unhandled_key_input().
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			orbit_by(-e.relative.x * ORBIT_SENS.x)
			tilt_by(e.relative.y * ORBIT_SENS.y)
			queue_redraw()
		elif e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			pan_by(e.relative)
			queue_redraw()
		elif not spectator:
			# A band's figure is a thing to click (_seek), so it says so.
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if _band_at(e.position) != null else CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _wheel_over_ui():
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(e.position, 1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(e.position, 1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT and not spectator:   # the guest looks; the host orders
			var p := world.player()
			var band = _band_at(e.position)
			# A band already met and parted with (slipped past, or under a
			# truce) standing on a town does not eat the click on the town:
			# the place wins, and the march goes there. A fresh band on the
			# same spot is still the road doing its job — the click meets it.
			var place = _place_at(e.position) if band != null and _parted_with(band) else null
			if place != null and p != null and not RouteTravel.on(world):
				_drop_meet()
				world.set_goal(p, place.position)
			elif place != null and p != null:
				_route_click(e.position)
			elif band != null:
				_seek(band)
			elif p != null and RouteTravel.on(world):
				_route_click(e.position)
			elif p != null:
				_drop_meet()
				world.set_goal(p, _click_target(e.position))
		queue_redraw()

# A band the company has met and parted with: slipped past, or under a truce.
func _parted_with(band) -> bool:
	return _slipped.has(band.id) or WorldAI.in_truce(band, world.clock.elapsed)

# The known place under screen point `sp` — a town, a found lair, a found
# landmark — within ROUTE_PICK screen pixels, or null.
func _place_at(sp: Vector2):
	var at := _click_target(sp)
	var reach: float = ROUTE_PICK / maxf(0.01, ISO_GAIN * _zoom)
	var best = null
	var best_d := reach
	var places: Array = world.settlements.duplicate()
	places.append_array(world.lairs.filter(func(l): return l.discovered))
	places.append_array(world.landmarks.filter(func(m): return m.found))
	for x in places:
		var d: float = at.distance_to(x.position)
		if d <= best_d:
			best = x
			best_d = d
	return best

# #231: on the roads a click is a place, never ground — the company goes there by
# the known roads, or not at all (the owner's call: it never leaves the road).
# The place nearest the click within ROUTE_PICK screen pixels, counted in world
# units at the current zoom, so a town's diorama and a landmark's stone are both
# easy to hit.
const ROUTE_PICK := 28.0
func _route_click(sp: Vector2) -> void:
	var id := RouteTravel.place_near(world, _click_target(sp), ROUTE_PICK / maxf(0.01, ISO_GAIN * _zoom))
	if id == "":
		_camp_msg.text = "No road you know goes there."
		return
	if RouteTravel.go(world, id):
		_camp_msg.text = "On the road to %s." % RouteTravel.place_name(world, id)
	else:
		_camp_msg.text = "No road you know goes to %s yet." % RouteTravel.place_name(world, id)

# #193: a ScrollContainer that is already at its end, or a list too short to
# scroll at all, does not accept the wheel, so the event bubbled on up to this
# screen and a player reading a town's board zoomed the map behind it instead.
# The wheel belongs to the map only when the pointer is over the map: anything
# under a panel or a scrolling list is the panel's, whether or not it moved.
func _wheel_over_ui() -> bool:
	var c: Control = get_viewport().gui_get_hovered_control()
	while c != null and c != self:
		if c is ScrollContainer or c is PanelContainer:
			return true
		c = c.get_parent() as Control
	return false

# #110/#113: a settlement or lair is drawn as a diorama standing UP from its
# ground point, so a click on its roofs lands on the ground behind it and the
# party walks past the town. A click anywhere on a landmark's model is a click
# on the landmark: the goal is its position, and the ring is drawn there.
func _click_target(sp: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for s in world.settlements:
		var at := _pix(s.position)
		var h: float = float(Settlements3D.TARGET_HEIGHT.get(s.kind, 25.7)) * ISO_GAIN * _zoom
		if _in_model_box(sp, at, h):
			var d := sp.distance_to(at)
			if d < best_d:
				best = s.position; best_d = d
	for l in world.lairs:
		if not l.discovered:
			continue
		var at := _pix(l.position)
		var h: float = Lairs3D.TARGET_HEIGHT * ISO_GAIN * _zoom
		if _in_model_box(sp, at, h):
			var d := sp.distance_to(at)
			if d < best_d:
				best = l.position; best_d = d
	return best if best != Vector2.INF else _unpix(sp)

# The screen box a diorama of height `h` (px) fills over its ground point `at`:
# roughly as wide as it is tall, standing on a shallow ellipse.
static func _in_model_box(sp: Vector2, at: Vector2, h: float) -> bool:
	return absf(sp.x - at.x) <= h * 0.7 and sp.y <= at.y + h * 0.3 and sp.y >= at.y - h

# --- drawing -----------------------------------------------------------
# Three things, and every one of them is annotation rather than scenery: the
# route the party is marching, the name under each landmark, and the chevrons
# pinned to the frame for the settlements that are off screen. Everything that
# stands on the ground (towns, lairs, bands, woods) or lies on it (footprints,
# rings, shadows) is geometry in the 3D view, where the depth buffer can sort
# it — see ground_marks() below and scenes/world/world_view3d.gd.
func _draw() -> void:
	_layout()
	_draw_roads()
	var p := world.player()
	if p != null and not p.at_goal():
		# #95/#115: the way there — a faint gold thread from the party through
		# any corners to the ring at the end. Straight or routed, same thread.
		var pts := PackedVector2Array([_pix(p.position), _pix(p.goal)])
		for wp in p.route:
			pts.append(_pix(wp))
		draw_polyline(pts, Color(Icons.COL_GOLD, 0.45), 1.5, true)
		# `pts` is already in screen space — p.goal is the NEXT corner and p.route
		# the ones after it, so pts[-1] is the destination, projected. This used
		# to read _ring(_pix(pts[-1]), ...), projecting a screen point a second
		# time and putting the marker at the end of the march somewhere that was
		# not the end of the march. The radius is still quoted in world units,
		# which is what the * _zoom is for: _ring() applies _iso() but not the
		# zoom, the way _pix() does.
		draw_polyline(_ring(pts[-1], 9.0 * _zoom, true, true, 18), Icons.COL_GOLD, 1.5, true)
	var ppos: Vector2 = p.position if p != null else Vector2.ZERO
	_draw_labels()
	_draw_offscreen_markers(ppos)
	_draw_quest_marks(ppos)


# #231: the roads the company knows, under everything else this draws — the
# only ground it can walk on a route world, so it is drawn whatever the fog
# says (a road you have been told of is a road you know). Hidden ones are not
# drawn at all: finding them is the point. Same inks tests/shot_routes.gd uses,
# so the spike's diagrams and the map agree.
const ROAD_INK := {"road": Color(0.80, 0.63, 0.38, 0.9), "track": Color(0.72, 0.35, 0.25, 0.85),
	"path": Color(0.78, 0.78, 0.72, 0.8), "byway": Color(0.45, 0.62, 0.85, 0.85), "trail": Color(0.45, 0.85, 0.40, 0.9)}
const ROAD_WIDTH := {"road": 5.0, "track": 3.5, "path": 2.5, "byway": 2.5, "trail": 3.5}
const ROAD_EDGE := Color(0.10, 0.07, 0.04, 0.75)   # the dark bed each road is drawn on, so it reads over grass and fog alike
func _draw_roads() -> void:
	if not RouteTravel.on(world):
		return
	for eid in world.routes.edges:
		var e: Dictionary = world.routes.edges[eid]
		if not e["known"]:
			continue
		var pts := PackedVector2Array()
		for pt in e["points"]:
			pts.append(_pix(pt))
		var kind := String(e["kind"])
		var width: float = float(ROAD_WIDTH.get(kind, 2.5)) * clampf(_zoom, 0.6, 1.6)
		draw_polyline(pts, ROAD_EDGE, width + 2.0, true)
		draw_polyline(pts, ROAD_INK.get(kind, ROAD_INK["road"]), width, true)

# #153: the job's own tile (assets/generated/quest-<kind>.png, the one the
# offer card shows) floated over whatever it names on the map, gilt-framed; a
# job that is done wears it over the town that pays. Off screen, it pins to the
# frame as a chevron the way a settlement does, in gold, so an open job is
# never a name you have to remember the way to. Which jobs, and where, is
# Quest.map_marks — testable without a viewport.
const QUEST_TILE := 22.0
func _draw_quest_marks(ppos: Vector2) -> void:
	var frame := _marker_frame()
	for m in Quest.map_marks(world, party):
		var at: Vector2 = _pix(m["pos"])
		if not frame.has_point(at):
			if frame.size.x > 0.0 and frame.size.y > 0.0:
				_draw_offscreen_marker(m["pos"], m["title"], Icons.COL_GOLD, frame, ppos)
			continue
		at.y -= QUEST_TILE * 1.4   # above the footprint and the figure standing in it
		var r := Rect2(at - Vector2.ONE * QUEST_TILE * 0.5, Vector2.ONE * QUEST_TILE)
		var tex: Texture2D = Icons.scene_art("quest-" + String(m["kind"]), null)
		draw_rect(r.grow(2.0), Icons.COL_INK)
		if tex != null:
			draw_texture_rect(tex, r, false)
		draw_rect(r.grow(2.0), Icons.COL_GOLD if m["done"] else Icons.COL_GOLD_EDGE, false, 1.5)
		# A pin down to the footprint, so a tile over a crowded town is not
		# ambiguous about which roof it is over.
		draw_line(at + Vector2(0.0, QUEST_TILE * 0.5 + 2.0), at + Vector2(0.0, QUEST_TILE * 1.4),
			Icons.COL_GOLD_EDGE, 1.0, true)

# The name under every landmark the player can see, painter-sorted so a nearer
# label is drawn over a further one. Which landmarks those are is the same
# question ground_marks() answers — the fog rules live there, once, and this
# reads the list it produced.
func _draw_labels() -> void:
	var labels: Array = []
	for m in ground_marks():
		if not m.has("label"):
			continue
		labels.append({"at": _pix(m["pos"]) + Vector2(0.0, _footprint_drop(m["radius"]) + 12.0),
			"text": m["label"], "col": _remembered(Icons.COL_BODY, m["live"])})
	labels.sort_custom(func(a, b): return a["at"].y < b["at"].y)
	for l in labels:
		var w := ThemeDB.fallback_font.get_string_size(l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		# A one-pixel drop shadow, for the same reason the chevron labels have
		# one: a name can land on bright water, a pale roof or black fog, and it
		# has to stay readable over all three.
		draw_string(ThemeDB.fallback_font, l["at"] - Vector2(w * 0.5, 0.0) + Vector2(1, 1),
			l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, l["at"] - Vector2(w * 0.5, 0.0), l["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, l["col"])


# Every footprint on the ground this frame, and the name that goes under it:
# one list, rebuilt per frame, read by scenes/world/ground_marks3d.gd (which
# draws the discs, rings, shadows and haloes as one MultiMesh) and by
# _draw_labels() above.
#
# It exists as a list rather than as three draw calls because the fog rules are
# the interesting part and they must not be written twice. T9x: settlements are
# landmarks, always shown regardless of fog — the whole point of the beacon is
# to give the player something to walk toward on a still-dark map. Lairs and
# roaming bands stay fog-gated: those are meant to be found, not signposted.
# T9y: "live" is the currently-visible tier the ground is dimmed by — a
# landmark the party can see right now reads in full colour, one they are only
# remembering reads washed out.
#
#   pos     where it stands, in world units
#   radius  the footprint's radius, in world units
#   color   its tint, alpha already faded for the fog
#   ring    ring width as a fraction of the radius, 0 for no ring
#   fill    how strongly the disc inside the ring is painted, 0 for none
#   shadow  how dark the soft shadow under it is, 0 for none
#   label   the name to draw under it; absent means no name
#   live    whether the party can see it right now
func ground_marks() -> Array:
	var p := world.player()
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
	var out: Array = []
	for s in world.settlements:
		var live: bool = world.is_visible_now(s.position, ppos)
		out.append({"pos": s.position,
			"radius": _footprint(float(SETTLEMENT_RADIUS.get(s.kind, 17.0)),
				_settlements3d.footprint(s) if _settlements3d != null else 0.0),
			"color": _remembered(faction_color(s.faction), live), "ring": RING_WIDTH,
			"fill": SETTLEMENT_FILL, "shadow": 0.9,
			"label": s.sname + Raids.settlement_tag(world, s, world.clock.elapsed)
				+ (" · your lodge" if Lodge.at(party, s) else ""), "live": live})
	for l in world.lairs:
		# T91: an undiscovered lair draws nothing at all — that is the mechanic.
		if not (l.discovered and world.is_explored(l.position)):
			continue
		var live: bool = world.is_visible_now(l.position, ppos)
		out.append({"pos": l.position,
			"radius": _footprint(LAIR_RADIUS, _lairs3d.footprint(l) if _lairs3d != null else 0.0),
			"color": _remembered(Icons.COL_MUTED if l.looted else Icons.COL_FOE, live),
			"ring": RING_WIDTH, "fill": SETTLEMENT_FILL, "shadow": 0.85,
			"label": l.sname + Raids.lair_tag(l), "live": live})
	for m in world.landmarks:
		if not m.found or not world.is_explored(m.position):
			continue
		var live: bool = world.is_visible_now(m.position, ppos)
		out.append({"pos": m.position,
			"radius": _footprint(LANDMARK_RADIUS, _landmarks3d.footprint(m) if _landmarks3d != null else 0.0),
			"color": _remembered(Icons.COL_MUTED if m.spent else Icons.COL_ACCENT, live),
			"ring": RING_WIDTH, "fill": SETTLEMENT_FILL, "shadow": 0.8, "label": m.sname, "live": live})
	for q in world.parties:
		if q.is_player and not _visit.is_empty():
			continue   # inside the gates for the duration of the visit, not standing on the map
		# A watchtower's "keep watch" marks every band within two vision radii for
		# a day: treat the map as explored under them too, same as a place the
		# party actually walked past.
		if not q.is_player and not world.band_seen(q.position):
			continue
		# A roaming band is the one landmark whose remembered position is a lie
		# — it has walked on since. Shown at its live position either way (the
		# map has no last-known-position memory to show instead), but washed
		# out, which is the honest reading: "they were around here".
		var live: bool = q.is_player or world.is_visible_now(q.position, ppos)
		var rad: float = PLAYER_RADIUS if q.is_player else BAND_RADIUS
		if q.is_player:
			# T9x: a halo, not just an outline — it has to read as "this one is
			# you" whichever hero figure is standing there, now that the player
			# can pick any of them from the Party screen. First in the list so
			# the band's own shadow blends over it, not under it.
			out.append({"pos": q.position, "radius": rad * HALO_SCALE,
				"color": Color(Icons.COL_GOLD, 0.55), "ring": 0.14, "fill": 0.22,
				"shadow": 0.0, "live": true})
		# The player's own headcount comes off the real Party (active roster),
		# everyone else's off their troops[] flavour roster.
		var count: int = party.active.size() if q.is_player else q.troops.size()
		var who: String = "You" if q.is_player else EnemyNames.upper_first(EnemyNames.band_name(q, world))
		# #229: a band in a clash says so, and how far in it is — the fight is
		# being told an hour a round, and the label is where the hours show.
		var fighting: Dictionary = {} if q.is_player else world.clash_of(q)
		var tag: String = "" if fighting.is_empty() else " · fighting, round %d/%d" % [
			WorldBattle.round_of(fighting, world.clock.elapsed), int(fighting["rounds"])]
		out.append({"pos": q.position, "radius": rad,
			"color": _remembered(faction_color(q.faction, q.is_player), live),
			"ring": 0.0, "fill": 0.0, "shadow": 1.0,
			"label": "%s (%d)%s" % [who, count, tag], "live": live})
	# #229: the ground the two bands are fighting over, ringed in the foe's
	# red and throbbing, so a battle reads from across the map before the
	# labels do. Fog-gated like the bands themselves.
	for c in world.clashes:
		var at: Vector2 = c["at"]
		if not world.band_seen(at):
			continue
		var live: bool = world.is_visible_now(at, ppos)
		var throb: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		out.append({"pos": at, "radius": CLASH_RADIUS,
			"color": _remembered(Color(Icons.COL_FOE, 0.55 + 0.4 * throb), live),
			"ring": 0.10 + 0.06 * throb, "fill": 0.12, "shadow": 0.0, "live": live})
	return out


# The radius a landmark's footprint is drawn at: its old flat-map radius, or
# enough to clear the model standing on it, whichever is more.
#
# It has to be measured rather than declared. On the flat map the ring was
# painted over the buildings, so a ring narrower than the town it encircled
# still read; lying on the ground it does not, and how wide a town is depends
# on which art source built it — a GLB fitted to a target height and a kit
# assembled from primitives come out different widths, and
# Settlements3D.source switches between them. `model` is 0.0 when the layer has
# nothing to measure, and then the floor is the answer, which is also what
# keeps this honest headless.
func _footprint(floor_r: float, model: float) -> float:
	return maxf(floor_r, model * FOOTPRINT_CLEARANCE)


# The fog's memory, as a texture: R forest, G water, B explored, one texel per
# ground cell. scenes/world/world_view3d.gd puts it on the ground mesh and
# assets/world/ground/ground3d.gdshader reads it; this side owns WHICH cells and
# HOW OFTEN, because that is the fog's business and the expensive part.
#
# Issue #31 — the frame-rate drop. Three things were wrong with the loop this
# grew out of, and all three were about doing work per cell, per frame, that
# does not change per frame:
#
#  1. It walked every cell of the VIEWPORT and asked world.is_explored() about
#     each one (3.7us a cell measured, since it folds in a scan of every
#     settlement) even though the answer is no for most of a map nobody has
#     walked yet. It walks the explored ground instead — the cells around each
#     remembered waypoint and each settlement beacon, clipped to the viewport —
#     so the unwalked map costs a box test per waypoint, not a distance query
#     per cell. The set it arrives at is the same set is_explored() would have
#     said yes to; it is reached from the other end.
#  2. Never-explored cells were a draw call each. They are one channel of one
#     texture now, and the shader paints them.
#  3. The tile a cell shows is a pure function of the cell and the world's
#     water, and was recomputed every frame at ~5.8us a cell — water_depth()
#     alone is a linear scan of every lake. It is cached; terrain does not move.
#
# Called from _process() rather than from _draw(): the ground is no longer
# something this Control paints, but the mask still has to be ready before the
# view's camera looks at it in the same frame.
func _update_ground() -> void:
	_layout()
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var w := _unpix(corner)
		mn = mn.min(w); mx = mx.max(w)
	var i0 := int(floor(mn.x / CELL)); var i1 := int(ceil(mx.x / CELL))
	var j0 := int(floor(mn.y / CELL)); var j1 := int(ceil(mx.y / CELL))
	# The mask covers the screen's cell box plus a quarter of it each side, and
	# is rebuilt only when the screen leaves that box (or the map's memory
	# grows) — a pan of a few cells costs nothing.
	var step := 1
	while (i1 - i0 + 1) / step > MASK_MAX or (j1 - j0 + 1) / step > MASK_MAX:
		step += 1
	var pad_x := maxi(2, (i1 - i0) / 4)
	var pad_y := maxi(2, (j1 - j0) / 4)
	var inside: bool = _mask_key.size() == 7 and i0 >= _mask_key[0] and i1 <= _mask_key[1] \
		and j0 >= _mask_key[2] and j1 <= _mask_key[3] and step == _mask_key[4] \
		and world.explored.size() == _mask_key[5] and world.settlements.size() == _mask_key[6]
	if not inside:
		var a0 := i0 - pad_x; var a1 := i1 + pad_x
		var b0 := j0 - pad_y; var b1 := j1 + pad_y
		_mask_tex = _build_mask(a0, a1, b0, b1, step, _visible_ground(a0, a1, b0, b1))
		_mask_key = [a0, a1, b0, b1, step, world.explored.size(), world.settlements.size()]
	if _view == null:
		return
	var mw: int = (_mask_key[1] - _mask_key[0]) / step + 1
	var mh: int = (_mask_key[3] - _mask_key[2]) / step + 1
	_view.set_ground_mask(_mask_tex, Vector2(_mask_key[0], _mask_key[2]) * CELL,
		Vector2(mw, mh) * float(step) * CELL, Vector2(1.0 / mw, 1.0 / mh))

const MASK_MAX := 96      # texels a side; far out a texel spans several cells, and nobody can tell

# R forest, G water, B explored — the ground's kinds and the fog's memory,
# one texel per cell (per `step` cells far out). The shader softens it; this
# only has to be right. Water is the bank ramp itself rather than
# a per-cell dithered pick, which is what makes a shore a shore.
func _build_mask(i0: int, i1: int, j0: int, j1: int, step: int, cells: Dictionary) -> ImageTexture:
	var w := (i1 - i0) / step + 1
	var h := (j1 - j0) / step + 1
	var bytes := PackedByteArray()
	bytes.resize(w * h * 3)
	var o := 0
	for y in h:
		var cy: int = j0 + y * step
		for x in w:
			var cell := Vector2i(i0 + x * step, cy)
			var wet := 0.5 - world.water_depth(Vector2(cell.x + 0.5, cell.y + 0.5) * CELL) / (SHORE * 2.0)
			var water := smoothstep(0.3, 0.7, wet)
			bytes[o] = 255 if (water < 0.5 and block_wooded(_cluster(cell, TILE_CLUSTER))) else 0
			bytes[o + 1] = int(water * 255.0)
			bytes[o + 2] = 255 if cells.has(cell) else 0
			o += 3
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes))

# The explored cells inside the viewport's cell box, as a set. Walks out from
# each remembered waypoint and each settlement beacon rather than testing every
# cell on screen, so an unwalked map costs one box intersection per waypoint.
# Every cell it yields is one world.is_explored() would have said yes to: the
# same VISION_RADIUS around the same trail, and the same beacon radius around
# the same settlements (core/world.gd).
func _visible_ground(i0: int, i1: int, j0: int, j1: int) -> Dictionary:
	# Memoised on what it depends on and nothing else: the box of cells on
	# screen, and how much trail there is to walk out from. The box is in whole
	# cells, so marching only invalidates it once every CELL units of ground
	# rather than every frame, and a camera that is sitting still (a menu, a
	# paused clock, a player reading the map) recomputes nothing at all.
	var key := [i0, i1, j0, j1, world.explored.size(), world.settlements.size()]
	if key == _ground_key:
		return _ground_set
	var out := {}
	var seeds: Array = []
	for w in world.explored:
		seeds.append([w, World.VISION_RADIUS])
	for s in world.settlements:
		seeds.append([s.position, World.SETTLEMENT_BEACON_RADIUS])
	for seed_at in seeds:
		var at: Vector2 = seed_at[0]
		var r: float = seed_at[1]
		var a0: int = maxi(i0, int(floor((at.x - r) / CELL)))
		var a1: int = mini(i1, int(ceil((at.x + r) / CELL)))
		var b0: int = maxi(j0, int(floor((at.y - r) / CELL)))
		var b1: int = mini(j1, int(ceil((at.y + r) / CELL)))
		if a0 > a1 or b0 > b1:
			continue      # this waypoint is nowhere near the screen
		var rsq: float = r * r
		for i in range(a0, a1 + 1):
			for j in range(b0, b1 + 1):
				var cell := Vector2i(i, j)
				if out.has(cell):
					continue
				if (Vector2(i + 0.5, j + 0.5) * CELL).distance_squared_to(at) <= rsq:
					out[cell] = true
	_ground_key = key
	_ground_set = out
	return out

var _ground_key: Array = []       # what _ground_set was computed for
var _ground_set: Dictionary = {}  # the explored-and-on-screen cells, memoised

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
		_draw_offscreen_marker(s.position, s.sname, faction_color(s.faction), frame, ppos)

func _draw_offscreen_marker(pos: Vector2, sname: String, col: Color, frame: Rect2, ppos: Vector2) -> void:
	var center := frame.position + frame.size * 0.5
	var to := _pix(pos) - center
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
	var tip := at + dir * OFFSCREEN_SIZE
	var side := Vector2(-dir.y, dir.x) * OFFSCREEN_SIZE * 0.62
	draw_colored_polygon(PackedVector2Array([tip, at - dir * OFFSCREEN_SIZE * 0.5 + side,
		at - dir * OFFSCREEN_SIZE * 0.5 - side]), col)
	# World units read as nothing to a player; the clock is the map's real
	# currency, so the distance is quoted as the travel time it costs at the
	# party's own speed (World.SPEED is units per world-minute).
	var p := world.player()
	var speed: float = p.speed if p != null and p.speed > 0.0 else World.SPEED
	var mins: float = ppos.distance_to(pos) / speed
	var label := "%s  %s" % [sname, _travel_time(mins)]
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

# The 2D prop tier that used to live here — _draw_settlement()'s painted
# building blocks, _draw_lair()'s "☠" glyph, _draw_building() and
# _draw_party()'s pawn sprite — is gone, with the sheet textures it read from.
# A flat sprite pasted over the map was only ever a stand-in for a model, and a
# camera that turns walks straight round the back of one. Every landmark is a
# model in the 3D view now: scenes/world/settlements3d.gd, lairs3d.gd and
# party3d.gd, each of which covers everything the game can produce (the
# settlement and lair kits build from primitives, and a band with no character
# figure marches as a 3D pawn), so there is nothing left for a fallback tier to
# cover.

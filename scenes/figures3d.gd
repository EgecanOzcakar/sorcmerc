# Tier 0 of the token pipeline: a real 3D figure standing on its hex.
#
# One transparent SubViewport, its own 3D world, laid exactly over the Board it is a
# child of. The camera is DERIVED from Board.ISO_* rather than tuned by hand, so a
# figure placed at hex H lands on the same pixels Board._pix(H) produces — and because
# positions are re-read from Board._tok (+ _lunge) every frame, figures slide, lunge,
# pan and zoom identically to the vector tokens they replace. Change ISO_SQUASH and the
# camera tilts with it; there is no second source of truth for the projection.
#
# What this layer does NOT own: shadow, active-turn ring, hit flash, HP bar, condition
# tags. Those stay in Board._draw, shared with every tier — same contract as the
# sprite tier. Layering caveat: this draws above Board._draw, so a figure can cover the
# HP bar of the hex behind it. Moving the HUD to a CanvasLayer above this is the fix;
# ~30 lines, deliberately not in the spike.
extends "res://scenes/native_layer.gd"

const Catalog = preload("res://core/rules/catalog.gd")
const Props3D = preload("res://scenes/world/props3d.gd")
const BoardProps = preload("res://scenes/board_props.gd")
# The same cache the overworld layers read through, so the hero already
# standing on the map arrives in the fight without a second trip to disk.
# See scenes/model_cache.gd.
const ModelCache = preload("res://scenes/model_cache.gd")

# A lookup, not a hardcoded
# model, because coverage will always trail the 316-entry bestiary. A key with no
# file on disk yet (roster generation is a slow background batch, see kitbashforge)
# just falls through has_figure() to the vector disc/glyph tier — that's the
# design — the vector disc/glyph draws whoever the models do not cover — not a
# bug to chase per-monster.
#
# Heroes key by class id (core/character.gd, ids from data/classes.json — all 12);
# foes by Catalog.monster(id)["faction"] (data/bestiary.json) — one look per
# faction, not per bestiary id, since Board only ever fields one faction per
# encounter (core/scaler.gd) and melee/archer variants already read as
# different by pose.
const HERO_MODELS := {
	"barbarian": "res://assets/figures/barbarian_idle.glb",
	"bard": "res://assets/figures/bard_idle.glb",
	"cleric": "res://assets/figures/cleric_idle.glb",
	"druid": "res://assets/figures/druid_idle.glb",
	"fighter": "res://assets/figures/fighter_idle.glb",
	"monk": "res://assets/figures/monk_idle.glb",
	"paladin": "res://assets/figures/paladin_idle.glb",
	"ranger": "res://assets/figures/ranger_idle.glb",
	"rogue": "res://assets/figures/rogue_idle.glb",
	"sorcerer": "res://assets/figures/sorcerer_idle.glb",
	"warlock": "res://assets/figures/warlock_idle.glb",
	"wizard": "res://assets/figures/wizard_idle.glb",
}
const FOE_MODELS := {
	"goblinoid": "res://assets/figures/goblin_idle.glb",
	"bandit": "res://assets/figures/bandit_idle.glb",
	"soldier": "res://assets/figures/soldier_idle.glb",
	"cultist": "res://assets/figures/cultist_idle.glb",
	"kobold": "res://assets/figures/kobold_idle.glb",
	"undead": "res://assets/figures/undead_idle.glb",
	# The one beast without its own file under BEAST_DIR stands in as a wolf, and
	# so does a beast band on the overworld (party3d.gd reads this table).
	"beast": "res://assets/beasts/wolf.glb",
}
# Beasts key by bestiary id, one static Meshy model each (tools/import_beasts.py
# writes assets/beasts/<id>.glb); a missing file falls through to FOE_MODELS by
# faction, then to the vector tier, same as before.
const BEAST_DIR := "res://assets/beasts/%s.glb"
# A beast arrives at whatever scale and origin Meshy chose, with no rig to
# normalise it the way the 1.2 m hero rigs are. Fit by the bestiary's size
# category instead: the model's longest extent, in rig metres, so a Medium wolf
# is about as long as a hero is tall and a rat is a rat.
const BEAST_SPAN := {"Tiny": 0.5, "Small": 1.0, "Medium": 1.5, "Large": 2.0, "Huge": 2.6, "Gargantuan": 3.2}
const FIGURE_SCALE := 1.25     # rig is 1.2 m tall, feet at y=0; ~1.5 hex radii so neighbours do not stack
const CAM_DIST := 40.0
# How far off its hex centre a prop stands, in world units (one unit = one hex
# radius). 0.42 clears a figure's shoulders without letting anything drift into
# the neighbouring hex and lie about which tile it is cover for.
const PROP_OFFSET := 0.42

var board: Control
var main
var cb
var _cam: Camera3D
var _figs := {}                # combatant id -> Node3D
var _prev := {}                # combatant id -> last world position, for facing
# #167: the board's own furniture, in the same 3D world as the figures and for
# the same reason props3d.gd's header gives for the overworld — one camera, one
# depth buffer, so a hero walking behind a tree is behind the tree. Keyed by
# what it stands for ("o3" the board's fourth object, "c2,1" the cover on that
# hex, "r4,0" the rough), because a board is rebuilt per fight and nothing here
# needs to survive one.
var _props := {}               # key -> Node3D
var _prop_hex := {}            # key -> Vector2i, the hex it stands on


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE     # clicks fall through to the Board
	_sub = SubViewport.new()
	_sub.transparent_bg = true
	_sub.own_world_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.gui_disable_input = true
	# A manually-created SubViewport gets no AA by default (the root viewport's
	# project-settings MSAA doesn't apply here) — silhouette edges and the 4k
	# texture detail both alias hard without this. Screen-space AA (FXAA) needs
	# Forward+/Mobile; this project runs GL Compatibility, so MSAA alone.
	_sub.msaa_3d = Viewport.MSAA_4X
	add_child(_sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.50, 0.53, 0.60)
	e.ambient_light_energy = 1.0
	env.environment = e
	_sub.add_child(env)

	# Key light from the upper-left, the side Board.LIGHT shades the discs from.
	var sun := DirectionalLight3D.new()
	_sub.add_child(sun)
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true

	_cam = Camera3D.new()
	_sub.add_child(_cam)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.1
	_cam.far = CAM_DIST * 4.0
	_cam.current = true


static func _model_path(c) -> String:
	return model_path_for(c.sheet, c.src_id)


# The one lookup every face on screen goes through: the board's figure and the
# portrait cut from the same model (scenes/portraits.gd, #165) must agree on
# which file that is. A hero sheet, or null and a bestiary id for a foe.
static func model_path_for(sheet, src_id: String) -> String:
	if sheet != null:
		# ResolvedCharacter.class_levels: {"rogue": 5, ...} — no single-class
		# accessor (core/resolved.gd), so take the class carrying the most levels.
		var cid := ""
		var best := -1
		for k in sheet.class_levels:
			if sheet.class_levels[k] > best:
				best = sheet.class_levels[k]; cid = k
		return String(HERO_MODELS.get(cid, ""))
	if src_id == "":
		return ""
	var by_id := BEAST_DIR % src_id
	if ModelCache.exists(by_id):
		return by_id
	return String(FOE_MODELS.get(String(Catalog.monster(src_id).get("faction", "")), ""))


# Uniform-scale a beast model to BEAST_SPAN for its bestiary size, centred on
# its hex with its lowest point on the ground. The hero/faction rigs skip this:
# Meshy normalised those to 1.2 m itself. (The one rigged beast, the ape, is
# 0.005 units tall raw, so it goes through here like the rest — _bounds() reads
# mesh space, one level up, which is the right answer for it too.)
static func fit_beast(m: Node3D, id: String) -> void:
	var aabb := Props3D._bounds(m)
	var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if extent <= 0.0001:
		return
	var k: float = float(BEAST_SPAN.get(Catalog.monster(id).get("size", "Medium"), 1.5)) / extent
	m.scale = Vector3.ONE * k
	m.position = -Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5) * k


func _model(path: String) -> PackedScene:
	return ModelCache.get_scene(path)


func has_figure(c) -> bool:
	return _figs.has(c.id)


func reset(_cb) -> void:
	cb = _cb
	for n in _figs.values():
		n.queue_free()
	_figs.clear()
	_prev.clear()
	# The whole roster's models asked for in one go, before the first one is
	# instantiated: a fight fields up to a dozen figures at ~3 MB each, and
	# read one at a time that is a visible stall on the frame the board opens.
	# Whatever the overworld already loaded (the player's own class figure, a
	# beast band's model) is a cache hit and costs nothing here.
	ModelCache.prefetch(cb.combatants.map(_model_path))
	for c in cb.combatants:
		var path := _model_path(c)
		var scene := _model(path)
		if scene == null:
			continue          # no model for this class/faction yet — vector disc/glyph tier draws it
		var holder := Node3D.new()
		_sub.add_child(holder)
		var m := scene.instantiate()
		holder.add_child(m)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap:
			var clip: String = ap.get_animation_list()[0]
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
			ap.seek(randf() * ap.get_animation(clip).length)   # desync the roster
		if path.begins_with(BEAST_DIR.get_base_dir()):
			fit_beast(m, c.src_id)
		_figs[c.id] = holder
	_reset_props()


# One prop per object, per cover hex and per rough hex. Cover and rough are the
# two things a player most needs to read off a board and were the two drawn with
# the least — a hash-picked 2D leaf blob — so they get real furniture here and
# Board._foliage_at stands down for them (see props_on).
#
# Seeded off the hex, so a row of trees is a row of different trees and the same
# board always grows the same ones.
func _reset_props() -> void:
	for n in _props.values():
		n.queue_free()
	_props.clear()
	_prop_hex.clear()
	if cb == null:
		return
	var pal := String(cb.board.get("palette", "shrine"))
	for i in cb.board.get("objects", []).size():
		var o: Dictionary = cb.board["objects"][i]
		_add_prop("o%d" % i, o["pos"], String(o["type"]))
	for hx in cb.board.get("cover", []):
		_add_prop("c%d,%d" % [hx.x, hx.y], hx, BoardProps.cover_kind(pal))
	for hx in cb.board.get("rough", []):
		_add_prop("r%d,%d" % [hx.x, hx.y], hx, BoardProps.rough_kind(pal))


func _add_prop(key: String, hx: Vector2i, kind: String) -> void:
	var holder := Node3D.new()
	_sub.add_child(holder)
	holder.add_child(BoardProps.build(kind, hash(hx)))
	_props[key] = holder
	_prop_hex[key] = hx


# Whether the 3D furniture is up, which is what Board._foliage_at asks before
# scattering its own 2D plants: two answers to "what is on this hex" drawn one
# over the other reads as neither.
func props_on() -> bool:
	return not _props.is_empty()


# --- projection: the exact inverse of Board._iso -------------------------------
#
# Board:  screen = _origin + (K*x, K*z*SQUASH)   for a ground point (x, 0, z),
#         where K = ISO_GAIN * hex_px is pixels per world unit and one world unit
#         is one hex radius. An orthographic camera tilted DOWN by theta = asin(SQUASH)
#         reproduces that squash on the ground and shows height foreshortened by
#         cos(theta), which is the right thing for a standing figure.

# A stable per-hex number in -1..1, so a prop's offset is the same every frame
# and the same on every machine.
func _prop_jitter(hx: Vector2i, salt: int) -> float:
	return (float(absi(hash([hx.x, hx.y, salt])) % 2000) / 1000.0) - 1.0


func px_per_unit() -> float:
	return board.ISO_GAIN * main.hex_px

func theta() -> float:
	return asin(board.ISO_SQUASH)

func world_for_screen(p: Vector2) -> Vector3:
	var d: Vector2 = p - board._origin
	var K := px_per_unit()
	return Vector3(d.x / K, 0.0, d.y / (K * board.ISO_SQUASH))

func screen_for_world(w: Vector3) -> Vector2:
	var K := px_per_unit()
	var th := theta()
	return board._origin + Vector2(K * w.x, K * (w.z * sin(th) - w.y * cos(th)))


func _process(_dt: float) -> void:
	if cb == null or board == null or main == null:
		return
	# Anchors alone don't track the Board (it isn't a Container): pin the rect by hand.
	position = Vector2.ZERO
	size = board.size
	present()                       # native-pixel viewport for this rect (native_layer.gd)
	var th := theta()
	var target := world_for_screen(board.size * 0.5)          # ground under the centre
	var back := Vector3(0.0, sin(th), cos(th))
	_cam.look_at_from_position(target + back * CAM_DIST, target, Vector3.UP)
	_cam.size = board.size.y / px_per_unit()                    # KEEP_HEIGHT => px/unit == K

	for c in cb.combatants:
		var n: Node3D = _figs.get(c.id)
		if n == null:
			continue
		n.visible = not c.is_dead() and not c.has("withdrawn")   # off the field is gone (the audit's 3.5)
		var p: Vector2 = board._tok.get(c.id, board._pix(c.pos)) + board._lunge(c.id)
		# #156: the token's screen position already carries its hex's rise, and
		# world_for_screen reads every pixel as a point on the ground — so the
		# lift comes back out before the conversion and goes on again in world
		# Y, where it belongs. screen_for_world maps (0, y, 0) to -K·cos(theta)·y,
		# so that product is exactly what the pixel lift divides by, and the
		# figure lands on the tile the board drew for it at any zoom.
		var lift: float = -board._rise(c.pos)          # pixels up the screen, positive
		n.position = world_for_screen(p + Vector2(0, lift))
		n.position.y = lift / maxf(0.001, px_per_unit() * cos(th))
		n.scale = Vector3.ONE * FIGURE_SCALE
		# Face the direction of travel and keep facing it on arrival. The model's
		# forward is +Z (glTF), so yaw = atan2(dx, dz). _lunge feeds in here too, so a
		# melee jab turns the figure toward its target for free. Shipped facing is
		# toward the camera, which is what an un-moved figure keeps.
		if _prev.has(c.id):
			var d: Vector3 = n.position - _prev[c.id]
			d.y = 0.0
			if d.length() > 0.004:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 0.35)
		_prev[c.id] = n.position
		n.rotation.x = deg_to_rad(-80.0) if c.is_down() else 0.0   # unconscious: lying flat

	# The furniture, by the same arithmetic and for the same reason: it stands on
	# a hex, the hex has a rise, and the board pans and zooms under both.
	#
	# Nudged off the hex centre by a seeded offset rather than planted on it. A
	# cover hex is a hex you may STAND in, and a tree drawn dead centre swallows
	# whoever is standing there — the offset leaves room for the figure and, as a
	# bonus, stops a row of props looking like a row of fence posts.
	for key in _props:
		var n: Node3D = _props[key]
		var hx: Vector2i = _prop_hex[key]
		var off := Vector2(_prop_jitter(hx, 0), _prop_jitter(hx, 1)) * PROP_OFFSET
		if cb.object_at(hx).get("blocks_movement", false):
			off = Vector2.ZERO    # nobody stands here to make room for: a wall stands centred
		var lift: float = -board._rise(hx)
		n.position = world_for_screen(board._pix(hx) + Vector2(0, lift))
		n.position.y = lift / maxf(0.001, px_per_unit() * cos(th))
		n.position.x += off.x
		n.position.z += off.y

# Every roaming party, player included, as a figure walking the shared 3D
# world. The rig it lives in belongs to scenes/world/world_view3d.gd and the
# shared parts to scenes/world/props3d.gd; this file owns what is
# party-specific: picking a model from the party's highest-leveled troop
# (RoamingParty.highest_troop(), core/world.gd), facing the direction of
# travel, and walking. Parties move; settlements and lairs don't, so this is
# the one layer that needs either — same lerp_angle trick Figures3D uses on
# the combat board.
#
# T9x: the player picks one of their own active party on the Party screen
# (core/party.gd's overworld_figure — a member id) and that character's class
# figure from HERO_MODELS stands for the band. Bench them, or pick nobody, and
# has_model() goes false and the band marches as a pawn instead — a turned
# board-game piece in its faction's colour, built here out of primitives.
#
# That pawn used to be a flat painted sprite drawn over the map by
# World._draw_party(). It is a real one now for the same reason everything else
# on this map is: a camera that turns walks straight round the back of a
# billboard. It is the only tier below a character model, and every band that
# has no figure — a monster faction the art has never covered, a player with
# nobody marching — gets it.
#
# ponytail — the walk is procedural, not animated. Every model this project
# generates (assets/troops/*_idle.glb, assets/figures/*_idle.glb) ships
# exactly one clip, an idle, so a marching party would otherwise glide across
# the map standing perfectly still. The GAIT_* block below fakes it: a
# vertical bob and a counter-rotating sway on a sine whose cadence comes from
# how far the figure actually moved this frame. At map zoom that reads as
# walking; up close it is obviously not one, because the legs never move.
# The real fix is a `walk` clip out of the same generator that made the
# idles — then delete the GAIT_* constants, _gait_pose() and its two state
# dicts, keep reposition()'s position/facing lines, and cross-fade
# ap.play("walk") on the same moving/stopped signal this already computes.
#
# What this layer does NOT own: the footprint under the band — its shadow, and
# the gold halo that marks the player's own — which is shared with every other
# landmark (scenes/world/ground_marks3d.gd), or the name and headcount label
# above it (World._draw()).
extends "res://scenes/world/props3d.gd"

# Monster-faction parties (goblinoid, bandit, undead, ...) have no race and no
# troops-with-roles — they get the same single figure-per-faction combat
# already uses (figures3d.gd's FOE_MODELS), reused as-is rather than
# duplicated: one lookup, not two art pipelines for the same monster.
const FoeModels := preload("res://scenes/figures3d.gd").FOE_MODELS
const HeroModels := preload("res://scenes/figures3d.gd").HERO_MODELS
# For World.SPEED only — the gait quotes its cadence against the real marching
# speed rather than re-declaring a number that would drift away from it.
const WorldModel := preload("res://core/world.gd")

# core/world.gd's RoamingParty.faction is a Scaler.FACTIONS combat faction
# (bandit, goblinoid, human, orc, ...), not one of the four races the troop
# figures were generated for — most factions (goblinoid, undead, ...) have no
# race counterpart at all, and that's fine: they fall through to the 3D pawn,
# same as any other uncovered lookup here. Only the factions that plausibly
# *are* one of the four races are mapped.
const RACE_FOR_FACTION := {
	"human": "human", "bandit": "human", "soldier": "human",
	"orc": "orc", "dwarf": "dwarf", "elf": "elf",
}
const MODELS := {
	"dwarf": {"heavy": "res://assets/troops/dwarf_heavy_idle.glb", "light": "res://assets/troops/dwarf_light_idle.glb", "spellcaster": "res://assets/troops/dwarf_spellcaster_idle.glb"},
	"elf": {"heavy": "res://assets/troops/elf_heavy_idle.glb", "light": "res://assets/troops/elf_light_idle.glb", "spellcaster": "res://assets/troops/elf_spellcaster_idle.glb"},
	"human": {"heavy": "res://assets/troops/human_heavy_idle.glb", "light": "res://assets/troops/human_light_idle.glb", "spellcaster": "res://assets/troops/human_spellcaster_idle.glb"},
	"orc": {"heavy": "res://assets/troops/orc_heavy_idle.glb", "light": "res://assets/troops/orc_light_idle.glb", "spellcaster": "res://assets/troops/orc_spellcaster_idle.glb"},
}
const TARGET_HEIGHT := 15.0   # a person, not a building — smaller than any settlement/lair tier

# --- the pawn -------------------------------------------------------------
# A turned board-game piece: foot, waist, body, head. Built from primitives the
# way scenes/world/kit_parts.gd builds a settlement, so it ships as a dozen
# lines rather than a file, and tinted per band so whose army it is still reads
# at a glance — which is the one job the flat sprite it replaces actually did.
const PAWN_TRIS := 6          # radial segments: a low count is the look, not a budget
# The turned body, bottom up: radius at the top, radius at the bottom, height,
# and the centre height it sits at. One unit tall in total, so _fit_height()'s
# TARGET_HEIGHT is the pawn's height in world units the same way it is a
# figure's.
const PAWN_SHAPE := [
	[0.34, 0.42, 0.10, 0.05],   # foot
	[0.12, 0.30, 0.16, 0.18],  # waist
	[0.16, 0.13, 0.42, 0.47],  # body
]
const PAWN_HEAD_Y := 0.80
const PAWN_HEAD_R := 0.19

func _pawn(p) -> Node3D:
	var root := Node3D.new()
	root.name = "pawn"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = world_map.faction_color(p.faction, p.is_player)
	mat.roughness = 0.85
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for part in PAWN_SHAPE:
		var seg := CylinderMesh.new()
		seg.top_radius = part[0]
		seg.bottom_radius = part[1]
		seg.height = part[2]
		seg.radial_segments = PAWN_TRIS + 2
		seg.rings = 0
		root.add_child(_piece(seg, part[3], mat))
	var head := SphereMesh.new()
	head.radius = PAWN_HEAD_R
	head.height = PAWN_HEAD_R * 2.0
	head.radial_segments = PAWN_TRIS + 2
	head.rings = 4
	root.add_child(_piece(head, PAWN_HEAD_Y, mat))
	return root


static func _piece(mesh: Mesh, y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	return mi


# --- procedural walk (see the ponytail note in the header) -----------------
# Tuned for a 15-unit figure read at map zoom: enough to say "walking", small
# enough that nothing reads as a bouncing spring. Speed here is map units per
# real second, which is exactly what World.SPEED is — so the clock's 2x/4x/8x
# arrive as genuinely faster figures with no second multiplier to keep in sync.
const REF_SPEED := WorldModel.SPEED   # 1x marching speed: the yardstick for both cadence and amplitude
const GAIT_HZ := 1.4          # full strides per second at REF_SPEED (two footfalls each) — a brisk human cadence
const GAIT_HZ_EXP := 0.5      # cadence grows as sqrt(speed), the Froude relation real gaits follow: 8x clock hurries ~2.8x, it doesn't strobe
const BOB_HEIGHT := 0.42      # world units at full stride, ~3% of TARGET_HEIGHT — the hip rise of a real walk, and all this zoom can carry
const SWAY_RAD := 0.045       # ~2.6° of trunk roll, alternating with the stride so the weight reads as shifting from leg to leg
const LEAN_RAD := 0.035       # ~2° of steady pitch into the direction of travel — a body pushing forward, not a statue sliding
const GAIT_RAMP := 4.0        # gait weight per second: ~0.25s to spin up and the same to settle, so stopping eases into the idle pose
const IDLE_SPEED_GAIN := 0.35 # the idle clip runs up to 35% faster while moving — nudged along with the motion rather than fought

var _figs := {}                # party id -> Node3D (every band has one)
var _models := {}              # ...of those, the ids wearing a real character model, not the pawn
var _prev := {}                # party id -> last world position: drives facing, and the gait's speed
var _aps := {}                 # party id -> the model's idle AnimationPlayer, nudged with the walk
var _gait := {}                # party id -> how much walk is showing, 0 (idle pose) .. 1 (full stride)
var _step := {}                # party id -> gait phase, radians — seeded per party, never shared
var _frame_dt := 0.0           # real seconds since the last frame; see reposition()


func _model_path(p) -> String:
	if p.is_player:
		return String(HeroModels.get(_player_figure(), ""))
	var race := String(RACE_FOR_FACTION.get(p.faction, ""))
	var role := String(p.highest_troop().get("role", ""))
	if race != "" and role != "":
		var by_role := String(MODELS.get(race, {}).get(role, ""))
		if by_role != "":
			return by_role
	# Monster factions (goblinoid, bandit, undead, ...): no race/role, one
	# figure per faction, same source as combat.
	return String(FoeModels.get(p.faction, ""))


# Which HERO_MODELS class the player's figure wears, "" for the pawn.
# core/party.gd's overworld_member() picks the person: the player's choice
# while it is still marching (migrating a pre-identity save's class id on the
# way), else the highest-level marcher, else nobody. Enforced here and not
# only in the Party screen's picker, so a choice that goes stale between
# visits can't leave a figure on the map that nobody in the party answers for.
func _player_figure() -> String:
	if world_map.party == null:
		return ""
	var ch = world_map.party.overworld_member()
	if ch == null:
		return ""
	var cid: String = ch.class_id()
	return cid


# Whether this band wears a real character model, as opposed to the pawn.
# Every band has a figure of some kind, so this is not "is there anything
# standing here" — it is the question the Party screen's figure picker and
# tests/test_party3d.gd actually ask.
func has_model(p) -> bool:
	return _models.has(p.id)


func reset(world) -> void:
	for n in _figs.values():
		n.queue_free()
	_figs.clear()
	_models.clear()
	_prev.clear()
	_aps.clear()
	_gait.clear()
	_step.clear()
	_models.clear()
	for p in world.parties:
		var holder := Node3D.new()
		add_child(holder)
		var scene := _model(_model_path(p))
		var m: Node3D
		if scene == null:
			m = _pawn(p)
		else:
			m = scene.instantiate()
			_models[p.id] = true
		holder.add_child(m)
		_fit_height(m, TARGET_HEIGHT)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap:
			var clip: String = ap.get_animation_list()[0]
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
			ap.seek(randf() * ap.get_animation(clip).length)   # desync the roster
			_aps[p.id] = ap
		# Desynced for the same reason the seek above is, and the same way:
		# two bands crossing the map together must never bob in lockstep.
		_step[p.id] = randf() * TAU
		_figs[p.id] = holder


# One party's walk for this frame, advanced by `dt` seconds at `speed` map
# units/second: returns the pose to hold as (bob height, sway roll, forward
# lean). Split out of reposition() because it is the entire stand-in in one
# place — the thing a real walk clip deletes — and because it can then be
# driven with fixed deltas by a headless test.
func _gait_pose(id: String, speed: float, dt: float) -> Vector3:
	var w: float = _gait.get(id, 0.0)
	var ph: float = _step.get(id, 0.0)
	# Amplitude saturates at REF_SPEED: a party at 8x steps faster, it does
	# not bob higher. move_toward rather than lerp so rest is actually
	# reached instead of approached forever — "settled" has to mean exactly
	# the idle pose, not almost.
	w = move_toward(w, clampf(speed / REF_SPEED, 0.0, 1.0), GAIT_RAMP * dt)
	if speed > 0.0:
		ph = fposmod(ph + TAU * GAIT_HZ * pow(speed / REF_SPEED, GAIT_HZ_EXP) * dt, TAU)
	_gait[id] = w
	_step[id] = ph
	# The bob runs at twice the sway — one rise per footfall, one weight shift
	# per full stride, which is the real relationship between the two and why
	# they don't read as a single wobble. sin^2 (not |sin|) so the bottom of
	# each step is smooth, and never dips below where the feet rest.
	return Vector3(
		BOB_HEIGHT * w * (0.5 - 0.5 * cos(2.0 * ph)),
		SWAY_RAD * w * sin(ph),
		LEAN_RAD * w)


func reposition() -> void:
	# reposition() takes no delta: the signature is shared with Settlements3D
	# and Lairs3D, neither of which has any use for one. The gait does, and the
	# frame's own delta is already on the node.
	_frame_dt = get_process_delta_time()

	# A defeated party is erased from world.parties (core/world.gd, core/
	# world_battle.gd) — reset() only rebuilds _figs at travel start, so
	# without this the figure it left behind just stops being repositioned:
	# still in the tree, still visible, frozen where it died forever.
	if not _figs.is_empty():
		var live := {}
		for p in world_map.world.parties:
			live[p.id] = true
		for id in _figs.keys().duplicate():
			if not live.has(id):
				_figs[id].queue_free()
				_figs.erase(id)
				_prev.erase(id)
				_aps.erase(id)
				_gait.erase(id)
				_step.erase(id)

	for p in world_map.world.parties:
		var n: Node3D = _figs.get(p.id)
		if n == null:
			continue
		# T9x fog of war: everyone else is fog-gated; the player is exempt —
		# same "you can always see yourself" rule World._draw()'s 2D props
		# loop already applies. band_seen(), not _explored(): a watchtower's
		# watch marks a band drawn on the ground too (core/world.gd).
		n.visible = p.is_player or world_map.world.band_seen(p.position)
		# The band's own position on the map's floor. It used to be
		# world_for_screen(_pix(pos)) — a round trip out to a screen pixel and
		# back, which the old per-layer camera needed and which cancelled to
		# exactly this. One consequence worth keeping in mind either way: the
		# delta below is travel, never camera movement, so dragging the map
		# does not set anybody walking.
		var here := at(p.position)
		var moved := 0.0
		# Same trick as Figures3D: face the direction of travel, hold it on
		# arrival. The model's forward is +Z (glTF), so yaw = atan2(dx, dz).
		if _prev.has(p.id):
			var d: Vector3 = here - _prev[p.id]
			d.y = 0.0
			moved = d.length()
			if moved > 0.01:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 0.15)
		_prev[p.id] = here   # the rest pose, never the bobbed one: the gait must not feed itself
		var pose := _gait_pose(p.id, moved / maxf(_frame_dt, 0.0001), _frame_dt)
		n.position = here + Vector3(0.0, pose.x, 0.0)   # pose.x: the bob
		n.rotation.z = pose.y                         # pose.y: the sway, a roll about the figure's own forward axis
		n.rotation.x = pose.z                         # pose.z: the lean, a pitch into the direction of travel
		# Let the idle clip hurry along with the body instead of fighting it —
		# it keeps its own desynced phase, only the rate moves.
		var ap: AnimationPlayer = _aps.get(p.id)
		if ap != null:
			ap.speed_scale = 1.0 + IDLE_SPEED_GAIN * float(_gait.get(p.id, 0.0))

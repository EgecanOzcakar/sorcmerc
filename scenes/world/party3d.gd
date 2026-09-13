# Tier 0 for every roaming party, player included: a real 3D figure
# standing where World draws the flat PawnTex icon. Shared SubViewport/camera/
# projection rig lives in world_diorama3d.gd (also used by Settlements3D and
# Lairs3D) — this file only owns what's party-specific: picking a model from
# the party's highest-leveled troop (RoamingParty.highest_troop(), core/
# world.gd), and facing the direction of travel (parties move; settlements
# and lairs don't, so this is the one diorama layer that needs it — same
# lerp_angle trick Figures3D uses on the combat board).
#
# T9x: the player picks their own figure from HERO_MODELS on the Party
# screen (core/party.gd's overworld_figure) — a free choice, not derived
# from the active roster's classes. "" (never picked, or explicitly reset)
# falls through has_model() to the flat, gold-ringed pawn, same contract as
# every other uncovered lookup here.
#
# What this layer does NOT own: the shadow ellipse World._draw_party() draws
# — that stays shared, same contract as Settlements3D/Lairs3D. This only
# replaces the PawnTex sprite (and the faction-tint that comes with it).
extends "res://scenes/world/world_diorama3d.gd"

# Monster-faction parties (goblinoid, bandit, undead, ...) have no race and no
# troops-with-roles — they get the same single figure-per-faction combat
# already uses (figures3d.gd's FOE_MODELS), reused as-is rather than
# duplicated: one lookup, not two art pipelines for the same monster.
const FoeModels := preload("res://scenes/figures3d.gd").FOE_MODELS
const HeroModels := preload("res://scenes/figures3d.gd").HERO_MODELS

# core/world.gd's RoamingParty.faction is a Scaler.FACTIONS combat faction
# (bandit, goblinoid, human, orc, ...), not one of the four races the troop
# figures were generated for — most factions (goblinoid, undead, ...) have no
# race counterpart at all, and that's fine: they fall through to the PawnTex
# icon, same as any other uncovered lookup this session. Only the factions
# that plausibly *are* one of the four races are mapped.
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

var _figs := {}                # party id -> Node3D
var _prev := {}                # party id -> last world position, for facing


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


# The chosen figure only counts while someone in the active party actually
# is that class — enforced here, not just in the Party screen's picker, so
# a stale choice (the character it pointed to got benched, or an old save)
# can't leave a figure on the map that no longer matches who's in the party.
func _player_figure() -> String:
	var party = world_map.party
	if party == null:
		return ""
	var fig := String(party.overworld_figure)
	if fig == "":
		return ""
	for id in party.active:
		var ch = party.get_member(id)
		if ch != null and ch.class_id() == fig:
			return fig
	return ""


func has_model(p) -> bool:
	return _figs.has(p.id)


func reset(world) -> void:
	for n in _figs.values():
		n.queue_free()
	_figs.clear()
	_prev.clear()
	for p in world.parties:
		var scene := _model(_model_path(p))
		if scene == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		var m := scene.instantiate()
		holder.add_child(m)
		_fit_height(m, TARGET_HEIGHT)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap:
			var clip: String = ap.get_animation_list()[0]
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
			ap.seek(randf() * ap.get_animation(clip).length)   # desync the roster
		_figs[p.id] = holder


func _reposition() -> void:
	for p in world_map.world.parties:
		var n: Node3D = _figs.get(p.id)
		if n == null:
			continue
		# T9x fog of war: everyone else is fog-gated; the player is exempt —
		# same "you can always see yourself" rule World._draw()'s 2D props
		# loop already applies.
		n.visible = p.is_player or _explored(p.position)
		n.position = world_for_screen(world_map._pix(p.position))
		# Same trick as Figures3D: face the direction of travel, hold it on
		# arrival. The model's forward is +Z (glTF), so yaw = atan2(dx, dz).
		if _prev.has(p.id):
			var d: Vector3 = n.position - _prev[p.id]
			d.y = 0.0
			if d.length() > 0.01:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 0.15)
		_prev[p.id] = n.position

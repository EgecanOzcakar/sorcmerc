# A band that is outmatched runs (core/world_flee.gd, core/world_ai.gd's
# _flee_step). The model only, headless: the gauge prices every band off the
# same number its fights are built with, a band runs from a stronger player or
# band that would fight it, keeps running until it is clear, and never hunts
# what it would run from; nobody runs while every band is an even fight.
#   godot --headless --path . -s tests/test_world_flee.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldFlee = preload("res://core/world_flee.gd")
const Regions = preload("res://core/regions.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party_at(level: int) -> Party:
	var p = Party.new()
	for ch in Presets.party_at(level):
		p.add_member(ch)
	return p

# test_regions.gd's map: 1000 units across, so the heartland runs to 500, the
# marches to 710, the frontier to 870.
func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_lair(World.Lair.new("edge", Vector2(1000, 0), "dragon"))
	return w

func _band(w: World, id: String, pos: Vector2, faction: String) -> World.RoamingParty:
	var b = w.add_party(World.RoamingParty.new(id, pos, faction))
	WorldAI.hunt(b)
	return b

# Moving away from `from`: the goal is further from it than the band stands.
func _away(b, from: Vector2) -> bool:
	return b.goal.distance_to(from) > b.position.distance_to(from) + 1.0

func _init() -> void:
	FactionOpinion.reset()
	var seven := _party_at(7)
	var three := _party_at(3)

	# --- the gauge is the fight's own number --------------------------------
	var w := _world()
	var home := _band(w, "home", Vector2(300, 0), "goblinoid")      # heartland
	var march := _band(w, "march", Vector2(600, 0), "orc")          # marches
	var front := _band(w, "front", Vector2(800, 0), "giant")        # frontier
	var g: Dictionary = WorldFlee.gauge(w, seven)
	for b in [home, march, front]:
		check(is_equal_approx(float(g[b.id]), Regions.power_scale(w, b.position, seven)),
			"%s is gauged at exactly the power_scale its fights are built with" % b.id)
	check(float(g["home"]) < WorldFlee.FLEE_BELOW, "a level-7 party has outgrown the heartland: %.2f" % g["home"])
	check(float(g["march"]) > WorldFlee.FLEE_BELOW and float(g["march"]) < 1.0, "...the marches are thinner but stand: %.2f" % g["march"])
	check(is_equal_approx(float(g["front"]), 1.0), "...and the frontier is its own level: an even fight")
	var g3: Dictionary = WorldFlee.gauge(w, three)
	for b in [home, march]:
		check(is_equal_approx(float(g3[b.id]), 1.0), "at level 3 the %s band is an even fight" % b.id)
	check(WorldFlee.gauge(w, Party.new()).is_empty(), "no heroes, no gauge")
	check(is_equal_approx(Regions.scale_for(w, Vector2(300, 0), Regions.party_level(seven), Regions.fresh_score(seven)),
		Regions.power_scale(w, Vector2(300, 0), seven)), "scale_for is power_scale with the party read once")

	# --- a weak band runs from the party; an even one comes for it ----------
	w = _world()
	var player = w.add_party(World.RoamingParty.new("player", Vector2(300, 0), "human", true))
	var gobs := _band(w, "gobs", Vector2(350, 0), "goblinoid")
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(WorldAI.is_fleeing(gobs) and _away(gobs, player.position), "outmatched goblins in sight of a level-7 party run")
	w.band_strength = WorldFlee.gauge(w, three)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(gobs), "the same goblins against a level-3 party do not")
	check(gobs.goal.distance_to(player.position) < 1.0, "...they hunt it, as before")
	w.band_strength = {}
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(gobs), "a band nobody has gauged yet is an even fight: it stands")

	# --- it keeps running until it is clear, then stops -------------------
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	gobs.position = player.position + Vector2((WorldFlee.SIGHT + WorldFlee.CLEAR) * 0.5, 0)
	WorldAI.update(w)
	check(WorldAI.is_fleeing(gobs), "past SIGHT but short of CLEAR, a running band keeps running")
	gobs.position = player.position + Vector2(WorldFlee.CLEAR + 20.0, 0)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(gobs), "clear of the party, it stops")
	check(gobs.goal.distance_to(player.position) > 1.0, "...and does not turn round and hunt what it would run from")

	# --- a fresh band beyond SIGHT does not notice ------------------------
	var far := _band(w, "far", player.position + Vector2(0, WorldFlee.SIGHT + 40.0), "goblinoid")
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(far), "a band that has not seen the party yet does not run")
	check(far.goal.distance_to(player.position) > 1.0, "...nor does it hunt a party it is too weak for")

	# --- a friendly patrol has nothing to run from; an enemy faction's does ---
	w = _world()
	player = w.add_party(World.RoamingParty.new("player", Vector2(300, 0), "human", true))
	var patrol = w.add_party(World.RoamingParty.new("patrol", Vector2(340, 0), "human"))
	WorldAI.patrol(patrol, [Vector2(340, 0), Vector2(340, 200)])
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(patrol), "a friendly patrol, however weak, does not run from the party")
	FactionOpinion.set_opinion("human", FactionOpinion.HOSTILE - 1.0)
	check(WorldAI.is_hostile(patrol, player), "setup: the humans have turned on the party")
	WorldAI.update(w)
	check(WorldAI.is_fleeing(patrol) and _away(patrol, player.position), "an enemy faction's weak patrol runs from it too")
	FactionOpinion.reset()

	# --- bands run from bands ----------------------------------------------
	# Across the heartland/marches seam at 500: against a level-7 party the
	# heartland side is a 0.38 band and the marches side a 0.86 one.
	w = _world()
	w.add_party(World.RoamingParty.new("player", Vector2(-900, 0), "human", true))   # well out of it
	var weak_gobs := _band(w, "weak-gobs", Vector2(485, 0), "goblinoid")   # heartland
	var guards = w.add_party(World.RoamingParty.new("guards", Vector2(530, 0), "human"))   # marches
	WorldAI.patrol(guards, [Vector2(530, 0), Vector2(530, 200)])
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(WorldAI.is_fleeing(weak_gobs) and _away(weak_gobs, guards.position),
		"weak goblins run from a stronger patrol they would fight")
	check(not WorldAI.is_fleeing(guards), "...and the stronger patrol does not run from them")

	w = _world()
	w.add_party(World.RoamingParty.new("player", Vector2(-900, 0), "human", true))
	var weak_guards = w.add_party(World.RoamingParty.new("weak-guards", Vector2(485, 0), "human"))   # heartland
	WorldAI.patrol(weak_guards, [Vector2(485, 0), Vector2(485, 200)])
	var gnolls := _band(w, "gnolls", Vector2(530, 0), "gnoll")   # marches
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(WorldAI.is_fleeing(weak_guards) and _away(weak_guards, gnolls.position),
		"a weak patrol runs from a stronger warband")
	check(not WorldAI.is_fleeing(gnolls), "...which does not run from it")

	w = _world()
	w.add_party(World.RoamingParty.new("player", Vector2(-900, 0), "human", true))
	var even_gobs := _band(w, "even-gobs", Vector2(600, 0), "goblinoid")
	var even_guards = w.add_party(World.RoamingParty.new("even-guards", Vector2(640, 0), "human"))
	WorldAI.patrol(even_guards, [Vector2(640, 0), Vector2(640, 200)])
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(even_gobs) and not WorldAI.is_fleeing(even_guards),
		"two bands of one country are an even match: neither runs")

	w = _world()
	w.add_party(World.RoamingParty.new("player", Vector2(-900, 0), "human", true))
	var a := _band(w, "orc-a", Vector2(485, 0), "orc")
	var b := _band(w, "orc-b", Vector2(530, 0), "orc")
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(not WorldAI.is_fleeing(a), "monsters do not fight monsters, so a weak one has nothing to run from")

	# --- a raider backed against water has not "arrived" anywhere -----------
	w = _world()
	player = w.add_party(World.RoamingParty.new("player", Vector2(300, 0), "human", true))
	var raider := _band(w, "raider", Vector2(340, 0), "goblinoid")
	WorldAI.raid(raider, Vector2(300, 300), "riverhold", "edge")
	w.band_strength = WorldFlee.gauge(w, seven)
	WorldAI.update(w)
	check(WorldAI.is_fleeing(raider), "setup: the raider runs from the party")
	raider.ai["dest"] = raider.position   # cornered: its flee point snapped onto itself
	check(not WorldAI.arrived(raider), "a running raider never reads as arrived, so raids.gd cannot advance its phase")

	print("test_world_flee: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

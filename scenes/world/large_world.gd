# T-worlds: the large map — same four races, same mechanics (settlements,
# lairs, roaming-party troop rosters) as World's small map, just more of
# each and spread over a wider span. Split into its own file instead of
# growing world.gd's _small_world() in place, since "more content" is the
# whole point here, not more logic.
#
#   var w := LargeWorld.build()
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Landmarks = preload("res://core/landmarks.gd")
const WorldBands = preload("res://core/world_bands.gd")

static func build() -> World:
	var w := World.new()
	w.origin = {"kind": "large", "seed": 0}   # hand-placed: no seed to remember

	# Two settlements per race instead of one — a city/capital plus an outlying
	# town or camp, so a faction reads as an actual territory, not one dot.
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "human", "city"))
	w.add_settlement(World.Settlement.new("oakford", Vector2(900, -300), "human", "town"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(1050, -450), "elf", "town"))
	w.add_settlement(World.Settlement.new("silverleaf", Vector2(-600, -900), "elf", "camp"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-900, 650), "dwarf", "camp"))
	w.add_settlement(World.Settlement.new("ironhold", Vector2(-1400, 100), "dwarf", "town"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(400, 1175), "orc", "city"))
	w.add_settlement(World.Settlement.new("skarrow", Vector2(1500, 900), "orc", "town"))

	w.add_party(World.RoamingParty.new("player", Vector2(200, 300), "human", true))

	var bandits_n := w.add_party(World.RoamingParty.new("bandits-north", Vector2(-625, -300), "bandit"))
	bandits_n.troops = [{"role": "heavy", "level": 3}, {"role": "light", "level": 5}]
	WorldAI.hunt(bandits_n)
	var bandits_e := w.add_party(World.RoamingParty.new("bandits-east", Vector2(1000, 700), "bandit"))
	bandits_e.troops = [{"role": "heavy", "level": 4}, {"role": "spellcaster", "level": 3}]
	WorldAI.hunt(bandits_e)
	var goblins_s := w.add_party(World.RoamingParty.new("goblins-south", Vector2(950, 750), "goblinoid"))
	goblins_s.troops = [{"role": "heavy", "level": 1}, {"role": "heavy", "level": 1}, {"role": "light", "level": 2}]
	WorldAI.hunt(goblins_s)
	var goblins_f := w.add_party(World.RoamingParty.new("goblins-far", Vector2(1800, -200), "goblinoid"))
	goblins_f.troops = [{"role": "light", "level": 3}]
	WorldAI.hunt(goblins_f)
	var wolves := w.add_party(World.RoamingParty.new("wolves", Vector2(500, -650), "beast"))
	wolves.troops = [{"role": "light", "level": 2}, {"role": "light", "level": 2}, {"role": "light", "level": 3}]
	WorldAI.hunt(wolves)

	# Waypoints still start/end on the settlement gates; the party's own
	# position is nudged off so its label doesn't sit on top of the town's.
	var patrol_w := w.add_party(World.RoamingParty.new("patrol-west", Vector2(-860, 610), "human"))
	patrol_w.troops = [{"role": "heavy", "level": 2}, {"role": "heavy", "level": 2}]
	WorldAI.patrol(patrol_w, [Vector2(-900, 650), Vector2(-1400, 100), Vector2(0, 0)])
	var patrol_e := w.add_party(World.RoamingParty.new("patrol-east", Vector2(440, 1135), "orc"))
	patrol_e.troops = [{"role": "heavy", "level": 4}]
	WorldAI.patrol(patrol_e, [Vector2(400, 1175), Vector2(1500, 900)])

	# One lake+river, same shape as the small map's, scaled to this map's span.
	w.add_water(Vector2(-475, -175), 160.0)
	var river := PackedVector2Array([Vector2(-275, -50), Vector2(-100, 250),
		Vector2(-25, 525), Vector2(150, 800), Vector2(350, 1000)])
	for i in river.size() - 1:
		for t in 6:
			w.add_water(river[i].lerp(river[i + 1], t / 6.0), 60.0)
	w.add_water(river[-1], 60.0)

	# All five named lairs (T91) — the two with no diorama yet still work,
	# just draw the flat skull marker (Lairs3D falls through cleanly).
	# D6.1: was (1400, 150) — frac 0.71, the Frontier, same misfiling the small map
	# had. Pulled in to frac 0.39 so the Heartland has a lair of its own.
	w.add_lair(World.Lair.new("goblin-warren", Vector2(700, 300), "goblinoid"))
	w.add_lair(World.Lair.new("giant-hold", Vector2(-1300, -650), "giant"))
	w.add_lair(World.Lair.new("sunken-ruins", Vector2(-700, -850), "undead", "Sunken Ruins"))
	w.add_lair(World.Lair.new("zombie-graveyard", Vector2(750, 1550), "undead", "Zombie Graveyard"))
	w.add_lair(World.Lair.new("dragon-cave", Vector2(1700, -1000), "dragon", "Dragon's Cave"))
	Landmarks.place(w, 43)   # a fixed seed: the large map is hand-placed, and so are its landmarks
	WorldBands.seed(w, 43)   # #163: fill the roads to the cap, around the bands above
	return w

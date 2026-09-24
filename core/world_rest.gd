# The world goes on while the company sleeps. A long rest is eight hours of
# world clock, and the bible's price for it (design bible, "Long rests are
# expensive") was always "during which bands keep walking and markets
# restock" — but the eight hours went straight onto clock.elapsed, and roaming
# bands only move inside World.tick(), so nobody walked during the night. The
# design audit (docs/audit-game-design.md §1.7) called that a side door: a
# night cost nothing the map could see.
#
#   var lines := WorldRest.pass_time(world, party, 480.0, each)   # returns raid lines to show
#
# pass_time() runs the night in CHUNK-minute steps, doing per step what the
# map screen's _process() does per frame for the parts that are world rather
# than screen: every band re-plans (WorldAI.update) and walks (World.
# move_toward_goal, so water is respected hop by hop), opinion drains and
# drifts (FactionOpinion.tick, PartyOpinion.decay), and raids set out,
# besiege and land (Raids.tick). Markets need nothing: their restock is read
# off the clock whenever a market is next opened. `each`, when given, is
# called with the step's minutes after each step — the map passes its
# off-screen battles there (core/world_battle.gd needs the screen's
# encounter_spec(), which this file cannot own).
#
# The sleeping company itself does not move and is not hunted: WorldAI.update
# is told it is asleep, so a hunter keeps to whatever else it can see and a
# siege does not come out for it. That is what keeps a rest from being broken
# in the middle: nothing here can open the player's encounter (that is the
# screen's _check_encounter, which runs after the rest, in the morning), and
# the camp's one interruption is still the ambush roll core/world_camp.gd
# makes before the night starts. A band whose own walk ends near the camp is
# met in the morning like any band on the road.
#
# What this file does NOT own: the rest's benefits (core/settlement_visit.gd's
# rest() and Adapter.rest), the camp's risk (core/world_camp.gd), how a band
# chooses where to go (core/world_ai.gd), and the time-stamped catch-ups the
# screen already runs every frame off the clock alone — lair expiry and
# respawn, band respawn and refill, potion and trait expiry. Those read
# "has the time come" and so need no stepping; the first frame after the rest
# settles them.
# ponytail: a short rest (an hour) still jumps the clock without stepping it.
# Step it too if an hour's march by the bands ever turns out to matter.
extends RefCounted

const WorldAI = preload("res://core/world_ai.gd")
const Raids = preload("res://core/raids.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")

# One world-minute a step. A band walks World.SPEED (40) map units a minute, so
# a step is a little over three WATER_STEP hops and two closing bands are at
# most 80 units nearer each step — the screen's _trigger(dt) widens the
# off-screen battle reach by exactly that, so nobody walks through anybody. At
# 480 steps a night it is well under a frame's work on a full map.
const CHUNK := 1.0

static func pass_time(world, party, minutes: float, each := Callable()) -> Array:
	var lines: Array = []
	var me = world.player()
	var left := minutes
	while left > 0.0:
		var dt := minf(CHUNK, left)
		left -= dt
		world.clock.elapsed += dt   # the rest's own minutes, paused clock or not: a visit holds the map, not the night
		WorldAI.update(world, dt, me)
		for q in world.parties:
			if q != me:
				world.move_toward_goal(q, dt)
		FactionOpinion.tick(world, dt)
		if party != null:
			PartyOpinion.decay(party, dt)
		lines.append_array(Raids.tick(world, world.clock.elapsed))
		if each.is_valid():
			each.call(dt)
	if party != null:
		party.world_now = world.clock.elapsed
	return lines

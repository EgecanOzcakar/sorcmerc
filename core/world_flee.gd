# A band that is outmatched runs. A goblin pack that would field a third of an
# even fight used to hunt a level-9 party across the heartland like any other,
# and a warband walked into a patrol it could not beat because nothing told it
# not to. Now every band sizes up whatever would fight it on contact (the
# player, or another band) and turns away from anything it is too weak for.
#
#   WorldFlee.gauge(world, party)         # map screen, every GAUGE_MINUTES:
#                                         # fills world.band_strength
#   WorldFlee.outmatched(world, a, b)     # core/world_ai.gd: should a run from b?
#
# STRENGTH IS THE FIGHT, NOT THE HEADCOUNT. A band's `troops` are a label and a
# model pick (core/world_bands.gd); no roster is ever built from them. Every
# fight a band takes part in, the player's and the off-screen ones
# core/world_battle.gd resolves, is built by core/scaler.gd for the party,
# multiplied by Regions.power_scale for where the band stands. So that
# multiplier IS the band's strength, in the party's own units: the player is
# 1.0, a band inside its country's level range is 1.0 (an even fight, built to
# be one), and a band the party has outlevelled is less. Reading the troops
# instead would have a band flee from a fight it would in fact win, and stand
# its ground in one the scaler has already decided it loses.
#
# What that means, per country: a band runs from the party once the party has
# outgrown its country's top level by enough to take its fight under
# FLEE_BELOW. Measured 2026-09-24 with Scaler.held_at over Presets.party_at(L),
# against each country's top (a built party prices higher and gets there a
# little sooner):
#
#   heartland (1-3):  L4 0.87   L5 0.54 <- runs from here
#   marches   (3-6):  L9 0.71   L10 0.67   L11 0.58 <- runs from here
#   frontier  (6-9):  L12 0.79  L13 0.71   L14 0.68 (runs a little later)
#
# And between bands the same way: once the party has outlevelled the heartland,
# a heartland pack is a 0.54 band and a marches warband a 1.0 one, so the
# pack runs from the warband it meets. Before that every band on the map is an
# even fight and nobody runs from anybody, which is also true to the fights.
#
# The party's wounds are NOT in it. core/world_threat.gd thins a fight for a
# party that is hurt, but that is mercy on the party's side of the budget, not
# the band growing braver; a band does not run from a party because the party
# is limping.
#
# Owns the numbers, the gauge and the comparison. Does NOT own the running
# (core/world_ai.gd's _flee_step steers it, and keeps a band from hunting what
# it would run from), who fights whom (WorldAI.is_hostile), or the fight
# (core/scaler.gd, core/regions.gd).
extends RefCounted

const Regions = preload("res://core/regions.gd")

# ponytail: taste numbers, not a sweep. Nothing here moves a fight's odds, only
# whether a band stands to take one. Re-cut FLEE_BELOW if a playtest finds the
# map emptying of fights too early in the heartland (it bites at party level 5,
# per the table above) or bands standing their ground too long.
const FLEE_BELOW := 0.6       # a band runs from anything it would field under 60% of
const SIGHT := 200.0          # how close a threat has to be before a band notices
const CLEAR := 320.0          # ...and how far it runs before it stops looking back
const STEP := 150.0           # how far ahead each frame's "away" point is set
const GAUGE_MINUTES := 10.0   # world-minutes between the map screen's re-gauges

# The strength of every non-player band on the map against this party, keyed
# by band id. The party is read once (its level and fresh score) and every band
# priced off that, so a gauge costs one Power.estimate per hero, not per band.
static func gauge(world, party) -> Dictionary:
	var out := {}
	if party == null or party.party_characters().is_empty():
		return out
	var have: int = Regions.party_level(party)
	var fresh: float = Regions.fresh_score(party)
	for b in world.parties:
		if not b.is_player:
			out[b.id] = Regions.scale_for(world, b.position, have, fresh)
	return out

# A band's strength from the last gauge; the player is the unit everything is
# measured in. A band the gauge has not seen yet (spawned since) reads as an
# even fight, the safe default: it neither runs nor is run from.
static func strength(world, band) -> float:
	if band.is_player:
		return 1.0
	return float(world.band_strength.get(band.id, 1.0))

# Should `a` run from `b`? Only the strength test: whether `b` would fight `a`
# at all is core/world_ai.gd's to say.
static func outmatched(world, a, b) -> bool:
	return strength(world, a) < strength(world, b) * FLEE_BELOW

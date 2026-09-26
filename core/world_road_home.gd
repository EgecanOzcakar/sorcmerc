# The road home — the clock that says a company has just come up out of a site
# (a lair it cleared, or walked out of part-way) and has not yet slept or seen
# the sun come up. While it runs, core/world_threat.gd reads the company's
# wounds on the gentler walk-home curve instead of the road's own, so the fights
# between a lair and a bed are thinner for the same wounds.
#
#   WorldRoadHome.set_out(world)             # the delve is over: cleared or withdrawn
#   WorldRoadHome.active(world, party)       # -> bool, what WorldThreat.assess asks
#   WorldRoadHome.ends_at(world)             # -> world-minutes the clock lapses at, -1 when none
#   WorldRoadHome.hud_note(world, party)     # -> "" or the short form for the map's bar
#   WorldRoadHome.EXIT_LINE                  # what the lair's exit message adds
#
# WHY IT EXISTS (the owner's call, 2026-09-25, on the measured pass's Still
# open). The flattened wounds curve (world_threat.gd, HURT_AT 0.50 / floor 0.72)
# made pressing on hurt a real risk, which was the point — but it also caught
# the one walk a player cannot choose to skip: out of a site, where the
# adventuring day was spent on ONE set of resources, to the nearest bed. A
# level-8 company at half HP with no slots won 47.5% of those road fights.
# The owner kept the curve and asked for the lever the measured pass named: a
# gentler floor for a company fresh out of a site, until dawn or a long rest,
# whichever comes first. The number and its sweep are world_threat.gd's; this
# file is only the clock.
#
# A CLOCK, NOT A ROLL. It starts when the delve ends and it lapses at the next
# DAWN_HOUR or at the end of the company's next long rest, read off the world
# clock and Party.last_long_rest_at alone. Nothing is seeded and nothing is
# drawn, so a reload cannot move it; the one piece of state is
# World.walk_home_from, which core/world_save.gd round-trips (a save from before
# it existed reads -1: nobody walking home, the road it always was).
#
# The long rest needs no hook: every long rest in the game (an inn, a camp, the
# hermit's hollow, downtime's nights) goes through SettlementVisit.rest(), which
# stamps last_long_rest_at when the night ENDS. A stamp after the walk's
# start means the company has slept since it came out, and the walk is over.
#
# What it does NOT own: how much gentler the road is (world_threat.gd's
# WALK_HOME_HURT_AT / WALK_HOME_FLOOR and the sweep behind them), the site
# itself (core/site.gd — a wipe does not start the walk: core/defeat.gd's
# landing already carries the company to a settlement and costs it the day),
# and healing of any kind — like world_threat.gd, it makes the road kinder and
# never heals anybody.
extends RefCounted

# The hour the walk ends if the company has not slept first. 06:00, the middle
# of core/world.gd's dawn (daylight() climbs from 05:00 to 07:00), which is
# about when is_night() stops being true: the night road is behind them.
const DAWN_HOUR := 6.0
const DAY := 1440.0   # world-minutes

# The lair's exit message adds this (scenes/world/world.gd's _on_site_done).
# A rule said as the road, not as a number: the curve has no one number a line
# could honestly give, and "their wounds" is exactly what it reads.
const EXIT_LINE := "Until dawn or a night's sleep, the road home goes easier on their wounds."
# The map bar's short form, beside the country and the ground (core/world.gd's
# region label). Said only while the clock runs.
const HUD_NOTE := "the road home, until dawn"

# The delve is over and the company is back in the air: start the walk. A
# second site on the same walk restarts it from the second one's door.
static func set_out(world) -> void:
	if world == null:
		return
	world.walk_home_from = world.clock.elapsed

# The world-minute the walk lapses at if nobody sleeps: the first DAWN_HOUR
# strictly after it began. -1 when there is no walk to end.
static func ends_at(world) -> float:
	if world == null or float(world.walk_home_from) < 0.0:
		return -1.0
	var from: float = float(world.walk_home_from)
	var hour: float = fmod(from / 60.0 + world.clock.START_HOUR, 24.0)
	var ahead: float = fmod(DAWN_HOUR - hour + 24.0, 24.0)
	if ahead <= 0.0:
		ahead = 24.0   # came out at dawn exactly: the next one is tomorrow's
	return from + ahead * 60.0

# Is the company walking home right now? No world, or no walk begun, is no.
static func active(world, party) -> bool:
	if world == null or float(world.walk_home_from) < 0.0:
		return false
	if world.clock.elapsed >= ends_at(world):
		return false
	# Slept since it came out: the stamp lands when the night ENDS, so a rest
	# begun on the walk stamps strictly after its start. Strictly, because the
	# clock stands still underground — a company that slept at the lair's door
	# and went straight in comes out on the same minute its last rest ended,
	# and that night was before the delve, not after it.
	if party != null and float(party.last_long_rest_at) > float(world.walk_home_from):
		return false
	return true

# The bar's words, or "" when the walk is not on.
static func hud_note(world, party) -> String:
	return HUD_NOTE if active(world, party) else ""

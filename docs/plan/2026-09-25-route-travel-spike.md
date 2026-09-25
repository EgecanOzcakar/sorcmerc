## Roads instead of a free plane — the #231 spike (2026-09-25)

The owner's call on #231: stop letting the company travel to anywhere on the
map, keep the map, and join its places with distinct, fixed paths — the
towns' roads plain from the start, the rest found while out on the road the
way landmarks and lairs are found today. Enemy bands stop spawning and stop
being drawn; what a company meets is decided by the country, the peoples and
lairs near the road, and what every people thinks of the company.

This entry is the spike, not the feature: **nothing in the shipped game reads
it yet.** The design, the inventory of what leans on the free plane, the phase
order and the eight calls the owner made on the spike's questions are in
`docs/spike-route-travel.md`.

**The network** (`core/world_routes.gd`). Roads between the towns are their
relative neighbourhood graph; lairs hang off the roads on hidden tracks
found by the Survival check at the fork (the owner's call: lairs stay hidden
like today); landmarks on hidden paths revealed when the company walks past
the fork (the hut and the tower still want the search); hidden byways
shortcut the worst detours. Everything is walked over dry ground and nothing crosses without a
node. It is built from the map alone in under 20 ms, deterministic, and round
trips through a plain dictionary for the save. On the shipped maps: small 21
nodes and 22 edges, large 32 and 36, procedural seeds 1–4 22 to 26 and 21 to
27; a trip between two towns on known roads is 1.07× to 1.47× the crow's
distance on average. Pictures: `docs/shots/route-network-*.png`.

**Routes nobody laid.** The owner's follow-up: landmarks and decisions must
be able to create routes that were not on the map, not only reveal ones that
were. A fifth tier, the **trail**, is laid at runtime: `open_route()` between
two places (a crossroads cut wherever it crosses an edge, so nothing crosses
without a node), `lead_target()` picks where a lead should point (a place the
known roads join badly, seeded by the answer), and `scout_spot()` +
`open_place()` put a place no builder placed on the map with a trail to it.
Each carries the `why` that opened it, and the save is what keeps it.

**The odds** (`core/route_encounters.gd`). Per 1000 units walked:
`BASE × cover × lure + hunt + grudge`, one seeded roll per 100 units, keyed on the edge,
the stretch and the world-day so a reload never rerolls a road. Cover is a
civilized town's patrols thinning the road by what that people thinks of the
company; lure is a live lair, an orc hold or a raid pulling its people onto
nearby roads; hunt is a people at `HOSTILE` or worse sending patrols after the
company, heavier the lower their opinion; grudge is a monster people coming
looking for the company that has been killing it (`core/grudges.gd`, the
owner's call: a grudge and nothing else — no truce, trade or parley side,
and never in `FactionOpinion`). A second stream, `meet()`, rolls friendly
meetings near towns not hostile to the company — a patrol, a caravan —
apart from the threat odds, so it never replaces or adds a fight. Who is met comes from the ring's own
factions (weighted by `WorldBands.KINDS`) plus the lairs' and the hunters'
shares; what they field is the `KINDS` troop template at the ring's levels.
`RouteEncounters.band()` hands back an ordinary `RoamingParty`, so the
approach card and the fight need no second path.

**BASE is measured.** `tests/sweep_route_travel.gd` walks today's
free-roaming map (bands seeded, steered, respawned, refilled, raids on the
clock) along random itineraries on six maps and counts the hostile bands that
reach the company: 481 contacts in 720 000 units walked, 0.67 per 1000. Along the same itineraries on the network the
mean cover × lure is 1.12, so `BASE` = 0.60 and the model
delivers 0.67 per 1000 (0.66 in the seeded rolls) — today's total density, redistributed.

**A finding on the way: the far country is quieter than the near one
today** — 0.81, 0.71, 0.25 and 0.43 per 1000 units from the Heartland out, and the Deeps'
contacts mostly bandits, beasts and goblins that followed the company out.
Hunting bands make for the nearest hostile thing on the map and the towns
are in the middle. `BASE` is therefore flat rather than copying that shape;
the ring already sets who is met and how strong the fight is.

Not visible: three models, three tests (`test_world_routes` 1300 checks,
`test_route_encounters` 74, `test_grudges` 10), a sweep, and four diagrams.

### Still open

- Phase 1, the next PR, behind `SORCMERC_ROUTES=1`: `World.routes` and the
  grudges in the save, the known network drawn, click a place to walk
  `path_from()` (open ground does nothing: the company never leaves the
  road), `notice()` and the search at the fork, no band seeding under the
  flag, `roll()` per stretch into the approach card and `meet()` into the
  friendly card, `Grudges.add()` on a won fight and an emptied lair, a camp
  anywhere on a road reading its stretch's rate; the ruins' lead opens a
  trail; a drive robot to sweep the taste numbers (cover, lure, hunt,
  grudge, meetings, lead reach).
- Phase 2, routes by default: authored bands, `spawn_party`, `hunt_party`
  and raids re-homed as pinned encounters and town states; `WorldBands`,
  `WorldAI`'s hunt, `WorldBattle`, `WorldFlee`, `WorldChase` retired; the
  mod API keeps its vocabulary.
- Phase 3, #232 and #234: road meetings and road events that ask, two or three
  choices each, and outcomes that pin follow-ups so events chain or open
  trails and new places (each saying whether its trail shows at once); the
  event table as data packs can extend, and a story effect for the same door.
- Phase 4, #233: the same network inside a settlement.
- Nothing asked is still open (spike doc §7). What a meeting and a road event
  can offer are #232's and #234's own calls.

## Roads on the map — #231 phase 1, behind SORCMERC_ROUTES=1 (2026-09-25)

The spike (`docs/plan/2026-09-25-route-travel-spike.md`) built the road
network, the road's encounter odds and the monster peoples' grudge as models
nothing read. This is the first slice that plays: with `SORCMERC_ROUTES=1`
set, a new map is a **route world** — the company travels only on the roads it
knows, nothing walks the map, and what it meets is what the road sends.
Without the flag nothing changes. `docs/spike-route-travel.md` §6 is the plan
this is phase 1 of.

**A route world is a property of the world, not of the flag.** The flag only
decides how a map is born: one built while it is set is adopted
(`RouteTravel.adopt`: the network, every band the builder put down taken off
again, the company set down on the nearest road). From then on `world.routes`
is what says so, and the save carries it — the network with every trail a
decision opened, the road's odometer, and the grudges beside the opinions. A
route run resumed without the flag is still a route run; a free-roaming save
loaded with it is still free-roaming, because adopting a world mid-run would
strand every band, job and raid it holds. A save without the new keys loads as
it always did.

**What a player sees and does** (`core/route_travel.gd`, wired through
`scenes/world/world.gd`):

- The roads the company knows are drawn on the map, over the fog — a road you
  have been told of is a road you know. Hidden ones are not drawn at all.
- A click on a known place (a town, a found lair or landmark) walks there by
  the known roads, back or on along the one the company stands on. A click on
  open ground gives no order and says "No road you know goes there." The help
  line in the bar says the same.
- A town the march only passes through is passed through; the town at the end
  opens. Roads run town to town, and every trip across the map would otherwise
  stop at every market on the way.
- Walking past a fork shows the path leaving it ("A way leaves the road here —
  to the Nine Sisters"). A lair's track, or a hut's or tower's path, is found
  by the lair button's Survival check made at the fork, one try a day.
- The road rolls once per 100 units walked (`RouteEncounters.STEP`), seeded on
  the stretch and the day. A threat is met the way a band closing in always
  was — the approach card, or the watch's roll in the dark — and a friendly
  meeting gets the friendly card. Win, lose, talk or slip, the band is gone
  when the meeting is; nothing comes back, and no band is seeded or refilled.
- A camp can be made anywhere on a road, and its ambush chance is WorldCamp's
  8% scaled by that stretch's rate against `BASE`, held to 4%–24%
  (`RouteTravel.camp_ambush_pct`): safer under a friendly town's walls,
  riskier at a lair's door.
- The ruins' "read the stones" (and the hermit's lead) lays a **trail** to
  wherever `lead_target()` points — a way that was on no map. A place marked
  found by any other door — a rumour bought at the inn, D3's scout, a story's
  `reveal_lair` — has its hidden way revealed on the next frame, so a place you
  are told about is a place you can walk to.
- Putting down a monster band, or emptying a lair (a delve cleared, or looted
  by sneaking), adds to that people's grudge (`core/grudges.gd`), in every
  world; only the road reads it.

**One fix on the way, in every world.** `World.move_toward_goal` dropped a
party's waypoint list on a map with no water and walked it straight at the
first corner. Nothing gave a route on a dry map before, so it never showed;
a road does, and it cut every road trip short at its first bend. The
procedural maps have a lake, so today only a pack's dry map would have hit it.

Screenshots: `docs/shots/route-travel-map.png` (the small map's roads with the
company on the Greenmarch road) and `docs/shots/route-travel-met.png` (what
the road sent, on the approach card), from `tests/shot_routes_world.gd`.

Tests: `tests/test_route_travel.gd` (50 checks: adopting, the march, the road
over a long walk against its rate and deterministic, met bands, the search,
marks from other doors, a meeting the game was closed on, the lead's trail through Landmarks' own door, the
camp, the save both ways) and the drive robot `tests/drive_routes.gd` (76
checks: the real world screen with the flag — no bands, clicks on ground and
on towns, a trip that passes Riverhold without opening it, sixteen trips'
worth of road with every card the road opened met and its band gone after,
the search at a fork, and a map built without the flag still roaming free).

### Still open

- The taste-number sweep (`COVER`, `LURE`, `HUNT`, `GRUDGE_HUNT`, `MEET`,
  the camp bounds, the lead's reach). It wants a target before it wants a
  robot: what a trip between two neighbouring towns should cost, which is a
  balance call to make with the owner.
- Phase 2 (spike doc §6): raids as a town state (a route world has no raids
  today), `hunt_party` jobs and a pack's authored bands pinned to edges (a
  route world posts no bounty on a band), and routes by default.
- The minimap does not draw the roads; the map draws them as a 2D annotation
  over the 3D view (like the march thread), not as ground decals.
- Co-op: the guest reads the host's save, routes and all, but was not driven
  through a route world.

## Bands on the roads — #231 phase 2, still behind SORCMERC_ROUTES=1 (2026-09-26)

Phase 1 (`2026-09-25-route-travel-phase1.md`) made a route world playable: the
company walks only the roads it knows, nothing walks the map, and the road
decides what it meets. It left out everything that NAMES a band — a route
world had no raids, its boards posted no bounty on a band, and a story's
`spawn_party` or a pack's `parties[]` had nowhere to stand. The owner's call
for phase 2 was to finish route worlds before making them the default, and to
keep free roam as an opt-out; this is that, still behind the flag.

**A pinned band** (`core/route_pins.gd`) stands at one point of one road,
undrawn, and the road meets it when the company walks past — whatever the
dice say, because it is what that stretch fields. It is held in
`world.pinned`, apart from `world.parties`, so nothing that walks the map's
bands (WorldAI's steering and flight, WorldBattle, the fog, the figures) has
to learn to leave it alone; for the length of its meeting it is on the map
like the road's own band, because the approach card and `_launch_combat` take
any band that is. A meeting that does not put it down — a slip, a parley, a
lost fight, a hunt whose chief got away — puts it back on its spot, held until
the company has walked 120 units clear, so the card does not reopen every
frame. The walk is measured against the whole frame's movement, so an 8x
clock cannot step over one; a company standing still next to one does not
meet it. `World.band(id)` and `World.bands()` look in both lists, and the
jobs, callings, raids and stories that name a band by id now use them.

**What is pinned:**

- **A town's bounty.** Every civilized town on settled ground (the heartland
  and the marches — the raids' own country) prices one band at a time on a
  known road 150–500 units out, nearer its own town than any other, first
  inside the first day and then two days after the last one was put down
  (plus under a day of the town's own jitter; the two days are the respawn a
  band got on a free-roaming map). The band is who that stretch would send —
  `RouteEncounters.candidates()`' monster sources there, weighted as the road
  weights them — seeded off the town and the hour. The board's existing
  `hunt_party` pool reads it (reach 700, so the town's own board posts it),
  and the job's map mark points at the road it stands on even under the fog:
  on a map where nothing is drawn, a bounty that did not say where would be a
  name and nothing else.
- **A raid.** `core/raids.gd` runs on a route world now. The clock, the
  target and everything after the landing are unchanged; the band does not
  march. It is pinned the moment it sets out, straight to its siege, 100 units
  out along the town's own road that leaves most nearly toward the lair —
  inside the town's battle radius, so the hold-the-line objective still
  applies when it is fought there. The town's label says "raiders at the
  gate", the HUD says "Raiders from the Tangle are camped outside
  Greenmarch", a company walking out of that gate or up that road meets it,
  and a raid turned there is turned. Left alone it lands, and goes home off
  the map at once. The pull of the raiders' people on the town's roads after
  a landing was already in `RouteEncounters` (it reads `raided_by`).
- **A story's `spawn_party`**, on a route world: pinned on the nearest known
  road to where the story put it. On a free-roaming map it walks as it always
  did.
- **A pack's `world.json` `parties[]`**: a pack's map built while the flag
  is set is now born a route world too (`scenes/game/game.gd`), and its
  authored bands are pinned to the roads instead of dropped
  (`RouteTravel.adopt(world, true)`). A built-in map's bands are the
  builder's filler and still go.

The modding API's vocabulary is unchanged: `spawn_party` and `parties[]` mean
what they said, and `docs/modding.md` says where such a band stands on a
route world. The save carries `pinned` (in the parties' own shape) and
`bounty_due`; a save without them loads with none.

Screenshot: `docs/shots/route-travel-pins.png` (Greenmarch's label with the
raiders at its gate, and Riverhold's bounty job marked on the east road), from
`tests/shot_routes_world.gd`.

Tests: `tests/test_route_pins.gd` (82 checks: pinning, the march meeting a
pinned band, held and let go, met again on the way back, put down; a fast
frame; the bounties posted, seeded, one at a time, the job's pool, mark and
posting position, the next one two days on, none on a free-roaming map; the
raid at the gate, its label, standing not walking, landing, turned; a story's
band pinned and not doubled, walking on a free map; a pack's bands pinned by
id; the save, mid-meeting and old). The drive robot `tests/drive_routes.gd`
now also plays it on the real screen: Riverhold's bounty on its road and not
on the map, the march walking up to it once and the slip leaving it on its
road, the Tangle's raid pinned at Greenmarch's gate and said on the HUD, met
on the way in, and landing when left.

### Still open

- **Routes by default** (spike doc §6, phase 2b) — its own PR, with free roam
  kept as an opt-out; then the free-plane systems retire and a free-roaming
  save adopted into routes pins its named bands.
- **The bounty's numbers are taste** (one per town, 150–500 out, two days
  between), like the rest of `route_encounters.gd`'s constants. They join the
  taste-number sweep phase 1 left open, which still wants the owner's target
  for what a trip between two towns should cost.
- **A job whose band a story or pack named is not re-pinned** if its band is
  gone from a save for some other reason; nothing today removes one except
  putting it down.
- The minimap, the roads as ground decals, and co-op through a route world,
  as phase 1 left them.

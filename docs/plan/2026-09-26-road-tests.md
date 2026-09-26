## The world-screen tests on the roads — #231, the default map under the old tests (2026-09-26)

When routes became the default (`2026-09-26-routes-by-default.md`), thirteen
world-screen tests were pinned to `SORCMERC_ROUTES=0` because they drive the
free plane, and the map a player actually gets lost their coverage. The
completionist got its road tour first (`2026-09-26-completionist-on-the-
roads.md`); this entry gives the rest theirs. **No free-plane check was
removed, skipped or weakened**: every pinned test still runs in full on the
opt-out, which still ships.

**How.** Three shapes, chosen per file:

- **Run twice, one file.** Where the body is shared, `_init` runs it once per
  map (`_run(routes)`), with a fresh screen each time, failures tagged
  `[free plane]` / `[roads]`. The one step that differs is written both ways
  in place — usually "get into a town", which on the roads is a click on the
  town and the march there, since a route world opens a town only at the end
  of a march.
- **A twin that extends.** Where most of the file is shared but a few steps
  are not, the free file names those steps as hooks whose defaults are the
  code they replaced, word for word, and a `_routes` twin overrides only them
  (the pattern `drive_completionist_routes.gd` set).
- **A sibling.** Where the road's version of the behaviour is its own story,
  a new `tests/<name>_routes.gd`.

They share `tests/road_screen.gd` (not a test: the runner globs `test_*` and
`drive_*`): the real click through `_gui_input`, a frame at a fixed delta,
`march`/`go` (click a place, walk until the map raises something; `go` waves
off the road's own traffic with no fight, as `drive_routes.gd` does), and
`pin_ahead`, which stands a band on the road ahead with `RoutePins.place` —
the one arrangement, for the same reason the free tests put a band beside the
company: the road sends its own by its own dice (`test_route_travel.gd`'s
subject, not these).

| test | on the roads |
|---|---|
| `test_world_menu` | run twice; the visit is marched into |
| `test_world_panels` | run twice; the town's pages are marched into, the party screen locked on the road |
| `test_world_camera` | run twice; on a turned map a click on the town under the cursor is where the march ends, and open ground under it is no order |
| `test_world_camp_integration` | run twice; the night's minute is searched at `RouteTravel.camp_ambush_pct`, a minute the flat 8% and the road's odds disagree on goes the road's way, the inn is marched into, and the band in the dark is a pinned band met by the march — `_check_routes` → `_meet` → the night watch, both outcomes seen |
| `test_world_defeat` | run twice; the lost fight is a pinned band met on the road; after the loss the victors are back on their spot on the road, held, and the beaten company is not asked again |
| `test_world_fireside` | run twice; the camp on the road at the road's odds, the inn marched into |
| `test_party3d` | run twice; on the roads nobody is on the map, and a met band wears its figure only for its meeting, gone with it after |
| `test_world_callings` | twin `test_world_callings_routes.gd`: the map's own shrine, found by the telling, its way revealed (`_follow_marks`), marched to; the town marched into; the soldier's band pinned and charged from its card |
| `test_road_trip` | twin `test_road_trip_routes.gd`: the same two legs on the large map, clicked, the road's dice deciding who is met — a different stretch of them per run, the odometer (`step_key`) started `ODOMETER_STRIDE` apart — against the free trip's floors, unchanged |
| `test_world_landmarks` | sibling `test_world_landmarks_routes.gd`: a landmark found by its path noticed from a fork on the way to a town, drawn, clicked, marched to, visited, left, answered, spent; a hidden way is the search at its fork, not the place button's |
| `test_world_meet` | sibling `test_world_meet_routes.gd`: a patrol on the road ahead is met by the march on the friendly card; moving on walks on, the patrol back on its road and not met again; a greeting; a hostile band's card; no figure to click, and open ground is no order |
| `test_world_raids` | sibling `test_world_raids_routes.gd`: the raid pinned at the gate the moment it sets out, said, labelled; met walking out of that gate, hold the line with the lair's kin; landed, on the board; lifted; the cleared lair marched to and settled, and the camp walked back into; the open shelf re-read |
| `drive_world` | sibling `drive_world_routes.gd`: the same robot section for section — the click on a town walked by road, pause, speed, #94, #70 halting at a found landmark, the camera, a road band charged into a real fight, O9's 8x counterpart (the march cannot step over a pinned band), the market, the gate's three opinion bands, a monster's gate and the guards marched into, the panels, and a save that is still a route world |

**Free-plane only, and said so in each file's header:** `test_world_meet`'s
click-to-meet, following, the chase and the clash (#229) — on the roads there
is no figure to click and nobody to follow or run down; `drive_world`'s
off-screen band-on-band battle and the hunting band at 8x; the free
`test_party3d` pass's map bands standing from the start. Those tests stay
pinned and keep running.

**Two bugs the road counterparts found, fixed in `scenes/world/world.gd`:**

- *The settle button went stale at a fork.* On the roads a cleared lair can
  be a fork a hidden way leaves, and `_check_lairs` returned for the fork's
  search before pricing the settle button — greyed at the purse it last saw
  (`test_world_raids_routes`). It is priced first now.
- *A calling's done line named a stranger.* A beaten band's name is found in
  `world.fallen` (`Callings.target_name`), which the roads never write
  (nothing respawns there), so the soldier's done line named a faction-less
  "Sable's lot" instead of the band (`test_world_callings_routes`). On the
  roads the record is kept for the calling check and dropped after it.

**The road trip's books on the roads** (`test_road_trip_routes`, SORCMERC_SEED=5,
12 runs x 2 legs on the large map): 24 legs, 24 arrived, 1.1 bands met and
1.1 fought per leg, 82% HP on arrival, 24/24 legs nobody died, 21/24 arrived
whole — inside the free trip's floors (0.5..3 met a leg, 4 in 5 nobody dies, 3
in 5 whole) with room, so the road model keeps the books the free plane kept.

Proof: each new or changed file green through `tools/run_tests.sh`; every
route test and twice-run test run five times more with `SORCMERC_SEED`
varied, all green; the full suite green (the PR carries the summary line).
Not a visible change — test output instead of a screenshot.

### Still open

- **A settled camp on the roads is a lair node.** The network keeps the node
  as `lair:<id>`; a click reaches the camp and it opens, but
  `RouteTravel.place_name`, finding no lair by that id, falls back to the
  id capitalised on the HUD's "On the road to" line. Worth a settlement node when camps are touched next.
- **The road's own meetings are still arranged here.** Each meeting a test is
  about is a pinned band; the road's dice are `test_route_travel.gd`'s and
  `drive_routes.gd`'s. A test that waits for the friendly stream
  (`RouteEncounters.meet`) to send a patrol would cover that card's text end
  to end.
- **Retiring the free plane** retires the free passes and the pinned-only
  files with it; the road passes are written to stand alone when that day
  comes (the owner's call).

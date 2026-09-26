## Routes by default — #231 phase 2b, and a town click over a band already met (2026-09-26)

**A new map is a route world** unless `SORCMERC_ROUTES=0` is set
(`RouteTravel.flag_on()` now reads the variable as an opt-out). Every piece a
route world needs landed behind the flag first: the roads and what they send
(`2026-09-25-route-travel-phase1.md`), then the bands something names —
bounties, raids at the gate, a story's and a pack's bands
(`2026-09-26-route-travel-phase2.md`). The owner's call keeps the free plane as
an opt-out for now. A save is whatever it was born as: a free-roaming run
resumed stays free-roaming, a route run stays a route run.

**A click on a town wins over a band already met and parted with** (the
owner's call on the trap `2026-09-25-completionist-gate-band.md` found). A
band the company has slipped past, or is under a truce with, standing on a
town, a found lair or a found landmark no longer eats the click: the march
goes to the place (`world.gd`'s `_gui_input`, `_parted_with`, `_place_at`). A
band not yet met on the same spot is still met — the click is the road doing
its job. `tests/drive_town_click.gd` drives it through the real input handler.

**How this landed, honestly.** The flip merged as PR #270 while the full suite
was still running on it, and fourteen world-screen tests went red on master:
`test_party3d`, `test_road_trip`, `test_world_callings`, `test_world_camera`,
`test_world_camp_integration`, `test_world_defeat`, `test_world_fireside`,
`test_world_landmarks`, `test_world_meet`, `test_world_menu`,
`test_world_panels`, `test_world_raids`, `drive_completionist` and
`drive_world`. Every one of them drives the free plane on purpose — bands on
the map and closing on the company, a click on open ground, a landmark found
by walking up to it, a town opening wherever the march stops — none of which
a route world has. They now set `SORCMERC_ROUTES=0` as their first line and
run in full on the mode they were written for, which still ships; all
fourteen are green again. The route world is covered by its own tests
(`test_world_routes`, `test_route_encounters`, `test_route_travel`,
`test_route_pins`, `drive_routes`).

Screenshot: the default map now looks like `docs/shots/route-travel-map.png`
(the roads the company knows, nobody else on the map).

### Still open

- **The world-screen tests on the free plane.** They pin the opt-out, not the
  default. As free-plane systems retire (spike doc §6, phase 2b's list —
  `WorldBands`, `WorldAI`'s hunt, `WorldBattle`, `WorldFlee`, `WorldChase`,
  click-to-meet), each one's route-world counterpart replaces it: the camp's
  ambush on a road, a landmark found by its path, the approach card from a
  road meeting, the completionist tour by road.
- **The completionist tour on the roads.** `drive_completionist` is the robot
  that visits every screen; a route-world version of its tour (clicks on
  places, the search at a fork instead of a lair's own search, the road's
  meetings instead of a band closing) is the first of those.
- **Retiring the free plane**, and adopting a free-roaming save into routes
  (its named bands pinned: `RouteTravel.adopt(world, true)`), are the owner's
  call when they want it gone.

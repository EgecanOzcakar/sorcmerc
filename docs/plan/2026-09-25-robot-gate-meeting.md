## drive_completionist and a band at the gate — the leave check after nights walk the world (2026-09-25)

`tests/drive_completionist.gd` failed its `town:leave` check on a loaded
machine: three runs in four on master (`a2faa01`) with four copies running at
once, and in CI on two round-two PRs whose own changes do not touch it. The
robot drives the map with fixed steps, but the engine also runs the screen's
`_process` on real frame time, so a slow machine moves the world further per
frame. Since the design audit's §1.7 (`core/world_rest.gd`) an inn night
walks the world, and on such a machine a hunter reaches the town's walls by
morning. Leave then opens straight onto "They have seen you", and the check
read that paused clock as Leave having failed.

A band met at the gate is the map working, so the check now allows an
approach card being up; the next walk already answers it (`_walk_into` calls
`_meet_them`). Measured the same way after the change: four in four pass.

### Still open

- The robot's pacing still leans on real frame time through the engine's own
  `_process` calls. A fully fixed-step robot would stop a slow machine from
  changing which moments it meets at all.

## The downtime test after the night learned to pass — raids and drift at the inn (2026-09-24)

`tests/test_world_downtime.gd` went red on master once #240 (a long rest runs
the world clock for its eight hours, `core/world_rest.gd`) and #226 (the
gambling and downtime rewrite) had both landed. Each passed alone; together
the test's inn nights started doing what nights now do:

- **A raid landed during the night.** Riverhold's lair came due while the
  company slept, the raid halved the market, and the alchemist's shelf had no
  potion left for the Brew row the test checks next. The test now keeps every
  lair at home (`raid_at` pushed out) — raiding is `test_raids`' subject, not
  this one's.
- **Opinion drifted overnight.** `FactionOpinion.decay` moves every people
  2 points a day toward 0 while the clock runs, so "the insult took exactly 5"
  and "a brawl left opinion exactly where it was" stopped being exact. Both
  checks now allow the drift the elapsed minutes account for
  (`_drift()`, well under an insult or a service).

Also in `core/world_rest.gd`: the night sets the clock from its start
(`start + minutes elapsed`) instead of adding one minute 480 times. Summing
floats onto a fractional clock could land a hair under +480, and
`drive_completionist`'s inn check (`elapsed >= clock0 + 480`) failed on one
branch for exactly that. No rule changes.

### Still open

- Nothing from this fix. A test that wants a quiet world for its nights has
  to ask for one now; `test_world_downtime` shows how.

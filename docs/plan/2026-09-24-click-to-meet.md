## Meeting a band on purpose — a click, not a collision (2026-09-24)

Any band that came within `ENCOUNTER_RADIUS` of the party opened the approach
card, friendly or not. For a hostile band that is the point: it came for you,
and the card is how you answer. For a faction patrol it was not. T9z gave
friendly bands the greet/move-on card and opened it on contact, so a party
marching past a patrol on the road was stopped to be asked whether it wanted
to stop.

**A band that isn't hostile is now met only by clicking it.**
`_check_encounter()` skips non-hostile bands. A left click on a band's figure
(`_band_at()`, the same model-box pick `_click_target()` uses for towns and
lairs, over the bands the fog is drawing) calls `_seek()`. If the band is in
reach, the card opens at once. If not, the party marches at it, and
`_follow_meet()` re-aims when the band drifts half a radius. The card opens on
contact. The pointer turns to a hand over a band's figure.

- **A click on a hostile band works too.** It walks the party into the band,
  past a slip's `_slipped` mark or a parley's truce. Asking for a meeting by
  name is asking. At night the watch roll still applies (`_meet()`).
- **Any other order cancels the errand:** a ground click, or anything else
  that moves the party's destination off the point it was aimed at, such as a
  gate or a halt. So does losing the band to the fog.
- **Walking up to a band counts as arriving (#70).** The party stops there,
  and a meeting that ends without a fight hands back a halted map, not one
  that runs on with nobody giving orders.

**A band that outruns the party is run down on a roll** (`core/world_chase.gd`,
its own file like forage and camp). Following alone never closes on a band
as fast as the party or faster. That covers a beast pack (1.3x), a dragon
(1.5x), and a band walking off a truce at the party's pace. So while such a
band is still in sight, the party's best Athletics or Survival rolls every
`INTERVAL` (5 world-minutes). The DC is 12, +1 per 10% of speed the band has
over the party. A hit runs it down: the map holds still under the die, then the
card opens where it was caught. `MAX_TRIES` (3) misses and it gets away, and
each roll says so on the HUD line. A band that gets out of sight first is lost
("Lost sight of X"). Pace is the player's lever: a forced march outpaces
everything short of a dragon, and then there is no roll at all. The numbers
are taste, not a sweep, and the file's `ponytail:` says so.

"In sight" for the chase is `band_seen()` *or* inside the party's current
`sight_radius()`. `band_seen()` alone reads the remembered trail, whose last
waypoint can lag `EXPLORE_STEP` (150) behind a moving party. In the first cut,
a beast pack 137 units ahead in open daylight was "lost" before a single roll.

`tests/test_world_meet.gd` covers these cases:

- a patrol in reach opens nothing
- a click meets it at once or across the field, and it is followed when it moves
- another order drops the errand
- the figure is what gets picked
- a hostile band still forces the card
- the chase's DCs and the forced-march exemption
- twelve fleeing beast packs, where both outcomes occur: run down, and got away
- a band lost in the fog

Non-visual apart from the cursor and the chase's die; no save field (the
errand and the chase are transient).

### Still open

- Nothing on the map says a band is friendly before you click it. The cursor
  changes over every band. A hover name plate, tinted by hostility, would say
  what the click will do.
- A patrol has only greet and move on to offer. Now that meeting one is a
  choice, it could carry something worth choosing: news, a rumour, an escort.
- The band being chased doesn't know it. `core/world_ai.gd` walks it wherever
  it was going. A hunted band could flee outright, and a friendly patrol could
  stop and wait for the party that is plainly coming to talk to it.
- The fog quirk the chase works around is real on the map too. Party3D, the
  minimap and quest marks all draw bands off `band_seen()`, so a band a hundred
  units ahead of a moving party can blink out while it stands inside the live
  sight circle. Folding `is_visible_now()` into `band_seen()` is the likely fix.
  It touches every fog-gated draw, so it is its own change.

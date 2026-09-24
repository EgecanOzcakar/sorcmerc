## What the party can see, it sees — bands no longer blink out ahead of a march (2026-09-24)

A follow-up to `2026-09-24-click-to-meet.md`, closing the fog item in its
`### Still open`.

**The glitch.** `World.band_seen()` read only the remembered trail
(`is_explored()`). `reveal()` drops a waypoint every `EXPLORE_STEP` (150), so a
party on the move can have its last waypoint up to 150 units behind it. A band
ahead of the party could be inside the sight circle the ground shader draws,
yet more than `VISION_RADIUS` (260) from every waypoint. That band was hidden,
anywhere from roughly 110 to 260 units out, until the next waypoint landed.
The same was true everywhere the map asks the question:

- the 3D figures (`Party3D`)
- the minimap
- the click pick (`_band_at`)
- quest marks over a hunted band

**The fix.** `band_seen()` is now true for anything inside the party's
`sight_radius()` right now, as well as the trail and the watchtower's watch.
Every caller reads that one function, so all of them are fixed at once.

At night the live term is the night's shrunken sight, the same circle the
ground draws. The remembered trail still shows bands on explored ground beyond
it, which is unchanged. With no player party on the map (a bare `World` in a
test), there is no live sight and only the trail counts, as before.

The chase in `2026-09-24-click-to-meet.md` had worked around this with its
own `_in_view()`. That is gone, and the chase reads `band_seen()` like
everything else.

`tests/test_world_fog.gd` (+6 checks, 34 total) builds a party 149 units into
a march with its only waypoint back at the start. A band 200 units ahead,
off the trail but in sight, is seen. One past the sight circle is not. At
2am, the same band past the night's sight is not. With no party on the map,
only the trail counts. The in-sight check fails on the old `band_seen()` and
passes on the new one.

### Still open

- Settlements, lairs and landmarks fade on `is_visible_now()` and never had
  this gap. Bands were the only thing gated on the trail alone.
- The night still draws bands on explored ground beyond the party's shrunken
  sight: remembered ground shows who is standing on it now. That predates
  this change and is arguably wrong. The fix would be for bands to need live
  sight or a watch, never just memory. It would hide far more of the map at
  night, so it belongs to a pass on how the night should feel, not a bug fix.

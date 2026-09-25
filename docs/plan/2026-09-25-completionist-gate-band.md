## The completionist's two traps — master's last red robot (2026-09-25)

`tests/drive_completionist.gd` went red on master one run in several, the last
failure left after #258: "could not walk into greenmarch in 1200 frames", and
before that "could not walk to clear of ashfell". The same tree passed on the
pull request's own run, and nine runs in ten locally.

**Why it was intermittent.** This robot's fights are not seeded — combat, the
band refills and the searches all fall back to the clock when `SORCMERC_SEED`
is unset — so where the map's hunting bands stand when the tour reaches a town
differs every run.

**Why it failed when it did.** Caught with a state dump on the failing run:
an approach card up, the clock stopped, the company standing at Greenmarch's
gate, and the map's goblins — met earlier, parted with, under a truce —
loitering on the same spot. The robot marches the way a player does, by
clicking the town. But a click on a band's figure is an order to go and meet
that band (`world.gd`'s `_seek`), whatever lies under it, and asking for a
meeting by name overrides a truce on purpose. So:

1. the click on the town met the goblins again;
2. the meeting ended without a fight, which halts the map with the clock
   stopped (`_on_approach_reported`, a band the party walked up to on purpose);
3. a stopped clock keeps the band exactly where it was;
4. the robot re-ordered the march — the same click, on the same band.

Twelve hundred frames of the same card, and the town never reached.

**The fix is the robot's, and it is what a player does.** Nothing in the game
is stuck: the Resume button lets the clock run, the truced band walks off on
its break-off, and the town can be clicked. `_order` now looks before it
clicks: if the band under the spot it is about to click is one the company has
already met and parted with (slipped past, or under a truce), it presses the
HUD's own Pause/Resume to let the world run instead, and clicks the town once
the band has moved. The robot still never writes to the model: every order is
the real click on the real map, and the button is the real button.

**Only a band already met.** The first version of the fix held off the click
for any band on the spot, and went from one red run in nine to eighteen in
twenty: the wolves that hunt the dwarf camp stand on Dun-Arrow's gate, and a
FRESH band there is the road doing its job — the click meets them, the meeting
resolves, the next click is the town. Refusing that click meant never moving
at all. The loop needs a band that a meeting cannot make go away, which is one
the company has already parted with.

**The second trap: the level-up page.** With the first fixed, one run in
twenty still failed — every walk after one fight timed out. The dump: #118's
"somebody can level up" page up, the clock stopped. The robot waved away the
road's cards, the spoils page and the trait moments, but not this one, and it
is an overlay (`world.gd`'s `_overlay_up`): while it is up every march order is
refused and no gate opens. Whether it came up at all hung on whether the
unseeded fights had paid a level yet. The robot now answers it the way a
player putting it off does — "Not now" — since spending a level is the party
screen's subject, not this tour's; the page is announced once per level, so it
does not come back.

Proof: before, 2 red runs in 18; after both fixes, 30 runs of
`tests/drive_completionist.gd`, all green.

### Still open

- The trap is real for a player too, just not a dead end: with a truced band
  standing on a town, a click on the town meets the band, not the town, until
  the clock is let run. A click that lands on a place's diorama and a band
  that has already been met and parted with could prefer the place. That is a
  change to how the map reads a click (world.gd's `_gui_input`), and a design
  call — asking for a meeting by name overriding a truce is deliberate — so it
  is left for the owner.
- The robot's fights are unseeded, so each run plays a different game. That
  is what caught this; pinning it to one seed would have hidden it. Left as it
  is on purpose.

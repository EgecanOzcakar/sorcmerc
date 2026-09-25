## Downtime nights — a pinned inn, a night out that answers, a pit fought one on one (2026-09-25)

Four playtest issues from the evening the hiring pool and the downtime rows
first met, all on the inn page or the page a hire is settled in on.

**#228, the inn scrolled as a whole.** Since #201 every town page's body
scrolls as one, fitted to the window. The inn already had a list of its own
under the bed ("Looking for work", the downtime rows, the common room's
rumours), so at the game's 1280×800 the inn was two scrollbars, one inside
the other, and scrolling the page took the table and the bed up and out of
sight with it. The inn and the lodge are now *pinned* pages
(`PINNED_PAGES` in `scenes/world/world.gd`): the head — the room, around the
table, the party button, the bed — is not in any scroll, and the one list
under it takes whatever height the window leaves (`_fit_visit_list`, fitted
the frame after the page is built, never under `VISIT_LIST_MIN_H`). Every
other page scrolls as #201 made it. A page is rebuilt on every click, and a
rebuild used to throw the list back to its top; the list now keeps where it
was scrolled across rebuilds (`_visit_list_v`, cleared on walking into a
page or opening a visit).

**#237, "Go out" did nothing.** It did something — but not where anyone was
looking. The row said *A night on the town (30 ◉)*; the night also takes a
bed, 40 ◉ at a city, and a purse between the two got the refusal on the log
line at the foot of the panel, under a list that had just jumped back to its
top. Reproduced headless with 60 ◉ in the purse at Riverhold: the press
moved nothing and changed nothing on the row. Now `Downtime.carouse_cost`
is the whole night and the row names it (*A night on the town (30 ◉, and 40 ◉
for the bed)*); `Downtime.carouse_refusal` greys Go out and says why under
the row, the way the game's once-a-day line does; and a night that happened
leaves its line under the row (*Last night: …*), put there once the die has
landed so the row never tells the roll first. With the list keeping its
place (#228), the answer is where the press was.

**#236, the pit was the whole company against one.** A bout was the marching
four against the city roster's strongest humanoid pumped to `PIT_MULT`
1.3/1.7/2.2, a number the design audit listed as unmeasured. Now the pit
row asks *who goes in* (a picker of the marching company on their feet,
`Downtime.pit_fighters`, between the bracket and Fight) and the bout is that
hero against one champion:

- `Scaler.duel_for(target, pool)` finds the one foe of a pool nearest a
  score on core/rules/power.gd's ruler and pumps or eases it with the boss
  MULT knob to the target — the nearest, so the knob stays near 1.
- `Downtime.pit_champion(level, ratio)` sets the target: `PIT_RATIO` of the
  ruler's average hero at the hero's *level* (`Regions.ref_score / 3`), from
  `PIT_POOL`, the people who fight in a square for money (no archers). By
  level and not by the hero: priced off the hero's own power reading, a
  cleric met a champion sized to every spell on their sheet.
- For the bout the hero is the whole marching order
  (`Downtime.pit_line_up` / `pit_stand_down`), so the board, the XP, a trait
  earned and the write-back are theirs alone; the order is put back as soon
  as the bout is banked (or torn down), less anyone the bout killed. Nothing
  saves mid-fight, so the one-hero order never reaches a save file.
- The card names who won or was carried out.

`PIT_RATIO` 0.6 / 0.9 / 1.2, MEASURED with the new `tests/sweep_pit.gd`
(each preset alone, levels 1, 3, 5, 8, 12, 16, 40 pinned seeds a cell, both
sides on the autopilot), mean win % across the levels:

    ratio   fighter   rogue   cleric
    0.6      98.3     28.8     16.3
    0.9      91.7     12.1      7.5
    1.2      60.4      2.9      1.7

Set on the fighter's column: the first bout a near-certainty for the
company's sword-arm, the second about a road fight, the third lost four
times in ten. The rogue and cleric columns are the autopilot's: alone, it
never casts (a level-8 cleric against a bandit captain, replayed: nine
rounds of mace swings). They are not a target; they say "put in your
fighter", which is the choice the row now asks for.

**#235, "wht choice is left".** The issue was a screenshot we could not open,
filed six minutes after the hiring pool landed. The likeliest page is the
settle-in page or a level-up: Confirm with a choice open answered
*"2 choice(s) still unmade."* — a count, on a page where the open rows sat
under the gains card *and* the 430-pixel climb. `Leveling.left_to_choose`
names each open choice (*Fighter ability score increase*, *Cleric cantrips
(pick 3)*); the page lists them under a *Left to choose* heading over the
rows, the refusal reads *Still to choose: …* and scrolls to the first, and a
level-up now draws its choices before the climb, as settling in already did.
The inn's trainer row no longer offers a hero with no feat left to finish
(an empty picker beside a Go that said "will not take them"). If the
screenshot showed something else, this is still a real fix, and the issue
wants a look at the picture.

Tests: `tests/test_world_downtime.gd` (the pinned head, the list's scroll
kept and reset, a grey Go out and its reason, the last night's line, the
pit's picker, one hero on the board, the order put back, the XP all the
fighter's), `tests/test_downtime.gd` (the night's price and refusal, the
duel spec, the climb of the three bouts, line-up and stand-down, the named
card line), `tests/test_leveling.gd` (the named refusal, the list, the rows
before the climb).

Screenshots (`tests/shot_downtime_nights.gd`, under xvfb):
`docs/shots/issue-228-inn-scroll.png` (the head pinned, the list scrolled to
the downtime rows, Go out grey with the purse short),
`docs/shots/issue-237-night-out.png` (the last night's line under the row,
the pit's picker beside Fight), `docs/shots/issue-236-pit-bout.png` (one
hero, one champion), `docs/shots/issue-235-left-to-choose.png` (a level-4
fighter's page after Done).

### Still open

- The pit's rogue and cleric columns wait on an autopilot that duels: a lone
  caster that casts. Re-run `tests/sweep_pit.gd` when it does; `PIT_RATIO`
  may then be set on all three.
- At the game's 800 logical pixels (the canvas stretches to "expand" from
  1280×800, so it is never shorter) the inn's head is about 430 and the list
  gets about 200: three or four rows. A taller list would mean folding the
  room's picture away once the list is scrolled; not done.
- The market's shelf and the board still scroll with their page (#201) and
  still jump to the top on every buy; only the pinned pages keep their place.
- No wagers on another's bout, and the bench cannot be put in the pit: the
  picker is the marching company, as the trainer's is.
- #235 was matched to its most likely page, not to its picture.

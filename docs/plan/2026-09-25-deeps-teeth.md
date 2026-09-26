## The Deeps' teeth — a wall at the Unmapped, big creatures on its roads, a raid cap and real names on the bar (2026-09-25)

Four of the owner's calls on the Still open of the Far Deeps entry
(docs/plan/2026-09-25-far-deeps.md), which followed the design audit's §5.4 and
§8.3-8.4 (docs/audit-game-design.md, "The owner's calls"). The owner said "do
all"; the resolutions below are the ones chosen.

**The Unmapped is a wall, not a step.** A level 10 party one band out in the
Unmapped won 71.5% at easy, where a level 3 party one band out in the Marches
won 28.0%: the plain pin put a level 10 company against level 15 content, which
is x1.47 of it (level 6 content is x2.26 of a level 3 one). A band may now name
an `under` level in `core/regions.gd`'s BANDS — what a party below its floor
meets — and the Unmapped's is 17. Every other band pins to its floor as before
(`Regions.under_level`), and the floor itself stays 15: a higher floor would have
left 15 and 16 nobody's levels, and a party that has reached the Unmapped still
fights its own level there. `Regions.scale_in` is the one place the pin is
worked out now, `scale_for` and `power_scale` go through it, and
`level_here` says 17 for a party under the Unmapped, so a posting's XP and a
recruit's level read the fight that is actually built. Picked off
tests/sweep_regions.gd (200 seeds, easy, pinned, big one off), a level 10 party
against a plain pin at 15 / 17 / 18 / 19: 71.0 / 48.5 / 29.5 / 27.5%. The
sweep gained band cells (`CELLS=10:unmapped`) that price a band the way the map
does, and three rows: level 10, 12 and 14 in the Unmapped.

With the wall in place and the big one rolling, 200 seeds a cell, easy, back
to back on master (9dcc57e) and the branch (the band rows are new cells master's
sweep cannot express; 10/15 is what a level 10 party at the Unmapped met on
master):

    party  content    scale   master   branch
    lvl 3   lvl 3     x1.00    96.5%    96.5%
    lvl 5   lvl 5     x1.00    97.5%    97.5%
    lvl 6   lvl 6     x1.00    99.0%    99.0%
    lvl 8   lvl 8     x1.00    97.0%    97.0%
    lvl 10  lvl 10    x1.00    96.5%    96.5%
    lvl 12  lvl 12    x1.00    99.0%    99.0%
    lvl 15  lvl 15    x1.00    94.0%    94.5%
    lvl 6   lvl 3     x0.44     100%     100%
    lvl 10  lvl 3     x0.30     100%     100%
    lvl 3   lvl 6     x2.26    29.0%    29.0%
    lvl 3   lvl 10    x3.38     2.0%     2.0%
    lvl 10  lvl 15    x1.47    71.0%    70.5%
    lvl 12  lvl 15    x1.22    86.0%    86.0%
    lvl 15  lvl 14    x0.95    97.5%    97.5%
    lvl 20  lvl 14    x0.67     100%     100%
    lvl 3   lvl 15    x4.97     0.0%     0.0%
    lvl 10  unmapped  x1.68      -      48.0%
    lvl 12  unmapped  x1.40      -      77.5%
    lvl 14  unmapped  x1.21      -      88.0%

No inner row moved more than half a point; one band out into the Unmapped at
level 10 is 48.0%, the owner's 40-50%.

**Big creatures on the Deeps' roads.** The 26 CR 11-20 statblocks the Far Deeps
entry added reached 3-10% of Deeps fights, because `core/scaler.gd` buys bodies
first and BIGGEST_SHARE keeps any one foe under 0.6 of the budget: an adult
dragon (priced 159-197) never fit a Deeps road budget (easy: 103 at level 10,
151 at 15, 213 at 20). Now a road fight in the inner Deeps or the Unmapped
sometimes IS one creature (`Scaler.BIG_CHANCE`, per band, seeded off the fight):
one of the warband's own people at CR 11+, picked by seed among those the MULT
knob can bring to BIG_SHARE of the budget, standing alone. The scene passes the
band's id to `Scaler.roster_for` (`scenes/world/world.gd` encounter_spec); no
band, or any band outside the Far Deeps, builds exactly the roster it always did
(test_deeps_big pins it byte for byte, forced on). Lair rooms pass no band.

BIG_SHARE is 0.8, not 1.0, and that is a measurement: the ruler does not price a
lone creature against three heroes' action economy the way it plays. Forced on
every fight that can field one, tier hard, the Deeps' roaming mix, against the
same seeds' warbands (level 12 in the Deeps 73.5%, level 17 in the Unmapped
63.5%): share 0.60 -> 89.0 / 91.5%, 0.75 -> 79.0 / 79.5%, 0.80 -> 70.0 / 71.5%,
0.85 -> 62.5 / 57.5%, 1.00 -> 42.5% (tests/sweep_deeps_big.gd). With the chances
shipped (deeps 0.6, unmapped 0.37), 200 seeds a point at easy, the owner's
25-35% and the win rates beside master's rosters:

    band      lvl    master rosters     shipped
    deeps      10     0.0%  94.0%     29.5%  94.0%
    deeps      12     0.0%  98.5%     34.0%  98.0%
    deeps      14     1.0%  97.5%     35.0%  96.0%
    unmapped   15     8.5%  98.5%     26.5%  97.5%
    unmapped   17    11.0%  95.0%     33.5%  93.5%
    unmapped   20    11.0%  94.0%     32.5%  92.5%

Every move is under two standard errors. test_scaler never passes a band, so its
lines are the same rosters as master's.

**Raid pressure scales with the map.** The small map has seven settled lairs
running raid clocks against three raidable towns (the fourth, Ashfell, is
orcish), and could have every one of them under a raid at once. `Raids.raid_cap`
is half the map's civilized towns, rounded up; a lair counts as raiding while its
band is out or its landed raid still stands on a town, and a lair already
raiding may ride again. A lair due past the cap restarts its clock (it waits for
its next one, not the next frame), and when several are due together the one
whose seeded `due_at` ran out first goes. Over eight days of the real small map
it now holds two raids at most where it held three (test_raids).

**Real names on the turn bar.** A combatant known only by its kind read its
kind's first word: an adult red dragon was "Adult", a giant rat "Giant", a
wererat "Wererat,". `Combatant.species_short` drops the copy number, anything
after a comma or in brackets, and leading age and size words (Young, Adult,
Ancient, Elder, Greater, Lesser, Giant, Dire) while another word follows; a name
over 13 letters falls back to its last two words, then its last. "Red Dragon",
"Rat", "Giant Archer", "Wasps", "Hill Giant". Heroes and foes with a name of
their own ("Grix the Goblin") keep their first word, and an explicit short (a
summon's) still wins. Screenshot: docs/shots/deeps-teeth-turn-bar.png
(`tests/shot_deeps_teeth.gd`).

Tests: tests/test_deeps_big.gd and tests/test_short_names.gd are new;
test_raids gains the cap on a crowded unit map and on the small map;
test_regions pins the wall (a level 10 or 14 party under the Unmapped builds for
17, a level 15 party for 15, every other band for its floor).

### Still open

- **No dragon roams the Deeps.** `core/world_bands.gd` has no dragon kind, so
  the road's big creatures are vampires, mummy lords, djinn and efreet, storm
  giants, the sphinxes, behir, roc, remorhaz, purple worm and iron golem; the
  adult dragons are met only in a dragon's lair. A dragon band is a population
  change (every seed's draw reshuffles, test_road_trip moved the last time), so
  it wants its own entry.
- **Lair rooms pass no band.** A Far Deeps lair's rooms are built as before; the
  big one is the road's. Sweep a Deeps lair per band before giving it one.
- **The big one's price is a ratio, not a ruler fix.** BIG_SHARE 0.8 corrects
  core/rules/power.gd's view of a lone creature at two measured points. A solo
  pumped to the whole budget is a wall (42.5%), and a pumped CR 11 (a vampire
  at level 20) is not the same fight as an eased CR 17; if the ruler learns to
  price action economy, BIG_SHARE should go back toward 1.0 and be re-swept.
- **A quarter of the Far Deeps' bands are fey**, who have nothing at CR 11+ (the
  SRD has none); they cap how far BIG_CHANCE can lift the share.
- **The raid cap counts standing raids.** Two lairs that have landed hold the
  small map's two places until one is cleared, and every other settled lair
  waits. If that reads as a map gone quiet in play, count bands out only.
- **The turn bar's width.** Tiles grow with their names; SHORT_MAX 13 was sized
  to the dragons' colours, not measured against an eight-foe strip at the
  smallest chrome scale.

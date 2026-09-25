## The measured pass — a hurt company's risk, the stale sweeps re-run, and what the ruler could not see (2026-09-25)

The owner's calls on the design audit (docs/audit-game-design.md) §3.2
("flatten the wounds curve"), §7.2 (re-run the stale measurements), §7.3
(sweeps for the knobs that had none), §7.4 (the autopilot arms Metamagic;
price weapon mastery, road potions and bonds if a sweep sees them) and §4.4
(sweep the two estimates). One number moved on purpose (the wounds curve), two
things were priced, one constant was re-derived by its own rule, and the rest
is measurement written into the header of the file that owns the number.

Every sweep below: fight seed pinned, 200 seeds a point unless it says
otherwise (a standard error of about 3 points; a move inside 1.5 SE is
noise), run back to back on master (1d46a44) and the branch, or in copies of
master with one constant edited where the sweep is of a constant. Seven new
harnesses, none in `run_tests.sh`: `tests/sweep_wounds.gd`,
`sweep_metamagic.gd`, `sweep_unpriced.gd`, `sweep_mult.gd`,
`sweep_site_knobs.gd`, `sweep_xp.gd`, `sweep_road_day.gd`.

### The wounds curve, flattened (§3.2, §7.2)

`core/world_threat.gd`'s curve rested on a 2026-09-13 grid from a harness that
was never committed, taken under TIER 0.96 / CURVE 0.90 before the swing fix,
RAW cover and death saves and the autopilot that spends its whole turn.
`tests/sweep_wounds.gd` is that harness, and today's grid (level-3 presets,
easy, every slot back):

| hp | x1.00 | x0.90 | x0.75 | x0.60 | x0.50 | x0.40 |
|---|---|---|---|---|---|---|
| 100% | 96.5 | 99.0 | 99.0 | 100 | 100 | 100 |
| 70% | 89.5 | 93.0 | 96.5 | 99.5 | 100 | 100 |
| 50% | 76.0 | 86.5 | 94.0 | 99.5 | 99.0 | 99.5 |
| 30% | 60.0 | 69.5 | 81.0 | 92.5 | 96.5 | 98.0 |

The old curve (HURT_AT 0.90, floor 0.35) put a company at 70/50/30% HP on
x0.79/0.67/0.53: 98/98/96% wins, as good as fresh. **The target chosen:** a
company at half its HP meets what a fresh one meets at `normal` (85%), and
at 30% what a fresh one meets at `hard` (75%) — test_scaler's own targets,
so being hurt is a tier up rather than a new number, and the full-HP 99.0%
does not move. **HURT_AT 0.90 → 0.50, CONDITION_FLOOR 0.39 → 0.80** (floor
x0.35 → x0.72): above half HP the road does not thin a fight for wounds at all.

| | every slot back | | every slot spent | |
|---|---|---|---|---|
| hp | master | branch | master | branch |
| **level 3** 100% | 99.0 | 99.0 | 95.0 | 95.0 |
| 70% | 98.0 | 93.0 | 91.5 | 85.5 |
| 50% | 97.5 | **86.5** | 94.0 | 73.5 |
| 30% | 96.0 | **74.5** | 91.0 | 63.0 |
| **level 8** 100% | 97.5 | 97.5 | 80.0 | 80.0 |
| 70% | 99.0 | 92.5 | 82.5 | 59.0 |
| 50% | 99.0 | 86.5 | 85.5 | 47.5 |
| 30% | 98.0 | 72.5 | 87.5 | 38.5 |

On master the wounds discount more than repaid the spent slots: a drained
level-8 company won MORE often the more hurt it was. The right-hand column
is the walk home from a cleared lair and is the number to watch (see Still
open). Played rather than set up — `sweep_road_day`, the trio carried
through ten days of road on one set of resources, ten runs a level — the
road's win rate goes 98.0 → 94.7% at level 3, 94.1 → 88.4% at 6 and 97.2 →
92.5% at 10: pressing on now costs something you can see.

### The stale measurements (§7.2)

Re-run under today's rules, written into their headers, nothing retuned:

- **Traits** (`core/traits.gd`). `sweep_traits` (300 seeds, normal):
  baseline 89.7%, the largest moves Craven and Wrathful +2.0 — every row
  inside noise, as before. `sweep_traits_earn`: triumphs outnumber scars 3:1
  on easy fights and 11-19:1 where "flawless" fires; hardship saves asked 246
  times (was 355); the 30-day run ends with 5.6 earned traits a hero (was 6.1).
- **`BOARD_SHELVES`** (`core/encounter.gd`), `sweep_tier` in copies of master:
  no shelf 96.0/92.5/81.5, one 96.5/93.0/81.5, two 95.5/93.5/79.0. The
  shelf no longer moves the win rate; it is a taste number now.
- **`SPAWN_GAP`**: gap 3 97.0/95.0/81.5, gap 6 96.5/93.0/81.5, gap 9
  93.5/91.5/81.0. T37's +6.6 over gap 3 is gone on the grown boards; all
  inside noise.
- **`BOSS_REF_WIN_RATE`** (`core/campaign.gd`) said "re-derive on every TIER
  retune", and TIER was retuned after it was set: `sweep_tier` on master
  reads easy 96.5 / hard 81.5, so **0.86 → 0.89**. Every linear-campaign boss
  rated under it earns about 3.5% more bonus XP.

### What the ruler could not see (§7.4)

**The autopilot arms Metamagic** (`core/ai.gd`, `_quicken` and `_twin`;
`tests/test_autopilot.gd`). Quickened: a leveled damage spell it can aim goes
out on the Bonus Action from wherever the turn's move put the caster, and the
action then does what it would have done anyway — so a sweep sees the option
and nothing else. Twinned: armed just before a spell that twins; every such
spell today is a control spell, which the autopilot never throws, so it is
inert under autoplay (said so in the code). Co-op lockstep holds
(`test_coop_kits` 234/234).

`sweep_metamagic`: the preset fighter beside two built sorcerers, Quickened
and Twinned against Careful and Subtle (never armed, never priced). "Unpriced"
fights both columns on the rosters bought for the Careful party; "priced"
buys each its own.

| easy | off | on, unpriced | on, priced |
|---|---|---|---|
| level 3 | 85.0 | 85.5 | 83.5 |
| level 5 | 93.0 | 98.0 | 95.0 |
| level 10 | 79.5 | 88.0 | 83.0 |
| normal, level 3 | 64.5 | 69.0 | 69.5 |
| normal, level 5 | 88.0 | 91.0 | 88.5 |

Above noise at 5 and 10, so **`core/rules/power.gd` prices Quickened**: each
turn the points (2 a turn) and the leveled slots can pay for, up to ROUNDS,
is a second action's worth (`quickened_turns`). It comes back inside noise.

`sweep_unpriced`: the preset trio at hard, each thing on everyone who can
carry it, against the same rosters (unpriced) and against rosters bought for
the company carrying it (priced):

| | L3 unpriced | L3 priced | L8 unpriced | L8 priced |
|---|---|---|---|---|
| baseline | 81.5 | 81.5 | 78.0 | 78.0 |
| no weapon mastery | −2.5 | — | −4.3 | — |
| Heroism on all three | +8.0 | +3.5 | +4.0 | +3.3 |
| Giant Strength on the fighter | +8.0 | +0.0 | +4.0 | +0.7 |
| every pair bonded | +8.0 | +5.5 | +4.3 | +1.0 |

**Road potions are priced in power.gd** (`road_buffs`: a still-running
potion's to-hit, damage and AC read as the sheet's). **Bonds are priced where
the company is read** — a bond is a pair's, and power.gd reads one hero — in
`Regions.fresh_score`, which both the road's `slot_hold` and a lair's entry
score hold a budget at. Priced as the +1 AC held all fight it over-shot at
level 8 (−6.0 at 150 seeds: one AC point is a sixth of power.gd's ehp at a
level-8 AC), so it is priced for the share of blows it is there for,
`SHOULDER_SHARE` 0.45 (measured: 43% of the blows at a bonded hero at level
3, 50% at 8, land with the partner beside them); the level-3 residual (+5.5,
about 1.8 SE) is the rally, which is not priced. The level-8 mastery and
bond rows are 300 seeds (their baseline 75.7%); the rest are 200 at level 3
and 150 at level 8 (baseline 78.0%). **Weapon mastery is
not priced**, judged at the noise line: taking every mastery off the trio is
−2.5 at level 3 (0.8 SE) and −4.3 at level 8 (300 seeds, 1.7 SE; −5.3 on
the first 150) — a third to a half of what the three priced things measured,
and each of the eight masteries would need its own model (Vex and Sap are a
roll's odds, Graze a miss's damage, Topple a condition) that no sweep has yet
isolated. `tests/test_power_pricing.gd` holds it unpriced, so pricing it is
a deliberate change with its own sweep.

### The knobs that had no sweep (§7.3)

**The site's three** (`core/site.gd`, `sweep_site_knobs`): whole delves, the
preset trio at level 3 in its own country, 210 delves a row, one knob moved
at a time. As shipped a company that takes every rest offered clears 18.1%
and wipes 81.9% (never resting: 5.7%); by depth 30 / 14 / 16 / 10% for 3 to
6 rooms; a level-5 company clears 58.1%.

| | cleared | rests a delve | reached the boss | boss won |
|---|---|---|---|---|
| as shipped | 18.1% | 0.59 | 42.9% | 42.2% |
| SUPPORT_CHANCE 0.30 / 0.60 | 12.9 / 25.7% | 0.36 / 0.89 | 36.7 / 55.7% | 35.1 / 46.2% |
| REST_SHARE 0.20 / 0.70 | 9.5 / 31.0% | 0.30 / 1.09 | 33.3 / 61.4% | 28.6 / 50.4% |
| MAX_DEPTH 5 | 17.6% | 0.58 | 46.2% | 38.1% |

A rest taken is worth about 25 points of clear rate whichever knob offers it;
MAX_DEPTH does nothing (the boss, not the sixth floor, is where a delve is
lost).

**The per-mult bumps** (`core/encounter.gd`, `sweep_mult`): the boss pool's
leads, in copies of master with AC/ATK/DMG_PER_MULT edited. The pool reads the
same at 3/4/4 and 2/2/2 (level 3: 75.2 / 75.8%; level 8: 82.4 / 84.4%); on one
high-mult lead the bumps are worth more than the ruler credits (the level-3
captain at x2.05 plays 55.0% against 70.0% at 2/2/2's x2.45), still inside the
boss band. HP-only (0/0/0) is 67.9% at level 3. Nothing moved.

**XP pacing** (`core/leveling.gd`, `sweep_xp`; the `_tmp_xp` sweep its header
cited was never committed): a played road fight pays 5-10% under the
estimate; road fights to cross each country are 24 / 23 / 23 / 33 / 24
(Heartland to Unmapped), ~126 from level 1 to 20, ~70 with a three-fight job
turned in every four fights.

### The two estimates (§4.4)

`sweep_road_day`: the trio carried through ten days of road, ten runs a
level, a hostile contact every 37 walked minutes (the measured free-roam
rate), every one fought, an hour a round on the clock, a short rest under half
HP, a long rest the moment the gate opens.

| | level 3 | level 6 | level 10 |
|---|---|---|---|
| fights a day / a long rest | 2.84 / 4.1 | 2.49 / 3.7 | 2.28 / 3.3 |
| HP, slots at the long rest | 45%, 21% | 34%, 17% | 44%, 35% |
| income a long rest | 82 ◉ | 162 ◉ | 262 ◉ |
| town inn (20 ◉) / city inn (40 ◉) | 24% / 49% | 12% / 25% | 8% / 15% |
| camp kit (150 ◉) | 183% | 92% | 57% |

**The gate binds** (the audit estimated it barely does): a rest comes 24
hours after the last one ended, and a company that sleeps the moment it may is
down to a third to a half of its HP and a fifth to a third of its slots. **The
rest's price does shrink** — a town inn is a quarter of the takings at level 3
and 8% at level 10 — but a night away from town still costs half a day's
takings in the Deeps.

**Bench rotation** (a second preset trio on the bench): swapped only when the
marching trio is spent it is noise (94.7 → 94.8% at level 3, 88.4 → 88.8% at
6); swapped before nearly every fight it is real — 94.7 → 96.3% and 88.4 →
97.0%, the marching trio walking in at ~90% HP and slots instead of ~75% —
but it buys fresher fights, not more of them (4.2 and 4.0 a rest), and every
hero levels at half the pace. The bench already sleeps only when the company
does, the audit's own remedy, so nothing moved.

### What did not move

`tests/test_scaler.gd` and the region rows are byte-for-byte master: the
preset trio carries no Quickened, no potion and no bond, and neither sweep
reads the wounds curve (`sweep_regions` CELLS 3:3, 3:6, 8:8 at 200 seeds:
96.5 / 28.0 / 96.5% on both). test_scaler, 200 seeds a tier, prints the same
numbers on both, line for line: 96.5 / 93.0 / 81.5% at level 3, 96.0 / 84.0 /
78.0% at level 8, boss pool 72.0%. The full suite (`tools/run_tests.sh`,
after merging master at 03ca4ba) is 186 passed, 0 failed.

Not visible: no screen changed, so no screenshot. Tests:
`tests/test_world_threat.gd` (the flattened curve: a half-HP company meets the
fresh company's roster, body for body; the floor stays above 0.7),
`tests/test_autopilot.gd` (Quickened on a Fireball, nothing armed without a
slot, Twinned only for a spell that twins), `tests/test_power_pricing.gd`
(new: Quickened, road potions and bonds priced; mastery and rivals left
unpriced).

### Still open

- **The walk home from a lair.** A level-8 company at half HP with no slots
  wins a road fight 47.5% of the time now (85.5% on master). That is the
  gamble the owner asked for, and the approach card's other answers are how a
  hurt company avoids it; if it reads too harsh in play, the lever is a
  gentler floor for a company fresh out of a cleared site, not the curve.
- **Lairs at level 3 are very hard.** A company in its own country clears one
  lair in five taking every rest (the autopilot never withdraws, which a
  player does). Whether the Heartland's lairs should be this hard, and the
  support knobs that are the lever, are the owner's call.
- **Bench rotation's price is XP only.** Real when worked (+8.6 at level 6);
  if the XP halving is not enough of a price, a benched hero could come in
  tired, or swapping could cost time.
- **Quickened is priced; the other four options are not** — the autopilot
  does not arm them. Careful, Subtle and Seeking are small by construction;
  price them if a sweep that arms them sees them.
- **Rivals are unpriced** (a harder fight than its price, the safe side), and
  a potion's saves and one-element resistance, as the sheet's saves are.
- **A per-mult bump on one lead is under-priced** at level 3 (the captain);
  it stays in the boss band. Revisit if a FACTION_BOSS is found pinned at the
  ceiling and out of band.
- **Casters walk into melee.** The autopilot closes on anything that is not a
  shooter, so a sorcerer with no bow ends its spell turns punching; every
  caster sweep reads a caster weaker than a player plays it. A behaviour fix
  would move every caster sweep and is its own balance pass.

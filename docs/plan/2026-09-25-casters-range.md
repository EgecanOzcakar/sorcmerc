## Casters keep their distance — the autopilot stops walking a sorcerer into melee (2026-09-25)

The owner's call on the measured pass's Still open ("Casters walk into
melee", docs/plan/2026-09-25-measured-pass.md; the design audit,
docs/audit-game-design.md §7.4, on what the ruler could not see): fix the
autopilot. Until now `core/ai.gd` closed on anything that was not a shooter,
so a sorcerer with no bow walked up to the nearest foe and punched it, and
threw its cantrip only on the turn the walk fell short. Every caster sweep
read a caster weaker than a player plays one.

### What changed (`core/ai.gd`)

- **Who is a caster.** A hero whose best option is a spell with range:
  its hardest-hitting ranged cantrip (or, with none, the first leveled bolt on
  its bar) out-deals, on average, its whole Attack action — every swing Extra
  Attack buys plus the once-a-turn riders a hit carries (Sneak Attack,
  Dreadful Strike). A tie goes to the swing. Read off every verb it could
  pay for, not the bar, which hides a spell with no foe in reach (`_caster_bolt`,
  `_payable`). So the preset Light cleric (mace 4.5, Sacred Flame 4.5) fights
  as before at level 3 and stands back from level 5, when the cantrip doubles.
- **Where it stands** (`_keep_range`). Where the spell reaches a foe it can
  see, as far from the nearest foe as that allows, never paying an opportunity
  attack to get there: it steps back out of reach when the step is free (the
  foe's reaction spent, or nobody's reach to leave), and a Bonus Action
  Disengage buys the step when it is pinned. Otherwise it holds its ground and
  casts — in this engine a spell attack carries no penalty for a foe beside
  you, so a step would buy the foe a free swing and nothing else. Out of range
  of everything, it walks the nearest foe's way and stops at the first hex the
  spell reaches from.
- **The cone step** (`_cone_step`). The first version stood back and threw
  away the one thing the walk into melee did well: a built sorcerer whose only
  leveled damage is Burning Hands threw it 48 times in 40 easy fights from
  arm's length and 5 times from cantrip range, and its seat fell 93.0 → 82.5%
  (`sweep_sorcerer`, 200 seeds). A caster with a damaging cone now first looks
  for a hex its walk reaches, without provoking, from which the cone nets two
  foes. The seat is back to 95.0%.
- **What it throws.** The bolt at the weakest foe it reaches (the quarry on a
  hunt), in place of a swing at whatever stands beside it.
- **Enemy casters** (`_caster_turn`, core/enemy_casters.gd's slot casters)
  walk the same way when nothing they know reaches: to the first hex a spell
  does, no longer to arm's length. Their step clear when a hero is in their
  face (eating the opportunity attack, measured 2026-09-24) is unchanged.

Deterministic and co-op safe: no roll is added; ties break on the hex it
stands on, then the move field's own order; every move and cast goes through
`move_to` and `perform`. `test_coop_kits` 234/234, `test_coop` 473/473.

### Measured

Every sweep: fight seed pinned, 200 seeds a cell unless it says otherwise,
master (2662712 plus the adapter key fix) and the branch back to back. Nothing
in `core/scaler.gd`, `core/regions.gd` or `core/rules/power.gd` moved.

**`test_scaler`** (the gate for applying the fix to enemy casters): the level-3
lines and the boss pool are byte-for-byte master, as they must be — the
level-3 preset cleric is not a caster by the tie rule, and the scaler fields no
slot caster (CASTER_ELITE_CHANCE is 0.0; the only `lead_caster` is the cult's
site boss). At level 8 the cleric is a caster; every move is inside noise
(150 seeds, SE about 3.5):

| party, tier | master | branch |
|---|---|---|
| L3 easy / normal / hard | 96.5 / 93.0 / 81.0 | 96.5 / 93.0 / 81.0 |
| biomes downs / woods / marsh | 81.0 / 88.0 / 81.0 | 81.0 / 88.0 / 81.0 |
| L8 easy | 96.7 | 94.0 |
| L8 normal | 85.3 | 88.0 |
| L8 hard | 78.0 | 80.7 |
| boss pool | 71.0 | 71.0 |

So the fix is applied to enemy casters as well as the party.

**The caster sweeps** — parties with caster seats against rosters bought for
them at easy (target 95%):

The preset fighter beside two built sorcerers (`sweep_metamagic`), "off" the
sorcerers' Metamagic never armed, "on" Quickened and Twinned armed and priced:

| level | off, master | off, branch | on, master | on, branch |
|---|---|---|---|---|
| 3 | 85.0 | 92.5 | 83.5 | 93.5 |
| 5 | 93.0 | 97.0 | 95.0 | 96.5 |
| 10 | 79.5 | 86.5 | 83.0 | 88.0 |

The preset fighter and rogue beside one built sorcerer (`sweep_sorcerer`,
the shipped kit): level 3 93.0 → 95.0%, level 10 100.0 → 99.5%. The first
version, without the cone step, read 82.5% at level 3 here and 91.0 / 96.5 /
93.0% on the "off" row above: standing back is worth most to the sorcerers
whose damage is single-target, and cost the one whose only leveled damage is a
cone until the cone step gave it back.

**`sweep_caster_boss`** (the cult's lair boss at the Frontier tier, preset trio,
150 seeds; the only place a slot caster fights): plain lead 90.7 → 94.7% at
level 6 and 90.0 → 88.0% at 8 (the party side: the cleric is a caster there);
caster lead 74.0 → 81.3% and 70.0 → 78.0%. A mage that stops at spell range
instead of walking up to the fighter is a little easier to put down, not
harder; the caster room stays the harder climax it was measured to be.

**No re-price.** `core/rules/power.gd` already priced a caster's action as
the better of its swing and its best cantrip — it assumed the caster casts,
and the autopilot now does. Every caster row moved toward its 95% target and
none is over it past noise (level 5's 97.0 is +2); level 10 stays under it (a
caster still priced above what it plays, the safe side). Quickened's price
still holds: on minus off, priced, is +1.0 / −0.5 / +1.5 (was −1.5 / +2.0 /
+3.5). Both measurements are written into power.gd's comments and
`tests/sweep_metamagic.gd`'s header; no constant moved. `sweep_unpriced` reads
the preset trio, whose level-3 cleric is not a caster, so its level-3 rows are
master's by construction; its level-8 baseline is test_scaler's L8 hard above.

Not visible: no screen changed, so no screenshot. Tests:
`tests/test_autopilot.gd` (a sorcerer with no ranged weapon and a goblin six
hexes off casts and ends the turn at casting range, not adjacent, having not
walked in; three hexes off it casts rather than walking up to punch; beside a
goblin whose reaction is spent it steps out of reach free and casts; with the
reaction in hand it holds its ground and casts; a Burning Hands that would net
two from a step away is stepped to and thrown), `tests/test_enemy_casters.gd`
(a mage with nothing in reach walks until a spell does and casts from there,
not from beside the hero).

### Still open

- **The first cone on the bar.** The cone step (and the cone cast it feeds,
  unchanged from master) throws the first damaging cone the bar lists, so a
  level-10 sorcerer walks in for a level-1 Burning Hands with Cone of Cold
  prepared. Choosing the best cone is a slot-spending policy, its own pass.
- **Misty Step is never spent to get out of reach** at full HP (only at a third
  of HP, as before): a slot, and under the 2024 rule the turn's leveled spell.
- **Hit odds are not read.** A caster is chosen on average dice, so a
  save-for-nothing cantrip and a to-hit swing are compared as if both landed.
- **Leaving the field** is not a free step: the autopilot never withdraws.
- **The cone step takes the first cone hex in the move field**, even one beside
  a foe. Preferring the cone's far edge was tried and measured neutral
  (level 10 "off" 87.0% against 86.5%, the sorcerer seat 95.0% both), so it
  was not kept.

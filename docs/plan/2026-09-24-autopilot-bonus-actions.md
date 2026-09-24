## The autopilot spends its whole turn (2026-09-24)

The owner's ask: the autopilot should use Bonus Actions wherever reasonable.
Measured first: across every kit at levels 3 and 8, the party autopilot spent
a Bonus Action on **18%** of the turns it had one on offer, and only ever by
accident: `_use_kit` fired the first self-buff and Second Wind. It also turned
out to **swing once and return**. `resolve_attack` banks the rest of the Attack
action's swings in `econ.attacks_left`, and nothing ever spent them, so a
level-5 fighter fought as a level-4 one. The 2026-09-18 fix looped the
*monsters'* swings (`_strike`); the party path never used `_strike`.

**`core/ai.gd`:**

- `_party_auto` is now four steps: kit, heal the downed, the action, the
  Bonus Action.
- `_swing_all` spends every swing the economy holds, re-targeting between them.
- `_heal_downed` reaches for a Bonus Action heal (Healing Word, Mass Healing
  Word, Healing Light) before an action one, so the action is still there.
- `_party_action`: when a melee hero walks and still can't reach, a Bonus
  Action Dash (Cunning Action, Step of the Wind) covers the rest and the
  action still swings.
- `_bonus_after` takes the first rule that applies:
  1. more swings: Flurry of Blows, War Priest, an off-hand attack;
  2. a heal on an ally at a third of their HP or less;
  3. a Bonus Action spell that leaves something behind (Shield of Faith,
     Magic Weapon, Hunter's Mark, Spiritual Weapon), never over a held
     concentration; a smite-like one on a foe in reach;
  4. Bardic Inspiration on the ally with the most foes beside them; a summon;
  5. getting out at a third of HP with a foe adjacent: Misty Step to the
     furthest free hex (the resolver's own teleport test), or Disengage and
     walk away, or Patient Defense;
  6. a rogue with nothing beside them hides for next turn's Advantage.

Everything is chosen off `cb.available()`, so the 2024 one-leveled-spell rule
stays the resolver's to enforce.

**Measured.** The share of offered turns with a Bonus Action spent went
18% → 45% on `test_autopilot`'s every-kit sweep. The balance effect, from
`test_scaler`'s own sweeps, master against the branch:

| party, tier | master | branch |
|---|---|---|
| L3 easy | 96.5% | 96.5% |
| L3 normal | 90.0% | 93.0% |
| L3 hard | 79.5% | 81.5% |
| L8 easy | 87.3% | 96.0% |
| L8 normal | 78.7% | 84.0% |
| L8 hard | 58.7% | 79.3% |
| boss pool | 70.0% | 72.0% |

Level 3 has no Extra Attack and barely moves. Level 8 moves mostly on the
second swing every player already takes. So above level 5 the old ruler
measured a party weaker than anyone plays, and it read those fights as harder
than their targets (L8 hard 58.7% against 75%). With every swing taken, level 8
lands on the targets (96.0 / 84.0 / 79.3% against 95 / 85 / 75%).

**No knob moved.** The owner's call was to ship the ruler now and retune in
the next PR. `test_scaler`'s biome table was retaken: master had drifted off
the 09-23 row too, by 5 of the 6 allowed on the marsh. The marsh's 81.5% on
the test's 200 seeds is the draw: 600 fresh seeds put master at 82.2% and the
branch at 84.2%. The scaler and regions headers say which numbers are
old-ruler numbers.

**`tests/test_autopilot.gd` checks:**

- Extra Attack is swung, and a monk flurries into four swings.
- A rogue dashes to reach, and hides after a shot.
- Inspiration goes to the engaged ally.
- A held Bless is not overwritten.
- A downed ally is lifted by a Bonus Action heal with the action still spent
  on the fight.
- Misty Step and Disengage-and-walk at a quarter HP.
- Every kit at levels 3 and 8: fights end, the same seed plays the same
  fight, and the Bonus Action share stays at or above 35%.

### Still open

- ~~The retune question~~ **settled, no knob moved.** `sweep_regions` with the
  in-band curve added (80 seeds a cell, easy), master against the new ruler:
  level 3 96.2 → 93.8%, level 8 90.0 → 97.5%, level 10 81.2 → 96.2%,
  level 12 87.5 → 100%, level 15 78.8 → 93.8%. Every in-band level is on the
  95% target; the old ruler's level-10 and level-15 shortfall was the wasted
  second swing. The table is in `core/regions.gd`.
- **No Metamagic.** The autopilot arms none (it is not on master yet).
- **No Steady Aim.** The engine has no such verb.
- **Melee rogues** stay beside their target rather than Disengaging back out;
  Sneak Attack wants them there.

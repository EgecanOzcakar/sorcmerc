## Outmatched bands run — from the party, and from each other (2026-09-24)

Every hostile band hunted the party, however badly outmatched. A heartland
goblin pack walked straight at a level-9 company, and the only thing between it
and a fight it could not win was the approach card. Band against band was the
same: nothing stopped a band walking into a patrol that would rout it.

**A band too weak for something that would fight it now runs from it.** That
covers both kinds of band the player can have trouble with. One is a monster
band, which is hostile to the party always. The other is a civilized faction's
own patrol, once that faction has turned on the party (`FactionOpinion`
below `HOSTILE`). A friendly patrol has nothing to run from. Between bands, the
rule is `core/world_battle.gd`'s: two bands fight when either wants the other
dead. So a weak goblin pack runs from a strong human patrol, and a weak patrol
runs from a strong warband. Two monster bands never fight each other, so
neither runs.

**Strength is the fight it would field, not its headcount.** A band's
`troops` are a label and a model pick; no roster is built from them. Every
fight, the player's and the off-screen ones, is built by `core/scaler.gd` for
the party, times `Regions.power_scale` for where the band stands. So that
multiplier is the band's strength in the party's own units:

- The player is 1.0.
- A band inside its country's level range is 1.0, an even fight by
  construction.
- A band the party has outlevelled is less.

A band runs from anything it would field under **60%** of (`FLEE_BELOW`).
Measured 2026-09-24 with `Scaler.held_at` over `Presets.party_at(L)`, against
each country's top level:

| Country | Levels | The fight it fields | Its bands run from a party of |
|---|---|---|---|
| Heartland | 1–3 | L4 0.87, L5 0.54 | level 5 |
| Marches | 3–6 | L10 0.67, L11 0.58 | level 11 |
| Frontier | 6–9 | L13 0.71, L14 0.68 | later still |

Band against band, the same numbers apply. Once the party has outgrown the
heartland, a heartland pack is a 0.54 band and a marches warband a 1.0 one, so
the pack runs. Before that, every band is an even fight and nobody runs from
anybody. That is also what the fights would say. The party's wounds are left
out on purpose. `core/world_threat.gd` thins a fight for a hurt party, but that
is mercy on the party's side of the budget; a band doesn't grow braver because
the party is limping.

**How it runs.** `core/world_ai.gd`'s `_flee_step` handles it:

- A band notices a threat inside 200 units (`SIGHT`). It heads straight away
  from it, re-aimed every frame, and kept on dry land by `_steer()`.
- It keeps running until 320 units clear (`CLEAR`), so a band at the edge of
  sight doesn't turn back and forth.
- It outranks every behaviour except a truce's walk-away, which is already
  heading away.
- A hunt never picks a target it would run from, and a raid at the gate
  doesn't come for a party it would run from. So a hunter doesn't close to 200
  units, turn, and come back.
- A running band never reads as `arrived()`. So `core/raids.gd` can't advance
  a raider's phase while it runs. That matters for a raider backed against a
  lake, whose flee point `nearest_dry()` snaps onto where it already stands.
  Without the rule, a marching raid would have started its siege there, and a
  homeward one would have vanished.

**The gauge.** `core/world_flee.gd` prices the party once (its level and
`fresh_score`) and every band off that, through `Regions.scale_for`. That is
`power_scale` with the party already read, a pure extraction; `power_scale`
now calls it. The map screen re-gauges every 10 world-minutes into
`world.band_strength`. That field is runtime only, like the watchtower's
watch. It starts empty, and an ungauged band reads as an even fight. So every
test and tool that drives `WorldAI` without the map screen behaves exactly as
before.

This composes with the chase from `2026-09-24-click-to-meet.md`. A fleeing
band can still be clicked and run down. At the party's own speed, or faster,
that means the chase roll.

`tests/test_world_flee.gd` (30 checks) covers:

- the gauge equals `power_scale` band by band
- a weak band runs from the party and an even one hunts it
- an ungauged band stands
- the `SIGHT`/`CLEAR` margin
- a band that hasn't seen the party neither runs nor hunts it
- a friendly patrol doesn't run, and an enemy faction's weak patrol does
- band against band both ways, across the heartland/marches seam
- two bands of one country don't run
- two monster bands have nothing to run from
- a cornered raider doesn't read as arrived

Not visual beyond bands turning away on the map. No save field: `fleeing_from`
rides in the band's free-form `ai`, which `core/world_save.gd` already carries.

### Still open

- A band that runs looks exactly like one that hunts. A tell on the map (the
  figure turned away, a line on hover) would let the player read it before
  giving chase.
- `FLEE_BELOW`, `SIGHT` and `CLEAR` are taste, not a sweep (the file's
  `ponytail:`). The heartland empties of fights that come to the party at
  level 5. That is the intent, since those fights pay level-3 XP, but a
  playtest may want it later.
- Running is all or nothing. A band only a little outmatched could
  instead keep its distance, or come on only at night.

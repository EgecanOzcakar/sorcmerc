# sorcmerc — MVP brief

## Problem

A player who likes 5e combat has no way to get one clean fight in front of them in under a minute — tabletop needs a table, VTTs need a campaign, CRPGs bury the dice under animation. sorcmerc's bet is that the naked 5e combat loop (roll d20, beat AC, spend the slot, watch HP fall) is entertaining on its own when the math is visible and the fight takes three minutes.

## MVP

One hand-authored encounter, run in a terminal, that always ends in victory or defeat.

Ships:

- **One pregenerated PC.** Fixed stats, AC, HP, one weapon, two spells, two spell slots. No naming, no choices before the fight starts.
- **Two pregenerated enemies.** Weak enough that either can die in a turn or two; together they can kill the PC.
- **Initiative.** Rolled once at encounter start, fixed order for the fight, order is shown.
- **The player's turn = one decision:** pick an action, pick a target. Action set is exactly four: Attack, Spell A, Spell B, Dodge. Spells cost slots; when slots are gone those options are gone.
- **The 5e resolution core:** d20 + modifier vs AC, natural 20 crits (double damage dice), damage dice rolled and subtracted from HP, 0 HP removes a combatant.
- **Advantage/disadvantage,** with Dodge as the only source of it.
- **Everything else automated:** all rolls, enemy turns (a stated, dumb targeting rule), initiative, death.
- **A combat log** that shows every roll as its parts — `d20(14)+5 = 19 vs AC 15 → hit, 1d8(6)+3 = 9 damage` — not just outcomes.
- **Seeded RNG** so any run can be replayed exactly.
- **One runnable self-check** that plays the encounter headless to completion many times and asserts it always terminates with a winner.

## Explicit non-goals

- **Positioning, grid, movement, range, opportunity attacks, areas of effect.** Everyone is assumed in reach. This is the biggest cut and it is deliberate: the grid triples the surface area and the bet is about the dice loop, not the map. If the fight is boring without it, that is the answer we wanted.
- **Character creation, classes, levels, XP, equipment, inventory.** The PC is a constant.
- **More than two spells.** No spell list, no spell data model, no concentration, no conditions, no saving throws unless one of the two chosen spells needs one — and prefer two that do not.
- **Death saves.** PC at 0 HP is defeat, immediately.
- **Reactions, bonus actions, resistances, temp HP, healing, potions.**
- **Persistence, save/load, profiles, stats tracking.** Replay is rerunning the program.
- **Multiple encounters, encounter selection, difficulty settings, content files, a monster format.** One encounter, hardcoded.
- **Party of more than one PC.** Multiple PCs means an ally-control UI and turn switching for no additional signal.
- **Graphics, animation, colour theming, menus, title screen.**

Note on shape: an encounter engine, a campaign, and an authorable content system are three products. This scopes only the first, and it is scoped so the other two are not accidentally started.

## Success criteria

- Every run reaches a printed **Victory** or **Defeat** and exits. No hangs, no crashes, no stalemates. The self-check proves this across hundreds of seeded runs.
- A typical run is **6–15 rounds** and takes under three minutes of wall clock.
- Reading the log alone, a 5e-literate person can reconstruct why they won or lost — every hit/miss traces to a visible number.
- **Neither dominant strategy wins outright:** always-Attack and dump-both-slots-turn-one each lose some of the time. If one line always wins, the encounter has no decision in it.
- The user voluntarily replays it at least three times in a sitting, and the first request afterwards is for *more content*, not for the fight to work differently.

## Open risks

1. **The decision space may collapse.** With no positioning, "Attack" may be correct on nearly every turn and the two spells become a one-time damage button. This kills the core bet, and it is the thing the MVP exists to find out — measure it, do not pre-solve it with a grid.
2. **Single-encounter balance is a blind guess.** One badly chosen HP or damage number makes every run a foregone conclusion in either direction, and there is no tuning loop in scope. Numbers must be trivially editable in one place.
3. **Rules gravity.** Every 5e rule implies three more (a condition needs a duration needs a turn-end tick needs reactions). Any rule not in the MVP list above is a non-goal until the encounter ships.
4. **Log legibility is a real design problem, not a print statement.** Too verbose and the fight is unreadable; too terse and the "visible math" premise is gone. There is no second chance at a first read.
5. **Solo combat with no fiction may be inert.** The fun may live entirely in stakes and progression, both explicitly out of scope. Acceptable — if the bare loop is not fun, adding a campaign to it was going to be expensive anyway.

Given: TypeScript, terminal.

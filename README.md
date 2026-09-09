# sorcmerc

Turn-based combat on D&D 5e rules. Godot 4, GDScript. MVP = one hand-authored
encounter ("The Sunken Shrine") that plays start to finish.

## Layout

```
core/          pure rules, no engine deps — the part that's fully tested
  rng.gd         seeded xorshift32 (reproduce any fight)
  dice.gd        d20 adv/dis, dice notation, crit doubling
  combatant.gd   creature data + runtime state
  encounter.gd   The Sunken Shrine — all tuning numbers live here
  combat.gd      turn resolver: initiative, attacks, saves, death saves, zones, spells
  ai.gd          monster priority list + a party autopilot (demo/test only)
scenes/
  main.tscn/gd   minimal playable UI, built programmatically (placeholder art)
tests/
  test_combat.gd headless assertions on the dice/combat math
  autoplay.gd    headless full encounter, both sides on AI, narrated
docs/            product brief + combat design
```

## Run

Godot 4 is installed as a Flatpak here. A shorthand:

```sh
alias godot='flatpak run org.godotengine.Godot'
```

Play (needs a display):

```sh
godot --path .                       # opens the editor
godot --path . scenes/main.tscn      # runs the game directly
```

Headless checks (no display):

```sh
godot --headless --path . -s tests/test_combat.gd     # assertions
godot --headless --path . -s tests/autoplay.gd -- 42  # narrated fight, seed 42
```

## Status

- Rules core: complete and tested (533 assertions; encounter resolves across 200 seeds,
  ~86% party win on autopilot, avg ~8 rounds).
- UI: functional skeleton — initiative order, three zone panels, HP bars, action menu,
  coloured combat log. Placeholder visuals (coloured panels, no sprites).
- Not done: sprites/tilemap, roll animation timing, sound, the campaign layer.
  See `docs/combat-design.md` §9 for the intended feel.

## The encounter

Vera (Fighter 3) + Pike (Rogue 3) + Ilsa (Light Cleric 3) vs. Grull the bugbear
and three goblins, across three linear zones: Threshold ↔ Brazier Hall ↔ Alcove.
Tuned Hard — the party wins the damage race by ~2 rounds if it plays position and
tempo, loses if it plays a DPS race. Tune via `core/encounter.gd`.

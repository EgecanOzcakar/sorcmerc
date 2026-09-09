# sorcmerc

Turn-based combat on D&D 5e rules. Godot 4, GDScript. MVP = one hand-authored
encounter ("The Sunken Shrine") that plays start to finish.

## Layout

```
core/          pure rules, no engine deps — the part that's fully tested
  rng.gd         seeded xorshift32 (reproduce any fight)
  dice.gd        d20 adv/dis, dice notation, crit doubling
  hex.gd         flat-top axial hex math: distance, BFS reachable, cone, line
  combatant.gd   creature data + runtime state
  encounter.gd   The Sunken Shrine — board + all tuning numbers live here
  combat.gd      turn resolver: initiative, attacks, saves, death saves, hex movement, spells
  ai.gd          monster priority list + a party autopilot (demo/test only)
scenes/
  main.tscn/gd   playable UI: hex board, drawn tokens, styled buttons, tween juice
tests/
  test_hex.gd    headless assertions on the hex math
  test_combat.gd headless assertions on the dice/combat math
  autoplay.gd    headless full encounter, both sides on AI, narrated
  shot.gd        dev tool: render the scene and save combat_screen.png
docs/            product brief + combat design
```

## Run

Godot 4 is installed as a Flatpak here. A shorthand:

```sh
alias godot='flatpak run org.godotengine.Godot'
```

Play (needs a display):

Controls: number keys `1`–`9` pick the action, `0` ends the turn. Default click on
the board is Move (blue tiles); actions that need a target enter an aim mode where
hovering a token shows the hit / save / shove odds and a click applies it (`Esc` or
right-click cancels). Mouse wheel or `+` / `-` zooms (UI text scales with it), drag
or arrow keys pan, `Home` resets the view.

```sh
godot --path .                       # opens the editor
godot --path . scenes/main.tscn      # runs the game directly
```

Headless checks (no display):

```sh
godot --headless --path . -s tests/test_hex.gd        # hex math
godot --headless --path . -s tests/test_combat.gd     # rules assertions
godot --headless --path . -s tests/autoplay.gd -- 42  # narrated fight, seed 42
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_ui.gd  # robot presses real buttons
```

`SORCMERC_SEED` replays an exact fight; `SORCMERC_FAST` zeroes the UI tween timing.

## Status

- Rules core: complete and tested (663 assertions across hex + combat; encounter resolves
  across 200 seeds, ~93% party win on autopilot, avg ~8.8 rounds — tune in `core/encounter.gd`).
  Verbs: Attack, Shove (prone / back / brazier), Burning Hands (aimed cone, upcastable),
  Sacred Flame, Healing Word (upcastable), Second Wind, Dodge, Dash, Disengage, Help,
  Hide + Cunning Action (Pike). Difficult terrain flanks the brazier; opportunity attacks
  are path-aware; a mercy-rule constant governs finishing off downed PCs.
- UI: hex board with drawn tokens (initials + class glyph + tweened HP bar), a large glowing
  action log with round dividers, number-key actions, click-to-move with provoke warnings,
  hover-to-aim (hit / save / shove odds float over targets), a live Burning Hands cone preview,
  an attack-roll reveal (dice faces, discarded die struck, HIT/MISS/CRIT), a hover stat card,
  turn lookahead in the ribbon, confirm guards on Dodge/Dash/Second Wind, zoom-to-cursor with
  UI text scaling, pan clamp, and a seed-replay finish screen.
- Not done: sprite art, sound, the campaign layer, paced per-action enemy turns.
  See `docs/combat-design.md` §9, `docs/improvements.md`, and
  `docs/superpowers/specs/2026-09-09-hex-combat-design.md`.

## The encounter

Vera (Fighter 3) + Pike (Rogue 3) + Ilsa (Light Cleric 3) vs. Grull the bugbear
and three goblins, on a hex map: a Threshold room, a single-hex chokepoint into the
Brazier Hall (hazard at its centre), another choke, then the Alcove (half cover).
Melee reaches 1 hex, shortbows 6, Burning Hands is a length-2 cone. Tuned Hard —
the party wins the damage race by ~2 rounds if it plays position and tempo. Tune
ranges, speeds, and start hexes in `core/encounter.gd`.

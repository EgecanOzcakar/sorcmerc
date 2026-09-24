---
name: sorcmerc-godot-conventions
description: SorcMerc's engine setup, architecture and GDScript code style, as the repo actually does them. Use when writing or reviewing any .gd file, adding a mechanic, test, data file or save field, or deciding where new code belongs. Project-specific only; CLAUDE.md has the commands and runner details.
---

# SorcMerc Godot conventions

`CLAUDE.md` covers commands, the test runner and the top-level architecture. This skill covers the house style that the code follows and that CLAUDE.md doesn't spell out.

## Engine

- **Godot 4.7**, GL Compatibility renderer (`project.godot`). GDScript only; no C#, no GDExtension.
- **Autoloads:** `Audio` (`core/audio.gd`) and `AchievementToasts` (`scenes/achievements/toast.gd`). Don't add more lightly.
- Main scene: `scenes/game/game.tscn`.
- Godot runs as a Flatpak here. Always use `tools/run_tests.sh`, which is what CI runs.

## Architecture

- **`core/` is pure rules and state.** Every class there is `RefCounted`; the one exception is the audio autoload. There are no Nodes and no scene tree, so everything runs headless. New mechanics go here, and a scene calls into them.
- **No `class_name`, anywhere.** Scripts reference each other through `const X = preload("res://core/x.gd")` at the top of the file.
- **How logic talks to visuals.** Nothing is emitted from `core/`, which declares no signals:
  - A scene **calls** core functions. Core mutates its own state and appends human-readable lines to `Combat.log`, which the screen drains by index (`scenes/main.gd` `_logged`).
  - **Signals** are used only between UI nodes in `scenes/`: `chosen`, `closed`, `finished` and similar.
  - The one intentional await point in combat is `offer_reactions()`, and it suspends only when a reaction decider is installed (`core/ai.gd` header).
- **The build/fight seam is `core/adapter.gd`.** `Character` owns the build and `Combatant` owns the fight. The adapter converts one way, and `write_back` carries HP, pools and slots back.
- **Content is JSON, not `Resource`/`.tres`.** The repo has **zero** `.tres` files and no `extends Resource`.
  - The rules data is `data/*.json` (the SRD export plus `bestiary.json`). The sorcmerc mechanics layer is `data/effects/*.json`. `core/rules/catalog.gd` loads both. `data/SCHEMA.md` documents the gaps in the export.
  - Content packs (`content/`, `core/mod/`) are also JSON and ship no code.
- **One file per mechanism.** `core/world.gd` is the model, and each `core/world_*.gd` owns exactly one mechanism. Each file's header says what it does **not** own.

## Hex grid

- **Flat-top axial coordinates, stored as `Vector2i(q, r)`** (`core/hex.gd`). `Hex.DIRS` is the fixed six-direction order, and the index is the facing.
- **Pathfinding is custom, not `AStar2D`.** `Hex.reachable()` is a Dijkstra flood fill; `Hex.path_to()` runs on the same fill. Costs:
  - rough hexes cost 2 to enter;
  - climbing costs `CLIMB_STEP`, and a height change greater than `CLIMB_MAX` is a cliff;
  - height is passed as a Dictionary, not a Callable, because a Callable made the hottest function in a fight 42% slower (hex.gd header).
- The overworld is continuous `Vector2` space, not hexes. Band routing (`core/world_path.gd`) runs Dijkstra over a visibility graph around the water circles, then string-pulls the result.
- Units: rules are in feet and the board is in hexes. `Adapter.FT_PER_HEX` is 6.

## Turns and AI

- **Turns** are an initiative `order`, a `turn_idx` and a `round_num` on `Combat`, driven by `begin_turn()` and `end_turn()`, plus surprise and ambush rounds. There is no formal state-machine class. Action economy is tracked per combatant (`econ`).
- **Enemy AI is a priority list, not utility scoring** (`core/ai.gd`, from `docs/combat-design.md` §7):
  - use kit first (a self-buff, or a heal below half HP), then a special attack before a plain swing;
  - aim at the lowest-HP legal target;
  - archers step back before shooting;
  - the mercy rule applies (`MERCY`).
  - The one scored step is **movement**: candidate hexes get a score in hex units, adjusted by `ZONE_PENALTY` and a high-ground draw of less than 1.0.
  - `_party_auto` is the party autopilot that headless sweeps use.
- **RNG:** one seeded xorshift32 (`core/rng.gd`) per fight, passed in, never global. `SORCMERC_SEED` replays a fight. World outcomes are **seeded off the thing they belong to**, for example `hash("lair|%s" % id)` or a camp's world-time and position, so reloading can't reroll them. Never use `randi()` or `randf()` in `core/` for gameplay; the few existing uses are cosmetic or file names.

## GDScript style

- **Static typing is the norm but not total.** About 94% of functions declare a return type. Variables use `:=` or explicit types. Typed arrays (`Array[int]`, `Array[String]`) are used for state.
  - Parameters that take another core script's instance are usually **left untyped** (`func take_turn(cb, actor)`), because without `class_name` there is no type to name.
  - Match the surrounding code; don't retrofit types across a file.
- **Static functions over instances** for stateless modules. Examples: `Adapter.rest(ch, kind)`, `Visit.rest(party, world, kind)`, `WorldThreat.assess(party)`.
- **Constants in `SCREAMING_CASE` near their use**, each with a comment giving the reason and, when tuned, the measurement.
- **File headers** are long prose. They explain *why*, list the public API as a usage block, and say what the file does not own. Match that density.
- **Comments cite their provenance**: a ticket id (`T94`, `#176`, `O16`), a date, or a measured number. `ponytail:` marks a deliberate simplification and the condition for revisiting it.
- **Saves** (`core/*_save.gd`) read missing keys with defaults (`d.get("k", default)`), so old saves keep loading. Add a field and its default together, and never rename a key.

## Tests

- Tests are plain `extends SceneTree` scripts with `_pass`/`_fail` counters and a local `check(cond, label)`. No framework. `tests/test_world_bands.gd` is the model to copy.
- The verdict is the exit code. A failed `assert()` hangs, so the runner wraps every test in a timeout.
- `drive_*.gd` robots press real UI buttons. Every new screen needs a way for them to reach it.
- A visible change in a PR needs a screenshot (`tests/shot*.gd`). A rule change needs test output instead.

## Never touch without asking

The paths in `.github/always-ask.txt`: `project.godot`, `export_presets.cfg`, `tools/bug-relay/`, `.github/`, plus the security and lockfile rows. The shipped game holds no credentials.

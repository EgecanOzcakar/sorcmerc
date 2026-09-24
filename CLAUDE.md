# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A D&D 5.5e (2024) CRPG in Godot 4.7 / GDScript: character creation, hex tactical combat, and an open-world campaign layer. `README.md` is the orientation map; the build log is the authoritative dated record of what exists: `docs/expansion-plan.md` up to 2026-09-24, then one file per entry in `docs/plan/` (`python3 tools/plan_log.py` prints both as one).

## Commands

Godot is installed as a Flatpak here — `alias godot='flatpak run org.godotengine.Godot'`.

```sh
tools/run_tests.sh                           # the whole suite: import, parse check, every test
tools/run_tests.sh --unit                    # just tests/test_*.gd
tools/run_tests.sh --drive                   # just the drive robots
tools/run_tests.sh tests/test_story.gd       # just these files
tools/run_tests.sh --list                    # print what would run, run nothing
GODOT=/path/to/godot tools/run_tests.sh      # if `godot` is not on PATH
TEST_TIMEOUT=1200 tools/run_tests.sh         # per-test seconds, default 900
```

`tools/run_tests.sh` is exactly what CI runs (`.github/workflows/tests.yml`), so local green and PR green are the same claim. One test at a time:

```sh
godot --headless --path . -s tests/test_combat.gd
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_ui.gd
```

Running the game (needs a display): `godot --path . scenes/game/game.tscn` is the real entry point; `scenes/main.tscn` jumps straight into a standalone demo fight.

Screenshots for PRs — note `shot_world.gd` is **not** headless, the capture hangs:

```sh
godot --path . -s tests/shot.gd                     # combat board  -> combat_screen.png
godot --path . -s tests/shot_world.gd               # overworld     -> world_screen.png, world_turned.png
godot --headless --path . -s tests/shot_screens.gd  # every menu    -> shots_tmp/ (SHOT_ONLY=party for one)
```

Env vars: `SORCMERC_SEED` replays an exact fight/route, `SORCMERC_FAST` zeroes UI tweens and skips cosmetic systems, `SORCMERC_MODS_DIR` relocates community packs, `SORCMERC_UNLOCK_DLC=1` owns every paid pack, `SORCMERC_LINEAR_CAMPAIGN=1` restores the old node-route campaign, `SORCMERC_DEBUG=1` shows the title screen's "Random battle (debug)" button.

One-time: `git config core.hooksPath .githooks` so changed assets are re-imported after a pull or branch switch.

## Three things the test runner knows that a bare `godot -s` loop does not

1. **Assets must be imported first.** A script that preloads a texture cannot even *compile* without `.godot/imported/`, so on a fresh checkout half the suite fails with parse errors unrelated to the tests.
2. **The verdict is the exit code, never the output.** Tests print summaries in several different formats; all of them `quit(1)` on failure.
3. **A failed `assert()` hangs** — the SceneTree never reaches `quit()`. Everything runs under `timeout`, and a timeout is a failure, not a skip.

Tests are plain `extends SceneTree` scripts with their own `_pass`/`_fail` counters and a local `check(cond, label)` helper — no framework. Match that shape when adding one (`tests/test_world_bands.gd` is representative).

## Architecture

**`core/` is pure rules and state with no engine dependencies; `scenes/` draws it.** Core classes are `RefCounted`, not `Node` (the one exception is `core/audio.gd`, which is an autoload and has to be), which is why the whole game is testable headless and why the drive robots can play real sessions. Keep new mechanics in `core/` and let a scene call into them — this split is the strongest convention in the codebase.

**The build/fight seam is `core/adapter.gd`.** `Character` owns the build, `Combatant` owns the fight, and the adapter converts one way plus carries HP/pools/slots back. `core/rules/` is the 5e build engine behind `Character`: `catalog.gd` loads `data/*.json`, grants/bundles/choice resolve features step by step through the `pass_*.gd` passes, `resolve.gd` assembles the final sheet, and `effects.gd` + `data/effects/*.json` layer sorcmerc-authored combat mechanics over the prose-only SRD export.

**Encounter difficulty is composed from independent multipliers, each answering a different question.** `Scaler.roster_for()` owns the power budget and its curve; callers pass a `power_scale` that multiplies together `WorldThreat.assess(party)` (how beaten-up the party is — can only scale *down*) and `Regions.power_scale(world, pos, party)` (which of the four concentric countries this is, which clamps the level a fight is built for). See `scenes/world/world.gd`'s `encounter_spec()` for the composition, and `core/regions.gd`'s header for why the bands exist at all. Don't collapse these into one knob.

**A board theme picks both the terrain and the roster.** `Encounter.THEMES` names the hex boards; `Scaler.THEME_FACTION` maps a theme to the faction that fights on it and `THEME_HABITAT` filters the bestiary by habitat. `data/bestiary.json`'s 316 entries are hand-tagged with `faction` and `habitat`, and `Encounter._grow()` grows every authored room into its own seeded lumpy shape at fight time.

**The overworld is one model plus a file per mechanism.** `core/world.gd` holds the clock, settlements, lairs, landmarks, roaming parties, the water blobs that are the map's only terrain, and the fog. Each `core/world_*.gd` sibling owns exactly one thing (lairs, band spawning, threat, camping, foraging, pathing, off-screen battles, saving) and says in its header what it does *not* own. `scenes/world/world.gd` owns the screen; `scenes/world/world_view3d.gd` owns the 3D scene it draws into.

**Content packs are data only and ship no code** (`core/mod/`, `docs/modding.md`). The bundled packs under `content/` are written against the same public API a player's mod uses.

**Determinism is an idiom, not an afterthought.** Outcomes are seeded off the thing they belong to (`hash("lair|%s" % lair.id)`, the world-time and position of a camp) so that reloading cannot reroll a result the player didn't like. Saves in `core/*_save.gd` read missing keys as defaults, so a save written before a feature existed still loads.

## Conventions worth respecting

- **Balance numbers in comments are measured, and the comment names the sweep that produced them.** `BOARD_SHELVES` in `core/encounter.gd`, the tier knobs in `core/scaler.gd`, `FT_PER_HEX` in `core/adapter.gd` and the win-rate table in `core/regions.gd` all carry their measurements in capitals. Changing one is a balance pass with a re-run sweep, never an eyeballed edit.
- **`ponytail:` comments mark deliberate known simplifications** and usually state the condition under which to revisit. There are ~48. Don't silently "fix" one; if you do address it, remove the note.
- **File headers are long, prose, and explain the *why*** — including what the file deliberately does not own. Match that density rather than writing terse headers.
- **The build log is the source of truth, and every feature adds a NEW FILE to it: `docs/plan/YYYY-MM-DD-slug.md`**, in the `## Title — subtitle (date)` format with a `### Still open` section for deferred work (`docs/plan/README.md`). Never append to `docs/expansion-plan.md`: it is closed, because every PR appending to one file made every pair of open PRs conflict. `tests/test_plan_entries.gd` fails on an append. `docs/improvements.md` marks itself superseded and is archive only.
- **Every visible change in a PR needs a screenshot** (`.github/PULL_REQUEST_TEMPLATE.md`). For a non-visual change — a rule, a save format, a balance number — say so and paste test output instead.
- **Co-op lockstep and the modding API are promises, held by tests.** `tests/test_coop_kits.gd` fights every class in lockstep and `tests/test_mod_api.gd` freezes what a content pack may write (snapshot in `tests/fixtures/mod_api.json`, an API-1 canary pack in `tests/fixtures/mods/`). The `sorcmerc-compat` skill says what each needs from a change, and how to add vocabulary or state without breaking either.
- **`.github/always-ask.txt` lists paths an automated fix may never touch**: `project.godot`, `export_presets.cfg`, `tools/bug-relay/`, `.github/`, plus the generic security/lockfile rows.
- **The shipped game holds no credentials.** The bug reporter opens GitHub's own new-issue form in the player's browser; `core/bug_report.gd` argues the case at length. Don't add a token to anything that ships.

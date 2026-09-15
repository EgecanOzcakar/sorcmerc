# sorcmerc

A full D&D 5.5e (2024) CRPG: character creation, a hex-based tactical combat
engine, and a roguelike-style campaign layer (a generated route of fights,
merchants, rest and treasure nodes, a boss at the end). Godot 4.7, GDScript.
Started as a single hand-authored encounter ("The Sunken Shrine") — that
fight still exists as the classic boss, but it's one entry in a much larger
game now. `docs/expansion-plan.md` is the authoritative running log of what
was built and when; this file is an orientation map, not a changelog.

## Layout

```
core/            pure rules + game state, mostly no engine deps
  rng.gd, dice.gd, hex.gd        seeded RNG, d20/dice notation, axial hex math
  combatant.gd, combat.gd        runtime creature state + the turn resolver
  ai.gd                          monster turn logic (prioritizes special attacks)
  character.gd, adapter.gd       a build (Character) <-> a fight (Combatant), the seam
  encounter.gd, scaler.gd        board assembly + the difficulty/roster estimator
  loot.gd                        what a won fight leaves: who died decides what
                                  was on them, how dangerous they were decides
                                  how often and how good
  campaign.gd, campaign_save.gd  the run: generated route, shop/rest/treasure,
                                  autosave
  party.gd                       shared inventory, resurrection, marching order
  quest.gd                       what a quest is, and how each kind makes progress
  quest_posting.gd               which counter in which settlement posts which kind
  leveling.gd, progression.gd    per-character XP/level, and the meta-progression
                                  (lifetime XP unlocks species/classes/subclasses)
  achievements.gd, character_save.gd, settings.gd   local user:// persistence
  audio.gd, barks.gd, enemy_names.gd, ui_icons.gd, tutorial.gd   presentation
                                  data/helpers (procedural SFX, combat flavor
                                  lines, fantasy enemy names, the shared icon/
                                  color palette, the guided first fight)
  rules/           the 5e character-build engine (F2 spec): catalog.gd loads
                    data/*.json, grants/bundles/choice resolve a build's
                    features step by step, resolve.gd assembles the final
                    sheet, effects.gd + data/effects/*.json layer sorcmerc-
                    authored combat mechanics over the (prose-only) export
  mod/             the content-pack API (M1-M8): manifest/registry/entitlement
                    find and gate packs, world_pack.gd builds a map from JSON,
                    story.gd + story_runtime.gd are a campaign's schema and its
                    playthrough. Data only — a pack ships no code. See
                    docs/modding.md
scenes/
  game/            the one entry point (title -> party setup -> campaign ->
                    summary), routes every other screen
  mods/            the campaign/mod browser: everything installed, what state
                    it is in, and the button that starts one
  main.gd/.tscn    the combat screen: hex board, tokens, action log, buttons
  campaign/        the run screen: route choices, shop/rest/treasure, journal
  creator/, party/, profile/, progression/, achievements/, settings/
                   character creation + leveling, roster management, the
                   character sheet, the meta-progression viewer, the
                   achievements viewer, the settings overlay
data/              the 5e SRD export (classes/spells/species/...), a 316-
                   entry hand-tagged bestiary, and data/effects/*.json (the
                   sorcmerc-authored mechanics layer over the raw export)
content/           content packs that ship with the game: an example map, a
                   free campaign, and a paid DLC — all three written against
                   the same public API a player's mod uses
tests/             84 files, headless: one per subsystem (65 test_*.gd) plus
                   8 drive_*.gd (robots pressing real UI buttons end-to-end),
                   check_scripts.gd (every .gd in the project still parses)
                   and a few dev tools (shot.gd renders a frame to PNG).
                   Run them all with tools/run_tests.sh
docs/              docs/expansion-plan.md is the current source of truth;
                   modding.md is the content-pack authoring guide (worlds,
                   campaigns, data overlays, free/paid DLC); combat-design.md
                   and the docs/superpowers/specs/ hex design doc are the
                   original pre-expansion design record
tools/run_tests.sh the whole headless suite in one command — the asset import,
                   a project-wide script parse check (tests/check_scripts.gd),
                   then every test_*.gd and drive_*.gd. What CI runs on every
                   pull request, and what a contributor runs locally, so the
                   two are the same claim
tools/gen_audio_elevenlabs.py
                   the same SFX and bark file names from the ElevenLabs sound-
                   effects API instead, per sound, for anything the synthesis
                   cannot make sound like a recording. Needs a key; the
                   synthesized set stays the default and the fallback
tools/gen_audio.py procedurally synthesizes every SFX/music/bark asset under
                   assets/audio/ — no external audio assets, run it again
                   after editing it to regenerate. `--rate`/`--loop` trade
                   file size against fidelity; the default 32 kHz stereo is
                   13 MB for all 35 assets
tools/synth.py     the DSP it is built on: band-limited oscillators, biquads,
                   Freeverb, Karplus-Strong, and a formant voice for the barks
tools/check_audio.py
                   validates the generated WAVs (no clipping, no DC offset,
                   loop seams continuous) — the waveform half of the audio
                   tests, since tests/test_audio.gd can only prove the engine
                   parses them
tools/gen_action_icons.py
                   draws assets/icons/ — a gilt-framed 64x64 SVG badge for
                   every skill the action bar can offer (each combat-castable
                   spell, each feature that becomes a button, each Shove
                   variant) plus the verb-kind and spell-school fallbacks and
                   the bar's own controls, and the .import each one is read
                   through. Motifs are composed from a shared library and
                   coloured by what the skill does, so the disc says school and
                   the mark says fire/frost/poison. `--check` fails if a
                   committed icon has drifted from its recipe
```

## Assets and provenance

AI generation **may** be used for visual assets and for music/audio. This replaces the
project's earlier all-deterministic stance (policy changed 2026-09-12). The constraint
was dropped; the obligation it existed to avoid was not.

**Steam disclosure.** Shipping AI-generated art or audio requires declaring it in the
store page's AI content disclosure at publish time. Steam's form changed on 2026-01-16:
AI *coding* assistants are exempt, shipped AI-generated *art and audio* are not.
Whoever completes that form months from now needs to know what actually went into the
build — which is the point of the table below.

**Provenance stays decidable per asset.** Generated and hand-made/licensed assets live
in separate directories, so any file's origin is answerable from its path alone:

| Path | Origin | Recorded in |
|---|---|---|
| `assets/audio/` | procedurally synthesized, stdlib only — **not AI** | `tools/gen_audio.py`, `tools/synth.py` |
| `assets/icons/` | SVG path data written as source, stdlib only — **no image model**; the coordinates were authored with a coding assistant, which the disclosure exempts | `tools/gen_action_icons.py` |
| `assets/world/` | sourced packs | `License.txt` per subdirectory |
| `assets/fonts/` | DejaVu | `LICENSE-DejaVu.txt` |

**As of 2026-09-12 nothing in this repo is AI-generated.** Anything added under the new
policy goes in its own directory with the tool and date recorded alongside it, the same
way every directory above already carries its origin. Don't mix generated and licensed
assets in one folder — that is what makes the disclosure question answerable later
without archaeology.

## Run

Godot 4.7 is installed as a Flatpak here. A shorthand:

```sh
alias godot='flatpak run org.godotengine.Godot'
```

One-time setup so new/changed assets (art, audio, fonts) always get
imported automatically after a pull or branch switch — without this, a
pull that touched `assets/` can throw "Cannot open file ...ctex/.fontdata"
until someone remembers to run `godot --headless --import` by hand:

```sh
git config core.hooksPath .githooks
```

Play (needs a display):

```sh
godot --path .                       # opens the editor
godot --path . scenes/game/game.tscn # runs the game directly (the real entry point)
godot --path . scenes/main.tscn      # jumps straight into a standalone demo fight
```

In combat: number keys `1`-`9` pick an action, `0`/space ends the turn. Default
click on the board is Move (blue tiles); actions that need a target enter an
aim mode where hovering a token shows the hit/save/shove odds and a click
applies it (`Esc` or right-click cancels, number keys still switch actions
while aiming). Mouse wheel or `+`/`-` zooms, drag or arrow keys pan, `Home`
resets the view, `F1` opens settings.

Headless checks (no display). The whole suite, which is also exactly what CI
runs on every pull request (`.github/workflows/tests.yml`):

```sh
tools/run_tests.sh            # asset import, script parse check, every test
tools/run_tests.sh --unit     # just tests/test_*.gd
tools/run_tests.sh --drive    # just the robots
tools/run_tests.sh tests/test_story.gd        # just these
GODOT=/path/to/godot tools/run_tests.sh       # if `godot` is not on PATH
```

Or one at a time:

```sh
godot --headless --path . -s tests/test_combat.gd     # any single subsystem test
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_ui.gd      # a robot plays a real fight
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_campaign.gd # a robot plays a whole run
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_game.gd     # title -> run -> summary, end to end
godot --headless --path . -s tests/test_mod_packs.gd   # every shipped content pack loads clean
godot --headless --path . -s tests/drive_story.gd      # a robot plays a pack campaign's first chapter
```

Writing a content pack? `docs/modding.md` is the guide, and the browser behind
the title screen's **Campaigns & mods** lists every pack with every problem it
has. To poke at one without the game:

```sh
SORCMERC_MODS_DIR=/path/to/mods godot --path . scenes/mods/mods.tscn
```

`SORCMERC_SEED` replays an exact fight/route; `SORCMERC_FAST` zeroes UI tween
timing and skips cosmetic-only systems (barks, audio) that have nothing
meaningful to assert on in a headless run. `SORCMERC_LINEAR_CAMPAIGN=1` puts the
old linear node-route campaign (and its Resume-the-last-run autosave) back on the
title screen; without it, "New run" goes straight to the open world.
`SORCMERC_MODS_DIR` moves where community packs are read from, and
`SORCMERC_UNLOCK_DLC=1` (like `SORCMERC_PLAYTEST=1`) owns every paid pack — see
`docs/modding.md`.

## Status

See `docs/expansion-plan.md` for the full, dated build log — it is the
authoritative record of what exists and when it landed, kept up to date
after every feature (this README is not re-synced per change, only on a
health-check pass). Broad strokes as of the last such pass: character
creation and leveling for all 12 classes/10 species, a hex tactical combat
engine covering all 15 real 2024 conditions and all 8 weapon mastery
properties, a 316-monster bestiary with faction/habitat-aware encounter
building, a generated campaign route (sized settlements, quests, rest/
treasure nodes, a seed-picked boss pool), shared party inventory with
rarity-gated pricing and magic item identification, meta-progression
unlocks, local achievements, procedural audio, and a guided tutorial fight.
There is now a narrative layer, and it arrived as a modding API rather than as
a hardcoded campaign: content packs (`core/mod/`, `docs/modding.md`) carry
worlds, chapters, a cast, dialogue with choices and quest chains, plus data
overlays over `data/*.json`, and the same pipeline carries the team's own free
and paid story packs. Still an unmerged experiment: an isometric board
presentation (`git branch -a` for the current list of `feature/isometric-*`
branches).

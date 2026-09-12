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
  campaign.gd, campaign_save.gd  the run: generated route, shop/rest/treasure,
                                  autosave
  party.gd                       shared inventory, resurrection, marching order
  quest.gd                       kill/collect quests offered by settlement NPCs
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
scenes/
  game/            the one entry point (title -> party setup -> campaign ->
                    summary), routes every other screen
  main.gd/.tscn    the combat screen: hex board, tokens, action log, buttons
  campaign/        the run screen: route choices, shop/rest/treasure, journal
  creator/, party/, profile/, progression/, achievements/, settings/
                   character creation + leveling, roster management, the
                   character sheet, the meta-progression viewer, the
                   achievements viewer, the settings overlay
data/              the 5e SRD export (classes/spells/species/...), a 316-
                   entry hand-tagged bestiary, and data/effects/*.json (the
                   sorcmerc-authored mechanics layer over the raw export)
tests/             32 files, headless, one per subsystem (test_*.gd) plus
                   drive_*.gd (robots pressing real UI buttons end-to-end)
                   and a couple of dev tools (shot.gd renders a frame to PNG)
docs/              docs/expansion-plan.md is the current source of truth;
                   combat-design.md and the docs/superpowers/specs/ hex
                   design doc are the original pre-expansion design record
tools/gen_audio.py procedurally synthesizes every SFX/music/bark asset under
                   assets/audio/ — no external audio assets, run it again
                   after editing it to regenerate
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
| `assets/audio/` | procedurally synthesized, stdlib only — **not AI** | `tools/gen_audio.py` |
| `assets/lpc/` | Liberated Pixel Cup art, CC-BY-SA 3.0 / GPL-3.0 / OGA-BY 3.0 | `assets/lpc/CREDITS.csv`, `LICENSES/` |
| `assets/generated/` | sheets composited from `assets/lpc/` | `*_credits.txt` per sheet |
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

Headless checks (no display):

```sh
godot --headless --path . -s tests/test_combat.gd     # any single subsystem test
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_ui.gd      # a robot plays a real fight
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_campaign.gd # a robot plays a whole run
SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless --path . -s tests/drive_game.gd     # title -> run -> summary, end to end
```

`SORCMERC_SEED` replays an exact fight/route; `SORCMERC_FAST` zeroes UI tween
timing and skips cosmetic-only systems (barks, audio) that have nothing
meaningful to assert on in a headless run. `SORCMERC_LINEAR_CAMPAIGN=1` puts the
old linear node-route campaign (and its Resume-the-last-run autosave) back on the
title screen; without it, "New run" goes straight to the open world.

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
Explicit, deliberate TODOs: no narrative/dialogue layer (held back on
purpose), and an isometric board presentation exists as an unmerged
experiment (`git branch -a` for the current list of `feature/isometric-*`
branches).

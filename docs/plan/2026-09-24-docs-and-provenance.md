## Provenance, the bible and the skills brought up to date — every AI asset recorded (2026-09-24)

Four of the design audit's owner calls (`docs/audit-game-design.md`, "The owner's
calls": 8.1, 8.2, 8.7, 7.1), all of them documents. **Non-visual:** nothing a player
sees changes, and the only code touched is the wording of two comments in
`core/scaler.gd`.

**Provenance (8.1, audit §8).** The design bible's rule is that every AI-generated
asset sits in a directory whose `PROVENANCE.md` gives the tool, model, date and
prompt, because that is what the Steam AI-content disclosure will be filled in from.
Four such files existed, and seven directories of generated art had none. Every one
has one now, written from what the repository itself still holds:

- the ComfyUI graph ComfyUI writes into a PNG's `tEXt` chunk, which still sits in
  237 of the 362 paintings in `assets/generated/` and all six pack portraits: model
  (`sd_xl_base_1.0`), sampler, steps, seed, prompt and negative. The new
  `assets/generated/PROVENANCE.md` tabulates all 362, splitting each prompt into its
  subject and one of three fixed style tails;
- the prompt tables in `tools/` (`tools/localgen/gen_floor_textures.py`,
  `gen_sorcmerc_items.py`, `gen_single.py`, `gen_reroll.py`,
  `tools/gen_audio_elevenlabs.py`, `tools/gen_music_elevenlabs.py`);
- commit messages and the day each file was added (`git log --diff-filter=A`), and
  the build log.

What none of those hold is written down as **not recorded**, never guessed: the
prompts for the 3D models (they lived in the owner's `~/kitbashforge/`), for the 125
paintings with no metadata (first-pass counter portraits, the mood variants and the
outcome frames), for the shipping item icons (a 2026-09-16 repaint whose script is
not in the repo; the scripts that are describe the overwritten first pass), and for
the map's ground textures.

The audit missed one directory, and it is the biggest correction: **`assets/audio/`
is AI-generated.** The README called it "procedurally synthesized — not AI", but
120 of its 123 files are ElevenLabs sound-effects takes: the stings (made
2026-09-15 to 2026-09-21), the barks and the beds. `assets/audio/PROVENANCE.md` maps each file
to its prompt table and to the commit that made the take that ships. Two files are
`tools/gen_audio.py`'s synthesis (`marsh.wav`, `dice_rattle.wav`), and one,
`music/title.wav`, was placed by hand and its origin is not recorded anywhere.

The four existing files were completed and corrected: `assets/figures/` names the
seventeen rigs it had no entry for; `assets/troops/` no longer says orc_light and
orc_spellcaster are missing (they exist) or that the troops are unwired
(`scenes/world/party3d.gd` draws them), and says what is actually missing,
`human_light_idle.glb`; `assets/lairs/` is wired (`scenes/world/lairs3d.gd`) but
drawn only when `Lairs3D.source` is `"glb"`, and the kit is the default;
`assets/npcs/` has its date and says `female_mage.glb` is unused.
`assets/world/README.md` no longer calls its SDXL ground textures CC0.

`README.md`'s provenance table lists every asset directory, AI or not, and where it
is recorded, and "As of 2026-09-12 nothing in this repo is AI-generated" is gone.

**The bible (8.2, 8.7).** Art direction now has a 2D house style beside the 3D one,
taken from what the prompts say rather than from the one 3D prompt on record: all
243 recorded SDXL prompts say "painterly", in one of three tails (scenes, 110:
"painterly fantasy illustration, rich warm palette, soft rim light"; emblems, 122:
"… oil painting brushwork, rich but muted palette …" on a near-black ground;
portraits, 11). The icon line is corrected: the SVG icons are hand-authored, the
~428 item icons and achievement badges are SDXL. So is the audio line. The
paladin/ranger level-1 slot fix is marked built; rival raids and faction warfare
stay decided-not-built. A new section records the audit's calls that change the
game's rules or direction, one line each, as direction until each is built.

**The balancing skill and `core/scaler.gd` (7.1, audit §7).** The skill quoted
numbers the headers had moved past. It now says the half-caster level-1 gap is
fixed, quotes the current autopilot's 96.5 / 93.0 / 81.5% as the latest measured
(96.5 / 90.0 / 79.5 was the old autopilot), gives level 3 in the Marches as 28.8%
(17.5% under the old autopilot), and labels the fight lengths as old-autopilot
measurements. In `core/scaler.gd`, `CURVE := 1.15` is described as growing the budget
superlinearly (it said sublinearly), and the T40 block's "CURVE stays 0.90" is put
in the past tense. No constant and no measured number changed.

    GODOT=/tmp/claude-0/godot/godot tools/run_tests.sh tests/test_plan_entries.gd

### Still open

- **`music/title.wav`'s origin.** Placed by hand on 2026-09-16 and recorded nowhere.
  The owner is the only one who can say what made it; settle it before the store
  page.
- **`human_light_idle.glb` does not exist**, but `party3d.gd` names it, so a human,
  bandit or soldier band led by a light troop marches as the pawn. Generate it or drop
  the entry.
- **`assets/npcs/female_mage.glb` is unused and still exported.** Assign it or delete
  it, and the lair GLBs ship while the kit draws every lair by default.
- **The generator scripts are not in the repo.** `~/kitbashforge/` (every Meshy
  prompt) and most of `~/localgen/` (`gen_sorcmerc_scenes.py`, `_events.py`,
  `_moods.py`, `regen_sorcmerc_items.py`, `gen_overworld_ground.py`) hold the only
  copies of the prompts marked "not recorded" here. Committing them, or even their
  prompt tables, would close most of those gaps.
- `tools/import_item_art.py` and `tools/item_art_picks.txt` describe the overwritten
  first pass; re-running them would replace the shipping icons with the old look.
- Model versions for Meshy (all but the goblin) and ElevenLabs (no model id is sent)
  are not recorded. A future generation should write them into its `PROVENANCE.md`
  the day it lands.

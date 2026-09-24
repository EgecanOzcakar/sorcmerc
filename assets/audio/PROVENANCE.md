# assets/audio — mostly AI-generated (ElevenLabs), three files not

**120 of the 123 files here are AI-generated** and carry the Steam AI-content
disclosure obligation described in the README's "Assets and provenance", which
covers shipped AI audio exactly as it covers art. Until 2026-09-24 the README called
this directory "procedurally synthesized — not AI". That was true on 2026-09-13 and
stopped being true the next day, when the first 14 stings were replaced with
ElevenLabs takes (`14e31a2`); today every file but three is a take.

This directory is **mixed**, an exception to the README's one-origin-per-directory
rule, because `core/audio.gd` finds a sound by its name and does not care which tool
wrote it. The table at the bottom says which file is which.

## The 120 ElevenLabs takes

- **Tool:** the ElevenLabs sound-effects API (`POST /v1/sound-generation`), called by
  `tools/gen_audio_elevenlabs.py` for stings and barks, and by
  `tools/gen_music_elevenlabs.py --engine sfx` for the beds and music stings. That
  route rather than the Music API because the account's plan did not include the
  Music API (commit `6999d1c`); the sound-effects model returns mono, and all 120
  are 16-bit mono at 44.1 kHz.
- **Model:** the API's default sound-effects model. Neither script sends a model id,
  so **which model version answered is not recorded.**
- **Prompts:** in the scripts, keyed by the file's name — `SFX` and `BARKS` in
  `tools/gen_audio_elevenlabs.py`, `BEDS` and `STINGS` in
  `tools/gen_music_elevenlabs.py`. A take `hit_2.wav` is the `hit` prompt again
  (`--take N`); the barks are three takes each of their archetype's prompt. The
  tables are read as committed: a prompt edited after its take was made would only
  show in `git log -p` of the script. Every take then went through the script's own
  post-pass — trimmed or looped, levelled, faded (not AI).
- **Not deterministic:** the same prompt returns a different take every run, so these
  files are the only copy of what ships.

## The three that are not AI

| File | Origin |
|---|---|
| `music/marsh.wav` | Synthesized by `tools/gen_audio.py` (`bed_marsh`), 2026-09-22 (`d99f0b1`): the ElevenLabs quota ran out before it. Its prompt is in `BEDS` for when it is replaced. |
| `sfx/dice_rattle.wav` | Synthesized by `tools/gen_audio.py` (`sfx_dice_rattle`), 2026-09-23 (`8036e0b`). `SFX` holds an ElevenLabs prompt for it too, but the shipped file is the synthesized one (stereo, where every take is mono). |
| `music/title.wav` | Placed by the owner, 2026-09-16 (`0a1f436`, "chore: update title screen music asset"). **Its origin is not recorded**: neither tool's table has it, and nothing in the repository says what made it. Settle this before the store page. |

## Every file, by the commit that made the take that ships

(`7ebb4fe`, 2026-09-21, later added a 4 ms fade-in to 43 of these; that is a
post-pass, not a new take.)

| Made | Commit | Files |
|---|---|---|
| 2026-09-15 | `1ef748c` | 17 weapon-class and spell-school stings: `sfx/hit_{axe,bite,blunt,bow,claw,pierce,slam,sword,thrown}.wav`, `sfx/cast_{abjuration,conjuration,divination,enchantment,evocation,illusion,necromancy,transmutation}.wav` |
| 2026-09-16 | `57ff75e` | 26 stings: `sfx/{burst,buy,cast,click,collapse,condition,crit,defeat,down,heal,hit,identify,kill,level_up,miss,miss_ranged,pickup,quest,quest_complete,rest,save_failed,save_made,settlement,shop,travel,victory}.wav` |
| 2026-09-16 | `ba7d03a` | 26 second and third takes: `sfx/{crit,hit,hit_axe,hit_bite,hit_blunt,hit_bow,hit_claw,hit_pierce,hit_slam,hit_sword,hit_thrown,miss,miss_ranged}_{2,3}.wav` |
| 2026-09-16 | `5cc718d` | 12 bark stingers: `barks/{deep,gruff,hero,squeak}{1,2,3}.wav` |
| 2026-09-21 | `5c44cd2` | 20 stings for landmarks, objectives, threat clocks and the board: `sfx/{blessing,cache_open,captive_freed,carter_down,lair_dug,landmark_found,landmark_open,lead_marked,map_reveal,offering,quarry_gone,raid_bell,raid_drums,raid_horn,raid_lifted,rumour_bought,search_found,search_nothing,settle,wave_arrives}.wav` |
| 2026-09-21 | `ab95abf` | 6 music stings: `sfx/music_{alarm,deed,discovery,founding,relief,road}.wav` |
| 2026-09-21 | `6999d1c` | 12 music beds: `music/{city-square,deeps,forest-clearing,frontier,frozen-cave,goblin-camp,heartland,marches,merchant-shop,settlement,sunken-shrine,tension}.wav` |
| 2026-09-22 | `d99f0b1` | `music/downs.wav` (ElevenLabs) and `music/marsh.wav` (synthesized, above) |
| 2026-09-23 | `8036e0b` | `sfx/dice_rattle.wav` (synthesized, above) |
| 2026-09-16 | `0a1f436` | `music/title.wav` (origin not recorded, above) |

Licence: ElevenLabs output. Commercial use depends on the ElevenLabs plan the takes
were generated under; read their terms before the store page is filled in.

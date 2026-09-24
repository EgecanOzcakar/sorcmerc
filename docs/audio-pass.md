# The audio pass

2026-09-21. What `assets/audio/` is, file by file, before the new features got
their sounds; what was condemned and why; what was left alone and why. Nothing
here was listened to — this branch runs headless — so the quality read is a
measurement, not an ear: duration, peak and RMS, clipping, DC offset, spectral
flatness and the count of harmonic peaks (a pure oscillator is a comb of them;
a recording is not), the level of the first and last 10 ms (a one-shot that
ends loud is a voice cut off; one that *starts* loud is a click), and for the
beds the step at the loop seam. The script that took the numbers is a page of
numpy; `tools/check_audio.py` is the part of it worth keeping and now also
fails a one-shot that starts on a step.

## Where each file comes from

Two tools write into `assets/audio/`, and the set is mixed:

- `tools/gen_audio.py` synthesizes offline out of oscillators, filters and a
  reverb — deterministic, reproducible, no account. Its docstring still says
  "the beds and barks are this file's". Half of that is stale.
- `tools/gen_audio_elevenlabs.py` writes the same file names from ElevenLabs'
  sound-effects model: a recording of a thing rather than a recipe for one.
  Not deterministic, so its output is committed.
- `tools/import_licensed_sfx.py` (2026-09-24) rebuilds 45 sfx from real
  recordings in the Sonniss GDC bundles into `sfx/licensed/`, which is
  **gitignored**: that license lets them ship in the game but not be handed out as
  sound files, and this repo is public. `core/audio.gd` plays `licensed/<id>.wav`
  over `<id>.wav` and its takes, so the ElevenLabs files stay as the fallback a
  clone without the bundles plays. Never feed the licensed files to a generator:
  the license forbids using them to develop or enhance AI. The built files live
  in the private `EgecanOzcakar/sorcmerc-licensed-audio`: the git hooks run
  `tools/fetch_licensed_sfx.sh` to keep `sfx/licensed/` a checkout of it, and the
  release workflow clones it with a read-only deploy key (the
  `LICENSED_AUDIO_SSH_KEY` secret) before the import, so itch builds carry them.

Measured, the split is:

| set | files | source | fingerprint |
|---|---|---|---|
| stings (`sfx/`) | 43 ids, 70 files with the `_2`/`_3` takes | ElevenLabs, all of them (PR #44/#45, then `ba7d03a` for the takes) | mono 44.1 kHz, peak 28480 exactly (the tool's normalization target) |
| barks (`barks/`) | 12 | ElevenLabs (`5cc718d`, "the twelve bark stingers are takes now") | mono 44.1 kHz, peak 28480, capped at 1.00 s with the 120 ms fade |
| beds, the six themes + settlement + tension (`music/`) | 8 | `gen_audio.py`'s rebuilt recipes (`5b93c3e`) | stereo 32 kHz, 8.0 s, 13–19 harmonic peaks, flatness < 0.012 |
| beds, the four D6 countries | 4 | `gen_audio.py` **before** the rebuild (`68eca99`); the rebuild dropped their recipes and nobody regenerated the files | mono 22 kHz, 4.0 s, a bare sine/tri/saw — 26, 33 and 58 harmonic peaks on deeps, frontier and marches |
| `music/title.wav` | 1 | neither tool: `0a1f436`, "chore: update title screen music asset", a 60 s stereo track the author dropped in by hand | 22 kHz, peak 0.927, fades in and out |

## Who plays what

Every `Sound.play_sfx` / `play_bark` / `set_environment` in `core/` and
`scenes/`, before this branch:

- **combat** (`core/combat.gd`): `bark()` is the hookpoint — `hit`, `crit`,
  `kill`, `down` off `BARK_SFX`, and the weapon-class hits (`hit_sword`, `_axe`,
  `_blunt`, `_pierce`, `_bow`, `_thrown`, `_claw`, `_bite`, `_slam`) and misses
  (`miss`, `miss_ranged`) that `core/weapon_sfx.gd` picks per attacker; the
  eight `cast_<school>` off the spell; `heal`, `save_made`/`save_failed`,
  `condition`, `collapse`, `burst`. The twelve barks (`hero`/`gruff`/`deep`/
  `squeak` × 3) play under a text bark, one per line.
- **the linear run** (`core/campaign.gd`): `rest`, `pickup`, `settlement`,
  `travel` on a node; `victory`/`defeat` at the end of a fight; `level_up`;
  `identify`, `buy`, `quest_complete`. The beds per node theme, `settlement`
  between fights, `set_combat` in a fight.
- **the map** (`scenes/world/world.gd`): `settlement` at the gate, `shop` at
  the shop door, `buy`, `quest` (the board *and* a bought rumour), `heal`,
  `identify`, `pickup`, `rest`; the bed per D6 country off `_check_region`,
  `settlement` inside a town.
- **the title** (`scenes/game/game.gd`): the `title` bed. `click` is every
  button (`core/ui_icons.gd`), `quest_complete` is also the achievement toast.

`cast` and `hit` (the generic ones) still exist on disk and are the fallbacks
when the classifier has nothing better; `level_up` and `defeat` are only the
linear run's.

## The read

**Stings — kept.** No clipping anywhere (every peak is the 28480 target), DC
under 0.012 FS everywhere, every tail under 0.05 FS RMS. They are what the
tool says they are: takes. One defect, on 41 of the 70 files (and two of the
barks, `deep3` and `squeak2`): the *first* sample is not near zero. `defeat.wav` opens at −0.62 FS, `hit_slam.wav` at
−0.78, `level_up.wav` at +0.51, `cast_abjuration.wav` at −0.31. The trim keeps
5 ms of lead before the first live window, but a take whose sound starts at
sample 0 has no lead to keep, and after normalization that first sample is a
step from silence: a click, masked on an impact, audible on a chime or a slow
tone (`defeat`, `level_up`, `victory`, `save_made`, `cast_abjuration`,
`settlement`, `shop`). Not a reason to regenerate anything — the fix is a 4 ms
fade-in in the tool's post-pass (`HEAD_FADE_MS`), applied in place to the
committed files that had the step, and a matching check in `check_audio.py`
so it cannot come back.

**Barks — kept.** Already takes; the brief for this pass assumed they were
still oscillators because `gen_audio.py`'s docstring says so, and the
docstring was wrong. Measured clean: no DC, tails at zero after the fade, the
four archetypes still four (see `5cc718d`'s pitch runs). `hero2.wav` is 0.27 s
against its siblings' 1.0 s — a single short grunt, complete (its envelope
rises, peaks and falls inside the file), not a cut. Twelve API calls to make
twelve more takes of the same prompts would buy a different set, not a better
one.

**The eight rebuilt beds — condemned, replaced.** They are exactly what
`gen_audio.py` says: "still generated audio rather than recorded audio", and
the numbers agree — a flatness under 0.012 and, on the seven theme beds, a
comb of 13–19 harmonic peaks is a saw pad through a filter, however good the
reverb. Eight-second loops of
a four-chord progression also wear through inside a minute on the map screen,
which is where most of a session is spent. Replaced with 58 s loops, each
prompt written from the recipe's own mood (the key, the instruments, the
texture — `bed_frozen_cave`'s "vast and still, ice bells far apart" is the
prompt), the file names kept, and the loop seam crossfaded in the writer.
`tension.wav` keeps its one rule: it plays *over* whichever theme bed is
running, so it is asked for as percussion and a single-note pulse with no
chord changes — and the first take of it was a few hits and silence, so the
prompt now says "dense from start to finish" in so many words, and the retry
is.

The plan was the Music API (`tools/gen_music_elevenlabs.py`, 45–60 s pieces,
MP3 back through ffmpeg). The account this ran on gets a 402 from it —
`paid_plan_required` — so every bed and every music sting came through the
tool's `--engine sfx` road instead: the sound-effects model the sfx tool
already uses, which takes a `loop` flag and up to thirty seconds. Asked for
thirty it returns sixty, and the fold takes two, so the beds are 58 s, mono
like every other take, at the synthesized set's 0.89 peak. The day the
account can compose, `beds` with the default engine writes the same names.

**The four country beds — condemned, replaced.** The worst files in the set:
the pre-rebuild synthesis (one held chord, a tremolo, a saw), 22 kHz mono,
four seconds long, and — the deciding part — unreproducible, because the
rebuild deleted their recipes and the files were never remade. The gradient
`68eca99` describes (root pitch walking down G → F → D → G₁ as the country
gets older and emptier, the tremolo climbing through the settled bands and
dropping to stillness in the deeps) is carried into the four prompts.

**`title.wav` — kept.** Not either tool's; the author put it there by hand
four days ago, at 60 s with its own fade in and out. A tool does not overwrite
a hand-placed asset.

## What the new features play

None of these made a sound before this branch. Every id is a
`Sound.play_sfx` at the moment it names; `music_*` ids go through
`Sound.play_sting`, which is `play_sfx` on the Music bus without the pitch
drift (a ±6 % drift is right for a sword and wrong for a phrase that has to
sit in a key over the bed), on one player of its own. The stings came back
from the sound-effects model as a phrase, half a second of nothing, and the
phrase again; the post-pass keeps the one with the most in it, so they run
3.4 s (relief) to 11.7 s (alarm) rather than the 6–12 s asked for.

| moment | where | id |
|---|---|---|
| a landmark turns up on the map | `world.gd` `_check_places` | `landmark_found` |
| the place's card opens | `_open_place` | `landmark_open` |
| a Survival search finds the place / the tracks | `_place_action`, `_lair_action` | `search_found` |
| ... finds nothing; a landmark check lost | same, and `landmarks.gd` `resolve` | `search_nothing` (`hit_pierce` when the snare draws blood) |
| the door opens: a cache, a blessing, the offering, a lead, the tower | `landmarks.gd` `_open` | `cache_open`, `blessing`, `offering`, `lead_marked`, `map_reveal` |
| the doors that already had a sound | same | `scouted` → `identify`, `road`/`safe_camp` → `rest`, `camp_kit` → `pickup` |
| a landmark answered | same, on top of the door | `music_discovery`; `music_road` for the tower's reveal and watch |
| a hold wave arrives | `combat.gd` `_spawn_wave` | `wave_arrives` |
| the captive cut loose | `_objective_touch` | `captive_freed` |
| the quarry gone | `_quarry_escape` | `quarry_gone` |
| the carter (or the captive) killed | `_kill` | `carter_down`, over the `down` the body already makes |
| raiders set out / camped outside / the raid lands / lifted / dug in | `raids.gd` where each line is made | `raid_horn`, `raid_drums`, `raid_bell` + `music_alarm`, `raid_lifted` + `music_relief`, `lair_dug` |
| a raid turned on the road | `world.gd` `_launch_combat` | `music_deed` |
| a waystation settled | `_lair_settle_action` | `settle` + `music_founding` |
| a job taken | `_take_quest` | `quest` — the existing sting is literally "accepting a quest" and was never played here |
| a job turned in | `_turn_in` | `buy` (kept) + `music_deed` |
| a rumour bought | `_buy_rumor` | `rumour_bought`, instead of the `quest` it borrowed |

The raid sounds fire in `core/raids.gd` rather than on the world screen
because the screen gets prose back from `Raids.tick()` and matching on prose
is how a sound silently stops playing the day a line is reworded;
`core/combat.gd` and `core/campaign.gd` already play from `core/` on the same
reasoning, and the statics are no-ops headless.

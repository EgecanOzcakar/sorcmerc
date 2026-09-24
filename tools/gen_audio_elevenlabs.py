#!/usr/bin/env python3
"""ElevenLabs sound effects for sorcmerc, as an alternative to tools/gen_audio.py.

    export ELEVENLABS_API_KEY=...
    python3 tools/gen_audio_elevenlabs.py --list          # the prompts, writes nothing
    python3 tools/gen_audio_elevenlabs.py sfx             # regenerate EVERY sting (63)
    python3 tools/gen_audio_elevenlabs.py --only hit,crit # just those two
    python3 tools/gen_audio_elevenlabs.py sfx barks       # stings and the voice stingers

Why this exists alongside tools/gen_audio.py rather than replacing it: that
file synthesizes every asset offline out of the stdlib, which is what makes
`assets/audio/` reproducible from source with no network, no account and no
bill. It stays the default and stays supported. What it cannot do is sound like
a recording -- it is oscillators and filters, and several of the stings read as
exactly that. This writes the same file names into the same directories from a
generative model instead, so swapping is per-sound: regenerate `hit` here,
leave `click` as the synthesized one, and the game neither knows nor cares.

Output format: 16-bit PCM mono WAV at 44.1 kHz, which is what `pcm_44100` from
the API already is -- this only wraps it in a RIFF header. core/audio.gd reads
the sample rate and channel count out of each file's `fmt ` chunk rather than
assuming them, so a mono file sits happily beside the synthesized stereo ones.

NOT deterministic, unlike gen_audio.py: the same prompt returns a different
take every run. So the generated WAVs are committed (they already are), and
this is a tool you reach for when a sound needs replacing, not part of a build.
Listen to what comes back before committing it; a take can miss.

API: POST https://api.elevenlabs.io/v1/sound-generation, `xi-api-key` header.
`prompt_influence` trades faithfulness to the prompt against the model's own
judgement -- high for a sound with a precise brief (a click), lower where the
model has more room (a victory sting). Cost is per generation and this writes
63 of them for `sfx`, so --only is the normal way to use it. The beds and the
music stings are tools/gen_music_elevenlabs.py's, off the Music API.
"""
import argparse
import json
import math
import os
import struct
import sys
import urllib.error
import urllib.request

import trim_sfx

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
OUTPUT_FORMAT = "pcm_44100"
# The API's own floor, enforced server-side: anything under half a second is a
# 400. Shorter is still what several of these want -- a UI click is a tick, not
# half a second of anything -- so the prompt asks for a short sound and the rest
# of the window comes back as the silence after it, which costs a few KB of WAV
# and nothing at playback: core/audio.gd fires these as one-shots.
MIN_SECONDS = 0.5
MAX_SECONDS = 30.0
SR = 44100
CHANNELS = 1
KEY_ENV = "ELEVENLABS_API_KEY"

# What comes back is NOT drop-in on its own, and both reasons are measurable
# against the synthesized set it has to sit beside:
#
#  * LEVEL. tools/gen_audio.py peak-normalizes every sting to 28480 (-1.2 dBFS),
#    uniformly, all 14 of them. A generated take lands wherever it lands -- the
#    first click back was 7691, a quarter of that -- so dropping it in unchanged
#    makes one sound in the game four times quieter than its neighbours. Matched
#    to the same number rather than a number of my own, so the two sets mix.
#  * LENGTH. The API has a half-second floor and overruns it anyway; the first
#    click was 0.96s, against 0.06s for the synthesized one. Almost all of that
#    is silence after the sound, and a UI click that holds an audio voice for a
#    second is a click you can hear queueing. Trimmed to the actual sound.
PEAK = 28480                # tools/gen_audio.py's own normalization target
# Silence is judged over a WINDOW, not per sample. A take's noise floor is not
# flat -- the first usable click came back with the sound over by 200 ms and a
# single stray sample at 0.8% FS near the very end, which is enough to defeat a
# per-sample scan and keep three quarters of a second of nothing. RMS over a
# short window ignores one sample and still catches a real tail.
WINDOW_MS = 10
SILENCE_RMS = 0.004         # 0.4% FS averaged over a window: room tone, not sound
LEAD_MS = 5                 # kept before the first live window, so nothing clicks in
TAIL_MS = 60                # kept after the last, so a decay is not chopped
# The lead is only kept when there is one to keep. A take whose sound starts
# at sample 0 -- most impacts, and some chimes -- has no silence in front of
# it, and after normalization its first sample is a step from nothing to
# 0.6 FS: a click, masked under a slam and plain under a bell (defeat, level_up
# and cast_abjuration all shipped with it). Four milliseconds is under any
# attack the ear can tell from instant and long enough to be no step at all.
HEAD_FADE_MS = 4

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)

# name -> (prompt, seconds, prompt_influence)
#
# The prompts describe the SOUND, not the game event: "a sword hitting mail" is
# something a model has heard, "hit.wav" is not. Lengths match what the game
# gives each sting room for -- core/audio.gd fires these as one-shots over
# combat, so anything past about a second is still playing when the next thing
# happens.
#
# Three rules every prompt keeps, from measuring the takes (2026-09-24):
#  * A REAL SOURCE. "Real foley recording of", "field recording", "live orchestral
#    recording", and magic built from real layers (torch, glass, bowed metal,
#    wind), never "fantasy game magic" or "sting": those words pull the model
#    toward synth patches. "No synthesizer" where it might reach for one.
#  * A QUIET FLOOR. The first set carried hiss at a median 65 dB under the peak
#    (24 dB on shop, pickup, cast_enchantment) and constant codec tones through
#    their silence. "Silent background, no hiss" on everything recorded close.
#  * THE EVENT FIRST. The game fires a hit when it lands; library takes put the
#    impact up to 1.3 s in. Combat prompts say where the impact falls.
# And one sentence every sfx prompt ends with (jobs() appends it, so --list shows
# it): the handpicked library hits are heavy and dark next to a take -- a 0.9 kHz
# spectral centroid against 2-3 kHz -- so every take asks for that weight. The
# model does not reliably honour it, which is what tone_match() below is for.
SFX_STYLE = ("Full-bodied and weighty, with a deep natural low end and soft rounded "
             "highs, like a professional cinematic sound library recording; not bright, "
             "not harsh, not tinny, not retro, not arcade, not 8-bit")
SFX = {
    "hit": ("Real foley recording of a steel sword blade striking a chain mail shirt on a"
            " padded dummy. The impact lands within the first 0.1 seconds: a sharp bright"
            " crack of steel on rings over a short dull body thud, then mail rings "
            "jingling as they settle. Close microphone, dry room, silent background, no "
            "hiss, no whoosh before the hit, no music", 0.7, 0.7),
    "crit": ("Real foley recording of a brutal heavy sword blow cleaving a steel plate "
             "and biting into meat. The impact lands within the first 0.1 seconds: a loud"
             " tearing metal crack, a deep wet meaty thud and a bone snap, then a short "
             "metallic ring-out. Close microphone, dry, silent background, no hiss, no "
             "build-up, no music", 0.9, 0.65),
    "kill": ("Real foley recording of an armored body falling dead onto stone flagstones,"
             " one continuous event: a heavy body thud at the very start, a steel sword "
             "clattering on the stone a moment later, then chain mail rings settling. "
             "Close microphone, dry room, silent background, no hiss, no voice, no music", 1.0, 0.6),
    "cast": ("Magic spell built from real recordings: a short sharp intake of breath, the"
             " rushing whoosh of a torch swung hard, then a crisp snap of flint struck on"
             " steel with a few scattering sparks. Close microphone, dry, silent "
             "background, no hiss, no synthesizer, no electronic tones, no music", 1.1, 0.5),
    "heal": ("Healing magic built from real acoustic sources: a soft warm breath of air, "
             "a wet finger circling the rim of a crystal wine glass rising gently in "
             "pitch, and one soft harp string plucked at the end. Close microphone, "
             "intimate, silent background, no hiss, no synthesizer, no drums", 1.2, 0.5),
    "level_up": ("Live acoustic recording of a short celebratory flourish: a quick rising"
                 " harp run, a glockenspiel sparkle, and two bright natural trumpet notes"
                 " landing on a sustained major chord. Real instruments in a small hall, "
                 "no synthesizer, no vocals, ends with a natural ring-out", 1.6, 0.45),
    "victory": ("Live orchestral recording of a short medieval victory fanfare: two bold "
                "natural trumpet and French horn calls over a snare drum roll and timpani"
                " hits, resolving to a sustained major chord with a cymbal swell. Real "
                "players in a concert hall, no synthesizer, no vocals, ends cleanly", 2.5, 0.4),
    "defeat": ("Live orchestral recording of a short somber defeat phrase: a slow "
               "descending minor line on low cellos and bassoon, one deep muffled timpani"
               " hit, ending on a hollow sustained low chord that fades out. Real players"
               " in a concert hall, no synthesizer, no vocals", 2.5, 0.4),
    "click": ("Real foley recording of one small wooden game token placed firmly on a "
              "hardwood tabletop: a single tight dry tick with a tiny woody knock at the "
              "very first instant. Very short, close microphone, silent background, no "
              "hiss, no ring, no second tap, no reverb", 0.5, 0.9),
    "buy": ("Real foley recording of four gold coins dropped one after another onto a "
            "wooden shop counter, starting immediately: bright metallic clinks and a "
            "short jingle as they settle. Close microphone, dry room, silent background, "
            "no hiss, no voice, no music", 0.8, 0.75),
    "identify": ("Magic reveal built from real acoustic sources: a gentle rising shimmer "
                 "of small brass wind chimes brushed by hand, resolving into one clear "
                 "sustained tone of a struck crystal glass. Close microphone, silent "
                 "background, no hiss, no synthesizer, no drums, no voice", 1.2, 0.5),
    "quest": ("Real recording of a parchment scroll unrolled with a crisp dry paper "
              "rustle, followed by one short noble two-note call on a real brass natural "
              "horn. Small room, silent background, no hiss, no synthesizer, no drums, no"
              " voice", 1.2, 0.5),
    "pickup": ("Real foley recording of a small leather pouch with a metal buckle "
               "snatched quickly off a wooden table, starting immediately: a brief "
               "leather rustle and one light metallic tick. Very short, close microphone,"
               " dry, silent background, no hiss", 0.5, 0.8),
    "rest": ("Field recording of a small wood campfire at night: logs crackling, one log "
             "shifting and settling into the embers, soft ember pops over a quiet distant"
             " bed of crickets. Warm and calm, natural outdoor ambience, no voices, no "
             "music, no wind rumble, fades out gently", 2.0, 0.45),

    # T9z: per-weapon-class hits. core/weapon_sfx.gd picks one off the attacker's
    # main-hand weapon (or a monster's damage type), so a bow and a mace stop
    # sounding the same. Each is the SWING through the air and then the landing.
    "hit_sword": ("Real foley recording of a steel longsword slashing into a chain mail "
                  "hauberk: a very short swish that lands within the first 0.1 seconds in"
                  " a bright ringing metal clang, then rings jingling. Close microphone, "
                  "dry, silent background, no hiss, no music", 0.7, 0.7),
    "hit_axe": ("Real foley recording of a heavy steel battle axe chopping into an iron-"
                "rimmed wooden shield: a very short swish that lands within the first 0.1"
                " seconds in a deep splintering wood thunk with a dull metallic bite, "
                "then a wood creak. Close microphone, dry, silent background, no hiss, no"
                " ring, no music", 0.7, 0.7),
    "hit_blunt": ("Real foley recording of an iron mace smashing into a steel breastplate"
                  " worn over padding: the impact lands within the first 0.1 seconds, a "
                  "deep dull crunching thud with a short low metallic clank, then a faint"
                  " rattle. Close microphone, dry, silent background, no hiss, no ring, "
                  "no music", 0.7, 0.7),
    "hit_pierce": ("Real foley recording of a steel spear point thrust through leather "
                   "and chain mail into a padded target: the impact lands within the "
                   "first 0.1 seconds, a short sharp metallic shink as rings part and a "
                   "quick muffled puncture. Very brief, close microphone, dry, silent "
                   "background, no hiss, no music", 0.5, 0.75),
    "hit_bow": ("Real foley recording of an arrow shot into a wooden shield: a short taut"
                " bowstring snap, and within 0.15 seconds the steel-tipped arrow thuds "
                "into the wood with a hard woody thunk, the shaft buzzing briefly after. "
                "Close microphone, dry, silent background, no hiss, no long flight "
                "whistle, no music", 0.9, 0.7),
    "hit_thrown": ("Real foley recording of a thrown javelin striking a wooden shield: a "
                   "brief whoosh that lands within the first 0.15 seconds in a solid "
                   "heavy wooden thunk, the shaft wobbling with a short creak after. "
                   "Close microphone, dry, silent background, no hiss, no music", 0.8, 0.7),
    "hit_claw": ("Real foley recording of large animal claws raking across a leather "
                 "jerkin: the impact lands within the first 0.1 seconds, three fast "
                 "tearing scratches with leather and cloth ripping and a slightly wet "
                 "edge. Close microphone, dry, silent background, no hiss, no metal, no "
                 "growl, no music", 0.6, 0.7),
    "hit_bite": ("Real foley recording of large jaws biting down on a leather-armored "
                 "limb: within the first 0.1 seconds a hard snap of teeth, then a wet "
                 "meaty crunch with leather squeaking under the pressure. Close "
                 "microphone, dry, silent background, no hiss, no growl, no voice, no "
                 "music", 0.6, 0.7),
    "hit_slam": ("Real foley recording of a huge heavy fist slamming into an armored "
                 "chest: the impact lands within the first 0.1 seconds, a deep powerful "
                 "body thump with real low-end weight, then armor plates rattling. Close "
                 "microphone, dry, silent background, no hiss, no voice, no music", 0.8, 0.7),

    # T9z: per-school casts. Picked off data/spells.json's `school`. Same wide,
    # magical space as the generic cast; what differs is the character of it.
    "cast_evocation": ("Fire spell built from real recordings: the rushing whoosh of a "
                       "torch swung hard, a gas burst igniting into a roaring fireball, "
                       "embers crackling and scattering, and a deep low thump underneath."
                       " Powerful, close microphone, silent background, no hiss, no "
                       "synthesizer, no electronic tones, no music", 1.2, 0.55),
    "cast_abjuration": ("Protective ward spell built from real acoustic sources: a struck"
                        " crystal singing bowl, then a bowed cymbal swelling into a "
                        "steady shimmering metallic hum that holds and stops. Bright and "
                        "solid, close microphone, silent background, no hiss, no "
                        "synthesizer, no voice, no music", 1.2, 0.5),
    "cast_conjuration": ("Summoning spell built from real recordings: a rush of wind "
                         "through a narrow gap spinning up, a low rumble of shifting "
                         "stone underneath, ending in a heavy thump of something landing "
                         "on earth and a short puff of dust. Close microphone, silent "
                         "background, no hiss, no synthesizer, no voice, no music", 1.2, 0.5),
    "cast_enchantment": ("Charm spell built from real acoustic sources: a soft descending"
                         " cascade of small brass bells and a music box, with a gentle "
                         "breathy whisper of air. Sweet and hypnotic, close microphone, "
                         "silent background, no hiss, no synthesizer, no impacts, no "
                         "words", 1.2, 0.5),
    "cast_transmutation": ("Transmutation spell built from real recordings: thick liquid "
                           "bubbling in a glass flask, metal creaking and stretching "
                           "under strain, wet clay squelching, settling into one clean "
                           "struck glass chime. Close microphone, silent background, no "
                           "hiss, no synthesizer, no voice, no music", 1.2, 0.5),
    "cast_divination": ("Divination spell built from real acoustic sources: an ascending "
                        "run of crystal glasses struck softly, a wet finger singing on a "
                        "glass rim, and a soft rush of air opening up. Ethereal, close "
                        "microphone, silent background, no hiss, no synthesizer, no "
                        "drums, no voice", 1.3, 0.5),
    "cast_illusion": ("Illusion spell built from real recordings: a soft breathy whisper,"
                      " a bowed saw wavering in pitch, and a faint slightly out-of-tune "
                      "glass ring that sounds wrong. Eerie but acoustic, close "
                      "microphone, silent background, no hiss, no synthesizer, no words, "
                      "no music", 1.2, 0.5),
    "cast_necromancy": ("Necromancy spell built from real recordings: a slow raspy "
                        "exhale, dry bones rattling in a wooden box, a low bowed double "
                        "bass note bending downward, and cold wind. Sinister, close "
                        "microphone, silent background, no hiss, no synthesizer, no "
                        "words, no music", 1.3, 0.5),

    # The silent moments. Everything above fires when something LANDS; a fight is
    # at least as much the swings that don't, the saves that hold, and the hero
    # who drops. Those fired with no audio at all until now.
    #
    # A miss is the hardest of these to get right and the most often heard: it
    # must read as "nothing happened" while still being a sound, so it is air
    # and no impact. Kept quieter and shorter than `hit` on purpose — it lands
    # on roughly half of all attack rolls, and a miss as loud as a hit is a
    # fight that sounds like it is going twice as well as it is.
    "miss": ("Real foley recording of a heavy steel longsword swung fast past a close "
             "microphone and missing: one short air swish that peaks within the first 0.2"
             " seconds and cuts off, with a faint leather creak from the swing. Dry, "
             "silent background, no hiss, no impact, no metal ring, no music", 0.5, 0.8),
    "miss_ranged": ("Real foley recording of an arrow flying past close to the "
                    "microphone: a short sharp whistling fly-by with a natural doppler "
                    "drop, then the wooden shaft clattering and skittering on a stone "
                    "floor a few meters away. Dry, silent background, no hiss, no "
                    "bowstring, no body impact", 0.7, 0.75),

    # Saves. A pair, so they read against each other: the same event resolving
    # two ways. Made is bright and upward and over quickly; failed is dull and
    # downward. Neither is a full sting — they ride under the spell that caused
    # them, which is already making noise.
    "save_made": ("Real foley recording of a blade glancing off a steel shield boss, "
                  "starting immediately: a short bright metallic scrape and ricochet with"
                  " a fast natural ring-out. Crisp, close microphone, dry, silent "
                  "background, no hiss, no voice, no music", 0.6, 0.65),
    "save_failed": ("Real foley recording of a heavy blow landing on a body, starting "
                    "immediately: a dull muffled thud with a low shudder, like a sandbag "
                    "struck with a wooden club. Close microphone, dry, silent background,"
                    " no hiss, no brightness, no ring, no voice", 0.7, 0.65),

    # `down` was `kill`'s asset until now — the same crash for a hero dropping as
    # for a foe dying, which made a party wipe sound like a victory. A body going
    # down but not out: heavier on the armor, no finality.
    "down": ("Real foley recording of an armored person dropping to their knees and "
             "slumping sideways onto stone flagstones, starting immediately: chain mail "
             "and plate rattling, one heavy muffled body thud, then the armor settling. "
             "Close microphone, dry, silent background, no hiss, no weapon clatter, no "
             "voice", 1.0, 0.6),
    "burst": ("Real recording of a wooden barrel blown apart, starting immediately: a "
              "sharp percussive blast with a deep low thump, oak staves splintering, wood"
              " debris and iron hoops clattering down on stone. Close microphone, dry, "
              "silent background, no hiss, no fire roar, no voice, no music", 1.0, 0.7),

    # Conditions and exhaustion. `condition` fires whenever a status lands, which
    # is often, so it is deliberately small — a marker, not an event.
    "condition": ("Real foley recording of poison taking hold, small and close: a short "
                  "thick wet bubbling gurgle, a faint sizzle of acid on metal, and a dry "
                  "rattle of small bones. Close microphone, silent background, no hiss, "
                  "no voice, no music", 0.7, 0.6),
    "collapse": ("Real foley recording of an exhausted person in armor collapsing face-"
                 "first onto stone, starting immediately: a limp heavy body fall, chain "
                 "mail and plate clanking then slowly settling, a long tired exhale. "
                 "Close microphone, dry, silent background, no hiss, no weapon clatter, "
                 "no music", 1.4, 0.55),

    # The world outside a fight. These are the places rather than the moments, so
    # they are looser prompts and lower influence — the model has more room, and
    # a settlement that sounds slightly different each generation is fine.
    "travel": ("Field recording of leather boots walking at a steady pace on a packed "
               "dirt road with small gravel, about six paces, a light pack and leather "
               "straps creaking with each step, faint open air. Natural outdoor ambience,"
               " no voices, no music, no wind rumble", 1.6, 0.6),
    "settlement": ("Field recording at a medieval town gate: a heavy wooden gate creaking"
                   " open on iron hinges, then a distant busy market square with a "
                   "murmuring crowd, a blacksmith's hammer far off and one faint church "
                   "bell. Natural outdoor ambience, no music, no clear words", 2.0, 0.45),
    "shop": ("Real foley recording of entering a small shop: a wooden door opening with a"
             " creak, a small brass bell hanging above it jingling twice, then a quiet "
             "room and one floorboard creak. Close microphone, dry, silent background, no"
             " hiss, no voices, no music", 1.2, 0.55),
    "quest_complete": ("Real recording of a leather coin purse dropped onto a wooden "
                       "table with the coins jingling, followed by a short bright three-"
                       "note phrase on a real natural trumpet resolving on a held note. "
                       "Small hall, no synthesizer, no vocals, ends cleanly", 2.0, 0.45),

    # Landmarks (core/landmarks.gd). The place turning up, the card opening,
    # the search on the ground, and one sound per door the card can open. The
    # doors that already had a sound (a camp kit is a pickup, a night in the
    # ring is a rest) reuse it rather than getting a twin.
    "landmark_found": ("Live acoustic recording of a soft two-note wooden recorder call "
                       "rising like a quiet question, with a faint rustle of parchment. "
                       "Real instrument, small dry room, silent background, no hiss, no "
                       "synthesizer, no drums, no voice", 1.2, 0.5),
    "landmark_open": ("Live acoustic recording of three soft plucked pizzicato violin "
                      "notes climbing upward, inquisitive and light, with a small breath "
                      "of wind under the last note. Real instrument, dry, silent "
                      "background, no hiss, no synthesizer, no drums, no voice", 1.2, 0.5),
    "search_found": ("Real foley recording outdoors: boots shuffling through dry leaves, "
                     "a hand brushing dirt and pebbles aside, then a small bright "
                     "metallic tick of a hidden coin uncovered and a short satisfied "
                     "exhale. Close microphone, natural, no music, no wind rumble", 1.4, 0.6),
    "search_nothing": ("Real foley recording outdoors: boots shuffling through dry leaves"
                       " and gravel, a hand sweeping dirt and pebbles aside, a short "
                       "pause, then a quiet disappointed sigh. Nothing found, no object "
                       "sound, close microphone, natural, no music, no wind rumble", 1.4, 0.6),
    "cache_open": ("Real foley recording of an old buried wooden chest pried open: an "
                   "iron hinge creak and a crack of old wood, then gold coins and small "
                   "metal trinkets spilling and jingling onto dirt. Close microphone, "
                   "dry, silent background, no hiss, no voice, no music", 1.5, 0.65),
    "blessing": ("Live recording in a small stone chapel: a soft warm wordless choir of "
                 "real singers swelling in on a major chord, one clear small handbell "
                 "ring, natural chapel reverb. Sacred and calm, no synthesizer, no "
                 "lyrics, no drums", 2.0, 0.45),
    "offering": ("Real foley recording of three silver coins placed one by one on a stone"
                 " altar, a small bright clink each, then a soft breath of wind through a"
                 " quiet stone shrine. Close microphone, silent background, no hiss, no "
                 "voice, no music", 1.6, 0.65),
    "lead_marked": ("Real foley recording of a feather quill scratching a quick short "
                    "mark onto rough parchment, then a firm tap of the quill tip on a "
                    "wooden table. Close microphone, dry, silent background, no hiss, no "
                    "voice, no music", 1.0, 0.7),
    "map_reveal": ("Real recording of a large parchment map unrolled across a table with "
                   "a big sweeping paper rustle, then a gust of open-country wind through"
                   " tall grass and a soft rising shimmer of brass wind chimes. "
                   "Expansive, no synthesizer, no voice, no drums", 2.5, 0.45),

    # Encounter objectives (core/objectives.gd, fired from core/combat.gd). The
    # wave and the quarry are things happening at the far edge of the board,
    # so they are further away than a hit; the carter and the captive are
    # stingers over the body drop the kill already makes.
    "wave_arrives": ("Real recording of enemies arriving: distant war cries from a group "
                     "of men and a short blast on an animal horn beyond a doorway, then "
                     "many armored boots running in on stone, shields and weapons "
                     "rattling, getting closer. Intense, natural, no music", 2.0, 0.55),
    "captive_freed": ("Real foley recording of a knife sawing fast through thick hemp "
                      "rope for a few strokes, the rope snapping loose and dropping to "
                      "the floor, then a short relieved gasp. Close microphone, dry, "
                      "silent background, no hiss, no music", 1.2, 0.65),
    "quarry_gone": ("Field recording of a person fleeing through a forest: fast running "
                    "footsteps crashing through undergrowth, snapping twigs and rustling "
                    "leaves, receding into the distance until silent. Natural outdoor "
                    "ambience, no voice, no music", 2.0, 0.6),
    "carter_down": ("Real foley recording of a heavy body slumping against a wooden cart "
                    "with a loud creak, wooden crates tumbling off and thudding on the "
                    "ground, followed by one low sustained note on a real cello. Brief, "
                    "no voice, no synthesizer", 2.0, 0.55),

    # Threat clocks (core/raids.gd). Heard on the map, mostly from far away:
    # a raid is something happening to a town over the horizon until it is not.
    "raid_horn": ("Field recording of a single long low blast on a real animal war horn "
                  "far away across open hills, carried on the wind with a natural distant"
                  " echo, then silence. No music, no voices, no synthesizer", 3.0, 0.5),
    "raid_drums": ("Field recording at night of distant real war drums in an enemy camp: "
                   "deep hide drums beating a slow steady menacing rhythm, faint "
                   "crackling campfires, heard from behind town walls, fading out. No "
                   "melody, no voices, no synthesizer", 3.5, 0.5),
    "raid_bell": ("Field recording of a medieval town under attack: a real bronze church "
                  "bell ringing fast and urgently, a distant panicked crowd shouting and "
                  "running feet on cobblestones. Chaotic, natural outdoor ambience, no "
                  "music, no clear words", 3.5, 0.5),
    "raid_lifted": ("Field recording of a real bronze church bell tolling once and "
                    "ringing out slowly over a quiet town, then morning birdsong "
                    "returning and a soft relieved murmur of townsfolk. Calm, natural "
                    "outdoor ambience, no music, no clear words", 3.5, 0.45),
    "lair_dug": ("Real recording of digging underground: iron shovels biting into packed "
                 "earth, claws scraping stone, rocks tumbling and loose dirt shifting, "
                 "heard muffled through the ground over a low natural rumble. Dark, no "
                 "voices, no music, no synthesizer", 2.0, 0.55),
    "settle": ("Field recording of a timber frame being raised: a wooden mallet driving a"
               " peg into timber, one hand-saw stroke, a heavy beam dropped into place "
               "with a solid thud, then a short cheer from a small group of people. "
               "Natural outdoor ambience, no music", 3.0, 0.5),

    # The board. Taking a job already had `quest` (the parchment and the horn);
    # a bought rumour was borrowing it, and is a coin and a whisper instead.
    "rumour_bought": ("Real recording in a quiet tavern: a single coin slid across a "
                      "rough wooden table, then a hushed low whisper leaning in close, "
                      "conspiratorial and unintelligible, over soft distant chatter and a"
                      " mug set down. Natural room, no music, no clear words", 1.8, 0.55),
}

# Wordless voice stingers, three takes per archetype (core/barks.gd picks one at
# random). The text has no words on purpose -- these play under a written bark
# line, so a spoken one would fight it.
BARKS = {
    "hero": "A human warrior's short determined battle grunt, wordless, mid-range voice",
    "gruff": "A grizzled older fighter's short gruff shout, wordless, gravelly voice",
    "deep": "A huge creature's short deep guttural roar, wordless, low and heavy",
    "squeak": "A small goblin's short high-pitched startled shriek, wordless",
}
BARK_TAKES = 3
BARK_SECONDS = 0.8
BARK_INFLUENCE = 0.6
# What a bark is allowed to last, whatever came back. `duration_seconds` is a
# request, not a promise -- takes have come back at 2s and 3s for the 0.8s asked
# -- and a bark is a stinger under one line of text, fired from an 8-voice
# round-robin (core/audio.gd) while the fight moves on. A roar that holds a voice
# for two and a half seconds is still going when the next character speaks. Over
# this, the take is cut and faded out rather than thrown away: these are single
# wordless sounds, so the end of one is a tail, never a word.
BARK_MAX_SECONDS = 1.0
# The fade that ends every bark, cut or not. A take that was cut obviously needs
# one; so does one the model itself ended mid-shout, which is most of the short
# ones -- tools/check_audio.py fails a one-shot whose last 10 ms are still loud,
# because that is a voice stopping rather than a sound finishing. Squared, so the
# last few milliseconds are already at nothing rather than a ramp cut short.
BARK_FADE_MS = 120
# The same rule for a sting, looser. The API returns about twice the length
# asked for, and a sound with no silence to trim -- a bell still ringing, a
# cheer still going -- comes back the full window: settle.wav was 6.0 s and
# cut off mid-cheer, raid_bell.wav 7 s of bell. Nothing on the map or the board
# earns more than this; the fade is longer than a bark's because these are
# scenes, not shouts, and a scene stopping dead is what the fade is for.
SFX_MAX_SECONDS = 4.5
SFX_FADE_MS = 300


def jobs(groups, only, take=0):
    """(group, name, out_path, prompt, seconds, influence) for everything asked for.
    `take` > 1 writes name_<take>.wav: another recording of the same prompt,
    which core/audio.gd round-robins with the first (see play_sfx)."""
    out = []
    suffix = "_%d" % take if take > 1 else ""
    if "sfx" in groups:
        for name, (prompt, secs, infl) in SFX.items():
            out.append(("sfx", name,
                        os.path.join(ROOT, "assets", "audio", "sfx", name + suffix + ".wav"),
                        prompt + ". " + SFX_STYLE, secs, infl))
    if "barks" in groups:
        for archetype, prompt in BARKS.items():
            for i in range(1, BARK_TAKES + 1):
                name = "%s%d" % (archetype, i)
                out.append(("barks", name,
                            os.path.join(ROOT, "assets", "audio", "barks", name + ".wav"),
                            prompt, BARK_SECONDS, BARK_INFLUENCE))
    if only:
        wanted = {s.strip() for s in only.split(",") if s.strip()}
        unknown = wanted - {j[1] for j in out}
        if unknown:
            sys.exit("no such sound(s): %s" % ", ".join(sorted(unknown)))
        out = [j for j in out if j[1] in wanted]
    return out


def trim_and_normalize(pcm):
    """Raw take -> the same sound at the synthesized set's level and length.

    Returns (pcm, before_secs, after_secs, peak_before). A take that is silent
    all the way through comes back untouched rather than divided by zero -- that
    is a miss to listen to and re-run, not something to amplify into noise.
    """
    n = len(pcm) // 2
    before = n / float(SR)
    if n == 0:
        return pcm, before, before, 0
    vals = list(struct.unpack("<%dh" % n, pcm))
    peak = max(abs(v) for v in vals)
    floor = SILENCE_RMS * 32767.0
    if peak < floor:
        return pcm, before, before, peak

    win = max(1, int(SR * WINDOW_MS / 1000.0))
    live = []
    for i in range(0, n, win):
        chunk = vals[i:i + win]
        rms = (sum(v * v for v in chunk) / float(len(chunk))) ** 0.5
        if rms >= floor:
            live.append(i)
    if not live:
        return pcm, before, before, peak

    first = max(0, live[0] - int(SR * LEAD_MS / 1000.0))
    last = min(n - 1, live[-1] + win + int(SR * TAIL_MS / 1000.0))
    vals = vals[first:last + 1]

    # Some takes come back riding a DC offset (tools/check_audio.py rejects
    # anything past 0.02 FS); centre them before the peak is measured for gain.
    dc = sum(vals) / float(len(vals))
    vals = [v - dc for v in vals]
    peak = max(abs(v) for v in vals)

    gain = PEAK / float(peak)
    vals = [max(-32768, min(32767, int(round(v * gain)))) for v in vals]
    return (struct.pack("<%dh" % len(head_fade(vals)), *vals),
            before, len(vals) / float(SR), peak)


# Tone. Measured against the handpicked library hits (2026-09-24): the model's
# takes carry ~17 dB more energy above 15 kHz than a recording does -- a
# separately generated top band, heard as fizz, and where its hiss and constant
# tones live -- and 8-20 dB less below 120 Hz. The octave under that (8-16 kHz)
# is already thinner than a recording's, so the cut sits at 15 kHz, not lower:
# at 11 kHz it dulled that octave and left fizz on top. So each sfx take is
# pulled toward the library's balance: the band above AIR_HZ cut, the band below
# LOW_HZ lifted, each only as far as that take needs, and a take already there is
# left alone. The caps are per run: a take that hit one moves further if run
# again, so --retone is once per take. Targets are the library's medians,
# measured with these same filters.
# The low target is an impact's (half a library hit's energy is its thump), so
# the lift is capped at 6 dB: enough to give a chime or a click some body without
# turning it into a thud. A take with next to nothing down there is not lifted at
# all -- that would only raise rumble.
AIR_HZ, AIR_TARGET_DB, AIR_MAX_CUT = 15000.0, -31.8, 24.0
LOW_HZ, LOW_TARGET_DB, LOW_MAX_BOOST, LOW_FLOOR_DB = 120.0, -2.8, 6.0, -40.0


def _biquad(vals, b0, b1, b2, a1, a2):
    out, x1, x2, y1, y2 = [0.0] * len(vals), 0.0, 0.0, 0.0, 0.0
    for i, x in enumerate(vals):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def _rbj(kind, f0, sr, db=0.0):
    """RBJ cookbook coefficients, Q = 0.707 / shelf slope 1, normalized by a0."""
    w = 2 * math.pi * f0 / sr
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2 * 0.7071)
    if kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:
        A = 10 ** (db / 40.0)
        sa = 2 * math.sqrt(A) * alpha
        if kind == "high":
            b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw),
                 A * ((A + 1) + (A - 1) * cw - sa)]
            a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
        else:
            b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw),
                 A * ((A + 1) - (A - 1) * cw - sa)]
            a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa]
    return [b[0] / a[0], b[1] / a[0], b[2] / a[0], a[1] / a[0], a[2] / a[0]]


def band_share_db(vals, sr, kind, f0):
    """dB of `vals`' energy that lies above (kind "hp") or below ("lp") f0."""
    c = _rbj(kind, f0, sr)
    part = _biquad(_biquad(vals, *c), *c)
    total = sum(v * v for v in vals) or 1.0
    return 10 * math.log10(sum(v * v for v in part) / total + 1e-12)


def tone_match(vals, sr=SR):
    """Float samples -> the same take pulled toward the library's tonal balance."""
    cut_left, boost_left = AIR_MAX_CUT, LOW_MAX_BOOST
    if band_share_db(vals, sr, "lp", LOW_HZ) < LOW_FLOOR_DB:
        boost_left = 0.0
    for _ in range(3):   # a shelf moves its band only part-way; re-measure and go again
        cut = min(cut_left, max(0.0, band_share_db(vals, sr, "hp", AIR_HZ) - AIR_TARGET_DB))
        boost = min(boost_left, max(0.0, LOW_TARGET_DB - band_share_db(vals, sr, "lp", LOW_HZ)))
        if cut < 1.5 and boost < 1.5:
            break
        if cut >= 1.5:
            vals = _biquad(vals, *_rbj("high", AIR_HZ, sr, -cut))
            cut_left -= cut
        if boost >= 1.5:
            vals = _biquad(vals, *_rbj("low", LOW_HZ * 1.25, sr, boost))
            boost_left -= boost
    return vals


def retone(pcm):
    """16-bit mono PCM -> tone_match()ed 16-bit mono PCM, rescaled only if it
    would clip; trim_and_normalize() sets the final level after this."""
    vals = tone_match(list(struct.unpack("<%dh" % (len(pcm) // 2), pcm)))
    peak = max(abs(v) for v in vals) or 1.0
    k = min(1.0, 32767.0 / peak)
    return struct.pack("<%dh" % len(vals), *(int(round(v * k)) for v in vals))


def head_fade(vals, fade_ms=HEAD_FADE_MS):
    """Ramp the first `fade_ms` in, in place. Linear: at 4 ms nothing shapes the
    attack, it only takes the step out of it."""
    fade = min(len(vals), max(1, int(SR * fade_ms / 1000.0)))
    for i in range(fade):
        vals[i] = int(round(vals[i] * (i + 1) / float(fade)))
    return vals


def cap(pcm, seconds, fade_ms=BARK_FADE_MS):
    """Cut `pcm` to at most `seconds` and fade its last `fade_ms` out.

    The cut is a no-op for anything already short enough; the fade is not, and
    both are the point. Runs after trim_and_normalize, so the sound starts at
    sample 0 and a cut lands on the sound rather than on the silence in front of
    it.
    """
    n = len(pcm) // 2
    keep = min(n, int(SR * seconds))
    if keep <= 0:
        return pcm, n / float(SR)
    vals = list(struct.unpack("<%dh" % n, pcm))[:keep]
    fade = min(keep, max(1, int(SR * fade_ms / 1000.0)))
    for i in range(fade):
        g = 1.0 - (i + 1) / float(fade)
        vals[keep - fade + i] = int(round(vals[keep - fade + i] * g * g))
    return struct.pack("<%dh" % len(vals), *vals), keep / float(SR)


def wav(pcm):
    """16-bit mono PCM bytes -> a complete RIFF/WAVE file."""
    block_align = CHANNELS * 2
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, CHANNELS,
                      SR, SR * block_align, block_align, 16)
    data = struct.pack("<4sI", b"data", len(pcm)) + pcm
    body = b"WAVE" + fmt + data
    return struct.pack("<4sI", b"RIFF", len(body)) + body


def generate(key, prompt, seconds, influence, timeout=180, loop=False):
    """One call. Returns raw 16-bit PCM at SR, or raises. `loop` asks the model
    for a take that loops smoothly -- tools/gen_music_elevenlabs.py's beds."""
    body = json.dumps({
        "text": prompt,
        "duration_seconds": round(max(MIN_SECONDS, min(MAX_SECONDS, seconds)), 2),
        "prompt_influence": influence,
        "loop": loop,
    }).encode()
    req = urllib.request.Request(
        "%s?output_format=%s" % (API_URL, OUTPUT_FORMAT),
        data=body,
        headers={"xi-api-key": key, "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        raise SystemExit("ElevenLabs %s for this prompt: %s" % (e.code, detail))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="*", default=None,
                    help="sfx and/or barks (default: sfx)")
    ap.add_argument("--only", default="",
                    help="comma-separated sound names, e.g. hit,crit,click")
    ap.add_argument("--list", action="store_true",
                    help="print what would be generated and exit")
    ap.add_argument("--dry-run", action="store_true",
                    help="do everything but the API call and the write")
    ap.add_argument("--take", type=int, default=0,
                    help="write name_<N>.wav, an extra take the game round-robins (N >= 2)")
    ap.add_argument("--retone", action="store_true",
                    help="no API call: run tone_match over the sfx files already on disk "
                         "(the ones --only/--take name) and rewrite them in place")
    args = ap.parse_args()

    groups = args.groups or ["sfx"]
    bad = set(groups) - {"sfx", "barks"}
    if bad:
        sys.exit("unknown group(s): %s (want sfx and/or barks)" % ", ".join(sorted(bad)))

    todo = jobs(groups, args.only, args.take)
    if not todo:
        sys.exit("nothing to do")

    if args.list:
        for group, name, path, prompt, secs, infl in todo:
            asked = max(MIN_SECONDS, min(MAX_SECONDS, secs))
            note = "" if asked == secs else "  (floored from %.1fs)" % secs
            print("%-10s %-10s %4.1fs  infl %.2f  %s%s" % (group, name, asked, infl, prompt, note))
        print("\n%d generation(s)." % len(todo))
        return

    if args.retone:
        for group, name, path, prompt, secs, infl in todo:
            if group != "sfx" or not os.path.exists(path):
                continue
            with open(path, "rb") as f:
                raw = f.read()
            ch, rate, bits = struct.unpack_from("<HIxxxxxxH", raw, 22)
            if (ch, rate, bits) != (CHANNELS, SR, 16):
                print("%-10s %-14s skipped: %d ch %d Hz %d-bit is not this tool's output" % (group, name, ch, rate, bits))
                continue
            pcm = raw[44:]
            vals = list(struct.unpack("<%dh" % (len(pcm) // 2), pcm))
            before = (band_share_db(vals, SR, "hp", AIR_HZ), band_share_db(vals, SR, "lp", LOW_HZ))
            pcm, _, now, _ = trim_and_normalize(retone(pcm))
            vals = list(struct.unpack("<%dh" % (len(pcm) // 2), pcm))
            with open(path, "wb") as f:
                f.write(wav(pcm))
            print("%-10s %-14s air %6.1f -> %6.1f dB   low %6.1f -> %6.1f dB" % (
                group, os.path.basename(path)[:-4], before[0], band_share_db(vals, SR, "hp", AIR_HZ),
                before[1], band_share_db(vals, SR, "lp", LOW_HZ)))
        return

    key = os.environ.get(KEY_ENV, "")
    if not key and not args.dry_run:
        sys.exit("%s is not set. Get a key from elevenlabs.io and export it, or "
                 "pass --dry-run to check the plan without calling out." % KEY_ENV)

    for group, name, path, prompt, secs, infl in todo:
        print("%-10s %-10s %4.1fs ... " % (group, name, secs), end="", flush=True)
        if args.dry_run:
            print("(dry run)")
            continue
        pcm = generate(key, prompt, secs, infl)
        if group == "sfx" and len(pcm) >= 2:
            pcm = retone(pcm)
        pcm, was, now, peak = trim_and_normalize(pcm)
        if group == "barks":
            pcm, now = cap(pcm, BARK_MAX_SECONDS)
        else:
            pcm, now = cap(pcm, SFX_MAX_SECONDS, SFX_FADE_MS)
            # the part-aware trim tools/trim_sfx.py gives every sfx one-shot
            vals = trim_sfx.trim(list(struct.unpack("<%dh" % (len(pcm) // 2), pcm)), CHANNELS, SR)
            pcm, now = struct.pack("<%dh" % len(vals), *vals), len(vals) / float(SR)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(wav(pcm))
        note = ("  ** silent take, re-run this one **"
                if peak < SILENCE_RMS * 32767.0 else "")
        print("%s  %.2fs (from %.2fs, peak %d -> %d)%s"
              % (os.path.relpath(path, ROOT), now, was, peak, PEAK, note))

    if not args.dry_run:
        print("\nListen to them before committing — a take can miss, and this is not\n"
              "deterministic, so re-running is a different take rather than the same one.\n"
              "tools/gen_audio.py rewrites any of these back to the synthesized version.")


if __name__ == "__main__":
    main()

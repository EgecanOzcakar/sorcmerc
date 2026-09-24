#!/usr/bin/env python3
"""Rebuild assets/audio/sfx/licensed/ from your own copy of the Sonniss GDC bundles.

    python3 tools/import_licensed_sfx.py --bundles ~/Sonniss          # every sfx below
    python3 tools/import_licensed_sfx.py --bundles ~/Sonniss miss buy # just these
    python3 tools/import_licensed_sfx.py --bundles ~/Sonniss --check  # find the files, write nothing

Why the output is not in git: these are real recordings the user picked by ear
over the ElevenLabs takes (the generated ones kept a hiss, an ~11 kHz notch and
fizz above 15 kHz whatever the prompt said). They come from the free Sonniss
#GameAudioGDC bundles, whose license (v2.0, https://sonniss.com/gdc-bundle-license/)
lets them ship inside the game royalty-free with no credit, but forbids handing
them out as sound files -- "re-designed and manipulated sounds remain licensed
material" -- and forbids using them to develop, train or enhance AI. This repo
is public, so the processed files live in the gitignored licensed/ folder and
only this recipe is committed. core/audio.gd plays licensed/<id>.wav in place of
assets/audio/sfx/<id>.wav (and all its takes) when it exists, so a clone without
the bundles still plays the generated sounds. Do not feed these files, or
anything made from them, to a generator.

Where the output goes: the private EgecanOzcakar/sorcmerc-licensed-audio holds
it, and tools/fetch_licensed_sfx.sh (the git hooks) and the release workflow
check that out into licensed/. After a rebuild, commit and push licensed/ there.

Download the bundles from sonniss.com/gameaudiogdc (free) and point --bundles at
wherever you unpacked them; any layout works, files are found by pack folder and
name, and a .flac of the same name counts.

Each sfx is decoded to 48 kHz stereo; a long recording is cut to the window the
user auditioned; a take panned hard to one side is folded to mono; it is
peak-normalised to tools/gen_audio_elevenlabs.py's PEAK, trimmed by
tools/trim_sfx.py and capped at the generator's 4.5 s, and a take that still
sounds at its end is faded (tools/check_audio.py fails an abrupt ending).
"""
import argparse
import array
import math
import os
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trim_sfx

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "licensed")
RATE, CH = 48000, 2
PEAK = 28480           # tools/gen_audio_elevenlabs.py's normalisation target
MAX_SECONDS = 4.5      # its SFX_MAX_SECONDS
CAP_FADE, END_FADE = 0.3, 0.15
LOUD_END = 0.02        # rms of the last 50 ms, full scale 1.0, that needs END_FADE
MONO_BELOW = 0.3       # quieter channel's peak under this share of the louder: fold to mono

# id -> (GDC bundle year, pack folder, file, (start s, length s) auditioned, or None for the whole file)
SOURCES = {
    'blessing': (2020, 'Bluezone - Heaven - Ethereal Ambient Samples',
        'Bluezone_BC0270_heaven_synth_texture_melodic_phrase_soft_01_03.wav', (1.2, 8.0)),
    'burst': (2017, 'Gamemaster Audio -  Explosion Sound Pack',
        'explosion_large_no_tail_03.wav', None),
    'buy': (2017, 'Hzandbits - Money',
        'Money,Coins,Handle.wav', None),
    'cache_open': (2017, 'Resonance Sound Design - ASSORTED FOLEY ELEMENTS',
        'DOORS_MISC_CUPBOARD_OPEN_AND_CLOSE_CREAK_2.wav', (0.0, 2.0)),
    'captive_freed': (2023, 'InspectorJ - Essentials 04 Chains',
        'CHAINImpt_InsJ_Chains_Metal_Dropping_Close_01-03.wav', None),
    'cast': (2023, 'CB Sound Design - Whoosh And Push',
        'W_a_P_Spell_Whoosh_19.wav', None),
    'cast_abjuration': (2020, 'David Dumais Audio - Spells Magic 1',
        'Magic_Spells_Impact_Creation20.wav', None),
    'cast_conjuration': (2018, 'Gamemaster Audio - Magic and Spell Sounds',
        'dark_portal_wind_effect_04.wav', None),
    'cast_enchantment': (2026, 'CB_Sounddesign - Applicable Sounds - Organic UI and Building Games SFX',
        'GAMEMisc_Magic Creation 23_CB Sounddesign_APPlicable Sounds.wav', None),
    'cast_evocation': (2020, 'SmartSoundFX – Medieval',
        'WHOOSH Ball Crackle Small 02.wav', None),
    'cast_illusion': (2020, 'David Dumais Audio - Air Magic 1',
        'Magic_Spells_CastShort_Air_Whistling04.wav', None),
    'cast_necromancy': (2019, 'Sound Spark LLC – Magic Spells, Buffs and Attacks',
        'Dark_Spell_Life_Tap_03.wav', None),
    'cast_transmutation': (2019, 'Articulated Sounds - Magic Elements vol.1',
        'MAGIC ICE Whoosh, Ice Bloc, Debris 01.wav', None),
    'collapse': (2020, 'SmartSoundFX – Medieval',
        'ARMOR Body Drop Chain Leather Short 02.wav', None),
    'condition': (2023, 'Rogue Waves - Druid Magic',
        'MAGEvil_Dark Spell Dark Energy Attack_RogueWaves_DruidMagic.wav', None),
    'defeat': (2020, 'Sound Spark LLC - Metal Souls',
        'Metal_Souls_Stinger_Echos_of_Time_05.wav', None),
    'down': (2019, 'Red Libraries - Bodyfall',
        'RL_bodyfall_Dirt_M4_Close_Stereo_Hard_Impact_10.wav', None),
    'heal': (2026, 'Epic Stock Media - Fantasy Game 2 - Sound Kit for Enchanted Realms',
        'MAGAngl_Magic Light Spell Enchantment Potion Effect Tonal Bright 03_ESM_FG2.wav', None),
    'identify': (2019, 'Eiravaein Works - Helina',
        'Helinä,windchimes,mixed,paper,aluminum,tuned,glassclappermini,windcatcher,cottonrope,release,gentle,lingering,MidSide.wav', None),
    'lair_dug': (2019, 'Matt Script - You Me & Debris',
        'impact_gritty_grit_sandy_dirt_dig_shovel_shingle_roof_02.wav', None),
    'landmark_found': (2024, 'Orbital Emitter - Cinematic Transitions for Editors Volume 2',
        '80,TheGong.wav', None),
    'lead_marked': (2017, 'SoundBits - Handwriting Sound Effects',
        'Handwriting_FountainPen_023.wav', None),
    'level_up': (2019, 'The Chris Alan - Gliss Bliss',
        'Bell Guitar Gliss Up 01.wav', None),
    'map_reveal': (2026, 'Cinematic Sound Design - Paper Foley',
        'Newspaper Static Foley Rummage.wav', None),
    'miss': (2016, 'SoundBits -  Just Whoosh 3 _ Whoosh Essentials',
        'Whoosh_Rod_Pole_022.wav', None),
    'offering': (2020, 'PMSFX - Rocky Impacts',
        'PM_RI_Source_53 Rocks Impact Hit Single Stone.wav', None),
    'pickup': (2026, 'Epic Stock Media - Fantasy Game 2 - Sound Kit for Enchanted Realms',
        'CLOTHFlp_Action Inventory Open Flip Cloth Canvas Bag Slide Light 02_ESM_FG2.wav', None),
    'quarry_gone': (2017, 'G4F SFX - Horses',
        'G4F SFX06 - HORSES - Galloping outside in sand.wav', (4.9, 8.0)),
    'quest': (2020, 'SpillAudio - Paper',
        'newspaper_opening_009.wav', None),
    'quest_complete': (2015, 'Eiravaein Works - Start Select',
        'StartSelect,UI,set1,strings,ethnic,tonal,plucked,aura,hold_release.wav', None),
    'raid_bell': (2023, 'Justsoundeffects - Urban Ambiences',
        'AMBRlgn_Church Bells Ringing Village_JSE_UAG.wav', (6.1, 8.0)),
    'raid_drums': (2019, 'Baxter Audio - IMPACT',
        '03 Hit Big Drum.wav', None),
    'raid_horn': (2026, 'Jake Fielding - Cinematic Horn Braams',
        'DSGNBram____Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32.wav', (5.6, 8.0)),
    'raid_lifted': (2015, 'Coll Anderson - Battle Crowd',
        'EFX EXT GROUP Battle Celebration 02 A.wav', (0.0, 8.0)),
    'rest': (2026, 'Ivo Vicic - Campfire - Bonfire FX',
        '24 Campfire, Dropping Fresh Pine Branches in Fire, Crackling, Sizzling Strong, Close 02.wav', (76.7, 8.0)),
    'rumour_bought': (2023, 'CB Sound Design - Essential Sounds Vol.01 Coins',
        'handling_coins_7.wav', None),
    'save_failed': (2020, 'SmartSoundFX - Impacts, Hits & Whooshes',
        'IMPACT DARK Epic Punch_01.wav', None),
    'save_made': (2020, 'David Dumais Audio - Ice & Frost Magic 1',
        'Magic_Spells_Impact_Ice13.wav', None),
    'search_found': (2023, 'Eneas Mentzel - Debris & Rubble',
        'DESTRCrsh_rummaging through compact wood dry branches_Eneas Mentzel_Debris & Rubble_14.wav', None),
    'search_nothing': (2019, 'BlueZone - Wood Sound Effects',
        'Bluezone_BC0254_wood_crushing_branches_001_001.wav', None),
    'settle': (2015, 'Soundopolis - Tools:Construction 01',
        'Hammer_Multiple_Exterior_Fienup_013.wav', None),
    'settlement': (2017, 'SoundMorph - Portals',
        'Door - Medieval Open 16.wav', None),
    'shop': (2024, 'Mechanical Wave - Sound Effects Collection',
        'BELLHand_Metallic Bell_ 22_MWSFX_SEC.wav', None),
    'travel': (2019, 'PMSFX - STEPS Dirt & Gravel',
        'PM_SDNG_Stereo_Walk_Seamless_Loop_1.wav', (14.6, 8.0)),
    'victory': (2018, 'Sounds Visual - 50 Flat Design Sound Effects',
        '33 FX3184 Ascending Harp Glissando.wav', None),
}


def index(root):
    """(pack folder, name without extension) -> path, for every wav/flac under root."""
    found = {}
    for d, _, files in os.walk(os.path.expanduser(root)):
        for f in files:
            stem, ext = os.path.splitext(f)
            if ext.lower() in (".wav", ".flac"):
                key = (os.path.basename(d).strip(), stem)
                if key not in found or ext.lower() == ".wav":
                    found[key] = os.path.join(d, f)
    return found


def build(src, window):
    cmd = ["ffmpeg", "-loglevel", "error"]
    if window:
        cmd += ["-ss", str(window[0]), "-t", str(window[1])]
    raw = subprocess.run(cmd + ["-i", src, "-ac", str(CH), "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = array.array("f", raw)
    if sys.byteorder == "big":
        x.byteswap()
    peaks = [max(abs(v) for v in x[c::CH]) for c in range(CH)]
    if min(peaks) < MONO_BELOW * max(peaks):
        for i in range(0, len(x), CH):
            m = sum(x[i:i + CH]) / CH
            for c in range(CH):
                x[i + c] = m
    top = max(abs(v) for v in x) or 1.0
    s = trim_sfx.trim(array.array("h", (int(round(v / top * PEAK)) for v in x)), CH, RATE)
    frames = min(len(s) // CH, int(RATE * MAX_SECONDS))
    s = s[:frames * CH]
    tail = s[-int(RATE * 0.05) * CH:]
    if frames == int(RATE * MAX_SECONDS) or math.sqrt(sum(v * v for v in tail) / len(tail)) / 32768 > LOUD_END:
        n = min(frames, int(RATE * (CAP_FADE if frames == int(RATE * MAX_SECONDS) else END_FADE)))
        for i in range(n):
            g = (1 - (i + 1) / n) ** 2
            for c in range(CH):
                j = (frames - n + i) * CH + c
                s[j] = int(round(s[j] * g))
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="sfx ids (default: all)")
    ap.add_argument("--bundles", required=True, help="where the Sonniss GDC bundles are unpacked")
    ap.add_argument("--check", action="store_true", help="only report which source files are found")
    args = ap.parse_args()
    ids = args.ids or sorted(SOURCES)
    unknown = [i for i in ids if i not in SOURCES]
    if unknown:
        sys.exit("not licensed sfx: %s" % ", ".join(unknown))
    found = index(args.bundles)
    missing = 0
    os.makedirs(OUT, exist_ok=True)
    for sid in ids:
        year, pack, name, window = SOURCES[sid]
        src = found.get((pack, os.path.splitext(name)[0]))
        if not src:
            missing += 1
            print("%-19s MISSING  GDC %d / %s / %s" % (sid, year, pack, name))
            continue
        if args.check:
            print("%-19s found    %s" % (sid, src))
            continue
        s = build(src, window)
        if sys.byteorder == "big":
            s.byteswap()
        with wave.open(os.path.join(OUT, sid + ".wav"), "wb") as w:
            w.setnchannels(CH)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(s.tobytes())
        print("%-19s %.2fs  %s" % (sid, len(s) / CH / RATE, pack))
    if missing:
        sys.exit("%d of %d not found under %s" % (missing, len(ids), args.bundles))


if __name__ == "__main__":
    main()

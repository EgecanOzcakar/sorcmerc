#!/usr/bin/env python3
"""ElevenLabs sound effects for sorcmerc, as an alternative to tools/gen_audio.py.

    export ELEVENLABS_API_KEY=...
    python3 tools/gen_audio_elevenlabs.py --list          # the prompts, writes nothing
    python3 tools/gen_audio_elevenlabs.py sfx             # regenerate all 14 stings
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
14 of them for `sfx`, so --only is the normal way to use it.
"""
import argparse
import json
import os
import struct
import sys
import urllib.error
import urllib.request

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

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)

# name -> (prompt, seconds, prompt_influence)
#
# The prompts describe the SOUND, not the game event: "a sword hitting mail" is
# something a model has heard, "hit.wav" is not. Lengths match what the game
# gives each sting room for -- core/audio.gd fires these as one-shots over
# combat, so anything past about a second is still playing when the next thing
# happens.
SFX = {
    "hit": ("A single heavy sword strike landing on chain mail armor, sharp metallic "
            "impact with a short dull thud underneath, dry, no reverb tail", 0.7, 0.7),
    "crit": ("A devastating critical sword strike, metal shearing through armor and bone, "
             "sharp crack with a deep impact underneath, brief and brutal", 0.9, 0.65),
    "kill": ("A body collapsing to a stone floor in armor, heavy final thud with "
             "scattered metal rattle", 1.0, 0.6),
    "cast": ("A magic spell being cast, rising shimmering energy with a soft bright "
             "release at the end, fantasy game spell sound", 1.1, 0.5),
    "heal": ("A gentle healing magic chime, warm soft bells rising, brief and comforting, "
             "fantasy game heal sound", 1.2, 0.5),
    "level_up": ("A triumphant short fanfare for leveling up, bright ascending chime with "
                 "a warm resonant finish, fantasy RPG", 1.6, 0.45),
    "victory": ("A short triumphant brass and drum victory fanfare, heroic, medieval "
                "fantasy, ending cleanly", 2.5, 0.4),
    "defeat": ("A grim descending tone marking defeat, low strings and a distant drum, "
               "hollow and final", 2.5, 0.4),
    "click": ("A single crisp UI button click, small wooden tick, very short, dry", 0.3, 0.9),
    "buy": ("Coins being counted onto a wooden merchant counter, a few gold pieces, "
            "short and bright", 0.8, 0.75),
    "identify": ("A soft magical reveal, shimmering chime resolving into a clear tone, "
                 "the sound of a mystery being solved", 1.2, 0.5),
    "quest": ("A short parchment unfurling with a soft horn note, the sound of accepting "
              "a quest, medieval fantasy", 1.2, 0.5),
    "pickup": ("Picking up an item, a small leather and metal rustle with a soft bright "
               "tick, very short", 0.5, 0.8),
    "rest": ("A campfire settling with a soft exhale and a gentle low drone, the sound of "
             "making camp, warm and calm", 2.0, 0.45),

    # T9z: per-weapon-class hits. core/weapon_sfx.gd picks one off the attacker's
    # main-hand weapon (or a monster's damage type), so a bow and a mace stop
    # sounding the same. Each is the SWING through the air and then the landing.
    "hit_sword": ("A sword swung through the air then striking chain mail, quick whoosh "
                  "into a sharp bright metallic clang with a ring, dry, close", 0.7, 0.7),
    "hit_axe": ("A heavy battle axe swung and chopping into armor and shield, a whoosh into "
                "a deep heavy thunk with a short dull metallic bite, dry", 0.7, 0.7),
    "hit_blunt": ("A heavy mace or war hammer swung and slamming into armor, a deep dull "
                  "crushing thud with a low metallic clank, no ring, dry", 0.7, 0.7),
    "hit_pierce": ("A dagger or spear thrust quickly stabbing through leather and mail, a "
                   "short sharp metallic shink and a quick puncture, very brief, dry", 0.5, 0.75),
    "hit_bow": ("A bowstring released with a taut twang, an arrow whistling through the air, "
                "then thudding into a wooden shield, dry", 0.9, 0.7),
    "hit_thrown": ("A javelin or throwing axe whooshing through the air then striking a "
                   "target with a solid thunk, dry", 0.8, 0.7),
    "hit_claw": ("A large beast's claws raking and tearing through leather armor, a quick "
                 "triple scratch and rip, no metal, dry", 0.6, 0.7),
    "hit_bite": ("A large creature's jaws snapping shut and crunching down on armor and "
                 "flesh, a sharp snap into a wet crunch, brief, dry", 0.6, 0.7),
    "hit_slam": ("A huge creature's fist slamming down onto a warrior, a heavy deep body "
                 "blow with a low thump and armor rattle, dry", 0.8, 0.7),

    # T9z: per-school casts. Picked off data/spells.json's `school`. Same wide,
    # magical space as the generic cast; what differs is the character of it.
    "cast_evocation": ("A destructive evocation spell being cast, a rising surge of raw "
                       "energy erupting into a fiery crackling boom, fantasy game magic", 1.2, 0.55),
    "cast_abjuration": ("A protective ward spell being cast, a bright clear chime blooming "
                        "into a steady shimmering barrier hum, fantasy game magic", 1.2, 0.5),
    "cast_conjuration": ("A summoning spell being cast, a swirling portal opening with a "
                         "whooshing rush of air and a deep arrival thump, fantasy game magic", 1.2, 0.5),
    "cast_enchantment": ("A charm spell being cast, a soft dreamy descending twinkle of "
                         "bells with a hypnotic sparkle, fantasy game magic", 1.2, 0.5),
    "cast_transmutation": ("A transmutation spell reshaping matter, a warbling wobbling "
                           "tone with bubbling shifting textures settling into a chime, "
                           "fantasy game magic", 1.2, 0.5),
    "cast_divination": ("A divination spell revealing a vision, an ascending crystalline "
                        "cluster of bells with an airy ethereal shimmer, fantasy game magic", 1.3, 0.5),
    "cast_illusion": ("An illusion spell being cast, a phasing wavering unreal shimmer with "
                      "a ghostly whisper and an off-key glint, fantasy game magic", 1.2, 0.5),
    "cast_necromancy": ("A necromancy death spell being cast, a low ominous droning bend "
                        "downward with a rasping breath and a hollow wrong note, dark "
                        "fantasy game magic", 1.3, 0.5),
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


def jobs(groups, only):
    """(group, name, out_path, prompt, seconds, influence) for everything asked for."""
    out = []
    if "sfx" in groups:
        for name, (prompt, secs, infl) in SFX.items():
            out.append(("sfx", name,
                        os.path.join(ROOT, "assets", "audio", "sfx", name + ".wav"),
                        prompt, secs, infl))
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

    gain = PEAK / float(peak)
    vals = [max(-32768, min(32767, int(round(v * gain)))) for v in vals]
    return (struct.pack("<%dh" % len(vals), *vals),
            before, len(vals) / float(SR), peak)


def wav(pcm):
    """16-bit mono PCM bytes -> a complete RIFF/WAVE file."""
    block_align = CHANNELS * 2
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, CHANNELS,
                      SR, SR * block_align, block_align, 16)
    data = struct.pack("<4sI", b"data", len(pcm)) + pcm
    body = b"WAVE" + fmt + data
    return struct.pack("<4sI", b"RIFF", len(body)) + body


def generate(key, prompt, seconds, influence, timeout=180):
    """One call. Returns raw 16-bit PCM at SR, or raises."""
    body = json.dumps({
        "text": prompt,
        "duration_seconds": round(max(MIN_SECONDS, min(MAX_SECONDS, seconds)), 2),
        "prompt_influence": influence,
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
    args = ap.parse_args()

    groups = args.groups or ["sfx"]
    bad = set(groups) - {"sfx", "barks"}
    if bad:
        sys.exit("unknown group(s): %s (want sfx and/or barks)" % ", ".join(sorted(bad)))

    todo = jobs(groups, args.only)
    if not todo:
        sys.exit("nothing to do")

    if args.list:
        for group, name, path, prompt, secs, infl in todo:
            asked = max(MIN_SECONDS, min(MAX_SECONDS, secs))
            note = "" if asked == secs else "  (floored from %.1fs)" % secs
            print("%-10s %-10s %4.1fs  infl %.2f  %s%s" % (group, name, asked, infl, prompt, note))
        print("\n%d generation(s)." % len(todo))
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
        pcm, was, now, peak = trim_and_normalize(pcm)
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

#!/usr/bin/env python3
"""ElevenLabs music for sorcmerc: the ambient beds and the short musical stings.

    export ELEVENLABS_API_KEY=...
    python3 tools/gen_music_elevenlabs.py --list                  # the prompts, writes nothing
    python3 tools/gen_music_elevenlabs.py beds --only deeps,marches
    python3 tools/gen_music_elevenlabs.py stings --only music_discovery
    python3 tools/gen_music_elevenlabs.py beds stings             # everything (18 calls)

The sibling of tools/gen_audio_elevenlabs.py for the other half of
assets/audio/: that file writes one-shots off the sound-effects model, this
one writes music off the Music API (POST /v1/music), which is a different
model with a different shape of request -- a length in milliseconds, no
prompt_influence, and MP3 back rather than PCM. The beds it writes are the
same file names tools/gen_audio.py's recipes wrote (one per Encounter.THEMES,
settlement, tension, and the four D6 countries), so core/audio.gd neither
knows nor cares which tool made the one it is looping. title.wav is NOT in
the table: it is a hand-placed track (0a1f436), not either tool's to rewrite.

Two groups, two post-passes:

  beds     assets/audio/music/<name>.wav, BED_SECONDS long, stereo, and made
           to LOOP: the API has no loop flag, so the last XF seconds are
           crossfaded into the first and the file cut by XF, the same fold
           tools/synth.py's wrap_tail does for the synthesized beds. The
           tension layer plays OVER a theme bed (core/audio.gd), so its
           prompt asks for percussion and one note and no chord changes.
  stings   assets/audio/sfx/music_<name>.wav, a few seconds each, played as
           one-shots by Sound.play_sting -- the Music bus, no pitch drift.
           Trimmed, faded out over STING_FADE_MS, and peak-matched to the
           sfx tool's 28480 so they sit at the level of the stings around them.

Both come back as mp3_44100_192 (the PCM formats are mono, and a bed wants
its width) and go through ffmpeg to 16-bit stereo PCM. Not deterministic; the
WAVs are committed, and --only is how this is run. Cost is per second of
music, and a bed is fifty of them, so `beds` is not a thing to run twice.

--engine sfx is the other road to the same files: the Music API is a paid-plan
feature (a free account gets a 402, paid_plan_required), and the sound-effects
model tools/gen_audio_elevenlabs.py already uses is not -- and it takes a
`loop` flag and up to thirty seconds. So a bed through it is a 30 s looping
ambience rather than a 50 s piece, mono like every other take, and the same
prompt read by a model that knows rooms better than it knows chord
progressions. Every bed in assets/audio/music/ today came this way; the day
the account can compose, `beds` with the default engine writes the same names.
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import urllib.error
import urllib.request

API_URL = "https://api.elevenlabs.io/v1/music"
OUTPUT_FORMAT = "mp3_44100_192"
KEY_ENV = "ELEVENLABS_API_KEY"
SR = 44100
CHANNELS = 2
MIN_MS = 3000               # the API's floor
MAX_MS = 600000

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)

BED_SECONDS = 50            # asked for; the loop is this minus XF
SFX_BED_SECONDS = 30        # the sound-effects model's ceiling, --engine sfx
SFX_BED_INFLUENCE = 0.4     # room for the model: an ambience that drifts is fine
SFX_STING_INFLUENCE = 0.45
XF = 2.0                    # seconds of tail folded into the head at the seam
BED_PEAK = 0.89             # tools/synth.py write_wav's target, so the beds match
STING_PEAK = 28480 / 32768.0   # tools/gen_audio_elevenlabs.py's PEAK
STING_FADE_MS = 400
# The sound-effects model pads a short ask: asked for a 6 s phrase it returns
# twelve seconds -- the phrase, half a second of nothing, and the phrase again,
# differently. A sting is one phrase. Split at every gap this long and keep
# the phrase with the most energy -- loudness times length, so a developed
# second phrase beats a single opening hit.
PHRASE_GAP_MS = 500
PHRASE_LEAD_MS = 20
PHRASE_TAIL_MS = 250
SILENCE = 0.004             # the sfx tool's floor, judged over 10 ms windows
WINDOW_MS = 10
# ...but music is wet: a phrase's reverb sits at -40 dB for seconds after it
# is over, well above the dry floor, so silence is judged relative to the
# take's own loudest window as well -- under this share of it (-24 dB) is over.
REL_SILENCE = 0.06
HEAD_FADE_MS = 4            # the sfx tool's rule: never start on a step

# name -> prompt. Written from tools/gen_audio.py's recipes: the key, the
# instruments and the texture each bed was synthesized with are what the
# prompt asks for, so the mood survives the change of tool. "Instrumental,
# no vocals, loops seamlessly" is on every one; force_instrumental is set
# too, since the model otherwise reserves the right to sing.
LOOP = " Instrumental, no vocals, steady dynamics throughout so it loops seamlessly."
BEDS = {
    # Encounter.THEMES — the fight backdrops
    "sunken-shrine": ("Dark ambient for a drowned temple: slow wet cavernous pads in D minor "
                      "drifting to B flat, a far-off temple bell, water dripping and echoing "
                      "off stone, a low wind, no drums, no melody, very slow." + LOOP),
    "goblin-camp": ("A scrappy goblin camp at night: crude hand drums and rattles at a loping "
                    "tempo in E minor, a crude reed pipe playing a simple off-kilter tune, "
                    "rough, mischievous, dark fantasy, no orchestra." + LOOP),
    "city-square": ("A medieval market square at midday: a lute arpeggio over a warm "
                    "progression in C major, a hand drum, a fiddle answering, lively but "
                    "unhurried, folk." + LOOP),
    "forest-clearing": ("A forest clearing: soft harp arpeggios high up over warm pads in G, "
                        "a wooden flute, birdsong and a light breeze through leaves, calm and "
                        "green, slow, fantasy." + LOOP),
    "frozen-cave": ("A frozen cave: vast still pads in B minor, glassy ice bells struck far "
                    "apart, a cold wind through stone, glacial and slow, no drums, dark "
                    "ambient." + LOOP),
    "merchant-shop": ("A small medieval shop: a cheerful lute picking a light tune in F over "
                      "soft strings, a gentle shop bell now and then, cosy, warm, quiet." + LOOP),
    # O-biome's two boards. Both are OPEN COUNTRY, which is what keeps them
    # apart from forest-clearing above: no canopy, so no close birdsong and no
    # enclosed reverb — wind with distance in it, and the ground's own sound.
    "downs": ("Open moorland under a wide sky: a low drone in D with a slow wooden flute "
              "over it, steady wind across grass, a distant curlew, spare and unhurried, "
              "nothing enclosed, no drums." + LOOP),
    "marsh": ("A cold reed marsh: damp low pads in A minor, reeds hissing in a slow wind, "
              "water lapping and the occasional deep frog, a far-off wading bird, still "
              "and uneasy, no melody, no drums." + LOOP),
    # between fights, and the map inside a town
    "settlement": ("A small medieval town at evening: warm plucked lute and gentle strings "
                   "over a homely progression in C, a hurdy-gurdy drone underneath, peaceful "
                   "and settled." + LOOP),
    # the combat layer — plays OVER any of the above, so no key of its own
    # "driving" alone came back as a few hits and silence; the density has
    # to be asked for in so many words.
    "tension": ("A relentless combat drum loop: continuous driving war drums and taiko at "
                "a steady fast tempo with no pauses, a low pulsing string ostinato on one "
                "note underneath, tense rhythmic stabs, no melody, no chord changes, dense "
                "from start to finish, dark fantasy battle." + LOOP),
    # the four D6 countries (core/regions.gd). A gradient, not four moods: the
    # root walks down G -> F -> D -> low G as the country gets older and
    # emptier, the tremolo climbs through the settled bands and drops to
    # stillness in the deeps, where the stillness is the threat.
    "heartland": ("The settled heartland: gentle pastoral strings in G major, a soft flute "
                  "over open fifths, a slow easy tremolo, warm and safe, the country everyone "
                  "knows, slow ambient." + LOOP),
    "marches": ("The marches at dusk: rougher pastoral music in F, low viols, a wary tremolo "
                "underneath, a lone horn far off, uneasy but still somebody's country, slow." + LOOP),
    "frontier": ("The frontier: sparse and windswept in D minor, a rough bowed drone, a "
                 "restless fast tremolo, a distant drum, cold and empty, nobody's country, "
                 "dark ambient." + LOOP),
    "deeps": ("The far deeps: a very low subterranean drone on G, almost still, a single far "
              "bell every so often, stone and cold air, oppressive and vast, dark ambient, no "
              "rhythm." + LOOP),
}

# name -> (prompt, seconds). One-shots: a phrase, not a piece, and each ends.
STINGS = {
    "music_discovery": ("Live orchestral recording of a short discovery phrase: a rising "
                        "harp glissando into a warm sustained string chord, a soft "
                        "celesta and small-bell melody on top. Real players in a concert "
                        "hall, a sense of wonder, slow, no synthesizer, no drums, no "
                        "vocals, ends cleanly on the held chord.", 6),
    "music_road": ("Live orchestral recording of a short vista phrase: French horns "
                   "swelling from soft to full over sustained strings, a broad hopeful "
                   "rising melody. Real players in a concert hall, wide and cinematic, "
                   "slow, no synthesizer, no vocals, ends cleanly on a sustained major "
                   "chord.", 8),
    "music_alarm": ("Live orchestral recording of a short alarm phrase: a hard low brass "
                    "and timpani hit, an urgent tolling tubular bell, tense fast staccato"
                    " strings driving underneath. Real players in a concert hall, no "
                    "synthesizer, no vocals, ends cleanly on a final brass hit.", 8),
    "music_relief": ("Live orchestral recording of a short relief phrase: a held tense "
                     "suspended string chord easing and resolving into a warm major "
                     "chord, soft strings and one gentle tubular bell. Real players in a "
                     "concert hall, slow, no synthesizer, no drums, no vocals, ends "
                     "cleanly.", 8),
    "music_founding": ("Live orchestral recording of a short founding phrase: a lone "
                       "French horn melody joined by warm strings and a slow proud "
                       "timpani beat, grounded and dignified. Real players in a concert "
                       "hall, no synthesizer, no vocals, ends cleanly on a sustained "
                       "chord.", 10),
    "music_deed": ("Live orchestral recording of a short job-done phrase: a brief "
                   "confident trumpet and horn phrase over a warm sustained string chord,"
                   " satisfied. Real players in a concert hall, no synthesizer, no "
                   "vocals, ends cleanly with a short hall ring-out.", 6),
}


def jobs(groups, only):
    """(group, name, out_path, prompt, seconds) for everything asked for."""
    out = []
    if "beds" in groups:
        for name, prompt in BEDS.items():
            out.append(("beds", name, os.path.join(ROOT, "assets", "audio", "music", name + ".wav"),
                        prompt, BED_SECONDS))
    if "stings" in groups:
        for name, (prompt, secs) in STINGS.items():
            out.append(("stings", name, os.path.join(ROOT, "assets", "audio", "sfx", name + ".wav"),
                        prompt, secs))
    if only:
        wanted = {s.strip() for s in only.split(",") if s.strip()}
        unknown = wanted - {j[1] for j in out}
        if unknown:
            sys.exit("no such piece(s): %s" % ", ".join(sorted(unknown)))
        out = [j for j in out if j[1] in wanted]
    return out


def generate(key, prompt, seconds, timeout=600):
    """One call. Returns the MP3 bytes, or raises."""
    body = json.dumps({
        "prompt": prompt,
        "music_length_ms": int(max(MIN_MS, min(MAX_MS, seconds * 1000))),
        "force_instrumental": True,
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
        if e.code == 402:
            detail += "\n(the Music API is a paid-plan feature; --engine sfx writes the same files " \
                      "off the sound-effects model instead)"
        raise SystemExit("ElevenLabs %s for this prompt: %s" % (e.code, detail))


def generate_sfx(key, prompt, seconds, loop):
    """The same piece off the sound-effects model: [mono] float list at SR."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gen_audio_elevenlabs as sfx
    pcm = sfx.generate(key, prompt, min(seconds, sfx.MAX_SECONDS),
                       SFX_BED_INFLUENCE if loop else SFX_STING_INFLUENCE, loop=loop)
    n = len(pcm) // 2
    return [[v / 32768.0 for v in struct.unpack("<%dh" % n, pcm)]]


def decode(mp3):
    """MP3 bytes -> [left, right] as float lists at SR, via ffmpeg."""
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le", "-ac",
                        str(CHANNELS), "-ar", str(SR), "pipe:1"],
                       input=mp3, capture_output=True, check=True)
    n = len(r.stdout) // 2
    vals = struct.unpack("<%dh" % n, r.stdout)
    return [[vals[i] / 32768.0 for i in range(c, n, CHANNELS)] for c in range(CHANNELS)]


def rms(chans, a, z):
    n = max(1, z - a)
    return (sum(v * v for b in chans for v in b[a:z]) / (n * len(chans))) ** 0.5


def levels_of(chans):
    """(per-10 ms-window RMS, the silence floor for this take)."""
    n = len(chans[0])
    win = max(1, int(SR * WINDOW_MS / 1000.0))
    levels = [rms(chans, i, i + win) for i in range(0, n, win)]
    return levels, max(SILENCE, REL_SILENCE * max(levels or [0.0]))


def trim(chans):
    """Drop the silence either end, by the sfx tool's rule (RMS over 10 ms windows)."""
    n = len(chans[0])
    win = max(1, int(SR * WINDOW_MS / 1000.0))
    levels, floor = levels_of(chans)
    live = [w for w, lv in enumerate(levels) if lv >= floor]
    if not live:
        return chans
    first = max(0, live[0] * win - int(SR * PHRASE_LEAD_MS / 1000.0))
    last = min(n, (live[-1] + 1) * win + int(SR * PHRASE_TAIL_MS / 1000.0))
    return [b[first:last] for b in chans]


def loudest_phrase(chans):
    """Keep one phrase of a take that came back as several: the one with the most in it."""
    n = len(chans[0])
    win = max(1, int(SR * WINDOW_MS / 1000.0))
    gap = max(1, int(PHRASE_GAP_MS / WINDOW_MS))
    levels, floor = levels_of(chans)
    phrases, cur, quiet = [], None, 0
    for w, lv in enumerate(levels):
        if lv >= floor:
            cur = [w, w] if cur is None else [cur[0], w]
            quiet = 0
        elif cur is not None:
            quiet += 1
            if quiet >= gap:
                phrases.append(cur)
                cur, quiet = None, 0
    if cur is not None:
        phrases.append(cur)
    if len(phrases) <= 1:
        return chans
    a, z = max(phrases, key=lambda p: sum(lv * lv for lv in levels[p[0]:p[1] + 1]))
    first = max(0, a * win - int(SR * PHRASE_LEAD_MS / 1000.0))
    last = min(n, (z + 1) * win + int(SR * PHRASE_TAIL_MS / 1000.0))
    return [b[first:last] for b in chans]


def normalize(chans, target):
    """Centre (a low drone came back riding 0.024 FS of DC; check_audio.py's
    line is 0.02) and peak-match."""
    means = [sum(b) / len(b) for b in chans]
    chans = [[v - m for v in b] for b, m in zip(chans, means)]
    peak = max(abs(v) for b in chans for v in b) or 1.0
    g = target / peak
    return [[v * g for v in b] for b in chans]


def loop(chans):
    """Fold the last XF seconds into the first with an equal-power crossfade
    and cut them off, so sample N-1 hands over to sample 0 without a step."""
    k = int(XF * SR)
    out = []
    for b in chans:
        n = len(b)
        if n <= 2 * k:
            out.append(b)
            continue
        head = b[:n - k]
        tail = b[n - k:]
        for i in range(k):
            t = i / float(k)
            head[i] = head[i] * t ** 0.5 + tail[i] * (1.0 - t) ** 0.5   # equal power
        out.append(head)
    return out


def fade_in(chans, ms):
    k = min(len(chans[0]), max(1, int(SR * ms / 1000.0)))
    for b in chans:
        for i in range(k):
            b[i] *= (i + 1) / float(k)
    return chans


def fade_out(chans, ms):
    k = min(len(chans[0]), max(1, int(SR * ms / 1000.0)))
    for b in chans:
        n = len(b)
        for i in range(k):
            g = 1.0 - (i + 1) / float(k)
            b[n - k + i] *= g * g
    return chans


def wav(chans):
    """Float channels -> a complete 16-bit RIFF/WAVE, interleaved (one channel -> mono)."""
    n = min(len(b) for b in chans)
    ints = [int(max(-1.0, min(1.0, b[i])) * 32767) for i in range(n) for b in chans]
    frames = struct.pack("<%dh" % len(ints), *ints)
    block_align = len(chans) * 2
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, len(chans), SR, SR * block_align, block_align, 16)
    data = struct.pack("<4sI", b"data", len(frames)) + frames
    body = b"WAVE" + fmt + data
    return struct.pack("<4sI", b"RIFF", len(body)) + body


def measure(chans):
    """(seconds, peak, seam step) — what a take that came back wrong looks like:
    silent, short, or a step at the seam a bed will click on every lap."""
    n = len(chans[0])
    peak = max(abs(v) for b in chans for v in b) if n else 0.0
    seam = max(abs(b[0] - b[-1]) for b in chans) if n else 0.0
    return n / float(SR), peak, seam


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="*", default=None, help="beds and/or stings (default: stings)")
    ap.add_argument("--only", default="", help="comma-separated names, e.g. deeps,music_alarm")
    ap.add_argument("--list", action="store_true", help="print what would be generated and exit")
    ap.add_argument("--dry-run", action="store_true", help="everything but the API call and the write")
    ap.add_argument("--engine", choices=["music", "sfx"], default="music",
                    help="music: the Music API (paid plans); sfx: the sound-effects model, 30 s loops")
    args = ap.parse_args()

    groups = args.groups or ["stings"]
    bad = set(groups) - {"beds", "stings"}
    if bad:
        sys.exit("unknown group(s): %s (want beds and/or stings)" % ", ".join(sorted(bad)))
    todo = jobs(groups, args.only)
    if not todo:
        sys.exit("nothing to do")
    if args.list:
        for group, name, path, prompt, secs in todo:
            print("%-7s %-16s %3ds  %s" % (group, name, secs, prompt))
        print("\n%d generation(s), %d seconds of music." % (len(todo), sum(j[4] for j in todo)))
        return
    key = os.environ.get(KEY_ENV, "")
    if not key and not args.dry_run:
        sys.exit("%s is not set. Get a key from elevenlabs.io and export it, or "
                 "pass --dry-run to check the plan without calling out." % KEY_ENV)

    for group, name, path, prompt, secs in todo:
        if args.engine == "sfx" and group == "beds":
            secs = SFX_BED_SECONDS
        print("%-7s %-16s %3ds ... " % (group, name, secs), end="", flush=True)
        if args.dry_run:
            print("(dry run)")
            continue
        if args.engine == "sfx":
            # A looping take is trimmed of nothing: its first and last samples
            # are the seam, and there is no silence at either end to find.
            chans = generate_sfx(key, prompt, secs, loop=group == "beds")
            if group == "stings":
                chans = trim(chans)
        else:
            chans = trim(decode(generate(key, prompt, secs)))
        raw_secs, raw_peak, _ = measure(chans)
        if group == "beds":
            chans = normalize(loop(chans), BED_PEAK)   # the fold can add up past 1.0; level after
        else:
            chans = fade_in(fade_out(normalize(trim(loudest_phrase(chans)), STING_PEAK),
                                     STING_FADE_MS), HEAD_FADE_MS)
        now, peak, seam = measure(chans)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(wav(chans))
        note = ""
        if raw_peak < SILENCE:
            note = "  ** silent take, re-run this one **"
        elif now < secs * 0.5:
            note = "  ** short take (%.1fs for %ds asked), re-run this one **" % (now, secs)
        elif group == "beds" and seam > 0.05:
            note = "  ** seam step %.3f, re-run this one **" % seam
        print("%s  %.1fs (from %.1fs, peak %.2f)%s"
              % (os.path.relpath(path, ROOT), now, raw_secs, raw_peak, note))

    if not args.dry_run:
        print("\nListen before committing — a take can miss, and re-running is a different\n"
              "take, not the same one. python3 tools/check_audio.py checks the seams.")


if __name__ == "__main__":
    main()

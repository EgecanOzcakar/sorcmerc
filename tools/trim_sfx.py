#!/usr/bin/env python3
"""Trim the dead air off the front and back of every sfx one-shot.

    python3 tools/trim_sfx.py              # every assets/audio/sfx/*.wav but the music_ stings
    python3 tools/trim_sfx.py hit kill     # just these ids
    python3 tools/trim_sfx.py --dry-run    # say what would go, write nothing

A sound is cut to its first and last PART and nothing inside is touched, so a
two-part sound (a javelin's whoosh, then the impact) keeps the space between
them. A part is a run of 5 ms windows louder than REL_DB under the loudest
window, runs closer than GAP_MS merged into one; it only counts when it peaks
within PART_DB of the loudest part. That is what drops the 5 ms blips some
library takes end on and the faint noise a crit take opened on a second before
its hit, while a whoosh at -9 dB before a throw's impact stays.

Why it matters beyond tidiness: the game fires a sting the moment a thing
happens and holds a voice for its whole length (core/audio.gd has 8), so dead
air in front is a late hit and dead air behind is a voice nobody hears.

16-bit PCM, any rate, mono or stereo -- the generator's own takes and the
handpicked 48 kHz stereo library files alike. Written back in the same format.
"""
import argparse
import array
import glob
import math
import os
import sys
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
WINDOW_MS = 5
REL_DB = -45.0      # quieter than this under the loudest window is silence
GAP_MS = 150        # silence shorter than this is inside one part
PART_DB = -20.0     # a part quieter than this under the loudest is not a part
LEAD_MS = 5         # kept in front of the first part...
TAIL_MS = 20        # ...and after the last one, where the fade-out runs
FADE_IN_MS = 4      # no step at sample 0 (tools/check_audio.py fails one)


def window_db(samples, channels, rate):
    """dB of each 5 ms window's RMS (loudest channel per frame) under the loudest."""
    w = max(1, int(rate * WINDOW_MS / 1000))
    frames = len(samples) // channels
    peaks = [max(abs(samples[i * channels + c]) for c in range(channels)) for i in range(frames)]
    rms = [math.sqrt(sum(v * v for v in peaks[i:i + w]) / len(peaks[i:i + w])) for i in range(0, frames, w)]
    top = max(rms) or 1.0
    return [20 * math.log10(r / top) if r > 0 else -200.0 for r in rms], w


def parts(db):
    """[(first_window, last_window, peak_db)] of each run of sound, gaps < GAP_MS merged."""
    gap = GAP_MS // WINDOW_MS
    out = []
    for i, v in enumerate(db):
        if v <= REL_DB:
            continue
        if out and i - out[-1][1] <= gap:
            out[-1] = (out[-1][0], i, max(out[-1][2], v))
        else:
            out.append((i, i, v))
    return out


def span(samples, channels, rate):
    """(start_frame, end_frame, kept_parts, dropped_parts) to cut to, or None if silent."""
    db, w = window_db(samples, channels, rate)
    found = parts(db)
    if not found:
        return None
    loud = max(p[2] for p in found)
    kept = [p for p in found if p[2] >= loud + PART_DB]
    frames = len(samples) // channels
    start = max(0, kept[0][0] * w - int(rate * LEAD_MS / 1000))
    end = min(frames, (kept[-1][1] + 1) * w + int(rate * TAIL_MS / 1000))
    return start, end, kept, [p for p in found if p not in kept]


def trim(samples, channels, rate):
    """Interleaved 16-bit samples -> the trimmed, faded samples (a new array)."""
    s = span(samples, channels, rate)
    if s is None:
        return samples
    start, end = s[0], s[1]
    out = array.array("h", samples[start * channels:end * channels])
    frames = len(out) // channels
    fade_in = min(frames, max(1, int(rate * FADE_IN_MS / 1000)))
    fade_out = min(frames, max(1, int(rate * TAIL_MS / 1000)))
    for i in range(frames):
        g = 1.0
        if i < fade_in:
            g = (i + 1) / float(fade_in)
        if i >= frames - fade_out:
            t = (frames - i) / float(fade_out)
            g *= t * t
        if g < 1.0:
            for c in range(channels):
                out[i * channels + c] = int(round(out[i * channels + c] * g))
    return out


def trim_file(path, dry_run=False):
    with wave.open(path, "rb") as f:
        channels, width, rate, n = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        raw = f.readframes(n)
    if width != 2:
        return "skipped: %d-bit, only 16-bit PCM is handled" % (width * 8)
    samples = array.array("h", raw)
    if sys.byteorder == "big":
        samples.byteswap()
    s = span(samples, channels, rate)
    if s is None:
        return "silent, left alone"
    start, end, kept, dropped = s
    note = "%.2fs -> %.2fs (cut %d ms before, %d ms after)" % (
        n / rate, (end - start) / rate, start * 1000 // rate, (n - end) * 1000 // rate)
    if len(kept) > 1:
        note += ", %d parts kept with their gaps" % len(kept)
    if dropped:
        note += ", dropped %s" % ", ".join("%d ms at %.0f dB" % ((b - a + 1) * WINDOW_MS, v) for a, b, v in dropped)
    if not dry_run:
        out = trim(samples, channels, rate)
        if sys.byteorder == "big":
            out.byteswap()
        with wave.open(path, "wb") as f:
            f.setnchannels(channels)
            f.setsampwidth(2)
            f.setframerate(rate)
            f.writeframes(out.tobytes())
    return note


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="sfx ids (default: all but music_*)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.ids:
        paths = [os.path.join(SFX_DIR, i + ".wav") for i in args.ids]
    else:
        paths = [p for p in sorted(glob.glob(os.path.join(SFX_DIR, "*.wav")))
                 if not os.path.basename(p).startswith("music_")]
    for p in paths:
        print("%-20s %s" % (os.path.basename(p)[:-4], trim_file(p, args.dry_run)))


if __name__ == "__main__":
    main()

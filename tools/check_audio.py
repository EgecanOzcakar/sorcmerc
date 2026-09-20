#!/usr/bin/env python3
"""Validate the generated audio against what core/audio.gd actually requires.

    python3 tools/check_audio.py

The Godot side (tests/test_audio.gd) proves the engine can parse these files and
that every id the game asks for exists. This checks the things that are true or
false about the *waveforms* and would otherwise only show up as a click in
someone's headphones:

  * 16-bit PCM, 1 or 2 channels        -- the only shape audio.gd's reader handles
  * no clipping, no DC offset          -- both audible, both easy to introduce
  * one-shots end near silence         -- otherwise the voice cuts off abruptly
  * beds are seam-continuous           -- a bed loops forever, so a step at the
                                          seam is a click once every LOOP seconds

Exits non-zero on any failure, so it can gate a commit.
"""
import math
import os
import struct
import sys
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
AUDIO = os.path.join(ROOT, "assets", "audio")


def read(path):
    with wave.open(path, "rb") as w:
        ch, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width != 2:
        raise ValueError("sample width %d, expected 2" % width)
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    chans = [[vals[i] / 32768.0 for i in range(c, len(vals), ch)]
             for c in range(ch)]
    return chans, rate


def rms(b, a=0, z=None):
    z = len(b) if z is None else z
    n = max(1, z - a)
    return math.sqrt(sum(v * v for v in b[a:z]) / n)


def main():
    fails = []
    checked = 0
    for group in ("sfx", "music", "barks"):
        d = os.path.join(AUDIO, group)
        for name in sorted(os.listdir(d)):
            if not name.endswith(".wav"):
                continue
            path = os.path.join(d, name)
            rel = "%s/%s" % (group, name)
            try:
                chans, rate = read(path)
            except Exception as e:                       # noqa: BLE001
                fails.append("%s: unreadable (%s)" % (rel, e))
                continue
            checked += 1
            if len(chans) not in (1, 2):
                fails.append("%s: %d channels" % (rel, len(chans)))
            if rate < 22050:
                fails.append("%s: rate %d below 22050" % (rel, rate))
            for ci, b in enumerate(chans):
                if not b:
                    fails.append("%s ch%d: empty" % (rel, ci))
                    continue
                peak = max(max(b), -min(b))
                if peak > 0.999:
                    fails.append("%s ch%d: clipping (peak %.4f)" % (rel, ci, peak))
                if peak < 0.2:
                    fails.append("%s ch%d: suspiciously quiet (peak %.3f)"
                                 % (rel, ci, peak))
                dc = sum(b) / len(b)
                if abs(dc) > 0.02:
                    fails.append("%s ch%d: DC offset %.4f" % (rel, ci, dc))
                win = max(1, int(0.01 * rate))
                if group == "music":
                    # A loop's end must hand over to its start without a step.
                    # Compare the seam's sample-to-sample jump against the jumps
                    # inside the file: a click is a jump far larger than typical.
                    seam = abs(b[0] - b[-1])
                    steps = sorted(abs(b[i + 1] - b[i])
                                   for i in range(0, len(b) - 1, 97))
                    p99 = steps[int(len(steps) * 0.99)]
                    if seam > max(0.02, p99 * 6.0):
                        fails.append("%s ch%d: seam step %.4f vs p99 %.4f"
                                     % (rel, ci, seam, p99))
                    # Level either side of the seam. Only meaningful when BOTH
                    # sides carry signal: a rhythmic bed is supposed to run
                    # quiet into the seam and land a transient on the downbeat,
                    # and that is a beat, not a click. What would click is a
                    # step between two loud, mismatched levels.
                    head, tail = rms(b, 0, win), rms(b, len(b) - win)
                    if min(head, tail) > 0.02:
                        ratio = max(head, tail) / min(head, tail)
                        if ratio > 6.0:
                            fails.append("%s ch%d: seam level jump x%.1f"
                                         % (rel, ci, ratio))
                else:
                    # one-shots must decay, not stop mid-note
                    if rms(b, len(b) - win) > 0.05:
                        fails.append("%s ch%d: ends abruptly (tail rms %.3f)"
                                     % (rel, ci, rms(b, len(b) - win)))
                    # ...and must not START on a step either: sample 0 at
                    # 0.6 FS is a click before the sound (see HEAD_FADE_MS in
                    # tools/gen_audio_elevenlabs.py). The sfx bus starts a
                    # voice from silence, so the first sample IS the step.
                    if abs(b[0]) > 0.05:
                        fails.append("%s ch%d: starts abruptly (first sample %.3f)"
                                     % (rel, ci, b[0]))
    print("checked %d files" % checked)
    for f in fails:
        print("  FAIL %s" % f)
    print("%d passed, %d failed" % (checked - len({f.split(':')[0] for f in fails}),
                                    len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

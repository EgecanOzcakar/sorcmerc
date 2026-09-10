#!/usr/bin/env python3
"""Procedural placeholder audio for sorcmerc (T27).

Stdlib only (wave/struct/math/random). Writes mono 16-bit 22050 Hz WAVs:

    assets/audio/sfx/*.wav     one-shot stings
    assets/audio/music/*.wav   one loopable ambient bed per Encounter.THEMES
                               (+ settlement, title) and one combat tension layer

Same ceiling as every other asset here: shapes, not sprites. Run once:

    python3 tools/gen_audio.py

Regenerating is deterministic (fixed RNG seed), so re-running produces byte
identical files unless the recipes below change.
"""
import math
import os
import random
import struct
import wave

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)

# --- synth primitives -----------------------------------------------------


def buf(dur):
    return [0.0] * int(dur * SR)


def _add(b, i, v):
    if 0 <= i < len(b):
        b[i] += v


def _wave(kind, phase):
    if kind == "sine":
        return math.sin(phase)
    if kind == "square":
        return 1.0 if math.sin(phase) >= 0 else -1.0
    if kind == "saw":
        return (phase / math.pi) % 2.0 - 1.0
    # triangle
    return 2.0 * abs((phase / math.pi) % 2.0 - 1.0) - 1.0


def tone(b, start, dur, f0, f1=None, amp=0.4, kind="sine", decay=5.0, attack=0.004):
    """One note/sweep with an exponential decay envelope."""
    f1 = f0 if f1 is None else f1
    n = max(1, int(dur * SR))
    i0 = int(start * SR)
    phase = 0.0
    for i in range(n):
        u = i / n
        phase += 2.0 * math.pi * (f0 * (f1 / f0) ** u) / SR
        env = math.exp(-decay * u)
        t = i / SR
        if attack > 0 and t < attack:
            env *= t / attack
        _add(b, i0 + i, _wave(kind, phase) * amp * env)


def noise(b, start, dur, amp=0.3, decay=12.0, cutoff=0.35):
    """One-pole lowpassed white noise burst (cutoff 0..1, 1 = raw)."""
    n = max(1, int(dur * SR))
    i0 = int(start * SR)
    prev = 0.0
    for i in range(n):
        prev += cutoff * (random.uniform(-1.0, 1.0) - prev)
        _add(b, i0 + i, prev * amp * math.exp(-decay * i / n))


def drone(b, freq, amp=0.12, trem_cycles=0, trem_depth=0.4, kind="sine"):
    """A sine held for the whole buffer. `freq` and the tremolo rate must both
    complete a whole number of cycles across the buffer or the loop clicks."""
    n = len(b)
    for i in range(n):
        u = i / n
        trem = 1.0 - trem_depth * (0.5 - 0.5 * math.cos(2.0 * math.pi * trem_cycles * u))
        _add(b, i, _wave(kind, 2.0 * math.pi * freq * i / SR) * amp * trem)


def loop_freq(dur, hz):
    """Nearest frequency to `hz` that completes whole cycles in `dur` seconds."""
    return max(1, round(hz * dur)) / dur


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def write(path, b, fade_edges=0.0):
    if fade_edges > 0:  # one-shots: taper the tail so nothing clicks off
        k = int(fade_edges * SR)
        for i in range(k):
            b[len(b) - 1 - i] *= i / k
    peak = max(0.0001, max(abs(v) for v in b))
    gain = 0.85 / peak if peak > 0.85 else 1.0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v * gain)) * 32000)) for v in b))
    return os.path.getsize(path)


# --- one-shots ------------------------------------------------------------


def sfx_hit():
    b = buf(0.18)
    noise(b, 0.0, 0.10, 0.5, 24.0, 0.55)
    tone(b, 0.0, 0.12, 320, 120, 0.45, "square", 18.0)
    return b


def sfx_crit():
    b = buf(0.42)
    noise(b, 0.0, 0.16, 0.55, 14.0, 0.7)
    tone(b, 0.0, 0.20, 520, 140, 0.5, "square", 10.0)
    for i, n in enumerate((72, 79, 84)):
        tone(b, 0.10 + i * 0.05, 0.28, midi(n), amp=0.35, kind="tri", decay=7.0)
    return b


def sfx_kill():
    b = buf(0.55)
    noise(b, 0.0, 0.22, 0.5, 9.0, 0.4)
    tone(b, 0.0, 0.45, 220, 55, 0.5, "saw", 5.0)
    tone(b, 0.06, 0.35, 110, 40, 0.4, "sine", 4.0)
    return b


def sfx_cast():
    b = buf(0.55)
    tone(b, 0.0, 0.5, 300, 1300, 0.32, "sine", 2.0, 0.05)
    tone(b, 0.05, 0.45, 452, 1960, 0.18, "tri", 2.5, 0.05)
    noise(b, 0.30, 0.22, 0.15, 8.0, 0.9)
    return b


def sfx_heal():
    b = buf(0.7)
    for i, n in enumerate((67, 71, 74, 79)):
        tone(b, i * 0.07, 0.55, midi(n), amp=0.28, kind="sine", decay=3.5, attack=0.02)
    return b


def sfx_level_up():
    b = buf(1.2)
    for i, n in enumerate((60, 64, 67, 72, 76)):
        tone(b, i * 0.10, 0.7, midi(n), amp=0.3, kind="tri", decay=3.0, attack=0.01)
    for n in (72, 76, 79):
        tone(b, 0.55, 0.6, midi(n), amp=0.22, kind="sine", decay=2.5, attack=0.02)
    return b


def sfx_victory():
    b = buf(1.8)
    for t, n in ((0.0, 60), (0.16, 60), (0.32, 67), (0.60, 65), (0.76, 67), (0.92, 72)):
        tone(b, t, 0.55, midi(n), amp=0.3, kind="tri", decay=4.0)
        tone(b, t, 0.55, midi(n - 12), amp=0.16, kind="saw", decay=4.5)
    for n in (72, 76, 79, 84):
        tone(b, 1.05, 0.7, midi(n), amp=0.2, kind="sine", decay=2.2, attack=0.02)
    return b


def sfx_defeat():
    b = buf(1.8)
    for i, n in enumerate((57, 55, 52, 48)):
        tone(b, i * 0.28, 1.0, midi(n), amp=0.3, kind="saw", decay=2.5, attack=0.02)
    tone(b, 0.9, 0.9, midi(36), midi(33), 0.3, "sine", 1.8, 0.05)
    return b


def sfx_click():
    b = buf(0.07)
    tone(b, 0.0, 0.05, 1400, 900, 0.35, "square", 30.0, 0.001)
    return b


def sfx_buy():
    b = buf(0.5)
    for i in range(4):  # coins
        tone(b, i * 0.045, 0.22, 1800 + i * 260, amp=0.22, kind="sine", decay=16.0)
    noise(b, 0.0, 0.12, 0.12, 20.0, 0.9)
    return b


def sfx_identify():
    b = buf(0.9)
    tone(b, 0.0, 0.45, 600, 1500, 0.25, "sine", 3.0, 0.04)
    for i, n in enumerate((76, 83)):
        tone(b, 0.30 + i * 0.12, 0.5, midi(n), amp=0.28, kind="tri", decay=3.5)
    return b


def sfx_quest():
    b = buf(1.3)
    for t, n in ((0.0, 62), (0.18, 69), (0.36, 74), (0.54, 78)):
        tone(b, t, 0.7, midi(n), amp=0.28, kind="tri", decay=3.2)
    tone(b, 0.54, 0.7, midi(62), amp=0.16, kind="saw", decay=3.2)
    return b


def sfx_pickup():
    b = buf(0.3)
    tone(b, 0.0, 0.16, midi(76), amp=0.3, kind="sine", decay=9.0)
    tone(b, 0.08, 0.2, midi(83), amp=0.25, kind="sine", decay=8.0)
    return b


def sfx_rest():
    b = buf(1.6)
    for i, n in enumerate((53, 60, 65)):
        tone(b, i * 0.22, 1.3, midi(n), amp=0.26, kind="sine", decay=2.0, attack=0.03)
    return b


SFX = {
    "hit": sfx_hit, "crit": sfx_crit, "kill": sfx_kill, "cast": sfx_cast,
    "heal": sfx_heal, "level_up": sfx_level_up, "victory": sfx_victory,
    "defeat": sfx_defeat, "click": sfx_click, "buy": sfx_buy,
    "identify": sfx_identify, "quest": sfx_quest, "pickup": sfx_pickup,
    "rest": sfx_rest,
}

# --- loops ----------------------------------------------------------------
#
# 4 s beds. Everything in a bed is either a held tone at a loop-locked frequency
# or a short event placed well before the end, so the loop tiles without a click.

LOOP = 4.0

# theme -> (chord midi notes, tremolo cycles per loop, sparkle notes, wave)
BEDS = {
    "sunken-shrine":   ([36, 43, 48, 55], 2, [72, 79], "sine"),
    "goblin-camp":     ([38, 45, 50, 57], 4, [62, 65], "saw"),
    "city-square":     ([41, 48, 53, 60], 3, [69, 72, 76], "tri"),
    "forest-clearing": ([40, 47, 52, 59], 2, [71, 76, 78], "sine"),
    "frozen-cave":     ([35, 42, 47, 54], 1, [83, 86], "sine"),
    "merchant-shop":   ([43, 50, 55, 62], 3, [74, 77, 81], "tri"),
    "settlement":      ([41, 48, 55, 60], 2, [67, 72, 76], "sine"),
    "title":           ([36, 48, 55, 64], 1, [76, 79, 84], "tri"),
}


def bed(notes, trem, sparkle, kind):
    b = buf(LOOP)
    for i, n in enumerate(notes):
        drone(b, loop_freq(LOOP, midi(n)), 0.13 if i else 0.18,
              trem + i, 0.35, kind if i else "sine")
    for i, n in enumerate(sparkle):  # a few soft plucks, all ending before the seam
        tone(b, 0.4 + i * 0.9, 0.8, midi(n), amp=0.11, kind="sine", decay=4.0, attack=0.05)
    return b


def tension():
    """The shared combat layer: kick + bass ostinato over the same 4 s grid."""
    b = buf(LOOP)
    beat = LOOP / 8.0
    for i in range(8):
        t = i * beat
        if i % 2 == 0:  # kick
            tone(b, t, 0.22, 110, 45, 0.5, "sine", 12.0, 0.002)
            noise(b, t, 0.06, 0.18, 30.0, 0.5)
        else:  # hat
            noise(b, t, 0.07, 0.10, 26.0, 0.95)
        n = (33, 33, 40, 33, 36, 36, 31, 38)[i]  # bass ostinato
        tone(b, t, beat * 0.9, midi(n), amp=0.30, kind="saw", decay=4.0)
    return b


def main():
    random.seed(2027)
    total = count = 0
    for name, fn in sorted(SFX.items()):
        p = os.path.join(ROOT, "assets", "audio", "sfx", name + ".wav")
        total += write(p, fn(), fade_edges=0.02)
        count += 1
    for theme, args in sorted(BEDS.items()):
        p = os.path.join(ROOT, "assets", "audio", "music", theme + ".wav")
        total += write(p, bed(*args))
        count += 1
    total += write(os.path.join(ROOT, "assets", "audio", "music", "tension.wav"), tension())
    count += 1
    print("wrote %d files, %.1f KB" % (count, total / 1024.0))


if __name__ == "__main__":
    main()

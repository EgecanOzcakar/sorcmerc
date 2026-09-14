#!/usr/bin/env python3
"""Pure-stdlib DSP toolkit for sorcmerc's generated audio.

No numpy, no ffmpeg, no network: this container has none of them, and the
project's rule has always been that any contributor can regenerate every asset
with a bare `python3`. So everything here is hand-rolled float math over plain
Python lists, which is slow but exact and dependency-free.

What it buys over the first pass of tools/gen_audio.py (naive oscillators + a
one-pole filter + exponential decays):

  * PolyBLEP oscillators      band-limited saw/square instead of aliased ones.
                              The old naive saw folded every harmonic above
                              Nyquist back down as grit; this removes it.
  * Biquad filters            resonant low/high/band-pass and peaking EQ, so a
                              sound can have a formant or a filter sweep rather
                              than a single fixed one-pole rolloff.
  * Freeverb                  8 combs + 4 allpasses, mono in / stereo out. The
                              single biggest reason the old assets read as
                              "beeps" and these read as "in a room".
  * Formant voice             a glottal pulse through an F1/F2/F3 resonator
                              bank: vowel-like barks instead of pitched blips.
  * ADSR + soft clipping      real attacks/releases and analog-ish saturation
                              instead of exponential decay and hard clamping.

Sample layout is float [-1, 1]; a stereo signal is a pair of equal-length
lists. `write_wav` is the only thing that cares about integers.

Hot loops pull their state into locals and avoid attribute/method lookups on
purpose — it is the difference between seconds and minutes per asset here.
"""
import math
import os
import random
import struct
import wave

SR = 32000          # generation rate; core/audio.gd reads it from each header.
                    # 32 kHz, not 44.1: this material is synthesised and has
                    # almost nothing above 12 kHz, so the top octave costs 27% of
                    # the download for no audible gain in a web build. Override
                    # with `gen_audio.py --rate 44100` if that ever stops being
                    # true.
TWO_PI = 2.0 * math.pi


def set_rate(hz):
    """Change the generation rate. Must be called before building anything:
    every generator reads SR at call time, so this has to precede them."""
    global SR
    SR = int(hz)
    return SR


# --- buffers ---------------------------------------------------------------

def buf(dur):
    """A silent mono buffer of `dur` seconds."""
    return [0.0] * int(dur * SR)


def stereo(dur):
    return [0.0] * int(dur * SR), [0.0] * int(dur * SR)


def add(b, i, v):
    if 0 <= i < len(b):
        b[i] += v


def mix(dst, src, gain=1.0, offset=0):
    """dst += src * gain, starting at sample `offset`."""
    n = len(dst)
    for i, v in enumerate(src):
        j = i + offset
        if 0 <= j < n:
            dst[j] += v * gain
    return dst


# --- pitch -----------------------------------------------------------------

def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def loop_freq(dur, hz):
    """Nearest frequency to `hz` completing whole cycles in `dur` seconds, so a
    held tone meets its own start at the loop seam without a click."""
    return max(1, round(hz * dur)) / dur


# --- oscillators -----------------------------------------------------------
#
# PolyBLEP: at every discontinuity a naive saw/square would step through, add a
# 2-sample polynomial correction. Cheap, and kills nearly all the aliasing that
# made the old high-pitched saws buzz.

def _blep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def osc(kind, phase, dt):
    """One band-limited sample. `phase` in [0,1), `dt` = freq/SR."""
    if kind == "sine":
        return math.sin(TWO_PI * phase)
    if kind == "saw":
        return 2.0 * phase - 1.0 - _blep(phase, dt)
    if kind == "square":
        v = 1.0 if phase < 0.5 else -1.0
        v += _blep(phase, dt)
        v -= _blep((phase + 0.5) % 1.0, dt)
        return v
    if kind == "tri":                      # integrated square: soft, hollow
        return 4.0 * abs(phase - 0.5) - 1.0
    if kind == "pulse":                    # narrow pulse, reedy
        v = 1.0 if phase < 0.25 else -1.0
        v += _blep(phase, dt)
        v -= _blep((phase + 0.75) % 1.0, dt)
        # A 25% duty cycle averages -0.5. Left in, that DC offset eats headroom
        # and thumps whenever the note is gated; +0.5 makes the wave zero-mean.
        return v + 0.5
    raise ValueError("unknown wave %r" % kind)


# --- envelopes -------------------------------------------------------------

def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2, curve=2.0):
    """An ADSR envelope of `n` samples, times in seconds. Exponential-ish
    segments (curve>1) because linear ramps sound synthetic on transients."""
    ai = max(1, int(a * SR))
    di = max(1, int(d * SR))
    ri = max(1, int(r * SR))
    out = [0.0] * n
    for i in range(n):
        left = n - i
        if i < ai:
            v = (i / ai) ** (1.0 / curve)
        elif i < ai + di:
            u = (i - ai) / di
            v = 1.0 + (s - 1.0) * (u ** (1.0 / curve))
        else:
            v = s
        if left < ri:                       # release always wins
            v *= (left / ri) ** curve
        out[i] = v
    return out


def decay_env(n, rate=5.0, attack=0.004):
    """Percussive: near-instant attack, exponential fall."""
    ai = max(1, int(attack * SR))
    out = [0.0] * n
    for i in range(n):
        v = math.exp(-rate * i / n)
        if i < ai:
            v *= i / ai
        out[i] = v
    return out


# --- filters ---------------------------------------------------------------

class Biquad:
    """RBJ cookbook biquad. Call `run(samples)` for the fast path."""

    def __init__(self, kind, freq, q=0.707, gain_db=0.0):
        self.set(kind, freq, q, gain_db)
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def set(self, kind, freq, q=0.707, gain_db=0.0):
        freq = max(20.0, min(freq, SR * 0.45))
        w = TWO_PI * freq / SR
        cw, sw = math.cos(w), math.sin(w)
        alpha = sw / (2.0 * q)
        A = 10.0 ** (gain_db / 40.0)
        if kind == "lp":
            b0, b1, b2 = (1.0 - cw) / 2.0, 1.0 - cw, (1.0 - cw) / 2.0
            a0, a1, a2 = 1.0 + alpha, -2.0 * cw, 1.0 - alpha
        elif kind == "hp":
            b0, b1, b2 = (1.0 + cw) / 2.0, -(1.0 + cw), (1.0 + cw) / 2.0
            a0, a1, a2 = 1.0 + alpha, -2.0 * cw, 1.0 - alpha
        elif kind == "bp":                  # constant skirt, peak gain = q
            b0, b1, b2 = sw / 2.0, 0.0, -sw / 2.0
            a0, a1, a2 = 1.0 + alpha, -2.0 * cw, 1.0 - alpha
        elif kind == "peak":
            b0, b1, b2 = 1.0 + alpha * A, -2.0 * cw, 1.0 - alpha * A
            a0, a1, a2 = 1.0 + alpha / A, -2.0 * cw, 1.0 - alpha / A
        else:
            raise ValueError(kind)
        self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
        self.a1, self.a2 = a1 / a0, a2 / a0

    def run(self, b):
        """Filter list `b` in place."""
        b0, b1, b2, a1, a2 = self.b0, self.b1, self.b2, self.a1, self.a2
        x1, x2, y1, y2 = self.x1, self.x2, self.y1, self.y2
        for i, x in enumerate(b):
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1 = x1, x
            y2, y1 = y1, y
            b[i] = y
        self.x1, self.x2, self.y1, self.y2 = x1, x2, y1, y2
        return b


def sweep_lp(b, f0, f1, q=1.2):
    """Time-varying lowpass. Coefficients are recomputed in blocks — per-sample
    would be ~4x slower and is inaudible here."""
    n = len(b)
    block = 64
    f = Biquad("lp", f0, q)
    for start in range(0, n, block):
        u = start / max(1, n)
        f.set("lp", f0 * (f1 / f0) ** u, q)
        end = min(start + block, n)
        seg = b[start:end]
        f.run(seg)
        b[start:end] = seg
    return b


# --- Freeverb --------------------------------------------------------------
#
# Schroeder/Freeverb topology: 8 parallel lowpass-damped comb filters into 4
# series allpasses, per output channel, with the right-channel delays offset by
# `STEREO_SPREAD` so a mono source lands as a wide stereo tail. Tunings are the
# classic Freeverb ones, rescaled from their native 44.1 kHz.

_COMBS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
_ALLPASS = (556, 441, 341, 225)
_SPREAD = 23


class Reverb:
    def __init__(self, room=0.84, damp=0.35, width=1.0, scale=None):
        self.room = room
        self.damp = damp
        self.width = width
        # Resolved here, not as a default argument: the Freeverb tunings are in
        # samples at 44.1 kHz, and SR may have been changed since import.
        self.scale = (SR / 44100.0) if scale is None else scale

    def _chan(self, src, offset):
        scale, room, damp = self.scale, self.room, self.damp
        n = len(src)
        out = [0.0] * n
        # parallel combs, summed
        for tune in _COMBS:
            size = max(4, int((tune + offset) * scale))
            d = [0.0] * size
            idx = 0
            store = 0.0
            d1 = damp
            d2 = 1.0 - damp
            for i in range(n):
                y = d[idx]
                store = y * d2 + store * d1        # one-pole damping in the loop
                d[idx] = src[i] + store * room
                idx += 1
                if idx == size:
                    idx = 0
                out[i] += y
        # series allpasses, diffusion
        for tune in _ALLPASS:
            size = max(4, int((tune + offset) * scale))
            d = [0.0] * size
            idx = 0
            for i in range(n):
                y = d[idx]
                x = out[i]
                d[idx] = x + y * 0.5
                out[i] = y - x
                idx += 1
                if idx == size:
                    idx = 0
        return out

    def run(self, src):
        """Mono list -> (left, right) wet-only lists."""
        wl = self._chan(src, 0)
        wr = self._chan(src, _SPREAD)
        if self.width < 1.0:                       # narrow by blending to mid
            k = (1.0 - self.width) * 0.5
            for i in range(len(wl)):
                l, r = wl[i], wr[i]
                wl[i] = l * (1.0 - k) + r * k
                wr[i] = r * (1.0 - k) + l * k
        return wl, wr


def reverb_into(dst_l, dst_r, src, wet=0.3, room=0.84, damp=0.35, width=1.0):
    """Add a reverb of mono `src` into an existing stereo pair."""
    wl, wr = Reverb(room, damp, width).run(src)
    g = wet * 0.06                                  # combs sum 8x; keep headroom
    for i in range(len(dst_l)):
        dst_l[i] += wl[i] * g
        dst_r[i] += wr[i] * g
    return dst_l, dst_r


# --- delay / chorus --------------------------------------------------------

def delay(b, time, feedback=0.35, mix_amt=0.3):
    """Feedback delay, in place."""
    size = max(1, int(time * SR))
    d = [0.0] * size
    idx = 0
    for i, x in enumerate(b):
        y = d[idx]
        d[idx] = x + y * feedback
        idx += 1
        if idx == size:
            idx = 0
        b[i] = x + y * mix_amt
    return b


def chorus(b, rate=0.6, depth_ms=6.0, mix_amt=0.4):
    """Single-tap modulated delay with linear interpolation: thickens pads."""
    n = len(b)
    base = int(0.018 * SR)
    depth = depth_ms * 0.001 * SR
    size = base + int(depth) + 4
    d = [0.0] * size
    idx = 0
    out = list(b)
    for i in range(n):
        d[idx] = b[i]
        off = base + depth * (0.5 + 0.5 * math.sin(TWO_PI * rate * i / SR))
        r = idx - off
        while r < 0:
            r += size
        i0 = int(r)
        frac = r - i0
        i1 = i0 + 1
        if i1 >= size:
            i1 -= size
        out[i] = b[i] + (d[i0] + (d[i1] - d[i0]) * frac) * mix_amt
        idx += 1
        if idx == size:
            idx = 0
    b[:] = out
    return b


# --- saturation / level ----------------------------------------------------

def dc_block(b, hz=18.0):
    """One-pole DC blocker. Karplus-Strong and short noise bursts both start
    with a nonzero mean, and the averaging in a KS loop preserves it."""
    r = 1.0 - (TWO_PI * hz / SR)
    x1 = y1 = 0.0
    for i, x in enumerate(b):
        y = x - x1 + r * y1
        x1 = x
        y1 = y
        b[i] = y
    return b


def softclip(b, drive=1.0):
    """tanh-ish saturation: adds even/odd harmonics and glues transients."""
    for i, v in enumerate(b):
        x = v * drive
        b[i] = math.tanh(x) if -3.0 < x < 3.0 else (1.0 if x > 0 else -1.0)
    return b


def peak(*chans):
    p = 0.0
    for b in chans:
        for v in b:
            if v > p:
                p = v
            elif -v > p:
                p = -v
    return p


def normalize(chans, target=0.89):
    """Scale a list of channels together so the loudest peak hits `target`."""
    p = peak(*chans)
    if p <= 1e-9:
        return chans
    g = target / p
    for b in chans:
        for i in range(len(b)):
            b[i] *= g
    return chans


def fade_out(b, secs):
    k = min(len(b), int(secs * SR))
    n = len(b)
    for i in range(k):
        b[n - 1 - i] *= i / k
    return b


def fade_in(b, secs):
    k = min(len(b), int(secs * SR))
    for i in range(k):
        b[i] *= i / k
    return b


def trim_silence(b, thresh=0.0015, keep=0.02):
    """Drop a dead tail (generators often leave one), keeping `keep` seconds."""
    last = 0
    for i, v in enumerate(b):
        if v > thresh or -v > thresh:
            last = i
    end = min(len(b), last + int(keep * SR) + 1)
    return b[:end]


# --- seamless looping ------------------------------------------------------

def wrap_tail(chans, loop_secs):
    """Make a decaying render loop cleanly.

    Everything is rendered `loop_secs` plus a tail; the tail (reverb, note
    releases) is folded back onto the head and the buffer truncated to
    `loop_secs`, so what rings out past the seam is exactly what is already
    ringing when the loop restarts. This is what lets the beds carry reverb
    without a click or a swell at the loop point.
    """
    n = int(loop_secs * SR)
    out = []
    for b in chans:
        head = b[:n]
        for i, v in enumerate(b[n:]):
            if i < n:
                head[i] += v
        out.append(head)
    return out


# --- output ----------------------------------------------------------------

def write_wav(path, chans, target=0.89):
    """Write 16-bit PCM. One channel -> mono, two -> interleaved stereo."""
    normalize(chans, target)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    n = min(len(c) for c in chans)
    frames = bytearray()
    if len(chans) == 1:
        b = chans[0]
        for i in range(n):
            v = b[i]
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000))
    else:
        l, r = chans[0], chans[1]
        for i in range(n):
            frames += struct.pack("<hh",
                                  int(max(-1.0, min(1.0, l[i])) * 32000),
                                  int(max(-1.0, min(1.0, r[i])) * 32000))
    with wave.open(path, "wb") as w:
        w.setnchannels(len(chans))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    return os.path.getsize(path)


# --- formant voice ---------------------------------------------------------
#
# T31 barks are deliberately wordless (see core/barks.gd: the text bark is
# random, so any fixed spoken line would contradict it). But "wordless" does not
# have to mean "beep". A glottal pulse pushed through a bank of three bandpass
# resonators tuned to real vowel formants reads as a voice saying *something*
# without saying anything — which is exactly the Don't-Starve register the task
# asked for, and a large step up from the original pitched-sine syllables.
#
# F1/F2/F3 in Hz, from the standard measured vowel chart.
VOWELS = {
    "a":  (800.0, 1150.0, 2900.0),
    "e":  (400.0, 1700.0, 2600.0),
    "i":  (280.0, 2250.0, 2900.0),
    "o":  (450.0,  800.0, 2830.0),
    "u":  (325.0,  700.0, 2530.0),
    "ae": (660.0, 1700.0, 2400.0),
}
_FORMANT_GAIN = (1.0, 0.45, 0.18)      # F1 loudest; F3 is mostly presence
_FORMANT_Q = (11.0, 13.0, 15.0)


def glottal(n, f0_hz, f1_hz, vib_hz=5.0, vib_depth=0.012, jitter=0.004, rng=None):
    """A band-limited pulse train with vibrato and a little pitch jitter.

    The jitter matters: a mathematically perfect pitch sounds synthetic, and a
    few tenths of a percent of wobble is most of what makes this read as
    something with lungs.
    """
    rng = rng or random
    out = [0.0] * n
    phase = 0.0
    drift = 0.0
    for i in range(n):
        u = i / n
        f = f0_hz * (f1_hz / f0_hz) ** u
        f *= 1.0 + vib_depth * math.sin(TWO_PI * vib_hz * i / SR)
        drift += (rng.uniform(-1.0, 1.0) - drift) * 0.02
        f *= 1.0 + jitter * drift
        dt = f / SR
        phase += dt
        if phase >= 1.0:
            phase -= 1.0
        # saw source: rich in harmonics for the formants to carve
        out[i] = (2.0 * phase - 1.0 - _blep(phase, dt)) * 0.5
    return out


def formants(src, vowel, shift=1.0):
    """Run a source through the F1/F2/F3 resonator bank for `vowel`."""
    f1, f2, f3 = VOWELS[vowel]
    out = [0.0] * len(src)
    for f, g, q in zip((f1, f2, f3), _FORMANT_GAIN, _FORMANT_Q):
        band = list(src)
        Biquad("bp", f * shift, q).run(band)
        for i, v in enumerate(band):
            out[i] += v * g
    return out


def syllable(dur, root_hz, bend_hz, vowel, shift=1.0, breath=0.06,
             plosive=False, rng=None):
    """One vowel-like syllable, optionally with a consonant-ish onset."""
    rng = rng or random
    n = max(1, int(dur * SR))
    src = glottal(n, root_hz, bend_hz, vib_hz=5.5 + rng.random() * 4.0, rng=rng)
    if breath > 0:                              # aspiration rides with the tone
        for i in range(n):
            src[i] += rng.uniform(-1.0, 1.0) * breath
    out = formants(src, vowel, shift)
    env = adsr(n, a=0.012, d=0.05, s=0.75, r=max(0.03, dur * 0.35), curve=1.6)
    for i in range(n):
        out[i] *= env[i]
    if plosive:                                 # a click of noise at the attack
        k = int(0.012 * SR)
        burst = [rng.uniform(-1.0, 1.0) for _ in range(min(k, n))]
        Biquad("bp", 1800.0 * shift, 1.4).run(burst)
        for i, v in enumerate(burst):
            out[i] += v * 0.5 * (1.0 - i / max(1, len(burst)))
    return out

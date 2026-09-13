#!/usr/bin/env python3
"""Generated audio for sorcmerc (T27 sound + T31 barks).

    python3 tools/gen_audio.py            # everything
    python3 tools/gen_audio.py sfx barks  # just those groups
    python3 tools/gen_audio.py --list     # what would be written
    python3 tools/gen_audio.py --rate 44100 --loop 12   # bigger, longer

Writes 16-bit PCM WAVs that core/audio.gd reads straight off disk with
FileAccess (no editor import round-trip):

    assets/audio/sfx/*.wav     14 one-shot stings
    assets/audio/music/*.wav   one loopable bed per Encounter.THEMES, plus
                               settlement/title, plus the combat tension layer
    assets/audio/barks/*.wav   T31 wordless voice stingers, 3 per archetype

Deterministic: every recipe seeds its own RNG, so re-running produces
byte-identical files unless a recipe changes.

This is still generated audio rather than recorded audio -- the same "shapes,
not sprites" ceiling as the rest of the project's assets. What changed is how
much is asked of the synthesis: see tools/synth.py for the DSP (band-limited
oscillators, biquads, Freeverb, formant voice). Recipes here are written in
terms of *instruments* rather than raw tones, beds carry actual chord
progressions instead of one held chord, and everything lands in a room.

A note on the format, since it is load-bearing: beds and stings are stereo and
everything runs at 44.1 kHz. core/audio.gd reads the channel count and sample
rate out of each file's `fmt ` chunk rather than assuming them, so adding a
mono 22 kHz file here still works.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import synth as S
from synth import midi, buf, stereo, mix, adsr, decay_env, Biquad

# Rebound by main() for --rate/--loop. Every recipe reads these as globals at
# call time, so they must not be captured into a local or a default argument.
SR = S.SR

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)


# --- instruments -----------------------------------------------------------
#
# Each returns a mono buffer. They are deliberately small and composable; the
# recipes below are mostly arrangement, not synthesis.

def tone(dur, f0, f1=None, amp=0.4, kind="sine", decay=5.0, attack=0.004,
         detune=0.0):
    """One note or sweep with a percussive envelope. `detune` in cents adds a
    second slightly-off copy, which is most of what makes a synth sound thick."""
    f1 = f0 if f1 is None else f1
    n = max(1, int(dur * SR))
    env = decay_env(n, decay, attack)
    out = [0.0] * n
    voices = ((0.0, 1.0),) if detune <= 0 else ((-detune, 0.5), (detune, 0.5))
    for cents, g in voices:
        mult = 2.0 ** (cents / 1200.0)
        phase = 0.0
        for i in range(n):
            u = i / n
            dt = f0 * (f1 / f0) ** u * mult / SR
            phase += dt
            if phase >= 1.0:
                phase -= 1.0
            out[i] += S.osc(kind, phase, dt) * g * env[i]
    for i in range(n):
        out[i] *= amp
    return out


def noise(dur, amp=0.3, decay=12.0, freq=4000.0, q=0.8, kind="lp", rng=None):
    """A filtered noise burst: the transient half of every impact."""
    rng = rng or random
    n = max(1, int(dur * SR))
    out = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    m = sum(out) / n                     # a short burst is not mean-zero by luck
    for i in range(n):
        out[i] -= m
    Biquad(kind, freq, q).run(out)
    env = decay_env(n, decay, 0.0008)
    for i in range(n):
        out[i] *= amp * env[i]
    return out


def pluck(dur, freq, amp=0.4, damp=0.5, bright=0.5, rng=None):
    """Karplus-Strong plucked string.

    A burst of noise in a delay line one period long, lowpassed a little on
    every lap. Two lines of code and it sounds like a real plucked string --
    the lutes in the town beds and the harps in the magic stings are all this.
    """
    rng = rng or random
    n = max(1, int(dur * SR))
    size = max(2, int(SR / max(20.0, freq)))
    line = [rng.uniform(-1.0, 1.0) for _ in range(size)]
    Biquad("lp", 200.0 + 9000.0 * bright, 0.7).run(line)
    m = sum(line) / size                 # the KS loop's averaging preserves DC,
    for i in range(size):                # so any offset here rings for the whole
        line[i] -= m                     # note and shows up as a thump

    out = [0.0] * n
    idx = 0
    prev = 0.0
    # `damp` sets how fast the loop loses its high end -> long vs muted note
    a = 0.5 - 0.22 * (1.0 - damp)
    for i in range(n):
        v = line[idx]
        out[i] = v
        smoothed = a * v + (1.0 - a) * prev
        prev = v
        line[idx] = smoothed * 0.998
        idx += 1
        if idx == size:
            idx = 0
    for i in range(n):
        out[i] *= amp
    S.dc_block(out)
    S.fade_out(out, min(0.05, dur * 0.25))
    return out


def bell(dur, freq, amp=0.3, inharm=1.0, partials=5):
    """Struck metal: inharmonic partials, each decaying faster than the last."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    ratios = (1.0, 2.0 + 0.01 * inharm, 3.01 + 0.03 * inharm,
              4.17 + 0.05 * inharm, 5.43 + 0.08 * inharm)[:partials]
    for k, r in enumerate(ratios):
        f = freq * r
        if f > SR * 0.45:
            continue
        g = amp / (1.0 + k * 1.5)
        env = decay_env(n, 2.2 + k * 1.8, 0.002)
        step = S.TWO_PI * f / SR
        ph = 0.0
        for i in range(n):
            ph += step
            out[i] += math.sin(ph) * g * env[i]
    return out


def brass(dur, freq, amp=0.35, detune=12.0, cutoff=2600.0):
    """Horn-ish: detuned saws, a filter that opens with the attack."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    for cents, g in ((-detune, 0.5), (0.0, 0.6), (detune, 0.5)):
        mult = 2.0 ** (cents / 1200.0)
        dt = freq * mult / SR
        ph = 0.0
        for i in range(n):
            ph += dt
            if ph >= 1.0:
                ph -= 1.0
            out[i] += S.osc("saw", ph, dt) * g
    S.sweep_lp(out, cutoff * 0.35, cutoff, q=1.1)
    env = adsr(n, a=0.035, d=0.12, s=0.72, r=max(0.06, dur * 0.3), curve=1.7)
    for i in range(n):
        out[i] *= amp * env[i]
    return out


def pad(dur, freqs, amp=0.16, cutoff=1500.0, sweep=1.6, kind="saw", detune=9.0):
    """The sustained bed layer: a detuned stack, gently swept, then chorused."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    for f in freqs:
        for cents, g in ((-detune, 0.5), (detune, 0.5)):
            dt = f * 2.0 ** (cents / 1200.0) / SR
            ph = 0.0
            for i in range(n):
                ph += dt
                if ph >= 1.0:
                    ph -= 1.0
                out[i] += S.osc(kind, ph, dt) * g
    S.sweep_lp(out, cutoff, cutoff * sweep, q=0.9)
    S.chorus(out, rate=0.23, depth_ms=7.0, mix_amt=0.45)
    for i in range(n):
        out[i] *= amp
    return out


def sub(dur, freq, amp=0.4, decay=1.2):
    """Sine sub-bass. Keeps the low end clean where a saw would muddy it."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    step = S.TWO_PI * freq / SR
    env = decay_env(n, decay, 0.01)
    ph = 0.0
    for i in range(n):
        ph += step
        out[i] = math.sin(ph) * amp * env[i]
    return out


def kick(amp=0.7, rng=None):
    out = tone(0.28, 145.0, 44.0, amp, "sine", 9.0, 0.001)
    mix(out, noise(0.02, amp * 0.35, 40.0, 2200.0, 0.9, rng=rng))
    S.softclip(out, 1.4)
    return out


def snare(amp=0.45, rng=None):
    out = noise(0.20, amp, 16.0, 2600.0, 0.9, rng=rng)
    mix(out, noise(0.20, amp * 0.4, 13.0, 900.0, 1.6, "bp", rng=rng))
    mix(out, tone(0.09, 250.0, 180.0, amp * 0.35, "tri", 20.0, 0.001))
    return out


def hat(amp=0.2, dur=0.06, rng=None):
    return noise(dur, amp, 34.0, 8500.0, 1.1, "hp", rng=rng)


def tom(freq=190.0, amp=0.4, rng=None):
    out = tone(0.22, freq, freq * 0.55, amp, "sine", 11.0, 0.002)
    mix(out, noise(0.03, amp * 0.25, 30.0, 1400.0, 0.9, rng=rng))
    return out


def metal(dur, freq, amp=0.3, rng=None):
    """Sword-on-armour ring: a noise burst forced through inharmonic resonances."""
    rng = rng or random
    n = max(1, int(dur * SR))
    src = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    out = [0.0] * n
    for r, g, q in ((1.0, 1.0, 26.0), (1.68, 0.6, 30.0), (2.41, 0.4, 34.0),
                    (3.77, 0.25, 38.0)):
        f = freq * r
        if f > SR * 0.45:
            continue
        band = list(src)
        Biquad("bp", f, q).run(band)
        for i in range(n):
            out[i] += band[i] * g
    env = decay_env(n, 7.0, 0.001)
    for i in range(n):
        out[i] *= amp * env[i]
    return out


def wind(dur, amp=0.1, freq=700.0, q=1.2, rate=0.13, rng=None):
    """Slow-swelling filtered noise: the air in a cave or a forest."""
    rng = rng or random
    n = max(1, int(dur * SR))
    out = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    Biquad("bp", freq, q).run(out)
    cycles = max(1, round(rate * dur))          # whole cycles -> loop-safe
    for i in range(n):
        u = i / n
        lfo = 0.45 + 0.55 * (0.5 - 0.5 * math.cos(S.TWO_PI * cycles * u))
        out[i] *= amp * lfo
    return out

# --- rendering helpers -----------------------------------------------------

def room(mono, wet=0.22, size=0.80, damp=0.40, width=1.0, tail=0.5):
    """Put a mono sound in a room: dry down the middle, reverb in stereo.

    `tail` extends the buffer so the reverb can ring out past the dry sound
    instead of being chopped off, which is what made the old stings stop dead.
    """
    n = len(mono) + int(tail * SR)
    dry = mono + [0.0] * (n - len(mono))
    l, r = list(dry), list(dry)
    S.reverb_into(l, r, dry, wet, size, damp, width)
    return [l, r]


def spread(mono, ms=11.0, amount=0.55):
    """Haas widening: the same signal a few ms later on one side reads as wide
    without the phasiness of detuning. Used on the big fanfares."""
    d = int(ms * 0.001 * SR)
    l = list(mono)
    r = [0.0] * len(mono)
    for i in range(len(mono)):
        j = i - d
        r[i] = mono[i] * (1.0 - amount) + (mono[j] if j >= 0 else 0.0) * amount
    return [l, r]


# --- one-shot stings -------------------------------------------------------
#
# Every one is layered transient + body + tail, then placed in a room. Sizes and
# damping differ on purpose: combat hits are dry and close, magic is wide and
# wet, UI clicks have no room at all.

def sfx_hit(rng):
    b = buf(0.30)
    mix(b, noise(0.045, 0.55, 38.0, 3200.0, 0.9, rng=rng))       # impact
    mix(b, metal(0.22, 1450.0, 0.34, rng=rng))                   # armour ring
    mix(b, tone(0.10, 260.0, 90.0, 0.45, "tri", 22.0, 0.001))    # body thud
    S.softclip(b, 1.5)
    return room(b, wet=0.14, size=0.62, damp=0.55, tail=0.25)


def sfx_crit(rng):
    b = buf(0.55)
    mix(b, noise(0.06, 0.6, 26.0, 4200.0, 0.9, rng=rng))
    mix(b, metal(0.42, 2100.0, 0.42, rng=rng))
    mix(b, tone(0.14, 420.0, 110.0, 0.5, "square", 16.0, 0.001))
    mix(b, sub(0.22, 60.0, 0.35, 6.0))
    for i, n in enumerate((72, 79, 84)):                          # rising flourish
        mix(b, bell(0.34, midi(n), 0.20), offset=int((0.09 + i * 0.05) * SR))
    S.softclip(b, 1.6)
    return room(b, wet=0.26, size=0.76, damp=0.42, tail=0.55)


def sfx_kill(rng):
    b = buf(0.70)
    mix(b, noise(0.10, 0.5, 15.0, 1500.0, 0.8, rng=rng))
    mix(b, tone(0.34, 210.0, 48.0, 0.5, "saw", 6.0, 0.002, detune=18.0))
    mix(b, sub(0.55, 45.0, 0.5, 2.4))
    mix(b, tom(120.0, 0.4, rng=rng))
    S.softclip(b, 1.8)
    return room(b, wet=0.22, size=0.82, damp=0.62, tail=0.6)


def sfx_cast(rng):
    b = buf(0.85)
    # a rising, opening shimmer: detuned saws under a filter that lifts with it
    sweep = tone(0.55, 300.0, 1500.0, 0.26, "saw", 1.6, 0.05, detune=14.0)
    S.sweep_lp(sweep, 700.0, 6500.0, q=1.6)
    mix(b, sweep)
    for i, n in enumerate((76, 83, 88)):
        mix(b, pluck(0.5, midi(n), 0.22, damp=0.8, bright=0.8, rng=rng),
            offset=int((0.16 + i * 0.07) * SR))
    mix(b, noise(0.3, 0.10, 5.0, 7000.0, 0.7, "hp", rng=rng), offset=int(0.3 * SR))
    return room(b, wet=0.42, size=0.90, damp=0.26, tail=1.1)


def sfx_heal(rng):
    b = buf(1.0)
    for i, n in enumerate((67, 71, 74, 79)):                      # warm major arp
        mix(b, pluck(0.75, midi(n), 0.26, damp=0.9, bright=0.45, rng=rng),
            offset=int(i * 0.075 * SR))
        mix(b, tone(0.6, midi(n), amp=0.10, kind="sine", decay=2.4, attack=0.05),
            offset=int(i * 0.075 * SR))
    return room(b, wet=0.38, size=0.88, damp=0.34, tail=1.0)


def sfx_level_up(rng):
    b = buf(1.5)
    for i, n in enumerate((60, 64, 67, 72, 76)):
        mix(b, brass(0.42, midi(n), 0.24), offset=int(i * 0.095 * SR))
    for i, n in enumerate((72, 76, 79, 84)):                      # bell stack on top
        mix(b, bell(0.9, midi(n), 0.20), offset=int((0.52 + i * 0.04) * SR))
    mix(b, sub(0.6, midi(36), 0.3, 2.0), offset=int(0.5 * SR))
    S.softclip(b, 1.2)
    return spread_room(b, wet=0.34, size=0.88, damp=0.3, tail=1.2)


def sfx_victory(rng):
    b = buf(2.2)
    # I - I - V - IV - V - I, the shape of every victory jingle ever written
    for t, n in ((0.0, 60), (0.15, 60), (0.30, 67), (0.58, 65), (0.73, 67),
                 (0.90, 72)):
        mix(b, brass(0.5, midi(n), 0.26), offset=int(t * SR))
        mix(b, brass(0.5, midi(n - 12), 0.14, detune=8.0), offset=int(t * SR))
    for i, n in enumerate((72, 76, 79, 84)):
        mix(b, bell(1.1, midi(n), 0.18), offset=int((1.02 + i * 0.035) * SR))
    mix(b, noise(0.7, 0.12, 3.2, 6000.0, 0.7, "hp", rng=rng), offset=int(0.95 * SR))
    mix(b, sub(0.8, midi(36), 0.32, 1.8), offset=int(0.95 * SR))
    S.softclip(b, 1.25)
    return spread_room(b, wet=0.34, size=0.90, damp=0.3, tail=1.3)


def sfx_defeat(rng):
    b = buf(2.4)
    for i, n in enumerate((57, 55, 52, 48)):                      # sagging minor fall
        mix(b, brass(0.95, midi(n), 0.26, detune=16.0, cutoff=1500.0),
            offset=int(i * 0.30 * SR))
    mix(b, tone(0.9, midi(36), midi(32), 0.3, "saw", 1.8, 0.06, detune=20.0),
        offset=int(0.95 * SR))
    mix(b, sub(1.1, 42.0, 0.34, 1.4), offset=int(0.95 * SR))
    return spread_room(b, wet=0.40, size=0.92, damp=0.55, tail=1.4)


def sfx_click(rng):
    b = buf(0.06)
    mix(b, noise(0.012, 0.3, 60.0, 2600.0, 1.2, "bp", rng=rng))
    mix(b, tone(0.035, 1500.0, 1000.0, 0.28, "tri", 40.0, 0.0005))
    return [b, list(b)]                                          # no room on UI


def sfx_buy(rng):
    b = buf(0.6)
    for i in range(5):                                           # coins on wood
        mix(b, metal(0.20, 2400.0 + i * 520.0, 0.20, rng=rng),
            offset=int(i * 0.042 * SR))
    mix(b, noise(0.10, 0.10, 22.0, 1100.0, 0.8, rng=rng))        # purse
    return room(b, wet=0.18, size=0.68, damp=0.5, tail=0.4)


def sfx_identify(rng):
    b = buf(1.2)
    rise = tone(0.5, 480.0, 1400.0, 0.20, "tri", 1.8, 0.06, detune=10.0)
    S.sweep_lp(rise, 900.0, 5200.0, q=1.5)
    mix(b, rise)
    for i, n in enumerate((76, 83, 90)):
        mix(b, bell(0.85, midi(n), 0.22, inharm=1.6),
            offset=int((0.26 + i * 0.10) * SR))
    return room(b, wet=0.46, size=0.92, damp=0.24, tail=1.2)


def sfx_quest(rng):
    b = buf(1.5)
    for t, n in ((0.0, 62), (0.17, 69), (0.34, 74), (0.52, 78)):
        mix(b, brass(0.55, midi(n), 0.26), offset=int(t * SR))
    mix(b, brass(0.7, midi(50), 0.16, detune=8.0), offset=int(0.52 * SR))
    mix(b, sub(0.6, midi(38), 0.26, 2.0), offset=int(0.5 * SR))
    S.softclip(b, 1.2)
    return spread_room(b, wet=0.32, size=0.86, damp=0.34, tail=1.0)


def sfx_pickup(rng):
    b = buf(0.35)
    mix(b, pluck(0.22, midi(76), 0.30, damp=0.85, bright=0.8, rng=rng))
    mix(b, bell(0.3, midi(88), 0.16), offset=int(0.06 * SR))
    return room(b, wet=0.20, size=0.66, damp=0.45, tail=0.3)


def sfx_rest(rng):
    b = buf(2.0)
    for i, n in enumerate((53, 60, 65)):                          # settling chord
        mix(b, tone(1.5, midi(n), amp=0.14, kind="tri", decay=1.3, attack=0.12),
            offset=int(i * 0.20 * SR))
    mix(b, wind(1.9, 0.07, 480.0, 0.9, rate=1.0, rng=rng))        # campfire air
    mix(b, noise(0.05, 0.06, 30.0, 2400.0, 0.9, rng=rng), offset=int(0.7 * SR))
    return room(b, wet=0.36, size=0.90, damp=0.45, tail=1.1)


def spread_room(mono, wet, size, damp, tail):
    """Wide + wet: Haas on the dry, stereo reverb around it. The fanfares."""
    n = len(mono) + int(tail * SR)
    dry = mono + [0.0] * (n - len(mono))
    l, r = spread(dry)
    S.reverb_into(l, r, dry, wet, size, damp, 1.0)
    return [l, r]


SFX = {
    "hit": sfx_hit, "crit": sfx_crit, "kill": sfx_kill, "cast": sfx_cast,
    "heal": sfx_heal, "level_up": sfx_level_up, "victory": sfx_victory,
    "defeat": sfx_defeat, "click": sfx_click, "buy": sfx_buy,
    "identify": sfx_identify, "quest": sfx_quest, "pickup": sfx_pickup,
    "rest": sfx_rest,
}

# --- ambient beds ----------------------------------------------------------
#
# 8 second loops. The old beds were one held chord plus a few plucks; these are
# a 4-chord progression with a bass, a pad, a lead voice and per-theme texture,
# rendered LOOP + TAIL long and then folded back on themselves (S.wrap_tail) so
# the reverb and the last chord's release are already ringing when the loop
# restarts. That fold is the whole trick: it is what allows a wet, evolving bed
# to loop without a click or a pumping swell at the seam.
#
# Anything periodic (tremolo, wind swell) must complete whole cycles across the
# loop, and any held tone uses S.loop_freq, for the same reason.

LOOP = 8.0            # seconds per bed; --loop overrides
TAIL = 2.0            # rendered past the loop, then folded back in
XF = 0.6              # chord-to-chord crossfade


def _pan(pan):
    """Constant-power pan: -1 hard left, 0 centre, +1 hard right."""
    a = (pan + 1.0) * 0.25 * math.pi
    return math.cos(a), math.sin(a)


class Bed:
    """A stereo canvas plus a mono reverb send, sized LOOP + TAIL."""

    def __init__(self):
        self.n = int((LOOP + TAIL) * SR)
        self.l = [0.0] * self.n
        self.r = [0.0] * self.n
        self.send = [0.0] * self.n

    def put(self, mono, at=0.0, pan=0.0, gain=1.0, send=0.7):
        gl, gr = _pan(pan)
        gl *= gain
        gr *= gain
        gs = gain * send
        off = int(at * SR)
        n = self.n
        L, R, W = self.l, self.r, self.send
        for i, v in enumerate(mono):
            j = i + off
            if 0 <= j < n:
                L[j] += v * gl
                R[j] += v * gr
                W[j] += v * gs
        return self

    def finish(self, wet=0.34, size=0.90, damp=0.36, width=1.0):
        S.reverb_into(self.l, self.r, self.send, wet, size, damp, width)
        return S.wrap_tail([self.l, self.r], LOOP)


def chords(b, prog, amp=0.15, cutoff=1300.0, sweep=1.5, kind="saw",
           detune=9.0, pan=0.30, send=0.85):
    """Lay a chord progression down as overlapping, crossfaded pad blocks."""
    seg = LOOP / len(prog)
    for i, notes in enumerate(prog):
        block = pad(seg + XF, [midi(n) for n in notes], amp, cutoff, sweep,
                    kind, detune)
        S.fade_in(block, XF if i else 0.05)
        S.fade_out(block, XF)
        # alternate the stack slightly left/right so the progression moves
        b.put(block, i * seg, pan * (1 if i % 2 == 0 else -1), send=send)
    return b


def bassline(b, prog, octave=-24, amp=0.34, decay=1.6, send=0.25):
    """Root note per chord, as a clean sine sub."""
    seg = LOOP / len(prog)
    for i, notes in enumerate(prog):
        b.put(sub(seg * 0.95, midi(notes[0] + octave), amp, decay),
              i * seg, 0.0, send=send)
    return b


def arp(b, prog, pattern, amp=0.20, octave=12, dur=0.55, damp=0.85,
        bright=0.6, pan=0.25, send=0.6, rng=None):
    """Plucked arpeggio over the progression. `pattern` indexes into the chord."""
    seg = LOOP / len(prog)
    step = seg / len(pattern)
    for i, notes in enumerate(prog):
        for k, sel in enumerate(pattern):
            if sel is None:
                continue
            n = notes[sel % len(notes)] + octave + 12 * (sel // len(notes))
            b.put(pluck(dur, midi(n), amp, damp, bright, rng=rng),
                  i * seg + k * step,
                  pan * (1.0 if k % 2 else -1.0), send=send)
    return b


# theme -> builder. Each is a short arrangement, not a preset.

def bed_sunken_shrine(rng):
    b = Bed()
    prog = [[50, 57, 62, 65], [46, 53, 58, 62]]          # Dm -> Bb, slow and wet
    chords(b, prog, amp=0.13, cutoff=620.0, sweep=1.7, detune=11.0)
    bassline(b, prog, -26, 0.36, 1.1)
    for i, n in enumerate((74, 81)):                      # far-off temple bell
        b.put(bell(3.4, midi(n), 0.10, inharm=2.2), 1.2 + i * 3.6,
              -0.4 + 0.8 * i, send=1.0)
    for t, p in ((0.9, 0.6), (2.7, -0.5), (4.4, 0.3), (6.1, -0.7), (7.3, 0.5)):
        b.put(noise(0.05, 0.13, 34.0, 2100.0 + rng.random() * 1500.0, 2.2, "bp",
                    rng=rng), t, p, send=1.0)             # drips
    b.put(wind(LOOP + TAIL, 0.05, 320.0, 0.8, rate=0.25, rng=rng), 0.0, 0.0,
          send=0.5)
    return b.finish(wet=0.52, size=0.94, damp=0.22)


def bed_goblin_camp(rng):
    b = Bed()
    prog = [[52, 59, 64, 67], [52, 59, 64, 67], [50, 57, 62, 65], [52, 59, 64, 67]]
    chords(b, prog, amp=0.10, cutoff=900.0, sweep=1.3, kind="pulse", detune=14.0)
    bassline(b, prog, -24, 0.30, 2.2)
    beat = LOOP / 16.0                                    # scrappy hand percussion
    for i in range(16):
        t = i * beat
        if i % 4 == 0:
            b.put(tom(150.0, 0.42, rng=rng), t, -0.15, send=0.3)
        elif i % 4 == 2:
            b.put(tom(205.0, 0.30, rng=rng), t, 0.25, send=0.3)
        if i % 2 == 1:
            b.put(noise(0.05, 0.11, 30.0, 5200.0, 1.1, "hp", rng=rng),
                  t, 0.45 if i % 4 == 1 else -0.45, send=0.25)
    for i, n in enumerate((64, 67, 71, 67, 64, 62)):      # crude pipe melody
        b.put(tone(0.30, midi(n), amp=0.13, kind="pulse", decay=5.0,
                   attack=0.012), 0.55 + i * 1.2, 0.2, send=0.6)
    return b.finish(wet=0.26, size=0.74, damp=0.42)


def bed_city_square(rng):
    b = Bed()
    prog = [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
    chords(b, prog, amp=0.12, cutoff=1500.0, sweep=1.4, detune=8.0)
    bassline(b, prog, -24, 0.30, 1.9)
    arp(b, prog, (0, 2, 1, 3), amp=0.17, octave=12, dur=0.7, rng=rng)
    for i in range(4):                                    # a hand drum, market-ish
        b.put(tom(170.0, 0.22, rng=rng), i * 2.0, -0.2, send=0.25)
        b.put(noise(0.05, 0.07, 30.0, 6200.0, 1.0, "hp", rng=rng),
              i * 2.0 + 1.0, 0.35, send=0.25)
    return b.finish(wet=0.30, size=0.80, damp=0.40)


def bed_forest_clearing(rng):
    b = Bed()
    prog = [[43, 50, 55, 59], [45, 52, 57, 62], [40, 47, 52, 59], [43, 50, 55, 59]]
    chords(b, prog, amp=0.12, cutoff=1150.0, sweep=1.6, detune=7.0)
    bassline(b, prog, -24, 0.26, 1.5)
    arp(b, prog, (0, None, 2, 3), amp=0.15, octave=24, dur=0.85, damp=0.92,
        bright=0.75, rng=rng)
    b.put(wind(LOOP + TAIL, 0.06, 900.0, 0.7, rate=0.5, rng=rng), 0.0, 0.0,
          send=0.6)
    for t, n, p in ((1.4, 92, 0.6), (3.1, 96, -0.55), (5.6, 89, 0.45),
                    (6.9, 95, -0.3)):                     # birds
        b.put(tone(0.10, midi(n), midi(n + 5), 0.09, "sine", 14.0, 0.004), t, p,
              send=0.8)
    return b.finish(wet=0.38, size=0.86, damp=0.30)


def bed_frozen_cave(rng):
    b = Bed()
    prog = [[47, 54, 59, 62], [45, 52, 57, 61]]           # Bm -> A, vast and still
    chords(b, prog, amp=0.11, cutoff=700.0, sweep=1.8, detune=12.0)
    bassline(b, prog, -26, 0.32, 0.9)
    for i, n in enumerate((83, 86, 90, 88)):              # ice bells, far apart
        b.put(bell(2.6, midi(n), 0.13, inharm=2.6), 0.7 + i * 1.9,
              (-1) ** i * 0.5, send=1.0)
    b.put(wind(LOOP + TAIL, 0.08, 1500.0, 0.6, rate=0.375, rng=rng), 0.0, 0.0,
          send=0.7)
    return b.finish(wet=0.58, size=0.96, damp=0.18)


def bed_merchant_shop(rng):
    b = Bed()
    prog = [[53, 60, 65, 69], [48, 55, 60, 64], [50, 57, 62, 65], [46, 53, 58, 62]]
    chords(b, prog, amp=0.11, cutoff=1700.0, sweep=1.3, detune=7.0)
    bassline(b, prog, -24, 0.26, 2.1)
    arp(b, prog, (0, 1, 2, 1), amp=0.18, octave=12, dur=0.5, damp=0.8,
        bright=0.7, rng=rng)
    for i, n in enumerate((84, 88)):                      # shop bell
        b.put(bell(1.2, midi(n), 0.11, inharm=1.4), 0.3 + i * 4.0, 0.4, send=0.9)
    return b.finish(wet=0.24, size=0.68, damp=0.45)


def bed_settlement(rng):
    b = Bed()
    prog = [[48, 55, 60, 64], [43, 50, 55, 59], [45, 52, 57, 60], [41, 48, 53, 57]]
    chords(b, prog, amp=0.13, cutoff=1300.0, sweep=1.4, detune=8.0)
    bassline(b, prog, -24, 0.28, 1.7)
    arp(b, prog, (0, 2, None, 1), amp=0.15, octave=12, dur=0.8, damp=0.9,
        bright=0.5, rng=rng)
    return b.finish(wet=0.34, size=0.84, damp=0.38)


def bed_title(rng):
    b = Bed()
    prog = [[38, 45, 50, 57], [43, 50, 55, 62]]           # big, open, heroic
    chords(b, prog, amp=0.13, cutoff=1100.0, sweep=1.7, detune=13.0)
    bassline(b, prog, -24, 0.36, 0.8)
    for i, n in enumerate((62, 69, 74)):                  # slow horn swell
        b.put(brass(2.6, midi(n), 0.13, detune=14.0, cutoff=1900.0),
              0.6 + i * 0.25, -0.3 + 0.3 * i, send=0.9)
    for i, n in enumerate((81, 86, 93)):
        b.put(bell(3.0, midi(n), 0.12, inharm=1.8), 4.3 + i * 0.5,
              (-1) ** i * 0.45, send=1.0)
    return b.finish(wet=0.46, size=0.93, damp=0.28)


def bed_tension(rng):
    """The combat layer. It plays *on top of* whichever theme bed is running, so
    it stays harmonically neutral -- root and fifth, percussion-led -- instead of
    laying a second chord progression over the first."""
    b = Bed()
    beat = LOOP / 16.0
    ost = (33, 33, 40, 33, 36, 36, 31, 38, 33, 33, 40, 33, 38, 38, 36, 31)
    for i in range(16):
        t = i * beat
        if i % 4 == 0:
            b.put(kick(0.62, rng=rng), t, 0.0, send=0.18)
        if i % 8 == 4:
            b.put(snare(0.38, rng=rng), t, -0.1, send=0.35)
        b.put(hat(0.13 if i % 2 else 0.07, 0.05, rng=rng), t,
              0.4 if i % 2 else -0.4, send=0.2)
        b.put(tone(beat * 0.85, midi(ost[i]), amp=0.26, kind="saw", decay=4.2,
                   attack=0.003, detune=10.0), t, 0.0, send=0.2)
    for i in range(4):                                    # stab on the downbeats
        b.put(tone(0.5, midi(57), amp=0.10, kind="pulse", decay=6.0,
                   attack=0.01), i * 2.0, (-1) ** i * 0.35, send=0.7)
    return b.finish(wet=0.20, size=0.70, damp=0.48)


BEDS = {
    "sunken-shrine": bed_sunken_shrine,
    "goblin-camp": bed_goblin_camp,
    "city-square": bed_city_square,
    "forest-clearing": bed_forest_clearing,
    "frozen-cave": bed_frozen_cave,
    "merchant-shop": bed_merchant_shop,
    "settlement": bed_settlement,
    "title": bed_title,
    "tension": bed_tension,
}

# --- T31 bark stingers -----------------------------------------------------
#
# Wordless on purpose: core/barks.gd picks the *text* bark at random, so any
# fixed spoken line would sooner or later contradict the line on screen. What
# changed from the first pass is the source -- a glottal pulse through an
# F1/F2/F3 formant bank (synth.syllable) rather than a pitched sine, so these
# read as a creature saying something rather than as a blip.
#
# archetype -> root midi, syllables, syllable secs, gap, formant shift,
#              breath, growl drive, vowel pool
VOICES = {
    "hero":   (60, 4, 0.115, 0.025, 1.00, 0.05, 1.0, "aeiE"),
    "gruff":  (46, 3, 0.150, 0.035, 0.88, 0.10, 2.2, "aoU"),
    "squeak": (74, 5, 0.075, 0.018, 1.45, 0.04, 1.0, "iea"),
    "deep":   (36, 3, 0.200, 0.045, 0.72, 0.07, 1.6, "oUa"),
}
_VOWEL = {"a": "a", "e": "e", "i": "i", "o": "o", "U": "u", "E": "ae"}
SCALE = (0, 2, 3, 5, 7, 10)          # any step off this reads as deliberate
BARK_VARIANTS = 3


def gibberish(voice, variant):
    root, count, dur, gap, shift, breath, drive, pool = VOICES[voice]
    rng = random.Random("%s-%d-v2" % (voice, variant))
    total = count * (dur + gap) + 0.5
    b = buf(total)
    t = 0.0
    step = rng.randrange(len(SCALE))
    for i in range(count):
        step = max(0, min(len(SCALE) - 1, step + rng.choice((-2, -1, 1, 1, 2))))
        last = i == count - 1
        n = root + SCALE[step]
        # exclamations fall at the end; a rise would read as a question
        bend = n - rng.choice((2, 3, 5)) if last else n + rng.choice((-2, 0, 0, 2))
        v = _VOWEL[rng.choice(pool)]
        syl = S.syllable(dur * (1.25 if last else 1.0), midi(n), midi(bend), v,
                         shift=shift, breath=breath,
                         plosive=(i == 0 or rng.random() < 0.4), rng=rng)
        mix(b, syl, gain=0.5, offset=int(t * SR))
        t += dur + gap
    if drive > 1.0:                       # growl on the low/rough archetypes
        S.softclip(b, drive)
    Biquad("hp", 130.0 * shift, 0.7).run(b)    # no mud under the voice
    b = S.trim_silence(b, 0.002, 0.05)
    S.fade_out(b, 0.02)
    return room(b, wet=0.16, size=0.60, damp=0.5, tail=0.22)


# --- drivers ---------------------------------------------------------------

def _sfx_jobs():
    for name in sorted(SFX):
        yield ("sfx", os.path.join("assets", "audio", "sfx", name + ".wav"),
               lambda n=name: SFX[n](random.Random("sfx-" + n)))


def _music_jobs():
    for name in sorted(BEDS):
        yield ("music", os.path.join("assets", "audio", "music", name + ".wav"),
               lambda n=name: BEDS[n](random.Random("bed-" + n)))


def _bark_jobs():
    for voice in sorted(VOICES):
        for v in range(1, BARK_VARIANTS + 1):
            yield ("barks",
                   os.path.join("assets", "audio", "barks",
                                "%s%d.wav" % (voice, v)),
                   lambda vo=voice, i=v: gibberish(vo, i))


GROUPS = {"sfx": _sfx_jobs, "music": _music_jobs, "barks": _bark_jobs}


def _flag(argv, name, cast, default):
    if name not in argv:
        return default
    i = argv.index(name)
    if i + 1 >= len(argv):
        sys.exit("%s needs a value" % name)
    return cast(argv[i + 1])


def main(argv):
    global SR, LOOP
    rate = _flag(argv, "--rate", int, S.SR)
    loop = _flag(argv, "--loop", float, LOOP)
    SR = S.set_rate(rate)          # synth reads its own SR; keep ours in step
    LOOP = loop
    skip = {"--rate", "--loop"}
    argv = [a for i, a in enumerate(argv)
            if a not in skip and (i == 0 or argv[i - 1] not in skip)]
    want = [a for a in argv if not a.startswith("-")] or list(GROUPS)
    bad = [w for w in want if w not in GROUPS]
    if bad:
        sys.exit("unknown group(s): %s (have: %s)"
                 % (", ".join(bad), ", ".join(sorted(GROUPS))))
    jobs = [j for w in want for j in GROUPS[w]()]
    if "--list" in argv:
        for _, path, _ in jobs:
            print(path)
        return
    total = 0
    for group, path, make in jobs:
        chans = make()
        size = S.write_wav(os.path.join(ROOT, path), chans)
        total += size
        print("  %-34s %s %5.2fs %7.1f KB"
              % (path, "stereo" if len(chans) == 2 else "mono  ",
                 len(chans[0]) / SR, size / 1024.0))
    print("wrote %d files, %.1f MB at %d Hz (beds %.1fs)"
          % (len(jobs), total / 1048576.0, SR, LOOP))


if __name__ == "__main__":
    main(sys.argv[1:])

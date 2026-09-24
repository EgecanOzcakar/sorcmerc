#!/usr/bin/env python3
"""Generated audio for sorcmerc (T27 sound + T31 barks).

    python3 tools/gen_audio.py            # everything
    python3 tools/gen_audio.py sfx barks  # just those groups
    python3 tools/gen_audio.py --list     # what would be written
    python3 tools/gen_audio.py --only miss,down         # just those two
    python3 tools/gen_audio.py --only sfx/settlement    # when a name spans groups
    python3 tools/gen_audio.py --rate 44100 --loop 12   # bigger, longer

`--only` matters more than it looks: nothing in assets/audio/ is this file's
output any more. The stings and barks are tools/gen_audio_elevenlabs.py's
takes and the beds are tools/gen_music_elevenlabs.py's (docs/audio-pass.md),
so a bare `gen_audio.py` overwrites all of it with the offline fallback. Name
the sounds you actually want synthesized back.

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


# --- T9z: one hit sound per weapon class -----------------------------------
#
# core/weapon_sfx.gd picks one of these off the attacker's main-hand weapon
# (or, for a monster, off what kind of wound it deals). The shared vocabulary:
# a `swing` is the air the weapon moves before it lands (a rising-then-falling
# filtered noise), the impact is a noise burst + a body thud, and only edged
# metal gets a `metal()` ring after it. Blunt and natural attacks get none — a
# club against mail thumps, it doesn't sing.

def swing(dur, amp=0.22, f0=900.0, f1=2600.0, rng=None):
    """Whoosh: bandpassed noise whose centre sweeps up as the swing accelerates."""
    rng = rng or random
    n = max(1, int(dur * SR))
    out = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    S.sweep_lp(out, f0, f1, q=2.2)
    env = adsr(n, a=dur * 0.55, d=dur * 0.15, s=0.35, r=dur * 0.3)
    for i in range(n):
        out[i] *= amp * env[i]
    return out


def sfx_hit_sword(rng):
    b = buf(0.36)
    mix(b, swing(0.09, 0.20, 700.0, 3200.0, rng=rng))
    mix(b, noise(0.035, 0.5, 40.0, 3800.0, 0.9, rng=rng), offset=int(0.085 * SR))
    mix(b, metal(0.26, 1700.0, 0.36, rng=rng), offset=int(0.085 * SR))   # bright blade ring
    mix(b, tone(0.08, 240.0, 90.0, 0.35, "tri", 24.0, 0.001), offset=int(0.085 * SR))
    S.softclip(b, 1.5)
    return room(b, wet=0.14, size=0.62, damp=0.55, tail=0.3)


def sfx_hit_axe(rng):
    b = buf(0.36)
    mix(b, swing(0.11, 0.24, 400.0, 1800.0, rng=rng))                     # heavier, slower swing
    mix(b, noise(0.05, 0.6, 30.0, 1900.0, 0.8, rng=rng), offset=int(0.10 * SR))
    mix(b, metal(0.14, 900.0, 0.22, rng=rng), offset=int(0.10 * SR))     # a short, dull ring
    mix(b, tone(0.12, 160.0, 55.0, 0.5, "tri", 18.0, 0.001), offset=int(0.10 * SR))
    mix(b, sub(0.18, 55.0, 0.30, 7.0), offset=int(0.10 * SR))           # the chop lands
    S.softclip(b, 1.7)
    return room(b, wet=0.12, size=0.60, damp=0.6, tail=0.3)


def sfx_hit_blunt(rng):
    b = buf(0.34)
    mix(b, swing(0.10, 0.18, 300.0, 1200.0, rng=rng))
    mix(b, noise(0.06, 0.5, 24.0, 1100.0, 0.8, rng=rng), offset=int(0.095 * SR))
    mix(b, tone(0.14, 130.0, 45.0, 0.55, "tri", 14.0, 0.001), offset=int(0.095 * SR))
    mix(b, tom(110.0, 0.4, rng=rng), offset=int(0.095 * SR))              # no ring: a thump
    mix(b, sub(0.2, 48.0, 0.32, 6.0), offset=int(0.095 * SR))
    S.softclip(b, 1.8)
    return room(b, wet=0.12, size=0.60, damp=0.65, tail=0.3)


def sfx_hit_pierce(rng):
    b = buf(0.26)
    mix(b, swing(0.06, 0.16, 1200.0, 4200.0, rng=rng))                    # quick, thin
    mix(b, noise(0.025, 0.45, 55.0, 5200.0, 1.0, "hp", rng=rng), offset=int(0.055 * SR))
    mix(b, metal(0.16, 2600.0, 0.26, rng=rng), offset=int(0.055 * SR))   # high, brief "shink"
    mix(b, tone(0.06, 300.0, 120.0, 0.25, "tri", 30.0, 0.001), offset=int(0.055 * SR))
    S.softclip(b, 1.4)
    return room(b, wet=0.12, size=0.58, damp=0.55, tail=0.22)


def sfx_hit_bow(rng):
    b = buf(0.55)
    # the string: a tight pluck at the release, then the arrow's flight, then it lands
    mix(b, pluck(0.14, 220.0, 0.28, damp=0.35, bright=0.9, rng=rng))
    mix(b, noise(0.02, 0.25, 70.0, 3000.0, 1.0, "bp", rng=rng))            # snap of the release
    flight = noise(0.22, 0.14, 4.0, 5000.0, 0.6, "hp", rng=rng)
    S.sweep_lp(flight, 8000.0, 2500.0, q=1.4)                             # doppler-ish fall
    mix(b, flight, offset=int(0.06 * SR))
    mix(b, noise(0.03, 0.45, 40.0, 2200.0, 0.9, rng=rng), offset=int(0.30 * SR))
    mix(b, tone(0.10, 200.0, 70.0, 0.4, "tri", 20.0, 0.001), offset=int(0.30 * SR))   # thunk
    S.softclip(b, 1.4)
    return room(b, wet=0.16, size=0.68, damp=0.5, tail=0.35)


def sfx_hit_thrown(rng):
    b = buf(0.5)
    flight = noise(0.26, 0.20, 3.0, 4000.0, 0.7, "bp", rng=rng)
    S.sweep_lp(flight, 1200.0, 3600.0, q=1.6)                             # rising whoosh
    mix(b, flight)
    mix(b, noise(0.035, 0.45, 38.0, 2400.0, 0.9, rng=rng), offset=int(0.27 * SR))
    mix(b, tone(0.10, 220.0, 80.0, 0.4, "tri", 20.0, 0.001), offset=int(0.27 * SR))
    S.softclip(b, 1.4)
    return room(b, wet=0.14, size=0.64, damp=0.55, tail=0.3)


def sfx_hit_claw(rng):
    b = buf(0.34)
    # a tearing rake: three fast staggered scratches, no metal anywhere
    for i in range(3):
        mix(b, noise(0.05, 0.42, 34.0, 2600.0 + i * 500.0, 1.3, "bp", rng=rng),
            offset=int(i * 0.035 * SR))
    mix(b, tone(0.10, 180.0, 70.0, 0.3, "tri", 20.0, 0.001), offset=int(0.04 * SR))
    S.softclip(b, 1.5)
    return room(b, wet=0.12, size=0.6, damp=0.6, tail=0.25)


def sfx_hit_bite(rng):
    b = buf(0.3)
    mix(b, noise(0.02, 0.5, 60.0, 4200.0, 1.0, "bp", rng=rng))              # snap
    mix(b, noise(0.07, 0.4, 22.0, 900.0, 0.8, rng=rng), offset=int(0.02 * SR))   # crunch
    mix(b, tone(0.12, 150.0, 60.0, 0.45, "tri", 16.0, 0.001), offset=int(0.02 * SR))
    mix(b, sub(0.15, 60.0, 0.25, 8.0), offset=int(0.02 * SR))
    S.softclip(b, 1.7)
    return room(b, wet=0.12, size=0.6, damp=0.6, tail=0.25)


def sfx_hit_slam(rng):
    b = buf(0.4)
    mix(b, swing(0.12, 0.16, 200.0, 900.0, rng=rng))
    mix(b, noise(0.08, 0.45, 18.0, 800.0, 0.8, rng=rng), offset=int(0.11 * SR))
    mix(b, tone(0.18, 110.0, 40.0, 0.5, "tri", 12.0, 0.001), offset=int(0.11 * SR))
    mix(b, kick(0.5, rng=rng), offset=int(0.11 * SR))
    mix(b, sub(0.26, 42.0, 0.38, 5.0), offset=int(0.11 * SR))
    S.softclip(b, 1.8)
    return room(b, wet=0.14, size=0.66, damp=0.65, tail=0.35)


# --- T9z: one cast sound per school of magic -------------------------------
#
# core/weapon_sfx.gd picks one off data/spells.json's `school`. Each keeps the
# generic cast's wide, wet room but changes what happens inside it: evocation
# is force and heat, abjuration a held ward, necromancy a drone, and so on.

def sfx_cast_evocation(rng):
    b = buf(0.9)
    sweep = tone(0.4, 200.0, 1400.0, 0.30, "saw", 2.0, 0.03, detune=18.0)
    S.sweep_lp(sweep, 500.0, 7000.0, q=1.8)
    mix(b, sweep)
    mix(b, noise(0.30, 0.34, 9.0, 3000.0, 0.7, rng=rng), offset=int(0.28 * SR))  # the burst
    mix(b, sub(0.5, 50.0, 0.42, 3.5), offset=int(0.28 * SR))                    # the boom
    mix(b, noise(0.5, 0.10, 3.0, 6500.0, 0.7, "hp", rng=rng), offset=int(0.32 * SR))  # crackle tail
    S.softclip(b, 1.5)
    return room(b, wet=0.40, size=0.88, damp=0.3, tail=1.0)


def sfx_cast_abjuration(rng):
    b = buf(1.1)
    # a ward going up: a bright chime, then a held, slowly-swelling hum under it
    mix(b, bell(0.7, midi(84), 0.22, inharm=1.2))
    mix(b, bell(0.7, midi(91), 0.14, inharm=1.2), offset=int(0.05 * SR))
    hum = tone(0.9, midi(60), amp=0.16, kind="tri", decay=0.9, attack=0.30, detune=8.0)
    mix(b, hum, offset=int(0.10 * SR))
    mix(b, tone(0.9, midi(67), amp=0.10, kind="sine", decay=0.9, attack=0.35), offset=int(0.10 * SR))
    mix(b, noise(0.4, 0.08, 4.0, 7500.0, 0.7, "hp", rng=rng), offset=int(0.15 * SR))
    return room(b, wet=0.44, size=0.90, damp=0.28, tail=1.1)


def sfx_cast_conjuration(rng):
    b = buf(1.1)
    # something arriving: a downward filtered swell like a portal opening, wind around it
    swell = tone(0.7, 900.0, 220.0, 0.28, "saw", 1.4, 0.18, detune=22.0)
    S.sweep_lp(swell, 5000.0, 600.0, q=1.5)
    mix(b, swell)
    mix(b, wind(0.9, 0.16, 600.0, 1.1, rate=2.0, rng=rng))
    mix(b, noise(0.06, 0.32, 24.0, 2400.0, 0.9, rng=rng), offset=int(0.62 * SR))  # it lands
    mix(b, sub(0.4, 55.0, 0.30, 4.0), offset=int(0.62 * SR))
    S.softclip(b, 1.3)
    return room(b, wet=0.44, size=0.92, damp=0.32, tail=1.1)


def sfx_cast_enchantment(rng):
    b = buf(1.1)
    # a charm: a soft, dreamy descending bell run, widened
    for i, n in enumerate((91, 88, 84, 79, 76)):
        mix(b, bell(0.6, midi(n), 0.16, inharm=1.05), offset=int(i * 0.09 * SR))
        mix(b, pluck(0.45, midi(n - 12), 0.12, damp=0.9, bright=0.5, rng=rng),
            offset=int(i * 0.09 * SR))
    mix(b, noise(0.5, 0.06, 3.0, 8000.0, 0.7, "hp", rng=rng), offset=int(0.2 * SR))
    S.chorus(b, rate=0.4, depth_ms=8.0, mix_amt=0.5)
    return room(b, wet=0.48, size=0.92, damp=0.26, tail=1.2)


def sfx_cast_transmutation(rng):
    b = buf(1.0)
    # matter reshaping: a wobbling pitch that climbs, then settles, bubbling under it
    wob = tone(0.55, 320.0, 640.0, 0.24, "tri", 1.8, 0.05, detune=30.0)
    S.chorus(wob, rate=6.5, depth_ms=14.0, mix_amt=0.7)                   # the wobble
    mix(b, wob)
    for i in range(6):                                                     # bubbles
        f = 900.0 + rng.uniform(-300.0, 500.0)
        mix(b, tone(0.06, f, f * 1.6, 0.14, "sine", 26.0, 0.001), offset=int((0.1 + i * 0.08) * SR))
    mix(b, bell(0.5, midi(79), 0.16), offset=int(0.55 * SR))              # it settles
    return room(b, wet=0.40, size=0.88, damp=0.3, tail=1.0)


def sfx_cast_divination(rng):
    b = buf(1.2)
    # a glimpse of what's coming: a rising crystalline cluster with airy shimmer on top
    for i, n in enumerate((79, 84, 88, 91, 96)):
        mix(b, bell(0.8, midi(n), 0.16, inharm=1.4), offset=int(i * 0.07 * SR))
    shim = noise(0.8, 0.12, 2.5, 9000.0, 0.6, "hp", rng=rng)
    mix(b, shim, offset=int(0.1 * SR))
    mix(b, tone(0.9, midi(72), amp=0.08, kind="sine", decay=1.0, attack=0.3), offset=int(0.2 * SR))
    return room(b, wet=0.50, size=0.94, damp=0.22, tail=1.3)


def sfx_cast_illusion(rng):
    b = buf(1.1)
    # not quite there: a detuned, phasing pad that never fully lands, a whisper over it
    pad_ = tone(0.8, midi(64), amp=0.20, kind="saw", decay=1.2, attack=0.12, detune=40.0)
    S.sweep_lp(pad_, 3000.0, 900.0, q=1.2)
    S.chorus(pad_, rate=1.2, depth_ms=12.0, mix_amt=0.8)
    mix(b, pad_)
    mix(b, noise(0.7, 0.10, 2.0, 5500.0, 0.6, "hp", rng=rng), offset=int(0.1 * SR))
    mix(b, bell(0.5, midi(88), 0.10, inharm=2.2), offset=int(0.4 * SR))   # an off-key glint
    return room(b, wet=0.52, size=0.94, damp=0.3, tail=1.2)


def sfx_cast_necromancy(rng):
    b = buf(1.2)
    # death magic: a low drone bending down, a rasp of breath over it
    drone = tone(0.9, midi(40), midi(36), 0.30, "saw", 1.0, 0.08, detune=24.0)
    S.sweep_lp(drone, 900.0, 300.0, q=1.3)
    mix(b, drone)
    mix(b, sub(1.0, 36.0, 0.36, 1.6))
    mix(b, noise(0.8, 0.14, 2.0, 1400.0, 0.9, "bp", rng=rng), offset=int(0.1 * SR))  # the rasp
    mix(b, bell(0.6, midi(63), 0.12, inharm=2.6), offset=int(0.3 * SR))    # a wrong note
    S.softclip(b, 1.3)
    return room(b, wet=0.46, size=0.94, damp=0.5, tail=1.3)


# --- the silent moments ----------------------------------------------------
#
# Everything above fires when something LANDS. These are the swings that don't,
# the saves that hold, the hero who drops, and the world between fights -- all
# of which fired with no audio at all until now. tools/gen_audio_elevenlabs.py
# carries a prompt for each of these ids, so either tool can rewrite any of them.

def sfx_miss(rng):
    """Air, and deliberately nothing else -- no impact layer at all.

    Quieter and shorter than sfx_hit on purpose: this lands on roughly half of
    all attack rolls, and a miss as loud as a hit makes a fight sound like it is
    going twice as well as it is.
    """
    b = buf(0.26)
    mix(b, swing(0.20, 0.30, 700.0, 3200.0, rng=rng))
    mix(b, noise(0.05, 0.05, 30.0, 900.0, 0.7, "hp", rng=rng), offset=int(0.13 * SR))
    return room(b, wet=0.10, size=0.55, damp=0.62, tail=0.18)


def sfx_miss_ranged(rng):
    b = buf(0.5)
    # The whistle sweeps DOWN, not up: the shot is already past you and receding.
    fly = noise(0.16, 0.26, 6.0, 2600.0, 6.0, "bp", rng=rng)
    S.sweep_lp(fly, 4200.0, 1500.0, q=3.0)
    mix(b, fly)
    for i in range(3):                                            # skittering off stone
        mix(b, noise(0.035, 0.16 - i * 0.04, 55.0, 3000.0 + i * 700.0, 1.4, "bp", rng=rng),
            offset=int((0.20 + i * 0.045) * SR))
    return room(b, wet=0.24, size=0.80, damp=0.45, tail=0.4)


# A pair, written to read against each other -- the same moment resolving two
# ways. Made is bright and glances upward and off; failed is dull and sinks.
# Neither is a full sting: both ride under the spell that caused them, which is
# already making noise of its own.

def sfx_save_made(rng):
    b = buf(0.5)
    mix(b, metal(0.30, 3100.0, 0.26, rng=rng))
    mix(b, bell(0.40, midi(88), 0.18, inharm=1.3), offset=int(0.03 * SR))
    mix(b, tone(0.14, 900.0, 1800.0, 0.14, "tri", 14.0, 0.002))   # glancing away
    return room(b, wet=0.30, size=0.78, damp=0.34, tail=0.45)


def sfx_save_failed(rng):
    b = buf(0.6)
    mix(b, noise(0.07, 0.34, 20.0, 700.0, 0.7, rng=rng))
    mix(b, tone(0.26, 220.0, 70.0, 0.40, "tri", 8.0, 0.003, detune=12.0))
    mix(b, sub(0.40, 48.0, 0.34, 3.0))
    return room(b, wet=0.20, size=0.82, damp=0.66, tail=0.5)


def sfx_down(rng):
    """sfx_kill's shape without its finality.

    `down` was sfx_kill's asset until now, which made a hero dropping sound
    exactly like a foe dying. Same armour and body, but a softer attack, no
    sub-bass crash under it, and it settles rather than stops.
    """
    b = buf(0.75)
    mix(b, noise(0.09, 0.30, 16.0, 1200.0, 0.8, rng=rng))
    mix(b, tone(0.30, 180.0, 62.0, 0.34, "tri", 7.0, 0.006))
    mix(b, tom(150.0, 0.26, rng=rng), offset=int(0.05 * SR))
    for i in range(4):                                            # armour settling after
        mix(b, metal(0.13, 1700.0 + i * 430.0, 0.10, rng=rng),
            offset=int((0.16 + i * 0.055) * SR))
    return room(b, wet=0.24, size=0.84, damp=0.58, tail=0.55)


def sfx_burst(rng):
    b = buf(0.8)
    mix(b, noise(0.14, 0.60, 14.0, 2600.0, 0.6, rng=rng))         # the blast
    mix(b, kick(0.6, rng=rng))                                    # the thump under it
    mix(b, sub(0.45, 52.0, 0.46, 3.2))
    for i in range(6):                                            # splintering staves
        mix(b, noise(0.03, 0.18, 70.0, 1400.0 + i * 520.0, 1.6, "bp", rng=rng),
            offset=int((0.05 + i * 0.038) * SR))
    S.softclip(b, 1.7)
    return room(b, wet=0.30, size=0.86, damp=0.44, tail=0.6)


def sfx_condition(rng):
    """Small on purpose: a status landing is frequent, so this is a marker under
    whatever caused it rather than an event of its own."""
    b = buf(0.5)
    warble = tone(0.34, 420.0, 190.0, 0.22, "saw", 5.0, 0.01, detune=28.0)
    S.sweep_lp(warble, 1800.0, 500.0, q=2.4)
    mix(b, warble)
    mix(b, noise(0.22, 0.07, 6.0, 1600.0, 2.2, "bp", rng=rng), offset=int(0.04 * SR))
    mix(b, bell(0.30, midi(58), 0.09, inharm=2.8), offset=int(0.10 * SR))
    return room(b, wet=0.28, size=0.80, damp=0.56, tail=0.4)


def sfx_collapse(rng):
    b = buf(1.2)
    mix(b, noise(0.12, 0.40, 13.0, 900.0, 0.7, rng=rng))
    mix(b, tone(0.38, 150.0, 45.0, 0.42, "tri", 5.0, 0.004))
    mix(b, sub(0.60, 40.0, 0.36, 2.0))
    mix(b, wind(0.75, 0.10, 620.0, 0.8, rate=1.2, rng=rng), offset=int(0.14 * SR))  # the exhale
    for i in range(5):                                            # metal settling
        mix(b, metal(0.16, 1500.0 + i * 380.0, 0.09, rng=rng),
            offset=int((0.22 + i * 0.085) * SR))
    return room(b, wet=0.30, size=0.88, damp=0.60, tail=0.8)


def sfx_travel(rng):
    b = buf(1.7)
    for i in range(5):                                            # five paces, uneven
        t = i * 0.30 + rng.uniform(-0.02, 0.02)
        mix(b, noise(0.06, 0.26, 34.0, 700.0 + rng.uniform(-120.0, 120.0), 0.8, rng=rng),
            offset=int(t * SR))
        mix(b, tone(0.09, 120.0, 60.0, 0.14, "tri", 20.0, 0.002), offset=int(t * SR))
        mix(b, noise(0.04, 0.05, 40.0, 3200.0, 1.1, "hp", rng=rng),   # leather creak
            offset=int((t + 0.03) * SR))
    return room(b, wet=0.22, size=0.86, damp=0.50, tail=0.5)


def sfx_settlement(rng):
    b = buf(2.1)
    creak = noise(0.7, 0.16, 1.6, 520.0, 3.4, "bp", rng=rng)      # the gate
    S.sweep_lp(creak, 420.0, 900.0, q=3.0)
    mix(b, creak)
    mix(b, wind(1.9, 0.09, 380.0, 0.7, rate=0.9, rng=rng))        # the crowd, as murmur
    mix(b, noise(0.10, 0.12, 24.0, 260.0, 0.7, rng=rng), offset=int(0.72 * SR))  # it thuds home
    mix(b, bell(1.1, midi(72), 0.11, inharm=1.2), offset=int(1.0 * SR))
    return spread_room(b, wet=0.38, size=0.92, damp=0.40, tail=1.0)


def sfx_shop(rng):
    b = buf(1.1)
    mix(b, noise(0.30, 0.13, 3.0, 600.0, 3.0, "bp", rng=rng))     # the door
    for i, n in enumerate((91, 95)):                              # the little bell
        mix(b, bell(0.55, midi(n), 0.17, inharm=1.5), offset=int((0.10 + i * 0.07) * SR))
    mix(b, noise(0.07, 0.10, 30.0, 900.0, 0.8, rng=rng), offset=int(0.34 * SR))  # it shuts
    return room(b, wet=0.30, size=0.74, damp=0.44, tail=0.6)


def sfx_quest_complete(rng):
    """sfx_quest is these same instruments ACCEPTING a quest; this is the phrase
    resolving -- it ends on the tonic rather than reaching for it, and the purse
    lands under the last note."""
    b = buf(1.9)
    for t, n in ((0.0, 67), (0.15, 71), (0.30, 74), (0.48, 79)):
        mix(b, brass(0.55, midi(n), 0.26), offset=int(t * SR))
    mix(b, brass(0.85, midi(55), 0.17, detune=8.0), offset=int(0.48 * SR))
    mix(b, sub(0.7, midi(43), 0.24, 1.8), offset=int(0.46 * SR))
    for i in range(5):                                            # the purse landing
        mix(b, metal(0.18, 2300.0 + i * 480.0, 0.15, rng=rng),
            offset=int((0.72 + i * 0.045) * SR))
    S.softclip(b, 1.2)
    return spread_room(b, wet=0.34, size=0.88, damp=0.34, tail=1.1)


def sfx_dice_rattle(rng):
    """A d20 thrown onto a table: one hard strike, then bounces that come quicker
    and quieter as it spins down, each a click of hard plastic on wood, and a
    last flutter as it rocks onto a face. scenes/dice_roll.gd plays it once as
    the tumble starts; the tumble used to tick the UI click on every face."""
    b = buf(1.0)
    t, gap, amp = 0.0, 0.11, 0.34
    for i in range(11):
        f = rng.uniform(2200.0, 3600.0)
        at = int(t * SR)
        mix(b, noise(0.018, amp, 70.0, f, 1.6, "bp", rng=rng), offset=at)
        mix(b, tone(0.03, f * 0.62, f * 0.55, amp * 0.45, "tri", 55.0, 0.0005), offset=at)
        if i < 3:                                                # the table answers the first few, low
            mix(b, tone(0.08, 180.0 - i * 20.0, 140.0, amp * 0.5, "sine", 30.0, 0.001), offset=at)
        t += gap * rng.uniform(0.75, 1.15)
        gap *= 0.82
        amp *= 0.8
    for _ in range(8):                                           # rocking onto its face
        mix(b, noise(0.008, amp * 0.6, 90.0, 3000.0, 1.8, "bp", rng=rng), offset=int(t * SR))
        t += 0.018
    return room(b, wet=0.16, size=0.60, damp=0.50, tail=0.3)


SFX = {
    "hit": sfx_hit, "crit": sfx_crit, "kill": sfx_kill, "cast": sfx_cast,
    "heal": sfx_heal, "level_up": sfx_level_up, "victory": sfx_victory,
    "defeat": sfx_defeat, "click": sfx_click, "buy": sfx_buy,
    "identify": sfx_identify, "quest": sfx_quest, "pickup": sfx_pickup,
    "rest": sfx_rest,
    # T9z: per-weapon-class hits, per-school casts (core/weapon_sfx.gd)
    "hit_sword": sfx_hit_sword, "hit_axe": sfx_hit_axe, "hit_blunt": sfx_hit_blunt,
    "hit_pierce": sfx_hit_pierce, "hit_bow": sfx_hit_bow, "hit_thrown": sfx_hit_thrown,
    "hit_claw": sfx_hit_claw, "hit_bite": sfx_hit_bite, "hit_slam": sfx_hit_slam,
    "cast_evocation": sfx_cast_evocation, "cast_abjuration": sfx_cast_abjuration,
    "cast_conjuration": sfx_cast_conjuration, "cast_enchantment": sfx_cast_enchantment,
    "cast_transmutation": sfx_cast_transmutation, "cast_divination": sfx_cast_divination,
    "cast_illusion": sfx_cast_illusion, "cast_necromancy": sfx_cast_necromancy,
    # The moments that used to fire silently: a swing that whiffs, a save either
    # way, a hero going down, a barrel going up, a status landing, and the world
    # between fights.
    "miss": sfx_miss, "miss_ranged": sfx_miss_ranged,
    "save_made": sfx_save_made, "save_failed": sfx_save_failed,
    "down": sfx_down, "burst": sfx_burst,
    "condition": sfx_condition, "collapse": sfx_collapse,
    "travel": sfx_travel, "settlement": sfx_settlement, "shop": sfx_shop,
    "quest_complete": sfx_quest_complete,
    # The live rolls' die (scenes/dice_roll.gd).
    "dice_rattle": sfx_dice_rattle,
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


# O-biome's two boards. Open country, which is the whole difference from
# bed_forest_clearing above: no canopy, so the reverb is wide and dry rather
# than close, and the wind carries instead of rustling.
def bed_downs(rng):
    b = Bed()
    prog = [[38, 45, 50, 57], [40, 47, 52, 59]]           # Dm -> Em, two chords, unhurried
    chords(b, prog, amp=0.10, cutoff=980.0, sweep=1.3, detune=9.0)
    bassline(b, prog, -24, 0.30, 2.2)
    b.put(wind(LOOP + TAIL, 0.11, 620.0, 0.5, rate=0.31, rng=rng), 0.0, 0.0, send=0.5)
    for t, n, p in ((2.2, 79, 0.7), (5.4, 76, -0.6), (9.1, 81, 0.4)):   # a curlew, far off
        b.put(tone(0.34, midi(n), midi(n - 7), 0.07, "sine", 6.0, 0.05), t, p, send=0.9)
    return b.finish(wet=0.42, size=0.94, damp=0.42)


# The one bed in assets/audio/music/ that is this file's own output rather than
# tools/gen_music_elevenlabs.py's, and the header above says why that matters:
# everything else there is an ElevenLabs take. This one is synthesized because
# the account's quota ran 20 credits short of it on 2026-09-22 (downs came back,
# marsh did not), and a board that ships silent fails tests/test_audio.gd. The
# prompt for it is in gen_music_elevenlabs.py's BEDS either way, so re-running
# `beds --only marsh` on a funded account replaces this with the same name.
def bed_marsh(rng):
    b = Bed()
    prog = [[45, 52, 57, 60], [43, 50, 55, 58]]           # Am -> Gm, damp and low
    chords(b, prog, amp=0.11, cutoff=620.0, sweep=1.1, detune=14.0)
    bassline(b, prog, -26, 0.30, 1.8)
    # Reeds: a narrower, hissier wind than the downs', and a second one panned
    # off it so the bed has width without anything in the middle to hear.
    b.put(wind(LOOP + TAIL, 0.09, 2600.0, 0.9, rate=0.22, rng=rng), 0.0, -0.4, send=0.35)
    b.put(wind(LOOP + TAIL, 0.07, 1900.0, 0.8, rate=0.17, rng=rng), 0.0, 0.45, send=0.35)
    for t, n, p in ((1.1, 34, -0.3), (4.7, 32, 0.35), (8.3, 35, -0.15)):   # frogs
        b.put(tone(0.22, midi(n), midi(n - 3), 0.16, "saw", 11.0, 0.006), t, p, send=0.5)
    for t, n, p in ((3.0, 71, 0.6), (7.2, 68, -0.55)):    # a wading bird, further off
        b.put(tone(0.18, midi(n), midi(n + 4), 0.06, "sine", 9.0, 0.02), t, p, send=1.0)
    return b.finish(wet=0.50, size=0.90, damp=0.52)


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
    "downs": bed_downs,
    "marsh": bed_marsh,
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
    only = _flag(argv, "--only", str, "")
    skip = {"--rate", "--loop", "--only"}
    argv = [a for i, a in enumerate(argv)
            if a not in skip and (i == 0 or argv[i - 1] not in skip)]
    want = [a for a in argv if not a.startswith("-")] or list(GROUPS)
    bad = [w for w in want if w not in GROUPS]
    if bad:
        sys.exit("unknown group(s): %s (have: %s)"
                 % (", ".join(bad), ", ".join(sorted(GROUPS))))
    jobs = [j for w in want for j in GROUPS[w]()]
    # --only, same spelling as tools/gen_audio_elevenlabs.py's. Load-bearing now
    # that assets/audio/ is a MIXED set: the stings are the ElevenLabs tool's and
    # the beds and barks are this one's, so a bare `gen_audio.py sfx` would
    # silently overwrite 31 generated takes with their synthesized versions.
    # Naming what you want back is how you rewrite one without touching the rest.
    if only:
        # A bare name is matched against every group, so it must be unambiguous:
        # `settlement` is BOTH a sfx sting and a music bed, and quietly writing
        # both because they share a basename is how you lose a bed you never
        # named. Qualify it as `sfx/settlement` to say which.
        by_name = {}
        for j in jobs:
            stem = os.path.splitext(os.path.basename(j[1]))[0]
            by_name.setdefault(stem, []).append(j)
            by_name.setdefault("%s/%s" % (j[0], stem), []).append(j)
        picked, seen = [], set()
        for w in (w.strip() for w in only.split(",")):
            if not w:
                continue
            if w not in by_name:
                sys.exit("no such sound: %s (have: %s)"
                         % (w, ", ".join(sorted(k for k in by_name if "/" not in k))))
            hits = by_name[w]
            if len(hits) > 1:
                sys.exit("%s is ambiguous — name one of: %s"
                         % (w, ", ".join(sorted("%s/%s" % (h[0],
                            os.path.splitext(os.path.basename(h[1]))[0]) for h in hits))))
            if hits[0][1] not in seen:
                seen.add(hits[0][1])
                picked.append(hits[0])
        jobs = picked
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

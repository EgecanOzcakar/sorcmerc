#!/usr/bin/env python3
"""tone_match() pulls a bright, thin take to the library balance, and leaves one
already there alone.   python3 tools/test_tone_match.py"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio_elevenlabs as g

random.seed(1)
noise = [random.uniform(-8000, 8000) for _ in range(g.SR)]   # white: ~half its energy above 11 kHz
air0 = g.band_share_db(noise, g.SR, "hp", g.AIR_HZ)
low0 = g.band_share_db(noise, g.SR, "lp", g.LOW_HZ)
once = g.tone_match(noise)
air1 = g.band_share_db(once, g.SR, "hp", g.AIR_HZ)
low1 = g.band_share_db(once, g.SR, "lp", g.LOW_HZ)
assert air1 < air0 - 10, (air0, air1)                       # the fizz band comes down hard
assert low1 > low0 + 3, (low0, low1)                        # and the bottom gets weight
# White noise is far past both caps, so it takes a few runs to arrive -- and
# once it has, another run leaves it exactly where it is.
there, runs = once, 1
while True:
    nxt = g.tone_match(there)
    if nxt == there:
        break
    there, runs = nxt, runs + 1
    assert runs <= 8, "tone_match never settles"
air2 = g.band_share_db(there, g.SR, "hp", g.AIR_HZ)
low2 = g.band_share_db(there, g.SR, "lp", g.LOW_HZ)
assert abs(air2 - g.AIR_TARGET_DB) < 2, air2                # at the target, not past it
assert abs(low2 - g.LOW_TARGET_DB) < 2, low2
print("ok  air %.1f -> %.1f dB, low %.1f -> %.1f dB, settled after %d runs" % (air0, air2, low0, low2, runs))

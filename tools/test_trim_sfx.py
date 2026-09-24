#!/usr/bin/env python3
"""trim_sfx keeps both halves of a two-part sound and the gap between them, and
drops the dead air, a faint precursor and an end blip.   python3 tools/test_trim_sfx.py"""
import array
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trim_sfx

RATE = 48000
ms = lambda t: int(RATE * t / 1000)


def tone(t_ms, amp):
    return [int(amp * math.sin(2 * math.pi * 440 * i / RATE)) for i in range(ms(t_ms))]


def silence(t_ms):
    return [0] * ms(t_ms)


# 300 ms dead air, a faint precursor (-30 dB), 1 s gap, whoosh (-6 dB), 400 ms gap,
# the hit, 500 ms dead air, a 5 ms blip (-40 dB), 100 ms dead air. Mono.
sig = (silence(300) + tone(50, 300) + silence(1000) + tone(100, 16000) + silence(400) +
       tone(120, 30000) + silence(500) + tone(5, 300) + silence(100))
out = trim_sfx.trim(array.array("h", sig), 1, RATE)
start, end, kept, dropped = trim_sfx.span(array.array("h", sig), 1, RATE)
assert len(kept) == 2 and len(dropped) == 2, (kept, dropped)       # whoosh + hit kept; precursor + blip gone
whoosh_at = ms(300 + 50 + 1000)
assert abs(start - (whoosh_at - ms(trim_sfx.LEAD_MS))) <= ms(trim_sfx.WINDOW_MS), start
expect = ms(trim_sfx.LEAD_MS) + ms(100 + 400 + 120) + ms(trim_sfx.TAIL_MS)
assert abs(len(out) - expect) <= 2 * ms(trim_sfx.WINDOW_MS), (len(out), expect)
gap = out[ms(trim_sfx.LEAD_MS) + ms(100) + ms(20):ms(trim_sfx.LEAD_MS) + ms(100) + ms(380)]
assert max(abs(v) for v in gap) == 0                                  # the gap between the parts is kept
assert out[0] == 0 and abs(out[-1]) < 300                             # faded in and out
print("ok  %d ms -> %d ms, 2 parts kept, precursor and blip dropped" % (len(sig) * 1000 // RATE, len(out) * 1000 // RATE))

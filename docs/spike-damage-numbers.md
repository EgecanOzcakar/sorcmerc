# Spike: the floating damage number

2026-09-17. Measurement only — nothing adopted here, no code changed.
Measured at `6be5970`.

From play, three lines of feedback on the same thing (Onat Cesur, 08:59):

> Hasar böyle kırmızı ve büyük — *damage [should be] red and big like this*
> Göze batan tarzda yazabilir — *it could be written in an eye-catching way*
> Veya daha uzun kalabilir — *or it could stay [on screen] longer*

Three asks: **colour**, **weight**, **duration**. This spike takes them at
face value and asks what is actually on screen today before anything is
retuned, because the obvious reading — "bump the font size, bump the TTL,
make it red" — turns out to fix the smallest of the four things wrong with
it.

The short version: **the board does not draw one damage number. It draws
between 12 and 39 of them, stacked on top of each other inside 11 pixels,
counting down from the real damage to `-0`, degrading from red to yellow
on the way.** The number the player's eye lands on — the newest, the
opaque one, the one on top — is `-0` in yellow. Everything below is
detail on that and on the three asks.

## 1. What the board draws today

`scenes/main.gd`, inner `Board` class. Three sites:

- **spawn** — `tick()`, lines 2186–2192, off the HP-bar lerp;
- **age/reap** — `tick()`, lines 2195–2197 (`age < 1.1`);
- **paint** — `_draw()`, lines 2708–2713.

```gd
# 2263
func _spawn_float(c, amount: float) -> void:
	var band := Color("ffd24a")
	if amount >= 12: band = Color("ff5a4a")
	elif amount >= 6: band = Color("ff9146")
	_floats.append({"pos": _pix(c.pos), "text": "-%d" % int(round(amount)), "color": band, "age": 0.0})

# 2708
for f in _floats:
	var col: Color = f.color
	col.a = 1.0 - f.age / 1.1
	draw_string(ThemeDB.fallback_font, f.pos + Vector2(-8, -(20.0 + f.age * 34.0)), f.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
```

Set against every other piece of text the board puts over a hex:

| text | painted on | size | scales with zoom | hold | fade | lifetime |
|---|---|---|---|---|---|---|
| **damage float** | **Board** (under the figures) | **18, literal** | **no** | **none** | 1.1s, linear from frame 0 | 1.1s |
| reveal headline (`HIT 7`) | Board | 26·fz, +35% punch-in | yes | 0.90s | 0.50s | 1.40s |
| reveal dice line | Board | 11·fz | yes | 0.90s | 0.50s | 1.40s |
| bark | HUD overlay | 14·fz | yes | 1.70s | 0.50s | 2.20s |
| odds chip | HUD overlay | 15–20·fz | yes | — | — | while aiming |
| HP `n/max` | HUD overlay | 11·fz | yes | — | — | persistent |
| condition tags | HUD overlay | 13·fz | yes | — | — | persistent |
| token glyph | Board | 24·fz | yes | — | — | persistent |

`fz = clampf(_zoom, 0.75, 1.7)`. The damage float is the only board text
that ignores it, so **zooming in to look at a fight makes the damage number
relatively smaller**: at max zoom the reveal headline is 44px and the damage
float is still 18. It is also the only transient text with no hold — it
begins fading on the frame it is born — and the only transient text still
painted on `Board` rather than on the HUD overlay (§4).

## 2. The cascade — the actual bug

`tick()` spawns the float as a side effect of animating the HP bar:

```gd
var k := clampf(dt * 12.0, 0.0, 1.0)            # 2159
...
var hv: float = _hp.get(c.id, float(c.hp))      # 2186
if absf(hv - c.hp) > 0.15:
	if hv > c.hp:
		_spawn_float(c, hv - c.hp)               # 2190  ← every frame
		_flash[c.id] = 0.35
	_hp[c.id] = lerpf(hv, float(c.hp), k)
```

`_hp[c.id]` is the *displayed* HP, eased toward the real value at `k` per
frame. The branch fires on every frame the bar is still catching up, so one
hit spawns one float **per frame until the bar closes**, each one carrying
the *remaining* gap, not the damage. At 60 fps, Normal pace, `k = 0.2`, so
the gap decays ×0.8 a frame and takes ~19 frames to drop under the `0.15`
cut-off.

A 14-damage hit, Normal pace, 60 fps, in the order drawn (oldest first =
furthest back; the last one is on top and fully opaque):

```
-14 -11 -9 -7 -6 -5 -4 -3 -2 -2 -2 -1 -1 -1 -1 -0 -0 -0 -0 -0 -0
 ^ red      ^ orange          ^ yellow ..................^ what you read
```

| damage | fps | floats | on-screen sequence | red | orange | yellow | seconds |
|---|---|---|---|---|---|---|---|
| 3 | 60 | 14 | `-3 -2 -2 -2 -1 -1 -1 -1 -1 -0 -0 -0 -0 -0` | 0 | 0 | 14 | 0.23 |
| 5 | 60 | 16 | `-5 -4 -3 -3 -2 -2 -1 -1 -1 -1 -1 -0 …` | 0 | 0 | 16 | 0.27 |
| 8 | 60 | 18 | `-8 -6 -5 -4 -3 -3 -2 -2 -1 -1 -1 -1 -1 -0 …` | 0 | 2 | 16 | 0.30 |
| 11 | 60 | 20 | `-11 -9 -7 -6 -5 -4 -3 -2 -2 -1 -1 -1 -1 -1 -0 …` | 0 | 3 | 17 | 0.33 |
| 14 | 60 | 21 | `-14 -11 -9 -7 -6 -5 -4 -3 -2 -2 -2 -1 -1 -1 -1 -0 …` | 1 | 3 | 17 | 0.35 |
| 22 | 60 | 23 | `-22 -18 -14 -11 -9 -7 -6 -5 -4 -3 -2 -2 -2 -1 …` | 3 | 3 | 17 | 0.38 |
| 40 | 60 | 26 | `-40 -32 -26 -20 -16 -13 -10 -8 -7 -5 -4 -3 -3 -2 …` | 6 | 3 | 17 | 0.43 |

**Finding F1 — the last five to eight floats of every hit read `-0`.**
`int(round(0.14))` is `0`, and the loop only stops once the gap is under
0.15. They are the newest, so they draw last, on top, at the highest alpha.
Whatever the damage was, the number sitting over the body at the end of the
animation is `-0`.

**Finding F2 — the colour band is computed from the shrinking gap, so every
hit fades red → orange → yellow regardless of how hard it landed.** A
40-damage hit is red for 6 frames (0.10s) and yellow for the remaining 17
(0.28s), at the higher alpha. The colour is not reporting the hit, it is
reporting how far the HP bar has left to travel.

**Finding F3 — they are stacked, not spread.** The rise is `20 + age·34`
px, so consecutive floats are `34·dt ≈ 0.57` px apart at 60 fps. All 21
land inside an 11.3 px band, drawn at 18 px, at the same `x`. It is not a
list of numbers; it is one smear of overlapping glyphs. (And `x` is
`pos.x - 8` — left-aligned with a fixed nudge rather than `_centered`, so
`-14`, `-1` and `-0` do not even share a centre line as they pile up.)

**Finding F4 — it gets worse the slower you play.** `tick()` is fed
`dt * _anim` (line 1675), so the pace setting scales `k`. The pace a player
picks *in order to watch blows land* is the one that shreds the number
hardest:

| pace | speed | k @60fps | floats for a 14-damage hit |
|---|---|---|---|
| Weighty | 0.55 | 0.11 | **39** |
| Measured | 0.75 | 0.15 | 28 |
| Normal | 1.00 | 0.20 | 21 |
| Brisk | 1.60 | 0.32 | 12 |
| Instant | 999 | 1.00 | **1** (correct, and invisible — the log is the fight) |

Frame rate does the same thing: the same hit is 9 floats at 30 fps and 53
at 144 fps. The number of damage numbers on screen is a function of the
player's monitor.

So of the three asks: the number is not big (18px, unscaled), not red
(§3), does not stay (1.1s, fading from frame 0) — and is not, on any frame,
a single legible number.

## 3. The colour bands, against the damage the game actually deals

`_spawn_float` cuts at absolute 12 and 6. Against the bestiary's authored
attack dice (exact pmf per body, no scaling applied):

| bestiary tier | bodies | mean hit | yellow <6 | orange 6–11 | red 12+ |
|---|---|---|---|---|---|
| CR 0–1/2 | 104 | 5.6 | 52% | 45% | 3% |
| CR 1–2 | 71 | 8.9 | 22% | 53% | 25% |
| CR 3–5 | 73 | 11.9 | 11% | 46% | 43% |
| CR 6–10 | 49 | 16.1 | 9% | 27% | 64% |

158 of 297 bodies with parseable damage can roll into red at all; the
median CR of one that can is 4.0. Early play is a yellow game.

Party side is worse, because the thresholds were never checked against a
d8:

| weapon | dice | +3 mod, mean | yellow <6 | orange 6–11 | red 12+ | red on a crit |
|---|---|---|---|---|---|---|
| Longsword | 1d8 | 7.5 | 25% | 75% | **0%** | 56% |
| Shortbow | 1d6 | 6.5 | 33% | 67% | **0%** | 28% |
| Mace | 1d6 | 6.5 | 33% | 67% | **0%** | 28% |
| Rapier | 1d8 | 7.5 | 25% | 75% | **0%** | 56% |
| Longbow | 1d8 | 7.5 | 25% | 75% | **0%** | 56% |
| Dagger | 1d4 | 5.5 | 50% | 50% | **0%** | 0% |
| Greataxe | 1d12 | 9.5 | 17% | 50% | 33% | 81% |
| Greatsword | 2d6 | 10.0 | 3% | 69% | 28% | 95% |

**Finding F5 — the preset party can never show a red number on a normal
hit.** Vera's longsword, Pike's shortbow and Ilsa's mace all cap at 11 with
a +3 modifier. `1d8+3 ≤ 11 < 12`. Red exists for them only on a crit — and
per F2 even a crit is red for two frames. The tester asking for "red and
big" has, on the preset party, most likely **never seen the red band at
all**. That is not a request to change the colour; it is a report that the
colour is not arriving.

**Finding F6 — an absolute threshold is the wrong axis anyway.** 5 damage
onto a 7 HP goblin ends it; 5 onto a CR-6 body is a scratch. The same
number means opposite things and gets the same colour. Fraction of the
target's max HP, and crit-vs-not, are the two axes that carry the meaning
the colour is being asked to carry.

## 4. Where it is painted, and what stands in front of it

Three things have already been moved off `Board`'s own canvas onto
`main.gd`'s `_hud_overlay` CanvasLayer (line 1689, `layer = 5`) for one
reason, recorded three times in the source: **a `Figures3D` model is a
`Board` child, so it draws after everything `Board` paints, whatever the
order within `_draw()`.** The HP bar went first, then the odds chip
(`scenes/main.gd:2694–2699`), then the T26 barks (`2700–2706`), the barks
picking up a dropped shadow on the way because they now land on top of
figure art.

**Finding F7 — the damage float is the last transient readout still
painted under the figures.** It draws at `_pix(c.pos) + (-8, -(20 + age·34))`
— a fixed screen offset over the hex centre, which is precisely the offset
that got the odds chip moved (`-s * 1.35`, "a tall figure … could stand
right over the chip's fixed screen offset"). Anyone standing in front of
the damaged body covers their damage number. The reveal popup and the hover
stat card are in the same position, but the reveal at least sits `-s*1.7`
up and the stat card follows the mouse.

**Finding F8 — the anchor is frozen at spawn.** `_pix(c.pos)` bakes
`_origin` and `hex_px` into a pixel at spawn time; every other overlay
resolves its position at draw time through `_tok` / `_pix`. Pan or zoom
during the 1.1s and the numbers stay behind on the screen where the hex
used to be. It is also `c.pos` (the hex) rather than `_tok[c.id]` (the
drawn token) plus `_lunge`, so damage taken mid-slide — an opportunity
attack on a moving body is the everyday case — pops over the destination
hex while the body is still walking to it.

Minor, same neighbourhood: the board draws in `ThemeDB.fallback_font`
throughout, not the project's `assets/fonts/DejaVuSans.ttf`
(`project.godot`, `gui/theme/custom_font`).

## 5. What gets a reveal and what only gets the float

`show_reveal()` is called from exactly one place: `_apply_target()`
(`scenes/main.gd:1199`), the hero's single-target path. So the big
`HIT  7` / `CRIT!  14` headline — 26·fz, punch-in, 0.9s hold — appears for
a hero's targeted attack or single-target spell, and for nothing else.

| event | reveal headline | float |
|---|---|---|
| hero single-target attack / spell | yes | yes |
| hero cone (`_mode == "cone"`) | no | yes |
| hero area / hex-targeted spell | no | yes |
| **every foe attack on the party** | **no** | yes |
| lingering-zone burst (`core/combat.gd:195`) | no | yes |
| poison / potion self-damage | no | yes |

**Finding F9 — for everything the party takes, and for every AoE either
way, the float is the only damage readout on the board.** That is the half
of the fight the player has no control over and most needs to read, and it
is served by the cascade in §2. It is also why the two readouts are not
redundant: fixing the float is not "the headline already says it".

**Finding F10 — healing shows nothing.** The spawn is gated on `hv > c.hp`
(line 2189), so HP going *up* animates the bar silently. A cure-wounds has
no number at all.

## 6. The three asks, against the findings

| ask | what it would take on its own | what it actually needs |
|---|---|---|
| "red and big" | change two constants | F1/F2 first — the red one is on screen for 2 frames and buried; then F5, because the party's own weapons cannot reach the red band |
| "eye-catching" | bigger font | F3 (one number, not a smear), F7 (paint above the figures, with a shadow like the barks got), F1 (stop ending on `-0`) |
| "stays longer" | raise `1.1` | F1 — length is not the problem while the tail is `-0 -0 -0`; then a hold-then-fade curve like the bark's rather than fading from frame 0 |

None of the three is wrong. All three are downstream of the cascade.

## 7. Recommendation

In order. All of it is `scenes/main.gd`, none of it touches `core/`, and
nothing here changes a rule or a number the simulation sees.

1. **Spawn one float per damage event.** The spawn is currently a side
   effect of the bar lerp; latch the goal instead and leave the lerp
   exactly as it is, so the HP bar keeps its easing:

   ```gd
   var goal: float = _goal.get(c.id, float(c.hp))
   if not is_equal_approx(goal, float(c.hp)):
       if float(c.hp) < goal:
           _spawn_float(c, goal - float(c.hp))
           _flash[c.id] = 0.35
       _goal[c.id] = float(c.hp)
   ```

   One dict, cleared alongside `_hp` at line 1998, and `_spawn_float` now
   receives the true damage. This alone kills F1, F2, F3, F4 and the
   frame-rate dependence, and makes every other item below meaningful.
   ~8 lines.

2. **Re-cut the bands on fraction of max HP, plus a crit colour**, not on
   absolute 12/6 (F5, F6). A colour that the preset party's own longsword
   cannot reach is not a colour. Crit is the one case that should be
   unmistakable and is currently indistinguishable from a good hit, because
   the float never learns the hit was a crit — `_spawn_float` reads HP, not
   the result dictionary. If crit colouring is wanted, the damage event has
   to carry it (either pass the result through, or have `core/combat.gd`
   queue damage events the way it already queues `cb.barks`).

3. **Size from the same axis, times `fz`.** 18 unscaled is the outlier in
   the §1 table; a big hit reading bigger is exactly ask #1, and it costs
   one multiply. Anything drawn over a hex should move with the zoom.

4. **Hold, then fade** — the bark curve (`alpha = (TTL - age) / 0.5`
   clamped), not `1 - age/1.1`. Ask #3 is free here: floats never block, so
   a longer TTL costs no pacing, unlike `REVEAL_PAUSE` which is an `await`.
   1.1s → ~1.6s with a ~1.1s hold is the same order as the bark's 2.2/1.7.

5. **Move the paint to `_draw_hud_overlay`** with a dropped shadow (F7),
   the fourth item to make that move for the third time the same reason has
   been written down in this file.

6. **Anchor at draw time** — keep the combatant id and resolve
   `_tok.get(id) + _lunge(id)` in `_draw()`, with a small per-float x
   jitter so two hits on one body in one round do not sit on each other
   (F8). Use `_centered_on`, not `x - 8`.

7. **Decide on healing** (F10). A green `+n` on the same path is four
   lines, or the silence is deliberate — but it should be a decision.

Not recommended: raising the TTL or the font size on their own. Either one
applied to today's code makes a bigger, longer-lived pile of `-0`.

## 8. What a fix must not break

- **The HP bar's easing.** `_hp` and its `k` lerp are what draw the bar
  sliding down; item 1 deliberately adds a second latch rather than
  touching them.
- **`SORCMERC_FAST` / headless.** Floats are not gated on `_fx_on`, and at
  `_anim = 999` `k` clamps to 1.0, so today exactly one float is spawned
  and the drive robots never see the cascade. Any new per-event path must
  stay just as cheap — and note that the robots have therefore never been
  able to catch this.
- **`tests/drive_game.gd` and friends** assert on the log and on state, not
  on the overlay, so none of this is covered by a test today. A regression
  test is possible without a window: drive one hit through `Board.tick()`
  at a fixed `dt` and assert `_floats.size() == 1` and its text.

## Reproduce

No engine needed — §2 and §4's tables are the arithmetic of `tick()`:

```python
import math
def cascade(dmg, dt, anim=1.0):          # dt from the monitor, anim from Settings.ANIM_PACES
    k = min(max(dt * anim * 12.0, 0.0), 1.0)      # scenes/main.gd:2159, fed dt*_anim at :1675
    hv, out = float(dmg), []
    while abs(hv) > 0.15:                          # :2187
        out.append(int(math.floor(hv + 0.5)))      # "-%d" % int(round(gap)), :2267
        hv *= (1.0 - k)                            # lerpf(hv, hp, k), :2191
    return out
print(cascade(14, 1/60))     # 21 floats, ending -0 -0 -0 -0 -0 -0
print(cascade(14, 1/60, 0.55))  # Weighty: 39
```

§3's tables are exact pmfs over `data/bestiary.json`'s `damage` field and
`data/weapons.json`'s `damageDice` + 3, banded at the `_spawn_float`
thresholds.

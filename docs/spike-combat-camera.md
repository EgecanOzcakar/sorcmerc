# Spike: a larger combat view, and a camera that follows the action

2026-09-21, issue #152. Measurement first, then the smallest change that
answers "much larger, more immersive": **the boards stay the size they are;
the camera stops showing all of one at once.** Implemented in the same PR
(`scenes/main.gd`, `_follow_cam`); `tests/test_combat_camera.gd` holds the
rules below as a regression test.

## 1. What the view showed before

`Board._layout()` is TFT-style: the whole map on screen, zoomed *down* from
`ZOOM_DEFAULT` (1.5) until it fits, never up. Measured headless with every
theme's board at seed 7, the window's canvas at three sizes (the game runs a
1280×800 canvas under `canvas_items` stretch, so a 4K window sees the first
row scaled ×2.6 — the same picture, bigger pixels):

| canvas    | board          | hexes | zoom | hex px | board fill (w × h) |
|-----------|----------------|------:|-----:|-------:|--------------------|
| 1280×800  | sunken-shrine  |   130 | 0.49 |     17 | 90% × 86%          |
| 1280×800  | goblin-camp    |    91 | 0.57 |     20 | 89% × 73%          |
| 1280×800  | merchant-shop  |    88 | 0.57 |     20 | 89% × 58%          |
| 1920×1080 | sunken-shrine  |   130 | 0.77 |     26 | 87% × 90%          |
| 1920×1080 | goblin-camp    |    91 | 0.97 |     33 | 92% × 82%          |
| 3840×2118 | any            |     – | 1.50 |     51 | 62–74% × 46–81%    |

(The last row is the canvas at native 4K, which the stretch mode never
produces; it is here to show that even unstretched the ceiling caps a hex at
51 px.)

So: a hex is **17–20 canvas px** on the canvas every player actually gets, a
1.2 m figure rig stands about 30 px tall, and the board is a strip across
the middle of the screen with the bar under it. That is the "not immersing".

## 2. The change

- **`ZOOM_FOLLOW = 2.2`** — a hex is 75 canvas px, a figure ~110 px. Four
  and a half times the area of the fit-all view.
- **The camera's subject is who is acting.** `_advance()` focuses the actor
  at the top of every turn; `cb.on_perform` focuses the actor *and the
  target* for every action, both teams. Ids, not hexes, so a walking token
  is tracked as it slides.
- **A pair is kept in frame.** With two subjects the zoom is the lesser of
  `ZOOM_FOLLOW` and what fits both inside a 140 px margin; the view centres
  on their midpoint. One subject: `ZOOM_FOLLOW`, centred on it.
- **Glide, not cut.** Zoom and pan each converge at `CAM_RATE` 4/s (1/e in a
  quarter second), the zoom about the subject so it does not drift while the
  hexes grow. Under `SORCMERC_FAST` the pace multiplier makes it land in one
  frame, which is why the headless robots never wait on it.
- **The player's hand wins until the next action.** Scroll or drag sets
  `_cam_hold`; the next focus releases it. Home toggles `_cam_follow`: off
  is the old fit-all view (and stays there); on is back on the action.
- **The chrome does not breathe.** The bar, the initiative strip and the key
  chips used to scale by `_zoom`; a camera that zooms every action would
  have resized the bar every action (and resized the board under it — see
  #140 for why that is worse than it sounds). They scale by `_ui_zoom` now,
  which only the player's own zoom, Home and the fit-all pass set. The HUD
  text over tokens (HP bars, barks, the odds chip) still scales with the
  camera, as it should — it is over the hexes.

## 3. Not taken, and why

- **Bigger boards.** Encounter boards are 88–130 hexes. Growing them touches
  `encounter.gd`'s `_grow`, AI ranges, deployment starts and every authored
  room; and the measurement says the problem was never the board's size but
  how much of the screen a hex got. Revisit if the follow camera makes
  fights feel *small* rather than close.
- **A cinematic on hits only.** Cheaper, but a camera that only moves for
  the punch is a camera that is somewhere else when the punch comes.
- **A setting to disable it.** Home is the switch, and it is per fight. If
  someone wants it off for good, that is a one-line entry in
  `core/settings.gd` read where `_cam_follow` is set on a new fight.
- **Orbit/tilt.** `ISO_YAW`/`ISO_SQUASH` are still constants; the follow
  camera pans and zooms only. The `ponytail:` note on them stands.

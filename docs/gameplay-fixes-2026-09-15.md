# Gameplay fixes, 2026-09-15 — what was mechanical, what is a decision

Rule for this pass: fix what the code can prove is wrong; for anything that is a
design call, write down what Baldur's Gate 3 does and stop for a decision.

## Fixed (mechanical)

### Unauthored spells were touch-range — `dca249b`
`Effects.spell()` only carried `range_ft` when `data/effects/spells.json` authored
it (26 of 146 spells). Everything else fell to `m.get("range_ft", 5)`: Hold
Person, Web, Fireball, Hypnotic Pattern, Sleep, Hold Monster, Confusion, Fog
Cloud… all touch. The export's prose `"range": "60 feet"` is now parsed as the
default; authored values still win; Self/Touch/Self-(cone) stay 5 ft.
`test_rules` pins six of them.

Still capped by `adapter.gd` `RANGE_CAP := 8` hexes (40 ft at 5 ft/hex), so
Fireball's 150 ft becomes 8 hexes in play. See decision 2.

### Encounter difficulty retuned — `fd54b54`
Decision taken: keep the movement rule, recalibrate. `TIER` 0.96/1.10/1.32 →
0.77/0.90/1.04 (swept with `tests/sweep_tier.gd`), confirmed 94.0 / 86.5 /
72.0. The smaller hard budget sat below the mammoth's score at `MULT_MIN`, so
`boss_for` now always seats one escort body. `BOSS_POOL` win rates and
`BOSS_REF_WIN_RATE` re-derived.

### Boards widened — every board is the room plus its mirror
Decision taken: grow boards, not the cap. `Encounter.board_for()` now returns
the authored room mirrored along q (`_widen`): cover, rough and objects come
along, `region_at` answers for a hex's twin. Diameters 12–19 (was 7–10);
`SPAWN_GAP` 6 is honoured on every board (spawn distance 6..15, was 3..5).
Measured with `tests/sweep_range_detail.gd`, 150 seeds: Pike's shots at 6–7
hexes 61 → 268, foe archers' 178 → 426 — range does work now. Win rates on
the retuned `TIER` did not move (93.5 / 85.5 / 74.5), so no second retune.
The board view auto-fits, so no scene work. Two fixtures updated: board size
band 36–64, and the wipe fixture hits at ×12 (foes no longer start adjacent).

## Found, not fixed (decisions)

### 1. Encounter difficulty dropped 15–25 points — `6b098e8`
`test_scaler` fails on master: easy 80% / normal 68% / hard 51.5% against
targets 95 / 85 / 75 (±10). Bisected in a worktree, 200 pinned seeds each:

| commit | easy | normal | hard |
|---|---|---|---|
| `01eee36` (bosses out of early rooms) | pass | pass | pass |
| `6b098e8` allow moving through ally hexes | **80.0** | **68.0** | **51.5** |
| `40d8751` (ledger theme) | 80.0 | 68.0 | 51.5 |

Cause: `_blockers()` went from "every conscious body" to "hostiles only", so a
melee foe queued behind its own archer in a choke now reaches the party. The
rule is symmetric, but 3 heroes vs 4–5 foes means the side with more bodies
gains more turns-in-contact — exactly the action-economy effect `scaler.gd`'s
header measured ("5e punishes the number of turns the other side gets much
harder than any stat line"). The rule itself is correct 5e and the change was
deliberate; what is stale is the `TIER` calibration underneath it.

**BG3:** you can move through allies freely and never through enemies — same
rule sorcmerc now has. BG3 does not budget encounters at all; every fight is
hand-placed, and difficulty is a stat layer on top: Explorer enemy HP −30%,
player HP +100%; Tactician enemy HP +20–30% (bosses more), +2 to enemy attack
rolls and spell DCs, more aggressive targeting; Honour adds Legendary Actions
to bosses. Custom mode exposes those as sliders (enemy aggression, character
power, enemy loadouts, proficiency −1..+4, camp cost 0.5–3×, trade price 1–4×).

Options:
- **A. Recalibrate `TIER`** (mechanical, ~1 h of sweeps). Keeps the rule. The
  header's own procedure: sweep, set 0.96/1.10/1.32 to whatever lands 95/85/75,
  record the numbers. Level-8 curve must be re-checked (it moved the other way
  last time).
- **B. Revert `6b098e8`.** Restores the numbers, loses correct movement; melee
  foes stand in chokes again (the bug it fixed).
- **C. BG3-style difficulty layer.** Keep the roster generator at one tier and
  make easy/normal/hard a stat overlay: enemy HP ×0.7/1.0/1.25, to-hit and DC
  +0/+0/+2, party HP ×2 on easy. `encounter._scale()` already multiplies
  hp/ac/to-hit/damage by `mult`, so this is mostly one table. Predictable across
  levels (the header's stated pain), and it makes the level-8 ceiling problem go
  away because bodies stop being the difficulty knob.

Recommendation: **A now** (unblocks the failing test, no design change), and
queue **C** as the real answer if the level-8 curve fights the recalibration
again.

### 2. Spell range grammar — the spike's open question
`docs/spike-hex-ranges.md` measured that `RANGE_CAP` 6/8/10/12 and "uncapped"
are byte-identical on current boards (nobody shoots past 7 hexes), and asked
whether range should be a 3-tier grammar (touch / 5 / cap) or whether boards
should grow.

**BG3:** it did the 3-tier thing. Almost every ranged spell is 18 m (60 ft) —
Fireball, Fire Bolt, Eldritch Blast, Hold Person all 18 m, regardless of the
120/150 ft tabletop numbers; a few are 9 m (30 ft); touch and self stay. Fireball's
radius is 4 m (13 ft), not 20 ft. So BG3 shipped exactly "cap at 60 ft, halve
the big AoEs" on maps not much bigger than sorcmerc's boards.

Now that the 29 spells carry real ranges, the cap is doing real work for the
first time (Fireball 150 → 40 ft). Options:
- keep `RANGE_CAP` 8 (40 ft) — BG3-tighter, unchanged play;
- raise to 12 (60 ft) to match BG3 and 5e's most common range, and
  re-measure ranged share with `tests/sweep_range_detail.gd`;
- grow boards instead (the spike's "bigger boards + `_foe_spots` fix" branch).

No recommendation without a sweep; it is cheap to run once you pick.

### 3. `_scale()` does not scale `save_dc` with `mult`
Noted in the scaler header as a real gap that "is not what drives the
outliers". BG3 scales DCs with difficulty (+2 on Tactician). Mechanical once
decided; ~3 lines. Skipped only because it shifts the same calibration as (1).

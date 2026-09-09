# Hex Combat + Combat-Screen Eye Candy — Design

**Status:** approved design, pre-implementation.

Replaces the 3-zone positioning model ([combat-design.md §3](../../combat-design.md))
with a true hex grid: attacks and spells gain range constraints measured in
hexes. Also reskins the combat screen — styled buttons, token art, animated HP
bars, floating damage numbers, range/target highlighting.

The zone model was a deliberate choice in the original design; this spec
knowingly overrides it. The chokepoint room shape and the "fight happens on top
of the hazard" intent are preserved on the new grid.

---

## 1. Scope

**In:**

- New `core/hex.gd` — pure hex math (static funcs, no engine deps).
- `core/combatant.gd` — position becomes a hex coord, speed becomes hexes/turn.
- `core/encounter.gd` — board definition (passable / brazier / cover hexes),
  hex start positions, range constants.
- `core/combat.gd` — movement, melee reach, ranged range, opportunity attacks,
  cover, Burning Hands cone, Shove push — all re-expressed in hexes.
- `core/ai.gd` — same five-rule priority list, hex movement and targeting.
- `scenes/main.gd` — hex board renderer, click-to-move / click-to-target,
  range and cone highlighting, HP-bar tweens, floating damage numbers, restyled
  buttons via a programmatic `Theme`.
- `tests/test_combat.gd`, `tests/autoplay.gd`, `tests/drive_ui.gd` — updated for
  hex positions and the new range rules.

**Out (explicitly not built):**

- `AStar2D` / weighted-terrain pathfinding — BFS flood-fill + greedy steps only.
- Line-of-sight / vision / "can't target it" — vision stays cut, as in the
  original design.
- Path-aware opportunity attacks — OA is evaluated on start-vs-end adjacency
  only, not per hex crossed. Marked with a `ponytail:` comment.
- Sprite / image assets, sound, particle systems. Tokens are drawn shapes
  (circle + initials + class glyph). No files added to `assets/`.
- A status *system* — the existing status flag-set is unchanged.
- `.tscn` scene-tree work — the screen stays built programmatically.
- Facing as a persistent stat — Burning Hands direction is chosen per cast.

---

## 2. Hex math — `core/hex.gd`

`extends RefCounted`, all `static func`. Flat-top **axial** coordinates,
`Vector2i(q, r)`.

| Function | Purpose |
|---|---|
| `distance(a: Vector2i, b: Vector2i) -> int` | axial/cube hex distance |
| `neighbors(p: Vector2i) -> Array[Vector2i]` | the 6 adjacent hexes |
| `DIRS: Array[Vector2i]` | the 6 unit direction vectors, fixed order |
| `direction_to(a, b) -> Vector2i` | nearest of the 6 dirs from a toward b |
| `reachable(passable: Callable, start, steps, blocked: Array) -> Dictionary` | BFS flood-fill; returns `{hex: cost}` for every hex within `steps` move points, not entering `blocked` hexes (occupied) but allowed to end adjacent to them |
| `cone(origin, dir: Vector2i, length: int) -> Array[Vector2i]` | hexes in the 60° wedge centred on `dir`, out to `length` (excludes `origin`) |
| `line(a, b) -> Array[Vector2i]` | hex line, for push/knockback direction |
| `to_pixel(p, size) -> Vector2` / `from_pixel(v, size) -> Vector2i` | render + click mapping |

`reachable` takes `passable` as a `Callable` so the board stays data in
`encounter.gd` and `hex.gd` has zero knowledge of it.

**Check:** `tests/test_hex.gd` (new, tiny) — `distance` symmetry and known
values, `cone` cardinality, `reachable` respects step budget and blocked hexes.

---

## 3. Data model

### `core/combatant.gd`

- Remove `zone: int`, `speed_zones: int`.
- Add `pos: Vector2i` (axial hex), `speed: int` (move points / turn; 1 hex = 1).
- `clone()` — swap `zone`/`speed_zones` for `pos`/`speed`. `pos` is a `Vector2i`
  (value type), so plain assignment in the copy loop is fine.

### `core/encounter.gd`

New board constant — a sculpted room, ~28 hexes:

```
  Threshold (open, left, ~3x3)
        │  1-hex choke
  Brazier Hall (brazier at centre hex)
        │  1-hex choke
  Alcove (2 cover hexes, dead end)
```

```gdscript
const BOARD := {
    "hexes":   [ <Vector2i list of every passable hex> ],
    "brazier":   Vector2i(bx, br),
    "cover":   [ Vector2i(...), Vector2i(...) ],   # the Alcove hexes
}
```

Range constants (tune here, nowhere else):

```gdscript
const REACH_MELEE   := 1
const RANGE_SHORTBOW := 6
const CONE_BURNING_HANDS := 2          # wedge length in hexes
const RANGE_SPELL_LONG   := 12         # sacred flame / healing word — whole map
```

Speeds: Vera 4, Ilsa 4, Grull 4, Pike 5, Snik/Vess/Kritch 5. Dash doubles the
budget for that turn.

Start positions: party clustered in Threshold, Grull + Snik + Vess in Brazier
Hall, Kritch in the Alcove. Exact coords chosen so Kritch is out of shortbow
range of the party's opening hexes by 1–2 hexes (movement has to answer him).

`Combat.new(rng, combatants, board)` — board passed in, defaults to
`Encounter.BOARD` when omitted so tests can supply their own.

---

## 4. `core/combat.gd`

### Constants / helpers

- `ZONE_NAMES` / `ALCOVE` removed. Add `region_at(pos) -> String` — returns
  `"Threshold" | "Brazier Hall" | "Alcove"` from coarse `q` bands, for log
  flavour only ("Grull moves toward the Brazier Hall").
- `board` stored on the resolver. `_passable(p) -> bool`, `_is_cover(p) -> bool`,
  `_occupied(p) -> Combatant` (conscious blocker for movement).

### Queries (rename + re-implement)

| Old | New |
|---|---|
| `zone_has_enemy(c)` | `adjacent_enemy(c) -> bool` — a conscious hostile at `distance == 1` |
| — | `in_reach(attacker, target) -> bool` — melee: `distance == 1`; ranged: `distance <= RANGE_SHORTBOW` |
| `effective_ac(c)` | uses `_is_cover(c.pos)` instead of `zone == ALCOVE` |

`hit_chance` unchanged except it calls the new `effective_ac`.

### Attack

`_attack_mode` — ranged disadvantage when `adjacent_enemy(attacker)` (was
`zone_has_enemy`). Prone / dodging / hidden branches unchanged.

`_sneak_ok` — "ally in the target's zone" → "ally at `distance <= 1` of the
target".

`resolve_attack` — add an early guard: if `not in_reach(attacker, target)` the
call is rejected (returns `{"error": "out of range"}`, no log line). The UI
never offers an out-of-range target, but the AI and tests rely on the guard.

### Movement

```gdscript
func move_to(mover, dest: Vector2i, disengage := false) -> void
```

- Reject if `dest` not in `hex.reachable(_passable, mover.pos, budget, occupied)`
  where `budget` = remaining move points this turn and `occupied` = conscious
  others' hexes.
- Opportunity attacks: for each conscious hostile `h` with
  `distance(h.pos, mover.pos) == 1` **and** `distance(h.pos, dest) > 1`, if not
  `disengage` and not `h.has("reacted")` → `h` takes an OA. Existing
  down/dead-after-OA bail-out kept.
  `# ponytail: OA on start-vs-end adjacency only, not hexes crossed en route.`
- `mover.pos = dest`; log via `region_at`.

`Dash` — action + move consumed, budget = `speed * 2`.

### Cover

`_saving_throw` — `c.zone == ALCOVE` → `_is_cover(c.pos)`. Sacred Flame's
`ignore_cover` path unchanged.

### Burning Hands — now a cone

```gdscript
func cast_burning_hands(caster, dir: Vector2i, level := 1) -> void
```

- `dir` is one of `hex.DIRS`.
- Affected = conscious combatants whose `pos` is in
  `hex.cone(caster.pos, dir, CONE_BURNING_HANDS)` (caster excluded by `cone`).
- Everything else (save, half-on-save, upcast dice) unchanged.
- AI passes the direction that catches the most foes and fewest allies.

### Shove push

`act_shove` `"push"` branch — push target one hex along
`hex.direction_to(attacker.pos, target.pos)`; if that hex isn't passable the
push fizzles (still counts as a successful shove — pick prone instead in the UI).
`"brazier"` branch — allowed when the push destination **is** the brazier hex or
the target is already adjacent to it; 2d6 fire as now.

---

## 5. `core/ai.gd`

Same five rules, hex mechanics:

- "conscious hostile shares my zone / I can melee" → `distance == 1`.
- Goblin retreat (rule 2) — move `speed` hexes maximising distance from the
  largest cluster of conscious PCs, ending on a passable unoccupied hex.
- Kritch (rule 3) — if a PC is adjacent, Nimble Escape then move to keep
  `2 <= distance <= RANGE_SHORTBOW` from the nearest PC; else shoot lowest-HP
  conscious PC in range.
- Rule 4 (no target in reach) — one greedy step: pick the hex in
  `hex.reachable(...)` that minimises `distance` to the nearest conscious PC,
  move there, then attack if now adjacent.
- Mercy rule constant unchanged.

`_away_from` replaced by a hex helper `_retreat_hex(cb, m, threats)`.

---

## 6. `scenes/main.gd` — board + eye candy

One `Control` subclass with custom `_draw()`. Layout: hex board fills the centre,
initiative ribbon on top, actor card + action buttons below, combat log at the
bottom (log rendering unchanged).

### Board rendering

- Each passable hex → filled polygon (`hex.to_pixel`), thin border. Brazier hex
  warm glow (pulsing via a `Tween` on modulate). Cover hexes drawn with a hatch
  overlay + "cover" label.
- **Token** per conscious combatant: filled circle (party green / foe red),
  2-letter initials, a small class glyph (sword / bow / book / claw). Current
  actor gets a bright animated ring. Prone → token squashed + `↓`; hidden →
  half-alpha + `👁`; down → grey + `✗` and the death-save pips.
- Exact HP shown next to each token as `hp/max` with a slim bar; the bar
  `Tween`s its value and flashes on change.

### Interaction (small state machine: `IDLE → MOVE → TARGET → CONE`)

- **Move:** "Move" button → reachable hexes tint blue, hexes whose entry would
  cost the last point and leave a threatened hex show `⚠` + the provoking
  foes' initials. Click a hex → `move_to`. `b` / right-click cancels.
- **Attack / Sacred Flame:** verb button → in-range enemies outlined, floating
  hit-% (or save-DC) chip over each. Click token → resolve. Out-of-range enemies
  are not outlined and not clickable.
- **Burning Hands:** enter `CONE` — a translucent wedge preview follows the
  mouse hex, snapping to the nearest of 6 directions; affected tokens highlight
  live. Click to fire, `b` cancels.
- **Healing Word / Second Wind / Dodge / Dash / Disengage / Action Surge /
  End turn** — buttons as today, re-styled.

### Juice

- Floating damage numbers rise + fade from the target token, coloured by band
  (chip / solid / big), crits larger and brighter.
- Token slides (`Tween` position) along `hex.line` on a move.
- Kill: token fades and drops out. Nat-20 death-save recovery: bright flash +
  log line, as the original design demands.
- A single `Theme` resource built in code: rounded buttons, hover / pressed
  states, consistent fonts and panel styles. One `PAUSE`-style constant for
  tween durations, set to 0 when `SORCMERC_FAST` is in the environment so
  `drive_ui.gd` runs instantly.

### Anti-juice (kept out)

No screen clears between actions, no spinners, no sound, no "press any key"
between monster turns — the enemy round is batched with paced tweens then
control returns.

---

## 7. Tests

### `tests/test_hex.gd` (new)

`distance` known values + symmetry; `neighbors` count 6; `cone` cardinality for
length 1 and 2; `reachable` honours the step budget and refuses blocked hexes
but allows ending adjacent to them.

### `tests/test_combat.gd` (rewrite positions + add)

Keep every existing dice/death-save/heal assertion. Replace zone setup with hex
coords. New asserts:

- melee `resolve_attack` at `distance 2` is rejected; at `distance 1` resolves.
- ranged attack at `distance <= RANGE_SHORTBOW` resolves; beyond is rejected.
- ranged attack with an adjacent hostile is at disadvantage.
- `move_to` beyond the speed budget is rejected; within it succeeds.
- moving from adjacent-to-hostile to non-adjacent provokes an OA; `disengage`
  suppresses it; moving while staying adjacent does not provoke.
- `cast_burning_hands(dir)` hits only combatants in the wedge, never the caster,
  and still splits allies vs foes correctly.
- a combatant on a cover hex has +2 effective AC and +2 to DEX saves; Sacred
  Flame ignores it.

### `tests/autoplay.gd`

Hex start positions; narration uses `region_at`. The existing multi-seed
win-rate / round-count sweep must still run — record the new numbers in the
README (they will shift; the target stays "party wins ~4–6 rounds, ~80–90%").

### `tests/drive_ui.gd`

Drive the new state machine: click a reachable hex to move, click an outlined
enemy to attack, fire Burning Hands in a direction. Runs under `SORCMERC_FAST`.

---

## 8. Build order

1. `core/hex.gd` + `tests/test_hex.gd`.
2. `core/combatant.gd` + `core/encounter.gd` board & positions & ranges.
3. `core/combat.gd` — queries, movement + OA, cover, reach guards.
4. `core/combat.gd` — Burning Hands cone, Shove push.
5. `core/ai.gd`.
6. `tests/test_combat.gd` + `tests/autoplay.gd` green; record new sweep numbers.
7. `scenes/main.gd` — board render + tokens (static first).
8. `scenes/main.gd` — move / target / cone state machine.
9. `scenes/main.gd` — Theme + tween juice + floating numbers.
10. `tests/drive_ui.gd`; update README status + the encounter description.

Each of 1–6 leaves the headless tests runnable. 7–10 are verified by
`drive_ui.gd` and a manual play.

---

## 9. Risks

- **AI kiting oscillation** — Kritch could ping-pong between two hexes. Mitigate:
  only move if it strictly improves the range situation, else shoot / hold.
- **Encounter tuning drift** — hex distances change effective damage-race math.
  Section 8 step 6 re-runs the sweep; tune via the `encounter.gd` constants
  (speeds, ranges, start coords, Grull HP) in that order.
- **Cone ambiguity at the caster's hex** — `cone` excludes the origin; a foe
  sharing the caster's hex is impossible (movement blocks it), so no special
  case needed.
- **Click accuracy** — `from_pixel` rounding; snap to nearest hex centre and
  ignore clicks outside the board.

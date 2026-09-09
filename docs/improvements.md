# Improvement backlog — parallel-agent ready

Each item is scoped to a small set of files with an explicit acceptance check so
independent agents can work in parallel. Contention is called out per item.
Lazy-first: the "Minimum" line is what to build; everything past it is optional.

## The one contention point

`scenes/main.gd` is ~720 lines and every UI task wants it. **Do P1 first** (or
assign all UI work to a single agent). Core (`core/*.gd`) tasks are naturally
separable and can start immediately.

---

## P1 — Split `scenes/main.gd`  ·  size M  ·  blocks U*

Extract the inner `Board` class to `scenes/board_view.gd` (a `Control` script),
and move the hero-menu / hotkey / aim-mode code to `scenes/hero_menu.gd`.
`main.gd` keeps: layout construction, the turn driver (`_advance`/`_end_turn`),
`_refresh`, `_flush_log`, `_finish`.

- **Files:** `scenes/main.gd`, new `scenes/board_view.gd`, new `scenes/hero_menu.gd`
- **Acceptance:** `tests/drive_ui.gd` passes unchanged for seeds 5/42/99; a
  screenshot via `tests/shot.gd` is visually identical.
- **After this:** U1–U4 own `board_view.gd`; U5–U8 own `hero_menu.gd` / `main.gd`
  regions that no longer overlap.

---

## Mechanical track (core/) — can start now

### M1 — Path-aware opportunity attacks  ·  size S  ·  file `core/combat.gd`, `core/hex.gd`
Today `move_to` only checks start-vs-end adjacency (`# ponytail:` comment).
Real rule: leaving *any* hex adjacent to a hostile provokes.
- **Minimum:** in `hex.reachable`, record a parent pointer; reconstruct the path
  to `dest`; a hostile provokes if the path ever moves from adjacent→non-adjacent
  to it. Update `provokers_for` the same way so the UI warning matches.
- **Acceptance:** new assert in `tests/test_combat.gd` — a path that grazes a
  second hostile's zone provokes from both; Disengage suppresses all.
- **Contention:** touches `move_to` + `provokers_for` only. Conflicts with M3
  if M3 also edits `move_to` — coordinate or sequence M1→M3.

### M2 — Help action  ·  size S  ·  files `core/combat.gd`, `scenes/hero_menu.gd`
`combat-design.md §4` verb, currently absent. Grant advantage to a named ally's
next attack roll before the helper's next turn.
- **Minimum:** `act_help(helper, ally)` sets `ally.statuses["helped"] = true`;
  `_attack_mode` grants ADV if attacker `has("helped")`, cleared in
  `resolve_attack`. One verb in the menu, target = an ally in reach of a foe.
- **Acceptance:** assert helped attacker rolls with advantage exactly once.

### M3 — Hide / Cunning Action for Pike  ·  size M  ·  files `core/combat.gd`, `core/ai.gd`, `scenes/hero_menu.gd`
`hidden` status is already read by `_attack_mode` (grants ADV, and is Pike's
Sneak-Attack enabler) but nothing ever sets it. `cunning_action`/`stealth` fields
exist and are unused for the player.
- **Minimum:** `act_hide(c)` — Stealth `d20+stealth` vs the best enemy passive
  perception; on success `statuses["hidden"]=true`. Bonus-action menu entries for
  Pike: Hide / Disengage / Dash (Cunning Action). `hidden` already breaks on
  attack.
- **Acceptance:** assert a successful Hide gives Pike's next attack ADV and
  triggers Sneak Attack; assert Hide breaks after the attack.
- **Watch:** `combat-design.md §11` warns ranged-Hide-every-turn is the likely
  degenerate strategy — leave a tuning note, don't balance it here.

### M4 — Upcasting from the UI  ·  size S  ·  file `scenes/hero_menu.gd`
`cast_burning_hands`/`cast_healing_word` already take `level` and spend `slots2`;
the UI always passes level 1.
- **Minimum:** when `slots2 > 0`, the spell verb offers "at 2nd level" as a
  second entry (or a toggle). No core change.
- **Acceptance:** casting at 2nd drops `slots2`, rolls the bigger dice.

### M5 — Weighted movement / difficult terrain  ·  size M  ·  files `core/hex.gd`, `core/combat.gd`, `core/encounter.gd`
`hex.reachable` is uniform cost 1/hex. Add per-hex cost so rubble / the brazier's
surround can cost 2.
- **Minimum:** `reachable(cost_fn, ...)` where `cost_fn(hex)->int`; board gains a
  `"rough": [Vector2i]` list; brazier-adjacent hexes cost 2.
- **Acceptance:** assert a rough hex halves effective movement through it; AI
  `_move_by` still terminates.
- **Contention:** changes `hex.reachable` signature → coordinate with M1
  (also in `hex.reachable`). Do M1+M5 as one agent, or M5 after M1.

### M6 — Nat-1 flavour + downed-target rule  ·  size S  ·  file `core/combat.gd`
Two tiny design-doc items:
- `_log_attack`: on `nat == 1`, pick one of 3–4 per-weapon miss lines.
- Foe AI currently ignores downed PCs entirely; `combat-design.md §7` rule 5 is
  "don't attack a downed PC *while a conscious one is in reach*" — i.e. they
  *should* finish someone off if nothing else is reachable. Expose a
  `MERCY := true` constant in `core/ai.gd` and implement the weaker rule behind it.
- **Acceptance:** assert with MERCY off a foe adjacent only to a downed PC attacks
  it; with MERCY on it doesn't.
- **Contention:** `ai.gd` change here vs M3's `ai.gd` change — different functions,
  low risk.

---

## UI track (scenes/) — after P1

### U1 — Roll reveal animation  ·  size M  ·  files `scenes/board_view.gd`, `scenes/main.gd`
`combat-design.md §9`: the roll is the drama. Today attacks resolve instantly.
- **Minimum:** `board_view` gets a `reveal(attacker, result)` coroutine: print
  "Vera swings…", ~350ms, show the d20 face over the target, ~200ms, show total +
  outcome. One `PAUSE` const, `0` when `SORCMERC_FAST`. The turn driver awaits it
  before `_after_hero_action`.
- **Acceptance:** `drive_ui.gd` (runs with `SORCMERC_FAST`) still finishes in
  <2s/seed; a manual run shows the pause.

### U2 — Dice widget (adv/dis)  ·  size M  ·  file `scenes/board_view.gd`
`combat-design.md §6` non-negotiable #5: show both dice on advantage, dim the
discarded one. `resolve_attack`'s return dict already has `dice: [a,b]` and `mode`.
- **Minimum:** draw the die face(s) near the target token during U1's reveal;
  discarded die at 35% alpha with a strike.
- **Depends on:** U1 (shares the reveal moment). Assign U1+U2 to one agent.

### U3 — "You act again after X" + turn lookahead  ·  size S  ·  file `scenes/main.gd` (`_refresh`)
`combat-design.md §6` non-negotiable #2. The ribbon shows order + cursor but not
when the current hero comes up again.
- **Minimum:** append "· you act again after <name>" to the actor line; bold the
  next 3 actors in the ribbon.
- **Contention:** `_refresh` only. Conflicts with U6 (also `_refresh`) — sequence.

### U4 — Pan clamp + zoom-to-cursor  ·  size S  ·  files `scenes/board_view.gd`, `scenes/main.gd`
`pan_by` is unbounded (you can lose the board); wheel-zoom anchors on board centre.
- **Minimum:** clamp `_pan` so ≥40% of the board bbox stays on screen; on wheel,
  adjust `_pan` so the hex under the cursor stays put.
- **Acceptance:** manual — board can't be fully scrolled away; zooming keeps the
  hovered hex under the mouse.

### U5 — Confirm step for instant actions  ·  size S  ·  file `scenes/hero_menu.gd`
Aim mode already gives back-out for targeted verbs. Dodge / Dash / Second Wind /
End turn fire on the first press.
- **Minimum:** a two-press confirm (button relabels "Confirm Dodge?") or a
  `y/n` prompt; `Esc` cancels. Keep it out of `SORCMERC_FAST` path.
- **Acceptance:** `drive_ui.gd` still terminates (it double-presses).

### U6 — Log: round dividers + enemy-turn pacing  ·  size M  ·  files `scenes/main.gd`
- `_flush_log`: insert "──  ROUND N  ──" when `cb.round_num` changes.
- Enemy round: instead of one 0.5s timer then a batch dump, pace each foe action
  ~250ms with the log line appearing as it resolves (design §9 "batch with paced
  prints").
- **Contention:** `_advance` + `_flush_log` + `_refresh`. Heaviest `main.gd`
  task — give it its own agent and land it last, or first, but not concurrent
  with U3.

### U7 — Token stat card on hover  ·  size M  ·  file `scenes/board_view.gd` (+ a Panel in `main.gd`)
Hovering a token shows AC, HP, speed, statuses, kit (Sneak Attack, Nimble Escape…).
- **Minimum:** a small follow-the-cursor panel; data straight off the combatant.
- **Contention:** `board_view` hover handler — coordinate with U4 (also hover).

### U8 — Responsive layout + seed entry  ·  size S  ·  file `scenes/main.gd`
- Log panel is a fixed 820px; clamp to `min(820, viewport.x * 0.72)`.
- Add a seed `LineEdit` + "Replay" on the finish screen (currently only "New
  encounter"); `R` restarts.
- **Contention:** layout construction in `_ready` + `_finish`.

---

## Deliberately skipped (say so, don't build)

- **Reaction prompts** (Shield, Warding Flare) — `combat-design.md §10` risk 1;
  turns the resolver async. Not until there's a real user.
- **Concentration** — dead code with only 2 non-concentration spells. Add only
  alongside a 3rd (concentration) spell.
- **Sound, particles, sprite assets** — MVP juice budget is timing + colour.
- **Grapple, Ready, Two-Weapon Fighting, flanking, exhaustion, resistances,
  temp HP** — `combat-design.md §4` cut list; each collapses an existing choice.
- **Smarter monster AI** — `combat-design.md §10` risk 2. Tune numbers in
  `core/encounter.gd`, not behaviour, without playtest evidence.

---

## Suggested parallel batches

| Batch | Agents | Items | Shared files |
|---|---|---|---|
| 1 (now) | 3 | M1+M5 (one agent), M2, M4 | `combat.gd` localized; sequence M1→M5 |
| 1 (now) | +2 | M3, M6 | `ai.gd` (different funcs), `combat.gd` |
| 2 (after P1) | 1 | P1 split | `main.gd` → 3 files |
| 3 | 4 | U1+U2 (one), U4+U7 (one), U3→U6 (one, sequenced), U5, U8 | separated by P1 |

Every item lands its own test or a `drive_ui.gd` / `tests/shot.gd` check.
Re-run the 200-seed sweep in `tests/test_combat.gd` after any core change and
record the new win-rate / round-count in `README.md`.

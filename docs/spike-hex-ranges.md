# Spike: hex distances, spell ranges, ranged↔melee balance

2026-09-15. Measurement only — nothing adopted here. **Acted on the same day:**
`d7c875f` mirrored every board (diameters 12–19, `SPAWN_GAP` honoured) and
retuned `TIER`, so §1e and the §2 baseline describe the boards as they were
that morning; the `fight-rules-fixes` PR landed S1 (spell ranges), the
downed-body/OA rules and the archer step-back from §4/§5. Follows T35–T37 in
`expansion-plan.md`, which measured *ranged share* against `FT_PER_HEX`,
`SPAWN_GAP` and board width and found the needle didn't move. This spike asks
the narrower questions those left open: do ranges *differentiate* at all on
the current boards, which knobs actually reach which combatants, and where
the balance sits per role rather than in aggregate.

Tooling: `tests/sweep_range_detail.gd` (throwaway; same 150 seeds, same
`Presets.party()` — Vera fighter/longsword, Pike rogue/shortbow, Ilsa
cleric/mace + sacred flame + burning hands — same `Scaler.roster_for` on
`normal`, same six themes as T35's `sweep_range.gd`). Every attack and cast
is tagged with the hex distance it was thrown from. Candidates were a
one-line constant edit, run, `git checkout` — no branches this time, the
edits are listed under each row.

## 1. Static: what the feet→hex conversion does to the data

`core/adapter.gd`: `hexes(ft) = max(1, round(ft / FT_PER_HEX))`, then
`min(RANGE_CAP, …)`; areas floor instead of round. `FT_PER_HEX = 6`,
`RANGE_CAP = 8`.

### 1a. Spell ranges — 53 combat-castable spells

| catalog range | hexes @6 | after cap 8 | hexes @5 | after cap 8 | authored spells |
|---|---|---|---|---|---|
| 5 ft / touch | 1 | 1 | 1 | 1 | cure-wounds, shocking-grasp, (+ 3 cones/emanations) |
| 30 ft | 5 | 5 | 6 | 6 | poison-spray, thorn-whip, blight, hideous-laughter |
| 60 ft | 10 | **8** | 12 | 8 | produce-flame, ray-of-frost, sleep, acid-splash, ray-of-sickness, dissonant-whispers, mind-sliver, sacred-flame, hellish-rebuke |
| 90 ft | 15 | **8** | 18 | 8 | chromatic-orb |
| 120 ft | 20 | **8** | 24 | 8 | scorching-ray, guiding-bolt, fire-bolt, chill-touch |
| 150 ft | 25 | **8** | 30 | 8 | fireball |

So there are exactly **three** effective spell ranges in the game: 1, 5 and
8 hexes. Everything from 60 ft up is the same spell as far as the board is
concerned; a 120 ft Fire Bolt and a 60 ft Sacred Flame reach identically.
`FT_PER_HEX = 5` (D&D-canonical) changes nothing above the cap; it only
moves 30 ft from 5 to 6 hexes.

**Finding S1 — 29 of the 53 castable spells have no authored `range_ft` and
default to 5 ft = touch.** `effects.gd:146` reads `m.get("range_ft", 5)`,
and the catalog's regex-parsed `mechanics` never carries a range. Hold
Person (60 ft), Hypnotic Pattern (120 ft), Web, Moonbeam, Hold Monster,
Dominate, Banishment, Ice Storm, Flame Strike, Stinking Cloud, Wall of Fire
… are all touch-range if a character ever gets them. The preset party
doesn't (so no sweep number moves), but any Wizard/Bard/Druid a player
builds will. This is a data bug, not a balance question, and it dwarfs
every knob measured below. Full list is in §6.

### 1b. Areas

| authored size | hexes @6 (floor) | @5 |
|---|---|---|
| 10 ft (arms of hadar) | 1 | 2 |
| 15 ft cone (burning hands) | 2 | 3 |
| 20 ft sphere (fireball — `targeting: hex`, dropped by adapter) | 3 | 4 |
| 30 ft cone (fear) | 5 | 6 |
| 60 ft cone (cone of cold) | 10 | 12 |

### 1c. Weapons

| weapon | normal ft | hexes @6 | cap 8 | @5 | cap 8 |
|---|---|---|---|---|---|
| net | 5 | 1 | 1 | 1 | 1 |
| dart | 20 | 3 | 3 | 4 | 4 |
| blowgun | 25 | 4 | 4 | 5 | 5 |
| sling, hand-crossbow, pistol | 30 | 5 | 5 | 6 | 6 |
| musket | 40 | 7 | 7 | 8 | 8 |
| shortbow, light-crossbow | 80 | 13 | **8** | 16 | 8 |
| heavy-crossbow | 100 | 17 | **8** | 20 | 8 |
| longbow | 150 | 25 | **8** | 30 | 8 |

Longbow = shortbow = light crossbow = heavy crossbow on the board. Long
range (`longRange`) is never read; there is no disadvantage band. Thrown
weapons (dagger, handaxe, javelin, spear, trident…) have `range: "melee"`
and can't be thrown at all.

### 1d. Bestiary is hex-native — `FT_PER_HEX` never touches it

`bestiary.json` stores `speed` and `atk_range` already in hexes (145 of 316
bodies at speed 5, i.e. 30 ft pre-baked at 6 ft/hex; 27 of 35 ranged bodies
at `atk_range: 8`, i.e. already capped). `Combatant.clone()` copies them
verbatim; only `Adapter.to_combatant` (PCs) goes through `hexes()`.

**Finding S2 — `FT_PER_HEX` and `RANGE_CAP` are party-only knobs.** T35's FT 8/10 slowed
the *party* from 5 to 4/3 hexes a turn while every monster kept 5 — that is
the whole 7-point win-rate cost T35 saw, not "slower closing". §3 below
shows the mirror image. Likewise `RANGE_CAP 6` leaves 27 bestiary archers at
8. Any future re-scale needs a bestiary re-bake or a `hexes()`/`mini(RANGE_CAP)`
pass in `spawn()` first.

### 1e. Boards

| theme | hexes | diameter | farthest hex from any party start |
|---|---|---|---|
| sunken-shrine | 23 | 10 | 6 |
| goblin-camp | 28 | 9 | 5 |
| city-square | 28 | 9 | 5 |
| forest-clearing | 26 | 7 | 4 |
| frozen-cave | 21 | 9 | 6 |
| merchant-shop | 20 | 7 | 3 |

`SPAWN_GAP = 6` is already unreachable on four of six boards — no hex is 6
from every party start, so `_foe_spots` falls through to its "least-bad"
overflow and foes spawn at 3–5. A party member at speed 5 reaches any foe
in one move on every board. **First contact is round 1 in 150/150 fights.**

## 2. Baseline — where attacks actually happen (150 fights, 5,918 swings/casts)

Distance histogram, every attack and single-target cast, by actor:

| actor | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | total | ≥2 |
|---|---|---|---|---|---|---|---|---|---|---|
| vera (longsword) | 1164 | 6 | 0 | 3 | 1 | 1 | 2 | 0 | 1177 | 1% |
| pike (shortbow, cap 8) | **224** | 151 | 110 | 191 | 13 | 61 | 0 | 0 | 750 | 70% |
| ilsa (mace / sacred flame cap 8) | 419 | 44 | 5 | 3 | 3 | 0 | 1 | 0 | 475 | 12% |
| foe-melee | 2018 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2019 | 0% |
| foe-ranged (mostly cap 8) | **325** | 224 | 208 | 364 | 151 | 157 | 21 | 1 | 1451 | 78% |

(46 swings at distance 0 — a body standing on a downed target's hex — are
left out of the table.)

Plus 202 Burning Hands cones (radius 2), catching 2.79 foes per cast.

- **Nobody ever shoots past 7 hexes; 8 is hit once in 5,918 events.** The
  cap is not binding for the party at all (`shots at exactly own cap`:
  foe-ranged 43, party 0).
- **Point-blank is the most common ranged distance.** Pike fires adjacent
  (at disadvantage, `combat.gd:786`) for 30% of his shots because the party
  autopilot never repositions a shooter; ranged foes do it 22% of the time
  because `_foe_turn` strikes any adjacent PC before checking `m.ranged`.
- Range 4 is the modal *real* ranged distance for both sides. Range 2–4
  holds 60% of Pike's shots and 55% of foe shots; ≥5 is 10–23%.
- Sacred Flame (cap 8) averages 2.43 hexes, max 7. Ilsa casts it 53 times
  against 419 mace swings: the autopilot closes to melee and only casts when
  no foe is in mace reach.
- Damage: party 8,609 melee / 4,243 ranged (33% ranged); foes 8,070 / 3,113
  (28%). Opportunity attacks: 24 in 150 fights (22 by the party), 99 damage
  total — OAs are not a factor.
- Per theme, ranged share tracks roster not geometry (T35's finding holds):
  goblin-camp 42% (3.0 ranged foes/fight) vs frozen-cave 17% (0.0).
- Win 63.3%, 9.87 rounds, universal adjacency round 7.0, 59 fights never
  reach it. (T35 published 74.7% on this same harness; since then
  `SPAWN_GAP` went 3→6 and T38 retuned `TIER` — this is today's number.)

## 3. Candidates

| run | edit | win | len | party dmg m/r | foe dmg m/r | sacred flame | cones | max d used |
|---|---|---|---|---|---|---|---|---|
| **baseline** | — | 63.3% | 9.87 | 8609 / 4243 | 8070 / 3113 | 53 | 202 (r2) | 8 |
| RANGE_CAP 6 | `adapter.gd:13` | 63.3% | 9.88 | 8609 / 4298 | 8060 / 3113 | 52 | 202 | 8 (foes; party 6) |
| RANGE_CAP 10 | `adapter.gd:13` | 63.3% | 9.87 | identical | identical | 53 | 202 | 8 |
| RANGE_CAP 12 | `adapter.gd:13` | 63.3% | 9.87 | identical | identical | 53 | 202 | 8 |
| spells uncapped, weapons capped | `adapter.gd:242` drop `mini(RANGE_CAP,…)` | 63.3% | 9.87 | identical | identical | 53 | 202 | 8 |
| FT_PER_HEX 5 | `adapter.gd:12` | **74.0%** | 9.07 | 7565 / 4284 | 7358 / 2491 | 30 | **282 (r3)** | 8 |

**Finding C1 — `RANGE_CAP` is inert on current boards.** 6, 8, 10, 12 and
"no cap for spells" produce byte-identical fights (cap 6 differs by one
blocked Sacred Flame and Pike hitting his cap 61 times instead of never).
Board diameter ≤ 10 and spawn distance ≤ 6 mean no shot is ever attempted
past 7. What a lower cap *would* have blocked in the baseline: cap 6 → 25
shots, cap 5 → 244, cap 4 → 412, cap 3 → 973 of 1,722 ranged events. Range
only becomes a design variable at cap ≤ 5 — or with boards twice the size.

**Finding C2 — `FT_PER_HEX = 5` is +10.7 win-rate points, and it's all
party-side.** Party speed 5→6 hexes, Burning Hands cone 2→3 hexes (282
casts, 3.04 caught vs 2.79), 30 ft spells 5→6. Monsters unchanged (§1d).
Ranged share barely moves (Pike 70%→73%); fights are shorter because the
cone does more. The mirror of T35's FT 8/10 result. Not a hex-scale change;
a party buff.

## 4. Reading the ranged↔melee balance

1. **Melee closes on turn 1, every fight.** Speed 5 vs a maximum spawn
   distance of 6 (usually 3–5). There is no approach phase for anyone to
   shoot into; ranged play is "shoot the thing that's already next to
   someone", which is why the modal distance is 4 (across the melee) and
   the second most common is 1.
2. **The ranged/melee split is roster and autopilot, not geometry** —
   T35/T36 said this and the per-actor histogram confirms it from the
   other side: the only party member who shoots at range does so 70% of
   the time regardless of every knob; the cleric with an 8-hex cantrip
   casts it 12% of the time because the autopilot prefers the mace.
3. **Range tiers don't exist.** Three spell ranges (1/5/8), five weapon
   ranges (1/3/4/5/7/8), and the top tier is never reached. A longbow, a
   shortbow and Fire Bolt are the same tool.
4. **Point-blank shooting is the biggest unpriced behaviour.** 549 of
   2,201 ranged shots are at distance 1 with disadvantage. That's a
   ranged-side *penalty* the balance currently absorbs silently; if an AI
   ever learns to step back first, ranged output rises ~15–20% with no
   constant changed.

## 5. Recommendation

Nothing here argues for touching `FT_PER_HEX`, `RANGE_CAP` or `SPAWN_GAP`
again — all three have now been swept alone and in pairs across T35–T37
and this spike, and none of them reaches the thing they were meant to
reach on these boards.

In order of value:

1. **Author `range_ft` for the 29 unauthored castable spells** (§6). Data
   fix, no engine change. Until then Hold Person is a touch spell.
2. **Decide what range should *mean* before tuning it.** Two honest
   options: (a) accept 3 tiers (touch / 5 / 8) as the game's grammar and
   set the cap where it bites — `RANGE_CAP 5` would block 244 baseline
   shots and make 60 ft+ spells and bows a real "reach across the room"
   tier vs 30 ft's 5; or (b) enlarge boards to diameter 14–16 *and* fix
   `_foe_spots` so `SPAWN_GAP` can actually be honoured (T35 found wide
   boards inert for exactly this reason). (a) is a one-line experiment;
   (b) is the only path on which longbow ≠ shortbow ever matters.
3. **If `FT_PER_HEX` is ever changed, re-bake the bestiary in the same
   commit** (`speed`, `atk_range`) or convert in `Encounter.spawn`. As it
   stands the constant is a party-only multiplier and every past
   measurement of it (T35, T37, this) is a measurement of that.
4. **Don't sweep the autopilot.** Pike's 30% point-blank rate and Ilsa's
   mace preference are `ai.gd` choices; the sweep's ranged share is bounded
   by them, not by the board. A real player won't play like this, so use
   the sweep for *foe* behaviour and the static tables for the party.

## 6. Unauthored castable spells (default 5 ft → 1 hex)

burning-hands (cone, no range needed), charm-person 30, ensnaring-strike
(self), heroism 5, hunters-mark 90, calm-emotions 60, hold-person 60,
invisibility 5, moonbeam 120, phantasmal-force 60, web 60,
crusaders-mantle (self), hypnotic-pattern 120, lightning-bolt (line),
stinking-cloud 90, banishment 30, charm-monster 30, dominate-beast 60,
evards-black-tentacles 90, freedom-of-movement 5, greater-invisibility 5,
ice-storm 300, wall-of-fire 120, dominate-person 60, flame-strike 60,
hold-monster 90, insect-plague 300, modify-memory 30, steel-wind-strike 30.

Numbers are the catalog's range in feet; several also need a `size_ft`
and a shape before they're anything but a single-target save.

## Reproduce

```
godot --headless --path . -s tests/sweep_range_detail.gd
# candidates: edit the one constant named in §3, rerun, git checkout -- core/adapter.gd
```

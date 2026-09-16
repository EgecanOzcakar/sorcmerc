# sorcmerc — Combat Design (MVP: one encounter)

**Pitch:** three mercenaries, one room, four monsters, a lit brazier, and a turn order you can
read three turns ahead. You lose if you play it like a DPS race.

**References drawn from:** Into the Breach (visible turn order + perfect information as the
decision surface), Solasta (the best-executed 5e action-economy UI), Baldur's Gate 3 (shove and
environment as a real answer, hit chance always on screen), Darkest Dungeon (positional discipline
without a grid), XCOM (percentage-forward commitment), Slay the Spire (short readable loop,
numbers you can do in your head).

---

## 1. Core loop

**The 10–30 second cycle:**

> Read the board (who's where, who's next, who's about to die) → pick the one thing you can
> afford to do with this character's action → watch the d20 resolve against numbers you already
> knew → the board shifts and the next actor is someone else's problem.

**Why it stays interesting for the ~18 turns of one encounter:**

Because the loop is not "choose damage." It's **choose what to spend**, and there are four
different currencies bleeding at once:

1. **Your action** — the biggest one. Damage now vs. setup that makes an ally's turn better.
2. **HP** — standing in the Brazier Hall is where the fight is decided and where you get hit.
3. **Slots and 1/encounter buttons** — Ilsa's six slots, Vera's Action Surge and Second Wind.
   Spend early and win the race; spend late and you may not get to.
4. **Turn order position** — you can't reorder your party. If Ilsa acts before Vera, Healing Word
   comes at the wrong time. You play *around* initiative, you don't fix it.

The anti-boring guarantee: **no character's best action is the same two turns in a row**, because
the board changes underneath them. Vera's "kill the goblin vs. shove the bugbear prone" flips the
moment Pike needs advantage. Ilsa's Burning Hands is the correct play for exactly one round and
the wrong play the round before and after.

**The one-sentence test the build must pass:** if a playtester can win by mashing `1` (Attack)
on every turn, the design failed and the tuning numbers in §7 are wrong, not the mechanics.

---

## 2. Initiative and turn structure

### Initiative
- `d20 + DEX mod`, rolled once at encounter start, static for the whole fight.
- Ties broken by higher DEX mod, then by a coin flip (record it, don't re-roll).
- **The player does not choose which of their characters goes when.** This is the cheapest and
  best constraint in the whole design. A party that always acted in a chosen order is three solo
  puzzles; a party locked into `Pike → Grull → Ilsa → goblins → Vera` is one puzzle.
- The full order is **on screen at all times**, with a cursor and the next four actors visible.
  This is the single highest-value UI element in the game. It converts "what do I do" into "what
  do I do *before Grull swings*."

### Action economy — what earns its keep in an MVP

| Slot | Verdict | Why |
|---|---|---|
| **Action** | Keep, obviously | The decision. |
| **Move** | Keep | 0 or 1 zone. Cheap, and it's what makes the board a board. |
| **Bonus action** | Keep — **but only because all three PCs have a real one** | A bonus action prompt that's empty for two of three characters is a dead key press. Every PC here has a genuinely tempting bonus: Ilsa's Healing Word, Vera's Second Wind, Pike's Cunning Action. It earns its keep *only* under that condition — see §11. |
| **Reaction** | **Keep. Free ones auto-resolve; one that spends a slot stops and asks.** | This was the most important architectural line in the doc, and it read "zero reaction *prompts*" for a reason: prompting means pausing a monster's turn mid-resolution, asking the player, and resuming, and that turns the turn resolver into a coroutine. *(2026-09-16, in two steps. First `fire_reactions()` landed — a general trigger dispatcher over `hit_by_attack`, `damaged_by_attack`, `spell_cast`, with Uncanny Dodge, Hellish Rebuke and Counterspell riding it, all auto-resolved. Then the prompt landed too, and **the resolver still did not become a coroutine**: the question is asked one step earlier, by whoever is about to call it. `core/ai.gd` calls `cb.offer_reactions()` before each swing and each cast, that is the one function in the engine that can suspend, and `fire_reactions()` reads the recorded answer back synchronously when the trigger fires. Cost of the compromise: the answer is given against the hit chance rather than against the damage — you decide before the d20, and nothing is spent if the swing misses. Only slot- and pool-spending reactions ask; an opportunity attack and Uncanny Dodge still fire by themselves, because a question with one sensible answer is a key press, not a decision.)* |
| **Free object interaction** | **Cut.** | Nothing to interact with. |

**Turn structure, final:**

```
BEGIN TURN → tick statuses (dodging expires, prone visible, death save if at 0 HP)
           → player spends, in any order: Move (1 zone) / Bonus action / Action
           → END TURN
```

Order-agnostic spending matters: "move then attack" and "attack then move" are different plays
(hit and back out of the brazier). Do not force a fixed sequence.

---

## 3. Positioning — recommendation: **three linear zones. Yes, it's worth it.**

**Verdict: build zones. Not a grid, not "melee/ranged tags", not an abstract `engaged` boolean.**

Three named zones in a line:

```
    THRESHOLD  ←→  BRAZIER HALL  ←→  ALCOVE
    (PC start)     (the hazard)      (half cover)
```

Rules, complete:
- Every creature is in exactly one zone. `zoneId: 0 | 1 | 2`.
- **Move** = step to an adjacent zone, or stay. **Dash** (action) = two steps.
- **Engaged** is emergent, not a stat: you are engaged if a hostile shares your zone. Free.
- **Melee** attacks require the same zone. **Ranged** attacks reach any zone, but have
  **disadvantage if a hostile shares your zone** (5e RAW, and it's the rule that keeps archers
  honest).
- **Leaving a zone that contains a hostile provokes an opportunity attack from each hostile in
  it**, unless you Disengaged. Auto-resolved.
- **Alcove: half cover.** +2 AC and +2 to DEX saves for anything in it. (Sacred Flame explicitly
  ignores cover — that is a *designed answer to a designed problem*, see §7.)
- **Brazier Hall: the brazier.** Not passive damage. It's ammunition for Shove (§4).

**Why zones and not less:** with no positioning, six of the seven verbs collapse. Move, Dash,
Disengage, opportunity attacks, area-of-effect targeting, cover, and half of Shove all stop
meaning anything, and you are left with attack-until-dead. Zones are what make the verb list a
verb list.

**Why zones and not more:** a grid costs you pathfinding, cone/sphere templates, reach and
diagonals, and a renderer that can draw all of it in a terminal. That's the whole two-day budget
spent on geometry. Zones are ~40 lines and buy 80% of the tactics.

**Why linear and not a graph:** the Alcove is only reachable through the Brazier Hall. That
chokepoint is why the fight happens on top of the hazard. A loop or a fourth zone lets the player
route around the interesting part.

---

## 4. The verb set

This is the minimum set where the player has a real choice. Each verb is here because there is a
readable, recurring board state in which it **beats Attack** — that's the bar. Anything that
never beats Attack is a menu item, not a mechanic.

### Actions (one per turn)

| Verb | Rules | When it beats Attack |
|---|---|---|
| **Attack** | `d20 + atk` vs AC. Crit on 20 (Vera: 19–20) = double the damage dice, not the modifier. Melee = same zone; ranged = any zone, disadvantage if engaged. | The baseline. It's correct maybe half the time and that's fine. |
| **Cast a Spell** | Ilsa only. See §5. | When the board clusters, or when someone is down. |
| **Dodge** | Attacks against you have disadvantage until your next turn; you have advantage on DEX saves. | You're at low HP with Grull on you and Ilsa acts before your next turn. Turns 11 damage/round into ~6 and buys the heal. |
| **Dash** | Move two zones instead of one. | Round 1, and any time the archer has to be answered in person. |
| **Disengage** | Your movement this turn provokes nothing. | Peeling a bloodied Pike out of the brawl through two hostiles. |
| **Help** | Name an ally and a target: that ally's next attack roll before your next turn has advantage. | Ilsa is out of slots and Vera is swinging at AC 16. Also the rescue button for Pike's Sneak Attack. **Cut candidate #1** — see §11. |
| **Shove** | Replaces your attack. Athletics vs. target's better of Athletics/Acrobatics. On success pick one: **knock prone** / **push 1 zone** / **push into the brazier for 2d6 fire** (Brazier Hall only). | Constantly. Prone = advantage for every melee ally + the target burns half its move standing. The brazier = 7 avg damage with no attack roll. The push = drag the archer out of cover, or shove a goblin off Ilsa. |

Prone: attacks against a prone creature have advantage in melee, **disadvantage at range**;
standing costs your entire move.

### Bonus actions (one per turn)

| Who | Verb |
|---|---|
| **Ilsa** | **Healing Word** (spell slot) |
| **Vera** | **Second Wind** — heal `1d10+3`, 1/encounter. **Action Surge** — take an entire second Action, 1/encounter (free, not technically a bonus action; give it its own menu row). |
| **Pike** | **Cunning Action** — Hide, Disengage, or Dash |

**Hide** (Pike, and goblins via Nimble Escape): Stealth vs. the enemy's passive Perception (9).
On success: attacks against you have disadvantage, and **your next attack has advantage** — which
is Pike's private key to Sneak Attack. Hidden breaks the instant you attack. **No vision system,
no line-of-sight, no "you can't target it."** Hidden is a two-flag status. That's the whole thing.

### Passives worth their line count

- **Sneak Attack (Pike):** +2d6, once per turn, if you have advantage on the attack **or** an ally
  is engaged with the target — and you don't have disadvantage. This one conditional is what makes
  Pike a positional character instead of a second fighter. Ten lines, enormous return.
- **Nimble Escape (goblins):** bonus action Disengage or Hide. Makes the goblins skirmishers who
  punish you for chasing.
- **Surprise Attack (Grull):** +2d6 on a hit against a creature that has not yet taken a turn this
  combat. *House rule* (RAW requires surprise) — it makes the initiative roll matter, loudly, in
  round 1. Flag it in the log so the player learns the rule from being hit by it.

### Deliberately cut

**Grapple** (a second contested check that duplicates Shove), **Ready an action** (needs the
reaction/interrupt system), **Two-Weapon Fighting** (competes with the bonus actions that already
justify the slot), **Opportunity attack prompts**, **concentration** (see §5), **reach**,
**flanking** (free advantage for standing next to each other would make Shove and Help pointless
and collapse the correct play into "everyone melee the same guy"), **exhaustion**, **encumbrance**,
**resistances**, **temp HP**.

---

## 5. The two spells

Both belong to Ilsa. The pair is chosen so that they cover the maximum number of orthogonal axes
per line of code: **offense/support, action/bonus action, area/single-target, save/no-roll,
front-line/any-range.**

### 1. Burning Hands — Action, 1st-level slot

> **Every other creature in your own zone** makes a DC 13 DEX save. `3d6` fire, half on a save.
> Upcast to 2nd level: `4d6`.

The cone is abstracted to "your zone, not you." This is not a simplification — it's the *point*.
It means Ilsa has to **walk into the brawl** to cast her big spell, and it means **it hits Vera
too**. Average 10.5 deletes both 7-HP goblins; average 10.5 also puts your AC-18 anchor at half
health. Every cast is a real question with a wrong answer.

Cost to build: reuses the save resolver you need anyway + `creatures.filter(c => c.zone === self.zone && c !== self)`.

### 2. Healing Word — Bonus action, 1st-level slot, any zone

> `1d4+3`. A creature at 0 HP stands up conscious at that HP, and its death saves reset.
> Upcast: `+1d4` per level.

This spell is what makes the **bonus action slot earn its keep** — cast it and still attack in the
same turn. It is also the encounter's pacing valve: going down becomes a tempo disaster instead of
a death spiral, which lets you tune the fight genuinely hard (§7) without it being unfair. And it
gives the monster AI a real decision to make about finishing people off.

Cost to build: ~10 lines.

### Ilsa's cantrip is not one of the two

**Sacred Flame** (DC 13 DEX save, `1d8` radiant, **target gains no benefit from cover**) is a
cantrip, not a spell slot, and it's her at-will. It exists mainly because it is the *scripted
answer* to the archer in the Alcove — a puzzle the player gets to solve by reading a tooltip.

### What we lose by capping at two: concentration

With two spells and neither of them concentration, **concentration is dead code — cut it
entirely**. Say so out loud so nobody builds a save-on-damage system for zero users. If a third
spell is ever added, make it a concentration spell (Bless or Faerie Fire) and concentration
becomes the interesting thing it should be.

### Slots

Cleric 3: **four 1st-level, two 2nd-level.** Keep the 2nd-level slots — "do I burn the big one
now" is exactly the resource tension the loop needs, and upcasting is one line.

---

## 6. What the player sees each turn

Perfect information about the *present*. No hidden AC, no hidden hit chance, no hidden enemy HP
band. The decision should be hard because the tradeoff is hard, not because you're guessing.

```
────────────────────────────────────────────────────────────────────────────
 ROUND 2                                        THE SUNKEN SHRINE
────────────────────────────────────────────────────────────────────────────
  THRESHOLD              │  BRAZIER HALL  🔥      │  ALCOVE  (half cover)
  ─────────              │  ─────────────         │  ──────
  Ilsa    ██████░░ 16/22 │ ▶Vera  ████████ 28/28  │  Kritch  ███████░ 6/7
                         │  Grull ██████░░ 21/27  │    hidden
                         │  Snik  ███░░░░░ 3/7    │
                         │  Pike  █████░░░ 13/21  │
                         │  Vess  ████████ 7/7    │
                              ↑ prone
────────────────────────────────────────────────────────────────────────────
 ORDER  Pike(19) → Grull(15) → ▶VERA(14) → Kritch(12) → Ilsa(9) → Snik/Vess(7)
                                          you act again after Vess
────────────────────────────────────────────────────────────────────────────
 VERA KORD · Fighter 3 · AC 18 · HP 28/28 · move: available · bonus: available
 Second Wind ●  Action Surge ●
────────────────────────────────────────────────────────────────────────────
 ACTION
  1) Attack  longsword +5, 1d8+3  (crit 19-20)
       a) Grull   AC 16 → 50%   b) Snik  AC 15 → 55%   c) Vess  AC 15 → 55%
  2) Shove   Athletics +5 vs contest        → prone / push 1 zone / brazier 2d6
  3) Dodge   attacks vs you have disadvantage until your next turn
  4) Dash · 5) Disengage · 6) Help
 BONUS   7) Second Wind  1d10+3
 FREE    8) Action Surge — take a second Action
 MOVE    9) → Threshold  ⚠ provokes: Grull, Snik, Vess     0) end turn
────────────────────────────────────────────────────────────────────────────
 ⚑ Grull hit Pike: d20[13]+4 = 17 vs AC 15 — HIT, morningstar 2d8+2 = 13. Pike 13/21.
 ⚑ Pike hid behind the pillar. Stealth 22 vs 9 — hidden.
 ⚑ Vera shoved Snik prone. Athletics 18 vs Acrobatics 11.
────────────────────────────────────────────────────────────────────────────
```

Non-negotiables in that mock:

1. **Hit percentage next to every target.** 5e players compute this anyway; hiding it just adds
   arithmetic, not tension. This is the single highest-leverage UI decision in the game — it turns
   a menu into a decision.
2. **The full initiative order with "you act again after X."** Lets the player plan two turns
   ahead. This is where the tactics actually live.
3. **`⚠ provokes: Grull, Snik, Vess`** on the move option. Never let a player eat three
   opportunity attacks they couldn't have known about.
4. **Advantage/disadvantage flagged on the option, before committing** — e.g. Pike's ranged
   attacks show `(disadv — engaged)` in red, and after a Hide they show `(ADV)`.
5. **Every roll printed with its parts.** `d20[13]+4 = 17 vs AC 15`. With advantage, show both
   dice and dim the discarded one: `d20[13̶ 19]+4`. Trust is built by showing the math.
6. **Exact HP for everyone, friend and foe.** Hidden monster HP would make "can I kill it this
   turn?" a coin flip instead of a plan.
7. **Confirm before committing.** The player must be able to back out after picking "Attack" and
   before picking a target.

---

## 7. The encounter: **The Sunken Shrine**

### Party (all level 3, no magic items)

**Vera Kord — Fighter 3 (Champion).** AC 18, HP 28, init +0.
Longsword +5, `1d8+3`. Crit on 19–20. Athletics +5. Second Wind, Action Surge.
*Role: the anchor. Her turn is "kill the small thing or set up the big one."*

**Pike Sallow — Rogue 3.** AC 15, HP 21, init +3.
Shortsword / shortbow +5, `1d6+3`. Sneak Attack `2d6`. Cunning Action. Stealth +7. Acrobatics +5.
*Role: the conditional. He does double damage only if he earns it, every single turn.*

**Ilsa Vane — Cleric 3 (Light Domain).** AC 16, HP 22, init +1.
Save DC 13. Mace +3 `1d6+1` (deliberately pathetic). Sacred Flame, Burning Hands, Healing Word.
Slots: 4× 1st, 2× 2nd.
*Role: the spender. Every turn is "is this the round?"*

### Monsters

**Grull, Bugbear.** AC 16, HP 27, init +2. Morningstar +4, `2d8+2` (avg 11, max 18).
Surprise Attack: +`2d6` vs. anyone who hasn't acted yet this combat.
*He can two-shot Pike. He exists to make Dodge and Healing Word necessary.*

**Snik & Vess, Goblins.** AC 15, HP 7, init +2. Scimitar +4, `1d6+2`. Nimble Escape.
*7 HP means Vera one-shots one on most turns and Burning Hands wipes both. Legible payoffs.*

**Kritch, Goblin Archer.** AC 15 (**17 in the Alcove**), HP 7, init +2. Shortbow +4, `1d6+2`.
Nimble Escape.
*The pressure that makes movement the point. He is a slow bleed you must walk across the room to
stop — through Grull.*

### Setup

```
THRESHOLD              BRAZIER HALL 🔥          ALCOVE (half cover)
Vera, Pike, Ilsa       Grull, Snik, Vess        Kritch
```

### Monster AI — specify it or the architect loses a day here

Priority list, evaluated top-down. This is the entire AI:

1. If any conscious hostile shares my zone and I can melee → attack the one with the **lowest
   current HP**; ties go to lowest AC.
2. Goblins only: after attacking, if my HP is below half → Nimble Escape (bonus Disengage) and
   move one zone away from the largest hostile group.
3. Kritch only: if a conscious hostile enters my zone → Nimble Escape, move to Brazier Hall or
   stay if cornered; otherwise shoot the **lowest-HP conscious PC**.
4. If no hostile in my zone → move one zone toward the nearest zone containing a conscious PC.
5. **Never attack a downed PC while a conscious PC is in reach.** A mercy rule and a tuning knob —
   it is the difference between "tense" and "feels-bad." Expose it as a constant.

~25 lines. Do not make it smarter than this without playtest evidence.

### Tuning math (why this is winnable but not trivial)

- Enemy HP pool: **48**. Party effective damage: ~16–18/round → **~3 rounds** if the party plays
  well. Burning Hands into both goblins compresses that to two.
- Enemy damage: Grull ~6/round expected, three goblins ~8/round → **~14/round** vs. a **71 HP**
  party pool → ~5 rounds to a TPK.
- The party wins the race by roughly two rounds. **That margin is the entire difficulty budget.**
  It disappears if you chase goblins across zones, leave Ilsa in the front, cast Burning Hands on
  the wrong round, or let Kritch shoot for free in the Alcove.
- Grull focus-firing Pike (21 HP) can drop him in **round 2**. That's intentional — it's the
  scripted moment where the player learns what Healing Word is for.
- Adjusted XP ≈ 700 for three level-3 PCs = **Hard**. Hard is where 5e is fun, and Healing Word
  plus the mercy rule are the safety net that lets it be hard.

**Tuning knobs, in the order to reach for them:** Grull's HP (27 → 22), the mercy rule, Kritch
starting in the Brazier Hall instead of the Alcove, and Ilsa's 2nd-level slot count.

---

## 8. Progression & pacing across the encounter

One encounter still needs an arc. The shape is designed, not emergent:

**Round 1 — Approach.** Nobody is engaged. The correct plays are all positional: Vera Dashes or
moves in, Pike Hides and takes a ranged Sneak Attack, Ilsa holds slots. Grull's Surprise Attack
punishes whoever rolled low initiative. *Teaches: zones, movement, hiding.*

**Round 2 — Contact.** The brawl forms in the Brazier Hall. Opportunity attacks fire for the first
time. Shove becomes correct. Someone is probably below half. *Teaches: engagement, the OA rule,
ranged-while-engaged disadvantage.*

**Round 3 — The spike.** Grull drops a PC or comes close. Burning Hands is exactly right or
exactly wrong. Second Wind and Action Surge are burning holes in the player's pocket. *This is the
peak — highest stakes, most resources on the table, most information to weigh.*

**Round 4 — Cleanup with a sting.** Goblins are dying or fleeing on Nimble Escape. Kritch is still
in cover being annoying. Someone is on death saves. The player's remaining slots decide whether
this is a win or an ugly win.

**Round 5+ — Only if it went badly.** The failure mode must stay legible: you are out of slots,
Grull is at 12 HP, Vera is at 6, and you can see the arithmetic. Losing should feel like a
sentence you can read.

**Escalation levers already in the box** (no new systems): Grull's damage variance (`2d8+2` swings
4–18), the shrinking slot pool, death save accumulation across the fight (a PC that goes down twice
is one bad round from dead), and the goblins retreating on low HP which stretches the fight out
exactly when the party can least afford it.

---

## 9. Feel

A terminal game's juice budget is timing, color, and word choice. Spend it in this order:

**Input responsiveness**
- Numbered menu + `readline`. No arrow-key raw mode, no TUI framework. One keypress → one visible
  reaction.
- **Every destructive choice is two steps with a back-out**: pick verb → pick target (with the
  hit % shown) → resolve. `b` goes back. Never commit on the first key.
- Never require Enter for a single-digit choice if you can avoid it; if you can't, don't fight it.

**The roll is the moment — animate exactly this and nothing else**
- Print `Vera swings at Grull...`, sleep **~350ms**, print the die, sleep **~200ms**, print the
  total and the outcome. One shared `PAUSE` constant, one `--fast` flag that sets it to 0 for
  playtesting and tests. That single pause is 90% of the game's felt drama.
- Advantage/disadvantage prints **both dice**, dimming the discarded one. Players love watching a
  bad roll get thrown away.

**Outcome differentiation — the same event should never read the same twice**
- **Crit:** its own line, bright, with the doubled dice shown separately: `CRIT! 2d8+2 → 4d8+2 = 24`.
- **Nat 1:** a flavor miss line, one of three or four variants per weapon.
- **Kill:** the creature's row visibly leaves the zone panel. Say how it died.
- **Downed:** the row goes dim with a strikethrough name and a death-save tracker `[✗ · ·]` that
  ticks in front of the player once per round. Nat 20 on a death save popping someone back up at
  1 HP is the best moment in 5e — make sure it's loud.
- **Damage numbers colored** by band (chip / solid / big). HP bars in block characters, colored by
  fraction, with the exact numbers next to them.

**Language**
- Combat log is terse past tense, one line per event, monsters and PCs in different colors.
  `Snik lunges — 9 vs AC 18, turned aside.` Not `Snik attacks Vera. Miss.`
- Status changes get their own line with a symbol: `↓ Snik is prone.` `🔥 Vess is shoved into the
  brazier — 2d6 = 9 fire.` `👁 Kritch loses sight of Pike.`
- The room gets three sentences of description at the top of round 1 and never again.

**Anti-juice (things that will feel bad — don't build them)**
- No clearing the screen between every action; the log scrolling is the memory of the fight.
- No spinner animations. No progress bars. No sound.
- No "press any key to continue" between monster turns — batch the whole enemy round with paced
  prints, then hand control back.

---

## 10. Feasibility note for studio-architect

**Cheap — build without hesitation** (each is tens of lines, all pure functions, all trivially testable):

- `roll(n, sides)`, `d20(mode: 'normal'|'adv'|'dis')`, attack resolution, damage, crits.
- Saving throws — one function, shared by Burning Hands, Sacred Flame, and nothing else.
- Zones: `zoneId: 0|1|2`, adjacency is `Math.abs(a-b) === 1`. AoE is one `.filter()`.
- Statuses as `Set<string>` on the creature: `prone`, `dodging`, `hidden`, `down`, `helped`.
  Do not build a status *system* with durations and stacking — five flags cleared at known points.
- Death saves. Opportunity attacks (auto-resolved on a move that leaves an occupied zone).
- Contested shove (two `d20 + mod`).
- Monster AI as the literal priority list in §7.
- Rendering: `process.stdout.write` + raw ANSI escapes. No `ink`, no `blessed`, no `chalk` — a
  dozen `\x1b[..m` constants covers it, and the repo currently has zero runtime deps. Keep it that way.

**Risky / where the time actually goes** (in descending order of danger):

1. **Reaction prompts.** Interrupting a monster's turn to ask the player a question means the turn
   resolver can no longer be a straight-line function. **The MVP has zero of these.** If Warding
   Flare or Shield is ever added, that's the day it becomes an async/generator-based resolver.
   *(2026-09-16: reactions shipped, then prompts shipped, and that day still has not arrived.
   `fire_reactions()` resolves a reaction inline off the creature's own data; when the answer is
   the player's to give, `offer_reactions()` collects it from the caller one step before the
   action resolves. Only that one function suspends, so `perform()`, `cast()`, `resolve_attack()`
   and `move_to()` are the same straight-line calls they always were and their ~100 call sites
   never changed. What it costs is fidelity, not architecture: the choice is made before the roll
   rather than after the hit.)*
2. **Monster AI creep.** The temptation to make goblins "smart" is where a two-day build becomes a
   week. Cap it at the five rules. Tune with numbers, not with cleverness.
3. **The action-order-agnostic turn.** Letting the player move before *or* after their action means
   turn state is `{moveUsed, actionUsed, bonusUsed}` and the menu re-renders against it. Not hard,
   but it's the one place where sloppy state produces "I attacked and lost my move" bugs. Model it
   explicitly.
4. **Terminal layout.** Column alignment with variable-width HP bars and color codes will eat an
   hour if you fight it. Pad on the *uncolored* string length; wrap that in one helper on day one.
5. **Targeting UX.** "Pick a verb, pick a target, back out" is more branching than it looks.
   One small state machine, not nested prompt calls.

**Do this on the first commit:** a **seeded RNG** (mulberry32, six lines) with the seed printed in
the header and settable by env var. In a dice game, "reproduce that fight" is the difference
between debugging and guessing, and it makes the whole combat resolver deterministically testable
with `node --test`, which the repo is already wired for.

**Minimum test surface** (the repo already has `tsx --test`): one file that asserts advantage beats
normal over a fixed seed, that a crit doubles dice and not the modifier, that Burning Hands hits
allies in the caster's zone and not the caster, that moving out of an occupied zone provokes and
Disengage prevents it, and that Healing Word on a downed PC clears death saves. That's five
asserts and it covers every rule that can silently rot.

---

## 11. Cut list, in order

If day two is running out, cut in this order — each cut is designed to leave the loop intact:

1. **Help.** Its job (granting advantage) is covered by Shove and Hide. It's the only verb that's
   sometimes just filler.
2. **Upcasting.** Six 1st-level slots instead of 4+2. Loses one resource decision.
3. **Kritch.** Three monsters instead of four. The encounter gets easier and the Alcove gets
   quieter, but Sacred Flame's cover-piercing loses its reason to exist.
4. **The brazier.** Shove keeps prone and push. Loses the room's personality.
5. **Bonus actions entirely.** — **This is the load-bearing cut and it should be the last one.**
   Cutting it kills Healing Word, Cunning Action, and Second Wind in one stroke, and takes about
   half the turn's texture with them. If you're considering this, cut the encounter's scope instead.

**Never cut:** the visible initiative order, the hit percentages, the roll animation pause, or
Sneak Attack's conditional. Those four are the design.

---

## 12. Playtest checklist

The first playtest is looking for evidence, not opinions. Instrument the game to answer these.

**Does the loop hold?**
1. **Log every choice.** What fraction of turns were plain Attack? **If it's above ~55%, the design
   has failed** and the other verbs are underpriced. Look for the verb with near-zero uses and ask
   whether it beat Attack *ever*.
2. Did the player ever pause visibly before choosing? Where? Silence before a keypress is the
   signal that a decision was real.
3. Can the player state, unprompted, what they were planning for **next** turn? If not, the
   initiative display isn't doing its job.

**Is there an obvious dominant line?**
4. Did the player find a repeatable optimal sequence by round 3? Specifically watch for: Shove
   spam, Dodge-turtling while Ilsa cantrips, and Pike hiding every single turn from the Threshold
   (that last one is the most likely degenerate strategy — if ranged Hide → Sneak Attack every turn
   with no downside is correct, Kritch's targeting or Nimble Escape needs to punish it).
5. Was Burning Hands ever cast? On which round, and did the player agonize? A Burning Hands that's
   always correct or never correct is a failed spell.
6. Were Action Surge and Second Wind used at all? Unspent 1/encounter buttons at the end of a win
   mean the fight wasn't hard enough or the buttons weren't visible enough.

**Difficulty and length**
7. How many rounds? **Target 4–6.** Under 4 = trivial. Over 7 = the pool math is wrong or the
   goblins are fleeing too effectively.
8. Did anyone go down? **Target: exactly one PC down, once, and recovered.** Zero = too easy. Two+
   = check whether the mercy rule fired.
9. Did the player lose? Could they articulate *why*? An unreadable loss is worse than a hard one.

**Comprehension — the rules should be learnable from the log**
10. Did the player understand why an attack had advantage/disadvantage, every time it happened?
11. Did they ever eat an opportunity attack they didn't expect? (If yes, the `⚠ provokes` warning
    isn't loud enough.)
12. Did they understand that ranged attacks while engaged have disadvantage — and did they change
    their play because of it?
13. Did they correctly guess what a Shove would do before doing it?

**Feel**
14. Where did they react out loud? Crits, death saves, the brazier — mark the moments and consider
    whether the budget is spent in the right places.
15. Is the roll pause too slow on turn 40? Time the full encounter with and without `--fast`.
16. Could they read the board at a glance, or did they have to scroll back up? Scrolling back means
    the panel is missing something.

**The single question the playtest exists to answer:**
> **Was any turn boring?** Name it. That turn's character had nothing worth deciding, and the fix
> is either a new board state that makes an existing verb correct, or one fewer verb — never a new
> system.

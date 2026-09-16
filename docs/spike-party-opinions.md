# Spike: opinions between party members, and romance

2026-09-16. A feasibility spike, not a feature: **nothing in the shipped game
reads any of this yet.** What exists on the branch is a model
(`core/party_opinion.gd`, one new field on `core/party.gd`), a headless test
of it (`tests/test_party_opinion.gd`, 708 checks), and a throwaway sweep
(`tests/sweep_party_opinion.gd`) that runs the same 150 seeded fights the
T35 and hex-range spikes used with each proposed combat effect switched on,
so the numbers in §6 are measured rather than guessed. §9 lists the seven
call sites that would turn it into a feature, and §10 what that costs.

The question asked was three questions: can party members have opinions of
each other, can two of them fall in love, and what would either do to a
fight or to the road. Short answers: yes, cheaply, because most of the
machinery already exists (`FactionOpinion` is the same shape one level up,
D3's road cards are the delivery vehicle, D4's approach card is the asking
vehicle); yes, if it is *asked* and never rolled; and at the sizes a 5e
player would accept (+1 AC, -1 to hit, advantage once) the combat effects
are flavour rather than balance — they are below the sweep's ±2.7-point
resolution — while the road effect (a morale point on every check) is the
same size as a pace order and reads immediately.

## 1. What sorcmerc is decides the shape

Every companion in this game is **player-made**. There are no authored
characters with voices, agendas and a writer behind them, and the creator
(`scenes/creator/creator.gd`) does not ask for a gender, an orientation or
a temperament. So the BioWare model — romance as an authored dialogue tree
with a specific NPC, gated on approval — has nothing to attach to. The
model that fits is **Wildermyth / RimWorld / Jagged Alliance 2**:
relationships between *whoever the player brought*, produced by what happened
to them, labelled by a system, told in templated lines. (Appendix A3 corrects
an earlier draft of this line, which also named Battle Brothers — it tracks a
per-brother mood scalar and no pair relationships at all.) That decides four
things:

1. **Personality has to come off the sheet.** The only thing the game knows
   about a character is species, background, class and what they have done.
   Two soldiers get on; a noble and a thief do not; an elf and a dwarf need
   time. That is a *baseline*, and it is where a pair drifts back to when
   nothing happens (§2) — the reason the model does not decay toward 0 the
   way `FactionOpinion` does.
2. **The text is lines, not scenes.** A camp beat is one sentence with two
   names in it (§4's `LINES`), the same register as a D3 road card. Anything
   longer needs a writer per pair, and there are C(roster, 2) pairs.
3. **Romance is the player's decision about their own characters.** It is
   offered, never rolled (§4). And since the game has no gender or
   orientation field, the model is blind to both — any two adults the
   player made can be asked. A per-character opt-out is the one knob worth
   adding at the creator if this ships; it is one boolean.
4. **Pairs, not directions.** "Vera's opinion of Pike" and "Pike's opinion
   of Vera" would double the state for a difference the player almost never
   sees; Wildermyth, Darkest Dungeon 2 and XCOM 2 all store one number per
   pair. Symmetric. **This is the decision A4 most wants revisited**: the two
   games in the survey that model opinion rather than a bond — RimWorld and
   Jagged Alliance 2 — both went directed, and both get something from it
   this cannot express.

## 2. The model — `core/party_opinion.gd`

One float per pair of members, -100..100, keyed `"a|b"` (ids sorted), in a
new `party.relations` dictionary — on the Party, not in a static, because a
relationship is between two *saved* characters and has to round-trip with
them. Plus a status on top: `""`, `"lovers"`, or `"declined"`.

**An unrecorded pair sits at its baseline.** `score()` falls back to
`baseline(a, b)` when nothing has been written, so a fresh party already
means something and the dictionary stays empty until something happens.

| baseline input | value |
|---|---|
| same background temper (soldier/guard, acolyte/hermit, criminal/charlatan, noble/merchant, sage/scribe, the five plain trades, entertainer) | +10 |
| martial↔crooked, gentry↔crooked | -10 |
| gentry↔plain, devout↔crooked, devout↔showy | -5 |
| same species | +5 |
| dwarf↔elf, dwarf↔orc, elf↔orc | -5 |

So the preset party starts: Vera+Ilsa +5 (two humans), Vera+Pike -5 (soldier
and criminal, both human), Pike+Ilsa 0 (thief and acolyte cancel the
kinship). All three read "neutral". The table is small on purpose — it is a
starting point the road overwrites, not a personality system.

**Bands** — what the rest of the game reads:

| band | score | what it means elsewhere |
|---|---|---|
| rivals | ≤ -40 | -1 to hit when adjacent (§6) |
| cold | ≤ -15 | drags morale (§7) |
| neutral | | |
| warm | ≥ 20 | lifts morale |
| bonded | ≥ 50 | +1 AC adjacent, rally on a fall (§6); courtship possible from 60 |
| lovers | status, any score | everything bonded gets; breaks up at ≤ 0 |

**Drift** is 1 point per world-day toward the *baseline*, half a faction's
rate, applied wherever `FactionOpinion.tick` already runs (§9). A pair left
alone settles where their sheets put them; a feud or a bond has to be
maintained by things happening.

## 3. What moves it, and how fast — measured

| event | amount | how often it fires (150 sweep fights, preset party, "normal") |
|---|---|---|
| saved — brought up from 0 HP by this member (Cure Wounds, First Aid) | +12 | 0.59 per fight |
| fought beside — both still standing at the end of a won fight | +1 per pair | 0.87 per fight |
| friendly fire — caught in this member's cone or area | -6 | 0.23 per fight |
| road event passed by this member (D3) | +1 from each other marcher | one roll per 6 world-hours |
| road event failed, `kind: bad` | -2 with each other marcher | |
| camp warming / quarrel (§4) | ±8 | ≤ 1 per long rest, 50% |
| courtship accepted / declined | +15 / -10 | |
| breakup | -20 on top of the fall | |

Net drift per pair over the 150 baseline fights: Pike+Vera +0.7 per fight,
Ilsa+Vera +1.5, **Ilsa+Pike +5.3**. That last number is the finding: Pike
goes down a lot (1.48 party downs per fight, mostly him) and Ilsa is the one
who picks him up, and at +12 a save the healer and the one who keeps falling
would be *bonded* after ten fights and eligible for courtship after twelve.
That is a good story — it is exactly the pair that should get close — but
it is fast, and the sweep's autopilot heals more than a player would. Two
things to do before shipping, both one-liners: count `saved` **once per
pair per fight** (the sweep's baseline row shows 2 shoulder-bonused attacks
and 1 rally with *no* pinned relations — two fights out of 150 where
repeated in-fight heals pushed a pair past 50 on their own), and consider
+8 rather than +12. Everything else moves at a pace where a session's play
shifts a pair one band.

## 4. Romance: the ladder, and the one rule

neutral → warm → bonded → **asked at a camp** → lovers. Every step but the
fourth is the score doing what §3 does to it. The fourth is
`camp_moment()`:

- A long rest (camp kit, or an inn) rolls one beat, half the time, for one
  pair drawn from the active party. A pair below 0 quarrels 60/40; a pair
  above warms 70/30 — a camp pushes a pair the way it is already leaning.
  Warming and quarrel **resolve themselves** and come back in D3's shape
  (`{kind, text, delta, score, band}`): a card that reports.
- If the pair is at 60+, neither is spoken for, both are alive and the pair
  has not said no before, half of those beats are a **courtship** instead —
  and that comes back in D4's shape, `options: ["accept", "decline"]`, with
  **nothing applied** until `answer_courtship()` is called with the answer.
  Accept: lovers, +15. Decline: -10 (awkward for a while, still bonded),
  and the fire never asks that pair again.

That is the one rule: **romance is asked, never rolled.** D3 locked "cards
resolve themselves so fast-forward never has to stop and ask"; this is the
single beat that has to break it, and it breaks it through the mechanism
D4 already built for the approach card, so `world.gd` learns nothing new.

Defaults worth stating because they are choices, not facts:

- **One partner at a time.** `courtship_possible` refuses anyone who already
  has one. Polyamory is deleting one `if`; monogamy is the default because
  it keeps "breakup" meaning one thing.
- **Lovers break up at ≤ 0** and take -20 on top — worse than strangers —
  then can court again if they climb back to 60. A feud between exes is a
  story; a silent status flip is not.
- **Declined is permanent per pair.** The alternative (ask again after N
  days) is a cooldown field; permanent is the one that never nags.
- **No gender, no orientation, no content.** Nothing to model, and
  "lovers" is a label on a party page and a +1 AC. The creator makes
  adults; that is the whole extent of what the game asserts.
- **Death.** The dead cannot be courted; a lover's death is not yet an
  event. It should be one (-something to everyone, more to the partner) —
  it is the obvious next source and it is one call from
  `world.gd`'s `_apply_deaths`.

## 5. Where the player sees it

- **Party page** (`scenes/party/party.gd`): a Relations block, one
  `describe()` line per active pair — "Vera Kord and Pike Sallow — rivals
  (-44)". Six lines at most for a party of four. No portraits, no hearts.
- **The event card** (`scenes/world/event_card.gd`) already draws a D3
  result and D4's options; a camp beat is one more `show_event`. The
  courtship card is the approach card with two buttons.
- **The combat log** for §6: "Vera rallies — Ilsa is down." / "Vera and
  Pike get in each other's way." A -1 nobody can see is nothing.

## 6. Combat — three hooks, measured

The sweep subclasses `Combat` the way the hex spike did and wires in the
three hooks the model exposes. All three take the `Combat` and a
`Combatant` whose `id` is a member id (`Adapter.to_combatant` copies it),
and return 0 / nothing for foes.

| hook | effect | goes in |
|---|---|---|
| `shoulder_bonus` | bonded/lovers adjacent to each other: +1 AC each | `combat.gd` `effective_ac`, next to cover |
| `bicker_penalty` | rivals adjacent to each other: -1 to hit each | `resolve_attack`'s `atk_bonus` |
| `rally` | a bonded partner just hit 0: advantage on the next attack | `_apply_damage`, on the crossing into "down" |

150 seeds, same party, same rosters; one relationship pinned per row:

| variant | win% | rounds | attacks vs a +1 AC | of which turned to a miss | swings at -1 | of which turned to a miss | rallies | rally swings |
|---|---|---|---|---|---|---|---|---|
| baseline (nothing pinned) | 86.7 | 7.06 | 2 | 0 | 0 | 0 | 1 | 1 |
| lovers Vera+Ilsa | 90.0 | 7.17 | 784 | 41 | 0 | 0 | 85 | 74 |
| …shoulder only | 88.7 | 7.11 | 794 | 40 | | | 0 | 0 |
| …rally only | 89.3 | 7.22 | 0 | 0 | | | 87 | 77 |
| bonded Vera+Pike | 87.3 | 6.96 | 201 | 9 | 0 | 0 | 127 | 124 |
| rivals Vera+Pike | 86.7 | 7.09 | 2 | 0 | 265 | 14 | 1 | 1 |
| rivals Vera+Ilsa | 88.0 | 7.21 | 4 | 0 | 665 | 34 | 0 | 0 |
| everyone bonded | 90.7 | 6.81 | 1024 | 56 | 0 | 0 | 301 | 254 |

One standard error on a 150-fight win rate at 87% is **±2.7 points**.

- **Every row is inside the noise.** Lovers +3.3, everyone bonded +4.0 (the
  only one that brushes significance), rivals 0 to +1.3 — a -1 to hit on
  265 swings turned 14 into misses and the fight did not notice. At
  Wildermyth sizes these are things a player *sees* (a rally fires every
  other fight for a bonded pair; that is a log line and a moment) and not
  things that move the balance T38/T40 tuned. That is arguably correct for
  a relationship effect. If they are meant to bite, the sizes are +2 AC
  (half cover) and advantage *plus* a damage die, and then T40's 95/85/75
  targets need re-checking — the hex spike found +10 points from one
  constant; that is the scale a real effect lives at.
- **Which hook you see depends on who your characters are.** Vera+Ilsa
  (two melee) are adjacent most of the fight: 784 attacks against the +1,
  85 rallies. Vera+Pike (melee + archer) are almost never adjacent — 201 —
  but Pike goes down constantly, so Vera rallies 127 times. A tank–healer
  bond and a tank–archer bond are different features, for free.
- **Rally has its own status** (`"rallied"`) rather than reusing Help's
  `"helped"`, because `Combatant.new_turn()` erases `"helped"` at the top
  of the bearer's turn — before an attack can spend it. **Side finding,
  pre-existing:** `act_help` therefore never grants advantage in real play;
  `tests/test_combat.gd:366` checks the flag in the same turn it was set,
  so nothing catches it. Not fixed here — it is not this spike's — but it
  is one line (`combatant.gd:62`, take `"helped"` off `TURN_STATUSES` and
  erase it in `resolve_attack`, which already does) and its own PR.

## 7. Overworld travel — where the effect actually reads

The road is where this system pays, for one reason: a road check is
`d20 + skill + pace`, and a pace order is ±2. A morale point is the same
kind of number, on the same line of the same card, and the player already
knows what it means.

- **Morale on every road check.** `travel_bonus(party)` is the mean score of
  every pair in the marching order cut into -1/0/+1 (≤ -15 / ≥ +20), added
  to the roll next to `pace_bonus` (`travel.gd:280`). One feud in a warm
  party of four pulls it back to 0; two pull it under. The card's roll line
  grows a term: "Survival 14+5+1 vs DC 13".
- **The roll feeds back.** After D3 resolves (`travel.gd:287`),
  `road_result(party, who, ok, kind)`: a pass earns the roller +1 from
  everyone else marching; a failed *bad* event (the snare, the toll, the
  bad ground) costs -2 with each of them. A failed *good* one — the cache
  was not there — is nobody's fault. This is the loop that makes the
  standing orders matter socially: the scout who keeps reading the road
  right is liked for it; the forced march that keeps walking people into
  things is felt.
- **Camp is the relationship screen.** A long rest is the only place the
  party stops with nothing else happening, which is why every game in this
  genre puts these beats there. `camp_moment` slots in beside the ambush
  roll in `world.gd`'s camp handler (and the inn's long rest in
  `settlement_visit.gd`), on the same seeded RNG, drawn *after* the
  ambush check so a jumped camp has no fireside.
- **Road events that need a relationship.** D3.1's `needs` gate already
  refuses to roll a card the world cannot hold. Two more values —
  `"rivals"` (a rival pair is marching) and `"lovers"` — gate events like
  *"An argument on the road"* (bad; Persuasion/Insight by anyone *else*;
  fail: the pair -8 and two hours lost) and *"A long detour past somewhere
  they wanted to see"* (good; no check; lovers +4, one hour). The table
  entries are D3.1's shape exactly; the `_apply` arms are two lines each.
- **Drift** rides `FactionOpinion.tick`'s call in `world.gd`'s `_process`
  (`world.gd:389`): `PartyOpinion.decay(party, dt)`. A paused clock drifts
  nothing, same contract.

Not proposed: a speed effect. Rivals slowing the march would double up on
the pace order and turn a feud into a tax the player cannot see coming.
The road effects above are all on the *roll*, which the card shows.

## 8. Persistence

`relations` is one more key in `world_save.gd`'s `_party_dict` /
`_party_from` and `campaign_save.gd`'s equivalent, via `to_dict` /
`from_dict`. `from_dict` re-keys through the sorted pair key, clamps, and
drops junk, so an old save without the key loads as a fresh party and a
hand-edited one cannot corrupt a pair. Tested.

## 9. The seven call sites

If this ships, these are the edits, in the order that pays soonest:

| # | file | change |
|---|---|---|
| 1 | `world_save.gd:193,207`, `campaign_save.gd:77,94` | `"relations": PartyOpinion.to_dict(party)` / `from_dict` |
| 2 | `scenes/party/party.gd` | the Relations block, `describe()` per active pair |
| 3 | `travel.gd:280` | `+ PartyOpinion.travel_bonus(party)` on the bonus; the card shows the term |
| 4 | `travel.gd:287` | `PartyOpinion.road_result(party, who["id"], ok, e["kind"])` |
| 5 | `world.gd:389` | `PartyOpinion.decay(party, dt)` beside `FactionOpinion.tick` |
| 6 | `world.gd`'s camp handler, `settlement_visit.gd`'s long rest | `camp_moment` → event card; courtship → the approach card's two buttons → `answer_courtship` |
| 7 | `combat.gd:365`, `resolve_attack`, `_apply_damage`, `perform`/`cast` | the three hooks (as `tests/sweep_party_opinion.gd`'s `Measured` does it) and the two sources (`saved`, `friendly_fire`); `main.gd:402` hands `party` to the Combat |

1–5 is a morning: the model is done and tested, and every line is a call.
6 is the real work — a card with two buttons that comes back through
`_on_approach_reported`'s bound-callback path, not `_on_event_ack` (the
drive robots found that trap once already). 7 is the least valuable per
§6's numbers and the most likely to need a retune; do it last, and ship
the log lines with it or not at all.

## 10. Risks and open questions

- **It is the player's own characters.** A player who made four heroes
  and gets told two of them are in love may or may not have wanted that.
  Asking (§4) is the whole mitigation; the creator opt-out is the
  belt-and-braces. Keep the register Wildermyth-light: a line, a label, a
  point of AC.
- **Pacing is the tuning problem, not the effects.** §3's healer–faller
  drift is the number to watch. Once-per-fight saves, +8, and a 1/day
  drift make a bond a thing a session earns; without the cap it is a thing
  a bad fight hands out.
- **A pair the player cannot see is a pair that does not exist.** The
  party page line and the card's roll term are not polish, they are the
  feature; ship 2 and 3 before anything else moves a score.
- **The sweep plays worse than a player.** The autopilot walks Pike into
  melee and heals on reflex; a human downs less and heals more
  deliberately, so §3's rates are an upper bound on saves and a lower
  bound on how much the road matters relative to fights.
- **A lover's death** is not an event yet and should be; the roster keeps
  the dead (`ch.dead`) so the pair survives it, which is right — a
  resurrection restores a relationship that was never removed.
- **Not measured:** anything against a human. The numbers in §6 are the
  autopilot against the scaler's rosters, which is what every prior sweep
  measured too, so they compare; they do not say how the effects *feel*.

## Reproduce

```
godot --headless --path . -s tests/test_party_opinion.gd     # the model
godot --headless --path . -s tests/sweep_party_opinion.gd    # §3 and §6, ~1 min
```

Variants are the `VARIANTS` table at the top of the sweep; the constants
are the top of `core/party_opinion.gd`.

---

# Appendix A — what Darkest Dungeon and its neighbours do, and how much of it transfers

Added 2026-09-16, after the spike above, in answer to two questions: how do
the games that are known for opinionated party members actually model them,
and what do they do about **uncontrollable actions** — the part §6 above does
not touch at all, because every effect it measured is a modifier the player
still steers around.

This appendix is research plus a recommendation. It changes no code.

## A1. Darkest Dungeon 1 — stress, not relationships

DD1 has **no relationships between heroes at all.** The thing people remember
as "my heroes hate each other" is one hero's *Stress* meter plus the barks it
produces, which land on whoever is nearby. Worth saying plainly, because it is
the most-cited reference for a feature it does not have.

The loop: stress 0–100 per hero. Crossing 100 forces a **Resolve Test** —
**25% Virtue, 75% Affliction** by default, shiftable with trinkets. At 200 a
hero has a heart attack: HP to 0 and onto Death's Door, and a second one while
already there kills them.

An Affliction is where the control loss lives. Each of the nine has a chance,
**rolled at the start of the afflicted hero's turn**, to "act out" instead of
doing what the player asked, and a flat 33% to **refuse** specific commands:

| Affliction | act-out chance | what the act-out can be | refuses |
|---|---|---|---|
| Fearful | 31.5% | stress bark, move back, pass the turn | move (33%), camping skill (33%) |
| Paranoid | 31.25% | stress bark, move back, random skill, **attack an ally (3.1%)** | retreat, move, healing, buffs, items (33%); eating (33%) |
| Selfish | 33.3% | stress bark, move back, pass, random skill | camping skill (33%); steals from treasure curios (50%) |
| Masochistic | 33.3% | stress bark, move forward, **self-attack**, self-mark | retreat, move, healing, items, camping (33%) |
| Abusive | 29.4% | stress bark (23.5%), **attack an ally (5.8%)** | move, camping skill (33%) |
| Hopeless | 35% | bark, move, pass, random skill, self-attack, self-mark | retreat, buffs, healing, items, camping (33%) |
| Irrational | 33.3% | all of the above, plus **7.5% to touch any curio** | retreat, move, buffs, healing, items, camping (33%) |
| Rapturous | 41.67% | bark, move forward, random skill, **attack an ally**, self-attack | retreat, move, camping (33%); buffs/items (10%) |
| Refracted | 39% | bark, move, pass, attack ally (2.4%), self-mark, **random item use** | healing, buffs, camping (33%); eating (33%) |

Three things about that table matter more than the numbers:

1. **Refusal is the common case; hitting your own people is the rare one.**
   Every affliction refuses something at 33%, and the highest chance of
   attacking an ally on any given turn is 8.3% (Rapturous). The felt
   experience is "my healer will not accept a heal", not "my fighter murdered
   the cleric".
2. **The act-out is rolled per turn and stated in the log.** The player is
   told which hero acted out and what they did. It is a visible dice roll
   with a published table behind it, which is why it reads as the game being
   hard rather than the game cheating.
3. **The barks are the real damage.** An afflicted hero's comments deal **6
   stress** to the whole party (when they are hit, or on an act-out) or to a
   single ally (when that ally attacks or is attacked). That is the spiral:
   one afflicted hero manufactures the stress that afflicts the next one.
   DD1's system is a *contagion* model, not an opinion model.

Virtue is the mirror, and it is worth copying the symmetry: it drops the hero
to 45 stress, reduces the whole party's stress, and act-outs become *good*
unprompted actions — Courageous can spend a turn cutting 25 stress off
everyone, Stalwart can take a hit meant for an adjacent ally and heals 5
stress off an ally on every miss, Vigorous heals itself 5 HP a turn. So the
same machinery that steals a turn also *gives* turns away, and the player
meets both.

The other half of DD1 is **Quirks**, and the cheapest good idea in either game
is here: a hero with a locked quirk **cannot use the town building the player
wants**. An alcoholic refuses the Abbey and must be sent to the Tavern. That
is control loss with a completely different feel — it happens in a menu, with
the clock stopped, where the player can plan around it, and it costs money
rather than a life.

## A2. Darkest Dungeon 2 — the actual relationship system

DD2 is the one with pair relationships, and it is the closest published thing
to what §2 above proposes. **Affinity is 0–20 per pair, starting at 9**, and
it is *symmetric* — one number for the pair, which is the same call this spike
made. Bands and the chance that a band resolves into a named relationship:

| affinity | band | resolves to |
|---|---|---|
| 0 | zero | — |
| 1–4 | very unfriendly | 90% negative |
| 5–8 | unfriendly | 65% negative |
| 9–13 | neutral | 5% negative / 5% positive |
| 14–16 | friendly | 33% positive |
| 17–19 | very friendly | 65% positive |
| 20 | max | 90% positive |

Note the shape: the meter does not *become* a relationship at a threshold, it
becomes a **chance** of one. A pair sitting at 18 is probably going to bond
and might not. That is a deliberately softer contract than this spike's
`band()`, which is a pure function of the score.

The named relationships and what each actually does:

| relationship | standing effect on the partner | act-outs |
|---|---|---|
| **Respectful** (+) | +Strength, +Dodge | follow-up attack, counterattack when the partner is hit, stress-healing bark |
| **Hopeful** (+) | −1 stress per turn | big stat buff to the partner, −5 stress and removes Horror, stress-healing bark |
| **Amorous** (+) | heals 10% HP, clears Bleed/Blight/Burn | **intercepts an attack aimed at the partner**, heals the partner 50% max HP and clears DoTs, stress-healing bark |
| **Suspicious** (−) | +Taunt, +Vulnerable | stress-dealing bark |
| **Envious** (−) | +1 stress | stress-dealing bark |
| **Hateful** (−) | +Vulnerable | **chance to hit the partner for damage**, stress-dealing bark |
| **Resentful** (−) | +Blind, +Weak | stress-dealing bark |

And the mechanism that is more interesting than any of those: a negative
relationship **curses a skill**. A cursed skill is force-equipped to the
hero's bar, cannot be removed by the player, carries a debuff, and has
**triple priority over mastered skills**. It does not seize a turn. It
narrows the menu the player chooses from, permanently, until the
relationship changes.

What moves affinity, which is the part this spike's §3 should be compared
against — note how much of it is *combat behaviour* rather than events:

**+1 each** (doubled on a 10% crit chance): buffing an ally, healing a
low-HP or Death's Door ally, cutting an ally's stress, guarding a low-HP
ally, moving while calm, attacking the same enemy as an ally on consecutive
turns, attacking an enemy an ally debuffed or comboed, attacking an enemy
that just hit an ally, agreeing with an ally at a narrative node, and Inn
items (Candles and Chocolate up to +3).

**−1 to −2**: disagreeing at a node, healing or guarding *yourself* while
low, cutting *your own* stress while high, moving while stressed, random
combat and road events, and a failed Inn item (25–33% of them fail).

That negative list is the sharpest idea in DD2: **selfishness is the thing
that costs you affinity.** Heal yourself instead of the man bleeding out and
the party notices. It is measured off actions the player was going to take
anyway, so the system reads the player's play rather than asking them
questions.

Stress in DD2 is 0–10. At 10 in combat there is an **80% chance of a
Meltdown**: HP down to 10%, −15% Deathblow resistance until the next Inn,
+40% stress resistance for 3 turns, a 40% chance of a new negative quirk,
and **three negative affinity hits with every party member at once**. So
DD2 wires stress into relationships explicitly: the hero who breaks takes
the whole party's opinion of them down with it.

## A3. The comparison set

Six more games, surveyed for the same two things: the shape of the stored
relationship, and whether it ever takes the character out of the player's
hands. Claims flagged **unverified** below are ones the sources would not
settle; they are left in because the gap is itself worth knowing, and they
are not load-bearing for anything in A4.

### Wildermyth — every relationship state is a buff, and none is a punishment

Symmetric, one relationship per pair, three mutually exclusive types
(Friend / Rival / Lover) plus a non-exclusive Family tag. Five levels each,
at cumulative point breakpoints **20 / 60 / 120 / 200 / 300**. Points accrue
passively from fighting and doing overworld jobs together *and* in lumps from
authored event outcomes, so it is a meter fed by events rather than one or
the other. The award is then scaled by a charisma term
(`0.005 × (chaA + chaB) + 0.5`) and a compatibility "fascination" factor
(`(|compatibility| + 3) / 3`), the product clamped to **0.33×–3.0×**.
Compatibility comes off personality traits and is what pushes a pair toward
Lover or Rival.

The finding that matters is the mechanical table:

| type | level 1 → level 5 |
|---|---|
| Friend | +10 → **+30** block chance when body-blocking for that hero |
| Lover | +1 → **+5** damage against enemies who attacked that hero, until end of mission |
| Rival | +25% → **+100%** stunt chance when your rival stunts |
| Family | no combat effect; blocks Lover, permits Friend and Rival |

**Rivalry is a damage buff, not a tax.** There is no negative relationship
state anywhere in the system, and no relationship-driven disobedience at all.
The only control loss in the game is injury-driven: after a non-fatal Mortal
Choice the hero withdraws to the nearest town and cannot be controlled until
healed. Relationship *consequences* are routed into authored events instead —
losing a lover sets a Brokenheart hook that targets follow-up story
opportunities — and even there the hero neither leaves nor becomes
uncontrollable, and the player may decline. Children of heroes do become
recruitable units, and a romance can be *locked* so re-recruited legacy
heroes re-enter it across campaigns. (The "children draw from a separate
origin pool" detail is **lightly verified**, from search snippets only.)

### RimWorld — directed opinion, and three separate routes to disobedience

**Directed, not symmetric**: A's opinion of B is a different number from B's
opinion of A, and the wiki says so explicitly — a pawn can be friends with
someone who considers them a rival. Clamped **−100..+100**, banded Rival
(−100..−20), Acquaintance (−20..+20), Friend (+20..+100).

Inputs are dense and mostly not about combat: beauty ±20 per level capped
±40, disfigurement −15, traits (Annoying Voice −25, Joyous +20), social
interactions (Deep Talk +15, Insult −15), player actions (recruited +20,
rescued +15/+25, botched surgery −20), rejected romance (−10 to the
proposer, **−15 to the target**), family relations (parent/child +30,
sibling +20, a relative's death −15 to −80), and romance itself (Lovers +35,
Spouse +30, ex −15 base plus **−50 to −70 on the dumped party**, cheated on
**−70**).

Control loss comes three ways, and they are worth separating:

1. **Social fight.** An Insult has a **4%** base chance to start one, a
   Slight 0.5%, multiplied by malnutrition, Bloodlust (×4) and drunkenness.
   Fighting pawns **cannot be drafted**. Aftermath is a coin flip:
   **cathartic +38** opinion or **angering −22**, for 20 days. This is the
   cleanest "opinion produces a fight the player cannot stop" loop anywhere
   in this survey.
2. **Mental breaks on social mood damage.** Minor 35%, major 20%, extreme
   5%. During any break the player has no direct control. Targeted Insulting
   Spree stacks to about **−33** mood on one victim, which is an explicit
   insult spiral; Murderous Rage picks a colonist and melees them until dead.
3. **Autonomous romance.** Breakups and affairs fire on their own once
   opinion toward a third pawn sufficiently exceeds opinion of the partner.
   **The player is not consulted.** That is the precise opposite of §4's rule
   here, and it is worth knowing that the most systemic game in the set went
   the other way.

### Battle Brothers — no pair relationships, but the best coupling idea

Two systems, neither of them relational. Mood is **one scalar per brother,
0–7**, drifting toward ~3.15 at ±0.1–0.15 per hour, fed by company-wide
events: Pay Raise +2, Battle Won +0.35, Lost Confidence in Your Leadership
−6 to −1, Permanent Injury −1.35, Brother Died **−0.25 for everyone
regardless of who died**. Combat morale is a separate six-state ladder
(Unbreakable / Confident / Steady / Wavering / Breaking / Fleeing) applying
multipliers ×1.1 down to ×0.7 across Resolve, both attack skills and both
defences.

The idea worth stealing is the **coupling**: mood does not set combat morale,
it **caps** it. Dissatisfied caps you at Steady, Disgruntled at Wavering,
Angry at Breaking and risks desertion; Euphoric gives a 75% chance to *start*
Confident. One line lets the campaign layer bound the combat layer without a
second simulation.

What not to steal is Fleeing. It is total AI takeover: Shieldwall, Spearwall,
Riposte and Indomitable are all cancelled, the unit gets **−1000 initiative**
each round, and it runs from enemies and **will not fight even if
surrounded**. That works because Battle Brothers fields 12–20 expendable men
over 10+ rounds. (A secondary claim that the developers explicitly ruled out
inter-brother relationships is **unverified**; that the system does not exist
is well supported by its absence from every mechanics page.)

### XCOM 2: War of the Chosen — the relationship is both the cure and the trigger

Per-pair **Cohesion on a 1.0–10.0 scale**, raised by deploying two soldiers
together on combat or Covert Action missions; at 10 they may bond. (The
levelling thresholds beyond that are **partially verified** — the wiki's
wording is internally ambiguous. The widely repeated claim that pair
compatibility derives from personality traits is **unverified** community
inference.)

| bond level | what it grants |
|---|---|
| 1 | **Teamwork** — grant your bondmate an extra action by spending one of yours; one charge per mission, shared between the two |
| 2 | **Covert Operators** (−1 day when deployed together), **Spotter** (+10% aim against targets that attacked or were attacked by your bondmate, +10% more if adjacent), **Stand By Me** (ending a move *orthogonally* adjacent to your bondmate cleanses any negative mental effect) |
| 3 | **Advanced Teamwork** (two charges) and **Dual Strike** (both fire at one enemy; free action for the partner) |

Panic is the control-loss mechanism, and in WOTC it is **Battle Madness** in
four forms, all of which take the soldier's actions away: Panic (random
actions), Berserk (offensive only, and the stat bonuses are useless because
you are not steering), Shattered (defensive only), Obsessed (attacks the
feared enemy type). And the trigger list explicitly includes **a bondmate
being killed or captured**.

So one data structure sits on both sides of control loss: *Stand By Me* is
the game's main non-psionic **cure** for a negative mental state, and the
same bond is among the biggest **causes** of one. That symmetry is the single
most transferable idea in this appendix. (A distinct "bondmate gravely
wounded" trigger is **unverified**.)

### Fire Emblem — the positional formula, and it is one line

Support is a per-pair point total with an authored conversation gate, and the
accrual differs per game: GBA awards points **each turn two units are
adjacent**; Path of Radiance 1 per chapter deployed together (C/B/A at
5/8/11); Radiant Dawn 5 for starting a turn adjacent and 17 for being
deployed together (50/100/150); Three Houses 6 per Linked Attack and 20 for
viewing a C support (101/301/601/1001); Awakening caps a unit's best pair at
3 points per map.

The GBA model is the one that fits a hex grid, and it is elegant: each unit
has an **affinity** carrying a fixed bonus vector, you **sum both partners'
vectors and multiply by the support rank** (C=1, B=2, A=3), and it applies
while the two are **within 3 tiles**.

| affinity | Atk | Def | Accuracy | Avoid | Crit | Crit evade |
|---|---|---|---|---|---|---|
| Fire | +0.5 | | +2.5 | +2.5 | +2.5 | |
| Thunder | | +0.5 | | +2.5 | +2.5 | +2.5 |
| Wind | +0.5 | | +2.5 | | +2.5 | +2.5 |
| Ice | | +0.5 | +2.5 | +2.5 | | +2.5 |
| Dark | | | +2.5 | +2.5 | +2.5 | +2.5 |
| Light | +0.5 | +0.5 | +2.5 | | +2.5 | |
| Anima | +0.5 | +0.5 | | +2.5 | | +2.5 |

Supports never carry a penalty and never remove agency. S rank unlocks
marriage, and in Awakening and Fates produces a recruitable child unit.
(Per-rank bonus figures that circulate as universal are Awakening-era and
**unverified** as a general rule; the formula is genuinely game-specific.)

### Jagged Alliance 2 — the closest precedent in the set, from 1999

The most directly relevant system here, and the best documented, because the
1.13-derived source is open. Every number below is read out of the code.

Storage is **directed and asymmetric**: `bMercOpinion[75]` is a merc's
opinion of every other profile, one byte each way. On top of that sit static
`bBuddy[3]` and `bHated[3]` slots (friend 1, friend 2, eventual friend; the
same for enemies), with `BUDDY_OPINION = +25` and `HATED_OPINION = −25`.
Morale is 0–100, default 50.

The rule worth copying is how the two combine. `HourlyMoraleUpdate()`
averages the opinions of everyone in the sector, adds a leadership term, and
clamps to ±25 — **but if a hated merc is present the average is discarded
and team opinion is forced to the minimum.** One hated teammate poisons the
whole reading no matter how many friends are there. That is a legible roster
decision instead of a diffuse average nobody can read.

Relationship events are the largest single-person entries in the morale
table: Buddy Died **−15**, Hated Died **+5**, Teammate Died −5, and a merc
who hated the deceased gets the Hated Died bonus *instead of* any grief
penalty. Morale then feeds competence directly: `GetMoraleModifier()` runs
+5 at 95 morale down to **−20** at 0, added straight into every skill check.

And control loss is **relationship-caused, not stress-caused**, in two hard
forms. `bHatedCount` decrements every hour a merc shares a sector with
someone they hate; they complain partway through, **complaining stops time
compression** so the player must notice, and at zero MERC-type mercs quit on
the spot. There is one safety valve: if the count would hit zero while an
enemy is in the sector it is bumped back to 1, so nobody walks out
mid-firefight. Second, `FindRefusalReason()` ranks contract-renewal refusal
with **hated mercs highest, above death rate and above morale** — and on the
positive side a merc with a buddy on the team renews and *says it is because
of their friend*. Finally, `bLearnToHate` and `bLearnToLike` are timers that
on expiry **write** a permanent relationship and interpolate opinion toward
±25, which is authored seeds growing into simulated opinion, in 1999.
(Tactical insubordination — a low-morale merc refusing an order in combat —
is **unverified**; JA2's relationship control loss is strategic.)

### Two footnotes

**Baldur's Gate II** is the purest case of a *relationship* rather than a
stress meter causing disobedience: authored pair conflicts on a 24-hour
in-game timer, and when Keldorn's ultimatum about Viconia expires with both
still present, **both leave the party and fight each other to the death**,
entirely outside player control. No morale scalar anywhere in the loop.

**Crusader Kings** was not verifiable: the wiki sits behind a challenge that
defeated every route tried. Personality traits drive opinion and opposite
traits lower it; nothing else here should be quoted. The practical route is
reading the game's own `common/opinion_modifiers/`.

### The shape table

| game | stored as | range | directed? | control loss from the relationship |
|---|---|---|---|---|
| DD1 | nothing (per-hero stress) | 0–200 | n/a | via affliction: refuse 33%, act out ~30–42% |
| DD2 | per-pair affinity | 0–20, start 9 | no | cursed skill force-equipped; Hateful can hit the partner |
| Wildermyth | per-pair, one of 3 types | 20–300 pts, 5 levels | no | **none** |
| RimWorld | per-ordered-pair | −100..+100 | **yes** | social fight, mental breaks, autonomous affairs |
| Battle Brothers | none (per-brother mood) | 0–7 | n/a | none relational; Fleeing is total takeover |
| XCOM 2 WOTC | per-pair cohesion | 1.0–10.0 | no | bondmate death triggers Battle Madness |
| Fire Emblem | per-pair support points | game-specific | no | **none** |
| JA2 | per-ordered-pair + buddy/hate slots | −100..+100 (±25 flags) | **yes** | quits the company; refuses renewal |
| sorcmerc (this spike) | per-pair | −100..+100 | no | none proposed |

## A4. What transfers to sorcmerc, and what must not

sorcmerc is not Darkest Dungeon, and the difference is the one that decides
this entire question: **a DD hero is a resource and a sorcmerc character is
an investment.** DD1 hands you a fresh stagecoach of heroes every week and
the game is *about* spending them; a hero lost to an affliction spiral is
the content working. A sorcmerc character was built by the player in
`scenes/creator/creator.gd` across a dozen 5e choices, banks its own XP,
levels, carries gear, and survives runs — and `core/progression.gd` spends
its lifetime XP on unlocking species and classes. Taking the turn away from
*that* character is a far bigger insult than taking one away from Reynauld.

The second difference is the brief. `docs/brief.md`: *"Reading the log alone,
a 5e-literate person can reconstruct why they won or lost — every hit/miss
traces to a visible number."* A 5.8% unannounced roll at the top of a turn
that makes a character swing at their own cleric does not trace to a visible
number. **But 5e already has the canonical mechanism for control loss, and
it is a saving throw** — which is a visible number, published DC, rolled in
the open. That is the translation this game can take: *not* "8.3% chance to
act out", but *"Vera, WIS save 12+2 vs DC 13 — fails. She will not take an
order from Pike this round."*

### The engine already has every primitive

This is the finding that makes the rest cheap. `data/effects/conditions.json`
and `core/combat.gd`'s `apply_condition()` already express all four DD
act-out categories as 5e conditions, tested and shipping:

| DD behaviour | sorcmerc equivalent, already implemented |
|---|---|
| passes the turn / refuses to act | `incapacitated` — `no_action`, `no_bonus`, `no_reaction` |
| refuses to attack the target you picked | `charmed` — `cannot_target_source`, and `resolve_attack` already returns `{"error": "charmed"}` |
| moves back / will not close | `frightened` — `cannot_approach_source`, already honoured in `move_field()` |
| will not move at all | `grappled` / `restrained` — `speed: 0` |
| affliction stat penalty | `exhaustion` — `d20_penalty`, `speed_penalty_ft` |
| DD2's Vulnerable / Weak / Blind | the `attacks_against` / `own_attacks` adv-dis vocabulary, and `blinded` |

And the signature is already the right shape for a *pair*:
`apply_condition(target, cond, source, duration, v)` stores `source` for
exactly the two conditions that need to know *who* — which is what
"frightened **of Pike**" and "charmed **by Vera**" require, and a
relationship always has an other end. `duration: "round"` gives a one-turn
effect; `held_by` + `repeat_save` + `dc` gives "save at the end of your turn
to shake it off". A relationship act-out needs **no new engine machinery at
all** — it is one `apply_condition` call with the other member as the source.

One more existing path worth naming: `core/ai.gd`'s `take_turn()` already
routes a party member to `_party_auto()`, and `combat.gd`'s `skips_turn()`
already exists for surprise and ambush rounds. So "this member acts on their
own this round" and "this member loses their turn" are both one call to
tested code. If control loss is ever wanted, it is hours, not days. That is
an argument for deciding it on design grounds rather than cost.

### Two decisions this spike made that the survey argues against

Before the recommendations, the two places the research disagrees with §2 and
§6 above. Both are cheap to change now and expensive later.

**1. Rivalry as a penalty is the minority position, and probably the wrong
one.** §6 gives rivals −1 to hit when adjacent. In the whole survey, exactly
one game punishes a *relationship* with a combat malus the player cannot
avoid: Darkest Dungeon 2, whose characters are roguelike runs. Wildermyth,
whose characters are player-made like this game's, makes **rivalry a damage
buff** — up to a guaranteed stunt against a single target — and has no
negative relationship state at all. Fire Emblem's supports carry no penalty
either. The reasoning is the same one A4 opens with: a player who built both
characters will not accept the game taxing them for a feud the game invented.
The fix is to make `bicker_penalty` a *different* bonus rather than a malus —
two people trying to outdo each other hit harder and guard each other less,
which is one sign flip and a swap of which stat it touches.

**2. Symmetric was the easy call, not obviously the right one.** §2 stores
one number per pair, and every *bond* system in the survey does the same
(Wildermyth, DD2, XCOM 2, Fire Emblem). But both games that model *opinion* —
RimWorld and Jagged Alliance 2, the two closest to this design — store it
per ordered pair, and both buy something real with it. RimWorld's wiki calls
it out directly: a pawn can be friends with someone who considers them a
rival. JA2 goes further and adds a rule symmetric storage cannot express:
**one hated teammate forces the whole squad's opinion reading to the
minimum**, however many friends are present. That is a legible roster
decision — get that person out — instead of an average nobody can read. If
directed is ever wanted, the migration is not bad (`"a|b"` stops being
sorted, `score()` grows an argument order, and `band()` takes the lower of
the two directions), but it is a save-format change, so it is a now-or-never
call rather than a later one.

### Recommended, in order

1. **Copy DD2's affinity inputs, not its act-outs.** The single best idea in
   either Darkest Dungeon is that **affinity is measured off combat behaviour
   the player was going to choose anyway** — buffing, healing the person who
   is actually dying, focusing the same enemy, and losing points for treating
   yourself first while an ally is down. §3 above has only four sources and
   two of them are events; DD2 has nine, all free reads on actions
   `combat.gd` already resolves. Concretely: `act_help` on an ally, a heal
   aimed at the lowest-HP ally rather than at yourself, two members attacking
   the same foe in consecutive turns, and a heal or buff spent on yourself
   while somebody is down. Five hooks in functions this spike already
   touches, and it turns the score into a reading of how the player plays
   rather than a tally of things that happened to them.
2. **Steal Fire Emblem's positional formula, because this is a hex game.**
   The GBA support model is one line of arithmetic: each character has an
   affinity carrying a small bonus vector, a supported pair **sums both
   vectors and multiplies by the rank**, and it applies while the two are
   within N tiles. It needs no authored dialogue, which is this game's
   binding constraint, and it makes *positioning* the expression of the
   relationship rather than a flat passive. It also generalises §6's two
   adjacency hooks into one mechanism: `shoulder_bonus` and
   `bicker_penalty` are both "sum a vector over nearby related allies, scale
   by band", and `Hex.distance` is already the check. A character's affinity
   can come off the same sheet `baseline()` already reads.
3. **Make the relationship the cure for control loss, not only its cause.**
   XCOM 2's *Stand By Me* is the most transferable single idea in the
   appendix: ending your move adjacent to your bondmate **cleanses a negative
   mental effect**. It is a perfect hex-grid verb, it turns the game's
   condition system into a positioning puzzle instead of a dice tax, and it
   is symmetrical with the same bond being one of the biggest triggers of
   Battle Madness in the first place. In sorcmerc terms: a member who ends
   their movement adjacent to someone they are bonded to sheds `frightened`,
   or gets a free repeat save against a `held_by` condition. `_repeat_saves`
   and `move_to` already exist; this is a call at the end of movement.
4. **Take the cursed-skill idea, not the stolen turn.** Narrowing the menu is
   legible and survivable; seizing a turn is neither. The sorcmerc version is
   a rival pair losing access to the *cooperative* verbs with each other:
   `act_help` on a rival is not offered, and `OFFERABLE`'s `ally_buff` skips
   them. The button is visibly greyed with a reason in the tooltip, which is
   the whole difference between a restriction and a betrayal.
5. **Put whatever real control loss there is in town and at camp, where DD1's
   quirks and JA2's hatreds put it.** DD1 makes an alcoholic refuse the Abbey;
   JA2 makes a merc quit the company over a teammate, ranks that refusal
   **above** death rate and morale, and stops time compression when they
   complain so the player must notice. Both happen in menus with the clock
   stopped. sorcmerc has the surfaces already: `settlement_visit.gd` prices an
   inn per settlement and rolls Persuasion, Investigation and Sleight of Hand
   with a party-picked roller, and `travel.gd` asks the player to name a scout
   and a watch. So: rivals will not share a room, so the inn costs more;
   lovers insist on the same watch, so naming one scout and the other watch is
   refused; a feuding pair cannot both be named to the same job. Nothing is
   lost mid-fight and it costs coin and convenience rather than a character.
   Copy JA2's safety valve too — it refuses to let a merc walk out while an
   enemy is in the sector.
6. **Copy Battle Brothers' "the campaign layer caps the combat layer"
   coupling.** Mood there does not *set* combat morale, it **bounds** it:
   Dissatisfied caps you at Steady, Euphoric gives a 75% chance to start
   Confident. §7's `travel_bonus` is a flat ±1 on road checks; a cap is the
   same idea with better teeth and no second simulation. A party at rivals
   could cap the *best* band any pair can reach in a fight, which is one
   `mini()` rather than a new system.
7. **Take JA2's learn-to-hate timers as the bridge between authored and
   simulated.** `bLearnToHate` and `bLearnToLike` are countdowns that on
   expiry *write* a permanent relationship and interpolate opinion toward it.
   That is how you get Wildermyth-shaped arcs with no authored companions:
   the authoring lives in the trigger condition and the bark, not in the
   character. It is also the honest answer to §3's pacing problem — a bond
   that is *becoming* something over a known number of days reads better than
   one that crossed 50 because the cleric healed a lot.
8. **Copy the symmetry DD1 gets right and most imitators drop.** The same
   machinery that costs a turn should sometimes give one. §6's rally is
   already this shape; DD2's Amorous interception and Wildermyth's
   body-blocking are the other half, and the precedent for a reaction that
   eats damage is `rogue-uncanny-dodge` in `data/effects/features.json` — a
   `kind: reaction` on the `hit_by_attack` trigger with `halve_damage`, which
   `combat.gd`'s `_react()` already resolves with no prompt. (The Fighter's
   Interception style is *not* the precedent: `data/fighting-styles.json`
   grants `fighting-style-interception` but no effects entry authors it, so it
   currently does nothing — which is why `Presets.vera` can pick it to keep
   her AC at the authored 18.)
9. **If a combat act-out is ever wanted, gate it behind a saving throw and
   nothing else.** One shape, at the extreme band only: at the top of their
   turn, a member adjacent to someone they hate makes a Wisdom save against a
   published DC; on a failure they take `frightened` or `charmed` sourced at
   that rival for one round, which the engine already enforces and the log
   already narrates. Never an unannounced roll, never friendly-fire damage,
   and never at a band the player was not warned about.

### Not recommended

- **A stress meter.** DD's afflictions hang off stress, and adding a second
  resource with its own threshold, its own UI and its own spiral to a game
  that already tracks HP, slots, pools, exhaustion and 15 conditions buys a
  worse version of exhaustion, which is already in the engine and already
  5e-legal.
- **Contagion.** DD1's 6-stress barks are how one bad hero ruins four. In a
  four-member party of the player's own hand-built characters this reads as
  the game punishing you twice for one bad roll.
- **RimWorld's real-time social tick.** Chitchat, Deep Talk, Slight and
  Insult with a 4% fight chance need continuous time and pathing to generate
  proximity. In discrete 5e turns there is no equivalent clock, and rolling
  it per round would be either invisible or maddening.
- **Any break that seizes a whole turn** — RimWorld's Murderous Rage and
  Tantrum, XCOM's Berserk, Battle Brothers' Fleeing. Those games field 12 to
  20 units, or run in real time, or both. In a four-to-six character 5e
  encounter one lost turn is a fifth of the action economy plus possible
  friendly fire, and it is a loss the player could not have played around.
  5e's `frightened` already does most of Fleeing's job legibly, and it is
  already in the engine.
- **Making a relationship a chance of a relationship.** DD2's band-to-named
  roll (90/65/33/5 by affinity band) exists to keep a roguelike run
  surprising. These relationships persist across runs and have to be
  *plannable*, so `band()` staying a pure function of the score is right.
- **Marriage that produces recruitable children.** Fire Emblem's and
  Wildermyth's payoff is authored offspring inheriting authored personality
  and dialogue. With player-made characters there is nothing to inherit that
  the player could not build at the roster screen, so it would cost a
  generator and deliver a worse character creator. Wildermyth only earns it
  because cross-campaign legacy is the entire point of the game.
- **BG2-style forced expulsion, and anything that can kill a character.**
  Keldorn's ultimatum ends with two characters leaving and fighting to the
  death; DD1's affliction path ends in a heart attack. Removing or killing a
  character the *player designed* is a far harsher contract than losing an
  authored companion they merely recruited — it reads as the game deleting
  their work. The invariant this project already holds, that nothing rolled
  between towns may drop anybody (`core/travel.gd`'s `_hp_toll`), is the
  right precedent, and a relationship should respect it too.
- **CK3-style opinion.** Wrong scale: it is tuned for hundreds of AI agents
  whose purpose is to be disobedient, and a party of four has no faction
  layer for it to feed. (It was also the one system in the survey that could
  not be verified from a primary source.)

## A5. Sources

**Darkest Dungeon 1** — [Affliction](https://darkestdungeon.wiki.gg/wiki/Affliction),
[Stress](https://darkestdungeon.wiki.gg/wiki/Stress_(Darkest_Dungeon)),
[Virtue](https://darkestdungeon.wiki.gg/wiki/Virtue).

**Darkest Dungeon 2** — [Relationships](https://darkestdungeon.wiki.gg/wiki/Relationships),
[Stress](https://darkestdungeon.wiki.gg/wiki/Stress_(Darkest_Dungeon_II)),
[Affinity System](https://darkestdungeon2.wiki.fextralife.com/Affinity_System).

**Wildermyth** — [Relationship](https://wildermyth.com/wiki/Relationship),
[Modding Relationship Points](https://wildermyth.com/wiki/Modding_Relationship_Points),
[Mortal choice](https://wildermyth.com/wiki/Mortal_choice),
[Pyrelight](https://wildermyth.com/wiki/Pyrelight).

**RimWorld** — [Social](https://rimworldwiki.com/wiki/Social),
[Mental break](https://rimworldwiki.com/wiki/Mental_break).

**Battle Brothers** — [Morale](https://battlebrothers.fandom.com/wiki/Morale),
[Mood](https://battlebrothers.fandom.com/wiki/Mood),
[dev blog 20 (Bravery/Morale)](https://battlebrothersgame.com/dev-blog-20-bravery-morale/),
[dev blog 84 (Mood/Desertion)](https://battlebrothersgame.com/dev-blog-84-mood-desertion/).

**XCOM 2: WOTC** — [Bonding](https://xcom.fandom.com/wiki/Bonding),
[Panic](https://xcom.fandom.com/wiki/Panic_(XCOM_2)).

**Fire Emblem** — [Support](https://fireemblemwiki.org/wiki/Support),
[Affinity](https://fireemblemwiki.org/wiki/Affinity),
[GBA support calculation (Serenes Forest)](https://serenesforest.net/blazing-sword/characters/supports/calculation/).

**Jagged Alliance 2** — read out of the open
[ja2-stracciatella](https://github.com/ja2-stracciatella/ja2-stracciatella)
source: `src/game/Tactical/Morale.cc` (the `gbMoraleEvent` table,
`GetMoraleModifier`, `HourlyMoraleUpdate`),
`src/game/Tactical/Soldier_Profile_Type.h` (`bMercOpinion`, `bBuddy`,
`bHated`, `BUDDY_OPINION`, `HATED_OPINION`),
`src/game/Strategic/Strategic_Merc_Handler.cc`
(`UpdateBuddyAndHatedCounters`), `src/game/Strategic/Merc_Contract.cc`
(`FindRefusalReason`), `src/game/Tactical/SkillCheck.cc`. This is the
1.13-derived source, faithful to the 1999 release but not the shipped binary.

**Baldur's Gate II** — Sorcerer's Place walkthrough pages for
[Keldorn](https://sorcerers.net/Games/BG2/Walkthrough2/npcs/keldorn.php) and
[Viconia](https://sorcerers.net/Games/BG2/Walkthrough2/npcs/viconia.php). A
long-standing fan resource rather than an official wiki; the exact conflict
timer is community-documented.

Percentages are as those pages state them and were not verified against the
games' own data files, except for Jagged Alliance 2, where every number is
read from source. Everything the sources would not settle is marked
**unverified** at the point it is claimed; Crusader Kings could not be
verified at all and nothing from it should be quoted.

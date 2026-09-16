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
a temperament. So the authored-companion model — romance as a
dialogue tree with a specific written NPC, gated on approval — has nothing to
attach to. What fits is the systemic model: relationships between *whoever the
player brought*, produced by what happened to them, labelled by a system, and
told in templated lines. That decides four things:

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
   sees. Symmetric. **This is the decision §A3 most wants revisited**:
   a directed score could say that Vera counts Pike a friend while Pike
   counts her a rival, and it could carry a rule this shape cannot express —
   that one hated member floors the whole marching order's reading however
   many friends are in it.

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
  265 swings turned 14 into misses and the fight did not notice. At these
  sizes they are things a player *sees* (a rally fires every other fight for
  a bonded pair; that is a log line and a moment) and not things that move
  the balance T38/T40 tuned. That is arguably correct for
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
  belt-and-braces. Keep the register light: a line, a label, a point of AC.
  Anything heavier needs a writer per pair, and there is no writer.
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

# Appendix A — control loss, and why this spike proposes none

Added 2026-09-16, after the spike above, in answer to a question it does not
touch: what about **uncontrollable actions** — a character who refuses an
order, wanders off, or swings at the wrong person because of how they feel
about somebody. Every effect measured in §6 is a modifier the player still
steers around. This appendix is about the other kind.

The reasoning below was checked against a set of shipped games that are known
for opinionated party members, and against the two that model a numeric
opinion between characters rather than a simple bond. That survey is not
reproduced here: a design doc in this repo should carry the decisions and the
reasons, not a competitive analysis of other people's games assembled from
fan wikis. It is in this pull request's history if anyone wants the workings.

## A1. Why this game can take less of it than most

Two differences decide the whole question.

**A character here is an investment, not a resource.** The genre's control-loss
systems are built for rosters you spend: a stable of interchangeable recruits,
replaced weekly, where losing one to a spiral is the content working as
intended. A sorcmerc character is built by the player in
`scenes/creator/creator.gd` across a dozen 5e choices, banks its own XP,
levels, carries gear, survives runs, and spends its lifetime XP in
`core/progression.gd` unlocking species and classes. Taking the turn away from
*that* character is a much larger insult than taking one away from a recruit
the player merely hired.

**The brief promises visible math.** `docs/brief.md`: *"Reading the log alone,
a 5e-literate person can reconstruct why they won or lost — every hit/miss
traces to a visible number."* An unannounced roll at the top of a turn that
makes a character swing at their own cleric does not trace to a visible
number. **But 5e already has the canonical mechanism for control loss, and it
is a saving throw** — a published DC, rolled in the open, narrated by the log.
That is the translation this game can take. Not "8% chance to act out", but
*"Vera, WIS save 12+2 vs DC 13 — fails. She will not take an order from Pike
this round."*

## A2. The engine already has every primitive

This is the finding that makes the rest cheap, and it is the reason this
appendix ends in a recommendation rather than an estimate.
`data/effects/conditions.json` and `core/combat.gd`'s `apply_condition()`
already express every category of "the character did something you did not
choose" as a 5e condition, tested and shipping:

| the behaviour | what already implements it |
|---|---|
| passes the turn / refuses to act | `incapacitated` — `no_action`, `no_bonus`, `no_reaction` |
| refuses to attack the target you picked | `charmed` — `cannot_target_source`, and `resolve_attack` already returns `{"error": "charmed"}` |
| backs away / will not close | `frightened` — `cannot_approach_source`, already honoured in `move_field()` |
| will not move at all | `grappled` / `restrained` — `speed: 0` |
| a flat competence penalty | `exhaustion` — `d20_penalty`, `speed_penalty_ft` |
| "vulnerable", "weak", "blind" style debuffs | the `attacks_against` / `own_attacks` adv-dis vocabulary, and `blinded` |

And the signature is already the right shape for a *pair*:
`apply_condition(target, cond, source, duration, v)` stores `source` for
exactly the two conditions that need to know *who* — which is what
"frightened **of Pike**" and "charmed **by Vera**" require, and a relationship
always has an other end. `duration: "round"` gives a one-turn effect;
`held_by` + `repeat_save` + `dc` gives "save at the end of your turn to shake
it off". A relationship act-out needs **no new engine machinery at all** — it
is one `apply_condition` call with the other member as the source.

One more existing path worth naming: `core/ai.gd`'s `take_turn()` already
routes a party member to `_party_auto()`, and `combat.gd`'s `skips_turn()`
already exists for surprise and ambush rounds. So "this member acts on their
own this round" and "this member loses their turn" are both one call to tested
code. If control loss is ever wanted, it is hours, not days — which is an
argument for deciding it on design grounds rather than on cost.

## A3. Two decisions this spike made that the research argues against

Both are cheap to change now and expensive later, which is why they are here
rather than in a follow-up.

**1. Rivalry as a penalty is probably wrong for this game.** §6 gives rivals
−1 to hit when adjacent. The games that punish a relationship with a malus the
player cannot avoid are the ones whose characters are disposable; the ones
built around characters the player made themselves consistently make *every*
relationship state a different **bonus**, with no punishing state at all —
rivalry included, as a damage or crit effect rather than a tax. The reasoning
is the same as A1's: a player who built both characters will not accept the
game taxing them for a feud the game invented. The fix is to make
`bicker_penalty` a *different bonus* rather than a malus — two people trying to
outdo each other hit harder and cover each other less. One sign flip and a
change of which stat it touches.

**2. Symmetric storage was the easy call, not obviously the right one.** §2
stores one number per pair. That is right for a *bond*, which is inherently
mutual. It is not obviously right for an *opinion*: the systems that model
opinion numerically store it per ordered pair, so that A can count B a friend
while B counts A a rival, and one of them buys a rule this shape cannot
express — **one hated member forces the whole group's reading to the minimum**,
however many friends are present. That is a legible "get that person out of
the marching order" decision instead of an average nobody can read. If
directed is ever wanted the migration is not bad — `"a|b"` stops being sorted,
`score()` grows an argument order, and `band()` takes the lower of the two
directions — but it is a save-format change, so it is a now-or-never call.

## A4. Recommended, in order

1. **Measure the score off combat behaviour the player was going to choose
   anyway.** §3 has four sources and two of them are events. The stronger
   design reads the play instead: buffing an ally, healing the person who is
   actually dying rather than yourself, focusing the same enemy two turns
   running, guarding someone who is down — and **losing** points for treating
   yourself first while an ally is on the floor. Selfishness costing you is
   the sharpest single idea available here, and it needs five hooks in
   functions this spike already touches, all free reads on actions
   `combat.gd` already resolves.
2. **Use a positional formula, because this is a hex game.** Give each
   character a small bonus vector, have a related pair **sum both vectors and
   multiply by the band**, and apply it while the two are within N hexes. It
   is one line of arithmetic, it needs no authored dialogue, and it makes
   *positioning* the expression of the relationship rather than a flat
   passive. It also generalises §6's two adjacency hooks into one mechanism:
   `shoulder_bonus` and `bicker_penalty` are both "sum a vector over nearby
   related allies, scale by band", and `Hex.distance` is already the check. A
   character's vector can come off the same sheet `baseline()` already reads.
3. **Make the relationship the cure for control loss, not only its cause.**
   The most transferable idea in the whole survey: ending your movement
   adjacent to someone you are bonded to **cleanses a negative mental
   effect**. It is a natural hex-grid verb, and it turns the condition system
   into a positioning puzzle instead of a dice tax. In sorcmerc terms, a
   member who ends their move beside a bonded ally sheds `frightened`, or gets
   a free repeat save against a `held_by` condition. `_repeat_saves` and
   `move_to` already exist; this is a call at the end of movement.
4. **Narrow the menu; never seize the turn.** Restriction is legible and
   survivable, and a stolen turn is neither. The version to build is a rival
   pair losing access to the *cooperative* verbs with each other: `act_help`
   on a rival is not offered, and `OFFERABLE`'s `ally_buff` skips them. The
   button is visibly greyed with a reason in the tooltip, which is the whole
   difference between a restriction and a betrayal.
5. **Put whatever real control loss there is in town and at camp.** The best
   precedents for relationship-driven disobedience put it in menus with the
   clock stopped, where it costs coin and convenience rather than a character,
   and where the player can plan around it. sorcmerc has the surfaces already:
   `settlement_visit.gd` prices an inn per settlement and rolls Persuasion,
   Investigation and Sleight of Hand with a party-picked roller, and
   `travel.gd` asks the player to name a scout and a watch. So: rivals will
   not share a room, so the inn costs more; lovers insist on the same watch,
   so naming one scout and the other watch is refused; a feuding pair cannot
   both be named to the same job. Copy the safety valve the best version of
   this has, too — it refuses to let anybody walk out while a fight is
   actually on.
6. **Let the campaign layer *cap* the combat layer rather than set it.** §7's
   `travel_bonus` is a flat ±1 on road checks. A cap has better teeth for the
   same cost: a party at rivals bounds the *best* band any pair can reach in
   a fight. One `mini()`, and no second simulation to maintain.
7. **Use a timer as the bridge between authored and simulated.** A countdown
   that, on expiry, *writes* a permanent relationship and interpolates the
   score toward it is how you get a narrative arc with no authored
   companions: the authoring lives in the trigger condition and the bark, not
   in the character. It is also the honest answer to §3's pacing problem — a
   bond that is visibly *becoming* something over a known number of days
   reads far better than one that crossed 50 because the cleric healed a lot.
8. **Keep the symmetry: the machinery that costs a turn should sometimes give
   one.** §6's rally is already this shape. The other half is a reaction that
   eats a hit meant for a partner, and the precedent for that is
   `rogue-uncanny-dodge` in `data/effects/features.json` — a `kind: reaction`
   on the `hit_by_attack` trigger with `halve_damage`, which `combat.gd`'s
   `_react()` already resolves with no prompt. (The Fighter's Interception
   style is *not* the precedent: `data/fighting-styles.json` grants
   `fighting-style-interception` but no effects entry authors it, so it
   currently does nothing — which is why `Presets.vera` can pick it and keep
   her AC at the authored 18.)
9. **If a combat act-out is ever wanted, gate it behind a saving throw and
   nothing else.** One shape, at the extreme band only: at the top of their
   turn, a member adjacent to someone they hate makes a Wisdom save against a
   published DC; on a failure they take `frightened` or `charmed` sourced at
   that rival for one round, which the engine already enforces and the log
   already narrates. Never an unannounced roll, never friendly-fire damage,
   and never at a band the player was not warned about.

## A5. Not recommended

- **A second stress or mood resource.** The genre hangs its act-outs off one,
  but adding a resource with its own threshold, its own UI and its own spiral
  to a game that already tracks HP, slots, pools, exhaustion and fifteen
  conditions buys a worse version of exhaustion, which is already in the
  engine and already 5e-legal.
- **Contagion.** The classic design has an afflicted character manufacture the
  stress that afflicts the next one, which is how one bad character ruins
  four. In a party of four the player hand-built, that reads as being punished
  twice for one bad roll.
- **A real-time social tick.** Chitchat-and-insult systems need continuous
  time and pathing to generate proximity. In discrete 5e turns there is no
  equivalent clock, and rolling it per round would be either invisible or
  maddening.
- **Any break that seizes a whole turn.** The games that do this field twelve
  to twenty units, or run in real time, or both. In a four-to-six character 5e
  encounter one lost turn is a fifth of the action economy plus possible
  friendly fire, and it is a loss the player could not have played around.
  `frightened` already does most of that job legibly and is already in the
  engine.
- **Making a relationship a *chance* of a relationship.** Rolling for whether
  a band resolves into a named state keeps a roguelike run surprising. These
  relationships persist across runs and have to be *plannable*, so `band()`
  staying a pure function of the score is right.
- **Marriage that produces recruitable children.** That payoff is authored
  offspring inheriting authored personality and dialogue. With player-made
  characters there is nothing to inherit that the player could not build at
  the roster screen, so it would cost a generator and deliver a worse
  character creator.
- **Anything that can remove or kill a character over a feud.** Both exist in
  the genre: a pair conflict that ends with two characters leaving and
  fighting to the death, and an affliction path that ends in a heart attack.
  Deleting a character the *player designed* is a far harsher contract than
  losing a companion they merely recruited. The invariant this project already
  holds, that nothing rolled between towns may drop anybody
  (`core/travel.gd`'s `_hp_toll`), is the right precedent, and a relationship
  should respect it too.
- **A grand-strategy opinion model.** Wrong scale: those are tuned for
  hundreds of AI agents whose whole purpose is to be disobedient, and a party
  of four has no faction layer for it to feed.

# Downtime — what a company does in town when it is not working

Sub-project 6 of the 2026-09-20 content batch (objectives → landmarks → threat
clocks → the ladder → callings → **downtime** → the lodge). A town today is a
market, a board, a bed and four one-shot rows (work the healer's ward, steal
from the stall, investigate the battle, haggle). Every one of them takes a
moment. Nothing in a town takes *days* — so the clocks the batch built (a
raid due in two days, a lair's window, a calling's road) never trade against
anything, and gold has nowhere to go but the shelf. This adds the things that
take days, from the table 5e keeps for exactly this question: **training** (a
feat, over days, for gold — once per hero), **carousing** (a night on the town
that buys a contact, a lead, or a complication), **gambling** (a stake and a
roll, once a visit), **crafting** (brew at the alchemist's bench, scribe at the
librarian's desk — half price, a day each), and **the pit** (a city's bracket
of three named champions, once a week). Each is a row on a page the game
already has; each spends world-days the way an inn night does; and each can
turn into a small story, because the complication is the anti-grind.

## 0. Scope

**In:** `core/downtime.gd` (the activities, their rolls, costs, days,
complications; state on `party.downtime`, saved); rows on the inn page
(carouse, gamble, train, the pit) and at the alchemist's and librarian's
counters (brew, scribe); the pit's bracket (three champions seeded per city
per week, fought one at a time as ordinary encounters with a named foe, a
purse per bout, once per bracket); the complication table (four kinds: a
tab, a brawl, an insult, a bad lead), each a small event card; days spent
advance the world clock and rest the party; deeds and renown from the pit;
achievements; tests; the robot; pictures (an event scene per activity and one
for the pit).

**Out:** tools and languages (the sheet has neither); retraining (the lodge's
training yard, #7); a second trained feat; crafting magic items (the smith's
back room sells them); pit wagers on others' bouts; a downtime activity that
takes more than five days.

**Untouched behaviour:** the four existing rows keep their rules; a player
who never spends a day in town loses nothing they have today.

## 1. The model

```gdscript
# core/downtime.gd — static, like settlement_visit.gd's rows
# party.downtime: Dictionary  # {"trained": [char_id...], "pit": {settlement_id: {"week": int, "beaten": int}}}
const DAY := 1440.0
static func spend_days(party, world, days: int) -> void    # clock += days*DAY; Visit.rest(long) once; last_visited stamps stay
```

Every activity returns the dict shape the existing rows return (`ok`, `nat`,
`bonus`, `dc`, `text`, plus its own fields) and the screen shows it the way
it shows `work_healer` — a line under the row, and a card when there is a
complication. Days are spent through `spend_days`, which advances the clock
(so raids land, windows close, callings wait) and rests the party (a day in
town is a night in a bed; the bed is paid at `Visit.inn_cost(s)` per night —
free at Sworn).

## 2. The five activities

**Training** — inn page, city or town (a trainer stands where there is an
inn). *Train %s in a feat.* Picks a hero; the row opens a picker of the
`general`-category feats the sheet does not have (`Catalog.all("feats.json")`
filtered), level 4 or better. Costs `TRAIN_COST` (150 + 50 × level) and
`TRAIN_DAYS` (5). Adds the feat id to `ch.feats` (`core/rules/bundles.gd`
step 9 expands it at the next resolve — `ch.dirty()`), records the hero in
`party.downtime.trained`. Once per hero, ever. Copy: *"Five days with a
master-at-arms, and %s comes out of it with %s."*

**Carousing** — inn page, any settlement with an inn. *A night on the town
(%d ◉).* Costs `CAROUSE_COST[kind]` (city 30, town 20, camp 10) and one day.
The party's best at Persuasion or Performance rolls vs `CAROUSE_DC` 13. Pass:
a **contact** — `FactionOpinion.raise(s.faction, CAROUSE_CONTACT)` (5) and a
free rumour (`Rumors.free_lead` — the same the landmarks' lead uses; if none
is left, gold instead: the contact stands a round, +`CAROUSE_COIN` 15). Nat 20:
both. Fail: a **complication** (§4). Nat 1: the complication and the tab.

**Gambling** — inn page. *Sit in on a game (stake %d ◉).* A stake picker
(25 / 50 / 100 / 200, capped at the purse). The party's best at Insight,
Deception or Sleight of Hand rolls vs `GAMBLE_DC` 12: nat 20 → 3×; ≥ DC + 5
→ 2×; ≥ DC → 1.5×; < DC → the stake is gone; nat 1 → the stake, and an
**insult** complication (they think you cheated). Once per visit (seeded off
`s.id`, `last_visited`, like `steal`). No days — an evening.

**Crafting** — at the counter. *Brew %s (%d ◉, a day)* on the alchemist's
stall for every potion it stocks; *Scribe %s (%d ◉, a day)* on the
librarian's for its own scrolls (`Campaign.SCROLL_IDS`). Half list price
(`CRAFT_RATE` 0.5), one day each, the item into the stash identified. The
bench is the door: a party with no caster scribes nothing; anyone can brew
(the alchemist supervises). Once per item per visit.

**The pit** — inn page, city only. *The pit: %s, %s and %s stand this week
(purse %d ◉).* A bracket of three champions seeded off `(s.id, week)`
(`week = int(elapsed / (7 × DAY))`): each a named foe (`EnemyNames`) from the
city's own faction roster at the party's level +1, +2, +3 in turn, fought as
an ordinary encounter (`encounter_spec` with a one-foe roster and the
champion's name; theme `city-square`; no objective). A bout is an evening. Win
→ `PIT_PURSE[bout]` (60 / 120 / 240) and a deed (`Ladder.deed(s.faction)`);
the third win → `Ach.unlock("pit_champion")`. Lose → the party is carried out
(`_retreat`'s rule: no death, gold lighter by the purse of that bout — the
house keeps its stake) and the bracket closes for the week. Once per bracket:
`party.downtime.pit[s.id] = {week, beaten}`; a new week, a new bracket.

## 3. Days, and what they cost

`spend_days(party, world, n)`: the clock moves `n × DAY`; the raids poll, the
lair windows, the landmarks' watch, the callings' road all see it — that is
the trade. The party rests once (a long rest), pays the bed for `n` nights at
the inn's rate, and every `last_visited`/`battle_at` stamp stays (the market
restocks on its own clock). A day is never free: the inn row says so
(*"Five days, five nights: %d ◉ for the bed."*).

## 4. Complications — the small stories

One of four, seeded off the activity and the visit; each is an event card
(`camp-`-style, art `event-downtime-<kind>`) and one consequence:

| kind | line | consequence |
|---|---|---|
| tab | *"The morning brings a bill nobody remembers running up."* | `−2 × the activity's cost` in gold (to zero) |
| brawl | *"Somebody's cousin takes exception to the company."* | a fight at the inn: a `bandit` roster at `easy`, the *drunk brawlers*, no objective; a win pays nothing; a loss is `_retreat` |
| insult | *"Something was said that should not have been, and it was heard."* | `FactionOpinion.lower(s.faction, 5)` |
| bad lead | *"A man at the bar knew exactly where the treasure was."* | a rumour that names nothing (`Rumors` gets a `dud` offer id shown as a lead that marks no landmark — the party page shows it as a rumour bought for 0 that goes nowhere) |

## 5. Where it shows

The inn page gains a **Downtime** section under the bed: Train (with a hero
and feat picker), A night on the town, Sit in on a game (with a stake picker),
and at a city, The pit. The alchemist's and librarian's counters gain Brew /
Scribe rows beside their stock. Results are lines under the row, cards for
complications and the pit's bouts. The party page's hero card shows a
trained feat like any feat. Achievements (`road` group): `trained_first`
*Schooled*, `carouse_contact` *Friends in Low Places*, `gamble_treble` *The
House Loses* (a 3×), `pit_champion` *Champion of the Pit*.

## 6. Numbers, and how they get checked

| constant | value | why |
|---|---|---|
| `TRAIN_COST`, `TRAIN_DAYS` | 150 + 50 × level, 5 | a feat is a level's worth; five days is two raid clocks |
| `CAROUSE_COST` | city 30 / town 20 / camp 10 | a night at the inn, and the drinks |
| `CAROUSE_DC`, `CAROUSE_CONTACT`, `CAROUSE_COIN` | 13, 5, 15 | the road's DCs; half a job's opinion |
| `GAMBLE_DC` | 12 | a coin flip with skill |
| `GAMBLE_STAKES` | 25 / 50 / 100 / 200 | a potion to a magic item |
| `CRAFT_RATE` | 0.5 | half price for a day |
| `PIT_PURSE` | 60 / 120 / 240 | a job, two jobs, a rare item's tenth |
| `PIT_LEVELS` | +1 / +2 / +3 | each bout harder than a road fight |

Tests (`tests/test_downtime.gd`): `spend_days` moves the clock, rests, pays
the bed by rung; training adds the feat, charges, takes five days, refuses a
second, refuses under level 4, lists only general feats the hero lacks;
carousing pass/fail/nat 20/nat 1 branches with their consequences; gambling's
five outcomes and the once-per-visit seed; brew/scribe at half price into the
stash, scribe refused without a caster, once per item per visit; the pit's
bracket seeded per week, three champions named and levelled, the purse per
bout, a loss closing the bracket, a new week reopening it; each complication
applies its consequence; the save round-trips `downtime`. Screen tests: the
Downtime section and the counter rows, a pit bout launching a fight with the
champion's name on the card. The robot: takes each row sometimes; invariant:
the purse never goes negative through downtime.

## 7. Files

| file | change |
|---|---|
| `core/downtime.gd` | new |
| `core/party.gd`, saves | `downtime` |
| `core/settlement_visit.gd` | nothing (rows call `Downtime`) |
| `core/rumors.gd` | `dud` offer for the bad lead |
| `scenes/world/world.gd` | the inn page's Downtime section; counter rows; the pit fight launch (a one-foe spec, a named champion) |
| `core/enemy_names.gd` | reuse |
| `core/achievements.gd` | four entries |
| tests, `docs/expansion-plan.md`, pictures `event-downtime-{train,carouse,gamble,craft,pit,tab,brawl,insult,bad-lead}` | §5, §6 |

## 8. Decided here

- **Days are the currency.** Every downtime activity that changes the party
  costs days, and days are what the clocks eat. Gambling is the exception
  because it is an evening and its cost is the stake.
- **One trained feat per hero.** Retraining and a second are the lodge's
  yard; the trainer in town teaches once.
- **The pit is once a week per city**, and a loss closes it. It cannot be
  farmed; it can be come back to.
- **Complications are small and one-shot.** A tab, a brawl, an insult, a
  bad lead — a story the size of a card, never a quest.

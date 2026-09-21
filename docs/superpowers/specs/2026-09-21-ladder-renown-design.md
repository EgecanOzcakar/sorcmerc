# The ladder and renown — standing with a people, and a name across the map

Sub-project 4 of the 2026-09-20 content batch (objectives → landmarks → threat
clocks → **the ladder and renown** → callings with party relations → downtime
→ the lodge). Today a faction's opinion of the party is one decaying number
that moves prices and, at the ends, the gate. It is invisible, it drifts back
to zero when you are away, and it opens nothing but a discount. This adds a
second track that does not decay and that opens *people*: **standing**, a
ladder per civilized faction with four named rungs — Stranger, Known,
Trusted, Sworn — climbed by deeds done for that people (jobs finished, raids
turned and lifted, a lair settled in their name, a fight won at their gate, an
offering at their shrine). Each rung opens something a stranger cannot get: the
innkeeper's word about a neighbour's work, a cheaper bed and then a free one,
the armorsmith's **back room** where the 264 magic items finally have somewhere
to be bought, a **patron** in the faction's city who posts work about anything
on the map, and once, an **audience** with the lord. Across all of it runs
**renown**: one party-wide title from the sum of every deed — Nobodies,
Hirelings, a Company of Note, Famous, Legends — that says how the world speaks
of the company and puts a premium on every job it takes.

## 0. Scope

**In:** `core/ladder.gd` (deeds, rungs, renown, audiences; saved with the
world); five deed sources wired; the rungs' doors (neighbour's jobs, the bed,
the back room, the patron's reach, the audience); renown's title and pay
premium; the standing shown where the player reads it (the town square's line,
the quest log, the HUD); four achievements; three generated audience scenes;
tests and the robot.

**Out:** anything that lowers a rung (standing is earned, not lost — opinion
already does the souring); orc/monster factions (they have no ladder; their
gate is the fight); titles per hero (that is callings, #5); a keep to rest in
(the lodge, #7, is the party's own house — the free bed at Sworn is what a
faction offers); tiers of magic beyond rare in the back room (very rare and
legendary stay loot).

**Untouched behaviour:** opinion (`core/faction_opinion.gd`) keeps every rule
it has — prices, hostility, the gate, the decay. The ladder reads nothing from
it and writes nothing to it. A save without a `ladder` key loads at zero deeds
everywhere.

## 1. The model

```gdscript
# core/ladder.gd — static, process-global, like faction_opinion.gd
static var _deeds: Dictionary = {}       # faction -> int, never decays, never drops
static var _audiences: Array = []        # factions whose audience has been held

const RUNGS := ["Stranger", "Known", "Trusted", "Sworn"]
const RUNG_AT := [0, 4, 12, 25]           # deeds
const KNOWN := 1
const TRUSTED := 2
const SWORN := 3

const TITLES := ["Nobodies", "Hirelings", "a Company of Note", "Famous", "Legends"]
const TITLE_AT := [0, 6, 18, 40, 80]      # total deeds across civilized factions
const PAY_PER_TITLE := 0.1                # every job pays +10 % per title above Nobodies

static func deed(faction: String, n := 1) -> void
static func deeds(faction: String) -> int
static func rung(faction: String) -> int          # 0..3
static func rung_name(faction: String) -> String
static func renown() -> int                       # sum over civilized factions
static func title_index() -> int                  # 0..4
static func title() -> String
static func pay_mult() -> float                   # 1.0 + PAY_PER_TITLE * title_index()
static func audience_held(faction: String) -> bool
static func hold_audience(faction: String) -> void
static func all() -> Dictionary                   # {"deeds": {...}, "audiences": [...]} for the save
static func load(d: Dictionary) -> void
static func reset() -> void
```

`deed()` ignores monster factions (`WorldAI.is_monster`, via `load()` — the
same cycle-dodge `faction_opinion.gd` uses). Rung and title changes are
noticed by the caller that made the deed: `deed()` returns the new rung when
it changed and `-1` otherwise, and `title_index()` is compared before and
after by the world screen, which says *"The company is spoken of now: a
Company of Note."* through `_lair_msg` and bumps the achievements.

`WorldSave` writes `Ladder.all()` under `"ladder"` beside `"opinion"` and
loads it after `FactionOpinion`; a missing key is `reset()`.

## 2. Deeds — what climbs the ladder

| deed | points | where it is credited |
|---|---|---|
| a job turned in | 1 to the taker's faction | `Quest.turn_in` (beside `QUEST_DONE`) |
| a monster band put down near a town | 1 per faction credited | `FactionOpinion.credit_fight` (beside the opinion) — so a raid turned is 2, its `TURNED_FOR` credit being a second `credit_fight` |
| a raid lifted by clearing its lair | 2 to the town's faction | `Raids.tick`'s lift |
| a lair settled | 3 to the settlers' faction | `Raids.settle` |
| an offering at a shrine | 1 to the nearest town's faction | `Landmarks._open("offering")` |

Sized so that a party that does a town's board (three or four jobs) and clears
the lair behind its raid is *Known* there; *Trusted* is a session of taking
that people's side; *Sworn* is a campaign. Nothing on this table can be
farmed without playing — fights near towns come to you, jobs are finite per
board, raids are the clock's.

## 3. The rungs' doors

Every door is a one-line gate on an existing system; the ladder adds no new
screen, only lines and one tab.

**Known** (4 deeds):
- The innkeeper passes a neighbour's job once the town's own is taken:
  `Quest.offer_for`'s generous branch is `opinion >= QUEST_GENEROUS or rung >=
  KNOWN` (the opinion path stays as it is).
- A bed at half price: `Visit.inn_cost(s)` × 0.5 (rounded up).
- The town square's standing line says *"Known here — they will pass you a
  neighbour's work."*

**Trusted** (12):
- **The back room.** `Visit.visit()` appends `BACK_ROOM_N` (3) uncommon magic
  items to the market's `stock`, tagged `"service": "backroom"`, drawn by
  `Loot.items_of_rarity("uncommon")` seeded off `(s.id, steps)` the way the
  shelf is, priced at `Campaign.item_price × markup`; `stock_by_service`
  groups them under `backroom`; the market page shows a **Back room** tab
  (the armorsmith's portrait) when the group is non-empty. Bought items land
  in the stash identified. Only settlements with an armorsmith or weaponsmith
  have a back room (a camp's generalist does not deal in these).
- **The patron.** The faction's chief settlement (its largest kind: city >
  town > camp; ties by id) posts the three world-target kinds about anything
  on the map: `Posting._world_offers` reads reach as `INF` there. Its board
  line says *"The patron's table: word of work from all over."*
- The standing line: *"Trusted here — the back room is open to you."*

**Sworn** (25):
- The back room adds `BACK_ROOM_RARE` (2) rare items.
- The bed is on the house: `inn_cost` 0, the inn button says *"Inn. On the
  house."*
- **The audience**, once: the chief settlement's town square gains a button
  *"Seek an audience with the lord"* while `not audience_held(faction)`. It
  opens the event card (`event_card.gd`, whose art is `event-<id>`: id `audience-<faction>`, so the file is `event-audience-<faction>.png`): *"The
  hall is cleared for you. The lord speaks of what the company has done for
  <faction>'s people, and of what a lord owes such a company."* — the gift is
  one rare magic item (`Loot.items_of_rarity("rare")`, seeded off the
  faction, identified, into the stash) and `AUDIENCE_XP` (200) split through
  `Campaign._split_xp`; `hold_audience(faction)`; `Ach.collect("audiences",
  faction)`.
- The standing line: *"Sworn to this people. Their doors are yours."*

## 4. Renown

`renown()` is the sum of deeds over civilized factions; the title is read off
`TITLE_AT`. It shows in three places: the HUD's region label gains *" · a
Company of Note"* once past Nobodies; the quest log gains a **Standing**
section under the quests — the title with its deed count and the next
threshold, then one line per civilized faction with its rung and count; the
town square's line ends with the title when it is Famous or better.

The premium: `Posting.offers()` multiplies every job's `reward.gold` by
`Ladder.pay_mult()` after the kind-specific builders (so the chain tiers and
the raid premium compound with it), and the board's mood line says *"Famous —
work pays +30 %."* when the title is past Nobodies. Turn-in pays what the
posting said, as today.

Titles do not gate anything else. What Famous buys is the premium and the
name; what opens doors is standing with a people.

## 5. Where it shows, and the pictures

- `_standing_line(s)` (world.gd): the ladder's line precedes the opinion's
  when the rung is Known or better; the opinion's hostile lines still win at
  the bottom (a Sworn company that has since burned the town is still
  fought at the gate).
- The quest log's Standing section (§4).
- The HUD region label (§4).
- The market's Back room tab; the town square's audience button; the inn
  button's price.
- Achievements (`road` group): `known_first` *Known Faces* (a first Known
  rung), `sworn_first` *Sworn* (a first Sworn rung), `renown_famous`
  *Famous* (title Famous), `audience_first` *An Audience* (a first audience).
- Pictures: three audience scenes generated with the house tooling
  (`~/localgen/gen_sorcmerc_scenes.py`, a new `audience` group, SCENE style):
  a human lord's timbered hall, an elven lord's canopy court, a dwarven lord's
  stone hall, each receiving a small band of adventurers. Files
  `assets/generated/event-audience-{human,elf,dwarf}.png` (the event card's
  own stem rule).

## 6. Numbers, and how they get checked

| constant | value | why |
|---|---|---|
| `RUNG_AT` | 0 / 4 / 12 / 25 | a board and a lair; a session; a campaign |
| `TITLE_AT` | 0 / 6 / 18 / 40 / 80 | Hirelings after the first town, Legends after the whole map twice |
| `PAY_PER_TITLE` | 0.1 | +10 % per title, +40 % at Legends — felt, not the economy |
| `BACK_ROOM_N`, `BACK_ROOM_RARE` | 3, 2 | a shelf, not a catalogue; 400 ◉ and 2 025 ◉ each at list |
| `INN_KNOWN` | 0.5 | half a bed |
| `AUDIENCE_XP` | 200 | five landmarks; a once-per-faction milestone |

Tests (`tests/test_ladder.gd`): deeds accumulate and never drop; monster
factions are ignored; rungs and titles at exactly their thresholds; `deed()`
reports a rung change once; `pay_mult`; `all()`/`load()` round-trip and
`reset()`. `tests/test_world_save.gd`: the `ladder` key round-trips; an old
save loads at zero. `tests/test_quest.gd`: `offer_for` passes a neighbour's
job at Known with opinion 0; `turn_in` credits a deed. `tests/test_faction_opinion.gd`:
`credit_fight` credits a deed per faction moved. `tests/test_raids.gd`: lift
and settle credit. `tests/test_landmarks.gd`: the offering credits.
`tests/test_settlement_visit.gd`: the back room appears at Trusted with three
uncommon items, adds two rare at Sworn, is absent below, is absent at a
camp; `inn_cost` halves at Known and is 0 at Sworn; buying a back-room item
stashes it identified. `tests/test_quest_posting.gd`: the patron's reach
posts a far lair at the chief settlement and nowhere else; the premium.
`tests/test_world_visit_pages.gd` (or a new `tests/test_world_ladder.gd`,
driving the real screen): the standing line per rung, the Back room tab, the
audience button and its card, the quest log's Standing section, the HUD
label. `tests/test_achievements.gd`: the four entries. `drive_random.gd`: the
robot seeks the audience when the button is there; invariant: deeds never
decrease between frames.

## 7. Files

| file | change |
|---|---|
| `core/ladder.gd` | new |
| `core/world_save.gd` | `ladder` in and out |
| `core/quest.gd` | `offer_for` Known gate; `turn_in` deed |
| `core/faction_opinion.gd` | `credit_fight` deed |
| `core/raids.gd` | lift and settle deeds |
| `core/landmarks.gd` | offering deed |
| `core/settlement_visit.gd` | `inn_cost` by rung; the back room in `visit`/`stock_by_service` |
| `core/quest_posting.gd` | patron reach; `pay_mult` on every offer |
| `core/achievements.gd` | four entries |
| `scenes/world/world.gd` | standing line, HUD title, quest log Standing, Back room tab, audience button + card, inn button text, title-change line |
| `tests/…` | §6 |
| `docs/expansion-plan.md` | the record |
| `assets/generated/event-audience-*.png` | §5 |

## 8. Decided here

- **Standing never drops.** Opinion is the mood and already sours; a ladder
  that could be lost would make every deed provisional. A Sworn company that
  turns on the town is fought at the gate (opinion) but is still Sworn (its
  history) — that is the right reading of a betrayal, and the doors it
  opened are worth nothing to a company the guards attack.
- **The patron is reach, not a new kind of job.** The world-target jobs exist;
  what a stranger lacks is a town willing to post work about the far country.
- **The back room sells uncommon and rare only.** Very rare and legendary items
  are found, not bought — the hoards keep their point.
- **Renown pays; standing opens.** Two tracks, two verbs, so neither is
  redundant with the other.
- **One audience per faction.** It is a milestone, not a shop.

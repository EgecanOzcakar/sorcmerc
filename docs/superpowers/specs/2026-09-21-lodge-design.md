# The lodge — one house in a town, and what a company builds onto it

Sub-project 7, the last of the 2026-09-20 content batch (objectives →
landmarks → threat clocks → the ladder → callings → downtime → **the
lodge**). The batch gave the party ways to earn — jobs, raids turned, the
pit, renown's premium — and the shelf and the back room to spend on. What it
has nowhere to put is *itself*: no door of its own, no strongroom the road
cannot take a fifteenth of, no yard, no garden, no map on a wall that fills
while it is away. The lodge is that: **one house, bought once in a town
where the company is Known, with five rooms built onto it over time** — a
strongroom, a training yard, an herb garden, a shrine, a map room — each a
gold sink with a visible answer on the map and a use on the road. The 09-13
scope said no settlement building; this is not a settlement, it is the
party's house, and the user chose it.

## 0. Scope

**In:** `core/lodge.gd` (buy, the five rooms, deposit/withdraw, the garden's
and map room's yields, the yard's retraining, the shrine's blessing; state
on `party.lodge`, saved); the town square's *Your lodge* / *Buy a lodge
here* button and the lodge page; a free bed at the lodge; `_retreat` spares
stored gold; the lodge on the 3D map (a house beside the town that gains a
part per room) and the minimap; achievements; tests; the robot; pictures
(the lodge page's scene, one per room count).

**Out:** a second lodge; moving it; staff or hirelings; the lodge as a
raid target (a raid on the town halves the market, not the strongroom);
crafting at the lodge (the counters' benches are downtime's); the lodge in
co-op beyond mirroring (it rides the party dict).

**Untouched behaviour:** a company that never buys a lodge plays exactly as
today.

## 1. The model

```gdscript
# core/lodge.gd — static; state on party.lodge
# party.lodge: Dictionary  # {} until bought; then
#   {"settlement_id": String, "rooms": [room_id...], "gold": int,
#    "garden_at": float, "maproom_at": float, "retrained": [char_id...]}
const HOUSE_COST := 400
const ROOMS := {
	"strongroom": {"cost": 200, "title": "the strongroom"},
	"yard":       {"cost": 300, "title": "the training yard"},
	"garden":     {"cost": 150, "title": "the herb garden"},
	"shrine":     {"cost": 200, "title": "the shrine"},
	"maproom":    {"cost": 250, "title": "the map room"},
}
static func can_buy(party, world, s) -> bool          # no lodge yet; s civilized; Ladder.rung(s.faction) >= KNOWN; gold >= HOUSE_COST
static func buy(party, world, s) -> Dictionary        # {"text"}; Ach; a deed for the town's faction
static func at(party, s) -> bool                      # this settlement holds the lodge
static func has(party, room: String) -> bool
static func can_build(party, room) -> bool           # lodge, not built, gold
static func build(party, world, room) -> Dictionary  # pays; appends; stamps garden_at/maproom_at at build; {"text"}
static func deposit(party, n) / withdraw(party, n) -> bool     # strongroom only
static func collect(party, world) -> Dictionary      # on arrival: the garden's potions and the map room's leads since last collected; {"potions": int, "leads": [...], "text"}
static func can_retrain(party, ch) -> bool; retrain(party, world, ch, old_feat, new_feat) -> Dictionary   # yard: swap one general feat for another, RETRAIN_COST, RETRAIN_DAYS (through Downtime.spend_days); one swap per hero per visit
static func bless(party) -> Dictionary                # shrine: party.blessed = true (the landmark's temp HP) on leaving, once per visit
static func to_dict / from_dict
```

## 2. The rooms

| room | cost | what it does on the road |
|---|---|---|
| the house | 400 | a free long rest in its town; the *Your lodge* page; the company's name on the door |
| strongroom | 200 | deposit and withdraw gold; stored gold is not the party's when `_retreat` takes its fifteenth or a tab is run up |
| training yard | 300 | retrain: swap one general feat for another (the +1 re-decided), `RETRAIN_COST` 100, `RETRAIN_DAYS` 3, one swap per hero per visit |
| herb garden | 150 | one potion of healing per `GARDEN_DAYS` (3) away, up to `GARDEN_CAP` (3), collected on arrival |
| shrine | 200 | the blessing: temp HP at the next fight (the landmark shrine's door), taken when the party leaves the lodge, once per visit |
| map room | 250 | one free lead per `MAPROOM_DAYS` (4) away, up to `MAPROOM_CAP` (2), collected on arrival (`Rumors.free_lead` from the lodge's town) |

Buying is gated by standing: the town has to know the company (*Known*).
Rooms build at once (the sink is the gold; the days are downtime's). Total
sink 1 400 ◉ + retraining — a campaign's worth of jobs, visible as it goes.

## 3. Where it shows

- The town square: *Buy a lodge here (400 ◉)* when `can_buy`; *Your lodge* when
  `at`; at another town with a lodge elsewhere, one Dim line *"The company's
  lodge is at Riverhold."*
- The lodge page (a visit page like the inn's): the house's line and its
  rooms; per room a Build row or its use (the strongroom's deposit/withdraw
  with an amount picker 50/100/200/all; the yard's retrain pickers; the
  garden's and map room's counts collected on arrival with a line *"The
  garden has three potions ready."*); the bed (free); Leave takes the
  shrine's blessing.
- The 3D map: a lodge diorama beside the town's (`settlement_kit.gd`: a
  house plan that gains a fence for the yard, beds for the garden, a stone
  for the shrine, a small tower for the map room); the minimap marks it; the
  town's label gains *" · your lodge"*.
- `_retreat`: the loss is taken from `party.gold` only.
- Achievements: `lodge_bought` *A Door of Our Own*, `lodge_full` *Every Room
  Built*.

## 4. Numbers, and how they get checked

Tests (`tests/test_lodge.gd`): buy gates (no lodge, civilized, Known, gold);
one lodge only; each room's build gate and effect; deposit/withdraw bounds;
the garden's and map room's accrual by days away with the caps and the
collect-on-arrival reset; retrain swaps the feat and re-decides the +1,
charges, spends days through `Downtime.spend_days`, once per hero per visit;
bless sets `party.blessed`; `_retreat` spares stored gold (a world screen
test); the save round-trips `lodge`. Screen test: the button, the page, the
rows, the diorama part count growing with rooms. Robot: buys and builds
when it can; invariant: stored gold never negative, never lost to a retreat.

## 5. Files

`core/lodge.gd` (new), `core/party.gd` + saves (`lodge`), `core/downtime.gd`
(nothing — the yard calls `spend_days`), `scenes/world/world.gd` (the square
button, the lodge page, `_retreat`, the label), `scenes/world/settlement_kit.gd`
+ `settlements3d.gd` (the lodge diorama), `scenes/world/minimap.gd`,
`core/achievements.gd`, tests, `docs/expansion-plan.md`, pictures
`event-lodge-{house,strongroom,yard,garden,shrine,maproom}`.

## 6. Decided here

- **One lodge, bought where the company is Known.** A house is a
  relationship with a town before it is a building.
- **Rooms build at once; the sink is the gold.** Days are downtime's
  currency; the lodge is the reward for having spent them.
- **The strongroom is the one thing the road cannot take.** That is what a
  house is for.
- **The garden and the map room accrue while away, capped.** A reason to come
  home, not a reason to stay.

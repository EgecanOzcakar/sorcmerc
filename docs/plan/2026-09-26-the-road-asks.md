## The road asks — #232 and #234, #231 phase 3a (2026-09-26)

D3's road events resolved themselves: the standing orders decided who rolled,
and the card reported what had already happened. That was a locked rule —
"orders resolve events; nothing is asked of the player on the road" — and
#232 reverses it: decisions pop up when they happen, with at least two and
usually three choices, leading to different outcomes, able to set off more
events or encounters, and not necessarily solved by fighting. #234 asks for
many events, chaining, with a story attached. The owner's calls (2026-09-26):
**every event asks**, the standing orders stay as bonuses on the rolls, and
**the events move to data** so content packs can add their own.

**Every road event now stops the company on a choice card**
(`scenes/world/road_choice_card.gd`) with two or three things to do about it,
each saying what it would take: who would roll it and at what ("Pike Sallow,
Stealth +7 vs DC 13"), the spell that would answer it, the coin it costs (and
disabled, with the reason, when the purse is short or nobody can). The answer
is resolved by `core/road_events.gd` and reported on D3's own event card, die
and all.

**The standing orders still decide.** Every event built on one of D3's offers
"as the orders have it" — `Travel.resolve`, exactly D3's roll and outcome, so
nothing D3 did is lost and its tests still hold. Every other choice with a
check is rolled by the character the standing orders put on that job (scout,
watch, or the party's best), with the pace, the party's morale and the
roller's traits on it (`Travel.roll`, split out of `Travel.check`). Waving the
card away (Enter, or a robot's `acknowledged`) takes the first choice, which
is the orders' — so "dismiss the road's card" means what it always meant.

**The events are data**: `data/road_events.json` — all fifteen of D3's events,
each with one or two new choices, and two follow-up events. What an outcome
can do is a closed vocabulary (`RoadEvents.EFFECTS`): time, gold (found, or
lost but never more than the purse), a wound that never drops anybody, a
heal, an item or a piece of salvage, experience, a people's opinion, a lair
revealed, **a trail** to a place on no map, **a fight**, and **a follow-up**.

- **A trail** is the owner's earlier ask — "landmarks and decisions should be
  able to create new routes that were not visible on the map before" — for
  road events: a way laid from the nearest place the company knows to the
  landmark lead's own kind of target (`WorldRoutes.lead_target`). Each outcome
  says whether it is **shown at once** (`"known": true` — the wayfarer's
  scratched map) or **only noticed** when the company passes where it starts
  (`false` — the waystone's old road). On a free-roaming map it reveals the
  nearest lair instead.
- **A fight** puts a band in front of the company on the approach card — who
  the road here would send, or a named people (the toll-men are bandits) —
  so a fight is one outcome among several, not the default.
- **A follow-up** (`"next": {"event", "after"}`) is how events chain (#234):
  it goes on the road ahead (`world.road_chain`, saved) and is the road's
  next event once its time comes, ahead of any random pick. Following the
  tracks leads to the camp in the hollow (go in hard, watch and count them —
  which puts their lair on the map — or back away); hunting the snare's owner
  leads to the trapper (buy his draught, get a path out of him, or run him off
  — and his friends).

**Content packs can add road events** (docs/modding.md §5.3): a
`road_events` file in `pack.json`, validated at scan time like every other
pack file (an unknown effect, a follow-up to nothing, an item that is not
one, the wrong number of choices, a choice without its outcome — each a line
in the browser), merged into the table by `Registry.apply_data()`, a pack's
event replacing a built-in of the same id. The mod API snapshot
(`tests/fixtures/mod_api.json`) freezes the new vocabulary
(`road_events.effects`, `.needs`, `.roles`); the API level stays 1 — a new
file a pack may decline to use is not a break.

Screenshots: `docs/shots/road-choice.png` (the camp in the hollow, three
choices, the roll each would take) and `docs/shots/road-choice-answer.png`
(watching them: the stealth roll made, +20 XP, the lair on the map), from
`tests/shot_road_choice.gd`.

Tests: `tests/test_road_events.gd` (the table, every D3 event reachable by its
orders, eleven kinds of authoring mistake caught, the pick with follow-ups
first and chain-only events never by chance, the choices' hints and refusals,
each shape of choice resolved, every effect, both kinds of trail, the chain
saved and played through, and a pack's events through the real pack
pipeline) and the robot `tests/drive_road_events.gd` on the real world
screen (the choice card stops the clock, a real button press, the answer on
the event card, a fight onto the approach card, a chain onto the road ahead
and back as the next event, waving the card away taking the orders).

### Still open

- **#232's meetings**: the approach card's four ways (fight, ambush, parley,
  slip) grow the owner's four more — trade, tribute or toll, news or rumour,
  an escort or a job. Phase 3b, next.
- **More events.** #234 wants lots of them; this is the machinery and
  seventeen events. The table grows as data now, and packs can grow it too.
- **Chains that go further than one step**, and a follow-up tied to a place
  rather than to time (fires when the company reaches a town, a fork, a lair)
  — the spike's "pin a follow-up on a node or edge".
- The sweeps that measure a day's road (`tests/sweep_road_day.gd`,
  `tests/sweep_traits_road.gd`) still measure D3's self-resolving table via
  `Travel.check`, which is now the "as the orders have it" choice; a sweep
  over what players actually pick would need a model of what they pick.

## Meetings that are not fights — #232, #231 phase 3b (2026-09-26)

#232: "the encounters aren't necessarily solved with fighting." The approach
card (D4, `core/approach.gd`) already had one way through a hostile band that
was not a fight — parley, which pays a toll — and a friendly band on the road
offered only a greeting or walking on. The owner picked four more on
2026-09-26: **trade, tribute or toll, news or rumour, an escort or a job**.

- **Demand tribute** — the other half of a toll. On the hostile card, beside
  parley, but only against a band that has troops and that the company
  outclasses by `DEMAND_MARGIN` (1.5x its levels), and never against the
  mindless: nobody demands tribute of their betters, or of a zombie. An
  Intimidation check (DC 14), rolled by whoever is best at it, with the pace on
  the roll like every way; made, they pay `TRIBUTE_PER_LEVEL` (6) gold per
  level of troops and are gone; refused, a plain, even fight — they are not
  handed the first round, since it was the company that made the demand. The
  row prices both halves before the press, as every row on this card does.
- **Trade** — a caravan (the road's friendly stream,
  `RouteEncounters.meet`, source "caravan") opens its packs: two things at a
  road's markup (`CARAVAN_MARKUP` 1.25 over list), and "nothing today", asked
  on the road event choice card (`Approach.wares`, a road event built in code
  and held to `RoadEvents.validate`). Each thing is a choice with its price,
  disabled when the purse is short; buying is a real purchase. Seeded off the
  band, so a reload shows the same packs.
- **Ask for news** — anybody on the road has seen something: a way on the map
  to a place the company could not reach (a trail, shown at once — the same
  `RoadEvents.apply` a road event's trail uses), or, on a map without roads,
  the nearest hidden lair.
- **Ask for work** — somebody wants a crate run from the nearest town to the
  next (`QuestPosting.deliver_offer`, the board's own delivery), taken on the
  spot: it is a real job in the log, paid at the far gate, and it brings the
  escort objective to any fight on the way. The row names where and what it
  pays; the same run is not offered twice.

Both tolls now sit on the card side by side, and the friendly card has up to
five rows (greet, trade, news, work, move on). The card's "friendly meeting"
test (`FRIENDLY_WAYS`) knows the new ways, so a caravan's card shows the
friendly picture; demand wears the toll's gold and scales.

On the way, one thing in 3a kept honest: the road events achievement's "every
kind of road event" set is D3's table, so a follow-up, a caravan's packs or a
pack's own event counts toward the road-events tally but not toward "every
kind" (`RoadEvents.choose`).

Screenshots: `docs/shots/road-meeting-caravan.png` (a caravan: greet, trade,
news, work, move on) and `docs/shots/road-meeting-demand.png` (a weak band:
slip away, parley, demand tribute, ambush, engage), from
`tests/shot_road_choice.gd`.

Tests: `tests/test_approach_road.gd` (24: demand offered only against the
outclassed and never the mindless or an empty band, priced, paid or fought
plainly; the caravan's packs a sound road event, seeded, a real purchase,
refused when short; news a known way or a lair; work a real delivery, once;
no world, no new ways), and `tests/drive_road_events.gd` now also meets a
caravan on the real screen and buys from it. `tests/test_approach.gd`
(426) and `tests/test_approach_card.gd` (86) unchanged and green.

### Still open

- The friendly card still wears the hostile caption and stripe ("They have
  seen you", red): it always did, for greet and move on too. A friendly
  meeting deserves its own caption and colour — a card change for its own
  small PR.
- Escort as its own kind of job (walking a band's people to a town rather
  than carrying a crate) — the delivery's escort objective covers the fight
  half of it today.
- The demand numbers (`DEMAND_MARGIN`, `DEMAND_DC`, `TRIBUTE_PER_LEVEL`) and
  the caravan's markup are taste, for the balancing pass the owner put last.

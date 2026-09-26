## The road remembers — repetition, pace, degrees, the right item, variants (2026-09-26)

The research pass (`docs/research-road-events.md`, PR #278) found the road's
biggest risk was repetition: seventeen events and a question every six hours,
with no cooldowns, no one-time events, no quiet and no memory of the last
event. That is the complaint players make about CK3's travel events. The owner
said go on the first batch of its proposals (1, 7, 8, 10 and 11), one PR, all
in `core/road_events.gd` and new optional keys in `data/road_events.json`.

**The road remembers** (`world.road_seen`, `world.road_last`, saved; an old
save remembers nothing). An event is never asked twice running. It waits out a
`cooldown` before it can come again: a day (`COOLDOWN`) unless it sets its
own. Clear running sets 12 hours; the toll-men set three days. `once: true`
makes an event one-time. The new **bell in the river** is the first one: haul
it out, tell the village, or leave it. And sometimes the road has nothing to
say: `NOTHING_WEIGHT` is one more entry on the table. A follow-up is exempt
from all of it, because it was promised.

**The pace is no longer a metronome.** For `PACE_MIN` (3h) after a question
nothing is asked. After that, every `PACE_STEP` (1h), the chance climbs until
it is certain at `PACE_MAX` (9h). The gap averages ~346 minutes, against D3's
flat 360 (measured in `tests/test_road_events.gd` over 2000 gaps); the quiet
entries stretch that. A fight or a meeting starts the gap over
(`_road_quiet()` in `scenes/world/world.gd`), so nothing is asked of a company
still binding wounds. A due follow-up asks at once.

**Degrees of success.** A choice with a check may write a `triumph` (beat the
DC by 8, or a natural 20) and a `disaster` (miss by 8, or a natural 1). The die
decides first, BG3's rule, so a natural 1 is a disaster however big the bonus.
Where a choice writes neither, the roll is an ordinary pass or fail. Pushing
through the mud, watching the camp, digging out the cache, the storm's high
ground and the bell all have them. The event card names the result:
"✦ a triumph", "↯ a disaster".

**The right thing makes it certain.** `uses: {"item", "keep"?}` on a choice.
With the item in the pack, the choice succeeds without a roll, and whoever
would have rolled uses it. The item is spent unless `keep` is set. With a check
as well, the item is one more way through. Alone, the choice needs the item
and the card disables it when the pack has none. A Rope of Climbing makes
roping across the ford certain, and hauling out the bell; it is kept. The card
says so: "the Rope of Climbing makes it certain" (or "— and is used up"), and
the report carries a chip for it.

**Text that varies.** Any `text`, an event's or an outcome's, may be a list, and
one variant is picked with the road's own dice. Four events have variants so
far.

Content packs get all of it (docs/modding.md §5.3). The mod API snapshot now
also freezes the keys an event and a choice may carry
(`road_events.event_keys`, `road_events.choice_keys`). The validator reports
a triumph with no check, an item that is not one, a `uses` without its pass,
an empty variant, and a cooldown that is not a number. API level stays 1: every
key is new and optional.

Screenshots: `docs/shots/road-choice-rope.png` (the ford, with the rope
making it certain) and `docs/shots/road-triumph.png` (a triumph through the
mud, on the event card), from `tests/shot_road_choice.gd`.

Tests: `tests/test_road_events.gd` covers:
- memory, cooldowns, one-time events and the quiet, over 400 stretches with no
  repeat inside a cooldown;
- the pace's bounds and mean;
- every degree, including a natural die against the margin;
- items kept and spent, and a choice that needs one;
- variants for events and outcomes;
- the memory saved, and an old save.

`tests/drive_road_events.gd` covers, on the real screen, a meeting starting the
gap over and the rope carrying the ford without a die.

### Still open

- **Every number here is taste**: `COOLDOWN`, `NOTHING_WEIGHT`,
  `TRIUMPH_MARGIN`, the three `PACE_*` constants and the per-event cooldowns.
  They carry a `ponytail:` for the balancing pass the owner put at the end of
  #231. `tests/sweep_road_day.gd` still measures D3's self-resolving day.
- **Conditional text variants** (`[{if: "night", text}]`, CK3's
  `first_valid`): lists only, for now.
- The next proposals, in the research's order: choices that depend on who is
  in the company, with the same hero cast through a chain (2, 3); traits
  pushing back (4); weights from the world and follow-ups waiting at a place
  (5, 6); threads and standing problems (9, 12). More events alongside (#234).

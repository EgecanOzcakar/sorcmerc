## The completionist tours the roads — #231, the default map covered end to end (2026-09-26)

Routes became the default map (`2026-09-26-routes-by-default.md`), and the
robot that asks every door on the world screen whether it still opens —
`tests/drive_completionist.gd` — was pinned to `SORCMERC_ROUTES=0`, because
it was written for the free plane. So the map a player actually gets had no
end-to-end tour. That entry's first "Still open" item was this.

**`tests/drive_completionist_routes.gd` is the same tour of the route world.**
It extends the free-plane robot rather than copying it: the same checklist
(`REQUIRED`, `OPPORTUNISTIC`), the same chapters and the same contracts —
buying moves gold and the pack, a night at the inn spends the fee, the hours
and the wounds, and so on. The two cannot drift apart. The parent names the
steps a route world does differently as hooks, and the route tour overrides
only those:

- **Every order is a click on a place** (a town, a found lair or landmark),
  through the real input handler (`_order` → `_route_click`); a click after a
  pause lets the clock run with the HUD's own button.
- **Out of a gate** (`_step_out_of`) is a walk to the nearest other place
  that is not a monster's gate, and back in.
- **The open road** (`_into_the_open`) — where the tour short-rests, camps
  and is met — is the middle of a march to the farthest town, stopped with
  the HUD's Pause once no town is within 200 units. A camp may be made
  anywhere on a road (the owner's call).
- **`lair:search`** (`_search_for_lair`) is the Survival check at a fork: the
  tour marches along a road that passes a fork a hidden way leaves, and
  presses the lair button when it offers the search. Same deed and contract:
  the button rolls, and says what it rolled.
- **The four meetings** (`_band_in_the_way`, `_close_in`, `_band_gone`) are
  with a band pinned on the road 120 units ahead (`core/route_pins.gd`),
  arranged for the same reason the free tour spawns one — the road sends
  bands by its own dice — met on the same approach card as the march walks
  past, and taken off the road after.

The free-plane robot's behaviour is unchanged: its hooks' defaults are the
code they replaced, word for word. Its verdict line now names which tour it
is.

**One fix in the shared tour, found on the roads.** `_walk_into` took any
open market as the answer to "walk into this town". One route tour in six
failed at Ashfell: the road there runs through Riverhold, a fight on it
inside Riverhold's gate ended with the company halted — and a halted company
has arrived, so Riverhold opened (the map working). The tour read that as
the orc gate running a friendly market. `_walk_into` now accepts only the
gate of the town it is walking to, and walks out of any other; the free
tour had the same latent trap.

Proof: after the fix, ten route tours and three free tours, all green, 43/43
REQUIRED each — including `lair:search` and `meet:card` on the roads, the
two the free tour missed when the default flipped under it.

### Still open

- The other world-screen tests pinned to the free plane
  (`2026-09-26-routes-by-default.md` lists them) still want their road
  counterparts, one by one, as the free plane's systems retire.
- The tour meets its four bands by arrangement. A tour that waits for the
  road to send them would be the road's own odds under test, which is
  `tests/test_route_travel.gd`'s long walk and `tests/sweep_route_travel.gd`'s
  subject, not this file's.

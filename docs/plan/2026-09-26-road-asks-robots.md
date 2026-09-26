## Two robots taught that the road asks — master green after #274 (2026-09-26)

#274 ("the road asks", `2026-09-26-the-road-asks.md`) was merged while its
full-suite run was still going, and two robots went red on master. Neither is a
fault in the game; both assumed a road event is one card.

- **`tests/drive_routes.gd` — "the lair button offers the search at the
  fork".** A road event is now two cards: the question, then the answer on
  D3's card. The robot waves one card away per frame, so its last lap could
  end with the answer still up, and a card up hides every map button — the
  lair button among them, which is right. The robot now answers every card
  that is up before it stands at the fork. Failed every run before; 3 of 3
  green after.
- **`tests/drive_completionist.gd` (and its route twin) — "Leave did not give
  the world clock back".** The inn's night runs the clock past the road's
  interval, so the road asks the moment the company is out of the gate, and
  an answer that turns into a fight stops the clock too. Both stop it on
  purpose. The check now counts a road card or a fight as the map working, as
  it already counted a band's approach card. After the change: 6 route tours
  and 3 free tours, all green.

### Still open

- Nothing from this; the lesson is the process one — a full-suite run should
  finish before a merge, which is the reviewer's call, not the robot's.

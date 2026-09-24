## The price of magic, enforced — rest and slots (2026-09-24)

The design audit (docs/audit-game-design.md) found seven places where the
bible's third pillar, "magic is powerful but costly", had a side door or a
blind spot: the cost was real in the rules and missing where the player
stood. This batch builds the owner's calls on §1.1, §1.6, §1.7, §1.9, §4.1,
§4.2 and §4.3. None of it moves a measured number; it closes doors the
sweeps never walked through.

**The sheet only shows (§1.1).** The character sheet had HP −5/−1/+1/+5/full
buttons, a − and + on every pool, and a "Long rest (restore all)" button,
reachable from the map's party page in open country. A sorcerer could refill
sorcery points there and turn them into slots in the next fight. All of it
is gone (`scenes/profile/profile.gd`); the sheet equips gear, levels up and
casts road spells, and nothing else. The drive robot's profile sweep lost its
stepper exemptions with the steppers.

**Real slots everywhere, from one source (§4.1).** The sheet's "Level N
slots" rows were a `pools["slot:N"]` counter nothing else read; the party
page had no slots at all; the combat pips took their maximum from the slots
left when the fight began, so a slot spent in an earlier fight vanished
instead of showing as spent, and a level with none left was hidden.
`Adapter.slot_table(ch)` (and `combat_slot_table(c)` for a fighter mid-fight)
is now the one reading: `[{level, left, max, pact}]`, `max` from the sheet,
`left` from `slots_used` — including Font of Magic's negative entry, which
reads one over the maximum until the long rest, and the warlock's Pact Magic
row. The sheet shows it as "left/max", the party page's roster rows as a new
✧ line of pips (`Party.summary()["slots"]`), and the actor line in a fight as
the same pips (`Adapter.slot_pips`). A foe with no sheet still takes the
count it walked on with.

**Rope Trick is the kit and nothing more (§1.6).** It used to skip the camp
kit *and* the 8% ambush, and the long rest it enabled handed its slot
straight back. Now the ambush roll is made whether the night is roped or not
(the owner's follow-up: Rope Trick does not cancel it), and the slot is
*held*: `RoadSpells.cast` records `{id, level, spell}` in `party.camp_holds`,
`Visit.rest()` spends it again after every long rest until the camp is made,
and `WorldCamp.make_camp()` lets the hold go once it is. So the morning after
a roped camp, the caster is a slot down, and the rest's line says which.
Alarm is held the same way and keeps its benefit (the ward hears an ambush
whatever the watch rolled); it is now spent by the camp it was cast for,
where it used to stay up through every quiet night until one was not. The
whole camp decision moved out of `scenes/world/world.gd` into
`WorldCamp.make_camp()`, so it is tested headless.

**A long rest moves the world, and nobody camps next to a band (§1.7).** The
480 minutes went straight onto `clock.elapsed`; bands only move inside
`World.tick`, so nobody walked during the night. `core/world_rest.gd` steps
the night a world-minute at a time: bands re-plan and walk (water respected
hop by hop), opinion drains and drifts, raids set out, besiege and land, and
the map's off-screen battles run through a per-step hook. The sleeping
company does not move and is not hunted (`WorldAI.update`'s `asleep`), so a
rest cannot be broken in the middle; the camp's one interruption is still
its ambush roll, and a band whose own walk ends near the camp is met in the
morning like any band. Every long rest goes through it: the inn, the camp and
downtime. Making camp now refuses with a hostile band in reach, exactly as
the short rest always has (`WorldCamp.hostile_near`, the map's
`ENCOUNTER_RADIUS`): "Too dangerous to make camp here: something hostile is
close." A night on the small map costs ~0.13 s, ~0.5 s with its off-screen
battles (measured once, headless, on the demo map).

**Downtime keeps the 24-hour gate (§1.9).** Training, carousing, crafting and
the lodge's retraining ended every stay with a long rest regardless, so a
day's work begun the morning after a rest refilled everything sixteen hours
later. `Downtime.spend_days` now asks `Visit.can_long_rest` as the last
night begins; when it is shut, the days still pass and the bed is still paid,
but nothing refills and the rest stamp does not move.

**Arcane Recovery works (§4.2).** `Adapter.arcane_recovery` existed and only
tests called it. `Adapter.rest(ch, "short-rest")` now ends with
`arcane_recovery_auto`: a wizard who has not used it since the last long rest
gets back spent slots whose levels add up to at most half the wizard level
(rounded up), none above 5th, picked greedily highest first. It is used up
the first time it restores anything, and a short rest with nothing spent
leaves it for later. A never-rested wizard reads as having it ready (missing
key means full, like every pool). The map's, the site's and the linear
campaign's short rests all get it; the map and the site say what came back
("Mara works through the spellbook: Arcane Recovery brings back a level 3
slot."). The sheet shows it as ready or used. The manual's rest page and the
wizard's blurb now say what is built.

**Trance banks a short rest (§4.3).** Its short-rest top-up ran the moment
the long rest ended, when everyone was full, so it did nothing. A long rest
with a Trance hero in the company now banks one short rest on the party
(`party.trance_rest_until`, saved; an old save has none), good for a day and
no later than the next long rest. The company's next short rest takes it
first and does not count it against the two RAW allows; with the two gone, a
banked one can still be taken. The inn's and camp's line says it was banked,
and the short rest's line says when it was the banked one. Scouting and the
free identify are unchanged.

The manual's "Rests and resources" page, the design bible's price-of-magic
section and the balancing skill's refill list were brought in line with all
of the above.

Tests: `tests/test_rest_and_slots.gd` (new: the slot table and its pips,
combat maxima, Arcane Recovery, the Trance bank, the walked night and a
hunter that does not come for a camp, the downtime gate, camp refusals, and
Rope Trick's and Alarm's holds); `tests/test_profile.gd` (no edit buttons,
real slot rows, a Font slot over the maximum); `tests/test_road_spells.gd`
(holds, and a save round trip); `tests/test_trance.gd` (no top-up at wake);
`tests/test_rest_mechanics.gd` (its "an ordinary caster's slot stays spent
through a short rest" case is a cleric now, since a wizard's short rest
recovers one on purpose); `tests/drive_buttons.gd` (the profile sweep).

### Still open

- **The short rest still jumps its hour.** Only the long rest's eight hours
  are stepped (`core/world_rest.gd` has a `ponytail:` on it). Step it too if
  an hour of bands walking ever turns out to matter.
- **Downtime's days are jumped, not walked.** Only the last night of a stay
  is a stepped long rest; the days before it still land on the clock in one
  go, so a band does not walk through a five-day training either. The map's
  per-frame catch-ups (lair expiry and respawn, band refill) settle them on
  the next frame, but bands do not move. Worth doing with the §1.8 defeat
  costs, which also spend days.
- **Arcane Recovery picks for the player.** Highest first, greedily; a
  `ponytail:` on `Adapter.arcane_recovery_auto` says so. A picker on the
  rest's message is the fix if anyone wants two 1sts over a 2nd.
- **A Rope Trick cast and then slept off at an inn** holds its slot through
  that inn night as well as the camp it still pays for — the spell is still
  waiting. That is deliberate (otherwise an inn night would refund the slot
  and leave the rope up for free), but it can charge one cast twice if the
  player never camps soon after.
- **The hermit's safe hollow shares Rope Trick's flag.** The landmark reward
  "A safe camp tonight" (`core/landmarks.gd`, the hut's "Ask about the
  road") set the same `party.safe_camp`, so it now spares the kit but not
  the ambush roll, and its line says so ("A dry hollow to camp in tonight:
  no camp kit needed."). No slot is held for it. If the owner wants the
  hermit's hollow to stay ambush-free, it needs its own flag.
- **Hunters make for the town the company sleeps in.** A goblin or bandit
  band hunts the nearest hostile thing, towns included, and eight walked
  hours at an inn are enough for it to reach the gate. Leaving the next
  morning can mean meeting it at once. That is the world moving, as asked;
  whether the inn should warn of a band at the gate is open.
- **A band that walks near a camp in the night** is met in the morning, on
  the first frame after the camp's card is acknowledged. The camp's own
  ambush roll is still the night's only interruption; whether a morning
  meeting should get its own card line is a tone call left open.
- **Bench rotation and rest gold** (audit §4.4's estimates) are not swept
  here; they are their own batch.

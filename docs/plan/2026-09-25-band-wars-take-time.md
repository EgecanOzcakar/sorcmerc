## Band wars take time — a clash told round by round, and heard by nobody (2026-09-25)

Two issues about the fights the map's bands have with each other, which the
player only ever sees from outside.

**#229 — a band-vs-band battle used to be over in the frame the two met.**
`core/world_battle.gd` fought it headless and erased the loser on the spot: a
ten-round fight in no world time at all, one figure simply gone. Meeting now
opens a **clash** (`World.clashes`, `core/world.gd`). The fight is still fought
once, headless and seeded off the pair's ids, in the frame they meet, but its
verdict is held back: both bands stand where they met — `World.tick()` does
not walk them and `WorldAI.update()` does not steer them — for as many rounds
as the fight lasted at `WorldBattle.MINUTES_PER_ROUND` (10) world-minutes
each, and only when the clock has run through the last of them does the loser
fall (`WorldAI.fell`, so a monster band still comes back two days on) and the
winner walk on. `WorldBattle.check()` still returns `{winner, loser, outcome}`
per fight, now as each one ENDS, so the map's `Visit.mark_battle` reads the
same as it always did; `start()` and `settle()` are its two halves.

Fighting it up front and telling it over time, rather than stepping a live
Combat a round an interval, is what makes it survive a save: a clash is eight
plain fields (`a`, `b`, `winner`, `outcome`, `rounds`, `at`, `from`, `until`)
under a new `"clashes"` key in the world save, and a reload mid-battle resumes
the same battle with the same verdict — it cannot be re-fought into a
different one. A save from before this has no key and loads with none. A
clash one of whose bands leaves the map some other way (`core/raids.gd` sends
home raiders whose lair is gone) closes with nobody lost.

Ten minutes a round, not the party's hour: measured over every hostile pairing
of ten map factions, two seeds each, `Presets.party()` rosters at normal (84
fights, `WorldBattle.fight` directly), a band's AI-vs-AI fight runs **median 10
rounds, mean 11.6, p90 18, max 35, min 3** — about twice a party's. Billed the
party's hour a round, the median pair would be off the map for ten hours. At
ten minutes the median clash lasts 1h40 on the clock (100 real seconds at 1x,
12 at 8x), p90 3h, the longest just under 6h. Nothing wins or loses by the
number, so it is a taste number over a measured distribution, marked
`ponytail:` with its re-measure condition.

**The player arriving mid-battle.** Both bands have their hands full.
`_check_encounter` skips a band in a clash, so the party can stand and watch
or walk straight past. A fighting band's figure is not clickable (`_band_at`
skips it), so a click on it is a click on the ground there and the party
marches up to watch; a band the party was already following or chasing that
falls into a clash first stops the march at its edge with "The Cold Spring
raiders are locked in a fight with the Saltmarsh wardens — nobody will stop to
talk until it's over." (`_meet`). The moment it ends the winner is an ordinary
band again, and a hostile winner still beside the party opens the ordinary
approach card. The figure-click rule came out of one full-suite run of
`tests/drive_completionist.gd` (an unseeded robot) whose walks all ran out of
frames with the figure still clickable. The loop that fits is a march target
under a fighting band: the click hits the band, the march stops at its edge,
the robot re-orders and clicks it again. Three more runs after the change were
clean. `tests/test_world_meet.gd` now checks all three rules.

**What the player sees.** The ground the two are fighting over is ringed in
the foe's red and throbs (`ground_marks()`, `CLASH_RADIUS`); each band's label
reads "· fighting, round 3/16", counting off as the clock runs
(`WorldBattle.round_of`); and both figures square up to the middle of the
fight and lunge at it (`Party3D._brawl`, a procedural jab in the same spirit as
the procedural walk, because the models ship one idle clip).
`tests/shot_clash.gd` stages one beside the player:
`docs/shots/issue-229-band-battle.png`.

**#227 — the sound of other people's fights.** Every kill, collapse, miss and
crit in a band-vs-band fight played through the Audio autoload, all in the one
frame it was resolved in, over the campaign map. The suite never heard it
because a test's main loop has no autoload and `Sound.*` no-ops there. Combat
has a new `audible` flag (default true) beside T19's `tracked`; every sting in
`core/combat.gd` now goes out through one `_sfx()` door that checks it, the
bark's voice is gated beside it (its variant still rolled, so the bark stream
is the same heard or not), and `WorldBattle.fight` turns it off. The player's
own fights are untouched. Cosmetic only, so outside `Coop.state_hash` on
purpose.

`tests/test_world_battle.gd` is rewritten for the new shape (43 checks): a
meeting opens a clash and nobody falls yet; a minute short of the last round
both still stand, at the last round the verdict decided at contact lands;
locked bands do not move and the winner walks the moment it ends; the same
meeting resolves the same way and takes as long; a clash rides a JSON
round-trip of the save and ends the same way after it, and an old save loads
with none; a third band waits its turn; a side leaving the map ends it; and an
`Ear` on the Audio statics hears nothing from a whole band fight, while the
same Combat left audible is heard (the control). With `cb.audible = false`
commented out the #227 check fails with the miss, claw, crit, down and kill it
heard.

### Still open

- **Wading in as a third side.** The party cannot join a clash — attack the
  side it favours, or fall on the winner while it is still catching its
  breath. It wants a fight built with two foe rosters, one of them allied, and
  that is a Combat feature, not a map one.
- **The winner carries no wounds.** A band has no HP between fights, so the
  winner of a sixteen-round clash is as fresh as it was before it. When bands
  get a strength that can be spent, the rounds a clash ran are the natural
  thing to spend it by.
- **The co-op guest's mirror** learns of a clash only from the next full save
  (`Coop.world_full`); `Coop.map_delta` carries positions only, so a clash that
  starts mid-session is drawn on the host's map and not the guest's until then.
  Add the clash list to the delta if a guest ever needs to see one live.
- **Rosters are priced at contact.** `encounter_spec` reads the player's party,
  so each side of a clash is what it would have been against the party the
  moment the two met. That is right for the verdict; it only matters if a
  clash ever runs long enough for the party to level in the middle of it.

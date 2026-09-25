## Choices with teeth — parley, defeat, the end of a company, deadlines and the board's edge (2026-09-25)

Seven of the owner's calls on the design audit (docs/audit-game-design.md,
"The owner's calls", and the follow-ups asked after round one). Each one puts
a cost back on a choice that had none, or a choice back where there was only a
cost. None of them moves a measured number: the new numbers are taste
numbers, and each says so where it is defined.

**A failed parley with a band that keeps no opinion gives it the first round
(§3.1 follow-up).** Round one made a failed parley cost faction opinion, but
only a people that keeps one pays it (`WorldAI.CIVILIZED`), and most parleys
are with bandits and goblins: for them a failed parley was still exactly
Engage, a free roll before every fight. Now it hands them the first round, the
same surprise a blown ambush hands over (`forced_ambush`; `core/approach.gd`).
The card's row says so before the press ("They take the offer as weakness,
and the first round with it.") and the result line after it ("…and they come
in while the company is still talking."); the card is drawn as a setback.
Civilized peoples keep the opinion cost and do not also take the round.

**The company is finished (the owner's call).** When the whole roster died
after a defeat, the highest-level hero came to alone, because the open world
had no end screen (a `ponytail:` in `Party.revive_downed`, now gone). Now the
run ends. `Party.revive_downed` stands nobody up and says `finished`; the map
(`_end_company` in `scenes/world/world.gd`) writes `Defeat.ending()`'s record
onto the party, sends the living to the barracks and takes the dead out of it
(`Defeat.to_barracks`: a dead hero's file is deleted, so an inn never offers
them back as a veteran), writes the slot one last time and hands over to
`scenes/game/game.gd`'s `show_company_end`: the linear summary's panel and
defeat art, "The company is finished", who fell last, how many days the
company lasted and what it was called on the renown ladder, and the roll of
everyone who marched under it. The world save carries the record at the top
as `finished` (`core/world_save.gd`); the title screen lists a finished slot
with "The company is finished: read the roll" in place of Resume, still with
its Delete, and `_resume_world` refuses to open one. An old save has no key
and is not finished. A site wipe that leaves nobody ends the same way.

**The hermit's hollow is never jumped (the owner's call).** Round one's §1.6
put the ambush roll back on a Rope Trick night, and the landmark's safe camp
shared Rope Trick's flag, so the hollow lost its one promise with it.
`party.hollow_camp` (saved; an old save has none) is its own flag:
`WorldCamp.make_camp` spends it before a Rope Trick or a kit, spares the kit
and does not roll the ambush at all. It is still a long rest behind the
24-hour gate, still refused with a hostile band in reach, and still eight
walked hours. A Rope Trick up on the same night is spent with it. The card
now reads "A dry hollow to camp in tonight: no camp kit needed, and nothing
will find it."

**Decided, no code (the owner's calls).** Rope Trick's slot stays spent until
the camp it was cast for is made — including through an inn night slept in
between, which round one left as an open point. A level-17 sorcerer, who has
six Metamagic picks and five built options, repeats one pick until a sixth
option is built. Both are recorded in the design bible's decided list.

**A defeat costs more than the purse (§1.8).** The defeat tax is 15% of
carried gold and the strongroom (`core/lodge.gd`) shelters the rest, so
banking everything made losing nearly free. `core/defeat.gd` adds two costs
the purse cannot touch, paid by every open-world defeat and every site wipe.
The company comes to `Defeat.DAYS_LOST` (1) day later, and the world walks
through that day the proper way (`WorldRest.pass_time`, with the map's
off-screen battles): bands move, raids land, opinion drifts, and a quest's
deadline runs down. It is not a rest; nothing refills. And every hero the
fight put on the ground who is still alive makes a seeded CON save against
`Traits.DEFEAT_DC` (12): failed, Wounded; failed by 5 or a natural 1, Maimed.
These are the wound traits a failed death save already leaves, mended the same
way (an inn, or a city for Maimed), with their moment cards. The map's line
says "…come to at Riverhold a day later, 60 ◉ lighter." Because the beaten
company now lies a day where it fell, the band that beat it could walk off
and back, which cleared its slip; it is now also given a truce, as a band
slipped past is. Both numbers are taste numbers, not a sweep's.

The parley toll with an empty purse no longer takes nothing. It takes one item
from the packs, picked by a seed off the band and the minute, so the card
can name the item before the press and the parley takes that same item. It
never takes quest goods (anything an open job is collecting or supplying).
`Approach.toll_item`.

**Quest deadlines (§3.4).** Bounties (`hunt_party`, and the innkeeper's
head-count `kill_count`) and rescues carry `deadline_days`
(`Posting.DEADLINE_DAYS`: rescue 3, hunt 4, head count 6, taste numbers):
the posting says "4 days to do it", `Quest.accept` stamps the world-minute it
runs out at, and the quest log says "2 days left". Past it, a job still being
done fails: `Quest.expire` takes it out of the log, the way a lost delivery
is, so the board can post it again, and the map says "Too late: …". A job
already done keeps and can still be turned in. Errands, deliveries, scouting,
war work and lairs stay open-ended. A quest with no deadline (every job in an
old save) never expires. A content pack's story quest may carry the same
optional `deadline_days`; it is documented in `docs/modding.md` and validated
in `core/mod/story.gd`. Nothing was removed or renamed, and no vocabulary
list in the API snapshot changed.

**Leave the field (§3.5).** The only way out of a fight was "Admit defeat". Now
a hero standing on a board-edge hex can spend their action on "Leave the
field" (a BASIC verb, `leave_field`, kind `withdraw`, a two-press confirm on
the bar, with its own icon from `tools/gen_action_icons.py`). They are out of
the fight: off the board, not conscious, alive at the HP they left with. Walking
off from beside a foe provokes it unless the hero Disengaged; a hero cut down
by that swing does not get away. Grappled or restrained, nobody leaves. The
heroes left behind fight on. When the last conscious hero walks off, the
fight ends as a WITHDRAWAL (`Combat.WITHDRAWN`): `Encounter.resolve_outcome`
pays no XP, no coin, no loot and no kills (so no quest progress), nothing is
scored, and the map charges no defeat cost at all. The band stays where it
was, slipped and under a truce, and the after-action page is headed
"Withdrawn". Anyone left lying on the field then is dead: with nobody left
standing to engage, the mercy rule has nothing to hold the foes back, and the
log and the map name them. If instead the heroes left behind are all beaten,
it is a defeat as ever. On a hero's turn the board tints its edge hexes, and
tints the hex under a hero standing on one more strongly. Only the open world's
road fights allow it (the spec's `withdraw`). A site's room has its own way
out between rooms, the pit is a bout, a breakout's way off the board is its
objective, and the linear run never asks.

For co-op, the verb crosses the wire by id through `all_verbs`, `perform()`
refuses before paying anything (`leave_refusal`), the new `withdrawn` status
is in the hashed statuses (and in `ActiveEffects.HIDDEN`), and `withdrew`,
the one new field outside them, is added to `Coop.state_hash`. `test_coop`,
`test_coop_kits`, `test_class_abilities` and `test_active_effects` pass.

Tests: `tests/test_approach.gd` (the first round, the item toll, never quest
goods), `tests/test_rest_and_slots.gd` (the hollow on a minute that jumps
every other camp; Rope Trick on that minute still jumped), `tests/test_landmarks.gd`,
`tests/test_defeat.gd` (new: finished, the walked day, the seeded wounds, the
record and its words, the barracks, the save flag and an old save),
`tests/test_party.gd` and `tests/test_world_defeat.gd` (no lone survivor; the
day and the wound roll on the map; the save marked finished),
`tests/test_quest_deadlines.gd` (new), `tests/test_withdraw.gd` (new: only
where allowed, the edge, the provoked swing, refusal changes nothing, the
withdrawal pays nothing and buries the left-behind, left-behind beaten is a
defeat, lockstep and the hash).

Screenshots: `docs/shots/choices-with-teeth-parley.png` (a goblin band's card,
parley's first round on the row), `choices-with-teeth-finished.png` (the
closing screen), `choices-with-teeth-deadline.png` (a bounty's posting with
its days), `choices-with-teeth-leave.png` (the edge tinted and Leave the field
on the bar).

### Still open

- **A withdrawal from a co-op guest's screen** runs through the same intent,
  but the guest's after-fight map is the host's to draw, as with any outcome.
  A finished company in a co-op room ends on the host's screen only; the
  guest's copy of the map is left where it was until the room closes.
- **The downed left behind die.** This rule was not in the owner's call. It
  follows the mercy rule (nobody left to engage), and it keeps a withdrawal
  from being a free escape with half the company on the ground. If it reads
  too hard, the other option is to carry a downed hero off from an adjacent
  hex at the cost of the carrier's move.
- **The foes do not use the edge.** A band never withdraws. A routing-foe rule
  would be its own balance pass.
- **DAYS_LOST, DEFEAT_DC and DEADLINE_DAYS are taste numbers.** They belong
  with the §3.2 wounds-curve sweep, which is the one that should say how
  much a lost fight is allowed to cost.
- **A finished slot keeps its world file.** It is listed until the player
  deletes it. Whether a finished run should also leave a line on the profile
  or an achievement is open.
- **A deadline shows in days, not on the map.** The quest marks
  (`Quest.map_marks`) do not dim as a job runs out. A countdown there is the
  obvious next step if deadlines get missed without being noticed.

## Mercs remembered — death, a service record, and recruits with a past (2026-09-25)

The design audit (docs/audit-game-design.md §2, "Pillar 1 — every merc is
memorable") found the counting and the bonds already in the code and almost
none of it reaching the player: a death was one line on the spoils page, the
kills-toward-a-bane counts were on every sheet and on no page, and a recruit
was a name and three trait words. The owner's calls §2.1, §2.2 and §2.5 settle
each; this entry builds all three.

**§2.1 — death has weight.** `core/fallen.gd` (new) is now the one door the
open world applies a death through; `scenes/world/world.gd`'s `_apply_deaths`
calls `Fallen.apply` and nothing else. For each of a fight's dead it reads who
was close to them (`PartyOpinion.close_to`: bonded or lovers, anywhere on the
roster, the bench included) before anything moves, marks and benches them as
before, and then:

- **counts the death** toward "The Cost of Doing Business" (Ach `deaths`),
  which only the linear campaign used to bump, so the achievement and the
  death tally work in the open world;
- **writes them on the roll of the fallen** — `party.fallen`, one entry each:
  name, level, class, where ("on the road near Riverhold", "in The Vale
  Warren", "in the pit at Ashfell"), what killed them (the fight's credit),
  the world-day. Saved in the world save and the campaign save beside the
  lodge; a save from before it reads as an empty roll. The lodge page has a
  "The roll of the fallen" section, and the party page a "The fallen" group
  under the roster: "Vera Kord, fighter 3. Fell to a goblin boss on the road
  near Riverhold, on day 6." A hero raised later stays on the roll, marked
  "Raised since.";
- **asks grief of the bonded** — `Traits.grieve`, a new hardship
  (`bonded_died` in data/traits.json). Unlike the witness's "Watched a friend
  die", which is asked of anyone in the fight at 50% whoever died, grief is
  guaranteed and harder: the witness's DC off whatever did it, plus
  `GRIEF_BONDED` (2), or `GRIEF_LOVER` (4) for a lover. Made well they are
  Hardened; failed, **Grieving** (a new wound: −1 to hit, seven days); failed
  badly, Shaken too. The bench grieves as well — a friend who was not there
  loses them just the same. A hero who grieves is spared the witness's
  fifty-fifty (`after_fight`'s new `grieving` context), so nobody is asked
  twice for one death. The save is seeded off the griever, the dead and the
  minute;
- **is an opinion event** (the spike doc's "a lover's death is not an event
  yet"): `PartyOpinion.mourn` — two who lost the same person draw together by
  `SHARED_GRIEF` (8, a camp warming), and the ones who loved the dead cool by
  `SURVIVOR_BLAME` (4; 8 from a lover) toward each who walked away from that
  fight and was not grieving too. The pair with the dead is kept, so a raise
  gives it back;
- **gets a camp beat**: the first fire after a death speaks of the dead, once
  (`Fallen.camp_beat`, first in `_fireside`, before a calling's telling): a
  mourner at the fire says it ("Pike Sallow tells the others how Vera Kord
  came to be with the company. Nobody interrupts."), or the company does when
  nobody marching was close to them.

**The dead stay out of the veteran pool.** `Recruits._veteran_for` skips a
barracks file that says dead, and `Recruits.build` no longer stands a veteran
back up — the two lines that cleared `dead` on the way into a new run are
gone. A hero who died and was never raised stays dead across runs.

**§2.2 — a service record.** `core/service.gd` (new) reads it back. The
profile has a **Service** panel: fights and wins, times put down, kills in all
and by faction, and each faction's progress toward its bane ("7/10 toward
Orc-bane", "12, Goblin-bane", or the reason the caps block it — "already
known for two banes") and toward Veteran ("17/20 wins"). The thresholds are
the trait rules' own constants (`Traits.BANE_KILLS`, `BANE_KILLS_DRAGON`,
`VETERAN_WINS`), and the blocked reasons come from `Traits.refusal`, the check
`grant()` itself now calls, so the panel cannot promise what the rules would
not hand over. Fights are newly counted (`trait_counts["fights"]`, bumped in
`after_fight` for everyone in the fight); an older hero's record never shows
fewer fights than wins. Each earned trait on the profile now says why and
when, from the "why" and "since" it always stored: "Earned on day 4: 10
goblins killed." The spoils page credits the killer on each kill chip —
"Goblin ×2 100 xp / struck by Pike Sallow ×2" — from `result.credit`.

**§2.5 — recruits with a past.** Every chair at an inn has a one-line intro
(`Recruits.intro`): what their background made of them and what they are
like, two sentences with the subject left off the way a trait's text reads
("Has slept in more ditches than beds, and complains of neither. Checks the
floor, the ceiling and the way out, in that order."), two lines for each of
the sixteen backgrounds and each of the eight temperaments, picked off the
name, background and temperament so the same face says the same thing on
every look. A veteran's row adds their record from earlier runs
(`Service.veteran_line`): "Two companies before this one: 27 fights, 15
kills, one scar." — runs are counted as a hero joins a company
(`Service.enlist`: the founder when a run begins, a hire when the fee is
paid). And each background has two or three callings now, not one
(`Callings.VARIANTS`, eighteen new ones): a hero's is picked when it is
assigned, seeded off the hero, kept in the save as `variant` (missing in an
old save, read as the first), and when the picked past has nothing on this
map to point at the next one that does is taken instead of none. Round one's
target fix holds and is extended: a band past about people who keep papers
or grudges names its factions (the merchant's bought note is bandits or
soldiers, the sailor's mutineers bandits, the acolyte's taken novices
cultists). A pack's `callings.json` entry for a background is the past for
it: the built-in alternatives step aside while the pack is on
(docs/modding.md §5.2 says so; no new vocabulary, the API snapshot is
unchanged).

Tests: `tests/test_fallen.gd` (new: the door, the roll and its line, grief
guaranteed and harder for a lover, the bench grieving, two deaths in one
fight, the witness spared, the web, the fire's once-only line, the save
through JSON, the world save and the campaign save, an old save),
`tests/test_service.gd` (new: the record, progress off the rules' constants
and caps, a due bane or Veteran arriving as the panel said, the origin line,
who struck the blow, the veteran line), `tests/test_world_fallen.gd` (new:
the world screen end to end — spoils credit and grief, the roll with where,
the achievement, the fire, the lodge's wall, the party page, the inn's
intros), `test_recruits.gd` (the dead never offered and never raised, the
veteran's record, runs counted at the hire, every recruit's intro),
`test_callings.gd` (the variants validated, seeded, falling back, saved, and
stepping aside for a pack), `test_profile.gd` (the Service panel and an origin
line). Ran green: those, plus test_traits_earn, test_traits, test_party_opinion,
test_world_traits, test_world_callings, test_world_fireside, test_world_spoils,
test_world_defeat, test_world_lodge, test_lodge, test_world_save,
test_campaign_save, test_coop, test_coop_kits, test_mod_api, test_mod_packs,
test_game_flow, test_road_trip.

Screenshots (`tests/shot_mercs_remembered.gd`, under xvfb at 1600x1200):
`docs/shots/mercs-remembered-service.png` (the Service panel, and "Earned on
day 4: ..." under a trait), `-spoils.png` (who struck the blow, the death, a
lover's grief), `-fire.png` (the first fire after), `-lodge.png` and
`-party.png` (the roll of the fallen), `-inn.png` (an intro on every chair and
a veteran's record).

### Still open

- **Grief is not in a sweep.** `tests/sweep_traits_earn.gd` passes no
  `grieving` and its preset trio holds no bonds, so its table still describes
  what it measured; how often a company with bonds in it now carries Grieving,
  and whether `GRIEF_BONDED`/`GRIEF_LOVER` and the Grieving row's −1 to hit are
  the right size, is taste until a sweep with bonded pairs runs.
  `SHARED_GRIEF` and `SURVIVOR_BLAME` are taste numbers sized against the camp
  beats, likewise unmeasured.
- **The linear campaign keeps its own death rule** (`core/campaign.gd`
  `finish_combat`, T10's revive at the end of the road, and its own
  `deaths` bump on a won fight): no roll, no grief there. It is the debug
  path; route it through `Fallen.apply` if it ever matters again.
- **A lost pit bout's fallen are carried out** (not dead), so they neither
  grieve nor go on the roll; but a bonded fighter in that bout is still spared
  the witness's save for a death that did not happen. Harmless, and noted.
- **Kills by a hero who died in the same fight are not counted** toward their
  record (after_fight counts kills for the living only, as it always did);
  the spoils chip still credits them.
- **An older hero's fights read as at least their wins**; fights before this
  entry were never counted, so their record's fight count starts low.
- **Runs are counted from here on.** A barracks hero from before reads as one
  earlier company at the inn.
- **The camp-line and bench decisions (§2.4, §2.6)** and the bark pools
  (§2.3) are other entries. `core/callings.gd`'s header no longer says every
  companion is player-made (it had to change to stop saying "one per
  background"); `core/party_opinion.gd`'s still does, and is §2.6's to fix.

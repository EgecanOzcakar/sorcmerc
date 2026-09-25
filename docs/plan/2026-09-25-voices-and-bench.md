## Voices and the bench — barks by temperament, a bench that minds, and the fire's lines (2026-09-25)

Three of the owner's calls from the design audit (`docs/audit-game-design.md`
§2.3, §2.4 and §2.6), all about the company as people rather than a roster.
The audit found a company whose members shared one voice in a fight, one set
of eight lines at the fire, and a bench that cost nothing and meant nothing.
"No wages" stays; nothing here charges the purse.

**§2.3 — party barks per temperament.** `core/barks.gd` had one shared
`PARTY` pool, four to six lines a trigger, drawn from at 20% for whoever spoke.
Each of the eight temperaments (`data/traits.json`'s `temperament` family:
Brave, Craven, Wrathful, Calm, Greedy, Generous, Curious, Cautious) now has
its own pool for every trigger, three lines each, in `PARTY_TEMPER`, and a
hero speaks from theirs (`Barks.temperament(c.traits)` in `Combat.bark`). A
temperament with no line for a trigger — one a content pack added, or a hero
from before traits — falls back to the shared pool, which stays. One new
trigger, `partner_down`: when a hero hits 0 HP, the first bonded friend or
lover to rally (`PartyOpinion.rally`, already wired) says so, by the fallen's
first name — "{ally}! I'm coming — hold on!" from a Brave one, "Easy. {ally}
needs us steady." from a Calm one. The name comes from the Combatant that went
down, so a line that names someone always names an ally really in the fight,
and a named line with no name to give is never said. It speaks every time
(`CHANCE_BY_TRIGGER`), since a partner goes down a handful of times a campaign
and the name is the point; taste, not a sweep. Selection is off the fight's
own bark stream (`_bark_rng`, seeded off the fight seed) exactly as before,
never `cb.rng`, so co-op lockstep is untouched. Dialogue keeps its
contractions and its "!" — it is speech.

**§2.4a — restless mercs may leave.** New `core/bench.gd`. A merc left out of
the marching order for `RESTLESS_DAYS` (10) grows restless and the company is
told, once, on a card on the live map ("Gera Ashvein has sat on the bench for
10 days now … Put them in the marching order soon, or they may leave the
company."). After `LEAVE_AFTER_DAYS` (5) more, each morning carries a
`LEAVE_PCT` (34%) chance they are gone, told on a second card; the leaver is
filed back in the barracks, where an inn may offer them again one day as a
veteran. The roll is seeded off the merc and the world-day
(`hash("bench-leave|id|day")`), so a reload replays the same morning. Never
mid-fight (the beat is only asked over a clear map — no fight, site, visit or
card — `scenes/world/world.gd`'s `_check_bench`), never the founder (the first
name on the books, skipped outright), never below `MIN_ROSTER` (4) living. A
day in the line is the whole cure: the clock starts over. All four numbers are
taste, not a sweep, and say so. The clocks live in the new `party.bench_clock`
(id → `{since, warned}`), kept lazily off `active` rather than stamped at the
six places the marching order changes, and saved as the world save's
`party.bench`; a save without the key loads with no clocks, and everyone on
the bench starts counting at the first frame after the load.

**§2.4b — the bench joins the fire and the web.** `PartyOpinion.camp_moment`
takes a `bench` flag: at an inn or the lodge (`world.gd`'s `_rest`, which both
use) the benched are under the same roof and can be the pair; on the open road
the fire is still the marching party's alone. The moment says which of the
pair is benched (`benched`). `scenes/party/relations_web.gd` draws the living
bench in a column down the web's right edge — smaller faces, their lines faint
and unbadged until a face or line is hovered, so the marching four's picture
stays the picture — and a restless merc wears an amber ring and a mark, their
tooltip saying how many days and what it means. A column, not a row under the
ring: the card shares its height with the marching list, and a first try with
a row squeezed that list.

**§2.6 — camp relationship lines.** The fire had eight lines (three warmings,
three quarrels, two courtships). They are now picked by the pair's
temperaments, from three layers (`PartyOpinion.lines_for`): `PAIR_LINES` for
the twelve pairings that mean something on their own (the four opposed pairs
and the eight same-temperament pairs), `TEMPER_LINES` for what each
temperament does at a fire with anyone (three of each kind), and the old
shared `LINES` for a side with no temperament. Any pairing draws from at least
six lines of its own for a warming or a quarrel. In a courtship the line's
asker is always the moment's `a`, which the answer card reads as the asker;
the moment turns the pair round when a line needs it. The stale header lines
in `core/party_opinion.gd` and `core/callings.gd` ("every member is
player-made") now say what is true: the founder is made, everyone after is
hired.

Tests: `tests/test_barks.gd` (every temperament has every trigger or falls
back; only partner lines name anyone; in a real fight a bonded partner names
the fallen, in their temperament's words, the same for the same seed),
`tests/test_bench.gd` (the clock, the warning once, the leaving, never the
founder, never below the minimum, the seeded morning, the fire under a roof
and not on the road, the save and an old save), and new cases in
`tests/test_party_opinion.gd` (every pairing's lines, the asker, the headers)
and `tests/test_party_screen.gd` (bench faces in the web, a restless face's
tooltip). `tests/test_combat.gd`'s bark check now reads the hero's own pool.
Screenshots: `docs/shots/voices-and-bench-{relations,hover,restless,leaves,fire}.png`
(`tests/shot_voices_bench.gd`).

### Still open

- A merc bonded to or in love with someone marching might reasonably be slower
  to grow restless; nothing reads relations in `core/bench.gd` yet. Add it if
  the leaving reads as heartless in play.
- The linear debug campaign (`SORCMERC_LINEAR_CAMPAIGN=1`) keeps no bench
  clock and never asks; `core/campaign_save.gd` does not carry `bench`.
- The restless state shows on the relations web and the card, not on the
  roster row itself; a small mark there would put it where the player swaps.
- Enemy barks are still per faction only; a named caster (`casters.json`) could
  have its own voice the same way.
- `RESTLESS_DAYS`, `LEAVE_AFTER_DAYS`, `LEAVE_PCT` and `MIN_ROSTER` are taste.
  If a sweep of long campaigns ever runs, measure how often a real bench trips
  the warning.

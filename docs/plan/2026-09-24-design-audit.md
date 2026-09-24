## A design audit against the bible — the side doors, and where each pillar stands (2026-09-24)

Seven read-only passes went over the code against the `sorcmerc-design-bible`
and `sorcmerc-balancing` skills: one per pillar, one on tone, one on balance
discipline, one on the economy, and one on scope, setting and art. The full
report, every finding with the code it stands on, is
[`docs/audit-game-design.md`](../audit-game-design.md). Nothing in the game
changed and no sweep was run; the arithmetic in it is from constants and says
so.

The headline is five **side doors**: places where the code lets a player skip
a cost the rest of the design is built on.
- The character sheet's "Long rest (restore all)" and HP buttons work
  anywhere in a campaign.
- A lost fight revives the whole roster for free.
- A lair is priced for the drained party at the door.
- The lodge garden grows potions of healing priced as rare (2,025 ◉).
- Gambling pays more than it takes from a +2 bonus up.

None of these moves a measured number, because no sweep ever walked through
them, which is also why the sweeps have not caught them.

Also found:
- Death has little weight.
- Spent slots can't be seen outside a fight.
- Band ids are shown as names.
- `core/world_threat.gd`'s wounds curve rests on a 2026-09-13 grid.
- Most AI-generated art has no PROVENANCE.md.
- The cult's slot-casting boss sits in no shipped lair.
- The Far Deeps have 4 bestiary entries at CR 10 and up.
- The skills lag the code in five places, listed in §7 of the report.

### Still open

- Everything in the report. Its "What to do, in order" list is the proposed
  order; each item is its own piece of work with its own entry here when it
  lands.
- Three findings are estimates that want a sweep before anyone acts on them:
  - rest's gold cost as a share of income;
  - road fights per long rest;
  - bench rotation as a second slot pool.
- The skills were deliberately not edited here. The owner's calls live in
  them, and the drift table in §7 is the list to apply.

## Names and voice — one register for the whole game (2026-09-24)

The design audit (`docs/audit-game-design.md` §6, "Tone") found the authored
fiction on-tone and the machine-assembled text off it: band ids shown as
names, a second, shouting voice in system messages and dice verdicts, "gold",
"gp" and "◉" side by side, "party", "company" and "hero" used for the same
people. The owner's calls §6.1–§6.5 settle each. This entry builds all five.

**§6.1 — bands have names.** A band's id ("goblin-raiders-3") is a key that
saves, hunt quests, callings, the respawn list and the mod API all look it up
by, and it never changes. Until now it was also what the player read: "Hunt
down the Goblin Raiders 3 band", "The band called Gnoll Pack 2 is asking after
you". `EnemyNames.band_name(band, world)` (`core/enemy_names.gd`) is now the one
place a band is named: "Ribsnap's goblins" for a people with a leader someone
has heard of (the leader drawn from the faction's own `NAMES`), "the Low Fen
gnolls" for one named after where it was last seen, always "the …" for a pack
of beasts or the dead, "the raiders out of The Vale Warren" for a lair's raid,
"Edda's wagons" for a caravan. It is seeded off the id and `world.origin.seed`,
so it needs no save field, reads the same after a reload and after a respawn,
and differs from one map to the next. Every generated name is a plural, so the
lines around it agree ("… are asking after you"). A pack's own name wins:
`world.json` `parties[].name` and a story's `spawn_party` `name` (the two
shipped stories already wrote one) are kept in the new `RoamingParty.sname`,
saved with the band and with its grave in `world.fallen` (an old save reads
`""` and gets the seeded name it would have had). Used by the quest board's
hunt postings, the respawn line, the refill line ("Word on the road: …", which
said the kind, now says who), callings' tells and done lines (a beaten band is
found in `world.fallen` so the done line names it the same), the march-to-meet
HUD, the chase, the night jump, the approach card's title and the map labels.
`WorldBands.label`, the kind label the refill line read, had no other reader
and is gone. The hunt chain labels read with a full name now: "Hunt down %s",
"Break %s", "See %s off the roads".

**§6.2 — the audit's rewrites, as written.** Party barks ("Keep them off the
wounded!", "Found the gap.", "That went in."), goblin and dragon barks ("Stick
it! Stick it!", "That one leaks!", "Blood. You will not do that twice.",
"Not… you…"); the chain labels "Break the gate at %s", "Clear %s out to the
last room", "Make sure %s stays empty"; the soldier's "deserters" calling
limited to bandit or soldier bands (a new optional `factions` list on a band
calling's target — with none on the map the calling waits, rather than make a
gnoll pack deserters; validated, and documented in `docs/modding.md`); "A
natural 20: up, at 1 HP."; the camp ambush "Nobody is watching the dark. They
are in the camp before anyone can draw."; achievements Fifty Dropped Blades,
Lamp Oil and a Spark, Sent Back Five Times, Bonesetter, and the renown ones to
match the ladder (ids unchanged, so nothing re-locks); the ladder's top two
titles "Asked For by Name" and "Sung Wrong in Taverns" (only the index is
saved); Dresden → Dresk, the second Kael → Rusk, Keyleth → Sariel; the
creator's "real 5.5e builds" and the tip's "the engine telling you" rewritten;
"(hard)" out of a campaign title and into the node card's kind line
("Combat, hard."), where every easy or hard node now says so. The title
screen's "Random battle (debug)" shows only under `SORCMERC_DEBUG=1`
(documented in `CLAUDE.md` and `README.md`); the tutorial's own "Quick fight"
door stays.

**§6.3 — ◉ beside every number.** "+%d gold.", "%d gold lighter", "The toll is
%d gold", "%d gp" and the achievement descriptions now carry ◉; "coin" and
"gold" stay in prose ("Not enough gold."). The combat log's number tint knows ◉.

**§6.4 — company in the fiction.** Narration says "the company" (travel and
approach outcomes, site and campaign lines, the camp and rest lines, the
combat log's breakout and surrender, the defeat and pit lines); "party" stays
where a line states a rule ("rolls initiative at disadvantage", "not tired
enough for another long rest", "+1 for a party that pulls together") or names
a screen (the Party page). "Hero" became "merc" where it read as fiction
(achievements, the blessing, the co-op lobby, placement hints, trait texts).

**§6.5 — one register.** The dice verdicts say "A natural 20.", "Made it.",
"A natural 1.", "Missed." — the words the trait moment already used; the gold
of a natural 20 is the colour's job. System lines on the map lost their
contractions and exclamation marks ("They will not budge on price again
today.", "cannot close the gap"), as did a verb's log line ("Vera — Action
Surge."), the End-turn confirm and the ambush option's "THEY take the first
round". The combat popup's HIT/MISS/CRIT stamps keep
their capitals as a board readout; only CRIT's "!" went.

Tests: `tests/test_band_names.gd` (new) holds the name to its seed, the save,
the grave, a pack's own name, the raiders, the posting and the refill line;
`test_callings.gd` the deserters' factions and the validator;
`test_world_callings.gd` a done card that names a beaten band;
`test_game_flow.gd` the title screen with and without `SORCMERC_DEBUG`. Every
test that read a changed string was updated to the new one.

### Still open

- A told calling in an old save that already points a soldier at a gnoll band
  keeps it; only new and re-picked targets honour `factions`.
- Quest titles are written when the job is posted, so a save's open hunt
  postings keep their old "the Goblin Raiders 3 band" wording until turned in.
- "Party" in rule text and "hero" in the manual and tips were left alone on
  purpose; a pass over `core/manual.gd` for the same register is not done.
- The bark pools themselves (per temperament, the bonded partner's line) are
  the audit's §2.3 and are not this entry.

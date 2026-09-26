## Loose ends — rotation at a halt, the carried, a guest's ending, and the provenance gaps (2026-09-25)

Round three of the design audit (docs/audit-game-design.md, "The owner's
calls"): the owner answered "do all" to the open questions in the Still open
sections of this day's entries and of "Docs and provenance". This entry is the
ones that were loose ends rather than balance passes.

**Bench rotation costs more than XP.** The measured pass found the bench a
second pool when it is worked: a fresh trio swapped in before nearly every
road fight takes a level-6 company from 88.4% to 97.0% on the road
(`tests/sweep_road_day.gd` ROTATE, table in `core/party.gd`'s `swap`), and its
only price was the XP a benched hero does not earn. The owner judged that not
enough. A hero now comes into or goes out of the marching company only where
the company stops: a camp it made and still stands at, a settlement, or the
lodge. `core/bench.gd`'s `rotation_refusal(world, under_roof, guest)` is the
one rule; it returns "" or the line the greyed buttons say — "The company
changes who marches at a camp, a settlement or the lodge, not on the open road
between fights." The camp is new state on the world: a quiet night
(`core/world_camp.gd`) leaves `World.camp_spot` where the company slept, and
`World.tick` strikes it the moment the player walks more than `CAMP_RADIUS` off
it. It rides the world save as `"camp"`; a save without the key has no camp.
Swapping before every fight now means a camp before every fight, which is a
long rest behind the 24-hour gate. Marching ORDER stays live everywhere, as it
always did (a travel decision). The party screen splits its lock: recruiting
and dismissing are still the inn's (`roster_locked`), and Bench, To party and
a swap off the bench follow `rotation_note`, which `scenes/world/world.gd`
fills from the rule. The HUD's party screen at a camp opens the swap; the inn
opens both; the lodge page gets its own door, "Settle who marches", which
opens the swap and not the hiring. The rotation table in `core/party.gd` was
measured with no such gate and was not re-run: it is the case the gate exists
to close.

A co-op guest cannot get round it. The guest's map never opens the party
screen (`_open_party` refuses a spectator, as its HUD and keys already did),
the host's inbox takes nothing from the road but a guest's own level-up, and
the rule itself refuses a guest everywhere with its own line, so a door added
later cannot silently do nothing. `tests/test_bench.gd` holds the rule, the
camp's life (made, saved, walked off, not re-pitched by walking back) and the
guest; `tests/test_world_panels.gd` holds the screen: greyed on the road with
the refusal on the button and the hint, no slot click round it, live at a
camp with dismissing still locked, and no screen at all for a guest.

**The downed on a withdrawal.** "Anyone left lying there is lost" stays, with
one exception the owner chose from the entry's own Still open: a hero who
walks off the board carries a downed comrade from an adjacent hex with them
(`core/combat.gd`'s `_leave_field` and `_carried_by`). One body each, the
first in the combatants' own order when two lie beside the carrier, so both
co-op peers pick the same one. The carried hero is off the field the way the
carrier is (`withdrawn`, off the board) and **stable**: out cold at 0 HP and no
longer rolling, which is where the existing rules put a downed hero with no
turn to roll on, and `Adapter.write_back` brings anyone stable round at 1 HP
when the fight ends. It costs nothing beyond the carrier's action to leave; a
carrier cut down by the parting swing carries nobody; everyone downed and not
beside a leaver still dies with the withdrawal. The log says "Vera leaves the
field, carrying Pike." and the button's text says it can. No new fight state:
it is statuses and positions, both in `Coop.state_hash`.
`tests/test_withdraw.gd` holds both cases (carried alive and stable, home at 1
HP; the far one dead; a second body beside the same carrier left) and the
co-op half (the carry happens on the guest's side from the same intent, the
hashes agree, and `stable` on the carried is in the hash).

**A finished company ends on every screen.** The host's `_end_company`
autosaves with `party.finished` written, and that autosave already crosses the
wire as the guest's full map; the guest's `scenes/game/game.gd` rebuilt a road
from it that nobody was left on. It now shows the same closing screen from the
same record (`show_company_end`) and writes nothing: the barracks and the slot
are the host's. `tests/test_coop_finished.gd` runs both halves over stub
links: the host's ending sends a full save carrying the whole roll, and the
guest's front door shows the company-finished page from it, where an ordinary
full save still puts the map up.

**Confirmed as built, no code.** The victors' truce after a defeat stays. It
and the carry are recorded in the audit's "The owner's calls" as a dated
follow-up line.

**Docs and provenance.**
- `CLAUDE.md`: the bestiary has 342 entries, not 316.
- `scenes/world/party3d.gd` no longer names `human_light_idle.glb`, which was
  never generated. A species with no figure for a role wears its heavy troop
  (`ROLE_STAND_IN`), so a human, bandit or soldier band led by a light troop
  wears `human_heavy_idle.glb` instead of the pawn. `tests/test_party3d.gd`
  checks the three factions and that every model `MODELS` names is on disk;
  `assets/troops/PROVENANCE.md` says what happened and drops its note.
- SDXL licence lines: of the six `PROVENANCE.md` files that name SDXL, four
  already had one (`assets/generated`, `assets/art/items`, `assets/board`,
  `assets/world/ground`). The two story-portrait files
  (`content/ashen-road/portraits`, `content/vault-of-the-ember-crown/portraits`)
  now have a Licence section: CreativeML Open RAIL++-M for SDXL 1.0, after
  checking that all six PNGs name `sd_xl_base_1.0.safetensors` in their
  `prompt` chunk.
- `core/party_opinion.gd`'s header no longer says every companion is
  player-made: that was fixed already, in `eae313d` ("Camp lines picked by the
  pair's temperaments; fix stale headers"), and nothing here changed. The
  spike write-up it points at (`docs/spike-party-opinions.md`) still says it,
  as a dated spike does.
- Tone pass against the design bible on the ten new lair names
  (`core/world_homes.gd`: Cutthroat Hollow, The Tangle, The Scale Pits, The
  Tusk Camp, The Boneyard, The Quiet Chapel, The Roost, The Restless Hill, The
  Silent Foundry, The Green Hollow) and the Unmapped's blurb (`core/regions.gd`:
  "Past anywhere with a name. The maps stop here because the people drawing
  them did."). None breaks a bible rule: plain and concrete, no prophecy
  capitals, no joke that breaks the scene, no contraction or "!". Nothing was
  changed.

**Also in this branch.** Master did not compile under Godot 4.7.2:
`core/adapter.gd`'s off-hand verb held the key `"weapon"` twice, once for the
log's blade name (#245) and once for the bar's icon id (#241), and a duplicate
key is a parse error that takes every script preloading the adapter down with
it. The icon's id moved to its own `"weapon_id"`, which `Icons.skill_icon`
reads first (it still accepts `"weapon"`).

Screenshots: `docs/shots/loose-ends-refused.png` (the party screen on the
road, the swap refused and saying where to go), `docs/shots/loose-ends-camp.png`
(the same screen at a camp: the swap live, recruiting locked),
`docs/shots/loose-ends-lodge.png` (the lodge's new door). The carry and the
guest's ending are a rule and a screen already shot
(`docs/shots/choices-with-teeth-finished.png`); their proof is the test output.

### Still open

- **Owner-only, not in this container:** `music/title.wav`'s origin, and the
  generator scripts in the owner's `~/localgen/` and `~/kitbashforge/` (every
  Meshy prompt, most SDXL scene prompts). Both stay as "Docs and provenance"
  left them.
- **The rotation gate is not in a sweep.** `tests/sweep_road_day.gd` ROTATE
  swaps whenever it likes; a run that swaps only at camps would say what the
  bench is worth now. The expectation is the "swapped when spent" column, which
  was noise.
- **Walking back to a camp does not re-pitch it.** Once the company has walked
  off, the camp is struck even if it comes straight back; a second camp is a
  second long rest. Taste, and the simpler rule.
- **A settlement means an open visit.** Standing outside the gates with the
  counter closed is the road; the inn's and the lodge's doors are the way in.
  `World.near_settlement` could count instead if that reads wrong.
- **A human light troop** generated with the same Meshy chain would retire
  `ROLE_STAND_IN`.
- **Carrying is free.** The Still open note that proposed it priced it at the
  carrier's move; the step off the edge already spends the carrier's action,
  so nothing more is charged. If withdrawals with the fallen read too easy, the
  lever is a move cost or the carrier leaving at half speed.
- **A lair name mid-sentence keeps its capital "The"** ("the captive is out of
  The Quiet Chapel"). Not a bible rule; a lowercase-article pass over the lair
  lines would be typography.

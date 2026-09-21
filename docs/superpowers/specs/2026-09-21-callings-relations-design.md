# Callings, and the party's own opinions — a quest per hero, and the people beside them

Sub-project 5 of the 2026-09-20 content batch (objectives → landmarks → threat
clocks → the ladder → **callings and relations** → downtime → the lodge). Two
things, one branch, because they share a fireside: every companion in
sorcmerc is player-made, so the CRPG staple — the companion with a past that
comes calling — has to be systemic. A **calling** is a personal quest a hero's
*background* hands them: the acolyte's defiled shrine, the criminal's old debt
on the road, the sage's lost library under a lair, the soldier's deserters, the
noble's rival envoy. Sixteen templates, one per background, each aimed at
something the live world already holds — a landmark, a lair, a band, a town —
told at the campfire in the beat the opinion spike designed, answered by going
there and doing the thing, paid in a bond, a milestone and an heirloom. And
the fireside itself: `core/party_opinion.gd` has sat complete and unused since
its spike (`docs/spike-party-opinions.md`); this wires its seven call sites, so
the party's own opinions of each other move on the road, show on the party
page, warm or sour at camp, and are felt in the fight.

## 0. Scope

**In:** `core/callings.gd` (templates per background; `assign`, `progress`,
`complete`; targets chosen from the world; the telling; the rewards; save);
callings shown on the party page and the quest log, the target marked on the
map (a lead), the calling's own camp beat; relations wired at the spike's
seven sites (save, party page, road bonus and result, decay, the camp beat
with courtship, the three combat hooks with `saved`/`friendly_fire`/
`fought_beside`); the calling's completion moves the hero's relation with
whoever rolled or struck for it; pictures (one scene per calling template,
`event-calling-<background>`); achievements; tests; the robot.

**Out:** authored dialogue trees (a calling is a beat, a target and a
resolution line); a second calling per hero (one, then done — the sheet is
what it is); romance beyond the spike's consensual courtship (already
designed; shipped as designed); relations for the bench (active pairs only,
as the spike says); the spike's appendix-A4 ideas (positional vectors,
cleansing conditions) — a later pass.

**Untouched behaviour:** a party with no `relations` saved starts every pair
at its `baseline()`; a hero with no background id gets no calling; the road,
the camp and the fight play as today when no pair is past `WARM` or under
`COLD`.

## 1. Relations — the seven sites, as the spike listed them

| # | where | change |
|---|---|---|
| 1 | `core/world_save.gd`, `core/campaign_save.gd` | `"relations": PartyOpinion.to_dict(party)` / `from_dict` beside the party |
| 2 | `scenes/party/party.gd` | a **Relations** block: `PartyOpinion.describe(party, a, b)` per active pair ("Vera Kord and Pike Sallow — rivals (−44)"); the hero's calling line above it |
| 3 | `core/travel.gd` `check()` | `bonus += PartyOpinion.travel_bonus(party)`; the card's roll line shows the term (`"+1 (a party that pulls together)"` / `"−1 (a party at odds)"`) |
| 4 | `core/travel.gd` `check()` | `PartyOpinion.road_result(party, who["id"], ok, e["kind"])` after `_apply` |
| 5 | `scenes/world/world.gd` `_process` | `PartyOpinion.decay(party, dt)` beside `FactionOpinion.tick` |
| 6 | `scenes/world/world.gd` `_make_camp` (the safe night) and `_rest()` (the inn) | `PartyOpinion.camp_moment(party, rng)` → a *warming*/*quarrel* beat on the event card (`_camp_card`), or a *courtship* on the approach card with two rows (`accept`/`decline`, `Landmarks.options` shape) → `answer_courtship`; the bound-callback path, not `_on_event_ack` |
| 7 | `core/combat.gd` | `fought_beside(party, standing)` at Victory; `saved(party, saver, saved_id)` when a heal or First Aid brings someone up from 0; `friendly_fire(party, caster, victim)` when an ally is caught in a cone or area; `shoulder_bonus` on AC, `bicker_penalty` on to-hit, `rally` when a partner goes down — with the log lines the spike names; `main.gd` hands `party` to the Combat |

Numbers are the spike's (`RIVALS −40`, `COLD −15`, `WARM 20`, `BONDED 50`,
`COURTSHIP_MIN 60`, `SAVED 12`, `FOUGHT_BESIDE 1`, `FRIENDLY_FIRE 6`,
`ROAD_PASS 1`, `ROAD_FAIL 2`, `CAMP_WARMING/QUARREL 8`, `DRIFT_PER_DAY 1`,
`SHOULDER_AC 1`, `BICKER_TO_HIT 1`, `MOMENT_CHANCE_PCT 50`). Nothing in
`core/party_opinion.gd` changes except what a calling adds (§3).

## 2. Callings — the model

```gdscript
# core/callings.gd — static, like landmarks.gd; state lives on the party
# party.callings: Dictionary  # char_id -> {"id", "target_kind", "target_id", "state", "told_at"}
#   state: "" (none yet) | "told" (the beat has fired; the target is marked) | "done"
const TEMPLATES := {background_id: {...}}     # sixteen, §4
static func assign(party, world) -> Array             # heroes newly given a calling (once each; the target must exist); re-validates the rest
static func beat(party, world) -> Dictionary          # the next untold calling's telling, or {}: {"char_id", "cname", "id", "title", "text"}
static func check(party, world, event: Dictionary) -> Array   # events from the world screen; returns the callings to complete
static func complete(party, world, char_id, who) -> Dictionary  # the resolution: rewards applied; {"text", "xp", "item", "item_name", "bond_with"}
static func describe(party, char_id) -> String        # one line for the party page / quest log
static func to_dict(party) / from_dict(party, d)
```

`assign()` runs every frame over the active party and picks the template's
target from the live world for anyone without one: the nearest landmark of
the kind (`world.landmarks`, found or hidden — a hidden one is found by the
telling), the nearest live lair, a civilized settlement of a given kind, or
a monster band — each template says which (§4). No target on this map → no
calling yet; the next frame tries again. The same pass re-validates every
calling not yet done (§5): a target the world has lost is re-picked.

`beat()` is the telling: the next hero with a calling in state `""` (and a
target to point at) speaks at the fire — one paragraph of second person in
the template — and the target is **marked** (a landmark becomes found; a
lair becomes discovered; the ground it stands on is revealed, since every
layer that draws a mark gates on `is_explored`; a band or town is named in
the line). It fires from `_make_camp` and the inn before the opinion moment
(a calling outranks a warming: it happens once). A calling told at the inn
of the very town it names is done as the party leaves: `_rest()` asks
`check()` again after the fire.

`check()` is the world screen telling the module what just happened, in one
shape: `{"kind": "landmark_answered", "id": ...}`, `{"kind":
"lair_cleared", "id"}`, `{"kind": "band_beaten", "id"}`, `{"kind":
"visited", "id"}`, `{"kind": "audience", "id": faction}`. A told calling
whose target and kind match completes — unless its hero is dead.

`complete()` pays, the frame the thing is done (so the autosave the doing
makes carries it; only the card waits for the map to clear): `CALLING_XP`
(120) split; the heirloom — one **uncommon** magic item named by the
template (a real id from `data/magic-items.json`, chosen to fit: the
acolyte's *amulet of proof*, the soldier's *javelin of lightning*, the
sage's *pearl of power*, …), identified, into the stash; and the **bond** —
`PartyOpinion.adjust(party, hero, other, CALLING_BOND)` (+15) with the one
who did the thing (the roller of the landmark row; the party's leader at a
fight, a lair, a visit or an audience — the screen passes `who`) — or, when
that was the hero themself or nobody, with whoever stands closest to them:
the active companion whose score with the hero is highest, ties by marching
order (the acolyte is the party's best at Religion, so at the shrine the
hero is usually their own roller, and the bond is the reward that matters;
a hero marching alone gets none). So the calling leaves a friendship behind
it, not only an item. The line, on the event card, art `event-calling-<background>`.

## 3. What a calling adds to the fireside

`camp_moment()` stays the spike's. `world.gd`'s camp handler asks in order:
a calling's `beat()` (once per calling, ever) → a calling's resolution card
if one completed on the road since the last camp (queued by `check()`) →
the opinion moment. One card a night; the queue holds the rest.

The party page's Relations block gains a **Callings** line per active hero:
*"Ilsa Vane — the Drowned Shrine wants reconsecrating (told, marked on the
map)"* / *"— done: the Drowned Shrine is hers again"* / nothing while untold.
The quest log's Standing section (the ladder's) gains the same lines under a
**Callings** header.

## 4. The sixteen templates

`{title, target_kind, target: {…}, tell, done, item}`. Target kinds:
`landmark` (with `kind`), `lair` (any live; the nearest), `band` (a monster
band; the nearest of the *people* — bandit, goblinoid, orc, gnoll, kobold,
cultist, since the copy is about deserters and debt collectors — falling
back to any monster band; never a band raiding a town, which is gone or
dead before the party gets there), `settlement` (with `kind`, civilized),
`audience` (the ladder's, any faction). Completion is the matching
`check()` event.

| background | title | target | done by |
|---|---|---|---|
| acolyte | The defiled shrine | landmark shrine | answering any row at it |
| artisan | The master's mark | landmark wreck (a master's cart, wrecked) | answering it |
| charlatan | The old mark | settlement town (someone here was fleeced) | visiting it |
| criminal | An old debt | band (the debt collectors) | beating it |
| entertainer | A hall worth the song | audience | holding one |
| farmer | The burned steading | lair (what burned the farm) | clearing it |
| guard | The one that got away | band | beating it |
| guide | The road not yet walked | landmark tower | answering it |
| hermit | The stones that spoke | landmark stones | answering it |
| merchant | The lost consignment | landmark wreck | answering it |
| noble | The rival envoy | settlement city | visiting it |
| sage | The lost library | lair (the library is under it) | clearing it |
| sailor | The wreck of the *Kestrel* | landmark wreck | answering it |
| scribe | The unfinished chronicle | landmark ruins | answering it |
| soldier | The deserters | band | beating it |
| wayfarer | The hut at the end of the road | landmark hut | answering it |

Each carries a `tell` paragraph in second person addressed to the hero
("You were an acolyte at a shrine like the Drowned Shrine…" — the target's
name is `%s`), a `done` line, and an uncommon `item` id. The copy lives in
`core/callings.gd`; a pack may add or replace templates through
`content/<pack>/callings.json` (same shape, keyed by background), validated
at scan time like landmarks.

## 5. Numbers, and how they get checked

| constant | value | why |
|---|---|---|
| `CALLING_XP` | 120 | two landmarks; a personal milestone |
| `CALLING_BOND` | 15 | the spike's `COURTSHIP_ACCEPTED`: the biggest warming short of a rescue |
| targets | nearest of kind | a calling points down the road you are on |
| re-validation | every `assign()` pass | a target the world lost — a landmark spent before the telling, a band beaten by someone else or gone home, a lair the map dropped, a settlement gone — is re-picked the same way; a told calling's new target is marked; nothing fits → the entry stays with an empty target, untold and uncompletable until one appears (a looted lair is not lost: it respawns) |

Tests (`tests/test_callings.gd`): every background has a template whose item
exists and is uncommon and whose target kind is one of the five; `assign`
picks the nearest target of the kind and skips a hero with none; `beat`
tells one calling per call, marks the target (a hidden landmark found, a
lair discovered), never tells twice; `check` completes only the matching
kind+id; `complete` pays XP, stashes the item identified, adjusts the pair,
flips state; `describe` per state; `to_dict`/`from_dict` round-trip; a
pack template replaces the built-in. `tests/test_party_opinion.gd` (exists)
gains the site tests: travel bonus applied and shown; `road_result` moves the
roller's pairs; decay from the screen; the camp beat's three kinds through
the world screen (`tests/test_world_camp.gd`); courtship through the
approach card; the combat hooks (`tests/test_combat.gd`: shoulder AC,
bicker to-hit, rally status, `saved` on a heal from 0, `friendly_fire` on an
area). Save round trips in `test_world_save`/`test_campaign_save`. The party
page shows the Relations block and the Callings lines
(`tests/test_party_screen.gd`). The robot: camp beats answered (courtship:
decline unless `_me["care"]` is high), callings completed count.

## 6. Pictures

Sixteen scenes `assets/generated/event-calling-<background>.png`, SCENE
style, generated with the house tooling: each the target as the hero sees
it (a defiled shrine, a burned steading, deserters at a crossroads, an
envoy's carriage at a city gate, a library under stone…).

## 7. Files

| file | change |
|---|---|
| `core/callings.gd` | new |
| `core/party.gd` | `callings` dictionary |
| `core/party_opinion.gd` | `CALLING_BOND`; nothing else |
| `core/world_save.gd`, `core/campaign_save.gd` | `relations`, `callings` |
| `core/travel.gd` | sites 3, 4 |
| `core/combat.gd`, `scenes/main.gd` | site 7 |
| `scenes/world/world.gd` | decay; the camp/inn beats (calling → resolution → moment); courtship rows; `Callings.check` at landmark answered / lair cleared / band beaten / visit / audience; the marks |
| `scenes/party/party.gd` | Relations + Callings block |
| `core/mod/registry.gd`, `docs/modding.md` | `callings.json` |
| `core/achievements.gd` | `calling_first` (*A Past*), `callings_4` (*Four Pasts*); the pair ones — `bonded` (*Shoulder to Shoulder*), `lovers` (*Something in the Firelight*) — were on the list already, wired in `adjust` and `answer_courtship` |
| tests, `docs/expansion-plan.md`, the sixteen scenes | §5, §6 |

## 8. Decided here

- **One calling per hero, from the background, never rerolled.** The sheet
  is the only personality a made character has; the calling is what that
  sheet says about the past.
- **Told at the fire, done on the road.** The camp is the one place the
  party talks; the world is where things are done.
- **The bond is the reward that matters.** The item is a keepsake; the +15
  with the one who helped is what changes the next fight and the next camp.
- **Relations ship as the spike designed them** — all seven sites, the
  numbers measured then — with one new source (the calling's bond).

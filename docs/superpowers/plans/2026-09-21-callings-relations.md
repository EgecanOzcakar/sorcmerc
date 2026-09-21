# Callings and Relations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `core/party_opinion.gd` (complete since its spike, unused) at its seven call sites so the party's opinions of each other move on the road, show on the party page, warm/sour/court at the fire and are felt in the fight; and add **callings** — one personal quest per hero from their background, aimed at something the live world holds, told at the fire, done on the road, paid in a bond, XP and an heirloom.

**Architecture:** Relations: no new model — `core/party_opinion.gd` already has everything; the tasks are calls and one Relations block. Callings: `core/callings.gd` (static, like `landmarks.gd`), state on `party.callings`, sixteen templates with copy and an uncommon item each, targets chosen from the world, `beat()` told through the existing `_camp_card`, completion reported by the screen through one `check()` event shape, the resolution on the event card with a generated scene per background.

**Tech Stack:** Godot 4.7 / GDScript; headless `SceneTree` tests; ComfyUI for the sixteen scenes.

**Spec:** `docs/superpowers/specs/2026-09-21-callings-relations-design.md` (and the spike it ships: `docs/spike-party-opinions.md` §5–§9).

## Global Constraints

- Every godot invocation is `--headless`; screen tests with `SORCMERC_FAST=1 timeout 180`.
- `core/party_opinion.gd` changes only by adding `CALLING_BOND := 15.0`; every number in it is the spike's and stays.
- `core/callings.gd` preloads nothing that preloads `party.gd` (it may preload `party_opinion.gd`, `campaign.gd`, `regions.gd`, `rng.gd`; `world.gd` via `load()` if needed for classes).
- Constants verbatim: `CALLING_XP 120`, `CALLING_BOND 15.0`; states `""`, `"told"`, `"done"`; check event kinds `landmark_answered`, `lair_cleared`, `band_beaten`, `visited`, `audience`; target kinds `landmark` (+`kind`), `lair`, `band`, `settlement` (+`kind`), `audience`.
- The sixteen templates, verbatim from Task 4's table (title, target, item, copy).
- Art stems `event-calling-<background>` (the event card's `event-<id>` rule with id `calling-<background>`).
- Commit after every task, message in the repo's voice (a sentence, no prefixes), trailer `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`; new scripts' `.uid` sidecars tracked.
- Comment voice per file; new tests in `tests/test_world_lairs.gd`'s shape.

---

### Task 1: Relations on the road and in the save (sites 1, 3, 4, 5)

**Files:**
- Modify: `core/world_save.gd` (`_party_to` ~328 / `_party_from` ~337), `core/campaign_save.gd` (the party dict ~81 and its reader), `core/travel.gd` (`check()` ~283–320), `scenes/world/world.gd` (`_process`, beside `FactionOpinion.tick(world, dt)`), `scenes/world/event_card.gd` (the roll line)
- Test: `tests/test_party_opinion.gd`, `tests/test_world_save.gd`, `tests/test_campaign_save.gd`, `tests/test_travel.gd`

**Interfaces:**
- Consumes: `PartyOpinion.to_dict(party) -> Dictionary`, `from_dict(party, d)`, `travel_bonus(party) -> int`, `road_result(party, roller, ok, kind)`, `decay(party, dt)`, `score/adjust/set_score`.
- Produces: `"relations"` key in both party serialisers (missing → `{}`); `Travel.check()`'s `out["morale"]` (the bonus term, −1/0/+1, present only when non-zero) and `bonus` including it; the card's roll line shows `(a party that pulls together +1)` / `(a party at odds −1)`.

- [ ] **Step 1: Failing tests**

`tests/test_world_save.gd` (before the final `print(`): build a party (`Party.demo_roster()`), `PartyOpinion.set_score(p, "vera", "pike", 33.0)`, `WorldSave.to_dict(w, p)["party"]["relations"]` has the pair key with 33; `from_dict` → `PartyOpinion.score(party, "vera", "pike") == 33.0`; a party dict without `relations` loads with `party.relations.is_empty()`. The same shape in `tests/test_campaign_save.gd` with its own fixtures.

`tests/test_travel.gd` (before the final `print(`): with `_party()` and `_world()`, set every active pair to 40 (`PartyOpinion.set_score` for `PartyOpinion.active_pairs(p)`), force an event (`_force(p, w, "tracks")` exists), assert `int(e["morale"]) == 1` and `int(e["bonus"]) == <the roller's skill bonus + pace_bonus + 1>` (read `who["bonus"]` from the same roll: assert `e["bonus"] - Travel.pace_bonus(p) - c.skill_bonus(e["char_id"], e["skill"]) == 1` using `Campaign.new(p)`); set pairs to −30 → `morale == -1`; neutral → no `morale` key. Then `road_result`: after a passed `"good"` event, the roller's score with each other active member rose by `ROAD_PASS`; after a failed `"bad"` event (force `rough-going` with a fail — loop seeds until `not e["ok"]`), it fell by `ROAD_FAIL`.

`tests/test_party_opinion.gd`: a decay check through the screen is the world test's — here just assert `decay(p, 1440.0)` moves a pair by `DRIFT_PER_DAY` toward baseline (may exist already; skip if so).

- [ ] **Step 2: Run them to see them fail.**

- [ ] **Step 3: Implement**

`core/world_save.gd` `_party_to`: add `"relations": PartyOpinion.to_dict(party),` (preload `PartyOpinion`); `_party_from`: `PartyOpinion.from_dict(party, pd.get("relations", {}))`. Same in `core/campaign_save.gd`. Update each file's format comment.

`core/travel.gd` `check()`: `var morale: int = PartyOpinion.travel_bonus(party)`; `var bonus: int = int(who["bonus"]) + pace_bonus(party) + morale`; if `morale != 0`: `out["morale"] = morale`; after `_apply(e, ok, party, world, rng, out)`: `PartyOpinion.road_result(party, String(who["id"]), ok, String(e["kind"]))` (not on the spell-pass or no-check exits — nobody rolled). Comment: the party that pulls together rolls a point better, and the roller carries the result with them.

`scenes/world/event_card.gd`: where the roll line is composed (`nat`, `bonus`, `dc`), append ` (a party that pulls together +1)` / ` (a party at odds −1)` when `_num("morale")` is non-zero.

`scenes/world/world.gd` `_process`: `PartyOpinion.decay(party, dt)` right after `FactionOpinion.tick(world, dt)` (preload `PartyOpinion`).

- [ ] **Step 4: Run the four tests + `tests/test_event_card.gd`** → `0 failed`.

- [ ] **Step 5: Commit** — `git add core/world_save.gd core/campaign_save.gd core/travel.gd scenes/world/event_card.gd scenes/world/world.gd tests/...` — "The party's opinions ride the save, move on the road, and drift at the world's pace".

---

### Task 2: The party page (site 2) and the combat hooks (site 7)

**Files:**
- Modify: `scenes/party/party.gd` (after `_build_orders`: a Relations block), `core/combat.gd` (`effective_ac`, `resolve_attack`, `_apply_damage`, `perform`, `cast`, the Victory resolution), `scenes/main.gd:498` (already `cb.party = party` — verify), `scenes/world/world.gd:1480` (already `_combat.party = party` — verify)
- Test: `tests/test_party_screen.gd`, `tests/test_combat.gd`

**Interfaces:**
- Consumes: `PartyOpinion.describe(party, a, b)`, `active_pairs`, `shoulder_bonus(party, c, cb)`, `bicker_penalty`, `rally(party, fallen, cb)`, `RALLY_STATUS`, `saved`, `friendly_fire`, `fought_beside(party, standing)`.
- Produces: `Combat` applies the three hooks and the three sources when `party != null` (the linear campaign passes a party too); log lines `"%s and %s stand shoulder to shoulder."` (once per fight, first time the bonus applies), `"%s and %s get in each other's way."` (once per fight), `"%s rallies — %s is down."`, `"%s gets %s back on their feet."`, `"%s catches %s in it."`.

- [ ] **Step 1: Failing tests**

`tests/test_combat.gd` (read its fixtures for building a `Combat` with a party team — it has helpers; the sweep `tests/sweep_party_opinion.gd` shows a `_build(spec, theme, seed, chars)` pattern to copy if needed): with `cb.party = p` and `PartyOpinion.set_score(p, a, b, 60.0)` (bonded), place `a` and `b` adjacent → `cb.effective_ac(a) == base + 1`; move `b` two hexes away → base. Rivals (`-50`) adjacent → an attack by `a` has `atk_bonus` one lower (read `r["total"]` against a known roll via a seeded RNG, or assert `PartyOpinion.bicker_penalty(p, a, cb) == 1` and that `resolve_attack` passes `opts["atk_bonus"] == a.atk_bonus - 1` — expose nothing new; assert through the attack's `total` with `nat` known). Rally: `a` bonded with `b`; `_apply_damage(b, b.hp_current)` → `a.has(PartyOpinion.RALLY_STATUS)`; `a`'s next `resolve_attack` has `opts["advantage"]` (assert via the result's `rolls` size 2 if the result exposes it — read `resolve_attack`'s return shape) and the status is gone after. Sources: `b` down, `a` heals `b` via `perform(a, {kind: "heal_ally", ...})` (read the vocabulary shape for a heal in `core/ai.gd`'s or the class abilities' verbs) → `PartyOpinion.score(p, a, b)` rose by `SAVED`; an area cast by `a` that hits `b` → fell by `FRIENDLY_FIRE`; a Victory with both standing → each pair `+FOUGHT_BESIDE` (call whatever `combat.gd` runs at the end of a won fight — `resolve_outcome()` or the `outcome() == "Victory"` path in `Encounter`; read where kills/XP are tallied and hook there).

`tests/test_party_screen.gd`: the page shows a "Relations" caption and one line per active pair from `PartyOpinion.describe` (set one pair to −44 → a line containing "rivals (−44)" or the exact `describe` output).

- [ ] **Step 2: Run to see them fail.**

- [ ] **Step 3: Implement**

Port `tests/sweep_party_opinion.gd`'s `Measured` overrides INTO `core/combat.gd`'s own methods (no subclass): `effective_ac` adds `shoulder_bonus` when `party != null`; `resolve_attack` applies `bicker_penalty` via `opts["atk_bonus"]` (not on opportunity attacks, not when the caller already set `atk_bonus`) and turns `RALLY_STATUS` into `opts["advantage"]`, erasing the status after the swing; `_apply_damage` calls `rally` when a party member newly goes down; `perform` and `cast` call `saved` when a heal brings a downed member up; `cast` calls `friendly_fire` for each conscious ally caught in an area the caster's own spell hit (the sweep's `cast` override shows the `allies_up` diff — copy it); at Victory, `fought_beside(party, <ids of party members conscious at the end>)`. Log through the file's own `log(...)` with the lines above, guarded so each pair's shoulder/bicker line is said once per fight (a small `_said := {}`).

`scenes/party/party.gd`: after the orders block, a caption "Relations" and, per `PartyOpinion.active_pairs(party)`, a Dim Label with `PartyOpinion.describe(party, a, b)`; nothing when fewer than two active.

- [ ] **Step 4: Run `tests/test_combat.gd`, `tests/test_party_screen.gd`, `tests/test_fight_invariants.gd`, `tests/test_summons.gd`, `tests/sweep_party_opinion.gd` (it subclasses Combat — its overrides now double-apply; make `Measured` a pure counter by removing the hook calls it duplicates, or delete the sweep's overrides that Combat now does itself and keep its counters reading the results — say which)** → all `0 failed`.

- [ ] **Step 5: Commit** — "The party's opinions are felt: shoulder to shoulder, in each other's way, a rally when a friend goes down — and shown on the party page".

---

### Task 3: The fireside (site 6) — warming, quarrel, courtship

**Files:**
- Modify: `scenes/world/world.gd` (`_make_camp`'s safe night ~3040; `_rest()` at the inn ~2960; new `_fireside(rng, then)`, `_on_courtship_chosen`)
- Test: `tests/test_world_camp.gd` (exists), or new `tests/test_world_fireside.gd`

**Interfaces:**
- Consumes: `PartyOpinion.camp_moment(party, rng) -> {kind: warming|quarrel|courtship, a, b, a_name, b_name, text, options?}`, `answer_courtship(party, a, b, accepted) -> Dictionary` (returns the line), `_camp_card(id, title, kind, text, then)`, `ApproachCard` (`show_approach(rows, title)`, `chosen` signal, `caption/glyph/hint/art_stem`), `_on_event_ack`.
- Produces: `_fireside(rng: RNG, then: Callable) -> bool` — shows one fireside card if a moment fires (returns true) and calls `then` on ack; a courtship shows the approach card with two rows `{id: "accept", label: "Say yes", note: ..., skills: [], dc: 0, win: ..., lose: ""}` / `{id: "decline", label: "Let it lie", ...}` → `_on_courtship_chosen(id, a, b)` → `answer_courtship` → the line on `_camp_card("courtship", ...)`. Task 5 inserts the calling beats ahead of it.

- [ ] **Step 1: Failing screen test** — instantiate the world screen; give the party a kit (`party.stash_add(WorldCamp.CAMP_KIT_ITEM)`), `Visit.can_long_rest` true (set `party.last_long_rest_at = -99999.0`), make the night safe (Rope Trick: `party.safe_camp = true`), set two active members to 30 (warm → a warming/quarrel moment possible) and call `main._make_camp()`; loop seeds/attempts (the moment is `MOMENT_CHANCE_PCT`) by resetting rest state and re-camping up to 20 times until `main._event_card != null` with `_e["id"]` beginning `camp-fireside`; assert the text names both; ack; then set the pair to 70 and `status ""` and loop until an approach card with an `accept` row appears; choose `accept` → `PartyOpinion.status(party, a, b) == "lovers"` and a card says so; ack.

- [ ] **Step 2: Run to see it fail.**

- [ ] **Step 3: Implement** `_fireside`, called from `_make_camp`'s safe branch after `Visit.rest` (replace the direct `_camp_card("night", ...)` with: `if not _fireside(rng, _on_event_ack): _camp_card("night", ...)`) and from `_rest()` after the inn's rest (same, with a fresh `RNG.new(hash(...))` seeded off the clock and the settlement id). The courtship card: `ApproachCard` with `caption = "A T   T H E   F I R E"`, `glyph = "♥"`, `art_stem = "camp-night"` (reuse the night's art), `hint = "Choose"`, rows as above; `chosen.connect(_on_courtship_chosen.bind(a, b))`; in the handler close the approach card the way `_on_place_chosen` does, call `answer_courtship`, show its line via `_camp_card("courtship", "At the fire", "good"/"bad", line, _on_event_ack)`.

- [ ] **Step 4: Run the screen test + `tests/test_world_camp.gd`, `tests/test_world_camp_integration.gd`, `tests/test_world_visit_pages.gd`** → `0 failed`.

- [ ] **Step 5: Commit** — "At the fire: a warming, a quarrel, or a question asked and answered".

---

### Task 4: `core/callings.gd` — the sixteen templates, targets, telling, completion

**Files:**
- Create: `core/callings.gd`, `tests/test_callings.gd`
- Modify: `core/party.gd` (`var callings: Dictionary = {}`), `core/party_opinion.gd` (`const CALLING_BOND := 15.0`), `core/world_save.gd` + `core/campaign_save.gd` (`"callings": party.callings`)
- Test: `tests/test_callings.gd`, `tests/test_world_save.gd`

**Interfaces (produces):**

```gdscript
const CALLING_XP := 120
const TEMPLATES := {  # background -> template
	"acolyte":     {"title": "The defiled shrine", "target": {"kind": "landmark", "landmark": "shrine"}, "done_by": "landmark_answered",
		"item": "amulet-of-proof-against-detection-and-location",
		"tell": "You served at a shrine like %s once, before the road. Word at the fire is that this one has been used for something it was not raised for. You would know what to do about that.",
		"done": "%s is a shrine again. Whatever they did there is undone, and you did the undoing."},
	"artisan":     {"title": "The master's mark", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "gloves-of-swimming-and-climbing",
		"tell": "%s, they say, was a master's cart — the one whose mark is on your own tools. Whatever is left of the load is worth a look from someone who can read the work.",
		"done": "You found the master's mark on a broken chest at %s, and a set of tools you will not sell."},
	"charlatan":   {"title": "The old mark", "target": {"kind": "settlement", "settlement": "town"}, "done_by": "visited",
		"item": "hat-of-disguise",
		"tell": "Somebody in %s paid you once for something that was not what you said it was. You have been avoiding the place. It is time to walk in the front gate and see what that costs.",
		"done": "Nobody in %s remembered your face, or nobody said so. You bought the old mark a drink."},
	"criminal":    {"title": "An old debt", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "cloak-of-elvenkind",
		"tell": "The band called %s is asking after you by name, town to town. You know what you owe them and you know they will not take coin for it.",
		"done": "%s will not come asking again. The debt is paid in the only coin they took."},
	"entertainer": {"title": "A hall worth the song", "target": {"kind": "audience"}, "done_by": "audience",
		"item": "pipes-of-haunting",
		"tell": "You have played taverns and camps. You have never played a hall with a lord at the far end of it. The company is getting the kind of name that gets asked.",
		"done": "You played the hall. They will tell it wrong for years, and that is the point."},
	"farmer":      {"title": "The burned steading", "target": {"kind": "lair"}, "done_by": "lair_cleared",
		"item": "decanter-of-endless-water",
		"tell": "The thing that burned your family's steading came out of %s. You told nobody in this company. You did not have to.",
		"done": "%s is empty. It is not the steading back, but it is the thing that burned it gone."},
	"guard":       {"title": "The one that got away", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "shield-1",
		"tell": "Every guard has one they let past the gate. Yours is riding with %s now, and the company keeps crossing their road.",
		"done": "%s is finished, and the one that got away did not, this time."},
	"guide":       {"title": "The road not yet walked", "target": {"kind": "landmark", "landmark": "tower"}, "done_by": "landmark_answered",
		"item": "eyes-of-the-eagle",
		"tell": "There is one height in this country you have never stood on: %s. A guide who has not seen the whole of it is guessing about the rest.",
		"done": "From %s you saw the whole of it. You are not guessing any more."},
	"hermit":      {"title": "The stones that spoke", "target": {"kind": "landmark", "landmark": "stones"}, "done_by": "landmark_answered",
		"item": "ring-of-mind-shielding",
		"tell": "You went into the wild to hear something, and once, at a ring like %s, you did. You have not been back to ask what it meant.",
		"done": "%s said the rest of it. You are keeping that one."},
	"merchant":    {"title": "The lost consignment", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "bag-of-holding",
		"tell": "%s was carrying your consignment when it went over, the one that ended your trade. Nobody has been through it since.",
		"done": "The consignment at %s was mostly gone. What was left was worth the walk."},
	"noble":       {"title": "The rival envoy", "target": {"kind": "settlement", "settlement": "city"}, "done_by": "visited",
		"item": "cloak-of-protection",
		"tell": "A rival house's envoy is at %s, and the company's name has reached them. Your house's business is yours to conduct, sword or no sword.",
		"done": "The envoy at %s knows the company's name now, and whose company it is."},
	"sage":        {"title": "The lost library", "target": {"kind": "lair"}, "done_by": "lair_cleared",
		"item": "pearl-of-power",
		"tell": "The books you spent your youth looking for are under %s. Whatever lives in it now does not read.",
		"done": "The library under %s was mostly rot. Three books were not, and you carried them out yourself."},
	"sailor":      {"title": "The wreck of the Kestrel", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "cloak-of-the-manta-ray",
		"tell": "You have heard %s called by another name: the Kestrel, the one you got off in the dark and swore was lost with all hands. Somebody should go and see.",
		"done": "%s was the Kestrel. Nobody else got off. You put a stone on it."},
	"scribe":      {"title": "The unfinished chronicle", "target": {"kind": "landmark", "landmark": "ruins"}, "done_by": "landmark_answered",
		"item": "helm-of-comprehending-languages",
		"tell": "The chronicle you copied as an apprentice ended mid-sentence, at a place it called %s. The stones there might say how the sentence ends.",
		"done": "The stones at %s finished the sentence. You have written it down."},
	"soldier":     {"title": "The deserters", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "javelin-of-lightning",
		"tell": "%s are deserters from a company you served in. You know their captain. He knows what you do to deserters.",
		"done": "%s are accounted for. You did not enjoy it, and you did not pretend to."},
	"wayfarer":    {"title": "The hut at the end of the road", "target": {"kind": "landmark", "landmark": "hut"}, "done_by": "landmark_answered",
		"item": "boots-of-striding-and-springing",
		"tell": "Every road you have walked, someone told you it ended at a hut like %s, and someone lived there who knew the way on. You have never reached it.",
		"done": "%s was the end of the road, and someone did live there. They knew the way on. So do you, now."},
}

static func templates() -> Dictionary                     # built-in, with a pack's callings.json merged over it (Task 6)
static func assign(party, world, rng) -> Array            # heroes newly given a calling (char ids)
static func beat(party, world) -> Dictionary              # the next untold: {"char_id", "cname", "title", "text", "id"} or {}; flips to "told", marks the target
static func check(party, world, event: Dictionary) -> Array   # char ids whose told calling this event completes (state stays "told"; the screen calls complete())
static func complete(party, world, char_id: String, who := "") -> Dictionary   # {"text", "xp", "item", "item_name", "bond_with"}; state "done"
static func describe(party, char_id: String) -> String    # "" | "<title> — told, marked on the map" | "<title> — done"
static func target_name(party, world, char_id: String) -> String
static func to_dict(party) -> Dictionary
static func from_dict(party, d) -> void
```

`assign()`: for each active member with a `background_id` in `templates()` and no entry in `party.callings`, find the target: `landmark` → nearest `world.landmarks` of that kind (found or not); `lair` → nearest `not looted` lair; `band` → nearest non-player monster band (`WorldAI.is_monster`); `settlement` → nearest civilized settlement of that kind (`kind` matches), falling back to any civilized settlement of a larger kind; `audience` → no target needed (`target_id = ""`). Distances from the player's position. No target → skip (tried again next call). Writes `{"id": background, "target_kind", "target_id", "state": "", "told_at": -1.0}`.

`beat()`: the first active member whose calling is `""`; mark: a landmark → `found = true`; a lair → `discovered = true`; a band/settlement → nothing to mark. Returns the tell with `%s` = the target's `sname` (band: `id.capitalize()`; audience: no `%s`). Sets `state = "told"`, `told_at = world.clock.elapsed`.

`check()`: matches `done_by == event.kind` and (`target_kind == "audience"` or `target_id == event.id`).

`complete()`: `Campaign.new(party)._split_xp(CALLING_XP)`; `party.stash_add(item)` + `Campaign._note_rarity`; if `who != ""` and `who != char_id`: `PartyOpinion.adjust(party, char_id, who, PartyOpinion.CALLING_BOND)`, `bond_with = who`; `state = "done"`; `Ach.collect("callings", char_id)`; returns the `done` line formatted with the target name.

- [ ] **Step 1: Write `tests/test_callings.gd`** covering §5 of the spec: every template's item exists in `data/magic-items.json` and is uncommon; every `done_by` is one of the five kinds and matches its target kind; `assign` on a small world (a shrine landmark, a lair, a band, a town and a city, a player) gives the acolyte the shrine, the sage the nearest lair, the soldier the band, the noble the city, the charlatan the town, the entertainer an empty target, and skips a hero whose target kind is absent; `beat` tells one per call in active order, marks (hidden shrine → found; lair → discovered), never repeats; `check` completes only kind+id; `complete` pays XP, stashes identified, adjusts the pair by 15 when `who` given, flips to done, and refuses a second time; `describe` per state; `to_dict`/`from_dict` round-trip; `assign` is a no-op for a hero without a template. Use `Party.demo_roster()` and set `background_id` on members directly.

- [ ] **Step 2: Run to see it fail. Step 3: Implement. Step 4: Run + `tests/test_world_save.gd` (add the `callings` round-trip) + `tests/test_party.gd`.**

- [ ] **Step 5: Commit** — "Callings: sixteen pasts, one per background, each pointed at something the map holds".

---

### Task 5: Callings on the screen — the beat, the marks, the checks, the resolution, the lines

**Files:**
- Modify: `scenes/world/world.gd` (`_fireside` chain: calling beat → queued resolution → moment; `Callings.assign` on world start/load and each camp; `Callings.check` at: `_on_place_chosen` (after `Landmarks.resolve` — event `landmark_answered`, `who` = the row's roller `e.get("char_id", "")`), the lair-cleared path (where `WorldLairs.loot`/`mark_cleared` is called on a win — `lair_cleared`, `who` = the party's leader `party.active[0]`), `_launch_combat`'s Victory erase (`band_beaten`, `who` = leader), `_open_visit` (`visited`), `_audience_action` (`audience`); the quest log's Standing section gains a "Callings" header + `describe` lines), `scenes/party/party.gd` (a Callings line per active hero above Relations)
- Test: new `tests/test_world_callings.gd`

**Interfaces:**
- Consumes: Task 3's `_fireside(rng, then)`, Task 4's API.
- Produces: `_calling_queue: Array` of char ids completed on the road since the last card (persisted? no — resolution shows at once when the completion happens on the map, as an event card after the fight's spoils / the landmark's outcome: simplest — `_calling_done(char_id, who)` shows `_camp_card`-style event `{"id": "calling-<background>", "title": <title>, "kind": "good", "ok": true, "text": done line, "xp": 120, "item": id, "item_name": name, "thanks": ""}` immediately when the screen is free, else queued to the next `_fireside`).

- [ ] **Step 1: Failing screen test**: small map; set the party's first member `background_id = "acolyte"`; add a hidden shrine landmark 200 out; `Callings.assign` runs on the next frame (assert `party.callings` has the hero); camp (kit + safe) → the beat card (`_event_card._e["id"] == "calling-acolyte"`, text names the shrine), the shrine now `found`; ack; the party page / quest log line says "told, marked on the map"; walk to the shrine, `_open_place`, choose the first row → after the outcome ack, a resolution card `calling-acolyte` with the done line, XP chip, the amulet in the stash identified, the pair (hero, roller) `+15` if different; `describe` says done; a second camp tells nothing new.

- [ ] **Step 2–4: fail, implement, run** (+ `test_world_landmarks`, `test_world_raids`, `test_world_ladder`, `test_world_camp`, `test_world_visit_pages`, `test_party_screen`).

- [ ] **Step 5: Commit** — "A calling is told at the fire, marked on the map, done on the road, and paid with a bond".

---

### Task 6: Packs, achievements, the robot, the pictures, the record

**Files:**
- Modify: `core/mod/registry.gd` + `docs/modding.md` (`content/<pack>/callings.json`: `{background: template}`, validated: `item` exists, `target.kind` ∈ the five, `done_by` matches), `core/callings.gd` (`templates()` merges the active pack's), `core/achievements.gd` (`calling_first` *A Past* counter `callings` goal 1; `callings_4` *Four Pasts* goal 4; `bonded_pair` *Shoulder to Shoulder* counter `bonded` goal 1 — `PartyOpinion.adjust` records via `Ach.record("bonded", 1)` when a pair first reaches BONDED (add that one line to `adjust`, guarded); `lovers` *More Than Friends* counter `lovers` goal 1 — `answer_courtship` accepted), `tests/test_achievements.gd`, `tests/test_mod_packs.gd`, `tests/drive_random.gd` (answer a courtship: decline unless `_me["care"] >= 70`; ack calling cards; invariant: a `done` calling's item is in the stash), `docs/expansion-plan.md` (the record), sixteen scenes
- Art: `~/localgen/gen_sorcmerc_scenes.py` group `event-calling` (SCENE), one prompt per background (the target as the hero sees it), `SORCMERC_GEN=/home/egeo/sorcmerc/assets/generated`, `--import`, `.import` sidecars; look at each; one retry each at most.

- [ ] Steps: tests first for the pack merge and the four entries; implement; the robot; generate; the record ("## Callings, and the party's own opinions — … (2026-09-21)" after the ladder record; Still open: a second calling; relations for the bench; the A4 ideas); full suite green; commit — "Sixteen pasts painted, a pack's own callings, four deeds on the list, and the record".

# Landmarks — places on the map that are not a fight

Sub-project 2 of the 2026-09-20 content batch (objectives → **landmarks** →
threat clocks and reclaiming → faction ladder and renown → callings with
party relations → downtime → the lodge). Today the map has three kinds of
thing on it: towns, lairs, and bands, and every one of them ends in a menu or
a fight. This adds a fourth: **landmarks** — ruins, a shrine, standing stones,
a hermit's hut, a wreck, a watchtower — each a place you walk up to and answer
a question with a skill the game barely uses today. Two checks per kind, one
visit each, rewards that are not fights: a blessing, a cache, a lead, a safe
camp, a quicker road, a piece of the map. The point is that a sage and a
fighter see different doors on the same map, at no new-content cost.

## 0. Scope

**In:** a `Landmark` on the world model, saved and loaded; six kinds with two
skill-gated choices each; placement by the three built-in builders and by a
pack's `world.json`; discovery (four kinds are visible once the fog is
explored, two are hidden and found the way lairs are); a marker on the map
and the minimap; a landmark card that reuses the approach card; the reward
doors (three exist, two are new); milestone XP for the deed; an inn lead can
point at a hidden landmark; region tiers scale the DC and the cache; tests.

**Out:** trainers (a hermit who teaches a feat — that is *downtime*, B2, where
it costs days and gold); anything that regenerates or can be farmed (a
landmark is answered once); a drawn interior; fights from landmarks (a
battlefield that wakes its dead belongs with threat clocks, C1); story
predicates beyond `near`; Performance at inns (downtime).

**Untouched behaviour:** a map with no landmarks — an old save, a pack that
declares none — plays exactly as today. `scaler.gd` does not change.

## 1. The model

```gdscript
# core/world.gd
class Landmark extends RefCounted:
	var id: String
	var kind: String        # one of Landmarks.KINDS
	var sname: String       # "the Broken Chapel"
	var position: Vector2
	var found := false      # drawn on the map? visible kinds flip this on explore, hidden ones on a Survival check or a lead
	var spent := false      # answered — a landmark is one visit
```

`world.landmarks: Array[Landmark]`; `world.add_landmark(l)`. `WorldSave`
writes them under a `"landmarks"` key and an old save without one loads with
none (the same rule lairs and terrain already follow).

`core/landmarks.gd` (new, static, like `world_lairs.gd`) owns the kinds, the
cards, the checks and the rewards. It preloads nothing that preloads
`world.gd`.

## 2. The six kinds

Each kind has two choices and *Leave*. A choice is `{id, label, skills, dc,
note, win, lose}` in exactly `Approach.WAYS`' shape, so `Approach._roller()`
picks the best roller and `Approach.needs()` prices it on the card. DCs are
the base at ring 0 and rise by 1 per region ring (`Regions.at(world,
pos).index`), the way the whole map gets harder outward.

| kind | visible? | choice A | choice B |
|---|---|---|---|
| **ruins** | yes | *Read the stones* — History or Investigation, DC 13. Win: a **lead** (the nearest unfound lair or hidden landmark is marked). Lose: an hour lost. | *Dig in the rubble* — Athletics or Investigation, DC 14. Win: a **cache**. Lose: a snare — the digger takes the road's HP toll (never dropped). |
| **shrine** | yes | *Kneel* — Religion, DC 12. Win: a **blessing**. Lose: nothing. | *Leave an offering* — no roll, costs 25 ◉ × (ring + 1); offered only when the purse covers it (parley's rule). The blessing, and +2 opinion with the nearest settlement's faction (they keep this shrine). |
| **standing stones** | yes | *Read the marks* — Arcana, DC 14. Win: the next fight starts **scouted** (`party.scouted_next`). Lose: nothing. | *Sleep in the ring* — Nature, DC 13. Win: the **road is quicker** (`Travel.TIME_SAVED` refunded off the clock). Lose: an hour lost. |
| **hermit's hut** | hidden | *Knock* — Persuasion or Performance, DC 13. Win: a **free lead** and the hermit identifies one unidentified item in the pack. Lose: the door stays shut (an hour lost). | *Ask about the road* — Insight, DC 12. Win: a **safe camp** tonight (`party.safe_camp`, Rope Trick's door). Lose: nothing. |
| **wreck** | yes | *Search it* — Investigation, DC 14. Win: a **cache**. Lose: a snare (HP toll). | *Salvage* — Athletics, DC 13. Win: a **Camp Kit** in the pack. Lose: an hour lost. |
| **watchtower** | hidden | *Climb* — Athletics, DC 12. Win: the **map opens** — `world.reveal()` at the tower and at eight points a vision radius out. Lose: an hour lost. | *Keep watch* — Perception, DC 13. Win: every band within two vision radii is **marked** (drawn as if explored) until the next day. Lose: nothing. |

Every win also pays the deed (§4). *Leave* costs nothing and does not spend
the landmark. A win or a loss on either choice spends it: one visit, one
answer — that is the anti-grind rule, and it is why there are two choices and
not five.

**A third row, gated by who you are.** Each kind carries one more choice that
appears only when a party member *is* the right kind of person — an acolyte
or cleric at the shrine, a sage in the ruins, a druid or an elf at the
stones, a hermit or ranger at the hut, a merchant or sailor at the wreck, a
soldier at the tower. They answer it in their own name, without a roll, and
it opens a door one of the two rolled rows already opens: flavour, not
power. The roller for the rolled rows stays the party's best at the skill
(`Approach._roller`), which is the rule the road already uses.

## 3. Placement and discovery

- **Built-in maps:** the three builders in `world.gd` (small, large,
  procedural) place `LANDMARKS_PER_LAIR` (1.5) landmarks per lair, kinds drawn
  round-robin from `Landmarks.KINDS` off the map seed, at least
  `LANDMARK_GAP` (120) from any settlement, lair or other landmark, not on
  water. Names from a per-kind list (`the Broken Chapel`, `the Nine Sisters`,
  `Old Marrow's hut`…) picked off the id hash, the way lair names are.
- **Packs:** `world.json` gains `"landmarks": [{"id", "kind", "position",
  "name"}]`; `core/mod/registry.gd` validates `kind ∈ KINDS` at scan time
  with the same error shape settlements and lairs get. The example world gets
  two so the format is exercised.
- **Visible kinds** (ruins, shrine, stones, wreck) become `found` the first
  time `world.is_explored(position)` is true — a ruin is hard to miss.
- **Hidden kinds** (hut, watchtower) are found the way lairs are:
  `WorldLairs.search`'s Survival check when within `DISCOVER_RADIUS`, on
  their own button (`_place_btn` reads "Search the ground (Survival)" when
  one is near — the lair button is already two-state, so a second button
  was cleaner than a third state on it), or by an inn lead —
  `core/rumors.gd`'s offer pool gains hidden landmarks at half a lair's
  price, and `free_lead()` may hand one out.
- **Story:** `near` accepts a landmark id (`story.gd`'s `world_ids` map
  gains `"landmark"`). Nothing else in the story layer changes.

## 4. Rewards — the doors

| reward | door |
|---|---|
| **cache** | `party.add_gold(CACHE_GOLD × (ring + 1) ± 25 %)` and, one time in three, one item rolled off `Loot`'s common table; said on the card |
| **blessing** | **new:** `party.blessed := true`; `Party.to_combatants()` grants each hero `temp_hp = 2 × level` and clears the flag — the same shape as `scouted_next` |
| **lead** | `Rumors`' existing lead: the nearest unfound lair or hidden landmark gets `discovered`/`found` and a line |
| **scouted** | `party.scouted_next = true` (exists) |
| **safe camp** | `party.safe_camp = true` (exists) |
| **quicker road** | `world.clock.elapsed -= Travel.TIME_SAVED` (the good-day refund; `drive_random`'s clock invariant already allows it) |
| **map opens** | `world.reveal()` at the tower and around it (exists) |
| **marked bands** | **new:** `world.marked_until := clock + DAY`, `world.marked_at := tower position`; every band within two vision radii of the tower draws as explored until tomorrow. Not saved — it lapses with the day |
| **camp kit / identify** | `party.stash_add("camp-kit")`; the librarian's identification path (T13) without the fee |

**The deed pays:** `LANDMARK_XP` (40) × (ring + 1), split the way a fight's
XP is (`Campaign._split_xp`). This is the batch's milestone-XP rule again:
answering a place is worth a small fight. Achievements: `Ach.collect(
"landmarks", id)` and one badge, *Surveyor*, for every kind answered once.

**The HP toll on a snare** is `Travel._hp_toll`'s rule verbatim: a percentage
of max HP, never below 1 — nothing rolled between towns drops anybody.

## 5. The card and the map

- **Walking up:** `_check_lairs()` grows into `_check_places()`: the nearest
  found, unspent landmark within `DISCOVER_RADIUS` puts a button on the bar
  — *"Visit the Broken Chapel"* — beside the lair's. Pressing it pauses the
  clock and opens `ApproachCard.show_approach(Landmarks.options(l, party,
  world), l.sname)`, so the card looks and works exactly as the one the
  player already knows: a picture, a title, rows priced with who rolls and
  what they need. `chosen(id)` resolves through `Landmarks.resolve(l, id,
  party, world, rng)`, and the outcome shows on the event card as approach
  outcomes do — the check named, the roll named, the reward said.
- **Art:** one picture per kind in `assets/generated/landmark-<kind>.png` if
  the art pipeline can make them; without one the card draws its title band
  and rows, so art is a follow-up, not a gate. On the 3D map a
  landmark is drawn by `Landmarks3D` (a sibling of `Lairs3D`) from the lair
  kit's existing pieces where one fits (`ruins`, `cave` for the hut's hillside)
  and a small new piece for the shrine, the stones and the tower; the wreck
  reuses a settlement-kit cart. A kind without a model gets the marker ring
  and its label, like anything else the models don't cover.
- **Markers:** a found landmark draws on the map and minimap in
  `Icons.COL_ACCENT` (verdigris — neither a town nor a foe), muted once spent;
  the HUD's band label is unchanged.
- **Journal/log:** the world's own log line on resolve, and the spoils page
  is not involved — a landmark is not a fight.

## 6. Numbers, and how they get checked

- `LANDMARKS_PER_LAIR` 1.5 → the small map (≈6 lairs) gets ≈9, the large ≈18.
- Two checks a kind, DC 12–14 at ring 0, +1 per ring: at level 3 a specialist
  (+5 to +7) passes ~65–75 %, a non-specialist (+0 to +2) ~40–50 %. The card
  says *needs N+*, so the player sees it.
- `CACHE_GOLD` 60 — a cache in the heartland is a night at the inn and a
  potion; in the deeps it is four times that.
- `LANDMARK_XP` 40 — a third of a normal heartland fight.

Tests (`tests/test_landmarks.gd`): every kind has two choices whose skills
exist in `data/skills.json`; the options rows carry a roller and a `needs`
line when the party can roll them and are dropped when nobody can; each
reward's door is exercised (the blessing shows up as temp HP on the next
`to_combatants()`, the lead marks something, the road refund respects the
clock invariant, the map opens, `spent` flips and a second visit is
refused); the builders place the right count with the gap respected on 100
seeds; a pack landmark with an unknown kind is a scan-time error; a save
round-trips `landmarks`; an old save loads with none. `drive_random.gd`
learns the *Visit* button (one weighted roll, like the lair button) and its
frame invariants gain "a spent landmark never offers a card".

## 7. Files

| file | change |
|---|---|
| `core/world.gd` | `Landmark` class, `landmarks`, `add_landmark`, `marked_until`, builders place them |
| `core/landmarks.gd` | new: `KINDS`, `CARDS`, `NAMES`, `options()`, `resolve()`, `place()`, the reward doors |
| `core/world_save.gd` | `landmarks` in and out |
| `core/party.gd` | `blessed`; `to_combatants()` grants temp HP |
| `core/rumors.gd` | hidden landmarks in the offer pool and `free_lead` |
| `core/mod/registry.gd`, `core/mod/story.gd`, `docs/modding.md` | `landmarks` in `world.json`; `near` accepts one |
| `scenes/world/world.gd` | `_check_places()`, the *Visit* button, the card, the outcome, markers |
| `scenes/world/landmarks3d.gd` | new: the models |
| `scenes/world/minimap.gd` | the marker |
| `content/example-world/world.json` | two landmarks |
| `tests/test_landmarks.gd`, `tests/test_world_save.gd`, `tests/test_world_pack.gd`, `tests/drive_random.gd` | §6 |
| `docs/expansion-plan.md` | the shipped record |

## 8. Open, decided here unless overruled

- A landmark is answered once per map and never restocks. If the world later
  gets a "years pass" mechanic, that is where it would.
- The hermit does not teach. Training is downtime's, where it costs days.
- Hidden landmarks share the lair's Survival DC (13) and radius — the same
  roll, so there is one way to search the ground, not two — but get their own
  button (`_place_btn`, §3): the lair button is already two-state, and a third
  state on it would have been worse than a second button.
- The blessing is temp HP, not a to-hit bonus: it is visible on the sheet,
  costs nothing to explain, and cannot stack with itself.
- Landmarks do not spawn fights. A landmark that wakes something is a threat
  clock's job (C1), and a landmark that a story wants to be a set piece is M9's.

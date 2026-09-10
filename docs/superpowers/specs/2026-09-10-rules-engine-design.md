# D&D 5.5e Rules Engine in GDScript — Architecture (A0)

**Status:** approved design, pre-implementation. Input to **F2**.
**Reconciled against:** the F1 export as it actually landed — `data/*.json` + `data/SCHEMA.md`.
**Source of truth being ported:** `~/dnd-maintainer/src/lib/resolver/*`, `src/types/{grants,choices,resolved,sources}.ts`, `src/lib/sources/index.ts`.

---

## 0. Approach

The port keeps dnd-maintainer's shape exactly: **sources emit grants → a
collector expands choice-dependent grants into a flat bundle list → a handful of
independent passes fold those bundles into a resolved sheet → the sheet is
adapted into the flat `Combatant` the existing combat resolver already eats.**
Nothing about the engine is invented. The only genuinely new work is (a) rendering
TypeScript discriminated unions as validated Dictionaries, (b) a *mechanics* layer
giving features, spells and conditions the numbers dnd-maintainer never had, and
(c) a power estimator for the encounter scaler.

Three facts from the shipped export drive most of the decisions below:

1. **Features carry no mechanics.** A `feature` grant is `{id, name?, description?,
   usesPerRest?, usesCount?, saveDC?}`. `barbarian-rage` is a string. Combat cannot
   be driven off it directly, so sorcmerc owns a feature-effects table (§6).
2. **Spell mechanics are a best-effort regex parse.** `spells[].mechanics` exists
   but is `null` for 65 of 146 spells and is explicitly flagged non-authoritative
   by SCHEMA.md. It's a good starting draft, not a contract (§6, §9).
3. **Monsters are not characters.** T8 generates enemy rosters from statblocks, not
   class levels, and nothing in the export describes a monster. The runtime combat
   type must therefore exist independently of the resolver (§3).

---

## 1. Module layout

Everything new lives under `core/rules/`. `core/combatant.gd`, `core/combat.gd`,
`core/dice.gd`, `core/rng.gd`, `core/hex.gd` stay where they are.

```
core/
  rules/
    catalog.gd        load + index data/*.json, lazily, once
    grants.gd         grant type constants + the schema table + validator
    choice.gd         choice-key make/parse, decision shape checks
    bundles.gd        collect(build) -> bundles: the expansion passes
    resolved.gd       class ResolvedCharacter (typed fields, no Dictionary soup)
    resolve.gd        the orchestrator: bundles -> ResolvedCharacter
    pass_abilities.gd ability scores + ASI + ability-choice
    pass_profs.gd     saves, skills, armor/weapon/tool/language, expertise
    pass_defense.gd   hit points, AC, speed  (ports resolver/combat.ts)
    pass_spells.gd    spellcasting: DC, attack, slots, known/prepared
    pass_gear.gd      equipment resolution + attacks  (ports resolver/equipment.ts)
    pass_pools.gd     resource pools
    pass_pending.gd   unresolved / invalid choices -> pending list
    effects.gd        feature id / spell id / condition id -> combat mechanics
    power.gd          combat-power estimate for the T8 scaler
  character.gd        the persistable build + a cached resolved sheet
  adapter.gd          ResolvedCharacter -> Combatant (and back for HP/pools)
  leveling.gd         (T2) level-up: append level, drive pending choices
data/
  effects/features.json    sorcmerc-authored (§6)
  effects/spells.json      sorcmerc-authored overrides layered on spells[].mechanics
  effects/conditions.json  sorcmerc-authored numbers for conditions.json's 15 prose entries
  monsters.json            sorcmerc-authored (T8 owns it)
  third-caster-slots.json  the one table F1 could not export (SCHEMA gap #5)
```

Rough sizes, for planning: `bundles.gd` ~250 lines, `pass_gear.gd` ~200,
`pass_profs.gd` ~180, `resolve.gd` ~120, everything else under 120.

### 1.1 Typed grants without discriminated unions

A grant is a `Dictionary` with a `"type"` String key. **Keys stay camelCase,
exactly as exported** — `hitDie`, `alwaysPrepared`, `minClassLevel`,
`featureIdPrefix`, `spellList`, `poolId`, `dieSizeSteps`, `fromTools`. Do not
rename to snake_case: the export is verbatim TS, SCHEMA.md documents those names,
and a rename layer is a bug farm that buys nothing. GDScript naming conventions
apply to sorcmerc's own code, not to a foreign data format passing through it.

Grant type ids are **String constants**, not enums — enums cannot round-trip
through JSON and the catalog is JSON.

`core/rules/grants.gd` holds one table and one function:

```gdscript
# type -> {req: {key: TYPE_HINT}, opt: {key: TYPE_HINT}}
const SCHEMA := {
    "ability-bonus":  {"req": {"ability": TYPE_STRING, "bonus": TYPE_INT}},
    "hit-die":        {"req": {"die": TYPE_INT}},
    "spell":          {"req": {"spellId": TYPE_STRING, "alwaysPrepared": TYPE_BOOL},
                       "opt": {"minClassLevel": TYPE_INT, "ability": TYPE_STRING}},
    "resource-pool":  {"req": {"poolId": TYPE_STRING, "max": TYPE_DICTIONARY,
                               "regen": TYPE_NIL},                       # String or Dict
                       "opt": {"dieSizeSteps": TYPE_ARRAY}},
    ...  # one row per type — all 25 in SCHEMA.md's grant-vocabulary table
}

static func validate(g: Dictionary) -> String   # "" when valid, else the reason
static func validate_catalog() -> Array[String] # every grant in every data file
```

Safety, in three places and no more:

- **`tests/test_rules.gd` runs `validate_catalog()` once** over the whole loaded
  catalog and asserts it returns `[]`. This is the real guard — a bad grant is a
  data bug and data is fixed, so validating at load time in production buys
  nothing. `TYPE_NIL` in the table means "present, any type" (used for the two
  fields that are legitimately String-or-Dictionary). It also validates the
  sorcmerc-authored `data/effects/*.json`, where typos are actually likely.
- **Every pass's `match g["type"]` has a `_:` arm that `assert`s**, so an
  unhandled grant type is loud in a debug build and inert in a release one.
- **`ResolvedCharacter` is a typed class, not a Dictionary.** Dictionaries stop at
  the grant boundary; everything downstream of `resolve.gd` has named fields.

No wrapper class per grant type. 25 one-field-different classes wrapping data that
arrives as JSON is exactly the abstraction this codebase does not need.

### 1.2 Catalog

```gdscript
# core/rules/catalog.gd  — all static, lazy, no autoload (project.godot untouched)
static func class_src(id: String) -> Dictionary
static func subclass_src(id: String) -> Dictionary
static func subclasses_of(class_id: String) -> Array[String]
static func species_src(id: String) -> Dictionary
static func background_src(id: String) -> Dictionary
static func feat_src(id: String) -> Dictionary
static func fighting_style_src(id: String) -> Dictionary
static func weapon(id: String) -> Dictionary
static func armor(id: String) -> Dictionary
static func spell(id: String) -> Dictionary
static func spell_list(class_id: String, level: int) -> Array[String]
static func spell_slots(class_id: String, class_level: int) -> Array[int]
static func condition(id: String) -> Dictionary
static func skills() -> Dictionary          # skill_id -> {name, ability}
static func monster(id: String) -> Dictionary
static func all(file: String) -> Variant    # the raw parsed file
```

Each accessor lazily `JSON.parse_string(FileAccess.get_file_as_string(...))`s its
file on first touch and caches it in a `static var`. Per-file laziness matters:
`magic-items.json` is 236 KB and `classes.json` 114 KB, and the creator's species
step should not pay for either.

Arrays get indexed to `{id: record}` on first access — `classes.json`,
`species.json`, `feats.json`, `spells.json`, `weapons.json` etc. are all
top-level arrays, and every consumer wants id lookup. `skills.json` and
`conditions.json` are already id-keyed objects.

`spell_list(class_id, level)` builds a `class_id -> level -> [spell_id]` index from
`spells[].classes` on first call. Note SCHEMA gap #7: that field is *native class
lists only* — subclass expanded lists arrive as `spell` grants inside
`subclasses.json` and must not be folded into this index.

Unknown id returns `{}` and appends to a `static var warnings: Array[String]` that
the resolver drains into `ResolvedCharacter.warnings` — same warn-don't-throw
policy as `collectBundles`, so a data hole degrades the sheet instead of killing
the run.

---

## 2. The resolve pipeline

### 2.1 Input — the build

`core/character.gd` holds it. This is the only thing that gets saved.

```gdscript
class_name Character extends RefCounted

var id: String
var cname: String
var species_id: String
var background_id: String
var base_abilities: Dictionary          # {"str": 15, "dex": 14, ...}
var levels: Array[Dictionary] = []      # [{class_id: "rogue", hp_roll: 6}, ...] ordered
var choices: Dictionary = {}            # choice_key(String) -> decision(Dictionary)
var feats: Array[String] = []           # feats taken outside a feat-choice grant
var equipped: Array[String] = []        # weapon/armor ids currently worn or wielded
var inventory: Array[Dictionary] = []   # [{item_id, quantity}] — post-creation loot
var pools: Dictionary = {}              # pool_id -> current uses (campaign-persistent)
var hp_current: int = -1                # -1 = full; carried between nodes
var prepared: Array[String] = []        # prepared-caster picks, chosen at rest

var _sheet: ResolvedCharacter = null
var _dirty := true

func sheet() -> ResolvedCharacter:      # cached; every mutator sets _dirty
func level() -> int: return levels.size()
func class_level(cid: String) -> int
```

`choices` is a flat `{choice_key: decision}` map exactly as in TS.
**Choice keys are opaque strings produced by F1**, format
`category:origin:id:index` (`"skill-choice:class:fighter:0"`), and they are
already in the exported grants — never regenerate one. `choice.gd` provides
`make(category, origin, id, index)` and `parse(key) -> Dictionary` with the same
four-segment validation; parse failure is a warning, not a throw.

Decisions are Dictionaries with a `"type"` matching the choice category and the
same payload keys as `ChoiceDecision`: `abilities`, `skills`, `tools`,
`languages`, `savingThrows`, `allocation`, `subclassId`, `styles`, `weaponIds`,
`damageTypes`, `bundleId` + `slotPicks`, `lineageId`, `featId`, `optionId`,
`spellIds`.

### 2.2 Pass 1 — `bundles.collect(character) -> {bundles, warnings, expanded_feats}`

A bundle is `{source: {origin, id, level?, classId?}, grants: Array}`. Order is
load-bearing (`getClassLevel` counts class-origin bundles; several passes are
first-seen-wins), so the sub-passes run in **exactly** the source's order:

1. species: `species.traits`
2. one bundle per class level from `classes.levels[i]` (a flat grant array per
   level, index 0 = level 1), in `character.levels` order, tagged
   `{origin: "class", id, level: n}`
3. subclass features: `subclasses.levels[]` entries whose `classLevel <=
   class_level(id)`, for the decided subclass
4. fighting-style choices → `fighting-styles.json` grants for each chosen style
5. damage-choices → a synthesized `feature` grant `"%s-%s" % [featureIdPrefix, type]`
6. lineage-choices → the matching entry in `species.lineages[]`
7. background: `backgrounds.grants`
8. expand embedded `feat` grants (background origin feats) — snapshot length first
9. expand `character.feats`
10. expand decided `feat-choice` grants (after 9, so a chosen feat's sub-grants are visible)
11. item grants for `character.equipped` — **v1: no-op**, see §2.3 note
12. expand decided `feature-choice` grants (after all sources, so feat-origin ones are seen)
13. expand decided `spell-choice` grants → one `spell` grant per chosen id (after 12,
    so Magic Initiate's injected spell-choices resolve)
14. gate every grant by `minClassLevel` against its granting class's level

**Port the ordering comments verbatim.** Passes 8–13 are single-pass, not a
fixpoint; the source documents that this is only safe because no feature-choice
option nests a `feat`, `lineage-choice`, or `feature-choice`.
`tests/test_rules.gd` asserts that invariant over the exported catalog — if it
goes red, promote 12 to a loop before shipping the offending option.

### 2.3 Pass 2 — `resolve.resolve(character) -> ResolvedCharacter`

Order matters only where noted; everything else is independent.

| # | Pass | Reads | Notes |
|---|------|-------|-------|
| 1 | `pass_abilities` | bundles, choices | `ability-bonus`, `ability-choice`, `asi`; cap 20; over-allocated or out-of-pool ASI skipped with a warning |
| 2 | `pass_profs` | abilities, PB | proficiency, expertise, `ability-check-bonus` (half-PB); `skills.json` supplies skill→ability |
| 3 | `pass_defense.hp` | `hit-die`, hp rolls, CON | L1 = max die + CON; L2+ = roll or `die/2+1`, + CON; then `hp-bonus × level` |
| 4 | `pass_defense.speed` | `speed` grants | highest per mode; `walk-equivalent` in a second pass |
| 5 | `pass_gear.equipment` | `character.equipped` + `inventory` | resolves ids against `weapons.json` / `armor.json` |
| 6 | `pass_defense.ac` | armor from 5, DEX/CON/WIS, bardic die | max of all `armor-class` calculations + all `ac-bonus` + shield |
| 7 | `pass_gear.attacks` | equipped weapons, abilities, PB, weapon profs, fighting styles, monk level | |
| 8 | `pass_spells` | `spellcasting`, `spell`, `spell-choice` grants | DC/attack from the dominant ability; slots from `classes.spellSlots` |
| 9 | `pass_pools` | `resource-pool` grants | `fixed` / `class-level` / `level-steps` / `proficiency-bonus` / `class-level-plus`, plus `dieSizeSteps` |
| 10 | `pass_pending` | every choice-bearing grant vs `choices` | including the ASI ↔ feat-choice either-or suppression |

**Equipment is weapons + armor only in v1.** The export ships `weapons.json` (39)
and `armor.json` (13) but no gear, packs, or bundles (SCHEMA gap #2), and
`magic-items.json` has `structuredBonuses: null` on all 262 records (prose only).
So: `bundle-choice` grants resolve to *nothing* and are surfaced as a warning
rather than a pending choice; `equipment` grants for unknown ids become inert
inventory rows; magic items are inventory + flavor text with no mechanical effect.
T1's equipment step picks from `weapons.json`/`armor.json` directly. This is a
scope cut, not a bug — record it, and revisit when F1 adds the bundles dump.

Non-proficient body armor still sets `cannot_cast`, `disadvantage_from_armor` on
STR/DEX saves and skills, and disadvantage on all attacks. Port it; heavy armor on
a wizard is a build the creator can produce.

**Third-caster slots.** `classes.spellSlots` is `[]` for fighter and rogue
(SCHEMA gap #5). Eldritch Knight and Arcane Trickster get their casting as feature
grants with no table. `pass_spells` detects a `spellcasting` grant with a
subclass-origin source and no class slot table, and reads
`data/third-caster-slots.json` — one hardcoded 20-row table, written once in F2.

### 2.4 Output — `ResolvedCharacter`

```gdscript
class_name ResolvedCharacter extends RefCounted

# identity / scale
var level: int
var class_levels: Dictionary          # "rogue" -> 5
var subclasses: Dictionary            # "rogue" -> "thief"
var proficiency_bonus: int

# abilities
var abilities: Dictionary             # "str" -> {base, total, mod, bonuses:[{value, source}]}
func mod(a: String) -> int

# defense
var max_hp: int
var ac: int
var ac_breakdown: Array               # [{mode, base, source}] + [{bonus, source}]
var speeds: Dictionary                # "walk" -> ft; also fly/swim/climb/burrow
var initiative: int                   # DEX mod (+ features that add to it)
var resistances: Array[String]
var immunities: Array[String]

# checks
var saves: Dictionary                 # "str" -> int  (total bonus)
var save_prof: Dictionary             # "str" -> bool
var skills: Dictionary                # "stealth" -> int
var skill_prof: Dictionary            # "stealth" -> "none"|"prof"|"expert"
var passive_perception: int
var disadvantage_from_armor: bool

# offense
var attacks: Array[Dictionary]
#   {id, name, ability, to_hit, dice_count, dice_sides, dmg_bonus, notation,
#    damage_type, properties: [String], range: "melee"|"ranged",
#    normal_ft, long_ft, versatile_notation, mastery}
var spellcasting: Dictionary          # {} when the character casts nothing
#   {ability, save_dc, attack_bonus, slots: [9 ints], pact: {count, slotLevel} | {},
#    cantrips: [id], known: [{id, level}], always_prepared: [id],
#    prepared_count: int, spells_known: {level: count}, ability_overrides: {id: ability}}

# kit
var features: Dictionary              # feature_id -> {source, save_dc, uses, per_rest}
var pools: Array[Dictionary]          # {id, max, regen, die_size}
var weapon_masteries: Dictionary      # weapon_id -> mastery_id
var fighting_styles: Array[String]
var proficiencies: Dictionary         # {armor:[], weapon:[], tool:[], language:[]}
var equipment: Array[Dictionary]      # {item_id, def, kind, quantity, equipped, source}

# build state
var pending: Array[Dictionary]        # see §4
var warnings: Array[String]

func has_feature(id: String) -> bool  # O(1) — the queryable feature set
func pool_max(id: String) -> int
```

`features` is a Dictionary keyed by id specifically so `has_feature()` is the
one-liner every downstream consumer needs. The TS returns an array and every
caller does `.some(f => f.feature.id === x)`; that's the port's one deliberate
divergence.

**Attacks carry ints, not just notation.** `Dice.parse` in `core/dice.gd` rejects
a bare `"1"`, which is what the TS emits for a plain unarmed strike — so
`pass_gear` treats `dice_count`/`dice_sides`/`dmg_bonus` as the source of truth
and formats `notation` from them, with plain unarmed becoming `"1d1+%d"`. Crit
doubling in `Dice.roll` then works unchanged.

### 2.5 Feet, hexes, and the calibration knob

The resolver works in **feet**, like the rules and like the export. The adapter
converts. Two knobs in `core/adapter.gd`, both of which change the tuning of every
existing encounter:

```gdscript
const FT_PER_HEX := 6      # 30 ft -> 5 hexes  (matches Pike's current speed 5)
const RANGE_CAP := 8       # ranged weapons/spells clamped to this many hexes
```

Existing hand-tuned numbers do **not** convert cleanly: Vera is 30 ft but has
`speed 4`, and the shortbow is 80 ft (`weapons.json` `normalRange: 80`) but
`atk_range 6`. That's map tuning, not a formula. Converting honestly makes a real
shortbow cover the whole 9-hex room and changes the tactical shape of the fight.
The knobs exist so T8 can re-sweep; **`tests/test_combat.gd`'s 200-seed sweep must
be re-run and its win-rate expectations re-baselined the day the adapter lands.**

---

## 3. `Character` vs `Combatant` — decision

**Keep `Combatant`. `Character` owns the build and the sheet; `core/adapter.gd`
projects a sheet into a `Combatant` for a fight.** Not a replacement.

Why:

- **Monsters have no `Character`.** T8 generates enemy rosters from
  `data/monsters.json` statblocks — nothing in the F1 export describes a monster
  at all. If combat consumed `ResolvedCharacter`, every goblin would need a fake
  class build. `Combatant` is the one type both a level-12 paladin and a 7-HP
  goblin can be, and it's the type `combat.gd` and `ai.gd` already speak.
- **The diff stays at one file.** `combat.gd` (507 lines), `ai.gd` (158) and
  `scenes/main.gd` read ~30 flat fields off a combatant. Making combat read nested
  sheet structures rewrites all three. The adapter is one function.
- **Runtime state belongs to the fight, not the build.** `hp`, `statuses`,
  `death_s/f`, `pos`, `init_roll` are per-encounter. `ResolvedCharacter` is a pure
  function of the build and must stay immutable and cacheable.

Changes to `core/combatant.gd`:

```gdscript
# unchanged: id, cname, team, ac, max_hp, hp, init_mod, speed, pos,
#            atk_bonus, damage, ranged, atk_range, crit_range,
#            save_dc, dex_save, athletics, acro, stealth, passive_perception,
#            statuses, death_s, death_f, has_acted, init_roll

# added
var attacks: Array[Dictionary] = []    # from the sheet; [0] backs atk_bonus/damage
var saves: Dictionary = {}             # all six, replaces the lone dex_save
var features: Dictionary = {}          # feature_id -> true — the queryable set
var verbs: Array[Dictionary] = []      # resolved combat verbs (§6)
var pools: Dictionary = {}             # pool_id -> {cur, max, regen}
var spell_ids: Array[String] = []      # castable-now spells (prepared ∩ has-mechanics)
var slots: Array[int] = [0,0,0,0,0,0,0,0,0]
var econ: Dictionary = {}              # per-turn action economy (§7)
var sheet: ResolvedCharacter = null    # null for monsters

# removed once F3 lands (replaced by features/verbs/pools):
#   sneak_attack, nimble_escape, surprise_attack, second_wind,
#   action_surge, cunning_action, spells, slots1, slots2,
#   used_second_wind, used_action_surge
```

`dex_save` and `slots1/slots2` stay as **read-only aliases** through F2 so
`combat.gd` keeps compiling; F3 deletes the call sites and then the aliases.

```gdscript
# core/adapter.gd
static func to_combatant(ch: Character, team: String, pos: Vector2i) -> Combatant
static func from_monster(m: Dictionary, team: String, pos: Vector2i) -> Combatant
static func write_back(c: Combatant, ch: Character) -> void   # hp, pools, slots -> the build
```

`write_back` is what T7 calls when a fight ends: HP, spent slots and spent pool
uses persist to the campaign; statuses and position do not.

---

## 4. Level-up flow

Level-up is a **fixpoint loop over `pending`**, not a scripted wizard. A feat
choice reveals the feat's own sub-choices only after it is decided, so the UI
cannot know the step list up front.

```gdscript
# core/leveling.gd
static func add_level(ch: Character, class_id: String, hp_roll: int) -> void
static func pending(ch: Character) -> Array[Dictionary]   # ch.sheet().pending
static func decide(ch: Character, key: String, decision: Dictionary) -> void
static func can_finalize(ch: Character) -> bool           # pending.is_empty()
static func preview(ch: Character, class_id: String) -> Dictionary  # what L+1 grants
```

T2's loop: `add_level` → render `pending()` → `decide` → re-resolve → render again
→ until empty. `add_level` appends to `levels` and marks dirty; nothing else.
Everything a level grants — subclass at 3, ASI/feat at 4/8/12/16/19, a new skill or
expertise, new spells known, a new resource pool, a bigger die — is a grant that
either applies silently or surfaces as a pending entry.

A pending entry is:

```gdscript
{type: <choice category>, key: <choice key>, source: {origin, id, level},
 count: int, from: Array | null, ...category-specific fields}
```

`from == null` means "any legal value of this category" — the UI fills it from the
catalog (all 18 skills, all feats of a category, all six abilities).

Four cases that need explicit handling, all ported straight from the source:

- **Subclass at 3.** A `subclass` grant with an undecided key; options come from
  `catalog.subclasses_of(class_id)` (4 per class, always). Deciding it makes
  `bundles.collect` splice in every `subclasses.levels[]` entry at or below the
  current class level — including retroactive ones — on the next resolve.
- **ASI vs feat.** Two grants with the *same* origin/id/index and different
  categories. Satisfying either suppresses the other's pending entry. Port the
  suppression **and** the "both satisfied" warning. Note the export's `asi.points`
  is 3 for backgrounds and 2 for class ASI levels — don't hardcode 2.
- **Spells known.** A `spell-choice` grant with `count`, `spellList`, `spellLevel`;
  the UI offers `catalog.spell_list(list, level)` minus already-known. Prepared
  casters instead read `spellcasting.prepared_count` and pick from their whole list
  at rest time into `Character.prepared` — a T3 profile action, not level-up.
- **HP roll.** `add_level` takes it as a parameter. Pass `-1` for "average"
  (`die/2+1`), which is what the resolver already substitutes for `null`. A
  roguelite should probably default to average; the parameter stays so a mode can
  roll.

**Retroactivity is free and must stay free.** Because the sheet is a pure function
of the whole build, editing a level-1 choice at level 12 just re-resolves. Never
mutate the sheet in place at level-up.

---

## 5. Multiclassing — out for v1

Recommend **single-class only**, with the multiclass-shaped data model retained.

`Character.levels` is already `[{class_id, hp_roll}]` — an ordered per-level list,
not a `{class_id, level}` pair. `bundles.collect` already groups by class and tags
each bundle with its per-class level. `pass_pools` already keys pool maxima on a
named class's level. All of that is free; it's the source's shape and flattening it
would be work, not savings.

What v1 does **not** build:

- the multiclass spell-slot table (caster level = full + ½ half + ⅓ third)
- per-class hit-die HP (`pass_defense.hp` uses the first `hit-die` grant, the same
  TODO the source carries)
- PB from total level where a pool keys on class level (the source's known limitation)
- multiclass prerequisites (13 in both primaries)
- creator/level-up UI for a second class

The gate is one `assert` in `leveling.add_level` — `class_id` must match
`levels[0].class_id` — plus the creator never offering a second class. SCHEMA gap
#6 confirms the export makes the same assumption. Lifting it later means writing
the slot table and a per-class HP loop, roughly 80 lines in two files, touching no
interfaces.

---

## 6. Feature → combat verb wiring

**The gap:** a `feature` grant is an id and some prose. `barbarian-rage` has no
damage bonus in it. Combat cannot be driven off the export alone.

**The fix:** one sorcmerc-owned table, `data/effects/features.json`, keyed by
feature id, loaded by `core/rules/effects.gd`. It is *not* an F1 deliverable — F1
has nothing to export. It is authored here incrementally, and **a feature with no
entry is a flavor feature**: it shows on the character sheet and does nothing in
combat. That default is what makes 430 feature ids tractable — F2 authors the ~30
the shipping classes actually use in a fight; the rest degrade to text.

```jsonc
{
  "rogue-sneak-attack": {
    "kind": "passive_damage", "cost": "none", "trigger": "on_weapon_hit",
    "once_per": "turn", "requires": ["advantage_or_ally_adjacent", "not_disadvantage"],
    "dice": {"sides": 6, "count": {"by": "class_level", "class": "rogue", "formula": "ceil_half"}}
  },
  "barbarian-rage": {
    "kind": "self_buff", "cost": "bonus", "pool": "rage", "duration": "encounter",
    "status": "raging",
    "bonus_damage": {"by": "class_level", "class": "barbarian",
                     "steps": [{"min": 1, "value": 2}, {"min": 9, "value": 3}, {"min": 16, "value": 4}]},
    "resist": ["bludgeoning", "piercing", "slashing"]
  },
  "fighter-action-surge": { "kind": "grant_action", "cost": "free", "pool": "action-surge", "amount": 1 },
  "fighter-second-wind":  { "kind": "heal_self", "cost": "bonus", "pool": "second-wind",
                            "dice": {"count": 1, "sides": 10, "plus": {"by": "class_level", "class": "fighter"}} },
  "rogue-cunning-action": { "kind": "grant_verb", "cost": "bonus", "verbs": ["dash","disengage","hide"] },
  "fighter-extra-attack": { "kind": "attacks_per_action", "value": 2 }
}
```

The `kind` vocabulary is **closed**, and each kind maps to code that already exists
or is a handful of lines in `combat.gd`:

| kind | combat.gd effect |
|---|---|
| `passive_damage` | extra dice folded into `resolve_attack` on hit — generalizes today's `sneak_attack` / `surprise_attack` branches |
| `self_buff` / `ally_buff` | sets a status for a duration; statuses already exist |
| `heal_self` / `heal_ally` | calls the existing `heal()` |
| `grant_action` | `+1` to `econ.action` |
| `grant_verb` | adds `dash`/`disengage`/`hide` at the declared cost — generalizes `cunning_action` |
| `attacks_per_action` | sets `econ.attacks_per_action` |
| `attack_modifier` | adv/dis or a flat to-hit delta for the turn (Reckless Attack) |
| `damage_bonus` | flat or dice added to weapon damage while a status holds (Rage) |
| `save_effect` | forces a save; status/damage on fail (Battle Master maneuvers) |
| `reaction` | fires on a declared trigger (§7) |

The scaling vocabulary is also closed: `{"by": "class_level"|"pb"|"ability_mod",
...}` with an optional `"steps"` table or `"formula": "ceil_half"|"floor_half"`.
Both tables are resolved **once, at adapter time**, against the sheet — so `verbs`
on a `Combatant` are fully numeric and combat never re-reads the sheet mid-turn.

### Spells

`spells[].mechanics` from the export is the **draft**, not the contract: SCHEMA.md
states it is a regex parse of English prose, `null` for 65 of 146 spells, and
explicitly non-authoritative. Burning Hands parsed cleanly
(`3d6 fire / dex / 15 ft cone / halfOnSave`); Healing Word did not parse at all.

So `effects.gd` layers `data/effects/spells.json` **over** `spells[].mechanics`,
keyed by spell id, and a spell is combat-castable only if the merged result has a
`cost` and at least one of `damage` / `heal` / `conditions`. Concretely:

```jsonc
"healing-word": {
  "cost": "bonus", "shape": "single", "range_ft": 60,
  "heal": {"count": 2, "sides": 4, "plus": "ability_mod"},
  "upcast": {"per_level": {"count": 2, "sides": 4}}
}
```

`castingTime` in the export is a string (`"Action"`, `"Bonus Action"`,
`"Reaction"`, `"1 minute"`) — map it to `cost` with a small lookup, and treat
anything longer than a Reaction as non-combat. Everything else — `area.shape`
(`sphere|cube|cone|line|cylinder|emanation|radius`) → hex shape, `save`,
`halfOnSave`, `damage[]` — carries straight through. `upcast` must be authored:
the export gives only a `higherLevel` prose sentence.

**Author the ~25 combat spells the shipping classes get first.** A prepared spell
with no usable mechanics simply doesn't appear in combat.

### Conditions

`conditions.json` ships 15 conditions as name + prose, with `structured` present
only for exhaustion. `data/effects/conditions.json` supplies the numbers combat
needs — which are few, because most conditions are two flags:

```jsonc
"prone":      {"attacks_against": {"melee": "adv", "ranged": "dis"}, "stand_costs": "half_move"},
"restrained": {"attacks_against": "adv", "own_attacks": "dis", "speed": 0, "saves": {"dex": "dis"}},
"frightened": {"own_attacks": "dis", "cannot_approach_source": true}
```

The existing `statuses` Dictionary on `Combatant` is already the storage; this only
gives the ids meaning.

### The interface `combat.gd` gets

```gdscript
func available(actor) -> Array[Dictionary]
# [{id, label, cost, kind, targeting: "self"|"ally"|"enemy"|"hex"|"direction"|"none",
#   range_hexes, disabled_reason}]
func perform(actor, verb_id: String, target) -> Dictionary
```

`available()` filters `actor.verbs` by: economy slot free, pool has uses, a slot
available for a spell, a legal target in range. `scenes/main.gd` renders the
returned list instead of its current hardcoded per-hero button set, and `ai.gd`
scores the same list. **Nothing in combat.gd names a hero or a class again.**

---

## 7. Action economy (specified here, implemented by F3)

Per-turn state moves off `combat.gd`'s four loose vars into one Dictionary, held
**on the `Combatant`** (reactions are spent between your own turns, so this cannot
live only on the active turn) and reset in `begin_turn()`:

```gdscript
var econ := {
    "action": 1,
    "bonus": 1,
    "reaction": 1,
    "move_left": 0,               # hexes
    "attacks_left": 0,            # within the current Attack action
    "attacks_per_action": 1,      # from the attacks_per_action effect kind
    "used": {},                   # verb_id -> count, for once_per: "turn"
    "cast_bonus_spell": false,
    "free_object_interaction": 1,
}
```

Costs are declared in `data/effects/features.json` and `data/effects/spells.json`
as `"cost": "action"|"bonus"|"reaction"|"free"|"none"`. `combat.gd` spends via one
function:

```gdscript
func _spend(actor, cost: String) -> bool   # false = can't afford; the verb no-ops
```

Rules the design commits to:

- **Order-agnostic spending** within a turn (combat-design.md §2). No sequencing.
- **Attack action + Extra Attack:** taking the Attack action sets
  `attacks_left = attacks_per_action`; each swing decrements; the action is
  consumed only on the first swing.
- **Reactions stay auto-resolved, zero prompts** — the existing OA behaviour,
  generalized. A `reaction` effect declares
  `"trigger": "enemy_leaves_reach"|"hit_by_attack"|"ally_hit_nearby"` and fires
  automatically when `econ.reaction` is free. `statuses["reacted"]` is replaced by
  `econ.reaction`. Prompted reactions remain out of scope; the trigger vocabulary
  exists so adding one later is data plus a dispatch line.
- **Bonus-action spell rule:** casting a bonus-action spell forbids a leveled spell
  with your action that turn — one flag, `econ.cast_bonus_spell`.
- **Concentration:** one `statuses["concentrating"] = spell_id`, dropped on a new
  concentration cast and on a failed CON save after damage. In scope for F3: 
  `spells.json` marks 40-odd spells `concentration: true` and half the control
  spells are broken without it.

---

## 8. Power budget for the encounter scaler (T8)

`core/rules/power.gd` estimates against a **`Combatant`, not a `Character`** — it
has to score monsters too.

```gdscript
const REF_AC   := 14     # what a party member is assumed to be swinging at
const REF_ATK  := 5      # what a party member is assumed to be swung at by
const REF_SAVE := 2      # reference save bonus for save-based effects
const ROUNDS   := 4      # the fight length resources are amortized over

static func estimate(c) -> Dictionary
# -> {dpr: float, ehp: float, control: float, score: float}

static func team_score(combatants: Array) -> float     # Σ score
static func roster_budget(party: Array, tier: String) -> float
static func fits(roster: Array, budget: float) -> bool
```

**`dpr`** — for each attack: `p_hit(to_hit, REF_AC) × avg_damage`, ×
`attacks_per_action`, plus a crit term from `crit_range`. Plus each damaging verb
and spell amortized: `(uses × avg_damage × expected_targets) / ROUNDS`, with
save-based effects weighted by `1 - p_save(save_dc, REF_SAVE)`.

**`ehp`** — `max_hp × (baseline_hit_chance / p_hit(REF_ATK, ac))`, plus healing and
temp-HP verbs at face value, × 1.3 when the combatant resists
bludgeoning/piercing/slashing (Rage, and the common monster case).

**`control`** — a weighted count of verbs that deny enemy turns: hard control
(stun/paralyze/restrain) 3, soft (prone/frighten/slow) 1, movement/utility 0.5,
scaled by remaining uses / `ROUNDS`.

**`score`** — `sqrt(dpr × ehp) × (1.0 + 0.08 × control)`. Geometric mean because a
glass cannon and a damageless wall are both worth less than the balanced middle,
and avoiding both is the scaler's whole job.

**Roster sizing:**

```gdscript
const TIER := {"easy": 0.55, "normal": 0.85, "hard": 1.15}   # calibration knobs
```

T8 fills a roster until `team_score(enemies) >= roster_budget(party, tier)`, runs
the seed sweep, then edits `TIER` until autopilot win-rate lands at ~90 / 75 / 50%.
**These three numbers are placeholders and are expected to move.** The contract T8
depends on is `estimate()`'s four keys and their meanings, not the constants.

Also expose `estimate()` per character in the profile screen (T3) — one "power"
number is a good difficulty affordance, and putting it in front of the player keeps
the estimator honest.

---

## 9. The data schema contract — reconciled with the shipped export

`data/SCHEMA.md` is the authoritative reference; F2 reads it. What follows is what
F2 must *do* about it.

### What landed, and what F2 does with it

| File | Records | F2 consumer |
|---|---|---|
| `classes.json` | 12 | `bundles` (`levels[i]` = flat grant array, index 0 = L1), `pass_spells` (`spellSlots[i]`, `pactMagic`) |
| `subclasses.json` | 48 | `bundles` (`levels[].classLevel` gating) |
| `species.json` | 10 | `bundles` (`traits`, `lineages[]`) |
| `backgrounds.json` | 16 | `bundles` (`grants`) |
| `feats.json` | 74 | `bundles` feat expansion; `prerequisites` for the creator's filter |
| `fighting-styles.json` | 10 | `bundles` step 4 |
| `weapons.json` | 39 | `pass_gear.attacks`, weapon-mastery eligibility |
| `armor.json` | 13 | `pass_defense.ac` |
| `spells.json` | 146 | `pass_spells` + `effects.gd` (`mechanics` as a draft) |
| `conditions.json` | 15 | `effects.gd` (prose only; numbers authored locally) |
| `skills.json` | 18 | `pass_profs` (skill → ability) |
| `magic-items.json` | 262 | inventory + prose only; `structuredBonuses` is always `null` |

Two naming notes that will bite if missed: feat categories exported as
`origin | general | fighting-style | epic` (not the TS `fightingStyle`/`epicBoon`);
`species` uses `traits`, not `grants`.

### The gaps F2 must close locally

Ranked by what blocks work:

1. **Spell mechanics are a prose regex parse, 81/146 non-null.** Blocks combat
   casting. → `data/effects/spells.json` overrides, ~25 spells authored in F2 (§6).
2. **Feature mechanics don't exist at all.** Blocks every class verb. →
   `data/effects/features.json`, ~30 features authored in F2 (§6).
3. **No monster data anywhere.** Blocks T7/T8. → `data/monsters.json`, T8's to own;
   F2 seeds it with the four Sunken Shrine foes so the adapter has something to
   test against.
4. **Third-caster slot table absent** (SCHEMA gap #5): `classes.spellSlots` is `[]`
   for fighter/rogue. → `data/third-caster-slots.json`, one 20-row table.
5. **Starting-equipment bundles not exported** (gaps #1, #2): `bundle-choice`
   references `bundleIds` whose contents live in un-exported `bundles.ts`;
   `backgrounds.startingEquipment`/`startingGold` are `null`. → v1 resolves
   `bundle-choice` to a warning, and T1 picks gear directly from
   `weapons.json`/`armor.json` (§2.3). Revisit if F1 adds the dump — SCHEMA calls
   it small.
6. **No gear/packs/items file.** → `equipment` grants for ids not in
   weapons/armor become inert inventory rows.
7. **Feature and resource-pool prose not re-exported** (gap #4). Every UI surface
   would show `barbarian-primal-knowledge`. → **ask F1 for the one-line
   `features.json` + `resourcePools` dump**; it's their file and they've already
   scoped it as trivial. Until then the UI falls back to a
   `id.replace("-", " ").capitalize()` humanizer.
8. **Magic items are prose-only** (`structuredBonuses: null`, all 262). → out of
   mechanical scope for v1; loot is inventory and flavor.
9. **Conditions are prose-only** except exhaustion. → `data/effects/conditions.json`.

`data/effects/*.json` and `data/monsters.json` are validated by the same
`grants.validate_catalog()` run in `tests/test_rules.gd` — they're hand-authored,
so they're the files where typos are actually likely.

---

## 10. Build sequence (F2), independently testable

Each step ends with assertions in `tests/test_rules.gd` (same headless SceneTree
pattern as `tests/test_combat.gd`), run by
`godot --headless --path . -s tests/test_rules.gd`.

1. **`catalog.gd` + `grants.gd`.** Load every `data/*.json`; `validate_catalog()`
   returns `[]`; every type in `grants.SCHEMA` appears at least once in the catalog
   and every catalog type appears in `SCHEMA`. *Run this the hour F2 starts — it is
   the F1 acceptance gate and it will find the first schema drift.*
2. **`choice.gd`.** make/parse round-trip; every `key` in every exported grant parses.
3. **`bundles.gd`.** A fighter 1 build yields the expected bundle count and order; a
   subclass decision at 3 splices in retroactive features; the no-nested-expansion
   invariant holds across the catalog.
4. **`pass_abilities` + `pass_profs`.** Port the TS unit tests' numbers directly —
   `abilities.test.ts` and `proficiencies.test.ts` are 40 KB of ready-made fixtures.
5. **`pass_defense` + `pass_pools`.** HP at L1/L5/L20; barbarian and monk unarmored
   AC; rage/ki/sorcery-point maxima at each `level-steps` boundary.
6. **`resolved.gd` + `resolve.gd` + `pass_pending`.** End-to-end: rebuild Vera, Pike
   and Ilsa as level-3 characters and assert the sheet reproduces `encounter.gd`'s
   hand-authored AC / HP / to-hit / damage / slots **within ±1**. *This is the
   highest-value test in F2* — it validates the port against a known-good target,
   and a mismatch is either a port bug or a tuning decision that needs writing down.
7. **`pass_gear` + `pass_spells`.** Attacks for weapon / finesse / ranged / unarmed;
   slots for a wizard 1–20, warlock pact magic, and an Eldritch Knight against the
   local third-caster table.
8. **`adapter.gd`.** `to_combatant` produces a `Combatant` that the *unmodified*
   `combat.gd` runs a fight with; the 200-seed sweep still terminates on every seed.
   Win-rate is re-baselined here, not asserted equal.
9. **`effects.gd` + `power.gd`.** Sneak Attack / Second Wind / Action Surge as data
   reproduce today's hardcoded behaviour; `estimate()` ranks the three heroes in the
   intuitive order and scores a goblin an order of magnitude lower.

Deferrable past F2 without blocking anyone: multiclassing (§5), magic-item
mechanics, starting-equipment bundles, tool/language proficiencies (resolve and
store, no UI), `ability-check-bonus` half-proficiency features, weapon mastery
*effects* (resolve which masteries are known; implementing cleave/graze/vex is F3),
the other ~400 flavor features.

---

## 11. Risks and GDScript-specific hazards

**Dictionary soup.** Mitigated structurally: Dictionaries exist only for grants,
decisions and effect definitions — all of which arrive as JSON and have a
validator. `ResolvedCharacter` and `Combatant` are typed classes. Any new
long-lived Dictionary field on either is a review flag.

**Resolve cost at level 20.** ~40 bundles × ~8 grants ≈ 320 grants, each scanned by
~15 passes ≈ 5k iterations — low single-digit milliseconds. The hazard isn't the
cost, it's **calling it from `_process` or a UI redraw**. `Character.sheet()`
caches and `_dirty` invalidates; nothing else may call `resolve()` directly. If
profiling ever disagrees, the fix is to bucket grants by type once per `collect()`
instead of rescanning per pass — don't do it preemptively.

**No enums for grant types.** Handled by `SCHEMA` + `validate_catalog()` in the
test + `assert` in each `match` default (§1.1). The failure mode left open is a
typo'd type string in the hand-authored `data/effects/*.json` — which is exactly
why the validator covers those files too.

**JSON load size.** The export is 706 KB across 12 files, `magic-items.json` (236 KB)
and `classes.json` (114 KB) being the bulk. Per-file lazy loading means a
combat-only path never parses either. If parse time ever shows up, binary
`ResourceSaver` caching is the escape hatch; don't build it now.

**The re-tuning cliff.** Sheet-derived heroes will not exactly equal the
hand-authored ones, and feet→hexes is a genuine design change (§2.5). Budget a
tuning pass at the end of F2 and treat the 200-seed sweep's win-rate as a number to
*re-establish*, not a regression to defend.

**Warning fatigue.** The source warns rather than throws in ~20 places — correct at
runtime, useless if nobody reads them. `ResolvedCharacter.warnings` must be
surfaced: an assert in `tests/test_rules.gd` that a fully-decided preset build
resolves with **zero** warnings, and an amber line in the T3 profile screen.

**Export drift.** `data/*.json` is regenerated by
`cd ~/dnd-maintainer && npm run export:sorcmerc`. Step 1's schema test is the
tripwire; run it after every regeneration, and treat SCHEMA.md as the changelog.

### Existing structural debt that blocks this work

- **`combat.gd` preloads `encounter.gd`** and reads `Encounter.REACH_MELEE`,
  `Encounter.CONE_BURNING_HANDS`, `Encounter.region_at()`, `Encounter.board()`.
  That hard-wires the one hand-authored room into the turn resolver and blocks
  T7/T8's generated encounters. Fix during F2's adapter step: move the constants
  and `region_at` into the `board` Dictionary the resolver is already handed, and
  drop the preload. ~15 lines, three call sites.
- **`Dice.parse` asserts on non-`NdM` notation** (§2.4). Attacks must carry ints;
  never let a bare `"1"` reach it.
- **`scenes/main.gd` builds its action bar from per-hero fields**
  (`cunning_action`, `second_wind`, `action_surge`, `spells`, `slots1/2`). It must
  render `combat.available(actor)` instead (§6). Not F2's job — but F2 must not add
  more fields of that kind, which is why the aliases in §3 are marked temporary.

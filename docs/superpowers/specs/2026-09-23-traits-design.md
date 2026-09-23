# Traits — who a hero is, and what the road has done to them (#176)

A design for discussion, not yet a build. Issue #176 asks for "character traits,
these can be what they start with and what they receive after some event they
were affected" — Crusader Kings' traits, in a 5e company. This document says
what a trait *is* here, what it can touch (the place a fight stands in, the
element a blow carries, the people across the board), how a hero gets and loses
one, and — most of it — which existing hook each piece hangs on, because
nearly every seam this needs is already cut. Nothing here is built. §9 is the
order it would be built in, §10 the questions the owner should answer first.

## 0. What Crusader Kings does, and what of it survives the trip

CK3 gives every character a handful of traits, in families that behave
differently:

- **Personality** (Brave/Craven, Wrathful/Calm, Greedy/Generous …) — three at
  most, picked or born with, arranged in **opposed pairs**. Each is a mixed bag
  (Brave: +prowess, −stress-when-fleeing, but more likely to die in battle) and
  each changes **opinion**: two Brave characters like each other, Brave and
  Craven do not.
- **Congenital / education** — what you were born or raised into. Fixed.
- **Lifestyle and event traits** — *earned*: Scarred, Wounded, Blademaster,
  Hunter, Shy, Drunkard. Some are good, some bad, many are both, and several
  come with a **cure loop** (Wounded heals; a stress-coping trait can be shed).
- **Coping traits from stress** — an event pushes a character against their own
  personality (a Compassionate ruler executing someone), and the fallout is
  rolled *weighted by who they are*.

Four ideas travel well into sorcmerc. The rest are about dynasties and do not.

1. **A trait is mixed.** Almost none is a pure buff. That keeps them
   interesting and keeps them from being a second feat list.
2. **Opposed pairs drive opinion.** sorcmerc already has the opinion model
   (`core/party_opinion.gd`), and its `baseline()` already reads personality
   off the sheet — `TEMPER` from the background. Traits are the finer grain
   that `TEMPER` was a stand-in for (see its comment: "the only 'personality'
   a pair can have is what their sheets say").
3. **Events leave marks, and who you are weights which mark.** A hero downed
   by a fire giant comes back from it either *tempered* or *afraid of fire*.
   Which one is seeded off the event (the determinism idiom) and weighted by
   the hero's personality (Brave leans tempered).
4. **Some marks heal.** A debuff with a way out is a goal, not a punishment:
   *Haunted by the Bloodfang* goes away when the Bloodfang's lair is cleared,
   which is a calling in all but name.

## 1. Scope

**In:** the trait model and its data file; the save key; the starting pick at
character creation; the effect vocabulary (§3) and the hooks that read it
(§5); earning and losing traits from events (§6); opinion between traits (§7);
showing them (§8).

**Out:** traits for monsters (a bestiary entry already carries its own
defences and verbs); dynasty/inheritance anything; stress as a meter (§10, Q4);
authored event chains beyond one line of text per gain or loss; traits that
change *class* features (that is what feats and subclasses are for).

**Untouched behaviour:** a hero with no traits fights, travels and camps
exactly as today; a save written before this reads `traits` as `[]`; a fight
spec with no `where` (§4) fires no location trait.

## 2. The model

A trait is a row of data, like an effect or a calling template, not code:

```jsonc
// data/traits.json — content packs may add rows (data only, like everything under content/)
"marsh-bred": {
  "name": "Marsh-bred",
  "family": "origin",                 // personality | origin | mark | bane | wound
  "opposes": [],                      // personality pairs name each other
  "text": "Grew up where the ground is half water. Knows which of it holds.",
  "effects": [
    {"when": {"biome": ["marsh"]},       "gives": {"ac": 1}},
    {"when": {"biome": ["marsh"]},       "gives": {"skill": {"survival": 2}}},
    {"when": {"biome": ["downs"]},       "gives": {"skill": {"survival": -1}}}
  ]
}
```

On the hero it is a short list, because the person owns their traits — not the
party, unlike `party.callings`. A trait has to survive the barracks, a preset,
a co-op sync and a move between companies, and every one of those already goes
through `CharacterSave`:

```gdscript
# core/character.gd — beside feats / buffs
var traits: Array = []   # [{"id", "since" (world minutes), "why" (one line), "until" (optional, a wound)}]
```

`core/traits.gd` is static like `core/landmarks.gd` and owns the rules: which
traits a hero has, what they give in a given context, what an event grants,
what cures what, and `to_dict`/`from_dict`. It does not own when any of that is
asked (the world screen and the fight do) or the drawing.

**Families and their caps** (the caps are CK's, scaled to a party of four):

| family | how many | how you get one | leaves? |
|---|---|---|---|
| personality | 1 at creation, at most 2 | picked at creation; a second only from an event | no |
| origin | 1 | picked at creation, defaulted from the background | no |
| mark | any | earned (§6) | only a *fear* mark, by its cure |
| bane | up to 2 | earned: kills of one faction/type | no |
| wound | up to 2 | earned: downed badly | yes — rest, a healer, or time |

## 3. What a trait can give, and when

A closed vocabulary, deliberately small, each word read at exactly one hook
(§5). An open vocabulary is how `data/effects/*.json` grew thirty kinds; this
one should stay one screen long.

**`when`** — every key must hold; an empty `when` always holds.

| key | means | known at |
|---|---|---|
| `biome` | the fight's or the road's biome: `downs`, `woods`, `marsh` (`World.BIOMES`) | fight start / road check |
| `board` | the board theme (`Encounter.THEMES`: `frozen-cave`, `sunken-shrine`, `city-square` …) | fight start |
| `night` | `true`/`false` (`world.clock.is_night()`, already on the spec) | fight start / road check |
| `band` | the region band (`heartland`, `marches`, `frontier`, `deeps`) | fight start / road check |
| `site` | `road`, `lair`, `camp` (a night ambush), `town` | fight start / check |
| `vs_faction` / `vs_type` | the *target's* bestiary `faction` or `type` (`orc`, `undead`, `dragon` …) | per roll |
| `dtype_in` | the incoming damage type (`fire`, `cold`, `poison` …) | per damage |
| `dtype_out` | the damage type of the hero's own attack or spell | per roll |
| `bloodied` | the hero is under half HP | per roll |
| `alone` | no ally adjacent (the inverse of `shoulder_bonus`'s adjacency) | per roll |
| `first_round` | round 1 (the requirement `_requires_met` already knows) | per roll |

**`gives`**:

| key | reads as | lands in |
|---|---|---|
| `to_hit` | ± to attack rolls | `bonus_to_hit` status key, or the per-roll hook |
| `ac` | ± AC | `ac` status key, or `effective_ac` |
| `save` | ± to saves, optionally `{"ability": "wis"}` | `bonus_save`, or `_saving_throw` |
| `save_adv` | advantage on saves vs a damage type or condition (`{"vs": "frightened"}`) | `_saving_throw` |
| `damage` | ± flat damage on a hit | `bonus_damage` / the per-roll hook |
| `ward` | reduce incoming damage of `dtype_in` by N per hit (**new**; not 5e resistance — see below) | `_damage_after_defenses` |
| `initiative` | ± initiative | `init_mod` at fight start |
| `skill` | ± to one skill on the road (`survival`, `stealth`, `persuasion` …) | `Campaign.skill_bonus` |
| `watch` / `forage` / `travel` | ± to those overworld checks | their bonus sums (§5.3) |
| `gold` | ± % of a fight's purse | the spoils |

Two rules that keep this 5e:

- **One trait term per roll, capped at ±2 total** across every trait a hero
  has. Bounded accuracy is the reason a +1 matters in this game at all;
  `PartyOpinion`'s combat terms are ±1 for the same reason. A stack of four
  "+1 in the marsh at night vs undead" traits must not buy a +4.
- **Traits do not grant 5e resistance.** Halving a whole damage type is a
  species or a ring, not a scar. `ward` (a flat −2 or −3 per hit of that type)
  is the trait-sized version: it matters against a goblin's torch and barely
  against a dragon's breath, which is the right shape for "I've been burned
  before".

## 4. What a fight needs to know about where it is

Today a fight knows its `theme` and `night` and nothing else about place —
biome is collapsed into the board theme and the roster in
`scenes/world/world.gd` `encounter_spec()` (~1519–1574), the band only enters
as a power multiplier, and road-vs-lair-vs-camp is only visible at the call
site (`_launch_combat` ~1667, site rooms ~2553, the pit ~4194, the night jump
~1500/3389).

So the spec grows one key, stamped where the facts are known:

```gdscript
spec["where"] = {"biome": world.biome_at(pos), "band": Regions.band_of(...).id,
                 "site": "road" | "lair" | "camp", "night": world.clock.is_night()}
```

`Encounter.build` copies it onto the board, `Combat` exposes it as `cb.where`.
The linear campaign (`core/campaign.gd` `combat_spec`) and the demo fight pass
none, and no location trait fires there. That is the save-compat idiom applied
to a spec.

## 5. The hooks — every one of them already exists

### 5.1 At fight start: the static half, for free

Anything whose `when` can be decided before the first roll (biome, board,
night, band, site) is evaluated once in `Adapter.to_combatant` and written as a
status dict — the exact path road potions already take (`core/adapter.gd`
~129–134, `statuses["potion:<id>"]`). The engine already sums `ac`,
`bonus_to_hit`, `bonus_save` and `bonus_damage` out of any status dict
(`_buff_sum`, `core/combat.gd` ~540). So *Marsh-bred's +1 AC in the marsh* is
`statuses["trait:marsh-bred"] = {"ac": 1}` and needs **no combat.gd change at
all**. `to_combatant` needs the `where`; its callers (`scenes/main.gd` ~587,
`encounter.gd` ~423) have it or pass `{}`.

### 5.2 Per roll: the PartyOpinion precedent

Anything that depends on *who you are hitting* or *what is hitting you*
(`vs_faction`, `vs_type`, `dtype_in`, `dtype_out`, `bloodied`, `alone`) has to
be asked at the roll. `PartyOpinion` already shows the shape — a static helper
asked from four places in `core/combat.gd`:

| trait asks | beside | where |
|---|---|---|
| `Traits.attack_bonus(attacker, target, cb)` | `bicker_penalty` | `resolve_attack` ~2339 |
| `Traits.ac_bonus(c, attacker, cb)` | `shoulder_bonus` | `effective_ac` ~754 |
| `Traits.save_bonus(c, ability, source, cb)` | `_buff_sum("bonus_save")` | `_saving_throw` ~3139 |
| `Traits.ward(c, dtype)` | the resist/immune/vuln step | `_damage_after_defenses` ~2639 |

Foe faction and type are one lookup away — `Catalog.monster(target.src_id)`,
the way the barks already do it (combat.gd ~292). The log gets a once-per-fight
line through the existing `_said` dedupe ("Brenna is Orc-bane: +1 to hit").

`hit_chance` (combat.gd ~778, the odds chip) today leaves out `bonus_to_hit`
and the bicker penalty, so it already disagrees with the roll it describes.
The trait hook has to go into both, and fixing the existing gap comes with it.

### 5.3 On the road

Most overworld checks resolve their bonus through `Campaign.skill_bonus`
(`core/campaign.gd` ~777), so one `+ Traits.skill_bonus(ch, skill, where)` there
reaches road events, the approach card, forage, the settlement and downtime at
once. The three that sum their own terms get one line each, beside the term
that is already there:

- `Travel.check` bonus (`core/travel.gd` ~347), beside `PartyOpinion.travel_bonus`;
- `WorldCamp.watch_check` (`core/world_camp.gd` ~59), beside `Trance.WATCH_BONUS`
  — Trance is the existing "a thing about this person helps the watch";
- `WorldForage.check` (`core/world_forage.gd` ~25).

The roll line on the event card names the term, as it does for pace and
opinion ("+2 (Marsh-bred)").

## 6. Earning a trait, and losing one

**Events are observed, not polled.** `Traits.after_fight(party, result, where)`
runs where `PartyOpinion.fought_beside` does (`core/encounter.gd` ~869) and
returns what was gained or lost, for the after-action page to say. The world
calls `Traits.after(party, event)` beside `_calling_check`
(`scenes/world/world.gd` ~2346) for lair cleared, band beaten, calling done,
and from the camp and downtime flows.

**One gap has to be filled first.** The fight result
(`resolve_outcome`, encounter.gd ~879) knows *which monsters died* but not
*who killed them*, and knows *who went down* but not *what put them there*.
`_kill` takes no killer; `_apply_damage` takes no source. Both are in scope at
the call sites (`resolve_attack` ~2423–2441, `_spell_hit` ~1439), so the fix
is to record `result.credit = {hero_id: {"kills": [src_id…], "downed_by":
{"dtype", "src_id"}, "revived_by": id, "crits": n}}` as it happens. The
after-action page's own "Not built" list (per-hero killing blows, damage
taken — expansion-plan ~6855) wants the same record.

**Seeding.** Every roll a trait event makes is seeded off the event
(`hash("trait|%s|%s|%d" % [hero_id, cause, world_minutes])`), so a reload
cannot reroll the scar the player did not want.

### A first catalogue

Enough to test the vocabulary on every axis the issue names — location,
element, attack type, event. Numbers are placeholders until the sweep (§9).

**Personality** (pick one at creation; opposed pairs):

| trait | gives | costs | opposes |
|---|---|---|---|
| Brave | `save_adv` vs frightened | −2 on the approach's *avoid* | Craven |
| Craven | +1 AC while `bloodied` | −1 to hit in `first_round` | Brave |
| Wrathful | +1 damage while `bloodied` | −2 persuasion | Calm |
| Calm | +1 CON saves (holds concentration) | −1 initiative | Wrathful |
| Greedy | +10% purse | −5 baseline with every hero who is not Greedy (§7) | Generous |
| Generous | opinion drifts +1/day faster toward warm | −10% sale price | Greedy |
| Curious | +2 investigation / lair search | −1 on saves vs traps and hazards | Cautious |
| Cautious | +1 AC in `first_round` | −1 travel (stops to look at everything) | Curious |

**Origin** (one at creation, defaulted from background; the *location* axis):

| trait | gives | costs |
|---|---|---|
| Marsh-bred | +1 AC and +2 survival in the marsh | −1 survival on the downs |
| Woods-born | +1 to hit and +2 forage in the woods | −1 perception in towns |
| Downs-rider | +1 initiative on the downs; +1 travel | −1 stealth in the woods |
| Cave-dweller | +1 to hit on `frozen-cave`/`sunken-shrine` boards | −1 to hit on open boards in daylight |
| Street-raised | +2 persuasion/haggle and +1 AC on `city-square` | −2 survival in the wild |
| Night-owl | +1 to hit at `night` | −1 initiative by day |

**Marks** (earned; the *element* axis; one event, two outcomes weighted by personality):

| event | outcome A ("tempered") | outcome B ("afraid") | cure for B |
|---|---|---|---|
| downed by `fire` | **Fire-tempered**: `ward` fire 3 | **Burn-shy**: −1 to hit vs a foe that deals fire | down a fire-dealer yourself |
| downed by `cold` | **Frost-hardened**: `ward` cold 3 | **Chilled**: −1 initiative on `frozen-cave` | a long rest at an inn |
| downed by `lightning`/`thunder` | **Storm-struck**: +1 DEX saves | **Storm-shy**: −1 AC at `night` in the open | kill the caster type |
| poisoned 3 times | **Venom-proof**: `save_adv` vs poisoned | — | — |
| downed by one faction twice | — | **Haunted by <faction>**: −1 to hit vs them | clear one of their lairs |

Brave leans A (say 70/30), Craven leans B, everyone else 50/50 — the same
"who you are weights the fallout" as CK's stress events.

**Banes** (earned; the *attack type / foe* axis): ten killing blows on one
bestiary `type` or `faction` — *Orc-bane*, *Undead-hunter*, *Dragon-slayer*
(three, for dragons) — give +1 to hit and +1 damage vs it. Two at most, which
makes the player choose what the hero is known for.

**Other marks:** *Hard to kill* (revived from 0 three times: advantage on
death saves); *Veteran* (twenty won fights: +1 initiative); *Blade-sworn* /
*Bow-sworn* (twenty killing blows with one weapon damage type — `slashing`,
`piercing` — for +1 to hit with that type, the `dtype_out` axis).

**Wounds** (earned, temporary, the cure loop):

| wound | from | gives | heals |
|---|---|---|---|
| Wounded | downed and failed a death save | −1 to hit, −1 AC | a long rest at an inn, or 3 days |
| Shaken | an ally died beside you | −1 to all saves | 5 days; Calm heroes shed it in 2 |
| Maimed | two failed death saves in one fight | −5 ft speed | a healer in a city (`Downtime` / `SettlementVisit.work_healer`) |

`until` on the trait row carries the world-minute it lapses, the way
`Potions.expire` treats a road buff (`core/potions.gd` ~131).

## 7. Opinion — the part that makes it Crusader Kings

`PartyOpinion.baseline()` gains one more term beside `SAME_TEMPER` and
`TEMPER_GRUDGE`: **+5 per personality trait two heroes share, −10 per opposed
pair between them** (Brave and Craven do not get on). Drift already pulls every
pair toward its baseline (`DRIFT_PER_DAY`), so this needs no new machinery —
two Wrathful fighters will warm to each other on the road, and a Greedy rogue
and a Generous cleric will not, until something happens between them that
drags them past it. That is exactly CK's opinion-from-traits, on the numbers
the spike already measured.

Two hooks do more than baseline: *Generous* changes the pair's drift rate, and
friendly fire from a *Wrathful* caster costs half again (`FRIENDLY_FIRE × 1.5`)
because it looks deliberate.

## 8. Showing it

- **Character creation** — a step, or a row on the background step: pick one
  personality (a chip per trait, the opposed one greyed) and an origin
  (defaulted from the background).
- **Profile page** (`scenes/profile/profile.gd`) — a Traits panel beside
  Features (~406), each trait's name, its `text` and a line per effect ("+1 AC
  in the marsh"), and for a wound or a fear, what cures it.
- **Party page** — a trait chip line on the roster row (`_summary_label`
  ~599); the Relations block names the trait behind a pull ("Vera and Pike —
  cold (−18): Greedy and Generous").
- **Combat card** (`scenes/combat_card.gd`) — the traits *live right now*
  (whose `when` holds on this board) as chips, with a tooltip. **Naming
  collision:** the card already has a row headed "Traits" that means non-spell
  verbs (~180). One of the two has to be renamed (§10, Q1).
- **After-action page** — one line per gain or loss, under the hero's card
  ("Brenna came back from the fire **Fire-tempered**"); a picture per mark
  later, the way each calling has one.

## 9. Build order

Each step is one PR, green on its own, and each is playable without the next.

0. **Hero resistances reach the fight.** Separate from traits, but traits
   depend on it: `Adapter.to_combatant` never copies `sheet.resistances` /
   `sheet.immunities` into `c.resist` / `c.immune` (it does for monsters,
   `from_monster` ~309). A dwarf's poison resistance and a tiefling's fire
   resistance show on the profile page and do nothing in combat. Fixing it
   changes balance, so it wants its own sweep and its own PR, and it should
   land before `ward` is designed against it.
1. **Model, save, creation, the static half.** `data/traits.json` (the
   personality and origin rows), `core/traits.gd`, `ch.traits` through
   `CharacterSave`, the creation pick, `spec.where`, the fight-start stamp
   (§5.1), the profile panel. Tests: save round-trip incl. a pre-traits save;
   a Marsh-bred hero's AC in a marsh fight vs a downs fight.
2. **The per-roll half.** The four combat hooks (§5.2), `hit_chance` agreeing
   with them, the cap, the combat card chips. `tests/sweep_traits.gd` in the
   shape of `sweep_party_opinion.gd` measures the win-rate movement of each
   trait, and the numbers in `data/traits.json` get their measurement in
   capitals, like every other balance number in the repo.
3. **Earning.** `result.credit`, `Traits.after_fight`, marks, banes and
   wounds, the after-action line, the cures.
4. **The road and the fire.** `skill_bonus` and the three check sums (§5.3),
   the opinion terms (§7), a camp beat when a trait is gained ("Pike hasn't
   slept since the fire").
5. **The robot.** `drive_random` / `drive_completionist` play with traits on,
   so a trait that softlocks or crashes a run is caught the way everything
   else is.

## 10. Questions for the owner before step 1

1. **What are they called on screen?** "Traits" is taken on the combat card
   (non-spell verbs). Options: rename that row "Abilities" and keep *Traits*
   for these; or call these *Temperament* / *Marks* / *Nature*.
2. **Does the player choose, or does the sheet?** Proposed: the player picks
   one personality and one origin at creation. The alternative is rolling
   them off the background, CK-style, with a reroll.
3. **Can the player refuse a mark?** Proposed: no — earned traits are rolled
   (seeded, weighted by personality) and applied, because a scar you can
   decline is a menu, not a scar. The courtship precedent (asked, never
   rolled) is the other way to go, for the good/bad fork only.
4. **Stress?** CK3's stress meter is what makes a trait *cost* something when
   you act against it (a Craven hero ordered to hold the line). It would be a
   second meter per hero beside HP and exhaustion. Proposed: not in this
   design; revisit once traits exist and we see whether they feel inert.
5. **Heroes in old saves.** Proposed: they keep `traits: []` and are offered
   the creation pick once, the first time the party page opens. The
   alternative is to seed one silently off `hash("traits|%s" % ch.id)` and
   the background.
6. **Can a trait be lost to death or retirement for the others?** A hero who
   saw a friend die gets *Shaken*; should the *bond* traits (a pair who were
   lovers) carry something permanent? Proposed: later, with the relations
   pass.

# Personality traits — who a hero is, and what the road has done to them (#176)

A design, agreed with the owner on 2026-09-23 (§10), not yet built — its step 0
(three gaps in the fight the design stands on) is. Issue #176 asks for "character traits,
these can be what they start with and what they receive after some event they
were affected" — Crusader Kings' traits, in a 5e company. This document says
what a trait *is* here, what it can touch (the place a fight stands in, the
element a blow carries, the people across the board), how a hero gets and loses
one, and — most of it — which existing hook each piece hangs on, because
nearly every seam this needs is already cut. §9 is the order it is built in,
§10 what the owner decided.

**On screen they are "Personality traits"** — the whole system, every family
below. The one family that is about temper alone (Brave/Craven and its kin) is
called *temperament* in this document and in the data, so "personality" never
means two things.

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
character creation, and the same pick offered once to a hero from an older
save; the effect vocabulary (§3) and the hooks that read it
(§5); earning and losing traits from events (§6); opinion between traits (§7);
showing them (§8).

**Out:** traits for monsters (a bestiary entry already carries its own
defences and verbs); dynasty/inheritance anything; stress as a meter (§10,
decided no); refusing an earned trait (§10, decided no);
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
  "family": "origin",                 // temperament | origin | mark | bane | wound
  "opposes": [],                      // temperament pairs name each other
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
| temperament | 1 at creation, at most 2 | picked at creation; a second only from an event | no |
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

The odds chip and the roll now share one sum, `Combat.to_hit_bonus()` (step 0,
§9), so the trait's attack term goes in there once and both see it.

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

**One gap had to be filled first.** The fight result
(`resolve_outcome`, encounter.gd ~879) knows *which monsters died* but not
*who killed them*, and knows *who went down* but not *what put them there*.
`_kill` took no killer; `_apply_damage` took no source, though both were in
scope at every call site that has one. The after-action page's own "Not
built" list (per-hero killing blows, damage taken — expansion-plan ~6855)
wants the same record.

**Built (step 0).** `Combat.credit` records it as it happens, and
`resolve_outcome` hands a copy back as `result.credit`:
`{hero_id: {"kills": [bestiary id…], "downed_by": [{"dtype", "by", "team"}…],
"revived_by": [hero id…]}}`. `_apply_damage` takes the blow's `source`; a
hazard's burn and a death save name nobody and credit nobody.

### One event, several outcomes — and not the same one for everybody

An event does not hand out a trait; it rolls on a small **outcome table**, and
every hero it touched rolls on their own. Two heroes downed by the same fire
giant can walk away one Fire-tempered and one Burn-shy, and a third who only
watched can come out of it with nothing at all. That is the CK stress event:
the same thing happens to everybody, and who they are decides what it does to
them.

```jsonc
// data/traits.json, beside the traits themselves
"events": {
  "downed_by_fire": {
    "who": "the downed",                               // or "the witnesses", "the party", "the killer"
    "outcomes": [
      {"trait": "fire-tempered", "weight": 30, "lean": {"brave": 20, "craven": -15}},
      {"trait": "burn-shy",      "weight": 30, "lean": {"craven": 20, "brave": -15, "calm": -10}},
      {"trait": "scarred",       "weight": 15},
      {"trait": "",              "weight": 25, "lean": {"calm": 15}}  // walks it off
    ]
  }
}
```

- **Weights, leaned by who you are.** Each `lean` adds to an outcome's weight
  when the hero has that trait (temperament mostly, but any trait may lean:
  a hero already *Burn-shy* is likelier to go further than to recover). A
  weight never goes under 0.
- **"Nothing" is an outcome.** Most events should mostly do nothing, or every
  hero is a list of scars by level five. The empty row is what keeps a trait
  worth reading when it does land.
- **A trait already held is re-rolled as "nothing"**, and a family at its cap
  (§2) drops the rows it cannot take before the roll.
- **Some outcomes remove.** `{"lose": "burn-shy"}` is a row like any other — the
  cure for a fear can itself be a roll, on the event that ought to cure it.
- **Applied, never asked** (§10, decided): the after-action page and the camp
  card *tell* the player what the event did; there is no accept/decline.

**Seeding.** Every roll is seeded off the event and the hero
(`hash("trait|%s|%s|%d" % [hero_id, event_id, world_minutes])`), so a reload
cannot reroll the scar the player did not want, and two heroes in one event
roll independently.

### A first catalogue

Enough to test the vocabulary on every axis the issue names — location,
element, attack type, event. Numbers are placeholders until the sweep (§9).

**Temperament** (pick one at creation; opposed pairs):

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

**Marks** (earned; the *element* axis; each event an outcome table as above,
every row but the empty one shown):

| event (who rolls) | outcomes | leans |
|---|---|---|
| downed by `fire` (the downed) | **Fire-tempered** (`ward` fire 3) · **Burn-shy** (−1 to hit vs a fire-dealer; cured by downing one) · **Scarred** (+2 intimidation) · nothing | Brave → tempered, Craven → shy, Calm → nothing |
| downed by `cold` (the downed) | **Frost-hardened** (`ward` cold 3) · **Chilled** (−1 initiative on `frozen-cave`; an inn's long rest) · nothing | Brave → hardened, Craven → chilled |
| downed by `lightning`/`thunder` (the downed) | **Storm-struck** (+1 DEX saves) · **Storm-shy** (−1 AC at `night` in the open) · nothing | as fire |
| poisoned a third time (the poisoned) | **Venom-proof** (`save_adv` vs poisoned) · **Weak stomach** (−1 CON saves) · nothing | Wrathful → venom-proof |
| downed by one faction twice (the downed) | **Haunted by <faction>** (−1 to hit vs them; cured by clearing one of their lairs) · **Grudge: <faction>** (+1 damage vs them, −1 AC vs them) · nothing | Craven → haunted, Wrathful → grudge |
| an ally died (every hero who saw it) | **Shaken** (wound) · **Vengeful** (+1 to hit vs the killer's faction, 5 days) · **Hardened** (+1 WIS saves) · nothing | Calm → nothing, Wrathful → vengeful, Craven → shaken |
| brought back from 0 (the revived) | **Hard to kill** (after the third: advantage on death saves) · **Grateful** (+10 baseline with the reviver) · nothing | Generous → grateful |
| a lair cleared (the party) | **Delver** (+1 to hit on lair boards) · nothing | Curious → delver |

The same event, different heroes: in a fight where a fire giant drops Vera
(Brave) and Pike (Craven) and Ilsa (Calm) watches, Vera most likely comes out
Fire-tempered, Pike most likely Burn-shy, and Ilsa most likely nothing — but
any of them can land anywhere on their table.

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
| Shaken | the "an ally died" table | −1 to all saves | 5 days; Calm heroes shed it in 2 |
| Maimed | two failed death saves in one fight | −5 ft speed | a healer in a city (`Downtime` / `SettlementVisit.work_healer`) |

`until` on the trait row carries the world-minute it lapses, the way
`Potions.expire` treats a road buff (`core/potions.gd` ~131).

## 7. Opinion — the part that makes it Crusader Kings

`PartyOpinion.baseline()` gains one more term beside `SAME_TEMPER` and
`TEMPER_GRUDGE`: **+5 per temperament two heroes share, −10 per opposed
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

- **Character creation** — the player picks (§10, decided): a step, or a row
  on the background step, "Personality traits" — one temperament (a chip per
  trait, the opposed one greyed) and an origin (defaulted from the
  background, changeable).
- **Heroes from an older save** — `traits` reads `[]`, and the first time the
  party page opens with such a hero on it, the same pick is offered once
  (§10, decided). A flag on the character (`traits_offered`) stops it asking
  twice, and closing it without choosing still sets the flag — the offer is an
  offer, not a gate.
- **Profile page** (`scenes/profile/profile.gd`) — a "Personality traits" panel beside
  Features (~406), each trait's name, its `text` and a line per effect ("+1 AC
  in the marsh"), and for a wound or a fear, what cures it.
- **Party page** — a trait chip line on the roster row (`_summary_label`
  ~599); the Relations block names the trait behind a pull ("Vera and Pike —
  cold (−18): Greedy and Generous").
- **Combat card** (`scenes/combat_card.gd`) — a "Personality traits" row: the
  ones *live right now* (whose `when` holds on this board) as chips, with a
  tooltip. The card's existing "Traits" row (non-spell verbs, ~180) keeps its
  name; the two headings differ by the word that matters.
- **After-action page** — one line per gain or loss, under the hero's card
  ("Brenna came back from the fire **Fire-tempered**"); a picture per mark
  later, the way each calling has one.

## 9. Build order

Each step is one PR, green on its own, and each is playable without the next.

0. **The fight tells the truth — BUILT (2026-09-23).** Three gaps the hook
   survey found, fixed before anything is designed on top of them
   (`tests/test_combat_credit.gd`):
   - *Hero resistances reach the fight.* `Adapter.to_combatant` never copied
     `sheet.resistances` / `sheet.immunities` into `c.resist` / `c.immune`
     (`from_monster` always did), so a dwarf's poison resistance showed on the
     profile page and did nothing in combat. The presets are all human, so
     `Regions.ref_score` and every sweep anchored on them are unchanged; a
     player party with a dwarf, a tiefling, a dragonborn or an aasimar is a
     little sturdier than it was, by exactly what the rules say.
   - *The odds chip agrees with the roll.* `Combat.to_hit_bonus()` is the one
     sum both `hit_chance` and `resolve_attack` use — it now counts
     `bonus_to_hit` statuses, a condition's d20 penalty and a rival's bicker,
     and a rally shows as advantage. Only Bardic Inspiration stays off the
     chip: it is a die rolled when it is spent.
   - *The fight says who did what.* `Combat.credit` / `result.credit` (§6).
1. **Model, save, creation, the static half — BUILT (2026-09-23).**
   `data/traits.json` (8 temperaments, 6 origins, a default of each per
   background), `core/traits.gd`, `ch.traits` / `ch.traits_offered` through
   `CharacterSave`, the creator's pick on the background step (the
   background's pre-selected), the one-time offer to an older hero on the
   party page, `spec.where` (biome, band, site) from `world.gd`'s
   `_run_combat`, the fight-start stamp (§5.1) with its log line, the profile
   panel, the combat card's row and the roster card's line
   (`tests/test_traits.gd`, `tests/test_trait_pages.gd`). Two things learned
   building it: the stamp has to land **before** `Combat.new`, which rolls
   initiative in its constructor (`Traits.stamp(combatants, board)` in
   `Encounter.build`); and the board and the night are always known, so a
   board- or night-keyed trait fires even in a fight with no `spec.where` —
   only biome, band and site need the world screen. The presets carry no
   traits and are never offered them: they are the ruler every sweep stands on.
   Effects whose `when`/`gives` the build does not apply yet are shown on every
   page marked "(not yet in play)".
2. **The per-roll half.** The four combat hooks (§5.2), `hit_chance` agreeing
   with them, the cap, the combat card chips. `tests/sweep_traits.gd` in the
   shape of `sweep_party_opinion.gd` measures the win-rate movement of each
   trait, and the numbers in `data/traits.json` get their measurement in
   capitals, like every other balance number in the repo.
3. **Earning.** `Traits.after_fight` over `result.credit`, the outcome tables
   (§6) with their leans, marks, banes and wounds, the after-action line, the
   cures.
4. **The road and the fire.** `skill_bonus` and the three check sums (§5.3),
   the opinion terms (§7), a camp beat when a trait is gained ("Pike hasn't
   slept since the fire").
5. **The robot.** `drive_random` / `drive_completionist` play with traits on,
   so a trait that softlocks or crashes a run is caught the way everything
   else is.

## 10. Decided (the owner, 2026-09-23)

1. **Name:** "Personality traits", for the whole system. The combat card's
   existing "Traits" row keeps its name.
2. **The player picks** one temperament and one origin at creation — yes.
3. **An earned trait cannot be refused** — no accept/decline; it is rolled
   (seeded, leaned by who the hero is) and applied, and the game says so.
4. **No stress meter** — no.
5. **Heroes from an older save are offered the pick once** — yes (§8).
6. **Bond traits — possibly yes, later.** Noted, not designed: when a hero's
   lover or closest friend (`PartyOpinion` `lovers` / `bonded`) dies, the
   survivor rolls on a table of their own that can leave something
   *permanent* — *Widowed*, *Oath-sworn* against the killer's faction,
   *Hollow* — rather than the five-day *Shaken* anyone gets. It wants the
   relations pass it depends on and the outcome tables (step 3) first.

And one from the owner that shapes §6: **an event can have different outcomes,
and not the same one for every person in it** — every event is an outcome
table, every hero it touched rolls on it separately, and who they are leans
the roll.

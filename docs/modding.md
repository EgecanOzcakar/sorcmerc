# Making content for sorcmerc

Everything in this document is available to anybody. The campaigns the team
ships — free ones and paid DLC — are content packs written against exactly the
API below, loaded by exactly the same loader, validated by exactly the same
validator. There is no second, better pipeline behind the curtain. That is
deliberate: it is the only arrangement in which the community's half keeps
working, because the team's own content breaks the moment it stops.

A pack can do three things, in increasing order of ambition:

1. **Add or retune data** — monsters, items, spells, species, anything under
   `data/` — and say what the new things *do* in a fight.
2. **Ship a world** — a map: settlements, lairs, roaming bands, water, where
   the party starts.
3. **Tell a story** — chapters, a cast, dialogue with choices, and quest chains
   that escalate, on your map or on somebody else's.

---

## 1. Where packs live

| Root | What it is |
|---|---|
| `res://content/<pack>/` | ships with the game — official free content and paid DLC |
| `user://mods/<pack>/` | what a player installed |

`user://` is the per-user data directory: `~/.local/share/godot/app_userdata/sorcmerc/mods/`
on Linux, `%APPDATA%\Godot\app_userdata\sorcmerc\mods\` on Windows,
`~/Library/Application Support/Godot/app_userdata/sorcmerc/mods/` on macOS. Set
`SORCMERC_MODS_DIR` to point the game somewhere else while you are working.

A pack is a **directory with a `pack.json` in it**. A directory without one is
not a broken pack, it is not a pack — so unzipping something untidy into the
mods folder cannot break the list.

Open **Campaigns & mods** on the title screen to see every pack the game found,
what state each is in, and every problem with the broken ones, in full. Press
**Rescan** after editing a file: you do not have to restart the game to see
what you just typed wrong.

### Packs are data, and only data

A pack may not ship GDScript, and there is no hook, callback or script field
anywhere in the formats below. Community content is downloaded from strangers
and run on somebody's machine; a pack that could carry code would be a way to
run that code. Everything here is JSON interpreted by the modules under
`core/mod/`.

This is a real constraint on what you can author. It is also why official DLC
and a mod from a forum can go through one pipeline with one trust level.

---

## 2. `pack.json`

```json
{
  "format": "sorcmerc-pack",
  "api": 1,
  "id": "ashen-road",
  "title": "The Ashen Road",
  "summary": "One paragraph, shown in the browser.",
  "authors": ["Your name"],
  "pack_version": "1.0.0",
  "kind": "campaign",
  "access": "free",
  "priority": 10,
  "requires": [],
  "world": "world.json",
  "story": "story.json",
  "callings": "callings.json",
  "data": {"bestiary.json": "monsters.json", "magic-items.json": "items.json"}
}
```

| Key | Meaning |
|---|---|
| `format` | always `"sorcmerc-pack"` |
| `api` | the modding API you wrote against. This build speaks **1**. A pack declaring a higher number is refused with a readable reason instead of half-loading; a lower one keeps working, which is the promise this field exists to make. |
| `id` | lowercase slug, unique across both roots. **Saves remember it**, so renaming a published pack orphans its saves. |
| `title`, `summary`, `authors`, `pack_version` | what the browser shows |
| `kind` | `world`, `campaign` or `data` — a label for the browser. What a pack *does* is decided by the files it declares, never by this. |
| `access` | `free` (default) or `paid` — see §6 |
| `priority` | data-overlay order; higher lands later, so it wins a collision. Official content layers before user content regardless. |
| `requires` | pack ids that must be installed and loaded, or this one is marked broken and says why |
| `world` | a world file (§3) |
| `story` | a story file (§4) |
| `callings` | a callings file (§5.2) |
| `data` | `{game data file: your file}` (§5) |

Everything but `format`, `id` and `title` is optional.

The API level is still **1**. The `data/effects/` files in §5.1 and the
`callings` file in §5.2 are new, and no pack written before them mentioned
them; a capability a pack can decline to use is not a break. `api` moves only when something a pack already
wrote stops meaning what it meant.

---

## 3. `world.json` — a map

```json
{
  "format": "sorcmerc-world",
  "version": 1,
  "name": "The Long Vale",

  "settlements": [
    {"id": "longvale", "name": "Long Vale", "position": [0, 0],
     "faction": "human", "kind": "town"}
  ],

  "lairs": [
    {"id": "vale-warren", "name": "The Vale Warren", "position": [220, 210],
     "faction": "goblinoid", "discovered": false}
  ],

  "parties": [
    {"id": "vale-bandits", "position": [-240, -160], "faction": "bandit",
     "troops": [{"role": "heavy", "level": 2}],
     "ai": {"behavior": "hunt"}}
  ],

  "waters": [
    {"position": [-140, -60], "radius": 90},
    {"river": [[-70, -10], [-20, 120], [30, 260]], "radius": 35}
  ],

  "start": {"at": "longvale", "offset": [40, 40], "faction": "human"}
}
```

**Settlements** are where trade, rest, quests and rumours happen. `kind` is
`city`, `town` or `camp` (size, and which sprite). `faction` is one of
`human`, `elf`, `dwarf` (civilized, tradeable) or any monster faction — an
orc city is hostile, and that is a supported thing to build.

**Lairs** are dungeons: hidden until a Survival check finds them, then delved
room by room. `faction` must be one the bestiary can fill a fight from
(`goblinoid`, `undead`, `dragon`, `giant`, `orc`, `gnoll`, `kobold`, `bandit`,
`beast`, `cultist`, `monstrosity`, `fey`, `elemental`, `construct`,
`soldier`) — a lair is *made of* its faction's roster. `"discovered": true`
puts it on the map from the start. A lair on heartland or marches ground with
a civilized settlement within 800 runs a raid clock like the built-in maps'
(`core/raids.gd`); there is no opt-out today.

**Landmarks** are places on the map that are not a fight — ruins, a shrine,
standing stones, a hermit's hut, a wreck, a watchtower (`kind`: `ruins` |
`shrine` | `stones` | `hut` | `wreck` | `tower`). `name` is optional, the same
as everywhere else. A pack that declares no `landmarks` gets none — the
built-in builders place their own by hand or by seed, but that placement never
runs for a pack; if you want them on your map, write them here.

**Parties** are roaming bands. `troops` is flavour — the map figure and the
headcount label; their actual fight is built from the faction. `name` is
optional: without one the game names the band itself ("Ribsnap's goblins",
"the Low Fen gnolls", seeded off its `id`), and a band is never shown to the
player by its `id`. A story's `spawn_party` takes the same `name`. `ai.behavior`:

| behavior | extra keys |
|---|---|
| `hunt` | — (chases what it is hostile to) |
| `patrol` | `waypoints`: a list of `[x, y]` points **or settlement/lair ids** |
| `wander` | `home`: a point or an id · `radius` · `seed` |
| `idle` | — (stands where it was placed) |

**Waters** are circles, and a circle is the whole terrain vocabulary. Water is
impassable, so it is walls as much as scenery. A `river` is sugar for a chain
of blobs stamped along a polyline, because writing that loop by hand in JSON is
writing it wrong; `"blobs": 5` sets how many go between each pair of points,
and it wants to stay well under the radius so the bank comes out scalloped
rather than machined.

**start** is `{"at": <settlement id>, "offset": [x, y]}` or
`{"position": [x, y]}`. A start inside water is nudged to the nearest bank —
nobody begins the game swimming.

### Difficulty comes from where you put things

You do **not** declare levels or difficulty anywhere. The map is banded into
four countries — Heartland, Marches, Frontier, Far Deeps — measured from your
human settlement out to the furthest thing you placed, in equal-area rings
(`core/regions.gd`). A fight is built for the party that is standing there,
*clamped* to the band's level range. So:

- Put the goblins near home and the dragon at the far edge.
- A faction belongs to a band (`Regions.HOMES`): bandits/beasts/goblinoids
  in the Heartland, undead/cultists/giants out at the Frontier, dragons and
  elementals in the Deeps. Following that makes a map read right.
- Widening your map moves the seams. Adding one far-off lair pushes every band
  outward, so place the far things first and check the near ones after.

`tests/test_world_pack.gd` asserts this on the shipped campaign: three lairs,
three bands, no region data in the pack at all.

---

## 4. `story.json` — a campaign

A story is chapters. A chapter holds **beats**. A beat has a condition and
fires the first time that condition is true.

```json
{
  "format": "sorcmerc-story",
  "version": 1,
  "title": "The Ashen Road",
  "synopsis": "Shown in the journal before anything has happened.",

  "cast": [
    {"id": "maera", "name": "Maera Vulk", "role": "Reeve of Emberwatch",
     "home": "emberwatch", "about": "Tired, and out of soldiers."}
  ],

  "chapters": [
    {
      "id": "smoke",
      "title": "Smoke on the Marches",
      "intro": "A line for the journal when the chapter opens.",
      "beats": [ ... ],
      "ends_when": {"quest": "ashen-warren", "state": "turned_in"}
    }
  ]
}
```

Chapters run in the order written. A chapter ends when its `ends_when` holds
or — with none written — when every non-`optional` beat in it has fired. The
end of the last chapter ends the story. There is no chapter graph on purpose:
a story that branches does it with flags and conditions *inside* a chapter,
which is the same tool everything else already uses.

### Beats

```json
{
  "id": "the-reeve",
  "kind": "scene",
  "speaker": "maera",
  "when": {"near": "emberwatch"},
  "optional": false,
  "title": "The Reeve of Emberwatch",
  "lines": ["\"You're the ones who take work.\""],
  "choices": [
    {"id": "take", "text": "Name the price.",
     "then": {"flags": ["hired"]}},
    {"id": "buy", "text": "Buy the map off her.", "when": {"gold": 300},
     "then": {"gold": -300, "flags": ["hired", "has-map"]}}
  ],
  "then": {"journal": ["The reeve has a job."]}
}
```

| `kind` | what it is |
|---|---|
| `scene` | someone speaks; needs `lines` or `choices` |
| `quest` | hands over a quest (below); shows as a card if it has anything to say |
| `note` | no scene — just `then`. A note with nothing to show does not interrupt the map. |

A beat fires **once, ever** — that is saved, so a story survives a reload
mid-telling. Firing applies the beat's own `then`. A choice's `then` is applied
only when the player picks it, and a choice whose `when` fails is not offered
at all. Nothing blocks: a card dismissed without choosing simply applied no
choice, and a story that is never looked at still advances.

### Quest beats are ordinary quests

```json
{"id": "warren-work", "kind": "quest", "when": {"flag": "hired"},
 "quest": {"id": "ashen-warren", "kind": "clear_lair",
           "target_lair_id": "ash-warren",
           "title": "Burn out the Ash Warren",
           "required": 1, "reward": {"gold": 220, "item_id": "ember-brand"}}}
```

The quest goes into the party's own quest log, where every existing piece of
quest machinery picks it up with no idea a story is involved: progress from
kills, the turn-in at any merchant, the log panel, the encounter spawn bias. A
**quest chain is quests that unlock each other**, not a second quest system.

| `kind` | target field | completes when |
|---|---|---|
| `kill_count` | `target_monster_id` | that many of them die |
| `collect_item` | `target_monster_id` + `target_item_id` + `drop_chance` | that many drop |
| `hunt_party` | `target_party_id` | that band is destroyed |
| `raid_settlement` | `target_settlement_id` | that settlement is raided |
| `clear_lair` | `target_lair_id` | that lair is cleared |
| `supply_item` | `target_item_id` | that many are in the shared stash |
| `deliver_goods` | `target_settlement_id` | the party walks into that settlement |
| `scout_region` | `target_region_id` | the party is standing in that band (`heartland` / `marches` / `frontier` / `deeps`) |
| `rescue` | `target_lair_id` | the captive in that lair's pens is freed (the room's rescue objective is done) |

### Conditions (`when`)

Every key in a condition must hold. `{}` is true — "as soon as this chapter
opens".

| condition | true when |
|---|---|
| `{"flag": "hired"}` | the story set that flag |
| `{"flags": ["a", "b"]}` | all of them |
| `{"not_flag": "refused"}` | it did not |
| `{"beat": "the-reeve"}` | that beat has fired |
| `{"chapter": "smoke"}` | that chapter is the live one |
| `{"quest": "id", "state": "turned_in"}` | `offered` / `active` / `complete` / `turned_in` / `any` |
| `{"party_level": 4}` | average party level is at least 4 |
| `{"gold": 500}` | the purse holds at least that |
| `{"has_item": "ember-brand"}` | it is in the shared stash |
| `{"visited": "emberwatch"}` | that settlement has ever been entered |
| `{"near": "emberwatch", "within": 120}` | the party is that close (default 60). Works on lairs too. |
| `{"lair_found": "ash-warren"}` | discovered |
| `{"lair_cleared": "ash-warren"}` | looted |
| `{"region": "frontier"}` | the party is standing in that band |
| `{"day": 4}` | world-day 4 or later |
| `{"opinion": {"faction": "human", "atleast": 20}}` | that faction thinks that well of you |
| `{"all": [...]}` `{"any": [...]}` `{"none": [...]}` | nesting |

An **unknown condition key is an error**, not a beat that silently never
fires. That is the worst failure mode a data-driven story can have, so the
validator refuses to ship one.

### Effects (`then`)

| effect | does |
|---|---|
| `"flags": ["hired"]` | set them |
| `"clear_flags": ["hired"]` | unset them |
| `"journal": ["..."]` | write lines into the journal and onto the card |
| `"gold": 220` | pay the party; a negative number charges them |
| `"items": [{"id": "potions-of-healing", "quantity": 3}]` | into the stash |
| `"xp": 1200` | split over the party, through the same path a fight uses (so it feeds meta-progression too) |
| `"quest": {...}` | hand over a quest, same shape as a quest beat's |
| `"opinion": [{"faction": "human", "delta": 25}]` | move a faction's opinion |
| `"reveal_lair": "ash-warren"` | put it on the map |
| `"spawn_party": {"id": ..., "name": ..., "near": ..., "offset": [x, y], "faction": ..., "troops": [...]}` | a band takes the field (idempotent: firing twice does not make two); `name` is optional and is what the player reads from then on |
| `"next_chapter": "barrow"` | jump there |
| `"end_story": true` | finish |

An unknown effect key is an error too.

---

## 5. `data` — adding and retuning game data

```json
"data": {"bestiary.json": "monsters.json", "magic-items.json": "items.json"}
```

The key is one of the game's own files under `data/`; the value is yours,
relative to your pack. Records merge **by `id`**: an id the base game does not
have is added, an id it does have is **replaced**. So a pack can both add a
monster and retune an existing one, and the result is folded into the same
arrays every system already reads — your monster is a monster to the encounter
builder, the faction rosters and the bestiary screen, with nothing anywhere
made aware that packs exist.

Overlayable files: `classes.json`, `subclasses.json`, `species.json`,
`backgrounds.json`, `feats.json`, `fighting-styles.json`, `weapons.json`,
`armor.json`, `magic-items.json`, `spells.json`, `conditions.json`,
`monsters.json`, `bestiary.json`, `skills.json`, and the four mechanics files
of §5.1: `effects/spells.json`, `effects/potions.json`, `effects/features.json`,
`effects/conditions.json`, and the two the inns' hirelings are rolled from:
`recruit-names.json` (`{"id": "<species id>", "names": [...]}` — a pack's new
species gets its own names this way, or falls back to the `default` record)
and `recruit-kits.json` (`{"id": "<class id>", "kits": [{"ability": "str",
"items": ["longsword", "shield", "chain-mail"]}]}` — any item the class cannot
use is skipped). A key that is not one of them is a typo and is reported as one.

Copy the shape of an existing record — `data/SCHEMA.md` documents the export,
and `content/ashen-road/monsters.json` is a two-entry worked example. A
bestiary entry needs at least `id`, `cname`, `ac`, `max_hp`, `atk_bonus`,
`damage`, `cr`, `xp`, `faction` and `habitat` to take part in a real fight.

Four more fields on a bestiary entry are read, and are what makes a monster
more than its numbers. `resist`, `immune` and `vulnerable` are lists of damage
types; `cond_immune` is a list of `conditions.json` ids. RAW's order applies,
once each: immunity wins outright, vulnerability doubles, resistance halves.
`senses` (`{"darkvision": "60 ft.", "passive_perception": 12}`) feeds the one
perception check this engine has — a watcher with a keen sense is harder to
hide from, and blinding it takes away only the senses it was relying on.
`features` is a list of `effects/features.json` ids (§5.1).

You cannot break the difficulty curve by writing a big number:
`core/rules/power.gd` prices every one of those fields, and the fight builder
spends a budget, so a monster you make tougher is a monster it buys fewer of.

Turning a pack off takes its records back out, including its retunes.

### 5.1 `data/effects/` — what a thing *does*

`spells.json` says a spell exists. `effects/spells.json` says what casting it
puts on the board. The split is not tidiness: the game's own catalog is an SRD
export and the export carries prose, so everything mechanical is hand-authored
over the top of it — by us, and through these same four files, by you. Without
them a pack could add a spell nobody could cast and a potion nobody could
drink, which is exactly the silent dead-end the rest of this pipeline exists to
refuse.

| file | keyed by | gives |
|---|---|---|
| `effects/spells.json` | a `spells.json` id | the cast: cost, shape, range, save, damage, upcast |
| `effects/potions.json` | a `magic-items.json` id | the drink: a combat action, or a swallow on the road |
| `effects/features.json` | a feature id — one named by a monster's `features`, or a class feature | the mechanic, under a closed `kind` |
| `effects/conditions.json` | a `conditions.json` id | what wearing that condition costs |

All four are **objects keyed by id**, not lists, and they merge by key rather
than by a record's `id` field. A key beginning with `_` is an authoring comment
and is skipped. Every id an entry names must be in the catalog or be one your
own pack adds: a mechanic for a spell nobody wrote is an error, not a silence.

A key you write **replaces the whole entry**, it does not patch it. Retuning
one number in the game's Fireball means writing out the rest of Fireball too —
otherwise you have written a spell that does only the thing you mentioned.

**A spell.** `cost` is `action`, `bonus` or `reaction`. `shape` is `single`,
`cone`, `line`, `sphere`, `cube`, `cylinder`, `radius`, `emanation`, `self` or
`allies`; `size_ft` sizes the shape, `range_ft` says how far it reaches.

```json
"ember-lance": {
  "cost": "action", "shape": "single", "range_ft": 60,
  "save": "dex", "half_on_save": true,
  "damage": [{"count": 2, "sides": 8, "type": "fire"}],
  "upcast": {"per_level": {"count": 1, "sides": 8}}
}
```

Beside `damage`, or instead of it, a spell may carry `heal`, `conditions`,
`buff`, `teleport`, `summon` or a `reaction` block. With none of them it is not
combat-castable, and it is never offered as a pick — a utility spell with no
hook would be a slot spent on nothing.

`upcast.per_level` is what a bigger slot buys: more dice (`count`), more `rays`,
or one more `targets` for a single-target status spell. `cantrip_scale` does the
same job for a cantrip, against character level instead of slot. A `reaction`
block names its `trigger` and, for a counter, `counter` and `min_level`.

`damage` must be written as `[{count, sides, type}]`. The export's
`{"dice": "8d6"}` is a draft the verb builder cannot read, and a pack that
leaves it that way is refused rather than shipping a fifth-level spell that
hits like a dagger.

**A potion** hangs a mechanic on a `magic-items.json` id, and being listed here
is what makes the bottle real: an alchemist's shelf is exactly the ids in this
file, and nothing anywhere will let a player drink one that is not on it. Loot
is the exception — `core/loot.gd`'s drop bands are a hand-picked list rather
than everything drinkable, and a pack cannot extend them, so a pack's potion is
bought and not found.

```json
"potion-of-embers": {"status": {"bonus_damage": 2}, "rounds": 10,
                     "minutes": 30, "text": "+2 damage while it burns"}
```

`heal` and `damage` are dice strings. `condition` names a `conditions.json` id.
`status` is a buff the drinker wears, built from keys combat already honours —
`resist`, `bonus_damage`, `bonus_to_hit`, `bonus_save`, `extra_action`,
`speed_mult`, `ac`, `no_attack`, `str_score`. `rounds` is its life in a fight
and `minutes` its life on the world clock when it is drunk on the road, where an
unexpired buff is carried into the next fight; `road` names something it does
out of combat. A potion with none of `heal`, `damage`, `condition`, `status` or
`road` does nothing at all, and is refused.

**A feature** is a mechanic under a closed `kind`:

`passive_damage`, `self_buff`, `ally_buff`, `heal_self`, `heal_ally`,
`grant_action`, `grant_verb`, `attacks_per_action`, `attack_modifier`,
`damage_bonus`, `save_effect`, `reaction`, `save_modifier`, `survive_damage`,
`keen_senses`, `aura`, `summon`, `font_of_magic`, `metamagic`.

```json
"monster-parry-2": {"label": "Parry", "kind": "reaction",
                    "cost": "reaction", "trigger": "would_be_hit", "ac_bonus": 2}
```

A feature with **no** entry here is a flavour feature: it shows on the sheet and
does nothing in a fight. That default is what makes a bestiary of hundreds of
ids tractable, so author only the ones that matter — and note that it is also
why the `kind` vocabulary is closed rather than open. A typo'd kind would be
indistinguishable from a feature you meant to leave as flavour.

An `aura` is a standing fact about a piece of the board rather than a button:
it needs a `range_ft` and a payload (`save_bonus`, `cond_immune` or
`aura_resist`), and the resolver reads the best one in reach at the moment a
number is needed.

A `summon` puts a second creature on the board, on its owner's side, in the
free hex nearest them. It names a stat block and may scale it off its owner:

```json
"beastmaster-primal-companion": {"kind": "summon", "cost": "action",
  "summon": {"id": "dire-wolf"}, "uses": {"by": "pb"},
  "mult_pct": {"by": "class_level", "class": "ranger",
               "steps": [{"min": 3, "value": 70}, {"min": 9, "value": 110}]}}
```

`summon.id` is a `monsters.json` or `bestiary.json` id and must exist — a
summon naming nothing is refused rather than standing nothing up. `mult_pct` is
whole percent (`encounter._scale`'s multiplier ×100, since a scaling spec deals
in ints), `rounds` puts a clock on it, and `summon.illusion` marks it as not a
creature: nothing can target it and it cannot attack. It **rolls its own
initiative** and takes its place in the order by that roll. The button greys
out while one of the same stat block is still standing, so a feature summon
cannot be stacked.

A `self_buff` may also carry `spell_dc_bonus` (added to the wearer's spell
save DC while it lasts) and `spell_attack_adv` (Advantage on spell attack
rolls), with `rounds` as its clock. That is Innate Sorcery.

A `font_of_magic` trades between a spell-slot pool and a resource `pool` in
both directions. It is one entry that becomes a button per slot level each way:
burn a level-L slot for L points (no action), or pay a `font.create` row's
`cost` for a slot of its `level`, once `font.class` has reached `min` levels.

```json
"sorcerer-font-of-magic": {"kind": "font_of_magic", "cost": "bonus",
  "pool": "sorcery-points",
  "font": {"class": "sorcerer",
           "create": [{"level": 1, "cost": 2, "min": 2}, {"level": 2, "cost": 3, "min": 3}]}}
```

A `metamagic` button arms the caster's next spell with one `option`:
`quickened` (an action spell costs a Bonus Action), `twinned` (one more target
for a spell that upcasts for targets), `careful` (spares allies in the area),
`subtle` (it cannot be Counterspelled) or `seeking` (a missed spell attack is
rolled again). It pays `pool_cost` from its `pool`, and the points come back if
no spell took the option by the end of the turn.

`cost` is `action`, `bonus`, `reaction`, or `none` for a passive. A reaction
must name a `trigger` the engine actually fires — `hit_by_attack`,
`damaged_by_attack`, `spell_cast`, `would_be_hit` — because a reaction hung off
anything else will never wake. `dice`, `uses`, `amount` and `bonus_damage` take
either a plain number or a scaling spec (`{"by": "class_level" | "pb" |
"ability_mod", ...}`); a monster has no character sheet, so a monster's feature
must use plain numbers.

**A condition** says what wearing it costs: `attacks_against`, `own_attacks`
and `own_checks` (`"adv"` or `"dis"`), `speed`, `saves`, and `auto_fail` — the
senses it takes away, which is how blinding something interacts with what it
was using to see.

Turning the pack off takes all of this back out, the same as any other overlay.

### 5.2 `callings.json` — a past for each background

Every hero's background hands them a **calling** — a personal quest pointed
at something the live map holds (`core/callings.gd`: the acolyte's defiled
shrine, the soldier's deserters, the sage's lost library under a lair), told
once at the campfire, done on the road, paid in XP, an heirloom and a bond.
The game ships sixteen, one per background. A pack can add or replace them:

```json
"callings": "callings.json"
```

```json
{
  "soldier": {
    "title": "The Vale's deserters",
    "target": {"kind": "band"},
    "done_by": "band_beaten",
    "item": "javelin-of-lightning",
    "tell": "%s came over the Vale's passes last winter: men from a company you served in...",
    "done": "%s are accounted for, and the Vale's roads are the quieter for it."
  }
}
```

Keyed by background id, merged over the built-in table **by background**: a
background the game already has is replaced, one it does not (a background
your `backgrounds.json` overlay adds) is added. Each entry:

| Key | Meaning |
|---|---|
| `title` | the line on the party page and the quest log |
| `target.kind` | what the calling points at: `landmark` (with `landmark`: `ruins` \| `shrine` \| `stones` \| `hut` \| `wreck` \| `tower`), `lair` (the nearest not yet looted), `band` (the nearest monster band; with an optional `factions` list, e.g. `["bandit", "soldier"]`, only a band of one of those — none on the map and the calling waits for one, the way the built-in soldier's deserters do), `settlement` (with `settlement`: `camp` \| `town` \| `city`, civilized; a missing size falls back to a larger one), or `audience` (the ladder's, with any lord) |
| `done_by` | the one event that completes that kind — `landmark_answered`, `lair_cleared`, `band_beaten`, `visited`, `audience`, respectively; anything else is an error |
| `item` | the heirloom: a `magic-items.json` id, the game's or your pack's overlay's |
| `tell`, `done` | the telling at the fire and the resolution line, second person; `%s` is the target's name (an audience has none to name). A band's name is a plural ("Ribsnap's goblins", "the Low Fen gnolls"), so write "%s are..."; a `%s` that opens the line is capitalised for you |

The target is chosen from the map the party is on — the nearest thing of the
kind — so a calling written for your world plays on any world that has the
kind. No such thing on the map means no calling yet, tried again at every
camp. The pictures are the game's (`event-calling-<background>.png`); a pack
cannot ship its own yet. Checked at scan time like everything else: a kind the game
cannot point at, a `done_by` that does not match it, an item that does not
exist, a missing title — each is a line in the browser, and the pack does not
load until they are fixed.

Turning the pack off takes its callings back out with its records.

---

## 6. Free and paid packs

`"access": "paid"` plus a `"product_id"` makes a pack DLC. The rules:

- A paid pack the player does not own is **listed but not loaded**. Not
  "loaded and hidden" — a locked pack cannot leak a monster, an item name or a
  line of its story through some other system. The browser shows its title,
  summary and SKU, because that is how anybody learns it exists.
- A free pack is owned by everybody. Community content and official free
  content are the same thing to this system.
- What the player owns is `user://entitlements.json`, and `core/mod/entitlement.gd`
  is the only thing that reads it. A storefront integration (Steam, itch,
  whatever) calls `Entitlement.sync([...])` once at boot with the ids that
  account owns; everything downstream keeps working, offline, from what was
  written down.
- Playtest builds own everything (`OS.has_feature("playtest")`, or
  `SORCMERC_PLAYTEST=1` / `SORCMERC_UNLOCK_DLC=1` while developing) — the same
  switch that unlocks species and classes for the playtest channel.

The game is not the storefront and does not pretend to be: there is no purchase
button, only a line saying where the thing comes from.

---

## 7. Writing one

```
user://mods/my-pack/
    pack.json
    world.json
    story.json
    monsters.json
    spells.json          # what your spells are
    spell-mechanics.json # what casting them does — "effects/spells.json" in pack.json
```

Your own filenames are yours; `data` in `pack.json` is what maps them onto the
game's. Nothing has to sit at a path that mirrors `data/effects/`.

1. Copy `content/example-world/` — the shortest thing that is a working pack
   (a map, and nothing else).
2. Open **Campaigns & mods**. Your pack is listed, with every problem spelled
   out under it.
3. Edit, press **Rescan**, repeat.
4. Press **Play**, build a party, and you are in your own map.

Things the validator catches before a player ever sees them, all at once
rather than one per run:

- unknown ids anywhere: a quest pointing at a lair your map does not have, a
  `speaker` who is not in the cast, a beat waiting on a beat nobody wrote, a
  `region` that is not a region
- mistyped condition and effect keys
- a quest kind the game cannot track, or one missing its target field
- duplicate ids, of anything, anywhere
- a reward naming an item that does not exist (a warning: it may be another
  pack's)
- an effect `kind` or a reaction `trigger` the engine does not have, a
  mechanic written for a spell or an item nobody wrote, spell damage the verb
  builder cannot read, a potion that does nothing
- a paid pack with no `product_id`, an `api` from the future, a declared file
  that is not there
- placement mistakes the schema cannot express — a settlement standing in a
  lake (a warning)

### Sharing

A pack is a directory of text files. Zip it; a player unzips it into their
mods folder. Nothing is compiled, nothing is installed, and nothing runs.

Pack ids are global, so pick something nobody else will: `yourname-thevale`
beats `campaign`. If two packs claim one id the first root wins — official
content before user content — and the loser is marked broken and says so,
which means a mod cannot shadow a DLC by claiming its id.

---

## 8. Not yet: scripted fights

A beat cannot yet say "this fight, these foes, this board, now". Every fight in
the game — including the ones a story's quests send you into — is built for the
party standing there by `core/scaler.gd`, so a pack shapes encounters by
*placing* things (a lair's faction, where it sits on the map) rather than by
writing a roster.

It is designed and not built: `docs/expansion-plan.md` §M9 has the intended
shape — a `fights` block in the pack, a `"kind": "fight"` beat that runs one,
and `on_win`/`on_loss` effect blocks so a story can branch on the outcome. If
you are writing a pack now, the thing worth knowing is that the trigger already
works (`when` on a beat); only the fight itself is missing, so a set-piece can
be written today as a scene plus a `clear_lair` quest and upgraded later
without rewriting the chapter around it.

## 9. What is where, in the code

| File | Owns |
|---|---|
| `core/mod/manifest.gd` | `pack.json`: parse and validate |
| `core/mod/registry.gd` | discovery, load order, enable/disable, what the game asks for |
| `core/mod/entitlement.gd` | free/paid, the storefront seam |
| `core/mod/world_pack.gd` | `world.json` → a live `World` |
| `core/mod/story.gd` | `story.json`: the schema, and the validator |
| `core/mod/story_runtime.gd` | the playthrough: conditions, effects, chapters, save state |
| `core/callings.gd` | `callings.json`: the built-in sixteen, the validator, where a pack's land |
| `core/rules/catalog.gd` | where data overlays land |
| `core/rules/effects.gd` | the `data/effects/*.json` vocabulary, and what reads it |
| `core/potions.gd` | `effects/potions.json`: the two doors a bottle opens |
| `core/rules/power.gd` | what a monster's defences and features cost the fight builder |
| `scenes/mods/mods.gd` | the browser |
| `scenes/world/story_card.gd` | the card a beat is shown on |

Tests, which are also the most precise documentation of every rule above:
`tests/test_mod_packs.gd`, `tests/test_world_pack.gd`, `tests/test_story.gd`,
`tests/test_mod_screens.gd`, `tests/drive_story.gd`.

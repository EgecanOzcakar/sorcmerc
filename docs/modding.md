# Making content for sorcmerc

Everything in this document is available to anybody. The campaigns the team
ships — free ones and paid DLC — are content packs written against exactly the
API below, loaded by exactly the same loader, validated by exactly the same
validator. There is no second, better pipeline behind the curtain. That is
deliberate: it is the only arrangement in which the community's half keeps
working, because the team's own content breaks the moment it stops.

A pack can do three things, in increasing order of ambition:

1. **Add or retune data** — monsters, items, spells, species, anything under
   `data/`.
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
| `data` | `{game data file: your file}` (§5) |

Everything but `format`, `id` and `title` is optional.

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
puts it on the map from the start.

**Parties** are roaming bands. `troops` is flavour — the map figure and the
headcount label; their actual fight is built from the faction. `ai.behavior`:

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
| `"spawn_party": {"id": ..., "near": ..., "offset": [x, y], "faction": ..., "troops": [...]}` | a band takes the field (idempotent: firing twice does not make two) |
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
`monsters.json`, `bestiary.json`, `skills.json`. A key that is not one of them
is a typo and is reported as one.

Copy the shape of an existing record — `data/SCHEMA.md` documents the export,
and `content/ashen-road/monsters.json` is a two-entry worked example. A
bestiary entry needs at least `id`, `cname`, `ac`, `max_hp`, `atk_bonus`,
`damage`, `cr`, `xp`, `faction` and `habitat` to take part in a real fight.

Turning a pack off takes its records back out, including its retunes.

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
```

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
| `core/rules/catalog.gd` | where data overlays land |
| `scenes/mods/mods.gd` | the browser |
| `scenes/world/story_card.gd` | the card a beat is shown on |

Tests, which are also the most precise documentation of every rule above:
`tests/test_mod_packs.gd`, `tests/test_world_pack.gd`, `tests/test_story.gd`,
`tests/test_mod_screens.gd`, `tests/drive_story.gd`.

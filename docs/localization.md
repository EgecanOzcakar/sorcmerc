# Localization

sorcmerc ships in English and Turkish. English is the **source language**: every
call site in the code passes the English text it would have shown anyway, so
"en" costs a dictionary miss and nothing else, and a translation that is missing
a line degrades to that English rather than to a key name or a blank label.

Switch languages in the settings overlay (the first control on the panel). The
choice is stored in `user://settings.json` as `"language"`. Tests and tools can
pin it with the `SORCMERC_LANG` environment variable, which wins over the
setting — the same debug-gate shape as `SORCMERC_SEED` and `SORCMERC_FAST`.

```
SORCMERC_LANG=tr godot --headless --path . -s tests/drive_ui.gd
```

---

## The shape of it

`core/loc.gd` is the whole engine: static, no autoload, no instances, and it
loads nothing until something asks. A language is a directory of JSON under
`data/loc/<code>/`:

| File | What is in it | Read by |
|---|---|---|
| `ui.json` | UI chrome, keyed by a dotted key (`"title.new_run"`) | `Loc.t()` / `Loc.tf()` |
| `terms.json` | the keyword glossary, grouped (`"condition"` → `"prone"`) | `Loc.term()` |
| `features.json` | feature id → name (`"fighter-second-wind"`) | `Loc.name_of()` |
| `names.json` | every other bare id that becomes a label: resource pools, choice types, class ids | `Loc.name_of()` |
| `records/<file>.json` | per-`data/*.json` overrides, id → the fields to replace | `core/rules/catalog.gd` |

Each file is parsed on first use and cached; switching languages drops every
cache, including the catalog's (the record overlay is folded in at parse time,
so the parsed data itself has to go).

### Why the records are an overlay and not a lookup

`Loc.localize_records()` is called by `core/rules/catalog.gd` once per data
file, right after the content packs have had their turn:

```gdscript
_files[file] = Loc.localize_records(file, _layered(file, _files[file]))
```

So a translation of `classes.json` is not something a screen has to remember to
ask for — it *is* `Catalog.class_src("barbarian")["name"]`, for every one of the
dozens of call sites that already read that field, with no per-caller
awareness. It is the same trick the mod loader uses, for the same reason.

The merge is field-by-field: a table that gives a `name` and no `description`
leaves the English description in place. Array files (spells, classes,
monsters) match on the record's `id`; dictionary files (skills, conditions) on
the key. A pack's own monster is translated on exactly the same terms as the
base game's when the language names its id — packs go in first.

### Feature names

`data/*.json` carries no prose for the 479 feature ids the resolver grants
(SCHEMA gap #4), so the engine's fallback has always been
`Effects.humanize("fighter-second-wind")` → `"Fighter Second Wind"`. That
function is now the one door every feature name goes through: it asks
`Loc.name_of()` first and falls back to knocking the hyphens out. `features.json`
is what answers.

A translated name is already the short one — Turkish does not carry the class
prefix — so `Effects.verb_label()` (the action bar's "Second Wind", not
"Fighter Second Wind") returns it unchanged and only splits the English
fallback.

---

## Adding a language

1. `mkdir -p data/loc/<code>/records`
2. Add `{"id": "<code>", "label": "<the language's own name>"}` to `LANGS` in
   `core/loc.gd`. The label is the one string on the settings panel that is
   deliberately never translated: a player who has landed in the wrong language
   has to be able to read their way out.
3. Write as much of the table set as you like. Every file is optional and every
   key is optional; what is missing reads as English.
4. `tests/test_loc.gd` will tell you what you have not covered yet.

## Adding a string to a screen

Wrap it where it is built, with the English as the fallback:

```gdscript
b.text = Loc.t("party.create_new", "Create new")
head.text = Loc.tf("title.barracks", "%d in the barracks.", [roster])
```

`Loc.tf()` is `Loc.t()` with the format arguments applied after the lookup, so a
translation keeps the placeholders and may reorder them. Then add the key to
`data/loc/tr/ui.json` — `tests/test_loc.gd` scrapes the scripts for every key a
screen actually asks for and fails on any that has no Turkish, so a key added
and forgotten is a red test rather than an English sentence in a Turkish menu.
It also compares the `printf` specs on both sides: a `%d` that became `%s` in
translation is a crash at the call site, not a typo.

Keywords go through `Loc.term(group, id, fallback)` rather than `t()`, so that
"light" the armour category and "light" the weapon property can differ — which
in Turkish they do.

---

## What is translated today

**Fully**, in Turkish:

- every **keyword**: abilities, skills, the 15 conditions (names *and* prose),
  damage types, spell schools, sizes, creature types, factions, rarities,
  weapon properties and masteries, action costs, rest types, spell casting
  times / ranges / durations — 282 glossary entries
- all **493 feature ids** — every class, subclass, species, feat and monster
  feature the resolver can grant
- **names** for everything the catalog holds: 12 classes, 48 subclasses (with
  their prose), 10 species, 16 backgrounds, 74 feats (with their prose), 10
  fighting styles (with their prose), 146 spells, 39 weapons, 13 armours,
  264 magic items, all 316 bestiary entries
- the **UI**: title and summary, settings, the party screen and standing
  orders, the character sheet, the creator and level-up, progression,
  achievements, the mod browser, the combat HUD and its tutorial, and the open
  world's HUD and menus — 392 keys

**Not yet** — large bodies of authored English prose, and the next pass:

- the combat action log (`core/combat.gd`), which narrates every roll
- the road events, settlement pages and approach cards (`core/travel.gd`,
  `core/site.gd`, `core/settlement_visit.gd`, `core/approach.gd`)
- the field manual's long-form pages (`core/manual.gd`)
- spell and magic-item descriptions (names are done; the SRD prose is not)
- the content packs under `content/`, which carry their own prose

Class and keyword terminology follows the conventions the Turkish D&D and
Baldur's Gate 3 community translations settled on — Barbar, Ozan, Rahip,
Druid, Savaşçı, Keşiş, Paladin, Korucu, Hırsız, Efsunbaz, Kara Büyücü,
Büyücü; Zırh Sınıfı, Kurtarma Zarı, Uzmanlık Bonusu, avantaj/dezavantaj.
Where two renderings are both current, the one that reads as a game term
rather than a dictionary gloss wins.

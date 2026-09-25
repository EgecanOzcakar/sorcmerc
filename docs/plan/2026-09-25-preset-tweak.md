## Preset tweak — temperament and origin on the ready-made heroes, and one for every starting class (2026-09-25)

Issue #200 asked three things of the creator's "Load a preset" list. The
lock-gate half (a preset used to hand a fresh profile the Fighter and the
Rogue it had not opened) already landed as `build_lock_note`. This entry is
the other two.

**Temperament and origin.** The presets carried no personality trait on
purpose (#176): `Presets.party()` and `party_at()` are the ruler
`core/regions.gd`'s win-rate table, the scaler's `REF_SCORE` and every sweep
(`tests/sweep_*.gd`, `tests/test_scaler.gd`) are measured against, and a trait
stamped into those fights would move a measured number nobody re-ran. So the
traits go on the player's door only. `core/presets.gd` now has two:
`build(id)`, bare, which is exactly what `vera()`/`pike()`/`ilsa()` always
returned, and `hero(id)`, the same build with the temperament and origin from
`PERSONALITY` set. The creator's `_preset()` goes through `hero()`; nothing
that measures a fight does. A loaded preset shows its picks on the Skills &
Background step like any other hero, the player can change them there, and
Confirm's `Traits.fill_defaults` leaves a picked family alone, so they
survive. Checked: the trio's `CharacterSave.to_dict` and sheets from
`party()`, `party_at(1/3/8/15/20)` and `vera(5)`/`pike(2)`/`ilsa(8)` are
byte-identical before and after the change, and `tests/test_presets.gd` holds
`party()`/`party_at()` to carrying no trait from now on.

| Preset | Build | Temperament | Origin |
|---|---|---|---|
| Vera Kord | Human Fighter 3 (Champion), soldier | Brave | Downs-rider |
| Pike Sallow | Human Rogue 3 (Thief), criminal | Cautious | Street-raised |
| Ilsa Vane | Human Cleric 3 (Light Domain), acolyte | Generous | Cave-dweller |
| **Brakka Thorn** | Orc Barbarian 3 (Berserker), farmer | Wrathful | Downs-rider |
| **Sael Ambry** | Wood-elf Ranger 3 (Hunter, Colossus Slayer), guide | Cautious | Woods-born |
| **Marit Quell** | Human Wizard 3 (Evoker), sage | Calm | Night-owl |
| **Dagna Holt** | Dwarf Warlock 3 (Fiend Patron, Pact of the Tome), charlatan | Curious | Cave-dweller |

**One more per starting class.** The five classes open from day one are
`core/progression.gd`'s `STARTING_CLASSES`: cleric, warlock, wizard, barbarian
and ranger. Ilsa already covered the cleric; the four in bold are new, one for
each of the others, each on a starting species (human, orc, elf, dwarf) and
one of its class's two starting subclasses, so a fresh profile can load every
one of them. It still greys out Vera and Pike. They are level-3 builds in the
trio's style, with every choice decided, including the subclass-level ones
(Sael's Hunter's Prey) and the level-3 pact boon. Their gear is off
`data/recruit-kits.json` and their spells are ones `data/effects/spells.json`
gives a combat verb, so every one of them does something in a fight. Unlike the
trio, whose scores were tuned to match the old hand-authored MVP numbers, the
four stand on the standard array before their background's +2/+1, the same
budget as a hero made in the creator. That makes a preset a shortcut and never
an upgrade. None of them is in `party()`, so no sweep sees them. Like any
preset, they start a run at level 2 (`PRESET_START_LEVEL`), with the
subclass waiting for level 3.

The list is `Presets.ROSTER` now, and its labels are built from the sheet
("Brakka Thorn (Barbarian 3)"), the same shape as "Your presets" below it.
Each button's tooltip says who they are ("Orc Barbarian (Path of the
Berserker), Farmer. Wrathful, Downs-rider."). The note above the list no
longer names Vera, Pike and Ilsa. Screenshots: `docs/shots/issue-200-presets.png`
(the list on a fresh profile) and `docs/shots/issue-200-preset-traits.png`
(Brakka loaded, on the Skills & Background step).

Tests: new `tests/test_presets.gd` holds both promises: the ruler is bare,
and every listed preset resolves with nothing pending at 3 and at 2, carries
proficient gear, turns into a Combatant with attacks (and spells, for a
caster), and loads or wears its lock correctly on a fresh profile. It also
checks that every starting class has a preset. `tests/test_leveling.gd`'s
#200 block now loads Ilsa and Brakka through the creator and checks the traits
come with them.

This is not a balance change. No tuned number moved and the ruler's sheets are
byte-identical, so no sweep was re-run.

### Still open

- No second preset for the cleric. The issue's "another one per starting
  class" reads as one more per class, and Ilsa already is the cleric's. Add a
  Life Domain cleric if the list wants to be two per class.
- The Review step, where a loaded preset lands, does not show the temperament
  and origin. They are on the Skills & Background step and in the button's
  tooltip. Put them on the Review sheet once the creator's layout work
  (#188/#189/#190) settles.
- The engine asks a wizard for 6 first-level spells and a warlock for 2 at
  level 3 (the export's level-1 grants only), and invocations are not
  modelled, so Marit and Dagna are a little under a 2024 sheet of their level.
  That is true of any hero made in the creator, not a preset issue.

## Combat rules sweep — Speed 0, one reaction, free species spells, named weapons (2026-09-25)

Four issues filed against the fight, each checked against the 2024 rules and
held by its own test.

**#249 — does Incapacitated block movement?** No, and the engine already
agreed: the 2024 Incapacitated condition takes actions, Bonus Actions and
Reactions and says nothing about Speed, and `data/effects/conditions.json`
gives it no `speed`. What stops a creature moving is Speed 0: Grappled,
Restrained, Paralyzed, Petrified, Unconscious (0 HP is the engine's `down`),
and Stunned as this repo's SRD export words it. That was right too
(`Combat.move_left`). The sweep turned up two real gaps beside it:

- **Petrified** is Incapacitated, but its entry carried only `no_action`, so a
  statue could still take a Bonus Action or a Reaction. It now carries all
  three flags.
- **Standing up at Speed 0.** `_auto_stand` stood every prone creature at the
  top of its turn, including one held Paralyzed, Restrained or in a grapple.
  2024 Prone: "If your Speed is 0, you can't right yourself." It now stays
  down. The new `Combat.speed_zero(c)` is the one question `move_left` and
  `_auto_stand` both ask. `_release_grapples` now runs before the stand, so a
  grip whose holder has just dropped lets go before the check rather than
  after it.

**#247 — one reaction, back on your own turn.** Also already right:
`econ["reaction"]` refreshes in `Combatant.new_turn()`, which only
`begin_turn_for` (the creature's own turn) calls. Nothing refreshes it at the
top of a round, and every reaction path spends it through `_spend`: the
opportunity attack in `move_to`, and every branch of `fire_reactions`. The
sweep found one leak beside it. **Warding Flare's uses were never spent.**
`_reaction_affordable` refused an empty pool, but nothing emptied it, so a
Light cleric flared once every round of every fight. `fire_reactions` now
pays a feature reaction's pool when it fires. It is the only feature reaction
with uses today.

**#246 — a tiefling's Hellish Rebuke costs no slot.** The 2024 species and
origin-feat spells (Fiendish Legacy, Elven Lineage, Gnomish Lineage, Fey
Touched, Shadow Touched) are castable once per Long Rest without a slot, and
with slots besides. The engine read them as plain always-prepared spells. A
tiefling warlock paid a pact slot for its Rebuke. A tiefling fighter has no
slots at all, so it carried a Hellish Rebuke that could never fire.

- `PassSpells` marks every leveled `alwaysPrepared` grant from a species or
  feat bundle as **innate** (`spellcasting["innate"]`). Cantrips are left
  out, since they cost nothing already. So are a subclass's prepared lists,
  which are paid for with slots.
- `resolve.gd` grants each innate spell a pool, `innate-<spell>`, of max 1
  and regen `long-rest`. The fight, `write_back`, `Adapter.rest`, the save
  file and the co-op hash already carry pools, so they carry this one with
  no new code.
- `Effects.spell_verbs_for` puts `innate_pool` on the base-level verb.
- `Combat.can_pay_spell` / `_pay_spell` take a slot **or** the free cast, the
  free one first. Every place that checked or spent a slot for a spell asks
  them now: `_offerable`, `_cast_refusal`, `cast`, `_reaction_affordable`, and
  Shield's branch of `fire_reactions`. An upcast always takes a slot.
- `RoadSpells` spends the same pool first, so a wood elf's Longstrider on the
  road is free once per Long Rest too.
- A species/feat caster with no casting class (the tiefling fighter) has no
  spellcasting ability, which left its DC at 0. It now uses the best of
  INT/WIS/CHA (a `ponytail:` in `pass_spells.gd`: RAW is the player's choice,
  and the export records none).
- The reaction prompt and the tooltip say "free once per long rest, no slot"
  while the free cast is there.

**#245 — the log names the weapon.** The line used to read "Vera Kord hits
Snik the Goblin — d20[14]+5 = 19 vs AC 15, …". It now reads "Vera Kord hits
Snik the Goblin with a Longsword — …", and the hit, the miss, the nat-1 and
the crit lines all say it. `Combat.weapon_name` picks the name:

- a hero's main-hand attack (`attacks[0]`, the one every derived number
  already comes from);
- a monster's statblock `attack_name` (Bite, Scimitar, Slam — all 316
  bestiary entries carry one);
- the off-hand blade (the verb now carries `weapon`);
- "Unarmed Strike" for an archer's opportunity attack.

A plural natural weapon takes no article ("with Claws"). A combatant nothing
names reads exactly as before. Spells already named themselves ("casts Fire
Bolt on …"). The words the log colouring keys on (" hits ", " CRITS ",
"misses") stay where they were. There is no localization layer to update.

**Balance.** One tuned outcome moves. **Warding Flare is now WIS-mod uses per
Long Rest** instead of one a round, forever. Ilsa, the preset Light cleric,
is on the preset party the `Regions` win-rate table and the tier sweeps are
anchored on, so those fights get slightly harder for the party. No constant
was retuned; the sweep needs a re-run in a balance pass. The free species
spells touch no preset (all human). The Speed-0 stand only matters for a
creature that is both prone and held.

Tests: `tests/test_speed_zero.gd`, `tests/test_reaction_economy.gd`,
`tests/test_innate_spells.gd`, `tests/test_attack_log.gd`.

### Still open

- **Stunned and Speed.** The 2024 PHB's Stunned condition is Incapacitated,
  auto-fails STR/DEX saves and gives Advantage against, and says nothing
  about Speed. This repo's SRD export (`data/conditions.json`) says "can't
  move", so `speed: 0` was kept. Dropping it would change what Stunning
  Strike is worth. Come back to it as a balance decision with the Monk
  sweep, not as a data fix.
- **Species spells arrive at level 1.** RAW gives the 1st-level spell at
  character level 3 and the 2nd-level one at 5 (Fiendish Legacy, Elven
  Lineage). The export's grants carry no level, so a level-1 tiefling already
  has Hellish Rebuke and Darkness. Gate it when the export emits a
  `minCharacterLevel`, or with a table in `pass_spells.gd`.
- **Uses other than one.** A forest gnome's Speak with Animals is PB times per
  Long Rest, not once. It is off the board today, so nothing reads it. Make
  `INNATE_USES` per-grant if that changes.
- **Magic Initiate** (a `spell-choice`, not an `alwaysPrepared` grant) also
  gives a free 1st-level cast per Long Rest, and is not marked innate yet.
- **The HUD's move readout.** `scenes/main.gd`'s `_econ_bb` and the "click a
  blue tile to move" hint read `econ["move_left"]`, not `Combat.move_left()`.
  A Paralyzed hero's bar can therefore show move points it cannot spend (the
  board offers no blue hexes). This is presentation only; fix it with a
  screenshot.
- `core/rules/power.gd` still values a spell only by slots, so a non-caster's
  free Hellish Rebuke adds nothing to its power score.

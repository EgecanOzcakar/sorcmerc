## What's riding on you — the effect strip on the action bar (2026-09-24)

The owner's ask: make every buff we have (an armed Metamagic, the Advantage
on a next attack...) more obvious in the action bar, since nothing else on
screen holds it. Until now a status was invisible between the log line that
set it and the roll that spent it. An armed Quickened Spell, a Help's
Advantage, a Bless's +2 and Poisoned's Disadvantage all change what the next
press does, and the bar said nothing about any of them.

**`core/active_effects.gd`** (pure, headless-tested) turns a combatant's
statuses into:

- **Chips** `{label, tone, clock, detail}`. There are four tones: edge (it
  helps), hindrance (it hurts), mixed (Reckless) and hold (concentration).
  The families it knows:
  - the engine's own flags: Hidden, Helped, Dodging, Vex, Sapped, Rallied and
    the rest;
  - conditions, in the SRD's own words;
  - feature buffs, named for the button that set them: Rage, a Smite, Innate
    Sorcery;
  - spells, which help or hurt by whose side cast them (a friend's Bless, a
    foe's Bane);
  - potions;
  - the hero's traits.

  Dead, down, stable and the other bookkeeping stay off the strip on purpose
  (`HIDDEN`).
- **Marks on buttons.** An attack gets `ADV` or `DIS` from the same
  `Combat.cond_sources()` list the roll weighs, or `±` when they cancel.
  A Smite's waiting dice show as `+2d8`. A spell gets `✦` exactly when the
  armed Metamagic would ride it (`Combat.metamagic_for()`, the rule, asked
  without casting), and `ADV` under Innate Sorcery if it is a spell attack.
  The bar never claims an edge the dice won't give: spell attacks still ignore
  conditions (the ponytail in `_spell_hit`), so Poisoned puts no DIS on them.

**`scenes/main.gd`** draws them:

- **The strip.** Chips sit to the right of the button row, in the space the
  fixed eleven buttons leave. Green, red and verdigris edges, a clock in
  small type, and the description on hover. The strip is held at two rows
  tall and scrolls beyond that, so a buff arriving never moves the board.
- **Marked buttons.** A button an effect changes is framed in its colour with
  a filled pill on the corner. The reason heads its tooltip.
- **List buttons.** Spells ▸ and Bonus actions ▸ carry the mark when
  something inside them has one. An armed Quickened Spell is no use hidden
  one level down.
- **Other heroes.** Looking at another hero's sheet shows their strip.

**The guard.** `tests/test_active_effects.gd` checks:

- every family's words, tone and clock;
- that the button marks agree with the rules (Quickened marks exactly the
  action spells; Seeking only spell attacks);
- that every self-buff, ally-buff and buff spell in all 48 kits leaves a chip
  named for its button (147 pressed);
- a sweep of every kit's real fights at levels 3 and 8, where any status that
  falls through to the generic chip fails.

A new mechanic cannot add a buff the bar is silent about. The mutation check
(dropping Vex from the vocabulary) fails where it should.

`tests/kits.gd` is the "every kit, built the way a player builds it" helper,
moved out of `test_coop_kits` so both checks share it.

### Still open

- **Target-dependent edges aren't marked.** Prone, dodging and faerie-fired
  targets, and darkness, change the odds against one target, not the button.
  The aim preview and the hover card say those.
- **Enemies' buffs** are only on the board's token tags. The strip is about
  the hero whose bar it is.
- **Chips have no icons yet.** A buff whose source verb has a badge could wear
  it.

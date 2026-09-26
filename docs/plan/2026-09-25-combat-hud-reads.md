## The fight reads what it holds — weapon badges, the card's effects, the blow before the death (2026-09-25)

Three owner-reported gaps on the combat screen, each a place where the screen
knew something and did not say it.

**#241 — the Attack button wears the weapon.** The Attack badge was one
generic sword whether the hero held a longsword, a mace or a shortbow, and the
Swap button was one generic ⇄ whatever it would swap to.

- `Icons.skill_icon(v, who)` now takes the combatant. Given one, the plain
  Attack wears `who.attacks[0]`'s item render (`assets/art/items`, which covers
  all 38 SRD weapons), the same way a Drink button already wore its bottle.
- The off-hand swing wears its own weapon: `Adapter._offhand_verb` now names it
  in a display-only `weapon_id` key (`weapon`, the name, is what #245's log prints).
- A thrown javelin or dagger is still the javelin (`Icons.weapon_icon` strips
  `-thrown`).
- An Unarmed Strike or a pack's undrawn weapon keeps the generic badge. So does
  a granted attack (`<feature>:attack`), so it does not look like the plain one
  beside it.
- The Swap slot wears the weapon it would put in your hand, with a gilt ⇄ in
  the corner so it still reads as a swap. The pair reads "this, or that". With
  nothing to swap to, it stays the greyed swap badge.

Screenshot: `docs/shots/issue-241-weapon-icons.png`. The top row is a mace in
hand with a crossbow on Swap. The bottom row is after Tab: the crossbow on
Attack and the mace on Swap.

**#238 — the character card says what is riding on it.** The #173 card listed
only the CONDITION_ORDER flags. A Bless, a Bane, a Rage, a held concentration
spell or a potion never showed, and neither did any clock. Being sticky, the
card also went stale: it redrew only on a hover over somebody new, so a
creature knocked prone after you looked still read as standing.

- "Right now" moved up under the health bar. It is built from
  `core/active_effects.gd`'s chips, the effect strip's own words, tones, clocks
  and hover text, so the card and the strip cannot disagree.
- A condition keeps its `CONDITION_COLORS` colour and glyph. Anything else
  takes the strip's tone colour.
- The card adds two chips the strip leaves to other readouts: death saves
  ("Down, saves 1/2", or "Stable") and "In cover".
- This is the one place a foe's buffs, or a hero's off their turn, can be read.
  That answers half of the effect strip's "Enemies' buffs" still-open item.
- `CombatCard.refresh()` runs on every `_refresh()` of the combat screen. It
  redraws only when a signature of HP, AC, speed, chips, death saves and cover
  has changed.

Screenshot: `docs/shots/issue-238-card-effects.png`. It shows a bugbear under
Bane and Prone, and a cleric holding Bless.

**#244 — the blow first, then the death.** A killing hit played the kill sting
and the creature's death sting in the same frame and no weapon sound at all.
The last swing of a fight was the one swing you never heard land.

- `Combat._hold_sfx()` collects the stings `_apply_damage` sets off instead of
  playing them: the fall, the kill sting, a victory, a carter going down.
- `resolve_attack` then plays them through `Audio.play_sfx_then(landing,
  after)`. The weapon's hit starts at once, and the rest follows once it has
  landed.
- The follow-up waits for the whole of a short take, capped at `FOLLOW_MAX`
  (0.45 s). The generated hit takes run 0.2 to 3.2 s, and almost all of that
  is ring-out; a death three seconds behind its blow reads as two unrelated
  events. There is no wait under `SORCMERC_FAST`.
- A hero dropped by a hit now also sounds the hit, then the fall.
- Holds nest. A reaction resolving inside the blow plays its own sounds and
  leaves the outer list alone.

Not visual. `tests/test_audio.gd` covers it:

- `follow_gap`'s cap and its `SORCMERC_FAST` zero;
- that a real lethal `_apply_damage` holds "down" (and "victory" on the last
  foe) rather than playing it;
- that nested holds stay apart.

**Tests.**

- `tests/test_action_icons.gd`: real preset builds wear their weapon (longsword,
  shortbow), a main-hand swap swaps the badge, thrown/unarmed/off-hand/granted
  resolve as above.
- `tests/test_combat_card.gd`: Bless with its clock, Concentrating, a foe's
  Prone and not the hero's Bless, a condition ending leaves the card through
  `refresh()` with no new hover, and death saves on a downed hero.
- `tests/shot_hud_reads.gd` is the dev-only capture for both screenshots.

### Still open

- **Spell kills still play death and cast together.** Only a weapon attack holds
  its consequences; a Fireball's deaths land in its cast's frame. The same
  `_hold_sfx` around the spell's damage loop would do it, once there is a
  "landing" sound for a spell to put first.
- **Item art on the bar is a painted render, not a gilt badge.** It reads, but
  it sits unframed beside the SVG set. A frame drawn around item art (potions
  included) is the fix if it jars.
- **A granted attack keeps the generic sword** even when it swings the main hand
  (a feature's granted swing, like `monk-flurry-of-blows:attack`). Revisit if
  a granted attack ever needs to be told apart by what it swings, not by being
  a different button.
- **The card's chips carry no icons**, the same open item the effect strip has.

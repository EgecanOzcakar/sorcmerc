## Painted caricature faces for the heroes — the #230 spike (2026-09-26)

#230 asks for a 2D caricature portrait for every gender × class × race: a
bust cropped just above the chest, with huge funny heads, showing what marks
the people and the class. It would be used in every 2D place a hero is drawn:
the turn strip, the party page, the relations web, the stat card and the trait
moment. Only the live board keeps the 3D figures.

This entry is the spike, not the feature: **nothing in the shipped game reads
it yet.** The design, the inventory and the owner's questions are in
`docs/spike-hero-portraits.md`.

**What is there today.** No hero picture exists. Every face is rendered live
from the class's rig (`scenes/portraits.gd`), keyed on the class alone, so a
dwarf fighter and an elf fighter wear the same face. The game has no gender
field at all. The matrix is therefore 10 species × 12 classes × 2 looks = 240
pictures, or 696 by lineage. It also needs one cosmetic `Character.look`.
Nothing in the rules reads it, and it slots into saves, recruits and co-op
without moving anything: old heroes get a look from `hash(id)`, recruits from
a hash off their seed, and co-op carries it through `CharacterSave`.

**What the generator can do.** The render tool is
`tools/localgen/gen_hero_portraits.py`. It ran 124 renders on the owner's
SDXL-base ComfyUI, at 22–24 s each.

- **Prompt alone**, five recipes: the best was recipe E. It rendered 12 keys
  at 2 seeds, touching every class, species and look, and about 8 of the 24
  renders passed all of people, class, look, caricature and clean framing.
- **Measured: SDXL base holds about three of those five in one prompt.** The
  aasimar and the goliath failed until they were described harder, and then the
  framing and the caricature went.
- **A template** (img2img off one picked render at denoise 0.75) gives true
  bobbleheads in one uniform set: class, look and caricature 8/8. The price is
  the peoples that differ by skin or glow rather than silhouette: the aasimar
  and the goliath came out humans, 5/8 peoples read.
- **At 40 px the people reads and the class mostly does not**, so the class
  glyph stays. The big heads read better small than the handsome ones.
- **The full set** would be about 6 GPU hours at 4 seeds a key, 240 picks and
  85 MB.

**Recommended:** twelve class templates, img2img per species × look, and a
reviewer's pick of four. `Portraits.hero(ch, px)` returns the painted file
when there is one and today's rig bust when not, so the art can land species
by species.

Visible: nine contact sheets of the renders and four at the game's sizes, in
`docs/shots/hero-portraits-*`. No game code changed.

### Still open

- The owner's six calls (spike doc §7): how funny (varied faces or uniform
  bobbleheads), whether the look is a gender in text too and whether the name
  lists split by it, species or lineage, foe faces on the strip, bearded dwarf
  women, and a LoRA if templates are not enough.
- Phase 1, the next PR: `Character.look` with its save default, recruit hash,
  creator pick and presets; `Portraits.hero()` with the rig-bust fallback in
  the five places; the stat card and the trait moment reframed as busts; a
  coverage test; and the design bible's art section rewritten.
- Phase 2: twelve templates, 240 × 4 renders, the picks, and
  `assets/portraits/` with its `PROVENANCE.md` and a README row.
- Phase 3, if asked: lineages (dragonborn colours first), foe faces, a face on
  the screens that show only text today, and pack-shipped hero portraits.

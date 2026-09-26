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

**Recommended at first:** twelve class templates, img2img per species ×
look, and a reviewer's pick of four. `Portraits.hero(ch, px)` returns the
painted file when there is one and today's rig bust when not, so the art can
land a people at a time. The owner's calls below replaced the per-key img2img
with a style LoRA.

**The owner's calls, the same day.**

- **Uniform huge heads**, the template's style.
- **The look is only a picture.**
- **Paint by lineage**: 29 peoples × 12 × 2 = 696.
- **Paint the foes too**: 342, one per bestiary id.
- **No bearded women.**
- **Install a trainer and train a LoRA.**
- Along the way: an angelic aasimar (halo, wings, golden eyes), **one backdrop
  gradient for every class**, and "tune down the realistic drawing a bit".

**What that built.**

- **One backdrop.** Every figure is cut out (rembg's BiRefNet, which keeps the
  aasimar's wings where isnet cut them) and laid on one gradient, from the
  UI's `COL_EDGE` brass to `COL_PANEL` brown.
- **Twelve class templates** in a less realistic recipe F: smooth painted
  skin, storybook shapes, the heads still huge.
- **Each template repainted as two other peoples.**
- **A 31-picture training set** from those.
- **A style LoRA, `sorcbobble`**, trained with kohya `sd-scripts` on the 8 GB
  card: UNet only, fp8 base, 1500 steps, 6.5 GB, about 55 minutes
  (`tools/localgen/train_hero_lora.sh`).

**Measured on 12 keys it never saw**, plain txt2img:

- the backdrop comes straight out of the model, 12/12;
- people 11/12 — the goliath reads 2/2 against 1/6 off the templates, and
  the blue dragonborn is blue;
- class 10/12;
- look 12/12, with no bearded women;
- one uniform style.

About 8 of 12 pass everything except a pale smear under the bust, which the
LoRA learnt from its own training cutouts. The next round fixes that from the
data side.

Visible: 21 sheets in `docs/shots/hero-portraits-*`. The last round is
`hero-portraits-lora.jpg`, `-lora-small.png` and `-lora-steps.jpg`. No game
code changed.

### Still open

- LoRA round two before phase 2: clean the bottom edge of every training
  cutout, which is what causes the pale smear; replace the off-colour peoples
  (the blue dragonborn and the chthonic tiefling came out purple off the
  templates, and the chthonic one brown through the LoRA); and add seated and
  full-figure negatives.
- Phase 1, the next PR: `Character.look` with its save default, recruit hash,
  creator pick and presets; `Portraits.hero()` and `Portraits.foe()` with the
  rig-bust fallback in the five places; the stat card and the trait moment
  reframed as busts; a coverage test; and the design bible's art section
  rewritten.
- Phase 2: the 696 hero pictures by lineage through the LoRA, 4 seeds a key,
  a reviewer's pick, cut out onto the backdrop, and `assets/portraits/` with
  its `PROVENANCE.md` and a README row. One PR per people.
- Phase 3: the 342 foe pictures, one per bestiary id, with a faction
  fallback. One PR per faction.
- Later, if asked: a face on the screens that show only text today, and
  pack-shipped portraits for a pack's own species and monsters.
- Whether the name lists split by look: not asked. They stay as they are.

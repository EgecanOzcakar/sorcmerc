# Spike: painted caricature faces for the heroes (#230)

2026-09-26. A feasibility spike, not a feature: **nothing in the shipped game
reads any of this yet.** What exists on the branch is a render tool
(`tools/localgen/gen_hero_portraits.py`), 124 test renders made with it on the
owner's local ComfyUI, nine contact sheets of them and four at game size
(`docs/shots/hero-portraits-*`),
and this document. §4 is what the generator can and cannot do. §5 is the
pipeline and the code seam I recommend. §6 is the order the work lands in, and
§7 is the questions only the owner can answer.

## 1. What #230 asks

> research into creating 2d caricaturized arts for characters of combination
> gender X class X race. these should be cropped right above the
> chest/shoulder, and show distinctive features of their race/class. huge funny
> heads are intended. these are to be used for any 2d platform showing the
> characters, party tab, character tab, turn bar in the combat screen etc. only
> live combat models are to be left 3d meshed models

That is four requirements:

1. **One picture per gender × class × race.**
2. **A bust cropped just above the chest**, showing what marks the people and
   the class.
3. **Caricature, huge heads, funny.**
4. **Every 2D place a hero is drawn uses it.** The 3D figure stays only on the
   live board.

## 2. What the game draws today

There is no 2D picture of a hero anywhere in the repo. Every hero face on
screen is **rendered live from the class's 3D figure** (#165): `scenes/portraits.gd`
points an orthographic camera at the rig inside a `SubViewport`. The one key is
the class carrying the most levels (`Figures3D.model_path_for`,
`scenes/figures3d.gd:142`). Species, lineage and gender play no part. There are
12 hero rigs, one per class, so a dwarf fighter and an elf fighter wear the same
face.

The places that would change:

| Place | Where | Drawn today | Size | Without a model |
|---|---|---|---|---|
| Combat turn strip | `scenes/main.gd:2189` `_build_order_strip` | `Portraits.bust` of the combatant's rig | 40 × `chrome_scale` px | the combatant glyph |
| Combat stat card | `scenes/combat_card.gd:195` `_figure` | `Portraits.figure`, the whole body | 92 × 158 | column not built |
| Party page roster card | `scenes/party/party.gd:771` | `bust` of `HERO_MODELS[class]` | 48 | text only |
| Relations web | `scenes/party/relations_web.gd:371` `_draw_face` | `bust`, circle-clipped | 56 (smaller when benched) | the class glyph |
| Trait moment | `scenes/world/trait_moment.gd:220` | `figure`, the whole body | 300 × 520 | the name's first letter |

Five places, then. Places that show only text or the class glyph today, so a
face there would be new: the profile/character sheet, the creator, level-up,
the hiring rows, the world HUD's party list and the run summary. The issue
names the "character tab", so the profile is the sixth.

The painted portraits the game already has are the 28 counter keepers (`Icons.portrait`,
`assets/generated/<race>-<role>.png`, 160 px) and the packs' six story speakers.
They are SDXL paintings at 512 px with a `PROVENANCE.md`. A hero portrait would
be one more directory of the same thing.

## 3. The matrix, and the field the game does not have

- **Species:** 10 (`data/species.json`). With lineages there are 29 peoples:
  elf ×3, gnome ×2, dragonborn ×10 colours, goliath ×6, tiefling ×3, plus
  five with no lineage.
- **Classes:** 12. The key is the primary class, as the rigs use today.
- **Gender:** **the game has no such field.** There is nothing in `Character`,
  `CharacterSave`, the creator, the recruit roll, the presets or the name lists
  (`data/recruit-names.json` is one list per species, not split).

So the matrix is **10 × 12 × 2 = 240** pictures by species, or **29 × 12 × 2 = 696**
by lineage.

The field the matrix needs is small, and nothing in the rules reads it:

- **`Character.look`**, `"a"` or `"b"`. It names *which picture*, not a
  pronoun. The spike paints `a` masculine and `b` feminine. Whether it also
  means gender in text is question 2 (§7).
- **Old saves:** a missing key reads as `"ab"[hash(id) % 2]`. Every old hero
  gets a stable look and no migration is needed, which is the `*_save.gd`
  idiom.
- **Recruits:** the look is rolled off `hash("look|" + seed)`, **not** the
  recruit's `rng` stream. Taking it from the stream would reroll every later
  pick of every existing pool (`core/recruits.gd` `_roll`).
- **Creator:** one two-way pick beside the name. The presets get one each.
- **Co-op:** `Coop` ships `CharacterSave.to_dict`, so the peer sees the same
  face for free. The field is cosmetic, so lockstep never reads it.
  `test_coop_kits` and `test_mod_api` still run, per the `sorcmerc-compat` skill.
- **Mods:** a pack cannot author a hero, so the mod API does not change. A
  pack's new species or class falls back to the rig bust (§5).

## 4. Can the local generator paint it

The owner's machine has ComfyUI with **SDXL 1.0 base, no LoRA, no ControlNet,
no IP-Adapter**, on an 8 GB RTX 4060 (`~/localgen/README.md`). That is the same
setup every 2D painting in the game came from. One 1024² render at 28 steps
takes **22–24 s**.

### 4.1 Prompt alone: five recipes

`--spread` renders twelve keys that touch every class once, every species at
least once, and both looks six times each. From round C on, each key was
rendered at two seeds. Each render was scored on five things:

- **people**: does it read as its species?
- **class**
- **look**
- **caricature**: a big head or an exaggerated, funny face.
- **clean**: no sculpted head on a plinth, no floating head, no full body.

| Recipe | What changed | Result | Sheet |
|---|---|---|---|
| A | the house portrait tail + "caricature, huge oversized head", "cartoon" kept in the negative | Rembrandt-style oil portraits at normal proportions. Not funny. 3 of 6 look-b came out men (both dwarves, the goliath). | `hero-portraits-A.jpg` |
| B | "big head, chibi proportions", "cartoon" out of the negative | Cleaner, game-like, handsome. Still normal proportions; look-b still 3/6. | `hero-portraits-B.jpg` |
| C | caricature, head size and the look **weighted**, and the look first | **Funny at last, and look-b 12/12.** But heads come loose (busts on plinths, floating heads), the class kit is lost under the proportion words, and elf ears spread to humans, halflings and dragonborn. | `hero-portraits-C.jpg` |
| D | kit first and weighted, "clothes cover the shoulders", ears and sculpture in the negative | Kit, shoulders and the painterly house style are back. The caricature is gone again. A beardless dwarf woman, a goliath and an aasimar read as humans. | `hero-portraits-D.jpg` |
| E | C's weights on the head, D's on the kit, the people weighted too, a shorter frame | **The best prompt-only result.** Class 19/24, people 20/24 (aasimar 0/2, goliath 0/2), look 24/24, clean 22/24, caricature about 9/24. **About 8 of 24 renders pass all five.** | `hero-portraits-E.jpg` |

A stronger description for the two peoples that failed E fixed one of them, and
the fix cost everything else. Over four seeds each, the aasimar read 4/4 by its
halo and glow, but drifted to half-body with hands. The goliath read 2/4 by its
grey skin, and two of the four were full figures in a landscape. None was a
caricature (`hero-portraits-E-peoples.jpg`).

**The finding: SDXL base holds about three of people, class, look, caricature
and framing in one prompt, and the fourth and fifth slip.** Adding words for one
takes attention from the others. That is a limit of the model, not something
the prompt can fix.

### 4.2 A template: img2img off a picked render

Starting from a render that already has the framing and the proportions takes
those two off the prompt's plate (`--init FILE --denoise X`).

- **A gnome druid as the template** for six other classes and peoples
  (`hero-portraits-Et70.jpg`, `Et80.jpg`). Every one came out a true bobblehead
  in one uniform set. But at 0.70 the druid leaked into all of them: antlers,
  green palette, a leaf crown. At 0.80 the dragonborn, orc and warlock read and
  the goliath did not.
- **A wizard as the template** for eight peoples at 0.75 (`hero-portraits-Et75.jpg`).
  **Class 8/8, look 8/8, caricature 8/8, one consistent set.** People 5/8: the
  dragonborn, orc and tiefling (whose head *is* the people), the human and the
  halfling. The aasimar and the goliath came out bearded humans, and the elf's
  ears went under the hat. The template's spectacles are on all eight.

**The finding: a template buys consistency and caricature, and pays for them
in variety.** Denoise is the knob between the two. Peoples whose head is their
silhouette (dragonborn, orc, tiefling, gnome) survive a template. Peoples who
differ by skin, eyes or a glow (aasimar, goliath, drow) do not.

### 4.3 At the size the game draws them

The `-small.png` sheets show every face at 40, 48 and 56 px, circle-clipped the
way the relations web clips them.

- **The people reads at 40 px** by head silhouette: horns, snout, tusks, ears,
  beard, green skin.
- **The class mostly does not.** Only headgear survives: the wizard's hat, the
  fighter's helm, the druid's antlers, the ranger's hood. The class glyph beside
  the name still has to carry the class, as it does today.
- **The big heads read better small than the handsome ones** (compare
  `C-small` with `B-small`): the head fills the circle. That argues for
  requirement 3 on legibility alone.

### 4.4 What the whole set costs

- **GPU time:** 240 keys × 4 seeds × 23 s is **about 6 hours**. At lineage
  level (696 keys) it is about 18 hours.
- **Review:** a human picks one of four for each of 240 keys, with the 2026-09-21
  picture audit's rules (count the fingers, one person per picture).
- **Disk:** at 512 px like every house painting, about 350 KB each, so
  **about 85 MB** in the repo. That is next to `assets/generated/`'s 137 MB.

## 5. Recommendation

### 5.1 The pipeline

1. **Twelve class templates**, one per class. Each is a big-head bust with its
   kit, **bareheaded or with headgear that leaves the ears showing**, and no
   spectacles or other props that would leak. The owner picks them from the
   `--spread` renders or a dedicated run.
2. **img2img each species × look from its class's template** at about 0.75–0.8,
   4 seeds each, with recipe E's words. A reviewer picks one per key.
3. **The peoples a template washes out** (aasimar, goliath, and drow if
   lineages come in) get either their own template per class or a denoise near
   0.85, whichever the picks prefer. This is measured per species on the first
   full run, not guessed here.
4. **If the picks still will not agree**, train a small SDXL LoRA on the
   approved picks. The picks are our own SDXL output, so the provenance stays
   "SDXL base, plus a LoRA trained on our own renders". SDXL LoRA training fits
   in 8 GB, barely (batch 1, gradient checkpointing). It needs kohya or
   OneTrainer installed, and is question 6.

Every picked file keeps ComfyUI's `prompt` tEXt chunk, as in `assets/generated/`.
They go in a new **`assets/portraits/`** directory with its own `PROVENANCE.md`,
plus a row in the README's provenance table. The generator is in the repo this
time (`tools/localgen/`), not only in `~/localgen/`.

### 5.2 The code seam

- **One lookup:** `Portraits.hero(ch, px)`, taking the `Character`. It returns the painted
  `assets/portraits/<species>-<class>-<look>.png` when it exists, and otherwise
  **today's rig bust**. So the art can land key by key and a pack's species
  never draws blank.
- **The five places in §2 call it** instead of `bust()` / `figure()`. The turn
  strip and the combat card have only the combatant. Its resolved `sheet`
  carries neither species nor look, so they find the hero by `c.id`, which
  the adapter sets to `ch.id` (`core/adapter.gd:146`). Foes keep `bust()`
  (question 4).
- **The two whole-figure places** (combat card 92 × 158, trait moment 300 × 520)
  **become bust-framed**. That is a layout change to both, not a swap.
- A texture loads headless where a `SubViewport` does not. `hero()` would
  therefore answer in tests, unlike `bust()`, and a coverage test in the shape
  of `test_figure_models.test_every_class_has_a_figure` can then assert that
  every species × class × look has a file.

### 5.3 What this crosses in the design bible

- **"Hero portraits are rendered from the same rigs"**: they no longer would
  be, and the bible's art section gets rewritten when phase 1 lands.
- **"Art stays 3D", and "the 2D cutout plan is dropped"**: #230 keeps every
  live figure 3D, so this is not the dropped cutout-rig direction. The
  portraits are paintings beside the 3D figures, as the counter keepers are.
- **The house 2D negative rules out "cartoon"**. Recipe A kept it and got no
  caricature. The recipes that worked drop it and keep the rest of the
  painterly tail, so these are a *painterly caricature*: the fourth tail in the
  house list, beside scene, emblem and portrait.

## 6. The order it lands in

1. **This spike.**
2. **Phase 1: the field and the seam.** `Character.look` (save default, recruit
   hash, creator pick, presets), `Portraits.hero()` with the rig-bust fallback,
   the five places, the two layouts, the coverage test (allowed to be
   incomplete until phase 2 fills it), and the bible's art section. It ships
   with no painted file and looks the same as today.
3. **Phase 2: the art.** Twelve templates, then 240 × 4 renders, the picks, and
   `assets/portraits/` with its provenance. Each species can land as its own PR,
   since the fallback covers the rest.
4. **Phase 3, if asked:** lineages (dragonborn colours first, then drow), foe
   faces, a face on the screens that show only text today (the profile's
   header, the hiring rows), and a way for a pack to ship hero portraits for
   its own species.

## 7. Questions for the owner

1. **How funny?** Recipe E is caricatured faces at nearly normal proportions,
   varied and each one different (`hero-portraits-E.jpg`). The template is true
   bobbleheads, one uniform set, where some peoples wash out
   (`hero-portraits-Et75.jpg`). I recommend the template, for "huge funny heads"
   and for how they read at 40 px.
2. **Is the look a gender?** The spike paints two looks. Should `look` stay a
   picture only, or should text (barks, moments) read pronouns from it? I
   recommend a picture only for now; pronouns are their own piece of work. And
   are the name lists split by look?
3. **Species or lineage?** 240 pictures or 696. I recommend species now and
   dragonborn colours first if lineages follow; ten colours of one people is
   the difference a player notices most.
4. **Foes on the turn strip.** Painted heroes beside rig-rendered foes is two
   styles on one strip. Keep that, or paint foe faces per faction later?
5. **Dwarf women: bearded or not?** Unbearded, they read as small human women
   (rounds D and E). 5e allows either.
6. **A LoRA, if the template is not enough?** It means installing a trainer on
   the owner's machine. The provenance note would say it was trained on our own
   picks.

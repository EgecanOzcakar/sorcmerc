# Spike: painted caricature faces for the heroes (#230)

2026-09-26. A feasibility spike, not a feature: **nothing in the shipped game
reads any of this yet.** What exists:

- **The render tool** (`tools/localgen/gen_hero_portraits.py`): prompts, templates,
  the 29 peoples, cutting out onto one backdrop, and the contact sheets.
- **The LoRA training script** (`tools/localgen/train_hero_lora.sh`).
- **About 310 renders** made with them on the owner's local ComfyUI, and a style
  LoRA trained on 31 of them.
- **21 sheets** of those renders in `docs/shots/hero-portraits-*`.
- **This document.**

§4 is what the generator can and cannot do; §4.5 is what happened after the
owner's calls. §5 is the pipeline and the code seam. §6 is the order the work
lands in, and §7 is the owner's calls.

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
  pronoun. The spike paints `a` masculine and `b` feminine. By the owner's
  call it is only a picture (§7).
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

### 4.5 After the owner's calls: one backdrop, a gentler hand, and a style LoRA

The owner picked the template's uniform huge heads (§7) and asked for three
things along the way. Each one changed the pipeline:

**One backdrop for every class.** The owner asked that the background gradient
not change with the class. No prompt gets SDXL to paint the same gradient
twice, so the figure is cut out after rendering and laid on one fixed
gradient: lamplight brass behind the head (`COL_EDGE`), fading to the UI's
panel brown at the corners (`COL_PANEL`, `core/ui_icons.gd`). This is
`gen_hero_portraits.py --matte`. It runs rembg in its own venv
(`~/localgen/matte`), and the ComfyUI `prompt` chunk is kept in each file.

- **isnet** (rembg's general model) takes about 1 s an image, but it cut the
  aasimar's white wings away every time.
- **BiRefNet** kept them on 6 of 8 and kept every halo, at about 15 s an image
  on the CPU. It is the default.

Only picked files need cutting out, so that is about 4 CPU hours for all
1038 pictures. Compare `hero-portraits-aasimar-angelic.jpg` with
`hero-portraits-trainset.jpg`.

**A less realistic hand.** The owner's note on the first class templates was
"tune down the realistic drawing a bit". Recipe F is recipe E with:

- "stylized storybook illustration, simplified shapes, smooth painted skin" in
  the prompt;
- photorealism, skin pores and heavy wrinkles in the negative.

The heads and the kit held, and the skin went from oil-portrait wrinkles to
flat painted planes (`hero-portraits-M3.jpg`). One seed in 24 went wrong in a
new way: a monk holding a baby.

**The class templates, then the peoples.**

- *Stage 1* painted a human of every class off one master template (the gnome
  druid) at 0.80, with the master's antlers and leaves in the negative.
  - Off the wizard master at 0.85, every class read, but the heads came out
    normal size and hats leaked onto the paladin, sorcerer and warlock
    (`hero-portraits-M1.jpg`).
  - Off the gnome master (`M3`), the heads stayed huge and 12/12 classes read.
    4 of 24 leaked the master's horns, and 2 drifted to a full figure.
- *Stage 2* painted each picked class template as two other peoples at 0.75,
  at two seeds each (`hero-portraits-S2.jpg`, 48 renders). The style held
  across all 48. The failures, which are not in the training set:
  - **The goliath again:** 1 of 6 reads.
  - **Beards leaked onto look b** off a bearded template: both dwarf fighters
    and one aasimar cleric.
  - **Two colours drifted to purple:** the blue dragonborn and the ashen
    chthonic tiefling.

  So a template holds the style and the class, and it pulls the face toward
  its own. That is what the LoRA is for.

**The LoRA, `sorcbobble`.**

- **The trainer:** kohya `sd-scripts` v0.9.1, in its own venv at
  `~/localgen/sd-scripts`. It needed three fixes: torch 2.14 cu130 to match
  ComfyUI, bitsandbytes upgraded to 0.50, and numpy pinned below 2 for its
  pinned OpenCV.
- **The recipe** (`tools/localgen/train_hero_lora.sh`): an SDXL LoRA, UNet
  only, dim 16 / alpha 8, fp8 base, cached latents and text-encoder outputs,
  gradient checkpointing, batch 1 at 1024², Adafactor at 1e-4, 1500 steps.
  On the 8 GB card that is 6.5 GB and 2.2 s a step, about 55 minutes.
  ComfyUI has to be stopped while it runs.
- **The training set: 31 picks.** The 12 stage-1 class templates plus 19
  stage-2 peoples, every one cut out onto the backdrop
  (`hero-portraits-trainset.jpg`). Each caption is the trigger word plus the
  plain people, look and class words, so those stay promptable and the style
  is what the trigger learns.
- **The provenance note** is "SDXL base, plus a LoRA trained on our own
  SDXL renders".

**What the LoRA does.** The test was 12 keys that were **not** in the training
set, aimed at stage 2's failures: two goliaths, a blue dragonborn, a chthonic
tiefling and a dwarf woman, among others. Each ran as plain txt2img through
recipe L (the trigger plus the caption words) at 1.0 strength, one seed each,
at each saved step (`hero-portraits-lora-steps.jpg`: 500, 1000 and 1500 from
the top).

- **Steps 500 and 1000 are undertrained.** They paint character-sheet
  duplicates (three blue dragon heads, a turnaround of the orc) and the
  backdrop is not settled yet.
- **Step 1500 is the one**, cut out onto the backdrop in `hero-portraits-lora.jpg`:
  - **The backdrop comes out of the model**, the same brass-to-brown on 12/12,
    before any cutting.
  - **People 11/12.** The goliath reads **2/2**: stone-cracked grey skin on the
    fighter, fire cracks on the cleric, against 1/6 off the templates. The
    blue dragonborn is blue, the silver one is silver, and the aasimar druid
    has its halo, its wings *and* its leaves. The one miss: the chthonic
    tiefling came out brown instead of ashen.
  - **Class 10/12.** The silver dragonborn bard lost its lute, and the forest
    gnome paladin wears a robe.
  - **Look 12/12, and no beards** on the dwarf woman.
  - **One uniform style** on all 12, and at 40 px every people still reads
    (`hero-portraits-lora-small.png`).
  - **Two defects.** The monk drifted to a seated full figure, and **9 of 12
    stand on a pale smear**. The cutout step keeps the smear as part of the
    figure. The LoRA learnt it from the training cutouts, which carried a
    little of the templates' light ground under each bust.

  **About 8 of 12 pass everything but the smear.** That is against about 8 of
  24 for prompt-only recipe E, from one seed each, at txt2img speed, with no
  template per key.

So the pipeline the owner asked for works. The next training round fixes the
smear from the data side:

- clean the bottom edge of every training cutout (cut the busts off square at
  the frame, or erode the alpha there);
- replace the three off-colour peoples with renders that match their
  captions;
- add a few more seated or full-figure negatives.


## 5. Recommendation

### 5.1 The pipeline

As measured in §4.5, not as first guessed:

1. **Twelve class templates**, painted with recipe F off one master template
   at 0.80, and picked one per class (done: `hero-portraits-M3.jpg`).
2. **Each template repainted as other peoples** at 0.75 (stage 2). This is
   only to grow the training set, not to paint the matrix.
3. **The style LoRA `sorcbobble`**, trained on the clean picks from both
   stages (done, round one: 31 images, about 55 minutes).
4. **The matrix itself by txt2img through the LoRA**, recipe L, 4 seeds a key.
   A reviewer picks one per key, and the pick is cut out onto the one
   backdrop (`--matte`). That is 696 heroes and 342 foes, about 26 GPU hours
   at 4 seeds (or 13 at 2), plus about 4 CPU hours of cutting out.
5. **A second training round before phase 2 starts** (§4.5's fixes: clean
   bottom edges, the off-colour peoples replaced). Then again whenever the
   picks show a people or a class the LoRA keeps getting wrong. Every round
   is the same script on a bigger set of picks.

The provenance note is "SDXL base, plus a LoRA trained on our own SDXL
renders". The trainer (`~/localgen/sd-scripts`) and the cutout venv
(`~/localgen/matte`) are on the owner's machine. The recipes that drive them
are in the repo (`tools/localgen/gen_hero_portraits.py`,
`tools/localgen/train_hero_lora.sh`).

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
  the adapter sets to `ch.id` (`core/adapter.gd:146`). Foes go through
  `Portraits.foe(c, px)`, keyed on `c.src_id`, then its faction, then
  today's `bust()` (the owner's call, §7).
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

As changed by the owner's calls (§7):

1. **This spike**, with the style LoRA trained (§4.5).
2. **Phase 1: the field and the seam.** This covers:
   - `Character.look`: the save default, the recruit hash, a creator pick and
     the presets.
   - `Portraits.hero(ch, px)` for heroes and `Portraits.foe(c, px)` for
     foes, both falling back to the rig bust.
   - The five places, and the two whole-figure layouts reframed as busts.
   - A coverage test, allowed to be incomplete until phase 2 fills it.
   - The bible's art section.

   It ships with no painted file and looks the same as today.
3. **Phase 2: the heroes' art**, by lineage: 29 peoples × 12 classes × 2
   looks = **696 pictures**. The LoRA paints them from the prompt, and the
   picks land in `assets/portraits/` with a `PROVENANCE.md`. One PR per people,
   since the fallback covers the rest.
4. **Phase 3: the foes' art**, one bust per bestiary id, **342 pictures**. The
   lookup falls back to the id's faction and then to the rig bust. By
   faction: beast 87, monstrosity 40, dragon 35, humanoid 22, undead 19,
   elemental 16, giant 16, bandit 12, and 17 more under 12 each. One PR per
   faction.
5. **Later, if asked:** a face on the screens that show only text today (the
   profile's header, the hiring rows), and a way for a pack to ship portraits
   for its own species and monsters.

## 7. The owner's calls (2026-09-26)

Asked at the end of the spike and answered the same day. What each one
changed:

1. **Uniform huge heads.** The template's style (`hero-portraits-Et75.jpg`),
   not recipe E's varied faces.
2. **The look is only a picture.** `Character.look` picks the portrait and
   nothing reads it as a pronoun. The name lists stay as they are.
3. **Paint by lineage**: 696 hero pictures, not 240 (§6, phase 2).
4. **Paint the foes as well**: 342 more, one per bestiary id (§6, phase 3).
5. **No bearded women.** Kept in the negative for look `b` (`NEG_LOOK`).
6. **Templates are good, but install the trainer and train.** kohya
   `sd-scripts` is now on the owner's machine, and the LoRA is trained on
   template renders (§4.5).

Asked separately the same day: **the aasimar should be more angelic, with a
halo.** Its description now asks for a floating halo ring, small feathered
wings, golden eyes and luminous skin (`hero-portraits-aasimar-angelic.jpg`).
From the prompt alone that gave the halo and wings 8/8, but also golden-angel
paintings in which the class and the caricature were lost. Off the wizard
template it gave the halo 4/4 and no wings. The LoRA pass (§4.5) is what holds
the halo together with the style.

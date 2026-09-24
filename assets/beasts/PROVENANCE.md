# assets/beasts — AI-generated monster models (Meshy)

**Every model in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". 110 `.glb`
files, each named for a `data/bestiary.json` id, plus the albedo `.jpg` Godot
extracts beside each one on import (109; the doppelganger has none). `scenes/figures3d.gd` asks for
`assets/beasts/<bestiary id>.glb` for every foe before it falls back to the
faction rig in `assets/figures/`, so the directory holds any monster, not only
beasts (the name is historical: the first batch was animals).

## What is recorded

- **Tool:** Meshy. The owner downloaded each batch from Meshy into a gitignored
  folder (`assets/NewlyDownloadedModels/` by default); `tools/import_beasts.py`
  converted it and only its output is committed.
- **Model version, prompts, task ids and credits: not recorded.** Nothing in the
  repository says which Meshy model made these, what each was asked for, or whether
  a given file was the owner's own generation or a Community-feed download.
- **Dates:** only the day each batch landed, below. The generation dates are not
  recorded.
- **Processing (not AI):** `tools/import_beasts.py` — gltfpack's simplifier to ~20k
  triangles, the base-colour texture alone, resampled to 1024 px by
  `tools/shrink_glb.py`. Its `FIXUPS` table maps the downloads' own file names to
  bestiary ids.

| Landed | Commit | Files |
|---|---|---|
| 2026-09-19 | `e0e6f22` | 75 beasts: `ape`, `axe-beak`, `baboon`, `badger`, `bat`, `black-bear`, `blood-hawk`, `boar`, `brown-bear`, `camel`, `cat`, `constrictor-snake`, `crab`, `crocodile`, `deer`, `dire-wolf`, `draft-horse`, `eagle`, `elephant`, `elk`, `flying-snake`, `giant-badger`, `giant-bat`, `giant-boar`, `giant-centipede`, `giant-crab`, `giant-crocodile`, `giant-elk`, `giant-fire-beetle`, `giant-frog`, `giant-hyena`, `giant-lizard`, `giant-octopus`, `giant-rat-diseased`, `giant-rat`, `giant-scorpion`, `giant-sea-horse`, `giant-shark`, `giant-spider`, `giant-toad`, `giant-wasp`, `giant-wolf-spider`, `goat`, `hawk`, `hunter-shark`, `hyena`, `jackal`, `killer-whale`, `lion`, `lizard`, `mammoth`, `mastiff`, `mule`, `octopus`, `owl`, `panther`, `plesiosaurus`, `poisonous-snake`, `polar-bear`, `pony`, `quipper`, `rat`, `raven`, `reef-shark`, `rhinoceros`, `riding-horse`, `saber-toothed-tiger`, `scorpion`, `spider`, `tiger`, `triceratops`, `tyrannosaurus-rex`, `vulture`, `warhorse`, `wolf` |
| 2026-09-22 | `c113a93` | 34 for giant, gnoll, monstrosity and orc: `ankheg`, `basilisk`, `bulette`, `cockatrice`, `darkmantle`, `death-dog`, `drider`, `ettercap`, `ettin`, `frost-giant`, `gnoll-archer`, `gnoll`, `gorgon`, `griffon`, `harpy`, `hill-giant-archer`, `hill-giant`, `hippogriff`, `hydra`, `manticore`, `medusa`, `merrow`, `mimic`, `minotaur`, `ogre`, `oni`, `orc`, `owlbear`, `phase-spider`, `roper`, `rust-monster`, `troll`, `winter-wolf`, `worg` |
| 2026-09-23 | `dda308d` | `doppelganger` — the 2026-09-22 download had no texture; imported with `--untextured` (a flat grey material) |

`orc.glb` is the download named "orcarcher", standing in for the one orc the
bestiary has (`FIXUPS`).

Licence: Meshy output. Commercial rights depend on the Meshy plan the owner generated
under (a Community download is CC0 under Meshy ToS §3.3); see the Meshy ToS before
shipping.

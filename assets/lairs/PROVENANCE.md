# assets/lairs — lair dioramas (Meshy: one Community download, two generated)

**Every model in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Three
static `.glb` dioramas, no rig or animation (lairs are scenery), each with the
textures Godot extracted from it on import.

**Wired, but not drawn by default.** `scenes/world/lairs3d.gd` `MODELS` names all
three, and `Lairs3D._build()` draws whichever source `Lairs3D.source` prefers,
falling back to the other. The default is `"kit"` (`scenes/world/lair_kit.gd`,
primitives, not AI; `tests/test_lair_kit.gd` pins the default), and the kit covers
all five lair ids, so these three are only drawn with `source = "glb"` and in
`tests/shot_lair_kit.gd`'s comparison. They still ship in the export, so they still
belong in the disclosure.

## goblin-warren.glb — Meshy Community feed, CC0

Source: Meshy Community feed (meshy.ai/discover), downloaded by the user
directly through the web UI — not generated via our API. Filename as
downloaded: "Meshy AI Goblin Camp Fortifica[tion]_0912210319_texture.glb".
License: CC0 1.0 (Meshy ToS §3.3 — anything published to the Community page
is CC0, no attribution required). Landed 2026-09-13 (commit `665db95`). Its author,
Meshy model and prompt are not recorded.

## giant-hold.glb / dragon-cave.glb — generated

- **Tool:** Meshy text-to-3D, through the API from the owner's
  `~/kitbashforge/run_lairs.py` (not in this repository). Chain: preview -> refine
  (2k, no PBR) -> remesh (80k tris), the same as the settlement dioramas. 20 credits
  each.
- **Date:** generated and committed 2026-09-13 (commit `b9deae8`, "generated, 40
  credits").
- **Model version, task ids and prompts: not recorded.** The Community feed was
  searched first and had nothing suitable for either.
- Licence: Meshy output from the owner's account. Commercial rights require a paid
  Meshy plan (free-tier output is CC BY 4.0 with Meshy retaining ownership; Meshy ToS
  §3.2).

## sunken-ruins / zombie-graveyard — no model here, and none needed

These two were deferred on the theory they would turn up on Meshy's Community
feed (kitbashforge/NEXT_BATCH.md). `Lairs3D.MODELS` still names paths for them
that do not exist.

They are built by `scenes/world/lair_kit.gd` instead: primitives assembled in code,
no asset file, and therefore **not AI-generated** — nothing about these two carries
the README's Steam AI-content disclosure obligation. If a GLB is ever generated for
either, dropping the file in beside the other three is enough: `Lairs3D._build()`
prefers whichever source `Lairs3D.source` names and falls back to the other, so no
registry edit is needed.

On the evidence of `tests/shot_lair_kit.gd` the generated models win over the kit
on all three, which is the opposite of the settlement result and not a surprise: a
cave and a rock pile are the fused organic volumes text-to-3D is good at.

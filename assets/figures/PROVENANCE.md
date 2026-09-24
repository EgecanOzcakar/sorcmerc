# assets/figures — AI-generated 3D figures (Meshy)

**Everything in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Twenty
`.glb` files, each with the texture Godot extracted from it on import
(`*_texture_0.jpg`, or `*_0.jpg` for the three unrigged ones). The README's
provenance table lists every other asset directory and what made it.

`scenes/figures3d.gd` draws them on the combat board: `HERO_MODELS` by class id,
`FOE_MODELS` by bestiary faction. The overworld's bands borrow the same tables
(`scenes/world/party3d.gd`), and portraits are rendered from the same rigs
(`scenes/portraits.gd`).

## The goblin — the one fully recorded

| File | Tool | Model | Date | Task id | Credits |
|---|---|---|---|---|---|
| `goblin_std.glb`  | Meshy text-to-3D | `meshy-6`      | 2026-09-12 | `01a0964e-9a49-767d-ace1-98551c2f81ba` | ~22 |
| `goblin_lite.glb` | Meshy text-to-3D | `meshy-6-lite` | 2026-09-12 | `01a0964e-9816-778b-b8ac-c15d7278c228` | ~22 |

Prompt (both): "a goblin archer, wiry green-skinned humanoid with long pointed ears, dark
hood and wrapped cloth armour, quiver on the back, a short recurve bow held at the side,
standing upright in a neutral A-pose with arms slightly out, full body, semi-realistic
fantasy, muted earthy palette". Settings: `pose_mode: a-pose`, `enable_pbr: false`,
`texture_resolution: 2k`, `alpha_thumbnail: true`, `target_formats: [glb]`.

`goblin_std` and `goblin_lite` were the spike's two candidates. No script loads
either any more; the board draws `goblin_idle.glb`, made from `goblin_std`:

**`goblin_idle.glb`** — Meshy chain on goblin_std (task 01a0964e-9a49-767d-ace1-98551c2f81ba):
remesh v1 50k tris (01a0965e-6438-7561-932d-45b707248d25) → rig 1.2 m
(01a0965f-ea5b-74d8-87f0-1468cc99136b, 0 credits) → animation "Idle" action 0
(01a09663-a7e2-73b1-9dfe-e9a8c629a8cc, 3 credits). Clip `Armature|Idle|baselayer`,
4.03 s. Rigged base + walking/running GLBs kept in `~/kitbashforge/meshy_out`, outside
this repository.

## The other seventeen rigs

All generated 2026-09-12 with the same Meshy chain as the goblin and the troops:
text-to-3D preview -> refine (2k, no PBR) -> remesh (50k tris) -> rig (1.2 m) -> the
"Idle" animation. The batch ran from the owner's `~/kitbashforge/` scripts, which are
**not in this repository**.

**Prompts, model version, task ids and credits: not recorded** for any of these
seventeen. The goblin's prompt above is the only figure prompt that survives, which
is where the design bible's "semi-realistic fantasy, muted earthy palette" comes
from.

| File | Draws | Landed | Notes |
|---|---|---|---|
| `fighter_idle.glb` | fighter | 2026-09-12 `e50efd3` | |
| `rogue_idle.glb` | rogue | 2026-09-12 `e50efd3` | |
| `cleric_idle.glb` | cleric | 2026-09-12 `e50efd3` | |
| `bandit_idle.glb` | bandit foes | 2026-09-12 `e50efd3` | |
| `soldier_idle.glb` | soldier foes | 2026-09-12 `e50efd3` | |
| `cultist_idle.glb` | cultist foes | 2026-09-12 `e50efd3` | |
| `undead_idle.glb` | undead foes | 2026-09-12 `e50efd3` | |
| `barbarian_idle.glb` | barbarian | 2026-09-12 `1239247` | |
| `bard_idle.glb` | bard | 2026-09-12 `1239247` | |
| `druid_idle.glb` | druid | 2026-09-12 `1239247` | |
| `monk_idle.glb` | monk | 2026-09-12 `1239247` | |
| `paladin_idle.glb` | paladin | 2026-09-12 `1239247` | |
| `ranger_idle.glb` | ranger | 2026-09-12 `1239247` | **No rig, no idle:** the bow tripped Meshy's pose estimator, so it is the static A-pose mesh |
| `sorcerer_idle.glb` | sorcerer | 2026-09-12 `1239247` | |
| `warlock_idle.glb` | warlock | 2026-09-12 `1239247` | |
| `wizard_idle.glb` | wizard | 2026-09-12 `1239247` | |
| `kobold_idle.glb` | kobold foes | 2026-09-12 `1239247` | The second generation: the first came back as a horned demon; the commit describes the replacement as "small reptile, no horns/wings" (its prompt is not recorded) |

The textures were shrunk to 1024 px and re-encoded as JPEG on 2026-09-13
(`9702e31`, `tools/shrink_glb.py`); that is a resample, not a regeneration.

## Licence

Meshy output. Commercial rights require a paid Meshy plan; free-tier output is
CC BY 4.0 with Meshy retaining ownership. See Meshy ToS §3.2 before shipping.

Meshy deletes API assets after 3 days; these local copies are the only durable ones.

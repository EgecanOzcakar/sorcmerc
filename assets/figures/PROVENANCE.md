# assets/figures — AI-generated 3D figures

**Everything in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's asset policy. It is kept apart from
`assets/lpc/`, `assets/generated/`, `assets/world/` and `assets/audio/`, none of which
are AI-generated, so provenance stays decidable per path.

| File | Tool | Model | Date | Task id | Credits |
|---|---|---|---|---|---|
| `goblin_std.glb`  | Meshy text-to-3D | `meshy-6`      | 2026-09-12 | `01a0964e-9a49-767d-ace1-98551c2f81ba` | ~22 |
| `goblin_lite.glb` | Meshy text-to-3D | `meshy-6-lite` | 2026-09-12 | `01a0964e-9816-778b-b8ac-c15d7278c228` | ~22 |

Prompt (both): "a goblin archer, wiry green-skinned humanoid with long pointed ears, dark
hood and wrapped cloth armour, quiver on the back, a short recurve bow held at the side,
standing upright in a neutral A-pose with arms slightly out, full body, semi-realistic
fantasy, muted earthy palette". Settings: `pose_mode: a-pose`, `enable_pbr: false`,
`texture_resolution: 2k`, `alpha_thumbnail: true`, `target_formats: [glb]`.

Licence: Meshy output. Commercial rights require a paid Meshy plan; free-tier output is
CC BY 4.0 with Meshy retaining ownership. See Meshy ToS §3.2 before shipping.

Meshy deletes API assets after 3 days; these local copies are the only durable ones.

## goblin_idle.glb
Meshy chain on goblin_std (task 01a0964e-9a49-767d-ace1-98551c2f81ba): remesh v1 50k tris
(01a0965e-6438-7561-932d-45b707248d25) → rig 1.2 m (01a0965f-ea5b-74d8-87f0-1468cc99136b, 0 credits)
→ animation "Idle" action 0 (01a09663-a7e2-73b1-9dfe-e9a8c629a8cc, 3 credits). Clip
`Armature|Idle|baselayer`, 4.03 s. Rigged base + walking/running GLBs kept in ~/kitbashforge/meshy_out.
goblin_std_0.jpg / goblin_lite_0.jpg: textures Godot extracted from the GLBs on import.

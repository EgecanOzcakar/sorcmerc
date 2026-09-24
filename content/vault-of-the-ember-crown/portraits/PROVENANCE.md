# content/vault-of-the-ember-crown/portraits — AI-generated story portraits (SDXL)

**All three portraits here are AI-generated** and carry the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". The story
card draws a cast member's face from `portraits/<speaker id>.png`
(`scenes/world/story_card.gd`).

Made exactly as the 237 recorded paintings in `assets/generated/` were, and that
file's `PROVENANCE.md` says how to read the record back out of a PNG:

- **Tool:** ComfyUI, run locally.
- **Model:** `sd_xl_base_1.0.safetensors` (SDXL 1.0 base), no refiner, no LoRA.
- **Settings:** 1024 × 1024 latent, KSampler `dpmpp_2m` / `karras`, 28 steps, CFG 7.0,
  denoise 1.0, then a Lanczos downscale to 512 × 512.
- **Prompt:** the subject below, then the portrait tail
  `, painterly digital art, 1:1 bust portrait, fantasy RPG character portrait`.
- **Negative:** as named below; the lists are in `assets/generated/PROVENANCE.md`.

All of it is read from the `prompt` tEXt chunk ComfyUI wrote into each file. The
generator script (`~/localgen/gen_sorcmerc_scenes.py`, per commit `b2ffa48`) is not in
this repository.
*Landed* is the commit that last changed the file.

| File | Landed | Seed | Style | Neg | Subject (the prompt before the style tail) |
|---|---|---|---|---|---|
| `durn.png` | 2026-09-21 `7b60b59` | 12813 | P | N9 | Durn Stonewake, a grim dwarven column-captain, short and broad with a thick grey braided beard and small round human-shaped ears, dented plate, a scarred face and a captain's baton, banners and cold mountain road behind |
| `hale.png` | 2026-09-16 `b2ffa48` | 11709 | P | N4 | Warden Hale, a weathered human man warden of a mountain gate fort, worn mail and a heavy cloak, ink on his fingers, snow on the battlements behind |
| `vessa.png` | 2026-09-16 `b2ffa48` | 11712 | P | N4 | Vessa of the Nine Coals, a striking woman with ember-red eyes and dark robes stitched with nine glowing coals, speaker for crown-seekers, a vault door glowing behind |

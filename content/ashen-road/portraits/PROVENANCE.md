# content/ashen-road/portraits — AI-generated story portraits (SDXL)

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
| `maera.png` | 2026-09-21 `7b60b59` | 12611 | P | N3 | Maera Vulk, a stern middle-aged human woman reeve of a burned frontier town, plain wool and a chain of office, ledger under her arm, tired sharp eyes, ash on the wind behind her |
| `oss.png` | 2026-09-16 `b2ffa48` | 11703 | P | N4 | Oss Tallow, a wiry young goblin in patched leathers who ran from a burning warren, quick eyes, a knife at the belt, defiant, firelit ruins behind |
| `sigrun.png` | 2026-09-16 `b2ffa48` | 11706 | P | N4 | Sigrun Barrowkeep, an ancient grey-haired human woman keeper of a barrow of kings, heavy furs and a great iron key, unbending, a stone doorway behind her |

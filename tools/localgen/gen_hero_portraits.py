#!/usr/bin/env python3
"""The #230 spike's portrait renders: a caricatured, big-headed bust of a hero,
one per species x class x look, through the local ComfyUI API (SDXL base, no
LoRA — the only model on the owner's machine, `~/localgen/README.md`).

This is a research tool, not the production pipeline: it renders a *spread*
that touches every species, every class and both looks once (`--spread`), or
the named keys (`--only human-fighter-a,orc-bard-b`), at one or more seeds,
under one of the prompt recipes below, so a reviewer can judge whether one
style holds across the whole matrix before 240 of them are painted.
`--sheet DIR` then lays the renders in DIR out as a contact sheet and again at
the sizes the game draws a face (40, 48 and 56 px), because a face that reads
at 512 and not at 40 is useless on the turn strip.

Outputs land in ComfyUI's own output folder as
`hero_<recipe>_<species>-<class>-<look>~<seed>_00001_.png`, with ComfyUI's
`prompt` tEXt chunk inside — the provenance record, as for `assets/generated/`.
Sequential: one GPU, 8 GB, each job queued after the last one finishes.

    python3 tools/localgen/gen_hero_portraits.py --spread --recipe A
    python3 tools/localgen/gen_hero_portraits.py --only dwarf-cleric-b --seeds 4
    python3 tools/localgen/gen_hero_portraits.py --sheet ~/localgen/ComfyUI/output --out docs/shots
"""
import argparse
import json
import os
import re
import time
import urllib.request

HOST = "http://127.0.0.1:8188"

# What makes each people read as itself at 40 px: the silhouette of the head
# first (ears, horns, snout, tusks, beard), colour second. Dragonborn and
# goliath lineages differ by colour; the spread paints the default.
SPECIES = {
    "human": "a human",
    "dwarf": "a stout dwarf with a broad nose and a thick braided beard",
    "elf": "an elf with very long pointed ears and sharp fine features",
    "gnome": "a tiny gnome with an enormous nose, huge bright eyes and wild hair",
    "halfling": "a halfling with a round cheerful face, rosy cheeks and curly hair",
    "aasimar": "an angelic aasimar with (a glowing golden halo ring floating above the head:1.4), (small white feathered angel wings rising behind the shoulders:1.2), radiant golden eyes and softly luminous skin",
    "dragonborn": "a dragonborn, a dragon-headed humanoid with a scaled snout, bronze scales and small back-swept horns, no hair",
    "goliath": "a goliath, a towering bald giant-kin with (slate grey skin:1.4) like weathered stone, dark stone-like markings on the face",
    "orc": "an orc with grey-green skin, a heavy jaw and two big tusks",
    "tiefling": "a tiefling with red skin, two large curling horns and solid gold eyes",
}
# The owner's call (spike doc §7): paint by lineage. A lineage's people is
# written `<species>_<lineage>` (the game's own lineage id after the
# underscore), 24 of them beside the five species that have none: 29 peoples.
_DRAGON = "a dragonborn, a dragon-headed humanoid with a scaled snout, (%s scales:1.3), small back-swept horns, no hair"
_GOLIATH = "a goliath, a towering bald giant-kin with (%s:1.4), dark stone-like markings on the face"
LINEAGES = {
    "elf_drow": "a drow elf with (dark grey-purple skin:1.3), stark white hair and very long pointed ears",
    "elf_high-elf": "a high elf with very long pointed ears, sharp fine features, pale skin and silver-blond hair",
    "elf_wood-elf": "a wood elf with very long pointed ears, tanned freckled skin and leaf-brown hair",
    "gnome_forest": "a tiny forest gnome with an enormous nose, huge bright eyes and wild mossy-brown hair",
    "gnome_rock": "a tiny rock gnome with an enormous nose, huge bright eyes, wild hair and brass goggles on the brow",
    "goliath_cloud": _GOLIATH % "pale blue-grey skin, wisps of cloud about the shoulders",
    "goliath_fire": _GOLIATH % "dark grey skin with glowing ember-red cracks",
    "goliath_frost": _GOLIATH % "icy blue-white skin, frost on the brows",
    "goliath_hill": _GOLIATH % "ruddy brown-grey skin, a heavy brow",
    "goliath_stone": _GOLIATH % "slate grey skin like weathered stone",
    "goliath_storm": _GOLIATH % "dark grey skin, crackling blue sparks",
    "tiefling_abyssal": "a tiefling with (deep purple skin:1.3), jagged black horns and glowing yellow eyes",
    "tiefling_chthonic": "a tiefling with (ashen grey skin:1.3), black backswept horns and pale silver eyes",
    "tiefling_infernal": "a tiefling with (red skin:1.3), two large curling ram horns and solid gold eyes",
}
for _c in ("black", "blue", "green", "red", "white"):
    LINEAGES["dragonborn_chromatic-" + _c] = _DRAGON % _c
for _c in ("brass", "bronze", "copper", "gold", "silver"):
    LINEAGES["dragonborn_metallic-" + _c] = _DRAGON % ("gleaming metallic " + _c)
PEOPLES = [sp for sp in SPECIES if not any(k.startswith(sp + "_") for k in LINEAGES)] + sorted(LINEAGES)

# ponytail: two looks, "a" and "b", painted masculine and feminine. The game has
# no gender field (spike doc §3); the key names a look, not a pronoun.
LOOKS = {"a": "man", "b": "woman"}
# The dwarf's beard is the dwarf; a bearded dwarf woman is 5e canon, but the
# spike paints the look with braids instead and asks the owner (§7).
SPECIES_LOOK = {("dwarf", "b"): "a stout dwarf with a broad nose and thick braided hair"}

CLASSES = {
    "barbarian": "a barbarian in a shaggy fur mantle, bare scarred shoulders, war paint across the face",
    "bard": "a bard in a feathered cap and a bright slashed doublet, a lute neck over one shoulder",
    "cleric": "a cleric in white vestments over chain mail, a big holy-symbol pendant on the chest",
    "druid": "a druid wearing a crown of antlers and leaves, a rough hide cloak, moss and feathers",
    "fighter": "a fighter in battered steel plate, heavy pauldrons and a gorget, an open-faced helm",
    "monk": "a monk with a shaved head, a simple wrapped ochre robe, prayer beads, hands wrapped in cloth",
    "paladin": "a paladin in shining ornate plate with a blue tabard and a sunburst crest",
    "ranger": "a ranger in a deep green hood and cloak, a quiver strap across the chest",
    "rogue": "a rogue with a (black leather hood:1.2) up over the head, a dark mask pulled down under the chin, a sly grin",
    "sorcerer": "a sorcerer with crackling violet sparks around the eyes, a high ornate collar",
    "warlock": "a warlock with glowing purple eldritch sigils on the cheeks, a dark high-collared coat",
    "wizard": "a wizard in a tall pointed hat and a star-embroidered blue robe, small spectacles",
}

# One framing for every face, so 240 of them line up on the strip: facing us,
# head filling the top two-thirds, cut just below the shoulders, plain backdrop.
FRAME = ("head and shoulders bust cropped just below the shoulders, facing the viewer, "
         "centered, the head fills the upper two thirds of the picture, plain dark warm backdrop")
RECIPES = {
    # A: the house painterly tail with the proportions pushed. Keeps "cartoon"
    # in the negative, as every house painting does.
    "A": ("painterly caricature portrait of {who}, {kit}. Huge oversized head on a small body, "
          "exaggerated features, comical expression, " + FRAME + ", painterly fantasy illustration, "
          "oil painting brushwork, rich but muted palette, soft rim light, detailed, 1:1"),
    # B: the same, said the way SDXL's training captions say it — "big head",
    # "chibi proportions" — and without "cartoon" in the negative.
    "B": ("fantasy caricature of {who}, {kit}, big head, chibi proportions, exaggerated funny face, "
          + FRAME + ", painterly digital painting, oil brushwork, rich muted palette, soft rim light, 1:1"),
    # C: round one's B came out handsome, not funny, and at normal proportions
    # (spike doc §4.1), and three of six "woman" looks came out men. So the
    # proportion and the look are weighted, and the look leads.
    "C": ("(caricature:1.3) of a ({sex}:1.3) {who}, {kit}. (huge oversized head:1.4) on (tiny narrow "
          "shoulders:1.2), bobblehead proportions, exaggerated funny face, big expressive eyes, "
          + FRAME + ", painterly digital painting, oil brushwork, rich muted palette, soft rim light, 1:1"),
    # D: C's heads were right but came loose — sculpted heads on plinths, the
    # class kit lost under the proportion words, and elf ears on everyone
    # (§4.1). So the kit leads and is weighted, the shoulders are dressed, and
    # the ears and the sculpture go in the negative.
    "D": ("painted caricature of a ({sex}:1.3) {who}, ({kit}:1.2), the clothes cover the shoulders. "
          "(huge oversized head:1.3) on narrow shoulders, bobblehead proportions, funny exaggerated face, "
          + FRAME + ", painterly digital painting, oil brushwork, rich muted palette, soft rim light, 1:1"),
    # E: D got the kit, the shoulders and the house style back and lost C's
    # proportions, and lost the people where the head is not its silhouette
    # (a dwarf woman, a goliath, an aasimar; §4.1). C's weights on the head,
    # D's on the kit, the people weighted too, and a shorter frame so the
    # words that matter are fewer.
    "E": ("(caricature:1.3) of a ({sex}:1.3) ({who}:1.2), ({kit}:1.2). (huge oversized head:1.4), "
          "small body, funny exaggerated face, chest-up bust facing the viewer, plain backdrop, "
          "painterly digital painting, oil brushwork, rich muted palette, soft rim light, 1:1"),
}
NEG_BASE = ("blurry, low quality, deformed, bad anatomy, text, watermark, signature, out of frame, "
            "two people, crowd, multiple characters, character sheet, collage, grid, extra fingers, "
            "hands, modern clothing, gun, monochrome, sketch, lineart, frame, border, picture frame, "
            "flat colours, cel shading, vector, glossy render, 3d render, plastic, full body, legs")
NEG = {"A": NEG_BASE + ", cartoon, anime", "B": NEG_BASE + ", anime",
       "C": NEG_BASE + ", anime, realistic proportions, photo",
       "D": NEG_BASE + ", anime, realistic proportions, photo, sculpture, statue, bust statue, clay, "
            "figurine, pedestal, plinth, floating head, severed head, bare neck"}
NEG["E"] = NEG["D"]
# F: the owner on stage 1's class templates (2026-09-26): "tune down the
# realistic drawing a bit". E's words, with the rendering pushed toward a
# storybook painting: simpler shapes, smooth painted skin, no pores or
# photographic wrinkles.
RECIPES["F"] = ("(caricature:1.3) of a ({sex}:1.3) ({who}:1.2), ({kit}:1.2). (huge oversized head:1.4), "
                "small body, funny exaggerated face, chest-up bust facing the viewer, plain backdrop, "
                "(stylized storybook illustration:1.2), simplified shapes, smooth painted skin, soft painterly "
                "shading, oil brushwork, rich muted palette, soft rim light, 1:1")
NEG["F"] = NEG["D"] + (", (photorealistic:1.3), realistic, hyperrealism, detailed skin texture, skin pores, "
                       "heavy wrinkles, photograph")
# L: txt2img through the trained style LoRA (§4.5). The words are the
# captions' words, so the style comes from the trigger and the prompt only has
# to say who and what.
RECIPES["L"] = "sorcbobble, a ({sex}:1.2) ({who}:1.2), ({kit}:1.1)"
NEG["L"] = NEG["D"]
SEX = {"a": "male", "b": "female"}
# A look-b dwarf came out bearded both times in round one: say it twice.
NEG_LOOK = {("dwarf", "b"): ", beard, moustache", ("goliath", "b"): ", beard"}
# Round two gave pointed ears to every people that has none (§4.1).
NEG_SPECIES = {s: ", pointed ears, elf ears" for s in
               ("human", "dwarf", "halfling", "aasimar", "dragonborn", "goliath")}


def key(species: str, cls: str, look: str) -> str:
    return "%s-%s-%s" % (species, cls, look)


TRIGGER = "sorcbobble"


def plain(text: str) -> str:
    """A prompt fragment without its (weights:1.3)."""
    return re.sub(r"\(([^()]*?):[0-9.]+\)", r"\1", text)


def prompt_who(species: str, look: str) -> str:
    base = LINEAGES.get(species) or SPECIES[species]
    return SPECIES_LOOK.get((species, look), base) + " " + LOOKS[look]


def prompt(recipe: str, species: str, cls: str, look: str) -> str:
    who = prompt_who(species, look)
    return RECIPES[recipe].format(who=who, kit=CLASSES[cls], sex=SEX[look])


def spread() -> list:
    """Every class once, every species at least once, the looks alternating."""
    sp = list(SPECIES)
    return [(sp[i % len(sp)], c, "ab"[i % 2]) for i, c in enumerate(CLASSES)]


def workflow(text: str, neg: str, prefix: str, seed: int, init="", denoise=1.0, lora="", lora_w=1.0) -> dict:
    g = {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": text, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": neg, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler", "inputs": {
            "seed": seed, "steps": 28, "cfg": 7.0, "sampler_name": "dpmpp_2m", "scheduler": "karras",
            "denoise": denoise, "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0],
        }},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["8", 0]}},
    }
    if init:
        # img2img off a template render (a file in ComfyUI's input folder): the
        # template holds the framing and the proportions, so the prompt's words
        # go on the people, the look and the kit (§4.2).
        g["10"] = {"class_type": "LoadImage", "inputs": {"image": init}}
        g["11"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["10", 0], "vae": ["4", 2]}}
        g["3"]["inputs"]["latent_image"] = ["11", 0]
    if lora:
        # A UNet-only LoRA (train_hero_lora.sh), so it loads on the model alone.
        g["12"] = {"class_type": "LoraLoaderModelOnly",
                   "inputs": {"model": ["4", 0], "lora_name": lora, "strength_model": lora_w}}
        g["3"]["inputs"]["model"] = ["12", 0]
    return g


def run(text: str, neg: str, prefix: str, seed: int, init="", denoise=1.0, lora="", lora_w=1.0,
        timeout=300) -> None:
    body = json.dumps({"prompt": workflow(text, neg, prefix, seed, init, denoise, lora, lora_w)}).encode()
    req = urllib.request.Request(HOST + "/prompt", data=body, headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=15).read())
    if resp.get("node_errors"):
        raise RuntimeError("%s: %s" % (prefix, resp["node_errors"]))
    pid, start = resp["prompt_id"], time.time()
    while time.time() - start < timeout:
        with urllib.request.urlopen("%s/history/%s" % (HOST, pid), timeout=15) as r:
            if pid in json.loads(r.read()):
                return
        time.sleep(2)
    raise TimeoutError(prefix)


# The owner's call (2026-09-26): one backdrop behind every face, whatever the
# class. SDXL never paints the same gradient twice, so the figure is cut out
# (rembg's BiRefNet, which keeps the aasimar's wings where isnet cut them)
# and laid on this one: lamplight brass behind the head fading to the UI's
# panel colour at the corners (core/ui_icons.gd COL_EDGE -> COL_PANEL).
BACK_IN, BACK_OUT = (0x4a, 0x3d, 0x2c), (0x22, 0x1c, 0x16)


def backdrop(size: int):
    from PIL import Image
    import numpy as np
    y, x = np.mgrid[0:size, 0:size] / (size - 1)
    # centred on the head, which sits in the upper middle of every bust
    t = np.clip(np.hypot(x - 0.5, (y - 0.4) * 0.9) / 0.75, 0, 1)[..., None]
    rgb = np.array(BACK_IN) * (1 - t) + np.array(BACK_OUT) * t
    return Image.fromarray(rgb.astype("uint8"), "RGB")


def matte(src: str, out: str) -> None:
    """Every hero_* render in src, cut out and laid on the one backdrop, saved
    under the same name in out with the render's own prompt chunk kept. Run it
    with the rembg venv's python (~/localgen/matte/.venv)."""
    from PIL import Image, PngImagePlugin
    from rembg import new_session, remove
    session = new_session(os.environ.get("MATTE_MODEL", "birefnet-general"))
    os.makedirs(out, exist_ok=True)
    back = None
    for f in sorted(f for f in os.listdir(src) if f.startswith("hero_") and f.endswith(".png")):
        im = Image.open(os.path.join(src, f))
        meta = PngImagePlugin.PngInfo()
        for k, v in im.text.items():
            meta.add_text(k, v)
        if back is None or back.size != im.size:
            back = backdrop(im.size[0])
        cut = remove(im.convert("RGB"), session=session)
        pic = back.copy()
        pic.paste(cut, (0, 0), cut)
        pic.save(os.path.join(out, f), pnginfo=meta)
        # The LoRA's caption (§4.5): the trigger word and the plain words for
        # people, look and class, so those stay promptable and the rest of
        # what the picture has in common — the style — goes to the trigger.
        sp, cl, lk = f.split("_", 2)[2].split("~")[0].rsplit("-", 2)
        with open(os.path.join(out, f[:-4] + ".txt"), "w") as t:
            t.write("%s, a %s %s, %s" % (TRIGGER, SEX[lk], plain(prompt_who(sp, lk)), plain(CLASSES[cl])))
        print("matte", f, flush=True)


def sheet(src: str, out: str) -> None:
    """A contact sheet of every hero_* render in src, and the same faces at the
    sizes the game draws them, circle-masked the way the relations web does."""
    from PIL import Image, ImageDraw
    files = sorted(f for f in os.listdir(src) if f.startswith("hero_") and f.endswith(".png"))
    for recipe in sorted({f.split("_")[1] for f in files}):
        group = [f for f in files if f.split("_")[1] == recipe]
        cols, cell = 6, 256
        rows = (len(group) + cols - 1) // cols
        big = Image.new("RGB", (cols * cell, rows * cell), (20, 16, 12))
        # Small sizes: one row per size, each face at 40, 48, 56 px.
        sizes = (40, 48, 56)
        small = Image.new("RGB", (len(group) * 64 + 8, len(sizes) * 64 + 8), (28, 22, 16))
        for i, f in enumerate(group):
            im = Image.open(os.path.join(src, f)).convert("RGB")
            big.paste(im.resize((cell, cell), Image.LANCZOS), ((i % cols) * cell, (i // cols) * cell))
            for r, px in enumerate(sizes):
                face = im.resize((px, px), Image.LANCZOS)
                mask = Image.new("L", (px, px), 0)
                ImageDraw.Draw(mask).ellipse((0, 0, px - 1, px - 1), fill=255)
                small.paste(face, (8 + i * 64 + (56 - px) // 2, 8 + r * 64 + (56 - px) // 2), mask)
        big.save(os.path.join(out, "hero-portraits-%s.jpg" % recipe), quality=85)
        small.save(os.path.join(out, "hero-portraits-%s-small.png" % recipe))
        print("sheet", recipe, len(group), "renders")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--recipe", default="A", choices=sorted(RECIPES))
    ap.add_argument("--spread", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--seed0", type=int, default=2300)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--matte", default="", help="cut out every render in this folder onto the backdrop, into --out")
    ap.add_argument("--out", default=".")
    ap.add_argument("--init", default="", help="a template render in ComfyUI/input for img2img")
    ap.add_argument("--denoise", type=float, default=1.0)
    ap.add_argument("--lora", default="", help="a LoRA in ComfyUI/models/loras, e.g. sorcbobble.safetensors")
    ap.add_argument("--lora-w", type=float, default=1.0)
    ap.add_argument("--neg-extra", default="", help="appended to the negative, e.g. a template's props")
    ap.add_argument("--tag", default="", help="names the run in the output file instead of the recipe")
    a = ap.parse_args()
    if a.matte:
        matte(os.path.expanduser(a.matte), a.out)
        raise SystemExit
    if a.sheet:
        sheet(os.path.expanduser(a.sheet), a.out)
        raise SystemExit
    keys = spread() if a.spread else [tuple(k.rsplit("-", 2)) for k in a.only.split(",") if k]
    jobs = [(k, a.seed0 + s) for k in keys for s in range(a.seeds)]
    for n, ((sp, cl, lk), seed) in enumerate(jobs, 1):
        tag = a.tag or a.recipe + ("t%02d" % round(a.denoise * 100) if a.init else "")
        name = "hero_%s_%s~%d" % (tag, key(sp, cl, lk), seed)
        t = time.time()
        neg = NEG[a.recipe] + (NEG_LOOK.get((sp.split("_")[0], lk), "") if a.recipe >= "C" else "") \
            + (NEG_SPECIES.get(sp.split("_")[0], "") if a.recipe >= "D" else "") + (", " + a.neg_extra if a.neg_extra else "")
        run(prompt(a.recipe, sp, cl, lk), neg, name, seed, a.init, a.denoise, a.lora, a.lora_w)
        print("[%d/%d] %s %.0fs" % (n, len(jobs), name, time.time() - t), flush=True)

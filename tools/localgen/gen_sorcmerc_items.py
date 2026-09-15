#!/usr/bin/env python3
"""Generate one icon per item in sorcmerc's data/{weapons,armor,magic-items}.json,
via the local ComfyUI API. Item icons, not portraits: 512x512, fewer steps, single
object on a plain background — much faster than the NPC portraits since there are
316 of these. Sequential, one GPU.
"""
import json
import time
import urllib.request

HOST = "http://127.0.0.1:8188"
SORCMERC = "/home/egeo/sorcmerc/data"
NEG = "blurry, low quality, text, watermark, cropped, multiple objects, hands, person, deformed"

RARITY_GLOW = {
    "common": "no special glow, plain and practical",
    "uncommon": "a faint magical shimmer",
    "rare": "a soft magical glow",
    "very-rare": "a vivid magical aura with light particles",
    "legendary": "an intense radiant magical aura with swirling energy",
    "artifact": "an overwhelming, awe-inspiring magical aura with crackling power",
    "varies": "a subtle magical shimmer",
}
CATEGORY_HINT = {
    "weapon": "a weapon",
    "armor": "a suit of armor, shield, or piece of protective gear",
    "ring": "a ring",
    "potion": "a potion in a glass bottle",
    "wand": "a wand",
    "staff": "a staff",
    "wondrous-item": "a magical object",
}

ICON_TAIL = ("fantasy RPG item icon, ornate detailed design, polished metal and fine engraving, "
             "sharp well-defined silhouette, single object centered on a plain dark background, "
             "digital painting, game asset, highly detailed, dramatic lighting")


def weapon_prompt(w: dict) -> str:
    return f"{w['name']}, a {w['category']} {w.get('range', 'melee')} weapon, {ICON_TAIL}"


def armor_prompt(a: dict) -> str:
    return f"{a['name']}, {a['category']} armor, {ICON_TAIL}"


def magic_prompt(m: dict) -> str:
    hint = CATEGORY_HINT.get(m["category"], "a magical item")
    glow = RARITY_GLOW.get(m["rarity"], "a magical shimmer")
    return f"{m['name']}, {hint}, {glow}, {ICON_TAIL}"


def load_items():
    items = []
    for w in json.load(open(f"{SORCMERC}/weapons.json")):
        items.append(("weapon", w["id"], weapon_prompt(w)))
    for a in json.load(open(f"{SORCMERC}/armor.json")):
        items.append(("armor", a["id"], armor_prompt(a)))
    for m in json.load(open(f"{SORCMERC}/magic-items.json")):
        items.append(("magic", m["id"], magic_prompt(m)))
    return items


def workflow(prompt_text: str, prefix: str, seed: int) -> dict:
    return {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": 512, "height": 512, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt_text, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler", "inputs": {
            "seed": seed, "steps": 18, "cfg": 7.0, "sampler_name": "euler", "scheduler": "normal",
            "denoise": 1.0, "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0],
        }},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["8", 0]}},
    }


def queue(prompt_text: str, prefix: str, seed: int) -> str:
    payload = json.dumps({"prompt": workflow(prompt_text, prefix, seed)}).encode()
    req = urllib.request.Request(f"{HOST}/prompt", data=payload, headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=15).read())
    if resp.get("node_errors"):
        raise RuntimeError(f"{prefix}: node_errors {resp['node_errors']}")
    return resp["prompt_id"]


def wait_done(prompt_id: str, timeout=120) -> None:
    start = time.time()
    while time.time() - start < timeout:
        with urllib.request.urlopen(f"{HOST}/history/{prompt_id}", timeout=15) as r:
            hist = json.loads(r.read())
        if prompt_id in hist:
            return
        time.sleep(2)
    raise TimeoutError(f"{prompt_id} did not finish in {timeout}s")


if __name__ == "__main__":
    items = load_items()
    print(f"{len(items)} items total", flush=True)
    t0 = time.time()
    for i, (kind, item_id, text) in enumerate(items):
        prefix = f"item_{kind}_{item_id}"
        print(f"[{i+1}/{len(items)}] {prefix} ...", flush=True)
        try:
            pid = queue(text, prefix, seed=2000 + i)
            wait_done(pid)
        except Exception as e:
            print(f"[{i+1}/{len(items)}] FAILED {prefix}: {e}", flush=True)
            continue
        elapsed = time.time() - t0
        avg = elapsed / (i + 1)
        remaining = avg * (len(items) - i - 1)
        print(f"[{i+1}/{len(items)}] done: {prefix}  (avg {avg:.1f}s/item, ~{remaining/60:.0f}min left)", flush=True)
    print("ALL DONE")

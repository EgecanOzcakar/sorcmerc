#!/usr/bin/env python3
"""The twelve settlement paintings: one establishing shot per (faction, kind),
in the same painterly family as the counter portraits and the road-event art.

    python3 gen_settlement_art.py                    # all twelve
    python3 gen_settlement_art.py human-town orc-camp

Where they go: the keeper is copied to sorcmerc's
assets/generated/settlement-<faction>-<kind>.png at 768px wide, which is what
core/ui_icons.gd's settlement_art() looks for. A (faction, kind) with no file
yet simply has no picture — the loader returns null and the town square page
leaves the strip out — so this set can be filled in a faction at a time.

WHY THE PROMPTS LOOK LIKE THIS. Three things the set has to hold together on,
all of them learned from the portraits:

* One camera, twelve times. Three-quarter view from a slight elevation with
  the whole settlement inside the frame. A shot that wanders between eye level
  and a map view stops reading as the same world.
* The faction's two colours, named out loud, and the same two settlement_kit.gd
  paints the map diorama with (see its PROFILES header — the palettes are read
  back OUT of this art with tools/palette_from_art.py). Cream and terracotta is
  human, ivory and teal is elf, stone and near-black with forge light is dwarf,
  hide and dark timber under red banners is orc.
* No people in the foreground. These sit under a panel title with the
  shopkeeper's own portrait one page away; a figure in the establishing shot
  competes with the face that is supposed to be the character.

PROVENANCE. settlement-human-{camp,town,city}.png in the repo were rendered
with flux-2-pro through the ElevenLabs flow API (prompts below, verbatim), not
with this script — the ElevenLabs free tier stops at three images a day, which
is why the other nine are still unpainted. Both routes are prompt-compatible
on purpose. One thing to check on any render from either: these models like to
sign their work, and two of the three human frames came back with a painted
signature in the bottom-right. The repo copies are cropped to 90% width and
96% height to cut it off; do the same, and look before you commit.
"""
import json
import sys
import time
import urllib.request

import gen_sorcmerc_items as g

# Landscape, not the items' 512 square: these are establishing shots, and a
# village squeezed into a square frame either loses its ends or is drawn from
# so far back that it is a smudge on a horizon. 1024x576 is SDXL's own 16:9
# bucket — off-bucket sizes are where it starts growing second towers — and
# 768 wide is what the repo keeps after the crop.
WIDTH, HEIGHT = 1024, 576
STEPS = 30        # 18 is enough for one object on black; a whole village is not that

# One shot, twelve times over. Trailing half of every prompt.
TAIL = ("Seen from a slight elevation in three-quarter view, the whole settlement inside "
        "the frame. Soft oil-paint brushwork, golden hour light, rich earthy colour, "
        "fantasy RPG concept art. No text, no lettering, no watermark, no signature, "
        "no logos, no borders, no close-up figures.")

NEG = ("signature, artist signature, watermark, copyright mark, text, lettering, caption, "
       "border, frame, split screen, collage, sprite sheet, map, close-up portrait, "
       "modern buildings, cars, blurry, low quality, deformed")

SCENES = {
    "human-camp": "a small human roadside camp. Three canvas-and-timber lean-tos with cream "
                  "canvas and brown beams around a cookfire, a cart with its shafts tipped up, "
                  "laundry on a line, a rutted dirt track through open farmland.",
    "human-town": "a human market town of whitewashed timber-framed houses with red clay tile "
                  "roofs, ringed by a wooden palisade, a watermill wheel on a stream, chimney "
                  "smoke, a market square with awnings.",
    "human-city": "a walled human city of pale stone houses with red tile roofs, a cathedral "
                  "spire and a square keep rising above the rooftops, stone gate towers, a "
                  "bridge over a river, hanging banners.",
    "elf-camp": "a small elven forest camp. Slender ivory silk pavilions with teal-green "
                "canopies pitched between silver birches, hanging lanterns, a carved standing "
                "stone, gold filigree on the tent poles, ferns and dappled light.",
    "elf-town": "an elven town of tall narrow ivory houses with steep conical teal-green roofs "
                "and gilt trim, built among huge ancient trees, arched wooden bridges between "
                "terraces, hanging lanterns, a slender spire at the centre.",
    "elf-city": "an elven city of slender ivory towers with teal-green spires and gold filigree, "
                "stepped terraces and waterfalls, arched bridges, glowing lanterns, tall trees "
                "woven through the architecture.",
    "dwarf-camp": "a dwarven mining camp at the foot of a mountain. A timbered mine head, ore "
                  "carts on rails, a stone forge shed glowing orange, low broad huts of grey "
                  "stone with near-black slate roofs, cut rock and spoil heaps.",
    "dwarf-town": "a dwarven town of squat broad stone houses with near-flat near-black slate "
                  "roofs, forge chimneys throwing orange light, carved rune-pillars, terraced "
                  "into a mountain slope.",
    "dwarf-city": "a dwarven mountain city. A great carved gate in a cliff face, stepped stone "
                  "halls with near-black roofs, bridges over a chasm, forge light burning in "
                  "every window and vent, statues cut into the rock.",
    "orc-camp": "an orc war camp. Crooked hide-and-timber lean-tos, a skull totem on a pole, a "
                "cookfire, sharpened stakes driven into churned mud, red rag banners.",
    "orc-town": "an orc stronghold town. Crooked timber longhouses with single-pitch turf roofs, "
                "a palisade of sharpened stakes, red war banners, smoke from cook pits, a "
                "trophy post at the centre.",
    "orc-city": "a great orc fortress city. Heavy log and rough stone walls, towers of lashed "
                "timber, red banners the length of the walls, a huge bonfire, crooked longhouses "
                "packed inside the ring.",
}

TRIES = 3


def prompt(key: str) -> str:
    return "Painterly digital fantasy illustration: %s %s" % (SCENES[key], TAIL)


def queue(text: str, prefix: str, seed: int) -> str:
    """gen_sorcmerc_items.queue(), at this file's frame size and step count."""
    wf = g.workflow(text, prefix, seed)
    wf["5"]["inputs"].update({"width": WIDTH, "height": HEIGHT})
    wf["3"]["inputs"]["steps"] = STEPS
    req = urllib.request.Request("%s/prompt" % g.HOST, data=json.dumps({"prompt": wf}).encode(),
                                 headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=15).read())
    if resp.get("node_errors"):
        raise RuntimeError("%s: node_errors %s" % (prefix, resp["node_errors"]))
    return resp["prompt_id"]


if __name__ == "__main__":
    only = set(sys.argv[1:])
    keys = [k for k in SCENES if not only or k in only]
    unknown = only - set(SCENES)
    if unknown:
        print("no such settlement: %s" % ", ".join(sorted(unknown)))
        sys.exit(2)
    g.NEG = NEG
    print("%d settlement(s), %d render(s) each" % (len(keys), TRIES), flush=True)
    t0 = time.time()
    for i, key in enumerate(keys):
        for t in range(TRIES):
            prefix = "settlement_%s_%d" % (key.replace("-", "_"), t)
            try:
                g.wait_done(queue(prompt(key), prefix, seed=9000 + 10 * i + t), timeout=300)
            except Exception as e:
                print("[%d/%d] FAILED %s: %s" % (i + 1, len(keys), prefix, e), flush=True)
                continue
            print("[%d/%d] %s" % (i + 1, len(keys), prefix), flush=True)
    print("ALL DONE in %.0f min — pick a keeper per settlement, crop the corner, "
          "resize to 768 wide" % ((time.time() - t0) / 60.0))

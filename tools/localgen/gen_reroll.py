#!/usr/bin/env python3
"""Third pass for the ids neither batch got right: a hand-written subject each
(the export names — "Ammunition +3", "Weapon +3", "Dust of Dryness" — are what
SDXL turns into sprite sheets), SEEDS renders apiece under re_<kind>_<id>_<n>.
    python3 gen_reroll.py
"""
import time
import gen_sorcmerc_items as g
import gen_single as gs

SEEDS = 4
SUBJECT = {
    "hide": "one rough hide leather cuirass with fur trim",
    "splint": "one splint mail breastplate of vertical steel strips",
    "ammunition-3": "one single steel-tipped arrow, glowing runes on the shaft",
    "ammunition-of-slaying": "one single black arrow with a cruel barbed head, dark red glow",
    "armor": "one steel breastplate with a faint magical shimmer",
    "boots-of-elvenkind": "one pair of soft green elven leather boots, side by side",
    "dust-of-dryness": "one small leather pouch spilling fine golden dust",
    "dust-of-sneezing-and-choking": "one small clay jar of grey dust with a cork",
    "dwarven-plate": "one heavy dwarven plate armor breastplate with runic engraving",
    "flame-tongue": "one longsword whose blade is wreathed in fire",
    "helm-of-teleportation": "one steel helmet with a glowing blue gem on the brow",
    "oathbow": "one elegant elven longbow of pale wood with silver inlay",
    "pipes-of-haunting": "one set of pan pipes carved from bone, tied together",
    "plate-armor-of-etherealness": "one suit of plate armor breastplate, ghostly translucent, pale blue glow",
    "potion-of-animal-friendship": "one round glass potion bottle with green liquid and a cork",
    "potion-of-heroism": "one glass potion bottle with golden liquid and a cork",
    "potion-of-speed": "one slender glass potion bottle with swirling orange liquid",
    "staff-of-healing": "one wooden staff topped with a glowing white crystal",
    "staff-of-striking": "one iron-shod oak staff with a heavy knotted head",
    "staff-of-the-python": "one wooden staff carved as a coiled snake",
    "staff-of-withering": "one twisted blackened staff with a dead grey tip",
    "tome-of-clear-thought": "one thick leather-bound book with a silver clasp, closed",
    "wand-of-magic-detection": "one slender ivory wand with a small blue crystal tip",
    "wand-of-secrets": "one dark wooden wand with a silver spiral",
    "weapon-3": "one ornate longsword with a glowing golden blade",
    "weapon-of-warning": "one steel longsword with a faintly glowing eye motif on the pommel",
    "blowgun": "one long bamboo blowgun tube",
    "dart": "one single steel throwing dart with feather fletching",
    "maul": "one two-handed iron maul with a huge square head",
    "shortbow": "one short recurve bow of dark wood, strung",
}

if __name__ == "__main__":
    kinds = {iid: kind for kind, iid, _ in g.load_items()}
    g.NEG = gs.NEG
    for i, (iid, subject) in enumerate(SUBJECT.items()):
        for n in range(SEEDS):
            prefix = f"re_{kinds[iid]}_{iid}_{n}"
            try:
                g.wait_done(g.queue(f"{subject}, {gs.TAIL}", prefix, seed=9000 + 10 * i + n), timeout=240)
            except Exception as e:
                print(f"FAILED {prefix}: {e}", flush=True)
        print(f"[{i+1}/{len(SUBJECT)}] {iid}", flush=True)
    print("ALL DONE")

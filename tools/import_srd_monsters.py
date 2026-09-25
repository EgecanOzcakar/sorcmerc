#!/usr/bin/env python3
"""Append SRD statblocks to data/bestiary.json the way its first 316 were made.

The bestiary (F1b, 2026-09-09) was derived from 5e-bits/5e-database's 2014 SRD
monster file, CR 0-10, and no script was committed with it — data/SCHEMA.md
("bestiary.json") is the only record of the rules. This is those rules written
down, so the Far Deeps' CR 11-20 entries (build log 2026-09-25-far-deeps) come
out of the same pipe instead of being typed in, and so the next batch can too.

    python3 tools/import_srd_monsters.py --check          # re-derive the existing entries, report drift
    python3 tools/import_srd_monsters.py --write          # append the ADD table below

The source is fetched from the pinned commit SCHEMA.md names (or read from
--src). --check is the proof the derivation is the original one: it rebuilds
every existing entry the SRD still has and compares the fields the engine
consumes. What it cannot rebuild is the hand work — `faction`, `habitat` and
`features` were tagged per monster, and are tagged per monster here too, in ADD.
Run 2026-09-25: 312 of the 313 entries the SRD still has re-derive exactly; the
one that does not is the giant elk, whose damage was corrected by hand (its
Hooves only strike a prone target, so it swings its Ram's 2d6+4).

What is MECHANICAL (SCHEMA.md):
  ac, max_hp, init_mod (DEX mod), speed (walk ft / 6, rounded — the adapter's
  FT_PER_HEX), the statblock's best MELEE attack (highest average damage, every
  damage line counted; versatile taken two-handed) for atk_bonus / damage (its
  first damage line) / atk_range (reach / 6) / attack_name / damage_type,
  athletics / acro / stealth (the skill if proficient, else the ability mod),
  passive_perception, saves (the proficient bonus, else the mod), save_dc (the
  statblock's highest DC, else 8 + PB + best mod — only on an entry whose
  features roll a save), and the inert metadata copied through.
  A statblock with a ranged WEAPON attack also yields `<id>-archer` with the
  same body and that attack as its primary (range / 6, capped at 8 hexes).

What is HAND-TAGGED (ADD below): faction, habitat, at most three feature
templates out of data/effects/features.json, and the `_notes` naming what was
implemented and what was flattened away.
"""
import argparse
import json
import re
import sys
import urllib.request

SRC_URL = ("https://raw.githubusercontent.com/5e-bits/5e-database/"
           "edc5a53c05097a4d9727aeedb6426003a6ffad74/src/2014/en/5e-SRD-Monsters.json")
BESTIARY = "data/bestiary.json"
FEATURES = "data/effects/features.json"
FT_PER_HEX = 6
MAX_RANGE_HEX = 8
ABIL = [("str", "strength"), ("dex", "dexterity"), ("con", "constitution"),
        ("int", "intelligence"), ("wis", "wisdom"), ("cha", "charisma")]

# The Far Deeps' batch (2026-09-25): every SRD statblock at CR 11-20 whose
# creature type is one of the Deeps' home factions (core/regions.gd HOMES:
# dragon, giant, undead, elemental, construct, fey, monstrosity). The SRD has
# no fey above CR 3, so fey gets none. `id` is the SRD index except where the
# index is a form list (vampire-vampire -> vampire, the bestiary's own name
# rule: CamelCase name -> kebab, tools/import_beasts.py). Habitat follows the
# faction's existing entries (every dragon "wild", every undead and construct
# "dungeon"), with the dragon turtle "water" as the SRD reads it.
#
# Features, three at most, picked the way the first batch's were: multiattack
# first where the statblock has one, then the action that makes the fight
# different (a breath, a gaze, a grab), then a passive.
DRAGON = ["monster-multiattack-3", "monster-frightful-presence", "monster-breath-weapon-greater"]
ADD = [
    # monstrosity
    {"src": "behir", "faction": "monstrosity", "habitat": "cave",
     "features": ["monster-multiattack-2", "monster-constrict", "monster-breath-weapon-greater"],
     "implemented": ["Constrict", "Lightning Breath"], "not": ["action: Swallow"]},
    {"src": "gynosphinx", "faction": "monstrosity", "habitat": "wild",
     "features": ["monster-multiattack-2", "monster-innate-bolt"],
     "implemented": ["Spellcasting"], "not": ["Inscrutable", "Magic Weapons", "legendary actions"]},
    {"src": "remorhaz", "faction": "monstrosity", "habitat": "wild",
     "features": ["monster-elemental-rider", "monster-grappling-attack"],
     "implemented": ["Bite"], "not": ["Heated Body", "action: Swallow"]},
    {"src": "roc", "faction": "monstrosity", "habitat": "wild",
     "features": ["monster-multiattack-2", "monster-grappling-attack", "monster-keen-sight"],
     "implemented": ["Talons", "Keen Sight"], "not": []},
    {"src": "purple-worm", "faction": "monstrosity", "habitat": "cave",
     "features": ["monster-multiattack-2", "monster-venom-sting"],
     "implemented": ["Tail Stinger"], "not": ["Tunneler", "swallow"]},
    {"src": "androsphinx", "faction": "monstrosity", "habitat": "wild",
     "features": ["monster-multiattack-2", "monster-frightful-presence", "monster-innate-bolt"],
     "implemented": ["Roar", "Spellcasting"], "not": ["Inscrutable", "Magic Weapons", "legendary actions"]},
    # elemental
    {"src": "djinni", "faction": "elemental", "habitat": "wild",
     "features": ["monster-multiattack-3", "monster-elemental-rider", "monster-innate-bolt"],
     "implemented": ["Scimitar", "Innate Spellcasting"], "not": ["Elemental Demise", "action: Create Whirlwind"]},
    {"src": "efreeti", "faction": "elemental", "habitat": "wild",
     "features": ["monster-multiattack-2", "monster-elemental-rider", "monster-innate-bolt"],
     "implemented": ["Scimitar", "Innate Spellcasting"], "not": ["Elemental Demise", "action: Hurl Flame"]},
    # giant
    {"src": "storm-giant", "faction": "giant", "habitat": "wild",
     "features": ["monster-multiattack-2", "monster-innate-bolt"],
     "implemented": ["Innate Spellcasting", "Lightning Strike"], "not": ["Amphibious"]},
    # undead
    {"src": "vampire-vampire", "id": "vampire", "cname": "Vampire", "faction": "undead", "habitat": "dungeon",
     "features": ["monster-multiattack-2", "monster-regeneration", "monster-charm-gaze"],
     "implemented": ["Regeneration", "Charm"],
     "not": ["Shapechanger", "Legendary Resistance", "Misty Escape", "Spider Climb",
             "Vampire Weaknesses", "action: Children of the Night", "legendary actions"]},
    {"src": "mummy-lord", "faction": "undead", "habitat": "dungeon",
     "features": ["monster-life-drain", "monster-frightful-presence", "monster-magic-resistance"],
     "implemented": ["Rotting Fist", "Dreadful Glare", "Magic Resistance"],
     "not": ["Rejuvenation", "Spellcasting", "legendary actions"]},
    # construct
    {"src": "iron-golem", "faction": "construct", "habitat": "dungeon",
     "features": ["monster-multiattack-2", "monster-breath-weapon-greater", "monster-magic-resistance"],
     "implemented": ["Poison Breath", "Magic Resistance"],
     "not": ["Fire Absorption", "Immutable Form", "Magic Weapons"]},
    # dragon
    {"src": "dragon-turtle", "faction": "dragon", "habitat": "water",
     "features": ["monster-multiattack-3", "monster-breath-weapon-greater"],
     "implemented": ["Steam Breath"], "not": ["Amphibious", "action: Tail"]},
] + [
    {"src": d, "faction": "dragon", "habitat": "wild", "features": DRAGON,
     "implemented": ["Frightful Presence", breath], "not": ["Legendary Resistance", "legendary actions"]}
    for d, breath in [
        ("adult-white-dragon", "Cold Breath"), ("adult-brass-dragon", "Fire Breath"),
        ("adult-black-dragon", "Acid Breath"), ("adult-copper-dragon", "Acid Breath"),
        ("adult-green-dragon", "Poison Breath"), ("adult-bronze-dragon", "Lightning Breath"),
        ("adult-blue-dragon", "Lightning Breath"), ("adult-silver-dragon", "Cold Breath"),
        ("adult-red-dragon", "Fire Breath"), ("adult-gold-dragon", "Fire Breath"),
        ("ancient-white-dragon", "Cold Breath"), ("ancient-brass-dragon", "Fire Breath"),
    ]
]


def mod(score):
    return (score - 10) // 2


def dice_avg(d):
    m = re.fullmatch(r"(\d+)d(\d+)\s*([+-]\s*\d+)?", d.replace(" ", ""))
    if not m:
        return float(d) if d.lstrip("-").isdigit() else 0.0
    n, s = int(m.group(1)), int(m.group(2))
    k = int(m.group(3).replace(" ", "")) if m.group(3) else 0
    return n * (s + 1) / 2 + k


def dmg_lines(a):
    """[(dice, type)] for an action; a versatile/choice line takes its biggest option."""
    out = []
    for d in a.get("damage", []):
        if "damage_dice" in d:
            out.append((d["damage_dice"].replace(" ", ""), d.get("damage_type", {}).get("index", "")))
        elif "from" in d:
            opts = [o for o in d["from"].get("options", []) if "damage_dice" in o]
            if opts:
                o = max(opts, key=lambda o: dice_avg(o["damage_dice"]))
                out.append((o["damage_dice"].replace(" ", ""), o.get("damage_type", {}).get("index", "")))
    return out


def weapon_attacks(src, kind):
    """(action, lines) for every weapon attack of `kind` ("Melee" or "Ranged").
    A thrown weapon ("Melee or Ranged Weapon Attack") is melee: the first batch
    made an archer only out of a bow, a sling or a rock (no orc-archer for the
    orc's javelin), which --check confirms."""
    out = []
    for a in src.get("actions", []):
        desc = a.get("desc", "")
        pure = "%s Weapon Attack" % kind in desc and "Melee or Ranged" not in desc
        thrown = kind == "Melee" and "Melee or Ranged Weapon Attack" in desc
        if "attack_bonus" in a and (pure or thrown):
            lines = dmg_lines(a)
            if lines:
                out.append((a, lines))
    return out


def best(attacks):
    return max(attacks, key=lambda al: sum(dice_avg(d) for d, _ in al[1])) if attacks else None


def feet(desc, word):
    m = re.search(word + r" (\d+)(?:/\d+)? ft", desc)
    return int(m.group(1)) if m else 5


def prof(src, key):
    for p in src.get("proficiencies", []):
        if p["proficiency"]["index"] == key:
            return p["value"]
    return None


def highest_dc(src):
    dcs = []
    for group in ("special_abilities", "actions", "legendary_actions"):
        for a in src.get(group, []):
            if "dc" in a:
                dcs.append(a["dc"]["dc_value"])
            for m in re.finditer(r"DC (\d+)", a.get("desc", "")):
                dcs.append(int(m.group(1)))
            sc = a.get("spellcasting", {})
            if "dc" in sc:
                dcs.append(sc["dc"])
    return max(dcs) if dcs else None


def derive(src, attack=None, ranged=False):
    ab = {k: src[full] for k, full in ABIL}
    a, lines = attack
    dice, dtype = lines[0]
    walk = src.get("speed", {}).get("walk", "0 ft.")
    walk_ft = int(re.match(r"(\d+)", walk).group(1)) if re.match(r"(\d+)", walk) else 0
    if ranged:
        rng = min(MAX_RANGE_HEX, round(feet(a["desc"], "range") / FT_PER_HEX))
    else:
        rng = max(1, round(feet(a["desc"], "reach") / FT_PER_HEX))
    skill = lambda name, ability: prof(src, "skill-" + name) if prof(src, "skill-" + name) is not None else mod(ab[ability])
    saves = {}
    for k, _ in ABIL:
        v = prof(src, "saving-throw-" + k)
        saves[k] = v if v is not None else mod(ab[k])
    speeds = {}
    for mode, v in src.get("speed", {}).items():
        m = re.match(r"(\d+)", str(v))
        if m:
            speeds[mode] = int(m.group(1))
    senses = {}
    for k, v in src.get("senses", {}).items():
        senses[k] = v
    return {
        "id": src["index"], "cname": src["name"], "ac": src["armor_class"][0]["value"],
        "max_hp": src["hit_points"], "init_mod": mod(ab["dex"]),
        "speed": round((walk_ft or max(speeds.values(), default=0)) / FT_PER_HEX),
        "atk_bonus": a["attack_bonus"], "damage": dice, "ranged": ranged, "atk_range": rng,
        "athletics": skill("athletics", "str"), "acro": skill("acrobatics", "dex"),
        "stealth": skill("stealth", "dex"),
        "passive_perception": src.get("senses", {}).get("passive_perception", 10 + mod(ab["wis"])),
        "saves": saves,
        "cr": src["challenge_rating"], "xp": src["xp"], "size": src["size"], "type": src["type"],
        "attack_name": a["name"], "damage_type": dtype, "hit_dice": src.get("hit_points_roll", src.get("hit_dice", "")),
        "abilities": ab, "speeds_ft": speeds, "senses": senses,
        "resist": list(src.get("damage_resistances", [])), "immune": list(src.get("damage_immunities", [])),
        "vulnerable": list(src.get("damage_vulnerabilities", [])),
        "cond_immune": [c["index"] for c in src.get("condition_immunities", [])],
    }


# The key order every existing entry is written in.
ORDER = ["id", "cname", "ac", "max_hp", "init_mod", "speed", "atk_bonus", "damage", "ranged",
         "atk_range", "athletics", "acro", "stealth", "passive_perception", "saves", "save_dc",
         "features", "cr", "xp", "size", "type", "faction", "habitat", "attack_name", "damage_type",
         "hit_dice", "abilities", "speeds_ft", "senses", "resist", "immune", "vulnerable",
         "cond_immune", "_notes", "variant_of"]


def ordered(e):
    return {k: e[k] for k in ORDER if k in e}


def build(src, spec, features_db):
    melee = best(weapon_attacks(src, "Melee"))
    if melee is None:
        raise SystemExit("%s has no melee weapon attack" % src["index"])
    e = derive(src, melee)
    e["id"] = spec.get("id", e["id"])
    e["cname"] = spec.get("cname", e["cname"])
    e["faction"], e["habitat"] = spec["faction"], spec["habitat"]
    feats = spec["features"]
    assert len(feats) <= 3, e["id"]
    for f in feats:
        assert f in features_db, "%s: no feature %s" % (e["id"], f)
    e["features"] = list(feats)
    if any("save" in features_db[f] for f in feats):
        dc = highest_dc(src)
        if dc is None:
            dc = 8 + src.get("proficiency_bonus", 2) + max(mod(v) for v in e["abilities"].values())
        e["save_dc"] = dc
    notes = []
    multi = [a for a in src.get("actions", []) if a["name"] == "Multiattack"]
    kinds = {x.get("action_name") for a in multi for x in a.get("actions", [])}
    if len(kinds) > 1 or (multi and not kinds):
        notes.append("flattened to basic attacks")
    if spec["implemented"]:
        notes.append("implemented: " + ", ".join(spec["implemented"]))
    if spec["not"]:
        notes.append("not modeled: " + "; ".join(spec["not"]))
    e["_notes"] = "; ".join(notes)
    out = [ordered(e)]
    ranged = best(weapon_attacks(src, "Ranged"))
    if ranged is not None and ranged[0] is not melee[0]:
        r = derive(src, ranged, ranged=True)
        for k in ("features", "save_dc", "faction", "habitat", "_notes"):
            if k in e:
                r[k] = e[k]
        r["id"] = e["id"] + "-archer"
        r["cname"] = e["cname"] + " Archer"
        r["variant_of"] = e["id"]
        out.append(ordered(r))
    return out


def load_src(path):
    if path:
        return json.load(open(path))
    with urllib.request.urlopen(SRC_URL) as f:
        return json.load(f)


def check(srd, bestiary):
    """Rebuild what the SRD still has and compare the consumed fields."""
    by_idx = {m["index"]: m for m in srd}
    fields = ["ac", "max_hp", "init_mod", "speed", "atk_bonus", "damage", "atk_range",
              "athletics", "acro", "stealth", "passive_perception", "saves", "attack_name",
              "hit_dice", "cr", "xp"]
    same = diff = 0
    for e in bestiary:
        src_id = e.get("variant_of", e["id"])
        if src_id not in by_idx:
            continue
        src = by_idx[src_id]
        att = best(weapon_attacks(src, "Ranged" if e["ranged"] else "Melee"))
        if att is None:
            continue
        got = derive(src, att, ranged=e["ranged"])
        bad = [f for f in fields if got[f] != e[f]]
        if bad:
            diff += 1
            print("  %-28s %s" % (e["id"], ", ".join("%s %r!=%r" % (f, got[f], e[f]) for f in bad)))
        else:
            same += 1
    print("check: %d entries re-derive exactly, %d differ" % (same, diff))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", help="a local copy of 5e-SRD-Monsters.json")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    srd = load_src(args.src)
    bestiary = json.load(open(BESTIARY))
    if args.check:
        check(srd, bestiary)
    if args.write:
        features_db = json.load(open(FEATURES))
        by_idx = {m["index"]: m for m in srd}
        have = {e["id"] for e in bestiary}
        added = []
        for spec in ADD:
            for e in build(by_idx[spec["src"]], spec, features_db):
                if e["id"] in have:
                    print("refused: %s is already in the bestiary" % e["id"])
                    continue
                bestiary.append(e)
                have.add(e["id"])
                added.append(e["id"])
        with open(BESTIARY, "w") as f:
            json.dump(bestiary, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("added %d: %s" % (len(added), ", ".join(added)))


if __name__ == "__main__":
    sys.exit(main())

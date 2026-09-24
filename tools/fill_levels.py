#!/usr/bin/env python3
"""The level-table holes docs/audit-class-levels.md counted, filled in.

    python3 tools/fill_levels.py            # apply to data/classes.json + subclasses.json
    python3 tools/fill_levels.py --check    # exit 1 if anything here is not applied

Also the half casters' first level: the export carries the 2014 table, where a
paladin and a ranger cast nothing until level 2. The 2024 book gives both
Spellcasting and two 1st-level slots at level 1 (CLASS_SLOTS, CLASS_GRANT_MOVES),
and three sorcerer grants sit a level or more off the book (CLASS_FEATURE_MOVES).

Idempotent: a feature already present is left alone, so this can be re-run
after any future edit to confirm the tables still carry everything.

WHY THIS IS HAND-AUTHORED AND NOT RE-EXPORTED
data/SCHEMA.md says to regenerate the catalog with dnd-maintainer's
`npm run export:sorcmerc`. Do not. Measured 2026-09-22: a clean re-export
DELETES magic-missile, healing-word, shield, eldritch-blast and
vicious-mockery from data/spells.json, plus scroll-of-resurrection and
scroll-of-identification from data/magic-items.json — content that was added
downstream and exists nowhere upstream. The export is one-way and lossy in
this direction. The same additions are mirrored into dnd-maintainer by hand so
a future export carries them, but this file is what the game actually reads.

WHAT THIS CLAIMS
The levels and feature names are the 2024 Player's Handbook progressions,
written from knowledge of the book rather than transcribed from a machine
source — neither repo has one to transcribe. Ids follow the catalog's own
convention (`<class>-<kebab-name>`, `<subclassid>-<kebab-name>`), which is
what Effects.verb_label() renders into the name a player reads. Treat a name
here as good but not golden; `coverage-matrix.ts`'s GOLDEN_VERIFIED set is
empty upstream for exactly this reason.

Features carry no mechanics. 253 of the catalog's 286 features already have no
entry in data/effects/features.json, so a new id behaves like the majority:
the sheet lists it, and nothing in combat reads it until someone authors one.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

# --- class tables ---------------------------------------------------------
# {class_id: {level: [feature-name, ...]}} — ids are built as "<class>-<name>".
CLASS_FEATURES = {
    "cleric": {14: ["improved-blessed-strikes"]},
    "fighter": {
        11: ["extra-attack-2"],
        13: ["indomitable-2", "studied-attacks"],
        17: ["action-surge-2", "indomitable-3"],
        20: ["extra-attack-3"],
    },
    "rogue": {
        11: ["reliable-talent"],
        14: ["devious-strikes"],
        15: ["slippery-mind"],
        18: ["elusive"],
        20: ["stroke-of-luck"],
    },
}

# Ability Score Improvement levels the tables lost. Every 2024 class takes one
# at 4/8/12/16 and again at 19; fighter and rogue take extras (6, and 10) which
# the data already has. The ten other classes are already whole.
CLASS_ASI = {
    "fighter": [12, 14, 16, 19],
    "rogue": [12, 16, 19],
}

# The 2024 half-caster slot row the export lost. Every other row of both
# tables already matches the book (checked 2026-09-24, levels 2-20); only
# level 1 was [] — the 2014 table, where a half caster starts casting at 2.
# {class_id: {level: slots by spell level}}.
CLASS_SLOTS = {
    "paladin": {1: [2]},
    "ranger": {1: [2]},
}

# Grants the export files a level late. The 2024 ranger takes Spellcasting at
# level 1, beside Favored Enemy, and Deft Explorer and the Fighting Style stay
# at 2. The paladin's Spellcasting and spell pick are already at 1, so this is
# the ranger catching up to the same shape. Choice keys ride along unchanged
# (core/rules/choice.gd reads a key, not the level that granted it).
# {class_id: {grant type: (from level, to level)}}.
CLASS_GRANT_MOVES = {
    "ranger": {"spellcasting": (2, 1), "spell-choice": (2, 1)},
}

# Single grants the export files on the wrong level, named by feature id or by
# choice key. The sorcerer's are the 2024 book's: Sorcerous Restoration at 5
# (the export had 20), Arcane Apotheosis at 20 (18), and the third pair of
# Metamagic picks at 17 (18). Choice keys ride along unchanged.
# {class_id: {feature id or choice key: (from level, to level)}}.
CLASS_FEATURE_MOVES = {
    "sorcerer": {
        "sorcerer-sorcerous-restoration": (20, 5),
        "sorcerer-arcane-apotheosis": (18, 20),
        "feature-choice:class:sorcerer:4": (18, 17),
        "feature-choice:class:sorcerer:5": (18, 17),
    },
}

# --- subclass tiers -------------------------------------------------------
# {subclass_id: {class_level: [feature-name, ...]}} — "<subclassid>-<name>".
SUBCLASS_FEATURES = {
    # barbarian — every path owes a 14
    "wildheart": {3: ["animal-speaker"], 10: ["nature-speaker"], 14: ["power-of-the-wilds"]},
    "worldtree": {14: ["travel-along-the-tree"]},
    "zealot": {3: ["divine-fury"], 14: ["rage-of-the-gods"]},
    # bard
    "collegedance": {14: ["tandem-footwork"]},
    "collegeglamour": {14: ["unbreakable-majesty"]},
    "collegelore": {14: ["peerless-skill"]},
    "collegevalor": {14: ["battle-magic"]},
    # cleric — domains close at 17
    "lifedomain": {17: ["supreme-healing"]},
    "lightdomain": {17: ["corona-of-light"]},
    "trickerydomain": {17: ["improved-duplicity"]},
    "wardomain": {17: ["avatar-of-battle"]},
    # druid
    "circleland": {14: ["natures-sanctuary"]},
    "circlemoon": {14: ["lunar-form"]},
    "circlesea": {14: ["oceanic-gift"]},
    "circlestars": {14: ["full-of-stars"]},
    # monk
    "warriorofmercy": {11: ["flurry-of-healing-and-harm"], 17: ["hand-of-ultimate-mercy"]},
    "warriorofshadow": {11: ["improved-shadow-step"], 17: ["cloak-of-shadows"]},
    "warriorofelements": {11: ["stride-of-the-elements"], 17: ["elemental-epitome"]},
    "warrioropenhand": {11: ["fleet-step"], 17: ["quivering-palm"]},
    # ranger
    "beastmaster": {11: ["bestial-fury"], 15: ["share-spells"]},
    "feywanderer": {11: ["fey-reinforcements"], 15: ["misty-wanderer"]},
    "gloomstalker": {11: ["stalkers-flurry"], 15: ["shadowy-dodge"]},
    "hunter": {11: ["superior-hunters-prey"], 15: ["superior-hunters-defense"]},
    # rogue
    "thief": {13: ["use-magic-device"], 17: ["thiefs-reflexes"]},
    "assassin": {13: ["envenom-weapons"], 17: ["death-strike"]},
    "arcanetrickster": {13: ["versatile-trickster"], 17: ["spell-thief"]},
    "soulknife": {13: ["psychic-veil"], 17: ["rend-mind"]},
}

# Berserker's tiers sit one rung early: the book puts Mindless Rage at 6,
# Retaliation at 10 and Intimidating Presence at 14, and the catalog has all
# three a step down with two features stacked on level 3. {feature: new level}.
SUBCLASS_MOVES = {
    "berserker": {
        "berserker-mindless-rage": 6,
        "berserker-retaliation": 10,
        "berserker-intimidating-presence": 14,
    },
}


def feature(fid):
    return {"type": "feature", "feature": {"id": fid}}


def asi_grants(class_id, index):
    return [
        {"type": "asi", "key": "asi:class:%s:%d" % (class_id, index), "points": 2, "from": None},
        {"type": "feat-choice", "key": "feat-choice:class:%s:%d" % (class_id, index),
         "from": None, "category": "general"},
    ]


def write(name, data):
    (DATA / name).write_text(json.dumps(data, indent=2) + "\n")


def fill_classes(classes, log):
    by_id = {c["id"]: c for c in classes}
    for cid, levels in CLASS_FEATURES.items():
        c = by_id[cid]
        have = {g["feature"]["id"] for lv in c["levels"] for g in lv if g["type"] == "feature"}
        for n, names in levels.items():
            for name in names:
                fid = "%s-%s" % (cid, name)
                if fid in have:
                    continue
                c["levels"][n - 1].append(feature(fid))
                log.append("%s level %d + %s" % (cid, n, fid))

    for cid, want in CLASS_ASI.items():
        c = by_id[cid]
        at = {n for n, lv in enumerate(c["levels"], 1) for g in lv if g["type"] == "asi"}
        # Choice keys are stable slots (core/rules/choice.gd) — never renumber an
        # existing one, only take the next free index.
        used = {int(g["key"].rsplit(":", 1)[1]) for lv in c["levels"] for g in lv
                if g["type"] == "asi"}
        nxt = max(used) + 1 if used else 0
        for n in sorted(want):
            if n in at:
                continue
            c["levels"][n - 1].extend(asi_grants(cid, nxt))
            log.append("%s level %d + ASI (key index %d)" % (cid, n, nxt))
            nxt += 1

    for cid, rows in CLASS_SLOTS.items():
        c = by_id[cid]
        for n, slots in rows.items():
            if c["spellSlots"][n - 1] == slots:
                continue
            log.append("%s level %d slots %s -> %s" % (cid, n, c["spellSlots"][n - 1], slots))
            c["spellSlots"][n - 1] = list(slots)

    for cid, moves in CLASS_FEATURE_MOVES.items():
        c = by_id[cid]
        for name, (frm, to) in moves.items():
            def named(g):
                return g.get("key") == name or (g["type"] == "feature" and g["feature"]["id"] == name)
            moving = [g for g in c["levels"][frm - 1] if named(g)]
            for g in moving:
                c["levels"][frm - 1].remove(g)
                c["levels"][to - 1].append(g)
                log.append("%s %s moved %d -> %d" % (cid, name, frm, to))

    for cid, moves in CLASS_GRANT_MOVES.items():
        c = by_id[cid]
        for gtype, (frm, to) in moves.items():
            moving = [g for g in c["levels"][frm - 1] if g["type"] == gtype]
            for g in moving:
                c["levels"][frm - 1].remove(g)
                c["levels"][to - 1].append(g)
                log.append("%s %s moved %d -> %d" % (cid, gtype, frm, to))


def fill_subclasses(subclasses, log):
    by_id = {s["id"]: s for s in subclasses}

    for sid, moves in SUBCLASS_MOVES.items():
        s = by_id[sid]
        for fid, to in moves.items():
            frm = None
            for e in s["levels"]:
                for g in list(e["grants"]):
                    if g["type"] == "feature" and g["feature"]["id"] == fid:
                        frm = int(e["classLevel"])
                        if frm != to:
                            e["grants"].remove(g)
            if frm is None or frm == to:
                continue
            tier(s, to)["grants"].append(feature(fid))
            log.append("%s %s moved %d -> %d" % (sid, fid, frm, to))
        s["levels"] = [e for e in s["levels"] if e["grants"]]
        s["levels"].sort(key=lambda e: e["classLevel"])

    for sid, levels in SUBCLASS_FEATURES.items():
        s = by_id[sid]
        have = {g["feature"]["id"] for e in s["levels"] for g in e["grants"]
                if g["type"] == "feature"}
        for n, names in sorted(levels.items()):
            for name in names:
                fid = "%s-%s" % (sid, name)
                if fid in have:
                    continue
                tier(s, n)["grants"].append(feature(fid))
                log.append("%s level %d + %s" % (sid, n, fid))
        s["levels"] = [e for e in s["levels"] if e["grants"]]
        s["levels"].sort(key=lambda e: e["classLevel"])


def tier(subclass, level):
    for e in subclass["levels"]:
        if int(e["classLevel"]) == level:
            return e
    e = {"classLevel": level, "grants": []}
    subclass["levels"].append(e)
    return e


if __name__ == "__main__":
    check = "--check" in sys.argv
    classes = json.loads((DATA / "classes.json").read_text())
    subclasses = json.loads((DATA / "subclasses.json").read_text())

    log = []
    fill_classes(classes, log)
    fill_subclasses(subclasses, log)

    if check:
        for line in log:
            print("MISSING: %s" % line)
        print("%d grants not applied" % len(log))
        sys.exit(1 if log else 0)

    if not log:
        print("nothing to do — every grant is already in the tables")
        sys.exit(0)
    write("classes.json", classes)
    write("subclasses.json", subclasses)
    for line in log:
        print(line)
    print("\n%d grants written" % len(log))

#!/usr/bin/env python3
"""Which features without a mechanic are worth authoring one for, ranked.

    python3 tools/audit_features.py             # the ranked report
    python3 tools/audit_features.py --markdown  # the same, as docs/audit-features.md
    python3 tools/audit_features.py --top 30    # how many rows to print

289 of the catalog's 340 features have no mechanic anywhere. That is an
unbounded grind taken alphabetically and a short, finite job taken in the order
play actually meets them, so this counts the order.

THE MEASURE, and it is deliberately not a guess about who plays what.
A feature is worth `21 - level` **character-levels of play**: granted at 3, it
is carried through eighteen of the twenty levels a character passes; granted at
17, through four. A CLASS feature scores that in full, because every character
of the class holds it. A SUBCLASS feature scores it divided by the number of
paths its class offers, because exactly one of them is taken — a barbarian path
feature is held by a quarter of barbarians, and that is the whole of the
correction. No popularity weighting: nothing in this repo measures which class
anybody picks, so inventing a distribution would dress a guess as a number.

Ties break toward the earlier level, since an early feature is also the one a
new player meets first.

WHAT IT CANNOT TELL YOU is whether the engine can express the thing at all,
and that answer already exists: tests/test_subclass_features.gd carries a
hand-written inventory line per un-authored SUBCLASS feature, tagged [C] a
combat mechanic the board is missing, [S] spell-list, [P] partly covered
already, [O] out of combat or flavour. That file says "the [C] rows are the
ones to author next", so the tag is joined onto each row here and the ranking
only decides the order within it. Class features have no such inventory; they
are listed untagged, which is itself worth knowing.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Features whose mechanic exists, just not in data/effects/features.json.
#
# This is the correction the first run of this tool needed, and it was a big
# one: the top thirteen rows were all class features at level 1, and most of
# them were already implemented — the mechanic simply arrives as a DIFFERENT
# GRANT TYPE on the same level (`armor-class`, `resource-pool`,
# `weapon-mastery-choice`, `feature-choice`) or as code that keys off the class
# level directly. Counting those as missing would have sent somebody to author
# Unarmored Defense a second time.
#
# Hand-written and hand-verified, because neither half is machine-derivable:
# a sibling grant on the same level proves nothing on its own (monk 2 carries
# one `resource-pool` and five features), and code that reads a class level
# names no feature id at all. Each row says where the mechanic actually lives,
# so the claim can be checked rather than believed.
COVERED_ELSEWHERE = {
    "barbarian-unarmored-defense": "`armor-class` grant -> core/rules/pass_defense.gd",
    "monk-unarmored-defense": "`armor-class` grant -> core/rules/pass_defense.gd",
    "barbarian-weapon-mastery": "`weapon-mastery-choice` grant -> core/rules/pass_gear.gd",
    "ranger-weapon-mastery": "`weapon-mastery-choice` grant -> core/rules/pass_gear.gd",
    "monk-martial-arts": "monk class level -> core/rules/resolve.gd (unarmed dice)",
    "monk-focus-points": "`resource-pool` grant on the same level",
    "sorcerer-font-of-magic": "`resource-pool` grant on the same level",
    "paladin-channel-divinity": "`resource-pool` grant on the same level",
    "sorcerer-metamagic": "two `feature-choice` grants on the same level",
    "champion-improved-critical": "core/adapter.gd sets crit_range from the feature id",
    "champion-superior-critical": "core/adapter.gd sets crit_range from the feature id",
    "rogue-thieves-cant": "a language proficiency; nothing on a board to express",
}

DATA = ROOT / "data"
MAX_LEVEL = 20


def load(name):
    return json.loads((DATA / name).read_text())


def raw_notes():
    """The hand-written inventory out of tests/test_subclass_features.gd.

    Parsed rather than duplicated: that file is the one place a human writes
    down what the book says a feature does, and a second copy here would be
    wrong within a release.
    """
    src = (ROOT / "tests/test_subclass_features.gd").read_text()
    body = src.split("const RAW_NOTES := {", 1)[1]
    out = {}
    for fid, note in re.findall(r'^\t"([^"]+)":\s*"((?:[^"\\]|\\.)*)"', body, re.M):
        out[fid] = note.replace('\\"', '"')
    return out


def survey():
    classes = load("classes.json")
    subclasses = load("subclasses.json")
    effects = load("effects/features.json")
    notes = raw_notes()

    paths_per_class = {}
    for s in subclasses:
        paths_per_class[s["classId"]] = paths_per_class.get(s["classId"], 0) + 1

    rows = {}

    def add(fid, level, owner, kind, share):
        # Two classes can grant the same id at different levels; keep the
        # earliest, and sum the reach.
        r = rows.setdefault(fid, {"id": fid, "level": level, "owners": [], "reach": 0.0})
        r["level"] = min(r["level"], level)
        r["owners"].append("%s %s %d" % (kind, owner, level))
        r["reach"] += (MAX_LEVEL + 1 - level) * share

    for c in classes:
        for n in range(1, MAX_LEVEL + 1):
            for g in c["levels"][n - 1]:
                if g["type"] == "feature":
                    add(g["feature"]["id"], n, c["id"], "class", 1.0)
    for s in subclasses:
        share = 1.0 / max(1, paths_per_class.get(s["classId"], 1))
        for e in s["levels"]:
            for g in e["grants"]:
                if g["type"] == "feature":
                    add(g["feature"]["id"], int(e["classLevel"]), s["id"], "path", share)

    for fid, r in rows.items():
        r["authored"] = fid in effects or fid in COVERED_ELSEWHERE
        r["elsewhere"] = COVERED_ELSEWHERE.get(fid, "")
        r["note"] = notes.get(fid, "")
        r["tag"] = r["note"][1:2] if r["note"].startswith("[") else ""
    return rows


def report(rows, top, md=False):
    todo = [r for r in rows.values() if not r["authored"]]
    todo.sort(key=lambda r: (-r["reach"], r["level"], r["id"]))
    out = []
    w = out.append
    tags = {}
    for r in todo:
        tags[r["tag"] or "-"] = tags.get(r["tag"] or "-", 0) + 1

    if md:
        w("# Features without a mechanic, in the order play meets them\n")
        w("Generated by `tools/audit_features.py`. **Reach** is character-levels")
        w("of play: `21 - level`, divided by a class's path count for a subclass")
        w("feature, since exactly one path is taken. **Tag** comes from")
        w("`tests/test_subclass_features.gd`'s hand-written inventory — `[C]` a")
        w("combat mechanic the board is missing, `[S]` spell-list, `[P]` partly")
        w("covered already, `[O]` out of combat. Class features carry no tag")
        w("because nothing in the repo inventories them.\n")
        w("**%d of %d features have no mechanic** — no entry in" % (len(todo), len(rows)))
        w("`data/effects/features.json` and no row in this tool's")
        w("`COVERED_ELSEWHERE`, which lists the ones whose mechanic arrives as a")
        w("different grant type or as code keyed off the class level.\n")
        w("| tag | count |")
        w("|---|---|")
        for t in sorted(tags):
            w("| %s | %d |" % (t, tags[t]))
        w("")
        w("| # | feature | level | reach | tag | granted by | what the book says |")
        w("|---|---|---|---|---|---|---|")
        for i, r in enumerate(todo[:top], 1):
            w("| %d | `%s` | %d | %.1f | %s | %s | %s |" % (
                i, r["id"], r["level"], r["reach"], r["tag"] or "—",
                ", ".join(r["owners"][:3]), r["note"][4:] if r["note"] else ""))
    else:
        w("%d of %d features have no mechanic; %s" % (
            len(todo), len(rows), ", ".join("%s:%d" % (k, tags[k]) for k in sorted(tags))))
        for i, r in enumerate(todo[:top], 1):
            w("%3d %-38s L%-2d reach %5.1f %-3s %s" % (
                i, r["id"], r["level"], r["reach"], r["tag"] or "-",
                r["note"][4:60] if r["note"] else ", ".join(r["owners"][:2])))
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    top = 40
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])
    md = "--markdown" in sys.argv
    text = report(survey(), top, md)
    if md:
        path = ROOT / "docs/audit-features.md"
        path.write_text(text)
        print("wrote %s" % path)
    else:
        sys.stdout.write(text)

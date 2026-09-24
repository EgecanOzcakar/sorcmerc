#!/usr/bin/env python3
"""Print the build log as one document: docs/expansion-plan.md (the entries
up to 2026-09-24), then docs/plan/*.md in date order. See docs/plan/README.md
for why the log is a folder now.

    python3 tools/plan_log.py                  # everything, oldest first
    python3 tools/plan_log.py --since 2026-09-20
    python3 tools/plan_log.py --titles         # one line per entry
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEGACY = os.path.join(ROOT, "docs", "expansion-plan.md")
FOLDER = os.path.join(ROOT, "docs", "plan")
NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-[a-z0-9-]+\.md$")
HEADING = re.compile(r"^## (.+)$", re.M)
DATE = re.compile(r"\((\d{4}-\d{2}-\d{2})\)\s*$")


def entries():
    """(date or '', title, text) for every entry, legacy sections first."""
    out = []
    text = open(LEGACY, encoding="utf-8").read()
    heads = list(HEADING.finditer(text))
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        d = DATE.search(m.group(1))
        out.append((d.group(1) if d else "", m.group(1), text[m.start():end].rstrip() + "\n"))
    for name in sorted(os.listdir(FOLDER)):
        m = NAME.match(name)
        if not m:
            continue
        body = open(os.path.join(FOLDER, name), encoding="utf-8").read()
        h = HEADING.search(body)
        out.append((m.group(1), h.group(1) if h else name, body.rstrip() + "\n"))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--since", help="only entries dated on or after YYYY-MM-DD")
    ap.add_argument("--titles", action="store_true", help="one line per entry")
    a = ap.parse_args()
    for date, title, text in entries():
        if a.since and (date == "" or date < a.since):
            continue
        if a.titles:
            print(title)
        else:
            sys.stdout.write(text + "\n")


if __name__ == "__main__":
    main()

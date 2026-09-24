# The build log, one entry per file

Every feature, fix or balance pass that lands gets **its own file here**,
named for the day it lands and what it is:

    docs/plan/2026-09-24-effect-strip.md
    docs/plan/2026-09-25-rival-raids.md

The entry inside is the same shape `docs/expansion-plan.md` always used:

    ## Title — subtitle (2026-09-24)

    What changed and why, what was measured (with the sweep named), what a
    player sees.

    ### Still open

    - what was deliberately left, and the condition for coming back to it

## Why a folder and not one file

`docs/expansion-plan.md` was one file that every pull request appended to,
at the same place, its end. Any two open PRs therefore conflicted with each
other, and every merge left the rest needing a hand-merge before they could
land. A new file per entry means two PRs never touch the same lines.

`docs/expansion-plan.md` stays as it is: it holds every entry up to
2026-09-24 and is still the record code comments point at. It takes no new
entries. `tests/test_plan_entries.gd` fails if a dated section is appended
to it, and checks every file here for the name and heading above.

## Reading it as one log

    python3 tools/plan_log.py                  # the whole log, oldest first
    python3 tools/plan_log.py --since 2026-09-20
    python3 tools/plan_log.py --titles         # one line per entry

It prints `docs/expansion-plan.md` and then these files in date order, so
the log still reads top to bottom.

## Conventions

- **Name:** `YYYY-MM-DD-short-slug.md`, lowercase, hyphens. The date is the
  day the work lands (the heading's date). Two entries on one day are two
  files with different slugs.
- **One entry per file.** A follow-up on another day gets its own file and
  names the first one; it does not edit it.
- **Correcting an entry** in its own PR before it merges is fine. After it
  merges, a correction is a new dated file that says what was wrong.

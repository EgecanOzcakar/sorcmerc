## The build log becomes a folder — one entry per file (2026-09-24)

The owner's ask: stop the merge conflicts in `docs/expansion-plan.md`. Every
pull request appended its entry to the end of that one file, so any two open
PRs edited the same lines. Each merge to master left every other open PR
conflicted and needing a hand-merge. On 2026-09-24 most merges of master into
an open branch were for this file and nothing else.

A git `merge=union` attribute would resolve appends on a local merge, but
GitHub's conflict check and merge button ignore `.gitattributes` merge
drivers, so a PR would still show as conflicted. The fix is structural:

- **`docs/plan/`** holds one file per entry, `YYYY-MM-DD-slug.md`, in the same
  `## Title — subtitle (date)` shape with `### Still open`. Two PRs add two
  files and never touch the same lines. `docs/plan/README.md` has the
  convention.
- **`docs/expansion-plan.md` is closed, not moved.** It keeps every entry up to
  2026-09-24 (150 sections), so the many code comments that cite it stay
  true. Its last section says where the log continues.
- **`tools/plan_log.py`** prints the old file and the folder as one log in
  date order (`--since DATE`, `--titles`).
- **`tests/test_plan_entries.gd`**:
  - fails on a dated section appended below the old file's closing heading,
    and says where the entry goes instead;
  - holds every folder file to its name, a single heading whose date matches
    the file name, and a `### Still open` section.
- `CLAUDE.md`, `README.md`, and the design-bible and balancing skills now say
  "add a file to `docs/plan/`" where they said "append to
  `docs/expansion-plan.md`".

### Still open

- **`.github/workflows/update-notes.yml`** tells the release-notes writer to
  read `docs/expansion-plan.md`'s dated entries. It should also name
  `docs/plan/`. That file is on `.github/always-ask.txt`, so it waits for the
  owner.
- **The open PRs at the time** (#216 effect strip, #217 hiring pool, #218
  autopilot) each carried an appended entry. Each one moves it into its own
  `docs/plan/` file.

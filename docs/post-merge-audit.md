# Post-merge audit

`.github/workflows/post-merge-audit.yml`. Every merge to master: audit the merged
diff, fix the small safe things on a branch and open a PR, hold everything else
in an issue assigned to the repo owner. Runs without anyone watching.

## The one guardrail

Automated work is only ever a **branch + pull request**. This is structural,
not a prompt rule: the Claude step is allowed `Read/Glob/Grep/Edit/Write` and
read-only `git diff/log/show` — no `git push`, no `gh`. A plain shell step
commits to `auto/post-merge-<sha>` and opens the PR. Nothing in this workflow
can reach master, and nothing it does is irreversible.

This is also why `fixer` stopped being manual-only. It was manual because
unattended writes across repos are hard to review after the fact; a PR is
reviewed like any other change, so that concern is covered. **If the PR
requirement is ever dropped, put fixer back to manual-only.**

## Auto vs ask

A finding is fixed automatically only if its fix passes **both** axes. The
Claude prompt applies these when choosing; the `Check the fix against the caps`
step re-checks the real diff afterwards and holds the whole run on any breach,
so a wrong classification costs a PR, never a merge.

**Size — all of:**

| cap | value |
|---|---|
| files changed | ≤ 5 |
| lines changed (added + deleted) | ≤ 150 |
| top-level directories touched | ≤ 2 |

**Risk — always ask, whatever the size.** Patterns live in
`.github/always-ask.txt` (one regex per line, the shell check and the fixer
prompt both read it):

- `.github/` — CI/CD
- anything named `auth*`, `rls*`, `polic*`, `security*`, `permission*`, `secret*`, `credential*`
- `migrations/`, `*.sql`
- `payment*`, `billing*`, `licens*`, `stripe*`, `checkout*`
- `.env*`, `*.pem`, `*.key`, `*.p12`
- manifests and lockfiles (`package.json`, lockfiles, `Cargo.lock`, `go.sum`)
- **any file deletion or rename** (checked separately, not a pattern)
- sorcmerc-specific: `project.godot`, `export_presets.cfg`, `tools/bug-relay/`

A three-line change to a policy file is tiny and still asks.

## How you get pinged

An issue titled `[needs approval] post-merge audit of <sha>`, assigned to you,
labelled `needs-approval`. Chosen over a draft PR because for an ASK item no code
exists yet, and because relabelling the issue `bug` hands it straight to the
existing `claude-issues.yml`, which fixes it and opens a PR — approval is one
click, no new infrastructure.

## Cost gate

The `gate` job skips the audit for: whitespace-only diffs; diffs touching only
`docs/`, `*.md`, `LICENSE`, `.gitignore`, `*.import`, `shots/`, images and
audio; commits whose message starts with `bump`/`release`/`v1.2.3`; and merges
of the workflow's own `[auto-fix]` PRs (otherwise it audits its own fixes
forever). The audit scope is the merged diff only, never the repo — the daily
sweep in `~/.claude/scripts/daily-repo-audit.sh` covers whole-repo drift.
Budget per run: 40 turns, 25 minutes.

## Private repos only

The `gate` job has `if: github.event.repository.private`. Merged content on a
public repo can carry prompt injection from outside contributors into a run
that holds write tools. sorcmerc is currently **public**, so the file is in
place but the workflow does not run here; it starts the moment the repo is
made private. Deleting that line to run it on a public repo is a deliberate
choice — make it knowingly.

## Porting to another repo

1. Copy `.github/workflows/post-merge-audit.yml`, `.github/always-ask.txt`,
   `.claude/agents/code-auditor.md`, `.claude/agents/fixer.md`.
2. Add the `CLAUDE_CODE_OAUTH_TOKEN` secret (same one `claude-issues.yml` uses).
3. Change `master` to the repo's default branch (two places in the workflow),
   and the `tests.yml` name in the `gh workflow run` line to that repo's test
   workflow — or delete the line if there is none. PRs opened with
   `GITHUB_TOKEN` do not trigger `pull_request` workflows, which is why the
   suite is dispatched by hand.
4. Replace the sorcmerc rows at the bottom of `always-ask.txt` with that
   repo's own trust boundaries (Supabase dir, RLS policies, payment code…).
5. Edit the docs/assets skip list in the `gate` step if the repo's trivial
   files look different.
6. Optional: `claude-issues.yml` for the one-click "relabel `bug`" approval.

The agent files are copies of `~/.claude/agents/`; when the global ones change,
re-copy. (No dotfiles repo exists to check out from — that would remove the
duplication.)

# The bug reporter's fallback relay

A Cloudflare Worker that files an in-game bug report as a GitHub issue, so a
player whose browser will not open still has a way to send one.

**This is the second door, not the first.** The game's primary path is still the
player's own browser on GitHub's prefilled new-issue form — no credential ships
in the game, and the issue is filed by the reporter's own account so we can
reply to them. `core/bug_report.gd` argues that at length. The relay exists for
where that path is shut: a popup blocker on the web export, or a machine with no
handler for `https`. Without it, the fallback is "copy this text and paste it
somewhere yourself", which most people will not do.

The game only shows the relay button when a relay URL is compiled in, so
everything here is optional — the reporter works without it.

## What it costs

Nothing, in practice. Cloudflare's free plan covers 100,000 Worker requests a
day and the KV free tier covers the rate-limit counters. A bug relay that sees
a hundred reports a month is not close to any of those limits.

## Deploy

You need a Cloudflare account and `npx wrangler`. From this directory:

**1. Make a token that can do exactly one thing.** On GitHub, under
Settings → Developer settings → **Fine-grained personal access tokens**, create
one scoped to *only* the `sorcmerc` repository, with **Issues: Read and write**
and nothing else. Do not use a classic token — a classic `repo` token can push
code, and this one is going to sit on a machine answering the open internet.

**2. Create the rate-limit KV namespace.**

```sh
npx wrangler kv namespace create RATE_LIMIT
```

Paste the id it prints into the commented-out `[[kv_namespaces]]` block in
`wrangler.toml` and uncomment it. (Skip this and the Worker still runs; it just
fails open on the rate limit, with the size caps still in force.)

**3. Put the token in as a secret — never in a file.**

```sh
npx wrangler secret put GITHUB_TOKEN     # paste the token at the prompt
```

Optionally also `npx wrangler secret put RELAY_KEY` for a shared string the game
sends in `X-Relay-Key`. It ships inside the client, so anyone who wants it can
read it out: it is a speed bump against someone who scraped the URL, not a lock.
If you set it, set the same value as `BUG_RELAY_KEY` in step 5.

**4. Deploy.**

```sh
npx wrangler deploy
```

Wrangler prints the URL, something like
`https://sorcmerc-bug-relay.<your-subdomain>.workers.dev`.

**5. Point the game at it.** The game reads the URL from, in order:

- the `SORCMERC_BUG_RELAY` environment variable (for a local run or a test), then
- `RELAY_URL` in `core/bug_report.gd`, which is empty in the repo.

For a release, do not edit that constant by hand — set a GitHub Actions
**repository variable** named `BUG_RELAY_URL` (Settings → Secrets and variables
→ Actions → Variables) to the `…/report` endpoint:

```
https://sorcmerc-bug-relay.<your-subdomain>.workers.dev/report
```

`.github/workflows/release.yml` stamps it into the constant at export time, the
same way it stamps the version. A variable, not a secret: the URL ends up inside
the shipped client either way, and Actions will not interpolate a secret into a
non-secret context cleanly. If you set a `RELAY_KEY` in step 3, add a matching
`BUG_RELAY_KEY` variable too.

Leave the variable unset and nothing changes — no relay button appears, and the
browser path is the only path, which is a perfectly good place to stop.

## Check it works

```sh
curl -X POST https://sorcmerc-bug-relay.<your-subdomain>.workers.dev/report \
  -H 'Content-Type: application/json' \
  -d '{"title":"Relay smoke test","body":"Ignore me, testing the relay."}'
```

A `201` with `{"ok":true,"url":"…"}` means it is live. Close the issue it just
filed.

## What it refuses

It is a door open to the whole internet holding a token that can write to one
repository, so most of `worker.js` is refusals:

| | |
|---|---|
| **Size** | 64 KB per request, checked against the real body and not just `Content-Length`; 120 characters of title, 30,000 of body |
| **Rate** | 5 reports per IP per 10 minutes (KV-backed; see step 2) |
| **Shape** | `POST /report` only, JSON object only, a non-empty title and body or it is a 400 |
| **Mentions** | `@name`, `#12` and `GH-12` in reporter text are defused with an empty HTML comment — invisible when rendered, inert as a ping. An open door that can @-mention a maintainer is a spam tool with extra steps |
| **Leaks** | An upstream failure comes back as a flat "could not reach GitHub". GitHub's own error bodies can quote request headers, and one of ours is the token |

Every issue it files carries a footer saying it arrived anonymously and that
**there is no account to reply to** — a maintainer should never have to guess
which of the two doors a report came through.

## Tests

```sh
node --test
```

25 tests, no network and no Cloudflare account needed: the validation, the
defusing, the CORS decisions, the rate-limit window, the label retry, and that a
failure upstream never puts the token in a response.

## Turning it off

```sh
npx wrangler delete
```

and clear the `BUG_RELAY_URL` Actions variable. The next release goes back to
the browser path only.

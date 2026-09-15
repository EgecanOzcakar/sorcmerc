// The bug reporter's fallback door: a Cloudflare Worker that holds the GitHub
// token so the game does not have to.
//
// The game's FIRST path is still the player's own browser on GitHub's prefilled
// new-issue form (core/bug_report.gd says why at length): the issue is filed by
// the reporter's own account, so we can reply to them, and no credential ships
// inside a game binary. This exists for when that path is shut — a popup
// blocker on the web export, a machine with no handler for https — where the
// choice would otherwise be "copy this text somewhere yourself" or nothing.
//
// So everything below is written for a door that is open to the whole internet
// and is holding a token that can write to one repository:
//
//   * the token is a Worker SECRET and a fine-grained PAT with Issues: RW on
//     the one repo. It is never in this file, never in wrangler.toml, and
//     never in a response body — including an error one.
//   * every request is rate limited per IP, and the body has hard length caps
//     BEFORE anything is parsed out of it.
//   * @mentions and #refs in reporter text are defused, because an open door
//     that can @-ping a maintainer or cross-link fifty issues is a spam tool
//     with extra steps.
//   * the filed issue says, in the issue itself, that it came in anonymously
//     and that the reporter cannot be replied to. A maintainer must never have
//     to guess which of the two doors an issue came through.
//
// Deploy:  see README.md in this directory.

export const MAX_TITLE = 120;
export const MAX_BODY = 30000;
// The whole request, before JSON.parse sees it. A report that needs more than
// this is not a report, and parsing a megabyte to find that out is the attack.
export const MAX_REQUEST_BYTES = 64 * 1024;
export const RATE_LIMIT = 5;            // reports per window, per IP
export const RATE_WINDOW_SECONDS = 600; // 10 minutes

// --- what a reporter is allowed to have written ---------------------------

// GitHub turns "@name" into a ping and "#12" into a cross-reference on another
// issue. Neither belongs in text an anonymous stranger typed, so both get an
// empty HTML comment wedged in: invisible when rendered, inert as a mention.
//
// Only forms GitHub actually links are touched — "you@example.com" and a plain
// "#1 priority" are left alone, because mangling ordinary prose in a bug report
// costs more than it saves.
export function defuse(text) {
  return String(text)
    .replace(/(^|[^\w@/-])@(?=[A-Za-z0-9][\w-]*)/g, "$1@<!---->")
    .replace(/(^|[^\w&])#(?=\d+\b)/g, "$1#<!---->")
    .replace(/\bGH-(?=\d+\b)/g, "GH<!---->-");
}

// Returns {ok: true, title, body} or {ok: false, error} — never throws, and
// never echoes back more of the input than the reason it was refused.
export function validate(payload) {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return { ok: false, error: "expected a JSON object" };
  }
  const title = typeof payload.title === "string" ? payload.title.trim() : "";
  const body = typeof payload.body === "string" ? payload.body.trim() : "";
  if (!title) return { ok: false, error: "a one-line summary is required" };
  if (title.length > MAX_TITLE) {
    return { ok: false, error: `the summary must be ${MAX_TITLE} characters or fewer` };
  }
  if (!body) return { ok: false, error: "a description is required" };
  if (body.length > MAX_BODY) {
    return { ok: false, error: `the report must be ${MAX_BODY} characters or fewer` };
  }
  // A newline in a title is how you make an issue list look like something it
  // is not; it is also never what the player meant.
  return { ok: true, title: defuse(title.replace(/\s+/g, " ")), body: defuse(body) };
}

// The one line that must be on every issue this Worker files. A maintainer
// replying to an anonymous report gets no reply, so the issue says so up front.
export const RELAY_FOOTER = [
  "",
  "---",
  "",
  "<sub>⚠️ Filed anonymously through the in-game relay, because this player's",
  "browser would not open. **There is no account to reply to** — anything this",
  "report does not already say cannot be asked for.</sub>",
].join("\n");

// --- rate limiting --------------------------------------------------------

// A fixed window in KV, keyed by IP. KV is eventually consistent, so a
// determined attacker racing many colos can beat the count by a little; that is
// fine. This is here to stop a loop, not a botnet, and the caps above are what
// stop a loop from being expensive.
export async function overRateLimit(kv, ip, now = Date.now()) {
  if (!kv) return false; // unconfigured: fail open, the caps still apply
  const window = Math.floor(now / 1000 / RATE_WINDOW_SECONDS);
  const key = `rl:${window}:${ip}`;
  const seen = parseInt((await kv.get(key)) || "0", 10) || 0;
  if (seen >= RATE_LIMIT) return true;
  // The TTL outlives the window so a count cannot expire mid-window and reset.
  await kv.put(key, String(seen + 1), { expirationTtl: RATE_WINDOW_SECONDS * 2 });
  return false;
}

// --- CORS -----------------------------------------------------------------

// The web export runs from itch.io's CDN, so this is a cross-origin fetch and
// the browser will not even deliver the response without these. A desktop build
// sends no Origin at all, which is allowed — CORS is a browser rule, and there
// is no browser in that case to enforce it for.
export function corsHeaders(origin, allowed) {
  const list = String(allowed || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const any = list.includes("*");
  const ok = !origin || any || list.includes(origin);
  if (!ok) return null;
  return {
    "Access-Control-Allow-Origin": origin && !any ? origin : "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Relay-Key",
    "Access-Control-Max-Age": "86400",
    ...(origin && !any ? { Vary: "Origin" } : {}),
  };
}

function json(data, status, headers) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...(headers || {}) },
  });
}

// --- filing it ------------------------------------------------------------

export async function createIssue(env, title, body, fetchImpl = fetch) {
  const repo = String(env.GITHUB_REPO || "").trim();
  if (!repo.includes("/")) throw new Error("GITHUB_REPO is not set to owner/repo");
  const labels = String(env.ISSUE_LABELS ?? "bug")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  const call = (withLabels) =>
    fetchImpl(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
        // GitHub rejects an API call with no User-Agent.
        "User-Agent": "sorcmerc-bug-relay",
      },
      body: JSON.stringify({
        title,
        body: body + RELAY_FOOTER,
        ...(withLabels.length ? { labels: withLabels } : {}),
      }),
    });

  let res = await call(labels);
  // A label that does not exist on the repo is a 422 on create (unlike the
  // prefilled-URL path, which silently drops it). Losing the label is better
  // than losing the report, so try once more without.
  if (res.status === 422 && labels.length) res = await call([]);
  return res;
}

// --- the door -------------------------------------------------------------

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin, env.ALLOWED_ORIGINS ?? "*");
    if (!cors) return json({ ok: false, error: "origin not allowed" }, 403);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "POST") {
      return json({ ok: false, error: "POST a report to /report" }, 405, cors);
    }
    if (new URL(request.url).pathname !== "/report") {
      return json({ ok: false, error: "not found" }, 404, cors);
    }

    // An optional shared string the game sends. It ships inside the client, so
    // anyone who wants it can read it out — it is a speed bump against a
    // scraped URL, never a lock, and nothing below relies on it.
    if (env.RELAY_KEY && request.headers.get("X-Relay-Key") !== env.RELAY_KEY) {
      return json({ ok: false, error: "bad relay key" }, 401, cors);
    }

    const declared = parseInt(request.headers.get("Content-Length") || "0", 10);
    if (declared > MAX_REQUEST_BYTES) {
      return json({ ok: false, error: "that report is too large to send" }, 413, cors);
    }
    let raw;
    try {
      raw = await request.text();
    } catch {
      return json({ ok: false, error: "could not read the request" }, 400, cors);
    }
    // Content-Length can lie or be absent (chunked); this is the real check.
    if (raw.length > MAX_REQUEST_BYTES) {
      return json({ ok: false, error: "that report is too large to send" }, 413, cors);
    }

    let payload;
    try {
      payload = JSON.parse(raw);
    } catch {
      return json({ ok: false, error: "that was not valid JSON" }, 400, cors);
    }
    const checked = validate(payload);
    if (!checked.ok) return json({ ok: false, error: checked.error }, 400, cors);

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (await overRateLimit(env.RATE_LIMIT, ip)) {
      return json(
        { ok: false, error: "too many reports from here — try again in a few minutes" },
        429,
        { ...cors, "Retry-After": String(RATE_WINDOW_SECONDS) },
      );
    }

    let res;
    try {
      res = await createIssue(env, checked.title, checked.body);
    } catch (e) {
      // Whatever went wrong upstream, the reporter gets a flat "it failed".
      // GitHub's error bodies can quote request headers back, and one of ours
      // is the token.
      console.error("relay: createIssue threw", e && e.message);
      return json({ ok: false, error: "could not reach GitHub" }, 502, cors);
    }
    if (!res.ok) {
      console.error("relay: GitHub said", res.status);
      return json({ ok: false, error: `GitHub refused the report (${res.status})` }, 502, cors);
    }
    const issue = await res.json();
    return json({ ok: true, url: issue.html_url, number: issue.number }, 201, cors);
  },
};

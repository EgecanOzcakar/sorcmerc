// The relay's own tests. Pure functions and the fetch handler, no network:
//   node --test          (from this directory)
//
// This is a door open to the internet holding a repo-scoped token, so what is
// tested here is mostly what it REFUSES.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, {
  defuse, validate, corsHeaders, overRateLimit, createIssue,
  MAX_TITLE, MAX_BODY, MAX_REQUEST_BYTES, RATE_LIMIT, RELAY_FOOTER,
} from "./worker.js";

// --- defuse ---------------------------------------------------------------

test("defuse breaks @mentions without changing what is rendered", () => {
  assert.equal(defuse("cc @octocat please"), "cc @<!---->octocat please");
  assert.equal(defuse("@octocat at the start"), "@<!---->octocat at the start");
  assert.ok(!defuse("ping @a @b @c").includes("@a"));
});

test("defuse breaks issue cross-references", () => {
  assert.equal(defuse("same as #12"), "same as #<!---->12");
  assert.equal(defuse("see GH-99"), "see GH<!---->-99");
});

test("defuse leaves ordinary prose alone", () => {
  assert.equal(defuse("mail me at you@example.com"), "mail me at you@example.com");
  assert.equal(defuse("the hex at 3,4"), "the hex at 3,4");
  assert.equal(defuse("Goblin Archer [foe] 0/7 hp"), "Goblin Archer [foe] 0/7 hp");
  // An HTML entity is &#NNNN; — the & guard is what keeps it intact.
  assert.equal(defuse("&#8212; an entity"), "&#8212; an entity");
});

test("defuse catches a #ref in ordinary prose too, deliberately", () => {
  // GitHub links "#1" wherever it appears, prose or not, so "my #1 complaint"
  // really does cross-reference issue 1. Mangling the sentence slightly beats
  // letting an anonymous report ping fifty issues.
  assert.equal(defuse("my #1 complaint"), "my #<!---->1 complaint");
});

// --- validate -------------------------------------------------------------

test("validate refuses everything that is not a report", () => {
  for (const bad of [null, undefined, 42, "a string", [], {}]) {
    assert.equal(validate(bad).ok, false, `accepted ${JSON.stringify(bad)}`);
  }
  assert.equal(validate({ title: "  ", body: "x" }).ok, false);
  assert.equal(validate({ title: "t" }).ok, false, "a title with no body");
  assert.equal(validate({ title: 5, body: "x" }).ok, false, "a non-string title");
});

test("validate enforces the caps", () => {
  assert.equal(validate({ title: "t".repeat(MAX_TITLE + 1), body: "x" }).ok, false);
  assert.equal(validate({ title: "t".repeat(MAX_TITLE), body: "x" }).ok, true);
  assert.equal(validate({ title: "t", body: "x".repeat(MAX_BODY + 1) }).ok, false);
});

test("validate flattens a title and defuses both fields", () => {
  const r = validate({ title: "line\none\ttwo", body: "hi @octocat" });
  assert.equal(r.ok, true);
  assert.equal(r.title, "line one two");
  assert.ok(r.body.includes("@<!---->octocat"));
});

// --- CORS -----------------------------------------------------------------

test("corsHeaders allows a listed origin and refuses an unlisted one", () => {
  const allow = "https://html-classic.itch.zone,https://example.com";
  assert.ok(corsHeaders("https://example.com", allow));
  assert.equal(
    corsHeaders("https://example.com", allow)["Access-Control-Allow-Origin"],
    "https://example.com",
  );
  assert.equal(corsHeaders("https://evil.test", allow), null);
});

test("corsHeaders allows a request with no Origin at all", () => {
  // A desktop build is not a browser; there is nothing for CORS to protect.
  assert.ok(corsHeaders(null, "https://example.com"));
  assert.ok(corsHeaders(undefined, ""));
});

test("corsHeaders honours the wildcard", () => {
  assert.equal(corsHeaders("https://anything.test", "*")["Access-Control-Allow-Origin"], "*");
});

// --- rate limiting --------------------------------------------------------

function fakeKV() {
  const store = new Map();
  return {
    store,
    async get(k) { return store.has(k) ? store.get(k) : null; },
    async put(k, v) { store.set(k, v); },
  };
}

test("overRateLimit lets RATE_LIMIT through and then stops", async () => {
  const kv = fakeKV();
  const now = Date.now();
  for (let i = 0; i < RATE_LIMIT; i++) {
    assert.equal(await overRateLimit(kv, "1.2.3.4", now), false, `refused report ${i + 1}`);
  }
  assert.equal(await overRateLimit(kv, "1.2.3.4", now), true, "let one too many through");
  // ...and it is per IP, not global.
  assert.equal(await overRateLimit(kv, "5.6.7.8", now), false);
});

test("overRateLimit fails open when no KV is bound", async () => {
  assert.equal(await overRateLimit(undefined, "1.2.3.4"), false);
});

// --- createIssue ----------------------------------------------------------

function fakeGitHub(responses) {
  const calls = [];
  const queue = [...responses];
  return {
    calls,
    fetch: async (url, init) => {
      calls.push({ url, init, body: JSON.parse(init.body) });
      return queue.shift();
    },
  };
}
const created = () => ({
  ok: true, status: 201,
  json: async () => ({ html_url: "https://github.com/o/r/issues/7", number: 7 }),
});

test("createIssue posts to the configured repo with the token and the footer", async () => {
  const gh = fakeGitHub([created()]);
  const env = { GITHUB_REPO: "o/r", GITHUB_TOKEN: "secret-token", ISSUE_LABELS: "bug" };
  await createIssue(env, "A title", "A body", gh.fetch);
  const [call] = gh.calls;
  assert.equal(call.url, "https://api.github.com/repos/o/r/issues");
  assert.equal(call.init.headers.Authorization, "Bearer secret-token");
  assert.ok(call.init.headers["User-Agent"], "GitHub rejects a call with no User-Agent");
  assert.equal(call.body.title, "A title");
  assert.ok(call.body.body.endsWith(RELAY_FOOTER), "the anonymous footer is not optional");
  assert.ok(call.body.body.includes("no account to reply to"));
  assert.deepEqual(call.body.labels, ["bug"]);
});

test("createIssue retries without labels rather than lose the report", async () => {
  const gh = fakeGitHub([{ ok: false, status: 422 }, created()]);
  const env = { GITHUB_REPO: "o/r", GITHUB_TOKEN: "t", ISSUE_LABELS: "bug,nonexistent" };
  const res = await createIssue(env, "t", "b", gh.fetch);
  assert.equal(res.status, 201);
  assert.equal(gh.calls.length, 2);
  assert.equal(gh.calls[1].body.labels, undefined, "the retry sent no labels");
});

test("createIssue refuses to run without a configured repo", async () => {
  await assert.rejects(() => createIssue({ GITHUB_TOKEN: "t" }, "t", "b", async () => {}));
});

// --- the handler ----------------------------------------------------------

const ENV = { GITHUB_REPO: "o/r", GITHUB_TOKEN: "secret-token", ALLOWED_ORIGINS: "*" };
const post = (body, headers = {}, url = "https://relay.test/report") =>
  new Request(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

test("OPTIONS preflight is answered", async () => {
  const res = await worker.fetch(
    new Request("https://relay.test/report", {
      method: "OPTIONS", headers: { Origin: "https://example.com" },
    }), ENV);
  assert.equal(res.status, 204);
  assert.ok(res.headers.get("Access-Control-Allow-Origin"));
});

test("a GET, and a POST to the wrong path, are refused", async () => {
  const get = await worker.fetch(new Request("https://relay.test/report"), ENV);
  assert.equal(get.status, 405);
  const wrong = await worker.fetch(post({ title: "t", body: "b" }, {}, "https://relay.test/"), ENV);
  assert.equal(wrong.status, 404);
});

test("an unlisted origin is refused before anything else happens", async () => {
  const res = await worker.fetch(
    post({ title: "t", body: "b" }, { Origin: "https://evil.test" }),
    { ...ENV, ALLOWED_ORIGINS: "https://example.com" });
  assert.equal(res.status, 403);
});

test("a wrong relay key is refused when one is configured", async () => {
  const res = await worker.fetch(post({ title: "t", body: "b" }, { "X-Relay-Key": "nope" }),
    { ...ENV, RELAY_KEY: "right" });
  assert.equal(res.status, 401);
});

test("an oversized body is refused by declared length and by real length", async () => {
  const declared = await worker.fetch(
    post({ title: "t", body: "b" }, { "Content-Length": String(MAX_REQUEST_BYTES + 1) }), ENV);
  assert.equal(declared.status, 413);
  // A lying/absent Content-Length must not get past the real check.
  const real = await worker.fetch(post({ title: "t", body: "x".repeat(MAX_REQUEST_BYTES) }), ENV);
  assert.equal(real.status, 413);
});

test("malformed JSON and an invalid report are 400, not 500", async () => {
  assert.equal((await worker.fetch(post("{not json"), ENV)).status, 400);
  assert.equal((await worker.fetch(post({ body: "no title" }), ENV)).status, 400);
});

test("a rate-limited IP gets a 429 with a Retry-After", async () => {
  const kv = fakeKV();
  const env = { ...ENV, RATE_LIMIT: kv };
  const req = () => worker.fetch(post({ title: "t", body: "b" }, { "CF-Connecting-IP": "9.9.9.9" }),
    { ...env, GITHUB_TOKEN: "t" });
  const saved = globalThis.fetch;
  globalThis.fetch = async () => created();
  try {
    for (let i = 0; i < RATE_LIMIT; i++) assert.equal((await req()).status, 201);
    const blocked = await req();
    assert.equal(blocked.status, 429);
    assert.ok(blocked.headers.get("Retry-After"));
  } finally { globalThis.fetch = saved; }
});

test("a good report comes back with the issue url", async () => {
  const saved = globalThis.fetch;
  globalThis.fetch = async () => created();
  try {
    const res = await worker.fetch(post({ title: "Door does nothing", body: "It did nothing." }), ENV);
    assert.equal(res.status, 201);
    const out = await res.json();
    assert.equal(out.ok, true);
    assert.equal(out.url, "https://github.com/o/r/issues/7");
  } finally { globalThis.fetch = saved; }
});

test("an upstream failure never leaks the token or GitHub's own error body", async () => {
  const saved = globalThis.fetch;
  globalThis.fetch = async () => ({
    ok: false, status: 401,
    json: async () => ({ message: "Bad credentials for Bearer secret-token" }),
  });
  try {
    const res = await worker.fetch(post({ title: "t", body: "b" }), ENV);
    assert.equal(res.status, 502);
    const text = JSON.stringify(await res.json());
    assert.ok(!text.includes("secret-token"), "the token reached the reporter");
    assert.ok(!text.includes("Bad credentials"), "GitHub's error body reached the reporter");
  } finally { globalThis.fetch = saved; }
});

test("a thrown upstream error is a 502, not an unhandled crash", async () => {
  const saved = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error("network down: Bearer secret-token"); };
  try {
    const res = await worker.fetch(post({ title: "t", body: "b" }), ENV);
    assert.equal(res.status, 502);
    assert.ok(!JSON.stringify(await res.json()).includes("secret-token"));
  } finally { globalThis.fetch = saved; }
});

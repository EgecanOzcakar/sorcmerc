// End to end against the real Worker runtime: starts `wrangler dev` on a spare
// port, drives it with Node's WebSocket client, stops it.
//   node --test          (from this directory; needs npx wrangler)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";

const PORT = 8799;
const URL = `ws://127.0.0.1:${PORT}/room/`;
let dev;

before(async () => {
  dev = spawn("npx", ["wrangler", "dev", "--port", String(PORT), "--local"], {
    cwd: import.meta.dirname, stdio: ["ignore", "pipe", "pipe"],
  });
  await new Promise((ok, no) => {
    const timer = setTimeout(() => no(new Error("wrangler dev did not come up")), 90_000);
    dev.stdout.on("data", (d) => { if (String(d).includes("Ready on")) { clearTimeout(timer); ok(); } });
    dev.on("exit", (code) => no(new Error(`wrangler dev exited ${code}`)));
  });
});

after(() => { dev?.kill(); });

// A socket that hands out messages one at a time, in order. `peers` frames are
// kept aside in .peers (latest) since they arrive whenever a seat changes.
function connect(code, role) {
  const ws = new WebSocket(`${URL}${code}?role=${role}`);
  const queue = [];
  const waiting = [];
  ws.peers = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.t === "peers") { ws.peers = m.roles; return; }
    waiting.length ? waiting.shift()(m) : queue.push(m);
  };
  ws.next = () => queue.length ? Promise.resolve(queue.shift()) : new Promise((ok) => waiting.push(ok));
  ws.say = (m) => ws.send(JSON.stringify(m));
  ws.closed = new Promise((ok) => { ws.onclose = (e) => ok(e.code); });
  return new Promise((ok, no) => { ws.onopen = () => ok(ws); ws.onerror = () => no(new Error("connect failed")); });
}

const settle = (ms = 150) => new Promise((ok) => setTimeout(ok, ms));
const fresh = () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".split("")
  .sort(() => Math.random() - 0.5).slice(0, 6).join("");
const SETUP = { t: "setup", seed: 7, owners: { vera: "host", pike: "guest", ilsa: "host" } };

test("a new room replays nothing; a joiner gets everything said before it", async () => {
  const code = fresh();
  const host = await connect(code, "host");
  assert.deepEqual(await host.next(), { t: "replay", log: [] });
  host.say(SETUP);
  host.say({ t: "swap", a: "vera", b: "pike" });
  const guest = await connect(code, "guest");
  const replay = await guest.next();
  assert.deepEqual(replay.log.map((m) => m.t), ["setup", "swap"]);
  host.close(); guest.close();
});

test("a message reaches the other peer, not its sender, stamped with the sender's seat", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  const guest = await connect(code, "guest"); await guest.next();
  host.say(SETUP); await guest.next();
  host.say({ t: "move", hero: "vera", hex: [1, 2], from: "guest" });   // a lie about `from`
  assert.deepEqual(await guest.next(), { t: "move", hero: "vera", hex: [1, 2], from: "host" });
  guest.say({ t: "end_turn", hash: 42 });
  assert.deepEqual(await host.next(), { t: "end_turn", hash: 42, from: "guest" });
  host.close(); guest.close();
});

test("dropping and reconnecting replays the whole log, own messages included", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  let guest = await connect(code, "guest"); await guest.next();
  host.say(SETUP);
  guest.say({ t: "move", hero: "pike", hex: [0, 0] });
  await guest.next(); await host.next();
  guest.close();
  await settle();
  guest = await connect(code, "guest");
  const replay = await guest.next();
  assert.deepEqual(replay.log.map((m) => m.from), ["host", "guest"]);
  host.close(); guest.close();
});

test("a hero's presses come only from its owner; swap/go/setup only from the host", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  const guest = await connect(code, "guest"); await guest.next();
  host.say(SETUP); await guest.next();
  guest.say({ t: "setup", seed: 9, owners: { vera: "guest" } });   // ignored
  guest.say({ t: "move", hero: "vera", hex: [1, 1] });             // not theirs
  guest.say({ t: "swap", a: "vera", b: "pike" });                   // host's
  guest.say({ t: "go" });                                           // host's
  guest.say({ t: "perform", hero: "pike", verb: "attack", c: "g1" });   // theirs
  assert.deepEqual(await host.next(), { t: "perform", hero: "pike", verb: "attack", c: "g1", from: "guest" });
  host.close(); guest.close();
  const late = await connect(code, "guest");
  assert.deepEqual((await late.next()).log.map((m) => m.t), ["setup", "perform"]);
  late.close();
});

test("a new setup starts a new fight: the log is cut back to it", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  host.say(SETUP);
  host.say({ t: "move", hero: "vera", hex: [1, 1] });
  host.say({ ...SETUP, seed: 8 });
  host.say({ t: "move", hero: "ilsa", hex: [2, 2] });
  await settle();
  const guest = await connect(code, "guest");
  const log = (await guest.next()).log;
  assert.deepEqual(log.map((m) => m.t), ["setup", "move"]);
  assert.equal(log[0].seed, 8);
  host.close(); guest.close();
});

test("hover is forwarded and never logged", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  const guest = await connect(code, "guest"); await guest.next();
  host.say({ t: "hover", hex: [3, 3], verb: "attack" });
  assert.deepEqual(await guest.next(), { t: "hover", hex: [3, 3], verb: "attack", from: "host" });
  guest.close();
  await settle();
  const again = await connect(code, "guest");
  assert.deepEqual((await again.next()).log, []);
  host.close(); again.close();
});

test("two seats; a second socket in a seat evicts the first; peers says who is here", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  await settle();
  assert.deepEqual(host.peers, ["host"]);
  const guest = await connect(code, "guest"); await guest.next();
  await settle();
  assert.deepEqual(host.peers, ["host", "guest"]);
  const guest2 = await connect(code, "guest"); await guest2.next();
  assert.equal(await guest.closed, 4000);
  await settle();
  assert.deepEqual(host.peers, ["host", "guest"]);
  guest2.close();
  await settle();
  assert.deepEqual(host.peers, ["host"]);
  host.close();
  await assert.rejects(connect(code, "judge"));   // no third seat
});

test("only JSON objects are kept; bad paths are refused", async () => {
  const code = fresh();
  const host = await connect(code, "host"); await host.next();
  host.send("not json");
  host.send("[1,2,3]");
  host.say({ t: "go" });
  const guest = await connect(code, "guest");
  assert.deepEqual((await guest.next()).log, [{ t: "go", from: "host" }]);
  host.close(); guest.close();
  const res = await fetch(`http://127.0.0.1:${PORT}/room/toolong1`);
  assert.equal(res.status, 404);
  const plain = await fetch(`http://127.0.0.1:${PORT}/room/ABC234?role=host`);
  assert.equal(plain.status, 426);
});

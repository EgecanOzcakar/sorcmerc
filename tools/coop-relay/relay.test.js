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

// A socket that hands out messages one at a time, in order.
function connect(code) {
  const ws = new WebSocket(URL + code);
  const queue = [];
  const waiting = [];
  ws.onmessage = (e) => { const m = JSON.parse(e.data); waiting.length ? waiting.shift()(m) : queue.push(m); };
  ws.next = () => queue.length ? Promise.resolve(queue.shift()) : new Promise((ok) => waiting.push(ok));
  ws.say = (m) => ws.send(JSON.stringify(m));
  return new Promise((ok, no) => { ws.onopen = () => ok(ws); ws.onerror = () => no(new Error("connect failed")); });
}

const fresh = () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".split("")
  .sort(() => Math.random() - 0.5).slice(0, 6).join("");

test("a new room replays nothing; a joiner gets everything said before it", async () => {
  const code = fresh();
  const host = await connect(code);
  assert.deepEqual(await host.next(), { t: "replay", log: [] });
  host.say({ t: "setup", seed: 7, from: "host" });
  host.say({ t: "swap", a: "vera", b: "pike", from: "host" });
  const guest = await connect(code);
  const replay = await guest.next();
  assert.equal(replay.t, "replay");
  assert.deepEqual(replay.log.map((m) => m.t), ["setup", "swap"]);
  host.close(); guest.close();
});

test("a message reaches the other peer and not its sender", async () => {
  const code = fresh();
  const host = await connect(code); await host.next();
  const guest = await connect(code); await guest.next();
  host.say({ t: "move", hero: "vera", hex: [1, 2], from: "host" });
  assert.deepEqual(await guest.next(), { t: "move", hero: "vera", hex: [1, 2], from: "host" });
  guest.say({ t: "end_turn", hero: "pike", hash: 42, from: "guest" });
  assert.equal((await host.next()).t, "end_turn");
  host.close(); guest.close();
});

test("dropping and reconnecting replays the whole log, own messages included", async () => {
  const code = fresh();
  const host = await connect(code); await host.next();
  let guest = await connect(code); await guest.next();
  host.say({ t: "setup", from: "host" });
  guest.say({ t: "move", from: "guest" });
  await guest.next(); await host.next();
  guest.close();
  await new Promise((ok) => setTimeout(ok, 100));
  guest = await connect(code);
  const replay = await guest.next();
  assert.deepEqual(replay.log.map((m) => m.from), ["host", "guest"]);
  host.close(); guest.close();
});

test("only JSON objects are kept; bad paths are refused", async () => {
  const code = fresh();
  const host = await connect(code); await host.next();
  host.send("not json");
  host.send("[1,2,3]");
  host.say({ t: "ok", from: "host" });
  const guest = await connect(code);
  assert.deepEqual((await guest.next()).log, [{ t: "ok", from: "host" }]);
  host.close(); guest.close();
  const res = await fetch(`http://127.0.0.1:${PORT}/room/toolong1`);
  assert.equal(res.status, 404);
  const plain = await fetch(`http://127.0.0.1:${PORT}/room/ABC234`);
  assert.equal(plain.status, 426);
});

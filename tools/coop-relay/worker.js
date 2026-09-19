// The co-op relay: a pipe with a memory. One Durable Object per room code;
// everything a peer sends is appended to the room's log and forwarded to the
// other peer, and anyone who connects is first sent the whole log. That one
// rule is what makes a fresh join and a rejoin the same thing on the client
// (core/coop.gd): rebuild from the setup, replay the rest.
//
// What it knows about the game is deliberately small:
//   - a room has two seats, host and guest, named in the URL (?role=). A new
//     socket in a seat evicts the old one — a crashed peer's socket can linger,
//     and the player pressing "join" again is the truth about who is there.
//   - `from` is stamped by the relay from the seat, never trusted from the client.
//   - a `setup` (host only) starts a new fight: the log is cut back to it, so
//     a rejoin replays this fight and not every fight before it.
//   - `owners` from the setup gate perform/move: a hero's presses come only
//     from its owner. swap/go are the host's. end_turn cannot be checked
//     without knowing whose turn it is, which is the game's business.
//   - `hover`, `map` and `world` (the host's map, mirrored to the guest) are
//     forwarded and never logged; `peers` is the relay's own, sent to
//     everyone whenever a seat changes.
// Turn order is what keeps the log meaningful: only the peer whose hero is up
// sends, so "the order the relay received them in" and "the order they were
// applied in" are the same order. State hashes ride on end_turn and the peers
// compare them themselves.

const CODE = /^\/room\/([A-Z2-9]{6})$/;    // Coop.ALPHABET: no 0/O/1/I
const ROLES = ["host", "guest"];
const MAX_MESSAGE = 256 * 1024;            // a setup is ~20 KB; a whole map save ~50 KB
const EPHEMERAL = ["hover", "map", "world"];   // forwarded, never logged: the host resends what matters
const EXPIRE_MS = 24 * 60 * 60 * 1000;     // a room nobody has spoken in for a day is gone

export class Room {
  constructor(ctx) { this.ctx = ctx; }

  async fetch(req) {
    if (req.headers.get("Upgrade") !== "websocket") {
      return new Response("expected a websocket", { status: 426 });
    }
    const role = new URL(req.url).searchParams.get("role");
    if (!ROLES.includes(role)) return new Response("role must be host or guest", { status: 400 });
    for (const old of this.live(role)) old.close(4000, "seat taken by a newer connection");
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [role]);   // hibernates between turns; the tag survives it
    const log = (await this.ctx.storage.get("log")) ?? [];
    server.send(JSON.stringify({ t: "replay", log }));
    this.peers();
    return new Response(null, { status: 101, webSocket: client });
  }

  // A socket that has just been closed (evicted, or gone) can still be listed
  // until the close completes; sending to it throws, and it is not our problem.
  send(ws, text) {
    try { ws.send(text); } catch {}
  }

  live(role) {
    return this.ctx.getWebSockets(role).filter((ws) => ws.readyState === WebSocket.READY_STATE_OPEN);
  }

  peers() {
    const roles = ROLES.filter((r) => this.live(r).length > 0);
    const msg = JSON.stringify({ t: "peers", roles });
    for (const ws of this.ctx.getWebSockets()) this.send(ws, msg);
  }

  async webSocketMessage(ws, raw) {
    if (typeof raw !== "string" || raw.length > MAX_MESSAGE) return;
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }   // the trust boundary: only JSON objects get kept
    if (msg === null || typeof msg !== "object" || Array.isArray(msg)) return;
    const from = this.ctx.getTags(ws)[0];
    msg.from = from;
    const out = JSON.stringify(msg);
    const others = this.ctx.getWebSockets().filter((p) => p !== ws);
    if (EPHEMERAL.includes(msg.t)) {
      for (const p of others) this.send(p, out);
      return;
    }
    // ponytail: the whole log is one value, rewritten per message. A fight is a
    // few hundred small messages; switch to one key per entry if that changes.
    let log = (await this.ctx.storage.get("log")) ?? [];
    let owners = (await this.ctx.storage.get("owners")) ?? {};
    switch (msg.t) {
      case "setup":
        if (from !== "host") return;
        owners = (msg.owners && typeof msg.owners === "object") ? msg.owners : {};
        await this.ctx.storage.put("owners", owners);
        log = [];   // a new fight supersedes the last
        break;
      case "swap": case "go":
        if (from !== "host") return;
        break;
      case "perform": case "move":
        if (owners[msg.hero] !== from) return;
        break;
    }
    log.push(msg);
    await this.ctx.storage.put("log", log);
    await this.ctx.storage.setAlarm(Date.now() + EXPIRE_MS);
    for (const p of others) this.send(p, out);
  }

  async webSocketClose(ws) { ws.close(); this.peers(); }
  async webSocketError(ws) { ws.close(); this.peers(); }

  async alarm() { await this.ctx.storage.deleteAll(); }
}

export default {
  fetch(req, env) {
    const m = CODE.exec(new URL(req.url).pathname);
    if (!m) return new Response("not found", { status: 404 });
    return env.ROOMS.get(env.ROOMS.idFromName(m[1])).fetch(req);
  },
};

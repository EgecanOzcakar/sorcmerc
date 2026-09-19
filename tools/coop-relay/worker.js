// The co-op relay: a dumb pipe with a memory. One Durable Object per room
// code; everything a peer sends is appended to the room's log and forwarded
// to every other socket in the room, and anyone who connects is first sent the
// whole log. That one rule is what makes a fresh join and a rejoin the same
// thing on the client (core/coop.gd): rebuild from the setup, replay the rest.
//
// The relay knows nothing about the game — not turns, not ownership, not
// hashes. Turn order is what keeps the log meaningful: only the peer whose
// hero is up sends, so "the order the relay received them in" and "the order
// they were applied in" are the same order. The peers check each other's
// state hashes themselves (see Coop.state_hash); the relay just carries them.
//
// Spike scope (docs/spike-coop.md): no room expiry, no peer limit, no
// ownership check — a room code is the only secret, and it is a friend's.

const CODE = /^\/room\/([A-Z2-9]{6})$/;   // Coop.ALPHABET: no 0/O/1/I
const MAX_MESSAGE = 64 * 1024;        // a setup with a full party is ~20 KB

export class Room {
  constructor(ctx) { this.ctx = ctx; }

  async fetch(req) {
    if (req.headers.get("Upgrade") !== "websocket") {
      return new Response("expected a websocket", { status: 426 });
    }
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server);   // hibernates between turns: an idle room costs nothing
    const log = (await this.ctx.storage.get("log")) ?? [];
    server.send(JSON.stringify({ t: "replay", log }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, raw) {
    if (typeof raw !== "string" || raw.length > MAX_MESSAGE) return;
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }   // the trust boundary: only JSON objects get kept
    if (msg === null || typeof msg !== "object" || Array.isArray(msg)) return;
    // ponytail: the whole log is one value, rewritten per message. A fight is a
    // few hundred small messages; switch to one key per entry if that changes.
    const log = (await this.ctx.storage.get("log")) ?? [];
    log.push(msg);
    await this.ctx.storage.put("log", log);
    for (const peer of this.ctx.getWebSockets()) {
      if (peer !== ws) peer.send(raw);
    }
  }

  async webSocketClose(ws) { ws.close(); }
}

export default {
  fetch(req, env) {
    const m = CODE.exec(new URL(req.url).pathname);
    if (!m) return new Response("not found", { status: 404 });
    return env.ROOMS.get(env.ROOMS.idFromName(m[1])).fetch(req);
  },
};

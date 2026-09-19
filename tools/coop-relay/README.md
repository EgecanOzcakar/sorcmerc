# The co-op relay

A Cloudflare Durable Object, one per room code, that forwards a co-op room's
messages between its peers and replays the whole room to anyone who connects.
It is the spike's transport — `docs/spike-coop.md` says why this and not
Godot's ENet, WebRTC or Supabase. It knows nothing about the game.

## What it costs

Nothing. Durable Objects (the SQLite-backed kind, which is what
`wrangler.toml` declares) are on the Workers free plan; with the hibernation
API an idle room costs nothing between turns, and a whole fight is a few
hundred messages of a few dozen bytes.

## Run it locally

```
npx wrangler dev          # ws://127.0.0.1:8787/room/ABCDEF
node --test               # end to end against wrangler dev, on port 8799
```

## Deploy

```
npx wrangler deploy       # prints the URL; the game wants wss://<that>
```

That URL is `Coop.RELAY_URL` in `core/coop.gd`; `SORCMERC_RELAY` overrides it
for one run.

## Protocol

Connect to `/room/<CODE>?role=host|guest` (six characters from
`A-HJ-NP-Z2-9`). A room has those two seats and no more; a new socket in a
seat evicts the old one, which is what lets a crashed peer come straight
back. The first message back is `{"t":"replay","log":[...]}` — the current
fight, in the order the relay received it. After that, every JSON object you
send is stamped with your seat as `from`, appended to the log and forwarded
to the other seat, with these exceptions:

- `setup` (host only) starts a new fight: the log is cut back to it, and its
  `owners` (hero id → seat) gate what follows.
- `perform` / `move` are kept only from the seat that owns `hero`;
  `swap` / `go` only from the host. `end_turn` and `reaction` cannot be
  checked without knowing whose turn it is, which is the game's business.
- `hover` is forwarded and never logged.
- `{"t":"peers","roles":[...]}` is the relay's own, sent to everyone whenever
  a seat changes.

Frames that are not a JSON object, or over 64 KB, are dropped. A room nobody
has spoken in for 24 hours is deleted. Ordering across peers is the game's
problem, and in a turn-based game it is no problem: only the peer whose hero
is up sends.

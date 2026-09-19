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

Then start the game with `SORCMERC_RELAY=wss://sorcmerc-coop-relay.<you>.workers.dev`.

## Protocol

Connect to `/room/<CODE>` (six characters from `A-HJ-NP-Z2-9`). The first
message back is `{"t":"replay","log":[...]}` — every JSON object anyone has
sent to that room, in the order the relay received them. After that, every
text frame you send is appended to the log and forwarded to the other sockets
in the room; frames that are not a JSON object, or over 64 KB, are dropped.
That is all of it. Ordering across peers is the game's problem, and in a
turn-based game it is no problem: only the peer whose hero is up sends.

Not built (spike): room expiry, peer limits, any check on who may send what.

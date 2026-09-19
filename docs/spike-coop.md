# Spike: two-player co-op over a room code

2026-09-19. Started as a feasibility spike — "can two people play one
sorcmerc fight together, joining by a code instead of a friend list, and what
does that cost?" — and, the answer being yes and cheap, grew the same day into
the feature: **Play together** on the title screen. Nothing changes for a
player who never presses it (`Coop.link` stays null and every hook is behind
it). The fight is turn-based and already deterministic, so the whole thing is
~400 lines of GDScript, a 100-line Cloudflare Worker, and no change to
`core/combat.gd`.

What is on the branch:

- `core/coop.gd` — the seam. Turns a combat-screen press into a small JSON
  intent and back, hashes a fight's state, serialises the setup a guest needs,
  holds the session (`Coop.link`, the host's `Coop.split`), and wraps a
  `WebSocketPeer` to the relay.
- `tools/coop-relay/` — the relay: one Durable Object per room code, two
  seats, the fight's log, expiry.
- `scenes/game/game.gd` — the lobby (host a room, join a room) and the
  guest's between-fights screen. The host then plays the game exactly as
  single player; every fight their world puts up is announced on the room.
- `scenes/main.gd` — ~150 lines under `_coop`: the host's "who plays whom"
  before each fight, each local press sent, a remote-owned hero's turn driven
  from the wire, reaction prompts routed to the reactor's owner, the acting
  player's cursor shown to the watcher.
- `tests/test_coop.gd` — two fights in lockstep over 40 seeds, hashes equal
  after every intent; a third peer that rebuilds from setup + log to the same
  hash; the same again with reaction prompts answered by the owner and
  replayed to the rejoiner (357 checks).
- `tools/coop-relay/relay.test.js` — the relay end to end on the real Worker
  runtime (`wrangler dev`): replay-on-join, fan-out, rejoin, seats, ownership,
  new-fight cut, hover, refusals.
- `tests/drive_coop.gd` + `tools/coop_smoke.sh` — two real headless Godot
  processes on the real combat screen through the real relay, in four
  variants: the guest killed mid-turn and rejoined; the host killed and
  rejoined; the host's socket closed under it mid-fight and reconnected; the
  guest coming in through the title screen's Join. All end on the same state
  hash. A fifth walks the road: the host's open world marches into a hunting
  band, both play the fight, both are back on the map at the same spot, the
  host opens a market and the guest's screen shows it greyed, and the guest
  takes a level on their hero that lands on the host's copy.

## 1. Turn-based is the whole design

Nothing here rolls back, predicts, or ticks. A fight is a seed and an ordered
list of what the players pressed; `core/combat.gd` is a pure `RefCounted`
whose every roll goes through the seeded `core/rng.gd`, and "Replay seed" has
been a dev button for months. So both peers just run the same fight —
**lockstep** — and the only things that cross the wire are the six calls
`scenes/main.gd` already makes: `perform(hero, verb, target)`, `move_to`,
`end_turn`, and a deployment swap. Foe turns run `core/ai.gd` on both sides
from the shared rng; nobody "owns the monsters".

The alternative, host-authoritative with state snapshots, needs a combat
serialiser — 2,800 lines of resolver with Callables, object references in
zones and concentration, summons spawned mid-fight. There is none, and writing
one is weeks. Lockstep needs nothing; what it costs instead is that any
non-determinism is a silent desync, so `Coop.state_hash` (rng state, turn,
round, every combatant's pos/hp/econ/statuses/slots) rides on every
`end_turn` and the receiver compares. `tests/test_coop.gd` found none over 40
seeds × full fights × ~800 intents; the audit of what *could* break it is in §6.

## 2. Transport: a Cloudflare Durable Object, not ENet and not Supabase

| | NAT / no port forwarding | web export | needs a server anyway | ordered + stored log |
|---|---|---|---|---|
| Godot ENet (high-level multiplayer) | no — direct IP or forwarding | no | no | no |
| Godot WebRTC | mostly (fails without TURN for some pairs) | GDExtension | yes — signalling | no |
| Supabase Realtime broadcast | yes | yes | account + hand-rolled Phoenix channels over `WebSocketPeer` | no — fire and forget; rejoin needs a table too |
| **Durable Object relay** | yes | yes (`WebSocketPeer` is built in) | yes — 60 lines | **yes, for free** |

ENet is out on the first column alone for a casual co-op game, and it does not
exist on the web export. Supabase would work, but sorcmerc already has a
Cloudflare account and a deployed Worker (`tools/bug-relay`), and the one
thing a Durable Object gives that a broadcast channel does not is the thing
that makes rejoin trivial: the room's log is ordered and stored *by the
relay*, and replayed to whoever connects. A fresh join and a rejoin are the
same message.

Cost: SQLite-backed Durable Objects are on the Workers free plan (verified
2026-09-19 on developers.cloudflare.com); with the hibernation API an idle
room costs nothing between turns; a whole fight is a few hundred messages of
a few dozen bytes. "Sorcmerc has no backend" becomes "sorcmerc has two
Workers with the same deploy story", and the game is fully playable with the
relay URL unset.

## 3. The room code is the design, not a stopgap

Six characters from `A-HJ-NP-Z2-9` (no 0/O/1/I — it gets read out loud over a
call), generated by the host, shown in the combat header, typed by the guest.
No accounts, no friend graph, nothing stored about anybody. For a two-player
co-op D&D game this is not a placeholder for a friends list; it is the right
permanent design — Jackbox has shipped on it for a decade. The only thing a
friends list would add is "play again with the same person", which a code in
a chat message already does.

## 4. One shared party, not two parties

**Spiked: each hero in the shared party is owned by one peer.** Heroes
alternate host/guest in party order (Vera → host, Pike → guest, Ilsa → host);
the peer whose hero is up presses, the other watches the same board update.
This is what the engine already does with one line changed: `_advance()` has
always branched on "whose turn is this" (foe → AI, hero → menu); co-op adds
"remote-owned hero → wait for the wire".

"Each player brings their own party" is a different game. It would need: two
parties in one encounter (the roster estimator and every "party" call in the
resolver assume one), initiative interleaving across parties, targeting rules
across them (can I heal yours? shove yours?), and a decision on whether it is
co-op or PvP at all. And it makes the actual problem — waiting — worse, not
better: twice the heroes is twice the interval between your turns. The
game-designer's read is the same: if shared-party co-op fails the fun test,
the fix is fewer, faster turns, not more bodies.

## 5. State authority, disconnects, rejoin — what was tested

**Authority.** Nobody; both peers are authoritative over their own copy and
turn ownership serialises the writes. Only the peer whose hero is up sends,
so "the order the relay received them in" is "the order they were applied
in". Each peer applies its own press immediately (optimistic) — safe because
the other peer is provably not sending during your turn. The relay enforces
the part it can see: a hero's `perform`/`move` are accepted only from the
seat the setup named as its owner, `setup`/`swap`/`go` only from the host,
and `from` is stamped from the seat, never read from the client.

**Disconnect.** The relay keeps the log; the other peer's screen says
"your friend's turn" and blocks. No host takeover, no timeout: that needs
ownership reassignment *in the log* and a relay-enforced clock, and is the
wrong thing to get subtly wrong first.

**Rejoin** = connect with the same code, receive the replay, rebuild from the
setup, apply the log. Same code path as a first join. Foe turns replay
without the animation beats. A new socket in a seat evicts the old one, so a
crashed peer's lingering socket never blocks its own return. A socket that
merely drops (a sleep, a hiccup, a relay restart) is reopened by the link
itself two seconds later, and the replay it gets is applied the same way —
the fight is rebuilt under whatever turn loop was suspended, which notices
(`_gen`) and ends, so a peer never goes blind for the rest of a fight. Cases found and
fixed by the smoke test: (a) the log ends *mid-turn on the rejoiner's own
hero* — the replay must hand that half-finished turn back to the local menu
rather than wait for "the other player" (who is waiting for you); (b) a
rejoining host must not announce a second setup; (c) the lobby's host, whose
world starts a new fight, must ignore a stale replay from the room.

**Tested:** lockstep headless (40 seeds, and 10 more with reaction prompts);
the real relay with two real Godot processes — guest killed mid-turn and
rejoined, host killed and rejoined, host's socket dropped and reconnected
mid-fight, guest in through the title screen, and the road itself (map →
fight → map → a mirrored counter → a guest's level-up applied on the host)
— all finishing on the same hash; the level-up screen's step transcript
replayed onto a second copy of the character gives an identical sheet
(`test_coop.gd`); relay seats, ownership, replay, new-fight cut,
hover, expiry wiring in `relay.test.js`.

**Not tested:** a disconnect *during* a foe turn's animation on one side;
two peers with different Godot builds (desktop vs web — the web export
cannot run headless here); latency above localhost; the relay's 24-hour
expiry actually firing (the alarm is set; a day was not waited); a site
delve or a linear-campaign fight with a live guest (same hand-off as the
road fight that is tested, but not walked); anything with three peers.

## 6. What could still desync

`core/rng.gd` and `Dice` are the only dice. Board generation uses Godot's
`RandomNumberGenerator`, explicitly seeded. Dictionaries iterate in insertion
order. Seed 0 falls back to the clock in two places (`rng.gd:10`,
`encounter.gd:398`) — the setup asserts it is nonzero. `_roll_initiative`
uses `sort_custom`, which is not stable, but both peers sort the same input
in the same order on the same engine version. The one data-dependent float is
`int(speed * 0.5 * mult)` at `combat.gd:347`; `econ` is in the hash so it
would show. The real risk is the web export: GDScript floats are f64 on both,
but it is the pairing the smoke test does not run.

**Reaction prompts** are answered by the reactor's *owner* — through the
card if their prompts are on, else the auto-yes the resolver always gave —
and the answer crosses the wire as a `reaction` message; the other peer waits
on it. Both peers reach the same prompts in the same order (they run the same
resolver), so answers are consumed in order, which is also what lets a
rejoiner replay them. Both peers install the co-op decider whatever their
setting: with it unset on one side that side would auto-resolve, and the
two would diverge on the first refused Shield.

## 7. The campaign layer: the host runs the road

Co-op across the world map was the big open design question, and the answer
that costs nothing is the right one: **the host plays the game exactly as in
single player; the guest watches the road and is in the fights.** The host's
world, sites, camps and the linear campaign all put a fight up the same way
— instantiate `scenes/main.tscn`, hand it the party and the spec — and that
screen sees `Coop.link` and announces the fight on the room. Each `setup`
cuts the room's log back to itself on the relay, so a rejoin replays *this*
fight, not the whole run.

**The guest sees the map.** The host's world screen (`scenes/world/
world.gd`) sends the whole save (`WorldSave.to_dict`, ~50 KB) when the guest
sits down and on every autosave — the world already autosaves on everything
structural: an arrival, a visit, a fight banked, a rest — and between those
a delta twice a second: the clock and where every party stands (~100
bytes). The guest's screen is the same `world.gd` with `spectator = true`:
it never ticks, never orders, never saves; positions and the clock come off
the wire, fog of war is revealed from them with the same `world.reveal`,
and the camera is the guest's own to pan, turn and zoom. The HUD keeps the
clock and the purse, loses every order, and gains *Leave the room*. When a
fight opens, the guest's screen is the fight; when the host banks it, the
autosave's full save puts the map back — camera carried over.

**The guest sees the counter.** A settlement visit is one panel with four
pages (square, market, inn, notice board), built from the host's market
dict. Every time the host's panel rebuilds — a page, a buy, a haggle — the
dict goes over the wire (minus the settlement object; its id goes) with the
purse and the shelf, which move on every buy without an autosave, and the
guest's screen builds the same panel from it with every button greyed. When
the host leaves, so does the panel. "Buy the potion, not the sword" is now a
conversation two people can have.

**The guest takes their own hero's levels.** A hero levels on the screen of
whoever plays them: the #118 "level waiting" panel names only your own, and
the party screen's *Level up* is greyed on a friend's ("the level is theirs
to take"). The guest's panel opens the real level-up screen on their
mirrored copy of the hero; every step it makes — `add_level`, then each
`decide(key, decision)` — is recorded, and on Confirm goes to the host as
one `levelup` message. The host makes the same steps on the real character,
saves it, autosaves the world, and the guest's copy is replaced by the truth
a moment later. This works because a character's choices were already data:
the same `decide` dictionaries the creator writes. The guest's copy is never
written to their own barracks (`persist = false`), and a full-save rebuild of
the guest's map is held back while their level-up screen is open.

What the guest still does not get: a hand on the road. Buying, resting,
taking a job, choosing the route and the save are the host's. Sharing
*control* of those — two hands in one purse, a vote on the route — is a
different design; the fight and the guest's own heroes are where two hands
belong, and the watching problem the game-designer named is solved by
seeing. Market purchases by the guest would be the next step if the purse
turns out to be table-talk rather than friction: host-authoritative
requests, ~35 lines. "Each player brings their own party" stays out, for
§4's reasons.

**Same build on both ends.** Lockstep on different code is a desync waiting
for its first roll, so the setup carries a build stamp (the game version and
the Godot version) and a guest on a different one is told so at the door.

## 8. What is still not built

- **Host takeover** of an absent player's hero after a timeout (§5).
- **The guest's map is a mirror, not a model.** An NPC band that appears or
  vanishes between two autosaves is a few seconds late on the guest's map;
  the event cards, the camp and the party screen the host is reading do not
  show — the guest sees the party stop and the clock pause. The counter does
  show (§7). A ticker line of "what the host is doing" would be cheap.
- **Guest purchases** (§7): the guest reads the counter and advises; the host
  presses Buy.
- **Three or more players.** The relay has two seats; the split is host/guest.
- **Hover replication is the cursor and the verb in hand**, not the aimed
  target list — the watcher sees the reach wash and the hot hex, not the
  per-target rings (`_mode == "target"` stays local).

## 9. Play it

Title → **Play together** → *Host a room*: a six-letter code appears; read it
out. Then *Resume the open world*, *New run* or *Quick fight* as usual —
before each fight, click a hero's name to hand it to your friend, then Begin.
Your friend: **Play together** → type the code → *Join* → your map appears on
their screen as soon as you are on it, and every fight opens on both.

The relay is `Coop.RELAY_URL` (`tools/coop-relay`, `npx wrangler deploy`
once from that directory); `SORCMERC_RELAY=ws://127.0.0.1:8787` points a run
at a local `wrangler dev`. The bare combat scene still takes
`SORCMERC_COOP=host` / `=CODE` / `=host:CODE`, which is what
`tools/coop_smoke.sh` and `tests/drive_coop.gd` use.

The one thing to watch in a real two-person session, per the game-designer:
**does the watching player talk about the active player's turn?** ("hit the
one on the left", "save your slot, I've got him"). If they are advising, the
loop works and the UI's only job is to make advising easier. If they are on
their phone, no amount of UI fixes it.

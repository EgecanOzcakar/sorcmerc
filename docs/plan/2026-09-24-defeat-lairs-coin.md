## Defeat, lairs and coin — the costs you could walk around (2026-09-24)

Five of the owner's calls on the design audit (docs/audit-game-design.md,
"The owner's calls"), each closing a side door that let a cost the rest of the
design is built on be skipped for free. None of them moves a measured number:
the sweeps never used these doors, which is why they never caught them.

**A lost fight revives the downed only (§1.2).** `_retreat()` used to call
`Party.auto_revive_all`, which stood up every dead member of the roster, the
benched dead of earlier fights included — so below about 2,000 ◉ carried,
losing a fight was cheaper than a 300 ◉ raise at the healer. The open world
now calls `Party.revive_downed` (`core/party.gd`): anyone alive at under 1 HP
comes to at 1, which keeps the soft-lock fix the old function was written
for, and the dead stay dead and benched until a healer or Revivify raises
them. The road now applies the fight's deaths *before* the retreat, the order
a site wipe already used, so neither path can stand this fight's dead up. The
pit's lost bout uses the same function, with that bout's fallen passed as
`carried_out` — the pit is a brawl for a purse, not a death match, but it is
no longer a way to raise the dead of earlier fights either. The linear run
keeps `auto_revive_all` for its own end-of-run rule (T10). If nobody who
marched is left standing, the living bench marches in their place. If the
whole roster is dead there is no open-world end screen to send the company to,
so the highest-level hero comes to alone (a `ponytail:` in `revive_downed`).
The map's line names this fight's dead and says what brings them back
(`Party.defeat_line`): "The company is beaten and left for dead. The living
come to at Riverhold, 60 ◉ lighter. Vera Kord did not get up. A healer can
raise the dead, at 300 ◉ a head."

**A lair resets on re-entry, and is priced with every slot back (§1.3, §3.3).**
`Site.for_lair` used to resume a withdrawn delve at the depth it reached, and
price the lair off `Scaler.party_score` — the slots the party had left at the
door — so walking in drained, or backing out and back in, bought a smaller
lair and a smaller boss. Now every entry starts at the mouth, and the reading
is `Regions.fresh_score`, the same full-slot reading the open world pins its
fights to. The in-delve hold (`_held()`, `Scaler.held_at(entry_score, now)`)
is unchanged in form and now pins every room, the first included, to that
fresh reading, so slots spent before the door and slots spent on the way down
are both invisible to the budget. For a rested party the two readings are the
same, so the site sweeps' numbers still describe what they measured. Walking
out is a wipe's reset without its toll on the bag. The coin already carried
out stays carried out: `Lair.caches_taken` (saved, default empty) keeps an
emptied cache empty on the next entry, or walking in and out of the first
floor would refill a purse for nothing; `WorldLairs.respawn` clears it with
the rest. The 2,880-minute window now reads "how long you have to try it
again from the top".

**A potion of healing costs 50 ◉ (§1.4).** The SRD files every grade under one
`potions-of-healing` heading with rarity "varies", which `VARIES_TIER` priced
as rare — 2,025 ◉ for the 2d4+2 potion the game pours. `Campaign.PRICE_OVERRIDE`
prices it at 50, the 2024 PHB's Potion of Healing. The lodge's herb garden now
takes 22 potions sold to pay back the house and garden, not one, and the
alchemist's cheapest cure costs about a night at the inn. Every other "varies"
item still prices as rare.

**The table is once a day per town, and the house wins (§1.5).** The game was
stamped with the visit, so stepping out of the gate re-armed it, and it paid
1.5x/2x/3x, a positive return from +2 up. It is now stamped with the world-day
(`party.downtime["gambled_day"]`, seeded off the town and the day), and the
payouts follow the owner's call that the lowest win pays the stake back: DC 13
returns the stake, 25 or better pays half again, a natural 20 still trebles
it, and a natural 1 always loses. EV (exact, d20 arithmetic): +0 0.500,
+2 0.600, +5 0.750, +7 0.900, +8 0.975, +9 1.050 — below 1 through +8, even
money only from +9. The table is in `core/downtime.gd`'s header and the test
enumerates it face by face. A second game the same day is refused, and the
row says why.

**A failed parley costs opinion (§3.1).** A failed parley was exactly Engage,
so it was a free roll before every fight with anything that talks. Now it
lowers the band's people's opinion by `FactionOpinion.PARLEY_REFUSED` (5, a
taste number the size of the inn's insult), and both the card's row and the
result line say so ("…and the humans will hear that the company tried to buy
them"). Only a people that keeps an opinion pays it — `WorldAI.CIVILIZED`, the
rule `contracts.gd` and the road's `KILLED_THEIRS` already follow — so a
bandit who will not be bought is still only the fight. A failed parley that
cost opinion is drawn as a setback card.

Screenshots (`tests/shot_defeat_lairs_coin.gd`, under xvfb): the map's line
after a lost fight (`docs/shots/defeat-lairs-coin-defeat.png`), the inn's game
played and refused for the day (`defeat-lairs-coin-gamble.png`), a human
patrol's approach card with parley's cost on the row
(`defeat-lairs-coin-parley-card.png`) and the failed parley
(`defeat-lairs-coin-parley-failed.png`).

### Still open

- **A failed parley with a monster band still costs nothing extra.** Monster
  factions keep no opinion, and most parleys are with bandits and goblins. The
  audit's other two options (the toll anyway, or their round one) were not the
  owner's call; revisit if parley still reads as a free roll in play.
- **No open-world end screen.** A company whose whole roster died keeps one
  hero (the `ponytail:` in `Party.revive_downed`). When the open world gets an
  end-of-run summary, a wiped company should end there instead.
- **The map's message line does not wrap.** The bottom bar is one unwrapped
  row, so a long line (the defeat line, a site wipe's list of lost items, a
  withdrawal) runs off the right edge at 1400 px wide; the screenshots are
  taken at 2800. This predates this entry; the new lines only make it show.
- **Healing potions still drop one band up** (`core/loot.gd`, a `ponytail:`):
  the pricing reason is gone, but moving them to "common" changes what the
  lowest-CR kills hand out, which is the economy pass's call (§5.1).
- **Old saves:** a lair withdrawn from under the old rule restarts at the mouth
  on its next entry, and an old save's once-a-visit gambling stamps are not
  read (no town counts as played today).

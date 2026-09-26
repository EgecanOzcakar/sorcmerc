## How other games do random events — research for the road (2026-09-26)

The owner asked, once #231's spike was done, for the games we follow closely —
Crusader Kings III, Solasta, Baldur's Gate 3, Battle Brothers, FTL, Darkest
Dungeon, Slay the Spire, Mount & Blade, Pathfinder — to be looked at for how
their random events work, for ideas. Two sourced research passes (one on CK3's
event scripting in depth, read partly from the game's own script files; one on
the rest) are written up in `docs/research-road-events.md`: what each game
does, with links, and twelve proposals mapped onto `core/road_events.gd`,
ordered by value.

No code changed. The research's headline finding about our own road: with
seventeen events and a question every six hours of travel, **repetition is the
biggest risk today** — the road has no cooldowns, no one-time events, no
"nothing happens" weight and no memory of the last event, which is exactly
what CK3's players complain of in its travel events.

### Still open

The proposals, as the document orders them, each waiting on the owner's go:

- **Small, one PR:** per-event cooldowns, one-time events, a "nothing" weight
  and no repeat of the last event; degrees of success (triumph and disaster
  bands, natural 20/1); an item that makes a choice certain; pacing that
  grows between events and pauses after a fight; text variants.
- **Blue options and cast roles** (who is in the company changes the choices,
  and the same hero comes back through a chain) — the owner's call on which
  hero facts may gate a choice (background, class, species, trait, skill).
- **Traits push back** — morale for acting against a trait, and compulsive
  traits that sometimes choose for the player; the owner's call on how often.
- **Weights from the world**, and **follow-ups waiting at a place, marked on
  the map**.
- **Threads with their own clock** (CK3's story cycles) and **standing
  problems** (Bannerlord's issues), later.
- More events, alongside all of it (#234).

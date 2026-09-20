# Named foes ("grudges") — the patent read, and a version that stays clear of it

A2 from the 2026-09-20 content menu: a foe that survives a fight with the
party comes back with a name, a level and a bounty. The question raised
before building it: isn't that Warner Bros' Nemesis System, and is it safe to
build anything like it? This note answers with the claims in hand and lays
out the version of the feature that does not touch them. It is an engineering
reading of a public document, not legal advice; the last rule below says
what to do about that.

## 1. What the protection actually is

It is a **patent**, not a copyright. Copyright protects expression — code,
art, text — and does not reach game mechanics at all. A patent can. WB holds
**US 10,926,179 B2**, "Nemesis characters, nemesis forts, social vendettas and
followers in computer games": filed 25 March 2016 on a 2015 priority, granted
23 February 2021, adjusted expiry **11 August 2036**, assignee Warner Bros.
Entertainment Inc. It is a US patent; whether counterparts were granted
elsewhere was not checked, and would matter for a game sold outside the US.

"Nemesis System" is also the name WB uses for the feature. Treat it as their
mark: it never appears in this game's code, UI, docs or store copy.

## 2. What the claims say

Three independent claims; everything else depends on one of them and only
matters if its parent is met.

- **Claim 1 (the method).** Control game events involving the player's avatar
  and a *first* NPC driven by a first set of parameters; detect a predefined
  event involving that NPC; **change a second set of parameters that controls a
  second, different NPC** because of that detection; show the change.
- **Claim 20 (forts).** Build a "nemesis fort" from a template, socket
  locations, and dynamic object groups matched to the overlord's traits.
- **Claim 28.** A storage medium carrying the method.

Dependent claims 2–19 narrow claim 1: also changing the first NPC (2);
narrative triggers such as the avatar's death, time passing, entering a zone
(3–5); dialogue chosen from the prior event (6); a faction hierarchy with ranks
tied to power, rank changes, a third NPC changed by changes to the first two
(7–10); appearance, personality and interaction-score changes (11–13); power
centres (14–17); sharing the faction data across players through a server —
the "social vendetta" (18–19).

## 3. The reading

The engine of claim 1 is **propagation between NPCs**: what happens to one
changes another. Kill the captain and his lieutenant is promoted; the orc who
kills you rises through a hierarchy; a vendetta passes to a brother; a fort is
rebuilt around whoever now holds it. That is the whole Nemesis System, and it
is what the claim protects.

What the claim does not describe is one NPC changed by **its own** history.
Claim 2 has to add "also change the first NPC" precisely because claim 1 is
about the second one. A foe that fled you and comes back a level higher, with a
scar and a line about it, is Battle Brothers' named enemies (in early access
from 2015, before this filing), a roguelike's ghost, a boss that remembers the
last attempt. None of that is the patented combination.

One honest caveat. Read at its broadest, claim 1 also describes every
reputation system since the 1990s — kill guard A and guard B turns hostile —
and so describes `core/faction_opinion.gd` as shipped. That says more about the
claim's breadth than about the risk: nobody has been sued over a reputation
system, and the practical exposure is *looking like* the Nemesis System, not a
literal reading of an over-broad claim. The rules below are chosen so the
feature neither reads on the claims nor resembles the product.

## 4. Rules for our version

1. **One individual, one memory.** A named foe's state changes only through
   events it was part of: it fled, it won, it was left alive. It never grows
   because a different NPC died or was beaten.
2. **No hierarchy, rank, promotion, succession or inheritance.** When a named
   foe dies its story ends. Nothing steps up, no brother comes for revenge, no
   band re-forms around a new chief whose stats derive from the old one. A band
   that loses its named chief is a band with no chief.
3. **No forts.** A named foe has no lair shaped by its traits. Lairs come from
   `core/world_lairs.gd` and `core/site.gd`, seeded off the map, and never read
   the foe.
4. **Never shared.** Named foes live in one save. In co-op the guest sees the
   host's foe through the world mirror (`Coop.world_full`), and nothing crosses
   save files, servers, or another player's game (claims 18–19).
5. **Its own name.** "Grudges", "named foes", "old enemies" — never the mark.
6. **If it ships in a paid product, buy an hour of a patent attorney's time on
   this note first.** It is cheap, and it turns an engineering reading into an
   opinion someone stands behind.

## 5. The design (deferred — not in the current batch)

- **Origin.** A foe that survives a fight with the party is given a name from
  `core/enemy_names.gd`: it fled (the hunt objective's escape from spec #1), or
  the party withdrew or lost (`world.gd`'s `_retreat()`), or a site was left
  part-cleared with it standing. One name per fight at most, and only for a
  foe that is a band's strongest or a site's boss — a named goblin archer is
  noise, a named warren chief is a grudge.
- **Ledger.** In `WorldSave`: `{id, monster_id, name, faction, bumps,
  met: [{day, what}], last_seen, dead}`. `bumps` counts *its own* escapes and
  wins, capped at 3, and is the only thing that ever raises its `mult`. Rule 1.
- **Return.** It rides in a roaming band of its faction spawned by
  `core/world_ai.gd`, as that band's leader, at `mult` raised per bump. The
  approach card names it and says why you know it: "Skarn the Limper, who fled
  you on day 12." Every fight with it is an ordinary fight; if spec #1's hunt
  objective is in, the band is a hunt with the foe as quarry.
- **The bounty.** The settlement nearest its last sighting posts a `hunt_party`
  job on its band (`core/quest_posting.gd` already posts hunt jobs); killing it
  pays the job and writes the deed to the journal and to achievements.
- **Barks.** One line on meeting, from its own ledger ("You again." / "I
  remember the one with the staff."). Claim 6 depends on claim 1; a line chosen
  from the foe's own history is fine under rule 1.
- **Death.** `dead: true` in the ledger. Nothing else in the world changes
  because of it — no successor, no band reshuffle, no fort. Rule 2.
- **Cost.** `enemy_names.gd` exists; a ledger in `world_save.gd`; a hook in
  `_launch_combat`/`_retreat`/site withdrawal; a line on the approach card; a
  spawn override in `world_ai.gd`; a posting hook. About the size of D5
  rumours.

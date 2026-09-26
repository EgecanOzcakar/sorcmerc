# How other games do random events — and what the road should borrow

*Research for #232 / #234, 2026-09-26. Owner's ask: look at the games we follow
closely — Crusader Kings III, Solasta, Baldur's Gate 3, Battle Brothers, FTL,
Darkest Dungeon, Slay the Spire, Mount & Blade, Pathfinder — for how their
random events are chosen, gated, priced, chained and kept from repeating, and
turn that into ideas for the road (`core/road_events.gd`,
`data/road_events.json`, `docs/plan/2026-09-26-the-road-asks.md`).*

Sourcing: two research passes with sources. Where a fact was read in a game's
own script or data files it is marked **[code]**; where it comes only from a
search summary of a wiki or forum page that refused a direct fetch, **[summary]**;
anything not confirmed, **[unverified]**. Links are to the pages that were read.

---

## 1. What we have today, for comparison

- **One pulse.** Every `Travel.EVENT_INTERVAL` (360 world-minutes) of actual
  travel the road *always* asks, if any event is eligible
  (`world.gd`'s `_check_travel` → `RoadEvents.pick`).
- **Pick:** a follow-up that is due, first; else a weighted pick (`weight`)
  among events whose `bands` and `needs` fit. **No cooldowns, no "not the same
  as last time", no "nothing happens" weight, no one-time events.**
- **Choices:** 2–3; a check (`skills`, `dc`, `role` — the standing order for
  scout or watch rolls, else the party's best), `spells` (a caster answers
  without a roll), `cost.gold`, `orders` (D3's own roll), or a plain `then`.
  **Pass or fail only.** Nothing gated on who is *in* the company.
- **Outcomes:** a closed vocabulary (`RoadEvents.EFFECTS`): minutes, gold,
  hurt, heal, item, xp, opinion, reveal, trail (shown or noticed), fight,
  next (a time-delayed follow-up, saved).
- **Text:** one fixed situation, one line per outcome; `%s` is the roller.
- **Seventeen events**, two of them follow-ups. Packs can add more (§5.3).

What sorcmerc already has that the reference games build events *around*, but
the road does not yet read: **traits** (`core/traits.gd`, #176, modelled on
CK3), **party opinion / morale** (`core/party_opinion.gd`), **callings** — a
past for each background (`core/callings.gd`), **faction opinion** and
**grudges**, **backgrounds, species, classes** on every hero, and the
**determinism idiom** (outcomes seeded off the thing they belong to).

---

## 2. What each game does

### Crusader Kings III — the event machine
- **Events never fire themselves** — "they have to be fired by something in the
  script": pulses (`yearly_playable_pulse`, `quarterly_…`, a random-date yearly
  one "useful for rare events") and hooks (`on_birth_child`, `on_war_won…`).
  CK3 dropped CK2's mean-time-to-happen because it "tanked performance" and
  made frequency hard to govern: one knob per pulse beats hundreds of timers.
  ([Event modding](https://ck3.paradoxwikis.com/Event_modding), via the
  synced copy [jesec/ck3-modding-wiki](https://github.com/jesec/ck3-modding-wiki);
  Dev Diary #30 [summary])
- **Two-stage gate with an explicit "nothing".** `random_events = {
  chance_to_happen = 25  200 = 0  50 = yearly.0001 … }` **[code]**: a 25% roll
  to consult the table at all, then a weighted pick in which **`200 = 0` is
  "nothing happens"** — "good for making sure that rare events don't always
  fire just because every other possible event is invalid".
- **Hard triggers vs soft weights.** `trigger` decides eligibility;
  `weight_multiplier` (base + conditional add/factor) biases the pick by the
  world and the character: "You are being paranoid" is ×10 likelier if someone
  really is guilty or you have the *paranoid* trait **[code]**.
- **Cooldowns** as timed flags: `add_character_flag = { flag =
  had_event_yearly_1080 years = 15 }` checked in `trigger` **[code]**.
- **The cast comes from your world.** In `immediate`, lists are built from the
  court, vassals and *relations* (lover, friend, rival…), one is picked with a
  weight, and saved as a named scope (`save_scope_as = suspicious`); **the same
  text serves many casts**. Missing cast is generated as a fallback. **[code]**
- **Options:** `trigger`-gated (only a Brave character sees the brave option),
  `show_as_unavailable` (see it greyed), a trait icon on the option
  (cosmetic, separate from the gate), `dangerous`/`special` colouring, and a
  **tooltip generated from the effects** so the price is visible.
- **Stress:** an option against your traits costs stress
  (`stress_impact = { honest = medium_stress_impact_gain }`) — "not to
  prohibit or punish" but to make you "think twice about otherwise no-brainer
  decisions" (Dev Diary #31 [summary]). The same traits drive the AI's pick.
- **Chains:** a branch queues a delayed event (`trigger_event = { id = …
  days = { 5 10 } }`), saved scopes carry through the chain, variables and
  flags persist; **story cycles** are a thread with its own clock and its own
  sub-table of events (the pet dog's life, a feud) and an owner-death handoff.
- **Known failure:** players complain of the *same events over and over* and
  "event spam during travels" ([Steam](https://steamcommunity.com/app/1158310/discussions/0/7529517132617872129)) —
  an uncapped per-pulse draw from a finite table, with no memory of what was
  just seen.

### Battle Brothers — travel events keyed to the roster
- Each event is its own script with a `onUpdateScore()` that looks at the world
  and the company and returns 0 (ineligible) or a weight; the manager does a
  weighted pick **[code]** ([Legends event_manager](https://github.com/Battle-Brothers-Legends/Legends-public/blob/development/mod_legends/hooks/events/event_manager.nut)).
- **Pacing:** checked at most every 2 in-game hours, never within a minimum gap
  of the last event, never with a hostile party near or just after a battle;
  the chance **grows with the time since the last event** **[code]**.
- **Background-gated options:** `onUpdateScore` finds the relevant brother
  ("has the Druid background", "level 11+") and the screen adds his option
  only if he exists — *"%bearTamer%, you're trained to handle bears, right?"* —
  with **his name in the text**. "What choices you have available at events may
  depend on what characters you have." ([Dev Blog #43](https://battlebrothersgame.com/dev-blog-43-event-system/))
- **Outcomes** are mood on individual brothers, injuries, renown, items, and a
  scripted battle that **returns to the event afterwards** (`registerToShowAfterCombat`).
- **Repetition:** a per-event cooldown, the last event excluded from the next
  pick. ~400 events, one every 3–4 in-game days [summary].

### FTL — blue options and quest beacons
- Events are XML: `<event>` → `<text>` (or a random line from a `<textList>`)
  → `<choice>`s → a nested or loaded event; **a choice that loads an
  `<eventList>` gets a random outcome from it** **[code]**.
- **Blue options:** `<choice req="doors" lvl="3" hidden="true">` — a crew race,
  a system level, a weapon, a drone, an augment. Hidden unless met, so they
  read as a reward, not a locked door; usually the safe result; some consume
  what they name. One requirement per choice.
- **`<quest event="Z"/>` puts a QUEST marker on a beacon on the map**; Z runs
  when you get there. Placement rules: this sector or the next, never over a
  store, the exit or another quest [summary].

### Darkest Dungeon — curios and the right item
- A curio can be touched by hand (weighted outcomes) **or with the right
  provision, which usually makes the good outcome certain** (holy water on the
  fountain; the key on the cabinet). Leaving it is always an option.
  ([Curios](https://darkestdungeon.wiki.gg/wiki/Curios))
- **Quirks force interactions**: a Curious hero touches curios without asking;
  a Bloodthirsty one the torture devices — character traits *making the choice*.
- Town events are "a deck of cards" with `base_chance` and `cooldown` in JSON [summary].

### Slay the Spire — pools, pity and prices in different currencies
- A "?" room's chance of each kind (monster, treasure, shop, event) **grows each
  time it does not happen** and resets when it does — pity pacing [summary].
- **Act events never repeat; one-time events happen once a run;** shrines at
  most once an act ([Events](https://slaythespire.wiki.gg/wiki/Events)).
- **Every option pays in a different currency** — a curse, 25% of max HP, 8% of
  max HP for good — so they cannot be compared on one axis, and costs are
  **percentages** so they stay meaningful at every level.

### Mount & Blade — problems that come from the world
- Warband's quests check live state: *deliver grain* needs a village elder with
  no grain and prosperity below 40; each has an expiry and a "don't give again"
  period **[code]**.
- Bannerlord's *issues* exist because a settlement's state is bad, **cost the
  giver every day they stay unsolved**, and can be **delegated** to a companion
  with troops, checked against his skill [summary].

### Solasta — the closest template to ours
- Solasta II's own world-event template: terrain, diorama, trigger (*visible on
  map* or *random during travel*), day/night, intro text, **at most 4 answers**
  of four kinds — **normal, skill check, hidden (appears only if a passive check
  passed)**, none — each with a consequence and an optional reward; 250 words,
  answers under 5 words ([dev news](https://www.solasta-game.com/news/224-community-contest-happy-little-world-events)).
- Solasta 1: pace trades speed for awareness (advantage/disadvantage on the
  Perception roll); at least a day between encounters; half on the road, half
  in camp ([Steam testing thread](https://steamcommunity.com/app/1096530/discussions/0/760682265019834900/)).

### Pathfinder: Kingmaker — degrees of success and advisors
- Kingdom events are resolved by an **advisor** (the right one lowers the DC),
  who is **busy for the event's duration**; the result falls in **four bands:
  Disaster (≤ DC−8), Failure, Success, Triumph (≥ DC+8)** **[code]**
  ([KingdomInfo.cs](https://github.com/spacehamster/KingmakerKingdomResolutionMod/blob/master/KingdomResolution/KingdomInfo.cs)).
- Claimed land has half the random encounters [summary].

### Baldur's Gate 3 — the check on the screen
- The **DC is shown**, the die is rolled in front of you, any companion can
  **add a bonus** (Guidance, Bardic Inspiration) before the roll; natural 20/1.
- **Inspiration** is earned by acting in character for your background and
  spent on a re-roll. **Passive checks** fire without asking. Dialogue options
  are **gated by tags** — race, class, background — shown as [Dwarf], [Cleric].
  ([Dice rolls](https://bg3.wiki/wiki/Dice_rolls), [Inspiration](https://bg3.wiki/wiki/Inspiration))

### Beyond the list, where the sourcing was good
- **Wildermyth** casts **roles** by scoring heroes (personality, relationships,
  aspects), and chains by tagging a hero with an aspect a later event looks
  for; outcomes include **map changes**; the rule is "dramatic, permanent,
  mechanically simple", no dominant or purely negative choices
  ([Story inputs and outputs](https://wildermyth.com/wiki/Story_Inputs_and_Outputs)).
- **Fallen London's storylets**: chunks playable in any order, unlocked by
  *qualities*; a progress quality counts to a conclusion; an exile quality
  closes a storyline for good ([Failbetter](https://www.failbettergames.com/news/echo-bazaar-narrative-structures-part-two)).

---

## 3. What the road should borrow — proposals, most value first

Each is additive: new optional keys in `data/road_events.json` (documented in
`docs/modding.md` §5.3, frozen by `tests/test_mod_api.gd`), so every existing
event and pack keeps working. Effort: **S** a day, **M** a few, **L** a week+.

1. **Don't repeat; sometimes nothing happens (S).** CK3's `0` weight, Battle
   Brothers' cooldown and last-event exclusion, Slay the Spire's one-time
   events — and CK3's own travel-spam complaint is the warning. Add
   `cooldown` (world-minutes, per event), `once` (never again this run), a
   table-level **"nothing" weight**, and exclude the last event fired. Saved
   with the world, like `road_chain`. *This is the one to do first*: with
   seventeen events and a question every six hours, repetition is the road's
   biggest risk today.

2. **Blue options — who is in the company matters (M).** FTL's `req`, Battle
   Brothers' background options, BG3's [Dwarf]/[Cleric], CK3's trait-gated
   options. A choice gains `requires: {background | class | species | trait |
   proficiency | item | spell}` and is **hidden unless met**; **the matched
   hero rolls it and is named on the button and in the text**
   ("Brother Aldo — Acolyte — knows whose shrine this is"). Usually safer, not
   strictly better; may consume the item it names. Our `spells` choices are
   already a blue option for casters — this generalises them.

3. **Cast a role, and keep it through the chain (M).** CK3's saved scopes,
   Wildermyth's roles and aspects. An event names a `cast`: *the hero with the
   highest Insight*, *a hero with the Greedy trait*, *the one with the lowest
   morale* — picked when the event fires, written into every `%role%`, and
   **carried to its follow-ups** so the same hero comes back three stretches
   later. This is what turns seventeen events into a hundred stories, and it
   is how traits and callings start to *show* on the road.

4. **Traits push back (M).** CK3's stress for acting against your personality;
   Darkest Dungeon's quirks that force a choice. An option marked `against:
   ["honest"]` costs that hero morale (`core/party_opinion.gd`) — shown on the
   button — and one marked `for: ["greedy"]` pleases them. A hero with a
   compulsive trait can **take the choice for you** now and then (the Curious
   hero touches the idol). Traits already exist and are modelled on CK3; this
   is where they meet the road.

5. **Weights from the world (S/M).** CK3's `weight_multiplier`, Battle
   Brothers' `onUpdateScore`, Warband's live-state quests. `weight` becomes
   `weight` plus `modifiers: [{if: …, factor: …}]` over a small closed set of
   conditions the road already knows: the country, a lair within reach, a
   raided town nearby, a people's grudge, the party's worst morale, night,
   wounded, gold low. The refugees event already does this by hand with
   `needs: "raided"`; this makes it general and moddable.

6. **Follow-ups at a place, marked on the map (M).** FTL's quest beacon,
   Battle Brothers returning to the event after the fight. `next` gains `at:
   "next_town" | "fork" | "lair" | "here"`: the follow-up waits at that place
   (never overwriting a town's own card), shown with the job marker the map
   already draws, and fires when the company arrives. A `fight` outcome can
   name an `after` event so a won or lost fight **comes back to the story**
   instead of ending it.

7. **Degrees of success (S).** Pathfinder's four bands; BG3's natural 20/1. A
   check may add `triumph` (beat the DC by 8+, or a natural 20) and
   `disaster` (miss by 8+, or a natural 1) outcomes; absent, they fall back to
   pass and fail. One roll, four stories, no new UI.

8. **The right thing makes it certain (S).** Darkest Dungeon's curio items;
   FTL's consumed blue options. A choice with `uses: {item: "rope-hempen"}`
   spends the item and takes the pass without a roll. Pays off what the
   company chose to carry out of town.

9. **Threads with their own clock (L).** CK3's story cycles; Fallen London's
   progress qualities. A `story` block — set up by an outcome, with a counter
   the thread advances and a small sub-table of its own events that only fire
   while it runs — for a feud with a band, a cursed trinket, a hero's calling
   (callings are already threads; this lets the road serve them). Once the
   pieces above exist, a thread is mostly data.

10. **Pacing that feels fair (S).** Battle Brothers' chance that grows with
    time since the last event and its gap after a fight; Slay the Spire's pity
    across kinds. Instead of a question every six hours exactly, a
    chance that climbs between them — and no road event in the minutes after a
    fight or a meeting.

11. **Text that varies (S).** CK3's `first_valid` / `random_valid`, FTL's
    `textList`. `text` may be a list (one at random, seeded) or conditional
    variants (`[{if: "night", text: …}, …]`) — the cheapest defence against
    the same words twice.

12. **Problems that cost while they wait (M, later).** Bannerlord's issues:
    an outcome can leave a standing problem ("the bridge is out: every trip
    through here costs an hour until someone fixes it") that a later event,
    a job or a town can resolve.

**Not to copy:** mean-time-to-happen polling (CK3 left it for good reason);
an uncapped draw from a small table (CK3's own event-spam complaint); options
that are strictly better or strictly worse (Wildermyth's rule); long text
(Solasta II keeps an event to 250 words and answers under five).

---

## 4. A suggested order

- **Now, small, together:** 1 (repetition), 7 (degrees), 8 (the right item),
  10 (pacing), 11 (text variants) — each a key or two, each a direct fix for a
  weakness of today's road, one PR.
- **Next:** 2 (blue options) and 3 (cast roles) together — they share "which
  hero" — then 4 (traits push back), which needs 3.
- **Then:** 5 (weights from the world) and 6 (place follow-ups on the map).
- **Later:** 9 (threads) and 12 (standing problems), which build on all of it.
- **Alongside all of it:** more events. Battle Brothers ships ~400, King of
  Dragon Pass 500+ scenes; each proposal above makes an event worth more
  plays, but #234's "lots of events" is still content to write — and packs can
  write it too.

Every proposal is a question of design as much as code; the calls that are the
owner's are marked in the plan entry that goes with this document
(`docs/plan/2026-09-26-road-events-research.md`).

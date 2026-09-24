---
name: sorcmerc-design-bible
description: SorcMerc's design pillars, tone, setting, art direction and scope rules. Use when proposing or reviewing a feature, writing player-facing text (barks, blurbs, event cards, manual pages, quest copy), deciding whether something is in scope, or making a call about sorcery/magic cost, mercs or the world. Project-specific only; generic game-design method comes from other skills.
---

# SorcMerc design bible

Thin on purpose. The facts behind each line are in the files named next to it, and those files win. The build log (`docs/expansion-plan.md` to 2026-09-24, then `docs/plan/`) is the dated record of what exists, and `README.md` is the orientation map.

## What the game is (as built)

A **D&D 5.5e (2024) CRPG** in Godot 4.7 with three layers:
- **Character creation** on the 2024 SRD: 12 classes, subclasses, species, backgrounds and feats (`core/rules/`, `data/*.json`).
- **Hex tactical combat**: turn-based, initiative order, 5e action economy with actions, bonus actions and reactions (`core/combat.gd`).
- **Open-world campaign**: a 3D overworld with settlements, lairs, multi-room sites (dungeons), roaming bands, quests, a lodge and a renown ladder (`core/world*.gd`, `core/site.gd`, `core/lodge.gd`, `core/ladder.gd`).

The mercenary-company fantasy is carried by flavour and structure, not by a Battle Brothers stat model. You keep a **roster** of recruited heroes. Up to **4** go into a fight (`Party.MAX_ACTIVE`). The company climbs a renown ladder: *Nobodies → Hirelings → a Company of Note → Asked For by Name → Sung Wrong in Taverns* (`core/ladder.gd`). A new run's **founder** is built in the character creator (or taken from a preset); everyone after is **hired** from an inn's pool for a one-time fee, with no wages or upkeep (`core/recruits.gd`, see below).

## Pillars (decided)

1. **Every merc is memorable.** Heroes get personality traits, some earned in play (scars, banes, Veteran) (`core/traits.gd`). The party holds opinions of each other that show up in fights: bonded neighbours cover each other, rivals get in each other's way (`core/party_opinion.gd`). Each hero has barks and a relations web.
2. **Hard choices, no perfect answer.** Rest is rationed (see pillar 3). Inside a site the only rest is a short one, because "the adventuring day IS the design" (`core/site.gd`). Other examples: the approach card before a fight, camp-kit ambush risk and a 2-short-rests-per-long-rest cap. A feature that removes a trade-off works against this pillar.
3. **Magic is powerful but costly.** The cost is **spell slots that do not come back between fights**. See "Sorcery and the price of magic" below.

## Sorcery and the price of magic

- **Decided:** mercs can be sorcerers. Sorcerers are *uncommon but not rare* in the world.
- **In code:** the sorcerer is one of 12 playable classes, with nothing special about how many exist. No mechanic makes sorcerers uncommon, and that is decided: their rarity is fiction only.
- **Casting costs slots.** How many slots comes from the class and its level (5e 2024 tables in `data/classes.json`). Slots have **levels 1–9**, and a spell can be upcast from a higher slot.
- **Slots refill on a long rest only, never per battle.** Spent slots are written back to the character when a fight ends (`Adapter.write_back`) and carry into the next fight. The exceptions are all RAW: warlock Pact Magic comes back on a short rest, a wizard's Arcane Recovery gets some slots back at a short rest once per long rest (`Adapter.arcane_recovery_auto`), and an elf's Trance banks one extra short rest for later that day (`core/trance.gd`). This supports pillar 3.
- **The player sees the real slots.** The sheet, the party page and the combat pips all read `Adapter.slot_table()`: left against the sheet's maximum. The sheet only shows HP, pools and slots; it has no rest or refill buttons.
- **Long rests are expensive:**
  - at most once per 24 in-game hours;
  - 8 hours of world clock, during which bands keep walking and markets restock (`core/world_rest.gd` steps the night);
  - an inn room costs gold, and camping needs a 150-gold camp kit (or Rope Trick, whose slot stays spent through that night) and carries an 8% ambush risk; nobody camps with a hostile band in reach;
  - downtime's nights refill only when the 24-hour gate allows;
  - none at all inside a site.
- **Spent slots never buy an easier fight.** The encounter budget reads the party's *remaining* slots, so it would send a drained party a smaller, poorer fight. `WorldThreat.slot_hold()` cancels that in the open world, and `core/site.gd` does the same inside sites. Only wounds thin a fight.
- **Enemy magic is mostly not slot-based.** An ordinary foe's "magic" is a limited-use feature such as `monster-innate-bolt` (2 uses), a breath weapon, a gaze or life drain (`data/effects/features.json`). The exception is the named casters in `data/effects/casters.json`.

## Tone

**Gritty but heroic.** Plain, concrete and dry, with the heroism shown through what people do, not stated. Match the voice already in the repo:
- Band blurbs (`core/regions.gd`): *"Patrolled, farmed, and about as dangerous as a bad harvest."* / *"Past the last waystone. What lives here has never been taxed."*
- Site rest (`core/site.gd`): *"An hour in the dark. Not a night's sleep, but it is something."*

Avoid epic-fantasy capitals-and-prophecy prose, jokes that break the scene, and grimdark cruelty for its own sake. The AI's mercy rule is a tone decision: foes don't finish off a downed hero while a conscious one can be engaged (`core/ai.gd` `MERCY`).

## Setting

- Four concentric countries, each with a level range: **the Heartland** (levels 1–3), **the Marches** (3–6), **the Frontier** (6–9) and **the Far Deeps** (10–20). Each has home factions (`core/regions.gd` `BANDS`/`HOMES`).
- Factions come from the bestiary's hand-tagged `faction` field. The ones that field rosters are listed in `Scaler.FACTIONS`: goblinoid, beast, undead, bandit, giant, kobold, orc, gnoll, cultist, soldier, monstrosity, fey, elemental, construct and dragon.
- Settlements have per-faction opinion (`core/faction_opinion.gd`). Persistent faction warfare is deferred (expansion-plan, "Post-T91 gap note").
- Species-flavoured towns exist: human, dwarf, elf and orc settlement kits.

## Art direction (as built)

Two house styles, one per dimension. Both are AI output; the README's provenance table says which directory holds which.

- **3D: figures and dioramas are Meshy models**: text-to-3D, rigged, with an **Idle** clip, standing on a 3D board and a 3D overworld (`assets/figures/`, `assets/troops/`, `assets/beasts/`, `assets/npcs/`, plus the static `assets/lairs/`, `assets/settlements/` and board props). The one 3D prompt on record, the goblin's, ends *"semi-realistic fantasy, muted earthy palette"*: that is the 3D house style. Hero portraits are rendered from the same rigs (`scenes/portraits.gd`).
- **2D: everything painted is an SDXL painting in one painterly style** (a local ComfyUI; `assets/generated/`, `assets/art/items/`, the packs' portraits, the board floors, the map's ground). All 243 prompts on record say *"painterly"*. Each is a subject plus one of three tails:
  - scenes, 110: *"painterly fantasy illustration, rich warm palette, soft rim light, detailed"*;
  - emblems (achievement badges, job tiles), 122: *"a single emblem, close up, centered, against a plain near-black shadowy backdrop, low-key dramatic lighting, painterly fantasy illustration, oil painting brushwork, rich but muted palette, soft rim light"*;
  - portraits, 11: *"painterly digital art, bust portrait, fantasy RPG character portrait"*.
  - The negative (209 of 243) rules out the other looks: cartoon, cel shading, flat colours, vector, 3d render, glossy, plastic, frames. The item icons were repainted in the same hand (2026-09-16).
  - A picture of the company shows exactly its four, and no crowd is over eight (the 2026-09-21 picture audit).
- **Icons:** the action, school, skill, class and path icons are hand-authored SVG from `tools/gen_action_icons.py`, no image model. The ~428 item icons and achievement badges are SDXL paintings (above).
- **Audio** is ElevenLabs sound-effects takes, 120 of 123 files (`assets/audio/PROVENANCE.md`); `tools/gen_audio.py`'s offline synthesis is the fallback and makes two.
- **Provenance rule:** AI-generated assets live in their own directories, with a `PROVENANCE.md` giving the tool, model, date and prompt, written the day the asset lands. Where something was not recorded, the file says so rather than guessing. This keeps Steam's AI-content disclosure answerable (`README.md`, "Assets and provenance").
- A 2D cutout-rig direction was considered in chat and **dropped** (2026-09-24): the game stays 3D. The LPC layered-sprite recipes it left in `data/lpc/`, which no script loaded, were removed on 2026-09-24.

## Scope rules

- **5e 2024 RAW first.** BG3 is the tie-breaker when RAW is unclear or doesn't fit a video game. Adapter and rules comments cite both.
- A deliberate deviation from RAW gets a `ponytail:` comment that says what was simplified and when to revisit it. Don't silently "fix" one.
- **Rules gravity** (`docs/brief.md`): every rule pulls in three more. Add a mechanic only when the loop needs it.
- **New mechanics go in `core/`** (pure, `RefCounted`, headless-testable). Scenes only draw them.
- **Content packs are data only** (`core/mod/`, `docs/modding.md`). A feature a mod should be able to use goes in the public data schema, not in code.
- Every feature gets its own build-log entry: a new file `docs/plan/YYYY-MM-DD-slug.md` with a `### Still open` section (`docs/plan/README.md`). Never append to `docs/expansion-plan.md`; it is closed.
- A balance number changes only with a re-run sweep (see the `sorcmerc-balancing` skill).

## Decided 2026-09-24 (owner's calls, not yet built)

These are direction, not description. The code still does the old thing until each one lands with its own `docs/plan/` entry. A bullet marked **built** has landed.

- **Recruitment — built** (`core/recruits.gd`; expansion-plan "Hired, not made"). The player **creates only the first character**, the founder, at the start of a run. Every later merc is **hired** at an inn, from a pool of pre-rolled recruits who come with their own traits.
  - The pool is seeded off the settlement and the world-day: 3 chairs at a city, 2 at a town, 1 at a camp. A hire leaves the pool.
  - A recruit is the local band's level minus one (`Regions.level_here`), floored at 1, and comes only in species and classes the meta-progression has unlocked.
  - A **one-time fee** of 50 ◉ a level, 10% off per renown title. There are **no wages or upkeep**. The roster cap is 6 as Nobodies, +2 per title. It stops hiring and never trims a roster.
  - **Fixed at hire:** class, species, background, ability scores (the standard array), skills, tools, languages, expertise, weapon mastery, feature choices like Divine or Primal Order, and gear.
  - The player makes the merc's **subclass, spells and normal level-up choices** (feats or ability increases, fighting styles) on a settle-in page before the fee is paid.
  - Heroes from earlier runs stay in the barracks. They turn up now and then as **veterans** in an inn's pool, at their own level, and only where the country fights at that level or higher.
  - **Old saves are grandfathered.** A save with no hiring rule keeps its roster, its Create new, and the inns' pools too. A new run starts with a 150 ◉ founding purse.
- **Sorcerer rarity is fiction only.** No recruit odds and no social mechanic. "Uncommon but not rare" lives in the writing.
- **Sorcerer features follow 2024 RAW.** Built: Innate Sorcery, Font of Magic, and Metamagic Quickened, Twinned, Careful, Subtle and Seeking (`test_sorcerer.gd`). The other five options are still catalogue text; `core/manual.gd` says so.
- **Enemy magic is rare and named.** Ordinary enemies keep their limited-use innate abilities. Built: the cult's lair boss casts from real slots in Frontier country and beyond, and announces itself. Caster elites in ordinary warbands are built but off, until the power model can price a glass cannon.
- **Factions post contracts** (built: `core/contracts.gd`). Every job carries its `issuer`, who is credited wherever it is handed in. War work waits for Known and neutral opinion, and regard pays up to +25%.
- **The player and the factions can fight each other** (the owner's call, 2026-09-24). This lifts the "never civilized-vs-civilized" rule: first rival-raid contracts, then NPC faction warfare. Neither is built yet.
- **Armor stays 5e AC.** No damage split, no durability.
- **Art stays 3D.** Rigged Meshy figures in the 3D house style. The 2D cutout plan is dropped.
- **Slots are scarce by the rest rules, not the tables.** Keep the 2024 slot tables. The paladin/ranger level-1 gap in the export is fixed — **built** (`data/classes.json` gives both `[2]` at level 1; build log "Paladins and rangers cast from level 1"). Encounters are sized **as if the party had every slot back** (built: `WorldThreat.slot_hold()`). Spending a slot never buys an easier next fight; wounds still thin one. See the `sorcmerc-balancing` skill.

## The design audit's calls (2026-09-24)

Direction, not description: each lands as its own piece of work with its own `docs/plan/` entry, and the code does the old thing until then. Detail and evidence: `docs/audit-game-design.md`, "The owner's calls" (section numbers below).

- **Death has weight.** A defeat revives the downed only; the dead stay dead until a paid raise, priced by level (about 50 ◉ a level). The bonded grieve, the fallen get a roll, the dead never come back as veterans, and deaths count in the open world too. (1.2, 2.1, 5.2)
- **Defeat costs more than coin.** A floor not tied to the purse: days, an injury or gear. An empty purse pays a parley toll in gear or opinion. (1.8)
- **A lair resets when you leave it.** Every room regrows and is priced fresh off `Regions.fresh_score`, so a drained party never meets a smaller lair. (1.3, 3.3)
- **Gambling** is once a day per town and loses on average; the lowest win pays the stake back. (1.5)
- **Rope Trick** replaces the camp kit, not the risk: the slot is not refunded and the ambush roll stands. (1.6)
- **A rest takes the world's time.** The world ticks through the 8 hours, nobody camps with a hostile band nearby, downtime refills only when a long rest is allowed, and the sheet has no rest or HP buttons. (1.1, 1.7, 1.9)
- **The bench is people, not storage.** Restless mercs may leave, told as a moment; the bench joins camp moments and the relations web. No bench XP, no upkeep. (2.4)
- **A failed parley costs faction opinion.** (3.1)
- **Economy.** Loot sells for less, sinks scale with level, magic items work in a fight, friendly towns pay more. Quest XP follows the region's fight XP; renown and regard multiply gold only. Still no wages or upkeep. (5.1, 5.3, 5.6)
- **Tone rules.** ◉ beside any number, "coin" or "gold" only in prose. "Company" in fiction, "party" only where a line states a rule. One register everywhere, the authored one: no contractions and no "!" in system messages or dice verdicts. Bands are named from `EnemyNames`, never by id. (6.1, 6.3–6.5)
- **Art provenance** — built 2026-09-24: every AI asset directory has its `PROVENANCE.md` (see Art direction). (8.1)

## Open questions

- None outstanding from the 2026-09-24 pass. Add new ones here as they come up.

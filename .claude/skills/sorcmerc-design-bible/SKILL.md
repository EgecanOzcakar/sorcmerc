---
name: sorcmerc-design-bible
description: SorcMerc's design pillars, tone, setting, art direction and scope rules. Use when proposing or reviewing a feature, writing player-facing text (barks, blurbs, event cards, manual pages, quest copy), deciding whether something is in scope, or making a call about sorcery/magic cost, mercs or the world. Project-specific only; generic game-design method comes from other skills.
---

# SorcMerc design bible

Thin on purpose. The facts behind each line are in the files named next to it, and those files win. `docs/expansion-plan.md` is the dated record of what exists, and `README.md` is the orientation map.

## What the game is (as built)

A **D&D 5.5e (2024) CRPG** in Godot 4.7 with three layers:
- **Character creation** on the 2024 SRD: 12 classes, subclasses, species, backgrounds and feats (`core/rules/`, `data/*.json`).
- **Hex tactical combat**: turn-based, initiative order, 5e action economy with actions, bonus actions and reactions (`core/combat.gd`).
- **Open-world campaign**: a 3D overworld with settlements, lairs, multi-room sites (dungeons), roaming bands, quests, a lodge and a renown ladder (`core/world*.gd`, `core/site.gd`, `core/lodge.gd`, `core/ladder.gd`).

The mercenary-company fantasy is carried by flavour and structure, not by a Battle Brothers stat model. You keep a **roster** of recruited heroes. Up to **4** go into a fight (`Party.MAX_ACTIVE`). The company climbs a renown ladder: *Nobodies → Hirelings → a Company of Note → Famous → Legends* (`core/ladder.gd`). Recruits are **built in the character creator** or taken from presets. No hiring pool, wages or upkeep exist.

## Pillars (decided)

1. **Every merc is memorable.** Heroes get personality traits, some earned in play (scars, banes, Veteran) (`core/traits.gd`). The party holds opinions of each other that show up in fights: bonded neighbours cover each other, rivals get in each other's way (`core/party_opinion.gd`). Each hero has barks and a relations web.
2. **Hard choices, no perfect answer.** Rest is rationed (see pillar 3). Inside a site the only rest is a short one, because "the adventuring day IS the design" (`core/site.gd`). Other examples: the approach card before a fight, camp-kit ambush risk and a 2-short-rests-per-long-rest cap. A feature that removes a trade-off works against this pillar.
3. **Magic is powerful but costly.** The cost is **spell slots that do not come back between fights**. See "Sorcery and the price of magic" below.

## Sorcery and the price of magic

- **Decided:** mercs can be sorcerers. Sorcerers are *uncommon but not rare* in the world.
- **In code:** the sorcerer is one of 12 playable classes, with nothing special about how many exist. No mechanic makes sorcerers uncommon: no recruitment odds, no NPC census. Their rarity is fiction only, for now.
- **Casting costs slots.** How many slots comes from the class and its level (5e 2024 tables in `data/classes.json`). Slots have **levels 1–9**, and a spell can be upcast from a higher slot.
- **Slots refill on a long rest only, never per battle.** Spent slots are written back to the character when a fight ends (`Adapter.write_back`) and carry into the next fight. The exceptions are all RAW: warlock Pact Magic comes back on a short rest, a wizard's Arcane Recovery gets some slots back once per day, and an elf's Trance adds a short-rest top-up after a long rest. This supports pillar 3.
- **Long rests are expensive:**
  - at most once per 24 in-game hours;
  - 8 hours of world clock, during which bands keep walking and markets restock;
  - an inn room costs gold, and camping needs a 150-gold camp kit and carries an 8% ambush risk;
  - none at all inside a site.
- **Known softener:** in the open world the encounter budget reads the party's *remaining* slots, so a drained party is sent a smaller, poorer fight (`core/world_threat.gd`, `core/regions.gd`). Sites correct for this and pin every room to the entry reading (`core/site.gd`). Keep this in mind when judging whether casting feels costly.
- **Enemy magic is not slot-based.** No bestiary entry has spell slots. A foe's "magic" is a limited-use feature such as `monster-innate-bolt` (2 uses), a breath weapon, a gaze or life drain, defined in `data/effects/features.json`.

## Tone

**Gritty but heroic.** Plain, concrete and dry, with the heroism shown through what people do, not stated. Match the voice already in the repo:
- Band blurbs (`core/regions.gd`): *"Patrolled, farmed, and about as dangerous as a bad harvest."* / *"Past the last waystone. What lives here has never been taxed."*
- Site rest (`core/site.gd`): *"An hour in the dark. Not a night's sleep, but it is something."*

Avoid epic-fantasy capitals-and-prophecy prose, jokes that break the scene, and grimdark cruelty for its own sake. The AI's mercy rule is a tone decision: foes don't finish off a downed hero while a conscious one can be engaged (`core/ai.gd` `MERCY`).

## Setting

- Four concentric countries, each with a level range: **the Heartland** (levels 1–3), **the Marches** (3–6), **the Frontier** (6–10) and **the Far Deeps** (10–20). Each has home factions (`core/regions.gd` `BANDS`/`HOMES`).
- Factions come from the bestiary's hand-tagged `faction` field. The ones that field rosters are listed in `Scaler.FACTIONS`: goblinoid, beast, undead, bandit, giant, kobold, orc, gnoll, cultist, soldier, monstrosity, fey, elemental, construct and dragon.
- Settlements have per-faction opinion (`core/faction_opinion.gd`). Persistent faction warfare is deferred (expansion-plan, "Post-T91 gap note").
- Species-flavoured towns exist: human, dwarf, elf and orc settlement kits.

## Art direction (as built)

- **Figures are AI-generated 3D models**: Meshy text-to-3D, rigged, with an **Idle** clip, standing on a 3D board and a 3D overworld (`assets/figures/`, `assets/beasts/`, `assets/npcs/`, `assets/troops/`). The house prompt style is *"semi-realistic fantasy, muted earthy palette"*. Portraits are rendered from the same rigs (`scenes/portraits.gd`).
- Icons are hand-authored SVG from `tools/gen_action_icons.py`, not an image model. Audio is procedural (`tools/gen_audio.py`).
- **Provenance rule:** AI-generated assets live in their own directories, with a `PROVENANCE.md` giving the tool, model, date and prompt. This keeps Steam's AI-content disclosure answerable (`README.md`, "Assets and provenance").
- The chat direction was **2D cutout rigs** (semi-realistic and semi-caricatured, 2–3 code-generated poses). **The repo does not do this.** There is no Skeleton2D/Polygon2D rig anywhere in `scenes/`. `data/lpc/*.json` holds LPC layered-sprite recipes that no script loads. Moving to 2D cutouts would replace the 3D board and figures, so it is an open decision, not a convention.

## Scope rules

- **5e 2024 RAW first.** BG3 is the tie-breaker when RAW is unclear or doesn't fit a video game. Adapter and rules comments cite both.
- A deliberate deviation from RAW gets a `ponytail:` comment that says what was simplified and when to revisit it. Don't silently "fix" one.
- **Rules gravity** (`docs/brief.md`): every rule pulls in three more. Add a mechanic only when the loop needs it.
- **New mechanics go in `core/`** (pure, `RefCounted`, headless-testable). Scenes only draw them.
- **Content packs are data only** (`core/mod/`, `docs/modding.md`). A feature a mod should be able to use goes in the public data schema, not in code.
- Every feature gets an appended `docs/expansion-plan.md` entry with a `### Still open` section.
- A balance number changes only with a re-run sweep (see the `sorcmerc-balancing` skill).

## Open questions

- **Sorcerer identity.** Font of Magic, Metamagic and Innate Sorcery have **no combat mechanic**. They are catalogue text only: absent from `data/effects/features.json`, with no sorcery-point pool in code. `core/manual.gd` nonetheless tells players that Font of Magic converts slots. Right now the namesake class plays as "a wizard with fewer spells".
- **Sorcerer recruitment and rarity.** How does "uncommon but not rare" show up in play: recruit offers, NPC casters, how towns react to sorcerers?
- **How often enemies use magic.** Today enemies use no slots and have no spell lists, only limited-use innate features. Should any faction (cultists, drow) get real casters?
- **Factions.** Is there a mercenary-contract layer between factions, or do they stay rosters plus opinion? Faction warfare is deferred.
- **Art.** Keep the 3D Meshy figures, or move to 2D cutout rigs?
- **Mercenary economy.** Add wages, upkeep or a hiring pool, or keep the creator-built roster?

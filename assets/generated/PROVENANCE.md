# assets/generated — AI-generated 2D paintings (SDXL)

**Everything in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Nothing
here is hand-painted or licensed. 362 PNGs, all 512 × 512:

| Kind | Files | What draws it |
|---|---|---|
| achievement badges | 113 `achievement-*.png` | the achievements list and the earned toast |
| job tiles | 9 `quest-*.png` | notice board, counters, the rescue card |
| road events, approach card, camp, downtime, lodge, callings, audiences | 112 `event-*.png` | the event and approach cards |
| site rooms | 29 `room-*.png` | the site screen |
| counter portraits | 28 `<race>-<role>.png` + 56 `-happy`/`-frown` moods | every shop tab and the inn |
| inns, camp nights, landmarks, run summary | 4 `inn-*`, 3 `camp-*`, 6 `landmark-*`, 2 `summary-*` | as named |

Dates: 2026-09-15 (the first counter portraits) to 2026-09-21 (the picture audit,
`7b60b59`, which repainted 72 of them). The *Landed* column below is the commit that
last changed each file, which is the render that ships.

## How they were made — the 237 files that still say so

237 of the 362 carry ComfyUI's own record of the render in a PNG `tEXt` chunk named
`prompt` (the API graph, as JSON). Every one of those 237 was made the same way:

- **Tool:** ComfyUI, run locally.
- **Model:** `sd_xl_base_1.0.safetensors` (Stability AI's SDXL 1.0 base), no refiner, no LoRA.
- **Settings:** 1024 × 1024 latent, KSampler `dpmpp_2m` / `karras`, 28 steps, CFG 7.0,
  denoise 1.0, then a Lanczos downscale to 512 × 512.
- **Seed and prompt:** per file, in the table below.

To read one back:

```sh
python3 -c "from PIL import Image; import sys; print(Image.open(sys.argv[1]).text['prompt'])" assets/generated/event-ford.png
```

The generator scripts themselves are **not in this repository**: they lived in the
owner's `~/localgen/` (`gen_sorcmerc_scenes.py`, `gen_sorcmerc_events.py`,
`gen_sorcmerc_moods.py`, named in commits `b2ffa48`, `992a13f`, `3cb6f8d`). The
metadata in each file is therefore the only record of its prompt, and it goes if a
file is re-saved through anything that drops `tEXt` chunks. Keep it when you edit one.

Each prompt is a subject followed by one of three fixed style tails. The table gives
the subject and names the tail:

| Tail | Files | Text appended to the subject |
|---|---|---|
| **E** (emblem) | 122 — the achievement badges and job tiles | `, a single emblem, close up, centered, against a plain near-black shadowy backdrop, low-key dramatic lighting, painterly fantasy illustration, oil painting brushwork, rich but muted palette, soft rim light, detailed, 1:1` |
| **S** (scene) | 110 — events, rooms, inns, camp, landmarks, summaries | `, painterly fantasy illustration, rich warm palette, soft rim light, detailed, 1:1` |
| **P** (portrait) | 5 — the counter portraits repainted on 2026-09-21 (and the six pack portraits under `content/`) | `, painterly digital art, 1:1 bust portrait, fantasy RPG character portrait` |

And one of these negative prompts (N6–N9 are N2 plus a few words for one picture):

| Neg | Files | Negative prompt |
|---|---|---|
| N1 | 149 | blurry, low quality, deformed, extra limbs, bad anatomy, text, watermark, signature, cropped, out of frame, modern clothing, gun, rifle, musket, monochrome, sketch, pencil, lineart, paper border, frame, poster, cartoon, flat colours, cel shading, vector, glossy render, 3d render, plastic, flat icon, picture frame, framed, canvas, kaleidoscope, tessellation, wallpaper |
| N2 | 29 | blurry, low quality, deformed, extra limbs, bad anatomy, text, watermark, signature, cropped, crowd, army, horde, many people, group of identical soldiers, duplicate figures, clones, character sheet, collage, multiple panels, grid, extra fingers, six fingers, fused fingers, missing fingers, extra hands, mutated hands, malformed limbs, extra legs, out of frame, modern clothing, gun, rifle, musket, monochrome, sketch, pencil, lineart, paper border, frame, poster, cartoon, flat colours, cel shading, vector, glossy render, 3d render, plastic, flat icon, picture frame, framed, canvas, kaleidoscope, tessellation, wallpaper |
| N3 | 26 | N2 without "character sheet, collage, multiple panels, grid" |
| N4 | 22 | blurry, low quality, deformed, extra limbs, bad anatomy, text, watermark, signature, cropped, out of frame, modern clothing, gun, rifle, musket, monochrome, sketch, pencil, lineart, paper border, frame, poster |
| N5 | 8 | blurry, low quality, deformed, extra limbs, bad anatomy, text, watermark, signature, cropped, out of frame, modern clothing |
| N6 | 1 | N2, then: horse, riding, daylight, sunset |
| N7 | 1 | N2, then: monitor, computer, screen, lamp, light bulb, electric light, world map, globe, Americas, Europe, Africa, modern, office |
| N8 | 1 | N2, then: elf, elven, human, pointed ears, horns, delicate, pale skin, border, frame |
| N9 | — | N2, then: elf, pointed ears, tall, slender, border, frame (used only by `content/vault-of-the-ember-crown/portraits/durn.png`) |

## The 125 files with no record

These carry no metadata, and nothing else in the repository holds their prompts or
seeds. **Prompt and seed: not recorded.** What the commits do say:

- **23 counter portraits, first pass** (`<race>-<role>.png`, 2026-09-15, `43c4e26`):
  "SDXL-generated in one painterly style". The checkpoint file is not named; every
  SDXL render in the repository that records one names `sd_xl_base_1.0`. The other five
  portraits were repainted on 2026-09-21 and do carry metadata.
- **56 moods** (`<race>-<role>-happy.png` / `-frown.png`, 2026-09-16, `3cb6f8d`;
  face boxes hand-set in `a5ad31e`; some redone in `7b60b59`): made *from* the
  portrait by `~/localgen/gen_sorcmerc_moods.py` — "only the face is re-sampled
  (Haar box, feathered mask, partial denoise) and pasted back, so hair, clothes and
  room are the original pixels; a warm or cold grade over the whole frame". So they
  are AI-modified derivatives of the portrait they are named after. Their denoise
  prompts are not recorded.
- **46 outcome frames** (`event-*-pass.png` / `-fail.png`, `room-*-pass.png` /
  `-fail.png`, 2026-09-16 to 2026-09-21): from `~/localgen/gen_sorcmerc_events.py`
  and `gen_sorcmerc_scenes.py`, "the event, in its outcome's light". Whether each
  frame is its own render or a regrade of its base picture is not recorded either.

## Licence

SDXL 1.0 is published under the CreativeML Open RAIL++-M licence, which puts use
restrictions on the model and not an ownership claim on its output. Read it before
the store page is filled in.

## Every file

| File | Landed | Seed | Style | Neg | Subject (the prompt before the style tail) |
|---|---|---|---|---|---|
| `achievement-ambush_win.png` | 2026-09-16 `f4fb635` | 11096 | E | N1 | a horn blown at dawn beside a torn tent, rude awakening |
| `achievement-bestiary_150.png` | 2026-09-16 `f4fb635` | 11126 | E | N1 | a thick leather bestiary book with a dragon embossed on its cover, the compleat bestiary |
| `achievement-bestiary_25.png` | 2026-09-16 `f4fb635` | 11120 | E | N1 | a field notebook open with a sketched monster and a quill, field notes |
| `achievement-bestiary_75.png` | 2026-09-16 `f4fb635` | 11123 | E | N1 | a naturalist's magnifying lens over a pinned wing and a claw, naturalist |
| `achievement-big_heal.png` | 2026-09-16 `f4fb635` | 11156 | E | N1 | a great burst of golden healing light over a helm, back on their feet |
| `achievement-big_hit_120.png` | 2026-09-16 `f4fb635` | 11081 | E | N1 | a colossal blow shattering a stone golem into fragments of light, unmaking |
| `achievement-big_hit_25.png` | 2026-09-16 `f4fb635` | 11075 | E | N1 | a war hammer striking an anvil with sparks, solid connection |
| `achievement-big_hit_60.png` | 2026-09-16 `f4fb635` | 11078 | E | N1 | a great maul splitting a boulder in half, overwhelming force |
| `achievement-big_spender.png` | 2026-09-16 `f4fb635` | 11030 | E | N1 | a fat purse bursting with gold coins spilling over a merchant's scale, big spender |
| `achievement-bonded.png` | 2026-09-16 `f4fb635` | 11312 | E | N1 | two shields leaning together, shoulder to shoulder |
| `achievement-bug_hunter.png` | 2026-09-16 `f4fb635` | 11333 | E | N1 | a beetle pinned under a magnifying glass with a quill note, bug hunter |
| `achievement-camp_first.png` | 2026-09-16 `f4fb635` | 11273 | E | N1 | a small campfire under stars with a bedroll beside it, firelight |
| `achievement-campaign_clear.png` | 2026-09-16 `f4fb635` | 11033 | E | N1 | a long winding road ending at a distant sunrise, worn boots in the foreground, the long road |
| `achievement-classes_6.png` | 2026-09-16 `f4fb635` | 11195 | E | N1 | six emblems of adventuring classes in a ring around a single gem, jack of all trades |
| `achievement-clean_run.png` | 2026-09-16 `f4fb635` | 11258 | E | N1 | a full company walking home together into a village at sunset, everyone came home |
| `achievement-counterspell.png` | 2026-09-16 `f4fb635` | 11144 | E | N1 | a hand halting a bolt of magic with a ripple of force, not today wizard |
| `achievement-counterspell_10.png` | 2026-09-16 `f4fb635` | 11147 | E | N1 | a torn thread of light going silent between two hands, silence in the weave |
| `achievement-created_10.png` | 2026-09-16 `f4fb635` | 11201 | E | N1 | a recruiting sergeant's ledger with ten signatures and a coin, the recruiter |
| `achievement-crit_250.png` | 2026-09-16 `f4fb635` | 11063 | E | N1 | a surgeon's scalpel-thin blade on a silk cloth with a golden ring, surgeon |
| `achievement-crit_50.png` | 2026-09-16 `f4fb635` | 11060 | E | N1 | a keen eye emblem over a crosshair of two crossed arrows, practised eye |
| `achievement-crit_first.png` | 2026-09-16 `f4fb635` | 11057 | E | N1 | a dagger point piercing the gap between two armour plates, right in the gap |
| `achievement-crit_kill.png` | 2026-09-16 `f4fb635` | 11066 | E | N1 | a sword cleanly striking a helm in two, clean finish |
| `achievement-damage_types_6.png` | 2026-09-16 `f4fb635` | 11129 | E | N1 | six small orbs of fire, ice, lightning, acid, radiance and shadow in a ring, every flavour |
| `achievement-death_save.png` | 2026-09-16 `f4fb635` | 11003 | E | N1 | a skull with a candle flame still burning in its eye, not today |
| `achievement-earned_100k.png` | 2026-09-16 `f4fb635` | 11228 | E | N1 | a ledger of wages with stacks of coins beside it, the wages of adventure |
| `achievement-equip_legendary.png` | 2026-09-16 `f4fb635` | 11012 | E | N1 | a legendary sword wreathed in golden light held aloft, wielding legend |
| `achievement-explored_150.png` | 2026-09-16 `f4fb635` | 11294 | E | N1 | a cartographer's compass rose over a hand-drawn map with many waypoints, cartographer |
| `achievement-faction_loved.png` | 2026-09-16 `f4fb635` | 11285 | E | N1 | a faction banner with a garland of flowers and a raised cup, friends in high places |
| `achievement-first_victory.png` | 2026-09-16 `f4fb635` | 11000 | E | N1 | a sword thrust point-down into the earth with a laurel wreath, first blood |
| `achievement-forage_25.png` | 2026-09-16 `f4fb635` | 11270 | E | N1 | a full foraging basket beside a knife and a cloth, nothing goes to waste |
| `achievement-forage_first.png` | 2026-09-16 `f4fb635` | 11267 | E | N1 | a basket of foraged mushrooms, berries and herbs, living off the land |
| `achievement-full_bench.png` | 2026-09-16 `f4fb635` | 11324 | E | N1 | a long wooden bench with eight helms hung above it, a full bench |
| `achievement-fumble_50.png` | 2026-09-16 `f4fb635` | 11072 | E | N1 | a dropped sword and a banana peel, a fumbled grip, butterfingers |
| `achievement-fumble_first.png` | 2026-09-16 `f4fb635` | 11069 | E | N1 | a twenty-sided die showing a single pip, cracked, it happens |
| `achievement-gold_1000.png` | 2026-09-16 `f4fb635` | 11219 | E | N1 | a leather purse with its strings pulled tight, coins visible, purse strings |
| `achievement-gold_10000.png` | 2026-09-16 `f4fb635` | 11222 | E | N1 | an iron-bound war chest heaped with gold coins, war chest |
| `achievement-gold_50000.png` | 2026-09-16 `f4fb635` | 11225 | E | N1 | a dragon's hoard of gold with a sleeping dragon's eye peeking from it, a dragon's problem |
| `achievement-haggle_25.png` | 2026-09-16 `f4fb635` | 11240 | E | N1 | a merchant's price list with every number crossed out and lowered, never pays list price |
| `achievement-haggle_first.png` | 2026-09-16 `f4fb635` | 11237 | E | N1 | two hands bargaining over a coin with a merchant's counter, talked down |
| `achievement-hard_flawless.png` | 2026-09-16 `f4fb635` | 11027 | E | N1 | an unblemished mirror-polished shield with no scratch, untouchable |
| `achievement-healer_work.png` | 2026-09-16 `f4fb635` | 11246 | E | N1 | a healer's bandages, a bowl and a few honest coins, honest work |
| `achievement-hide_first.png` | 2026-09-16 `f4fb635` | 11108 | E | N1 | a cloak melting into shadow, a half-seen mask, out of sight |
| `achievement-identify_25.png` | 2026-09-16 `f4fb635` | 11171 | E | N1 | a jeweller's eyepiece over a glowing ring with runes revealed, the appraiser's eye |
| `achievement-identify_item.png` | 2026-09-16 `f4fb635` | 11006 | E | N1 | a magnifying lens over a glowing rune, arcane appraisal |
| `achievement-investigate_battle.png` | 2026-09-16 `f4fb635` | 11249 | E | N1 | a crow on a broken helm with a purse tucked beneath, picking the bones |
| `achievement-kills_100.png` | 2026-09-16 `f4fb635` | 11048 | E | N1 | a notched bronze axe head with a tally of one hundred marks |
| `achievement-kills_2000.png` | 2026-09-16 `f4fb635` | 11054 | E | N1 | a field of skulls and bones under a black banner, a field of bones |
| `achievement-kills_500.png` | 2026-09-16 `f4fb635` | 11051 | E | N1 | a butcher's cleaver and a ledger of tally marks, iron and blood |
| `achievement-lair_deep.png` | 2026-09-16 `f4fb635` | 11303 | E | N1 | a stair spiralling down six landings into darkness, six rooms down |
| `achievement-lair_first.png` | 2026-09-16 `f4fb635` | 11297 | E | N1 | a torch held into a dark cave mouth, into the dark |
| `achievement-lair_no_rest.png` | 2026-09-16 `f4fb635` | 11306 | E | N1 | an arrow running straight through a cave with no camp along it, straight through |
| `achievement-lair_withdraw.png` | 2026-09-16 `f4fb635` | 11309 | E | N1 | a figure backing out of a cave mouth into daylight with a full sack, discretion |
| `achievement-lairs_10.png` | 2026-09-16 `f4fb635` | 11300 | E | N1 | ten cave mouths sealed with skulls on stakes, warren clearer |
| `achievement-legendary_5.png` | 2026-09-16 `f4fb635` | 11252 | E | N1 | five legendary items glowing on a display, a sword, a ring, a crown, a staff, a gem, hoarder |
| `achievement-level_10.png` | 2026-09-16 `f4fb635` | 11177 | E | N1 | a silver medallion stamped with the numeral X and a name scroll, name level |
| `achievement-level_15.png` | 2026-09-16 `f4fb635` | 11180 | E | N1 | a gold medallion stamped with XV and a peer's coronet, peer of the realm |
| `achievement-level_20.png` | 2026-09-16 `f4fb635` | 11018 | E | N1 | a golden crown medallion stamped with XX, living legend |
| `achievement-level_5.png` | 2026-09-16 `f4fb635` | 11015 | E | N1 | a bronze medallion stamped with the numeral V, seasoned |
| `achievement-levels_250.png` | 2026-09-16 `f4fb635` | 11186 | E | N1 | a great mountain with a winding path to a summit in cloud, the long climb |
| `achievement-levels_50.png` | 2026-09-16 `f4fb635` | 11183 | E | N1 | a mountain path climbing with fifty steps cut in stone, climbing |
| `achievement-long_fight.png` | 2026-09-16 `f4fb635` | 11090 | E | N1 | a worn shield with fifteen notches and a guttering candle, war of attrition |
| `achievement-loot_very_rare.png` | 2026-09-16 `f4fb635` | 11009 | E | N1 | an open treasure chest overflowing with a glowing gem, treasure hunter |
| `achievement-lovers.png` | 2026-09-16 `f4fb635` | 11315 | E | N1 | two hands clasped by a campfire under stars, something in the firelight |
| `achievement-modded.png` | 2026-09-16 `f4fb635` | 11336 | E | N1 | a hand-drawn map rolled with someone else's seal, someone else's map |
| `achievement-multiclass.png` | 2026-09-16 `f4fb635` | 11189 | E | N1 | a signpost at a fork with two roads under one sky, two roads |
| `achievement-multiclass_3.png` | 2026-09-16 `f4fb635` | 11192 | E | N1 | three different hats on one hook, a wizard's, a soldier's, a rogue's, dilettante |
| `achievement-oa_kill.png` | 2026-09-16 `f4fb635` | 11084 | E | N1 | a spear thrust into the back of a fleeing figure's shadow, never turn your back |
| `achievement-one_round.png` | 2026-09-16 `f4fb635` | 11087 | E | N1 | an hourglass with all its sand in the top and a sword through it, over before it started |
| `achievement-parry.png` | 2026-09-16 `f4fb635` | 11117 | E | N1 | two crossed blades locked at the guards with a spark, well guarded |
| `achievement-persuade_market.png` | 2026-09-16 `f4fb635` | 11243 | E | N1 | a shop door opening with a shopkeeper's reluctant face, talked our way in |
| `achievement-potion_25.png` | 2026-09-16 `f4fb635` | 11168 | E | N1 | a shelf of many potion bottles with a friendly alchemist's mortar, an alchemist's friend |
| `achievement-potion_first.png` | 2026-09-16 `f4fb635` | 11165 | E | N1 | a single potion bottle tipped to the lips, bottoms up |
| `achievement-quest_chain.png` | 2026-09-16 `f4fb635` | 11282 | E | N1 | a chain of three linked medallions each bigger than the last, trusted |
| `achievement-quest_first.png` | 2026-09-16 `f4fb635` | 11276 | E | N1 | a signed contract with a wax seal and a coin, on the job |
| `achievement-quests_25.png` | 2026-09-16 `f4fb635` | 11279 | E | N1 | a stack of completed contracts bound with ribbon, reliable |
| `achievement-reaction_100.png` | 2026-09-16 `f4fb635` | 11114 | E | N1 | a wide open eye at the centre of a shield, always watching |
| `achievement-reaction_first.png` | 2026-09-16 `f4fb635` | 11111 | E | N1 | a gauntleted hand catching a thrown dagger mid-air, quick hands |
| `achievement-read_manual.png` | 2026-09-16 `f4fb635` | 11330 | E | N1 | an open manual with reading spectacles resting on it, read the manual |
| `achievement-regions_4.png` | 2026-09-16 `f4fb635` | 11291 | E | N1 | a map quartered into heartland, marches, frontier and deeps, heartland to the deeps |
| `achievement-resurrect_5.png` | 2026-09-16 `f4fb635` | 11159 | E | N1 | a revolving door of light with a skull on one side and a face on the other, death's revolving door |
| `achievement-resurrect_ally.png` | 2026-09-16 `f4fb635` | 11024 | E | N1 | a hand reaching up from a grave into a shaft of holy light, back from the dead |
| `achievement-retire_run.png` | 2026-09-16 `f4fb635` | 11036 | E | N1 | a sword hung up over a cottage hearth with a pipe and a full purse, quit while ahead |
| `achievement-road_spell.png` | 2026-09-16 `f4fb635` | 11162 | E | N1 | a wizard's hand casting sparks over a winding road with a milestone, magic on the march |
| `achievement-runs_5.png` | 2026-09-16 `f4fb635` | 11255 | E | N1 | five tally marks carved into a roadside milestone, repeat offender |
| `achievement-saved_25.png` | 2026-09-16 `f4fb635` | 11321 | E | N1 | a field medic's bag with a red cross-shaped clasp and bandages, field medic |
| `achievement-saved_ally.png` | 2026-09-16 `f4fb635` | 11318 | E | N1 | a hand pulling a fallen comrade up from the ground, first aid |
| `achievement-schools_8.png` | 2026-09-16 `f4fb635` | 11141 | E | N1 | eight coloured arcane sigils arranged in a wheel, every school |
| `achievement-sell_500.png` | 2026-09-16 `f4fb635` | 11234 | E | N1 | a jewelled dagger on a fence's velvet cloth beside a heavy purse, fence |
| `achievement-settlements_6.png` | 2026-09-16 `f4fb635` | 11288 | E | N1 | six little town crests on a map with roads between, well known |
| `achievement-shove_10.png` | 2026-09-16 `f4fb635` | 11102 | E | N1 | an armored gauntlet shoving, an open palm with motion lines, off you go |
| `achievement-shove_hazard.png` | 2026-09-16 `f4fb635` | 11099 | E | N1 | a brazier of coals with a boot print kicking toward it, mind the brazier |
| `achievement-smash_10.png` | 2026-09-16 `f4fb635` | 11105 | E | N1 | a shattered crate and a broken barrel, splinters flying, property damage |
| `achievement-species_4.png` | 2026-09-16 `f4fb635` | 11198 | E | N1 | four different silhouettes, human, elf, dwarf, orc, side by side, all walks of life |
| `achievement-spell_5th.png` | 2026-09-16 `f4fb635` | 11021 | E | N1 | a spellbook open with five glowing arcane sigils rising, high magic |
| `achievement-spells_1.png` | 2026-09-16 `f4fb635` | 11132 | E | N1 | a single spark of magic leaping from a fingertip, first words |
| `achievement-spells_100.png` | 2026-09-16 `f4fb635` | 11135 | E | N1 | a wand with a hundred small runes along its length glowing, well practised |
| `achievement-spells_500.png` | 2026-09-16 `f4fb635` | 11138 | E | N1 | an archmage's staff with a great crystal and a spiral of runes, an archmage's habit |
| `achievement-spent_25000.png` | 2026-09-16 `f4fb635` | 11231 | E | N1 | a merchant's scale weighed down with gold and a patron's seal, patron of merchants |
| `achievement-summon_20.png` | 2026-09-16 `f4fb635` | 11153 | E | N1 | a menagerie of small spectral creatures around a summoning circle, menagerie |
| `achievement-summon_first.png` | 2026-09-16 `f4fb635` | 11150 | E | N1 | a glowing summoning circle with a spectral wolf rising from it, you are not alone |
| `achievement-surprise_win.png` | 2026-09-16 `f4fb635` | 11093 | E | N1 | a hooded figure with a dagger emerging from shadow, nobody saw us coming |
| `achievement-taking_stock.png` | 2026-09-16 `f4fb635` | 11327 | E | N1 | a mirror reflecting a ledger of stars, taking stock |
| `achievement-trance_identify.png` | 2026-09-16 `f4fb635` | 11174 | E | N1 | an elf's closed eyes under a crescent moon with a glowing ring above, elven nights |
| `achievement-travel_event_1.png` | 2026-09-16 `f4fb635` | 11261 | E | N1 | a small shrine of stones at a bend in a country road, something on the road |
| `achievement-travel_event_50.png` | 2026-09-16 `f4fb635` | 11264 | E | N1 | a worn pair of boots with fifty patches, well travelled |
| `achievement-unlock_class.png` | 2026-09-16 `f4fb635` | 11207 | E | N1 | a bell being rung in a tower at dawn, a new calling |
| `achievement-unlock_species.png` | 2026-09-16 `f4fb635` | 11204 | E | N1 | a heraldic shield with a new crest being carved, new blood |
| `achievement-unlock_subclass.png` | 2026-09-16 `f4fb635` | 11210 | E | N1 | a lectern with an open book and a deeper hidden page revealed, deeper study |
| `achievement-untouched.png` | 2026-09-16 `f4fb635` | 11045 | E | N1 | a pristine polished breastplate with a single rose petal on it, not a scratch |
| `achievement-wins_100.png` | 2026-09-16 `f4fb635` | 11042 | E | N1 | a golden laurel wreath around crossed swords with a worn banner, old hands |
| `achievement-wins_25.png` | 2026-09-16 `f4fb635` | 11039 | E | N1 | a bronze laurel wreath around crossed swords, veteran company |
| `achievement-xp_100k.png` | 2026-09-16 `f4fb635` | 11213 | E | N1 | a chest of experience crystals glowing blue, a career's worth |
| `achievement-xp_500k.png` | 2026-09-16 `f4fb635` | 11216 | E | N1 | a crystal the size of a fist glowing white, complete, nothing left to learn |
| `camp-jumped.png` | 2026-09-21 `7b60b59` | 12805 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace scrambling up from bedrolls half-armed as three hostile raiders in mismatched armour, faces shadowed under hoods and helms burst into the firelight of their night camp, chaos, no horses, mid shot |
| `camp-night.png` | 2026-09-21 `7b60b59` | 13101 | S | N6 | a campfire at night in open country under a sky full of stars, exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace around it on the ground: three asleep in bedrolls and the ranger sitting up awake on watch with the bow across their knees, tents behind, peaceful, mid shot |
| `camp-watch.png` | 2026-09-21 `7b60b59` | 12503 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace at a night camp, the knight on their feet with sword drawn shouting the other three awake as they scramble from bedrolls, torchlight, shapes in the dark beyond the firelight |
| `dwarf-alchemist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-alchemist.png` |
| `dwarf-alchemist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-alchemist.png` |
| `dwarf-alchemist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `dwarf-armorsmith-frown.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `dwarf-armorsmith.png` |
| `dwarf-armorsmith-happy.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `dwarf-armorsmith.png` |
| `dwarf-armorsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `dwarf-generalist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-generalist.png` |
| `dwarf-generalist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-generalist.png` |
| `dwarf-generalist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `dwarf-healer-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-healer.png` |
| `dwarf-healer-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-healer.png` |
| `dwarf-healer.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `dwarf-innkeeper-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-innkeeper.png` |
| `dwarf-innkeeper-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `dwarf-innkeeper.png` |
| `dwarf-innkeeper.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `dwarf-librarian-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `dwarf-librarian.png` |
| `dwarf-librarian-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `dwarf-librarian.png` |
| `dwarf-librarian.png` | 2026-09-21 `7b60b59` | 12801 | P | N3 | an elderly dwarven scholar librarian, groomed silver beard with gemstone clasps, wire-rim spectacles, deep velvet robes, holding a heavy stone-bound grimoire with glowing carved runes, shelves of stone tablets and scrolls behind, warm candlelight, painting fills the whole frame edge to edge |
| `dwarf-weaponsmith-frown.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `dwarf-weaponsmith.png` |
| `dwarf-weaponsmith-happy.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `dwarf-weaponsmith.png` |
| `dwarf-weaponsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-alchemist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-alchemist.png` |
| `elf-alchemist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-alchemist.png` |
| `elf-alchemist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-armorsmith-frown.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `elf-armorsmith.png` |
| `elf-armorsmith-happy.png` | 2026-09-16 `a5ad31e` | — | — | — | *not recorded* — mood variant of `elf-armorsmith.png` |
| `elf-armorsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-generalist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-generalist.png` |
| `elf-generalist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-generalist.png` |
| `elf-generalist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-healer-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-healer.png` |
| `elf-healer-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-healer.png` |
| `elf-healer.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-innkeeper-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `elf-innkeeper.png` |
| `elf-innkeeper-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `elf-innkeeper.png` |
| `elf-innkeeper.png` | 2026-09-21 `7b60b59` | 12803 | P | N3 | a welcoming elven innkeeper with pointed ears, warm and gracious expression, flowing braided hair, holding a carafe of spiced wine, standing behind a polished burl-wood tavern bar lit by hanging lanterns, painting fills the whole frame edge to edge |
| `elf-librarian-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-librarian.png` |
| `elf-librarian-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `elf-librarian.png` |
| `elf-librarian.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `elf-weaponsmith-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `elf-weaponsmith.png` |
| `elf-weaponsmith-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `elf-weaponsmith.png` |
| `elf-weaponsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `event-approach-ambush-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-ambush-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-ambush.png` | 2026-09-21 `7b60b59` | 11106 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace hidden behind rocks above a road, the ranger's bow drawn, waiting for three hostile raiders in mismatched armour, faces shadowed under hoods and helms coming round the bend below, mid shot |
| `event-approach-avoid-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-avoid-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-avoid.png` | 2026-09-21 `7b60b59` | 11100 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace crouched in roadside undergrowth watching three hostile raiders in mismatched armour, faces shadowed under hoods and helms pass on the road below, mid shot, dusk |
| `event-approach-engage-bandit.png` | 2026-09-21 `7b60b59` | 13227 | S | N2 | three human bandits in patched leather with axes and a crossbow coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-beast.png` | 2026-09-21 `7b60b59` | 13121 | S | N2 | three grey wolves, hackles up, snarling coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-construct.png` | 2026-09-21 `7b60b59` | 13157 | S | N2 | one stone golem, huge and rune-carved, lumbering coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-cultist.png` | 2026-09-21 `7b60b59` | 13042 | S | N2 | three hooded cultists in dark red robes with curved daggers coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-dragon.png` | 2026-09-21 `7b60b59` | 13260 | S | N2 | one young red dragon, wings half spread, smoke from its jaws coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-dwarf.png` | 2026-09-21 `7b60b59` | 13063 | S | N2 | three dwarf warriors in heavy mail with braided beards and axes coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-elemental.png` | 2026-09-21 `7b60b59` | 13654 | S | N2 | one fire elemental, a roaring man-shape of living flame coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-elf.png` | 2026-09-21 `7b60b59` | 13066 | S | N2 | three elf warriors in silver mail with longbows coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-fey.png` | 2026-09-21 `7b60b59` | 13151 | S | N2 | three fey warriors, thin and pale with antlers and leaf cloaks, glowing eyes coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-giant.png` | 2026-09-21 `7b60b59` | 13230 | S | N2 | one hill giant, twice a man's height, ragged hides and a tree-trunk club coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-gnoll.png` | 2026-09-21 `7b60b59` | 13239 | S | N2 | three gnolls, hyena-headed humanoids with spotted fur and spears coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-goblinoid.png` | 2026-09-21 `7b60b59` | 13118 | S | N2 | three goblins, small and green-skinned with big ears, crude spears and hide shields coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-human.png` | 2026-09-21 `7b60b59` | 13769 | S | N2 | three human men-at-arms in a lord's livery, each holding one spear, medieval coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-kobold.png` | 2026-09-21 `7b60b59` | 13033 | S | N2 | three kobolds, small red-scaled lizard folk with spears and slings coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-monstrosity.png` | 2026-09-21 `7b60b59` | 13148 | S | N2 | one owlbear, a hulking feathered bear with an owl's head and beak coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-orc.png` | 2026-09-21 `7b60b59` | 13136 | S | N2 | three orcs, grey-green skin and tusks, heavy axes and spiked leather coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-engage-soldier.png` | 2026-09-21 `7b60b59` | 13945 | S | N2 | three medieval men-at-arms turned deserter, rusty chainmail and torn surcoats, spears and a round shield, medieval coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage-undead.png` | 2026-09-21 `7b60b59` | 13024 | S | N2 | three skeletal undead warriors in rusted mail, empty eye sockets, notched swords coming down a country road straight at the viewer, weapons out, mid shot, no other people |
| `event-approach-engage.png` | 2026-09-21 `7b60b59` | 12209 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace advancing shoulder to shoulder down an open road straight at three hostile raiders in mismatched armour, faces shadowed under hoods and helms, shields up, steel out, mid shot |
| `event-approach-greet-dwarf.png` | 2026-09-21 `7b60b59` | 13172 | S | N2 | a mounted dwarf patrol of three in heavy mail on shaggy ponies under a clan banner riding up a country road toward the viewer, the captain raising an open hand in greeting, sunlit, mid shot, no other people |
| `event-approach-greet-elf.png` | 2026-09-21 `7b60b59` | 14575 | S | N2 | a mounted patrol of three elves with long pointed ears and pale faces in silver mail on grey horses under a leaf banner riding up a country road toward the viewer, the captain raising an open hand in greeting, sunlit, mid shot, no other people |
| `event-approach-greet-human.png` | 2026-09-21 `7b60b59` | 13678 | S | N2 | a mounted patrol of three medieval knights in surcoats over mail, bare-headed, on horses under a heraldic banner riding up a country road toward the viewer, the captain raising an open hand in greeting, sunlit, mid shot, no other people |
| `event-approach-greet-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-greet.png` | 2026-09-21 `7b60b59` | 11012 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace raising open hands to a mounted human patrol of three in a lord's livery on horses under a banner on a country road, friendly, sunlit, mid shot |
| `event-approach-parley-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-parley-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-parley.png` | 2026-09-21 `7b60b59` | 11103 | S | N3 | the priest of exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace walking forward alone with open hands toward three hostile raiders in mismatched armour, faces shadowed under hoods and helms across a road, the other three waiting behind, wary, mid shot |
| `event-approach-pass-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-approach-pass.png` | 2026-09-21 `7b60b59` | 11115 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace keeping to the far side of a road as a mounted human patrol of three in a lord's livery on horses under a banner rides by, heads down, no words, overcast, mid shot |
| `event-audience-dwarf.png` | 2026-09-21 `7b60b59` | 14413 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace standing before a bearded dwarven lord enthroned on a raised stone dais in a great hall cut deep into the mountain, pillars and forge-light, the hall otherwise empty, mid shot |
| `event-audience-elf.png` | 2026-09-21 `25e4e5b` | 11003 | S | N1 | an elven lord's court held under a living canopy of silver-leaved trees lit by hanging lanterns, receiving a small band of medieval adventurers with packs and weapons standing before her |
| `event-audience-human.png` | 2026-09-21 `7b60b59` | 14211 | S | N3 | a human lord enthroned on a dais in a timbered great hall hung with banners, firelight, receiving exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace bowed before him, the hall otherwise empty, mid shot |
| `event-cache-fail.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-cache-pass.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-cache.png` | 2026-09-16 `992a13f` | 9003 | S | N5 | Something half-buried under the roots of an old tree beside a wilderness road, a corner of weathered wood and rusted iron showing through leaves, an adventurer crouched over it |
| `event-calling-acolyte.png` | 2026-09-21 `51e285e` | 14301 | S | N1 | a desecrated wayside shrine in a wood, the holy statue toppled and broken on the ground, candles snuffed and kicked over, offerings smashed and scattered, a dark dried bloodstain across the altar stone, grey morning light, no people |
| `event-calling-artisan.png` | 2026-09-21 `51e285e` | 14303 | S | N1 | a woodworker's cart smashed and overturned on a muddy road, a broken wheel, its load of fine hand tools spilled across the mud in the foreground: chisels, a wooden plane, a mallet, a folding rule, a small chest of tools burst open, an empty harness, overcast |
| `event-calling-charlatan.png` | 2026-09-21 `51e285e` | 11006 | S | N1 | the gate of a small walled market town at dusk, lanterns being lit on the gatehouse, a few townsfolk going in, a lone figure hesitating on the road outside |
| `event-calling-criminal.png` | 2026-09-21 `51e285e` | 11009 | S | N1 | a rough band of armed men waiting at a crossroads under a bare tree, leaning on spears, watching the road, late afternoon, a signpost |
| `event-calling-entertainer.png` | 2026-09-21 `7b60b59` | 14421 | S | N3 | a timbered feast hall hung with banners, a lord and lady at a high table, a lone musician with a lute standing in the firelight playing to them, four servants along the wall, no one else |
| `event-calling-farmer.png` | 2026-09-21 `51e285e` | 11015 | S | N1 | a burned farmstead, blackened beams and a fallen barn in a field, and behind it a dark cave mouth in the hillside, thin smoke, dawn |
| `event-calling-guard.png` | 2026-09-21 `51e285e` | 11018 | S | N1 | a bandit band's camp among the trees, tents and a cookfire, stolen goods heaped, sentries at the edge of the firelight, night |
| `event-calling-guide.png` | 2026-09-21 `51e285e` | 11021 | S | N1 | a lone stone watchtower on a high ridge looking out over a whole country of forests, rivers and distant hills, clear evening light |
| `event-calling-hermit.png` | 2026-09-21 `51e285e` | 11024 | S | N1 | a ring of ancient standing stones on a moor under a night sky full of stars, faint mist between the stones, no people |
| `event-calling-merchant.png` | 2026-09-21 `51e285e` | 11027 | S | N1 | a wrecked river barge broken on a riverbank, crates and barrels bobbing in the water and strewn on the mud, reeds, grey light |
| `event-calling-noble.png` | 2026-09-21 `51e285e` | 11030 | S | N1 | a fine carriage with a rival house's crimson banner drawn up at a city gate, liveried footmen, guards at the gate, a city of towers behind |
| `event-calling-sage.png` | 2026-09-21 `51e285e` | 11033 | S | N1 | a library of rotting books in a torch-lit cave, shelves cut into the rock, mould and cobwebs, a few volumes still whole, dripping water |
| `event-calling-sailor.png` | 2026-09-21 `51e285e` | 11036 | S | N1 | a broken ship's hull lying on its side on a grey shingle shore, ribs open to the sky, ropes and a torn sail, gulls, cold light |
| `event-calling-scribe.png` | 2026-09-21 `51e285e` | 11039 | S | N1 | the ruined walls of an ancient hall, fallen columns, carved stones with worn inscriptions half-buried in grass, afternoon sun |
| `event-calling-soldier.png` | 2026-09-21 `7b60b59` | 14423 | S | N3 | five medieval deserters on foot trudging a country road, torn surcoats in a company's faded colours over rusting mail, a ripped banner, mismatched spears and swords, a stolen mule, glancing back over their shoulders, overcast, no one else |
| `event-calling-wayfarer.png` | 2026-09-21 `51e285e` | 11045 | S | N1 | a small hermit's hut at the very end of a narrow mountain track, smoke from the chimney, the track ending at its door, peaks and cloud beyond |
| `event-carter-fail.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-carter-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-carter.png` | 2026-09-16 `2348d55` | 9137 | S | N4 | A farm cart tipped into a roadside ditch, one wheel off, a frightened team of horses, an old carter wringing his hands, the adventurers coming up the road |
| `event-downtime-bad-lead.png` | 2026-09-21 `3696b08` | 11024 | S | N1 | a grinning stranger leaning over a bar drawing a crude treasure map on a napkin with a stub of charcoal, candlelight |
| `event-downtime-brawl.png` | 2026-09-21 `7b60b59` | 20825 | S | N3 | a tavern brawl, two men grappling and swinging fists at each other in the middle of the room, a chair broken, tables overturned and tankards flying, three patrons backing away, lamplight, no one else |
| `event-downtime-carouse.png` | 2026-09-21 `7b60b59` | 20921 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace at a tavern table at night with a fiddler playing beside them, tankards raised, singing, warm firelight, the rest of the room in shadow, mid shot |
| `event-downtime-insult.png` | 2026-09-21 `7b60b59` | 20827 | S | N3 | a slighted noble in a red cloak turning away sharply in a torch-lit hall, two attendants following him, one stunned adventurer left standing alone, the hall otherwise empty, mid shot |
| `event-downtime-pit.png` | 2026-09-21 `7b60b59` | 20923 | S | N3 | two armed fighters circling each other at the centre of a torch-lit sunken fighting pit, seen from the sand, the rim above them dark, a few shouting faces lit by torches at the edge, no one else |
| `event-downtime-tab.png` | 2026-09-21 `3696b08` | 11015 | S | N1 | a hungover adventurer slumped at an empty tavern table in grey morning light, an unpaid bill and an empty tankard before them |
| `event-downtime-train.png` | 2026-09-21 `3696b08` | 11000 | S | N1 | a master-at-arms in a fenced practice yard drilling a young fighter through sword and shield drills, sacks of sand and racked weapons, morning light |
| `event-ford-fail.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-ford-pass.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-ford.png` | 2026-09-16 `2348d55` | 9005 | S | N5 | A river ford running high and brown after rain, the road vanishing into fast water between wooded banks, adventurers at the edge weighing it up |
| `event-foul-water-fail.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-foul-water-pass.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-foul-water.png` | 2026-09-16 `992a13f` | 9004 | S | N5 | A forest stream beside the road, adventurers stopped to drink, the water strangely dark and still under overhanging trees |
| `event-good-ground-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-good-ground.png` | 2026-09-16 `992a13f` | 9005 | S | N5 | A clear dry road running straight through rolling green country under a bright blue sky, the adventurers walking easily, banners of cloud |
| `event-lodge-garden.png` | 2026-09-21 `3a6af27` | 33072 | S | N1 | raised herb beds with a beehive |
| `event-lodge-house.png` | 2026-09-21 `3a6af27` | 11000 | S | N1 | a timber-and-stone house with the company's banner over the door |
| `event-lodge-maproom.png` | 2026-09-21 `7b60b59` | 33283 | S | N7 | a medieval scriptorium at night, a large hand-drawn parchment map of an imaginary fantasy kingdom pinned to a rough stone wall with iron pins joined by red thread, painted coastlines and a mountain range, ink and quills on an oak table, a single candle, no people |
| `event-lodge-shrine.png` | 2026-09-21 `7b60b59` | 33181 | S | N3 | a small shrine of stacked stones with a lantern in a walled garden, evening, no people |
| `event-lodge-strongroom.png` | 2026-09-21 `3a6af27` | 11003 | S | N1 | an iron-bound strongroom door in a cellar |
| `event-lodge-yard.png` | 2026-09-21 `3a6af27` | 33071 | S | N1 | a fenced yard with a training post and racks |
| `event-refugees-fail.png` | 2026-09-21 `6242eaa` | — | — | — | *not recorded* — outcome frame |
| `event-refugees-pass.png` | 2026-09-21 `6242eaa` | — | — | — | *not recorded* — outcome frame |
| `event-refugees.png` | 2026-09-21 `6242eaa` | 9014 | S | N4 | A family of refugees on a country road at dusk, a handcart piled with bundles, a child on a woman's hip, an old man leaning on a stick, adventurers stopped to speak with them, smoke on the horizon behind |
| `event-rough-going-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-rough-going-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-rough-going.png` | 2026-09-21 `7b60b59` | 13401 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace on a wilderness road turned to mud and tangled roots under a grey sky, steep wooded slope, the ranger at the front reading the ground, mid shot |
| `event-shrine-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-shrine-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-shrine.png` | 2026-09-21 `7b60b59` | 13909 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace stopped before a small weathered stone shrine at a country crossroads, moss and old offerings, a carved figure worn smooth, mid shot |
| `event-snare-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-snare-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-snare.png` | 2026-09-16 `2348d55` | 9009 | S | N5 | A tripwire strung low across a narrow forest path between two trees, half-hidden in leaf litter, the adventurers approaching in the gloom |
| `event-storm-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-storm-pass.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-storm.png` | 2026-09-16 `2348d55` | 9011 | S | N5 | A storm front rolling in over a wilderness road, the sky turning a sick green-black, wind flattening the grass, the adventurers looking up |
| `event-toll-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-toll-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-toll.png` | 2026-09-16 `2348d55` | 9100 | S | N4 | A pole barred across a forest road, a rough band of medieval bandits with spears and axes lounging beside it, a small fire, the adventurers halted before them |
| `event-tracks-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-tracks-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-tracks.png` | 2026-09-21 `7b60b59` | 13205 | S | N2 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace on a dirt road at the edge of a dark forest, the ranger kneeling to study fresh tracks crossing the road, the other three waiting, morning mist, mid shot |
| `event-wayfarer-fail.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-wayfarer-pass.png` | 2026-09-16 `992a13f` | — | — | — | *not recorded* — outcome frame |
| `event-wayfarer.png` | 2026-09-16 `992a13f` | 9002 | S | N5 | A hooded wayfarer met on a country road at golden hour, leaning on a staff, a bundle on their back, the adventurers' road stretching behind |
| `event-waystone-fail.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-waystone-pass.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-waystone.png` | 2026-09-16 `2348d55` | 9008 | S | N5 | An old carved waystone half-swallowed by tall grass beside a wilderness road, runes cut into the granite, a traveller crouched to read it |
| `event-wreck-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `event-wreck-pass.png` | 2026-09-16 `2348d55` | — | — | — | *not recorded* — outcome frame |
| `event-wreck.png` | 2026-09-16 `2348d55` | 9110 | S | N4 | The wreck of a mercenary company on a wilderness road: an overturned wagon, broken shields and rusted mail scattered in the grass, crows, the adventurers arriving |
| `human-alchemist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-alchemist.png` |
| `human-alchemist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-alchemist.png` |
| `human-alchemist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `human-armorsmith-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-armorsmith.png` |
| `human-armorsmith-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-armorsmith.png` |
| `human-armorsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `human-generalist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-generalist.png` |
| `human-generalist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-generalist.png` |
| `human-generalist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `human-healer-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-healer.png` |
| `human-healer-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-healer.png` |
| `human-healer.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `human-innkeeper-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-innkeeper.png` |
| `human-innkeeper-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-innkeeper.png` |
| `human-innkeeper.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `human-librarian-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `human-librarian.png` |
| `human-librarian-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `human-librarian.png` |
| `human-librarian.png` | 2026-09-21 `7b60b59` | 12805 | P | N3 | a scholarly human librarian, round spectacles, ink-stained fingers, holding an open leather-bound book, a grand library of towering bookcases and soft amber lamplight behind, painting fills the whole frame edge to edge |
| `human-weaponsmith-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-weaponsmith.png` |
| `human-weaponsmith-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `human-weaponsmith.png` |
| `human-weaponsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `inn-dwarf.png` | 2026-09-16 `b2ffa48` | 11403 | S | N4 | the common room of a dwarven inn cut from stone, a huge hearth, carved pillars, oak casks, warm firelight |
| `inn-elf.png` | 2026-09-16 `b2ffa48` | 11406 | S | N4 | the common room of an elven inn grown from living wood, lanterns in the branches, moss and carved chairs, soft green-gold light |
| `inn-human.png` | 2026-09-16 `b2ffa48` | 11400 | S | N4 | the common room of a human medieval inn, timber beams, a great hearth, long tables, tankards, warm lamplight, empty chairs waiting |
| `inn-orc.png` | 2026-09-16 `b2ffa48` | 11409 | S | N4 | the common room of an orc inn under hides and bone, a fire pit, trophies on the walls, rough benches, smoky red light |
| `landmark-hut.png` | 2026-09-21 `6242eaa` | 11009 | S | N1 | a hermit's hut in the trees, smoke rising from its chimney and a bee-skep beside the door, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `landmark-ruins.png` | 2026-09-21 `6242eaa` | 11000 | S | N1 | the ruin of an old chapel, its roof fallen in and carved stones half-buried in rubble and ivy, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `landmark-shrine.png` | 2026-09-21 `6242eaa` | 11003 | S | N1 | a wayside shrine at a bend in the road, small offerings left at its foot and a lantern hung beside it, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `landmark-stones.png` | 2026-09-21 `6242eaa` | 11006 | S | N1 | a ring of weathered standing stones on a windswept hilltop, long grass and a wide sky, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `landmark-tower.png` | 2026-09-21 `6242eaa` | 11015 | S | N1 | a ruined watchtower on a rise, its top broken open to the sky, a wide view over the country below, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `landmark-wreck.png` | 2026-09-21 `6242eaa` | 11012 | S | N1 | an overturned wagon by the road, goods and broken crates scattered in the grass, a small band of medieval adventurers with packs and weapons arriving small in the frame |
| `orc-alchemist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-alchemist.png` |
| `orc-alchemist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-alchemist.png` |
| `orc-alchemist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `orc-armorsmith-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-armorsmith.png` |
| `orc-armorsmith-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-armorsmith.png` |
| `orc-armorsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `orc-generalist-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-generalist.png` |
| `orc-generalist-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-generalist.png` |
| `orc-generalist.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `orc-healer-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-healer.png` |
| `orc-healer-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-healer.png` |
| `orc-healer.png` | 2026-09-21 `7b60b59` | 13107 | P | N8 | an orc shaman, a big green-skinned orc with two thick lower tusks, heavy brow and small ears, bone necklace and grey braids, holding a clay bowl of crushed herbs, a hide tent hung with drying plants behind, firelight, painting fills the whole frame edge to edge |
| `orc-innkeeper-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-innkeeper.png` |
| `orc-innkeeper-happy.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-innkeeper.png` |
| `orc-innkeeper.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `orc-librarian-frown.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-librarian.png` |
| `orc-librarian-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-librarian.png` |
| `orc-librarian.png` | 2026-09-21 `7b60b59` | 12909 | P | N3 | an old orc lore-keeper with grey-green skin, tusks and a scarred brow, one cracked spectacle lens, holding a heavy hide-bound book, a cave library of stacked tomes and skull lanterns behind, painting fills the whole frame edge to edge |
| `orc-weaponsmith-frown.png` | 2026-09-16 `3cb6f8d` | — | — | — | *not recorded* — mood variant of `orc-weaponsmith.png` |
| `orc-weaponsmith-happy.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — mood variant of `orc-weaponsmith.png` |
| `orc-weaponsmith.png` | 2026-09-15 `43c4e26` | — | — | — | *not recorded* — counter portrait, first pass |
| `quest-clear_lair.png` | 2026-09-16 `f4fb635` | 11112 | E | N1 | a dark cave mouth with a skull on a stake before it, a torch |
| `quest-collect_item.png` | 2026-09-16 `f4fb635` | 11103 | E | N1 | a leather sack spilling gathered herbs, ears and trinkets, a collector's bundle |
| `quest-deliver_goods.png` | 2026-09-16 `f4fb635` | 11118 | E | N1 | a sealed parcel wrapped in oilcloth with a wax seal and a courier's strap |
| `quest-hunt_party.png` | 2026-09-16 `f4fb635` | 11106 | E | N1 | a wanted poster nailed to a board with a rough sketch of a bandit chief, a dagger through it |
| `quest-kill_count.png` | 2026-09-16 `f4fb635` | 11100 | E | N1 | a tally of notches carved into a wooden shield, a bloodied axe beside it, bounty |
| `quest-raid_settlement.png` | 2026-09-16 `f4fb635` | 11109 | E | N1 | a burning village palisade gate with a war horn, a raid |
| `quest-rescue.png` | 2026-09-21 `7b60b59` | 12701 | E | N3 | a broken iron manacle and its chain beside an opened cage door, a ring of keys, a rescue |
| `quest-scout_region.png` | 2026-09-16 `f4fb635` | 11121 | E | N1 | a rolled map with a compass and a spyglass, a scout's kit |
| `quest-supply_item.png` | 2026-09-16 `f4fb635` | 11115 | E | N1 | a wooden crate of potions and bandages with a healer's mark, supplies |
| `room-alcove.png` | 2026-09-21 `7b60b59` | 12565 | S | N3 | a cramped shrine alcove deep in a cave, a crude stone idol with guttering candles and offerings, three hooded cultists rising from their knees, torchlight, close, no one else |
| `room-barred-door.png` | 2026-09-21 `7b60b59` | 13173 | S | N2 | all four of exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace standing together with their backs to a heavy wooden dungeon door barred shut with a thick beam, catching their breath, a lantern, dark stone all around, group shot |
| `room-choke.png` | 2026-09-16 `b2ffa48` | 11139 | S | N4 | a narrow choke point in a cave passage, one way through, defenders braced behind a barricade of crates and spears |
| `room-cistern.png` | 2026-09-16 `b2ffa48` | 11103 | S | N4 | an underground cistern, waist-deep black water between stone pillars, torchlight on ripples, something moving beneath the surface |
| `room-dead-adventurer-fail.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `room-dead-adventurer-pass.png` | 2026-09-21 `7b60b59` | — | — | — | *not recorded* — outcome frame |
| `room-dead-adventurer.png` | 2026-09-21 `7b60b59` | 12469 | S | N3 | the skeleton of a long-dead adventurer in rusted fine armour slumped against a cave wall, skull tipped forward, a sword across its knees, a cold lantern beside it, no living people |
| `room-dry-corner.png` | 2026-09-21 `7b60b59` | 13171 | S | N2 | all four of exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace sitting together against the wall of a dry cave corner resting with their packs, a small shielded lantern between them, quiet, medieval, group shot |
| `room-flooded.png` | 2026-09-16 `b2ffa48` | 11124 | S | N4 | a flooded stone passage, cold water to the chest, a strong current pulling the wrong way, a torch held high |
| `room-forge.png` | 2026-09-16 `b2ffa48` | 11127 | S | N4 | an underground forge room, coals glowing red in a stone hearth, a hulking smith with a hammer turning from the anvil |
| `room-fungus.png` | 2026-09-16 `b2ffa48` | 11118 | S | N4 | a cave gallery lit by glowing blue and green fungus on the walls, spores in the air, something crawling in the glow |
| `room-gallery.png` | 2026-09-16 `b2ffa48` | 11100 | S | N4 | a collapsed mine gallery underground, heaped rubble and broken timbers, torchlight, shapes crouched among the stones that are not stones |
| `room-guard-post.png` | 2026-09-16 `b2ffa48` | 11109 | S | N4 | a guard post inside a lair, a crude wooden door with a bench and a brazier, two armed guards on their feet, alarmed |
| `room-kennels.png` | 2026-09-16 `b2ffa48` | 11121 | S | N4 | underground kennels, heavy chains and iron rings on stone, a huge beast straining at a chewed chain, snarling |
| `room-long-stair.png` | 2026-09-21 `7b60b59` | 12561 | S | N3 | a long narrow stone stair climbing through rock, held at the top by three armed guards with spears, torchlight from above, no one else |
| `room-midden.png` | 2026-09-16 `b2ffa48` | 11106 | S | N4 | a bone midden in a cave, heaps of gnawed bones and refuse, a low fire, goblins feeding, foul torchlight |
| `room-nook-fail.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-nook-pass.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-nook.png` | 2026-09-16 `b2ffa48` | 12399 | S | N4 | a quartermaster's nook underground, shelves of sorted supplies, sacks, rope and bottles, a lantern |
| `room-pillared-hall.png` | 2026-09-16 `b2ffa48` | 11115 | S | N4 | a wide underground hall of many stone pillars, deep shadows between them, figures half-seen behind the columns |
| `room-quarters.png` | 2026-09-21 `7b60b59` | 12467 | S | N3 | underground sleeping quarters in a cave, bedrolls and furs, three bandits waking and scrambling for weapons, a dropped lantern, no one else |
| `room-side-passage.png` | 2026-09-16 `b2ffa48` | 11160 | S | N4 | a caved-in side passage, a dead end of fallen rock and dust, undisturbed for years, a torch showing nothing |
| `room-spoil-heap.png` | 2026-09-21 `7b60b59` | 12463 | S | N3 | a mine diggings chamber with a great heap of spoil rock and picks, three ragged medieval miners with picks and a lantern climbing up out of the pit to see who is there, no one else |
| `room-strongbox-fail.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-strongbox-pass.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-strongbox.png` | 2026-09-16 `b2ffa48` | 12345 | S | N4 | an iron-bound strongbox in a lair storeroom, chains and a heavy lock, torchlight on studded wood |
| `room-tribute-fail.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-tribute-pass.png` | 2026-09-16 `b2ffa48` | — | — | — | *not recorded* — outcome frame |
| `room-tribute.png` | 2026-09-16 `b2ffa48` | 11145 | S | N4 | a tribute pile in a cave: heaped coins, cups and trinkets on a stone slab before a crude throne |
| `summary-defeat.png` | 2026-09-21 `7b60b59` | 12623 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace lying wounded and beaten on a muddy battlefield, dropped swords and a broken banner in the mud, crows landing, grey driving rain, no one standing, no one else |
| `summary-victory.png` | 2026-09-21 `7b60b59` | 12521 | S | N3 | exactly four adventurers and nobody else: an armoured knight with sword and shield, a hooded ranger with a longbow, a robed wizard with a staff, a priest in chainmail with a mace standing victorious over two fallen raiders on a battlefield, weapons raised, sunlight breaking through cloud, mid shot, no one else |

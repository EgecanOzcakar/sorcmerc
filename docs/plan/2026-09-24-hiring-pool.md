## Hired, not made — the inns' hiring pool (2026-09-24)

The owner's call on recruitment, built. A new run makes **one** hero, the
founder, in the creator. Everyone after that is hired from the people sitting in
an inn's common room, and the company does not redesign them. They arrive with a
species, class, background, ability scores, skills, tools, languages,
expertise, weapon mastery, feature choices (Divine Order, Primal Order), gear
and a temper and a past (both traits). What the company decides is what they
become from here: the subclass, the spells, and the normal level-up choices (an
ability increase or a feat, a fighting style). That is the same set the level-up
screen already hands a player, so a hire is the creator's work done by the dice,
minus level-up's choices, finished on a settle-in page before the fee is paid.

**The pool** (`core/recruits.gd`) is seeded off the settlement and the
world-day, `hash("recruit|<id>|<day>|<chair>")`. That is the market shelf's
idiom. It is not seeded off `last_visited`, which moves on every visit and would
make the pool a slot machine with a door. Walking out and back in, or reloading,
shows the same faces. Tomorrow shows new ones. A hire is remembered per
settlement and day (`party.hiring["taken"]`), so the chair empties. A town that
refuses to trade with the company has nobody who will sign with it either.

| knob | value | kind |
|---|---|---|
| chairs | city 3, town 2, camp 1 | TUNING, taste |
| recruit level | `Regions.level_here` − 1, floor 1 | the owner's rule |
| fee | 50 ◉ × level, −10% per renown title | the owner's figure; the discount is TUNING |
| roster cap | 6 / 8 / 10 / 12 / 14 by renown title | TUNING, taste; stops hiring, never trims |
| founding purse | 150 ◉ | TUNING, **not the owner's call**, see Still open |
| veteran | 1 day in 3, the first chair | TUNING, taste |

None of these came from a sweep. They are taste, marked TUNING where they are
defined.

**Who they are** (`Recruits.build`). An unlocked species and class
(`core/progression.gd`: a fresh profile rolls only its starting four and five).
The standard array, dealt the way the creator's quick build deals it: the class's
lead and second score fixed, the other four shuffled. It is always inside the
creator's budget. A kit from `data/recruit-kits.json` for the hand they are
better with, skipping anything they are not proficient with or too weak to
wear. A name from `data/recruit-names.json` by species. Every open choice that
is not the player's is answered through the creator's own choice model, moved
out of `scenes/creator/creator.gd` into `core/rules/choice_pick.gd` because a
core module may not preload a scene. `creator.gd` keeps one-line wrappers, so
every `Creator.*` call reads the same. The background's +2/+1 goes where the
class leans. A wasted pick (a skill they already have) is avoided while there is
anything else to pick. Mastery goes to the weapons they carry.
`Recruits.players_pick(p)` is the line between the two halves: subclass,
spells, a fighting style, anything a subclass grants, and a *class* level's
ability increase or feat.

**Veterans.** Barracks heroes from earlier runs no longer walk into a new
run's roster. One day in three, an inn's first chair is one of them: at their
own class, species and everything else, and at their **own** level. They are
never rebuilt lower, because their file is their career and the run writes it
back on the way out. They are offered only where the country fights at their
level or higher (`level <= Regions.level_here`), so a level-9 veteran is a
Frontier hire, not a heartland walkover. Hired, they keep their barracks id.

**The screens.**
- **The founding** (`scenes/game/game.gd` `show_party_setup`): a new
  open-world or pack run starts with an empty roster and `Recruits.found(party)`
  (the rule and the purse). The hint says to make the founder. Begin with nobody
  says the same. After the founder, Create new greys with *"The rest of the
  company is hired at an inn."* The linear debug campaign
  (`SORCMERC_LINEAR_CAMPAIGN=1`) keeps the old door, the whole barracks.
- **The inn** (`scenes/world/world.gd` `_hiring_rows`): a "Looking for work"
  list heads the inn's scrolling list. Each row gives the name, species, class,
  level and a veteran tag; under it the background and traits; the fee is on
  the button. A row the company can't take says why in its second line (the
  purse is N short, or a company of this name keeps N on the books). The square's
  Inn door counts who is looking.
- **Settling in** (`scenes/creator/levelup.gd` `set_recruit`): no level is
  added. A card shows what they came with and the fee, and every decided choice
  is drawn read-only under "What they came with". Only the open ones are live.
  Confirm is "Take them on (N ◉)". It calls `Recruits.hire`, which re-checks the
  chair, the cap, the purse and the choices, then pays, mints an id nobody holds
  (barracks *and* roster), adds them to the roster and empties the chair. A
  refused hire keeps the page up with the reason. Cancel ("Not this one") hires
  nobody.

**Grandfathering, no save version.** `party.hiring` defaults to `{}`, which is
the old rule. Such a save keeps its roster and its Create new and gets the inns'
pools as well. A new run writes `{"rule": "hire"}`. The key rides the world
save's party dict (`Recruits.to_dict/from_dict`, the Downtime/Lodge pattern).
JSON's floats are read back as ints.

**Mods.** `recruit-names.json` and `recruit-kits.json` join the pack allowlist
(`core/mod/manifest.gd`, `docs/modding.md`). A pack's new species can have its
own names (without a list, it gets the `default` record's), and its new class
can sign on armed.

Tests:
- `tests/test_recruits.gd` (new) checks:
  - the pool: same settlement and day gives the same pool, down to the picks; the next day and another town give new faces; 3/2/1 chairs;
  - level and fee: the band level minus one, and the fee;
  - 60 rolled recruits: standard array inside the budget, unlocked species and class, traits, proficient gear, only the player's choices left open, nothing of the player's decided for them;
  - every kit legal for its class, and names for every species;
  - the hire: refused while choices are open; then paid, on the roster, marching, its chair gone, not hirable twice, a same-named second hire gets its own id;
  - the taken chairs and the rule survive a JSON save round-trip;
  - short purse and full roster say so and hire nobody; an over-cap roster keeps everyone; the cap and discount move with renown;
  - veterans at their own level, never above the country, hired under their barracks id;
  - the settle-in page's locks, fee, refusal and Cancel;
  - the party screen's Create new, founding and grandfathered.
- `tests/test_world_save.gd` checks that the hiring key round-trips and that a save without it is grandfathered.
- `tests/test_game_flow.gd`: the linear run still loads the barracks; an open-world run starts empty under the rule.
- `tests/drive_game.gd` makes the founder on both new runs, and checks the barracks stays out and Create new shuts after the founder.
- `tests/drive_completionist.gd` has a new required deed, `town:hire`: press Take them on at the inn, answer every open choice on the settle-in page by its buttons, confirm, and check the roster grew by one and the purse by the fee.

Shots (`tests/shot_hiring.gd`):
- `docs/shots/hiring-founding.png`
- `docs/shots/hiring-inn.png`
- `docs/shots/hiring-settle-in.png`

### Still open

- **The founding purse is mine, not the owner's.** Without it a run starts
  with one level-1 hero and 0 ◉, and cannot hire until the road pays. 150 ◉ is
  three level-1 hands, the old start's party of four if the founder spends it
  that way. A lone founder's first fights are not measured; if the owner wants
  the lonely start, set `FOUNDING_PURSE` to 0.
- **Co-op.** `core/coop.gd`'s `owners_for` splits heroes by roster index, so a
  one-hero start leaves the guest nobody to play until the first hire. Not
  redesigned here.
- **Veterans and other saves.** The barracks is shared by every run. A veteran
  hired here can still be on an older run's roster, and whichever run is left
  last writes the file. The same was true before for any hero in two runs.
- **The pool's level moves within the day.** The faces are seeded; their level
  is read from the party each time. A party that levels mid-day sees the same
  people a level up. Harmless, but not fully frozen.
- **The settle-in subclass pick is not gated by progression**, the same as the
  level-up page's. The creator greys a locked subclass; the level-up and
  settle-in pages do not.
- **A prepared caster arrives with an empty prepared list**, the same as a hero
  from the creator. The prepare page fills it.
- Names can repeat within a pool or match someone on the roster. Ids never
  collide.

# The Ladder and Renown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A non-decaying per-faction ladder (Stranger → Known → Trusted → Sworn) climbed by deeds, whose rungs open people — a neighbour's job, a cheaper then free bed, the armorsmith's back room of magic items, a patron who posts work about the whole map, one audience with the lord — and a party-wide renown title that puts a premium on every job.

**Architecture:** One new static module, `core/ladder.gd` (`Ladder`), holds deeds, rungs, renown and audiences, saved under `"ladder"` beside opinion. Five existing credit sites call `Ladder.deed`. Every door is a one-line gate on an existing system (`offer_for`, `inn_cost`, `visit`'s stock, `_world_offers`' reach, `offers`' reward), plus the world screen's lines, one market tab, one town-square button.

**Tech Stack:** Godot 4.7 / GDScript; tests are `SceneTree` scripts run headless (`timeout 120 godot --headless --path . -s tests/<file>.gd`; screen tests with `SORCMERC_FAST=1 timeout 180`). Image generation: `~/localgen/gen_sorcmerc_scenes.py` with ComfyUI.

**Spec:** `docs/superpowers/specs/2026-09-21-ladder-renown-design.md`

## Global Constraints

- Every godot invocation is `--headless`. Never open a window.
- The module is `Ladder` in `core/ladder.gd`; it preloads nothing from `core/` except via `load()` at call time (`WorldAI.is_monster`) — `quest.gd`, `faction_opinion.gd`, `raids.gd`, `landmarks.gd`, `settlement_visit.gd`, `quest_posting.gd` will preload `ladder.gd`, so it must not preload them back.
- Constants verbatim: `RUNGS ["Stranger", "Known", "Trusted", "Sworn"]`, `RUNG_AT [0, 4, 12, 25]`, `KNOWN 1`, `TRUSTED 2`, `SWORN 3`, `TITLES ["Nobodies", "Hirelings", "a Company of Note", "Famous", "Legends"]`, `TITLE_AT [0, 6, 18, 40, 80]`, `PAY_PER_TITLE 0.1`, `BACK_ROOM_N 3`, `BACK_ROOM_RARE 2`, `INN_KNOWN 0.5`, `AUDIENCE_XP 200`.
- Deeds: job turned in 1 (taker's faction); `credit_fight` 1 per faction moved; raid lifted 2; lair settled 3; offering 1. Monster factions never gain deeds. Deeds never decrease.
- Copy verbatim: standing lines *"Known here — they will pass you a neighbour's work."*, *"Trusted here — the back room is open to you."*, *"Sworn to this people. Their doors are yours."*; the patron's board line *"The patron's table: word of work from all over."*; the inn button *"Inn.  On the house."* (two spaces, the file's own convention); the pay line *"%s — work pays +%d %%."* (title capitalised as written in TITLES, e.g. *"Famous — work pays +30 %."*); the title-change line *"The company is spoken of now: %s."*; the audience button *"Seek an audience with the lord"*; the audience text *"The hall is cleared for you. The lord speaks of what the company has done for %s's people, and of what a lord owes such a company."* (faction capitalised); the Standing section header *"Standing"*.
- Art: `assets/generated/event-audience-{human,elf,dwarf}.png` (the event card's `event-<id>` stem rule).
- Commit after every task, message in the repo's voice (a sentence, no conventional-commit prefixes), trailer `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. New scripts' `.uid` sidecars are tracked — add them.
- Match the comment density and voice of the file you are in; new tests follow `tests/test_world_lairs.gd`'s shape.

---

### Task 1: `core/ladder.gd` and the save

**Files:**
- Create: `core/ladder.gd`, `tests/test_ladder.gd`
- Modify: `core/world_save.gd` (`to_dict` ~line 218 `"opinion": FactionOpinion.all(),`; `from_dict` ~line 298 the `FactionOpinion.reset()` block)
- Test: `tests/test_world_save.gd`

**Interfaces:**
- Produces: everything in the spec §1 signature block. `deed(faction, n := 1) -> int` returns the new rung index when the rung changed, `-1` otherwise. `all()` returns `{"deeds": Dictionary, "audiences": Array}`; `load(d)` accepts that shape (missing keys → empty).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ladder.gd`:

```gdscript
# The ladder (core/ladder.gd): deeds per faction that never drop, four named
# rungs, one party-wide renown title, one audience per faction.
#   godot --headless --path . -s tests/test_ladder.gd
extends SceneTree

const Ladder = preload("res://core/ladder.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	Ladder.reset()
	check(Ladder.deeds("human") == 0 and Ladder.rung("human") == 0 and Ladder.rung_name("human") == "Stranger",
		"a fresh ladder: strangers everywhere")
	check(Ladder.renown() == 0 and Ladder.title_index() == 0 and Ladder.title() == "Nobodies" and Ladder.pay_mult() == 1.0,
		"...and nobodies")
	check(Ladder.deed("human") == -1 and Ladder.deeds("human") == 1, "one deed, still a stranger, no rung change reported")
	check(Ladder.deed("human", 2) == -1 and Ladder.deeds("human") == 3, "three")
	check(Ladder.deed("human") == Ladder.KNOWN and Ladder.rung("human") == Ladder.KNOWN and Ladder.rung_name("human") == "Known",
		"the fourth deed makes them Known, and says so once")
	check(Ladder.deed("human") == -1, "the fifth says nothing")
	check(Ladder.deed("human", 7) == Ladder.TRUSTED and Ladder.deeds("human") == 12, "twelve: Trusted")
	check(Ladder.deed("human", 13) == Ladder.SWORN and Ladder.deeds("human") == 25, "twenty-five: Sworn")
	check(Ladder.deed("human", 100) == -1 and Ladder.rung("human") == Ladder.SWORN, "nothing above Sworn")
	check(Ladder.deed("goblinoid", 5) == -1 and Ladder.deeds("goblinoid") == 0, "a monster faction takes no deeds")
	check(Ladder.deed("human", 0) == -1 and Ladder.deed("human", -3) == -1 and Ladder.deeds("human") == 125,
		"zero and negative deeds change nothing: standing never drops")
	# renown is the sum over civilized factions
	Ladder.reset()
	Ladder.deed("human", 3)
	Ladder.deed("elf", 2)
	Ladder.deed("orc", 50)
	check(Ladder.renown() == 5 and Ladder.title() == "Nobodies", "five deeds across two peoples; the orcs count for nothing")
	Ladder.deed("dwarf", 1)
	check(Ladder.title_index() == 1 and Ladder.title() == "Hirelings" and absf(Ladder.pay_mult() - 1.1) < 0.001, "six: Hirelings, +10 %")
	Ladder.deed("human", 12)
	check(Ladder.title() == "a Company of Note" and absf(Ladder.pay_mult() - 1.2) < 0.001, "eighteen")
	Ladder.deed("human", 22)
	check(Ladder.title() == "Famous", "forty")
	Ladder.deed("elf", 40)
	check(Ladder.title() == "Legends" and absf(Ladder.pay_mult() - 1.4) < 0.001, "eighty: Legends, +40 %")
	# audiences
	check(not Ladder.audience_held("human"), "no audience yet")
	Ladder.hold_audience("human")
	check(Ladder.audience_held("human") and not Ladder.audience_held("elf"), "held once, per faction")
	Ladder.hold_audience("human")
	check(Ladder.all()["audiences"].size() == 1, "holding it twice records it once")
	# the save shape
	var d: Dictionary = Ladder.all()
	check(d["deeds"]["human"] == 37 and d["deeds"]["elf"] == 42 and not d["deeds"].has("orc") and d["audiences"] == ["human"],
		"all() is the two dictionaries the save writes (%s)" % str(d))
	Ladder.reset()
	check(Ladder.renown() == 0 and not Ladder.audience_held("human"), "reset clears both")
	Ladder.load(d)
	check(Ladder.deeds("human") == 37 and Ladder.rung("human") == Ladder.SWORN and Ladder.audience_held("human") and Ladder.title() == "Legends",
		"load() restores them")
	Ladder.load({})
	check(Ladder.renown() == 0 and not Ladder.audience_held("human"), "load({}) is a fresh ladder")
	Ladder.load({"deeds": {"human": "7"}, "audiences": ["elf"]})
	check(Ladder.deeds("human") == 7 and Ladder.audience_held("elf"), "a value that came back as a string is read as an int")
	print("test_ladder: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_ladder.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: SCRIPT ERROR — `res://core/ladder.gd` does not exist.

- [ ] **Step 3: Write the module**

Create `core/ladder.gd`:

```gdscript
# The ladder — standing with a people, and a name across the map.
#
# Opinion (core/faction_opinion.gd) is what a faction feels about the party
# this week: it moves prices and, at the ends, the gate, and it drifts back
# to nothing when the party is away. This is what the party has DONE for a
# people, which does not drift: deeds, counted per civilized faction, never
# lost, read as four named rungs — Stranger, Known, Trusted, Sworn — each of
# which opens something a stranger cannot get (a neighbour's job, a cheaper
# bed, the back room, the patron's table, an audience). Across every people
# runs renown: the sum of all deeds, read as one title, which is how the
# world speaks of the company and what puts a premium on its pay.
#
#   Ladder.deed("human")            # -> the new rung when it changed, else -1
#   Ladder.rung("human")            # 0..3
#   Ladder.title(), Ladder.pay_mult()
#   Ladder.all() / Ladder.load(d)   # the save's "ladder" key
#
# Static and process-global for the same reason opinion is: the readers are
# static functions with no handle on a world, and there is one world at a
# time. ponytail: hang it on World the day two worlds coexist.
extends RefCounted

const RUNGS := ["Stranger", "Known", "Trusted", "Sworn"]
const RUNG_AT := [0, 4, 12, 25]           # deeds: a board and a lair; a session; a campaign
const KNOWN := 1
const TRUSTED := 2
const SWORN := 3

const TITLES := ["Nobodies", "Hirelings", "a Company of Note", "Famous", "Legends"]
const TITLE_AT := [0, 6, 18, 40, 80]      # total deeds: the first town; the whole map, twice
const PAY_PER_TITLE := 0.1                # every job pays this much more per title above Nobodies

static var _deeds: Dictionary = {}        # faction -> int
static var _audiences: Array = []         # factions whose audience has been held

static func reset() -> void:
	_deeds = {}
	_audiences = []

static func deeds(faction: String) -> int:
	return int(_deeds.get(faction, 0))

# A deed done for a people. Monster factions have no ladder (their gate is the
# fight), and nothing here ever takes a deed back — standing is history, not
# mood. Returns the new rung when this deed crossed a threshold, so the caller
# can say so once; -1 otherwise.
static func deed(faction: String, n := 1) -> int:
	if n <= 0 or load("res://core/world_ai.gd").is_monster(faction):   # load: world_ai.gd's chain preloads this file
		return -1
	var before := rung(faction)
	_deeds[faction] = deeds(faction) + n
	var after := rung(faction)
	return after if after != before else -1

static func rung(faction: String) -> int:
	var d := deeds(faction)
	var r := 0
	for i in RUNG_AT.size():
		if d >= int(RUNG_AT[i]):
			r = i
	return r

static func rung_name(faction: String) -> String:
	return String(RUNGS[rung(faction)])

# --- renown: the sum of every deed, as one title -----------------------------

static func renown() -> int:
	var total := 0
	for f in _deeds:
		total += int(_deeds[f])
	return total

static func title_index() -> int:
	var r := renown()
	var t := 0
	for i in TITLE_AT.size():
		if r >= int(TITLE_AT[i]):
			t = i
	return t

static func title() -> String:
	return String(TITLES[title_index()])

static func pay_mult() -> float:
	return 1.0 + PAY_PER_TITLE * float(title_index())

# --- the audience: once per people ------------------------------------------

static func audience_held(faction: String) -> bool:
	return _audiences.has(faction)

static func hold_audience(faction: String) -> void:
	if not _audiences.has(faction):
		_audiences.append(faction)

# --- the save ----------------------------------------------------------------

static func all() -> Dictionary:
	return {"deeds": _deeds.duplicate(), "audiences": _audiences.duplicate()}

# Values come back from JSON as floats or, from an old hand-edited save, as
# strings: read them as ints either way.
static func load(d: Dictionary) -> void:
	reset()
	for f in d.get("deeds", {}):
		_deeds[String(f)] = int(d["deeds"][f])
	for f in d.get("audiences", []):
		hold_audience(String(f))
```

- [ ] **Step 4: Run the test**

Run: `timeout 120 godot --headless --path . -s tests/test_ladder.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `0 failed`. (The `load` name shadows the global `load()` inside the class only for calls without a path — the body's `load("res://core/world_ai.gd")` still resolves to the engine's; if the parser complains, rename the static to `load_state` and update the test and spec — say so in the report.)

- [ ] **Step 5: The save**

`tests/test_world_save.gd`, before the final `print(`:

```gdscript
	# the ladder rides the save beside opinion; an old save is a fresh ladder
	var Ladder = load("res://core/ladder.gd")
	Ladder.reset()
	Ladder.deed("human", 13)
	Ladder.hold_audience("human")
	var wl := World.new()
	var dl: Dictionary = WorldSave.to_dict(wl)
	check(dl["ladder"]["deeds"]["human"] == 13 and dl["ladder"]["audiences"] == ["human"], "written under ladder")
	Ladder.reset()
	WorldSave.from_dict(dl)
	check(Ladder.deeds("human") == 13 and Ladder.audience_held("human"), "read back")
	dl.erase("ladder")
	WorldSave.from_dict(dl)
	check(Ladder.renown() == 0 and not Ladder.audience_held("human"), "an old save loads a fresh ladder")
```

In `core/world_save.gd`: add `const Ladder = preload("res://core/ladder.gd")` beside `FactionOpinion`; in `to_dict` after `"opinion": FactionOpinion.all(),` add `"ladder": Ladder.all(),`; in `from_dict` after the opinion loop add:

```gdscript
	# The ladder (core/ladder.gd) is process-global like opinion; a save from
	# before it had one loads as strangers everywhere.
	Ladder.load(d.get("ladder", {}))
```

Update the format comment block at the top of the file (the `"opinion": {...}` line) with a `"ladder": {"deeds": {"human": 13}, "audiences": ["human"]}` line.

Run: `timeout 120 godot --headless --path . -s tests/test_world_save.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head` → `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/ladder.gd core/ladder.gd.uid tests/test_ladder.gd tests/test_ladder.gd.uid core/world_save.gd tests/test_world_save.gd
git commit -m "The ladder: deeds per people that never drop, four rungs, one title, saved beside opinion"
```

---

### Task 2: The deeds, and the first door

**Files:**
- Modify: `core/quest.gd` (`offer_for` ~117–128; `turn_in` ~336–342), `core/faction_opinion.gd` (`credit_fight` ~122–132), `core/raids.gd` (`tick`'s lift loop; `settle`), `core/landmarks.gd` (the `"offering"` door ~360–364)
- Test: `tests/test_quest.gd`, `tests/test_faction_opinion.gd`, `tests/test_raids.gd`, `tests/test_landmarks.gd`

**Interfaces:**
- Consumes: `Ladder.deed`, `Ladder.rung`, `Ladder.KNOWN`.
- Produces: `Quest.offer_for(party, node_id, opinion := 0.0, rung := 0)` — the generous branch is `opinion >= QUEST_GENEROUS or rung >= Ladder.KNOWN`; callers that have a settlement pass `Ladder.rung(s.faction)` (`quest_posting.gd`'s `_build` for `kill_count`/`collect_item` — read how it calls `offer_for` and add the rung argument there).

- [ ] **Step 1: Write the failing tests**

`tests/test_quest.gd`, before the final `print(` (read the file's fixtures for how it builds a party and which curated giver node ids exist — use the ones its existing `offer_for` checks use):

```gdscript
	# the ladder: Known passes a neighbour's job at neutral opinion; turn-in is a deed
	var Ladder = load("res://core/ladder.gd")
	Ladder.reset()
	var pk := _party()
	var own: Dictionary = Quest.offer_for(pk, "<GIVER_A>", 0.0)
	check(not own.is_empty(), "the giver's own job first")
	Quest.accept(pk, own)
	check(Quest.offer_for(pk, "<GIVER_A>", 0.0).is_empty(), "own job taken, neutral, stranger: nothing more")
	check(not Quest.offer_for(pk, "<GIVER_A>", 0.0, Ladder.KNOWN).is_empty(), "...but Known gets a neighbour's")
	var before: int = Ladder.deeds("human")
	own["progress"] = own["required"]
	Quest.turn_in(pk, own, "human")
	check(Ladder.deeds("human") == before + 1, "a job turned in is a deed for the taker's people")
	Quest.turn_in(pk, own, "human")
	check(Ladder.deeds("human") == before + 1, "...once")
```

Replace `<GIVER_A>` with a real curated giver node id from `Quest.CURATED` that the file already uses.

`tests/test_faction_opinion.gd`, before the final `print(`:

```gdscript
	var Ladder = load("res://core/ladder.gd")
	Ladder.reset()
	var wf := World.new()
	wf.add_settlement(World.Settlement.new("h", Vector2.ZERO, "human", "town"))
	wf.add_settlement(World.Settlement.new("e", Vector2(50, 0), "elf", "town"))
	wf.add_settlement(World.Settlement.new("o", Vector2(50, 50), "orc", "town"))
	FactionOpinion.credit_fight(wf, Vector2.ZERO, 5.0)
	check(Ladder.deeds("human") == 1 and Ladder.deeds("elf") == 1 and Ladder.deeds("orc") == 0,
		"a fight near their towns is a deed for each civilized people credited")
```

`tests/test_raids.gd` — in `test_lift()` after the lift check add `check(Ladder.deeds("human") == lifted_before + 2, "lifting a raid is two deeds")` with `var lifted_before: int = Ladder.deeds("human")` captured before `mark_cleared`; in `test_settle()` capture `var settle_before: int = Ladder.deeds("human")` before the successful `settle` and check `+ 3` after. Preload `Ladder` in the file and call `Ladder.reset()` in `_init` after `FactionOpinion.reset()`.

`tests/test_landmarks.gd` — find the offering test (the one that checks `party.blessed` / `FactionOpinion.raise` of 2.0 / `thanks`) and add a check that `Ladder.deeds(<that faction>)` rose by 1.

- [ ] **Step 2: Run them to see them fail**

Run each: `timeout 120 godot --headless --path . -s tests/<file>.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head` — the new checks FAIL (or SCRIPT ERROR on the `rung` argument).

- [ ] **Step 3: Implement**

`core/quest.gd`: `const Ladder = preload("res://core/ladder.gd")`; `offer_for(party, node_id: String, opinion := 0.0, rung := 0)` with the generous `if` reading `opinion >= FactionOpinion.QUEST_GENEROUS or rung >= Ladder.KNOWN`; in `turn_in`, beside `FactionOpinion.raise(faction, FactionOpinion.QUEST_DONE)` add `Ladder.deed(faction)` (a job is a deed for the people who paid). In `core/quest_posting.gd` `_build`, pass `Ladder.rung(s.faction)` as the fourth argument to `Quest.offer_for` (preload `Ladder` there — it is needed again in Task 4).

`core/faction_opinion.gd` `credit_fight`: after `set_opinion(...)` inside the loop, `load("res://core/ladder.gd").deed(s.faction)` (load, not preload: ladder.gd loads world_ai.gd, which preloads this file).

`core/raids.gd`: `const Ladder = preload("res://core/ladder.gd")`; in `tick`'s lift block beside `FactionOpinion.raise(s.faction, LIFTED_FOR)` add `Ladder.deed(s.faction, 2)`; in `settle` beside `FactionOpinion.raise(home.faction, LIFTED_FOR)` add `Ladder.deed(home.faction, 3)`.

`core/landmarks.gd`: beside `FactionOpinion.raise(near.faction, 2.0)` add `load("res://core/ladder.gd").deed(near.faction)` (check whether landmarks.gd may preload it without a cycle — it preloads world.gd; ladder.gd preloads nothing, so `const Ladder = preload(...)` is fine too).

Comment each credit in the file's voice (one clause: "…and a deed on the ladder").

- [ ] **Step 4: Run the four tests, then `tests/test_quest_posting.gd` and `tests/test_settlement_visit.gd` (callers of `offer_for`)**

Expected: all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/quest.gd core/quest_posting.gd core/faction_opinion.gd core/raids.gd core/landmarks.gd tests/test_quest.gd tests/test_faction_opinion.gd tests/test_raids.gd tests/test_landmarks.gd
git commit -m "The ladder counts its deeds: a job, a fight at the gate, a raid lifted, a lair settled, an offering — and Known gets a neighbour's job"
```

---

### Task 3: The bed and the back room

**Files:**
- Modify: `core/settlement_visit.gd` (`inn_cost` ~64–65; `visit` ~283–293; `stock_by_service` ~394–415; new `back_room`)
- Test: `tests/test_settlement_visit.gd`

**Interfaces:**
- Consumes: `Ladder.rung`, `Ladder.KNOWN/TRUSTED/SWORN`; `Loot.items_of_rarity(rarity)` (`core/loot.gd`, sorted list of ids); `Campaign.item_price(id)`; `RNG.new(seed)`, `roll_die`.
- Produces: `Visit.INN_KNOWN := 0.5`, `Visit.BACK_ROOM_N := 3`, `Visit.BACK_ROOM_RARE := 2`; `Visit.inn_cost(s)` by rung (ceil of half at Known/Trusted, 0 at Sworn); `Visit.back_room(s, m: Dictionary) -> Array` of `{item_id, name, price, service: "backroom"}` (empty below Trusted or when the settlement has neither armorsmith nor weaponsmith); `visit()` appends them to `m["stock"]`; `stock_by_service` returns a `"backroom"` group when any.

- [ ] **Step 1: Write the failing tests**

`tests/test_settlement_visit.gd`, before the final `print(`:

```gdscript
	# the ladder: the bed by rung, and the back room at Trusted
	var Ladder = load("res://core/ladder.gd")
	var Loot = load("res://core/loot.gd")
	Ladder.reset()
	var wb := World.new()
	var city = wb.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	var camp = wb.add_settlement(World.Settlement.new("dun", Vector2(500, 0), "human", "camp"))
	wb.clock.elapsed = 20000.0
	check(Visit.inn_cost(city) == 40, "a stranger pays the city's 40")
	Ladder.deed("human", 4)
	check(Visit.inn_cost(city) == 20 and Visit.inn_cost(camp) == 5, "Known: half (ceil)")
	var m0: Dictionary = Visit.visit(city, wb)
	check(Visit.stock_by_service(city, m0).get("backroom", []).is_empty(), "Known: no back room")
	Ladder.deed("human", 8)
	city.last_visited = -1.0
	var m1: Dictionary = Visit.visit(city, wb)
	var br: Array = Visit.stock_by_service(city, m1).get("backroom", [])
	check(br.size() == Visit.BACK_ROOM_N, "Trusted: three in the back room (%d)" % br.size())
	for e in br:
		check(String(Campaign.item_data(String(e["item_id"])).get("rarity", "")) == "uncommon", "...uncommon (%s)" % e["item_id"])
		check(int(e["price"]) == maxi(1, int(round(Campaign.item_price(String(e["item_id"])) * float(m1["markup"])))), "...at list times the market's markup")
		check(String(e.get("service", "")) == "backroom", "...tagged for the tab")
	var ids0: Array = br.map(func(e): return e["item_id"])
	city.last_visited = -1.0
	var ids1: Array = Visit.stock_by_service(city, Visit.visit(city, wb)).get("backroom", []).map(func(e): return e["item_id"])
	check(ids0 == ids1, "the same shelf on the same day (seeded off the settlement and the steps)")
	camp.last_visited = -1.0
	check(Visit.stock_by_service(camp, Visit.visit(camp, wb)).get("backroom", []).is_empty(), "a camp has no back room: nobody there deals in these")
	Ladder.deed("human", 13)
	city.last_visited = -1.0
	var m2: Dictionary = Visit.visit(city, wb)
	var br2: Array = Visit.stock_by_service(city, m2).get("backroom", [])
	var rares := 0
	for e in br2:
		if String(Campaign.item_data(String(e["item_id"])).get("rarity", "")) == "rare":
			rares += 1
	check(br2.size() == Visit.BACK_ROOM_N + Visit.BACK_ROOM_RARE and rares == Visit.BACK_ROOM_RARE, "Sworn: two rare beside the three")
	check(Visit.inn_cost(city) == 0, "Sworn: on the house")
	# buying one lands it in the stash, identified
	var pb := _party()
	pb.gold = 100000
	var pick := String(br2[0]["item_id"])
	check(Visit.buy(m2, pb, pick), "bought")
	check(pb.stash_count(pick, true) == 1, "...identified in the stash")
	check(Visit.stock_by_service(city, m2).get("backroom", []).size() == br2.size() - 1, "...and off the shelf")
	Ladder.reset()
```

(`Campaign` and `_party()` exist in this file; `stash_count(id, identified_only := true)` — read `core/party.gd` for the exact signature and adjust.)

- [ ] **Step 2: Run it to see it fail**

Expected: `FAIL: Known: half (ceil)` and on.

- [ ] **Step 3: Implement**

In `core/settlement_visit.gd`: `const Ladder = preload("res://core/ladder.gd")`, `const Loot = preload("res://core/loot.gd")` (check `loot.gd` does not preload this file; use `load()` inside `back_room` if it does).

```gdscript
# The ladder (core/ladder.gd): a Known company pays half for its bed, a Sworn
# one nothing — the one thing every rung is for is people, and an innkeeper
# is people.
const INN_KNOWN := 0.5

static func inn_cost(s) -> int:
	var base := int(INN_COST.get(s.kind, INN_COST["town"]))
	var r: int = Ladder.rung(s.faction)
	if r >= Ladder.SWORN:
		return 0
	if r >= Ladder.KNOWN:
		return int(ceil(base * INN_KNOWN))
	return base

# The back room: where the magic items are, for a company the smith trusts.
# Uncommon at Trusted, two rare beside them at Sworn; only where there is a
# smith at all. Seeded off the settlement and the shelf's restock step, the
# way the shelf is, so it is the same shelf on the same day.
const BACK_ROOM_N := 3
const BACK_ROOM_RARE := 2

static func back_room(s, m: Dictionary) -> Array:
	var r: int = Ladder.rung(s.faction)
	if r < Ladder.TRUSTED:
		return []
	var svc: Array = services(s)
	if not ("armorsmith" in svc or "weaponsmith" in svc):
		return []
	var out: Array = []
	var rng = RNG.new(maxi(1, absi(hash("backroom|%s|%d" % [s.id, int(m.get("steps", 0))]))))
	var wants := [["uncommon", BACK_ROOM_N]]
	if r >= Ladder.SWORN:
		wants.append(["rare", BACK_ROOM_RARE])
	for w in wants:
		var pool: Array = Loot.items_of_rarity(String(w[0])).duplicate()
		for i in int(w[1]):
			if pool.is_empty():
				break
			var id: String = pool.pop_at(rng.roll_die(pool.size()) - 1)
			out.append({"item_id": id, "name": Campaign.item_name(id),
				"price": maxi(1, int(round(Campaign.item_price(id) * float(m.get("markup", 1.0))))),
				"service": "backroom"})
	return out
```

In `visit()`, after `var m := market(...)`: `m["stock"].append_array(back_room(s, m))` — as an Array append, not assignment (`stock` is a plain Array). In `stock_by_service`, after the services loop and before `return out`:

```gdscript
	var back: Array = []
	for e in m.get("stock", []):
		if String(e.get("service", "")) == "backroom":
			back.append(e)
	if not back.is_empty():
		out["backroom"] = back
```

(`price_of`/`buy` read `m["stock"]`, so a back-room item is bought like any other; `party.stash_add(id)` defaults to identified — confirm in `core/party.gd`.)

- [ ] **Step 4: Run the test, plus `tests/test_world_visit_pages.gd` (SORCMERC_FAST=1, timeout 180)**

Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/settlement_visit.gd tests/test_settlement_visit.gd
git commit -m "The bed by rung, and the back room: at Trusted the smith sells what the hoards used to keep"
```

---

### Task 4: The patron's reach and renown's premium

**Files:**
- Modify: `core/quest_posting.gd` (`offers` ~131–157; `_world_offers` ~211–225; new `chief_settlement`, `is_patron`)
- Test: `tests/test_quest_posting.gd`

**Interfaces:**
- Consumes: `Ladder.rung`, `Ladder.TRUSTED`, `Ladder.pay_mult`.
- Produces: `Posting.chief_settlement(world, faction)` → the faction's largest settlement (city > town > camp, ties by id ascending) or null; `Posting.is_patron(s, world) -> bool` (Trusted or better with `s.faction` and `s` is its chief settlement); `_world_offers` uses reach `INF` when `is_patron`; every offer's `reward.gold` × `Ladder.pay_mult()` (int) applied in `offers()` after `_build`.

- [ ] **Step 1: Write the failing test**

Add `test_patron_and_renown()` to `_init()` after `test_raid_premium_and_rescue()`:

```gdscript
func test_patron_and_renown() -> void:
	var Ladder = load("res://core/ladder.gd")
	Ladder.reset()
	var w := _world()
	var p := _party()
	var city = w.settlements[0]                       # riverhold, human, city
	var far = w.lairs[1]                              # far-barrow at (4000, 4000): out of any reach
	check(Posting.chief_settlement(w, "human") == city, "the city is the humans' chief settlement")
	check(not Posting.is_patron(city, w), "a stranger has no patron")
	var ids0: Array = _at(city, p, w).map(func(q): return q["id"])
	check(not ids0.any(func(id): return String(id).contains(far.id)), "the far barrow is nobody's problem")
	Ladder.deed("human", 12)
	check(Posting.is_patron(city, w), "Trusted: the patron's table")
	var ids1: Array = _at(city, p, w).map(func(q): return q["id"])
	check(ids1.any(func(id): return String(id).contains(far.id)), "...posts work about the far barrow")
	var town = w.settlements[1]                       # greenmarch, elf — not the humans', and not chief
	var ids2: Array = _at(town, p, w).map(func(q): return q["id"])
	check(not ids2.any(func(id): return String(id).contains(far.id)), "a town of another people does not")
	# a second human settlement that is only a camp is not the chief
	w.add_settlement(World.Settlement.new("h-camp", Vector2(300, 300), "human", "camp"))
	check(Posting.chief_settlement(w, "human") == city and not Posting.is_patron(w.settlements[-1], w), "the camp is not the patron")
	# renown's premium on every job
	Ladder.reset()
	var plain: Array = _at(city, p, w)
	Ladder.deed("elf", 6)                             # Hirelings, +10 %
	var dear: Array = _at(city, p, w)
	check(plain.size() == dear.size() and plain.size() > 0, "same board")
	var ok := true
	for i in plain.size():
		if int(dear[i]["reward"]["gold"]) != int(int(plain[i]["reward"]["gold"]) * 1.1):
			ok = false
	check(ok, "every job pays +10 % at Hirelings")
	Ladder.reset()
```

(`_at`, `_world`, `_party` are the file's fixtures. If the gold comparison trips on rounding, compare `int(gold * Ladder.pay_mult())` exactly as the implementation computes it.)

- [ ] **Step 2: Run it to see it fail** — SCRIPT ERROR on `chief_settlement`.

- [ ] **Step 3: Implement**

In `core/quest_posting.gd` (preload `Ladder` if Task 2 did not):

```gdscript
# The ladder (core/ladder.gd): a people's chief settlement — the largest kind
# it holds, ties by id — is where its patron sits.
const KIND_RANK := {"city": 3, "town": 2, "camp": 1}

static func chief_settlement(world, faction: String):
	var best = null
	for s in world.settlements:
		if s.faction != faction:
			continue
		if best == null or int(KIND_RANK.get(s.kind, 0)) > int(KIND_RANK.get(best.kind, 0)) \
				or (int(KIND_RANK.get(s.kind, 0)) == int(KIND_RANK.get(best.kind, 0)) and s.id < best.id):
			best = s
	return best

# Trusted or better, at the chief settlement: the patron posts work about
# anything on the map. What a stranger lacks is not a kind of job but a town
# willing to post the far country's.
static func is_patron(s, world) -> bool:
	return world != null and Ladder.rung(s.faction) >= Ladder.TRUSTED and chief_settlement(world, s.faction) == s
```

In `_world_offers`: `var reach: float = INF if is_patron(s, world) else float(PLACEMENT[kind]["reach"])`. In `offers()`, in the loop after `q["counter"] = counter`:

```gdscript
				# Renown's premium: a famous company charges more, on every job.
				if q.has("reward") and q["reward"].has("gold"):
					q["reward"]["gold"] = int(int(q["reward"]["gold"]) * Ladder.pay_mult())
```

- [ ] **Step 4: Run `tests/test_quest_posting.gd`, `tests/test_quest.gd`, `tests/test_settlement_visit.gd`** → `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/quest_posting.gd tests/test_quest_posting.gd
git commit -m "The patron's table posts the far country's work, and a famous company charges more for all of it"
```

---

### Task 5: The world screen — the lines, the tab, the audience

**Files:**
- Modify: `scenes/world/world.gd` (`_standing_line` ~3145; `_region_lbl.text` ~2500; the quest log builder ~1096–1130; `_build_hub_page` ~3182 (the inn button text; the audience button); the market page's tabs ~3270–3300 (`Back room`); `_build_board_page` (the patron and pay lines); a `_deed_said` hook for the title-change line — see Step 3)
- Create: `tests/test_world_ladder.gd`

**Interfaces:**
- Consumes: everything `Ladder` and `Posting.is_patron` produce; `EventCard` (`show_event(e)` renders chips for `xp`, `item_name`, `thanks`; art `event-<id>`); `Loot.items_of_rarity("rare")`; `party.stash_add(id)`; `Campaign.new(party)._split_xp(n)`; `Ach.collect("audiences", faction)`.
- Produces: `_audience_action()`, `_ladder_title_seen: int` (the last title index the screen said), `_check_title()` called from `_process` after `_check_raids()`.

- [ ] **Step 1: Write the failing screen test**

Create `tests/test_world_ladder.gd` (the `tests/test_world_raids.gd` harness: `labels()`, `said()`, `_init` with the small map):

```gdscript
# The ladder on the world screen: the standing line, the HUD title, the quest
# log's Standing section, the Back room tab, the audience.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_ladder.gd
extends SceneTree

const Ladder = preload("res://core/ladder.gd")
const Visit = preload("res://core/settlement_visit.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(buttons(c))
	return out

func button_named(node: Node, text: String):
	for b in buttons(node):
		if text in String(b.text):
			return b
	return null

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	Ladder.reset()
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var town = w.settlements[0]          # Riverhold, human city
	w.clock.pause()
	main._open_visit(town)
	await process_frame
	check(said(main, "Strangers here, for now."), "a stranger's town square")
	check(button_named(main, "Inn.  A night is 40") != null, "the city's bed at 40")
	check(button_named(main, "Seek an audience") == null, "no audience for a stranger")
	main._close_visit()
	await process_frame
	Ladder.deed("human", 4)
	main._open_visit(town)
	await process_frame
	check(said(main, "Known here — they will pass you a neighbour's work."), "Known: the line")
	check(button_named(main, "Inn.  A night is 20") != null, "Known: half a bed")
	main._close_visit()
	await process_frame
	Ladder.deed("human", 8)
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(said(main, "Trusted here — the back room is open to you."), "Trusted: the line")
	main._goto_page("market")
	await process_frame
	var tab = button_named(main, "Back room")
	check(tab != null, "the Back room tab is there")
	tab.pressed.emit()
	await process_frame
	check(not Visit.stock_by_service(town, main._visit).get("backroom", []).is_empty() and said(main, "◉"), "...and shows the shelf")
	main._goto_page("board")
	await process_frame
	check(said(main, "The patron's table: word of work from all over."), "the patron's board line")
	check(said(main, "Hirelings — work pays +10 %."), "renown's pay line (12 deeds: Hirelings)")
	main._close_visit()
	await process_frame
	# the HUD and the quest log
	check("Hirelings" in main._region_lbl.text, "the HUD carries the title: %s" % main._region_lbl.text)
	main._toggle_quests()
	await process_frame
	check(said(main, "Standing") and said(main, "Hirelings") and said(main, "Trusted") and said(main, "12"), "the quest log's Standing section")
	main._close_quests()
	await process_frame
	# Sworn: the audience, once
	Ladder.deed("human", 13)
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(said(main, "Sworn to this people. Their doors are yours."), "Sworn: the line")
	check(button_named(main, "Inn.  On the house.") != null, "Sworn: on the house")
	var aud = button_named(main, "Seek an audience with the lord")
	check(aud != null, "the audience button")
	var stash_before: int = main.party.stash.size() if "stash" in main.party else -1
	var xp_before: int = main.party.party_characters()[0].xp
	aud.pressed.emit()
	for i in 3:
		await process_frame
	check(main._event_card != null and said(main, "The hall is cleared for you."), "the audience card")
	check(main.party.party_characters()[0].xp > xp_before, "the XP")
	check(Ladder.audience_held("human"), "held")
	main._on_event_ack()
	await process_frame
	check(button_named(main, "Seek an audience with the lord") == null or main._visit.is_empty(), "once: no second audience")
	main._close_visit()
	await process_frame
	# the title-change line
	Ladder.deed("elf", 6)                  # 31 -> still a Company of Note? 25+6 = 31: yes; push to Famous
	Ladder.deed("elf", 9)                  # 40: Famous
	for i in 3:
		await process_frame
	check("The company is spoken of now: Famous." in main._lair_msg.text, "the title change is said: %s" % main._lair_msg.text)
	print("test_world_ladder: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

Read `scenes/world/world.gd` for the quest-log toggle/close names (`_toggle_quests`/`_close_quests` — adjust to the real ones), the party's stash API, and whether `_visit` closes on the event card; adjust the test's expectations to the real names, not the code to the test.

- [ ] **Step 2: Run it to see it fail** — `SORCMERC_FAST=1 timeout 180 godot --headless --path . -s tests/test_world_ladder.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head -20`.

- [ ] **Step 3: Implement, in `scenes/world/world.gd`**

Preload: `const Ladder = preload("res://core/ladder.gd")`, `const Posting = preload("res://core/quest_posting.gd")` if not already, `const Loot = preload("res://core/loot.gd")` if not already.

`_standing_line(s)`: after the two hostile-gate returns and before the opinion lines, insert the ladder's:

```gdscript
	# The ladder (core/ladder.gd): what the party has DONE here outranks how
	# they feel this week — unless the guards are already out.
	var tail := ""   # Famous or better rides on the end of every line
	if Ladder.title_index() >= 3:
		tail = "  %s, they say." % Ladder.title().capitalize()
	match Ladder.rung(s.faction):
		Ladder.SWORN: return "Sworn to this people. Their doors are yours." + tail
		Ladder.TRUSTED: return "Trusted here — the back room is open to you." + tail
		Ladder.KNOWN: return "Known here — they will pass you a neighbour's work." + tail
```

(and append `tail` to the existing returns below it too — read them and add `+ tail` to each).

HUD: where `_region_lbl.text = "%s, levels %d to %d" % [...]` is set, append ` · %s` with `Ladder.title()` when `Ladder.title_index() > 0`.

Quest log: after the quests' rows and before the Close button, a `_section(rows, "Standing")`-style header (use the file's own `_section` helper if it fits a VBox, else a `Label` with `theme_type_variation = "Head"`), then a Label *"%s — %d deeds%s"* with the title, `Ladder.renown()`, and `", %s at %d" % [next title, TITLE_AT[next]]` when there is a next; then one Label per civilized faction with a settlement on the map (`not WorldAI.is_monster(s.faction)`, each faction once): *"%s: %s, %d deeds%s"* with the faction capitalised, `rung_name`, `deeds`, and `", %s at %d"` for the next rung when any.

Hub page: the inn button text — when `Visit.inn_cost(s) == 0` and `wait <= 0.0`: `"Inn.  On the house."`. After the inn button: if `Posting.is_patron(s, world) and Ladder.rung(s.faction) >= Ladder.SWORN and not Ladder.audience_held(s.faction)` add a Button *"Seek an audience with the lord"* → `_audience_action`.

```gdscript
# The audience: once per people, at its chief settlement, for a Sworn company.
# A rare item and a milestone's worth of XP, on the event card, art
# event-audience-<faction>.
const AUDIENCE_XP := 200

func _audience_action() -> void:
	var s = _visit.get("settlement")
	if s == null or Ladder.audience_held(s.faction):
		return
	var pool: Array = Loot.items_of_rarity("rare")
	var gift := String(pool[absi(hash("audience|%s" % s.faction)) % pool.size()]) if not pool.is_empty() else ""
	if gift != "":
		party.stash_add(gift)
		Campaign._note_rarity(gift)
	Campaign.new(party)._split_xp(AUDIENCE_XP)
	Ladder.hold_audience(s.faction)
	Ach.collect("audiences", s.faction)
	var e := {"id": "audience-%s" % s.faction, "title": "An audience with the lord", "kind": "good", "ok": true,
		"text": "The hall is cleared for you. The lord speaks of what the company has done for %s's people, and of what a lord owes such a company." % String(s.faction).capitalize(),
		"xp": AUDIENCE_XP, "thanks": s.sname}
	if gift != "":
		e["item"] = gift
		e["item_name"] = Campaign.item_name(gift)
	_close_visit()
	_autosave()
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event(e)
```

(Check `_close_visit` leaves the clock paused until `_on_event_ack` resumes it — mirror what `_on_place_chosen` does around its card; if `_close_visit` resumes the clock, pause it again before showing the card.)

Market page: in the tabs loop the services come from `_visit["services"]`; after that loop, if `Visit.stock_by_service(s, _visit).has("backroom")` add a `Button` *"Back room"* wired to `_goto_market_tab.bind("backroom")`, disabled when `_market_tab == "backroom"`. In the rows loop, `for service in _visit["services"]` does not include `backroom` — iterate over `groups.keys()` order instead: services first, then `"backroom"` if present; its portrait is the armorsmith's (`_portrait(box, s.faction, "armorsmith")` when `_market_tab == "backroom"`), its section title *"The back room"*, tiles as any shelf (they buy through `_buy`).

Board page: after the mood Label, if `Posting.is_patron(s, world)` a Dim Label *"The patron's table: word of work from all over."*; if `Ladder.title_index() > 0` a Dim Label *"%s — work pays +%d %%." % [Ladder.title().capitalize(), int(round(Ladder.PAY_PER_TITLE * 100 * Ladder.title_index()))]*.

The title line: `var _ladder_title_seen := 0` set from `Ladder.title_index()` when the world is loaded (where `_settlements3d.reset(world)` is first called on a new/loaded world — find the load path); `_check_title()` in `_process` after `_check_raids()`:

```gdscript
# Renown's title, said once when it changes — deeds are credited in five
# places, none of which is this screen, so the screen watches the sum.
func _check_title() -> void:
	var t := Ladder.title_index()
	if t == _ladder_title_seen:
		return
	if t > _ladder_title_seen:
		_lair_msg.text = "The company is spoken of now: %s." % Ladder.title()
	_ladder_title_seen = t
```

Also bump the four achievements' counters here and in the deed sites? Simpler: in `_check_title`, `Ach.record("renown_title", t)`; and for rungs, in `_check_lairs`… no — keep achievements in Task 6 reading `Ladder` through a tiny poll: `_check_title` also does `Ach.record("best_rung", <max rung over factions>)`. Both are high-water marks (`Ach.record`).

- [ ] **Step 4: Run the screen test and the neighbours** (`test_world_visit_pages`, `test_world_landmarks`, `test_world_raids`, `test_world_panels`, `test_world_objectives`; all `SORCMERC_FAST=1 timeout 180`) → `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scenes/world/world.gd tests/test_world_ladder.gd tests/test_world_ladder.gd.uid
git commit -m "The ladder on the screen: the standing line, the title on the HUD and in the log, the Back room tab, the patron's line, and an audience with the lord"
```

---

### Task 6: Achievements, the robot, the pictures, the record

**Files:**
- Modify: `core/achievements.gd` (`DEFS`, after `waystations_3`), `tests/test_achievements.gd`, `tests/drive_random.gd`, `docs/expansion-plan.md`
- Create: `assets/generated/event-audience-{human,elf,dwarf}.png` (+ `.import`)
- Also: `scenes/model_cache.gd.uid` and `tests/test_model_cache.gd.uid` — master's model-cache commit forgot its sidecars; `--import` generates them; add them.

- [ ] **Step 1: Achievements**

Entries (group `road`): `{"id": "known_first", "title": "Known Faces", "desc": "Be Known to a people.", "counter": "best_rung", "goal": 1}`, `{"id": "sworn_first", "title": "Sworn", "desc": "Be Sworn to a people.", "counter": "best_rung", "goal": 3}`, `{"id": "renown_famous", "title": "Famous", "desc": "Be spoken of across the map.", "counter": "renown_title", "goal": 3}`, `{"id": "audience_first", "title": "An Audience", "desc": "Be received by a lord.", "counter": "audiences", "goal": 1}`. Test: the four are defined, `sworn_first` goal 3 on `best_rung`. (`Ach.record` is the high-water setter Task 5 calls; `Ach.collect("audiences", faction)` counts the set.)

- [ ] **Step 2: The robot**

In `tests/drive_random.gd`, where it walks a visit's hub buttons (read how it presses the inn / the board — there is a per-visit beat), add: if a button whose text contains "Seek an audience" is visible, press it with `_chance(80)` and `_saw["audience"] = true`. Frame invariant: keep `var _deeds_seen := 0`; each frame `var r := Ladder.renown(); if r < _deeds_seen: fail("renown went down: %d -> %d" % [_deeds_seen, r]); _deeds_seen = r`. Run: `SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/drive_random.gd 2>&1 | tail -5` → no FAIL.

- [ ] **Step 3: The pictures**

Add an `"audience"` group to `~/localgen/gen_sorcmerc_scenes.py`'s `ART` (SCENE style, the way `room`/`camp` declare it), ids `human`, `elf`, `dwarf`, output stem `event-audience-<id>` — check `out_path()` composes `<group>-<id>`; if so name the group `event-audience` or add an `out` override per entry (the dict supports `out`, per the docstring). Prompts, one sentence each in the register of the file's existing entries: a human lord in a timbered great hall on a dais receiving a small band of adventurers, banners, firelight; an elven lord's court under a living canopy of silver-leaved trees, lantern light, the adventurers received; a dwarven lord's stone hall cut into the mountain, pillars and forge-light, the adventurers received. ComfyUI is up at http://127.0.0.1:8188 (check with `curl -s -m 3 http://127.0.0.1:8188/system_stats`). Run with `SORCMERC_GEN=/home/egeo/sorcmerc/assets/generated cd ~/localgen && ComfyUI/.venv/bin/python gen_sorcmerc_scenes.py <group>` (the `SORCMERC_GEN` override exists in the script). Look at each PNG with the Read tool; one retry with a new seed if one is wrong. Then `timeout 300 godot --headless --path . --import > /dev/null 2>&1` for the `.import` sidecars; `git status` must show the three PNGs, three `.import`s, and the two model-cache `.uid` files — nothing else.

- [ ] **Step 4: The record**

Append to `docs/expansion-plan.md` after the threat-clocks record: `## The ladder and renown — standing with a people, and a name across the map (2026-09-21)`, spec/plan paths, three or four paragraphs in the file's voice (what the two tracks are, the deeds table in prose, each rung's door, renown's premium, where it shows), and `### Still open`: no pictures of the screens yet; the audience gift is seeded per faction (the same item every run — a list of the lord's gifts per people would be the next step); standing has no downward path by design.

- [ ] **Step 5: Run `tests/test_achievements.gd`, `tests/test_world_ladder.gd`, then the full suite `SORCMERC_FAST=1 tools/run_tests.sh --unit 2>&1 | tail -3`** → green.

- [ ] **Step 6: Commit**

```bash
git add core/achievements.gd tests/test_achievements.gd tests/drive_random.gd docs/expansion-plan.md assets/generated/event-audience-*.png assets/generated/event-audience-*.png.import scenes/model_cache.gd.uid tests/test_model_cache.gd.uid
git commit -m "The ladder's deeds on the achievement list, the robot seeks its audience, three halls painted, and the record"
```

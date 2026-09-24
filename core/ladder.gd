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

# Said by the world, not claimed (the design audit, docs/audit-game-design.md
# §6): a title is what people do about you, never "Famous" or "Legends".
# Only the index is saved (deeds are), so the words can change freely.
const TITLES := ["Nobodies", "Hirelings", "a Company of Note", "Asked For by Name", "Sung Wrong in Taverns"]
const TITLE_AT := [0, 6, 18, 40, 80]      # total deeds: the first town; the whole map, twice
const PAY_PER_TITLE := 0.1                # every job pays this much more per title above Nobodies

# The plural, for "Known among the elves now."
const PEOPLE := {"human": "humans", "elf": "elves", "dwarf": "dwarves"}

static func people(faction: String) -> String:
	return String(PEOPLE.get(faction, faction + "s"))

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
	if n <= 0 or load("res://core/world_ai.gd").is_monster(faction):   # load(), not preload: this file stays preload-free so every core module can preload it
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

# For the start of a line: "A Company of Note", not .capitalize()'s "A Company Of Note".
static func title_cap() -> String:
	var t := title()
	return t[0].to_upper() + t.substr(1)

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

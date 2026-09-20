# O13 — open-world autosave. One rolling slot, same shape as core/campaign_save.gd
# (that file is the linear run's slot; this one is normal play's).
#
#   WorldSave.save(world, party)            # on every overlay teardown, and on exit
#   var s = WorldSave.load_latest()         # {"world": World, "party": Party}, or null
#
# Loading also re-applies the saved faction opinion (it is process-global state in
# core/faction_opinion.gd, so there is nowhere else to put it).
#
# user://autosave/world.json (or $SORCMERC_SAVE_DIR/world.json):
#
# {
#   "format": "sorcmerc-world",       // literal, checked on load
#   "version": 1,
#   "elapsed": 742.5,                 // World.clock.elapsed, world-minutes
#   "opinion": {"soldier": -12.0},    // FactionOpinion.all()
#   "origin": {"kind": "procedural", "seed": 42},   // which builder made this map
#   "settlements": [
#     {"id": "riverhold", "sname": "Riverhold", "position": [0, 0], "faction": "soldier",
#      "kind": "city", "last_visited": 120.0, "battle_at": -1.0, "pending_opinion_delta": 0.0}
#   ],
#   "parties": [
#     {"id": "player", "position": [80, 120], "faction": "soldier", "is_player": true,
#      "goal": [80, 120], "speed": 40.0,
#      "ai": { <core/world_ai.gd's state dict, Vector2s and RNGs encoded, see _enc> }}
#   ],
#   "waters": [{"position": [-190, -70], "radius": 100.0}],  // O15 terrain blobs
#   "explored": [[80, 120], [125, 118]],  // T9x fog of war: World.explored waypoints
#   "party": {                        // the player's own party: the roster is also in
#     "roster": [ <character_save.gd dicts> ],   // the barracks, but gold/stash/quests
#     "active": ["vera"], "gold": 120,           // and marching order live nowhere else
#     "stash": [...], "quests": [...], "last_long_rest_at": 742.5,  // T9x rest cooldown
#     "overworld_figure": "wizard"  // T9x: chosen map token, "" = the flat pawn
#   },
#   "story": {                        // M7: the content pack's story, mid-telling.
#     "pack": "ashen-road",           //   {} on every run with no story on it.
#     "chapter": "smoke", "done": false,
#     "flags": {"hired": true}, "fired": ["meet-maera"], "journal": ["..."]
#   }
# }
#
# Unknown extra keys are ignored and missing keys fall back to defaults, same contract
# as character_save.gd/campaign_save.gd.
extends RefCounted

const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")
const Party = preload("res://core/party.gd")
const CharacterSave = preload("res://core/character_save.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

const SaveDir = preload("res://core/save_dir.gd")
const FORMAT := "sorcmerc-world"
const VERSION := 1

# O17: same env override as campaign_save.gd — user:// is shared by every godot
# process on the machine, so concurrent runs need their own directory.
static var _dir := ""

static func dir() -> String:
	if _dir == "":   # $SORCMERC_SAVE_DIR itself, or <root>/autosave — see core/save_dir.gd
		_dir = SaveDir.root() if OS.get_environment("SORCMERC_SAVE_DIR") != "" else SaveDir.path("autosave")
	return _dir

static func path() -> String:
	return dir() + "/world.json"

# M7: `story` is a core/mod/story_runtime.gd, or null for a run with no story
# on it (every built-in map). A save that carries one also carries the pack id
# it came from, so a resumed run knows which content pack to ask the registry
# for — without it a half-told story would resume as a map with orphan quests
# in the log.
static func to_dict(world, party = null, story = null) -> Dictionary:
	var settlements: Array = []
	for s in world.settlements:
		settlements.append({
			"id": s.id, "sname": s.sname, "position": _v(s.position),
			"faction": s.faction, "kind": s.kind,
			"last_visited": s.last_visited, "battle_at": s.battle_at, "stolen_at": s.stolen_at,
			"pending_opinion_delta": s.pending_opinion_delta,
		})
	var parties: Array = []
	for p in world.parties:
		parties.append({
			"id": p.id, "position": _v(p.position), "faction": p.faction,
			"is_player": p.is_player, "goal": _v(p.goal), "speed": p.speed,
			"route": p.route.map(_v),   # #95: the legs still to walk
			"ai": _enc(p.ai), "troops": p.troops,
		})
	# T91: lairs weren't a thing when this format was designed -- an old save
	# without a "lairs" key just loads with none (from_dict below), not a
	# missing-key crash.
	var lairs: Array = []
	for l in world.lairs:
		lairs.append({
			"id": l.id, "sname": l.sname, "position": _v(l.position),
			"faction": l.faction, "discovered": l.discovered, "looted": l.looted,
			"cleared_at": l.cleared_at,
			"depth_cleared": l.depth_cleared,
			"entered_at": l.entered_at, "resolved_as": l.resolved_as,
		})
	# Landmarks postdate this format like lairs and water did: an old save
	# without the key loads with none (from_dict below).
	var landmarks: Array = []
	for l in world.landmarks:
		landmarks.append({"id": l.id, "kind": l.kind, "sname": l.sname, "position": _v(l.position),
			"found": l.found, "spent": l.spent})
	# T-water: same story as lairs -- terrain postdates this format, so an old
	# save with no "waters" key loads as a world with none rather than crashing.
	# It has to be saved at all: a lake nobody remembers is a lake the player
	# walks through after a resume.
	var waters: Array = []
	for wtr in world.waters:
		waters.append({"position": _v(wtr["position"]), "radius": float(wtr["radius"])})
	var explored: Array = []
	for e in world.explored:
		explored.append(_v(e))
	return {
		"format": FORMAT, "version": VERSION,
		"elapsed": world.clock.elapsed,
		"opinion": FactionOpinion.all(),
		"origin": {"kind": String(world.origin.get("kind", "small")),
			"seed": int(world.origin.get("seed", 0))},
		"settlements": settlements,
		"parties": parties,
		"lairs": lairs,
		"landmarks": landmarks,
		"waters": waters,
		"explored": explored,
		"party": _party_dict(party),
		"story": story.to_dict() if story != null else {},
	}

# null when the dictionary is not a world save. Applies the saved opinion as a
# side effect — it is global, and a half-loaded world with the previous run's
# opinion still standing is worse than the side effect.
static func from_dict(d: Dictionary):
	if not d is Dictionary or d.get("format") != FORMAT:
		return null
	var world := World.new()
	world.clock.elapsed = float(d.get("elapsed", 0.0))
	for sd in d.get("settlements", []):
		var s := World.Settlement.new(String(sd["id"]), _vec(sd.get("position")),
			String(sd.get("faction", "soldier")), String(sd.get("kind", "town")),
			String(sd.get("sname", "")))
		s.last_visited = float(sd.get("last_visited", -1.0))
		s.battle_at = float(sd.get("battle_at", -1.0))
		s.stolen_at = float(sd.get("stolen_at", -1.0))
		s.pending_opinion_delta = float(sd.get("pending_opinion_delta", 0.0))
		world.add_settlement(s)
	for pd in d.get("parties", []):
		var p := World.RoamingParty.new(String(pd["id"]), _vec(pd.get("position")),
			String(pd.get("faction", "soldier")), bool(pd.get("is_player", false)))
		p.goal = _vec(pd.get("goal", pd.get("position")))
		for wp in pd.get("route", []):
			p.route.append(_vec(wp))
		p.speed = float(pd.get("speed", World.SPEED))
		p.ai = _dec(pd.get("ai", {}))
		var troops: Array[Dictionary] = []
		for t in pd.get("troops", []):
			troops.append(t)
		p.troops = troops
		world.add_party(p)
	for ld in d.get("lairs", []):
		var l := World.Lair.new(String(ld["id"]), _vec(ld.get("position")),
			String(ld.get("faction", "goblinoid")), String(ld.get("sname", "")))
		l.discovered = bool(ld.get("discovered", false))
		l.looted = bool(ld.get("looted", false))
		l.depth_cleared = int(ld.get("depth_cleared", 0))   # D1; an old save just starts at the mouth
		l.entered_at = float(ld.get("entered_at", -1.0))    # ...and has never been disturbed
		l.resolved_as = String(ld.get("resolved_as", ""))
		# An old save spent its lairs before the respawn rule existed; -1 leaves
		# them spent for good rather than repopulating them all on load.
		l.cleared_at = float(ld.get("cleared_at", -1.0))
		world.add_lair(l)
	for md in d.get("landmarks", []):
		var m := World.Landmark.new(String(md["id"]), String(md.get("kind", "ruins")),
			_vec(md.get("position")), String(md.get("sname", "")))
		m.found = bool(md.get("found", false))
		m.spent = bool(md.get("spent", false))
		world.add_landmark(m)
	for wd in d.get("waters", []):
		world.add_water(_vec(wd.get("position")), float(wd.get("radius", 0.0)))
	# T9x: an old save without "explored" just loads with none — everything
	# fogged again, same missing-key-falls-back-to-default contract as lairs.
	for e in d.get("explored", []):
		world.explored.append(_vec(e))
	# A save from before provenance existed is a small hand-placed map: that is
	# the only kind that could have been saved back then.
	var origin: Dictionary = d.get("origin", {})
	world.origin = {"kind": String(origin.get("kind", "small")),
		"seed": int(origin.get("seed", 0))}

	FactionOpinion.reset()
	var opinion: Dictionary = d.get("opinion", {})
	for faction in opinion:
		FactionOpinion.set_opinion(String(faction), float(opinion[faction]))
	# M7: the story's progress rides home as a plain dictionary — rebuilding a
	# runtime from it needs the pack, which is scenes/game/game.gd's job, not
	# this file's. An old save (or one with no story) simply has {}.
	var story = d.get("story", {})
	return {"world": world, "party": _party_from(d.get("party", {})),
		"story": story if story is Dictionary else {}}

# --- the player's party ------------------------------------------------------
# Same six fields campaign_save.gd stores; the roster round-trips through the same
# character_save.gd dicts the barracks uses.

static func _party_dict(party) -> Dictionary:
	if party == null:
		return {}
	var roster: Array = []
	for ch in party.roster:
		roster.append(CharacterSave.to_dict(ch))
	return {
		"roster": roster, "active": Array(party.active), "gold": party.gold,
		"stash": party.stash.duplicate(true), "quests": party.quests.duplicate(true),
		"last_long_rest_at": party.last_long_rest_at,
		"short_rests_since_long": party.short_rests_since_long,
		"overworld_figure": party.overworld_figure,
		"travel_orders": party.travel_orders.duplicate(true),   # D3 standing orders
		"road": {"scouted_next": party.scouted_next, "swift_until": party.swift_until,
			"safe_camp": party.safe_camp, "alarm_set": party.alarm_set, "blessed": party.blessed},   # potions / road spells
	}

static func _party_from(pd: Dictionary):
	var party := Party.new()
	for cd in pd.get("roster", []):
		var ch = CharacterSave.from_dict(cd)
		if ch != null:
			party.roster.append(ch)
	party.active.assign(pd.get("active", []))
	party.gold = int(pd.get("gold", 0))
	for e in pd.get("stash", []):
		party.stash_add(String(e["item_id"]), int(e.get("quantity", 1)),
			bool(e.get("identified", true)))
	party.quests = _ints(pd.get("quests", []))
	party.last_long_rest_at = float(pd.get("last_long_rest_at", -1e12))
	party.short_rests_since_long = int(pd.get("short_rests_since_long", 0))
	party.overworld_figure = String(pd.get("overworld_figure", ""))
	party.travel_orders = pd.get("travel_orders", {}).duplicate(true)   # D3; an old save marches at the default
	var road: Dictionary = pd.get("road", {})
	party.scouted_next = bool(road.get("scouted_next", false))
	party.swift_until = float(road.get("swift_until", 0.0))
	party.safe_camp = bool(road.get("safe_camp", false))
	party.alarm_set = bool(road.get("alarm_set", false))
	party.blessed = bool(road.get("blessed", false))
	return party

# JSON gives every number back as a float; quest counters are compared as ints.
static func _ints(quests: Array) -> Array:
	var out: Array = []
	for q in quests:
		var c: Dictionary = q.duplicate(true)
		for k in ["required", "progress"]:
			if c.has(k):
				c[k] = int(c[k])
		if c.get("reward") is Dictionary and c["reward"].has("gold"):
			c["reward"]["gold"] = int(c["reward"]["gold"])
		out.append(c)
	return out

# --- the `ai` dict -----------------------------------------------------------
# world_ai.gd's behavior state is free-form (patrol waypoints, a wander home and
# its own RNG, nothing at all for hunt), so it is walked generically rather than
# branched on `behavior`: a new behavior serializes without touching this file.
# JSON has no Vector2 and no objects, hence the two tagged forms.

static func _v(v: Vector2) -> Array:
	return [v.x, v.y]

static func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO

static func _enc(v):
	if v is Vector2:
		return {"__v2": _v(v)}
	if v is RNG:
		# State as well as the seed: the next wander roll has to be the one the
		# unsaved world would have made, not the first roll of the sequence again.
		return {"__rng": [v.seed_value, v._state]}
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_enc(e))
		return out
	if v is Dictionary:
		var out_d: Dictionary = {}
		for k in v:
			out_d[k] = _enc(v[k])
		return out_d
	return v

static func _dec(v):
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_dec(e))
		return out
	if v is Dictionary:
		if v.has("__v2"):
			return _vec(v["__v2"])
		if v.has("__rng"):
			var r := RNG.new(int(v["__rng"][0]))
			r._state = int(v["__rng"][1])
			return r
		var out_d: Dictionary = {}
		for k in v:
			out_d[k] = _dec(v[k])
		return out_d
	return v

# --- the slot ----------------------------------------------------------------

static func save(world, party = null, story = null) -> void:
	if world == null:
		return
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path())
		return
	f.store_string(JSON.stringify(to_dict(world, party, story), "  "))
	f.close()

# Never crashes on a missing or corrupt file — a bad autosave is just "no autosave".
static func load_latest():
	if not FileAccess.file_exists(path()):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return from_dict(d) if d is Dictionary else null

static func has_save() -> bool:
	return FileAccess.file_exists(path())

# What is in the slot, in words, without rebuilding a World to find out.
#
# There is exactly ONE slot and it rolls (see the header), which is a fine model
# right up until the title screen says nothing but "Resume the open world" — at
# which point the player cannot tell what they would be resuming, cannot tell
# that starting a new run is going to write over it, and has no way to clear it.
# scenes/game/game.gd's title reads this to say all three.
#
# {} when there is no slot or the file is unreadable — same "a bad autosave is
# just no autosave" contract as load_latest().
static func summary() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if not (d is Dictionary) or d.get("format") != FORMAT:
		return {}
	var pd: Dictionary = d.get("party", {})
	var names: Array = []
	for ch in pd.get("roster", []):
		if ch is Dictionary and String(ch.get("id", "")) in pd.get("active", []):
			names.append(String(ch.get("name", ch.get("id", "?"))))
	return {
		"elapsed": float(d.get("elapsed", 0.0)),
		"map": String(d.get("origin", {}).get("kind", "")),
		"party": names,
		"gold": int(pd.get("gold", 0)),
		"story": String(d.get("story", {}).get("pack", "")),
		"written_at": FileAccess.get_modified_time(path()),
	}

# "Day 3  14:05" off world-minutes — the same reading scenes/world/world.gd's
# clock label shows, so the title and the map agree about when you left.
static func day_clock(elapsed: float, sep := "  ") -> String:
	var m := elapsed + World.WorldClock.START_HOUR * 60.0   # #85: the face starts at 08:00
	return "Day %d%s%02d:%02d" % [int(m / 1440.0) + 1, sep, int(m / 60.0) % 24, int(m) % 60]

static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())

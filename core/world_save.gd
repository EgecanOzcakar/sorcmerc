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
#   "settlements": [
#     {"id": "riverhold", "sname": "Riverhold", "position": [0, 0], "faction": "soldier",
#      "kind": "city", "last_visited": 120.0, "battle_at": -1.0, "pending_opinion_delta": 0.0}
#   ],
#   "parties": [
#     {"id": "player", "position": [80, 120], "faction": "soldier", "is_player": true,
#      "goal": [80, 120], "speed": 40.0,
#      "ai": { <core/world_ai.gd's state dict, Vector2s and RNGs encoded, see _enc> }}
#   ],
#   "party": {                        // the player's own party: the roster is also in
#     "roster": [ <character_save.gd dicts> ],   // the barracks, but gold/stash/quests
#     "active": ["vera"], "gold": 120,           // and marching order live nowhere else
#     "stash": [...], "quests": [...]
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

const DEFAULT_DIR := "user://autosave"
const FORMAT := "sorcmerc-world"
const VERSION := 1

# O17: same env override as campaign_save.gd — user:// is shared by every godot
# process on the machine, so concurrent runs need their own directory.
static var _dir := ""

static func dir() -> String:
	if _dir == "":
		var env := OS.get_environment("SORCMERC_SAVE_DIR")
		_dir = env if env != "" else DEFAULT_DIR
	return _dir

static func path() -> String:
	return dir() + "/world.json"

static func to_dict(world, party = null) -> Dictionary:
	var settlements: Array = []
	for s in world.settlements:
		settlements.append({
			"id": s.id, "sname": s.sname, "position": _v(s.position),
			"faction": s.faction, "kind": s.kind,
			"last_visited": s.last_visited, "battle_at": s.battle_at,
			"pending_opinion_delta": s.pending_opinion_delta,
		})
	var parties: Array = []
	for p in world.parties:
		parties.append({
			"id": p.id, "position": _v(p.position), "faction": p.faction,
			"is_player": p.is_player, "goal": _v(p.goal), "speed": p.speed,
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
		})
	return {
		"format": FORMAT, "version": VERSION,
		"elapsed": world.clock.elapsed,
		"opinion": FactionOpinion.all(),
		"settlements": settlements,
		"parties": parties,
		"lairs": lairs,
		"party": _party_dict(party),
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
		s.pending_opinion_delta = float(sd.get("pending_opinion_delta", 0.0))
		world.add_settlement(s)
	for pd in d.get("parties", []):
		var p := World.RoamingParty.new(String(pd["id"]), _vec(pd.get("position")),
			String(pd.get("faction", "soldier")), bool(pd.get("is_player", false)))
		p.goal = _vec(pd.get("goal", pd.get("position")))
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
		world.add_lair(l)

	FactionOpinion.reset()
	var opinion: Dictionary = d.get("opinion", {})
	for faction in opinion:
		FactionOpinion.set_opinion(String(faction), float(opinion[faction]))
	return {"world": world, "party": _party_from(d.get("party", {}))}

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

static func save(world, party = null) -> void:
	if world == null:
		return
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path())
		return
	f.store_string(JSON.stringify(to_dict(world, party), "  "))
	f.close()

# Never crashes on a missing or corrupt file — a bad autosave is just "no autosave".
static func load_latest():
	if not FileAccess.file_exists(path()):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return from_dict(d) if d is Dictionary else null

static func has_save() -> bool:
	return FileAccess.file_exists(path())

static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())

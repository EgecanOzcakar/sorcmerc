# M3 — a map, written down. The same World a hand-placed builder produces
# (scenes/world/world.gd's _small_world, large_world.gd, procedural_world.gd),
# built from a pack's world.json instead of from GDScript.
#
#   var report := WorldPack.validate(JSON.parse_string(txt))   # {errors, warnings}
#   var w := WorldPack.build(dict, "ashen-road")               # null if it does not validate
#
# Everything the three built-in builders can place, a pack can place:
# settlements, hidden lairs, roaming bands with an AI behavior and a troop
# roster, water blobs, and where the player starts. Nothing is a new concept —
# that is the point. The regions (core/regions.gd) then band a pack map exactly
# like a built-in one, because banding is measured off the map's own extent and
# anchored on its human settlement; an author gets a level-banded map by
# placing settlements, not by declaring one.
#
# world.json:
#
# {
#   "format": "sorcmerc-world",
#   "version": 1,
#   "name": "The Ashen Vale",           // shown in the browser
#   "settlements": [
#     {"id": "riverhold", "name": "Riverhold", "position": [0, 0],
#      "faction": "human", "kind": "city"}          // kind: city | town | camp
#   ],
#   "lairs": [
#     {"id": "goblin-warren", "name": "The Warren", "position": [330, 130],
#      "faction": "goblinoid", "discovered": false}
#   ],
#   "landmarks": [
#     {"id": "chapel", "kind": "shrine", "position": [200, 40], "name": "the Broken Chapel"}
#   ],                                              // kind: ruins | shrine | stones | hut | wreck | tower
#   "parties": [
#     {"id": "bandits", "position": [-320, -180], "faction": "bandit",
#      "troops": [{"role": "heavy", "level": 3}],   // flavour: the map figure + headcount
#      "ai": {"behavior": "hunt"}}                  // hunt | patrol | wander | idle
#   ],
#   "waters": [
#     {"position": [-190, -70], "radius": 100},
#     {"river": [[-110, -20], [-40, 100], [60, 320]], "radius": 40}   // a chain of blobs
#   ],
#   "start": {"at": "riverhold", "offset": [80, 120]}   // or "position": [x, y]
# }
#
# A river is the one piece of sugar here, and it earns it: World.waters only
# knows circles, so every hand-placed river in this project is a for-loop
# stamping blobs along a polyline. Making an author write that loop in JSON
# would mean making them write it wrong.
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Scaler = preload("res://core/scaler.gd")

const FORMAT := "sorcmerc-world"
const KINDS := ["city", "town", "camp"]
const BEHAVIORS := ["hunt", "patrol", "wander", "idle"]
const ROLES := ["heavy", "light", "spellcaster"]
const WATER_RING := 20.0      # how far a start-in-a-lake is nudged per try
const WATER_SAMPLES := 12     # ...and how many directions each ring tries
const RIVER_BLOBS := 5        # blobs stamped between two river points; spacing well
                              # under the radius, so they merge with a scalloped bank

# A settlement flies a civilized banner or a monster one (a hostile town is a
# thing this game already ships — Ashfell). Lairs and roaming bands draw their
# fight from Scaler's rosters, so their faction has to be one Scaler knows.
# A function rather than a const: the two lists live in other scripts, and
# `const` wants an expression it can fold at parse time.
static func known_faction(f: String) -> bool:
	return WorldAI.CIVILIZED.has(f) or Scaler.FACTIONS.has(f)

static func _vec(v, fallback := Vector2.ZERO) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback

static func _is_point(v) -> bool:
	return v is Array and v.size() >= 2 and (v[0] is float or v[0] is int) \
		and (v[1] is float or v[1] is int)

# Every problem at once, split into what stops the map loading (`errors`) and
# what only makes it a worse map (`warnings`) — a settlement in a lake is not
# malformed JSON, it is a design mistake, and the author is the one who should
# be told about it rather than the loader guessing a fix.
static func validate(src) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not (src is Dictionary):
		return {"errors": ["world file is not a JSON object"] as Array[String],
			"warnings": warnings}
	var d: Dictionary = src
	if String(d.get("format", "")) != FORMAT:
		errors.append("world format must be \"%s\"" % FORMAT)

	var ids := {}
	var seen := func(id: String, what: String) -> void:
		if id.is_empty():
			errors.append("a %s has no id" % what)
		elif ids.has(id):
			errors.append("duplicate id \"%s\" (%s)" % [id, what])
		else:
			ids[id] = what

	var settlements = d.get("settlements", [])
	if not (settlements is Array) or settlements.is_empty():
		errors.append("a world needs at least one settlement")
		settlements = []
	for s in settlements:
		if not (s is Dictionary):
			errors.append("a settlement is not an object")
			continue
		seen.call(String(s.get("id", "")), "settlement")
		if not _is_point(s.get("position")):
			errors.append("settlement \"%s\" has no [x, y] position" % s.get("id", "?"))
		var kind := String(s.get("kind", "town"))
		if not KINDS.has(kind):
			errors.append("settlement \"%s\": kind \"%s\" is not one of %s"
				% [s.get("id", "?"), kind, ", ".join(KINDS)])
		var faction := String(s.get("faction", ""))
		if not known_faction(faction):
			errors.append("settlement \"%s\": unknown faction \"%s\""
				% [s.get("id", "?"), faction])

	for l in d.get("lairs", []):
		if not (l is Dictionary):
			errors.append("a lair is not an object")
			continue
		seen.call(String(l.get("id", "")), "lair")
		if not _is_point(l.get("position")):
			errors.append("lair \"%s\" has no [x, y] position" % l.get("id", "?"))
		# A lair IS its fight: core/site.gd builds every room from
		# Scaler.roster_for(faction), so a faction Scaler has no roster for is a
		# lair you can find, enter, and then meet nothing in.
		if not Scaler.FACTIONS.has(String(l.get("faction", ""))):
			errors.append("lair \"%s\": faction \"%s\" has no bestiary roster"
				% [l.get("id", "?"), l.get("faction", "")])

	var Landmarks = load("res://core/landmarks.gd")
	for m in d.get("landmarks", []):
		if not (m is Dictionary):
			errors.append("a landmark is not an object")
			continue
		seen.call(String(m.get("id", "")), "landmark")
		if not _is_point(m.get("position")):
			errors.append("landmark \"%s\" has no [x, y] position" % m.get("id", "?"))
		if not Landmarks.KINDS.has(String(m.get("kind", ""))):
			errors.append("landmark \"%s\": kind \"%s\" is not one of %s"
				% [m.get("id", "?"), m.get("kind", ""), Landmarks.KINDS])

	for p in d.get("parties", []):
		if not (p is Dictionary):
			errors.append("a party is not an object")
			continue
		var pid := String(p.get("id", ""))
		seen.call(pid, "party")
		if pid == "player":
			errors.append("\"player\" is the party the game adds; use \"start\"")
		if not _is_point(p.get("position")):
			errors.append("party \"%s\" has no [x, y] position" % pid)
		if not known_faction(String(p.get("faction", ""))):
			errors.append("party \"%s\": unknown faction \"%s\"" % [pid, p.get("faction", "")])
		var ai = p.get("ai", {})
		if ai is Dictionary and not ai.is_empty():
			var behavior := String(ai.get("behavior", ""))
			if not BEHAVIORS.has(behavior):
				errors.append("party \"%s\": behavior \"%s\" is not one of %s"
					% [pid, behavior, ", ".join(BEHAVIORS)])
			if behavior == "patrol":
				var wp = ai.get("waypoints", [])
				if not (wp is Array) or wp.size() < 2:
					errors.append("party \"%s\": a patrol needs 2+ waypoints" % pid)
		for t in p.get("troops", []):
			if t is Dictionary and not ROLES.has(String(t.get("role", ""))):
				warnings.append("party \"%s\": troop role \"%s\" has no map figure"
					% [pid, t.get("role", "")])

	for w in d.get("waters", []):
		if not (w is Dictionary):
			errors.append("a water blob is not an object")
			continue
		if float(w.get("radius", 0.0)) <= 0.0:
			errors.append("a water blob needs a radius above 0")
		if w.has("river"):
			var river = w["river"]
			if not (river is Array) or river.size() < 2:
				errors.append("a river needs 2+ points")
		elif not _is_point(w.get("position")):
			errors.append("a water blob needs a [x, y] position or a river")

	var start = d.get("start", {})
	if start is Dictionary and start.has("at"):
		var at := String(start["at"])
		if ids.get(at, "") != "settlement":
			errors.append("start.at \"%s\" is not a settlement in this world" % at)

	if errors.is_empty():
		warnings.append_array(_placement_warnings(d))
	return {"errors": errors, "warnings": warnings}

# Sanity the schema cannot express. Only run once the map parses, because these
# all need real positions to be worth reading.
static func _placement_warnings(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var blobs: Array = []
	for w in d.get("waters", []):
		var radius := float(w.get("radius", 0.0))
		if w.has("river"):
			for pt in w["river"]:
				blobs.append({"position": _vec(pt), "radius": radius})
		else:
			blobs.append({"position": _vec(w.get("position")), "radius": radius})
	var wet := func(p: Vector2) -> bool:
		for b in blobs:
			if p.distance_to(b["position"]) < float(b["radius"]):
				return true
		return false
	for group in [["settlements", "settlement"], ["lairs", "lair"], ["parties", "party"]]:
		for e in d.get(group[0], []):
			if e is Dictionary and wet.call(_vec(e.get("position"))):
				# Water is terrain, not decoration (core/world.gd): a thing
				# standing in a blob is a thing nobody can walk to.
				out.append("%s \"%s\" is standing in water" % [group[1], e.get("id", "?")])
	return out

# `null` when the map does not validate — callers that want the reason ask
# validate() first (core/mod/registry.gd does, and keeps it for the browser).
static func build(src, pack_id := "", seed_v := 0):
	if not validate(src)["errors"].is_empty():
		return null
	var d: Dictionary = src
	var w := World.new()
	# Which builder made this map, the same field every built-in world sets and
	# core/world_save.gd round-trips. A resumed pack world is restored from the
	# save's own settlement/lair/party lists like any other, so this is a label
	# — but it is the label that lets a save say which pack it belongs to.
	w.origin = {"kind": "pack:" + pack_id if pack_id != "" else "pack",
		"seed": seed_v}     # ("pack:x" when there is an id, "pack" when there is not)

	# id -> position, for everything an author may point at by name later: a
	# patrol waypoint, a wander home, the start. Settlements and lairs share
	# one namespace (the validator enforces that), so one table serves both.
	var by_id := {}
	for s in d.get("settlements", []):
		var st := World.Settlement.new(String(s["id"]), _vec(s.get("position")),
			String(s.get("faction", "human")), String(s.get("kind", "town")),
			String(s.get("name", "")))
		by_id[st.id] = st.position
		w.add_settlement(st)

	for l in d.get("lairs", []):
		var lair := World.Lair.new(String(l["id"]), _vec(l.get("position")),
			String(l.get("faction", "goblinoid")), String(l.get("name", "")))
		# An author may start a lair already on the map — a story that opens
		# with "everyone knows what is up that valley" should not need a
		# Survival check to say so.
		lair.discovered = bool(l.get("discovered", false))
		by_id[lair.id] = lair.position
		w.add_lair(lair)

	for m in d.get("landmarks", []):
		var mark := World.Landmark.new(String(m["id"]), String(m.get("kind", "ruins")),
			_vec(m.get("position")), String(m.get("name", "")))
		by_id[mark.id] = mark.position
		w.add_landmark(mark)

	# Water before the parties so nothing is placed into a blob that does not
	# exist yet... and before the player, whose start is snapped to dry land.
	for entry in d.get("waters", []):
		var radius := float(entry.get("radius", 0.0))
		if entry.has("river"):
			var pts: Array = entry["river"]
			var step: int = maxi(1, int(entry.get("blobs", RIVER_BLOBS)))
			for i in pts.size() - 1:
				var a := _vec(pts[i])
				var b := _vec(pts[i + 1])
				for t in step:
					w.add_water(a.lerp(b, float(t) / float(step)), radius)
			w.add_water(_vec(pts[-1]), radius)
		else:
			w.add_water(_vec(entry.get("position")), radius)

	var start: Dictionary = d.get("start", {}) if d.get("start") is Dictionary else {}
	var origin_pos: Vector2 = w.settlements[0].position
	if start.has("at") and by_id.has(String(start["at"])):
		origin_pos = by_id[String(start["at"])] + _vec(start.get("offset"))
	elif start.has("position"):
		origin_pos = _vec(start["position"])
	# Nobody starts the game already swimming. A party inside a blob is allowed
	# to move (core/world.gd would rather let it swim out than wedge it), but
	# starting there means the first thing the map does is look broken.
	origin_pos = _dry(w, origin_pos)
	var player := w.add_party(World.RoamingParty.new("player", origin_pos,
		String(start.get("faction", "human")), true))
	w.set_goal(player, player.position)

	for p in d.get("parties", []):
		var band := w.add_party(World.RoamingParty.new(String(p["id"]),
			_vec(p.get("position")), String(p.get("faction", "bandit"))))
		band.sname = String(p.get("name", ""))   # optional; unnamed is seeded (EnemyNames.band_name)
		for t in p.get("troops", []):
			if t is Dictionary:
				band.troops.append({"role": String(t.get("role", "heavy")),
					"level": int(t.get("level", 1))})
		_apply_ai(w, band, p.get("ai", {}), by_id)
	return w

# The nearest point outside the water, found by widening rings. The map's
# terrain is a handful of circles, so a dozen samples a ring is plenty.
static func _dry(world, pos: Vector2) -> Vector2:
	if not world.is_water(pos):
		return pos
	for i in 60:
		var r := WATER_RING * float(i + 1)
		for k in WATER_SAMPLES:
			var a := TAU * float(k) / float(WATER_SAMPLES)
			var candidate := pos + Vector2(cos(a), sin(a)) * r
			if not world.is_water(candidate):
				return candidate
	return pos

static func _apply_ai(world, band, ai, by_id: Dictionary) -> void:
	if not (ai is Dictionary):
		return
	match String(ai.get("behavior", "idle")):
		"hunt":
			WorldAI.hunt(band)
		"patrol":
			var waypoints: Array = []
			for p in ai.get("waypoints", []):
				# A waypoint may name a settlement instead of a point — a patrol
				# that rides between two towns should survive somebody moving one.
				if p is String:
					if by_id.has(String(p)):
						waypoints.append(by_id[String(p)])
				else:
					waypoints.append(_vec(p))
			WorldAI.patrol(band, waypoints)
		"wander":
			var home = ai.get("home", band.position)
			var at: Vector2 = by_id[String(home)] if home is String \
				and by_id.has(String(home)) else _vec(home, band.position)
			WorldAI.wander(band, at, float(ai.get("radius", 80.0)), int(ai.get("seed", 0)))
		_:
			band.goal = band.position     # "idle": stands where it was placed

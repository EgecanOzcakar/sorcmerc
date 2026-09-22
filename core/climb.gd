# The whole climb, 1 to 20, as one list: what every level of a class grants,
# which rungs are behind you, which is next, and which are still veiled.
#
# This exists because the character screens only ever drew the level you were
# standing on. A player could not see that Extra Attack waits at 5, or what
# taking the Berserker at 3 buys at 14, without leaving the game. Drawing the
# whole track is a reading problem, not a rules one — the data was always
# there, twenty entries deep in data/classes.json, with the paths keyed by
# classLevel in data/subclasses.json. The one piece of real work is merging
# those two, because a class level that looks empty (barbarian 14, monk 11) is
# usually a level where the path, not the class, does the granting.
#
#   Climb.track(ch)                       # the build's own climb
#   Climb.build("rogue", "thief", 5)      # any class, for the creator
#   Climb.headline(entry)                 # the one name a rung is called by
#
# Veiling is a display fact computed here so both screens agree on it: a rung
# past `at_level + 1` is `veiled`, meaning its names and marks stay legible but
# what they DO is not read until you get there.
#
# Not core/ladder.gd, which is the party's standing with a people — a different
# ladder entirely, and the older claim on the word.
#
# What this does NOT own: the level-up itself (core/leveling.gd), what a choice
# offers (scenes/creator/creator.gd's statics), what a feature does in a fight
# (core/rules/effects.gd), and anything about how a rung is drawn.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")

const MAX_LEVEL := 20


# The climb for a character's own class. ponytail: single-class — `class_id()`
# is the first class taken, and the resolver assumes single-class everywhere
# else too (data/SCHEMA.md gap #6). A multiclass build shows its first class's
# track; give this a per-class tab the day multiclassing is real.
static func track(ch) -> Array:
	if ch == null or ch.level() == 0:
		return []
	var cid: String = ch.class_id()
	return build(cid, String(ch.sheet().subclasses.get(cid, "")), ch.level())


# `at_level` is the level the reader stands on: everything at or below it is
# taken, the one above it is next, the rest are veiled. Pass 0 for a class
# nobody has taken yet — the creator's class step, where the whole track is
# veiled and read for its shape rather than its numbers.
static func build(class_id: String, subclass_id := "", at_level := 0) -> Array:
	var src: Dictionary = Catalog.class_src(class_id)
	if src.is_empty():
		return []
	var levels: Array = src.get("levels", [])
	var slots: Array = src.get("spellSlots", [])
	var paths: Array = paths_for(class_id)
	var sub: Dictionary = Catalog.subclass_src(subclass_id) if subclass_id != "" else {}

	var out: Array = []
	for n in range(1, MAX_LEVEL + 1):
		var grants: Array = []
		var fork: Array = []
		for g in (levels[n - 1] if n <= levels.size() else []):
			if String(g.get("type", "")) == "subclass":
				fork = paths
			var e: Dictionary = _grant(g)
			if not e.is_empty():
				grants.append(e)
		for e in _path_grants(sub, n):
			grants.append(e)
		out.append({
			"level": n,
			"grants": grants,
			"fork": fork,
			"slots": _slots(slots, n),
			"taken": n <= at_level,
			"next": n == at_level + 1,
			"veiled": n > at_level + 1,
		})
	return out


# Every path the class offers, in catalog order — the branches drawn at the
# fork, whether or not one has been taken.
static func paths_for(class_id: String) -> Array:
	var out: Array = []
	for s in Catalog.all("subclasses.json"):
		if String(s.get("classId", "")) == class_id:
			out.append({"id": String(s["id"]), "name": String(s.get("name", s["id"]))})
	return out


# The name a rung is called by: its first feature, or the choice that IS the
# level when it grants no feature. A level that only widens the slot table says
# so; one that grants nothing at all is honest about it (the warlock's 18).
static func headline(entry: Dictionary) -> String:
	if not entry["fork"].is_empty():
		return "Your path"
	for g in entry["grants"]:
		if g["kind"] == "feature":
			return g["label"]
	for g in entry["grants"]:
		if g["kind"] == "asi":
			return "Ability score or feat"
	if not entry["grants"].is_empty():
		return String(entry["grants"][0]["label"])
	if not entry["slots"].is_empty():
		return "Deeper magic"
	return "Hit points only"


# The running totals a reader wants beside the track, computed once here so
# both screens show the same numbers instead of each inventing its own.
static func summary(entries: Array) -> Dictionary:
	var feats := 0
	var picks := 0
	var forks := 0
	for e in entries:
		for g in e["grants"]:
			match g["kind"]:
				"feature": feats += 1
				"pick", "asi": picks += 1
		if not e["fork"].is_empty():
			forks += 1
	return {"features": feats, "choices": picks, "forks": forks}


static func _path_grants(sub: Dictionary, level: int) -> Array:
	var out: Array = []
	if sub.is_empty():
		return out
	for tier in sub.get("levels", []):
		if int(tier.get("classLevel", 0)) != level:
			continue
		for g in tier.get("grants", []):
			var e: Dictionary = _grant(g)
			if not e.is_empty():
				out.append(e)
	return out


# One grant, flattened to what a rung shows: a kind the view switches on, the
# id an icon is looked up by, and the two strings a reader sees.
static func _grant(g: Dictionary) -> Dictionary:
	match String(g.get("type", "")):
		"feature":
			var fid := String(g["feature"]["id"])
			return {"kind": "feature", "id": fid,
				"label": Effects.verb_label(fid), "source": Effects.feature_source(fid)}
		"subclass":
			return {"kind": "fork", "id": "subclass", "label": "Your path", "source": "choose one"}
		"asi":
			return {"kind": "asi", "id": "asi",
				"label": "+%d ability points" % int(g.get("points", 2)), "source": "or a feat"}
		"resource-pool":
			var pid := String(g.get("poolId", ""))
			return {"kind": "pool", "id": pid, "label": Effects.humanize(pid), "source": "resource"}
		"spell-choice":
			return _pick("spell-choice", "New spell", g)
		"weapon-mastery-choice":
			return _pick("weapon-mastery", "Weapon mastery", g)
		"expertise-choice":
			return _pick("expertise", "Expertise", g)
		"fighting-style-choice":
			return {"kind": "pick", "id": "fighting-style",
				"label": "Fighting style", "source": "choose one"}
		"feature-choice":
			return {"kind": "pick", "id": "feature-choice",
				"label": Effects.humanize(String(g.get("key", "choice")).get_slice(":", 0)),
				"source": "choose one"}
		"proficiency-choice":
			var cat := String(g.get("category", "skill"))
			return _pick(cat, "%s proficiency" % Effects.humanize(cat), g)
		"bundle-choice":
			return {"kind": "pick", "id": "kit", "label": "Starting kit", "source": "choose one"}
		"spellcasting":
			return {"kind": "feature", "id": "spellcasting", "label": "Spellcasting",
				"source": String(g.get("ability", "")).to_upper()}
		"speed":
			return {"kind": "num", "id": "speed", "label": "Speed",
				"source": "+%s ft" % str(g.get("value", ""))}
	# feat-choice always rides alongside an asi and would read as a second line
	# saying the same thing; hit-die, proficiency and armor-class are
	# bookkeeping the sheet already shows.
	return {}


static func _pick(id: String, label: String, g: Dictionary) -> Dictionary:
	var n := int(g.get("count", 1))
	return {"kind": "pick", "id": id, "label": label,
		"source": ("×%d" % n) if n > 1 else "choose one"}


# The slot row for a level, but only when it changed — a rung that repeats the
# level below it is not news, and every caster level would otherwise carry one.
static func _slots(table: Array, level: int) -> Array:
	if level > table.size():
		return []
	var now: Array = table[level - 1]
	var was: Array = table[level - 2] if level >= 2 else []
	return now.duplicate() if now != was else []

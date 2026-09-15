# M4 — a story, written down: chapters, the people in them, and the beats that
# fire as the party plays. This file is the SCHEMA half (parse, validate, look
# things up); core/mod/story_runtime.gd is the half that runs it.
#
# The whole model in one paragraph. A story is an ordered list of chapters.
# A chapter holds beats. A beat has a condition (`when`) and fires the first
# time that condition is true — and a condition is a plain predicate over
# things the game already tracks: a flag the story itself set, a quest's state
# in the party's own log, where the player is standing, which lairs are
# cleared, the party's level, the day. Nothing subscribes to anything: the
# runtime is polled, asks "what is true now", and hands back the beats that
# just became so.
#
# That is the design decision everything else falls out of. Events would need
# a bus, and every system in the game would need to publish into it; state
# predicates need nothing — a story can be written against the game as it
# already is, which is exactly what a modder has to work with.
#
# story.json:
#
# {
#   "format": "sorcmerc-story",
#   "version": 1,
#   "title": "The Ashen Road",
#   "synopsis": "Something is burning the marches, one holding at a time.",
#   "cast": [
#     {"id": "maera", "name": "Maera Vulk", "role": "Reeve of Riverhold",
#      "home": "riverhold", "about": "Tired, and out of soldiers."}
#   ],
#   "chapters": [
#     {"id": "smoke", "title": "Smoke on the Marches",
#      "intro": "A rider comes in at dusk with half a face.",
#      "beats": [
#        {"id": "meet-maera", "kind": "scene", "speaker": "maera",
#         "when": {"near": "riverhold"},
#         "lines": ["\"You're the ones who take work.\""],
#         "choices": [
#           {"id": "take", "text": "Name the price.",
#            "then": {"flags": ["hired"], "journal": ["Hired by the reeve."]}},
#           {"id": "refuse", "text": "Not our war.", "then": {"flags": ["refused"]}}
#         ]},
#        {"id": "the-warren", "kind": "quest", "when": {"flag": "hired"},
#         "quest": {"id": "ashen-warren", "kind": "clear_lair",
#                   "target_lair_id": "goblin-warren", "title": "Burn out the warren",
#                   "reward": {"gold": 150}}}
#      ],
#      "ends_when": {"quest": "ashen-warren", "state": "turned_in"}}
#   ]
# }
#
# A quest beat's `quest` is a core/quest.gd quest dict, and that is not a
# coincidence: firing one appends it to `party.quests`, where every existing
# piece of quest machinery — progress from kills, the turn-in, the log panel,
# the spawn bias — picks it up with no idea a story is involved. A quest chain
# is therefore quests that unlock each other, not a second quest system.
extends RefCounted

const Quest = preload("res://core/quest.gd")

const FORMAT := "sorcmerc-story"
const BEAT_KINDS := ["scene", "quest", "note"]
# The quest kinds core/quest.gd can actually track. A story may not invent one:
# an unknown kind is a quest that can be taken and never completed. Read off
# quest.gd rather than copied — this list was a copy until D7 added three kinds
# to quest.gd and left the validator rejecting all three.
const QUEST_KINDS := Quest.KINDS

# Condition vocabulary. Listed here (rather than being whatever the runtime
# happens to read) so a typo is an error an author is shown, not a beat that
# silently never fires — which is the single worst failure mode a data-driven
# story can have.
const CONDITION_KEYS := ["all", "any", "none", "flag", "flags", "not_flag",
	"beat", "quest", "state", "party_level", "gold", "has_item", "visited",
	"near", "within", "lair_cleared", "lair_found", "region", "day",
	"opinion", "faction", "atleast", "chapter"]
# `state` / `within` / `faction` / `atleast` are qualifiers on the key above
# them ({"quest": id, "state": ...}), not conditions of their own.
const EFFECT_KEYS := ["flags", "clear_flags", "journal", "gold", "items", "xp",
	"quest", "opinion", "reveal_lair", "spawn_party", "next_chapter", "end_story"]

const QUEST_STATES := ["offered", "active", "complete", "turned_in", "any"]

var title := ""
var synopsis := ""
var cast: Array = []          # [{id, name, role, home, about}]
var chapters: Array = []      # [{id, title, intro, beats: [...], ends_when: {}}]
var errors: Array[String] = []
var warnings: Array[String] = []
# Item ids this pack adds itself, from its own data overlays — the catalog does
# not have them yet at validation time (overlays land after a scan), so without
# this every reward a pack invents would look like a typo.
var _known_items := {}

func ok() -> bool:
	return errors.is_empty()

func chapter(id: String) -> Dictionary:
	for c in chapters:
		if String(c["id"]) == id:
			return c
	return {}

func first_chapter_id() -> String:
	return String(chapters[0]["id"]) if not chapters.is_empty() else ""

# The chapter after `id`, or "" at the end of the story. Order is the order
# they are written in; there is no chapter graph and deliberately so — a story
# that branches does it with conditions and flags inside a chapter, which is
# the same tool everything else uses.
func next_chapter_id(id: String) -> String:
	for i in chapters.size():
		if String(chapters[i]["id"]) == id:
			return String(chapters[i + 1]["id"]) if i + 1 < chapters.size() else ""
	return ""

func beats_of(chapter_id: String) -> Array:
	var c := chapter(chapter_id)
	return c.get("beats", []) if not c.is_empty() else []

func beat(id: String) -> Dictionary:
	for c in chapters:
		for b in c.get("beats", []):
			if String(b["id"]) == id:
				return b
	return {}

func member(cast_id: String) -> Dictionary:
	for m in cast:
		if String(m["id"]) == cast_id:
			return m
	return {}

# Who is speaking, for a card header: the cast entry's name and role, or the
# raw id if a story names somebody it never introduced.
func speaker_label(cast_id: String) -> String:
	var m := member(cast_id)
	if m.is_empty():
		return cast_id
	var role := String(m.get("role", ""))
	return "%s — %s" % [m["name"], role] if role != "" else String(m["name"])

static func parse(src):
	var s = new()
	if not (src is Dictionary):
		s.errors.append("story file is not a JSON object")
		return s
	var d: Dictionary = src
	if String(d.get("format", "")) != FORMAT:
		s.errors.append("story format must be \"%s\"" % FORMAT)
	s.title = String(d.get("title", ""))
	s.synopsis = String(d.get("synopsis", ""))
	if d.get("cast") is Array:
		s.cast = d["cast"]
	if d.get("chapters") is Array:
		s.chapters = d["chapters"]
	return s

# The rest of validation, split out because it is long and because parse()
# has to survive anything. `world_ids` is {id: "settlement"|"lair"|"party"}
# from the pack's own map when it has one — with it, a story that sends the
# party to a settlement the map does not have is caught by the validator
# rather than by a player standing somewhere waiting for a beat that cannot
# fire. Without it those references are simply not checked.
func check(world_ids := {}, item_ids := {}) -> void:
	_known_items = item_ids
	if chapters.is_empty():
		errors.append("a story needs at least one chapter")
	var beat_ids := {}
	var quest_ids := {}
	var cast_ids := {}
	for m in cast:
		if not (m is Dictionary) or String(m.get("id", "")).is_empty():
			errors.append("a cast member has no id")
			continue
		if cast_ids.has(String(m["id"])):
			errors.append("duplicate cast id \"%s\"" % m["id"])
		cast_ids[String(m["id"])] = true
		if String(m.get("name", "")).is_empty():
			errors.append("cast \"%s\" has no name" % m["id"])
		var home := String(m.get("home", ""))
		if home != "" and not world_ids.is_empty() and not world_ids.has(home):
			warnings.append("cast \"%s\" lives at \"%s\", which is not on the map"
				% [m["id"], home])

	var chapter_ids := {}
	for c in chapters:
		if not (c is Dictionary) or String(c.get("id", "")).is_empty():
			errors.append("a chapter has no id")
			continue
		var cid := String(c["id"])
		if chapter_ids.has(cid):
			errors.append("duplicate chapter id \"%s\"" % cid)
		chapter_ids[cid] = true
		if not (c.get("beats") is Array) or c["beats"].is_empty():
			errors.append("chapter \"%s\" has no beats" % cid)
			continue
		for b in c["beats"]:
			_check_beat(b, cid, beat_ids, quest_ids, cast_ids, world_ids)
		_check_condition(c.get("ends_when", {}), "chapter \"%s\" ends_when" % cid, world_ids)

	# Second pass: cross-references can point forward, so they can only be
	# checked once every id in the story is known.
	for c in chapters:
		if not (c is Dictionary):
			continue
		for b in c.get("beats", []):
			if not (b is Dictionary):
				continue
			_check_refs(b.get("when", {}), beat_ids, quest_ids, chapter_ids,
				"beat \"%s\"" % b.get("id", "?"))
			for choice in b.get("choices", []):
				if choice is Dictionary:
					_check_refs(choice.get("when", {}), beat_ids, quest_ids, chapter_ids,
						"choice \"%s\"" % choice.get("id", "?"))
		_check_refs(c.get("ends_when", {}), beat_ids, quest_ids, chapter_ids,
			"chapter \"%s\"" % c.get("id", "?"))

func _check_beat(b, chapter_id: String, beat_ids: Dictionary, quest_ids: Dictionary,
		cast_ids: Dictionary, world_ids: Dictionary) -> void:
	if not (b is Dictionary):
		errors.append("chapter \"%s\": a beat is not an object" % chapter_id)
		return
	var bid := String(b.get("id", ""))
	if bid.is_empty():
		errors.append("chapter \"%s\": a beat has no id" % chapter_id)
		return
	if beat_ids.has(bid):
		errors.append("duplicate beat id \"%s\"" % bid)
	beat_ids[bid] = chapter_id
	var kind := String(b.get("kind", "scene"))
	if not BEAT_KINDS.has(kind):
		errors.append("beat \"%s\": kind \"%s\" is not one of %s"
			% [bid, kind, ", ".join(BEAT_KINDS)])
	var speaker := String(b.get("speaker", ""))
	if speaker != "" and not cast_ids.has(speaker):
		errors.append("beat \"%s\": speaker \"%s\" is not in the cast" % [bid, speaker])
	# Shape before content: the world screen reads `lines`/`choices` straight
	# off the beat, so "lines": "a string" has to be an error here rather than
	# a crash there.
	for key in ["lines", "choices"]:
		if b.has(key) and not (b[key] is Array):
			errors.append("beat \"%s\": \"%s\" must be a list" % [bid, key])
	if kind == "scene" and _list(b, "lines").is_empty() and _list(b, "choices").is_empty():
		errors.append("beat \"%s\": a scene needs lines or choices" % bid)
	if kind == "quest":
		var q = b.get("quest", {})
		if not (q is Dictionary) or q.is_empty():
			errors.append("beat \"%s\": a quest beat needs a quest" % bid)
		else:
			_check_quest(q, bid, quest_ids, world_ids)
	_check_condition(b.get("when", {}), "beat \"%s\"" % bid, world_ids)
	_check_effects(b.get("then", {}), "beat \"%s\"" % bid, quest_ids, world_ids)
	var choice_ids := {}
	for c in _list(b, "choices"):
		if not (c is Dictionary):
			errors.append("beat \"%s\": a choice is not an object" % bid)
			continue
		var chid := String(c.get("id", ""))
		if chid.is_empty():
			errors.append("beat \"%s\": a choice has no id" % bid)
		elif choice_ids.has(chid):
			errors.append("beat \"%s\": duplicate choice id \"%s\"" % [bid, chid])
		choice_ids[chid] = true
		if String(c.get("text", "")).is_empty():
			errors.append("beat \"%s\": choice \"%s\" has no text" % [bid, chid])
		_check_condition(c.get("when", {}), "beat \"%s\" choice \"%s\"" % [bid, chid], world_ids)
		_check_effects(c.get("then", {}), "beat \"%s\" choice \"%s\"" % [bid, chid],
			quest_ids, world_ids)

# `d[key]` as a list, whatever an author actually put there.
static func _list(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []

func _check_quest(q: Dictionary, where: String, quest_ids: Dictionary,
		world_ids: Dictionary) -> void:
	var qid := String(q.get("id", ""))
	if qid.is_empty():
		errors.append("%s: the quest has no id" % where)
	elif quest_ids.has(qid):
		errors.append("%s: duplicate quest id \"%s\"" % [where, qid])
	else:
		quest_ids[qid] = true
	if String(q.get("title", "")).is_empty():
		errors.append("%s: the quest has no title" % where)
	var kind := String(q.get("kind", ""))
	if not QUEST_KINDS.has(kind):
		errors.append("%s: quest kind \"%s\" is not one of %s"
			% [where, kind, ", ".join(QUEST_KINDS)])
		return
	# Each kind names its target in its own field; a quest missing that field
	# can never make progress, which looks exactly like a bug in the game.
	var need: String = String(Quest.TARGET_FIELD[kind])
	if String(q.get(need, "")).is_empty():
		errors.append("%s: a %s quest needs %s" % [where, kind, need])
	elif not world_ids.is_empty() and Quest.WORLD_TARGET_FIELDS.has(need) \
			and not world_ids.has(String(q[need])):
		errors.append("%s: %s \"%s\" is not on this pack's map" % [where, need, q[need]])
	if kind == "collect_item" and String(q.get("target_item_id", "")).is_empty():
		errors.append("%s: a collect_item quest needs target_item_id" % where)
	if int(q.get("required", 1)) <= 0:
		errors.append("%s: required must be 1 or more" % where)
	if q.get("reward") is Dictionary and q["reward"].has("item_id"):
		_check_item(String(q["reward"]["item_id"]), where)
	if kind == "collect_item":
		# The collected thing is a quest token, not a catalog item — the game
		# stashes whatever id the quest names. Nothing to check.
		pass

# A reward nobody can receive is the most expensive kind of typo: the player
# finishes a chain and gets nothing. A warning rather than an error, because a
# pack may legitimately name an item another pack adds.
func _check_item(id: String, where: String) -> void:
	if id.is_empty() or _known_items.has(id):
		return
	var Catalog = load("res://core/rules/catalog.gd")
	for file in ["magic-items.json", "weapons.json", "armor.json"]:
		if Catalog.index(file).has(id):
			return
	warnings.append("%s: no item \"%s\" in the catalog or in this pack" % [where, id])

func _check_condition(c, where: String, world_ids: Dictionary) -> void:
	if c == null or (c is Dictionary and c.is_empty()):
		return
	if not (c is Dictionary):
		errors.append("%s: a condition must be an object" % where)
		return
	for key in c:
		var k := String(key)
		if not CONDITION_KEYS.has(k):
			errors.append("%s: unknown condition \"%s\"" % [where, k])
			continue
		match k:
			"all", "any", "none":
				if not (c[k] is Array):
					errors.append("%s: \"%s\" takes a list of conditions" % [where, k])
					continue
				for sub in c[k]:
					_check_condition(sub, where, world_ids)
			"quest":
				var st := String(c.get("state", "turned_in"))
				if not QUEST_STATES.has(st):
					errors.append("%s: quest state \"%s\" is not one of %s"
						% [where, st, ", ".join(QUEST_STATES)])
			"flags":
				if not (c[k] is Array):
					errors.append("%s: \"flags\" takes a list of flag names" % where)
			"opinion":
				if not (c[k] is Dictionary) or String(c[k].get("faction", "")).is_empty():
					errors.append("%s: \"opinion\" takes {faction, atleast}" % where)
			"near", "visited", "lair_cleared", "lair_found":
				if not world_ids.is_empty() and not world_ids.has(String(c[k])):
					errors.append("%s: \"%s\" is not on this pack's map" % [where, c[k]])
			"region":
				var Regions = load("res://core/regions.gd")
				if Regions.band_by_id(String(c[k])).is_empty():
					errors.append("%s: \"%s\" is not a region" % [where, c[k]])

func _check_effects(e, where: String, quest_ids: Dictionary, world_ids: Dictionary) -> void:
	if e == null or (e is Dictionary and e.is_empty()):
		return
	if not (e is Dictionary):
		errors.append("%s: `then` must be an object" % where)
		return
	for key in e:
		var k := String(key)
		if not EFFECT_KEYS.has(k):
			errors.append("%s: unknown effect \"%s\"" % [where, k])
			continue
		match k:
			"quest":
				if e[k] is Dictionary:
					_check_quest(e[k], where, quest_ids, world_ids)
				else:
					errors.append("%s: `quest` must be an object" % where)
			"reveal_lair":
				if not world_ids.is_empty() and not world_ids.has(String(e[k])):
					errors.append("%s: lair \"%s\" is not on this pack's map" % [where, e[k]])
			"flags", "clear_flags", "journal", "opinion":
				if not (e[k] is Array):
					errors.append("%s: \"%s\" takes a list" % [where, k])
			"items":
				if not (e[k] is Array):
					errors.append("%s: `items` must be a list" % where)
				else:
					for item in e[k]:
						if item is Dictionary:
							_check_item(String(item.get("id", "")), where)

# Ids that can only be resolved once the whole story is parsed.
func _check_refs(c, beat_ids: Dictionary, quest_ids: Dictionary,
		chapter_ids: Dictionary, where: String) -> void:
	if not (c is Dictionary):
		return
	for key in c:
		match String(key):
			"all", "any", "none":
				if c[key] is Array:
					for sub in c[key]:
						_check_refs(sub, beat_ids, quest_ids, chapter_ids, where)
			"beat":
				if not beat_ids.has(String(c[key])):
					errors.append("%s: no beat \"%s\" in this story" % [where, c[key]])
			"chapter":
				if not chapter_ids.has(String(c[key])):
					errors.append("%s: no chapter \"%s\" in this story" % [where, c[key]])
			"quest":
				# A story may also wait on a quest it did not write — one of
				# core/quest.gd's curated ones, or a generated world quest — so
				# an unknown id is a warning, not an error.
				if not quest_ids.has(String(c[key])) \
						and Quest.fresh(String(c[key])).is_empty():
					warnings.append("%s: waits on quest \"%s\", which this story never gives"
						% [where, c[key]])

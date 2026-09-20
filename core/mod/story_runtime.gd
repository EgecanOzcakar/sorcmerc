# M5 — the half of a story that runs. core/mod/story.gd holds the written
# story; this holds the playthrough of it, and it is the only thing in the
# modding API with mutable state.
#
#   var run := StoryRuntime.new(story, saved_state)   # saved_state may be {}
#   for b in run.pending(world, party):               # once a frame is fine
#       lines = run.fire(b, world, party)             # applies the beat
#   run.choose(beat, "take", world, party)            # if it had choices
#   var d := run.to_dict()                            # rides in the world save
#
# Polled, not subscribed: pending() asks the live world and party what is true
# and returns the beats that just became eligible. The cost is a handful of
# dictionary lookups over one chapter's beats, which is why the world screen
# can afford to call it every frame and why a story needs no hooks anywhere
# else in the game.
#
# Two rules hold the whole thing together:
#
#  1. A beat fires once. `fired` remembers which, and it is saved — so a story
#     survives a reload in the middle of itself.
#  2. The runtime never asks the player anything. A beat with choices fires
#     (its own `then` applies), and the SCREEN then calls choose() when the
#     player picks one. A story that is never shown still advances; a card
#     dismissed without choosing simply applied no choice. Nothing blocks.
extends RefCounted

const Story = preload("res://core/mod/story.gd")
const Quest = preload("res://core/quest.gd")
const Regions = preload("res://core/regions.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")

const DAY := 1440.0          # world-minutes, same constant the rest of the game counts in
const NEAR := 60.0           # default radius for {"near": "riverhold"} — a little wider
                             # than the settlement beacon, so a beat fires as you ride up
                             # rather than only once you are standing on the gate

var story                    # core/mod/story.gd
var pack_id := ""
var chapter := ""            # the chapter now running; "" once the story is done
var flags := {}              # story-set flags: {"hired": true}
var fired := {}              # beat id -> true
var journal: Array[String] = []   # the story log the player reads
var done := false

func _init(story_v, state := {}, pack_id_v := "") -> void:
	story = story_v
	pack_id = pack_id_v if pack_id_v != "" else String(state.get("pack", ""))
	chapter = String(state.get("chapter", ""))
	done = bool(state.get("done", false))
	for k in state.get("flags", {}):
		flags[String(k)] = true
	for b in state.get("fired", []):
		fired[String(b)] = true
	for line in state.get("journal", []):
		journal.append(String(line))
	if chapter == "" and not done:
		chapter = story.first_chapter_id()

func to_dict() -> Dictionary:
	return {"pack": pack_id, "chapter": chapter, "done": done,
		"flags": flags.duplicate(), "fired": fired.keys(), "journal": journal.duplicate()}

# --- what is eligible right now -------------------------------------------

# Beats of the current chapter whose condition holds and which have not fired.
# Returned in the order the author wrote them, so a chapter that opens with a
# scene and then gives a quest arrives in that order even when both become
# true on the same frame.
func pending(world, party) -> Array:
	if done:
		return []
	var out: Array = []
	for b in story.beats_of(chapter):
		if not (b is Dictionary) or fired.has(String(b.get("id", ""))):
			continue
		if holds(b.get("when", {}), world, party):
			out.append(b)
	return out

# Apply a beat: mark it fired, run its `then`, and return the lines to show.
# Safe to call with a beat that is not pending (a screen may have queued it a
# frame ago); it simply will not fire twice.
func fire(b: Dictionary, world, party) -> Array[String]:
	var lines: Array[String] = []
	var bid := String(b.get("id", ""))
	if bid.is_empty() or fired.has(bid):
		return lines
	fired[bid] = true
	if String(b.get("kind", "scene")) == "quest":
		lines.append_array(_give_quest(b.get("quest", {}), party))
	lines.append_array(apply(b.get("then", {}), world, party))
	_note(b, lines)
	return lines

# The player picked one of a scene's options. The choice's own `then` is
# applied here and nowhere else — which is what makes a choice a choice.
func choose(b: Dictionary, choice_id: String, world, party) -> Array[String]:
	for c in _list(b, "choices"):
		if c is Dictionary and String(c.get("id", "")) == choice_id:
			if not holds(c.get("when", {}), world, party):
				return [] as Array[String]
			var lines: Array[String] = apply(c.get("then", {}), world, party)
			return lines
	return [] as Array[String]

# Which of a scene's choices the player may actually take. A choice with a
# condition that does not hold is not shown — an author gates "Pay the
# hundred gold" on having it, rather than on the player finding out afterwards.
func choices_for(b: Dictionary, world, party) -> Array:
	var out: Array = []
	for c in _list(b, "choices"):
		if c is Dictionary and holds(c.get("when", {}), world, party):
			out.append(c)
	return out

# Chapter bookkeeping, called after a round of fires. A chapter ends when its
# `ends_when` holds, or — with none written — when every non-optional beat in
# it has fired. The end of the last chapter ends the story.
func advance(world, party) -> Array[String]:
	var lines: Array[String] = []
	if done or chapter == "":
		return lines
	var guard := 0        # a chapter whose beats all fire at once can close several
	while guard < 32:     # in one call; the cap is only against a malformed story
		guard += 1
		var c: Dictionary = story.chapter(chapter)
		if c.is_empty():
			done = true
			break
		if not _chapter_over(c, world, party):
			break
		lines.append_array(_open(story.next_chapter_id(chapter)))
		if done:
			break
	return lines

func _chapter_over(c: Dictionary, world, party) -> bool:
	var ends = c.get("ends_when", {})
	if ends is Dictionary and not ends.is_empty():
		return holds(ends, world, party)
	for b in c.get("beats", []):
		if b is Dictionary and not bool(b.get("optional", false)) \
				and not fired.has(String(b.get("id", ""))):
			return false
	return true

func _open(next_id: String) -> Array[String]:
	var lines: Array[String] = []
	chapter = next_id
	if next_id == "":
		done = true
		lines.append("The story ends.")
		journal.append_array(lines)
		return lines
	var c: Dictionary = story.chapter(next_id)
	var title := String(c.get("title", ""))
	if title != "":
		lines.append("— %s —" % title)
	var intro := String(c.get("intro", ""))
	if intro != "":
		lines.append(intro)
	journal.append_array(lines)
	return lines

func _note(b: Dictionary, lines: Array[String]) -> void:
	var title := String(b.get("title", ""))
	if title != "":
		journal.append(title)
	for line in lines:
		journal.append(line)

# --- conditions -----------------------------------------------------------

# Every key in a condition must hold (AND); an empty condition is true, which
# is how a beat says "as soon as this chapter opens". `all`/`any`/`none` nest.
func holds(c, world, party) -> bool:
	if c == null:
		return true
	if not (c is Dictionary) or c.is_empty():
		return true
	for key in c:
		if not _one(String(key), c, world, party):
			return false
	return true

func _one(key: String, c: Dictionary, world, party) -> bool:
	match key:
		"all":
			for sub in c[key]:
				if not holds(sub, world, party):
					return false
			return true
		"any":
			for sub in c[key]:
				if holds(sub, world, party):
					return true
			return false
		"none":
			for sub in c[key]:
				if holds(sub, world, party):
					return false
			return true
		"flag":
			return flags.has(String(c[key]))
		"flags":
			if not (c[key] is Array):
				return false
			for f in c[key]:
				if not flags.has(String(f)):
					return false
			return true
		"not_flag":
			return not flags.has(String(c[key]))
		"beat":
			return fired.has(String(c[key]))
		"chapter":
			return chapter == String(c[key])
		"quest":
			return _quest_is(party, String(c[key]), String(c.get("state", "turned_in")))
		"party_level":
			return Regions.party_level(party) >= int(c[key])
		"gold":
			return party != null and party.gold >= int(c[key])
		"has_item":
			return party != null and party.stash_count(String(c[key])) > 0
		"visited":
			var s = _settlement(world, String(c[key]))
			return s != null and s.last_visited >= 0.0
		"near":
			return _near(world, String(c[key]), float(c.get("within", NEAR)))
		"lair_cleared":
			var l = _lair(world, String(c[key]))
			return l != null and l.looted
		"lair_found":
			var lf = _lair(world, String(c[key]))
			return lf != null and lf.discovered
		"region":
			var p = world.player() if world != null else null
			return p != null and Regions.band_of(world, p.position) == String(c[key])
		"day":
			return world != null and world.clock.elapsed / DAY >= float(c[key]) - 1.0
		"opinion":
			if not (c[key] is Dictionary):
				return false
			return FactionOpinion.get_opinion(String(c[key].get("faction", ""))) \
				>= float(c[key].get("atleast", 0.0))
		# `state`, `within`, `faction`, `atleast` are qualifiers read by the
		# key they belong to; on their own they mean nothing and hold.
		_:
			return true

func _quest_is(party, quest_id: String, want: String) -> bool:
	if party == null:
		return false
	var q: Dictionary = Quest.get_quest(party, quest_id)
	if q.is_empty():
		return false
	return true if want == "any" else String(q.get("state", "")) == want

static func _settlement(world, id: String):
	if world == null:
		return null
	for s in world.settlements:
		if s.id == id:
			return s
	return null

static func _lair(world, id: String):
	if world == null:
		return null
	for l in world.lairs:
		if l.id == id:
			return l
	return null

static func _landmark(world, id: String):
	return world.landmark(id) if world != null else null

# "Near" takes a settlement, a lair, or a landmark — an author should not
# have to know which list the game keeps a place in.
static func _near(world, id: String, within: float) -> bool:
	if world == null:
		return false
	var p = world.player()
	if p == null:
		return false
	var s = _settlement(world, id)
	var at = s.position if s != null else null
	if at == null:
		var l = _lair(world, id)
		at = l.position if l != null else null
	if at == null:
		var m = _landmark(world, id)
		at = m.position if m != null else null
	return at != null and p.position.distance_to(at) <= within

# --- effects --------------------------------------------------------------

# Everything a beat or a choice is allowed to do to the game, and the only
# place in the modding API that writes anything. Returns the lines to show.
func apply(e, world, party) -> Array[String]:
	var lines: Array[String] = []
	if not (e is Dictionary) or e.is_empty():
		return lines
	for f in _list(e, "flags"):
		flags[String(f)] = true
	for f in _list(e, "clear_flags"):
		flags.erase(String(f))
	for line in _list(e, "journal"):
		lines.append(String(line))
	if e.has("gold") and party != null:
		var gold := int(e["gold"])
		party.add_gold(gold)     # negative is a price, and add_gold takes it
		lines.append("%+d ◉" % gold)
	for item in _list(e, "items"):
		if item is Dictionary and party != null:
			var qty: int = maxi(1, int(item.get("quantity", 1)))
			party.stash_add(String(item.get("id", "")), qty)
			lines.append("Received: %s ×%d" % [item.get("id", "?"), qty])
	if e.has("xp") and party != null:
		lines.append_array(_award_xp(int(e["xp"]), party))
	if e.has("quest") and party != null:
		lines.append_array(_give_quest(e["quest"], party))
	for op in _list(e, "opinion"):
		if op is Dictionary:
			FactionOpinion.raise(String(op.get("faction", "")), float(op.get("delta", 0.0)))
	if e.has("reveal_lair"):
		var l = _lair(world, String(e["reveal_lair"]))
		if l != null and not l.discovered:
			l.discovered = true
			lines.append("%s is marked on your map." % l.sname)
	if e.has("spawn_party"):
		lines.append_array(_spawn(e["spawn_party"], world))
	if e.has("next_chapter"):
		lines.append_array(_open(String(e["next_chapter"])))
	if bool(e.get("end_story", false)) and not done:
		lines.append_array(_open(""))
	return lines

# `d[key]` as a list, whatever an author actually put there. The validator
# rejects the wrong shape at load, but a runtime that crashes on data is a
# runtime that crashes on the ONE pack that got past it.
static func _list(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []

# A story quest is a core/quest.gd quest in every way — it goes in the same
# log and is progressed and turned in by the same code. The two extra keys are
# bookkeeping: `story` is what lets a condition find it again, and
# `giver_node_id` is what the existing turn-in flow expects to be there.
func _give_quest(q, party) -> Array[String]:
	var lines: Array[String] = []
	if not (q is Dictionary) or q.is_empty() or party == null:
		return lines
	var quest: Dictionary = q.duplicate(true)
	quest["progress"] = 0
	quest["state"] = "offered"
	quest["story"] = pack_id
	if not quest.has("giver_node_id"):
		quest["giver_node_id"] = ""
	if not quest.has("required"):
		quest["required"] = 1
	if Quest.accept(party, quest):
		lines.append("New quest: %s" % quest.get("title", quest.get("id", "?")))
	return lines

# The same even split a fight pays, banked through the same path so lifetime
# progression (core/progression.gd) sees story XP as well. Loaded rather than
# preloaded: core/campaign.gd is a heavy module and a story does not need it
# until somebody actually writes an xp reward.
static func _award_xp(total: int, party) -> Array[String]:
	if total <= 0:
		return [] as Array[String]
	var Campaign = load("res://core/campaign.gd")
	Campaign.new(party)._split_xp(total)
	return ["%d XP" % total] as Array[String]

static func _spawn(spec, world) -> Array[String]:
	var lines: Array[String] = []
	if not (spec is Dictionary) or world == null:
		return lines
	var id := String(spec.get("id", ""))
	if id.is_empty():
		return lines
	for p in world.parties:      # a story that fires twice must not double the band
		if p.id == id:
			return lines
	var at := Vector2(0, 0)
	if spec.has("near"):
		var s = _settlement(world, String(spec["near"]))
		var l = _lair(world, String(spec["near"]))
		var m = _landmark(world, String(spec["near"]))
		if s != null:
			at = s.position
		elif l != null:
			at = l.position
		elif m != null:
			at = m.position
	if spec.has("offset") and spec["offset"] is Array and spec["offset"].size() >= 2:
		at += Vector2(float(spec["offset"][0]), float(spec["offset"][1]))
	elif spec.has("position") and spec["position"] is Array and spec["position"].size() >= 2:
		at = Vector2(float(spec["position"][0]), float(spec["position"][1]))
	var band = world.add_party(World.RoamingParty.new(id, at,
		String(spec.get("faction", "bandit"))))
	for t in _list(spec, "troops"):
		if t is Dictionary:
			band.troops.append({"role": String(t.get("role", "heavy")),
				"level": int(t.get("level", 1))})
	WorldAI.hunt(band)
	lines.append("%s takes the field." % String(spec.get("name", id.capitalize())))
	return lines

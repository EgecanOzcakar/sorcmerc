# M4/M5 — a story validates before it ships and runs off nothing but the state
# the game already keeps: conditions are predicates over the world and the
# party, a beat fires once, a quest beat lands in the ordinary quest log, and
# the whole playthrough round-trips through the autosave.
#   godot --headless --path . -s tests/test_story.gd
extends SceneTree

const Story = preload("res://core/mod/story.gd")
const StoryRuntime = preload("res://core/mod/story_runtime.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")
const Registry = preload("res://core/mod/registry.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_MODS_DIR", "user://nonexistent-mods")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/story-%d" % OS.get_process_id())
	test_validation()
	test_validation_rejects()
	test_conditions()
	test_effects()
	test_choices()
	test_chapters()
	test_quest_chain()
	test_save_round_trip()
	test_shipped_campaign_plays()
	print("test_story: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _world():
	return WorldPack.build({"format": "sorcmerc-world", "version": 1,
		"settlements": [{"id": "hold", "position": [0, 0], "faction": "human", "kind": "town"}],
		"lairs": [{"id": "warren", "position": [400, 0], "faction": "goblinoid"}],
		"start": {"at": "hold", "offset": [10, 0]}}, "t")

func _party():
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _story(src := {}):
	var d := {"format": "sorcmerc-story", "version": 1, "title": "T",
		"cast": [{"id": "a", "name": "Ann", "role": "Reeve", "home": "hold"}],
		"chapters": [
			{"id": "one", "title": "One", "intro": "It starts.",
			 "beats": [
				{"id": "open", "kind": "scene", "speaker": "a", "when": {},
				 "lines": ["Hello."],
				 "choices": [
					{"id": "yes", "text": "Yes.", "then": {"flags": ["said-yes"]}},
					{"id": "rich", "text": "Buy it.", "when": {"gold": 500},
					 "then": {"gold": -500, "flags": ["bought"]}}]},
				{"id": "job", "kind": "quest", "when": {"flag": "said-yes"},
				 "quest": {"id": "clear-it", "kind": "clear_lair", "target_lair_id": "warren",
					"title": "Clear the warren", "reward": {"gold": 100}}}],
			 "ends_when": {"quest": "clear-it", "state": "turned_in"}},
			{"id": "two", "title": "Two", "intro": "It continues.",
			 "beats": [{"id": "done", "kind": "note", "when": {},
				"then": {"journal": ["over"], "end_story": true}}]}]}
	d.merge(src, true)
	var story = Story.parse(d)
	story.check(_world_ids())
	return story

func _world_ids() -> Dictionary:
	return {"hold": "settlement", "warren": "lair"}

func _run(s = null) -> StoryRuntime:
	return StoryRuntime.new(_story() if s == null else s, {}, "testpack")

# --- validation -------------------------------------------------------------

func test_validation() -> void:
	var s = _story()
	check(s.ok(), "the fixture story is valid: %s" % ", ".join(s.errors))
	check(s.first_chapter_id() == "one", "the first chapter is the first one written")
	check(s.next_chapter_id("one") == "two" and s.next_chapter_id("two") == "",
		"chapters run in written order and then stop")
	check(s.beats_of("one").size() == 2, "beats are found by chapter")
	check(String(s.beat("job")["id"]) == "job", "...and by id, across chapters")
	check(s.speaker_label("a") == "Ann — Reeve", "a speaker label names the part")
	check(s.speaker_label("ghost") == "ghost", "an unknown speaker still reads as something")

func test_validation_rejects() -> void:
	check(not _bad({"chapters": []}).is_empty(), "a story needs a chapter")
	check(not _bad({"format": "no"}).is_empty(), "the format is checked")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "when": {"flagg": "x"}, "lines": ["x"]}]}]}), "unknown condition"),
		"a mistyped condition is an error, not a beat that never fires")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "lines": ["x"], "then": {"golds": 5}}]}]}), "unknown effect"),
		"...and so is a mistyped effect")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "speaker": "nobody", "lines": ["x"]}]}]}), "not in the cast"),
		"a speaker has to be somebody the story introduced")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "quest", "quest": {"id": "q", "title": "t", "kind": "fetch-me"}}]}]}),
		"quest kind"), "a story may not invent a quest kind the game cannot track")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "quest", "quest": {"id": "q", "title": "t", "kind": "clear_lair"}}]}]}),
		"target_lair_id"), "...or leave its target off")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "quest", "quest": {"id": "q", "title": "t", "kind": "clear_lair",
		 "target_lair_id": "nowhere"}}]}]}), "not on this pack's map"),
		"a quest target is checked against the pack's own map")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "lines": ["x"], "when": {"beat": "ghost"}}]}]}), "no beat"),
		"a beat that waits on a beat nobody wrote is caught")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "lines": ["x"]}, {"id": "b", "kind": "note"}]}]}), "duplicate"),
		"duplicate beat ids are caught")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene"}]}]}), "needs lines or choices"),
		"a scene with nothing in it is not a scene")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "lines": "one line"}]}]}), "must be a list"),
		"...and lines the screen would read as a list must be one")
	check(_has(_bad({"chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "scene", "lines": ["x"], "when": {"region": "the-moon"}}]}]}), "not a region"),
		"regions are checked against the real band list")
	var warn = Story.parse({"format": "sorcmerc-story", "chapters": [{"id": "one", "beats": [
		{"id": "b", "kind": "note", "then": {"items": [{"id": "sword-of-nothing"}]}}]}]})
	warn.check({}, {})
	check(_has_in(warn.warnings, "no item"), "a reward nobody can receive is a warning")

func _bad(src: Dictionary) -> Array:
	var d := {"format": "sorcmerc-story", "version": 1, "title": "T",
		"cast": [{"id": "a", "name": "Ann"}]}
	d.merge(src, true)
	var story = Story.parse(d)
	story.check(_world_ids())
	return story.errors

func _has(errs: Array, needle: String) -> bool:
	return _has_in(errs, needle)

func _has_in(lines: Array, needle: String) -> bool:
	for e in lines:
		if needle in String(e):
			return true
	return false

# --- conditions -------------------------------------------------------------

func test_conditions() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	check(run.holds({}, w, p), "an empty condition is true — 'as soon as the chapter opens'")
	check(not run.holds({"flag": "x"}, w, p), "an unset flag is false")
	run.flags["x"] = true
	check(run.holds({"flag": "x"}, w, p), "...and a set one is true")
	check(run.holds({"not_flag": "y"}, w, p), "not_flag")
	check(run.holds({"all": [{"flag": "x"}, {"not_flag": "y"}]}, w, p), "all")
	check(run.holds({"any": [{"flag": "y"}, {"flag": "x"}]}, w, p), "any")
	check(run.holds({"none": [{"flag": "y"}]}, w, p), "none")
	check(not run.holds({"all": [{"flag": "x"}, {"flag": "y"}]}, w, p), "all is an AND")

	check(run.holds({"near": "hold"}, w, p), "the player starts next to the hold")
	check(not run.holds({"near": "warren"}, w, p), "...and nowhere near the warren")
	check(run.holds({"near": "warren", "within": 500}, w, p), "within widens the reach")
	w.player().position = Vector2(395, 0)
	check(run.holds({"near": "warren"}, w, p), "near works on lairs too, not just settlements")
	w.player().position = Vector2(10, 0)

	check(not run.holds({"visited": "hold"}, w, p), "nowhere is visited yet")
	w.settlements[0].last_visited = 10.0
	check(run.holds({"visited": "hold"}, w, p), "...until it is")
	check(not run.holds({"lair_cleared": "warren"}, w, p), "the warren stands")
	w.lairs[0].looted = true
	check(run.holds({"lair_cleared": "warren"}, w, p), "...until it is looted")
	w.lairs[0].discovered = true
	check(run.holds({"lair_found": "warren"}, w, p), "lair_found reads discovery, not looting")

	p.gold = 300
	check(run.holds({"gold": 250}, w, p) and not run.holds({"gold": 400}, w, p),
		"gold is a floor, not an equality")
	p.stash_add("torch")
	check(run.holds({"has_item": "torch"}, w, p), "has_item reads the shared stash")
	check(run.holds({"party_level": 1}, w, p), "party_level is a floor too")
	check(not run.holds({"party_level": 19}, w, p), "...and the preset party is not level 19")
	check(run.holds({"day": 1}, w, p), "day 1 is the first day")
	check(not run.holds({"day": 4}, w, p), "...and day 4 is not")
	w.clock.elapsed = 3.0 * StoryRuntime.DAY
	check(run.holds({"day": 4}, w, p), "three days of world-clock make it day four")
	check(run.holds({"region": "heartland"}, w, p), "the start is in the heartland")
	check(not run.holds({"region": "deeps"}, w, p), "...which is not the deeps")
	FactionOpinion.reset()
	FactionOpinion.raise("human", 30.0)
	check(run.holds({"opinion": {"faction": "human", "atleast": 20}}, w, p), "opinion floor")
	check(not run.holds({"opinion": {"faction": "human", "atleast": 60}}, w, p), "...both ways")
	FactionOpinion.reset()

	check(run.holds({"chapter": "one"}, w, p), "a beat can ask which chapter it is in")
	check(not run.holds({"beat": "job"}, w, p), "an unfired beat is false")
	run.fired["job"] = true
	check(run.holds({"beat": "job"}, w, p), "...and a fired one is true")

# --- effects ----------------------------------------------------------------

func test_effects() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	p.gold = 1000
	var lines := run.apply({"flags": ["a", "b"], "journal": ["it happened"], "gold": -200,
		"items": [{"id": "torch", "quantity": 2}],
		"opinion": [{"faction": "human", "delta": 5}],
		"reveal_lair": "warren"}, w, p)
	check(run.flags.has("a") and run.flags.has("b"), "flags are set")
	check(p.gold == 800, "gold moves, and a negative number is a price")
	check(p.stash_count("torch") == 2, "items land in the stash")
	check(FactionOpinion.get_opinion("human") == 5.0, "opinion moves")
	check(w.lairs[0].discovered, "a lair can be put on the map by a beat")
	check(lines.size() >= 4, "every one of them reported a line")
	run.apply({"clear_flags": ["a"]}, w, p)
	check(not run.flags.has("a") and run.flags.has("b"), "clear_flags takes one back")
	FactionOpinion.reset()

	run.apply({"spawn_party": {"id": "raiders", "near": "warren", "offset": [10, 0],
		"faction": "bandit", "troops": [{"role": "heavy", "level": 3}]}}, w, p)
	var band = null
	for q in w.parties:
		if q.id == "raiders":
			band = q
	check(band != null, "a beat can put a band on the map")
	check(band != null and band.position == Vector2(410, 0), "...where it said to")
	check(band != null and band.troops.size() == 1, "...with its roster")
	run.apply({"spawn_party": {"id": "raiders", "near": "warren", "faction": "bandit"}}, w, p)
	var n := 0
	for q in w.parties:
		if q.id == "raiders":
			n += 1
	check(n == 1, "spawning the same band twice does not make two of it")

	var before: int = p.party_characters()[0].xp
	run.apply({"xp": 400}, w, p)
	check(p.party_characters()[0].xp > before, "xp is split over the party, through the usual path")

# --- choices ----------------------------------------------------------------

func test_choices() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	var beat: Dictionary = run.story.beat("open")
	p.gold = 100
	check(run.choices_for(beat, w, p).size() == 1,
		"a choice the party cannot afford is not offered")
	p.gold = 900
	check(run.choices_for(beat, w, p).size() == 2, "...and is, once they can")
	run.fire(beat, w, p)
	check(run.fired.has("open"), "firing marks the beat")
	check(not run.flags.has("said-yes"), "firing a scene applies none of its choices")
	run.choose(beat, "yes", w, p)
	check(run.flags.has("said-yes"), "choosing applies that choice, and only it")
	check(not run.flags.has("bought"), "...only it")
	run.choose(beat, "rich", w, p)
	check(p.gold == 400, "the expensive choice charges for itself")
	p.gold = 10
	var none := run.choose(beat, "rich", w, p)
	check(none.is_empty() and p.gold == 10, "a choice whose condition fails does nothing")

# --- chapters ---------------------------------------------------------------

func test_chapters() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	check(run.chapter == "one", "a fresh runtime opens on the first chapter")
	var pend := run.pending(w, p)
	check(pend.size() == 1 and String(pend[0]["id"]) == "open",
		"only the beat whose condition holds is pending")
	run.fire(pend[0], w, p)
	check(run.pending(w, p).is_empty(), "a fired beat is not pending again")
	run.choose(pend[0], "yes", w, p)
	var next := run.pending(w, p)
	check(next.size() == 1 and String(next[0]["id"]) == "job",
		"the choice unlocked the next beat, because the flag is now set")
	run.fire(next[0], w, p)
	run.advance(w, p)
	check(run.chapter == "one", "the chapter does not end while its ends_when is false")
	var q := Quest.get_quest(p, "clear-it")
	q["progress"] = 1
	Quest.turn_in(p, q)
	var lines := run.advance(w, p)
	check(run.chapter == "two", "turning the quest in ends the chapter")
	check(lines.size() >= 1 and "Two" in String(lines[0]), "...and the next one announces itself")
	run.fire(run.pending(w, p)[0], w, p)
	check(run.done, "end_story ends it")
	check(run.pending(w, p).is_empty(), "a finished story has nothing pending")

# --- a chain, on the real quest log ----------------------------------------

func test_quest_chain() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	run.flags["said-yes"] = true
	var beat: Dictionary = run.story.beat("job")
	run.fire(beat, w, p)
	check(p.quests.size() == 1, "a quest beat puts its quest in the party's own log")
	var q := Quest.get_quest(p, "clear-it")
	check(q["state"] == "active", "it is a normal, active quest")
	check(String(q.get("story", "")) == "testpack", "...tagged with the pack that gave it")
	check(Quest.describe(q) != "", "the existing quest log panel can draw it")
	# ...and the existing completion path finishes it, with no story code involved.
	Quest.record_lair_cleared(p, "warren")
	check(Quest.get_quest(p, "clear-it")["state"] == "complete",
		"the game's own lair-cleared hook completes a story quest")
	check(run.holds({"quest": "clear-it", "state": "complete"}, w, p),
		"and the story can see that it did")

# --- persistence ------------------------------------------------------------

func test_save_round_trip() -> void:
	var w = _world()
	var p = _party()
	var run := _run()
	run.fire(run.story.beat("open"), w, p)
	run.choose(run.story.beat("open"), "yes", w, p)
	run.advance(w, p)
	var d := run.to_dict()
	var back := StoryRuntime.new(run.story, d)
	check(back.pack_id == "testpack", "the pack id survives")
	check(back.chapter == run.chapter, "the chapter survives")
	check(back.flags.has("said-yes"), "flags survive")
	check(back.fired.has("open"), "what has already fired survives — a beat cannot repeat")
	check(back.journal.size() == run.journal.size(), "the journal survives")
	check(back.pending(w, p).size() == run.pending(w, p).size(),
		"and it resumes with the same thing pending")

# --- the shipped campaign ---------------------------------------------------

func test_shipped_campaign_plays() -> void:
	var pack = Registry.find("ashen-road")
	check(pack != null and pack.live(), "the shipped campaign is live")
	if pack == null or not pack.live():
		return
	var story = Registry.story_of(pack)
	var w = Registry.world_of(pack)
	var p = _party()
	var run := StoryRuntime.new(story, {}, "ashen-road")
	var opening := run.pending(w, p)
	check(opening.size() >= 1, "chapter one has something to say the moment it starts")
	for b in opening:
		run.fire(b, w, p)
	check(run.flags.is_empty(), "...but the reeve's offer is a choice, so nothing is decided yet")
	var scene: Dictionary = story.beat("the-reeve")
	check(run.fired.has("the-reeve"), "the reeve speaks because the party starts at Emberwatch")
	run.choose(scene, "take", w, p)
	check(run.flags.has("hired"), "taking the work sets the flag the chapter turns on")
	var job := run.pending(w, p)
	var ids: Array = []
	for b in job:
		ids.append(String(b["id"]))
	check(ids.has("warren-work"), "which unlocks the warren job")
	for b in job:
		run.fire(b, w, p)
	check(not Quest.get_quest(p, "ashen-warren").is_empty(), "and the quest is in the log")
	var lair = null
	for l in w.lairs:
		if l.id == "ash-warren":
			lair = l
	check(lair != null and lair.discovered, "the beat marked the warren on the map")
	Quest.record_lair_cleared(p, "ash-warren")
	Quest.turn_in(p, Quest.get_quest(p, "ashen-warren"), "human")
	run.advance(w, p)
	check(run.chapter == "barrow", "clearing it moves the story to chapter two")

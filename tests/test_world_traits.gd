# #176 step 3 on the world screen — a fight's earned personality traits said on
# the after-action page, then shown one hero at a time on the full-screen moment
# (scenes/world/trait_moment.gd) once the page is closed, with the clock held;
# a lapsing trait said on the HUD; a night at an inn mending a wound; a cleared
# lair asking its triumph; and (step 4) where the party is stamped for the
# road's checks, and a trait earned said at the next fire. Drives the real
# world scene. Headless.
#   godot --headless --path . -s tests/test_world_traits.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const RNG = preload("res://core/rng.gd")

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

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for i in 10:
		await process_frame
	var hero = s.party.party_characters()[0]

	# A counted mark is earned outright, so the test does not lean on a roll:
	# the tenth goblin makes a Goblin-bane.
	hero.trait_counts["kill:goblinoid"] = 9
	var result := {"outcome": "Victory", "xp": 10, "gold": 1, "loot": [], "deaths": [], "kills": ["goblin"],
		"downed": [], "rounds": 1, "objective": {},
		"credit": {hero.id: {"kills": ["goblin"], "downed_by": [], "revived_by": []}}}
	s._earn_from_fight(result, "easy", "road")
	check(Traits.has(hero, "bane@goblinoid"), "the fight's result reaches the sheet: %s" % str(Traits.ids(hero)))
	check(s._moment_queue.size() == 1 and String(s._moment_queue[0].get("figure", "")) != "",
		"the moment is queued, with the hero's figure to stand on it")
	check(s._moment == null, "...and waits: nothing opens under a fight's own pages")

	s._show_spoils(result)
	check(labels(s._spoils_panel).any(func(t): return "%s is now Goblin-bane." % hero.cname in t),
		"the after-action page says it: %s" % str(labels(s._spoils_panel).filter(func(t): return "bane" in t)))
	s._process(0.016)
	check(s._moment == null, "the moment waits for the page to be read")
	s._close_spoils()
	s._process(0.016)
	check(s._moment != null and s._moment.remaining() == 1, "...then takes the whole screen")
	check(s.world.clock.is_paused(), "...with the clock held")
	check(String(s._moment.texts()["name"]) == "Goblin-bane", "it names the trait: %s" % s._moment.texts()["name"])
	s._moment._skip_or_advance()
	await process_frame
	check(s._moment == null and s._moment_queue.is_empty(), "a press moves on, and the queue is spent")

	# A lapsing trait goes on its minute, and the HUD says so.
	var now: float = s.world.clock.elapsed
	Traits.grant(hero, "emboldened", "test", now - 3 * Traits.DAY - 1.0)   # its three days are up
	s._process(0.016)
	check(not Traits.has(hero, "emboldened") and "no longer Emboldened" in s._lair_msg.text,
		"Emboldened runs out, on the HUD: %s" % s._lair_msg.text)

	# A night at an inn mends a Wounded hero.
	Traits.grant(hero, "wounded", "test", s.world.clock.elapsed)
	var home = s.world.settlements[0]
	s.party.last_long_rest_at = -1e12
	s.party.gold = 1000
	s._open_visit(home)
	s._goto_page("inn")
	s._rest()
	check(not Traits.has(hero, "wounded"), "a long rest at an inn mends Wounded")
	check("is no longer Wounded" in String(s._visit.get("log", "")), "...and the inn says so: %s" % s._visit.get("log", ""))
	s._close_visit()
	while s._event_card != null:
		s._event_card.acknowledged.emit()
		await process_frame

	# A cleared lair asks its triumph of everyone standing: over enough minutes
	# somebody comes out a Delver or Reckless.
	var got := false
	for i in 40:
		s.world.clock.elapsed += 60.0
		s._earn_from_lair()
		if not s._moment_queue.is_empty():
			got = true
			break
	check(got, "a cleared lair can leave a Delver or a Reckless")
	check(s._trait_news.any(func(t): return "Delver" in t or "Reckless" in t), "...with its line for the page")

	# Step 4: where the party is, stamped for the road's checks every frame.
	s._process(0.016)
	check(s.party.here.has("biome") and s.party.here.get("site") == "road" and s.party.here.has("night"),
		"the map stamps where the party is: %s" % str(s.party.here))
	s._open_visit(home)
	s._process(0.016)
	check(s.party.here.get("site") == "town", "...a town while visiting it")
	s._close_visit()
	while s._event_card != null:
		s._event_card.acknowledged.emit()
		await process_frame
	# ...and a trait earned since the last fire is said at the next one.
	Traits.grant(hero, "burn-shy", "test", s.world.clock.elapsed)
	# A calling's telling outranks it (one card a night), so ask a few nights.
	var heard := ""
	for night in 6:
		if not s._fireside(RNG.new(3 + night), func(): pass):
			continue
		heard = String(s._event_card._e.get("text", "")) if s._event_card != null else ""
		for _k in 20:
			if s._event_card == null:
				break
			s._event_card.acknowledged.emit()
			await process_frame
		if s._approach_card != null:
			s._close_approach()
		if "sits well back from the fire" in heard:
			break
	check("%s sits well back from the fire tonight" % hero.cname in heard, "the fire says the burn: %s" % heard)
	print("test_world_traits: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

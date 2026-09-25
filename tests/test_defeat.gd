# core/defeat.gd: what a lost open-world fight costs past the purse (the design
# audit §1.8 — a day walked by the world, and a wound roll for the downed), and
# the end of a company whose whole roster died (the owner's call, 2026-09-25):
# the record, its words, the barracks, and the save marked finished — an old
# save, with no such mark, is not finished.
#   godot --headless --path . -s tests/test_defeat.gd
extends SceneTree

const Defeat = preload("res://core/defeat.gd")
const Party = preload("res://core/party.gd")
const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Traits = preload("res://core/traits.gd")
const Ladder = preload("res://core/ladder.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_finished()
	test_lose_time()
	test_injure()
	test_ending_and_words()
	test_barracks()
	test_save_flag()
	print("test_defeat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _party() -> Party:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(40, 40), "human", true))
	return w

func test_finished() -> void:
	var p := _party()
	check(not Defeat.finished(p), "a living company is not finished")
	for ch in p.roster.slice(1):
		ch.dead = true
	check(not Defeat.finished(p), "...nor one with a single hero left")
	p.roster[0].dead = true
	check(Defeat.finished(p), "the whole roster dead: finished")
	check(not Defeat.finished(Party.new()), "an empty roster is a company not yet founded, not a dead one")

# A day passes the proper way: through WorldRest.pass_time, so a band walks.
func test_lose_time() -> void:
	var w := _world()
	var band = w.add_party(World.RoamingParty.new("walker", Vector2(300, 0), "bandit"))
	w.set_goal(band, Vector2(-300, 0))
	var from: Vector2 = band.position
	var p := _party()
	var t0: float = w.clock.elapsed
	var stepped := [0]
	Defeat.lose_time(w, p, func(_dt): stepped[0] += 1)
	check(is_equal_approx(w.clock.elapsed - t0, Defeat.DAYS_LOST * Defeat.DAY),
		"the company comes to %d day later (%.0f minutes)" % [Defeat.DAYS_LOST, w.clock.elapsed - t0])
	check(stepped[0] >= int(Defeat.DAYS_LOST * Defeat.DAY), "...stepped a minute at a time, with the map's hook (%d steps)" % stepped[0])
	check(band.position != from, "...and the world walked through it: the band moved")
	check(is_equal_approx(p.world_now, w.clock.elapsed), "...and the party's clock is stamped")
	check(p.last_long_rest_at < 0.0, "it is not a rest: the long-rest stamp does not move")

func test_injure() -> void:
	var p := _party()
	var ids: Array = p.active.duplicate()
	var dead_one = p.get_member(ids[-1])
	dead_one.dead = true
	var r: Dictionary = Defeat.injure(p, ids, 5000.0)
	check(r["lines"].size() == ids.size() - 1, "every downed hero still alive rolls once; the dead do not (%d lines)" % r["lines"].size())
	check(r["lines"].all(func(l): return String(l).contains("CON")), "...a CON save each, named in the line")
	var hurt: int = 0
	for id in ids.slice(0, ids.size() - 1):
		var ch = p.get_member(id)
		if Traits.has(ch, "wounded") or Traits.has(ch, "maimed"):
			hurt += 1
	check(hurt == r["moments"].size(), "a wound for each failed save, each with its moment (%d)" % hurt)
	# seeded: the same heroes at the same minute roll the same
	var q := _party()
	var r2: Dictionary = Defeat.injure(q, q.active.slice(0, q.active.size() - 1), 5000.0)
	check(r2["lines"] == r["lines"], "seeded off the hero and the minute: a reload cannot reroll it")
	# over enough minutes, both outcomes happen, and the wounds are the existing rows
	var made := 0
	var wounded := 0
	for m in range(0, 200):
		var t := _party()
		var one = t.get_member(t.active[0])
		var rr: Dictionary = Defeat.injure(t, [one.id], float(m * 1440))
		if Traits.has(one, "wounded") or Traits.has(one, "maimed"):
			wounded += 1
			var tr: Dictionary = one.traits.filter(func(x): return x is Dictionary and String(x.get("id", "")) in ["wounded", "maimed"])[0]
			check(String(tr["why"]) == Traits.DEFEAT_WHY and tr.has("until"), "a defeat's wound says why, and lapses")
		else:
			made += 1
	check(made > 0 and wounded > 0, "some walk it off, some do not (%d / %d)" % [made, wounded])

func test_ending_and_words() -> void:
	Ladder.reset()
	var p := _party()
	var w := _world()
	w.clock.elapsed = 3.5 * Defeat.DAY
	for ch in p.roster:
		ch.dead = true
	var last := [p.roster[0].id, p.roster[1].id]
	var e: Dictionary = Defeat.ending(p, w, last)
	check(int(e["days"]) == 4, "on the fourth day (%d)" % int(e["days"]))
	check(String(e["title"]) == Ladder.TITLES[0], "...as Nobodies, with no deeds done")
	check(e["fell"] == [p.roster[0].cname, p.roster[1].cname], "the last to fall, by name")
	check(e["roll"].size() == p.roster.size() and e["roll"].all(func(r): return bool(r["dead"])), "the roll: everyone who marched")
	check(JSON.parse_string(JSON.stringify(e)) is Dictionary, "plain data: it survives a save")
	var words: Dictionary = Defeat.end_lines(e)
	check(String(words["head"]) == "The company is finished", "the head: %s" % words["head"])
	check(String(words["lead"]).contains(p.roster[1].cname) and String(words["lead"]).contains("last of them to fall"),
		"the lead names the fallen: %s" % words["lead"])
	check(String(words["lasted"]).contains("4 days") and String(words["lasted"]).contains("Nobodies"),
		"days and title: %s" % words["lasted"])
	check(words["roll"].size() == p.roster.size() and String(words["roll"][0]).contains("dead"), "one roll line each: %s" % words["roll"][0])
	for line in [words["lead"], words["lasted"]] + words["roll"]:
		check(not String(line).contains("!") and not String(line).contains("n't"), "house voice, no shouting or contractions: %s" % line)
	print("  ", words["lead"], "  ", words["lasted"])

func test_barracks() -> void:
	var p := _party()
	for ch in p.roster:
		CharacterSave.save(ch)
	var living = p.roster[0]
	for ch in p.roster.slice(1):
		ch.dead = true
	var home: int = Defeat.to_barracks(p)
	check(home == 1 and CharacterSave.exists(living.id), "the living go home to the barracks")
	check(p.roster.slice(1).all(func(ch): return not CharacterSave.exists(ch.id)), "the dead do not, and their old files are taken out")
	CharacterSave.delete(living.id)

func test_save_flag() -> void:
	var p := _party()
	var w := _world()
	var d: Dictionary = WorldSave.to_dict(w, p)
	check(d.has("finished") and (d["finished"] as Dictionary).is_empty(), "a run still going saves no record")
	var back = WorldSave.from_dict(d)
	check(back["party"].finished.is_empty(), "...and loads as not finished")
	d.erase("finished")
	check(WorldSave.from_dict(d)["party"].finished.is_empty(), "an old save with no key is not finished")
	check((WorldSave._facts(d, 0)["finished"] as Dictionary).is_empty(), "...and its slot reads as playable")
	for ch in p.roster:
		ch.dead = true
	p.finished = Defeat.ending(p, w, [])
	var d2: Dictionary = JSON.parse_string(JSON.stringify(WorldSave.to_dict(w, p)))
	var back2 = WorldSave.from_dict(d2)
	check(not back2["party"].finished.is_empty() and int(back2["party"].finished["days"]) == 1,
		"a finished company's record survives a save round trip")
	check(not (WorldSave._facts(d2, 0)["finished"] as Dictionary).is_empty(), "...and its slot reads as finished, for the title screen")

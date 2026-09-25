# The fallen (core/fallen.gd; the design audit, docs/audit-game-design.md
# §2.1): the one door the open world applies a death through. A death is
# marked and benched, counted toward the deaths achievement, written on the
# roll of the fallen, grieved — guaranteed, and harder for a lover — by
# whoever was close to the dead, the bench included, and felt in the
# relations web; the fire speaks of each of the dead once; and the roll
# survives a save, an old save reading as an empty one. Headless.
#   godot --headless --path . -s tests/test_fallen.gd
extends SceneTree

const Fallen = preload("res://core/fallen.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Traits = preload("res://core/traits.gd")
const Ach = preload("res://core/achievements.gd")
const WorldSave = preload("res://core/world_save.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Campaign = preload("res://core/campaign.gd")

const NOW := 1440.0 * 5 + 100.0   # day 6

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/fallen-%d-%d" % [OS.get_process_id(), randi()])
	test_apply()
	test_grief_is_guaranteed_and_harder()
	test_two_deaths()
	test_after_fight_spares_the_grieving()
	test_camp_beat()
	test_save()
	print("test_fallen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

# Vera, Pike and Ilsa marching (the presets), Thrun marching too, Bran on the
# bench. Pike loves Vera, Ilsa is bonded to her, and so is Bran from the bench;
# Thrun is nobody's in particular.
func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	for id in ["thrun", "bran"]:
		var ch = Presets.vera()
		ch.id = id
		ch.cname = id.capitalize()
		p.add_member(ch)
	p.bench("bran")
	PartyOpinion.set_score(p, "vera", "pike", 70.0)
	PartyOpinion.answer_courtship(p, "vera", "pike", true)
	PartyOpinion.set_score(p, "vera", "ilsa", 55.0)
	PartyOpinion.set_score(p, "vera", "bran", 60.0)
	PartyOpinion.set_score(p, "vera", "thrun", 0.0)
	for pair in [["pike", "ilsa"], ["pike", "bran"], ["ilsa", "bran"], ["pike", "thrun"], ["ilsa", "thrun"], ["bran", "thrun"]]:
		PartyOpinion.set_score(p, pair[0], pair[1], 0.0)
	return p

func _died(ids: Array, by := "ogre") -> Dictionary:
	var credit := {}
	for id in ids:
		credit[id] = {"kills": [], "downed_by": [{"dtype": "bludgeoning", "team": "foe", "by": by}], "revived_by": []}
	return {"outcome": "Defeat", "deaths": ids, "credit": credit, "kills": []}

func _mentions(lines: Array, name: String) -> Array:
	return lines.filter(func(l): return String(l).begins_with(name + " "))

func test_apply() -> void:
	var p := _party()
	var deaths0 := Ach.count("deaths")
	var out := Fallen.apply(p, _died(["vera"]), {"now": NOW, "where": "on the road near Riverhold"})
	var vera = p.get_member("vera")
	check(vera.dead and not p.is_active("vera"), "the dead are marked and benched")
	check(Ach.count("deaths") == deaths0 + 1, "...and counted toward The Cost of Doing Business, out in the open world (%d)" % Ach.count("deaths"))
	var roll: Array = Fallen.roll(p)
	check(roll.size() == 1, "one name on the roll")
	var e: Dictionary = roll[0] if not roll.is_empty() else {}
	check(e.get("id") == "vera" and e.get("name") == "Vera Kord" and int(e.get("level", 0)) == vera.level()
		and e.get("class") == "fighter" and e.get("by") == "ogre" and int(e.get("day", 0)) == 6
		and e.get("where") == "on the road near Riverhold" and not bool(e.get("told", true)),
		"who, what level and class, where, to what, and the world-day: %s" % str(e))
	check(Fallen.line(e) == "Vera Kord, fighter %d. Fell to an ogre on the road near Riverhold, on day 6." % vera.level(),
		"the wall's line: %s" % Fallen.line(e))
	# grief: every close one, the bench included, and nobody else
	for name in ["Pike", "Ilsa", "Bran"]:
		check(_mentions(out["lines"], name).size() >= 1, "%s grieves (%s)" % [name, str(out["lines"])])
	check(_mentions(out["lines"], "Thrun").is_empty(), "Thrun was not close to her, and does not")
	# the lover's save is the harder one: the ogre's DC (10 + CR 2 / 2) plus two, or four for a lover
	var ogre_dc := 10 + 1
	check(_mentions(out["lines"], "Pike").any(func(l): return "vs DC %d)" % (ogre_dc + Traits.GRIEF_LOVER) in String(l)),
		"a lover's grief is DC %d: %s" % [ogre_dc + Traits.GRIEF_LOVER, str(_mentions(out["lines"], "Pike"))])
	check(_mentions(out["lines"], "Ilsa").any(func(l): return "vs DC %d)" % (ogre_dc + Traits.GRIEF_BONDED) in String(l)),
		"a friend's is DC %d" % (ogre_dc + Traits.GRIEF_BONDED))
	check(out["moments"].all(func(m): return String(m.get("event", "")) == "Lost Vera Kord"), "each moment says who they lost")
	# the relations web: the three who lost her draw together, and hold it
	# against Thrun, who walked away from the fight she did not
	check(PartyOpinion.score(p, "pike", "ilsa") == PartyOpinion.SHARED_GRIEF, "Pike and Ilsa lost the same person (+%d)" % int(PartyOpinion.SHARED_GRIEF))
	check(PartyOpinion.score(p, "ilsa", "bran") == PartyOpinion.SHARED_GRIEF, "...and so did Bran, from the bench")
	check(PartyOpinion.score(p, "pike", "thrun") == -PartyOpinion.SURVIVOR_BLAME_LOVER, "her lover holds it against Thrun (%d)" % int(PartyOpinion.score(p, "pike", "thrun")))
	check(PartyOpinion.score(p, "ilsa", "thrun") == -PartyOpinion.SURVIVOR_BLAME, "...a friend, less")
	check(PartyOpinion.score(p, "bran", "thrun") == -PartyOpinion.SURVIVOR_BLAME, "...and the bench blames whoever marched")
	check(PartyOpinion.status(p, "vera", "pike") == "lovers", "the pair with the dead is kept: a raise gives it back")
	# the road's defeat applies the fight's deaths twice: the second changes nothing
	var again := Fallen.apply(p, _died(["vera"]), {"now": NOW, "where": "on the road near Riverhold"})
	check(Fallen.roll(p).size() == 1 and Ach.count("deaths") == deaths0 + 1 and again["lines"].is_empty(),
		"a second call on the same fight changes nothing")
	check(PartyOpinion.score(p, "pike", "thrun") == -PartyOpinion.SURVIVOR_BLAME_LOVER, "...not even the web")
	# raised since: still on the roll, marked
	vera.dead = false
	check(Fallen.line(e, p).ends_with("Raised since."), "a hero raised since is still on the roll, marked: %s" % Fallen.line(e, p))
	check(Fallen.line({"id": "x", "name": "X", "class": "rogue", "level": 2, "day": 3, "by": "pike", "where": ""}, p)
		== "X, rogue 2. Fell to Pike Sallow, on day 3.", "friendly fire names the hero; no place, no place")

func test_grief_is_guaranteed_and_harder() -> void:
	var asked := 0
	var hardened := 0
	var grieving := 0
	var n := 60
	for i in n:
		var p := _party()
		var out := Fallen.apply(p, _died(["vera"]), {"now": NOW + i * 37.0})
		if _mentions(out["lines"], "Pike").size() >= 1:
			asked += 1
		var pike = p.get_member("pike")
		if Traits.has(pike, "hardened"):
			hardened += 1
		if Traits.has(pike, "grieving"):
			grieving += 1
			check(Traits.entry(pike, "grieving").has("until"), "Grieving lapses")
	check(asked == n, "grief is asked every time, never on chance (%d of %d)" % [asked, n])
	check(grieving > hardened, "at DC 15 a lover grieves more often than they harden (%d / %d)" % [grieving, hardened])
	check(grieving > 0 and hardened > 0, "...and both happen")

func test_two_deaths() -> void:
	var p := _party()
	var out := Fallen.apply(p, _died(["vera", "pike"]), {"now": NOW})
	check(Fallen.roll(p).size() == 2, "two names on the roll")
	check(_mentions(out["lines"], "Pike").is_empty() and _mentions(out["lines"], "Vera").is_empty(),
		"the two who died together do not grieve each other")
	check(_mentions(out["lines"], "Ilsa").size() >= 1, "the living still grieve")

# The fight's own hardships: whoever grieves through Fallen is not asked the
# witness's fifty-fifty on top.
func test_after_fight_spares_the_grieving() -> void:
	var p := _party()
	var r := _died(["vera"])
	r["outcome"] = "Victory"
	var asked := {"Pike": 0, "Ilsa": 0, "Thrun": 0}
	for i in 200:
		var q := _party()   # fresh each time: nobody hardened or shaken yet
		var out: Dictionary = Traits.after_fight(q.party_characters(), r, {"now": float(i * 13), "grieving": ["pike", "ilsa"]})
		for name in asked:
			var hit: bool = out["lines"].any(func(l): return String(l).begins_with(name + " ") and ("vs DC" in String(l)))
			asked[name] += 1 if hit else 0
	check(asked["Pike"] == 0 and asked["Ilsa"] == 0, "a grieving hero is not asked the witness's save (%s)" % str(asked))
	check(asked["Thrun"] > 60, "...while everyone else still is, half the time (%d of 200)" % asked["Thrun"])

func test_camp_beat() -> void:
	var p := _party()
	check(Fallen.camp_beat(p, NOW).is_empty(), "nobody dead: the fire has nothing to say about it")
	Fallen.apply(p, _died(["vera"]), {"now": NOW})
	check(Fallen.camp_beat(p, NOW - 10.0).is_empty(), "a fire before the death does not speak of it")
	var b := Fallen.camp_beat(p, NOW + 600.0)
	var mourner = p.get_member(String(b.get("char_id", "")))
	check(String(b.get("text", "")).contains("Vera Kord") and String(b.get("char_id", "")) in ["pike", "ilsa"]
		and mourner != null and String(b["text"]).begins_with(mourner.cname),
		"the first fire after: a mourner at the fire says her name: %s" % str(b))
	check(String(b.get("kind", "")) == "bad", "...as a hard beat")
	check(Fallen.camp_beat(p, NOW + 2000.0).is_empty(), "once, and never again")
	var b2 := Fallen.camp_beat(_party(), NOW)
	check(b2.is_empty(), "a fresh company has no dead")
	# nobody at the fire was close to them: the company says it
	var q := _party()
	for id in ["pike", "ilsa"]:
		q.bench(id)
	Fallen.apply(q, _died(["vera"]), {"now": NOW})
	var c := Fallen.camp_beat(q, NOW + 60.0)
	check(String(c.get("char_id", "x")) == "" and String(c.get("text", "")).contains("Vera Kord"), "no mourner at the fire: the company's line: %s" % str(c))
	# the same death gives the same line (seeded off the dead and the minute)
	var r1 := _party()
	var r2 := _party()
	Fallen.apply(r1, _died(["vera"]), {"now": NOW})
	Fallen.apply(r2, _died(["vera"]), {"now": NOW})
	check(Fallen.camp_beat(r1, NOW + 1.0) == Fallen.camp_beat(r2, NOW + 1.0), "a reload says the same line")
	# raised before the fire: no line, and nothing left to say
	var s := _party()
	Fallen.apply(s, _died(["vera"]), {"now": NOW})
	s.get_member("vera").dead = false
	check(Fallen.camp_beat(s, NOW + 1.0).is_empty() and bool(Fallen.roll(s)[0]["told"]), "raised before the fire: nothing to mourn")

func test_save() -> void:
	var p := _party()
	Fallen.apply(p, _died(["vera"]), {"now": NOW, "where": "in The Vale Warren"})
	var back = JSON.parse_string(JSON.stringify(Fallen.to_dict(p)))
	var q := Party.new()
	Fallen.from_dict(q, back)
	check(q.fallen.size() == 1 and q.fallen[0]["level"] is int and q.fallen[0]["day"] is int
		and Fallen.line(q.fallen[0]) == Fallen.line(p.fallen[0]), "the roll round-trips through JSON: %s" % Fallen.line(q.fallen[0]))
	Fallen.from_dict(q, null)
	check(q.fallen.is_empty(), "a missing roll is an empty one")
	Fallen.from_dict(q, [{"name": "no id"}, "junk"])
	check(q.fallen.is_empty(), "an entry with no id is dropped")
	# through the world save, and a world save from before the roll
	var d: Dictionary = WorldSave._party_dict(p)
	check(d.has("fallen") and d["fallen"].size() == 1, "the world save writes party.fallen")
	var wp = WorldSave._party_from(JSON.parse_string(JSON.stringify(d)))
	check(wp.fallen.size() == 1 and String(wp.fallen[0]["where"]) == "in The Vale Warren", "...and reads it back")
	d.erase("fallen")
	check(WorldSave._party_from(d).fallen.is_empty(), "a world save from before the roll loads with nobody on it")
	# and the linear campaign's save, which carries the same party
	var run := Campaign.new(p, 1)
	var cd: Dictionary = JSON.parse_string(JSON.stringify(CampaignSave.to_dict(run)))
	check(cd["party"].has("fallen") and CampaignSave.from_dict(cd).party.fallen.size() == 1, "the campaign save carries it too")
	cd["party"].erase("fallen")
	check(CampaignSave.from_dict(cd).party.fallen.is_empty(), "...and an old one reads as empty")

# The service record (core/service.gd; the design audit,
# docs/audit-game-design.md §2.2 and §2.5): what a merc has done, read back —
# the counts core/traits.gd keeps, progress toward a bane and Veteran off the
# very constants and caps the trait rules earn them by, an earned trait's
# reason and day, the inn's line for a veteran, and who struck the blow on
# the spoils page. Headless.
#   godot --headless --path . -s tests/test_service.gd
extends SceneTree

const Service = preload("res://core/service.gd")
const Traits = preload("res://core/traits.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const CharacterSave = preload("res://core/character_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_record()
	test_progress_reads_the_rules()
	test_progress_meets_the_rules()
	test_origin_line()
	test_kill_lines()
	test_veteran_line_and_enlist()
	print("test_service: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _hero(id := "vera"):
	var ch = Presets.vera()
	ch.id = id
	ch.traits = []
	ch.trait_counts = {}
	return ch

func test_record() -> void:
	var ch = _hero()
	ch.trait_counts = {"fights": 30, "wins": 25, "kill:goblinoid": 14, "kill:orc": 3, "downed:orc": 2, "downed:beast": 1, "runs": 2}
	ch.traits.append({"id": "burn-shy", "why": "Went down in the fire", "since": 900.0})
	ch.traits.append({"id": "wounded", "why": "x", "since": 10.0})
	var r := Service.record(ch)
	check(r["fights"] == 30 and r["wins"] == 25 and r["downs"] == 3 and r["kills_total"] == 17 and r["runs"] == 2,
		"the counts: %s" % str(r))
	check(r["kills"] == {"goblinoid": 14, "orc": 3}, "kills by faction")
	check(r["scars"] == 1, "a scar counts; a wound that heals does not")
	check(Service.kill_order(ch) == ["goblinoid", "orc"], "most killed first")
	# a hero from before fights were counted
	ch.trait_counts = {"wins": 12}
	check(Service.record(ch)["fights"] == 12, "fights never reads below wins")
	check(Service.record(_hero())["fights"] == 0 and Service.record(_hero())["kills"].is_empty(), "a fresh hero has done nothing yet")
	# after_fight counts every fight each of them was in, the dead included
	var a = _hero("a")
	var b = _hero("b")
	Traits.after_fight([a, b], {"outcome": "Defeat", "deaths": ["b"], "credit": {}, "kills": []}, {"now": 0.0})
	check(int(a.trait_counts.get("fights", 0)) == 1 and int(b.trait_counts.get("fights", 0)) == 1, "a fight is counted for all who were in it")
	check(int(a.trait_counts.get("wins", 0)) == 0, "...a loss is not a win")
	# and the count travels with the hero
	var back = CharacterSave.from_dict(JSON.parse_string(JSON.stringify(CharacterSave.to_dict(a))))
	check(int(back.trait_counts.get("fights", 0)) == 1, "the fights count survives the barracks file")

func test_progress_reads_the_rules() -> void:
	var ch = _hero()
	ch.trait_counts = {"kill:goblinoid": 7, "kill:dragon": 1, "wins": 12}
	var p := Service.progress(ch)
	var gob: Dictionary = p["banes"][0]
	check(gob["faction"] == "goblinoid" and gob["kills"] == 7 and gob["need"] == Traits.BANE_KILLS and not gob["held"] and gob["room"] == "",
		"7 of the rules' %d goblins toward Goblin-bane: %s" % [Traits.BANE_KILLS, str(gob)])
	check(gob["name"] == "Goblin-bane", "...named as the trait is")
	var dragon: Dictionary = p["banes"][1]
	check(dragon["need"] == Traits.BANE_KILLS_DRAGON, "a dragon bane needs the rules' %d" % Traits.BANE_KILLS_DRAGON)
	check(p["veteran"]["wins"] == 12 and p["veteran"]["need"] == Traits.VETERAN_WINS and not p["veteran"]["held"], "12 of %d wins toward Veteran" % Traits.VETERAN_WINS)
	# the caps grant() obeys, said in words
	ch.traits.append({"id": "bane@orc", "why": "t"})
	ch.traits.append({"id": "bane@beast", "why": "t"})
	p = Service.progress(ch)
	check(String(p["banes"][0]["room"]) != "" and "bane" in String(p["banes"][0]["room"]),
		"two banes held: a third is blocked, and the panel says why (%s)" % p["banes"][0]["room"])
	check(Traits.refusal(ch, "bane@goblinoid") == String(p["banes"][0]["room"]), "...the same reason grant() has")
	var full = _hero()
	for t in ["emboldened", "renowned", "delver", "protector"]:
		full.traits.append({"id": t, "why": "t"})
	full.trait_counts = {"wins": 25}
	check(String(Service.progress(full)["veteran"]["room"]) != "", "four triumphs: Veteran is blocked too (%s)" % Service.progress(full)["veteran"]["room"])
	var vet = _hero()
	vet.traits.append({"id": "veteran", "why": "t"})
	check(Service.progress(vet)["veteran"]["held"], "a held Veteran reads as held")

# What the panel says is due, the rules give: a hero whose count meets the
# need with room earns the mark at the very next kill or win.
func test_progress_meets_the_rules() -> void:
	var ch = _hero()
	ch.trait_counts = {"kill:goblinoid": Traits.BANE_KILLS - 1, "wins": Traits.VETERAN_WINS - 1}
	var p := Service.progress(ch)
	check(p["banes"][0]["kills"] < p["banes"][0]["need"] and p["banes"][0]["room"] == "", "one short of a bane, room for it")
	Traits.after_fight([ch], {"outcome": "Victory", "deaths": [], "kills": ["goblin"],
		"credit": {"vera": {"kills": ["goblin"], "downed_by": [], "revived_by": []}}}, {"now": 100.0})
	p = Service.progress(ch)
	check(p["banes"][0]["held"] and Traits.has(ch, "bane@goblinoid"), "the next goblin makes the bane the panel counted toward")
	check(p["veteran"]["wins"] == Traits.VETERAN_WINS and not p["veteran"]["held"],
		"the win that met Veteran's count came with a bane, so Veteran is due (one mark a fight)")
	Traits.after_fight([ch], {"outcome": "Victory", "deaths": [], "kills": [], "credit": {}}, {"now": 200.0})
	check(Service.progress(ch)["veteran"]["held"], "...and comes with the next win")

func test_origin_line() -> void:
	var ch = _hero()
	Traits.set_family(ch, "temperament", "brave", "born to it")
	check(Service.origin_line(ch, "brave") == "", "a trait they were born with has no origin line")
	var t := Traits.grant(ch, "bane@goblinoid", "10 goblins killed", 1440.0 * 3 + 5.0)
	check(not t.is_empty(), "granted")
	check(Service.origin_line(ch, "bane@goblinoid") == "Earned on day 4: 10 goblins killed.",
		"an earned one says why and on which day: %s" % Service.origin_line(ch, "bane@goblinoid"))
	Traits.grant(ch, "hardened", "Lost Pike Sallow", 20.0)
	check(Service.origin_line(ch, "hardened") == "Earned on day 1: lost Pike Sallow.", "...its reason as the trait stored it")
	check(Service.origin_line(ch, "craven") == "", "a trait not held says nothing")

func test_kill_lines() -> void:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	var result := {"kills": ["goblin", "goblin", "goblin-boss", "goblin", "wolf"],
		"credit": {"vera": {"kills": ["goblin", "goblin", "goblin-boss"]}, "pike": {"kills": ["goblin"]}}}
	var lines := Service.kill_lines(result, p)
	check(lines.size() == 3, "one line per kind: %s" % str(lines))
	check(lines[0]["id"] == "goblin" and lines[0]["count"] == 3 and lines[0]["by"] == "Vera Kord ×2, Pike Sallow",
		"who struck the blow, with a count on a repeat: %s" % str(lines[0]))
	check(lines[1]["by"] == "Vera Kord", "the boss's killer: %s" % str(lines[1]))
	check(lines[2]["id"] == "wolf" and lines[2]["by"] == "", "a kill nobody is credited with names nobody")
	check(lines[0]["xp"] == int(load("res://core/rules/catalog.gd").monster("goblin").get("xp", 0)) * 3, "...and what they were worth")
	check(Service.kill_lines({"kills": []}, p).is_empty(), "no kills, no lines")

func test_veteran_line_and_enlist() -> void:
	var ch = _hero()
	check(Service.veteran_line(ch) == "One company before this one: 0 fights, 0 kills, no scars.", "an uncounted veteran served one run")
	check(Service.enlist(ch) == 1 and Service.enlist(ch) == 2, "each company joined is one more run")
	ch.trait_counts.merge({"fights": 1, "kill:orc": 1})
	check(Service.veteran_line(ch) == "Two companies before this one: 1 fight, 1 kill, no scars.", "singulars: %s" % Service.veteran_line(ch))

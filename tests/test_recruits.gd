# core/recruits.gd — the inns' hiring pools, the hire itself, and the settle-in
# page that finishes one. The model headless, plus the two screens the rule
# changes (the settle-in page, the party screen's Create new).
#   godot --headless --path . -s tests/test_recruits.gd
extends SceneTree

const Recruits = preload("res://core/recruits.gd")
const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")
const Ladder = preload("res://core/ladder.gd")
const Prog = preload("res://core/progression.gd")
const Leveling = preload("res://core/leveling.gd")
const Traits = preload("res://core/traits.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const ChoicePick = preload("res://core/rules/choice_pick.gd")
const CharacterSave = preload("res://core/character_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The player's half of a hire, made the way a player in a hurry makes it: the
# first legal option for every open choice.
static func _finish(ch) -> void:
	for _i in 60:
		var pend: Array = ch.sheet().pending
		if pend.is_empty():
			return
		var p: Dictionary = pend[0]
		var picks: Array = []
		var opts := ChoicePick.options_for(p, ch.sheet())
		var i := 0
		while picks.size() < ChoicePick.pick_count(p) and i < opts.size() * 3 and not opts.is_empty():
			picks = ChoicePick.toggle(p, picks, opts[i % opts.size()]["id"])
			i += 1
		ch.decide(p["key"], ChoicePick.decision_for(p, picks))

func _by_id(w, id: String):
	for s in w.settlements:
		if s.id == id:
			return s
	return null

func _hero(id: String, level := 1):
	var ch = Presets.vera(level)
	ch.id = id
	return ch

func _init() -> void:
	OS.set_environment("SORCMERC_PLAYTEST", "")   # the real unlock gates, not the friends-and-family build
	Ladder.reset()
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var w: World = scene._small_world()
	scene.free()
	var party = Party.new()
	party.add_member(_hero("founder"))
	var city = _by_id(w, "riverhold")
	var town = _by_id(w, "greenmarch")
	var camp = _by_id(w, "dun-arrow")

	# --- the rule, and grandfathering ------------------------------------------
	var old = Party.new()
	check(not Recruits.hire_only(old), "a party with no hiring key keeps the old rule")
	Recruits.found(old)
	check(Recruits.hire_only(old), "a new run hires")
	check(old.gold == Recruits.FOUNDING_PURSE, "the founding purse is set (%d)" % old.gold)
	var loaded = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(w, Party.new()))))["party"]
	check(not Recruits.hire_only(loaded), "an old save round-trips as grandfathered")

	# --- the pool: seeded off the settlement and the day ------------------------
	w.clock.elapsed = 100.0
	var a: Array = Recruits.offers(city, w, party)
	var b: Array = Recruits.offers(city, w, party)
	check(a.size() == 3 and Recruits.offers(town, w, party).size() == 2 and Recruits.offers(camp, w, party).size() == 1,
		"three chairs in a city, two in a town, one at a camp")
	check(a.map(func(o): return o["seed"]) == b.map(func(o): return o["seed"]), "same settlement, same day: same pool")
	var ca = Recruits.build(a[1])
	var cb = Recruits.build(b[1])
	check(ca.cname == cb.cname and ca.class_id() == cb.class_id() and ca.species_id == cb.species_id
		and ca.base_abilities == cb.base_abilities and ca.choices == cb.choices and Array(ca.equipped) == Array(cb.equipped),
		"...and the same people, down to the picks (%s / %s)" % [ca.cname, cb.cname])
	ca.decide("probe:class:x:0", {"type": "probe"})
	check(not Recruits.build(a[1]).choices.has("probe:class:x:0"), "build() hands out a fresh copy each time")
	w.clock.elapsed = 100.0 + Recruits.PERIOD * 0.9
	check(Recruits.offers(city, w, party).map(func(o): return o["seed"]) == a.map(func(o): return o["seed"]),
		"later the same day: still the same pool")
	w.clock.elapsed = 100.0 + Recruits.PERIOD
	var tomorrow: Array = Recruits.offers(city, w, party)
	check(tomorrow.map(func(o): return o["seed"]) != a.map(func(o): return o["seed"]), "the next day: a new pool")
	check(Recruits.offers(town, w, party).map(func(o): return o["seed"]) != tomorrow.map(func(o): return o["seed"]).slice(0, 2),
		"a different town: different faces")

	# --- the level: the band's, less one -----------------------------------------
	var here := Regions.level_here(w, city.position, party)
	check(int(a[0]["level"]) == maxi(1, here - 1), "a recruit is the country's level less one, floored at 1 (%d)" % int(a[0]["level"]))
	var big = Party.new()
	big.add_member(_hero("big", 3))
	check(Recruits.level_for(w, city, big) == maxi(1, Regions.level_here(w, city.position, big) - 1),
		"...and moves with the party inside the band")
	check(Recruits.fee(1) == 50 and Recruits.fee(3) == 150, "the fee is 50 a level at Nobodies")

	# --- who they are: everything fixed but the player's choices ----------------
	var seen_pending := {}
	for i in 60:
		var lvl := 1 + i % 6
		var ch = Recruits.build({"seed": absi(hash("probe|%d" % i)) + 1, "level": lvl, "veteran": ""})
		var tag := "%s (%s %s %d)" % [ch.cname, ch.species_id, ch.class_id(), ch.level()]
		check(ch.level() == lvl, "%s: at the offered level" % tag)
		var arr: Array = ch.base_abilities.values()
		arr.sort()
		var std: Array = ChoicePick.STANDARD_ARRAY.duplicate()
		std.sort()
		check(arr == std and ChoicePick.point_buy_cost(ch.base_abilities) <= ChoicePick.PB_BUDGET,
			"%s: the standard array, inside the creator's budget" % tag)
		check(Prog.is_species_unlocked(ch.species_id) and Prog.is_class_unlocked(ch.class_id()),
			"%s: an unlocked species and class" % tag)
		check(ch.background_id != "" and Traits.of(ch, "temperament") != "" and Traits.of(ch, "origin") != "" and ch.traits_offered,
			"%s: a background and both traits" % tag)
		var sheet = ch.sheet()
		for p in sheet.pending:
			check(Recruits.players_pick(p), "%s: %s is left open, and it is not the player's" % [tag, p["key"]])
			seen_pending[String(p["type"])] = true
		for p in sheet.choice_points:
			if p.get("decided", false):
				check(not Recruits.players_pick(p), "%s: %s was decided for the player" % [tag, p["key"]])
		var profs: Array = ChoicePick.proficient_weapons(sheet) + ChoicePick.proficient_armor(sheet)
		check(not ch.equipped.is_empty() and Array(ch.equipped).all(func(id): return id in profs),
			"%s: carries gear, all of it proficient (%s)" % [tag, ", ".join(ch.equipped)])
		check(int(ch.xp) == Leveling.xp_for_level(lvl), "%s: banks the XP of their level, no more" % tag)
	check(seen_pending.has("spell-choice") and seen_pending.has("subclass"), "spells and subclasses do come up open (%s)" % str(seen_pending.keys()))

	# Every kit the data lists is one its class can use.
	for row in Catalog.all("recruit-kits.json"):
		var probe = Presets.vera(1)
		probe.levels.clear()
		probe.add_level(String(row["id"]))
		var s = probe.sheet()
		var ok: Array = ChoicePick.proficient_weapons(s) + ChoicePick.proficient_armor(s)
		for k in row["kits"]:
			for id in k["items"]:
				check(String(id) in ok, "recruit-kits: %s can use %s" % [row["id"], id])
	for sp in Catalog.all("species.json"):
		check(not Catalog.index("recruit-names.json").get(String(sp["id"]), {}).get("names", []).is_empty(),
			"recruit-names: %s has names" % sp["id"])

	# --- the hire -----------------------------------------------------------------
	w.clock.elapsed = 100.0
	party.gold = 1000
	var offer: Dictionary = Recruits.offers(city, w, party)[1]
	var hired = Recruits.build(offer)
	if not Leveling.can_finalize(hired):
		check(Recruits.hire(party, w, city, offer, hired) != "", "a hire with choices unmade is refused")
		check(party.roster.size() == 1 and party.gold == 1000, "...and changes nothing")
	_finish(hired)
	var why := Recruits.hire(party, w, city, offer, hired)
	check(why == "", "a finished hire goes through (%s)" % why)
	check(party.roster.size() == 2 and party.get_member(hired.id) == hired, "they are on the roster")
	check(party.is_active(hired.id), "...marching, while there is a slot")
	check(party.gold == 1000 - int(offer["fee"]), "the fee is paid (%d)" % int(offer["fee"]))
	check(hired.id != "" and hired.id != "founder", "they are filed under an id of their own (%s)" % hired.id)
	var after: Array = Recruits.offers(city, w, party)
	check(after.size() == 2 and not after.any(func(o): return int(o["slot"]) == 1), "their chair leaves the pool")
	check(Recruits.hire(party, w, city, offer, Recruits.build(offer)) != "", "the same chair cannot be hired twice")
	var twin = Recruits.build(after[0])
	twin.cname = hired.cname
	_finish(twin)
	check(Recruits.hire(party, w, city, after[0], twin) == "" and twin.id != hired.id,
		"a second hire with the same name gets its own id (%s, %s)" % [hired.id, twin.id])

	# ...and the taken chairs survive the save.
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(w, party))))
	check(Recruits.offers(_by_id(back["world"], "riverhold"), back["world"], back["party"]).size() == 1,
		"the hires survive a save round-trip (the pool stays one short of two)")
	check(Recruits.hire_only(back["party"]) == Recruits.hire_only(party), "the rule survives it too")

	# --- the purse and the cap ------------------------------------------------------
	var poor = Party.new()
	poor.add_member(_hero("poor"))
	poor.gold = 10
	var o2: Dictionary = Recruits.offers(town, w, poor)[0]
	check(Recruits.why_not(poor, o2).contains("short"), "short of the fee says so: %s" % Recruits.why_not(poor, o2))
	var c2 = Recruits.build(o2)
	_finish(c2)
	check(Recruits.hire(poor, w, town, o2, c2) != "" and poor.roster.size() == 1 and poor.gold == 10, "...and hires nobody")

	var full = Party.new()
	for i in Recruits.roster_cap():
		full.add_member(_hero("full-%d" % i))
	full.gold = 5000
	var o3: Dictionary = Recruits.offers(town, w, full)[0]
	check(Recruits.why_not(full, o3).contains("%d" % Recruits.roster_cap()), "a full roster says so: %s" % Recruits.why_not(full, o3))
	var c3 = Recruits.build(o3)
	_finish(c3)
	check(Recruits.hire(full, w, town, o3, c3) != "" and full.roster.size() == Recruits.roster_cap(), "...and hires nobody")
	var over = Party.new()
	for i in Recruits.roster_cap() + 2:
		over.add_member(_hero("over-%d" % i))
	check(over.roster.size() == Recruits.roster_cap() + 2 and Recruits.why_not(over, o3) != "",
		"a roster already over the cap keeps everyone; it just cannot hire")
	Ladder.load({"deeds": {"human": Ladder.TITLE_AT[2]}})
	check(Recruits.roster_cap() > int(Recruits.ROSTER_CAP[0]), "the cap grows with the company's name (%d)" % Recruits.roster_cap())
	check(Recruits.fee(3) < 150, "...and the name knocks some off the fee (%d)" % Recruits.fee(3))
	Ladder.reset()

	# --- veterans: barracks heroes, at their own level, where the country fits them
	var vet = _hero("old-hand", 1)
	vet.cname = "Old Hand"
	vet.dead = true
	CharacterSave.save(vet)
	var giant = _hero("far-too-good", 9)
	CharacterSave.save(giant)
	var fresh = Party.new()
	fresh.add_member(_hero("founder"))
	fresh.gold = 1000
	var vo := {}
	for day in 40:
		w.clock.elapsed = 10.0 + Recruits.PERIOD * day
		for o in Recruits.offers(city, w, fresh):
			check(String(o["veteran"]) != "far-too-good", "a veteran above the country's level is never offered (day %d)" % day)
			if String(o["veteran"]) == "old-hand" and vo.is_empty():
				vo = o
	check(not vo.is_empty(), "a barracks hero turns up as a veteran within 40 days")
	if not vo.is_empty():
		w.clock.elapsed = 10.0 + Recruits.PERIOD * int(vo["period"])
		var back_ch = Recruits.build(vo)
		check(back_ch.cname == "Old Hand" and back_ch.level() == 1 and not back_ch.dead and int(vo["level"]) == 1,
			"...as themselves, at their own level, alive and rested")
		_finish(back_ch)
		check(Recruits.hire(fresh, w, city, vo, back_ch) == "" and fresh.get_member("old-hand") != null,
			"...hired under their own barracks id")
		check(not Recruits.offers(city, w, fresh).any(func(o): return String(o["veteran"]) == "old-hand"),
			"...and not offered again while they are on the roster")
	CharacterSave.delete("old-hand")
	CharacterSave.delete("far-too-good")

	# --- the settle-in page -----------------------------------------------------------
	w.clock.elapsed = 100.0
	var so: Dictionary = {}
	for i in 30:
		var cand := {"seed": absi(hash("settle|%d" % i)) + 1, "level": 3, "veteran": "", "fee": 150}
		if not Leveling.can_finalize(Recruits.build(cand)):
			so = cand
			break
	check(not so.is_empty(), "a level-3 recruit with something left to decide exists")
	var sc = Recruits.build(so)
	var page = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(page)
	var said := [""]
	page.hire_check = func() -> String: return said[0]
	var result := [null]
	page.finished.connect(func(h): result[0] = h)
	page.set_recruit(sc, 150)
	var decided: Array = sc.sheet().choice_points.filter(func(p): return p.get("decided", false)).map(func(p): return p["key"])
	check(decided.all(func(k): return page._locked.has(k)), "every choice they came with is locked on the page")
	check(sc.sheet().pending.all(func(p): return not page._locked.has(p["key"])), "...and every open one is not")
	check(page._confirm.text.contains("150"), "Confirm names the fee: %s" % page._confirm.text)
	check(sc.level() == 3, "settling in adds no level")
	page._on_confirm()
	check(result[0] == null and page._status.text != "", "Confirm with choices open says so and hires nobody")
	_finish(sc)
	said[0] = "The purse is short."
	page._on_confirm()
	check(result[0] == null and page._status.text == "The purse is short.", "a refused hire keeps the page up with the reason")
	said[0] = ""
	page._on_confirm()
	check(result[0] == true, "Confirm with everything made takes them on")
	result[0] = null
	page._on_cancel()
	check(result[0] == false, "Cancel hires nobody")
	page.queue_free()

	_screens()

# The party screen builds itself in _ready, which only runs once the loop turns.
func _screens() -> void:
	await process_frame
	# --- the party screen's Create new ------------------------------------------------
	var founding = Party.new()
	Recruits.found(founding)
	var ps = load("res://scenes/party/party.tscn").instantiate()
	ps.party = founding
	root.add_child(ps)
	await process_frame
	check(not ps._create_btn.disabled, "the founding: Create new is open while the roster is empty")
	founding.add_member(_hero("the-founder"))
	ps._refresh()
	check(ps._create_btn.disabled and ps._create_btn.tooltip_text == ps.HIRED_NOTE,
		"after the founder, Create new is shut, and says why: %s" % ps._create_btn.tooltip_text)
	ps.queue_free()
	var grand = load("res://scenes/party/party.tscn").instantiate()
	grand.party = Party.new()
	grand.party.add_member(_hero("grandfathered"))
	root.add_child(grand)
	await process_frame
	check(not grand._create_btn.disabled, "a grandfathered roster still has Create new")
	grand.queue_free()

	print("test_recruits: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

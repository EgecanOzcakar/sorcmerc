# Callings — the past each background hands a hero, pointed at the map.
#   docs/superpowers/specs/2026-09-21-callings-relations-design.md §2–§5
#   godot --headless --path . -s tests/test_callings.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Callings = preload("res://core/callings.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/callings-%d-%d" % [OS.get_process_id(), randi()])
	test_templates()
	test_assign()
	test_beat()
	test_check()
	test_complete()
	test_describe_and_save()
	print("test_callings: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# The player at the origin; everything else strung out along the x axis so
# "nearest" is a number you can read off the fixture.
func _world() -> World:
	var w = World.new()
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_party(World.RoamingParty.new("caravan", Vector2(20, 0), "human"))   # civilized: never a target
	w.add_party(World.RoamingParty.new("wolves", Vector2(250, 0), "beast"))
	w.add_party(World.RoamingParty.new("goblins", Vector2(700, 0), "goblinoid"))
	w.add_settlement(World.Settlement.new("orc-hold", Vector2(50, 0), "orc", "town"))   # monster: never a target
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(200, 0), "elf", "town"))
	w.add_settlement(World.Settlement.new("riverhold", Vector2(500, 0), "human", "city"))
	var looted = w.add_lair(World.Lair.new("looted-hole", Vector2(100, 0), "kobold"))
	looted.looted = true
	w.add_lair(World.Lair.new("near-warren", Vector2(300, 0), "goblinoid"))
	w.add_lair(World.Lair.new("far-warren", Vector2(600, 0), "goblinoid"))
	w.add_landmark(World.Landmark.new("shrine-near", "shrine", Vector2(150, 0)))   # hidden until told
	w.add_landmark(World.Landmark.new("shrine-far", "shrine", Vector2(400, 0)))
	return w

# The demo roster (four active), the first `backgrounds.size()` given those
# backgrounds and the rest none — the presets carry their own, and an acolyte
# nobody asked for would be handed the shrine too.
func _party(backgrounds: Array) -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	for i in p.active.size():
		p.get_member(p.active[i]).background_id = String(backgrounds[i]) if i < backgrounds.size() else ""
	return p

# --- the sixteen ----------------------------------------------------------

func test_templates() -> void:
	var t: Dictionary = Callings.templates()
	check(t.size() == 16, "sixteen templates")
	for bg in Catalog.index("backgrounds.json"):
		check(t.has(bg), "%s has a calling" % bg)
	var items: Dictionary = Catalog.index("magic-items.json")
	var kind_for := {"landmark_answered": "landmark", "lair_cleared": "lair", "band_beaten": "band",
		"visited": "settlement", "audience": "audience"}
	check(Callings.EVENT_KINDS == kind_for.keys(), "the five event kinds, verbatim")
	for bg in t:
		var c: Dictionary = t[bg]
		for k in ["title", "target", "done_by", "item", "tell", "done"]:
			check(c.has(k), "%s has %s" % [bg, k])
		check(items.has(c["item"]) and String(items.get(c["item"], {}).get("rarity", "")) == "uncommon",
			"%s's %s is a real uncommon item" % [bg, c["item"]])
		check(kind_for.has(c["done_by"]), "%s is done by one of the five events" % bg)
		check(kind_for.get(c["done_by"], "") == c["target"]["kind"], "%s's event matches its target kind" % bg)
		check(("%s" in c["tell"]) == (c["target"]["kind"] != "audience"), "%s's tell names the target unless it is an audience" % bg)
		check(("%s" in c["done"]) == (c["target"]["kind"] != "audience"), "%s's done line likewise" % bg)
	check(Callings.CALLING_XP == 120 and PartyOpinion.CALLING_BOND == 15.0, "the numbers")

# --- assign -----------------------------------------------------------------

func test_assign() -> void:
	var w := _world()
	var p := _party(["acolyte", "sage", "soldier", "noble"])
	var got: Array = Callings.assign(p, w, RNG.new(1))
	check(got == ["vera", "pike", "ilsa", "thrun"], "the four newly assigned, in marching order (got %s)" % [got])
	check(p.callings["vera"]["target_kind"] == "landmark" and p.callings["vera"]["target_id"] == "shrine-near",
		"the acolyte gets the nearest shrine, hidden or not")
	check(p.callings["pike"]["target_id"] == "near-warren", "the sage gets the nearest lair that is not looted")
	check(p.callings["ilsa"]["target_kind"] == "band" and p.callings["ilsa"]["target_id"] == "wolves",
		"the soldier gets the nearest monster band, not the caravan")
	check(p.callings["thrun"]["target_kind"] == "settlement" and p.callings["thrun"]["target_id"] == "riverhold",
		"the noble gets the city")
	check(p.callings["vera"]["id"] == "acolyte" and p.callings["vera"]["state"] == "" and float(p.callings["vera"]["told_at"]) < 0.0,
		"an entry: the background, untold, never told")
	check(Callings.assign(p, w, RNG.new(1)).is_empty(), "a second call assigns nobody new")
	check(not w.landmarks[0].found and not w.lairs[1].discovered, "assigning marks nothing — that is the telling's job")

	p = _party(["charlatan", "entertainer", "hermit", "farmer"])
	got = Callings.assign(p, w, RNG.new(1))
	check(got == ["vera", "pike", "thrun"], "the hermit is skipped: no stones on this map (got %s)" % [got])
	check(p.callings["vera"]["target_id"] == "greenmarch", "the charlatan gets the civilized town, not the orc one")
	check(p.callings["pike"]["target_kind"] == "audience" and p.callings["pike"]["target_id"] == "",
		"the entertainer needs no target")
	check(not p.callings.has("ilsa"), "...and the hermit has no entry to be told")
	w.add_landmark(World.Landmark.new("ring", "stones", Vector2(900, 0)))
	check(Callings.assign(p, w, RNG.new(1)) == ["ilsa"] and p.callings["ilsa"]["target_id"] == "ring",
		"the stones appear, the hermit is assigned on the next call")

	# a settlement kind that is missing falls back to a larger one, never a smaller
	var w2 = World.new()
	w2.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w2.add_settlement(World.Settlement.new("riverhold", Vector2(500, 0), "human", "city"))
	p = _party(["charlatan", "noble"])
	Callings.assign(p, w2, RNG.new(1))
	check(p.callings.get("vera", {}).get("target_id", "") == "riverhold", "no town: the charlatan's old mark is in the city")
	var w3 = World.new()
	w3.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w3.add_settlement(World.Settlement.new("greenmarch", Vector2(200, 0), "elf", "town"))
	p = _party(["noble"])
	check(Callings.assign(p, w3, RNG.new(1)).is_empty(), "no city: the noble waits")

	p = _party(["acolyte"])
	p.get_member("pike").background_id = "nobody"
	p.get_member("ilsa").background_id = ""
	got = Callings.assign(p, w, RNG.new(1))
	check(got.has("vera") and not got.has("pike") and not got.has("ilsa"), "a hero without a template gets no calling")

# --- beat -------------------------------------------------------------------

func test_beat() -> void:
	var w := _world()
	w.clock.elapsed = 42.0
	var p := _party(["acolyte", "sage", "entertainer"])
	p.get_member("thrun").background_id = "hermit"   # no stones: never assigned, never told
	Callings.assign(p, w, RNG.new(1))
	var shrine = w.landmarks[0]
	var lair = w.lairs[1]
	check(not shrine.found and not lair.discovered, "hidden before the fire")

	var b: Dictionary = Callings.beat(p, w)
	check(b.get("char_id", "") == "vera" and b.get("cname", "") == "Vera Kord" and b.get("id", "") == "acolyte"
		and b.get("title", "") == "The defiled shrine", "the first active untold speaks (got %s)" % [b])
	check(String(b.get("text", "")) == Callings.TEMPLATES["acolyte"]["tell"] % shrine.sname, "the tell names the shrine")
	check(shrine.found, "the telling finds the shrine")
	check(p.callings["vera"]["state"] == "told" and float(p.callings["vera"]["told_at"]) == 42.0, "told, and when")

	b = Callings.beat(p, w)
	check(b.get("char_id", "") == "pike" and lair.discovered, "the next: the sage, and the lair is discovered")
	check(String(b.get("text", "")).contains(lair.sname), "the tell names the lair")
	b = Callings.beat(p, w)
	check(b.get("char_id", "") == "ilsa" and String(b.get("text", "")) == Callings.TEMPLATES["entertainer"]["tell"],
		"the entertainer's tell has no target to name and is not formatted")
	check(Callings.beat(p, w).is_empty(), "nobody left untold: nothing")
	check(Callings.beat(p, w).is_empty(), "...and never twice")

	# a band's name is its id, capitalized
	p = _party(["soldier"])
	Callings.assign(p, w, RNG.new(1))
	b = Callings.beat(p, w)
	check(String(b.get("text", "")) == Callings.TEMPLATES["soldier"]["tell"] % "Wolves", "a band is named by its id")
	check(Callings.target_name(p, w, "vera") == "Wolves", "target_name says the same")

# --- check ------------------------------------------------------------------

func test_check() -> void:
	var w := _world()
	var p := _party(["acolyte", "sage", "entertainer", "soldier"])
	Callings.assign(p, w, RNG.new(1))
	check(Callings.check(p, w, {"kind": "landmark_answered", "id": "shrine-near"}).is_empty(), "an untold calling never completes")
	for _i in 4:
		Callings.beat(p, w)
	check(Callings.check(p, w, {"kind": "landmark_answered", "id": "shrine-near"}) == ["vera"], "the right kind and id")
	check(Callings.check(p, w, {"kind": "landmark_answered", "id": "shrine-far"}).is_empty(), "the wrong shrine")
	check(Callings.check(p, w, {"kind": "lair_cleared", "id": "shrine-near"}).is_empty(), "the wrong kind")
	check(Callings.check(p, w, {"kind": "lair_cleared", "id": "near-warren"}) == ["pike"], "the sage's lair")
	check(Callings.check(p, w, {"kind": "band_beaten", "id": "wolves"}) == ["thrun"], "the soldier's band")
	check(Callings.check(p, w, {"kind": "audience", "faction": "elf"}) == ["ilsa"], "any audience is the entertainer's")
	check(Callings.check(p, w, {"kind": "visited", "id": "riverhold"}).is_empty(), "nobody is waiting on a visit")
	check(p.callings["vera"]["state"] == "told", "check() decides; it does not complete")

# --- complete ---------------------------------------------------------------

func test_complete() -> void:
	var w := _world()
	var p := _party(["acolyte", "entertainer"])
	Callings.assign(p, w, RNG.new(1))
	check(Callings.complete(p, w, "vera", "pike").is_empty(), "an untold calling cannot be completed")
	Callings.beat(p, w)
	Callings.beat(p, w)
	var xp_before: int = p.get_member("vera").xp
	var score_before: float = PartyOpinion.score(p, "vera", "pike")
	var r: Dictionary = Callings.complete(p, w, "vera", "pike")
	check(r.get("xp", 0) == 120 and p.get_member("vera").xp == xp_before + 30 and p.get_member("thrun").xp > 0,
		"120 XP split four ways")
	check(r.get("item", "") == "amulet-of-proof-against-detection-and-location"
		and r.get("item_name", "") == "Amulet of Proof against Detection and Location"
		and p.stash_count("amulet-of-proof-against-detection-and-location", true) == 1, "the heirloom, identified, in the stash")
	check(r.get("bond_with", "") == "pike" and PartyOpinion.score(p, "vera", "pike") == score_before + 15.0,
		"the bond with the one who did the thing")
	check(String(r.get("text", "")) == Callings.TEMPLATES["acolyte"]["done"] % w.landmarks[0].sname, "the done line names the shrine")
	check(p.callings["vera"]["state"] == "done", "done")
	check(Callings.complete(p, w, "vera", "pike").is_empty() and p.stash_count("amulet-of-proof-against-detection-and-location") == 1,
		"a second time pays nothing")

	score_before = PartyOpinion.score(p, "pike", "ilsa")
	r = Callings.complete(p, w, "pike", "pike")
	check(r.get("bond_with", "") == "" and PartyOpinion.score(p, "pike", "ilsa") == score_before, "who == the hero: no bond")
	check(String(r.get("text", "")) == Callings.TEMPLATES["entertainer"]["done"], "the entertainer's done line is verbatim")
	check(p.stash_count("pipes-of-haunting", true) == 1, "the pipes")
	p = _party(["sage"])
	Callings.assign(p, w, RNG.new(1))
	Callings.beat(p, w)
	r = Callings.complete(p, w, "vera")
	check(r.get("bond_with", "") == "" and p.callings["vera"]["state"] == "done", "no who: done, no bond")

# --- describe, save ---------------------------------------------------------

func test_describe_and_save() -> void:
	var w := _world()
	var p := _party(["acolyte", "sage"])
	check(Callings.describe(p, "vera") == "", "no calling: nothing")
	Callings.assign(p, w, RNG.new(1))
	check(Callings.describe(p, "vera") == "", "untold: nothing to show yet")
	Callings.beat(p, w)
	check(Callings.describe(p, "vera") == "The defiled shrine — told, marked on the map", "told")
	Callings.complete(p, w, "vera", "pike")
	check(Callings.describe(p, "vera") == "The defiled shrine — done", "done")
	check(Callings.describe(p, "thrun") == "", "no entry: nothing")

	var d: Dictionary = Callings.to_dict(p)
	check(d["vera"]["state"] == "done" and d["pike"]["state"] == "" and d["pike"]["target_id"] == "near-warren", "to_dict")
	d["vera"]["state"] = "told"
	check(p.callings["vera"]["state"] == "done", "...a copy, not the live dict")
	var back = JSON.parse_string(JSON.stringify(d))
	var p2 := _party([])
	Callings.from_dict(p2, back)
	check(p2.callings.size() == 2 and p2.callings["vera"]["state"] == "told" and p2.callings["pike"]["target_id"] == "near-warren"
		and p2.callings["pike"]["target_kind"] == "lair" and p2.callings["pike"]["id"] == "sage"
		and p2.callings["vera"]["told_at"] is float, "from_dict, through JSON")
	check(Callings.describe(p2, "vera") == "The defiled shrine — told, marked on the map", "and it reads the same")
	Callings.from_dict(p2, null)
	check(p2.callings.is_empty(), "a missing dict is an empty one")
	Callings.from_dict(p2, {"vera": "junk", "pike": {"target_id": "x"}})
	check(p2.callings.is_empty(), "an entry without a background is dropped")

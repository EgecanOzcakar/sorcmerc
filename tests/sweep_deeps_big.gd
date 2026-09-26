# MEASUREMENT — how often a Far Deeps road fight fields a CR 11+ creature, and
# what the big one does to the win rate (core/scaler.gd's BIG_CHANCE and
# BIG_SHARE, the design audit's "the new statblocks rarely reach a roster").
# Not a test, and not part of tools/run_tests.sh (the runner globs test_* and
# drive_*).
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_deeps_big.gd
#   SEEDS=200 FIGHTS=0 godot --headless --path . -s tests/sweep_deeps_big.gd   # rosters only, fast
#   CHANCE=1.0 FIGHTS=0 godot --headless --path . -s tests/sweep_deeps_big.gd   # the second column at this chance
#   POINTS=deeps:10,unmapped:15 godot --headless --path . -s tests/sweep_deeps_big.gd
#
# Per point (a band and a party level inside it, so the fight is built for the
# party standing there — power_scale 1.0): SEEDS road rosters at tier easy (what
# core/world_threat.gd sends into open country), habitat "" (the downs, the
# default fill), each seed pinned to a faction drawn from the band's own
# roaming population. That population is core/world_bands.gd's hunt kinds whose
# faction lives in the Far Deeps, weighted the way _place() scatters them: a
# kind picks one of its faction's COUNTRIES and fills it by area, so undead,
# giants and monstrosities (frontier and deeps) send half their weight here and
# fey, elementals and constructs (deeps only) all of it, split evenly between
# the inner Deeps and the Unmapped. Per band: undead 2, giant 1, monstrosity 1,
# fey 4, elemental 4, construct 4. No dragon roams; dragons are the lair's.
#
# Two columns a point, the same seeds, the fight seed pinned: `never` pins
# Scaler.big_chance_override at 0.0, which builds exactly the roster master
# builds (_big_one returns {} and _build runs as before), and `shipped` rolls
# BIG_CHANCE. Autoplayed both sides, the way tests/sweep_regions.gd does.
#
# MEASURED 2026-09-25, 200 seeds a point, easy, BIG_CHANCE deeps 0.6 /
# unmapped 0.37, BIG_SHARE 0.8 (share of fights with a CR 11+ creature, win):
#
#   band      lvl    never (= master)    shipped
#   deeps      10     0.0%  94.0%     29.5%  94.0%
#   deeps      12     0.0%  98.5%     34.0%  98.0%
#   deeps      14     1.0%  97.5%     35.0%  96.0%
#   unmapped   15     8.5%  98.5%     26.5%  97.5%
#   unmapped   17    11.0%  95.0%     33.5%  93.5%
#   unmapped   20    11.0%  94.0%     32.5%  92.5%
#
# BIG_SHARE was picked off CHANCE=1.0 TIER=hard POINTS=deeps:12,unmapped:17
# (the table is in core/scaler.gd's big-one header).
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const MIX := ["undead", "undead", "giant", "monstrosity", "fey", "fey", "fey", "fey",
	"elemental", "elemental", "elemental", "elemental", "construct", "construct", "construct", "construct"]
const POINTS := [["deeps", 10], ["deeps", 12], ["deeps", 14],
	["unmapped", 15], ["unmapped", 17], ["unmapped", 20]]

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var fights := OS.get_environment("FIGHTS") != "0"
	var points: Array = POINTS
	if OS.get_environment("POINTS") != "":
		points = []
		for pair in OS.get_environment("POINTS").split(","):
			var bl: PackedStringArray = pair.split(":")
			points.append([bl[0], int(bl[1])])
	print("band      lvl   never: big  win    shipped: big  win   (%d seeds, %s, BIG_CHANCE %s, BIG_SHARE %.2f)" % [
		seeds, _tier(), str(Scaler.BIG_CHANCE), Scaler.BIG_SHARE])
	for pt in points:
		var band: String = pt[0]
		var lvl: int = pt[1]
		var cols: Array = []
		var alt := float(OS.get_environment("CHANCE")) if OS.get_environment("CHANCE") != "" else -1.0
		for over in [0.0, alt]:
			Scaler.big_chance_override = over
			cols.append(_point(band, lvl, seeds, fights))
		Scaler.big_chance_override = -1.0
		print("%-9s %3d   %9.1f%% %5s   %11.1f%% %5s   %s" % [band, lvl,
			cols[0]["big"], cols[0]["win"], cols[1]["big"], cols[1]["win"], cols[1]["by"]])
	quit(0)

func _point(band: String, lvl: int, seeds: int, fights: bool) -> Dictionary:
	var chars: Array = Presets.party_at(lvl)
	var big := 0
	var wins := 0
	var by := {}
	for s in range(1, seeds + 1):
		var fac: String = MIX[s % MIX.size()]
		var seed_v: int = Scaler.pin_faction(s * 7919, fac)
		var spec: Dictionary = Scaler.roster_for(chars, _tier(), {}, "", seed_v, 1.0, [], "", 0, band)
		var has_big := false
		for m in spec["monsters"]:
			if float(Catalog.monster(String(m["id"])).get("cr", 0.0)) >= Scaler.BIG_CR:
				has_big = true
		if has_big:
			big += 1
			by[fac] = int(by.get(fac, 0)) + 1
		if not fights:
			continue
		spec["seed"] = s
		var party: Array = []
		for i in chars.size():
			party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(spec, party)
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		if cb.outcome() == "Victory":
			wins += 1
	return {"big": 100.0 * big / seeds, "win": ("%.1f%%" % (100.0 * wins / seeds)) if fights else "-",
		"by": by}

# TIER=hard reads the same points with headroom: easy in band sits near 98%.
func _tier() -> String:
	return OS.get_environment("TIER") if OS.get_environment("TIER") != "" else "easy"

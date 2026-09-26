# MEASUREMENT — the win-rate table in core/regions.gd's header, re-runnable.
# Not a test, and not part of tools/run_tests.sh (the runner globs test_* and
# drive_*). The table was first measured 2026-09-13 with no script committed;
# this is that method, written down so the claim can be re-run rather than
# re-argued:
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_regions.gd
#   SEEDS=40 godot --headless --path . -s tests/sweep_regions.gd
#   CELLS=10:15,15:14 SEEDS=200 godot --headless --path . -s tests/sweep_regions.gd
#
# Per cell: the preset trio at the party's level (Presets.party_at), a roster
# from Scaler.roster_for at wilderness tier `easy` (what core/world_threat.gd
# sends into open country) with the band's power_scale for content at the
# content's level — Scaler.held_at(score(C), score(P)), which is what
# Regions.power_scale computes when the party is the ruler — and the fight seed pinned (spec["seed"] = s). Autoplayed both
# sides, the way tests/sweep_tier.gd does.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")

# [party level, content level] — the rows of the published table: the in-band
# curve (party and content at the same level, 3 to 15), then one band back and
# one band out; then the rows the Far Deeps' split (2026-09-25) added — a
# level 10 and 12 party one band out in the Unmapped (content 15), a level 15
# and 20 party one band back in the inner Deeps (content 14), and level 3 at
# the very edge. `CELLS=p:c,p:c` runs only those.
#
# A content of a band's id instead of a level (the Deeps' teeth, 2026-09-25) is
# that band as the map prices it — Regions.scale_in, so a band's own `under`
# pin shows — rather than a plain pin at one content level: [10, "unmapped"]
# is a level 10 party in the Unmapped. Every cell passes the band its content
# stands in to Scaler.roster_for, which is how the map's road fights reach the
# Far Deeps' big one (Scaler.BIG_CHANCE); BIG=0 pins that roll off, which
# builds master's rosters.
const CELLS := [[3, 3], [5, 5], [6, 6], [8, 8], [10, 10], [12, 12], [15, 15],
	[6, 3], [10, 3], [3, 6], [3, 10],
	[10, 15], [12, 15], [15, 14], [20, 14], [3, 15],
	[10, "unmapped"], [12, "unmapped"], [14, "unmapped"]]

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 80
	if OS.get_environment("BIG") == "0":
		Scaler.big_chance_override = 0.0
	print("party  content   scale   win   (%d seeds a cell, tier easy%s)" % [seeds,
		", big one off" if Scaler.big_chance_override == 0.0 else ""])
	var cells: Array = CELLS
	if OS.get_environment("CELLS") != "":
		cells = []
		for pair in OS.get_environment("CELLS").split(","):
			var pc: PackedStringArray = pair.split(":")
			cells.append([int(pc[0]), int(pc[1]) if pc[1].is_valid_int() else pc[1]])
	for cell in cells:
		var p: int = cell[0]
		var band: Dictionary = {}
		var scale := 1.0
		var c_label := ""
		if cell[1] is String:
			band = Regions.band_by_id(String(cell[1]))
			scale = Regions.scale_in(band, p, Regions.ref_score(p))
			c_label = String(cell[1]).substr(0, 3)
		else:
			var c: int = cell[1]
			band = _band_holding(c)
			scale = 1.0 if p == c else Scaler.held_at(Regions.ref_score(c), Regions.ref_score(p))
			c_label = str(c)
		var wins := 0
		for s in range(1, seeds + 1):
			var chars: Array = Presets.party_at(p)
			var spec: Dictionary = Scaler.roster_for(chars, "easy", {}, "", s, scale, [], "", 0,
				String(band.get("id", "")))
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
		print("lvl %-3d lvl %-3s  x%.2f  %5.1f%%" % [p, c_label, scale, 100.0 * wins / seeds])
	quit(0)

# The deepest band whose levels hold content level `c` — where on the map a
# fight built for that level stands.
func _band_holding(c: int) -> Dictionary:
	var out: Dictionary = {}
	for b in Regions.BANDS:
		if c >= int(b["levels"][0]) and c <= int(b["levels"][1]):
			out = b
	return out

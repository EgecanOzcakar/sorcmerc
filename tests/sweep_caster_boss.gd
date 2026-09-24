# MEASUREMENT (2026-09-24) — the cult's lair boss with and without its caster
# lead, at the Frontier tier where core/enemy_casters.gd fields one. Not a test,
# and not part of tools/run_tests.sh. tests/sweep_faction_boss.gd cannot ask
# this: its lair sits on a one-town map, which core/regions.gd reads as all
# Heartland, so the boss there is never fielded as a caster.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_caster_boss.gd
#   SEEDS=100 LEVELS=6,9 godot --headless --path . -s tests/sweep_caster_boss.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const Site = preload("res://core/site.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 150
	var levels: Array = [6, 8]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("the cult's boss room, Frontier tier (3rd-level spells), %d seeds a cell, fight seed pinned" % seeds)
	print("  level   plain lead: win%    caster lead: win%   (what it fielded, seed 1)")
	for L in levels:
		var room: Dictionary = Site.FACTION_BOSS["cultist"].duplicate(true)
		room["difficulty"] = "hard"
		var plain: Dictionary = room.duplicate(true)
		plain["lead_caster"] = false
		var cast: Dictionary = room.duplicate(true)
		cast["caster_cap"] = 3
		var a := _sweep(L, plain, seeds)
		var b := _sweep(L, cast, seeds)
		print("  %5d       %5.1f%%             %5.1f%%          %s" % [L, a["rate"], b["rate"], b["shape"]])
	quit(0)

func _sweep(L: int, boss: Dictionary, seeds: int) -> Dictionary:
	var wins := 0
	var shape := ""
	for s in range(1, seeds + 1):
		var chars: Array = Presets.party_at(L)
		var spec: Dictionary = Scaler.boss_for(chars, boss, s)
		if s == 1:
			shape = ", ".join(spec["monsters"].map(func(m): return "%dx%s@%.2f%s" % [int(m["count"]), m["id"], float(m["mult"]), "*" if m.get("caster", false) else ""]))
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
	return {"rate": 100.0 * wins / seeds, "shape": shape}

# MEASUREMENT (2026-09-25) — the XP pace of the road, played: how many open-
# country fights a level takes, band by band, under the late-level step
# (core/leveling.gd's LATE_LEVEL) and with the country's quest XP beside it
# (core/quest.gd's XP_FIGHTS). The design audit §7.3 asked for it: leveling.gd's
# curve cited a tests/_tmp_xp sweep that was never committed, and the coin-and-
# xp pass's table (tests/sweep_economy.gd) is arithmetic on the budget, not a
# fight. Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_xp.gd
#   SEEDS=20 LEVELS=1,5,10 godot ... -s tests/sweep_xp.gd
#
# Each level: the preset trio at L (Presets.party_at), fresh, the road's own
# roster (Scaler.roster_for at WorldThreat.BASELINE with WorldThreat.assess's
# power scale — a fresh company's x0.90), fight seed pinned, autoplayed, paid by
# Encounter.resolve_outcome exactly as the world pays it, split three ways. A
# lost fight pays what it killed, as the world's does. The estimate beside it
# is sweep_economy's: Regions.fight_xp(L) (the full easy budget x XP_PER_POWER)
# split three ways, never played.
#
# The quest column: a job that pays XP_FIGHTS fights' worth (clear_lair, 3) at
# the level's own Regions.fight_xp, split the same way, taken once every JOB
# road fights (default 4) — what a level costs a company that works the board.
#
# Its table is in core/leveling.gd's header.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Leveling = preload("res://core/leveling.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Quest = preload("res://core/quest.gd")
const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")
const WorldThreat = preload("res://core/world_threat.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 60
	var job := int(OS.get_environment("JOB")) if OS.get_environment("JOB") != "" else 4
	var levels: Array = range(1, 20)
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("preset trio, fresh, the road's roster (easy x%.2f), %d seeds a level; a clear_lair job every %d fights" % [
		WorldThreat.SCALE_MAX, seeds, job])
	print("  level  band        win%  XP/hero  estimate  step  fights  +jobs")
	var by_band := {}
	for L in levels:
		var p := Party.new()
		for ch in Presets.party_at(L):
			p.add_member(ch)
		var chars: Array = p.party_characters()
		var scale := float(WorldThreat.assess(p)["power_scale"])
		var xp := 0.0
		var wins := 0
		for s in range(1, seeds + 1):
			var spec: Dictionary = Scaler.roster_for(chars, WorldThreat.BASELINE, {}, "", s, scale)
			spec["seed"] = s
			var team: Array = []
			for i in chars.size():
				team.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
			var cb = Encounter.build(spec, team)
			var g := 0
			while not cb.is_over() and g < 5000:
				var a = cb.current()
				cb.begin_turn()
				AI.take_turn(cb, a)
				cb.end_turn()
				g += 1
			var r: Dictionary = Encounter.resolve_outcome(cb, [])   # [] writes nothing back: every seed starts fresh
			xp += float(r["xp"]) / chars.size()
			if r["outcome"] == "Victory":
				wins += 1
		var per: float = xp / seeds
		var est: float = Regions.fight_xp(L) / 3.0
		var step: int = Leveling.xp_for_level(L + 1) - Leveling.xp_for_level(L)
		var quest: float = Quest.xp_for("clear_lair", Regions.fight_xp(L)) / 3.0
		var fights: float = step / maxf(1.0, per)
		var with_jobs: float = step / maxf(1.0, per + quest / job)
		var band := _band(L)
		print("  %5d  %-10s %5.1f%%  %7.1f  %8.1f  %4d  %6.1f  %5.1f" % [L, band, 100.0 * wins / seeds, per, est, step, fights, with_jobs])
		var b: Array = by_band.get(band, [0.0, 0.0])
		by_band[band] = [b[0] + fights, b[1] + with_jobs]
	print("  fights to cross each band's levels (road only / with a job every %d):" % job)
	for band in by_band:
		print("    %-10s %6.1f / %5.1f" % [band, by_band[band][0], by_band[band][1]])
	quit(0)

# The band whose level range this level is in (the first, where two share an
# edge: level 3 is the Heartland's last and the Marches' first).
func _band(L: int) -> String:
	for b in Regions.BANDS:
		var lv: Array = b["levels"]
		if L >= int(lv[0]) and L <= int(lv[1]):
			return String(b["id"])
	return "deeps" if L < 15 else "unmapped"

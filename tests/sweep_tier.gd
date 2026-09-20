# Throwaway: win rate vs a TIER scale, via roster_for's power_scale (budget =
# ... * TIER * scale, so effective tier = TIER[d] * scale). Level-3 presets.
#   godot --headless --path . -s tests/sweep_tier.gd -- easy=0.8,0.85 hard=0.85
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")

const SEEDS := 200

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=")
		for s in kv[1].split(","):
			_sweep(kv[0], float(s))
	quit(0)

func _sweep(d: String, scale: float) -> void:
	var chars := Presets.party()
	var wins := 0
	var foes := 0
	var mult := 0.0
	for s in range(1, SEEDS + 1):
		var spec: Dictionary = Scaler.roster_for(chars, d, {}, "", s, scale)
		for e in spec["monsters"]:
			foes += int(e["count"])
		mult += float(spec["monsters"][0]["mult"])
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
	print("%-6s tier %.3f (scale %.2f): avg %.1f foes x%.2f -> %.1f%%" % [
		d, float(Scaler.TIER[d]) * scale, scale, float(foes) / SEEDS, mult / SEEDS, 100.0 * wins / SEEDS])

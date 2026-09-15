# Throwaway: win rate of one BOSS_POOL entry with per-boss knob overrides.
#   godot --headless --path . -s tests/sweep_boss.gd -- the-arrow-chief mult_max=2.0 lead_share=0.4
extends SceneTree
const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Campaign = preload("res://core/campaign.gd")
const SEEDS := 60
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var boss: Dictionary = {}
	for b in Campaign.BOSS_POOL:
		if b["id"] == args[0]:
			boss = b.duplicate(true)
	for a in args.slice(1):
		boss[a.get_slice("=", 0)] = float(a.get_slice("=", 1))
	var chars := Presets.party()
	var wins := 0
	var foes := 0
	for s in range(1, SEEDS + 1):
		var sp: Dictionary = Scaler.boss_for(chars, boss, s)
		for e in sp["monsters"]:
			foes += int(e["count"])
		sp["seed"] = s
		sp["theme"] = boss["theme"]
		var party: Array = []
		for i in chars.size():
			party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(sp, party)
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current(); cb.begin_turn(); AI.take_turn(cb, a); cb.end_turn(); g += 1
		if cb.outcome() == "Victory":
			wins += 1
	print("%s %s -> %.1f%% (avg %.1f foes)" % [boss["id"], str(args.slice(1)), 100.0 * wins / SEEDS, float(foes) / SEEDS])
	quit()

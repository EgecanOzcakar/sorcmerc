# Headless full-encounter playthrough, both sides on AI. Proves an encounter resolves.
#   flatpak run org.godotengine.Godot --headless --path . -s tests/autoplay.gd [seed]
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	var sd = int(args[0]) if args.size() > 0 else 1337
	var rng = RNG.new(sd)
	var cb = Combat.new(rng, Encounter.all(), Encounter.board())

	print("=== The Sunken Shrine   seed=%d ===" % sd)
	var last_round = 0
	while not cb.is_over():
		if cb.round_num != last_round:
			last_round = cb.round_num
			print("\n-- Round %d --" % cb.round_num)
		var actor = cb.current()
		var log_before = cb.log.size()
		cb.begin_turn()
		AI.take_turn(cb, actor)
		cb.end_turn()
		for i in range(log_before, cb.log.size()):
			print("  ", cb.log[i])

	print("\n=== %s in %d rounds ===" % [cb.outcome(), cb.round_num])
	for c in cb.combatants:
		var state = "dead" if c.is_dead() else ("down" if c.is_down() else "%d/%d" % [c.hp, c.max_hp])
		print("  %-12s %s" % [c.cname, state])

	quit(0 if cb.outcome() != "ongoing" else 1)

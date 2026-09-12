# O7: one opinion score per faction — raise/lower/clamp, the slow drift back to
# neutral, and draining O6's per-settlement hook into the owning faction.
# The per-effect tests live with the systems they change (test_settlement_visit /
# test_quest / test_world_ai).
#   godot --headless --path . -s tests/test_faction_opinion.gd
extends SceneTree

const World = preload("res://core/world.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_raise_lower_clamp()
	test_decay_drifts_toward_neutral()
	test_decay_leaves_neutral_factions_alone()
	test_drain_settlement_hook()
	test_credit_fight_is_local_and_skips_the_dead()
	test_thresholds_are_ordered()
	print("test_faction_opinion: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(900, 0), "cultist", "city"))
	return w

func test_raise_lower_clamp() -> void:
	FactionOpinion.reset()
	check(FactionOpinion.get_opinion("soldier") == 0.0, "an unknown faction is neutral")
	FactionOpinion.raise("soldier", 10.0)
	check(FactionOpinion.get_opinion("soldier") == 10.0, "raise adds")
	FactionOpinion.lower("soldier", 25.0)
	check(FactionOpinion.get_opinion("soldier") == -15.0, "lower subtracts, past 0")
	FactionOpinion.raise("soldier", 1000.0)
	check(FactionOpinion.get_opinion("soldier") == FactionOpinion.RANGE, "clamped at +RANGE")
	FactionOpinion.lower("soldier", 1000.0)
	check(FactionOpinion.get_opinion("soldier") == -FactionOpinion.RANGE, "clamped at -RANGE")
	FactionOpinion.raise("soldier", -5.0)
	check(FactionOpinion.get_opinion("soldier") > -FactionOpinion.RANGE,
		"raise with a negative amount still raises")
	check(FactionOpinion.get_opinion("cultist") == 0.0, "factions are independent")

func test_decay_drifts_toward_neutral() -> void:
	FactionOpinion.reset()
	FactionOpinion.set_opinion("soldier", 50.0)
	FactionOpinion.set_opinion("cultist", -30.0)
	FactionOpinion.decay(FactionOpinion.DAY)
	check(is_equal_approx(FactionOpinion.get_opinion("soldier"),
		50.0 - FactionOpinion.DECAY_PER_DAY), "a day of nothing drifts a liked faction down")
	check(is_equal_approx(FactionOpinion.get_opinion("cultist"),
		-30.0 + FactionOpinion.DECAY_PER_DAY), "...and an angry one up")
	for i in 200:                     # long enough to cross 0 many times over
		FactionOpinion.decay(FactionOpinion.DAY)
	check(FactionOpinion.get_opinion("soldier") == 0.0, "drift stops exactly at neutral")
	check(FactionOpinion.get_opinion("cultist") == 0.0, "...from below too, no overshoot")
	FactionOpinion.set_opinion("soldier", 40.0)
	FactionOpinion.decay(0.0)
	check(FactionOpinion.get_opinion("soldier") == 40.0, "a paused clock does not decay")

func test_decay_leaves_neutral_factions_alone() -> void:
	FactionOpinion.reset()
	FactionOpinion.set_opinion("soldier", 0.0)
	FactionOpinion.decay(FactionOpinion.DAY * 10.0)
	check(FactionOpinion.get_opinion("soldier") == 0.0, "an already-neutral faction never moves")
	check(FactionOpinion.all().size() == 1, "decay invents no new factions")

func test_drain_settlement_hook() -> void:
	FactionOpinion.reset()
	var w := _world()
	w.settlements[0].pending_opinion_delta = -10.0    # O6's theft hook
	w.settlements[1].pending_opinion_delta = -5.0
	FactionOpinion.drain(w)
	check(FactionOpinion.get_opinion("human") == -10.0, "the delta lands on the owning faction")
	check(FactionOpinion.get_opinion("cultist") == -5.0, "...each on its own")
	check(w.settlements[0].pending_opinion_delta == 0.0, "the hook is zeroed once applied")
	FactionOpinion.drain(w)
	check(FactionOpinion.get_opinion("human") == -10.0, "draining twice does not double-count")
	# Two settlements of one faction both feed the same score.
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(60, 0), "human", "town"))
	w.settlements[0].pending_opinion_delta = -5.0
	w.settlements[2].pending_opinion_delta = -5.0
	FactionOpinion.drain(w)
	check(FactionOpinion.get_opinion("human") == -20.0, "opinion is per faction, not per town")
	# tick() = drain + decay, on the world-time the clock actually advanced.
	FactionOpinion.reset()
	w.settlements[0].pending_opinion_delta = -50.0
	FactionOpinion.tick(w, FactionOpinion.DAY)
	check(is_equal_approx(FactionOpinion.get_opinion("human"),
		-50.0 + FactionOpinion.DECAY_PER_DAY), "tick drains then decays")

func test_credit_fight_is_local_and_skips_the_dead() -> void:
	FactionOpinion.reset()
	var w := _world()
	FactionOpinion.credit_fight(w, Vector2(30, 0), FactionOpinion.FOUGHT_FOR)
	check(FactionOpinion.get_opinion("human") == FactionOpinion.FOUGHT_FOR,
		"a fight on their doorstep is credited")
	check(FactionOpinion.get_opinion("cultist") == 0.0, "a faction across the map hears nothing")
	FactionOpinion.reset()
	FactionOpinion.credit_fight(w, Vector2(30, 0), FactionOpinion.FOUGHT_FOR, "human")
	check(FactionOpinion.get_opinion("human") == 0.0,
		"killing their own band is not a favour to them")
	# O9 item 8: "every *civilized* faction nearby", which is what the comment always
	# claimed — a cultist city does not thank you for putting down a monster band.
	FactionOpinion.reset()
	FactionOpinion.credit_fight(w, Vector2(880, 0), FactionOpinion.FOUGHT_FOR)
	check(FactionOpinion.get_opinion("cultist") == 0.0,
		"a monster faction is not credited for a fight on its doorstep")

# O9 item 5: the three bands are ordered and distinct, so each one is reachable.
func test_thresholds_are_ordered() -> void:
	FactionOpinion.reset()
	check(FactionOpinion.GUARDS_ATTACK < FactionOpinion.REFUSE_TRADE
		and FactionOpinion.REFUSE_TRADE < FactionOpinion.HOSTILE,
		"guards attack below refuse-trade, which is below hostile")
	FactionOpinion.set_opinion("soldier", FactionOpinion.REFUSE_TRADE - 1.0)
	check(FactionOpinion.refuses_trade("soldier") and not FactionOpinion.guards_attack("soldier"),
		"a faction can refuse to trade without fighting you at the gate")
	FactionOpinion.set_opinion("soldier", FactionOpinion.GUARDS_ATTACK - 1.0)
	check(FactionOpinion.guards_attack("soldier"), "...and below that the guards come out")
	FactionOpinion.reset()

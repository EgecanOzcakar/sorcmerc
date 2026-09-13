# T9x: the camp-kit item (core/world_camp.gd) — ambush_roll's odds, watch_check's
# best-of-Survival-or-Perception DC roll, and the item/gold/cooldown plumbing in
# core/settlement_visit.gd and core/party.gd around it.
#   godot --headless --path . -s tests/test_world_camp.gd
extends SceneTree

const WorldCamp = preload("res://core/world_camp.gd")
const Visit = preload("res://core/settlement_visit.gd")
const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _init() -> void:
	# --- ambush_roll: "very low" and reproducible off a seed ---
	var hits := 0
	for seed_v in range(1, 2001):
		if WorldCamp.ambush_roll(RNG.new(seed_v)):
			hits += 1
	var pct := float(hits) / 2000.0 * 100.0
	check(pct > 4.0 and pct < 12.0, "ambush_roll lands near AMBUSH_CHANCE_PCT=%d over 2000 seeds (got %.1f%%)" % [WorldCamp.AMBUSH_CHANCE_PCT, pct])
	check(WorldCamp.ambush_roll(RNG.new(7)) == WorldCamp.ambush_roll(RNG.new(7)), "same seed -> same ambush outcome")

	# --- watch_check: best of Survival/Perception, vs a fixed DC ---
	var party := _party()
	var watch := WorldCamp.watch_check(party, RNG.new(1))
	check(watch["char_id"] != "", "a real party always has someone to roll the watch check")
	check(watch["dc"] == WorldCamp.AMBUSH_DC, "watch_check uses the documented DC")
	check(watch["ok"] == (watch["nat"] + watch["bonus"] >= WorldCamp.AMBUSH_DC), "ok matches the roll vs DC")
	var empty_party := Party.new()   # no members at all
	check(not WorldCamp.watch_check(empty_party, RNG.new(1))["ok"], "nobody to watch -> the check can't pass")

	# --- settlement_visit.gd: rest kinds and the long-rest cooldown ---
	var w := World.new()
	w.add_settlement(World.Settlement.new("home", Vector2.ZERO, "human", "city"))
	var p2 := _party()
	check(Visit.can_long_rest(p2, w), "a fresh party can long-rest immediately")
	var before: float = w.clock.elapsed
	Visit.rest(p2, w, "long-rest")
	check(is_equal_approx(w.clock.elapsed, before + Visit.LONG_REST_MINUTES), "a long rest spends the long-rest time block")
	check(is_equal_approx(p2.last_long_rest_at, w.clock.elapsed), "a long rest stamps last_long_rest_at")
	check(not Visit.can_long_rest(p2, w), "immediately after a long rest, another one is gated")
	w.clock.elapsed += Visit.LONG_REST_COOLDOWN
	check(Visit.can_long_rest(p2, w), "a full cooldown later, a long rest is allowed again")

	var p3 := _party()
	var before2: float = w.clock.elapsed
	Visit.rest(p3, w, "short-rest")
	check(is_equal_approx(w.clock.elapsed, before2 + Visit.SHORT_REST_MINUTES), "a short rest spends the shorter time block")
	check(is_equal_approx(p3.last_long_rest_at, -1e12), "a short rest never stamps the long-rest cooldown")

	# --- camp kit purchase/consume plumbing (core/party.gd) ---
	var p4 := _party()
	p4.gold = WorldCamp.CAMP_KIT_PRICE
	check(p4.spend_gold(WorldCamp.CAMP_KIT_PRICE), "the kit's price can be spent")
	p4.stash_add(WorldCamp.CAMP_KIT_ITEM)
	check(p4.stash_count(WorldCamp.CAMP_KIT_ITEM) == 1, "buying adds one kit to the stash")
	check(p4.stash_remove(WorldCamp.CAMP_KIT_ITEM, 1), "using it removes one kit")
	check(p4.stash_count(WorldCamp.CAMP_KIT_ITEM) == 0, "and it's gone after use — one shot per kit")

	print("test_world_camp: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

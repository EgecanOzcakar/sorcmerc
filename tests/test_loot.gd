# What a won fight leaves on the field (core/loot.gd), and the seam it plugs
# into (core/encounter.gd's resolve_outcome).
#   godot --headless --path . -s tests/test_loot.gd
extends SceneTree

const Loot = preload("res://core/loot.gd")
const Campaign = preload("res://core/campaign.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Every id in a hand-written table has to be a real catalog id. This is the
# whole reason loot.gd refuses to invent "wolf-pelt": the stash names it with
# Campaign.item_name(), the shop pays Campaign.item_price(), and both degrade
# silently — an id nothing has heard of shows as a capitalised slug worth 0 gp
# rather than failing, so nothing but a test catches the typo.
func real_item(id: String) -> bool:
	return not Campaign.item_data(id).is_empty()

func _init() -> void:
	table_ids_are_real()
	who_it_was_decides_what_drops()
	how_dangerous_decides_how_good()
	the_fight_pays_at_most_a_handful()
	it_replays_with_the_seed()
	print("test_loot: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func table_ids_are_real() -> void:
	for fac in Loot.CARRIED:
		for id in Loot.CARRIED[fac]:
			check(real_item(String(id)), "%s carries a real item id (%s)" % [fac, id])
	for band in Loot.CONSUMABLE_BANDS:
		for id in Loot.CONSUMABLE_BANDS[band]:
			check(real_item(String(id)), "%s consumable is a real item id (%s)" % [band, id])
			check(Campaign.item_price(String(id)) > 0, "%s is worth something (%s)" % [id, band])
	for b in Loot.RARITY_BANDS:
		var rarity := String(b["rarity"])
		check(not Loot.items_of_rarity(rarity).is_empty(),
			"the %s band has items in it" % rarity)
	# Artifacts price at 0 — a shop will not buy one, so it is not a reward.
	check(Loot.items_of_rarity("artifact").is_empty(), "artifacts are never in a band")

func who_it_was_decides_what_drops() -> void:
	var wolf: Dictionary = Catalog.monster("wolf")
	var bandit: Dictionary = Catalog.monster("bandit")
	check(not wolf.is_empty() and not bandit.is_empty(), "the bestiary has a wolf and a bandit")
	check(Loot.kit_for(wolf).is_empty(), "a wolf is not carrying a sword")
	check(not Loot.kit_for(bandit).is_empty(), "a bandit is")
	# The faction wins over the type where both are listed, since the faction is
	# the axis a roster is actually built along.
	var goblin: Dictionary = Catalog.monster("goblin")
	if not goblin.is_empty():
		check(Loot.kit_for(goblin) == Loot.CARRIED["goblinoid"],
			"a goblin's kit is the goblinoid one, not the generic humanoid one")
	check(Loot.drop_chance(1.0, false) < Loot.drop_chance(1.0, true),
		"something with nothing on it is less worth searching")

	# Over many fights a gear-carrier's drops include its own kit; a beast's
	# never do, because it has none.
	var from_wolves: Array = []
	var from_bandits: Array = []
	for s in range(400):
		from_wolves.append_array(Loot.for_kills(["wolf"], RNG.new(s + 1)))
		from_bandits.append_array(Loot.for_kills(["bandit"], RNG.new(s + 1)))
	check(not from_wolves.is_empty() and not from_bandits.is_empty(),
		"both drop something eventually (%d / %d)" % [from_wolves.size(), from_bandits.size()])
	check(from_wolves.all(func(i): return not i in Loot.CARRIED["bandit"]),
		"nothing a wolf leaves is a weapon or a jerkin")
	check(from_bandits.any(func(i): return i in Loot.CARRIED["bandit"]),
		"a bandit leaves the kit it was holding")
	check(from_bandits.size() > from_wolves.size(),
		"and leaves it more often than a beast leaves anything (%d vs %d)"
			% [from_bandits.size(), from_wolves.size()])

func how_dangerous_decides_how_good() -> void:
	check(Loot.drop_chance(0.125, true) < Loot.drop_chance(5.0, true),
		"a tougher kill is more likely to be worth searching")
	check(Loot.drop_chance(100.0, true) <= Loot.MAX_CHANCE, "the ramp is capped")
	check(Loot.rarity_for(0.25) == "common", "a CR 1/4 kill draws from the common shelf")
	check(Loot.rarity_for(4.0) == "uncommon", "a CR 4 kill, the uncommon one")
	check(Loot.rarity_for(12.0) == "very-rare", "and a CR 12 kill the top one")
	# Cumulative: a big kill can still turn up the cheap stuff, a small one
	# cannot turn up the expensive stuff.
	var low := Loot.consumables_for(0.25)
	var high := Loot.consumables_for(12.0)
	check(low.all(func(i): return i in high), "the big shelf contains the small one")
	check(high.size() > low.size(), "and more besides")
	check(not "potion-of-speed" in low, "a CR 1/4 kill is not carrying a potion of speed")

func the_fight_pays_at_most_a_handful() -> void:
	var many: Array = []
	for _i in 40:
		many.append("bandit")
	for s in range(60):
		check(Loot.for_kills(many, RNG.new(s + 1)).size() <= Loot.MAX_DROPS,
			"forty bandits still come to at most %d things" % Loot.MAX_DROPS)

func it_replays_with_the_seed() -> void:
	var kills := ["bandit", "goblin", "wolf", "ogre"]
	for s in range(20):
		check(Loot.for_kills(kills, RNG.new(s + 1)) == Loot.for_kills(kills, RNG.new(s + 1)),
			"the same seed drops the same things (seed %d)" % (s + 1))
	var runs := {}
	for s in range(60):
		runs[str(Loot.for_kills(kills, RNG.new(s + 1)))] = true
	check(runs.size() > 1, "and different seeds do not (%d distinct outcomes)" % runs.size())

	# An id the catalog has never heard of is skipped, not crashed on: a content
	# pack can name a monster this file has no table for.
	check(Loot.for_kills(["no-such-monster"], RNG.new(1)).is_empty(),
		"an unknown monster drops nothing rather than erroring")

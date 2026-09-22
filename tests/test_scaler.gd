# T8: the difficulty sweeps that back the constants at the top of core/scaler.gd.
# The bands are +/-10 points — autoplay is stochastic and the mult knob is lumpy.
#   godot --headless --path . -s tests/test_scaler.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Power = preload("res://core/rules/power.gd")
const Campaign = preload("res://core/campaign.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const SEEDS := 200
const TARGET := {"easy": 95.0, "normal": 85.0, "hard": 75.0}
const BAND := 10.0

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_control_pricing()
	test_spec_shape()
	test_forest_beasts_stay_on_land()
	test_biome_habitat_filters()
	test_marsh_never_falls_to_mix()
	test_built_place_survives_its_ground()
	test_civilized_roster_is_a_real_faction()
	test_quest_bias()
	test_monotone_difficulty()
	test_power_scale_knob()
	test_win_rates()
	test_biome_boards_are_neutral()
	test_higher_level_party()
	test_boss_pool()
	print("test_scaler: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# T23 — the same body priced with a full lockout, a half-turn debuff and nothing
# at all: control must be worth something, and a lockout must be worth the most.
func test_control_pricing() -> void:
	var plain := _scored("goblin", [])
	var frighten := _scored("goblin", ["monster-frightful-presence"])
	var knock := _scored("goblin", ["monster-knockdown"])
	var stun := _scored("goblin", ["monster-stunning-blow"])
	check(frighten > plain, "a control effect is worth more than none (%.1f > %.1f)" % [frighten, plain])
	check(stun > knock and knock > frighten,
		"the more of a turn it denies, the more it scores (stun %.1f > prone %.1f > fright %.1f)" % [
			stun, knock, frighten])

func _scored(id: String, features: Array) -> float:
	return Power.estimate(Encounter.spawn(id, 1.0, "foe", Vector2i.ZERO, 0, features))["score"]

func test_spec_shape() -> void:
	var spec = Scaler.roster_for(Presets.party(), "normal")
	check(spec.has("monsters") and spec["monsters"] is Array, "roster_for returns a build() spec")
	for e in spec["monsters"]:
		check(e.has("id") and int(e["count"]) > 0, "every entry is {id, count}")
		check(float(e["mult"]) > 0.0, "every entry carries the difficulty multiplier")
	# and it is directly buildable
	var cb = Encounter.build(spec, _party_at(Presets.party()))
	check(cb.team_of("foe").size() == _total(spec), "build() spawns exactly the spec's foes")
	check(Scaler.roster_for([], "normal")["monsters"].size() > 0, "an empty party still gets a roster")

# A Killer Whale showing up alongside a Giant Elk on a forest board was exactly
# this: "beast" is the one faction that spans two habitats (forest/water), and
# nothing filtered on the water half when the theme is landlocked.
func test_forest_beasts_stay_on_land() -> void:
	for seed_value in range(1, 41):
		var spec = Scaler.roster_for(Presets.party(), "normal", {}, "forest-clearing", seed_value)
		for m in spec["monsters"]:
			var habitat: String = String(Catalog.monster(m["id"]).get("habitat", "any"))
			check(habitat in ["forest", "any"],
				"seed %d: %s (habitat %s) has no business in a forest-clearing roster"
					% [seed_value, m["id"], habitat])

# O-biome. A biome names ONE habitat and `any` rides along free, so these are
# the same claim test_forest_beasts_stay_on_land makes, once per kind of ground.
# The marsh is the one that pays: its water entries were unreachable while
# forest-clearing was the only board that ever drew a beast.
func test_biome_habitat_filters() -> void:
	for pair in [["woods", "forest"], ["marsh", "water"]]:
		var biome: String = String(pair[0])
		var want: String = String(pair[1])
		check(String(Scaler.BIOME_HABITAT[biome]) == want, "%s names habitat %s" % [biome, want])
		for seed_value in range(1, 41):
			var spec = Scaler.roster_for(Presets.party(), "normal", {},
				String(Scaler.BIOME_BOARD[biome]), seed_value, 1.0, [], want)
			for m in spec["monsters"]:
				var habitat: String = String(Catalog.monster(m["id"]).get("habitat", "any"))
				check(habitat in [want, "any"],
					"seed %d on %s: %s is habitat %s" % [seed_value, biome, m["id"], habitat])
	check(String(Scaler.BIOME_HABITAT["downs"]) == "", "downs is the unfiltered default fill")

# The half of the wiring that fails QUIETLY, which is why it is worth a test of
# its own. _faction_order picks a faction by seed before the habitat filter
# runs, and six of the fifteen (construct, dragon, giant, goblinoid, kobold,
# undead) have no `water`-or-`any` entry at all — so without _viable_faction two
# marsh seeds in five emptied the pool and fell through to the hand-tuned MIX,
# which is four demo goblins and the code path scaler.gd records as swinging
# 6% to 47% across two TIER retunes. A silent difficulty cliff, on two fights
# in five, on a whole biome.
func test_marsh_never_falls_to_mix() -> void:
	var fell := 0
	for seed_value in range(1, 61):
		var spec = Scaler.roster_for(Presets.party(), "normal", {}, "marsh", seed_value, 1.0, [], "water")
		var ids: Array = spec["monsters"].map(func(m): return String(m["id"]))
		if ids.all(func(i): return i in Scaler.MIX):
			fell += 1
	check(fell == 0, "no marsh seed drops to the demo MIX (%d of 60 did)" % fell)

# A BUILT place beats the ground it stands on. A goblin camp pitched in a marsh
# is still a goblin camp, and goblinoid has no water entry — so the themed path
# has to fall back to the theme's own habitat rather than to MIX.
func test_built_place_survives_its_ground() -> void:
	for seed_value in range(1, 21):
		var spec = Scaler.roster_for(Presets.party(), "normal", {}, "goblin-camp", seed_value, 1.0, [], "water")
		for m in spec["monsters"]:
			check(String(Catalog.monster(m["id"]).get("faction", "")) == "goblinoid",
				"seed %d: a goblin camp in a marsh still fields goblinoids, not %s" % [seed_value, m["id"]])

# The map's peoples are not roster factions, and pin_faction can only pin what
# FACTIONS actually holds.
func test_civilized_roster_is_a_real_faction() -> void:
	check(Scaler.CIVILIZED_ROSTER in Scaler.FACTIONS, "the civilized stand-in is a faction a roster can field")
	var seed_value := 12345
	check(Scaler.pin_faction(seed_value, "human") == seed_value,
		"pin_faction still cannot pin a people — which is the bug world.gd now routes around")

func test_quest_bias() -> void:
	var plain = _counts(Scaler.roster_for(Presets.party(), "normal"))
	var biased = _counts(Scaler.roster_for(Presets.party(), "normal", {"grull": 3.0}))
	check(int(biased.get("grull", 0)) > int(plain.get("grull", 0)),
		"a quest bias puts more of its target in the roster (%d -> %d)" % [
			int(plain.get("grull", 0)), int(biased.get("grull", 0))])
	check(biased.size() > 1, "the bias tilts the mix, it does not replace it")

func test_monotone_difficulty() -> void:
	var chars := Presets.party()
	var prev := 0.0
	for d in ["easy", "normal", "hard"]:
		var s := _spec_power(Scaler.roster_for(chars, d))
		check(s > prev, "%s is worth more than the tier below it (%.1f > %.1f)" % [d, s, prev])
		prev = s

# T92 — the budget scale core/world_threat.gd drives. The whole point of the
# default is that it changes nothing: every win rate in scaler.gd's TUNING header
# was measured through the four-argument call, so the five-argument one had
# better still produce the identical roster, byte for byte, everywhere.
func test_power_scale_knob() -> void:
	var chars := Presets.party()
	for d in ["easy", "normal", "hard"]:
		for seed_value in range(1, 9):
			var plain: Dictionary = Scaler.roster_for(chars, d, {}, "", seed_value)
			var explicit: Dictionary = Scaler.roster_for(chars, d, {}, "", seed_value, 1.0)
			# str(), not ==: separately built Dictionaries are different objects, and
			# what is on trial is their contents.
			check(str(plain) == str(explicit),
				"%s seed %d: power_scale defaults to 1.0 and 1.0 is a no-op" % [d, seed_value])
	# the quest-bias and theme paths go through the same budget, so check one of each
	check(str(Scaler.roster_for(chars, "normal", {"grull": 3.0})) ==
		str(Scaler.roster_for(chars, "normal", {"grull": 3.0}, "", 0, 1.0)),
		"a quest-biased roster is unchanged at scale 1.0")
	check(str(Scaler.roster_for(chars, "hard", {}, "forest-clearing", 4)) ==
		str(Scaler.roster_for(chars, "hard", {}, "forest-clearing", 4, 1.0)),
		"a themed roster is unchanged at scale 1.0")
	# The formula itself, recomputed here from the constants: this is what pins
	# "a knob was added, nothing was retuned" — if TIER/REF_SCORE/CURVE or the
	# shape of _budget() moves, this fails before any sweep has to run.
	var team: float = maxf(1.0, Power.team_score(_party_at(chars)))
	for d in ["easy", "normal", "hard"]:
		var want: float = Scaler.REF_SCORE * pow(team / Scaler.REF_SCORE, Scaler.CURVE) * float(Scaler.TIER[d])
		check(is_equal_approx(Scaler._budget(chars, d), want),
			"%s: the default budget is still REF_SCORE*(team/REF_SCORE)^CURVE*TIER (%.4f vs %.4f)" % [
				d, Scaler._budget(chars, d), want])
		check(Scaler._budget(chars, d) == Scaler._budget(chars, d, 1.0),
			"%s: scale 1.0 is an exact identity on the budget" % d)
		check(is_equal_approx(Scaler._budget(chars, d, 0.5), want * 0.5),
			"%s: the scale multiplies the finished budget and nothing else" % d)
	# and the knob does something when it is actually turned
	var full := _spec_power(Scaler.roster_for(chars, "normal", {}, "", 3, 1.0))
	var half := _spec_power(Scaler.roster_for(chars, "normal", {}, "", 3, 0.5))
	check(half < full, "halving the scale buys a weaker roster (%.1f < %.1f)" % [half, full])
	check(_total(Scaler.roster_for(chars, "normal", {}, "", 3, 0.5)) >= 1,
		"and it is still a roster, not an empty spec")
	# bosses never come through the knob at all — boss_for has no such parameter
	var boss := {"lead": "goblin-archer", "difficulty": "hard", "theme": "goblin-camp"}
	check(str(Scaler.boss_for(chars, boss, 1)) == str(Scaler.boss_for(chars, boss, 1)),
		"boss_for is untouched by the new parameter")

func test_win_rates() -> void:
	var chars := Presets.party()
	print("  level-3 preset party (score %.1f):" % Power.team_score(_party_at(chars)))
	for d in ["easy", "normal", "hard"]:
		var r := _sweep(chars, d, SEEDS)
		check(absf(r["rate"] - TARGET[d]) <= BAND, "%s win rate %.1f%% is within %.0f of %.0f" % [
			d, r["rate"], BAND, TARGET[d]])

# The floor the biome design set for itself: a new board is never free. Both
# carry the same counts as the six that came before — three cover, three or four
# rough, one light source — and this is the check that the counts did what they
# were chosen to do. The first pass is flavour-only ON PURPOSE, so a board that
# played measurably harder or easier than the wood would be a difficulty change
# nobody asked for, smuggled in behind a palette.
# Measured against the SAME sweep with no board named, not against TARGET.
# Neutral here means "plays like the rest of the set", and the set's own hard
# rate sits at the top of TARGET's band — so checking a new board against TARGET
# would fail it for the calibration's offset rather than for anything the board
# does. Measured 2026-09-22 at 200 seeds: baseline 85.0%, downs 85.0% (identical
# roster mix, so this is the board and nothing else), marsh 88.5%.
#
# The marsh's 3.5 points are inside sampling noise — at 200 seeds and p≈0.85,
# one sigma is 2.5 points — but they are not obviously ONLY noise: the marsh
# also ends 1.4 rounds sooner on slightly fewer foes, which is what a smaller,
# squishier pool (26 `water` entries against 240 unfiltered) would look like.
# Worth re-measuring if the water half of the bestiary grows.
const BIOME_DRIFT := 6.0   # two sigma at these seeds, rounded up

func test_biome_boards_are_neutral() -> void:
	var chars := Presets.party()
	print("  O-biome boards, hard (against an unthemed hard sweep of the same size):")
	var base: float = _sweep(chars, "hard", SEEDS)["rate"]
	for biome in ["downs", "marsh"]:
		var r := _sweep(chars, "hard", SEEDS, String(Scaler.BIOME_BOARD[biome]),
			String(Scaler.BIOME_HABITAT[biome]))
		check(absf(r["rate"] - base) <= BIOME_DRIFT,
			"%s plays like the rest of the set (%.1f%% against the set's %.1f%%, drift %.1f of %.0f)" % [
				biome, r["rate"], base, absf(r["rate"] - base), BIOME_DRIFT])

func test_higher_level_party() -> void:
	var chars := [_lvl(Presets.vera(), "fighter", 5), _lvl(Presets.pike(), "rogue", 5),
		_lvl(Presets.ilsa(), "cleric", 5)]
	print("  level-8 party (score %.1f):" % Power.team_score(_party_at(chars)))
	# Four archetypes cannot hit the targets this far up (see scaler.gd's ceiling note);
	# what must hold is that the tiers stay ordered and the fight stays a fight.
	# 150 seeds, not 60: easy and normal both sit near 90% up here, and at 60 seeds
	# a two-point inversion is one fight — noise, not a tuning fact.
	var rates: Array = []
	for d in ["easy", "normal", "hard"]:
		rates.append(_sweep(chars, d, 150)["rate"])
	check(rates[0] >= rates[1] and rates[1] > rates[2], "tiers stay ordered at level 8 (%s)" % str(rates))
	check(rates[0] < 100.0 and rates[2] > 0.0, "neither end is a foregone conclusion at level 8")

# T18 — every boss in the pool is one lead plus an escort, and the pool as a whole
# is a real climax: harder than a hard node, not a wall. Checked pooled, not per
# boss — per-monster rates swing wildly (see scaler.gd's BOSS_LEAD_SHARE note),
# because power.gd prices a lone big bruiser far above what it plays like.
const BOSS_SEEDS := 40
const BOSS_BAND := [15.0, 85.0]

func test_boss_pool() -> void:
	var chars := Presets.party()
	var wins := 0
	var fights := 0
	for boss in Campaign.BOSS_POOL:
		if not boss.has("lead"):
			# The shrine is a plain hard node on a theme that maps to no faction, so it
			# fights the hand-tuned MIX: always MAX_FOES bodies with the whole budget
			# poured into mult. Printed, not banded — it measures far below the faction
			# rosters the TIER sweep above covers (see scaler.gd's boss TUNING note).
			_sweep(chars, boss["difficulty"], SEEDS, boss["theme"])
			continue
		var spec := Scaler.boss_for(chars, boss, 1)
		var lead: Dictionary = spec["monsters"][0]
		check(lead["id"] == boss["lead"] and int(lead["count"]) >= 1, "%s leads with its own monster" % boss["id"])
		check(float(lead["mult"]) >= Scaler.MULT_MIN and float(lead["mult"]) <= Scaler.BOSS_MULT_MAX,
			"%s: the lead's mult stays inside the knob's range (%.2f)" % [boss["id"], float(lead["mult"])])
		check(lead.get("features", []) == boss.get("lead_features", []),
			"%s carries its extra features onto the lead" % boss["id"])
		check(spec["monsters"].size() > 1, "%s brings an escort" % boss["id"])
		var ids := {}
		for e in spec["monsters"]:
			check(not ids.has(e["id"]), "%s: %s appears in one entry only" % [boss["id"], e["id"]])
			ids[e["id"]] = true
		wins += int(_sweep_boss(chars, boss, BOSS_SEEDS)["wins"])
		fights += BOSS_SEEDS
	var rate := 100.0 * wins / fights
	print("    boss pool overall: %dW/%dL (%.1f%%)" % [wins, fights - wins, rate])
	check(rate >= BOSS_BAND[0] and rate <= BOSS_BAND[1],
		"the boss pool is a real climax overall (%.1f%%, want %.0f-%.0f%%)" % [rate, BOSS_BAND[0], BOSS_BAND[1]])
	# the elite path: the same monster, pumped, is worth much more than its stat block
	var elite := {"lead": "goblin-archer", "difficulty": "hard", "theme": "goblin-camp",
		"lead_features": ["monster-multiattack-2"]}
	var plain = Encounter.spawn("goblin-archer", 1.0, "foe", Vector2i.ZERO)
	var boosted = Encounter.spawn("goblin-archer", float(Scaler.boss_for(chars, elite, 1)["monsters"][0]["mult"]),
		"foe", Vector2i.ZERO, 0, elite["lead_features"])
	check(boosted.ac > plain.ac and boosted.max_hp > plain.max_hp and boosted.atk_bonus > plain.atk_bonus,
		"the elite's AC/HP/to-hit are all pumped (%d/%d/%d vs %d/%d/%d)" % [boosted.ac, boosted.max_hp,
			boosted.atk_bonus, plain.ac, plain.max_hp, plain.atk_bonus])
	check(Power.estimate(boosted)["score"] > 3.0 * Power.estimate(plain)["score"],
		"and it is worth several of the common version")

func _sweep_boss(chars: Array, boss: Dictionary, seeds: int) -> Dictionary:
	var wins := 0
	for s in range(1, seeds + 1):
		var sp: Dictionary = Scaler.boss_for(chars, boss, s)
		sp["seed"] = s
		sp["theme"] = boss["theme"]
		var cb = Encounter.build(sp, _party_at(chars))
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		if cb.outcome() == "Victory":
			wins += 1
	var rate := 100.0 * wins / seeds
	print("    boss %-16s -> %dW/%dL (%.1f%%)" % [boss["id"], wins, seeds - wins, rate])
	return {"rate": rate, "wins": wins}

# --- helpers ----------------------------------------------------------

# T16: one roster per seed, each its own faction — the shipped distribution, not
# one lucky warband repeated 200 times.
func _sweep(chars: Array, difficulty: String, seeds: int, theme: String = "",
		habitat: String = "") -> Dictionary:
	var wins := 0
	var rounds := 0
	var foes := 0
	var mult := 0.0
	for s in range(1, seeds + 1):
		var spec: Dictionary = Scaler.roster_for(chars, difficulty, {}, theme, s, 1.0, [], habitat)
		foes += _total(spec)
		mult += float(spec["monsters"][0]["mult"])
		var sp: Dictionary = spec.duplicate(true)
		sp["seed"] = s
		var cb = Encounter.build(sp, _party_at(chars))
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		rounds += cb.round_num
		if cb.outcome() == "Victory":
			wins += 1
	var rate := 100.0 * wins / seeds
	print("    %-7s avg %.1f foes x%.2f -> %dW/%dL (%.1f%%) avg %.1f rounds" % [
		difficulty if theme == "" else theme, float(foes) / seeds, mult / seeds, wins, seeds - wins,
		rate, float(rounds) / seeds])
	return {"rate": rate, "wins": wins}

func _party_at(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

func _lvl(ch, class_id: String, extra: int):
	for i in extra:
		ch.add_level(class_id, -1)
	return ch

func _total(spec: Dictionary) -> int:
	var n := 0
	for e in spec["monsters"]:
		n += int(e["count"])
	return n

func _counts(spec: Dictionary) -> Dictionary:
	var d := {}
	for e in spec["monsters"]:
		d[e["id"]] = int(e["count"])
	return d

func _spec_power(spec: Dictionary) -> float:
	var roster: Array = []
	for e in spec["monsters"]:
		for i in int(e["count"]):
			roster.append(Encounter.spawn(e["id"], float(e["mult"]), "foe", Vector2i.ZERO))
	return Power.team_score(roster)

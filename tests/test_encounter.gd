# T7: spec -> Combat, and the write-back/rewards trip home.
#   godot --headless --path . -s tests/test_encounter.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_build_spec()
	test_placement()
	test_placement_overflow_degrades_gracefully()
	test_mult_scales_the_instance_not_the_data()
	test_outcome_victory()
	test_outcome_defeat_and_deaths()
	test_humanoid_foe_names()
	test_surprise_check()
	test_surprise_round_skips_only_the_foes_first_turn()
	test_ambush_round_skips_only_the_partys_first_turn()
	print("test_encounter: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _chars() -> Array:
	return Presets.party()

func _combatants(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

# A humanoid foe gets a fantasy name, not a bare species label; a non-humanoid
# foe and a party member are untouched; two copies in the same fight differ.
func test_humanoid_foe_names() -> void:
	var goblin_a = Encounter.spawn("goblin", 1.0, "foe", Vector2i(1, 0), 1)
	var goblin_b = Encounter.spawn("goblin", 1.0, "foe", Vector2i(2, 0), 2)
	check(goblin_a.cname.contains(" the Goblin"), "a humanoid foe is named \"<name> the <species>\"")
	check(goblin_a.cname != "Goblin the Goblin", "the name half isn't just the species again")
	check(goblin_a.cname != goblin_b.cname, "two goblins in one fight get different names")
	var again = Encounter.spawn("goblin", 1.0, "foe", Vector2i(1, 0), 1)
	check(again.cname == goblin_a.cname, "the same seed/spot names the same goblin the same way")

	var beast = Encounter.spawn("grull", 1.0, "foe", Vector2i.ZERO)
	check(not beast.cname.contains(" the "), "a non-humanoid foe keeps its plain species name")

# --- T39: surprise + scouting ----------------------------------------
func _fight(seed_v: int):
	# scouts: passive Perception 15, so the party's Stealth can genuinely miss.
	return Encounter.build({"monsters": [{"id": "scout", "count": 2}], "seed": seed_v}, _combatants(_chars()))

func test_surprise_check() -> void:
	var got := []
	for s in [3, 4, 5, 6, 7, 8, 9, 10]:
		var cb = _fight(s)
		var r: bool = Encounter.surprise_check(cb)
		check(r == cb.unseen, "the check's answer is what the fight records (seed %d)" % s)
		check(r == Encounter.surprise_check(_fight(s)), "same seed, same surprise (seed %d)" % s)
		got.append(r)
	check(got.has(true) and got.has(false), "the roll can go either way across seeds: %s" % str(got))

	for s in [3, 4, 5, 6]:
		var cb = _fight(s)
		check(Encounter.surprise_check(cb, true) and cb.unseen,
			"a scouted node is unseen no matter the roll (seed %d)" % s)

	var no_foes = Encounter.build({"monsters": []}, _combatants(_chars()))
	check(not Encounter.surprise_check(no_foes, true), "nobody to surprise, no surprise round")

	# The fight itself must roll identically whether or not the check happened.
	var checked = _fight(11)
	Encounter.surprise_check(checked)
	checked.unseen = false                       # mechanics off; only the RNG stream matters here
	var plain = _fight(11)
	check(_play(checked)["rounds"] == _play(plain)["rounds"], "the surprise roll doesn't disturb the fight's RNG")

func test_surprise_round_skips_only_the_foes_first_turn() -> void:
	var cb = _fight(5)
	check(Encounter.surprise_check(cb, true), "scouted: the party comes in unseen")
	var acted := {1: [], 2: []}
	while cb.round_num <= 2:
		acted[cb.round_num].append(cb.current())
		cb.end_turn()
	check(acted[1].all(func(c): return c.team == "party"), "no foe acts in the surprise round")
	check(_uniq(acted[1].map(func(c): return c.id)).size() == cb.team_of("party").size(),
		"every party member still gets its round-1 turn")
	check(_uniq(acted[2].map(func(c): return c.id)).size() == cb.combatants.size(),
		"round 2 is a normal round again — everyone acts")

# T9x: the camp-ambush counterpart — same one-round skip, the other team eats
# it. Unlike surprise_check, begin_ambush_round() is called unconditionally
# (the watch-check roll already happened in core/world_camp.gd), so this
# tests the combat-engine half only.
func test_ambush_round_skips_only_the_partys_first_turn() -> void:
	var cb = _fight(5)
	cb.begin_ambush_round()
	check(cb.ambushed and not cb.unseen, "ambushed is set, unseen (the other case) is not")
	var acted := {1: [], 2: []}
	while cb.round_num <= 2:
		acted[cb.round_num].append(cb.current())
		cb.end_turn()
	check(acted[1].all(func(c): return c.team == "foe"), "no party member acts in the ambush round")
	check(_uniq(acted[1].map(func(c): return c.id)).size() == cb.team_of("foe").size(),
		"every foe still gets its round-1 turn")
	check(_uniq(acted[2].map(func(c): return c.id)).size() == cb.combatants.size(),
		"round 2 is a normal round again — everyone acts")

func test_build_spec() -> void:
	var chars := _chars()
	var cb = Encounter.build({"monsters": [{"id": "snik", "count": 3}, {"id": "grull", "count": 1}],
		"seed": 5}, _combatants(chars))
	check(cb.combatants.size() == 7, "3 heroes + 4 spawned foes")
	check(cb.team_of("foe").size() == 4, "the foe team is the spec's count")
	var ids: Array = cb.team_of("foe").map(func(c): return c.id)
	check(ids.size() == _uniq(ids).size(), "duplicate spawns get unique ids (%s)" % str(ids))
	check(cb.team_of("foe").all(func(c): return c.src_id in ["snik", "grull"]),
		"every spawn remembers its monsters.json id")
	check(cb.board.get("palette", "") == "shrine", "an empty board argument falls back to the Sunken Shrine")
	var camp = Encounter.build({"monsters": [{"id": "snik", "count": 2}], "seed": 5,
		"theme": "goblin-camp"}, _combatants(chars))
	check(camp.board.get("palette", "") == "camp", "spec[\"theme\"] picks the board")
	check(camp.team_of("foe").all(func(f): return camp.passable(f.pos)),
		"no foe spawns inside a blocking prop")
	check(Encounter.build({"monsters": [{"id": "nosuch", "count": 2}], "seed": 1},
		_combatants(chars)).team_of("foe").is_empty(), "an unknown monster id spawns nothing")
	# same seed, same spec -> same fight
	var a = _play(Encounter.build({"monsters": [{"id": "snik", "count": 2}], "seed": 9}, _combatants(chars)))
	var b = _play(Encounter.build({"monsters": [{"id": "snik", "count": 2}], "seed": 9}, _combatants(chars)))
	check(a["outcome"] == b["outcome"] and a["rounds"] == b["rounds"], "seeded builds replay identically")

func test_placement() -> void:
	# Few enough foes that the shrine board (9 hexes wide) can seat every one
	# of them at the full SPAWN_GAP -- the invariant to prove here is "gap
	# honored when there's room", not "always", which _foe_spots's own
	# documented overflow fallback deliberately doesn't promise (see below).
	var cb = Encounter.build({"monsters": [{"id": "snik", "count": 2}], "seed": 3}, _combatants(_chars()))
	var far := true
	var on_board := true
	for f in cb.team_of("foe"):
		on_board = on_board and f.pos in cb.board["hexes"]
		for p in cb.team_of("party"):
			far = far and Hex.distance(f.pos, p.pos) >= Encounter.SPAWN_GAP
	check(on_board, "every foe spawns on a board hex")
	check(far, "no foe spawns inside the party's lap when the board has room")

# T36: SPAWN_GAP=6 on a 9-hex board can't always seat a crowd at full
# distance -- _foe_spots's own "overflow: the least-bad remaining hexes"
# fallback is deliberate, not a bug. Prove it degrades gracefully instead of
# breaking (still on-board, still one hex per foe) rather than pretending
# the gap always holds.
func test_placement_overflow_degrades_gracefully() -> void:
	var cb = Encounter.build({"monsters": [{"id": "snik", "count": 6}], "seed": 3}, _combatants(_chars()))
	var foes := cb.team_of("foe")
	check(foes.size() == 6, "all 6 still spawn even if the gap can't be honored for all of them")
	var seen := {}
	for f in foes:
		check(f.pos in cb.board["hexes"], "every foe still spawns on a real board hex")
		check(not seen.has(f.pos), "no two foes share a hex")
		seen[f.pos] = true
	var spots: Array = cb.team_of("foe").map(func(c): return c.pos)
	check(spots.size() == _uniq(spots).size(), "no two foes share a hex")

func test_mult_scales_the_instance_not_the_data() -> void:
	var base = Encounter.spawn("grull", 1.0, "foe", Vector2i.ZERO)
	var big = Encounter.spawn("grull", 1.5, "foe", Vector2i.ZERO)
	check(big.max_hp > base.max_hp and big.hp == big.max_hp, "mult raises HP")
	check(big.ac > base.ac and big.atk_bonus > base.atk_bonus, "mult raises AC and to-hit")
	check(big.damage != base.damage, "mult raises damage (%s -> %s)" % [base.damage, big.damage])
	var small = Encounter.spawn("grull", 0.7, "foe", Vector2i.ZERO)
	check(small.max_hp < base.max_hp and small.atk_bonus < base.atk_bonus, "a mult below 1 weakens")
	check(Encounter.spawn("grull", 1.0, "foe", Vector2i.ZERO).max_hp == base.max_hp,
		"monsters.json is untouched by scaling")
	# a caster's DC moves with its to-hit; a brute with no DC stays at 0
	var hyena = Encounter.spawn("hyena", 1.5, "foe", Vector2i.ZERO)
	var hyena1 = Encounter.spawn("hyena", 1.0, "foe", Vector2i.ZERO)
	check(hyena.save_dc == hyena1.save_dc + (hyena.atk_bonus - hyena1.atk_bonus),
		"mult raises save DC in step with to-hit (%d -> %d)" % [hyena1.save_dc, hyena.save_dc])
	check(big.save_dc == 0 if base.save_dc == 0 else true, "no DC stays no DC")

func test_outcome_victory() -> void:
	var party := Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var chars: Array = party.party_characters()
	var cb = Encounter.build({"monsters": [{"id": "snik", "count": 1}], "seed": 4},
		party.to_combatants(Encounter.PARTY_STARTS))
	_play(cb)
	var r = Encounter.resolve_outcome(cb, party)
	check(r["outcome"] == "Victory", "one goblin loses to three heroes")
	check(r["xp"] > 0 and r["gold"] > 0, "a win pays XP and gold (%d / %d)" % [r["xp"], r["gold"]])
	check(r["kills"] == ["snik"], "kills report the source monster id, for T9")
	check(r["deaths"].is_empty(), "nobody died")
	check(r["loot"] is Array, "loot is an array (empty until monsters.json carries drops)")
	var hurt := false
	for c in cb.team_of("party"):
		if c.hp < c.max_hp:
			hurt = true
	# write-back landed on the Characters, whichever of them took the hits
	var carried := false
	for ch in chars:
		if ch.hp_current >= 0 and ch.hp_current < ch.sheet().max_hp:
			carried = true
	check(carried == hurt, "damage taken in the fight persists to the Character")
	var ilsa = party.get_member("ilsa")
	check(ilsa.slots_used.size() > 0, "spell slots spent in the fight persist")
	check(int(ilsa.pools.get("fighter-second-wind", 0)) == 0, "pool bookkeeping only touches its owner")

func test_outcome_defeat_and_deaths() -> void:
	var party := Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	# a wipe is certain; a death takes three failed saves or massive damage, so sweep seeds
	# (x12 since the boards were widened: foes start SPAWN_GAP out, so fewer round-1 swings)
	var any_death := false
	for s in range(1, 31):
		var cb = Encounter.build({"monsters": [{"id": "grull", "count": 8, "mult": 12.0}], "seed": s},
			party.to_combatants(Encounter.PARTY_STARTS))
		_play(cb)
		var r = Encounter.resolve_outcome(cb, party)
		check(r["outcome"] == "Defeat", "eight giant bugbears wipe the party (seed %d)" % s)
		check(r["deaths"].all(func(id): return party.get_member(id) != null), "deaths are party ids")
		for id in r["deaths"]:
			any_death = true
			check(party.get_member(id).hp_current == 0, "a dead hero is written back at 0 HP")
	check(any_death, "some seed kills someone outright")

# --- helpers ----------------------------------------------------------

func _play(cb) -> Dictionary:
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return {"outcome": cb.outcome(), "rounds": cb.round_num}

func _uniq(a: Array) -> Array:
	var seen := {}
	for v in a:
		seen[v] = true
	return seen.keys()

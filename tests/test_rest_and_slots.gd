# The price of magic, enforced: rest and slots (docs/plan/2026-09-24-rest-and-slots.md,
# from the design audit's §1.1, 1.6, 1.7, 1.9, 4.1, 4.2 and 4.3). The model only,
# headless — the screens that draw these rows and lines are tests/test_profile.gd's,
# tests/test_party_screen.gd's and the camp integration test's.
#   godot --headless --path . -s tests/test_rest_and_slots.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const WorldRest = preload("res://core/world_rest.gd")
const WorldSave = preload("res://core/world_save.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Downtime = preload("res://core/downtime.gd")
const Trance = preload("res://core/trance.gd")
const RoadSpells = preload("res://core/road_spells.gd")
const Adapter = preload("res://core/adapter.gd")
const Combatant = preload("res://core/combatant.gd")
const Character = preload("res://core/character.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_slot_table()
	test_combat_slot_table()
	test_arcane_recovery()
	test_trance_bank()
	test_night_walks()
	test_downtime_gate()
	test_camp_refusals()
	test_rope_trick_holds()
	test_alarm_holds()
	print("test_rest_and_slots: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(40, 40), "human", true))
	return w

func _party(ilsa_spells: Array = []) -> Party:
	var p := Party.new()
	for ch in Presets.party():
		if ch.id == "ilsa":
			ch.prepared.append_array(ilsa_spells)
		p.add_member(ch)
	p.gold = 5000
	return p

func _wizard(levels: int) -> Character:
	var w := Character.new()
	w.id = "wiz"
	w.cname = "Mara"
	w.species_id = "human"
	w.background_id = "sage"
	w.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 16, "wis": 10, "cha": 10}
	for i in levels:
		w.add_level("wizard", -1)
	return w

func _warlock() -> Character:
	var w := Character.new()
	w.id = "lock"
	w.cname = "Test Warlock"
	w.species_id = "human"
	w.background_id = "acolyte"
	w.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	for i in 3:
		w.add_level("warlock", -1)
	return w

func _row(rows: Array, level: int) -> Dictionary:
	for r in rows:
		if int(r["level"]) == level:
			return r
	return {}

# The first world-minute from `from` on whose camp seed the night rolls `ambush`.
func _minute_for(w: World, ambush: bool, from := 5000) -> float:
	for t in range(from, from + 4000):
		if WorldCamp.ambush_roll(RNG.new(WorldCamp.camp_seed(float(t), w.player().position))) == ambush:
			return float(t)
	return -1.0

# --- 4.1: one reading of the slots --------------------------------------------

func test_slot_table() -> void:
	var ilsa = Presets.ilsa()
	var full: Array = ilsa.sheet().spellcasting["slots"]
	var rows: Array = Adapter.slot_table(ilsa)
	check(rows.size() == full.filter(func(n): return int(n) > 0).size(), "a fresh cleric: one row per slot level she has")
	check(int(_row(rows, 1)["left"]) == int(full[0]) and int(_row(rows, 1)["max"]) == int(full[0]), "...all full")
	ilsa.slots_used.assign([int(full[0]), 1])
	rows = Adapter.slot_table(ilsa)
	check(not _row(rows, 1).is_empty() and int(_row(rows, 1)["left"]) == 0, "a level spent to nothing is still a row")
	check(int(_row(rows, 1)["max"]) == int(full[0]), "...against the sheet's maximum")
	check(int(_row(rows, 2)["left"]) == int(full[1]) - 1, "spent slots are read off slots_used")
	check(Adapter.slot_pips(_row(rows, 1)) == "L1 " + "○".repeat(int(full[0])), "all spent: every pip hollow (%s)" % Adapter.slot_pips(_row(rows, 1)))
	check(Adapter.slot_pips(_row(rows, 2)) == "L2 " + "●".repeat(int(full[1]) - 1) + "○", "pips: left filled, spent hollow")
	# Font of Magic's unspent slot comes out of a fight as a negative entry.
	ilsa.slots_used.assign([-1])
	check(int(_row(Adapter.slot_table(ilsa), 1)["left"]) == int(full[0]) + 1, "a Font slot reads one over the maximum")
	var lock := _warlock()
	var pact: Dictionary = lock.sheet().spellcasting["pact"]
	var prow: Dictionary = _row(Adapter.slot_table(lock), int(pact["slotLevel"]))
	check(prow.get("pact", false) and int(prow["max"]) == int(pact["count"]), "the warlock's Pact Magic is its own marked row")
	check(Adapter.slot_table(Presets.vera()).is_empty(), "a fighter has no slot rows")
	var p := _party()
	p.get_member("ilsa").slots_used.assign([2])
	check(p.summary("ilsa")["slots"] == Adapter.slot_table(p.get_member("ilsa")), "the party page's row reads the same table")
	check(p.summary("vera")["slots"].is_empty(), "...and a fighter's row has none")

func test_combat_slot_table() -> void:
	var ilsa = Presets.ilsa()
	var full: Array = ilsa.sheet().spellcasting["slots"]
	ilsa.slots_used.assign([int(full[0]) - 1])   # one 1st left, spent in fights before this one
	var c = Adapter.to_combatant(ilsa, "party", Vector2i.ZERO)
	var start: Array = c.slots.duplicate()
	var r1: Dictionary = _row(Adapter.combat_slot_table(c, start), 1)
	check(int(r1["max"]) == int(full[0]) and int(r1["left"]) == 1,
		"the pips' maximum is the sheet's, so earlier fights' spent slots show as hollow")
	c.slots[0] = 0
	r1 = _row(Adapter.combat_slot_table(c, start), 1)
	check(not r1.is_empty() and int(r1["left"]) == 0, "a level with none left still shows")
	var foe = Combatant.new()
	foe.slots.assign([2, 1, 0, 0, 0, 0, 0, 0, 0])
	var fstart: Array = foe.slots.duplicate()
	foe.slots[0] = 1
	var fr: Dictionary = _row(Adapter.combat_slot_table(foe, fstart), 1)
	check(int(fr["max"]) == 2 and int(fr["left"]) == 1, "a foe with no sheet: what it walked on with is its maximum")

# --- 4.2: Arcane Recovery at a short rest ---------------------------------------

func test_arcane_recovery() -> void:
	var wiz := _wizard(5)
	var full: Array = Adapter._full_slots(wiz.sheet())
	check(full[0] >= 2 and full[1] >= 1, "a level 5 wizard has 1st and 2nd level slots")
	check(Adapter.arcane_recovery_left(wiz) == 3, "never rested since the build: the charges read full, not empty")
	# a 3rd, a 2nd and two 1sts spent; half of 5 rounded up is 3 levels back
	wiz.slots_used.assign([2, 1, 1])
	var p := Party.new()
	p.add_member(wiz)
	var w := _world()
	var r: Dictionary = Visit.rest(p, w, "short-rest")
	check(r["recovered"].size() == 1 and r["recovered"][0]["levels"] == [3], "highest first: the 3rd is the pick (%s)" % str(r["recovered"]))
	check(Adapter.slots_left(wiz)[2] == full[2], "...and it is back")
	check(Adapter.arcane_recovery_left(wiz) == 0, "used: nothing left until a long rest")
	check(Visit.rest_note(r).contains("Arcane Recovery brings back a level 3 slot"), "the rest says so: %s" % Visit.rest_note(r))
	var r2: Dictionary = Visit.rest(p, w, "short-rest")
	check(r2["recovered"].is_empty() and Adapter.slots_left(wiz)[0] == full[0] - 2, "once per long rest: the second short rest brings nothing")
	p.last_long_rest_at = -1e12
	Visit.rest(p, w, "long-rest")
	check(Adapter.arcane_recovery_left(wiz) == 3, "a long rest makes it ready again")
	# nothing spent: the rest leaves it for later
	var r3: Dictionary = Visit.rest(p, w, "short-rest")
	check(r3["recovered"].is_empty() and Adapter.arcane_recovery_left(wiz) == 3, "a short rest with nothing spent keeps it")
	# greedy under budget: a 2nd and a 1st when no 3rd is spent
	wiz.slots_used.assign([2, 1, 0])
	check(Adapter.arcane_recovery_auto(wiz) == [2, 1], "no 3rd spent: a 2nd, then a 1st, to the budget of 3")
	check(wiz.slots_used[0] == 1 and wiz.slots_used[1] == 0 and wiz.slots_used[2] == 0, "...refunded on slots_used")
	check(Visit._slot_words([2, 1, 1]) == "a level 2 slot and two level 1 slots", "the words read right")
	check(Adapter.arcane_recovery_auto(Presets.ilsa()).is_empty(), "a cleric has no Arcane Recovery")

# --- 4.3: Trance banks a short rest ---------------------------------------------

func test_trance_bank() -> void:
	var p := _party()
	var elf = p.get_member("pike")
	elf.species_id = "elf"
	elf.dirty()
	check(Trance.has_trance(p), "an elf in the company has Trance")
	var w := _world()
	w.clock.elapsed = 3000.0
	var r: Dictionary = Visit.rest(p, w, "long-rest")
	check(r["banked"] and is_equal_approx(p.trance_rest_until, w.clock.elapsed + Trance.BANK_MINUTES),
		"a long rest banks one short rest, good for a day")
	elf.hp_current = 1
	Trance.apply_rest_bonus(p, w, Vector2.ZERO)
	check(elf.hp_current == 1, "waking does not top anybody up any more (they were rested anyway)")
	# taken first, and not one of the two
	var s1: Dictionary = Visit.rest(p, w, "short-rest")
	check(s1["trance"] and p.short_rests_since_long == 0, "the first short rest is the banked one, and is not counted")
	check(Visit.rest_note(s1).contains("trance banked"), "...and the rest says so")
	check(not Trance.banked(p, w.clock.elapsed), "...and it is spent")
	Visit.rest(p, w, "short-rest")
	Visit.rest(p, w, "short-rest")
	check(p.short_rests_since_long == 2 and not Visit.can_short_rest(p, w), "then the two RAW allows, and no more")
	# banked with the two already gone: still one to take
	p.trance_rest_until = w.clock.elapsed + 100.0
	check(Visit.can_short_rest(p, w), "a banked rest can be taken with the day's two gone")
	var s4: Dictionary = Visit.rest(p, w, "short-rest")
	check(s4["trance"] and p.short_rests_since_long == 2 and not Visit.can_short_rest(p, w), "...and it does not touch the count")
	# a day, no more
	p.trance_rest_until = w.clock.elapsed + 10.0
	w.clock.elapsed += 11.0
	check(not Trance.banked(p, w.clock.elapsed) and not Visit.can_short_rest(p, w), "a day on, the bank has lapsed")
	# the next long rest without an elf clears it rather than stacking
	p.trance_rest_until = w.clock.elapsed + 500.0
	elf.species_id = "human"
	elf.dirty()
	Visit.rest(p, w, "long-rest")
	check(p.trance_rest_until < 0.0, "a long rest with nobody in trance leaves nothing banked")
	# saved, and an old save reads as none
	p.trance_rest_until = 1234.0
	check(is_equal_approx(WorldSave._party_from(WorldSave._party_dict(p)).trance_rest_until, 1234.0), "the bank survives a save")
	var old: Dictionary = WorldSave._party_dict(p)
	old.erase("trance_rest_until")
	check(WorldSave._party_from(old).trance_rest_until < 0.0, "an old save has nothing banked")

# --- 1.7: the night is walked -----------------------------------------------------

func test_night_walks() -> void:
	# No settlement: a goblin hunter chases towns too, and one beside the camp
	# would bring it here for its own reasons.
	var w := World.new()
	w.add_party(World.RoamingParty.new("player", Vector2(40, 40), "human", true))
	var me = w.player()
	var walker = w.add_party(World.RoamingParty.new("patrol", Vector2(-2000, 0), "human"))
	WorldAI.patrol(walker, [Vector2(-2000, 0), Vector2(-2000, -3000)])
	var hunter = w.add_party(World.RoamingParty.new("hunter", Vector2(3000, 3000), "goblinoid"))
	WorldAI.hunt(hunter)
	check(WorldAI.is_hostile(hunter, me), "fixture: the goblins hunt the company")
	var p := _party()
	p.last_long_rest_at = -1e12
	w.clock.elapsed = 100.0
	w.clock.pause()   # a visit holds the map; the night still passes
	var steps := [0]
	var r: Dictionary = Visit.rest(p, w, "long-rest", func(dt): steps[0] += 1)
	check(is_equal_approx(w.clock.elapsed, 100.0 + Visit.LONG_REST_MINUTES), "the night is exactly eight hours")
	check(steps[0] == int(Visit.LONG_REST_MINUTES / WorldRest.CHUNK), "...walked in %d steps, each handed to the screen (%d)" % [
		int(Visit.LONG_REST_MINUTES / WorldRest.CHUNK), steps[0]])
	check(walker.position.distance_to(Vector2(-2000, 0)) > 100.0, "a patrol walked its road in the night")
	check(me.position == Vector2(40, 40), "the sleeping company did not move")
	check(hunter.position.distance_to(me.position) > 1000.0, "a hunter does not come for a sleeping camp")
	check(is_equal_approx(p.last_long_rest_at, w.clock.elapsed) and p.world_now == w.clock.elapsed, "the rest is stamped at the end of the night")
	check(r["lines"] is Array, "the night's raid lines come back for the screen")
	# the control: on the road, the same hunter does come
	var w2 := World.new()
	w2.add_party(World.RoamingParty.new("player", Vector2(40, 40), "human", true))
	var h2 = w2.add_party(World.RoamingParty.new("hunter", Vector2(3000, 3000), "goblinoid"))
	WorldAI.hunt(h2)
	for i in 480:
		WorldAI.update(w2, 1.0)
		w2.tick(1.0)
	check(h2.position.distance_to(w2.player().position) < 100.0, "awake, the hunter closes in over the same eight hours")

# --- 1.9: downtime respects the 24-hour gate ---------------------------------------

func test_downtime_gate() -> void:
	var w := _world()
	var s = w.settlements[0]
	var p := _party()
	var ilsa = p.get_member("ilsa")
	w.clock.elapsed = 10000.0
	p.last_long_rest_at = w.clock.elapsed   # rested this morning
	ilsa.slots_used.assign([2])
	ilsa.hp_current = 3
	check(Downtime.spend_days(p, w, s, 1) > 0, "a day's work is paid for")
	check(is_equal_approx(w.clock.elapsed, 10000.0 + Downtime.DAY), "the day passes")
	check(ilsa.slots_used.size() > 0 and ilsa.slots_used[0] == 2 and ilsa.hp_current == 3,
		"...but the night is not a long rest: the last one was sixteen hours before it")
	check(is_equal_approx(p.last_long_rest_at, 10000.0), "...and the rest stamp does not move")
	Downtime.spend_days(p, w, s, 1)
	check(Adapter.slots_left(ilsa)[0] == int(ilsa.sheet().spellcasting["slots"][0]) and ilsa.hp_current < 0,
		"a day later the gate is open, and the night refills")
	check(is_equal_approx(p.last_long_rest_at, w.clock.elapsed), "...and is stamped")
	p.last_long_rest_at = w.clock.elapsed
	ilsa.slots_used.assign([1])
	Downtime.spend_days(p, w, s, Downtime.TRAIN_DAYS)
	check(Adapter.slots_left(ilsa)[0] == int(ilsa.sheet().spellcasting["slots"][0]), "five days: the last night is a long rest")

# --- 1.6 / 1.7: making camp ----------------------------------------------------------

func test_camp_refusals() -> void:
	var w := _world()
	var p := _party()
	p.stash_add(WorldCamp.CAMP_KIT_ITEM)
	w.clock.elapsed = 5000.0
	p.last_long_rest_at = w.clock.elapsed
	var r: Dictionary = WorldCamp.make_camp(p, w, 24.0)
	check(not r["ok"] and r["why"] == "tired", "not tired yet: refused")
	p.last_long_rest_at = -1e12
	var band = w.add_party(World.RoamingParty.new("raider", w.player().position + Vector2(10, 0), "bandit"))
	r = WorldCamp.make_camp(p, w, 24.0)
	check(not r["ok"] and r["why"] == "hostile" and r["text"] == WorldCamp.HOSTILE_TEXT, "a hostile band in reach: refused, and said so")
	check(p.stash_count(WorldCamp.CAMP_KIT_ITEM) == 1 and is_equal_approx(w.clock.elapsed, 5000.0), "...with nothing spent and no time gone")
	band.position = w.player().position + Vector2(200, 0)
	check(not WorldCamp.hostile_near(w, 24.0), "out of reach, the same band is no bar")
	w.parties.erase(band)
	p.stash_remove(WorldCamp.CAMP_KIT_ITEM, 1)
	r = WorldCamp.make_camp(p, w, 24.0)
	check(not r["ok"] and r["why"] == "kit", "no kit and no Rope Trick: refused")

func test_rope_trick_holds() -> void:
	var w := _world()
	var p := _party(["rope-trick"])
	var ilsa = p.get_member("ilsa")
	p.last_long_rest_at = -1e12
	RoadSpells.cast(p, ilsa, "rope-trick", 0.0)
	check(p.safe_camp and p.camp_holds.size() == 1 and int(p.camp_holds[0]["level"]) == 2, "Rope Trick is cast from a 2nd, and the slot is held")
	check(WorldSave._party_from(WorldSave._party_dict(p)).camp_holds == p.camp_holds, "the hold survives a save")
	# an inn night before the camp: the spell is still waiting, the slot still spent
	w.clock.elapsed = 2000.0
	var inn: Dictionary = Visit.rest(p, w, "long-rest")
	check(ilsa.slots_used.size() > 1 and ilsa.slots_used[1] == 1 and p.safe_camp, "a long rest before the camp keeps the slot spent")
	check(Visit.rest_note(inn).contains("Rope Trick stays spent"), "...and says so: %s" % Visit.rest_note(inn))
	# the camp: no kit, a quiet night, and the morning after the slot is still gone
	w.clock.elapsed = _minute_for(w, false)
	p.last_long_rest_at = -1e12
	var r: Dictionary = WorldCamp.make_camp(p, w, 24.0)
	check(r["ok"] and r["roped"] and not r["ambush"], "the rope is the kit: a camp with none in the stash")
	check(ilsa.slots_used[1] == 1 and r["rest"]["held"].size() == 1, "the slot is not refunded by the rest it made possible")
	check(not p.safe_camp and p.camp_holds.is_empty(), "the spell is spent and the hold let go")
	check(ilsa.hp_current < 0 and ilsa.slots_used[0] == 0, "...everything else came back")
	w.clock.elapsed += Visit.LONG_REST_COOLDOWN
	Visit.rest(p, w, "long-rest")
	check(Adapter.slots_left(ilsa)[1] == int(ilsa.sheet().spellcasting["slots"][1]), "the next long rest gives it back")
	# Rope Trick does not cancel the ambush roll
	var t := _minute_for(w, true)
	check(t >= 0.0, "fixture: an ambush minute exists")
	w.clock.elapsed = t
	p.last_long_rest_at = -1e12
	ilsa.slots_used.assign([])
	RoadSpells.cast(p, ilsa, "rope-trick", t)
	r = WorldCamp.make_camp(p, w, 24.0)
	check(r["ok"] and r["roped"] and r["ambush"] and r["watch"].has("ok"), "a roped camp can still be jumped in the night")
	check(is_equal_approx(w.clock.elapsed, t) and not p.safe_camp and p.camp_holds.is_empty(), "no rest, the rope spent, the hold let go")
	check(ilsa.slots_used[1] == 1, "...and the slot it cost is simply spent")

func test_alarm_holds() -> void:
	var w := _world()
	var p := _party(["alarm"])
	var ilsa = p.get_member("ilsa")
	p.stash_add(WorldCamp.CAMP_KIT_ITEM, 2)
	p.last_long_rest_at = -1e12
	RoadSpells.cast(p, ilsa, "alarm", 0.0)
	w.clock.elapsed = _minute_for(w, false)
	var r: Dictionary = WorldCamp.make_camp(p, w, 24.0)
	check(r["ok"] and not r["ambush"] and r["alarm"], "a warded, quiet night")
	check(ilsa.slots_used[0] == 1, "Alarm's slot stays spent through the night it warded")
	check(not p.alarm_set and p.camp_holds.is_empty(), "the ward is spent by the camp it was cast for")
	# the ward on a night that is jumped: heard, whatever the watch rolled
	var t := _minute_for(w, true)
	w.clock.elapsed = t
	p.last_long_rest_at = -1e12
	RoadSpells.cast(p, ilsa, "alarm", t)
	r = WorldCamp.make_camp(p, w, 24.0)
	check(r["ambush"] and r["watch"]["ok"] and r["watch"]["char_id"] == "alarm", "Alarm still hears the ambush coming")

# The turn resolver. Pure logic, no nodes. Mutates combatant state, appends to `log`.
# Straight-line functions only — no reaction PROMPTS (combat-design.md §2). The
# reactions themselves are real and general: see fire_reactions() below, which
# resolves them mid-moment without ever stopping to ask.
extends RefCounted

const Dice = preload("res://core/dice.gd")
const Hex = preload("res://core/hex.gd")
const Effects = preload("res://core/rules/effects.gd")
const Ach = preload("res://core/achievements.gd")
const Barks = preload("res://core/barks.gd")
const Sound = preload("res://core/audio.gd")
const WeaponSfx = preload("res://core/weapon_sfx.gd")
const Rng = preload("res://core/rng.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Potions = preload("res://core/potions.gd")

const FT_PER_HEX := 6  # adapter.gd's convention

# Engine-only states that behave like conditions but aren't the official 15, so
# they can't live in data/effects/conditions.json (validated against the catalog).
const ENGINE_CONDS := {
	"dodging": {"attacks_against": "dis"},
	"hidden": {"own_attacks": "adv"},
	"helped": {"own_attacks": "adv"},
	"reckless": {"own_attacks": "adv", "attacks_against": "adv"},
	"sapped": {"own_attacks": "dis"},    # weapon mastery Sap
	"slowed": {"speed_penalty_ft": 10},  # weapon mastery Slow
}

const MAX_ROUNDS := 60  # safety guard; a real fight ends in ~4-6

var rng
var combatants: Array = []
var party = null   # core/party.gd when a real party fights: its stash is the potion shelf
# T19: does what happens in here count towards this machine's achievements?
# False for the off-screen fights core/world_battle.gd resolves between two NPC
# bands — both sides are strangers, and one of them is only called "party"
# because Encounter.build only ever spawns the foe side.
var tracked := true
# Per-fight bookkeeping for the achievements that are about a whole fight
# rather than a single blow: the two ends of the die, and a turn's body count.
var _saw_nat20 := false
var _saw_nat1 := false
var _kills_this_turn := 0
var board: Dictionary = {}
var order: Array = []
var turn_idx: int = 0
var round_num: int = 1
var log: Array[String] = []
# T19: party combatant ids that hit 0 HP at any point this fight. Read back out by
# encounter.resolve_outcome() so campaign.gd can tell a flawless hard win from a
# messy one; "down" itself is erased the moment someone gets back up.
var downed: Dictionary = {}

# --- objectives (core/objectives.gd; the spec is docs/superpowers/specs/
# 2026-09-20-encounter-objectives-design.md). {} = rout: the fight every fight
# was before. `exit` is written here by Encounter.build, never into the spec.
const Objectives = preload("res://core/objectives.gd")
var objective: Dictionary = {}
var objective_done := false      # the deed is done: the gate held, the road reached, the quarry down
var objective_failed := false    # the captive killed, the carter dead, the quarry gone — the fight goes on

func objective_kind() -> String:
	return String(objective.get("kind", ""))

# The one combatant carrying a status (captive, carter, quarry), or null.
func with_status(s: String):
	for c in combatants:
		if c.has(s):
			return c
	return null

# The conscious party without its bystanders: who can act, who must reach the road.
func heroes() -> Array:
	return combatants.filter(func(c): return c.team == "party" and c.conscious() and not c.has("bystander"))

# --- the rules of each kind ---------------------------------------------------
#
# hold     Victory at the top of round `rounds` + 1 with anyone standing; a
#          wave arrives at the top of each Objectives.WAVE_ROUNDS round.
# rescue   a hero adjacent to the captive frees it (no action); unfreed at the
#          top of round `deadline` + 1, the captors kill it. The fight goes on.
# breakout every conscious hero on an exit hex ends the fight, a Victory.
# hunt     the quarry ending its turn on an exit hex is gone (objective failed,
#          fight goes on vs the escort); the quarry dead ends the fight, a Victory.
# escort   the carter dead fails the objective; the fight goes on.

# The top of a new round: waves, and the captors' deadline.
func _objective_round() -> void:
	match objective_kind():
		"hold":
			var waves: Array = objective.get("waves", [])
			var i: int = Objectives.WAVE_ROUNDS.find(round_num)
			if i >= 0 and i < waves.size():
				_spawn_wave(waves[i])
			if round_num > int(objective.get("rounds", 0)) and not _team_out("party") and not objective_done:
				objective_done = true
				log.append("The way behind is barred — the passage held.")
		"rescue":
			var cap = with_status("captive")
			if cap != null and not cap.has("freed") and not cap.is_dead() \
					and round_num > int(objective.get("deadline", 0)):
				log.append("Nobody reached %s in time. The captors make sure of it." % cap.cname)
				_kill(cap)

# A wave comes in from the far side and rolls its own initiative (_join_order),
# on the fight's own stream so both co-op peers see the same arrivals.
func _spawn_wave(roster: Array) -> void:
	var Enc = load("res://core/encounter.gd")   # load: encounter.gd preloads this file
	var taken: Array = combatants.filter(func(c): return not c.is_dead()).map(func(c): return c.pos)
	var spots: Array = Enc.far_hexes(board, taken, 12)
	var i := 0
	var names: Array = []
	for e in roster:
		var count: int = maxi(1, int(e.get("count", 1)))
		for n in count:
			if i >= spots.size():
				break
			var c = Enc.spawn(String(e["id"]), float(e.get("mult", 1.0)), "foe", spots[i],
				n + 1 if count > 1 else 0, e.get("features", []))
			if c == null:
				continue
			c.id = "w%d-%s" % [round_num, c.id]
			combatants.append(c)
			_join_order(c)
			names.append(c.cname)
			i += 1
	if not names.is_empty():
		log.append("More of them, from the far side: %s." % ", ".join(names))

# The deeds that are a matter of standing somewhere — reaching the captive,
# reaching the road — checked after every hero move and at every turn's end.
func _objective_touch(c) -> void:
	if c == null or c.team != "party" or not c.conscious() or c.has("bystander"):
		return
	match objective_kind():
		"rescue":
			var cap = with_status("captive")
			if cap != null and not cap.has("freed") and not cap.is_dead() and Hex.distance(c.pos, cap.pos) <= 1:
				cap.statuses["freed"] = true
				log.append("%s cuts %s loose." % [c.cname, cap.cname])
		"breakout":
			if objective_done:
				return
			var exit: Array = objective.get("exit", [])
			for h in heroes():
				if not (h.pos in exit):
					return
			objective_done = true
			log.append("The party is through — the road is under their feet, and the rest can chase.")

# The quarry ending its turn on the far edge is off the board: not killed (no
# loot, no XP — it took those with it), but `dead` is what `order` carries
# for a gap, the same reason _fade_if_expired leaves a body.
func _quarry_escape(q) -> void:
	q.statuses["escaped"] = true
	q.statuses["dead"] = true
	q.hp = 0
	objective_failed = true
	log.append("%s is into the trees and gone." % q.cname)

func _objective_over() -> bool:
	return objective_done and objective_kind() in ["hold", "breakout", "hunt"]

# Was the deed done — for the spoils page and the pay. The kinds that end the
# fight themselves are judged the moment they do; rescue and escort at the end.
func objective_result() -> bool:
	match objective_kind():
		"rescue":
			var cap = with_status("captive")
			return cap != null and cap.has("freed") and not cap.is_dead()
		"escort":
			var car = with_status("carter")
			return car != null and not car.is_dead()
		"hold":
			return objective_done or _team_out("foe")   # a rout holds the gate too
		"breakout":
			return objective_done   # the deed is the road; a rout is a win the kills already paid for
		"hunt":
			return objective_done
	return false

# The HUD's one line under the round counter.
func objective_line() -> String:
	match objective_kind():
		"hold":
			var r: int = int(objective.get("rounds", 0))
			return "Hold — round %d of %d" % [mini(round_num, r), r]
		"rescue":
			var cap = with_status("captive")
			if cap == null or cap.is_dead():
				return "Captive — lost"
			if cap.has("freed"):
				return "Captive — freed"
			var left: int = maxi(0, int(objective.get("deadline", 0)) - round_num + 1)
			return "Captive — %d round%s left" % [left, "" if left == 1 else "s"]
		"breakout":
			var exit: Array = objective.get("exit", [])
			var hs: Array = heroes()
			var there: int = hs.filter(func(h): return h.pos in exit).size()
			return "Road — %d of %d heroes there" % [there, hs.size()]
		"hunt":
			var q = with_status("quarry")
			if q == null:
				return ""
			if q.has("escaped"):
				return "Quarry — gone"
			if q.is_dead():
				return "Quarry — down"
			var d := 1 << 30
			for e in objective.get("exit", []):
				d = mini(d, Hex.distance(q.pos, e))
			return "Quarry — %d hex%s from the treeline" % [d, "" if d == 1 else "es"]
		"escort":
			var car = with_status("carter")
			if car == null:
				return ""
			return "Carter — dead" if car.is_dead() else "Carter — %d HP" % car.hp
	return ""

# T39: the party opened the fight unseen (Stealth beat the foes' passive
# Perception, or they scouted the node). 2024 PHB surprise: the surprised side
# rolls Initiative with Disadvantage — no lost round (that was 2014's rule, and
# the one this engine used until 2026-09-19). See _surprise().
var unseen := false

# T9x: the reverse — a camp ambush the party's watch failed to spot. The party
# is the surprised side and takes the Disadvantage.
var ambushed := false

# T26 barks: a cosmetic side channel. Entries are {"id": combatant id, "text": line};
# the board scene drains it each frame. Nothing in this file reads it back.
var barks: Array = []
const BARK_QUEUE_MAX := 8   # nobody draining (headless, campaign) must not grow it
var _bark_rng = null         # null under SORCMERC_FAST — barks skipped entirely

func _init(_rng, _combatants: Array, _board: Dictionary) -> void:
	rng = _rng
	combatants = _combatants
	board = _board
	# Own stream, seeded off the combat seed: reproducible per seed, and a fast/headless
	# run (which skips barks) still rolls the *fight* identically to a played one.
	if OS.get_environment("SORCMERC_FAST") == "":
		_bark_rng = Rng.new((rng.seed_value ^ 0x5EEDBA12) & 0xFFFFFFFF)
	_roll_initiative()

# T27: the same moments the barks fire on are the moments the SFX fire on, so the
# sound hangs off this one function rather than a second set of hookpoints.
# Empty = that trigger has no sting. Audio is a no-op headlessly.
const BARK_SFX := {"hit": "hit", "crit": "crit", "kill": "kill", "down": "down",
	"low_hp": "", "victory": "victory"}

# Fire a bark for `c` on `trigger` ("hit" | "crit" | "kill" | "low_hp" | "down" |
# "victory"). Cosmetic: never gates, never touches the combat RNG, never fails loudly.
# T9z: `sfx` overrides the trigger's default sting — resolve_attack passes the
# attacker's weapon-specific hit so a bow and a mace stop sounding identical.
func bark(c, trigger: String, sfx := "") -> void:
	var sound: String = sfx if sfx != "" else BARK_SFX.get(trigger, "")
	if sound != "":
		Sound.play_sfx(sound)   # before the returns below: sound plays even in a fast run
	if _bark_rng == null or c == null:
		return
	var faction := ""
	if c.team != "party" and c.src_id != "":
		faction = String(Catalog.monster(c.src_id).get("faction", ""))
	var text := Barks.line(_bark_rng, c.team, faction, trigger)
	if text == "":
		return
	# T31: a line never fires silently — pair it with this speaker's gibberish stinger.
	Sound.play_bark(Barks.voice(c.team, faction) + str(_bark_rng.roll_die(Barks.VARIANTS)))
	barks.append({"id": c.id, "text": text})
	if barks.size() > BARK_QUEUE_MAX:
		barks.pop_front()

# --- board -----------------------------------------------------------

func passable(p: Vector2i) -> bool:
	return p in board["hexes"] and not object_at(p).get("blocks_movement", false)

func is_cover(p: Vector2i) -> bool:
	return p in board["cover"]

func _rough() -> Array:
	return board.get("rough", [])

func region_at(p: Vector2i) -> String:
	var f = board.get("region_at")
	return f.call(p) if f is Callable else ""

# Only hostiles wall a hex off. An ally's space can be walked THROUGH (5.5e
# "Moving Around Other Creatures") — it just cannot be stopped in, which
# move_field() enforces by erasing those hexes after the flood. Before this, a
# melee foe queued behind its own archer in a choke stood there all fight.
# Not enemies_of(): a hidden foe is unseen, not incorporeal.
func _blockers(mover) -> Array:
	return combatants.filter(func(c): return c.team != mover.team and c.conscious()).map(func(c): return c.pos)

func _ally_hexes(mover) -> Array:
	return allies_of(mover).map(func(c): return c.pos)

func _hex_free(p: Vector2i, ignore = null) -> bool:
	for c in combatants:
		if c != ignore and c.conscious() and c.pos == p:
			return false
	return true

# --- interactables (T11) ---------------------------------------------
# board["objects"]: [{type, pos, hazard?: {dice, damage_type}, hp?, blocks_movement?,
# explosive?}]. The Sunken Shrine's brazier is one of these.

func objects() -> Array:
	return board.get("objects", [])

func object_at(p: Vector2i) -> Dictionary:
	for o in objects():
		if o["pos"] == p:
			return o
	return {}

# The hazard `c` is standing next to — the brazier, a campfire. {} if none.
func adjacent_hazard(c) -> Dictionary:
	for o in objects():
		if o.has("hazard") and Hex.distance(c.pos, o["pos"]) <= 1:
			return o
	return {}

func adjacent_to_hazard(c) -> bool:
	return not adjacent_hazard(c).is_empty()

# The whole rule of "Shove → brazier": you can only put somebody in the fire if
# they are already standing next to it. One function because it is asked twice —
# legal_target() asks it so the button is never offered or clickable, and
# perform() asks it again so a shove that reaches the resolver some other way
# cannot spend the action on something that could never do anything.
func can_shove_into_hazard(target) -> bool:
	return target != null and not adjacent_hazard(target).is_empty()

# A destructible neighbour (barrel, crate). {} if none.
func smashable_near(c) -> Dictionary:
	for o in objects():
		if int(o.get("hp", 0)) > 0 and Hex.distance(c.pos, o["pos"]) <= 1:
			return o
	return {}

func destroy_object(o: Dictionary, by = null) -> void:
	var arr: Array = objects()
	for i in arr.size():
		if arr[i]["pos"] == o["pos"]:
			arr.remove_at(i)
			break
	if not o.get("explosive", false):
		return
	var h: Dictionary = o.get("hazard", {})
	var dmg := Dice.roll(rng, String(h.get("dice", "2d6")))
	log.append("The %s bursts — %d %s to everything beside it." % [o["type"], dmg,
		h.get("damage_type", "fire")])
	if tracked and by != null and by.team == "party":
		Ach.unlock("explosive")
	Sound.play_sfx("burst")
	for c in combatants:
		if c.conscious() and Hex.distance(c.pos, o["pos"]) <= 1:
			_apply_damage(c, dmg, String(h.get("damage_type", "")))

# AoE damage claims destructible terrain caught in it too, not just whoever's
# standing there — a barrel in a fireball's blast shouldn't survive it just
# because "smash" is normally its own separate action. duplicate() first:
# destroy_object mutates the same array objects() hands back.
func _destroy_in_area(hexes: Array, by = null) -> void:
	for o in objects().duplicate():
		if int(o.get("hp", 0)) > 0 and o["pos"] in hexes:
			log.append("The %s is caught in the blast and comes apart." % o["type"])
			destroy_object(o, by)

func _roll_initiative() -> void:
	for c in combatants:
		c.init_roll = Dice.d20(rng, Dice.ADV if c.init_adv else Dice.NORMAL).nat + c.init_mod
	# A bystander (a captive, a carter) has no turn: it stands where it is put.
	order = combatants.filter(func(c): return not c.has("bystander"))
	order.sort_custom(_init_before)
	var names: Array = []
	for c in order:
		names.append("%s(%d)" % [c.cname, c.init_roll])
	log.append("Initiative: " + ", ".join(names))

func _init_before(a, b) -> bool:
	if a.init_roll != b.init_roll:
		return a.init_roll > b.init_roll
	if a.init_mod != b.init_mod:
		return a.init_mod > b.init_mod
	return a.team == "party"

# --- turn lifecycle -------------------------------------------------------

func current():
	return order[turn_idx]

func begin_turn() -> void:
	var c = current()
	# Not in begin_turn_for(): summon() calls that one mid-turn to stand a new
	# creature up, and a wolf arriving must not wipe the tally of what the
	# druid who called it has already killed this turn.
	_kills_this_turn = 0
	begin_turn_for(c)
	if c.is_down():
		_death_save(c)

func begin_turn_for(c) -> void:
	_fade_if_expired(c)
	c.new_turn()   # action/bonus/reaction/move + turn-long statuses (spec §7)
	# An answer is given for one trigger. Anything still sitting here was asked
	# about something that never happened — the caster died first, the swing
	# went elsewhere — and must not be spent on whatever comes next.
	reaction_intent.clear()
	var held = c.statuses.get("concentrating")
	if held is Dictionary and round_num >= int(held.get("until_round", 0)):
		_end_concentration(c, "lets %s lapse" % Effects.humanize(String(held["spell"])))
	_expire_conditions(c)
	_zone_touch(c)
	c.econ["action"] = int(c.econ["action"]) + _buff_sum(c, "extra_action")
	if _buff_sum(c, "speed_mult") > 0:
		c.econ["move_left"] = int(c.econ["move_left"]) * _buff_sum(c, "speed_mult")
	_regenerate(c)
	_auto_stand(c)
	_release_helps(c)
	_release_grapples()
	if round_num == 1:
		for v in c.verbs:   # Ambusher's Leap: +10 ft on the first turn of a fight
			if v.has("first_round_speed_ft"):
				c.econ["move_left"] = int(c.econ["move_left"]) + hexes_from_ft(int(v["first_round_speed_ft"]))
	if _no_economy(c, "action"):
		_end_lapsing_buffs(c, "is too dazed to keep it up")   # Rage ends when Incapacitated

# Help's advantage is "before the start of the helper's next turn" (RAW): the
# helper's turn is what takes it back, not the ally's.
func _release_helps(helper) -> void:
	for o in combatants:
		var h = o.statuses.get("helped")
		if h is Dictionary and h.get("by") == helper:
			o.statuses.erase("helped")

# A summon with a clock on it (Invoke Duplicity's minute) goes at the start of
# its own turn. Killed, not erased: a corpse is what `order` is built to carry,
# and removing an entry would slide turn_idx under the live turn — the same
# reason _end_concentration leaves a faded summon standing as a body.
func _fade_if_expired(c) -> void:
	var s = c.statuses.get("summoned")
	if not (s is Dictionary and s.has("fades_tick")) or c.is_dead():
		return
	if _tick() <= int(s["fades_tick"]):
		return
	c.hp = 0
	c.statuses["dead"] = true
	log.append("%s fades." % c.cname)

# What the drinker's potion buffs add up to for one key (core/potions.gd).
func _buff_sum(c, key: String) -> int:
	var n := 0
	for id in c.statuses:
		var s = c.statuses[id]
		if s is Dictionary:
			n += int(s.get(key, 0))
	return n

func _buff_flag(c, key: String) -> bool:
	for id in c.statuses:
		var s = c.statuses[id]
		if s is Dictionary and s.get(key, false):
			return true
	return false

# A condition applied with duration "round" lasts until the bearer's next turn:
# one lost turn, never a permanent lockout (nothing else in the engine ends them).
func _expire_conditions(c) -> void:
	for id in c.statuses.keys():
		var s = c.statuses[id]
		if s is Dictionary and s.has("until_tick") and _tick() > int(s["until_tick"]):
			c.statuses.erase(id)
			log.append("%s shakes off %s." % [c.cname, id])

# Ticks count turns with a fixed stride, not order.size(): a summon joining
# (or a corpse leaving) the order mid-fight must not re-time every until_tick.
const TICK_STRIDE := 1000
func _tick() -> int:
	return round_num * TICK_STRIDE + turn_idx

# Trolls and friends: a heal_self verb with trigger start_of_turn, no button.
func _regenerate(c) -> void:
	if not c.conscious():
		return
	for v in c.verbs:
		if v["kind"] == "heal_self" and v.get("trigger", "") == "start_of_turn" and c.hp < c.max_hp:
			heal(c, int(v.get("amount", 0)))

# Standing up from prone is free-ish and automatic at the top of your own turn
# (no "spend your whole move lying there" busywork) but still costs half your
# speed, per RAW — deducted from this turn's move budget before anything else
# touches it. A feature can shrink the cost via a data-driven multiplier
# (stand_cost_mult on the feature's effects.json entry); nothing grants one
# yet, so the discount is 0% until something does.
func _auto_stand(c) -> void:
	if not c.has("prone"):
		return
	# Hideous Laughter's prone is the spell holding you down: no getting up
	# until it ends, and no half-move charged for trying.
	if c.statuses["prone"] is Dictionary and c.statuses["prone"].has("held_by"):
		return
	c.statuses.erase("prone")
	var mult := 1.0
	for fid in c.features:
		var e := Effects.feature(fid)
		if e.has("stand_cost_mult"):
			mult = minf(mult, float(e["stand_cost_mult"]))
	var cost: int = int(c.speed * 0.5 * mult)
	c.econ["move_left"] = maxi(0, int(c.econ.get("move_left", 0)) - cost)
	log.append("%s scrambles up off the ground (-%d move)." % [c.cname, cost])

func end_turn() -> void:
	var c0 = current()
	c0.has_acted = true
	_repeat_saves(c0, "end_turn")
	_rage_upkeep(c0)
	_objective_touch(c0)
	if c0.has("quarry") and c0.conscious() and c0.pos in objective.get("exit", []):
		_quarry_escape(c0)
	for _i in order.size() + 1:
		turn_idx += 1
		if turn_idx >= order.size():
			turn_idx = 0
			round_num += 1
			_objective_round()
		var c = current()
		if c.is_dead() or c.is_stable():
			continue
		return

# 2024 PHB: a surprised creature has Disadvantage on its Initiative roll. The
# side that was caught re-rolls (with Disadvantage — an Assassin's Advantage
# cancels it) and the order is rebuilt. Called once, before the first turn.
# Rolled on a side stream so the fight's own dice are the same whether or not
# the check happened (tests/test_encounter.gd pins that).
func _surprise(team: String) -> void:
	var side = Rng.new((rng.seed_value ^ 0x5A1E5EED) & 0xFFFFFFFF)
	for c in combatants:
		if c.team == team:
			c.init_roll = Dice.d20(side, Dice.combine(c.init_adv, true)).nat + c.init_mod
	order.sort_custom(_init_before)
	turn_idx = 0
	var names: Array = []
	for c in order:
		names.append("%s(%d)" % [c.cname, c.init_roll])
	log.append("Initiative, re-rolled: " + ", ".join(names))

func begin_surprise_round() -> void:
	unseen = true
	log.append("The party has the drop on them — the enemy is surprised and rolls initiative at disadvantage.")
	_surprise("foe")

# T9x: camp-ambush counterpart — called unconditionally (no roll here; the
# watch/DC check already happened in core/world_camp.gd) when the party's
# watch failed to spot it coming.
func begin_ambush_round() -> void:
	ambushed = true
	log.append("The camp is jumped in the night — the party is surprised and rolls initiative at disadvantage.")
	_surprise("party")

# The party yielded (main.gd's Admit defeat). Resolves exactly like a wipe —
# resolve_outcome and every caller only ever read outcome() — minus the wait.
var surrendered := false

func surrender() -> void:
	surrendered = true
	log.append("The party lays down its arms.")

func is_over() -> bool:
	return surrendered or round_num > MAX_ROUNDS or _team_out("party") or _team_out("foe") or _objective_over()

# An illusion is not a creature, so it cannot be the last one standing. Without
# this, Invoke Duplicity's double kept a wiped party's fight "ongoing" until
# MAX_ROUNDS — nothing can attack the double, so nothing could ever end it.
func _team_out(team: String) -> bool:
	for c in combatants:
		if c.team == team and c.conscious() and not c.has("illusion") and not c.has("bystander"):
			return false
	return true

func outcome() -> String:
	if _team_out("foe"):
		return "Victory"
	if surrendered or _team_out("party"):
		return "Defeat"
	if _objective_over():
		return "Victory"   # the gate held, the road reached, the quarry down — with foes still standing
	return "ongoing"

# --- queries used by UI and AI ------------------------------------------

func team_of(team: String) -> Array:
	return combatants.filter(func(c): return c.team == team)

func enemies_of(c) -> Array:
	# Hidden (successfully used Hide) means unseen — RAW, you can't target what
	# you can't perceive. This is the shared choke point for targeting on both
	# sides: the player's target list (legal_target/available route through
	# it) and the AI's own candidate gathering (ai.gd's reach/cone lists).
	return combatants.filter(func(o): return o.team != c.team and o.conscious() and not o.has("hidden") \
		and not o.has("captive"))

func allies_of(c) -> Array:
	return combatants.filter(func(o): return o.team == c.team and o != c and o.conscious())

# --- auras --------------------------------------------------------------
#
# A paladin's aura is the first thing in the game that is neither a button nor a
# rider on a roll of its own: it is a standing fact about a piece of the board,
# read by whoever happens to be rolling inside it. So it is not a verb anyone
# performs — `aura` is not in OFFERABLE and never reaches the bar — it is a
# lookup the resolver does at the moment a number is needed.
#
# "You and allies within N feet" includes the paladin, hence the `+ [c]`. Auras
# do not stack: the best one in reach wins, which is RAW for two paladins
# standing together and conservative for anything else.
# The list half of the same lookup. Aura of Devotion is "you and your allies in
# the aura can't be Charmed" and Aura of Warding is a set of damage types you
# shrug off — both are a list rather than a number, so they share a reader.
func aura_types(c, key: String) -> Array:
	var out: Array = []
	for a in allies_of(c) + [c]:
		for v in a.verbs:
			if v["kind"] != "aura" or not v.has(key):
				continue
			if Hex.distance(a.pos, c.pos) > int(v.get("range", 1)):
				continue
			for entry in v[key]:
				if not entry in out:
					out.append(String(entry))
	return out

func aura_immunities(c) -> Array:
	return aura_types(c, "cond_immune")

func aura_bonus(c, key: String) -> int:
	var best := 0
	for a in allies_of(c) + [c]:
		for v in a.verbs:
			if v["kind"] != "aura" or not v.has(key):
				continue
			if Hex.distance(a.pos, c.pos) > int(v.get("range", 1)):
				continue
			best = maxi(best, int(v[key]))
	return best

func adjacent_enemy(c) -> bool:
	for o in enemies_of(c):
		if Hex.distance(o.pos, c.pos) <= 1:
			return true
	return false

# Can `attacker` reach `target` with a weapon attack right now?
func in_reach(attacker, target) -> bool:
	var d := Hex.distance(attacker.pos, target.pos)
	if attacker.ranged:
		return d <= attacker.atk_range
	return d <= attacker.reach

func effective_ac(c) -> int:
	var ac: int = c.ac + _buff_sum(c, "ac")
	if is_cover(c.pos):
		ac += 2  # half cover
	return ac

func hit_chance(attacker, target, opts := {}) -> float:
	var mode = _attack_mode(attacker, target, opts)
	var need: int = effective_ac(target) - attacker.atk_bonus
	var p: float = clampf((21.0 - need) / 20.0, 0.05, 0.95)
	if mode == Dice.ADV:
		p = 1.0 - (1.0 - p) * (1.0 - p)
	elif mode == Dice.DIS:
		p = p * p
	return p

# Probability `target` FAILS a DC `dc` save (what a caster wants). UI-only.
func save_fail_chance(target, dc: int, ability := "dex", ignore_cover := false) -> float:
	var bonus: int = int(target.saves.get(ability, 0))
	if is_cover(target.pos) and not ignore_cover:
		bonus += 2
	var p_make: float = clampf((21.0 - (dc - bonus)) / 20.0, 0.0, 1.0)
	if _dodging(target) and ability == "dex":
		p_make = 1.0 - (1.0 - p_make) * (1.0 - p_make)
	return 1.0 - p_make

# Probability a Shove or Grapple by `attacker` lands: the target fails its save
# against the Unarmed Strike DC (2024 PHB). UI-only.
func shove_chance(attacker, target) -> float:
	return save_fail_chance(target, unarmed_dc(attacker), _shove_save(target))

# 2024 Unarmed Strike: DC 8 + STR modifier + Proficiency Bonus.
func unarmed_dc(c) -> int:
	return 8 + c.str_mod + c.pb

# "a Strength or Dexterity saving throw (the target chooses)": the better one.
func _shove_save(target) -> String:
	return "str" if int(target.saves.get("str", 0)) >= int(target.saves.get("dex", 0)) else "dex"

const SIZES := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]
func _size_rank(size: String) -> int:
	var i := SIZES.find(size)
	return i if i >= 0 else 2

# Dodge's benefit is lost while Incapacitated or at speed 0 (2024 PHB).
func _dodging(c) -> bool:
	if not c.has("dodging"):
		return false
	for id in c.statuses:
		if id == "dodging":
			continue
		var e: Dictionary = Effects.condition("unconscious" if id == "down" else id)
		if e.is_empty():
			e = ENGINE_CONDS.get(id, {})
		if e.get("no_action", false) or (e.has("speed") and int(e["speed"]) == 0):
			return false
	return true

# --- action economy + verbs (spec §6/§7) -------------------------------
#
# Everything a combatant can do is a verb: the core actions below, plus the
# feature- and spell-derived verbs adapter.gd resolved onto `actor.verbs`.
# Nothing in this file names a hero, a class or a spell.

const BASIC := [
	{"id": "attack", "label": "Attack", "kind": "attack", "cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_prone", "label": "Shove → prone", "kind": "shove", "choice": "prone",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_push", "label": "Shove → back", "kind": "shove", "choice": "push",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "shove_brazier", "label": "Shove → brazier", "kind": "shove", "choice": "brazier",
		"cost": "action", "targeting": "enemy", "range": 1},
	{"id": "grapple", "label": "Grapple", "kind": "grapple", "cost": "action", "targeting": "enemy", "range": 1},
	{"id": "escape", "label": "Break free", "kind": "escape", "cost": "action", "targeting": "self"},
	{"id": "smash", "label": "Smash it", "kind": "smash", "cost": "action", "targeting": "object", "range": 1},
	{"id": "help", "label": "Help an ally", "kind": "help", "cost": "action", "targeting": "ally", "range": 1},
	{"id": "dodge", "label": "Dodge", "kind": "dodge", "cost": "action", "targeting": "self"},
	{"id": "dash", "label": "Dash", "kind": "dash", "cost": "action", "targeting": "self"},
	{"id": "disengage", "label": "Disengage", "kind": "disengage", "cost": "action", "targeting": "self"},
	{"id": "hide", "label": "Hide", "kind": "hide", "cost": "action", "targeting": "self"},
]

# Feature kinds that are a button. The rest are passive: passive_damage folds into
# resolve_attack, attacks_per_action into new_turn(), reaction fires on its trigger.
# 2024: Shove and Grapple are Unarmed Strikes — each is one of the Attack
# action's attacks, so they are priced the way a swing is (_take_attack).
const ATTACK_KINDS := ["attack", "shove", "grapple"]

const OFFERABLE := ["heal_self", "heal_ally", "self_buff", "ally_buff", "grant_action",
	"attack_modifier", "save_effect", "spell", "offhand_attack",
	# T-summon. A feature that puts a second token on the board — Primal
	# Companion, Invoke Duplicity. It aims at nothing (targeting "self"): the
	# arrival hex is the free one nearest its owner, as a spell's summon is.
	"summon"]

func _basic(id: String) -> Dictionary:
	for b in BASIC:
		if b["id"] == id:
			return b
	return {}

# Triggers that fire from the resolver rather than from a press: T94's on_death
# (Death Burst) is in here because save_effect IS in OFFERABLE and its `uses`
# would otherwise put a button on a living mephit's action bar. Reactions need no
# entry — is_button() refuses those by cost, whatever they trigger on.
const NON_BUTTON_TRIGGERS := ["passive", "start_of_turn", "on_death"]

# The plain Attack, for a caller that has to name the swing resolve_attack()
# makes without going through perform() — ai.gd, offering reactions before it.
func attack_verb() -> Dictionary:
	return _basic("attack")

# Every verb that is a BUTTON for `actor` at all — this instant or later in the
# fight. Split from available() so scenes/main.gd can lay its action bar out
# along the whole kit and grey out what is merely spent: a badge that vanishes
# the moment its pool empties takes every badge to its right along with it, and
# the slot under the player's finger stops meaning what it meant last turn.
# ai.gd and everything else still want available(), below.
func all_verbs(actor) -> Array:
	var out: Array = []
	for b in BASIC:
		if is_button(actor, b):
			out.append(b.duplicate())
	for v in actor.verbs:
		if v["kind"] == "grant_verb":
			for name in v.get("verbs", []):
				var g: Dictionary = _basic(name).duplicate()
				if g.is_empty():
					continue
				g["id"] = "%s:%s" % [v["id"], name]
				g["cost"] = v["cost"]
				if v.has("pool"):
					g["pool"] = v["pool"]
				if is_button(actor, g):
					out.append(g)
		elif v["kind"] in OFFERABLE and is_button(actor, v):
			out.append(v.duplicate())
	if party != null and actor.team == "party":
		var seen := {}
		for e in party.stash:
			var pid := String(e["item_id"])
			if seen.has(pid) or not party.is_identified(e) or not Potions.is_potion(pid):
				continue
			seen[pid] = true
			var m := Potions.mechanics(pid)
			out.append({"id": "drink:" + pid, "kind": "drink", "potion": pid, "cost": "action",
				"label": "Drink " + Catalog.magic_item(pid).get("name", pid), "text": Potions.text(pid),
				"targeting": "enemy" if m.has("target") else "self",
				"target_type": m.get("target", ""), "range": maxi(1, int(m.get("range_ft", 5)) / 6)})
	return out

# Every verb `actor` can use right now (spec §6). scenes/main.gd renders this list;
# ai.gd scores it.
func available(actor) -> Array:
	if not actor.conscious():
		return []
	return all_verbs(actor).filter(func(v): return _offerable(actor, v))

func can_spend(actor, cost: String) -> bool:
	if cost in ["free", "none", ""]:
		return true
	return not _no_economy(actor, cost) and int(actor.econ.get(cost, 0)) > 0

# What `actor` can pay for `v` right now. Attacks are the one verb whose price is
# not just its `cost`: the Attack action buys attacks_per_action swings and
# resolve_attack banks the rest in `attacks_left`, so a second swing is already
# paid for. Asking can_spend() alone greyed the Attack button out the instant the
# action was spent — with the banked swing still sitting in the economy — so
# Extra Attack, Flurry of Blows and War Priest were all unreachable from the bar.
func can_afford(actor, v: Dictionary) -> bool:
	if v["kind"] in ATTACK_KINDS and int(actor.econ.get("attacks_left", 0)) > 0:
		return not _no_economy(actor, "action")
	if _flurry_swap(actor, v):
		return true
	return can_spend(actor, v.get("cost", "action"))

# Warrior of Mercy: Hand of Healing may replace one Flurry of Blows strike —
# no Bonus Action (Flurry took it) and no Focus Point. True when that is the
# price on offer right now.
func _flurry_swap(actor, v: Dictionary) -> bool:
	return v.get("flurry_swap", false) and actor.econ.get("flurry", false) \
		and int(actor.econ.get("attacks_left", 0)) > 0

# The Attack action buys `attacks_per_action` swings; the first press pays the
# action and banks the rest in attacks_left. ADD, don't assign: Flurry of Blows
# banks its two as a Bonus Action before the Attack action is taken, and
# assigning threw them away on the first swing (measured: banked 2, one swing
# later attacks_left was 1). False when there is nothing left to swing with.
func _take_attack(attacker) -> bool:
	if int(attacker.econ.get("attacks_left", 0)) > 0:
		attacker.econ["attacks_left"] = int(attacker.econ["attacks_left"]) - 1
		return true
	if _spend(attacker, "action"):
		attacker.econ["attacks_left"] = int(attacker.econ["attacks_left"]) \
			+ int(attacker.econ.get("attacks_per_action", 1)) - 1
		return true
	return false

# 2024 PHB: a Bonus Action leveled spell forbids any other leveled spell on the
# same turn, in either order. Cantrips are free of it.
func _leveled_spell_allowed(actor, v: Dictionary) -> bool:
	if actor.econ.get("cast_bonus_spell", false):
		return false
	if v.get("cost", "") == "bonus" and actor.econ.get("cast_leveled_spell", false):
		return false
	return true

func _spend(actor, cost: String) -> bool:
	if not can_spend(actor, cost):
		return false
	if cost in ["action", "bonus", "reaction"]:
		actor.econ[cost] = int(actor.econ[cost]) - 1
	return true

# The half of offerability that does not change while the fight runs: whether
# this verb is ever a button, and whether this actor could ever press it. Asked
# on its own by all_verbs(), so the action bar's slots are settled by what a
# character IS rather than by what they have left this turn.
func is_button(actor, v: Dictionary) -> bool:
	if v.get("cost", "") == "reaction":
		return false   # a reaction is never a button — fire_reactions() casts it
	if v.get("trigger", "") in NON_BUTTON_TRIGGERS or v.get("trigger", "") == "on_weapon_hit":
		return false   # fires from resolve_attack / begin_turn, never a button (Stunning Strike too)
	return true

func _offerable(actor, v: Dictionary) -> bool:
	if not actor.conscious():
		return false
	if not is_button(actor, v):
		return false
	if not can_afford(actor, v):
		return false
	if v.get("once_per", "") == "turn" and actor.econ.get("used", {}).has(v["id"]):
		return false
	if v.has("pool") and actor.pool_left(v["pool"]) <= 0 and not _flurry_swap(actor, v):
		return false
	var slot := int(v.get("slot_level", 0))
	if slot > 0:
		if slot > actor.slots.size() or actor.slots[slot - 1] <= 0:
			return false
		if not _leveled_spell_allowed(actor, v):
			return false
	if _buff_flag(actor, "no_attack") and v["kind"] in ["attack", "offhand_attack", "spell"]:
		return false
	match v["kind"]:
		"hide": return not actor.has("hidden")
		"dodge": return not actor.has("dodging")
		"disengage": return not actor.has("disengaged")
		"dash": return true
		"self_buff": return not actor.has(v.get("status", v["id"]))
		"summon": return not _already_out(actor, String(v["summon"]["id"])) \
			and _free_near(actor.pos) != NOWHERE
		"attack_modifier", "grant_action": return true
		"escape": return _grappler_of(actor) != null
	match v.get("targeting", "self"):
		"enemy": return enemies_of(actor).any(func(e): return legal_target(actor, v, e))
		"ally": return combatants.any(func(a): return legal_target(actor, v, a))
		"direction", "hex", "corner", "line", "self_area": return not enemies_of(actor).is_empty()
		"object": return not smashable_near(actor).is_empty()
	return true

# RAW gives the Beast Master one beast and the Trickery cleric one double, and
# the button greys out while it stands rather than quietly stacking a second.
# A summon spell is not gated this way: its cost is the slot, and Summon Beast
# twice over is two slots for two wolves.
func _already_out(caster, monster_id: String) -> bool:
	for c in combatants:
		var s = c.statuses.get("summoned")
		if s is Dictionary and s.get("by") == caster and String(s.get("of", "")) == monster_id \
				and not c.is_dead():
			return true
	return false

# Is `c` a legal target for `v` cast/swung by `actor` right now?
# #79: the board's edge is a wall. A straight hex line from a to b that leaves
# the board passes through rock, and nothing can be aimed along it. Adjacent
# hexes always see each other; solid props are cover, not walls, and do not
# block.
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var line: Array = Hex.line(a, b)
	for i in range(1, line.size() - 1):
		if not (line[i] in board["hexes"]):
			return false
	return true

func legal_target(actor, v: Dictionary, c) -> bool:
	if not has_line_of_sight(actor.pos, c.pos):
		return false
	match v.get("targeting", "self"):
		"enemy":
			if c.team == actor.team or not c.conscious() or c.has("hidden"):
				return false
			if c.has("illusion"):
				return false  # Invoke Duplicity's double is not a creature (an area still catches it)
			if c.has("captive"):
				return false  # bound and worthless dead: not a target, and not shovable
			if v["kind"] in ["shove", "grapple"] and _size_rank(c.size) > _size_rank(actor.size) + 1:
				return false  # 2024: no more than one size larger than you
			if v["kind"] == "grapple" and _grappler_of(c) == actor:
				return false  # already in hand
			if _source_of(actor, "cannot_target_source") == c:
				return false  # charmed
			if String(v.get("target_type", "")) != "" \
					and String(Catalog.monster(c.src_id).get("type", "")) != String(v["target_type"]):
				return false  # Animal Friendship only ever works on a beast
			if v["kind"] == "attack" or (v["kind"] == "offhand_attack" and int(v.get("range", 1)) <= 1):
				return in_reach(actor, c)
			if v.get("choice", "") == "brazier" and not can_shove_into_hazard(c):
				return false
			return Hex.distance(actor.pos, c.pos) <= int(v.get("range", 1))
		"ally":
			# A touch heal reaches its own caster; Help, Bless-on-one and the rest do not.
			if c.team != actor.team or c.is_dead() or (c == actor and not v.has("heal_count")):
				return false
			if not (v.has("heal_count") or v["kind"] in ["heal_ally", "ally_buff", "help"]) and not c.conscious():
				return false
			return Hex.distance(actor.pos, c.pos) <= int(v.get("range", 1))
		"self":
			return c == actor
	return false

# Run a verb. `target` is a Combatant, a direction (Vector2i) or null.
func perform(actor, v: Dictionary, target = null) -> Dictionary:
	var kind: String = v["kind"]
	if on_perform.is_valid():
		on_perform.call(actor, v, target)
	# Asked before anything is spent. The rule used to live only in
	# legal_target(), so the resolver would take the action, roll the contest,
	# win it, and then quietly do nothing because there was no brazier beside
	# the target — a turn gone with not a line in the log to say why.
	if kind == "shove" and v.get("choice", "") == "brazier" and not can_shove_into_hazard(target):
		return {"error": "nothing to shove them into"}
	if kind in ["shove", "grapple"] and target != null and _size_rank(target.size) > _size_rank(actor.size) + 1:
		return {"error": "too big to %s" % kind}
	var swap := _flurry_swap(actor, v)
	if swap:
		actor.econ["attacks_left"] = int(actor.econ["attacks_left"]) - 1
	elif kind in ["shove", "grapple"]:
		if _no_economy(actor, "action") or not _take_attack(actor):
			return {"error": "no action left"}
	elif kind != "attack" and not _spend(actor, v.get("cost", "action")):
		return {"error": "no %s left" % v.get("cost", "action")}
	if v.get("once_per", "") == "turn":
		actor.econ["used"][v["id"]] = true
	if v.has("pool") and not swap:
		if actor.pool_left(v["pool"]) <= 0:
			return {"error": "pool empty"}
		actor.pools[v["pool"]]["cur"] = actor.pool_left(v["pool"]) - 1
	var slot := int(v.get("slot_level", 0))
	if kind != "spell" and slot > 0:
		# Divine Smite (2024) is a spell in all but the button: it spends the
		# slot and counts against the bonus-action spell rule like any other.
		if slot > actor.slots.size() or actor.slots[slot - 1] <= 0:
			return {"error": "no slot"}
		actor.slots[slot - 1] -= 1
		if v.get("cost", "") == "bonus":
			actor.econ["cast_bonus_spell"] = true
		actor.econ["cast_leveled_spell"] = true
	match kind:
		"attack": return resolve_attack(actor, target)
		"grapple": return act_grapple(actor, target)
		"escape": return act_escape(actor)
		"offhand_attack":
			# Costs its own bonus action (or nothing, with Nick) — never an Attack-action
			# swing, so it rides the same "free" path Cleave's second swing uses. Mastery
			# is read off the main hand, so the off-hand swing carries none.
			return resolve_attack(actor, target, {"free": true, "no_mastery": true,
				"damage": v["damage"], "atk_bonus": int(v["to_hit"])})
		"shove": return act_shove(actor, target, v.get("choice", "prone"))
		"smash": return act_smash(actor)
		"help": act_help(actor, target)
		"dodge": act_dodge(actor)
		"hide": act_hide(actor)
		"dash":
			actor.econ["move_left"] = int(actor.econ.get("move_left", 0)) + actor.speed
			log.append("%s dashes — +%d move." % [actor.cname, actor.speed])
		"disengage":
			actor.statuses["disengaged"] = true
			log.append("%s disengages." % actor.cname)
		"heal_self", "heal_ally":
			var who = actor if kind == "heal_self" else target
			var n := int(v.get("dice_count", 1))
			if v.has("max_dice") and v.has("pool") and not swap:
				# Healing Light: "spend up to CHA-mod dice at once" — as many as the
				# wound calls for, out of what is left (one is already paid above).
				var avg: float = (int(v.get("dice_sides", 6)) + 1) / 2.0
				var want: int = maxi(1, ceili((who.max_hp - maxi(who.hp, 0)) / avg))
				var extra: int = clampi(want, 1, mini(int(v["max_dice"]), actor.pool_left(v["pool"]) + 1)) - 1
				actor.pools[v["pool"]]["cur"] = actor.pool_left(v["pool"]) - extra
				n += extra
			log.append("%s uses %s%s." % [actor.cname, v["label"],
				(" (%d dice)" % n) if v.has("max_dice") and n > 1 else ""])
			heal(who, Dice.roll(rng, "%dd%d+%d" % [n, int(v.get("dice_sides", 10)), int(v.get("dice_bonus", 0))]))
		"self_buff":
			# `once` and the dice are a Smite's shape: Rage is a standing buff that
			# adds a flat bonus to every swing until the fight ends, a Smite is
			# dice on exactly one of them. Both are self_buffs; the difference is
			# whether the blow that reads the buff also spends it.
			actor.statuses[v.get("status", v["id"])] = {
				"bonus_damage": int(v.get("bonus_damage", 0)), "resist": v.get("resist", []),
				"once": v.get("once", false),
				"dice_count": int(v.get("dice_count", 0)), "dice_sides": int(v.get("dice_sides", 0)),
				# duration "rage" lapses on its own (2024 PHB) — see _rage_upkeep
				"duration": String(v.get("duration", "")), "started_round": round_num, "active_round": round_num}
			log.append("%s — %s!" % [actor.cname, v["label"]])
		"ally_buff":
			target.statuses[v.get("status", v["id"])] = {"dice_sides": int(v.get("dice_sides", 6))}
			log.append("%s inspires %s." % [actor.cname, target.cname])
		"attack_modifier":
			actor.statuses["reckless"] = true
			log.append("%s attacks recklessly." % actor.cname)
		"grant_action":
			actor.econ["action"] = int(actor.econ["action"]) + int(v.get("amount", 1))
			actor.econ["attacks_left"] = int(actor.econ["attacks_left"]) + int(v.get("extra_attacks", 0))
			if int(v.get("extra_attacks", 0)) > 0:
				actor.econ["flurry"] = true   # what Hand of Healing may swap into (_flurry_swap)
			log.append("%s — %s!" % [actor.cname, v["label"]])
		"save_effect": return _save_effect(actor, v, target)
		"summon":
			var called = summon(actor, v)
			if called == null:
				return {"error": "nowhere for it to stand"}
			log.append("%s — %s!" % [actor.cname, v["label"]])
			return {"summoned": called}
		"spell": return cast(actor, v, target)
		"drink":
			var r := Potions.drink_in_combat(self, actor, String(v["potion"]), target)
			if not r.has("error"):
				party.stash_remove(String(v["potion"]))
			return r
	return {}

func _save_effect(actor, v: Dictionary, target) -> Dictionary:
	var saved := _saving_throw(target, actor.save_dc, v.get("save", "dex"), false,
		v.get("magical", false))
	_mark_active(actor)   # forcing a save keeps a Rage going (2024)
	log.append("%s uses %s on %s — %s the save." % [
		actor.cname, v["label"], target.cname, "makes" if saved else "fails"])
	if saved and v.get("on_save_vex", false):
		# Stunning Strike 2024: a made save still leaves the target open —
		# advantage on the monk's next attack against it.
		actor.statuses["vex"] = {"target": target, "until_tick": _next_round_tick()}
		log.append("  ...but is thrown off balance: %s has advantage on the next swing." % actor.cname)
	var dmg := 0
	if int(v.get("dice_count", 0)) > 0:
		dmg = Dice.roll(rng, "%dd%d" % [int(v["dice_count"]), int(v["dice_sides"])])
		if saved:
			dmg = dmg / 2 if v.get("halve_damage", false) else 0
	if not saved:
		for cond in v.get("conditions", []):
			apply_condition(target, cond, actor, v.get("duration", ""), v)
	if dmg > 0:
		_apply_damage(target, dmg, v.get("damage_type", ""))
	return {"saved": saved, "damage": dmg}

# save_effect verbs that ride a weapon hit (a poison bite, a ghoul's paralysis).
# Pooled ones (Stunning Strike) stay a button — the pool is the player's to spend.
func _hit_riders(attacker, target) -> void:
	for v in attacker.verbs:
		if v["kind"] != "save_effect" or v.get("trigger", "") != "on_weapon_hit":
			continue
		if v.get("once_per", "") == "turn" and attacker.econ.get("used", {}).has(v["id"]):
			continue
		if v.has("pool"):
			# Stunning Strike: a Focus Point on the hit, once a turn (2024), and
			# never on a target already wearing what it inflicts.
			if attacker.pool_left(v["pool"]) <= 0 \
					or v.get("conditions", []).any(func(cond): return target.has(cond)):
				continue
			attacker.pools[v["pool"]]["cur"] = attacker.pool_left(v["pool"]) - 1
		if v.get("once_per", "") == "turn":
			attacker.econ["used"][v["id"]] = true
		_save_effect(attacker, v, target)

# --- spells ------------------------------------------------------------

# `target` is a Combatant (single / ally) or a direction (cone).
func cast(caster, v: Dictionary, target) -> Dictionary:
	# An upcast Hold Person and kin: the player hands over every target they
	# picked, primary first. A single Combatant still auto-fills the rest
	# (extra_targets) for the AI and the autopilot.
	var hand_picked: bool = target is Array and not target.is_empty() and target[0] is Object
	var chosen: Array = target.slice(1) if hand_picked else []
	if hand_picked:
		target = target[0]
	var lvl := int(v.get("slot_level", 0))
	if lvl > 0 and (lvl > caster.slots.size() or caster.slots[lvl - 1] <= 0):
		return {"error": "no slot"}
	if lvl > 0 and v.get("cost", "") != "reaction" and not _leveled_spell_allowed(caster, v):
		return {"error": "one leveled spell a turn beside a bonus-action one"}
	# The one moment a reaction reaches into somebody else's turn: the spell is
	# announced, and anything holding an answer gets it in before the slot is
	# spent. A countered spell costs the action already paid for it and nothing
	# more — the slot survives.
	var answer := fire_reactions("spell_cast", {"caster": caster, "verb": v, "level": lvl})
	if answer["countered"]:
		return {"countered": true, "by": answer["by"]}
	if lvl > 0:
		caster.slots[lvl - 1] -= 1
		if v["cost"] == "bonus":
			caster.econ["cast_bonus_spell"] = true
		if v["cost"] != "reaction":
			caster.econ["cast_leveled_spell"] = true
	if String(v.get("save", "")) != "":
		_mark_active(caster)   # forcing a save keeps a Rage going (2024)
	# T27: past the slot check, so a refused cast is silent. T9z: the school
	# picks the sting — evocation booms, necromancy drones, abjuration chimes.
	Sound.play_sfx(WeaponSfx.for_spell(String(v.get("spell", ""))))
	if tracked and caster.team == "party":
		Ach.bump("spells")
		Ach.collect("schools", String(Catalog.spell(String(v.get("spell", ""))).get("school", "")))
	if not (caster.statuses.get("invisible") is Dictionary and caster.statuses["invisible"].get("sticky", false)):
		caster.statuses.erase("invisible")
	if v.get("concentration", false):
		if caster.has("concentrating"):
			_end_concentration(caster, "drops concentration on %s" % Effects.humanize(String(caster.statuses["concentrating"]["spell"])))
		caster.statuses["concentrating"] = {"spell": v["spell"], "until_round": round_num + CONCENTRATION_ROUNDS}
	if v.get("teleport", false):
		if not (target is Vector2i and target in board["hexes"] and passable(target) and _hex_free(target)
				and Hex.distance(caster.pos, target) <= int(v.get("range", 1))):
			return {"error": "not a free hex in range"}
		log.append("%s casts %s and is simply elsewhere." % [caster.cname, v["label"]])
		caster.pos = target   # no provocation: the whole point of the spell
		return {}
	if v.has("summon"):
		var spawned = summon(caster, v)
		if spawned == null:
			return {"error": "nowhere to appear"}
		log.append("%s casts %s — %s answers." % [caster.cname, v["label"], spawned.cname])
		return {"summoned": spawned}
	var who: Array = []   # Bless, Mass Healing Word: everyone on the caster's side in range
	match v.get("targeting", ""):
		"self": who = [caster]
		"allies":
			for c in combatants:
				if c.team == caster.team and not c.is_dead() and Hex.distance(caster.pos, c.pos) <= int(v.get("range", 1)):
					who.append(c)
		"ally": who = [target]
	if not who.is_empty() and (v.has("heal_count") or v.has("buff") or v.has("temp_count")):
		log.append("%s casts %s%s." % [caster.cname, v["label"],
			"" if who.size() == 1 and who[0] == caster else " on " + ", ".join(who.map(func(c): return c.cname))])
		for c in who:
			if v.has("heal_count"):
				heal(c, Dice.roll(rng, "%dd%d+%d" % [int(v["heal_count"]), int(v["heal_sides"]),
					int(v.get("heal_bonus", 0))]))
			if v.has("temp_count"):   # False Life, Heroism: a buffer, not a heal
				grant_temp_hp(c, Dice.roll(rng, "%dd%d+%d" % [int(v["temp_count"]), int(v.get("temp_sides", 4)),
					int(v.get("temp_bonus", 0))]))
			if v.has("buff"):
				_apply_buff(caster, c, v)
		return {}
	if not (v.has("dice_count") or v.has("conditions") or v.has("buff")):
		return {}
	var notation := "%dd%d+%d" % [int(v.get("dice_count", 0)), int(v.get("dice_sides", 6)), int(v.get("dice_bonus", 0))]
	var dc := int(v.get("save_dc", caster.save_dc))
	var area := area_hexes(caster, v, target)
	if v.get("zone", false) and not area.is_empty():
		log.append("%s casts %s — it settles over %d hexes." % [caster.cname, v["label"], area.size()])
		_add_zone(caster, v, area)
		var caught := false
		for c in combatants:
			caught = _zone_touch(c) or caught
		_destroy_in_area(area, caster)
		return {"area": area, "caught": caught}
	if not area.is_empty() or v.get("targeting", "") in AREA_KINDS:
		log.append("%s casts %s — DC %d save." % [caster.cname, v["label"], dc])
		var hit_any := false
		for c in combatants:
			if c == caster or not c.conscious() or not (c.pos in area):
				continue
			if v.get("spare_allies", false) and c.team == caster.team:
				continue   # Spirit Guardians picks who it spares; here that is your side
			_spell_hit(c, v, notation, dc, caster)
			hit_any = true
		_destroy_in_area(area, caster)
		return {"area": area, "caught": hit_any}
	log.append("%s casts %s on %s." % [caster.cname, v["label"], target.cname])
	var out := _spell_hit(target, v, notation, dc, caster)
	for c in (chosen if hand_picked else extra_targets(caster, v, target)):
		log.append("  ...and on %s." % c.cname)
		_spell_hit(c, v, notation, dc, caster)
	return out

# An upcast single-target spell (`targets` > 1) also lands on the nearest
# other legal targets within SPREAD_HEXES of the aimed one — the rules' "within
# 30 feet of each other". Auto-picked by distance to the primary, so the aim
# stays one click.
# ponytail: no multi-select aiming; add a pick-N UI if players want to choose.
const SPREAD_HEXES := 5   # 30 ft
func extra_targets(caster, v: Dictionary, primary) -> Array:
	var n := int(v.get("targets", 1)) - 1
	if n <= 0 or not (primary is Object and primary.get("pos") != null):
		return []
	var pool: Array = []
	for c in combatants:
		if c != primary and c != caster and legal_target(caster, v, c) \
				and Hex.distance(primary.pos, c.pos) <= SPREAD_HEXES:
			pool.append(c)
	pool.sort_custom(func(a, b): return Hex.distance(primary.pos, a.pos) < Hex.distance(primary.pos, b.pos))
	return pool.slice(0, n)

const AREA_KINDS := ["direction", "hex", "corner", "line", "self_area"]

# The hexes an area verb covers for `target` — a direction (cone), a hex, a
# corner (Array of 3 hexes), an aimed hex (line), or nothing (self_area). []
# for a single-target verb. The board preview and the AI ask this too.
func area_hexes(caster, v: Dictionary, target) -> Array:
	match v.get("targeting", ""):
		"direction":
			return Hex.cone(caster.pos, target, int(v.get("radius", 2))) if target is Vector2i else []
		"hex":
			return [target] if target is Vector2i else []
		"corner":
			return Hex.corner_area(target, int(v.get("ring", 0))) if target is Array and target.size() == 3 else []
		"line":
			return Hex.ray(caster.pos, target, int(v.get("length", 1))) if target is Vector2i else []
		"self_area":
			return Hex.within(caster.pos, int(v.get("radius", 1)))
	return []

# Can `caster` aim `v` at `target` (hex / corner / aimed hex) from where it stands?
func legal_area(caster, v: Dictionary, target) -> bool:
	var r := int(v.get("range", 1))
	match v.get("targeting", ""):
		"hex", "line":
			return target is Vector2i and (target in board["hexes"]) and Hex.distance(caster.pos, target) <= r \
				and (v.get("targeting", "") == "hex" or target != caster.pos) \
				and has_line_of_sight(caster.pos, target)
		"corner":
			if not (target is Array) or target.size() != 3:
				return false
			var on_board := false
			var seen := false
			var near := 99
			for h in target:
				on_board = on_board or (h in board["hexes"])
				seen = seen or (h in board["hexes"] and has_line_of_sight(caster.pos, h))
				near = mini(near, Hex.distance(caster.pos, h))
			return on_board and seen and near <= r
	return true

func _spell_hit(c, v: Dictionary, notation: String, dc: int, caster = null) -> Dictionary:
	# T19: the damage types a party has actually dealt. Weapons only ever cover
	# the three physical ones (the SRD has no others), so without the spell side
	# of it "every flavour" would top out at three and never be earnable.
	if tracked and caster != null and caster.team == "party":
		Ach.collect("damage_types", String(v.get("damage_type", "")))
	if v.has("attack_bonus"):
		# Scorching Ray etc.: several independent attack rolls from one cast, all
		# at this same target (RAW also lets you split rays across several
		# targets — not modeled, the targeting UI only ever resolves one hex).
		var rays: int = int(v.get("rays", 1))
		var hits := 0
		var total := 0
		for i in rays:
			var r = Dice.d20(rng)
			var crit: bool = r.nat == 20
			var hit: bool = crit or (r.nat != 1 and r.nat + int(v["attack_bonus"]) >= effective_ac(c))
			var d := Dice.roll(rng, notation, crit) if hit else 0
			var tag := " ray %d/%d" % [i + 1, rays] if rays > 1 else ""
			log.append("  d20[%d]%+d vs AC %d%s — %s%s." % [r.nat, int(v["attack_bonus"]), effective_ac(c),
				tag, "hit for %d" % d if hit else "miss", " (CRIT)" if crit else ""])
			if hit:
				hits += 1
				total += d
				_apply_damage(c, d, v.get("damage_type", ""))
		if hits > 0 and (v.has("conditions") or v.has("buff")):
			# Ray of Sickness: the rider needs its own save when the spell names one
			if v.get("save", "") == "" or not _saving_throw(c, dc, v["save"], v.get("ignores_cover", false), true):
				for cond in v.get("conditions", []):
					apply_condition(c, cond, caster, v.get("duration", "round"), v)
					log.append("  %s is %s." % [c.cname, cond])
				if v.has("buff"):
					_apply_buff(caster, c, v)
		return {"hit": hits > 0, "damage": total, "hits": hits}
	var dmg := Dice.roll(rng, notation)
	var saved := false
	if v.get("save", "") != "":
		# every spell is a magical effect, so Magic Resistance applies (T94)
		saved = _saving_throw(c, dc, v["save"], v.get("ignores_cover", false), true)
		if saved:
			dmg = (dmg / 2) if v.get("half_on_save", false) else 0
	log.append("  %s %s the save — %d %s." % [c.cname, "makes" if saved else "fails", dmg,
		v.get("damage_type", "damage")])
	# Only when there WAS a save to make: a no-save spell always reports "fails"
	# through the line above, and firing save_failed on it would put a second
	# sting under every magic missile.
	if v.get("save", "") != "":
		Sound.play_sfx("save_made" if saved else "save_failed")
	# Only a save-or-suffer effect lands a condition. The raw parse also tags
	# buffs (Invisibility, Freedom of Movement) with `conditions` and no save —
	# those are tier-2 ally buffs, not something to inflict on the target here.
	if not saved and v.get("save", "") != "":
		for cond in v.get("conditions", []):
			apply_condition(c, cond, caster, v.get("duration", "round"), v)
			log.append("  %s is %s." % [c.cname, cond])
	if not saved and v.has("buff"):   # a `buff` is always authored: with no save it simply lands (Darkness)
		_apply_buff(caster, c, v)
	if dmg > 0:
		_apply_damage(c, dmg, v.get("damage_type", ""))
	return {"saved": saved, "damage": dmg}

# Summon Beast, Primal Companion and kin: a bestiary creature on the caster's
# side, in the free hex nearest the caster, for the rest of the fight (or until
# concentration drops — it is held like a condition, or until `rounds` run out).
#
# T-summon: it ROLLS ITS OWN INITIATIVE and takes its place in the order by that
# roll, rather than acting immediately after whoever called it. That is the
# design call, and it costs one thing to get right — a creature landing at or
# above `turn_idx` slides the live turn down a slot, so turn_idx moves with it
# or current() silently becomes somebody else mid-action. Landing BELOW the
# current index is not a bug either: that is a creature whose count has already
# gone by this round, and it waits for the next one, which is what RAW says.
#
# Its `summon` is {id, illusion?}: `id` a monsters.json id. `mult` on the verb
# scales the stat block (encounter._scale) — the ranger's companion grows with
# the ranger; a spell's summon is whatever the slot paid for and passes 1.0.
# The player drives it like a hero (scenes/main.gd dispatches on team).
func summon(caster, v: Dictionary):
	var m: Dictionary = v["summon"]
	var spot := _free_near(caster.pos)
	if spot == NOWHERE:
		return null
	var n := combatants.filter(func(c): return c.src_id == String(m["id"])).size() + 1
	var c = load("res://core/encounter.gd").spawn(String(m["id"]), float(v.get("mult", 1.0)), caster.team, spot, n)   # load: encounter.gd preloads this file
	if c == null:
		return null
	if tracked and caster.team == "party":
		Ach.bump("summons")
	c.short = c.cname.replace(" %d" % n, "")   # the bar says "Dire Wolf", the log "Ilsa's Dire Wolf 1"
	c.cname = "%s's %s" % [caster.cname.get_slice(" ", 0), c.cname]
	combatants.append(c)
	# Always stamped, so "does this caster already have one of these out?" has an
	# answer (_already_out, which is what keeps Primal Companion to one beast).
	# Written before begin_turn_for() rather than after: that call is what expires
	# a clock, and a double standing up in round 11 must fade on arrival, not get
	# a free turn because its stamp had not been applied yet.
	var held := {"by": caster, "of": String(m["id"])}
	if v.get("concentration", false):
		held["held_by"] = caster
		held["spell"] = String(v.get("spell", ""))
	elif int(v.get("rounds", 0)) > 0:
		held["fades_tick"] = _tick() + int(v["rounds"]) * TICK_STRIDE
	c.statuses["summoned"] = held
	if m.get("illusion", false):
		# Not a creature: nothing can swing at it (legal_target) and it cannot
		# swing back (the no_attack gate in _offerable).
		c.statuses["illusion"] = {"no_attack": true}
	_join_order(c)
	begin_turn_for(c)
	return c

# A mid-fight arrival takes its own initiative count. Everything below the
# current index has missed its turn this round and starts next round; keeping
# turn_idx pointed at the same combatant is the whole job.
func _join_order(c) -> void:
	c.init_roll = Dice.d20(rng, Dice.ADV if c.init_adv else Dice.NORMAL).nat + c.init_mod
	var at := 0
	while at < order.size() and _init_before(order[at], c):
		at += 1
	order.insert(at, c)
	if at <= turn_idx:
		turn_idx += 1
	log.append("  %s rolls initiative: %d." % [c.cname, c.init_roll])

const NOWHERE := Vector2i(-999, -999)

func _free_near(origin: Vector2i) -> Vector2i:
	var ring: Array = Hex.within(origin, 3).filter(func(p): return p != origin and p in board["hexes"] and passable(p) and _hex_free(p))
	ring.sort_custom(func(a, b): return Hex.distance(origin, a) < Hex.distance(origin, b))
	return ring[0] if not ring.is_empty() else NOWHERE

# A spell's `buff` (data/effects/spells.json) on `who`: a statuses entry under
# "spell:<id>" carrying the keys the resolver reads (ac, bonus_to_hit,
# bonus_save, bonus_damage, resist, extra_action, speed_mult, no_attack, and
# an `effects` dict of conditions.json-style adv/dis). Lives `rounds` rounds,
# or while the caster concentrates. `condition` hangs a conditions.json id
# beside it (Invisibility); `sticky` keeps that one through attacks (Greater).
func _apply_buff(caster, who, v: Dictionary) -> void:
	var b: Dictionary = v["buff"].duplicate(true)
	var until: int = _tick() + int(v.get("rounds", 10)) * TICK_STRIDE
	if b.has("resist_random"):
		var types: Array = b["resist_random"]
		b["resist"] = [types[rng.roll_die(types.size()) - 1]]
		b.erase("resist_random")
		log.append("  %s: resistance to %s." % [who.cname, b["resist"][0]])
	var held := {}
	if v.get("concentration", false):
		held = {"held_by": caster, "spell": String(v.get("spell", ""))}
	if b.has("condition"):
		var cond := String(b["condition"])
		b.erase("condition")
		var s := {"until_tick": until}
		if b.get("sticky", false):
			s["sticky"] = true
		s.merge(held)
		who.statuses[cond] = s
		log.append("  %s is %s." % [who.cname, cond])
	b.erase("sticky")
	if not b.is_empty():
		b["until_tick"] = until
		b.merge(held)
		who.statuses["spell:" + String(v.get("spell", v["id"]))] = b

# --- lingering areas (Darkness, Web, Spirit Guardians, Wall of Fire...) ----
#
# A `zone: true` spell stays on its hexes instead of resolving once against
# whoever stood there. A buff zone (Darkness) dresses and undresses occupants
# as they come and go; a save/damage zone (Web, Spirit Guardians) rolls against
# a creature the turn it starts inside or steps in, once per turn. Emanations
# walk with their caster; concentration zones die with the concentration.
var zones: Array = []   # {spell, label, hexes, caster, v, until_tick, hit: {id: tick}}

func _add_zone(caster, v: Dictionary, hexes: Array) -> void:
	zones.append({"spell": String(v.get("spell", v["id"])), "label": v["label"], "hexes": hexes,
		"caster": caster, "v": v, "until_tick": _tick() + int(v.get("rounds", 10)) * TICK_STRIDE, "hit": {}})

func _zone_live(z: Dictionary) -> bool:
	if _tick() > int(z["until_tick"]) or z["caster"].is_dead():
		return false
	if z["v"].get("concentration", false):
		var held = z["caster"].statuses.get("concentrating")
		return held is Dictionary and String(held.get("spell", "")) == z["spell"]
	return true

# The zones still standing, emanations re-centred on their caster. The board paints these.
func live_zones() -> Array:
	zones = zones.filter(_zone_live)
	for z in zones:
		if z["v"].get("targeting", "") == "self_area":
			z["hexes"] = Hex.within(z["caster"].pos, int(z["v"].get("radius", 1)))
	return zones

# Would standing on `hex` put `c` in a zone that works against it? Everything
# lingering is hostile except a caster's own side inside Spirit Guardians.
func zone_hurts(c, hex: Vector2i) -> bool:
	for z in live_zones():
		if hex in z["hexes"] and not (z["v"].get("spare_allies", false) and c.team == z["caster"].team):
			return true
	return false

# `c` started a turn or stepped: settle every zone against where it now stands.
# Returns true when a zone rolled against it.
func _zone_touch(c) -> bool:
	var rolled := false
	var worn := {}   # status key -> still standing in a zone that grants it
	for z in live_zones():
		var v: Dictionary = z["v"]
		var inside: bool = c.conscious() and c.pos in z["hexes"]
		if v.has("buff"):
			var key: String = "spell:" + String(z["spell"])
			worn[key] = worn.get(key, false) or inside
			if inside and not c.statuses.has(key):
				_apply_buff(z["caster"], c, v)
				c.statuses[key]["zone"] = true
				log.append("  %s is in the %s." % [c.cname, z["label"]])
		elif inside and c != z["caster"] and int(z["hit"].get(c.id, -1)) != _tick() \
				and not (v.get("spare_allies", false) and c.team == z["caster"].team):
			z["hit"][c.id] = _tick()
			log.append("%s, in the %s (DC %d):" % [c.cname, z["label"], int(v.get("save_dc", z["caster"].save_dc))])
			_spell_hit(c, v, "%dd%d" % [int(v.get("dice_count", 0)), int(v.get("dice_sides", 6))],
				int(v.get("save_dc", z["caster"].save_dc)), z["caster"])
			rolled = true
	for key in c.statuses.keys():
		var st = c.statuses[key]
		if st is Dictionary and st.get("zone", false) and not worn.get(key, false):
			c.statuses.erase(key)
			log.append("  %s is out of the %s." % [c.cname, Effects.humanize(String(key).trim_prefix("spell:"))])
	return rolled

# --- conditions (data/effects/conditions.json) --------------------------
#
# One reader; every resolution point below asks it instead of naming a status.
# exhaustion is the odd shape: {"level": N} with per-level numbers, scaled here.

func _cond_effects(c) -> Array:
	var out: Array = []
	for id in c.statuses:
		if id == "dodging" and not _dodging(c):
			continue   # Incapacitated or held fast: the Dodge is wasted (2024)
		# 0 HP is the Unconscious condition: advantage against, auto-fail STR/DEX,
		# any melee hit from reach a crit — the same entry, under the engine's name.
		var e: Dictionary = Effects.condition("unconscious" if id == "down" else id)
		if e.is_empty():
			e = ENGINE_CONDS.get(id, {})
		if e.is_empty() and c.statuses[id] is Dictionary:
			e = c.statuses[id].get("effects", {})   # Blur, Faerie Fire: a buff's own adv/dis
		if e.is_empty():
			continue
		if e.has("per_level"):
			var lvl := exhaustion_level(c)
			if lvl <= 0:
				continue
			var scaled := {}
			for k in e["per_level"]:
				scaled[k] = int(e["per_level"][k]) * lvl
			out.append(scaled)
		else:
			out.append(e)
	return out

func hexes_from_ft(ft: int) -> int:
	return roundi(float(ft) / FT_PER_HEX)

func exhaustion_level(c) -> int:
	var s = c.statuses.get("exhaustion", {})
	return int(s.get("level", 0)) if s is Dictionary else 0

# Every d20 the creature rolls: attacks and saves (this engine has no other checks).
func _d20_penalty(c) -> int:
	var p := 0
	for e in _cond_effects(c):
		p += int(e.get("d20_penalty", 0))
	return p

# The one entry point that inflicts exhaustion. Level `max_level` kills.
func gain_exhaustion(c, levels := 1) -> int:
	var lvl := exhaustion_level(c) + levels
	c.statuses["exhaustion"] = {"level": lvl}
	log.append("%s gains exhaustion (level %d)." % [c.cname, lvl])
	if lvl >= int(Effects.condition("exhaustion").get("max_level", 6)):
		if tracked:
			Ach.unlock("exhaust_death")
		log.append("%s collapses, spent." % c.cname)
		Sound.play_sfx("collapse")   # before _kill, so it is not buried under the kill sting
		_kill(c)
	return lvl

# Apply a named condition. charmed/frightened remember who caused them.
func apply_condition(target, cond: String, source = null, duration := "", v: Dictionary = {}) -> void:
	# T94 — `cond_immune` off the statblock. Checked ahead of everything, exhaustion
	# included: 31 bestiary entries are immune to exhaustion specifically, and
	# gain_exhaustion() is the one path that never comes back through here.
	if cond in target.cond_immune or cond in aura_immunities(target):
		log.append("%s cannot be %s." % [
			target.cname, "exhausted" if cond == "exhaustion" else cond])
		return
	if cond == "exhaustion":
		gain_exhaustion(target)
		return
	var e := Effects.condition(cond)
	var s := {}
	if source != null and (e.get("cannot_target_source", false) or e.get("cannot_approach_source", false)
			or e.get("held_by_source", false)):
		s["source"] = source
	if duration == "round":
		s["until_tick"] = _tick()
	elif duration == "minute":
		# Sleep and kin: a minute on the clock, shaken off the way the spell says.
		s["until_tick"] = _tick() + CONCENTRATION_ROUNDS * TICK_STRIDE
		s["repeat"] = String(v.get("repeat_save", "none"))
	elif duration == "concentration" and source != null:
		# Held by the caster: ends with their concentration, or when the target
		# shakes it off the way the spell allows (see _repeat_saves).
		s["held_by"] = source
		s["spell"] = String(v.get("spell", ""))
		s["repeat"] = String(v.get("repeat_save", "end_turn"))
		s["save"] = String(v.get("save", ""))
		s["dc"] = int(v.get("save_dc", source.save_dc))
	# Only sting a condition that is actually NEW. A concentration spell re-applies
	# its status to refresh the duration, and a sting on every refresh would put a
	# buzz under every round of a running Hold Person.
	var already: bool = target.statuses.has(cond)
	target.statuses[cond] = s if not s.is_empty() else true
	if not already:
		Sound.play_sfx("condition")

# --- concentration ---------------------------------------------------
#
# caster.statuses["concentrating"] = {spell, until_round}. Every condition the
# spell landed carries held_by = caster, so ending concentration — a failed CON
# save, a new concentration spell, going down, dying, or the duration running
# out at the caster's turn — strips them all in one pass.
const CONCENTRATION_ROUNDS := 10   # a minute, the RAW duration of the lot

func _end_concentration(caster, why: String) -> void:
	var held = caster.statuses.get("concentrating")
	caster.statuses.erase("concentrating")
	if not (held is Dictionary):
		return
	log.append("%s %s." % [caster.cname, why])
	for c in combatants:
		for id in c.statuses.keys():
			var s = c.statuses[id]
			if s is Dictionary and s.get("held_by") == caster and s.get("spell", "") == held["spell"]:
				c.statuses.erase(id)
				if id == "summoned":
					c.hp = 0
					c.statuses["dead"] = true   # stays in `order` as any corpse does: end_turn() skips it,
					log.append("  %s fades." % c.cname)   # and erasing would slide turn_idx under the live turn
					continue
				log.append("  %s is no longer %s." % [c.cname, id])

# A held condition the target can shake off: `when` is "end_turn" (its own
# turn ends), "on_damage" (it was just hurt). "damage_ends" needs no roll.
func _repeat_saves(c, when: String) -> void:
	for id in c.statuses.keys():
		var s = c.statuses[id]
		if not (s is Dictionary and (s.has("held_by") or s.has("repeat"))):
			continue
		var mode := String(s.get("repeat", "end_turn"))
		if when == "on_damage" and mode == "damage_ends":
			c.statuses.erase(id)
			log.append("%s is shaken out of %s." % [c.cname, id])
		elif mode == when and String(s.get("save", "")) != "":
			# held by a concentration spell, so the shake-off is magical too (T94)
			if _saving_throw(c, int(s["dc"]), s["save"], false, true):
				c.statuses.erase(id)
				log.append("%s shakes off %s (%s save)." % [c.cname, id, String(s["save"]).to_upper()])

func _source_of(c, key: String):
	for id in c.statuses:
		if Effects.condition(id).get(key, false) and c.statuses[id] is Dictionary:
			return c.statuses[id].get("source")
	return null

# Movement left this turn after speed-zeroing conditions and exhaustion.
func move_left(c) -> int:
	var mv := int(c.econ.get("move_left", 0))
	for e in _cond_effects(c):
		if e.has("speed") and int(e["speed"]) == 0:
			return 0
		mv -= hexes_from_ft(int(e.get("speed_penalty_ft", 0)))
	return maxi(0, mv)

func _no_economy(actor, cost: String) -> bool:
	var key: String = {"action": "no_action", "bonus": "no_bonus", "reaction": "no_reaction"}.get(cost, "")
	if key == "":
		return false
	for e in _cond_effects(actor):
		if e.get(key, false):
			return true
	return false

# --- attack ------------------------------------------------------------

# --- #85: night on the board ------------------------------------------------
#
# A fight begun after dark carries board["night"]. Then a hex is lit only by a
# flame on the board (LIGHT_TYPES, LIGHT_RADIUS) or by the party's own carried
# light (CARRIED_LIGHT around each standing hero — an adventurer walks with a
# torch). Anyone else in an unlit hex is unseen: 5e's blinded-attacker rule,
# disadvantage to swing at what you cannot see, advantage to swing from where
# you cannot be seen — unless the viewer has darkvision, which most monsters
# and several species do. Hiding in the dark is easier by DARK_HIDE_BONUS.
const LIGHT_TYPES := ["torch", "brazier", "campfire", "lamp"]
const LIGHT_RADIUS := 2
const CARRIED_LIGHT := 1
const DARK_HIDE_BONUS := 5

func is_night() -> bool:
	return bool(board.get("night", false))

func lit(h: Vector2i) -> bool:
	if not is_night():
		return true
	for o in board.get("objects", []):
		if String(o.get("type", "")) in LIGHT_TYPES and Hex.distance(o["pos"], h) <= LIGHT_RADIUS:
			return true
	for c in combatants:
		if c.team == "party" and c.conscious() and Hex.distance(c.pos, h) <= CARRIED_LIGHT:
			return true
	return false

func can_see(viewer, h: Vector2i) -> bool:
	return viewer.darkvision or lit(h)

func _attack_mode(attacker, target, opts := {}) -> int:
	var adv = false
	var dis = false
	if attacker.ranged and not opts.get("melee", false) and adjacent_enemy(attacker):
		dis = true
	if not can_see(attacker, target.pos):
		dis = true   # #85: swinging at the dark
	if not can_see(target, attacker.pos):
		adv = true   # #85: struck from the dark
	for e in _cond_effects(target):
		var a = e.get("attacks_against", "")
		if a is Dictionary:
			a = a.get("ranged" if attacker.ranged and not opts.get("melee", false) else "melee", "")
		adv = adv or a == "adv"
		dis = dis or a == "dis"
	for e in _cond_effects(attacker):
		var o = e.get("own_attacks", "")
		adv = adv or o == "adv"
		dis = dis or o == "dis"
	var vx = attacker.statuses.get("vex")
	if vx is Dictionary and vx.get("target") == target:
		adv = true   # weapon mastery Vex
	if opts.get("advantage", false):
		adv = true
	if _distracted(attacker, target):
		adv = true
	# passive attack_modifier: Pack Tactics and friends, no button, no action
	for v in attacker.verbs:
		if v["kind"] == "attack_modifier" and v.get("trigger", "") == "passive" \
				and v.get("self", "") == "adv" and _requires_met(attacker, target, Dice.combine(adv, dis), v.get("requires", [])):
			adv = true
	return Dice.combine(adv, dis)

# Invoke Duplicity: "you have Advantage on attack rolls against creatures within
# 5 feet of the illusion". Whose Advantage is the one liberty taken — it is the
# double's whole side here, not the cleric alone, because a double that helps
# only the one person who cannot also be standing where it stands is a Channel
# Divinity spent on almost nothing. The cleric's own swing is the RAW case and
# still the common one.
func _distracted(attacker, target) -> bool:
	for c in combatants:
		var s = c.statuses.get("summoned")
		if c.has("illusion") and not c.is_dead() and s is Dictionary and s.get("by") == attacker \
				and Hex.distance(c.pos, target.pos) <= 1:
			return true   # RAW: the cleric's own Advantage, nobody else's
	return false

# Paralyzed/unconscious: any melee hit from within reach is a crit.
func _auto_crit(attacker, target, opts := {}) -> bool:
	if attacker.ranged and not opts.get("melee", false):
		return false
	for e in _cond_effects(target):
		var ft := int(e.get("auto_crit_within_ft", 0))
		if ft > 0 and Hex.distance(attacker.pos, target.pos) <= hexes_from_ft(ft):
			return true
	return false

# The `requires` vocabulary of a passive_damage verb (data/effects/features.json).
func _requires_met(attacker, target, mode: int, reqs: Array) -> bool:
	for r in reqs:
		match r:
			"not_disadvantage":
				if mode == Dice.DIS:
					return false
			"target_has_not_acted":
				if target.has_acted:
					return false
			"advantage_or_ally_adjacent":
				if mode != Dice.ADV and not allies_of(attacker).any(
						func(a): return Hex.distance(a.pos, target.pos) <= 1):
					return false
			"ally_adjacent_to_target":
				if not allies_of(attacker).any(func(a): return Hex.distance(a.pos, target.pos) <= 1):
					return false
			# The three the class features wanted and the vocabulary did not have.
			# Every one of them is a sentence in a subclass's text that had no way
			# to be written down: Colossus Slayer's "a creature that is missing
			# any of its Hit Points", Frenzy's "while your Rage is active",
			# Dread Ambusher's "on your first turn of each combat".
			"target_damaged":
				if target.hp >= target.max_hp:
					return false
			"while_raging":
				if not attacker.has("raging"):
					return false
			"first_round":
				if round_num > 1:
					return false
	return true

# Extra dice a hit adds — Sneak Attack, a goblin's Surprise Attack. [{label, amount}]
func _passive_damage(attacker, target, mode: int, crit: bool) -> Array:
	var out: Array = []
	for v in attacker.verbs:
		if v["kind"] != "passive_damage" or v.get("trigger", "") != "on_weapon_hit":
			continue
		if v.get("once_per", "") == "turn" and attacker.econ.get("used", {}).has(v["id"]):
			continue
		if v.has("pool") and attacker.pool_left(v["pool"]) <= 0:
			continue   # Dreadful Strike: WIS-mod uses a day
		if not _requires_met(attacker, target, mode, v.get("requires", [])):
			continue
		if v.get("once_per", "") == "turn":
			attacker.econ["used"][v["id"]] = true
		if v.has("pool"):
			attacker.pools[v["pool"]]["cur"] = attacker.pool_left(v["pool"]) - 1
		out.append({"label": v["label"], "amount": Dice.roll(rng,
			"%dd%d+%d" % [int(v["dice_count"]), int(v["dice_sides"]), int(v.get("dice_bonus", 0))], crit)})
	return out

# --- reactions (spec §7) ------------------------------------------------
#
# One dispatcher for every reaction in the game, and still zero prompts
# (combat-design.md §2): the engine fires a trigger the moment it happens, finds
# everyone holding an answer to it, and resolves theirs before the moment
# finishes. So a reaction is never a button — is_button() refuses anything that
# costs one — and nothing here ever pauses a monster's turn to ask a question.
#
# A trigger is a name plus a context Dictionary:
#
#   hit_by_attack      {attacker, target, damage} -> {damage}       before it lands
#   damaged_by_attack  {attacker, target, damage} -> {}             after it landed
#   spell_cast         {caster, verb, level}      -> {countered, by} before the slot
#
# Adding one is a `trigger` in data/effects/*.json (Effects.REACTION_TRIGGERS
# validates the name) plus the one call site that fires it. Nothing below names
# a spell, a feature or a class.

# Reactions nest — a Counterspell can itself be counterspelled — and terminate
# on their own, since every level down spends a different creature's one
# reaction. The cap is for the trigger somebody adds later that doesn't.
const REACTION_DEPTH_MAX := 4
var _reaction_depth: int = 0

# Counterspell's DC, off its own catalog description: "a Constitution saving
# throw (DC 10 + the spell's level)". A bigger spell is a bigger target.
const COUNTER_DC_BASE := 10

# --- being asked first --------------------------------------------------
#
# A reaction that spends a spell slot is a real decision — the fight can turn on
# whether that 3rd-level slot went on stopping this spell or on casting your own
# next round — so the player gets to make it. A reaction that costs nothing
# (an opportunity attack, Uncanny Dodge) never asks: there is only one sensible
# answer and a question with one answer is a key press, not a choice.
#
# The question cannot be asked from in here. GDScript cannot block, so a
# straight-line resolver can never stop mid-call and wait for a click
# (combat-design.md §2 — the reason prompts were cut in the first place). So the
# asking happens one step EARLIER, from whoever is about to call the resolver:
# they call offer_reactions() — the one function in this file that can suspend —
# and it records the answers here. fire_reactions() then reads them back
# synchronously at the moment the trigger fires, and everything below it stays
# exactly as straight-line as it was.
#
# With no decider installed (the whole test suite, every headless run, and the
# game with prompts turned off) offer_reactions() returns without suspending and
# nothing else changes shape at all.
var reaction_decider: Callable = Callable()
var reaction_decider_team := "party"

# Told (actor, verb, target) at the top of every perform(), before it resolves.
# The combat screen hangs the attack FX off it, so a foe's swing draws the
# moment it happens and whether or not it lands — inferring it from who lost
# HP after the turn missed every miss, and drew the hit late. Unset, nothing
# is called and nothing changes shape.
var on_perform: Callable = Callable()

# "<reactor id>|<verb id>" -> bool. Written by offer_reactions(), read once by
# fire_reactions() and erased on the way — a yes is good for the trigger it was
# given for and no other, and begin_turn_for() drops whatever went unused.
var reaction_intent := {}

# Does spending this reaction cost `c` something it could want later?
func reaction_costs_resource(v: Dictionary) -> bool:
	return int(v.get("slot_level", 0)) > 0 or v.has("pool")

# Is this one the decider gets a say in?
func asks_first(c, v: Dictionary) -> bool:
	return reaction_decider.is_valid() and c.team == reaction_decider_team \
		and reaction_costs_resource(v)

# The triggers `actor` doing `v` at `target` is about to fire, as
# [trigger, ctx] — a pure prediction, no rolls, no state touched. It is the
# same shape fire_reactions() will be called with when the action resolves,
# which is what makes an answer given here good for the trigger that follows.
func reaction_triggers_for(actor, v: Dictionary, target) -> Array:
	var kind := String(v.get("kind", "attack"))
	if kind == "spell":
		return [["spell_cast",
			{"caster": actor, "verb": v, "level": int(v.get("slot_level", 0))}]]
	if kind in ["attack", "offhand_attack"] and target != null and not (target is Vector2i):
		# A swing fires three — the AC answer, then one before the damage lands
		# and one after — so all three are offered. The blow has not been rolled
		# yet, so this is a commitment made against the hit chance rather than
		# against the damage: answer for the case where it lands, and nothing is
		# spent if it misses. (Parry costs no slot and no pool, so asks_first()
		# never puts it to the decider; it is listed for the one somebody adds
		# later that does.)
		var ctx := {"attacker": actor, "target": target}
		return [["would_be_hit", ctx], ["hit_by_attack", ctx], ["damaged_by_attack", ctx]]
	return []

# Everyone the decider should be asked about before `actor` does `v` at
# `target`, as [reactor, verb, trigger, ctx]. Pure query — the UI renders it,
# the tests assert it, and nothing here spends anything.
func pending_reactions(actor, v: Dictionary, target) -> Array:
	var out: Array = []
	if not reaction_decider.is_valid():
		return out
	for pair in reaction_triggers_for(actor, v, target):
		var trigger: String = pair[0]
		var ctx: Dictionary = pair[1]
		for r in reactors_for(trigger, ctx):
			if not asks_first(r[0], r[1]):
				continue
			# #77: a yes is given before the d20. When the swing then misses on
			# its own the trigger never fires and the answer is never consumed —
			# so it still stands for the next swing, and is not asked twice.
			# A "hold it" is a decision about that one blow and IS asked again.
			if bool(reaction_intent.get("%s|%s" % [r[0].id, r[1]["id"]], false)):
				continue
			out.append([r[0], r[1], trigger, ctx])
	return out

# Put the question, record the answer. THE ONE SUSPENDING FUNCTION IN THIS FILE:
# with no decider it returns without ever reaching an await, which is why every
# synchronous caller of perform()/resolve_attack() in the suite is untouched by
# any of this. Callers that DO install a decider must await it.
func offer_reactions(actor, v: Dictionary, target) -> void:
	for ask in pending_reactions(actor, v, target):
		var yes = await reaction_decider.call(ask[0], ask[1], ask[2], ask[3])
		reaction_intent["%s|%s" % [ask[0].id, ask[1]["id"]]] = bool(yes)

# What the decider said, if it was asked. A reaction nobody was asked about
# fires the way it always did — the answer to "should this spend a slot without
# asking" is only ever no when somebody was there to ask.
func _intends(c, v: Dictionary) -> bool:
	var key := "%s|%s" % [c.id, v["id"]]
	if not reaction_intent.has(key):
		return true
	var yes: bool = bool(reaction_intent[key])
	reaction_intent.erase(key)   # good for this trigger, not the next one
	return yes

# The cheapest answer `c` holds to `trigger`, or {} for none it can pay for
# right now. Cheapest because upcasting a reaction buys nothing this engine
# reads — a 5th-level slot counters exactly what a 3rd-level one does.
func reaction_verb(c, trigger: String) -> Dictionary:
	var best := {}
	for v in c.verbs:
		if v.get("cost", "") != "reaction" or v.get("trigger", "") != trigger:
			continue
		if not _reaction_affordable(c, v):
			continue
		if best.is_empty() or int(v.get("slot_level", 0)) < int(best.get("slot_level", 0)):
			best = v
	return best

# The reaction itself is checked by can_spend(); this is everything else the
# verb costs. _offerable() asks the same questions of a button.
func _reaction_affordable(c, v: Dictionary) -> bool:
	var lvl := int(v.get("slot_level", 0))
	if lvl > 0 and (lvl > c.slots.size() or c.slots[lvl - 1] <= 0):
		return false
	if v.has("pool") and c.pool_left(v["pool"]) <= 0:
		return false
	if v.get("once_per", "") == "turn" and c.econ.get("used", {}).has(v["id"]):
		return false
	return true

# Everyone who could answer `trigger`, as [combatant, verb] pairs in initiative
# order — so the same seed resolves the same fight twice. Anyone down, or whose
# reaction is spent or denied (conditions.json's no_reaction: stunned,
# paralyzed, incapacitated), is already out via can_spend().
func reactors_for(trigger: String, ctx: Dictionary) -> Array:
	var out: Array = []
	for c in order:
		if not c.conscious() or not can_spend(c, "reaction"):
			continue
		var v := reaction_verb(c, trigger)
		if v.is_empty() or not _reaction_applies(c, v, ctx, trigger):
			continue
		out.append([c, v])
	return out

# Whether this trigger is `c`'s business at all.
func _reaction_applies(c, v: Dictionary, ctx: Dictionary, trigger: String) -> bool:
	match trigger:
		"hit_by_attack", "damaged_by_attack", "would_be_hit":
			if c != ctx.get("target"):
				return false   # a blow is only the business of whoever took it
			# Parry is spent only when its AC actually turns the blow into a
			# miss. The SRD lets it be wasted on one that lands anyway; this
			# engine resolves reactions with no prompt (combat-design.md §2), so
			# throwing it away on a swing it could not have stopped would model
			# the choice a player makes worse than holding it does. A prediction
			# (pending_reactions) carries no roll, and answers "could apply".
			# ...which is a test about AC, and only about AC. A reaction that
			# answers with Disadvantage re-rolls the d20 rather than raising the
			# bar, so "the bonus would not have been enough" says nothing about
			# whether it could have stopped this blow — and with ac_bonus 0 the
			# margin test refused it every single time.
			if trigger == "would_be_hit" and ctx.has("total") and not v.get("disadvantage", false) \
					and int(ctx["ac"]) + int(v.get("ac_bonus", 0)) <= int(ctx["total"]):
				return false
			if v.get("melee_only", false) and ctx.get("ranged", false):
				return false   # Parry answers a blade, not an arrow; Shield answers both
			var atk = ctx.get("attacker")
			return atk == null or _reaction_reaches(c, v, atk)
		"spell_cast":
			var caster = ctx.get("caster")
			if caster == null or caster == c or caster.team == c.team:
				return false
			if int(ctx.get("level", 0)) < int(v.get("min_level", 0)):
				return false   # the data says how low this stoops
			return _reaction_reaches(c, v, caster)
	return false

# A reaction answers something it can see, inside the range of whatever it is
# spending. A feature reaction carries no range: it is about its own bearer.
func _reaction_reaches(c, v: Dictionary, other) -> bool:
	if other.has("hidden"):
		return false
	if not v.has("range") or v.get("shape", "") == "self":
		return true   # Shield is about its own caster, whoever is shooting
	return Hex.distance(c.pos, other.pos) <= int(v["range"])

# Fire `trigger`. Returns the context back with whatever the answers changed:
# "damage" for the ones that alter a blow, "countered"/"by" for the ones that
# stop a spell. Callers that care about neither can ignore the return.
func fire_reactions(trigger: String, ctx: Dictionary) -> Dictionary:
	var out := {"damage": int(ctx.get("damage", 0)), "countered": false, "by": null,
		"ac_bonus": 0}
	if _reaction_depth >= REACTION_DEPTH_MAX:
		return out
	_reaction_depth += 1
	for pair in reactors_for(trigger, ctx):
		var c = pair[0]
		var v: Dictionary = pair[1]
		# The list was taken before any of it resolved: an earlier answer may
		# have dropped this one, or spent the slot it was going to pay with.
		if not c.conscious() or not _reaction_affordable(c, v):
			continue
		if not _intends(c, v):
			log.append("%s holds their reaction." % c.cname)
			continue
		if not _spend(c, "reaction"):
			continue
		if tracked and c.team == "party":
			Ach.bump("reactions")
		if v.get("once_per", "") == "turn":
			c.econ["used"][v["id"]] = true
		# What happens next is the verb's business, not the trigger's.
		if v.get("counter", false):
			if _counter(c, v, ctx):
				out["countered"] = true
				out["by"] = c
				break   # the spell is already gone; a second answer has nothing to stop
		elif int(v.get("ac_bonus", 0)) > 0:
			out["ac_bonus"] = int(v["ac_bonus"])
			log.append("%s %ss — AC %d, and the blow goes wide." % [
				c.cname, String(v["label"]).to_lower(),
				int(ctx.get("ac", 0)) + int(v["ac_bonus"])])
			if v["kind"] == "spell":
				# Shield: the slot is spent, and the +5 stays up until the caster's
				# next turn as a buff on top of the one blow it just turned.
				var lvl := int(v.get("slot_level", 0))
				if lvl > 0:
					c.slots[lvl - 1] -= 1
				if v.has("buff"):
					_apply_buff(c, c, v)
			break   # the swing is already a miss; a second answer has nothing to stop
		elif v.get("disadvantage", false):
			# Warding Flare and kin: "impose Disadvantage on the attack roll".
			# would_be_hit fires once a swing is known to land, so the honest
			# reading of Disadvantage at that moment is the second d20 the
			# attacker should have rolled — resolve_attack takes the lower of the
			# two and re-decides. Reported rather than applied here: the roll is
			# the resolver's to own.
			out["second_d20"] = Dice.d20(rng, 0).nat
			log.append("%s — %s, and the blow is thrown off." % [c.cname, v["label"]])
			break
		elif v.get("halve_damage", false):
			out["damage"] = int(out["damage"]) / 2
			log.append("%s — %s, halving the blow." % [c.cname, v["label"]])
		elif v["kind"] == "spell":
			cast(c, v, ctx.get("attacker", ctx.get("caster")))
	_reaction_depth -= 1
	return out

# Counterspell, and anything else the data gives a `counter`. The reactor pays
# the slot first (its own cast can be countered in turn), then the caster rolls
# to hold the spell together. A countered caster keeps the slot — the action it
# already spent is the whole cost, per the spell's catalog text.
func _counter(reactor, v: Dictionary, ctx: Dictionary) -> bool:
	var caster = ctx["caster"]
	var spell_label: String = String(ctx["verb"]["label"])
	log.append("%s answers %s with %s." % [reactor.cname, spell_label, v["label"]])
	if cast(reactor, v, caster).get("countered", false):
		return false   # the counter was itself counterspelled
	var dc: int = COUNTER_DC_BASE + int(ctx.get("level", 0))
	if _saving_throw(caster, dc, String(v.get("save", "con"))):
		log.append("  %s holds %s together (DC %d)." % [caster.cname, spell_label, dc])
		return false
	log.append("  %s unravels in %s's hands." % [spell_label, caster.cname])
	if tracked and reactor.team == "party":
		Ach.bump("counterspells")
	return true

# Damage a held buff adds to a weapon hit (Hunter's Mark, Magic Weapon, a
# potion), extras-shaped so the log labels it the same way a passive-damage
# rider is — not silently folded into the total with nothing to say where it
# came from. Rage is the one that is melee-only; the rest ride any weapon.
const MELEE_ONLY_BUFFS := ["raging"]

func _buff_damage_extras(attacker, ranged: bool, crit := false) -> Array:
	var out: Array = []
	var spent: Array = []
	for id in attacker.statuses:
		var s = attacker.statuses[id]
		if ranged and id in MELEE_ONLY_BUFFS:
			continue
		if not s is Dictionary:
			continue
		# `dice_count`, not `dice_sides`: an ally_buff writes dice_sides into
		# `inspired`, which is a bonus to a d20 and emphatically not damage.
		var dice: int = int(s.get("dice_count", 0))
		if int(s.get("bonus_damage", 0)) == 0 and dice <= 0:
			continue
		var amount: int = int(s.get("bonus_damage", 0))
		if dice > 0:
			amount += Dice.roll(rng, "%dd%d" % [dice, int(s.get("dice_sides", 6))], crit)   # a crit doubles a Smite too
		out.append({"amount": amount, "label": id})
		if s.get("once", false):
			spent.append(id)   # the blow that read it is the blow that spends it
	for id in spent:
		attacker.statuses.erase(id)
	return out

func resolve_attack(attacker, target, opts := {}) -> Dictionary:
	var oa: bool = opts.get("opportunity", false)
	if oa and attacker.ranged:
		# An opportunity attack is a melee attack. ponytail: an archer swings unarmed
		# (flat 1) at its own to-hit rather than modelling a sidearm per statblock.
		opts = opts.duplicate()
		opts["melee"] = true
		opts["damage"] = opts.get("damage", "1")
	var free: bool = oa or opts.get("free", false)   # Cleave's second swing costs nothing
	if not attacker.conscious() or _no_economy(attacker, "action" if not free else "reaction"):
		return {"error": "cannot act"}   # ai.gd swings without asking available()
	if _source_of(attacker, "cannot_target_source") == target:
		return {"error": "charmed"}
	if target.has("illusion"):
		# The choke point, not legal_target: ai.gd builds its own target list off
		# `combatants` and swings through here without asking, and so does the
		# opportunity attack in move_to. Invoke Duplicity's double is not a
		# creature, and this is the one place every swing in the game passes.
		return {"error": "there is nothing there to hit"}
	if not free and not in_reach(attacker, target):
		return {"error": "out of range"}
	if not free and not _take_attack(attacker):   # the Attack action buys its swings; OAs are free (§7)
		return {"error": "no action left"}
	var notation: String = opts.get("damage", attacker.damage)
	var mode = _attack_mode(attacker, target, opts)
	var r = Dice.d20(rng, mode)
	_mark_active(attacker)   # an attack roll keeps a Rage going (2024)
	var nat: int = r.nat
	var insp: int = _consume_inspired(attacker)
	var atk_bonus: int = int(opts.get("atk_bonus", attacker.atk_bonus)) + insp - _d20_penalty(attacker) \
		+ _buff_sum(attacker, "bonus_to_hit")
	var total: int = nat + atk_bonus
	var ac = effective_ac(target)
	var crit: bool = nat >= attacker.crit_range
	var hit: bool = crit or (nat != 1 and total >= ac)
	# T94 — Parry: "adds N to its AC against one melee attack that would hit it".
	# Fired only once the roll is known to land, which is what the SRD wording
	# says. A crit cannot be parried, and a shot cannot: it is a melee reaction.
	if hit and not crit:
		var answer := fire_reactions("would_be_hit", {
			"attacker": attacker, "target": target, "total": total, "ac": ac,
			"ranged": attacker.ranged and not opts.get("melee", false),
		})
		var parry := int(answer.get("ac_bonus", 0))
		if parry > 0:
			ac += parry
			hit = false
			if tracked and attacker.team == "party":
				Ach.unlock("parry")
		elif answer.has("second_d20"):
			# Disadvantage, arriving late (see fire_reactions): take the lower of
			# the two d20s and re-decide the swing on it. A 1 still misses and the
			# crit was already ruled out by the `not crit` gate above, so the only
			# thing that can change here is hit -> miss.
			nat = mini(nat, int(answer["second_d20"]))
			total = nat + atk_bonus
			hit = nat != 1 and total >= ac
	if hit and not crit and _auto_crit(attacker, target, opts):
		crit = true
	var out = {
		"attacker": attacker.cname, "target": target.cname,
		"nat": nat, "dice": r.dice, "bonus": atk_bonus, "total": total, "ac": ac,
		"hit": hit, "crit": crit, "damage": 0, "extras": [], "mode": mode,
	}
	_score_roll(attacker, nat, crit)
	if hit:
		var dmg_detail := Dice.roll_detailed(rng, notation, crit)
		var dmg: int = dmg_detail["total"]
		out["dmg_detail"] = dmg_detail
		out.extras = _passive_damage(attacker, target, mode, crit)
		out.extras.append_array(_buff_damage_extras(attacker,
			attacker.ranged and not opts.get("melee", false), crit))
		for e in out.extras:
			dmg += int(e["amount"])
		out.damage = dmg
	if hit:
		out.damage = int(fire_reactions("hit_by_attack",
			{"attacker": attacker, "target": target, "damage": out.damage})["damage"])
	attacker.statuses.erase("hidden")
	if not (attacker.statuses.get("invisible") is Dictionary and attacker.statuses["invisible"].get("sticky", false)):
		attacker.statuses.erase("invisible")   # gone the moment you swing — unless it's Greater
	attacker.statuses.erase("sapped")   # Sap is spent on the next roll, hit or miss
	var vx = attacker.statuses.get("vex")
	if vx is Dictionary and vx.get("target") == target:
		attacker.statuses.erase("vex")
	if not free:
		attacker.statuses.erase("helped")  # the granted advantage is spent
	_log_attack(out, oa)
	if hit and tracked and attacker.team == "party":
		Ach.record("biggest_hit", int(out.damage))
		Ach.collect("damage_types", _damage_type(attacker))
	if hit:
		_apply_damage(target, out.damage, _damage_type(attacker), crit)
		if tracked and attacker.team == "party" and target.is_dead():
			if crit:
				Ach.unlock("crit_kill")
			if oa:
				Ach.unlock("oa_kill")
		if target.conscious():
			_hit_riders(attacker, target)
			# The other half of hit_by_attack: one trigger changes the number
			# before it lands, this one answers it after. Hellish Rebuke is the
			# difference — it is retaliation, not damage reduction, and a
			# creature dropped by the blow doesn't get to make it.
			if out.damage > 0:
				fire_reactions("damaged_by_attack",
					{"attacker": attacker, "target": target, "damage": out.damage})
		# T9z: a plain hit sounds like the weapon that landed it. A crit and a kill
		# keep their own stingers — those are the dramatic beats, and a flourish
		# on top of every weapon variant would be a second matrix to maintain.
		if target.is_dead():
			bark(attacker, "kill")
		elif crit:
			bark(attacker, "crit")
		else:
			bark(attacker, "hit", WeaponSfx.for_attack(attacker))
	else:
		# A miss had no sound at all until now, which made a fight sound like it
		# was going better than it was: roughly half of all attack rolls resolved
		# in silence, so the only thing you ever heard was your own successes.
		# Straight to play_sfx rather than through bark(): there is no "miss"
		# bark trigger and adding one would put a line of dialogue on every whiff.
		Sound.play_sfx(WeaponSfx.for_miss(attacker))
	if not opts.get("no_mastery", false):
		_mastery_rider(attacker, target, hit)
	return out

# T19 — what one attack roll is worth to this machine's profile. Only the
# party's own dice count, and only in a fight somebody is actually playing.
func _score_roll(attacker, nat: int, crit: bool) -> void:
	if not tracked or attacker.team != "party":
		return
	if nat == 20:
		_saw_nat20 = true
	elif nat == 1:
		_saw_nat1 = true
		Ach.bump("fumbles")
	if crit:
		Ach.bump("crits")
	if _saw_nat20 and _saw_nat1:
		Ach.unlock("both_ends")

# --- weapon mastery (2024 PHB) ----------------------------------------
#
# pass_gear.gd already wrote the mastery id onto the attack only if the wielder
# knows it ("" otherwise), so this is one reader off attacks[0] — the same
# attack combat.gd swings with everywhere else. Auto-applied, no prompt (§2),
# same call T14's conditions made. Nick rides no hit at all: adapter.gd reads the
# main hand's mastery when it builds the off-hand verb and prices that verb "free"
# + once-per-turn, folding it into the Attack action (T24).

func _mastery(c) -> String:
	return str(c.attacks[0].get("mastery", "")) if not c.attacks.is_empty() else ""

# The weapon's damage modifier (Graze's damage, the part Cleave's second swing drops).
func _weapon_mod(c) -> int:
	return int(c.attacks[0].get("dmg_bonus", 0)) if not c.attacks.is_empty() else 0

func _weapon_dice(c) -> String:
	if c.attacks.is_empty():
		return c.damage
	var a: Dictionary = c.attacks[0]
	return "%dd%d" % [int(a.get("dice_count", 1)), int(a.get("dice_sides", 6))]

# No weapon carries a save DC of its own; a proficient wielder's atk_bonus is
# already ability mod + proficiency, so 8 + atk_bonus is the RAW formula.
func _weapon_dc(c) -> int:
	return 8 + c.atk_bonus

# Statuses that should survive the bearer's next turn expire a full cycle out —
# _expire_conditions only runs at the bearer's own begin_turn, so "round" (this
# tick) would clear them before they ever bite.
func _next_round_tick() -> int:
	return _tick() + TICK_STRIDE

func _mastery_rider(attacker, target, hit: bool) -> void:
	var m := _mastery(attacker)
	if m == "" or hit == (m == "graze"):
		return   # graze rides a miss, every other mastery rides a hit
	match m:
		"graze":
			var dmg := _weapon_mod(attacker)
			if dmg > 0:
				log.append("%s grazes %s for %d." % [attacker.cname, target.cname, dmg])
				_apply_damage(target, dmg, _damage_type(attacker))
		"cleave":
			for o in enemies_of(attacker):
				if o != target and Hex.distance(o.pos, target.pos) <= 1 and in_reach(attacker, o):
					log.append("%s cleaves on into %s." % [attacker.cname, o.cname])
					resolve_attack(attacker, o, {"free": true, "no_mastery": true,
						"damage": _weapon_dice(attacker)})
					break
		"push":
			# ponytail: Huge+ shrug it off; bestiary size is the only size model here.
			if target.conscious() and not target.size in ["Huge", "Gargantuan"]:
				if _push_away(attacker, target, hexes_from_ft(10)) > 0:
					log.append("%s drives %s back." % [attacker.cname, target.cname])
		"sap":
			if target.conscious():
				target.statuses["sapped"] = {"until_tick": _next_round_tick()}
				log.append("%s saps %s — disadvantage on its next attack." % [attacker.cname, target.cname])
		"slow":
			if target.conscious():
				target.statuses["slowed"] = {"until_tick": _next_round_tick()}   # refresh, never stack
				log.append("%s slows %s — -10 ft of speed." % [attacker.cname, target.cname])
		"topple":
			if target.conscious():
				var dc := _weapon_dc(attacker)
				if _saving_throw(target, dc, "con"):
					log.append("%s keeps its feet (DC %d CON)." % [target.cname, dc])
				else:
					apply_condition(target, "prone")
					log.append("%s topples %s prone (DC %d CON)." % [attacker.cname, target.cname, dc])
		"vex":
			if target.conscious():
				attacker.statuses["vex"] = {"target": target, "until_tick": _next_round_tick()}
				log.append("%s has %s's measure — advantage on the next swing." % [attacker.cname, target.cname])

func _push_away(attacker, target, hexes: int) -> int:
	var moved := 0
	for _i in hexes:
		var dest: Vector2i = target.pos + Hex.direction_to(attacker.pos, target.pos)
		if not passable(dest) or not _hex_free(dest, target):
			break
		target.pos = dest
		moved += 1
	_zone_touch(target)
	return moved

func _damage_type(attacker) -> String:
	return str(attacker.attacks[0].get("damage_type", "")) if not attacker.attacks.is_empty() else ""

func _log_attack(o: Dictionary, oa: bool) -> void:
	var dice_s = str(o.dice[0]) if o.dice.size() == 1 else "%d̶%d" % [o.dice[0], o.dice[1]]
	var tag = "OA " if oa else ""
	var roll_s = "d20[%s]%+d = %d vs AC %d" % [dice_s, o.bonus, o.total, o.ac]
	if not o.hit:
		if o.nat == 1:
			var flavs := [
				"the blow sails wide.", "a clumsy swing finds only air.",
				"the strike fumbles at the last inch.", "%s twists clear untouched." % o.target,
			]
			var pick: int = (str(o.attacker).hash() + round_num) % flavs.size()
			log.append("%s%s misses %s badly — nat 1, %s" % [tag, o.attacker, o.target, flavs[pick]])
		else:
			log.append("%s%s attacks %s — %s, misses." % [tag, o.attacker, o.target, roll_s])
		return
	var extra = ""
	for e in o.extras:
		extra += " +%d %s" % [int(e["amount"]), str(e["label"]).to_lower()]
	var word = "CRITS" if o.crit else "hits"
	# The damage roll gets its own d[rolls]+mod breakdown, same as the hit roll
	# above — so it reads as its own separate roll, not the to-hit bonus reused.
	var dmg_s := _dmg_roll_string(o.get("dmg_detail", {}))
	var base: int = int(o.dmg_detail["total"]) if o.has("dmg_detail") else o.damage
	var dmg_line: String = "%s damage" % dmg_s if dmg_s != "" else "%d damage" % o.damage
	dmg_line += extra
	if base != int(o.damage):
		dmg_line += " (%d total)" % o.damage
	log.append("%s%s %s %s — %s, %s." % [tag, o.attacker, word, o.target, roll_s, dmg_line])

# "1d6[4]+2 = 6" / "2d6[4,3]+2 = 9" — "" when the notation had no dice (a flat
# modifier like an unarmed strike's "1"), so the caller falls back to a bare number.
func _dmg_roll_string(d: Dictionary) -> String:
	var rolls: Array = d.get("rolls", [])
	if rolls.is_empty():
		return ""
	var sides: int = int(d.get("sides", 0))
	var mod: int = int(d.get("mod", 0))
	var rolls_s := ",".join(rolls.map(func(r): return str(r)))
	var count_s := "" if rolls.size() == 1 else str(rolls.size())
	return "%sd%d[%s]%s = %d" % [count_s, sides, rolls_s,
		("%+d" % mod) if mod != 0 else "", int(d.get("total", 0))]

# --- damage / death --------------------------------------------------

func _resists(c, dtype: String) -> bool:
	for e in _cond_effects(c):
		if e.get("resist_all", false):
			return true
	if dtype == "":
		return false
	if dtype in c.resist:
		return true   # T94: off the statblock (combatant.resist)
	for s in c.statuses.values():
		if s is Dictionary and dtype in s.get("resist", []):
			return true
	# ...and off a paladin standing nearby (Aura of Warding). Same lookup as the
	# save bonus and the condition immunity, third payload.
	return dtype in aura_types(c, "aura_resist")

# The word the log uses for whichever defence just fired.
func _defense_verb(c, dtype: String) -> String:
	if dtype != "" and dtype in c.immune:
		return "is immune to"
	if dtype != "" and dtype in c.vulnerable and not _resists(c, dtype):
		return "is vulnerable to"
	return "resists"

# T94 — the whole defence stack, in RAW's order: immunity wins outright, then
# vulnerability doubles, then resistance halves ONCE however many sources claim
# it (5e resistance never stacks, which is why _resists answers a bool and not a
# count). Before this, only the two status-shaped sources existed — a held Rage's
# `resist` and Petrified's `resist_all` — and the statblock's own three lists
# were dropped on the floor by combatant.gd's missing properties.
func _damage_after_defenses(c, dmg: int, dtype: String) -> int:
	if dmg <= 0:
		return dmg
	if dtype != "" and dtype in c.immune:
		return 0
	if _resists(c, dtype):
		dmg = dmg / 2   # "resistance and then vulnerability" (RAW): halve first
	if dtype != "" and dtype in c.vulnerable:
		dmg *= 2
	return dmg

func _apply_damage(target, dmg: int, dtype := "", crit := false) -> void:
	var raw := dmg
	dmg = _damage_after_defenses(target, dmg, dtype)
	if raw > 0 and dmg != raw:
		# Say why. Halved damage with nothing in the log reads as a dice roll
		# going badly, and the whole point of giving the bestiary its damage
		# types back is that the player can see them and change what they throw.
		log.append("  %s %s %s — %d damage, not %d." % [
			target.cname, _defense_verb(target, dtype), dtype, dmg, raw])
	if dmg > 0 and target.has("concentrating"):
		if not _saving_throw(target, maxi(10, dmg / 2), "con"):
			_end_concentration(target, "loses concentration")
	if dmg > 0:
		_repeat_saves(target, "on_damage")
	if dmg > 0 and target.temp_hp > 0:
		var soak: int = mini(target.temp_hp, dmg)
		target.temp_hp -= soak
		dmg -= soak
		log.append("  %s's temporary hit points take %d%s." % [target.cname, soak,
			"" if target.temp_hp > 0 else ", and are gone"])
	if target.is_down():
		if dmg >= target.max_hp:
			log.append("%s is struck past all saving — the blow alone would have killed them whole." % target.cname)
			_kill(target)   # RAW massive damage applies at 0 HP too
			return
		# Damage to a downed body is a failed death save; a crit (which any melee
		# hit from reach is, via _auto_crit) is two.
		target.death_f += (2 if crit else 1) if dmg > 0 else 0
		if target.death_f >= 3:
			_kill(target)
		return
	var before: int = target.hp
	target.hp -= dmg
	# Undead Fortitude / Relentless: the blow that would drop it doesn't.
	if target.hp <= 0 and dmg > 0 and _survives_at_one(target, dmg, dtype, crit):
		target.hp = 1
		return
	# bark only on the crossing into the last quarter, not every hit below it
	if target.hp > 0 and before * 4 >= target.max_hp and target.hp * 4 < target.max_hp:
		bark(target, "low_hp")
	if target.hp <= 0:
		var overkill: int = -target.hp
		target.hp = 0
		if target.team == "party" and not target.has("bystander"):
			downed[target.id] = true
		if target.team == "foe" or target.has("bystander") or overkill >= target.max_hp:
			if tracked and target.team == "foe" and overkill >= target.max_hp:
				Ach.unlock("overkill")
			_kill(target)
		else:
			target.statuses["down"] = true
			target.statuses.erase("prone")
			if target.has("concentrating"):
				_end_concentration(target, "loses concentration")
			target.death_s = 0
			target.death_f = 0
			log.append("%s falls unconscious." % target.cname)
			bark(target, "down")
			_release_grapples()

# Temporary hit points never stack: the higher of the two stays (RAW).
func grant_temp_hp(c, n: int) -> void:
	if n <= c.temp_hp:
		log.append("%s already has %d temporary HP — the %d would not add." % [c.cname, c.temp_hp, n])
		return
	c.temp_hp = n
	log.append("%s gains %d temporary HP." % [c.cname, n])

# T94 — a `survive_damage` feature turns lethal damage into 1 HP left. Two
# shapes, both straight off the SRD:
#   Undead Fortitude — a CON save at DC 5 + the damage taken, and neither radiant
#     damage nor a critical hit allows it at all (`except`).
#   Relentless      — no roll: any blow at or under `max_damage` (7 / 10 / 14,
#     by creature) simply leaves it standing. The printed MM recharges this on a
#     rest; the SRD dump this catalog was built from drops that clause, and
#     without it a boar chipped for 1 a turn never dies — so it is authored with
#     `uses: 1`, one save per fight, and the deviation is deliberate.
func _survives_at_one(c, dmg: int, dtype: String, crit: bool) -> bool:
	for v in c.verbs:
		if v["kind"] != "survive_damage":
			continue
		if v.has("pool") and c.pool_left(v["pool"]) <= 0:
			continue
		var forbidden: Array = v.get("except", [])
		if crit and "critical" in forbidden:
			continue
		if dtype != "" and dtype in forbidden:
			continue
		var cap := int(v.get("max_damage", 0))
		if cap > 0 and dmg > cap:
			continue
		if String(v.get("save", "")) != "":
			var dc := int(v.get("dc", 0)) + (dmg if v.get("dc_plus_damage", false) else 0)
			if not _saving_throw(c, dc, String(v["save"])):
				continue
		if v.has("pool"):
			c.pools[v["pool"]]["cur"] = c.pool_left(v["pool"]) - 1
		log.append("%s will not go down — %s, 1 HP left." % [c.cname, v["label"]])
		return true
	return false

func _kill(c) -> void:
	# T94 — never kill the same creature twice. A 0-damage hit on a corpse still
	# walks _apply_damage's hp <= 0 branch and used to land here for a second
	# "is dead" line, which was cosmetic; with _death_triggers below it is not,
	# because the burst would go off again.
	if c.is_dead():
		return
	if c.has("concentrating"):
		_end_concentration(c, "loses concentration")
	c.statuses["dead"] = true
	c.statuses.erase("down")
	c.hp = 0
	if c.has("bystander"):
		objective_failed = true   # whoever it was, they were the point
	if c.has("quarry") and not c.has("escaped"):
		objective_done = true
		log.append("The quarry is down — the rest break and run.")
	if tracked and c.team == "foe":
		Ach.bump("kills")
		# src_id is what Encounter.spawn stamps on a generated foe; the
		# hand-authored MVP room builds its monsters straight off the catalog
		# and leaves it empty, where the plain id IS the monsters.json id.
		Ach.collect("bestiary", String(c.src_id) if String(c.src_id) != "" else String(c.id))
		_kills_this_turn += 1
		if _kills_this_turn >= 3:
			Ach.unlock("triple_kill")
	log.append("%s is dead." % c.cname)
	bark(c, "down")
	_death_triggers(c)
	_release_grapples()
	if _team_out(c.team):   # that was the last of them — the winners get a word in
		for w in combatants:
			if w.team != c.team and w.conscious():
				bark(w, "victory")
				break

# T94 — Death Burst and kin: a save_effect the statblock fires as its owner
# dies, on everything in range of BOTH teams (a mephit's steam does not read
# tabards). Runs after the kill is logged, so the burst reads as a consequence of
# it. A burst that kills a second bursting creature resolves that one from its
# own _kill; the recursion terminates because the dead are never conscious().
func _death_triggers(c) -> void:
	for v in c.verbs:
		if v["kind"] != "save_effect" or v.get("trigger", "") != "on_death":
			continue
		var reach: int = maxi(1, int(v.get("range", 1)))
		for other in combatants:
			if other == c or not other.conscious():
				continue
			if Hex.distance(other.pos, c.pos) <= reach:
				_save_effect(c, v, other)

func _death_save(c) -> void:
	var r = Dice.d20(rng)
	if r.nat == 20:
		c.statuses.erase("down")
		c.death_s = 0
		c.death_f = 0
		c.hp = 1
		log.append("%s's eyes snap open — nat 20, up at 1 HP!" % c.cname)
		_survived_down(c)
		return
	if r.nat == 1:
		c.death_f += 2
	elif r.nat >= 10:
		c.death_s += 1
	else:
		c.death_f += 1
	if c.death_f >= 3:
		_kill(c)
	elif c.death_s >= 3:
		c.statuses.erase("down")
		c.death_s = 0
		c.death_f = 0
		c.hp = 1
		log.append("%s comes round — three saves made, up at 1 HP." % c.cname)
		_survived_down(c)
	else:
		log.append("%s death save: rolled %d  [%d ok / %d fail]" % [c.cname, r.nat, c.death_s, c.death_f])

func heal(c, amount: int) -> void:
	if c.is_dead():
		return
	Sound.play_sfx("heal")   # T27
	var revived = c.is_down()
	if revived:
		c.statuses.erase("down")
		c.statuses.erase("stable")
		c.death_s = 0
		c.death_f = 0
	c.hp = mini(c.max_hp, maxi(c.hp, 0) + amount)
	log.append("%s %s — %d HP (%d/%d)." % [c.cname, "revives" if revived else "is healed", amount, c.hp, c.max_hp])
	if tracked and c.team == "party":
		Ach.record("biggest_heal", amount)
		if revived:
			Ach.bump("allies_saved")
	if revived:
		_survived_down(c)

# T19: a hero who went to 0 HP and came back — stabilised, nat-20'd, or healed.
func _survived_down(c) -> void:
	if tracked and c.team == "party":
		Ach.unlock("death_save")

# --- movement -------------------------------------------------------

# Hexes reachable by `mover` with the move points left this turn.
func move_field(mover) -> Dictionary:
	var field := Hex.reachable(passable, mover.pos, move_left(mover), _blockers(mover), _rough())
	for h in _ally_hexes(mover):
		field.erase(h)
	# frightened: you can never end a step closer to what scares you
	var fear = _source_of(mover, "cannot_approach_source")
	if fear != null:
		var d0 := Hex.distance(mover.pos, fear.pos)
		for h in field.keys():
			if Hex.distance(h, fear.pos) < d0:
				field.erase(h)
	return field

# The shortest route `mover` would walk to `dest`.
func move_path(mover, dest: Vector2i) -> Array:
	return Hex.path_to(passable, mover.pos, dest, _blockers(mover), _rough())

# Hostiles that get an opportunity attack somewhere along `mover`'s walk to `dest`.
func provokers_for(mover, dest: Vector2i) -> Array:
	return _provocations(mover, dest).map(func(p): return p[0])

# [[hostile, hex]]: each foe that gets a swing, and the hex the mover is on when
# it steps out of that foe's reach — the OA is rolled from there, not from where
# the walk began, so cover and prone are judged where the swing actually lands.
func _provocations(mover, dest: Vector2i) -> Array:
	if mover.has("hidden"):
		return []   # unseen means unreacted-to: nobody can ready an OA on what they can't see
	var path := move_path(mover, dest)
	var out: Array = []
	var taken: Array = []
	for f in enemies_of(mover):
		if not can_spend(f, "reaction") or f in taken or _buff_flag(f, "no_attack"):
			continue   # an illusion swings at nobody, here least of all
		for i in range(path.size() - 1):
			if Hex.distance(f.pos, path[i]) <= f.reach and Hex.distance(f.pos, path[i + 1]) > f.reach:
				out.append([f, path[i]])
				taken.append(f)
				break
	return out

# id -> the hexes of its last walk, oldest first. Written by move_to, read and
# dropped by the board so the token follows the route instead of cutting across.
var walks := {}

func move_to(mover, dest: Vector2i, disengage := false) -> void:
	if dest == mover.pos:
		return
	var field := move_field(mover)
	if not field.has(dest):
		return  # out of range / blocked — UI never offers this; guard for AI + tests
	var from: Vector2i = mover.pos
	if not disengage and not mover.has("disengaged"):
		for p in _provocations(mover, dest):
			mover.pos = p[1]
			_spend(p[0], "reaction")
			resolve_attack(p[0], mover, {"opportunity": true})
			if mover.is_down() or mover.is_dead():
				# dropped mid-walk: the body lies where it was hit, the steps to it spent
				mover.econ["move_left"] = int(mover.econ.get("move_left", 0)) - int(field.get(p[1], 0))
				return
		mover.pos = from
	var before_region := region_at(from)
	walks[mover.id] = move_path(mover, dest)   # the board slides the token along it
	mover.pos = dest
	mover.econ["move_left"] = int(mover.econ.get("move_left", 0)) - field[dest]
	if region_at(dest) != before_region:
		log.append("%s moves to the %s." % [mover.cname, region_at(dest)])
	_zone_touch(mover)
	_release_grapples()
	_objective_touch(mover)

# --- actions -------------------------------------------------------

func act_dodge(c) -> void:
	c.statuses["dodging"] = true
	log.append("%s takes the Dodge action." % c.cname)

# Help: the named ally's next attack roll (before your next turn) has advantage.
func act_help(helper, ally) -> void:
	if ally.is_down():
		heal(ally, 1)   # First Aid: stir a downed ally back to their feet on 1 HP
		return
	ally.statuses["helped"] = {"by": helper}   # cleared at the helper's next turn (_release_helps)
	log.append("%s helps %s — advantage on their next attack." % [helper.cname, ally.cname])

# T94 — how hard it is to slip past ONE creature. Passive Perception is the
# floor. A keen sense (Keen Smell, Keen Hearing and Smell, Keen Sight — ~60
# bestiary entries carry one) is RAW advantage on the Perception check, which is
# +5 passive. Routing it through senses rather than a flat bonus is the point of
# the exercise: conditions.json's `auto_fail` lists ("blinded" auto-fails
# anything that needs sight, "deafened" hearing) were data nothing in the engine
# read, so blinding a wolf now takes its eyes out of the DC and leaves its nose
# working, while blinding a hawk takes its whole Keen Sight offline.
const SENSES := ["sight", "hearing", "smell"]
const BLIND_PERCEPTION_PENALTY := 5   # a watcher who cannot see is easier to pass

# The senses `c` can still use, per the conditions it is carrying.
func usable_senses(c) -> Array:
	var lost: Array = []
	for e in _cond_effects(c):
		for sense in e.get("auto_fail", []):
			if not sense in lost:
				lost.append(sense)
	return SENSES.filter(func(sense): return not sense in lost)

func hide_dc_against(observer) -> int:
	var senses: Array = usable_senses(observer)
	var dc: int = observer.passive_perception
	if not "sight" in senses:
		dc -= BLIND_PERCEPTION_PENALTY
	for v in observer.verbs:
		if v["kind"] != "keen_senses":
			continue
		if v.get("relies_on", SENSES).any(func(sense): return sense in senses):
			dc += int(v.get("passive_bonus", 5))
	return maxi(1, dc)

# Hide: Stealth vs the hardest enemy to slip past. On success you're hidden
# (attacks against you have disadvantage; your next attack has advantage).
func act_hide(c) -> bool:
	var dc: int = 0
	for e in enemies_of(c):
		dc = maxi(dc, hide_dc_against(e))
	var roll: int = Dice.d20(rng).nat + c.stealth
	if not lit(c.pos):
		roll += DARK_HIDE_BONUS   # #85
	if roll >= dc:
		c.statuses["hidden"] = true
		if tracked and c.team == "party":
			Ach.unlock("hide_first")
		log.append("%s slips out of sight — Stealth %d vs %d." % [c.cname, roll, dc])
		return true
	log.append("%s fails to hide — Stealth %d vs %d." % [c.cname, roll, dc])
	return false

# 2024 PHB: Shove is an Unarmed Strike. The target makes a STR or DEX save (its
# pick) against 8 + STR mod + PB and, failing, goes prone or 5 ft back. A
# creature more than one size larger cannot be shoved (legal_target / perform).
func act_shove(attacker, target, choice: String) -> Dictionary:
	var dc := unarmed_dc(attacker)
	var ab := _shove_save(target)
	if _saving_throw(target, dc, ab):
		log.append("%s tries to shove %s — it keeps its footing (DC %d %s)." % [
			attacker.cname, target.cname, dc, ab.to_upper()])
		return {"success": false}
	if tracked and attacker.team == "party":
		Ach.bump("shoves")
	match choice:
		"prone":
			target.statuses["prone"] = true
			log.append("%s shoves %s prone (DC %d)." % [attacker.cname, target.cname, dc])
		"push":
			var dest = target.pos + Hex.direction_to(attacker.pos, target.pos)
			if passable(dest) and _hex_free(dest, target):
				target.pos = dest
				log.append("%s shoves %s back into the %s (DC %d)." % [attacker.cname, target.cname, region_at(dest), dc])
				_zone_touch(target)
			else:
				target.statuses["prone"] = true
				log.append("%s shoves %s — no room to push, %s falls prone." % [attacker.cname, target.cname, target.cname])
		"brazier":
			# perform() refuses this verb without a hazard beside the target, so
			# the only way here is a direct act_shove() call.
			var haz := adjacent_hazard(target)
			if haz.is_empty():
				log.append("%s has nothing to shove %s into." % [attacker.cname, target.cname])
				return {"success": false}
			var notation: String = String(haz["hazard"].get("dice", "2d6"))
			var burn = Dice.roll(rng, notation)
			log.append("%s shoves %s into the %s — %s = %d fire." % [attacker.cname, target.cname,
				haz["type"], notation, burn])
			if tracked and attacker.team == "party":
				Ach.unlock("shove_hazard")
			_apply_damage(target, burn, String(haz["hazard"].get("damage_type", "fire")))
	return {"success": true}

# 2024 PHB Grapple: the same Unarmed Strike save; a failure is Grappled (speed
# 0) until the target breaks free, the grappler is Incapacitated or downed, or
# the two are ever further apart than the grappler's reach (_release_grapples).
# ponytail: the grappler moving does not drag the target along (RAW: it may, at
# half speed) — moving out of reach simply lets go.
func act_grapple(attacker, target) -> Dictionary:
	var dc := unarmed_dc(attacker)
	var ab := _shove_save(target)
	if _saving_throw(target, dc, ab):
		log.append("%s grabs at %s — it twists free (DC %d %s)." % [attacker.cname, target.cname, dc, ab.to_upper()])
		return {"success": false}
	apply_condition(target, "grappled", attacker)
	if _grappler_of(target) == attacker:
		log.append("%s grapples %s (DC %d)." % [attacker.cname, target.cname, dc])
		return {"success": true}
	return {"success": false}   # immune

# The Grappled creature's action: a STR (Athletics) or DEX (Acrobatics) check
# against the grappler's Unarmed Strike DC.
func act_escape(actor) -> Dictionary:
	var g = _grappler_of(actor)
	if g == null:
		return {"error": "not grappled"}
	var dc := unarmed_dc(g)
	var roll: int = Dice.d20(rng).nat + maxi(actor.athletics, actor.acro)
	if roll >= dc:
		actor.statuses.erase("grappled")
		log.append("%s breaks %s's grip (%d vs DC %d)." % [actor.cname, g.cname, roll, dc])
		return {"success": true}
	log.append("%s strains against %s's grip (%d vs DC %d) and stays held." % [actor.cname, g.cname, roll, dc])
	return {"success": false}

func _grappler_of(c):
	var s = c.statuses.get("grappled")
	return s.get("source") if s is Dictionary else null

func _release_grapples() -> void:
	for c in combatants:
		var g = _grappler_of(c)
		if g == null:
			continue
		if not g.conscious() or _no_economy(g, "action") or Hex.distance(g.pos, c.pos) > g.reach:
			c.statuses.erase("grappled")
			log.append("%s slips free of %s's grip." % [c.cname, g.cname])

# --- Rage's clock (2024 PHB) ----------------------------------------------
#
# A self_buff with duration "rage" lasts until the end of the barbarian's
# NEXT turn unless, on that turn, they made an attack roll or forced a save
# (each of which stamps active_round). Ten rounds is the ceiling either way,
# and Incapacitated ends it at once (begin_turn_for).
func _mark_active(c) -> void:
	for id in c.statuses:
		var s = c.statuses[id]
		if s is Dictionary and s.get("duration", "") == "rage":
			s["active_round"] = round_num

func _rage_upkeep(c) -> void:
	for id in c.statuses.keys():
		var s = c.statuses[id]
		if not (s is Dictionary and s.get("duration", "") == "rage"):
			continue
		var started := int(s.get("started_round", round_num))
		if round_num - started >= CONCENTRATION_ROUNDS:
			c.statuses.erase(id)
			log.append("%s's %s runs its course." % [c.cname, id])
		elif started != round_num and int(s.get("active_round", -1)) != round_num:
			c.statuses.erase(id)
			log.append("%s's %s subsides — nothing was fought this turn." % [c.cname, id])

func _end_lapsing_buffs(c, why: String) -> void:
	for id in c.statuses.keys():
		var s = c.statuses[id]
		if s is Dictionary and s.get("duration", "") == "rage":
			c.statuses.erase(id)
			log.append("%s %s — the %s ends." % [c.cname, why, id])

# A barrel or crate: one action, no roll, the hex clears. Explosive ones burst.
func act_smash(actor) -> Dictionary:
	var o := smashable_near(actor)
	if o.is_empty():
		return {"error": "nothing to smash"}
	log.append("%s smashes the %s apart." % [actor.cname, o["type"]])
	if tracked and actor.team == "party":
		Ach.bump("smashed")
	destroy_object(o, actor)
	return {"smashed": o["type"]}

# `magical` marks a save forced by a spell or an explicitly magical ability —
# what Magic Resistance ("advantage on saving throws against spells and other
# magical effects") keys off. Everything else is mundane: a dragon's breath and a
# ghoul's paralysis force saves but are not magic, so they are unaffected, which
# is RAW and also what keeps this from becoming a blanket +5 on 20 statblocks.
func _saving_throw(c, dc: int, ability := "dex", ignore_cover := false, magical := false) -> bool:
	var adv: bool = _dodging(c) and ability == "dex"   # Dodge: DEX saves only (RAW)
	var dis := false
	if magical:
		for v in c.verbs:
			if v["kind"] == "save_modifier" and String(v.get("vs", "")) == "magic" \
					and String(v.get("self", "")) == "adv":
				adv = true
	for e in _cond_effects(c):
		if ability in e.get("auto_fail_saves", []):
			log.append("%s can't resist — the %s save fails automatically." % [c.cname, ability.to_upper()])
			return false
		dis = dis or e.get("saves", {}).get(ability, "") == "dis"
	var bonus: int = int(c.saves.get(ability, 0)) + _consume_inspired(c) - _d20_penalty(c) \
		+ _buff_sum(c, "bonus_save") + aura_bonus(c, "save_bonus")
	if is_cover(c.pos) and not ignore_cover:
		bonus += 2
	return Dice.d20(rng, Dice.combine(adv, dis)).nat + bonus >= dc

# Bardic Inspiration (and anything shaped like it): a one-shot die added to the
# bearer's own next attack or save, auto-applied — this engine has no reaction
# prompts (combat-design.md §2), so "would you like to use it?" isn't a question.
func _consume_inspired(c) -> int:
	if not c.has("inspired"):
		return 0
	var sides: int = int(c.statuses["inspired"].get("dice_sides", 6))
	c.statuses.erase("inspired")
	var bonus: int = rng.roll_die(sides)
	log.append("%s's inspiration adds %d." % [c.cname, bonus])
	return bonus

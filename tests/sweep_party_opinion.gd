# THROWAWAY MEASUREMENT SPIKE (2026-09-16) — what party relationships would do
# to a fight. Not a test; delete once docs/spike-party-opinions.md is decided on.
#   godot --headless --path . -s tests/sweep_party_opinion.gd
#
# Same fixed party (Presets.party(): Vera fighter, Pike rogue, Ilsa cleric),
# same Scaler.roster_for on "normal", same six themes and 150 seeds as the T35
# and hex-range sweeps, so the baseline row here is comparable to theirs.
#
# Two questions:
#   1. How often would each SOURCE fire — how fast do scores actually move in
#      play? (saves, friendly fire, downs, won fights — counted on the baseline.)
#   2. What does each combat EFFECT cost or buy — win rate and fight length with
#      one relationship pinned per variant, hooks subclassed in the way the doc
#      proposes wiring them into combat.gd.
extends SceneTree

const AI = preload("res://core/ai.gd")
const RNG = preload("res://core/rng.gd")
const Hex = preload("res://core/hex.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Combat = preload("res://core/combat.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")

const SEEDS := 150
const DIFFICULTY := "normal"

# Each variant pins the relations a fresh preset party would have to earn, and
# says which hooks are live. "baseline" has all three hooks on but no
# relations, which must equal "hooks off" — a check that the wiring is inert
# for a neutral party.
const VARIANTS := [
	{"id": "baseline", "pairs": {}, "shoulder": true, "bicker": true, "rally": true},
	{"id": "lovers vera+ilsa", "pairs": {"vera|ilsa": "lovers"}, "shoulder": true, "bicker": true, "rally": true},
	{"id": "  shoulder only", "pairs": {"vera|ilsa": "lovers"}, "shoulder": true, "bicker": false, "rally": false},
	{"id": "  rally only", "pairs": {"vera|ilsa": "lovers"}, "shoulder": false, "bicker": false, "rally": true},
	{"id": "bonded vera+pike", "pairs": {"vera|pike": "bonded"}, "shoulder": true, "bicker": true, "rally": true},
	{"id": "rivals vera+pike", "pairs": {"vera|pike": "rivals"}, "shoulder": true, "bicker": true, "rally": true},
	{"id": "rivals vera+ilsa", "pairs": {"vera|ilsa": "rivals"}, "shoulder": true, "bicker": true, "rally": true},
	{"id": "everyone bonded", "pairs": {"vera|ilsa": "bonded", "vera|pike": "bonded", "pike|ilsa": "bonded"},
		"shoulder": true, "bicker": true, "rally": true},
]

# combat.gd with the three hooks the doc proposes, plus counters for the sources.
class Measured extends Combat:
	# `party` is Combat's own now — feature/spells-fix gave it one for the potion
	# shelf, with the same meaning and the same null default this spike declared
	# for itself when Combat had none. Redeclaring it here is a parse error.
	var use_shoulder := true
	var use_bicker := true
	var use_rally := true
	# effects
	var shoulder_hits := 0      # attacks against a member who had the +1 at the time
	var shoulder_saved := 0     # ...that missed by exactly the bonus
	var bicker_swings := 0
	var bicker_lost := 0        # ...that missed by exactly the penalty
	var rallies := 0
	var rally_swings := 0
	# sources
	var saves := 0              # a member brought up from 0 by another member
	var friendly := 0           # a member caught in another member's area
	var downs := 0              # a member hit 0 HP
	var _was_down := {}

	func effective_ac(c) -> int:
		var ac := super(c)
		if use_shoulder and party != null:
			ac += PartyOpinion.shoulder_bonus(party, c, self)
		return ac

	func resolve_attack(attacker, target, opts := {}) -> Dictionary:
		var pen := 0
		var rally := false
		if party != null and attacker.team == "party" and not opts.get("opportunity", false):
			if use_bicker and not opts.has("atk_bonus"):
				pen = PartyOpinion.bicker_penalty(party, attacker, self)
				if pen > 0:
					opts = opts.duplicate()
					opts["atk_bonus"] = attacker.atk_bonus - pen
			if use_rally and attacker.has(PartyOpinion.RALLY_STATUS):
				rally = true
				opts = opts.duplicate()
				opts["advantage"] = true
		var had_shoulder: int = PartyOpinion.shoulder_bonus(party, target, self) \
			if use_shoulder and party != null and target.team == "party" else 0
		var r := super(attacker, target, opts)
		if r.has("error"):
			return r
		if rally:
			attacker.statuses.erase(PartyOpinion.RALLY_STATUS)
			rally_swings += 1
		if pen > 0:
			bicker_swings += 1
			if not r["hit"] and r["nat"] != 1 and r["total"] + pen >= r["ac"]:
				bicker_lost += 1
		if had_shoulder > 0:
			shoulder_hits += 1
			if not r["hit"] and r["nat"] != 1 and r["total"] >= r["ac"] - had_shoulder:
				shoulder_saved += 1
		return r

	func _apply_damage(target, dmg: int, dtype := "", crit := false) -> void:
		var before: bool = target.is_down() or target.is_dead()
		super(target, dmg, dtype, crit)
		if target.team == "party" and not before and (target.is_down() or target.is_dead()):
			downs += 1
			if party != null and use_rally:
				rallies += PartyOpinion.rally(party, target, self).size()

	func perform(actor, v: Dictionary, target = null) -> Dictionary:
		var down_before: bool = target is Object and target != null and target.get("statuses") != null and target.is_down()
		var r := super(actor, v, target)
		if v["kind"] == "heal_ally" and down_before and target.team == "party" and not target.is_down():
			saves += 1
			if party != null:
				PartyOpinion.saved(party, actor.id, target.id)
		return r

	func cast(caster, v: Dictionary, target) -> Dictionary:
		var down_before: bool = target is Object and target != null and target.get("statuses") != null and target.is_down()
		var allies_up: Array = allies_of(caster).filter(func(c): return c.conscious())
		var r := super(caster, v, target)
		if r.has("error"):
			return r
		if v.has("heal_count") and down_before and caster.team == "party" and not target.is_down():
			saves += 1
			if party != null:
				PartyOpinion.saved(party, caster.id, target.id)
		if r.has("area") and caster.team == "party":
			for c in allies_up:
				if c.pos in r["area"]:
					friendly += 1
					if party != null:
						PartyOpinion.friendly_fire(party, caster.id, c.id)
		return r

func _init() -> void:
	print("party=vera/pike/ilsa  seeds=%d  difficulty=%s" % [SEEDS, DIFFICULTY])
	print("SHOULDER_AC=%d  BICKER_TO_HIT=%d  rally=advantage on next attack" % [
		PartyOpinion.SHOULDER_AC, PartyOpinion.BICKER_TO_HIT])
	print("")
	print("%-20s %6s %7s | %8s %8s %8s %8s | %7s %7s" % [
		"variant", "win%", "rounds", "shldr", "saved", "bicker", "lost", "rallies", "r-swing"])
	var rows: Array = []
	for v in VARIANTS:
		var t := {"wins": 0, "rounds": 0, "shoulder_hits": 0, "shoulder_saved": 0, "bicker_swings": 0,
			"bicker_lost": 0, "rallies": 0, "rally_swings": 0, "saves": 0, "friendly": 0, "downs": 0,
			"drift": {}}
		for s in range(1, SEEDS + 1):
			var theme: String = Encounter.THEMES[s % Encounter.THEMES.size()]
			var r := _fight(v, theme, s)
			for k in ["shoulder_hits", "shoulder_saved", "bicker_swings", "bicker_lost", "rallies",
					"rally_swings", "saves", "friendly", "downs"]:
				t[k] += r[k]
			t["rounds"] += r["rounds"]
			t["wins"] += 1 if r["won"] else 0
			for k in r["drift"]:
				t["drift"][k] = float(t["drift"].get(k, 0.0)) + float(r["drift"][k])
		print("%-20s %5.1f%% %7.2f | %8d %8d %8d %8d | %7d %7d" % [
			v["id"], 100.0 * t["wins"] / SEEDS, float(t["rounds"]) / SEEDS,
			t["shoulder_hits"], t["shoulder_saved"], t["bicker_swings"], t["bicker_lost"],
			t["rallies"], t["rally_swings"]])
		rows.append({"variant": v["id"], "t": t})
	print("")
	var b: Dictionary = rows[0]["t"]
	print("SOURCES on the baseline, %d fights:" % SEEDS)
	print("  members downed         %4d   (%.2f per fight)" % [b["downs"], float(b["downs"]) / SEEDS])
	print("  saved by another member %4d   (%.2f per fight, +%d each)" % [b["saves"], float(b["saves"]) / SEEDS, int(PartyOpinion.SAVED)])
	print("  caught in an ally's area %3d   (%.2f per fight, -%d each)" % [b["friendly"], float(b["friendly"]) / SEEDS, int(PartyOpinion.FRIENDLY_FIRE)])
	print("  won fights             %4d   (+%d per standing pair each)" % [b["wins"], int(PartyOpinion.FOUGHT_BESIDE)])
	print("  net score drift per pair over %d fights (fought-beside + saves - friendly fire):" % SEEDS)
	for k in b["drift"]:
		print("    %-12s %+7.1f  (%+.2f per fight)" % [k, b["drift"][k], float(b["drift"][k]) / SEEDS])
	quit(0)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _fight(v: Dictionary, theme: String, seed_value: int) -> Dictionary:
	var p := _party()
	for k in v["pairs"]:
		var ids: PackedStringArray = String(k).split("|")
		match String(v["pairs"][k]):
			"lovers":
				PartyOpinion.set_score(p, ids[0], ids[1], PartyOpinion.COURTSHIP_MIN)
				PartyOpinion.answer_courtship(p, ids[0], ids[1], true)
			"bonded": PartyOpinion.set_score(p, ids[0], ids[1], PartyOpinion.BONDED)
			"rivals": PartyOpinion.set_score(p, ids[0], ids[1], PartyOpinion.RIVALS)
	var before := {}
	for pr in PartyOpinion.active_pairs(p):
		before[PartyOpinion.key(pr[0], pr[1])] = PartyOpinion.score(p, pr[0], pr[1])
	var chars: Array = p.party_characters()
	var spec: Dictionary = Scaler.roster_for(chars, DIFFICULTY, {}, theme, seed_value)
	var cb := _build(spec, theme, seed_value, chars)
	cb.party = p
	cb.use_shoulder = v["shoulder"]
	cb.use_bicker = v["bicker"]
	cb.use_rally = v["rally"]
	var guard := 0
	while not cb.is_over() and guard < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		guard += 1
	var won := cb.outcome() == "Victory"
	if won:
		var standing: Array = []
		for c in cb.team_of("party"):
			if c.conscious():
				standing.append(c.id)
		PartyOpinion.fought_beside(p, standing)
	var drift := {}
	for k in before:
		var ids: PackedStringArray = String(k).split("|")
		drift[k] = PartyOpinion.score(p, ids[0], ids[1]) - float(before[k])
	return {
		"won": won, "rounds": cb.round_num,
		"shoulder_hits": cb.shoulder_hits, "shoulder_saved": cb.shoulder_saved,
		"bicker_swings": cb.bicker_swings, "bicker_lost": cb.bicker_lost,
		"rallies": cb.rallies, "rally_swings": cb.rally_swings,
		"saves": cb.saves, "friendly": cb.friendly, "downs": cb.downs,
		"drift": drift,
	}

# encounter.build(), but instantiating the Measured subclass instead of Combat.
func _build(spec: Dictionary, theme: String, seed_value: int, chars: Array) -> Measured:
	var b: Dictionary = Encounter.board_for(theme)
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var all_c: Array = party.duplicate()
	var spots: Array = Encounter._foe_spots(b, party)
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		for n in count:
			var c = Encounter.spawn(e["id"], float(e.get("mult", 1.0)), "foe",
				spots[i] if i < spots.size() else Encounter.PARTY_STARTS[0], n + 1 if count > 1 else 0)
			if c != null:
				all_c.append(c)
			i += 1
	return Measured.new(RNG.new(seed_value), all_c, b)

# T35 ONE-OFF MEASUREMENT SPIKE — not a permanent test, delete when the decision
# is made. Measures how fast melee closes and how much of a fight happens at range:
#   godot --headless --path . -s tests/sweep_range.gd
# Per fight: rounds until every combatant has been adjacent to an enemy at least
# once (a combatant that dies before ever closing counts as settled — it never
# will), the attack split at 1 hex vs 2+ hexes, and whether the party won.
# Seeds/party/roster are fixed so baseline and candidates are comparable.
extends SceneTree

const AI = preload("res://core/ai.gd")
const RNG = preload("res://core/rng.gd")
const Hex = preload("res://core/hex.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Combat = preload("res://core/combat.gd")

const SEEDS := 150
const DIFFICULTY := "normal"

# Every attack and every targeted spell, tagged with the distance it was thrown
# from. Subclassing is the only hook that sees the range at the moment of the
# swing — by the time a turn ends the attacker may have moved again.
class Measured extends Combat:
	var melee := 0
	var ranged := 0
	# ...and the same split counting only swings whose owner COULD have shot from
	# 2+ hexes: a melee-only goblin's attacks are melee by definition and say
	# nothing about whether range gets a window.
	var able_melee := 0
	var able_ranged := 0

	func _tally(a, t, able: bool) -> void:
		if t == null or typeof(t) != TYPE_OBJECT or not ("pos" in t) or t.team == a.team:
			return
		if Hex.distance(a.pos, t.pos) >= 2:
			ranged += 1
			able_ranged += 1 if able else 0
		else:
			melee += 1
			able_melee += 1 if able else 0

	func resolve_attack(attacker, target, opts := {}) -> Dictionary:
		var r := super(attacker, target, opts)
		if not r.has("error"):
			_tally(attacker, target, int(attacker.atk_range) >= 2)
		return r

	func cast(caster, v: Dictionary, target) -> Dictionary:
		var r := super(caster, v, target)
		if not r.has("error"):
			_tally(caster, target, int(v.get("range", 1)) >= 2)
		return r

func _init() -> void:
	var chars := Presets.party()
	var themes: Array = Encounter.THEMES
	var per_theme := {}
	var tot := {"adj": 0.0, "melee": 0, "ranged": 0, "wins": 0, "rounds": 0, "never": 0,
		"able_melee": 0, "able_ranged": 0}
	for s in range(1, SEEDS + 1):
		var theme: String = themes[s % themes.size()]
		var r := _fight(chars, theme, s)
		tot["adj"] += r["adj"]
		tot["melee"] += r["melee"]
		tot["ranged"] += r["ranged"]
		tot["rounds"] += r["rounds"]
		tot["wins"] += 1 if r["won"] else 0
		tot["never"] += 1 if r["never"] else 0
		tot["able_melee"] += r["able_melee"]
		tot["able_ranged"] += r["able_ranged"]
		var t: Dictionary = per_theme.get(theme, {"n": 0, "adj": 0.0, "melee": 0, "ranged": 0, "wins": 0})
		t["n"] += 1
		t["adj"] += r["adj"]
		t["melee"] += r["melee"]
		t["ranged"] += r["ranged"]
		t["wins"] += 1 if r["won"] else 0
		per_theme[theme] = t

	print("FT_PER_HEX=%d  RANGE_CAP=%d  seeds=%d  difficulty=%s" % [
		Adapter.FT_PER_HEX, Adapter.RANGE_CAP, SEEDS, DIFFICULTY])
	for theme in themes:
		var t: Dictionary = per_theme[theme]
		print("  %-16s adj@%.2f  ranged %5.1f%%  win %5.1f%%  (%d hexes wide)" % [
			theme, t["adj"] / t["n"], _pct(t["ranged"], t["melee"]),
			100.0 * t["wins"] / t["n"], _width(theme)])
	print("TOTAL  avg rounds to universal adjacency %.2f (%d fights never reached it)" % [
		tot["adj"] / SEEDS, tot["never"]])
	print("TOTAL  attacks: %d at 2+ hexes / %d at 1 hex -> %.1f%% ranged" % [
		tot["ranged"], tot["melee"], _pct(tot["ranged"], tot["melee"])])
	print("TOTAL  ranged-capable attackers only: %d at 2+ / %d at 1 hex -> %.1f%% ranged" % [
		tot["able_ranged"], tot["able_melee"], _pct(tot["able_ranged"], tot["able_melee"])])
	print("TOTAL  party win rate %.1f%%   avg fight length %.2f rounds" % [
		100.0 * tot["wins"] / SEEDS, float(tot["rounds"]) / SEEDS])
	quit(0)

func _pct(ranged: int, melee: int) -> float:
	var n := ranged + melee
	return 0.0 if n == 0 else 100.0 * ranged / n

func _width(theme: String) -> int:
	var qs: Array = Encounter.board_for(theme)["hexes"].map(func(h): return h.x)
	return qs.max() - qs.min() + 1

func _fight(chars: Array, theme: String, seed_value: int) -> Dictionary:
	var spec: Dictionary = Scaler.roster_for(chars, DIFFICULTY, {}, theme, seed_value)
	var cb := _build(spec, theme, seed_value, chars)
	var settled := {}          # id -> true once adjacent to an enemy (or dead)
	var adj_round := 0
	var guard := 0
	while not cb.is_over() and guard < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		guard += 1
		if adj_round == 0:
			for c in cb.combatants:
				if not settled.has(c.id) and (c.is_dead() or cb.enemies_of(c).any(
						func(o): return Hex.distance(o.pos, c.pos) <= 1)):
					settled[c.id] = true
			if settled.size() == cb.combatants.size():
				adj_round = cb.round_num
	return {
		"adj": float(adj_round if adj_round > 0 else cb.round_num),
		"never": adj_round == 0,
		"melee": cb.melee, "ranged": cb.ranged,
		"able_melee": cb.able_melee, "able_ranged": cb.able_ranged,
		"rounds": cb.round_num, "won": cb.outcome() == "Victory",
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

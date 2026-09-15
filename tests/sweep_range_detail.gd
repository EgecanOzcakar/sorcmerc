# THROWAWAY MEASUREMENT SPIKE (2026-09-15) — hex distances / spell ranges /
# ranged-melee balance. Not a test; delete once docs/spike-hex-ranges.md is decided on.
#   godot --headless --path . -s tests/sweep_range_detail.gd   (last line is JSON of everything)
# Same fixed party/roster/seeds as tests/sweep_range.gd (T35) so rows compare.
# Adds: per-actor distance histogram of every attack/cast, spell casts by id and
# distance, damage split by distance, opportunity attacks, first-contact round,
# board diameters, and "how many shots each RANGE_CAP candidate would have blocked".
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
const MAXD := 12   # histogram buckets 1..MAXD

class Measured extends Combat:
	var events: Array = []   # {who, bucket, d, kind, id, dmg, oa}

	func _bucket(a) -> String:
		if a.team == "party":
			return a.id
		return "foe-ranged" if a.ranged else "foe-melee"

	func _rec(a, t, kind: String, id: String, r: Dictionary, cap: int, oa := false) -> void:
		if t == null or typeof(t) != TYPE_OBJECT or not ("pos" in t) or t.team == a.team:
			return
		events.append({"who": _bucket(a), "d": Hex.distance(a.pos, t.pos), "kind": kind,
			"id": id, "dmg": int(r.get("damage", 0)), "hit": bool(r.get("hit", false)),
			"oa": oa, "team": a.team, "cap": cap})

	func resolve_attack(attacker, target, opts := {}) -> Dictionary:
		var r := super(attacker, target, opts)
		if not r.has("error"):
			var id := "natural"
			if not attacker.attacks.is_empty():
				id = String(attacker.attacks[0].get("id", "natural"))
			_rec(attacker, target, "attack", id, r, int(attacker.atk_range) if attacker.ranged else 1,
				bool(opts.get("opportunity", false)))
		return r

	var cones := {}   # spell id -> [casts, foes caught]

	func cast(caster, v: Dictionary, target) -> Dictionary:
		if v.get("targeting", "") == "direction" and target is Vector2i:
			var wedge := Hex.cone(caster.pos, target, int(v.get("radius", 2)))
			var caught: int = enemies_of(caster).filter(func(c): return c.conscious() and c.pos in wedge).size()
			var id := String(v.get("spell", v.get("id", "?")))
			var e: Array = cones.get(id, [0, 0])
			cones[id] = [e[0] + 1, e[1] + caught]
		var r := super(caster, v, target)
		if not r.has("error"):
			_rec(caster, target, "spell", String(v.get("spell", v.get("id", "?"))), r, int(v.get("range", 1)))
		return r

func _init() -> void:
	var chars := Presets.party()
	var themes: Array = Encounter.THEMES
	var out := {"FT_PER_HEX": Adapter.FT_PER_HEX, "RANGE_CAP": Adapter.RANGE_CAP,
		"SPAWN_GAP": Encounter.SPAWN_GAP, "seeds": SEEDS, "boards": {}, "themes": {},
		"hist": {}, "spells": {}, "dmg": {"party": {"melee": 0, "ranged": 0}, "foe": {"melee": 0, "ranged": 0}},
		"oa": {"n": 0, "dmg": 0, "party": 0, "foe": 0}, "wins": 0, "rounds": 0,
		"first_contact": 0.0, "adj": 0.0, "never": 0, "foes": 0, "foes_ranged": 0,
		"blocked_by_cap": {}, "party_cap_shots": {}, "cones": {}}
	for theme in themes:
		out["boards"][theme] = _board_stats(theme)
	for s in range(1, SEEDS + 1):
		var theme: String = themes[s % themes.size()]
		var r := _fight(chars, theme, s)
		var t: Dictionary = out["themes"].get(theme, {"n": 0, "wins": 0, "rounds": 0, "first": 0.0,
			"adj": 0.0, "melee": 0, "ranged": 0, "foes_ranged": 0, "foes": 0})
		t["n"] += 1
		t["wins"] += 1 if r["won"] else 0
		t["rounds"] += r["rounds"]
		t["first"] += r["first"]
		t["adj"] += r["adj"]
		t["foes"] += r["foes"]
		t["foes_ranged"] += r["foes_ranged"]
		out["wins"] += 1 if r["won"] else 0
		out["rounds"] += r["rounds"]
		out["first_contact"] += r["first"]
		out["adj"] += r["adj"]
		out["never"] += 1 if r["never"] else 0
		out["foes"] += r["foes"]
		out["foes_ranged"] += r["foes_ranged"]
		for id in r["cones"]:
			var ce: Array = out["cones"].get(id, [0, 0])
			out["cones"][id] = [ce[0] + r["cones"][id][0], ce[1] + r["cones"][id][1]]
		for e in r["events"]:
			var d: int = mini(e["d"], MAXD)
			var h: Dictionary = out["hist"].get(e["who"], {})
			h[str(d)] = int(h.get(str(d), 0)) + 1
			out["hist"][e["who"]] = h
			if e["d"] >= 2:
				t["ranged"] += 1
			else:
				t["melee"] += 1
			out["dmg"][e["team"]]["ranged" if e["d"] >= 2 else "melee"] += e["dmg"]
			if e["oa"]:
				out["oa"]["n"] += 1
				out["oa"]["dmg"] += e["dmg"]
				out["oa"][e["team"]] += 1
			if e["kind"] == "spell":
				var sp: Dictionary = out["spells"].get(e["id"], {"n": 0, "who": e["who"], "sum_d": 0, "max_d": 0, "cap": e["cap"]})
				sp["n"] += 1
				sp["sum_d"] += e["d"]
				sp["max_d"] = maxi(sp["max_d"], e["d"])
				out["spells"][e["id"]] = sp
			# a shot/cast at distance d would be illegal under any cap < d
			if e["d"] >= 2:
				for cap in [3, 4, 5, 6, 8, 10, 12]:
					if e["d"] > cap:
						out["blocked_by_cap"][str(cap)] = int(out["blocked_by_cap"].get(str(cap), 0)) + 1
				if e["d"] == e["cap"]:   # thrown from exactly max range: the cap is binding
					out["party_cap_shots"][e["who"]] = int(out["party_cap_shots"].get(e["who"], 0)) + 1
		out["themes"][theme] = t

	print("FT_PER_HEX=%d RANGE_CAP=%d SPAWN_GAP=%d seeds=%d" % [
		Adapter.FT_PER_HEX, Adapter.RANGE_CAP, Encounter.SPAWN_GAP, SEEDS])
	for theme in themes:
		var t: Dictionary = out["themes"][theme]
		var b: Dictionary = out["boards"][theme]
		print("  %-16s diam %2d  spawn-dist %d..%d  first@%.2f adj@%.2f  ranged %5.1f%%  foes %.1f (%.1f ranged)  win %5.1f%%" % [
			theme, b["diameter"], b["spawn_min"], b["spawn_max"], t["first"] / t["n"], t["adj"] / t["n"],
			100.0 * t["ranged"] / maxi(1, t["ranged"] + t["melee"]),
			float(t["foes"]) / t["n"], float(t["foes_ranged"]) / t["n"], 100.0 * t["wins"] / t["n"]])
	print("HIST (attacks+casts by distance):")
	for who in out["hist"]:
		var h: Dictionary = out["hist"][who]
		var line := "  %-11s" % who
		for d in range(1, MAXD + 1):
			line += " %4d" % int(h.get(str(d), 0))
		print(line)
	print("SPELLS:")
	for id in out["spells"]:
		var sp: Dictionary = out["spells"][id]
		print("  %-16s n=%4d avg d %.2f max d %d (cap %d) by %s" % [id, sp["n"], float(sp["sum_d"]) / sp["n"], sp["max_d"], sp["cap"], sp["who"]])
	for id in out["cones"]:
		print("  %-16s n=%4d cones, %.2f foes caught per cast (radius %d hexes)" % [id, out["cones"][id][0],
			float(out["cones"][id][1]) / maxi(1, out["cones"][id][0]), Adapter.area_hexes(15)])
	print("DAMAGE party melee/ranged %d/%d  foe melee/ranged %d/%d" % [
		out["dmg"]["party"]["melee"], out["dmg"]["party"]["ranged"], out["dmg"]["foe"]["melee"], out["dmg"]["foe"]["ranged"]])
	print("OA: %d (party %d, foe %d) for %d dmg" % [out["oa"]["n"], out["oa"]["party"], out["oa"]["foe"], out["oa"]["dmg"]])
	print("blocked_by_cap %s   shots at exactly own cap %s" % [out["blocked_by_cap"], out["party_cap_shots"]])
	print("TOTAL first contact %.2f  universal adj %.2f (%d never)  win %.1f%%  len %.2f  foes %.2f/fight (%.2f ranged)" % [
		out["first_contact"] / SEEDS, out["adj"] / SEEDS, out["never"], 100.0 * out["wins"] / SEEDS,
		float(out["rounds"]) / SEEDS, float(out["foes"]) / SEEDS, float(out["foes_ranged"]) / SEEDS])
	print("JSON " + JSON.stringify(out))
	quit(0)

func _board_stats(theme: String) -> Dictionary:
	var hexes: Array = Encounter.board_for(theme)["hexes"]
	var diam := 0
	for a in hexes:
		for b in hexes:
			diam = maxi(diam, Hex.distance(a, b))
	# farthest any board hex is from the party's nearest start, and from PARTY_STARTS[0]
	var far := 0
	for h in hexes:
		var dmin := 1 << 30
		for p in Encounter.PARTY_STARTS:
			dmin = mini(dmin, Hex.distance(h, p))
		far = maxi(far, dmin)
	return {"hexes": hexes.size(), "diameter": diam, "spawn_min": Encounter.SPAWN_GAP, "spawn_max": far}

func _fight(chars: Array, theme: String, seed_value: int) -> Dictionary:
	var spec: Dictionary = Scaler.roster_for(chars, DIFFICULTY, {}, theme, seed_value)
	var cb := _build(spec, theme, seed_value, chars)
	var foes: Array = cb.combatants.filter(func(c): return c.team == "foe")
	var settled := {}
	var adj_round := 0
	var first := 0
	var guard := 0
	while not cb.is_over() and guard < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		guard += 1
		if first == 0:
			for c in cb.combatants:
				if c.team == "party" and cb.enemies_of(c).any(func(o): return Hex.distance(o.pos, c.pos) <= 1):
					first = cb.round_num
					break
		if adj_round == 0:
			for c in cb.combatants:
				if not settled.has(c.id) and (c.is_dead() or cb.enemies_of(c).any(
						func(o): return Hex.distance(o.pos, c.pos) <= 1)):
					settled[c.id] = true
			if settled.size() == cb.combatants.size():
				adj_round = cb.round_num
	return {
		"adj": float(adj_round if adj_round > 0 else cb.round_num),
		"first": float(first if first > 0 else cb.round_num),
		"never": adj_round == 0, "events": cb.events, "cones": cb.cones,
		"rounds": cb.round_num, "won": cb.outcome() == "Victory",
		"foes": foes.size(), "foes_ranged": foes.filter(func(c): return c.ranged).size(),
	}

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

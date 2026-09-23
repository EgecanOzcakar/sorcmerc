# MEASUREMENT (#176 step 3's still-open line) — what fights actually leave on
# the people in them. tests/sweep_traits.gd measures fights with traits HELD;
# this measures what a fight EARNS, through the real path: a fight built by
# Encounter.build and played by the AI, its result from
# Encounter.resolve_outcome (the same dict world.gd hands Traits.after_fight),
# then Traits.after_fight / after_lair on the heroes who were in it. Not a
# test; its numbers are the ones core/traits.gd's earning constants and
# data/traits.json's events table cite.
#
#   godot --headless --path . -s tests/sweep_traits_earn.gd
#   SWEEP_SEEDS=60 SWEEP_RUNS=6 godot --headless --path . -s tests/sweep_traits_earn.gd   # quicker, noisier
#
# The same fixed party as every other sweep (Presets.party(): Vera fighter,
# Pike rogue, Ilsa cleric, level 3, no traits held), the eight board themes in
# turn, the fight seed pinned.
#
# Part 1, one fight at a time — a fresh party per fight, so nothing carries
# (no counts toward a bane, no scar to cure): per hero-fight, how often each
# kind of change happens at each difficulty, which events asked for it, and
# how the hardship saves fell.
#
# Part 2, a run — the same three heroes carried through SWEEP_DAYS days: one
# road fight a day at "easy" (core/world_threat.gd's BASELINE: open country is
# the walk between sites), and every fourth day a lair of two "normal" rooms
# and a "hard" boss room (core/site.gd: 12 of its 17 rooms are normal, the boss
# room is the hard one), then after_lair for whoever is standing. Lapsing
# traits expire on the clock (Traits.expire); nobody visits an inn, so a
# Wounded hero stays wounded for its three days. What the heroes hold at the
# end, and what came and went on the way.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Combat = preload("res://core/combat.gd")
const Traits = preload("res://core/traits.gd")
const RNG = preload("res://core/rng.gd")

const DIFFS := ["easy", "normal", "hard", "deadly"]
const KINDS := ["triumph", "resilience", "scar", "wound", "cure"]
const LAIR_EVERY := 4

func _init() -> void:
	var seeds := _env("SWEEP_SEEDS", 200)
	var runs := _env("SWEEP_RUNS", 20)
	var days := _env("SWEEP_DAYS", 30)
	print("party=vera/pike/ilsa lvl3, no traits held  seeds=%d  runs=%d x %d days" % [seeds, runs, days])
	_part_one(seeds)
	_part_two(runs, days)
	quit(0)

func _env(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.get_environment(k) != "" else d

# --- part 1 -------------------------------------------------------------------

func _part_one(seeds: int) -> void:
	print("\n== one fight, a fresh party each time: changes per 100 hero-fights ==")
	print("%-7s %5s %6s %6s  %8s %10s %6s %6s  %s" % ["diff", "win%", "downs", "deaths", "triumph", "resilience", "scar", "wound", "any"])
	var events := {}      # event label -> count, over every difficulty
	var saves := {"asked": 0, "tempered": 0, "shook": 0, "scar": 0, "scar+shaken": 0}
	var traits := {}      # trait id -> count
	for diff in DIFFS:
		var t := {"wins": 0, "downs": 0, "deaths": 0, "any": 0}
		for k in KINDS:
			t[k] = 0
		for s in range(1, seeds + 1):
			var chars: Array = Presets.party()
			var theme: String = Encounter.THEMES[s % Encounter.THEMES.size()]
			var result := _fight(chars, diff, theme, s * 7 + DIFFS.find(diff))
			t["wins"] += 1 if result["outcome"] == "Victory" else 0
			t["downs"] += (result["downed"] as Array).size()
			t["deaths"] += (result["deaths"] as Array).size()
			var out: Dictionary = Traits.after_fight(chars, result,
				{"now": float(s * 1440), "difficulty": diff, "site": "road"})
			var touched := {}
			for m in out["moments"]:
				t[m["kind"]] += 1
				touched[m["char_id"]] = true
				events[String(m["event"]).get_slice(" — ", 0)] = int(events.get(String(m["event"]).get_slice(" — ", 0), 0)) + 1
				var nm := String(m["trait"]["name"])
				traits[nm] = int(traits.get(nm, 0)) + 1
			t["any"] += touched.size()
			_tally_saves(out, saves)
		var hf := float(seeds * 3) / 100.0
		print("%-7s %4.0f%% %6.2f %6.2f  %8.1f %10.1f %6.1f %6.1f  %4.1f" % [diff, 100.0 * t["wins"] / seeds,
			float(t["downs"]) / seeds, float(t["deaths"]) / seeds, t["triumph"] / hf, t["resilience"] / hf, t["scar"] / hf, t["wound"] / hf,
			t["any"] / hf])
	print("\nhardship saves (every difficulty): asked %d — tempered %d, shook it off %d, scar %d, scar+Shaken %d" % [
		saves["asked"], saves["tempered"], saves["shook"], saves["scar"], saves["scar+shaken"]])
	print("what asked:  " + _top(events, 12))
	print("what it left: " + _top(traits, 16))

# Every hardship save leaves exactly one of four marks in the output: a
# resilience moment, a "shakes it off" line, a scar/wound moment, and on the
# bottom degree a Shaken moment besides. Counted from the lines, which carry
# the save words on every one of them.
func _tally_saves(out: Dictionary, saves: Dictionary) -> void:
	var by_hero := {}
	for m in out["moments"]:
		if m.has("save") and m["kind"] != "cure":
			by_hero[m["char_id"]] = by_hero.get(m["char_id"], []) + [m["kind"]]
		elif m["trait"]["name"] == "Shaken":
			by_hero[m["char_id"]] = by_hero.get(m["char_id"], []) + ["shaken"]
	for l in out["lines"]:
		if "shakes it off" in String(l):
			saves["asked"] += 1
			saves["shook"] += 1
	for id in by_hero:
		var ks: Array = by_hero[id]
		if "resilience" in ks:
			saves["asked"] += 1
			saves["tempered"] += 1
		elif ks.any(func(k): return k in ["scar", "wound"]):
			saves["asked"] += 1
			saves["scar+shaken" if "shaken" in ks else "scar"] += 1
		elif "shaken" in ks:   # the scar already held, only the bottom degree landed
			saves["asked"] += 1
			saves["scar+shaken"] += 1

# --- part 2 -------------------------------------------------------------------

func _part_two(runs: int, days: int) -> void:
	print("\n== a run: %d days, a road fight a day (easy), a lair every %d days (normal, normal, hard) ==" % [days, LAIR_EVERY])
	var tot := {"fights": 0, "wipes": 0, "deaths": 0, "held": 0, "held_scar": 0, "held_wound": 0, "held_triumph": 0}
	for k in KINDS:
		tot[k] = 0
	var ends: Array = []
	for r in runs:
		var chars: Array = Presets.party()
		var fight := 0
		for day in days:
			var plan: Array = ["easy"]
			if day % LAIR_EVERY == LAIR_EVERY - 1:
				plan = ["normal", "normal", "hard"]
			for i in plan.size():
				var now := float(day * 1440 + i * 60)
				for ch in chars:
					Traits.expire(ch, now)
				fight += 1
				var theme: String = Encounter.THEMES[(r * 31 + fight) % Encounter.THEMES.size()]
				var result := _fight(chars, String(plan[i]), theme, 100000 + r * 1000 + fight)
				tot["fights"] += 1
				if result["outcome"] != "Victory":
					tot["wipes"] += 1
				tot["deaths"] += (result["deaths"] as Array).size()
				var out: Dictionary = Traits.after_fight(chars, result,
					{"now": now, "difficulty": plan[i], "site": "lair" if plan.size() > 1 else "road"})
				for m in out["moments"]:
					tot[m["kind"]] += 1
				if plan.size() > 1 and i == plan.size() - 1 and result["outcome"] == "Victory":
					for m in Traits.after_lair(chars.filter(func(ch): return not ch.id in result["deaths"]), now + 30.0)["moments"]:
						tot[m["kind"]] += 1
		var end_now := float(days * 1440)
		var held: Array = []
		for ch in chars:
			Traits.expire(ch, end_now)
			for t in ch.traits:
				if not t is Dictionary:
					continue
				var fam := Traits.family_of(String(t["id"]))
				if fam in ["temperament", "origin"]:
					continue
				held.append(Traits.name_of(String(t["id"])))
				tot["held"] += 1
				var kind := String(Traits.row(String(t["id"])).get("kind", ""))
				if fam == "wound":
					tot["held_wound"] += 1
				elif kind == "scar":
					tot["held_scar"] += 1
				else:
					tot["held_triumph"] += 1
		ends.append(held)
	var hr := float(runs * 3)
	print("fights %d (%.1f a run), lost %d, hero deaths %d (raised for the next fight)" % [tot["fights"],
		float(tot["fights"]) / runs, tot["wipes"], tot["deaths"]])
	print("gained per hero over the run: triumph %.2f  resilience %.2f  scar %.2f  wound %.2f  cured %.2f" % [
		tot["triumph"] / hr, tot["resilience"] / hr, tot["scar"] / hr, tot["wound"] / hr, tot["cure"] / hr])
	print("held per hero at the end:     %.2f (triumph-kind %.2f, scar %.2f, wound %.2f)" % [
		tot["held"] / hr, tot["held_triumph"] / hr, tot["held_scar"] / hr, tot["held_wound"] / hr])
	for i in mini(ends.size(), 5):
		print("  run %d ends holding: %s" % [i + 1, ", ".join(ends[i]) if not ends[i].is_empty() else "nothing"])

# --- one fight ---------------------------------------------------------------------

func _fight(chars: Array, diff: String, theme: String, seed_value: int) -> Dictionary:
	var p := Party.new()
	for ch in chars:
		ch.dead = false
		Adapter.rest(ch, "long-rest")   # full HP, slots and pools: every sweep starts a fight fresh
		p.add_member(ch)
	var spec: Dictionary = Scaler.roster_for(chars, diff, {}, theme, seed_value)
	spec["theme"] = theme
	spec["seed"] = seed_value
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var built = Encounter.build(spec, party)
	var cb: Combat = built
	cb.party = p
	var guard := 0
	while not cb.is_over() and guard < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		guard += 1
	return Encounter.resolve_outcome(cb, p)

func _top(d: Dictionary, n: int) -> String:
	var ks: Array = d.keys()
	ks.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	return ", ".join(ks.slice(0, n).map(func(k): return "%s %d" % [k, d[k]]))

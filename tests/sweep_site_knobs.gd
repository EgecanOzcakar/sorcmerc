# MEASUREMENT (2026-09-25) — what core/site.gd's three untested knobs do to a
# whole delve: MAX_DEPTH (how deep the deepest lair runs), SUPPORT_CHANCE (how
# often a floor offers something other than a fight) and REST_SHARE (how many
# of those are a short rest rather than a cache). The design audit §7.3 named
# them "the attrition of the game's hardest content" with no sweep behind them.
# Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_site_knobs.gd
#   SEEDS=5 LEVEL=0 godot ... -s tests/sweep_site_knobs.gd
#
# tests/sweep_site_depth.gd answers a per-ROOM question (of the parties that
# reached room d, how many won it). This answers the per-DELVE one a player
# lives: walking in fresh, how often does the company clear the lair, how often
# does it wipe, how many fights and rests does it meet on the way, and what is
# it holding (HP, slots) when it opens the boss's door. A knob is measured by
# running this same file in a copy of the tree with that one constant edited —
# they are consts, and a sweep that patched them from outside would be
# measuring a different program from the one that ships.
#
# The party is the preset trio at level 3+LEVEL (default 0: level 3, in band
# for the Heartland lair it stands at), one lair per faction per seed, the
# rooms priced by core/site.gd exactly as the game prices them. Two policies
# bracket play, as sweep_site_depth's do:
#   rest   take a rest room whenever one is offered, else the first way on
#   fight  always the first way on — core/site.gd makes it a fight — never rest
#
# Its table is in core/site.gd's header, under REST_SHARE.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")
const Scaler = preload("res://core/scaler.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 14
	var extra := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 0
	print("MAX_DEPTH %d  SUPPORT_CHANCE %.2f  REST_SHARE %.2f  level %d  %d seeds x %d factions" % [
		Site.MAX_DEPTH, Site.SUPPORT_CHANCE, Site.REST_SHARE, 3 + extra, seeds, Scaler.FACTIONS.size()])
	print("  policy  delves  cleared  wiped  fights  rests  boss-reached  hp@boss  slots@boss  boss-won")
	for policy in ["rest", "fight"]:
		var t := {"n": 0, "cleared": 0, "wiped": 0, "fights": 0, "rests": 0, "boss": 0, "hp": 0.0, "slots": 0.0, "boss_won": 0,
			"depth": {}}
		for f in Scaler.FACTIONS:
			for s in range(1, seeds + 1):
				_delve(String(f), s, extra, policy, t)
		var n: float = maxf(1.0, float(t["n"]))
		var b: float = maxf(1.0, float(t["boss"]))
		print("  %-6s  %6d  %6.1f%%  %5.1f%%  %6.2f  %5.2f  %11.1f%%  %6.0f%%  %9.0f%%  %7.1f%%" % [
			policy, t["n"], 100.0 * t["cleared"] / n, 100.0 * t["wiped"] / n, t["fights"] / n, t["rests"] / n,
			100.0 * t["boss"] / n, 100.0 * t["hp"] / b, 100.0 * t["slots"] / b, 100.0 * t["boss_won"] / b])
		var keys: Array = t["depth"].keys()
		keys.sort()
		var line := "          cleared by depth:"
		for d in keys:
			var dd: Array = t["depth"][d]
			line += "  %d rooms %4.1f%% (%d)" % [d, 100.0 * dd[1] / maxf(1.0, dd[0]), dd[0]]
		print(line)
	quit(0)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party(extra: int) -> Party:
	var p = Party.new()
	for ch in Presets.party_at(3 + extra):
		p.add_member(ch)
	return p

func _pick(opts: Array, policy: String) -> int:
	if policy == "rest":
		for i in opts.size():
			if String(opts[i].get("kind", "")) == "rest":
				return i
	return 0

# HP as a fraction of max and slots left as a fraction of the full set, read off
# the Characters: what Adapter will hand the next fight.
func _condition(party) -> Array:
	var hp := 0.0
	var mx := 0.0
	var left := 0
	var full := 0
	for ch in party.party_characters():
		var sheet = ch.sheet()
		mx += float(sheet.max_hp)
		hp += float(ch.hp_current if ch.hp_current >= 0 else sheet.max_hp)
		for n in Adapter.slots_left(ch):
			left += int(n)
		for n in Adapter._full_slots(sheet):
			full += int(n)
	return [hp / maxf(mx, 1.0), float(left) / maxf(float(full), 1.0)]

func _fight(party, spec: Dictionary, seed: int) -> bool:
	var chars: Array = party.party_characters()
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var team: Array = []
	for i in chars.size():
		team.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var cb = Encounter.build(sp, team)
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	Adapter.write_back_all(cb.combatants.filter(func(c): return c.team == "party"), chars)
	return cb.outcome() == "Victory"

func _delve(faction: String, seed: int, extra: int, policy: String, t: Dictionary) -> void:
	var w := _world()
	var party := _party(extra)
	var lair = w.add_lair(World.Lair.new("ksweep-%s-%d" % [faction, seed], Vector2.ZERO, faction))
	var s = Site.for_lair(lair, party, w)
	var last: int = s.depth_total() - 1
	t["n"] += 1
	var dd: Array = t["depth"].get(s.depth_total(), [0, 0])
	dd[0] += 1
	t["depth"][s.depth_total()] = dd
	var guard := 0
	while not s.is_over() and guard < 12:
		guard += 1
		var at: int = s.depth
		var opts: Array = s.options()
		if opts.is_empty():
			break
		var room: Dictionary = s.enter(_pick(opts, policy))
		if String(room["kind"]) == "combat":
			t["fights"] += 1
			if at == last:
				var cond := _condition(party)
				t["boss"] += 1
				t["hp"] += cond[0]
				t["slots"] += cond[1]
			var won := _fight(party, s.combat_spec(), seed * 131 + at)
			if won and at == last:
				t["boss_won"] += 1
			s.finish_combat({"outcome": "Victory" if won else "Defeat", "deaths": [], "downed": []})
		elif String(room["kind"]) == "treasure":
			s.take()
		elif s.short_rest():
			t["rests"] += 1
		if s.state == "wiped":
			t["wiped"] += 1
			return
		s.leave()
	if s.state == "cleared":
		t["cleared"] += 1
		t["depth"][s.depth_total()][1] += 1

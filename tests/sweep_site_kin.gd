# MEASUREMENT SPIKE (2026-09-22) — what pinning a lair's rooms to the lair's
# own people costs. Not a test, and not part of tools/run_tests.sh (the runner
# globs test_* and drive_*). Kept the way tests/sweep_range.gd and
# tests/sweep_party_opinion.gd are kept: so the claim can be re-run rather than
# re-argued. Whatever grid it prints belongs in core/site.gd's header and in
# docs/expansion-plan.md, named as this sweep's.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_site_kin.gd
#   SEEDS=40 godot --headless --path . -s tests/sweep_site_kin.gd
#
# Run it once before the change and once after; the script itself has no
# switch, because a switch in core/ that only a sweep reads is a worse thing
# to own than running the sweep twice.
#
# What it does: a whole delve per seed, autoplayed on ONE set of resources the
# way a real one is — the party's HP, slots and pools carry room to room
# through Adapter, a rest room is the only thing that gives any of it back —
# and counts how often the party reaches the bottom. Per faction, because the
# faction IS the variable: the lair is always at the origin (heartland, so
# core/regions.gd's band clamp is a no-op and cannot muddy the comparison) and
# always the same level-3 preset party.
#
# It also prints WHICH peoples the rooms drew, which is the whole point: before
# the change a lair whose faction has no board of its own draws a fresh
# arbitrary faction per room.
#
# Two things it deliberately does NOT model, because both would only add noise
# to a before/after of one variable:
#  - It always takes the first option at each depth. A real player picks, and
#    the pick changes the route; a fixed policy is the same fixed policy on
#    both sides of the comparison.
#  - It ignores core/regions.gd's HOMES, which is where a faction's lairs
#    actually get placed — dragons live in the deeps, so a real dragon cave is
#    met at a deeper band and a higher budget than the origin gives it. Run it
#    with LEVEL set for that end of the map rather than moving the lair, so the
#    band clamp stays a no-op and the faction stays the only thing that moved.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Regions = preload("res://core/regions.gd")

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

# The calibration trio, optionally levelled the way tests/test_scaler.gd's
# higher-level sweep levels it. LEVEL is the number of levels ADDED, so 0 is
# the level-3 preset party core/scaler.gd's own numbers are measured on.
static var _extra := 0

func _party() -> Party:
	var p = Party.new()
	var roster: Array = Presets.party() if _extra == 0 else [
		_lvl(Presets.vera(), "fighter", _extra), _lvl(Presets.pike(), "rogue", _extra),
		_lvl(Presets.ilsa(), "cleric", _extra)]
	for ch in roster:
		p.add_member(ch)
	return p

func _lvl(ch, class_id: String, extra: int):
	for _i in extra:
		ch.add_level(class_id, -1)
	return ch

func _party_at(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

# One fight, autoplayed, with the party's state carried in and back out.
func _fight(party, spec: Dictionary, seed: int) -> bool:
	var chars: Array = party.party_characters()
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var team: Array = _party_at(chars)
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

# Every people a spec's roster draws from. A monster the bestiary has no
# faction for is named outright rather than lumped under "?" — that is either a
# boss lead off core/campaign.gd's BOSS_POOL or one of Scaler.MIX's hand-tuned
# fallbacks, and which it is matters when reading a row.
func _kin(spec: Dictionary, into: Dictionary) -> void:
	for m in spec.get("monsters", []):
		var id := String(m["id"])
		var fac := String(Catalog.monster(id).get("faction", ""))
		into[fac if fac != "" else "?" + id] = true

# One whole delve. Returns {cleared, rooms, kin}.
func _delve(faction: String, seed: int) -> Dictionary:
	var w := _world()
	var party := _party()
	var lair = w.add_lair(World.Lair.new("sweep-%s-%d" % [faction, seed], Vector2.ZERO, faction))
	var s = Site.for_lair(lair, party, w)
	var kin := {}
	var rooms := 0
	var won_rooms := 0
	var guard := 0
	while not s.is_over() and guard < 12:
		guard += 1
		var opts: Array = s.options()
		if opts.is_empty():
			break
		var room: Dictionary = s.enter(0)
		match String(room["kind"]):
			"combat":
				rooms += 1
				var spec: Dictionary = s.combat_spec()
				_kin(spec, kin)
				var won := _fight(party, spec, seed * 131 + rooms)
				if won:
					won_rooms += 1
				s.finish_combat({"outcome": "Victory" if won else "Defeat",
					"deaths": [], "downed": []})
			"treasure":
				s.take()
			"rest":
				s.short_rest()
		if s.state == "wiped":
			break
		s.leave()
	var out: Array = kin.keys()
	out.sort()
	return {"cleared": s.state == "cleared", "rooms": rooms, "won": won_rooms,
		"depth": Site.depth_for(lair), "kin": out}

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 40
	_extra = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 0
	# Every faction a lair can be, themed ones first as the control: those have
	# a board of their own, so nothing about them changes either way and their
	# rows are the "did the harness move under me" check.
	var themed: Array = []
	var themeless: Array = []
	for f in Scaler.FACTIONS:
		if Site.theme_for_faction(f) != "":
			themed.append(f)
		else:
			themeless.append(f)
	print("seeds per faction: %d, party level 3+%d, lair at the origin (band 1.0)" % [seeds, _extra])
	print("%-13s %-6s %5s %7s %6s  %s" % [
		"faction", "board", "depth", "rooms w", "clear", "peoples the rooms drew"])
	for group in [themed, themeless]:
		for f in group:
			var cleared := 0
			var kin := {}
			var won := 0
			var depth := 0
			for s in range(1, seeds + 1):
				var r: Dictionary = _delve(f, s)
				if r["cleared"]:
					cleared += 1
				won += int(r["won"])
				depth = int(r["depth"])
				for k in r["kin"]:
					kin[k] = true
			var names: Array = kin.keys()
			names.sort()
			# "rooms w" is the one with resolution: a level-3 party clears very
			# few whole sites, so a clear rate alone floors at 0 and hides
			# whatever the change did. Mean fights won per delve does not.
			print("%-13s %-6s %5d %7.2f %5.1f%%  %d: %s" % [f,
				"yes" if Site.theme_for_faction(f) != "" else "no", depth,
				float(won) / seeds, 100.0 * cleared / seeds, names.size(), ", ".join(names)])
		print("")
	quit(0)

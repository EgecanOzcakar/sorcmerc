# MEASUREMENT SPIKE (2026-09-22) — the win rate of every lair boss, the six
# themed ones from core/campaign.gd's BOSS_POOL beside the ten faction ones
# core/site.gd's FACTION_BOSS adds. Not a test, and not part of
# tools/run_tests.sh (the runner globs test_* and drive_*). Kept the way
# tests/sweep_range.gd and tests/sweep_site_kin.gd are kept: so the claim can
# be re-run rather than re-argued.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_faction_boss.gd
#   SEEDS=40 godot --headless --path . -s tests/sweep_faction_boss.gd
#
# Deliberately the same shape tests/test_scaler.gd's _sweep_boss uses for
# BOSS_POOL's own published numbers, so a new row is comparable to an old one:
# one boss room per seed, a level-3 preset party at FULL HP, autoplayed. That
# is the boss on its own terms — not the boss at the bottom of four rooms of
# attrition, which is what tests/sweep_site_kin.gd measures and what a player
# actually meets. Both numbers are worth having and they are not the same
# number.
#
# The themed rows are the control and the yardstick at once: they come through
# core/site.gd unchanged by this pass, and BOSS_POOL's published spread
# (mammoth 65%, oni 82.5%, arrow-chief 82.5%, shrine 77%, assassin 92.5%,
# captain 92.5%) is the company a new boss should be keeping. The band that
# must hold is tests/test_scaler.gd's climax band, 15-85%.
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

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _party_at(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

# The boss room of a lair of this faction, on its own seed. The lair sits at
# the origin so core/regions.gd's band clamp is a no-op — every boss is priced
# for the same party rather than for the ring its faction happens to live in.
func _boss_spec(faction: String, seed: int) -> Dictionary:
	var w := _world()
	var party := _party()
	var lair = w.add_lair(World.Lair.new("bsweep-%s-%d" % [faction, seed], Vector2.ZERO, faction))
	var s = Site.for_lair(lair, party, w)
	s.depth = s.depth_total() - 1
	s.state = "picking"
	s.enter(0)
	return {"spec": s.combat_spec(), "room": s.room, "party": party}

func _fight(party, spec: Dictionary, seed: int) -> bool:
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var cb = Encounter.build(sp, _party_at(party.party_characters()))
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return cb.outcome() == "Victory"

# What the boss room actually fielded, for reading a row that surprises you.
func _shape(spec: Dictionary) -> String:
	var bits: Array = []
	for m in spec.get("monsters", []):
		bits.append("%dx%s@%.2f" % [int(m.get("count", 1)), String(m["id"]), float(m.get("mult", 1.0))])
	return ", ".join(bits)

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 40
	# ONLY=cultist,soldier to re-measure one row after turning a knob, instead
	# of paying for all fifteen every iteration.
	var only: Array = OS.get_environment("ONLY").split(",", false)
	var themed: Array = []
	var own: Array = []
	for f in Scaler.FACTIONS:
		if not only.is_empty() and not f in only:
			continue
		if Site.theme_for_faction(f) != "":
			themed.append(f)
		else:
			own.append(f)
	print("seeds per boss: %d, level-3 preset party at full HP, lair at the origin" % seeds)
	print("%-13s %-6s %6s  %-34s %s" % ["faction", "board", "win", "title", "what it fielded (seed 1)"])
	for group in [themed, own]:
		for f in group:
			var wins := 0
			var title := ""
			var shape := ""
			for s in range(1, seeds + 1):
				var b: Dictionary = _boss_spec(f, s)
				if s == 1:
					title = String(b["room"].get("title", ""))
					shape = _shape(b["spec"])
				if _fight(b["party"], b["spec"], s):
					wins += 1
			print("%-13s %-6s %5.1f%%  %-34s %s" % [f,
				"yes" if Site.theme_for_faction(f) != "" else "no",
				100.0 * wins / seeds, title, shape])
		print("")
	quit(0)

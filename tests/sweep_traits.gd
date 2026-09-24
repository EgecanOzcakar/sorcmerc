# MEASUREMENT (#176 step 2) — what each personality trait does to a fight.
# Not a test; the numbers it prints are the ones data/traits.json's
# "_measured" lines and core/traits.gd's CAP comment carry.
#   godot --headless --path . -s tests/sweep_traits.gd
#   SWEEP_SEEDS=60 godot --headless --path . -s tests/sweep_traits.gd   # quicker, noisier
#
# The same fixed party as every other sweep here (Presets.party(): Vera
# fighter, Pike rogue, Ilsa cleric, level 3), the same Scaler.roster_for on
# "normal" and the eight board themes in turn, so the baseline row is
# comparable to tests/sweep_party_opinion.gd's. Each variant gives ONE trait to
# all three heroes — the loudest a trait can be — and fights the same seeds.
# Where a board has a biome it is told so (spec.where), so an origin fires on
# its own ground and the table says how often that is.
#
# Columns: win% and its move from the baseline, mean rounds, heroes downed per
# fight, and how many of the fights the trait counted in at all (a term was
# non-zero at least once) — a trait that never fires moves nothing and says
# nothing about its size.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Combat = preload("res://core/combat.gd")
const Traits = preload("res://core/traits.gd")

const DIFFICULTY := "normal"
const THEME_BIOME := {"downs": "downs", "marsh": "marsh", "forest-clearing": "woods"}

# Counts every term the traits hand the fight, without changing any of them.
class Measured extends Combat:
	var fired := 0
	func _say_trait(c, term: Dictionary, what: String) -> void:
		if int(term.get("n", 0)) != 0 or what == "advantage":
			fired += 1
		super(c, term, what)

func _init() -> void:
	var seeds := int(OS.get_environment("SWEEP_SEEDS")) if OS.get_environment("SWEEP_SEEDS") != "" else 120
	print("party=vera/pike/ilsa lvl3  seeds=%d  difficulty=%s  CAP=%d" % [seeds, DIFFICULTY, Traits.CAP])
	print("%-15s %6s %6s %7s %6s %7s" % ["variant", "win%", "Δwin", "rounds", "downs", "fired%"])
	var base := {}
	var variants: Array = [""]
	variants.append_array(Traits.of_family("temperament"))
	variants.append_array(Traits.of_family("origin"))
	for v in variants:
		var t := {"wins": 0, "rounds": 0, "downs": 0, "fired": 0}
		for s in range(1, seeds + 1):
			var theme: String = Encounter.THEMES[s % Encounter.THEMES.size()]
			var r := _fight(String(v), theme, s)
			t["wins"] += 1 if r["won"] else 0
			t["rounds"] += r["rounds"]
			t["downs"] += r["downs"]
			t["fired"] += 1 if (r["fired"] > 0 or r["stamped"]) else 0
		var win: float = 100.0 * t["wins"] / seeds
		if v == "":
			base = {"win": win}
		print("%-15s %5.1f%% %+5.1f %7.2f %6.2f %6.0f%%" % [
			"baseline" if v == "" else Traits.name_of(v), win, win - float(base["win"]),
			float(t["rounds"]) / seeds, float(t["downs"]) / seeds, 100.0 * t["fired"] / seeds])
	quit(0)

func _fight(trait_id: String, theme: String, seed_value: int) -> Dictionary:
	var p := Party.new()
	for ch in Presets.party():
		if trait_id != "":
			ch.traits = [{"id": trait_id, "why": "sweep"}]
		p.add_member(ch)
	var chars: Array = p.party_characters()
	var spec: Dictionary = Scaler.roster_for(chars, DIFFICULTY, {}, theme, seed_value)
	spec["theme"] = theme
	spec["seed"] = seed_value
	if THEME_BIOME.has(theme):
		spec["where"] = {"biome": THEME_BIOME[theme], "band": "heartland", "site": "road"}
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var built = Encounter.build(spec, party)
	# Re-home the built fight in the measuring subclass: same RNG seed, same
	# combatants, same board, so the fight is the one Encounter.build made.
	var RNG = load("res://core/rng.gd")
	var cb := Measured.new(RNG.new(seed_value), built.combatants, built.board)
	cb.purse = built.purse
	cb.objective = built.objective
	cb.party = p
	var stamped: bool = built.log.any(func(l): return " here: " in String(l))   # the fight-start stamp's line
	var guard := 0
	while not cb.is_over() and guard < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		guard += 1
	return {"won": cb.outcome() == "Victory", "rounds": cb.round_num, "downs": cb.downed.size(),
		"fired": cb.fired, "stamped": stamped}

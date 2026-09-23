# MEASUREMENT (#176 step 4's still-open line) — what a trait does to the road's
# own checks. tests/sweep_traits.gd measures traits in a fight; this measures
# them on the road event roller (core/travel.gd's check), which is where the
# origins' skill terms and the travel term land: Marsh-bred's +2 survival in
# the marsh, Street-raised's −2 survival in the wild, Downs-rider's +1 travel
# on the downs, Cautious's −1 travel everywhere. Not a test; its table is the
# one core/traits.gd's road section cites.
#
#   godot --headless --path . -s tests/sweep_traits_road.gd
#   SWEEP_SEEDS=300 godot --headless --path . -s tests/sweep_traits_road.gd   # quicker, noisier
#
# The preset trio (Presets.party(), level 3) on the road in each of the three
# biomes (core/world.gd's BIOMES), by day, heartland, at a normal pace, nobody
# named for a job, so the roller is whoever is best — the way most players
# leave it. Each variant gives ONE trait to all three heroes, the loudest it
# can be, and rolls the same seeds. A fresh party per seed, so the road's
# opinion feedback (PartyOpinion.road_result) and its costs never compound.
#
# Columns: of the events that asked for a roll, how many passed, the move from
# the baseline in that biome, and how many of the rolls the trait was part of
# (the roller's skill or travel term was non-zero). An event answered by a
# spell or with no check at all is not a roll and is not counted.
extends SceneTree

const Travel = preload("res://core/travel.gd")
const Traits = preload("res://core/traits.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Campaign = preload("res://core/campaign.gd")
const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")

func _init() -> void:
	var seeds := int(OS.get_environment("SWEEP_SEEDS")) if OS.get_environment("SWEEP_SEEDS") != "" else 1500
	print("party=vera/pike/ilsa lvl3  seeds=%d a biome  pace=normal, roller=whoever is best" % seeds)
	var variants: Array = [""]
	variants.append_array(Traits.of_family("origin"))
	variants.append("cautious")
	for biome in World.BIOMES:
		print("\n%-6s %-14s %6s %6s %8s" % [biome, "variant", "pass%", "Δpass", "counted"])
		var base := 0.0
		for v in variants:
			var t := {"rolls": 0, "ok": 0, "counted": 0}
			for s in range(1, seeds + 1):
				var e := _roll(String(v), String(biome), s)
				if not e.has("nat"):
					continue
				t["rolls"] += 1
				t["ok"] += 1 if e["ok"] else 0
				t["counted"] += 1 if e.get("_term", 0) != 0 else 0
			var rate: float = 100.0 * t["ok"] / maxi(1, t["rolls"])
			if v == "":
				base = rate
			print("%-6s %-14s %5.1f%% %+5.1f %7.0f%%" % ["", "baseline" if v == "" else Traits.name_of(v), rate,
				rate - base, 100.0 * t["counted"] / maxi(1, t["rolls"])])
	quit(0)

func _roll(trait_id: String, biome: String, seed_value: int) -> Dictionary:
	var p := Party.new()
	for ch in Presets.party():
		if trait_id != "":
			ch.traits = [{"id": trait_id, "why": "sweep"}]
		p.add_member(ch)
	p.here = {"biome": biome, "band": "heartland", "site": "road", "night": false}
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(4000, 4000), "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var e := Travel.check(p, w, RNG.new(seed_value))
	if e.has("nat"):
		# Whether the trait was part of this roll: the roller's travel term (on
		# the result) or their skill term for the skill they rolled.
		var who = p.get_member(String(e.get("char_id", "")))
		var n := int(e.get("trait_term", {}).get("n", 0))
		if who != null and String(e.get("skill", "")) != "":
			n += int(Traits.skill_term(who, String(e["skill"]), p.here)["n"])
		e["_term"] = n
	return e

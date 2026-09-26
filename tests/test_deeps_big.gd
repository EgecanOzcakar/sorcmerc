# The Far Deeps' big one (core/scaler.gd BIG_CHANCE / BIG_SHARE, the Deeps'
# teeth, 2026-09-25): a road fight in the inner Deeps or the Unmapped sometimes
# stands one CR 11+ creature alone in place of the warband, priced so the fight
# plays the same. Rosters only, no fights — tests/sweep_deeps_big.gd carries
# the win rates.
#   godot --headless --path . -s tests/test_deeps_big.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Power = preload("res://core/rules/power.gd")

# tests/sweep_deeps_big.gd's roaming population of one Far Deeps band.
const MIX := ["undead", "undead", "giant", "monstrosity", "fey", "fey", "fey", "fey",
	"elemental", "elemental", "elemental", "elemental", "construct", "construct", "construct", "construct"]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_other_bands_untouched()
	test_forced_big_one()
	test_fey_have_none()
	test_shipped_share()
	print("test_deeps_big: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _is_big(spec: Dictionary) -> bool:
	for m in spec["monsters"]:
		if float(Catalog.monster(String(m["id"])).get("cr", 0.0)) >= Scaler.BIG_CR:
			return true
	return false

# Only the bands BIG_CHANCE names are touched: every other band, and no band,
# builds byte for byte what it built before — even with the roll forced on.
func test_other_bands_untouched() -> void:
	check(Scaler.BIG_CHANCE.keys().all(func(b): return b in ["deeps", "unmapped"]),
		"only the Far Deeps' two bands roll a big one (%s)" % str(Scaler.BIG_CHANCE.keys()))
	Scaler.big_chance_override = 1.0
	for lvl in [3, 12]:
		var chars: Array = Presets.party_at(lvl)
		for s in range(1, 13):
			var seed_v: int = Scaler.pin_faction(s * 31, String(MIX[s % MIX.size()]))
			var plain := str(Scaler.roster_for(chars, "easy", {}, "", seed_v))
			for band in ["", "heartland", "marches", "frontier"]:
				check(str(Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, band)) == plain,
					"level %d seed %d: band \"%s\" builds the roster it always did" % [lvl, s, band])
	Scaler.big_chance_override = -1.0

# Forced on in the Unmapped: one creature, CR 11+, of the warband's own people,
# priced at BIG_SHARE of the budget (the first MULT_STEP that reaches it).
func test_forced_big_one() -> void:
	var chars: Array = Presets.party_at(17)
	var seed_v: int = Scaler.pin_faction(4242, "undead")
	Scaler.big_chance_override = 1.0
	var spec: Dictionary = Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, "unmapped")
	var again: Dictionary = Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, "unmapped")
	Scaler.big_chance_override = 0.0
	var never: Dictionary = Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, "unmapped")
	Scaler.big_chance_override = -1.0
	check(spec["monsters"].size() == 1 and int(spec["monsters"][0]["count"]) == 1,
		"the big one stands alone (%s)" % str(spec))
	var m: Dictionary = spec["monsters"][0]
	var mon: Dictionary = Catalog.monster(String(m["id"]))
	check(float(mon.get("cr", 0.0)) >= Scaler.BIG_CR and String(mon.get("faction", "")) == "undead",
		"a CR %s %s, one of the warband's own people" % [str(mon.get("cr")), String(m["id"])])
	var budget: float = Scaler._budget(chars, "easy")
	var score: float = Power.team_score([Encounter.spawn(String(m["id"]), float(m["mult"]), "foe", Vector2i.ZERO)])
	var under: float = Power.team_score([Encounter.spawn(String(m["id"]),
		float(m["mult"]) - Scaler.MULT_STEP, "foe", Vector2i.ZERO)])
	check(score >= budget * Scaler.BIG_SHARE and under < budget * Scaler.BIG_SHARE,
		"priced at BIG_SHARE of the budget (%.1f, one step under %.1f, target %.1f)" % [
			score, under, budget * Scaler.BIG_SHARE])
	check(str(spec) == str(again), "the same fight seed meets the same creature")
	check(str(never) == str(Scaler.roster_for(chars, "easy", {}, "", seed_v)),
		"rolled off, the warband is the one it always was")

func test_fey_have_none() -> void:
	var chars: Array = Presets.party_at(17)
	var seed_v: int = Scaler.pin_faction(77, "fey")
	Scaler.big_chance_override = 1.0
	var spec := str(Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, "unmapped"))
	Scaler.big_chance_override = -1.0
	check(spec == str(Scaler.roster_for(chars, "easy", {}, "", seed_v)),
		"the fey have nothing at CR 11+, so their warband is untouched")

# The owner's target: a CR 11+ creature in 25-35% of Far Deeps road fights at
# the levels those bands are built for. MEASURED with the shipped chances,
# 200 seeds a point (tests/sweep_deeps_big.gd's table); one point a band here.
func test_shipped_share() -> void:
	for pt in [["deeps", 12], ["unmapped", 17]]:
		var chars: Array = Presets.party_at(int(pt[1]))
		var big := 0
		for s in range(1, 201):
			var seed_v: int = Scaler.pin_faction(s * 7919, String(MIX[s % MIX.size()]))
			if _is_big(Scaler.roster_for(chars, "easy", {}, "", seed_v, 1.0, [], "", 0, String(pt[0]))):
				big += 1
		var rate := big / 2.0
		check(rate >= 25.0 and rate <= 35.0,
			"%s at level %d: a CR 11+ creature in %.1f%% of fights (want 25-35)" % [pt[0], pt[1], rate])

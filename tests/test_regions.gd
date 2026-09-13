# D6 — the map is banded. The model only, headless.
#
# What this pins is the one property that makes a band worth having: content
# stops following the party at the band's edge. Inside the band nothing changes
# (every measured number in core/scaler.gd still means what it says); outside
# it, the heartland is outgrown and the deeps are not survivable early. If the
# clamp ever silently becomes a scale again, these fail.
#   godot --headless --path . -s tests/test_regions.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Regions = preload("res://core/regions.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# A party of three at `level`, built from the same trio the ruler uses so a
# level comparison is a level comparison and nothing else.
func _party_at(level: int) -> Party:
	var p = Party.new()
	for ch in Presets.party_at(level):
		p.add_member(ch)
	return p

# A map 1000 units across, so the band seams land at 500 / 710 / 870 — the
# equal-area quarters core/regions.gd bands on.
func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_lair(World.Lair.new("edge", Vector2(1000, 0), "dragon"))
	return w

func _init() -> void:
	var w := _world()

	# --- where the rings are ------------------------------------------------
	check(Regions.anchor(w) == Vector2.ZERO, "the rings are anchored on the human settlement")
	check(is_equal_approx(Regions.extent(w), 1000.0), "and sized to the furthest thing on the map")
	check(Regions.band_of(w, Vector2(100, 0)) == "heartland", "home is the heartland")
	check(Regions.band_of(w, Vector2(600, 0)) == "marches", "a few hours out is the marches")
	check(Regions.band_of(w, Vector2(800, 0)) == "frontier", "past that is the frontier")
	check(Regions.band_of(w, Vector2(980, 0)) == "deeps", "the far edge is the deeps")
	check(Regions.band_of(w, Vector2(9999, 0)) == "deeps", "and so is anything past the edge")
	check(Regions.band_of(w, Vector2(0, -600)) == "marches", "the rings are rings, not a corridor")

	# The anchor does not follow the party — a map whose far away moves with you
	# has no far away in it.
	var moved := _world()
	moved.add_party(World.RoamingParty.new("player", Vector2(800, 0), "human", true))
	check(Regions.band_of(moved, Vector2(800, 0)) == "frontier",
		"standing in the frontier does not make it home")

	# Small maps are not sliced into four rings a stone's throw apart.
	var tiny = World.new()
	tiny.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "town"))
	tiny.add_lair(World.Lair.new("close", Vector2(120, 0), "goblinoid"))
	check(Regions.extent(tiny) >= Regions.MIN_EXTENT, "a cramped map keeps a floor under its extent")
	check(Regions.band_of(tiny, Vector2(120, 0)) == "heartland", "so all of it is still home")

	# The seams are equal-area quarters, not equal-radius slices. Pinned because
	# the difference is invisible in the constant and enormous on the map: at the
	# old 0.30/0.60/0.85 the heartland was 9% of the map and its three neighbours
	# 27/36/28%, which is how the band built for levels 1-3 ended up a bubble with
	# nothing but the starting town in it.
	var prev_area := 0.0
	for b in Regions.BANDS:
		var hi: float = minf(float(b["upto"]), 1.0)
		var share: float = hi * hi - prev_area
		check(absf(share - 0.25) < 0.03, "%s is a quarter of the map (%.0f%%)" % [b["id"], share * 100.0])
		prev_area = hi * hi

	# Every real map the game ships bands into more than one country, or the
	# feature does nothing where it actually has to work — AND its near ring holds
	# something, or a level 1-3 party has a country of its own with no destination
	# in it and has to ride into the marches to find its first fight.
	for builder in [preload("res://scenes/world/large_world.gd").build(),
			preload("res://scenes/world/procedural_world.gd").build(4242)]:
		var seen := {}
		for l in builder.lairs:
			seen[Regions.band_of(builder, l.position)] = true
		check(seen.size() >= 2, "a shipped map's lairs are spread over %d bands" % seen.size())
		check(seen.has("heartland"), "...and one of them is the heartland, so home has somewhere to go")

	# --- the clamp ----------------------------------------------------------
	var p3 := _party_at(3)
	var p10 := _party_at(10)
	check(Regions.party_level(p3) == 3, "a party of level 3s is a level 3 party")
	check(Regions.party_level(p10) == 10, "...and a party of level 10s is a level 10 party")

	# Inside the band, nothing happens at all. This is the case that must stay
	# free: every win rate core/scaler.gd measured was measured at x1.00.
	check(Regions.power_scale(w, Vector2(600, 0), p3) == 1.0,
		"a level 3 party in the marches gets the fight scaler already measured")
	check(Regions.power_scale(w, Vector2(800, 0), p10) == 1.0,
		"...and so does a level 10 party in the frontier")

	# Outside it, the content stops following.
	var outgrown := Regions.power_scale(w, Vector2(100, 0), p10)
	check(outgrown < 0.6, "a level 10 party has outgrown the heartland (x%.2f)" % outgrown)
	var lethal := Regions.power_scale(w, Vector2(980, 0), p3)
	check(lethal > 2.0, "a level 3 party in the deeps is in real trouble (x%.2f)" % lethal)

	# And it is monotone in both directions, which is what makes the map read as
	# a gradient rather than as four unrelated difficulty settings.
	var last := 0.0
	for x in [100, 600, 800, 980]:
		var s: float = Regions.power_scale(w, Vector2(x, 0), p3)
		check(s >= last, "further out is never easier (at %d: x%.2f)" % [x, s])
		last = s

	# The level a fight is built for is the clamp itself, stated plainly.
	check(Regions.level_here(w, Vector2(100, 0), p10) == 3, "the heartland builds for level 3")
	check(Regions.level_here(w, Vector2(980, 0), p3) == 10, "the deeps build for level 10")
	check(Regions.level_here(w, Vector2(600, 0), p3) == 3, "and the marches for whoever is standing in them")

	# --- the ruler ----------------------------------------------------------
	# It has to be monotone or the clamp above is meaningless, and it has to
	# agree with the anchor the whole scaler is tuned around.
	var prev := 0.0
	for n in range(1, 21):
		var s: float = Regions.ref_score(n)
		check(s > prev, "the ruler climbs at level %d (%.1f)" % [n, s])
		prev = s
	check(absf(Regions.ref_score(3) - Scaler.REF_SCORE) < 5.0,
		"the ruler agrees with REF_SCORE at level 3 (%.1f vs %.1f)" % [
			Regions.ref_score(3), Scaler.REF_SCORE])
	check(Regions.ref_score(21) == Regions.ref_score(20), "level 20 is the top of it")
	check(Regions.ref_score(0) == Regions.ref_score(1), "and level 1 the bottom")

	# --- where things belong ------------------------------------------------
	check(Regions.suits("deeps", "dragon"), "dragons live out in the deeps")
	check(not Regions.suits("heartland", "dragon"), "...and not down the road from the capital")
	check(Regions.suits("heartland", "bandit"), "bandits work the roads people actually use")
	check(Regions.home_band("bandit") == "heartland", "so that is a bandit's home band")
	check(Regions.home_band("dragon") == "deeps", "and the deeps are a dragon's")
	check(Regions.home_band("nonsense-faction") == "deeps",
		"an unplaceable faction goes to the far end rather than into somebody's garden")
	var ring: Array = Regions.ring(w, "frontier")
	check(float(ring[0]) > 0.0 and float(ring[1]) > float(ring[0]), "a band names a real ring to place in")
	check(Regions.band_of(w, Vector2((float(ring[0]) + float(ring[1])) * 0.5, 0)) == "frontier",
		"...and the middle of that ring really is in it")

	# --- what the player is told --------------------------------------------
	var here: Dictionary = Regions.at(w, Vector2(800, 0))
	check(Regions.describe(here).find("levels 6-10") >= 0, "a band says who it is for")
	check(String(here["blurb"]) != "", "...and what it is like")
	var home: Dictionary = Regions.at(w, Vector2(100, 0))
	check(Regions.crossing_text(home, here).find("out into") >= 0, "going out is narrated as going out")
	check(Regions.crossing_text(here, home).find("back inside") >= 0, "and coming back as coming back")
	check(Regions.crossing_text(home, home) == "", "standing still is not narrated at all")
	check(Regions.crossing_text({}, here) == "", "and neither is a crossing from nowhere")

	# --- degenerate ---------------------------------------------------------
	var bare = World.new()
	check(Regions.anchor(bare) == Vector2.ZERO, "an empty world is anchored at the origin")
	check(Regions.band_of(bare, Vector2(10, 0)) == "heartland", "...and its middle is still home")
	check(Regions.power_scale(bare, Vector2(10, 0), Party.new()) == 1.0,
		"a party with nobody in it changes nothing")
	for b in Regions.BANDS:
		var lv: Array = b["levels"]
		check(int(lv[0]) < int(lv[1]), "%s spans real levels" % b["id"])
		check(not Regions.HOMES.get(String(b["id"]), []).is_empty(), "%s has something living in it" % b["id"])

	print("test_regions: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

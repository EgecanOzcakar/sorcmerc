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
	check(Regions.band_of(w, Vector2(900, 0)) == "deeps", "past the last waystone, the deeps")
	check(Regions.band_of(w, Vector2(980, 0)) == "unmapped", "the far edge is the Unmapped")
	check(Regions.band_of(w, Vector2(9999, 0)) == "unmapped", "and so is anything past the edge")
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
	# Four COUNTRIES, a quarter each; the Far Deeps' two bands split theirs in half
	# (the equal-area point of the old ring, 2026-09-25).
	for c in Regions.countries():
		var f: Array = Regions.country_fracs(c)
		var share: float = float(f[1]) * float(f[1]) - float(f[0]) * float(f[0])
		check(absf(share - 0.25) < 0.03, "%s is a quarter of the map (%.0f%%)" % [c, share * 100.0])
	for id in ["deeps", "unmapped"]:
		var f: Array = Regions.ring_fracs(id)
		var share: float = float(f[1]) * float(f[1]) - float(f[0]) * float(f[0])
		check(absf(share - 0.125) < 0.02, "%s is half of the Far Deeps (%.1f%% of the map)" % [id, share * 100.0])

	# --- the Far Deeps, split (the design audit §5.4, 2026-09-25) -------------
	# Added, not renamed: every band id a pack could have written still exists
	# and still means what it meant, and "deeps" still names the whole country
	# wherever something asks a yes-or-no question of it.
	var ids: Array = Regions.BANDS.map(func(b): return String(b["id"]))
	for old in ["heartland", "marches", "frontier", "deeps"]:
		check(ids.has(old), "%s is still a band" % old)
	check(Regions.countries() == ["heartland", "marches", "frontier", "deeps"], "still four countries (%s)" % str(Regions.countries()))
	check(Regions.band_by_id("deeps")["levels"] == [10, 14], "the inner Deeps are levels 10-14")
	check(Regions.band_by_id("unmapped")["levels"] == [15, 20], "the Unmapped are levels 15-20")
	check(Regions.country_of("unmapped") == "deeps" and Regions.country_of("frontier") == "frontier"
		and Regions.country_of("nowhere") == "nowhere", "a band's country is its part_of, or itself")
	check(Regions.within(w, Vector2(980, 0), "deeps") and Regions.within(w, Vector2(900, 0), "deeps"),
		"\"deeps\" holds in both halves")
	check(not Regions.within(w, Vector2(900, 0), "unmapped"), "...and \"unmapped\" only in its own")
	check(not Regions.within(w, Vector2(800, 0), "deeps"), "...and neither on the frontier")
	var far_ring: Array = Regions.country_ring(w, "deeps")
	check(is_equal_approx(float(far_ring[1]), 1000.0) and absf(float(far_ring[0]) - 870.0) < 1.0,
		"the Far Deeps as a country run from the frontier to the edge (%s)" % str(far_ring))
	var inner: Array = Regions.ring(w, "deeps")
	check(Regions.band_of(w, Vector2((float(inner[0]) + float(inner[1])) * 0.5, 0)) == "deeps",
		"placing into the deeps' own ring lands in the deeps")
	var edge: Dictionary = Regions.at(w, Vector2(980, 0))
	var deeps_here: Dictionary = Regions.at(w, Vector2(900, 0))
	check(Regions.crossing_text(deeps_here, edge).find("the Unmapped — levels 15-20") >= 0,
		"the crossing card names the new band (%s)" % Regions.crossing_text(deeps_here, edge))
	check(String(edge["blurb"]) != "" and String(edge["blurb"]).find("'") < 0, "...with a blurb, in the authored register")
	# Every point still maps to a band — a save's position from before the split
	# included — and the bands still tile the map with no gap.
	for x in [0, 499, 500, 709, 711, 869, 871, 939, 941, 1000, 5000]:
		check(ids.has(Regions.band_of(w, Vector2(x, 0))), "a point %d out is in some band" % x)
	var prev_hi := 0.0
	for b in Regions.BANDS:
		var f: Array = Regions.ring_fracs(String(b["id"]))
		check(is_equal_approx(float(f[0]), prev_hi), "%s starts where the last band stopped" % b["id"])
		prev_hi = float(f[1])

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
	check(Regions.power_scale(w, Vector2(900, 0), p10) == 1.0,
		"...and so does a level 10 party in the deeps")
	# The Unmapped start at 15: a level 10 party at the far edge is one band out,
	# and a level 15 one has outgrown the inner Deeps.
	check(Regions.power_scale(w, Vector2(980, 0), p10) > 1.0,
		"a level 10 party in the Unmapped is out of its depth (x%.2f)" % Regions.power_scale(w, Vector2(980, 0), p10))
	# The Unmapped is a wall, not a step (the Deeps' teeth, 2026-09-25): a party
	# under it meets its `under` level's fight, above its floor, where every
	# other band pins an under-levelled party to its floor.
	var unm: Dictionary = Regions.band_by_id("unmapped")
	var wall: int = Regions.under_level(unm)
	check(wall > 15 and wall <= 20, "the Unmapped pins a party under it above its floor (%d)" % wall)
	for id in ["heartland", "marches", "frontier", "deeps"]:
		var b: Dictionary = Regions.band_by_id(id)
		check(Regions.under_level(b) == int(b["levels"][0]), "%s pins an under-levelled party to its floor" % id)
	check(Regions.level_here(w, Vector2(980, 0), p10) == wall, "...so a level 10 party there builds for level %d" % wall)
	var fresh10: float = Regions.fresh_score(p10)
	check(is_equal_approx(Regions.power_scale(w, Vector2(980, 0), p10), Scaler.held_at(Regions.ref_score(wall), fresh10)),
		"...priced as scaler's level-%d fight" % wall)
	check(Regions.power_scale(w, Vector2(980, 0), p10) > Scaler.held_at(Regions.ref_score(15), fresh10),
		"...which is steeper than the plain pin at the floor")
	var p14 := _party_at(14)
	check(Regions.level_here(w, Vector2(980, 0), p14) == wall, "a level 14 party is under it too")
	var p15 := _party_at(15)
	check(Regions.power_scale(w, Vector2(980, 0), p15) == 1.0, "a level 15 party is at home at the edge")
	check(Regions.level_here(w, Vector2(980, 0), p15) == 15, "...and meets its own level there, not the wall's")
	check(Regions.level_here(w, Vector2(900, 0), p15) == 14, "...and has outgrown the inner Deeps")
	# The frontier stops at 9: level 10 has outgrown it, and belongs to the deeps
	# alone rather than being in band on both sides of that seam.
	check(Regions.power_scale(w, Vector2(800, 0), p10) < 1.0,
		"a level 10 party has outgrown the frontier (x%.2f)" % Regions.power_scale(w, Vector2(800, 0), p10))
	check(Regions.level_here(w, Vector2(800, 0), p10) == 9, "...which builds for level 9")

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

	# A country is pinned to scaler's budget for the ruler at its edge level, so
	# a party that is not the ruler cannot carry its surplus (or its shortfall)
	# across the border. Two level 10s and a stacked four both meet exactly the
	# heartland's level-3 fight; the old ruler-ratio gave them x0.66 and x1.33
	# of it.
	var ruler3: float = Scaler._budget(Presets.party_at(3), "easy", 1.0)
	var deeps10: float = Scaler._budget(Presets.party_at(10), "easy", 1.0)
	var thin := Party.new()
	var stacked := Party.new()
	var tens: Array = Presets.party_at(10)
	for i in 2:
		thin.add_member(tens[i])
	var fourth = Presets.party_at(10)[0]
	fourth.id = "fourth"
	for ch in tens + [fourth]:
		stacked.add_member(ch)
	var ones := Party.new()
	ones.add_member(Presets.party_at(1)[0])
	for pr in [[thin, "two level 10s"], [stacked, "four level 10s"], [p10, "the ruler"]]:
		var pp: Party = pr[0]
		var b: float = Scaler._budget(pp.party_characters(), "easy",
			Regions.power_scale(w, Vector2(100, 0), pp))
		check(absf(b / ruler3 - 1.0) < 0.01,
			"%s in the heartland meet its level-3 fight (x%.3f of it)" % [pr[1], b / ruler3])
	var lone: float = Scaler._budget(ones.party_characters(), "easy",
		Regions.power_scale(w, Vector2(900, 0), ones))
	check(absf(lone / deeps10 - 1.0) < 0.01,
		"a lone level 1 in the deeps meets its level-10 fight, not a share of it (x%.3f)" % [lone / deeps10])
	# The ceiling holds inside the band too. Four level 3s are a level 3 party,
	# inside the heartland by level, and price above the ruler: they still meet
	# the heartland's top fight and no more. In the marches (3-6) they are well
	# under its top, so the fight follows them as scaler measured it.
	var four3 := _party_at(3)
	var extra = Presets.party_at(3)[0]
	extra.id = "extra"
	four3.add_member(extra)
	var capped: float = Scaler._budget(four3.party_characters(), "easy",
		Regions.power_scale(w, Vector2(100, 0), four3))
	check(absf(capped / ruler3 - 1.0) < 0.01,
		"four level 3s at home meet the heartland's top fight, not more (x%.3f)" % [capped / ruler3])
	check(Regions.power_scale(w, Vector2(600, 0), four3) == 1.0,
		"...and in the marches, a fight their own size")

	# Spent slots still thin it in proportion, as they do in band.
	var spent: Party = _party_at(10)
	for ch in spent.party_characters():
		ch.slots_used.assign([99, 99, 99, 99, 99, 99, 99, 99, 99])
	var tired: float = Scaler._budget(spent.party_characters(), "easy",
		Regions.power_scale(w, Vector2(100, 0), spent))
	check(tired < ruler3, "a party with its slots spent meets less of it (x%.3f)" % [tired / ruler3])

	# The level a fight is built for is the clamp itself, stated plainly.
	check(Regions.level_here(w, Vector2(100, 0), p10) == 3, "the heartland builds for level 3")
	check(Regions.level_here(w, Vector2(900, 0), p3) == 10, "the deeps build for level 10")
	check(Regions.level_here(w, Vector2(980, 0), p3) == Regions.under_level(Regions.band_by_id("unmapped")),
		"...and the Unmapped for its wall's level")
	check(Regions.level_here(w, Vector2(600, 0), p3) == 3, "and the marches for whoever is standing in them")

	# --- the ruler ----------------------------------------------------------
	# It has to be monotone or the clamp above is meaningless, and it has to
	# agree with the anchor the whole scaler is tuned around.
	var prev := 0.0
	for n in range(1, 21):
		var s: float = Regions.ref_score(n)
		check(s > prev, "the ruler climbs at level %d (%.1f)" % [n, s])
		prev = s
	# T-classes widened this from 5.0: the ruler measures core/presets.gd's trio
	# live, and Ilsa got stronger when her Channel Divinity stopped being a button
	# with a 0-use pool (see docs/expansion-plan.md). The level-3 party now reads
	# 53.9 against an anchor of 46.6. That is the ruler telling the truth about a
	# party that really did gain an ability, not drift — but it does mean the
	# preset party now buys ~18% more budget than the tier sweep was calibrated
	# on, so core/scaler.gd's TIER wants its measured re-run (the header there
	# says as much: "re-run the sweep after touching ... any verb"). Until
	# somebody does that, this asserts the two are still the same size, not that
	# they still coincide.
	check(absf(Regions.ref_score(3) - Scaler.REF_SCORE) < 10.0,
		"the ruler is still the anchor's size at level 3 (%.1f vs %.1f)" % [
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

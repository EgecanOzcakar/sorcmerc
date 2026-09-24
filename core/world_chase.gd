# Running a band down. The player clicks a band's figure to go and meet it
# (scenes/world/world.gd's _seek), and the party follows it wherever it walks.
# Against a slower band that is the whole story: the party gains, and the card
# opens on contact. Against one that is as fast or faster, following alone
# never closes the gap. Beasts (1.3x), dragons (1.5x), a band walking off a
# parley's truce at the party's own pace. So a chase it cannot win on legs
# alone is won on a roll instead. Every INTERVAL world-minutes that the band is
# still in sight and not being gained on, the party's best runner rolls
# Athletics or Survival against a DC that rises with how much faster the band
# is. A hit runs it down, and the meeting happens there. MAX_TRIES misses and
# it gets away. So does a band that gets out of sight first. A fast band
# opens the gap between tries, so a dragon may leave room for only one, and
# the night's shorter sight for fewer.
#
# The party's pace is the lever the player already has: a forced march (1.4x)
# outpaces everything short of a dragon, and then there is no roll at all,
# just the gap closing. That is deliberate — the roll is for a chase the legs
# cannot settle, not a tax on every one.
#
# Owns the numbers and the roll. Does NOT own the chase itself (world.gd's
# _follow_meet steers, times the tries and counts the misses — transient
# state, so there is nothing to save), what the band does about being chased
# (core/world_ai.gd, which does not know it is), or the meeting (core/approach.gd).
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")

# ponytail: taste numbers, not measured ones. A chase is not in any win-rate
# band tests/test_scaler.gd sweeps, and nothing it decides is a fight's odds,
# only whether a fight happens. Re-cut them if a playtest finds the escape
# too easy to force or too rare to bother with.
# INTERVAL is sized against sight: a beast pack (1.3x) chased from the edge of
# ENCOUNTER_RADIUS gains ~60 units a try, so all MAX_TRIES land inside the
# day's VISION_RADIUS (260); a dragon (1.5x) gets one or two.
const INTERVAL := 5.0      # world-minutes between tries: ~5 s of real chase at 1x
const MAX_TRIES := 3
const SKILLS := ["athletics", "survival"]   # outrun them, or read where they went
const BASE_DC := 12        # a band exactly as fast as the party
const DC_PER_SPEED := 10.0 # +1 DC per 10% of speed the band has over the party

# True when following alone will not close the gap.
static func outpaced(band_speed: float, party_speed: float) -> bool:
	return party_speed <= 0.0 or band_speed >= party_speed

static func dc(band_speed: float, party_speed: float) -> int:
	if party_speed <= 0.0:
		return BASE_DC
	return BASE_DC + maxi(0, roundi((band_speed / party_speed - 1.0) * DC_PER_SPEED))

# {} only when the party has nobody at all to roll with. Otherwise the full
# roll, "ok" true or false, in the shape every other overworld check has.
static func check(party, band_speed: float, party_speed: float, rng = null) -> Dictionary:
	var c = Campaign.new(party)
	var best_id := ""
	var best_skill := ""
	var best_bonus := -99
	for skill in SKILLS:
		var id: String = c.best_at(skill)
		if id == "":
			continue
		var b: int = c.skill_bonus(id, skill)
		if b > best_bonus:
			best_bonus = b
			best_id = id
			best_skill = skill
	if best_id == "":
		return {}
	if rng == null:
		rng = RNG.new()
	var nat: int = int(Dice.d20(rng)["nat"])
	var target := dc(band_speed, party_speed)
	var ch = party.get_member(best_id)
	return {
		"ok": nat + best_bonus >= target, "char_id": best_id, "cname": ch.cname if ch != null else "Someone",
		"skill": best_skill, "nat": nat, "bonus": best_bonus, "dc": target,
	}

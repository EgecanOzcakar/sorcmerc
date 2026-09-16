# T9x: foraging — an ambient reward for time spent traveling, not something
# the player triggers. world.gd rolls this once every INTERVAL world-minutes
# spent out on the map (not mid-fight, not visiting, not paused); a hit pays
# a small amount of gold, framed as living off the land along the way.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Ach = preload("res://core/achievements.gd")

const INTERVAL := 240.0     # one attempt per 4 world-hours of travel
const SKILLS := ["survival", "nature"]
const DC := 12
const GOLD_MIN := 5
const GOLD_MAX := 25

# {} only when the party has nobody at all to roll with (empty roster) —
# otherwise always a full roll breakdown, "ok" true or false, same "name the
# check and the roll" shape as every other overworld check.
static func check(party, rng = null) -> Dictionary:
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
	var ok: bool = nat + best_bonus >= DC
	var gold := 0
	if ok:
		gold = GOLD_MIN + rng.roll_die(GOLD_MAX - GOLD_MIN + 1) - 1
		Ach.bump("forages")
	var ch = party.get_member(best_id)
	return {
		"ok": ok, "char_id": best_id, "cname": ch.cname if ch != null else "Someone",
		"skill": best_skill, "nat": nat, "bonus": best_bonus, "dc": DC, "gold": gold,
	}

# T91 — monster lairs: hidden hostile camps found with a Survival check and
# attacked to loot. Pure data + math, no scene: scenes/world/world.gd draws
# the marker and offers the button once a lair is in range, this decides the
# roll and the reward.
#
#   WorldLairs.nearby_undiscovered(world, party.position, radius)  # -> Lair or null
#   WorldLairs.search(lair, party)          # one Survival roll, may set discovered
#   WorldLairs.loot(lair)                   # marks looted, returns the stash
#
# The attack itself isn't here: it's the same _launch_combat(World.RoamingParty)
# path a hostile settlement's guard fight already uses (scenes/world/world.gd),
# with the lair's own position/faction standing in — there's no separate combat
# code to write. loot() only supplies the lair's own stash on top of whatever
# the fight itself banks (XP/gold/kills), same relationship a dungeon's treasure
# room has to the monsters guarding it.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")

const DISCOVER_SKILL := "survival"
const DISCOVER_DC := 13
# Wider than Settlement's VISIT_RADIUS (34): a lair is hidden, not a landmark
# you walk up to see — reading the ground for it works from further off.
const DISCOVER_RADIUS := 60.0

# A stash roughly on par with a settlement's own market goods, scaled a little
# by how dangerous the faction reads on Scaler.FACTIONS (index as a stand-in
# for "further down the list, further into the wild, worth more").
const LOOT_BASE := 40
const LOOT_PER_FACTION_INDEX := 6

static func nearby_undiscovered(world, from: Vector2, radius: float = DISCOVER_RADIUS):
	var best = null
	var best_d := INF
	for l in world.lairs:
		if l.discovered:
			continue
		var d: float = from.distance_to(l.position)
		if d <= radius and d < best_d:
			best_d = d
			best = l
	return best

# One roll, pass or fail — no retry spam; the caller (world.gd) offers the
# button again next frame if it's still in range and still undiscovered, so a
# failed check just means "try again," same texture as T30's opportunity check.
static func search(lair, party, rng = null) -> Dictionary:
	var c = Campaign.new(party)
	var char_id := c.best_at(DISCOVER_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("lair|%s" % lair.id))))
	var bonus: int = c.skill_bonus(char_id, DISCOVER_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= DISCOVER_DC
	if ok:
		lair.discovered = true
	return {"ok": ok, "char_id": char_id, "cname": ch.cname, "nat": nat, "bonus": bonus, "dc": DISCOVER_DC}

# Called once, after the attacking fight is won. Second call on an already-
# looted lair returns an empty stash rather than paying out twice.
static func loot(lair) -> Dictionary:
	if lair.looted:
		return {"gold": 0}
	lair.looted = true
	var Scaler = load("res://core/scaler.gd")
	var idx: int = maxi(0, Scaler.FACTIONS.find(lair.faction))
	return {"gold": LOOT_BASE + idx * LOOT_PER_FACTION_INDEX}

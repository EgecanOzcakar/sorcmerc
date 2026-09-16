# T91 — monster lairs: hidden hostile camps found with a Survival check and
# attacked to loot. Pure data + math, no scene: scenes/world/world.gd draws
# the marker and offers the button once a lair is in range, this decides the
# roll and the reward.
#
#   WorldLairs.nearby_undiscovered(world, party.position, radius)  # -> Lair or null
#   WorldLairs.search(lair, party)          # one Survival roll, may set discovered
#   WorldLairs.loot(lair)                   # marks looted, returns the stash
#   WorldLairs.sneak_past(lair, party)      # T9x: Animal Handling — loot without a fight
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
static func loot(lair, now := -1.0) -> Dictionary:
	if lair.looted:
		return {"gold": 0}
	mark_cleared(lair, now)
	var Scaler = load("res://core/scaler.gd")
	var idx: int = maxi(0, Scaler.FACTIONS.find(lair.faction))
	return {"gold": LOOT_BASE + idx * LOOT_PER_FACTION_INDEX}

# --- D1: a disturbed lair does not wait for you -----------------------------
#
# Kicking the door starts a clock. Withdraw from a half-cleared warren and you
# have a day or two to come back and finish it; leave it longer and it resolves
# without you — either somebody else got there, or whatever lived in it packed
# up and moved on now that it is known.
#
# The point is that withdrawing costs something other than time. Without this,
# "back out and come back at full strength" is free and strictly correct, which
# makes the press-on-or-get-out decision D1 is built around a fake one. With it,
# retreating is a real trade: your party's hit points against the lair itself.
#
# It is deliberately NOT a punishment for losing. A wipe resets the lair and
# leaves it standing (core/site.gd's wipe_penalty) — you can always go back and
# try again. This only fires on a lair the party walked away from intact.
const WINDOW := 2880.0            # two in-game days; long enough to cross the map and heal, short enough to be a deadline
const OUTCOMES := ["cleared", "abandoned"]

static func window_left(lair, now: float) -> float:
	if lair.entered_at < 0.0 or lair.looted:
		return 0.0
	return maxf(0.0, WINDOW - (now - lair.entered_at))

# Stamps the clock the first time the party goes in. Idempotent: re-entering a
# lair you already disturbed does not buy you another two days.
static func mark_entered(lair, now: float) -> void:
	if lair.entered_at < 0.0:
		lair.entered_at = now

# Resolves every lair whose window has run out, and returns them so the caller
# can say so out loud — a landmark quietly going grey with no explanation reads
# as a bug. Called once a frame from the world screen; cheap, there are five.
static func expire(world, now: float) -> Array:
	var gone: Array = []
	for l in world.lairs:
		if l.looted or l.entered_at < 0.0:
			continue
		if now - l.entered_at < WINDOW:
			continue
		# Seeded off the lair, so the same warren always ends the same way —
		# reloading cannot reroll it into the outcome you preferred.
		l.resolved_as = OUTCOMES[absi(hash("resolve|%s" % l.id)) % OUTCOMES.size()]
		mark_cleared(l, now)
		gone.append(l)
	return gone

# --- a hole in the ground does not stay empty -------------------------------
#
# A spent lair used to sit grey on the map forever: cleared once, and that was
# the end of that landmark for the rest of the run. Five lairs, five clears,
# and the map had nothing left underground to do.
#
# So something moves back in. One in-game day after it was emptied — however it
# was emptied: fought to the bottom, talked past, or resolved without the party
# while the window ran out — the place is live again, with a fresh interior and
# guardians who have never met you. The party keeps knowing WHERE it is
# (`discovered` survives; finding a hole once is finding it), but everything
# about what is in it starts over: the rooms they cleared, the clock that was
# running on them, and whether the guardians are awake.
#
# RESPAWN is deliberately the shortest interval that still reads as "time
# passed" — a day is one long rest, so a party can clear a warren, sleep, and
# find it occupied again. Raise it if a lair should be scarcer than that.
const RESPAWN := 1440.0           # one in-game day, in world-minutes

# Every stamp of "this lair is spent" goes through here, so the respawn clock
# cannot be started in one place and forgotten in another.
static func mark_cleared(lair, now := -1.0) -> void:
	lair.looted = true
	lair.cleared_at = now

# Brings back every lair whose day is up, and returns them so the caller can say
# so — a grey landmark going red again with no explanation reads as a bug in the
# same way going grey did. Polled once a frame beside expire(); there are five.
static func respawn(world, now: float) -> Array:
	var back: Array = []
	for l in world.lairs:
		if not l.looted or l.cleared_at < 0.0:
			continue          # live already, or spent before this rule existed
		if now - l.cleared_at < RESPAWN:
			continue
		l.looted = false
		l.cleared_at = -1.0
		l.depth_cleared = 0       # a fresh interior, not the one they fought through
		l.entered_at = -1.0       # ...guarded by something that has not met them
		l.resolved_as = ""
		back.append(l)
	return back

# What moved in, in words. Separate from respawn() for the same reason
# resolution_text is separate from expire().
static func respawn_text(lair) -> String:
	return "Something has moved into %s again." % lair.sname

# What happened, in words. Separate from expire() so the world screen is not
# the only thing that can explain it.
static func resolution_text(lair) -> String:
	match lair.resolved_as:
		"cleared":
			return "%s has been cleared out — somebody else got there first." % lair.sname
		"abandoned":
			return "%s stands empty. Whatever was in it moved on once it was found." % lair.sname
	return ""

# --- T9x: a quieter approach ------------------------------------------------
const SNEAK_SKILL := "animalhandling"
const SNEAK_DC := 14

# An alternative to the straight fight, offered alongside "Attack" once a
# lair is discovered: calm whatever's guarding it instead of fighting
# through. A pass loots the lair clean, same payout as winning the fight,
# with no combat at all; a fail just means the guardians didn't buy it —
# the caller falls through to the normal attack. Exactly one attempt per lair,
# and alerted() below is what enforces it.
#
# Only on a lair nobody has been into yet. The guardians are awake the moment
# somebody comes through the door — the party kicked it in, or the quiet way was
# tried and failed and fell straight through to the attack (world.gd's
# _lair_sneak_action) — and they do not settle back down because the party
# withdrew and came back a day later. Without this you could fight half-way into
# a warren, walk out, and then talk your way past the very guardians you had
# been killing, for a second payout on top of the rooms you already looted.
#
# `entered_at` is the stamp already: mark_entered() sets it the first time the
# party goes in, it is what starts WINDOW, and core/world_save.gd round-trips it
# — so there is no second piece of state to keep in step, and an old save that
# was disturbed before this rule existed reads correctly too.
static func alerted(lair) -> bool:
	return lair.entered_at >= 0.0

# The quiet way is open at all only on a discovered, unspent, undisturbed lair.
# world.gd asks this to decide whether to show the button; sneak_past() asks it
# again so the rule holds whoever calls it.
static func can_sneak(lair) -> bool:
	return lair.discovered and not lair.looted and not alerted(lair)

static func sneak_past(lair, party, rng = null) -> Dictionary:
	if not can_sneak(lair):
		return {}
	var c = Campaign.new(party)
	var char_id := c.best_at(SNEAK_SKILL)
	var ch = party.get_member(char_id) if char_id != "" else null
	if ch == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("sneak|%s" % lair.id))))
	var bonus: int = c.skill_bonus(char_id, SNEAK_SKILL)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= SNEAK_DC
	var line := ("%s calms them down (Animal Handling %d+%d vs DC %d) — %s is looted clean, no fight needed."
		% [ch.cname, nat, bonus, SNEAK_DC, lair.sname]) if ok else (
		"%s can't settle them (Animal Handling %d+%d vs DC %d) — they attack."
		% [ch.cname, nat, bonus, SNEAK_DC])
	return {"ok": ok, "char_id": char_id, "cname": ch.cname, "nat": nat, "bonus": bonus,
		"dc": SNEAK_DC, "text": line}

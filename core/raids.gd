# Raids — a lair left alone does something about it.
#
# Every lair in the settled country runs a clock against the nearest town.
# When it runs out a band sets out (a RoamingParty like any other, so
# hostility, encounters, patrols and the hunt job all apply for free), walks
# to the town's edge, stands there for SIEGE so the player can meet it, and
# then the raid LANDS: the town's market halves (settlement_visit.gd reads
# `raided_by`), its board pays more for that lair's work (quest.gd), refugees
# walk the roads (travel.gd). The second landing seeds a child lair. Clearing
# the lair — however it is cleared — lifts all of it; this module polls for
# that rather than hooking mark_cleared, so every way of spending a lair is
# covered. Pure data + math, no scene: scenes/world/world.gd calls tick()
# once a frame and says the lines it returns.
#
#   Raids.tick(world, now)          # -> [String]; sets out, advances, lands, lifts
#   Raids.settle_cost(world, lair)  # -> gold, 0 when it cannot be settled
#   Raids.settle(world, lair, party, now)   # a cleared lair becomes a camp settlement
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ach = preload("res://core/achievements.gd")
const Campaign = preload("res://core/campaign.gd")
const Ladder = preload("res://core/ladder.gd")

# How far a lair's raiders will walk: quest_posting.gd's clear_lair reach — a
# lair a town would post work about is a lair that can reach it.
const RAID_REACH := 800.0
# The first raid is due this long after the clock starts (world start, or the
# respawn), every later one this long after the last; each lair adds under a
# day of its own jitter so five lairs are five mornings. A day is 1440.
const RAID_AFTER := 2880.0
const RAID_EVERY := 2880.0
const RAID_JITTER := 1440
# The stand at the gate. A band walks lair-to-town in twenty world-minutes;
# without this nobody would ever meet one. Eight hours is one long rest's
# worth of warning.
const SIEGE := 480.0
# Where it stands: this far out from the town on the lair's side — inside
# settlement_visit.gd's BATTLE_RADIUS (140), so a fight there is a fight at
# the town, and the hold-the-line objective applies.
const SIEGE_DIST := 100.0
# Only lairs on this ground raid. The frontier and the deeps are nobody's
# problem until you make them yours — and a deeps-level band at a heartland
# gate on day two is a raid nobody can turn.
const SETTLED_BANDS := ["heartland", "marches"]
# What the deed is worth to the town's faction: turning a raid before it
# lands is two bands put down (2 × FactionOpinion.FOUGHT_FOR); lifting one by
# clearing the lair is a job done (QUEST_DONE), posted or not.
const TURNED_FOR := 10.0
const LIFTED_FOR := 10.0
# Where a child lair goes: close enough to read as the same trouble, far enough
# to be its own dot; clear of every town by the procedural builder's own
# MIN_MONSTER_GAP (300, scenes/world/procedural_world.gd) and of every lair by
# SPREAD_MIN. SPREAD_TRIES seeded angles, then give up — no child is better
# than one in a lake or a front yard.
const SPREAD_MIN := 150.0
const SPREAD_MAX := 300.0
const SPREAD_TRIES := 24
const SPREAD_TOWN_GAP := 300.0

# Reclaiming. A cleared lair on settled ground can be bought into a camp
# settlement inside the respawn's own one-day window — the one deadline there
# already is. Priced as nights at a town inn (three and six): a real sink,
# once, for a permanent bed. SETTLE_XP is a landmark and a half — the biggest
# deed on the map that is not a fight — times (ring + 1) like every deed.
const RECLAIM_COST := {"heartland": 120, "marches": 240}
const SETTLE_XP := 60
const WAYSTATION_NAMES := ["Fairstead", "Newhold", "Hollowell", "Whitecross", "Longwater",
	"Kingsrest", "Ashford", "Stonebridge", "Greenhalt", "Oldwell"]

static func is_settled(world, lair) -> bool:
	return Regions.band_of(world, lair.position) in SETTLED_BANDS

# The nearest civilized settlement inside reach, or null.
static func target_for(world, lair):
	var best = null
	var best_d := INF
	for s in world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		var d: float = s.position.distance_to(lair.position)
		if d <= RAID_REACH and d < best_d:
			best_d = d
			best = s
	return best

# Seeded off the lair, so the same warren always sets out on the same morning.
static func due_at(lair) -> float:
	var gap: float = RAID_AFTER if lair.raids == 0 else RAID_EVERY
	return lair.raid_at + gap + float(absi(hash("raid|%s" % lair.id)) % RAID_JITTER)

static func lair_of(world, id: String):
	for l in world.lairs:
		if l.id == id:
			return l
	return null

static func settlement_of(world, id: String):
	for s in world.settlements:
		if s.id == id:
			return s
	return null

static func band_of(world, lair):
	if lair.raid_band == "":
		return null
	for p in world.parties:
		if p.id == lair.raid_band:
			return p
	return null

# The band itself: two troops at the region's floor level, the shape the
# procedural builder gives every band, pointed at the siege point.
static func set_out(world, lair, s, now: float):
	var b = world.add_party(World.RoamingParty.new("%s-raiders" % lair.id, lair.position, lair.faction))
	var lv: int = int(Regions.at(world, lair.position)["levels"][0])
	b.troops.append({"role": "heavy", "level": lv})
	b.troops.append({"role": "light", "level": lv})
	var dir: Vector2 = (lair.position - s.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	WorldAI.raid(b, s.position + dir * SIEGE_DIST, s.id, lair.id)
	lair.raid_band = b.id
	lair.raid_at = now
	return b

# A band that can still be turned: out, and not yet landed.
static func turnable(foe) -> bool:
	var st: Dictionary = foe.ai if "ai" in foe else {}
	return String(st.get("behavior", "")) == "raid" and String(st.get("phase", "")) in ["march", "siege"]

# The raid lands: the town names the lair, the market feels it (battle_at is
# what settlement_visit.gd's four-hour markup reads; raided_by is what keeps
# the shelf halved after that), and the second landing seeds a child.
static func land(world, lair, s, now: float) -> Array:
	s.raided_by = lair.id
	s.raided_at = now
	s.battle_at = now
	lair.raids += 1
	var lines: Array = ["%s is raided — the market is half what it was, and %s wants it answered."
		% [s.sname, lair.sname]]
	if lair.raids == 2 and lair.spawned_from == "":
		var child = spread(world, lair, now)
		if child != null:
			lines.append("Something has dug in near %s." % lair.sname)
	return lines

# The second landing's child: same faction, named after its parent, hidden,
# with a clock of its own that starts now. One per root, ever — a respawned
# parent counts its landings from zero again, and the id check is what keeps
# it from digging a second child on the same ground; a child that was settled
# (the "way-" camp standing where it was) counts as dug too. A child never
# spreads (land() checks spawned_from), so a map at most doubles its lairs
# and stops.
static func spread(world, parent, now: float):
	var id := "%s-2" % parent.id
	if lair_of(world, id) != null or settlement_of(world, "way-" + id) != null:
		return null
	var rng = RNG.new(maxi(1, absi(hash("spread|%s" % parent.id))))
	for i in SPREAD_TRIES:
		var angle := deg_to_rad(float(rng.roll_die(360)))
		var dist: float = SPREAD_MIN + float(rng.roll_die(int(SPREAD_MAX - SPREAD_MIN)))
		var pos: Vector2 = parent.position + Vector2(cos(angle), sin(angle)) * dist
		if world.is_water(pos) or not _room_for(world, pos):
			continue
		var child = world.add_lair(World.Lair.new(id, pos, parent.faction,
			("%s' outpost" if parent.sname.ends_with("s") else "%s's outpost") % parent.sname))
		child.spawned_from = parent.id
		child.raid_at = now
		return child
	return null

static func _room_for(world, pos: Vector2) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < SPREAD_TOWN_GAP:
			return false
	for l in world.lairs:
		if l.position.distance_to(pos) < SPREAD_MIN:
			return false
	return true

# Once a frame: lifts, then every band out, then any lair whose time has come.
# A looted lair is gated out of setting out regardless; the order that matters
# is erase-before-advance — a band whose lair was looted this frame is erased
# before its phase is advanced, so it never sieges or lands for a lair that is
# gone. A band gone from the map (beaten on the road by the party or a patrol)
# resets its lair's clock.
static func tick(world, now: float) -> Array:
	var lines: Array = []
	for s in world.settlements:
		if s.raided_by == "":
			continue
		var l = lair_of(world, s.raided_by)
		if l != null and not l.looted:
			continue
		s.raided_by = ""
		s.raided_at = -1.0
		FactionOpinion.raise(s.faction, LIFTED_FOR)
		Ladder.deed(s.faction, 2)   # ...and two deeds on the ladder
		Ach.bump("raids_lifted")
		lines.append("%s breathes again — %s is done raiding." % [s.sname, l.sname if l != null else "the lair"])
	for l in world.lairs:
		if l.raid_band == "":
			continue
		var b = band_of(world, l)
		if b != null and l.looted:
			world.parties.erase(b)   # its lair is gone; it has nowhere to go home to
			b = null
		if b == null:
			l.raid_band = ""
			l.raid_at = now
			continue
		_advance(world, l, b, now, lines)
	for l in world.lairs:
		if l.looted or l.entered_at >= 0.0 or l.raid_band != "" or now < due_at(l):
			continue
		if not is_settled(world, l):
			continue
		var s = target_for(world, l)
		if s == null:
			continue
		set_out(world, l, s, now)
		lines.append("Raiders are out from %s, making for %s." % [l.sname, s.sname])
	return lines

# march -> siege on arrival; siege -> home when the stand runs out (the raid
# lands wherever the band is standing — it may be chasing the player);
# home -> gone on arrival. Phase changes take effect on the NEXT frame's
# steer, which is why arrival is only read at the start of a phase.
static func _advance(world, lair, b, now: float, lines: Array) -> void:
	var st: Dictionary = b.ai
	if String(st.get("behavior", "")) != "raid":
		return
	match String(st.get("phase", "")):
		"march":
			# ponytail: a band whose siege point _steer can never reach (walled
			# in, an island town) never arrives, and that lair's clock and label
			# freeze on "raiding"; a march timeout is the upgrade if it ever shows.
			if WorldAI.arrived(b):
				st["phase"] = "siege"
				st["until"] = now + SIEGE
				var s = settlement_of(world, String(st["target"]))
				lines.append("Raiders from %s are camped outside %s." % [lair.sname, s.sname if s != null else "the town"])
		"siege":
			if now >= float(st.get("until", now)):
				var s = settlement_of(world, String(st["target"]))
				if s != null:
					lines.append_array(land(world, lair, s, now))
				st["phase"] = "home"
				st["to"] = lair.position
		"home":
			if WorldAI.arrived(b):
				world.parties.erase(b)
				lair.raid_band = ""

# What the map label says after the settlement's name: the standing raid, or
# the hours left on a siege, or nothing.
static func settlement_tag(world, s, now: float) -> String:
	if s.raided_by != "":
		return " — raided"
	for l in world.lairs:
		var b = band_of(world, l)
		if b == null or String(b.ai.get("target", "")) != s.id or String(b.ai.get("phase", "")) != "siege":
			continue
		return " — raiders at the gate, %d h" % int(ceil((float(b.ai["until"]) - now) / 60.0))
	return ""

static func lair_tag(lair) -> String:
	return " — raiding" if lair.raid_band != "" else ""

# --- reclaiming --------------------------------------------------------------

# The nearest civilized settlement to a point, any distance — where the
# settlers come from, and whose faction the camp flies. null on a map with none.
static func settlers_from(world, pos: Vector2):
	var best = null
	var best_d := INF
	for s in world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		var d: float = s.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best

# Gold to settle this lair, or 0 when it cannot be: live, spent before the
# respawn rule (no window), on frontier or deeps ground, or nobody to send.
static func settle_cost(world, lair) -> int:
	if not lair.looted or lair.cleared_at < 0.0 or not world.lairs.has(lair):
		return 0
	var band := Regions.band_of(world, lair.position)
	if not RECLAIM_COST.has(band) or settlers_from(world, lair.position) == null:
		return 0
	return int(RECLAIM_COST[band])

# Seeded off the lair, stepping past any name already on the map.
static func waystation_name(world, lair) -> String:
	var n := WAYSTATION_NAMES.size()
	var start: int = absi(hash("way|%s" % lair.id)) % n
	for i in n:
		var name: String = WAYSTATION_NAMES[(start + i) % n]
		var taken := false
		for s in world.settlements:
			if s.sname == name:
				taken = true
				break
		if not taken:
			return name
	return "%s Halt" % lair.sname.trim_prefix("the ")

# The purchase: the lair is gone for good (not a hole any more — no respawn),
# a camp of the settlers' faction stands where it was with a fresh market, and
# the deed pays. null when it cannot be settled or the purse is short.
static func settle(world, lair, party, now: float):
	var cost := settle_cost(world, lair)
	if cost <= 0 or not party.spend_gold(cost):
		return null
	var home = settlers_from(world, lair.position)
	var ring: int = int(Regions.at(world, lair.position)["index"])
	# A band still out for this lair has nowhere to go home to — tick()'s
	# lift would erase it next poll, but the lair is leaving the map now.
	var b = band_of(world, lair)
	if b != null:
		world.parties.erase(b)
	world.lairs.erase(lair)
	var s = world.add_settlement(World.Settlement.new("way-" + lair.id, lair.position, home.faction, "camp",
		waystation_name(world, lair)))
	s.last_visited = now
	Campaign.new(party)._split_xp(SETTLE_XP * (ring + 1))
	FactionOpinion.raise(home.faction, LIFTED_FOR)
	Ladder.deed(home.faction, 3)   # ...and three deeds on the ladder — the biggest going
	Ach.collect("waystations", s.id)
	return s

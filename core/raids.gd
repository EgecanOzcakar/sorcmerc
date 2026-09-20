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

# Task 3 fills this in: the second landing's child lair.
static func spread(_world, _parent, _now: float):
	return null

# Once a frame. Order matters: lifts first, so a lair cleared this frame does
# not also set out; then every band out is advanced or, if it is gone from the
# map (beaten on the road by the party or a patrol), the clock resets; then
# any lair whose time has come sets out.
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

# Landmarks — places on the map that are not a fight.
#
# Ruins, a shrine, standing stones, a hermit's hut, a wreck, a watchtower: each
# a place the party walks up to and answers with a skill the world barely uses
# elsewhere. Two choices a kind, one visit, rewards that are not fights.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#
# What this owns: the kinds, the names, the cards (the choices and their
# checks), placement, discovery, and the reward doors. What it does not: the
# model (core/world.gd's Landmark), the drawing (scenes/world/), the save.
#
# world.gd load()s this file for a name at call time (never preloads it), so
# this side may preload world.gd for the Landmark class.
extends RefCounted

const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")
const Approach = preload("res://core/approach.gd")
const Travel = preload("res://core/travel.gd")
const Regions = preload("res://core/regions.gd")
const Dice = preload("res://core/dice.gd")
const Loot = preload("res://core/loot.gd")
const Campaign = preload("res://core/campaign.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ach = preload("res://core/achievements.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Sound = preload("res://core/audio.gd")
const Ladder = preload("res://core/ladder.gd")

const KINDS := ["ruins", "shrine", "stones", "hut", "wreck", "tower"]
const HIDDEN := ["hut", "tower"]   # found the way lairs are; the rest are hard to miss

const NAMES := {
	"ruins": ["the Broken Chapel", "the Old Mill", "Kessel's Folly", "the Fallen Keep", "the Weir House"],
	"shrine": ["the Wayside Shrine", "the Three Saints", "the Drowned Shrine", "Mother Ash's Altar", "the Lantern Stone"],
	"stones": ["the Nine Sisters", "the Giant's Ring", "the Sleeping Stones", "the Moot Ring", "Harrow Stones"],
	"hut": ["Old Marrow's hut", "the Charcoal Hermit's hut", "Wren Hollow", "the Bee-keeper's hut", "Gallow's Hut"],
	"wreck": ["the Broken Wagon", "a wrecked barge", "the Salt Cart", "a tinker's overturned van", "the Lost Wain"],
	"tower": ["the Old Watch", "Beacon Tower", "the Broken Spire", "the Marcher's Tower", "Crow Tower"],
}

static func is_hidden(kind: String) -> bool:
	return HIDDEN.has(kind)

# Stable per id, so a reload names the same stones the same way.
static func name_for(id: String, kind: String) -> String:
	var pool: Array = NAMES.get(kind, ["a landmark"])
	return String(pool[absi(hash("landmark|%s" % id)) % pool.size()])

# --- placement ------------------------------------------------------------

const LANDMARKS_PER_LAIR := 1.5   # the small map's six lairs get nine, the large's ~eighteen
const LANDMARK_GAP := 120.0       # from any settlement, lair or landmark — a thing of its own
const PLACE_TRIES := 200

# The built-in builders call this last: kinds round-robin off the seed, spread
# over the map the settlements span, on dry ground, the gap kept. A pack
# places its own by hand and never comes through here.
static func place(world, seed: int) -> void:
	var rng = RNG.new(maxi(1, seed))
	var count: int = ceili(LANDMARKS_PER_LAIR * world.lairs.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in world.settlements:
		lo = Vector2(minf(lo.x, s.position.x), minf(lo.y, s.position.y))
		hi = Vector2(maxf(hi.x, s.position.x), maxf(hi.y, s.position.y))
	for l in world.lairs:
		lo = Vector2(minf(lo.x, l.position.x), minf(lo.y, l.position.y))
		hi = Vector2(maxf(hi.x, l.position.x), maxf(hi.y, l.position.y))
	lo -= Vector2(LANDMARK_GAP, LANDMARK_GAP)
	hi += Vector2(LANDMARK_GAP, LANDMARK_GAP)
	var start: int = rng.roll_die(KINDS.size()) - 1
	for i in count:
		var kind: String = KINDS[(start + i) % KINDS.size()]
		for _t in PLACE_TRIES:
			var pos := Vector2(lo.x + (hi.x - lo.x) * float(rng.roll_die(1000) - 1) / 999.0,
				lo.y + (hi.y - lo.y) * float(rng.roll_die(1000) - 1) / 999.0)
			if world.is_water(pos) or not _clear(world, pos):
				continue
			_dedupe_name(world, world.add_landmark(World.Landmark.new("landmark-%s-%d" % [kind, i], kind, pos)))
			break

# name_for() hashes the id, and a kind's pool is only a handful of names —
# round-robin placement puts more than one of a kind on the map often enough
# that two share a name by chance. If this one already collides with an
# earlier landmark of the same kind, hand it the next name in the pool.
static func _dedupe_name(world, l) -> void:
	var pool: Array = NAMES.get(l.kind, ["a landmark"])
	var idx: int = maxi(0, pool.find(l.sname))
	for _t in pool.size():
		if not world.landmarks.any(func(m): return m != l and m.kind == l.kind and m.sname == l.sname):
			return
		idx = (idx + 1) % pool.size()
		l.sname = String(pool[idx])

static func _clear(world, pos: Vector2) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for l in world.lairs:
		if l.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for m in world.landmarks:
		if m.position.distance_to(pos) < LANDMARK_GAP:
			return false
	return true

# --- the cards --------------------------------------------------------------
#
# Two choices a kind, in Approach.WAYS' shape so the approach card draws them
# and Approach._roller/needs price them. `reward` names the door resolve()
# opens on a win; `snare` is what a loss costs (nothing, an hour, or the toll).
#
# A third row, gated by who you are: a class, a background, a species. The
# roller for the two choices above stays the party's best at the skill,
# automatically (Approach._roller) — composition never touches who rolls.
# It shows up here instead, as flavour: an acolyte answers the shrine, a sage
# reads the ruins, in their own name, with no roll. It is not a third power —
# it opens a door one of the two rolled rows already opens.

const LEAVE := "leave"
const CACHE_GOLD := 60
const LANDMARK_XP := 40
const SNARE_PCT := 0.15
const OFFERING_GOLD := 25
const HOUR := 60.0

const CARDS := {
	"ruins": [
		{"id": "read", "label": "Read the stones", "skills": ["history", "investigation"], "dc": 13,
			"note": "Somebody wrote what happened here.",
			"win": "A lead — the nearest thing nobody has found yet is marked.", "lose": "An hour, and no wiser.",
			"reward": "lead", "snare": "hour"},
		{"id": "dig", "label": "Dig in the rubble", "skills": ["athletics", "investigation"], "dc": 14,
			"note": "Whatever fell in here is still in here.",
			"win": "A cache.", "lose": "A snare in the rubble — somebody bleeds for it.",
			"reward": "cache", "snare": "toll"},
		{"id": "script", "label": "Read the old script", "skills": [], "dc": 0,
			"gate": {"backgrounds": ["sage", "scribe"], "classes": ["wizard"]},
			"note": "%s reads it the way it was written.",
			"win": "A lead — the nearest thing nobody has found yet is marked.", "lose": "",
			"reward": "lead", "snare": "none"},
	],
	"shrine": [
		{"id": "kneel", "label": "Kneel", "skills": ["religion"], "dc": 12,
			"note": "Whoever kept this place, they kept it for travellers.",
			"win": "A blessing: every hero fights the next fight with something extra.", "lose": "Nothing answers.",
			"reward": "blessing", "snare": "none"},
		{"id": "offering", "label": "Leave an offering", "skills": [], "dc": 0,
			"note": "%d ◉ on the stone. No roll.",
			"win": "The blessing for %d ◉, and the people who keep this shrine hear of it.", "lose": "",
			"reward": "offering", "snare": "none"},
		{"id": "rite", "label": "Say the rite", "skills": [], "dc": 0,
			"gate": {"backgrounds": ["acolyte"], "classes": ["cleric", "paladin"]},
			"note": "%s knows the words.",
			"win": "A blessing: every hero fights the next fight with something extra.", "lose": "",
			"reward": "blessing", "snare": "none"},
	],
	"stones": [
		{"id": "marks", "label": "Read the marks", "skills": ["arcana"], "dc": 14,
			"note": "The ring is older than the road.",
			"win": "The next fight starts scouted.", "lose": "A headache, and nothing else.",
			"reward": "scouted", "snare": "none"},
		{"id": "sleep", "label": "Sleep in the ring", "skills": ["nature"], "dc": 13,
			"note": "The ground here is kinder than it looks.",
			"win": "The road is quicker for a day.", "lose": "An hour, and a stiff neck.",
			"reward": "road", "snare": "hour"},
		{"id": "remember", "label": "Remember what they are", "skills": [], "dc": 0,
			"gate": {"classes": ["druid", "wizard"], "species": ["elf"]},
			"note": "%s has stood in a ring like this before.",
			"win": "The next fight starts scouted.", "lose": "",
			"reward": "scouted", "snare": "none"},
	],
	"hut": [
		{"id": "knock", "label": "Knock", "skills": ["persuasion", "performance"], "dc": 13,
			"note": "Somebody lives out here on purpose.",
			"win": "A lead for nothing, and the hermit knows what one of your things is.", "lose": "The door stays shut.",
			"reward": "hermit", "snare": "hour"},
		{"id": "road", "label": "Ask about the road", "skills": ["insight"], "dc": 12,
			"note": "They know which hollows are safe.",
			"win": "A dry hollow to camp in tonight: no camp kit needed.", "lose": "Nothing they will say.",
			"reward": "safe_camp", "snare": "none"},
		{"id": "kin", "label": "Talk as one who knows the wild", "skills": [], "dc": 0,
			"gate": {"backgrounds": ["hermit", "guide"], "classes": ["ranger"]},
			"note": "%s and the hermit have the same mud on their boots.",
			"win": "A lead for nothing, and the hermit knows what one of your things is.", "lose": "",
			"reward": "hermit", "snare": "none"},
	],
	"wreck": [
		{"id": "search", "label": "Search it", "skills": ["investigation"], "dc": 14,
			"note": "Whoever lost it did not come back for it.",
			"win": "A cache.", "lose": "A snare under the boards — somebody bleeds for it.",
			"reward": "cache", "snare": "toll"},
		{"id": "salvage", "label": "Salvage", "skills": ["athletics"], "dc": 13,
			"note": "Canvas, rope, an axle.",
			"win": "A camp kit.", "lose": "An hour, and nothing worth the carrying.",
			"reward": "camp_kit", "snare": "hour"},
		{"id": "appraise", "label": "Know what is worth taking", "skills": [], "dc": 0,
			"gate": {"backgrounds": ["merchant", "sailor", "artisan"]},
			"note": "%s has loaded a wagon or two.",
			"win": "A cache.", "lose": "",
			"reward": "cache", "snare": "none"},
	],
	"tower": [
		{"id": "climb", "label": "Climb", "skills": ["athletics"], "dc": 12,
			"note": "The stair is half there.",
			"win": "The country opens up for miles.", "lose": "An hour on a stair that goes nowhere.",
			"reward": "reveal", "snare": "hour"},
		{"id": "watch", "label": "Keep watch", "skills": ["perception"], "dc": 13,
			"note": "An hour at the top, looking.",
			"win": "Every band for two days' walk is marked until tomorrow.", "lose": "Nothing moves.",
			"reward": "marked", "snare": "none"},
		{"id": "sightline", "label": "Read the ground like a soldier", "skills": [], "dc": 0,
			"gate": {"backgrounds": ["soldier", "guard"], "classes": ["fighter"]},
			"note": "%s knows what a watch is for.",
			"win": "Every band for two days' walk is marked until tomorrow.", "lose": "",
			"reward": "marked", "snare": "none"},
	],
}

static func ring(world, pos: Vector2) -> int:
	return int(Regions.at(world, pos)["index"])

static func dc_for(choice: Dictionary, world, pos: Vector2) -> int:
	return int(choice["dc"]) + ring(world, pos)

# The first party member the gate admits (party order), or null. A gate is
# {classes, backgrounds, species}; any match on any list admits.
static func gate_match(party, gate: Dictionary):
	for ch in party.party_characters():
		if gate.get("backgrounds", []).has(ch.background_id) or gate.get("species", []).has(ch.species_id):
			return ch
		for lv in ch.levels:
			if gate.get("classes", []).has(String(lv.get("class_id", ""))):
				return ch
	return null

# The rows the approach card draws. A skill nobody can roll is not offered
# (Approach's rule); an offering the purse cannot cover is not offered.
# A spent landmark offers nothing at all.
static func options(l, party, world) -> Array:
	if l.spent:
		return []
	var out: Array = []
	for c in CARDS[l.kind]:
		# A no-skill row never rolls, so it must never price one either — the
		# gate and offering rows both have empty skills, dc stays 0 for both.
		var o: Dictionary = {"id": c["id"], "label": c["label"], "note": c["note"],
			"dc": dc_for(c, world, l.position) if not c["skills"].is_empty() else 0, "win": c["win"]}
		if String(c["lose"]) != "":
			o["lose"] = c["lose"]
		if c.has("gate"):
			var who = gate_match(party, c["gate"])
			if who == null:
				continue
			o["note"] = String(c["note"]) % who.cname
			o.merge({"char_id": who.id, "cname": who.cname, "gated": true}, true)
			out.append(o)
			continue
		if c["skills"].is_empty():
			var price: int = OFFERING_GOLD * (ring(world, l.position) + 1)
			if party.gold < price:
				continue
			o["note"] = String(c["note"]) % price
			o["win"] = String(c["win"]) % price
			o["toll"] = price
		else:
			var who: Dictionary = Approach._roller(party, c)
			if who.is_empty():
				continue
			var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
			o.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
				"bonus": bonus, "named": bool(who["named"]), "needs": Approach.needs(o["dc"], bonus)}, true)
		out.append(o)
	out.append({"id": LEAVE, "label": "Leave it", "note": "Nothing spent, nothing gained.", "dc": 0, "win": "The road goes on."})
	return out

# One answer: roll the check, open the door, spend the place, pay the deed.
# Returns the event card's dict (core/travel.gd's shape) — the check named,
# the roll named, the reward said — or {} for leave.
static func resolve(l, choice_id: String, party, world, rng) -> Dictionary:
	if choice_id == LEAVE or l.spent:
		return {}
	var c: Dictionary = {}
	for cand in CARDS[l.kind]:
		if String(cand["id"]) == choice_id:
			c = cand
	if c.is_empty():
		return {}
	var e: Dictionary = {"id": "landmark-%s-%s" % [l.kind, choice_id], "title": l.sname, "ok": true}
	var price := 0   # >0 only for the offering: the one win text with a price in it
	if c.has("gate"):
		var who = gate_match(party, c["gate"])
		if who == null:
			return {}
		e.merge({"char_id": who.id, "cname": who.cname}, true)
	elif not c["skills"].is_empty():
		var who: Dictionary = Approach._roller(party, c)
		if who.is_empty():
			return {}
		var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
		var nat: int = int(Dice.d20(rng)["nat"])
		var dc: int = dc_for(c, world, l.position)
		e.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
			"nat": nat, "bonus": bonus, "dc": dc, "ok": nat + bonus >= dc, "named": bool(who["named"])}, true)
	else:
		price = OFFERING_GOLD * (ring(world, l.position) + 1)
		if not party.spend_gold(price):
			return {}
		e["gold"] = -price
	l.spent = true
	if e["ok"]:
		e["kind"] = "good"
		e["text"] = String(c["win"]) % price if price > 0 else String(c["win"])
		_open(String(c["reward"]), l, party, world, rng, e)
		var xp: int = LANDMARK_XP * (ring(world, l.position) + 1)
		Campaign.new(party)._split_xp(xp)
		e["xp"] = xp
		Ach.collect("landmarks", l.id)
		Ach.collect("landmark_kinds", l.kind)
	else:
		e["kind"] = "bad"
		e["text"] = String(c["lose"])
		# Heard as the search that found nothing, unless the snare drew blood.
		Sound.play_sfx("hit_pierce" if String(c["snare"]) == "toll" else "search_nothing")
		match String(c["snare"]):
			"hour":
				world.clock.elapsed += HOUR
				e["minutes"] = HOUR
			"toll":
				e["hurt"] = toll(party.get_member(String(e["char_id"])), SNARE_PCT)
	return e

# The road's rule, for one person: a share of what they have, never below 1.
static func toll(ch, pct: float) -> int:
	if ch == null:
		return 0
	var s = ch.sheet()
	var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
	var after: int = maxi(1, cur - maxi(1, int(floor(cur * pct))))
	ch.hp_current = after
	ch.dirty()
	return cur - after

# --- the doors --------------------------------------------------------------

# What each door sounds like. The tower's two doors open the map, and the
# phrase over them is the road's rather than the discovery's; the doors that
# already had a sound elsewhere in the game (a camp kit is a pickup, a night
# in the ring is a rest, a fight scouted is a thing identified) reuse it.
const DOOR_SFX := {"cache": "cache_open", "blessing": "blessing", "offering": "offering",
	"scouted": "identify", "road": "rest", "safe_camp": "rest", "camp_kit": "pickup",
	"lead": "lead_marked", "hermit": "lead_marked", "reveal": "map_reveal", "marked": "map_reveal"}

static func _open(reward: String, l, party, world, rng, e: Dictionary) -> void:
	Sound.play_sfx(String(DOOR_SFX[reward]))
	Sound.play_sting("music_road" if reward in ["reveal", "marked"] else "music_discovery")
	match reward:
		"cache":
			var gold: int = CACHE_GOLD * (ring(world, l.position) + 1)
			gold = gold * (75 + rng.roll_die(51) - 1) / 100   # ±25 %
			party.add_gold(gold)
			e["gold"] = gold
			if rng.roll_die(3) == 1:
				var pool: Array = Loot.items_of_rarity("common")
				if not pool.is_empty():
					var item: String = String(pool[rng.roll_die(pool.size()) - 1])
					party.stash_add(item)
					e["item_name"] = Campaign.item_name(item)
		"blessing":
			party.blessed = true
		"offering":
			party.blessed = true
			var near = _nearest_settlement(world, l.position)
			if near != null:
				FactionOpinion.raise(near.faction, 2.0)
				Ladder.deed(near.faction)   # ...and a deed on the ladder
				e["thanks"] = near.sname
		"scouted":
			party.scouted_next = true
		"road":
			world.clock.elapsed = maxf(0.0, world.clock.elapsed - Travel.TIME_SAVED)   # floors at zero, like Travel's own refund
			e["minutes"] = -Travel.TIME_SAVED
		"safe_camp":
			party.safe_camp = true
		"camp_kit":
			party.stash_add("camp-kit")
			e["item_name"] = Campaign.item_name("camp-kit")
		"lead":
			_lead(world, l.position, e)
		"hermit":
			_lead(world, l.position, e)
			var unknown: Array = party.unidentified()
			if not unknown.is_empty():
				var item: String = String(unknown[0]["item_id"])
				party.stash_identify(item)
				Campaign._note_identified(item)
				e["item_name"] = Campaign.item_name(item)
		"reveal":
			world.reveal(l.position)
			for i in 8:
				var a := TAU * float(i) / 8.0
				world.reveal(l.position + Vector2(cos(a), sin(a)) * World.VISION_RADIUS)
		"marked":
			world.marked_until = world.clock.elapsed + FactionOpinion.DAY
			world.marked_at = l.position

# The nearest unfound lair or hidden landmark gets marked, and the card says which.
static func _lead(world, from: Vector2, e: Dictionary) -> void:
	var best = null
	var best_d := INF
	for x in world.lairs:
		var d: float = from.distance_to(x.position)
		if not x.discovered and not x.looted and d < best_d:
			best = x
			best_d = d
	for x in world.landmarks:
		var d: float = from.distance_to(x.position)
		if not x.found and is_hidden(x.kind) and d < best_d:
			best = x
			best_d = d
	if best == null:
		e["text"] = String(e["text"]) + " Nothing left to find."
		return
	if "discovered" in best:
		best.discovered = true
	else:
		best.found = true
	e["lair"] = best.sname

static func _nearest_settlement(world, from: Vector2):
	var best = null
	var best_d := INF
	for s in world.settlements:
		var d: float = from.distance_to(s.position)
		if d < best_d:
			best = s
			best_d = d
	return best

# --- discovery ----------------------------------------------------------------

# Visible kinds are found by walking: the first frame the fog is off them.
# Returns the ones that just turned, so the screen can say so.
static func found_on_explore(world) -> Array:
	var out: Array = []
	for l in world.landmarks:
		if l.found or is_hidden(l.kind):
			continue
		if world.is_explored(l.position):
			l.found = true
			out.append(l)
	return out

# A hidden landmark in search range — the same radius a lair hides at.
static func nearby_hidden(world, from: Vector2):
	for l in world.landmarks:
		if not l.found and is_hidden(l.kind) and from.distance_to(l.position) <= WorldLairs.DISCOVER_RADIUS:
			return l
	return null

# A found, unspent landmark near enough to walk up to.
static func nearest_open(world, from: Vector2):
	var best = null
	var best_d := INF
	for l in world.landmarks:
		var d: float = from.distance_to(l.position)
		if l.found and not l.spent and d <= WorldLairs.DISCOVER_RADIUS and d < best_d:
			best = l
			best_d = d
	return best

# The lair's Survival check, verbatim (core/world_lairs.gd search()), so there
# is one way to search the ground. A pass marks the place found.
static func search(l, party, rng = null) -> Dictionary:
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("landmark|%s" % l.id))))   # seeded off the landmark, same as a lair's own search
	var r: Dictionary = WorldLairs.search_roll(party, rng)
	if not r.is_empty() and r["ok"]:
		l.found = true
	return r

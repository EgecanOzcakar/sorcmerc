# D1 — a site: what a lair becomes once it has an interior.
#
# A lair used to be one fight and a flat gold number (core/world_lairs.gd's
# loot()). A site is several linked encounters run on ONE set of resources —
# there is no long rest in here — which is the whole point: 5e's classes are
# balanced around an adventuring day, and an open world of isolated one-off
# fights never asks for one. See docs/expansion-plan.md, the 2026-09-13 scope
# revision, for why this exists.
#
#   var s = Site.for_lair(lair, party, world)
#   s.options()            # the ways on from here — 1-3 rooms, at least one a fight
#   s.enter(i)             # -> the room dict; state becomes "combat" or "visiting"
#   s.combat_spec()        # combat rooms: what scenes/main.tscn wants, unchanged
#   s.finish_combat(result)
#   s.take()               # treasure room: pocket it
#   s.short_rest()         # rest room: the only rest there is in here
#   s.leave()              # done with this room -> deeper, or the site is over
#   s.withdraw()           # walk out part-cleared, keeping everything banked
#
# What this does NOT own, deliberately:
#  - the fight itself. combat_spec() feeds the same unchanged scenes/main.tscn
#    hand-off the open world and the linear campaign both already use.
#  - what a defeat costs. A wipe sets state to "wiped" and stops; the world
#    screen's own _retreat() decides the consequences, because a site sits
#    inside a persistent world rather than ending a run.
#  - saving. Progress lives on the Lair (depth_cleared), which core/world_save.gd
#    already round-trips — this object is rebuilt on entry, never serialized.
#
# Why this is not core/campaign.gd with a flag: that file is a *run*. Its
# terminal states end the game, _conclude() revives the dead for free, and
# _autosave() writes the CampaignSave slot — all correct for a roguelite route
# and all wrong for one dungeon inside a living world. What is worth reusing is
# its node vocabulary (a room is the same {id, kind, title, desc, difficulty,
# theme} dict), its pick-one-of-several shape, and its measured BOSS_POOL; those
# are reused here directly. The 1140-assertion route engine stays untouched and
# still runs behind SORCMERC_LINEAR_CAMPAIGN=1.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Scaler = preload("res://core/scaler.gd")
const Regions = preload("res://core/regions.gd")
const Visit = preload("res://core/settlement_visit.gd")
const RNG = preload("res://core/rng.gd")

# How deep a site runs. Three rooms is the shallowest thing that can still be
# called an adventuring day (two fights and a boss on one set of slots); six is
# as far as a party can be asked to go without a long rest before it stops being
# a choice and starts being a wall.
const MIN_DEPTH := 3
const MAX_DEPTH := 6
# Faction index stands in for "how far into the wild this is", the same proxy
# core/world_lairs.gd's LOOT_PER_FACTION_INDEX already uses — a goblin warren
# (index 0) is three rooms, a dragon's cave (last) is six.
const DEPTH_PER_FACTION_STEP := 4

const PICK_MIN := 2      # every depth offers a real choice, never a corridor
const PICK_MAX := 3

# How often a depth offers something other than a fight. Kept low on purpose:
# a rest room every floor would hand back exactly the attrition this whole
# feature exists to create.
const SUPPORT_CHANCE := 0.45
const REST_SHARE := 0.4       # of those, how many are a rest rather than a cache

# Room gold. A site pays better than world_lairs.gd's flat sneak-past stash
# (LOOT_BASE 40) because you fought the whole way down for it.
const TREASURE_GOLD := 55
const TREASURE_PER_DEPTH := 15
const BOSS_CACHE := 180
const BOSS_CACHE_PER_DEPTH := 30

# Interior flavour. Deliberately faction-agnostic: a collapsed gallery reads the
# same whether goblins or the dead are holding it, and one pool that works
# everywhere beats five thin ones. Faction colours the *roster*, which is the
# part the player actually fights.
# ponytail: this is the content seam. Per-faction room pools, and rooms that
# remember what happened in them, are authoring work — the shape is here.
const COMBAT_ROOMS := [
	{"id": "gallery", "title": "The collapsed gallery", "difficulty": "normal",
		"desc": "Something has been using the rubble for cover, and it is not rubble-coloured."},
	{"id": "cistern", "title": "The cistern", "difficulty": "normal",
		"desc": "The water is waist-deep and it is not still."},
	{"id": "midden", "title": "Bone midden", "difficulty": "easy",
		"desc": "They eat here. Not all of it was animal."},
	{"id": "guard-post", "title": "The guard post", "difficulty": "easy",
		"desc": "Someone was supposed to be watching this door. They are now."},
	{"id": "long-stair", "title": "The long stair", "difficulty": "normal",
		"desc": "Narrow, and they hold the top of it."},
	{"id": "pillared-hall", "title": "The pillared hall", "difficulty": "normal",
		"desc": "Too many places to stand out of sight, and they know all of them."},
	{"id": "fungus", "title": "The fungus gallery", "difficulty": "easy",
		"desc": "The light is coming off the walls. So is something else."},
	{"id": "kennels", "title": "The kennels", "difficulty": "normal",
		"desc": "Whatever is chained here has chewed through worse than a chain."},
	{"id": "flooded", "title": "The flooded passage", "difficulty": "normal",
		"desc": "Cold to the chest, and the current is going the wrong way."},
	{"id": "forge", "title": "The forge room", "difficulty": "normal",
		"desc": "The coals are still live. So is the smith."},
	{"id": "spoil-heap", "title": "The spoil heap", "difficulty": "easy",
		"desc": "The diggings. They have come up to see who is knocking."},
	{"id": "alcove", "title": "The shrine alcove", "difficulty": "normal",
		"desc": "They kneel to something down here, and it keeps guards."},
	{"id": "quarters", "title": "The sleeping quarters", "difficulty": "normal",
		"desc": "You have woken them. All of them."},
	{"id": "choke", "title": "The choke", "difficulty": "normal",
		"desc": "One way through, and they know it better than you do."},
]
const TREASURE_ROOMS := [
	{"id": "strongbox", "title": "The strongbox", "desc": "Whatever they took off the road, they put in here."},
	{"id": "tribute", "title": "The tribute pile", "desc": "Coin, mostly. Somebody's, once."},
	{"id": "nook", "title": "The quartermaster's nook", "desc": "Sorted, counted, and now yours."},
	{"id": "dead-adventurer", "title": "A dead adventurer", "desc": "Better equipped than you were. It did not help."},
]
const REST_ROOMS := [
	{"id": "dry-corner", "title": "A dry corner", "desc": "Out of the draught and out of the sightlines. An hour, maybe."},
	{"id": "barred-door", "title": "The barred door", "desc": "It holds from this side. Long enough to breathe."},
	{"id": "side-passage", "title": "The caved-in side passage", "desc": "Nothing comes through here. Nothing has in years."},
]

# picking → the player is choosing a room; combat/visiting → inside one;
# cleared/withdrawn/wiped are terminal and the world screen reads them to decide
# what happens next.
const TERMINAL := ["cleared", "withdrawn", "wiped"]

var lair
var party
var world
var rooms: Array = []          # rooms[depth] -> Array of room dicts (the picks on offer)
var depth := 0
var room: Dictionary = {}
var state := "picking"
var log: Array = []
var rng


static func for_lair(lair, party, world):
	var s = new()
	s.lair = lair
	s.party = party
	s.world = world
	# Seeded off the lair's own id, so the same warren is the same warren every
	# time it is entered — including after withdrawing and coming back.
	s.rng = RNG.new(maxi(1, absi(hash("site|%s" % lair.id))))
	s.rooms = _build(lair, s.rng)
	s.depth = clampi(int(lair.depth_cleared), 0, s.rooms.size() - 1)
	return s


# How many rooms deep this lair runs, before anything is generated — the world
# screen shows it on the "go in?" prompt, so it has to be answerable without
# building the site.
static func depth_for(lair) -> int:
	var idx: int = maxi(0, Scaler.FACTIONS.find(lair.faction))
	return clampi(MIN_DEPTH + idx / DEPTH_PER_FACTION_STEP, MIN_DEPTH, MAX_DEPTH)


# The board a fight in this lair happens on: the theme whose faction matches.
# Same reverse lookup scenes/world/world.gd's encounter_spec() does for roaming
# bands — one rule for "which board does this faction fight on", not two.
static func theme_for_faction(faction: String) -> String:
	for t in Scaler.THEME_FACTION:
		if String(Scaler.THEME_FACTION[t]) == faction:
			return String(t)
	return ""


# The whole interior, laid out up front: one array of picks per depth, the last
# depth always the boss alone (there is no choosing your way past the thing the
# lair is built around).
static func _build(lair, rng) -> Array:
	var total := depth_for(lair)
	var theme := theme_for_faction(lair.faction)
	var out: Array = []
	var used := {}
	for d in total - 1:
		var picks: Array = []
		var want: int = PICK_MIN + (1 if _randf(rng) < 0.5 and PICK_MAX > PICK_MIN else 0)
		# At least one way on is always a fight: a floor you can tiptoe past in
		# its entirety is a floor that never happened.
		picks.append(_combat_room(rng, used, theme, d))
		while picks.size() < want:
			if _randf(rng) < SUPPORT_CHANCE:
				picks.append(_support_room(rng, used, d))
			else:
				picks.append(_combat_room(rng, used, theme, d))
		out.append(picks)
	out.append([_boss_room(lair, theme, total)])
	return out


static func _randf(rng) -> float:
	return float(rng.roll_die(1000) - 1) / 1000.0


# Draws without repeating a room id inside one site — the same gallery twice in
# four floors reads as a bug, not as a dungeon.
static func _pick(pool: Array, rng, used: Dictionary) -> Dictionary:
	var free: Array = pool.filter(func(r): return not used.has(String(r["id"])))
	var from: Array = free if not free.is_empty() else pool
	var picked: Dictionary = from[rng.roll_die(from.size()) - 1]
	used[String(picked["id"])] = true
	return picked.duplicate(true)


static func _combat_room(rng, used: Dictionary, theme: String, d: int) -> Dictionary:
	var r := _pick(COMBAT_ROOMS, rng, used)
	r["kind"] = "combat"
	r["theme"] = theme
	r["depth"] = d
	return r


static func _support_room(rng, used: Dictionary, d: int) -> Dictionary:
	var rest: bool = _randf(rng) < REST_SHARE
	var r := _pick(REST_ROOMS if rest else TREASURE_ROOMS, rng, used)
	r["kind"] = "rest" if rest else "treasure"
	r["depth"] = d
	if not rest:
		r["gold"] = TREASURE_GOLD + TREASURE_PER_DEPTH * d
	return r


# The last room. Where a tuned boss exists for this lair's own board it is used
# — campaign.gd's BOSS_POOL entries carry measured win rates (scaler.gd's TUNING
# header), and there is no reason to invent a second, unmeasured set. A faction
# with no themed boss (dragon, currently) gets a plain hard roster instead,
# which is the same fallback contract every other lookup in this codebase uses.
static func _boss_room(lair, theme: String, total: int) -> Dictionary:
	for b in Campaign.BOSS_POOL:
		if String(b.get("theme", "")) == theme and theme != "":
			var r: Dictionary = b.duplicate(true)
			r["kind"] = "combat"
			r["depth"] = total - 1
			r["gold"] = BOSS_CACHE + BOSS_CACHE_PER_DEPTH * total
			return r
	return {"id": "%s-master" % lair.id, "kind": "combat", "boss": true,
		"title": "WHAT THE LAIR WAS BUILT AROUND", "difficulty": "hard",
		"desc": "It has been listening to you come down.", "theme": theme,
		"depth": total - 1, "gold": BOSS_CACHE + BOSS_CACHE_PER_DEPTH * total}


func say(line: String) -> void:
	log.append(line)


# --- the player's moves ---------------------------------------------------

func options() -> Array:
	return rooms[depth] if state == "picking" and depth < rooms.size() else []


func is_over() -> bool:
	return state in TERMINAL


func is_boss_depth() -> bool:
	return depth >= rooms.size() - 1


func depth_total() -> int:
	return rooms.size()


# A one-line "where am I" for whatever draws this. Deliberately not a UI
# decision — just the numbers a caller would otherwise re-derive.
func progress_line() -> String:
	return "%s — room %d of %d" % [lair.sname, mini(depth + 1, rooms.size()), rooms.size()]


func enter(i: int) -> Dictionary:
	var opts := options()
	if state != "picking" or i < 0 or i >= opts.size():
		return {}
	room = opts[i]
	state = "combat" if room["kind"] == "combat" else "visiting"
	say("→ %s" % room["title"])
	return room


# --- combat ---------------------------------------------------------------

func combat_spec() -> Dictionary:
	if room.get("kind", "") != "combat":
		return {}
	var theme: String = String(room.get("theme", ""))
	var seed_v: int = rng.seed_value + hash(String(room.get("id", "")))
	# D6: a lair is built for the country it stands in. Inside the band this is
	# 1.0 and changes nothing; outside it, a warren three days past the last
	# waystone is a frontier warren whoever walks in. The boss takes maxf(1.0, x)
	# — T92's rule that a climax is never scaled DOWN still holds, and it is this
	# call site that holds it (core/scaler.gd's boss_for takes the knob neutrally).
	var band: float = Regions.power_scale(world, lair.position, party)
	var spec: Dictionary = Scaler.boss_for(party.party_characters(), room, seed_v,
			maxf(1.0, band)) if room.has("lead") \
		else Scaler.roster_for(party.party_characters(), String(room.get("difficulty", "normal")),
			{}, theme, seed_v, band)
	spec["theme"] = theme if theme != "" else Campaign.BOSS["theme"]
	return spec


# `result` is Encounter.resolve_outcome()'s dict, straight off scenes/main.gd —
# the same shape campaign.gd's finish_combat() reads. XP and gold are banked by
# the world screen (it owns the party's purse and the XP split); what happens
# here is only the site's own state.
func finish_combat(result: Dictionary) -> void:
	if result.is_empty() or state != "combat":
		return
	if String(result.get("outcome", "")) != "Victory":
		state = "wiped"
		say("The party goes down in %s." % room.get("title", "the dark"))
		return
	say("%s is cleared." % room.get("title", "The room"))
	# The boss's cache is the reason to have come. Banked here rather than in a
	# treasure room because the boss room is not one.
	if is_boss_depth():
		var cache := int(room.get("gold", 0))
		if cache > 0:
			party.add_gold(cache)
			say("The lair's own hoard: +%d gold." % cache)


# --- the rooms that are not a fight ---------------------------------------

func take() -> int:
	if state != "visiting" or room.get("kind", "") != "treasure" or room.get("taken", false):
		return 0
	room["taken"] = true
	var gold := int(room.get("gold", 0))
	party.add_gold(gold)
	say("+%d gold." % gold)
	return gold


# The only rest inside a site, and it is deliberately the short one. A long rest
# here would refill slots mid-dungeon and delete the attrition this whole
# feature exists to create — the adventuring day IS the design. Costs an hour of
# world time, same as the map's own short rest, so it is not free either.
func short_rest() -> bool:
	if state != "visiting" or room.get("kind", "") != "rest" or room.get("rested", false):
		return false
	room["rested"] = true
	Visit.rest(party, world, "short-rest")
	say("An hour in %s. Not a night's sleep, but it is something." % room.get("title", "the dark"))
	return true


# --- getting out ----------------------------------------------------------

# Done with this room: deeper, or the site is finished.
func leave() -> void:
	if is_over():
		return
	var was_boss := is_boss_depth()
	room = {}
	depth += 1
	lair.depth_cleared = maxi(int(lair.depth_cleared), depth)
	if was_boss or depth >= rooms.size():
		state = "cleared"
		lair.looted = true          # the stash is spent; the marker greys out on the map
		say("%s is cleared out." % lair.sname)
		return
	state = "picking"


# --- what a wipe underground costs ----------------------------------------
#
# Locked with the user: harder than losing a fight on the road, softer than
# losing people for good. Going down a hole is supposed to be the gamble in
# this game, and it should not be free — but a bad roll four rooms deep must
# not end the save.
#
# Three parts, and the world screen applies them alongside its own existing
# `_retreat()` soft landing (gold tax, free revival, wake at the nearest
# settlement — unchanged, because the walk home is not the punishment):
#
#  1. **The bag, not the body.** Whatever was loose in the shared stash is
#     what got dropped when the party was dragged out. `Character.equipped`
#     is untouched by design — a party that loses its weapons and armour on
#     a bad night cannot fight its way back to relevance, and stripping the
#     thing a build is made of reads as the game taking your character away
#     rather than taking your loot.
#  2. **The lair is reset.** `depth_cleared` goes back to zero: they carried
#     their dead out, and the warren closed up behind them. This is the real
#     sting — the rooms you already paid for have to be paid for again — and
#     it costs nothing the player was holding.
#  3. The stash loss is seeded off the lair and the attempt, so it is not a
#     reload-until-it-picks-differently lottery.
const WIPE_STASH_SHARE := 0.34   # a third of what was loose; the rest stayed in the packs

# Returns what was taken, so the caller can narrate it — never just "you lost
# some things", same contract as every other check in this codebase.
static func wipe_penalty(party, lair, rng = null) -> Dictionary:
	var lost := {}
	var total := 0
	for e in party.stash:
		total += int(e["quantity"])
	var take: int = mini(total, maxi(1, int(floor(total * WIPE_STASH_SHARE)))) if total > 0 else 0
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("wipe|%s|%d" % [lair.id, int(lair.depth_cleared)]))))
	for i in take:
		var pool: Array = party.stash.filter(func(e): return int(e["quantity"]) > 0)
		if pool.is_empty():
			break
		var entry: Dictionary = pool[rng.roll_die(pool.size()) - 1]
		var item_id := String(entry["item_id"])
		party.stash_remove(item_id, 1)
		lost[item_id] = int(lost.get(item_id, 0)) + 1
	# The warren closes up behind them. Everything already fought through has
	# to be fought through again.
	lair.depth_cleared = 0
	return {"items": lost, "count": take, "reset": true}


# Walk out with everything already banked, leaving the rest of the lair standing.
# Only legal between rooms — never mid-fight — which is what makes "press on or
# get out" a real decision rather than an undo button. The depth reached is
# remembered on the Lair, so coming back later resumes rather than restarts.
func withdraw() -> bool:
	if state != "picking":
		return false
	state = "withdrawn"
	say("The party backs out of %s, and it is still down there." % lair.sname)
	return true

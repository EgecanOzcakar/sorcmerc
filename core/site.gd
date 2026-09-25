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
# Every entry starts at the mouth, and every entry is priced for the party
# with every slot back (Regions.fresh_score). Walking out undoes the descent:
# the rooms fill in again behind you, like a wipe but without a wipe's toll on
# the bag, and the coin already pocketed stays pocketed (Lair.caches_taken).
# Until 2026-09-24 a withdrawn delve resumed where it stopped, and the lair was
# priced for the party as it stood at the door — so walking in drained, or
# backing out and back in, bought a smaller lair and a smaller boss (the design
# audit, docs/audit-game-design.md §1.3 and §3.3).
#
# What this does NOT own, deliberately:
#  - the fight itself. combat_spec() feeds the same unchanged scenes/main.tscn
#    hand-off the open world and the linear campaign both already use.
#  - what a defeat costs. A wipe sets state to "wiped" and stops; the world
#    screen's own _retreat() decides the consequences, because a site sits
#    inside a persistent world rather than ending a run.
#  - saving. How deep this delve got lives on the Lair (depth_cleared) and which
#    caches are empty (caches_taken), which core/world_save.gd round-trips —
#    this object is rebuilt on entry, never serialized. depth_cleared is a
#    record, not a resume point: the next entry starts at the mouth.
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
const EnemyCasters = preload("res://core/enemy_casters.gd")
const Visit = preload("res://core/settlement_visit.gd")
const RNG = preload("res://core/rng.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Ach = preload("res://core/achievements.gd")
const Objectives = preload("res://core/objectives.gd")

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

# What clearing the place out is worth on top of the rooms themselves. Every
# fight on the way down already pays its own XP (encounter.gd resolves it per
# room), but reaching the bottom paid nothing extra — so a delve was worth
# strictly less than the same number of fights out on the road, which is the
# wrong way round for the one piece of content you commit to blind.
#
# Flat, and scaled by depth the way the hoard above is: a 3-room warren pays
# about what one more fight would at the levels a party clears one, a 6-room
# hold rather more. Only on a clear — withdrawing keeps what the rooms paid
# and nothing else, which is the whole tension of deciding to turn back.
const CLEAR_XP := 60
const CLEAR_XP_PER_DEPTH := 30

static func clear_xp(lair) -> int:
	return CLEAR_XP + CLEAR_XP_PER_DEPTH * depth_for(lair)

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
	# Objectives (core/objectives.gd): the room asks a different question.
	{"id": "gate", "title": "The gate", "difficulty": "normal", "objective": "hold",
		"desc": "Hold the passage while the way behind is barred. More of them will come from the far side."},
	{"id": "pens", "title": "The pens", "difficulty": "normal", "objective": "rescue",
		"desc": "Somebody is chained at the back, and their keepers know exactly how long you will take to reach them."},
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
var _rested := false     # T19: did this delve stop for its short rest?
# core/rules/power.gd's reading of the party at the MOUTH of this lair with
# every slot back, taken once per entry and used to price every room below it.
# See _held().
var entry_score := 0.0


static func for_lair(lair, party, world):
	var s = new()
	s.lair = lair
	s.party = party
	s.world = world
	# Seeded off the lair's own id, so the same warren is the same warren every
	# time it is entered — including after withdrawing and coming back.
	s.rng = RNG.new(maxi(1, absi(hash("site|%s" % lair.id))))
	s.rooms = _build(lair, s.rng)
	# The mouth, every time. A party that withdrew (or quit mid-delve, or kept
	# a save from before this rule) finds the rooms it fought through filled in
	# again: leaving undoes the descent (the design audit §3.3). What the party
	# already carried out stays carried out — a cache emptied on an earlier
	# entry is still empty, or walking in and out of the first floor would be a
	# purse that refills for nothing.
	lair.depth_cleared = 0
	s.depth = 0
	for d in s.rooms.size():
		for r in s.rooms[d]:
			if String(r.get("kind", "")) == "treasure" and _cache_key(r) in lair.caches_taken:
				r["taken"] = true
	# Taken here and nowhere else, and taken FRESH: the party at the mouth with
	# every slot back, the same reading the open world pins its fights to
	# (Regions.fresh_score, WorldThreat.slot_hold). It used to be
	# Scaler.party_score, which counts only the slots left, so a party that
	# walked in drained met a smaller lair and a smaller boss — spent slots
	# bought an easier fight (the design audit §1.3). Wounds still do not
	# enter it; Power.estimate reads max_hp, never hp.
	s.entry_score = Regions.fresh_score(party)
	return s


# Which cache this is, for Lair.caches_taken: its floor and its id, since a
# room id is unique inside one site only while the pool lasts.
static func _cache_key(r: Dictionary) -> String:
	return "%d|%s" % [int(r.get("depth", 0)), String(r.get("id", ""))]


# A lair is priced for the party that WALKED IN — with every slot back — not
# for the party standing in the doorway of the room it is about to build.
#
# MEASURED (2026-09-22, tests/sweep_site_depth.gd) — core/rules/power.gd's
# estimate() reads a combatant's ehp off max_hp and never off hp, so the only
# thing the scaler can see about a party's condition is how many spell slots
# are left. Inside a site that reads backwards. The same dragon's boss room,
# same party, one variable moved: at 64% slots it is five bodies whether the
# party is at 20% HP or 100%; hold HP at 67% and walk the slots from 0% to
# 100% and it goes 80.1 -> 145.3 in budget, three bodies to five. So spending
# slots used to shrink the next fight and RESTING used to grow it — at level 8
# the rest room bought 67% HP instead of 49% and the boss win rate fell, 23.7%
# to 18.3%, because the budget it handed back was worth more than the healing.
#
# This is the site-local answer to that: hold the entry reading and correct the
# scale so every room comes out the size it would have been at the mouth. Since
# 2026-09-24 the entry reading is the FRESH one (for_lair), so the hold pins
# every room, the first included, to the party with every slot back: slots
# spent before the door and slots spent on the way down are both invisible to
# the budget. It moves no global number — a fresh party at a lair's mouth is
# the full-HP, full-slot party every existing sweep already measures, and for
# it fresh_score and party_score are the same reading — and it makes the
# descent say one thing:
# the lair is what it is, and your condition decides whether you can take it,
# rather than deciding what is in it. The root fix, teaching estimate() to read
# hp, is a re-tune of everything and is in the expansion plan's Still open.
#
# Unclamped on purpose. Levelling up mid-delve (the world screen banks XP per
# room) raises `now` above `then` and pulls this below 1.0, which is the same
# statement read the other way: the lair does not get harder because the party
# got stronger halfway down it either.
func _held() -> float:
	return Scaler.held_at(entry_score, Scaler.party_score(party.party_characters()))


# How many rooms deep this lair runs, before anything is generated — the world
# screen shows it on the "go in?" prompt, so it has to be answerable without
# building the site.
static func depth_for(lair) -> int:
	var idx: int = maxi(0, Scaler.FACTIONS.find(lair.faction))
	return clampi(MIN_DEPTH + idx / DEPTH_PER_FACTION_STEP, MIN_DEPTH, MAX_DEPTH)


# Whether a rescue job about this lair can still be done: a pens room at a
# depth the party has not yet fought past. core/quest_posting.gd asks before
# posting, so a job is only ever posted about captives that are actually
# reachable. Same seed as for_lair(), so it is the same interior.
static func pens_ahead(lair) -> bool:
	var rooms: Array = _build(lair, RNG.new(maxi(1, absi(hash("site|%s" % lair.id)))))
	for d in range(int(lair.depth_cleared), rooms.size()):
		for r in rooms[d]:
			if String(r.get("objective", "")) == "rescue":
				return true
	return false


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


# A boss for the ten factions that have no board of their own, and so never had
# one.
#
# campaign.gd's BOSS_POOL is keyed by THEME and holds six entries — the linear
# route's climaxes, reused here because they carry measured win rates and there
# was no reason to invent a second unmeasured set. But a theme is a BOARD, and
# only five factions have one, so _boss_room fell through for orc, gnoll,
# kobold, cultist, soldier, monstrosity, fey, elemental, construct and dragon:
# a plain "hard" roster with no lead at all, and the title "WHAT THE LAIR WAS
# BUILT AROUND" — a description where every real boss has a name. Two thirds of
# the lairs in the game ended in a slightly bigger version of the room before
# it, which is what the level-8 column of tests/sweep_site_kin.gd was saying
# when every one of those lairs came out a flat 100% clear while a giant hold
# with a real oni in it came out 25%.
#
# Same two shapes BOSS_POOL uses, and for the same reasons:
#   "bestiary" — a rare, high-CR creature of the faction's own kin, pulled out
#                of the ordinary pool by _boss_lead_exclusion() so that meeting
#                it is a reveal rather than the third one today.
#   "elite"    — the faction's ordinary creature with a title and an extra
#                attack, for the three whose bestiary pool is one or two thin
#                entries (orc has ONE, gnoll and kobold two). scaler.boss_for's
#                mult knob does the rest and the budget's remainder buys escort,
#                exactly as the arrow-chief's does.
#
# `lead_features` is the special, and it is the point of the pass: one feature
# out of data/effects/features.json that the base statblock does NOT already
# carry, picked so the fight asks a question the rooms above it did not. The
# specials are deliberately all different — a boss the party has to reach fast
# (the mage's charm), out-damage (the hag's regeneration), stand up to (the
# elemental's knockdown), or out-last (the golem's relentless).
#
# MEASURED — tests/sweep_faction_boss.gd, the same shape tests/test_scaler.gd's
# _sweep_boss uses for BOSS_POOL's own numbers: 40 seeds a boss, level-3 preset
# party at full HP, the boss room's own spec. The grid is in
# docs/expansion-plan.md. The band to stay inside is test_scaler's climax band
# (15-85%), and the company to keep is BOSS_POOL's own spread — mammoth 65%,
# oni 82.5%, arrow-chief 82.5%, shrine 77%, assassin 92.5%, captain 92.5%.
# `mult_max` is the knob that pulls a lead back out of the top of that band by
# spending the budget on escort instead; the arrow-chief's note explains why.
const FACTION_BOSS := {
	"orc": {"title": "THE WARCHIEF", "archetype": "elite", "lead": "orc",
		"desc": "The one the rest of them are frightened of.",
		"lead_features": ["monster-multiattack-2", "monster-relentless-10"]},
	"gnoll": {"title": "THE ONE THAT EATS FIRST", "archetype": "elite", "lead": "gnoll",
		"desc": "It has not had to fight for its share in a long time.",
		"lead_features": ["monster-multiattack-2", "monster-martial-advantage"]},
	"kobold": {"title": "THE SCALE-SINGER", "archetype": "elite", "lead": "kobold-archer",
		"desc": "Small, and behind everything else in the room, and the reason the rest of them are brave.",
		"lead_features": ["monster-multiattack-2", "monster-innate-bolt"]},
	# lead_share 0.25, not the default 0.40: a mage the budget had pumped to
	# fill four tenths of the fight came out 97.5%, softer than any boss in the
	# game. Spending less of the fight on the lead spends more of it on bodies,
	# and bodies are what the action economy makes dangerous (scaler.gd's own
	# header). The cult's bodies happen to be other casters, which is the point.
	"cultist": {"title": "THE VOICE THEY ALL ANSWER", "archetype": "bestiary", "lead": "mage",
		"desc": "It is not the knives that are the problem. It is what they are listening to.",
		"lead_features": ["monster-charm-gaze"], "lead_share": 0.25,
		# 2026-09-24: the voice casts from real slots (core/enemy_casters.gd)
		# rather than throwing the innate bolt its statblock stands in with.
		"lead_caster": true},
	"soldier": {"title": "THE CAPTAIN WITH THE SCALED ARM", "archetype": "bestiary",
		"lead": "half-red-dragon-veteran",
		"desc": "He took something from a dragon once, and it took something back.",
		"lead_features": ["monster-parry-3"]},
	"monstrosity": {"title": "THE THING WITH THREE HEADS", "archetype": "bestiary", "lead": "chimera",
		"desc": "Two of them are watching you. The third is breathing in.",
		"lead_features": ["monster-frightful-presence"]},
	"fey": {"title": "THE GREEN MOTHER", "archetype": "bestiary", "lead": "green-hag",
		"desc": "Everything you have cut so far down here grew back by morning. So does she.",
		"lead_features": ["monster-regeneration"]},
	"elemental": {"title": "WHAT THE HILL IS MADE OF", "archetype": "bestiary", "lead": "earth-elemental",
		"desc": "The floor stands up.",
		"lead_features": ["monster-knockdown"]},
	"construct": {"title": "THE THING SOMEBODY MADE", "archetype": "bestiary", "lead": "flesh-golem",
		"desc": "Whoever built it is one of the parts.",
		"lead_features": ["monster-relentless-14"]},
	# CR 6, a notch under the oni's 7, and not the CR 10 young red the first cut
	# reached for: boss_for's mult knob can raise a lead for the deeps and has no
	# way to lower one, so a lead priced above the boss band is a lead that is
	# 0% at every level below it. The dragon still out-carries every other lead
	# here on features alone — three attacks, a rider and the greater breath.
	"dragon": {"title": "THE WYRM AT THE BOTTOM", "archetype": "bestiary", "lead": "young-white-dragon",
		"desc": "Everything above this room was somebody it let live.",
		"lead_features": ["monster-magic-resistance"]},
}

# The last room. Where a tuned boss exists for this lair's own board it is used
# — campaign.gd's BOSS_POOL entries carry measured win rates (scaler.gd's TUNING
# header), and there is no reason to invent a second, unmeasured set. Failing
# that, the faction's own boss above. Failing BOTH — a content pack's faction
# this build has never heard of — the plain hard roster that every lair used to
# get, which is the same fallback contract every other lookup in this codebase
# uses.
static func _boss_room(lair, theme: String, total: int) -> Dictionary:
	for b in Campaign.BOSS_POOL:
		if String(b.get("theme", "")) == theme and theme != "":
			var r: Dictionary = b.duplicate(true)
			r["kind"] = "combat"
			r["depth"] = total - 1
			r["gold"] = BOSS_CACHE + BOSS_CACHE_PER_DEPTH * total
			return r
	var own: Dictionary = FACTION_BOSS.get(lair.faction, {})
	if not own.is_empty():
		var r: Dictionary = own.duplicate(true)
		r["id"] = "%s-master" % lair.id
		r["kind"] = "combat"
		r["boss"] = true
		r["difficulty"] = "hard"
		r["theme"] = theme          # "" — the roster comes off the pinned seed
		r["depth"] = total - 1
		r["gold"] = BOSS_CACHE + BOSS_CACHE_PER_DEPTH * total
		return r
	return {"id": "%s-master" % lair.id, "kind": "combat", "boss": true,
		"title": "WHAT THE LAIR WAS BUILT AROUND", "difficulty": "hard",
		"desc": "It has been listening to you come down.", "theme": theme,
		"depth": total - 1, "gold": BOSS_CACHE + BOSS_CACHE_PER_DEPTH * total}


# The creature the last room is built around must not be a regular pick on the
# way down. Once a party is strong enough (~level 6 for the oni), the faction
# pool would hand it out as plain escort, and "THE ONI OF THE DEEP ICE" is not a
# reveal after you have already killed two. Only for "bestiary" bosses — an
# "elite" lead (the arrow-chief's goblin archer) IS the common creature with a
# title, and pulling it from the warren would gut every goblin roster.
func _boss_lead_exclusion() -> Array:
	var boss: Dictionary = rooms[-1][0] if not rooms.is_empty() else {}
	if String(boss.get("archetype", "")) == "bestiary" and boss.has("lead"):
		return [String(boss["lead"])]
	return []


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
	# A lair is its own people, all the way down. theme_for_faction() returns ""
	# for the ten factions with no board of their own (orc, gnoll, kobold,
	# cultist, soldier, monstrosity, fey, elemental, construct, dragon), and for
	# those core/scaler.gd's _faction_order reads the faction off the SEED —
	# which is per-room here, so without this line each room rolled a fresh
	# arbitrary people and a dragon's cave was six rooms of six of them.
	# pin_faction touches only the remainder that carries the faction, so the
	# rooms still differ from each other in every other way.
	#
	# MEASURED — tests/sweep_site_kin.gd, 30 whole delves a faction, level-3
	# preset party, lair at the origin so the band clamp above is a no-op. The
	# grid is in docs/expansion-plan.md; the shape of it is that a themeless
	# lair drew from all fifteen factions before and draws from one after, and
	# that what the party gets through moves by faction rather than in one
	# direction — a pinned lair lands on its own people's number instead of on
	# the average of a random draw. Re-run it before changing anything here.
	if theme == "":
		seed_v = Scaler.pin_faction(seed_v, lair.faction)
	# D6: a lair is built for the country it stands in. Inside the band this is
	# 1.0 and changes nothing; outside it, a warren three days past the last
	# waystone is a frontier warren whoever walks in. The boss takes maxf(1.0, x)
	# — T92's rule that a climax is never scaled DOWN still holds, and it is this
	# call site that holds it (core/scaler.gd's boss_for takes the knob neutrally).
	var band: float = Regions.power_scale(world, lair.position, party)
	# ...times the entry correction, so the two knobs compose the way the world
	# screen's two do: the band says how dangerous this country is, `held` says
	# the descent is priced for the party that came through the door.
	#
	# T92's floor goes on the COMPOSED scale, `maxf(1.0, band * held)`, and not
	# on the band alone with `held` multiplied over it. Stacking two upward
	# corrections is how the first cut of this made the level-8 boss a 0/48
	# wall: at the origin a level-8 party reads band 0.320, so its rooms are
	# priced at a third while the floor already hands the boss a 3.1x jump over
	# them, and `held` was making that 3.75x. Floored together, an outgrown
	# lair's climax stays exactly the fight it was (0.320 * 1.2 is still under
	# 1.0) and `held` only bites where the country is not already discounting —
	# which is the case it was built for.
	var held: float = _held()
	# An enemy caster in here casts to this country's tier, not the party's
	# (core/enemy_casters.gd): a level-3 party that walks into the Deeps meets
	# the Deeps' casters, as it meets the Deeps' budget.
	var cap: int = EnemyCasters.cap_for_band(String(Regions.at(world, lair.position)["id"])) if world != null else 0
	var boss_room: Dictionary = room.duplicate()
	if cap > 0:
		boss_room["caster_cap"] = cap
	var spec: Dictionary = Scaler.boss_for(party.party_characters(), boss_room, seed_v,
			maxf(1.0, band * held)) if room.has("lead") \
		else Scaler.roster_for(party.party_characters(), String(room.get("difficulty", "normal")),
			{}, theme, seed_v, band * held, _boss_lead_exclusion(), "", cap)
	# Objectives: the gate holds against waves drawn from the same faction at
	# WAVE_SCALE of an easy roster; the pens hold a captive on a deadline.
	#
	# `lair.faction` for the same reason scenes/world/world.gd's road hold
	# passes the band's: waves_for gives each wave its own roll with a `+ 17`
	# that is not a multiple of FACTIONS.size(), so without it the offset walks
	# each wave off the people the room itself was drawn from. Pinning the room
	# seed above is not enough on its own — both have to move, which is what
	# the note here used to say was not yet true.
	match String(room.get("objective", "")):
		"hold":
			spec["objective"] = Objectives.make("hold", {"waves": Objectives.waves_for(
				party.party_characters(), theme, seed_v, band * held, _boss_lead_exclusion(),
				lair.faction)})
		"rescue":
			spec["objective"] = Objectives.make("rescue")
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
		Ach.unlock("lair_wipe")
		say("The company goes down in %s." % room.get("title", "the dark"))
		return
	say("%s is cleared." % room.get("title", "The room"))
	# The boss's cache is the reason to have come. Banked here rather than in a
	# treasure room because the boss room is not one.
	if is_boss_depth():
		var cache := int(room.get("gold", 0))
		if cache > 0:
			party.add_gold(cache)
			say("The lair's own hoard: +%d ◉." % cache)


# --- the rooms that are not a fight ---------------------------------------

func take() -> int:
	if state != "visiting" or room.get("kind", "") != "treasure" or room.get("taken", false):
		return 0
	room["taken"] = true
	lair.caches_taken.append(_cache_key(room))   # still empty when they come back
	var gold := int(room.get("gold", 0))
	party.add_gold(gold)
	say("+%d ◉." % gold)
	return gold


# The only rest inside a site, and it is deliberately the short one. A long rest
# here would refill slots mid-dungeon and delete the attrition this whole
# feature exists to create — the adventuring day IS the design. Costs an hour of
# world time, same as the map's own short rest, so it is not free either.
func short_rest() -> bool:
	if state != "visiting" or room.get("kind", "") != "rest" or room.get("rested", false):
		return false
	if not Visit.can_short_rest(party, world):
		say("Nobody can rest any more today — only a night's sleep will do now.")
		return false
	room["rested"] = true
	_rested = true
	var r: Dictionary = Visit.rest(party, world, "short-rest")
	say("An hour in %s. Not a night's sleep, but it is something.%s" % [room.get("title", "the dark"), Visit.rest_note(r)])
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
		# The stash is spent and the marker greys out — and the respawn clock
		# starts, so something can move back in a day from now (three on the
		# Frontier, five in the Deeps: core/world_lairs.gd's respawn_after).
		WorldLairs.mark_cleared(lair, world.clock.elapsed if world != null else -1.0)
		# #231: and its people remember who did it (core/grudges.gd).
		var Grudges = load("res://core/grudges.gd")
		Grudges.add(lair.faction, Grudges.LAIR)
		Ach.bump("lairs")
		Ach.record("deepest_lair", rooms.size())
		if not _rested:
			Ach.unlock("lair_no_rest")
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
# `_retreat()` (gold tax, the downed come to and the dead stay dead, wake at
# the nearest settlement — the walk home is not the punishment):
#
#  1. **The bag, not the body.** Whatever was loose in the shared stash is
#     what got dropped when the party was dragged out. `Character.equipped`
#     is untouched by design — a party that loses its weapons and armour on
#     a bad night cannot fight its way back to relevance, and stripping the
#     thing a build is made of reads as the game taking your character away
#     rather than taking your loot.
#  2. **The lair is reset.** `depth_cleared` goes back to zero: they carried
#     their dead out, and the warren closed up behind them. The rooms already
#     paid for have to be paid for again. Since 2026-09-24 walking out does
#     the same (withdraw(), for_lair()), so of the three this is the part a
#     wipe shares with any exit; the bag is what is a wipe's alone.
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
# get out" a real decision rather than an undo button. And it is not a pause:
# the rooms fought through fill in again, and the next entry starts at the
# mouth (for_lair), priced fresh — a wipe's reset without a wipe's toll on the
# bag (the design audit §3.3). It used to remember the depth and resume there,
# which made "withdraw, camp, come back" the right answer to every deep lair.
# depth_cleared keeps how far this delve got until the next entry, for the
# page that says what the descent paid.
func withdraw() -> bool:
	if state != "picking":
		return false
	state = "withdrawn"
	Ach.unlock("lair_withdraw")
	say("The company backs out of %s. What it cleared will not stay cleared." % lair.sname)
	return true

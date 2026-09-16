# What a won fight leaves on the field.
#
#   Loot.for_kills(["goblin-warrior", "hobgoblin"], rng)   # -> ["shortbow", ...]
#
# core/encounter.gd's resolve_outcome() calls this with the ids of everything
# that died and the fight's own RNG, and the result rides home in
# `result["loot"]` — which both banking paths (core/campaign.gd's
# finish_combat and scenes/world/world.gd's _bank) have always stashed. Until
# this file existed that array was always empty: it was built only from a
# monster's own hand-authored `loot` key, and not one of the 316 entries in
# data/bestiary.json has one. You could clear a bandit camp and come away with
# gold and XP and nothing you could hold.
#
# Two rules decide what drops, and both of them are "appropriate to what you
# just killed" rather than a flat table:
#
#   WHO it was decides what it was carrying. A bandit is holding a shortsword
#   and a leather jerkin; a goblin a scimitar and a shortbow. A wolf is holding
#   nothing, because a wolf is holding nothing — CARRIED below is keyed on the
#   bestiary's `faction`, falling back to its `type`, and anything not in it is
#   a creature you loot rather than a person you rob.
#
#   HOW DANGEROUS it was decides how often, and how good. A CR 1/8 rat is a
#   1-in-8 shrug; an ogre is worth stopping to search, and what turns up is
#   pulled from a rarity band that only opens at that CR.
#
# Every id this hands back is a REAL catalog id — data/weapons.json,
# data/armor.json, data/magic-items.json. That is not decoration: the stash
# shows `Campaign.item_name()`, the shop pays `Campaign.item_price()` and the
# rarity colour comes off `Icons.rarity_of()`, and all three quietly degrade
# to "capitalize the id, worth 0 gp, common grey" for an id the catalog has
# never heard of. An invented "wolf-pelt" would look like loot and behave like
# litter.
#
# Deterministic: it rolls on the RNG it is handed, which is the fight's own
# (seeded off the encounter), so SORCMERC_SEED replays the same drops.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

# Chance that one dead thing left anything at all, before the CR ramp.
const BASE_CHANCE := 0.12
const CHANCE_PER_CR := 0.09
const MAX_CHANCE := 0.70
# A creature that carries nothing is half as likely to be worth searching: what
# turns up is what the last person it ate was carrying, not its own kit.
const SCAVENGE_MULT := 0.5
# Something big enough gets searched twice — a lair-keeper is an event, and one
# roll makes it feel like a bigger wolf.
const SECOND_ROLL_CR := 8.0
# The whole fight, not per kill: eight goblins should not come to eight swords.
const MAX_DROPS := 3

# Who is carrying gear, and what kind. Keyed on `faction` first (the axis
# core/scaler.gd builds rosters along) and then on `type`, so a one-off entry
# with no faction of its own still reads as the humanoid it is.
#
# Deliberately short lists of ordinary kit. This is the stuff that was in their
# hands when they went down, so it is the stuff a shop will buy for a handful
# of gold — the interesting drops come out of the magic-item bands below.
const CARRIED := {
	"bandit":     ["dagger", "shortsword", "leather", "shortbow", "club"],
	"soldier":    ["spear", "longsword", "chain-shirt", "shield", "light-crossbow"],
	"goblinoid":  ["scimitar", "shortbow", "leather", "javelin"],
	"orc":        ["greataxe", "javelin", "hide"],
	"gnoll":      ["spear", "longbow", "hide"],
	"kobold":     ["dagger", "sling", "padded"],
	"cultist":    ["dagger", "sickle", "leather"],
	"drow":       ["rapier", "hand-crossbow", "studded-leather"],
	"duergar":    ["war-pick", "javelin", "scale-mail"],
	"lizardfolk": ["spear", "club", "hide"],
	"sahuagin":   ["spear", "trident"],
	"merfolk":    ["spear", "trident"],
	"grimlock":   ["club", "handaxe"],
	"tribal":     ["spear", "club", "hide"],
	"townsfolk":  ["club", "dagger"],
	"giant":      ["greatclub", "maul", "hide"],
	# They were people once, and they were buried with what they owned.
	"undead":     ["longsword", "rapier", "ring-mail", "shield"],
	"humanoid":   ["dagger", "club", "spear", "leather"],
	"devil":      ["trident", "glaive"],
	"demon":      ["greatsword", "whip"],
	"fiend":      ["greatsword", "whip"],
}

# What CR opens what shelf. A dragon does not hoard healing draughts.
const RARITY_BANDS := [
	{"cr": 0.0, "rarity": "common"},
	{"cr": 3.0, "rarity": "uncommon"},
	{"cr": 6.0, "rarity": "rare"},
	{"cr": 9.0, "rarity": "very-rare"},
]
# Never dropped: an artifact prices at 0 (Campaign.item_price), so it is the one
# thing a shop will not buy and the stash cannot value.
const UNDROPPABLE_RARITIES := ["artifact"]

# The drinkable/readable slice, banded by the same CR ladder and CUMULATIVE: a
# CR 10 kill can still turn up a healing potion, a CR 1/8 one cannot turn up a
# potion of speed. Hand-listed rather than sniffed out of the file by id prefix,
# the same way core/campaign.gd's STOCK and SCROLL_IDS are, because two of the
# would-be matches should not be rewards at all: potion of poison is a trap
# wearing a reward's shape, and the resurrection scroll is the campaign's own
# stock, not something a goblin was carrying. tests/test_loot.gd checks every id
# here resolves in the catalog.
#
# potions-of-healing sits in the UNCOMMON band rather than the obvious common
# one because of how it is priced: the SRD files healing/greater/superior under
# one heading, so its rarity is "varies", and core/campaign.gd deliberately
# prices "varies" as rare (VARIES_TIER) — 2025 gp. Handing that to a party for
# killing a CR 1/8 bandit is not a healing potion, it is a purse. One band up it
# is worth roughly what the thing that was carrying it was worth.
const CONSUMABLE_BANDS := {
	"common":    ["scroll-of-identification"],
	"uncommon":  ["potions-of-healing", "potion-of-animal-friendship", "potion-of-growth",
		"potion-of-resistance"],
	"rare":      ["potion-of-heroism", "potion-of-invisibility", "potion-of-mind-reading",
		"potion-of-gaseous-form", "potion-of-clairvoyance"],
	"very-rare": ["potion-of-speed"],
}

# Of the rolls that hit: how they split between the three kinds of thing.
# A creature with no kit rolls its GEAR share into the consumable instead —
# there is no jerkin on a wolf, but there may well be a vial in what it dragged
# back to its den.
const GEAR_SHARE := 55
const CONSUMABLE_SHARE := 30      # the rest (15%) is a real magic item

# --- the one call --------------------------------------------------------

# `kills` are bestiary ids, exactly as core/encounter.gd's `kills` list has them.
# Returns item ids, possibly with repeats (two bandits, two daggers) — the stash
# already stacks by id, so repeats are a quantity, not a bug.
static func for_kills(kills: Array, rng) -> Array:
	var out: Array = []
	for id in kills:
		if out.size() >= MAX_DROPS:
			break
		var mon: Dictionary = Catalog.monster(String(id))
		if mon.is_empty():
			continue
		var cr := float(mon.get("cr", 0.0))
		var kit: Array = kit_for(mon)
		var per_mille: int = roundi(drop_chance(cr, not kit.is_empty()) * 1000.0)
		var rolls: int = 2 if cr >= SECOND_ROLL_CR else 1
		for _i in rolls:
			if out.size() >= MAX_DROPS:
				break
			# core/rng.gd is a die roller, not a float source — a d1000 against
			# the chance in per-mille is the same thing and stays integral.
			if rng.roll_die(1000) > per_mille:
				continue
			var item := _pick(cr, kit, rng)
			if item != "":
				out.append(item)
	return out

# The odds one of these left something. Flat ramp on CR, capped, halved for a
# creature with nothing of its own to drop.
static func drop_chance(cr: float, carries_gear: bool) -> float:
	var c := clampf(BASE_CHANCE + CHANCE_PER_CR * cr, BASE_CHANCE, MAX_CHANCE)
	return c if carries_gear else c * SCAVENGE_MULT

# What this creature had in its hands. [] for anything that does not have hands,
# or does not put weapons in them.
static func kit_for(mon: Dictionary) -> Array:
	var fac := String(mon.get("faction", ""))
	if CARRIED.has(fac):
		return CARRIED[fac]
	return CARRIED.get(String(mon.get("type", "")), [])

# The shelf a kill of this CR draws from: the richest band it has reached.
static func rarity_for(cr: float) -> String:
	var out := String(RARITY_BANDS[0]["rarity"])
	for b in RARITY_BANDS:
		if cr >= float(b["cr"]):
			out = String(b["rarity"])
	return out

# Every magic item of one rarity that is worth carrying home, cached per rarity
# because this walks a 264-entry file and a fight can ask several times.
static var _by_rarity := {}

static func items_of_rarity(rarity: String) -> Array:
	if not _by_rarity.has(rarity):
		var out: Array = []
		if not rarity in UNDROPPABLE_RARITIES:
			for id in Catalog.index("magic-items.json"):
				if String(Catalog.magic_item(String(id)).get("rarity", "")) == rarity:
					out.append(String(id))
		out.sort()      # a Dictionary's key order is not a promise; the seed is
		_by_rarity[rarity] = out
	return _by_rarity[rarity]

# Everything drinkable a kill of this CR could have been carrying: its own band
# and every band below it.
static func consumables_for(cr: float) -> Array:
	var out: Array = []
	var top := rarity_for(cr)
	for b in RARITY_BANDS:
		out.append_array(CONSUMABLE_BANDS.get(String(b["rarity"]), []))
		if String(b["rarity"]) == top:
			break
	return out

# One drop. Which of the three kinds it is depends on the roll; which item
# within that kind depends on who died. A creature with no kit has no gear
# slice, so its low rolls fall through into the consumable — which is the
# "whatever it dragged back to its den" case.
static func _pick(cr: float, kit: Array, rng) -> String:
	var roll: int = rng.roll_die(100)
	if not kit.is_empty() and roll <= GEAR_SHARE:
		return String(kit[rng.roll_die(kit.size()) - 1])
	if roll <= GEAR_SHARE + CONSUMABLE_SHARE:
		var pool := consumables_for(cr)
		if not pool.is_empty():
			return String(pool[rng.roll_die(pool.size()) - 1])
	var band := items_of_rarity(rarity_for(cr))
	if band.is_empty():
		return ""
	return String(band[rng.roll_die(band.size()) - 1])

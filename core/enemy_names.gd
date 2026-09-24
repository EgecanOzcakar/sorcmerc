# Fantasy first names for humanoid foes, keyed by data/bestiary.json's `faction`
# tag (T16). Flavor only — cname becomes "<Name> the <Species>" instead of a bare
# species label; nothing here is read by combat mechanics. A faction with no list
# falls back to GENERIC.
#
# And the names of the roaming bands themselves (the design audit,
# docs/audit-game-design.md §6.1). A band's id — "goblin-raiders-3" — is a key:
# saves, hunt quests, callings, the mod API and the respawn list all look a band
# up by it, and it never changes. Until 2026-09-24 it was also the band's name,
# run through capitalize(), so the board posted "Hunt down the Goblin Raiders 3
# band" and a merc's past was "the band called Gnoll Pack 2". band_name() is now
# the one place a band is named to the player:
#
#   EnemyNames.band_name(band, world)   # "Ribsnap's goblins", "the Low Fen gnolls"
#   EnemyNames.upper_first(name)        # the same, at the head of a sentence
#
# The name is seeded off the band's id and the world's own seed, so it needs no
# save field, reads the same after a reload, and is the same when a beaten band
# comes back on the roads (WorldAI.respawn keeps the id). A name a pack wrote —
# world.json's parties[].name, or a story's spawn_party name — is kept in
# RoamingParty.sname and always wins. Every generated name is a plural ("...are
# asking after you"), so the lines around it agree whichever template it took.
#
# What this does not own: which band a quest or a calling points at
# (core/quest.gd, core/callings.gd), or what a band is (its `ai.kind`, from
# WorldBands.KINDS) — the refill line used to say only that, and now says who.
extends RefCounted

const NAMES := {
	"goblinoid": ["Grix", "Snik", "Muk", "Yarnik", "Korga", "Fessek", "Ribsnap", "Dolgar"],
	"bandit": ["Cutter", "Harlan", "Mags", "Wren", "Doss", "Fenn", "Priska", "Yorrick"],
	"soldier": ["Corvin", "Aldric", "Brenna", "Talon", "Ossric", "Vale", "Dresk", "Kael"],
	"cultist": ["Vesk", "Nyra", "Othmar", "Sable", "Grivane", "Ulda", "Peron", "Marrow"],
	"kobold": ["Zizzik", "Trak", "Piv", "Skree", "Nix", "Bok"],
	"gnoll": ["Ragjaw", "Skarn", "Yipfang", "Maug", "Crag", "Hessk"],
	"orc": ["Grosh", "Uzka", "Thokk", "Varga", "Mok", "Drem"],
	"drow": ["Vondal", "Szaress", "Ilphrin", "Quenthir", "Malyx"],
	"duergar": ["Drok", "Umbra", "Fenrig", "Coalspar", "Greyx"],
	"lizardfolk": ["Sskra", "Vashti", "Korrax", "Zeel", "Hissra"],
	"sahuagin": ["Kalthar", "Reevash", "Sszik", "Undrothal"],
	"grimlock": ["Mrek", "Ghast", "Nullo", "Vurm"],
	"merfolk": ["Tidesong", "Coralyn", "Whelan", "Nerinn"],
	"townsfolk": ["Doran", "Meg", "Willem", "Edda", "Toby", "Rosalind"],
	"tribal": ["Rusk", "Sura", "Brokk", "Yenna", "Tarn", "Ithil"],
}
const GENERIC := ["Ash", "Corr", "Rennet", "Sable", "Torin", "Wyn", "Bram", "Isolde"]

# `key` should be something already unique-per-spawn (combatant id + spawn pos, say)
# so two goblins in the same fight don't get the same name but the same fight,
# same seed, always names them the same.
static func name_for(faction: String, key: String) -> String:
	var pool: Array = NAMES.get(faction, GENERIC)
	var i: int = hash(key) % pool.size()
	if i < 0:
		i += pool.size()
	return String(pool[i])

# --- band names -------------------------------------------------------------

# The plural a band's name ends in, by faction. A faction with none is a "lot".
const BAND_NOUNS := {
	"goblinoid": ["goblins", "raiders"], "bandit": ["bandits", "cutthroats"],
	"soldier": ["soldiers", "deserters"], "cultist": ["faithful", "cultists"],
	"kobold": ["kobolds"], "gnoll": ["gnolls"], "orc": ["orcs"], "giant": ["giants"],
	"duergar": ["duergar"], "drow": ["drow"], "lizardfolk": ["lizardfolk"],
	"beast": ["beasts"], "undead": ["dead"], "monstrosity": ["horrors"],
	"dragon": ["drakes"], "construct": ["constructs"], "elemental": ["elementals"],
	"fey": ["fey"],
	"human": ["wardens"], "elf": ["wardens"], "dwarf": ["wardens"],   # a civilized band is a patrol
}
# Nobody follows a wolf by name. These are only ever called after a place.
const LEADERLESS := ["beast", "undead", "monstrosity", "dragon", "construct", "elemental", "fey"]
# Whose names a leader is drawn from, where it is not the band's own faction:
# a human patrol's sergeant is a soldier, a caravan's master is townsfolk.
const LEADER_POOL := {"human": "soldier", "caravan": "townsfolk"}
# Nobody on the road knows what a band calls itself; they call it after where
# it was last seen. Plain country names, the kind a map already has.
const PLACES := ["Hollow Road", "Black Ford", "Saltmarsh", "Greywater", "Crow Hill",
	"Old Mill", "Stonebridge", "Low Fen", "Ashcombe", "Thistle Down", "Cold Spring",
	"Gallows Oak", "Long Barrow", "Redmire", "Shepherd's Cross", "Nine Wells"]

# `band` is a World.RoamingParty or a WorldAI fallen record ({id, faction,
# sname}); `world` gives the seed (origin.seed) and, for a lair's raiders, the
# lair they came out of. With no world the seed is 0.
static func band_name(band, world = null) -> String:
	var own := String(_field(band, "sname", ""))
	if own != "":
		return own
	var id := String(_field(band, "id", ""))
	var faction := String(_field(band, "faction", ""))
	var ai = _field(band, "ai", {})
	if not (ai is Dictionary):
		ai = {}
	if String(ai.get("behavior", "")) == "raid" and world != null:
		for l in world.lairs:
			if l.id == String(ai.get("home", "")):
				return "the raiders out of %s" % l.sname
	var wseed: int = int(world.origin.get("seed", 0)) if world != null and "origin" in world else 0
	var h: int = absi(hash("band|%s|%d" % [id, wseed]))
	var caravan := String(ai.get("kind", "")) == "caravan"
	var nouns: Array = ["wagons"] if caravan else BAND_NOUNS.get(faction, ["lot"])
	var noun := String(nouns[(h / 7) % nouns.size()])
	if LEADERLESS.has(faction) or h % 2 == 0:
		return "the %s %s" % [PLACES[(h / 13) % PLACES.size()], noun]
	var pool := String(LEADER_POOL.get("caravan" if caravan else faction, faction))
	return "%s's %s" % [name_for(pool, "leader|%s|%d" % [id, wseed]), noun]

# "the Low Fen gnolls" at the head of a line.
static func upper_first(s: String) -> String:
	return s if s == "" else s.substr(0, 1).to_upper() + s.substr(1)

static func _field(band, key: String, default):
	if band is Dictionary:
		return band.get(key, default)
	var v = band.get(key) if band != null else null
	return default if v == null else v

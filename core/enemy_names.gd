# Fantasy first names for humanoid foes, keyed by data/bestiary.json's `faction`
# tag (T16). Flavor only — cname becomes "<Name> the <Species>" instead of a bare
# species label; nothing here is read by combat mechanics. A faction with no list
# falls back to GENERIC.
extends RefCounted

const NAMES := {
	"goblinoid": ["Grix", "Snik", "Muk", "Yarnik", "Korga", "Fessek", "Ribsnap", "Dolgar"],
	"bandit": ["Cutter", "Harlan", "Mags", "Wren", "Doss", "Fenn", "Priska", "Yorrick"],
	"soldier": ["Corvin", "Aldric", "Brenna", "Talon", "Ossric", "Vale", "Dresden", "Kael"],
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
	"tribal": ["Kael", "Sura", "Brokk", "Yenna", "Tarn", "Ithil"],
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

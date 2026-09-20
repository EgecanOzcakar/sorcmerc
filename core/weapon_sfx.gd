# T9z — which sound a hit or a cast makes. Pure lookup, no nodes: combat.gd asks
# here, then hands the id to core/audio.gd's play_sfx() exactly as it did with the
# old one-size "hit"/"cast". The assets are tools/gen_audio.py's — one recipe
# per id below, so adding a class here means adding a recipe there.
#
#   WeaponSfx.for_attack(attacker)    # "hit_sword" | "hit_bow" | ... | "hit"
#   WeaponSfx.for_spell("fireball")   # "cast_evocation" | ... | "cast"
#
# Heroes: attacks[0] (the main hand, core/adapter.gd's one writer) carries the
# weapon id, its properties, range and damage type — enough to tell an axe from
# a sword from a bow. Monsters carry no weapon at all, just "bite"/"claw"/"slam"
# and a damage type, so they fall through to a natural-attack class off that.
# Anything unrecognised gets the generic id, same fallback contract as every
# other lookup in this codebase.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

# Every id this file can hand out — tests/test_audio.gd asserts each has a WAV.
const ATTACK_IDS := ["hit_sword", "hit_axe", "hit_blunt", "hit_pierce", "hit_bow",
	"hit_thrown", "hit_claw", "hit_bite", "hit_slam"]
const SPELL_IDS := ["cast_evocation", "cast_abjuration", "cast_conjuration",
	"cast_enchantment", "cast_transmutation", "cast_divination", "cast_illusion",
	"cast_necromancy"]
# A miss splits only two ways, not nine. What you hear when a blow lands is the
# weapon meeting armour, which is what makes an axe and a mace different sounds;
# what you hear when it misses is air, and air moved by an axe and a mace is the
# same air. The one split worth keeping is melee against ranged: a whiffed swing
# is a whoosh that stays with you, a missed shot whistles past and lands somewhere.
const MISS_IDS := ["miss", "miss_ranged"]


static func for_attack(c) -> String:
	if c == null:
		return "hit"
	if not c.attacks.is_empty():
		var a: Dictionary = c.attacks[0]
		var id := String(a.get("id", "")).to_lower()
		var ranged: bool = String(a.get("range", "melee")) == "ranged"
		var dtype := String(a.get("damage_type", ""))
		if ranged:
			# shortbow, longbow, hand-/light-/heavy-crossbow all contain "bow";
			# javelin, dart, sling and the rest are launched by hand.
			return "hit_bow" if "bow" in id else "hit_thrown"
		# An axe is slashing like a sword but doesn't ring like one — chops.
		# Halberd/glaive are axe-headed polearms, same family.
		if "axe" in id or id in ["halberd", "glaive"]:
			return "hit_axe"
		match dtype:
			"slashing": return "hit_sword"
			"piercing": return "hit_pierce"
			"bludgeoning": return "hit_blunt"
		return "hit"
	# A monster: no weapon, a body. Ranged natural attacks (spit, thrown rock)
	# read as thrown; melee ones split on what the wound is.
	if c.ranged:
		return "hit_thrown"
	match String(c.damage_type):
		"slashing": return "hit_claw"
		"piercing": return "hit_bite"
		"bludgeoning": return "hit_slam"
	return "hit"


# Which miss a swing makes. Same contract as for_attack(): heroes carry the
# weapon on attacks[0], monsters carry only `ranged`, and anything unreadable
# falls through to the melee whoosh rather than going silent.
static func for_miss(c) -> String:
	if c == null:
		return "miss"
	if not c.attacks.is_empty():
		return "miss_ranged" if String(c.attacks[0].get("range", "melee")) == "ranged" else "miss"
	return "miss_ranged" if c.ranged else "miss"


static func for_spell(spell_id: String) -> String:
	if spell_id == "":
		return "cast"
	var school := String(Catalog.spell(spell_id).get("school", ""))
	var id := "cast_" + school
	return id if id in SPELL_IDS else "cast"

# The three MVP heroes rebuilt as real 5.5e builds. encounter.gd's hand-authored
# numbers are the target; tests/test_rules.gd asserts the sheets match within +/-1
# and records the differences that are tuning decisions rather than port bugs.
extends RefCounted

const Character = preload("res://core/character.gd")

static func _base(id: String, name: String, species: String, background: String,
		abil: Dictionary, cid: String, n: int) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = name
	ch.species_id = species
	ch.background_id = background
	ch.base_abilities = abil
	for i in n:
		ch.add_level(cid, -1, true)   # the starting party was handed to you, not played up
	# Human: two languages, a skill, and an origin feat.
	ch.decide("language-choice:species:human:0", {"type": "language-choice", "languages": ["elvish", "dwarvish"]})
	ch.decide("feat-choice:species:human:0", {"type": "feat-choice", "featId": "savage-attacker"})
	return ch

static func vera(levels := 3) -> Character:
	# Fighter 3 (Champion) — chain mail + shield, longsword. Improved Critical = crit 19.
	# Interception, not Defense: Defense's +1 AC would push AC to 19 vs the authored 18.
	var ch := _base("vera", "Vera Kord", "human", "soldier",
		{"str": 14, "dex": 12, "con": 13, "int": 10, "wis": 12, "cha": 10}, "fighter", levels)
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	ch.decide("tool-choice:background:soldier:0", {"type": "tool-choice", "tools": ["gaming-set-dice"]})
	ch.decide("language-choice:background:soldier:0", {"type": "language-choice", "languages": ["orc"]})
	ch.decide("skill-choice:species:human:0", {"type": "skill-choice", "skills": ["survival"]})
	ch.decide("skill-choice:class:fighter:0", {"type": "skill-choice", "skills": ["perception", "insight"]})
	ch.decide("fighting-style-choice:class:fighter:0", {"type": "fighting-style-choice", "styles": ["interception"]})
	ch.decide("weapon-mastery-choice:class:fighter:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["longsword", "greatsword", "handaxe"]})
	ch.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "champion"})
	ch.equipped = ["longsword", "chain-mail", "shield"]
	return ch

static func pike(levels := 3) -> Character:
	# Rogue 3 (Thief) — studded leather, shortbow. Sneak Attack 2d6 at rogue 3.
	var ch := _base("pike", "Pike Sallow", "human", "criminal",
		{"str": 10, "dex": 14, "con": 11, "int": 12, "wis": 10, "cha": 12}, "rogue", levels)
	ch.decide("asi:background:criminal:0", {"type": "asi", "allocation": {"dex": 2, "con": 1}})
	ch.decide("tool-choice:background:criminal:0", {"type": "tool-choice", "tools": ["thieves-tools"]})
	ch.decide("language-choice:background:criminal:0", {"type": "language-choice", "languages": ["thieves-cant"]})
	ch.decide("skill-choice:species:human:0", {"type": "skill-choice", "skills": ["perception"]})
	ch.decide("skill-choice:class:rogue:0",
		{"type": "skill-choice", "skills": ["acrobatics", "insight", "investigation", "deception"]})
	ch.decide("expertise-choice:class:rogue:0",
		{"type": "expertise-choice", "skills": ["stealth", "acrobatics"], "tools": []})
	ch.decide("weapon-mastery-choice:class:rogue:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["shortbow", "dagger"]})
	ch.decide("subclass:class:rogue:0", {"type": "subclass", "subclassId": "thief"})
	ch.equipped = ["shortbow", "studded-leather"]
	return ch

static func ilsa(levels := 3) -> Character:
	# Cleric 3 (Light Domain) — chain shirt + shield, mace. Save DC 13, slots 4/2.
	# Light Domain because it grants Burning Hands always-prepared, which is the kit
	# encounter.gd hand-authored for Ilsa.
	var ch := _base("ilsa", "Ilsa Vane", "human", "acolyte",
		{"str": 12, "dex": 12, "con": 12, "int": 10, "wis": 14, "cha": 12}, "cleric", levels)
	ch.decide("asi:background:acolyte:0", {"type": "asi", "allocation": {"wis": 2, "cha": 1}})
	ch.decide("language-choice:background:acolyte:0", {"type": "language-choice", "languages": ["celestial"]})
	ch.decide("skill-choice:species:human:0", {"type": "skill-choice", "skills": ["perception"]})
	ch.decide("skill-choice:class:cleric:0", {"type": "skill-choice", "skills": ["medicine", "persuasion"]})
	ch.decide("feature-choice:class:cleric:0", {"type": "feature-choice", "optionId": "protector"})
	ch.decide("spell-choice:class:cleric:0",
		{"type": "spell-choice", "spellIds": ["sacred-flame", "guidance", "light"]})
	ch.decide("subclass:class:cleric:0", {"type": "subclass", "subclassId": "lightdomain"})
	ch.equipped = ["mace", "chain-shirt", "shield"]
	# healing-word is not in the 146-spell export; cure-wounds is the catalogued stand-in.
	ch.prepared = ["cure-wounds"]
	return ch

static func party() -> Array:
	return [vera(), pike(), ilsa()]

# D6 — the same three at any level, as a RULER rather than as content: core/regions.gd
# measures "what is a level-N party worth" off this trio so a region can be banded in
# levels instead of in budget multipliers. Level 3 is what every other caller wants and
# is what party() still returns; only the ruler asks for anything else.
#
# ponytail: a trio levelled this way leaves the higher-level choices pending (a
# fighter 4's ASI is never decided here), so these sheets are slightly under a
# played character of the same level. That is fine for a ruler — it is the same
# understatement at every level — but do not read party_at(12) as "what a level-12
# party looks like".
static func party_at(levels: int) -> Array:
	var n: int = clampi(levels, 1, 20)
	return [vera(n), pike(n), ilsa(n)]

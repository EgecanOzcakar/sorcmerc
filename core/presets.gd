# The ready-made heroes. Vera, Pike and Ilsa are the three MVP heroes rebuilt as
# real 5.5e builds: encounter.gd's hand-authored numbers are the target, and
# tests/test_rules.gd asserts the sheets match within +/-1 and records the
# differences that are tuning decisions rather than port bugs.
#
# They are two things at once, and the two must not leak into each other (#200):
#
#   * A RULER. party() and party_at() are what core/regions.gd's ref_score, the
#     scaler's REF_SCORE and every balance sweep (tests/sweep_*.gd,
#     tests/test_scaler.gd) build their party from. Those numbers were measured
#     on bare sheets, so what these hand back never carries a personality trait
#     (#176) — a Brave stamped into a sweep's fight would move a measured win
#     rate without anyone re-running the sweep. vera()/pike()/ilsa() stay bare
#     too: plenty of tests and sweeps call them directly.
#
#   * CONTENT. hero(id) is the player's door: the creator's "Load a preset" list
#     (scenes/creator/creator.gd) builds through it, and it hands the same sheet
#     back with its temperament and origin already picked (PERSONALITY). ROSTER
#     is that list, in the order it is shown. Four of the seven — Brakka, Sael,
#     Marit and Dagna — exist only as content: one for each starting class
#     (core/progression.gd STARTING_CLASSES) that had no preset, so a fresh
#     profile, which has the Fighter and the Rogue locked, still has a
#     ready-made hero for every class it can play. Each is built on the
#     standard array before its background's increase, the same budget as a
#     hero made in the creator, so a preset is a shortcut and never an upgrade.
#     None of the four is in party(): the ruler is the trio it was measured as.
#
#   Presets.party()             # the ruler trio at level 3, bare
#   Presets.party_at(n)         # the ruler trio at level n, bare
#   Presets.build(id, levels)   # any preset, bare (no traits)
#   Presets.hero(id, levels)    # any preset as the creator loads it: traits picked
#   Presets.ROSTER              # the ids, in the order the creator lists them
#
# What it does NOT own: whether a preset may be loaded on this profile
# (creator.gd build_lock_note, against core/progression.gd), the level a loaded
# preset starts a run at (creator.gd PRESET_START_LEVEL), or what a trait does
# (core/traits.gd).
extends RefCounted

const Character = preload("res://core/character.gd")
const Traits = preload("res://core/traits.gd")

# #200: what the creator lists, in order — the ruler trio first, then one per
# starting class that had none.
const ROSTER := ["vera", "pike", "ilsa", "brakka", "sael", "marit", "dagna"]

# #200: [temperament, origin] per preset (data/traits.json), stamped only by
# hero(). Picked for who each of them is rather than read off the background's
# default (data/traits.json "defaults"), though most land on it anyway.
const PERSONALITY := {
	"vera": ["brave", "downs-rider"],        # a soldier off the open grass; the soldier's own pair
	"pike": ["cautious", "street-raised"],   # a thief who looks at the floor first; the criminal's own pair
	"ilsa": ["generous", "cave-dweller"],    # the healer who gives the bread away; raised under rock, sworn to the light
	"brakka": ["wrathful", "downs-rider"],   # the berserker: hurt her and she hits back harder
	"sael": ["cautious", "woods-born"],      # the wood-elf hunter who reads the ground before stepping on it
	"marit": ["calm", "night-owl"],          # the evoker who keeps a spell held; studies while the camp sleeps
	"dagna": ["curious", "cave-dweller"],    # opened the box, and a fiend was in it; a deep-hold dwarf
}

static func _base(id: String, name: String, species: String, background: String,
		abil: Dictionary, cid: String, n: int, human_feat := "savage-attacker") -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = name
	ch.species_id = species
	ch.background_id = background
	ch.base_abilities = abil
	# #176: the presets carry no personality traits and are never offered them.
	# They are the ruler Regions.ref_score and every balance sweep stand on, and a
	# trait stamped into those fights would move numbers measured without one.
	# A preset loaded into the creator comes through hero() instead, which picks
	# its temperament and origin (#200).
	ch.traits_offered = true
	for i in n:
		ch.add_level(cid, -1, true)   # the starting party was handed to you, not played up
	if species == "human":
		# Human: two languages, a skill, and an origin feat.
		ch.decide("language-choice:species:human:0", {"type": "language-choice", "languages": ["elvish", "dwarvish"]})
		ch.decide("feat-choice:species:human:0", {"type": "feat-choice", "featId": human_feat})
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

# --- #200: one more per starting class ------------------------------------------
# Content only, never the ruler (see the header). Standard array 15/14/13/12/10/8
# placed the way the class's quick build asks, then the background's +2/+1.

static func brakka(levels := 3) -> Character:
	# Barbarian 3 (Berserker) — greataxe, handaxes to throw, no armor: Unarmored
	# Defense puts her at AC 13 (10 + DEX 1 + CON 2). STR 17, Rage and Frenzy.
	# Farmer for Tough, the origin feat a front-liner wants most.
	var ch := _base("brakka", "Brakka Thorn", "orc", "farmer",
		{"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10}, "barbarian", levels)
	ch.decide("asi:background:farmer:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	ch.decide("language-choice:species:orc:0", {"type": "language-choice", "languages": ["orc", "giant"]})
	ch.decide("language-choice:background:farmer:0", {"type": "language-choice", "languages": ["halfling"]})
	ch.decide("skill-choice:class:barbarian:0", {"type": "skill-choice", "skills": ["athletics", "intimidation"]})
	ch.decide("skill-choice:class:barbarian:1", {"type": "skill-choice", "skills": ["perception"]})
	ch.decide("weapon-mastery-choice:class:barbarian:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["greataxe", "handaxe"]})
	ch.decide("subclass:class:barbarian:0", {"type": "subclass", "subclassId": "berserker"})
	ch.equipped = ["greataxe", "handaxe"]
	return ch

static func sael(levels := 3) -> Character:
	# Ranger 3 (Hunter) — a wood elf with a longbow, the Archery style, Hunter's
	# Mark and Colossus Slayer; Cure Wounds for the company, a shortsword for
	# when they close, studded leather. DEX 17, slots 3.
	var ch := _base("sael", "Sael Ambry", "elf", "guide",
		{"str": 12, "dex": 15, "con": 13, "int": 10, "wis": 14, "cha": 8}, "ranger", levels)
	ch.decide("asi:background:guide:0", {"type": "asi", "allocation": {"dex": 2, "wis": 1}})
	ch.decide("lineage-choice:species:elf:0", {"type": "lineage-choice", "lineageId": "wood-elf"})
	ch.decide("language-choice:species:elf:0", {"type": "language-choice", "languages": ["elvish", "sylvan"]})
	ch.decide("language-choice:background:guide:0", {"type": "language-choice", "languages": ["goblin"]})
	ch.decide("skill-choice:species:elf:0", {"type": "skill-choice", "skills": ["perception"]})
	ch.decide("skill-choice:class:ranger:0",
		{"type": "skill-choice", "skills": ["athletics", "nature", "animalhandling"]})
	ch.decide("fighting-style-choice:class:ranger:0", {"type": "fighting-style-choice", "styles": ["archery"]})
	ch.decide("weapon-mastery-choice:class:ranger:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["longbow", "shortsword"]})
	ch.decide("spell-choice:class:ranger:0",
		{"type": "spell-choice", "spellIds": ["hunters-mark", "cure-wounds"]})
	ch.decide("subclass:class:ranger:0", {"type": "subclass", "subclassId": "hunter"})
	ch.decide("feature-choice:subclass:hunter:0", {"type": "feature-choice", "optionId": "colossus-slayer"})
	ch.equipped = ["longbow", "shortsword", "studded-leather"]
	return ch

static func marit(levels := 3) -> Character:
	# Wizard 3 (Evoker) — INT 17, save DC 13, slots 4/2. Fire Bolt and Ray of
	# Frost at range, Shocking Grasp to step away, Magic Missile and Burning
	# Hands to spend slots on, Shield to live. Alert rather than the human
	# default Savage Attacker: a wizard wants to act first, not to hit harder.
	var ch := _base("marit", "Marit Quell", "human", "sage",
		{"str": 10, "dex": 13, "con": 14, "int": 15, "wis": 12, "cha": 8}, "wizard", levels, "alert")
	ch.decide("asi:background:sage:0", {"type": "asi", "allocation": {"int": 2, "con": 1}})
	ch.decide("language-choice:background:sage:0", {"type": "language-choice", "languages": ["draconic"]})
	ch.decide("skill-choice:species:human:0", {"type": "skill-choice", "skills": ["perception"]})
	ch.decide("skill-choice:class:wizard:0", {"type": "skill-choice", "skills": ["investigation", "insight"]})
	ch.decide("spell-choice:class:wizard:0",
		{"type": "spell-choice", "spellIds": ["fire-bolt", "ray-of-frost", "shocking-grasp"]})
	ch.decide("spell-choice:class:wizard:1", {"type": "spell-choice",
		"spellIds": ["magic-missile", "shield", "burning-hands", "sleep", "chromatic-orb", "detect-magic"]})
	ch.decide("subclass:class:wizard:0", {"type": "subclass", "subclassId": "evoker"})
	ch.equipped = ["dagger", "light-crossbow"]
	return ch

static func dagna(levels := 3) -> Character:
	# Warlock 3 (Fiend Patron) — CHA 17, Eldritch Blast, Pact Magic 2 slots of
	# 2nd level (short-rest refilled), and the Fiend's always-prepared list on
	# top. Pact of the Tome for the extra cantrips. Leather and a light crossbow.
	var ch := _base("dagna", "Dagna Holt", "dwarf", "charlatan",
		{"str": 8, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 15}, "warlock", levels)
	ch.decide("asi:background:charlatan:0", {"type": "asi", "allocation": {"cha": 2, "con": 1}})
	ch.decide("language-choice:species:dwarf:0", {"type": "language-choice", "languages": ["dwarvish", "undercommon"]})
	ch.decide("language-choice:background:charlatan:0", {"type": "language-choice", "languages": ["infernal"]})
	ch.decide("skill-choice:feat:skilled:0",
		{"type": "skill-choice", "skills": ["perception", "persuasion", "stealth"]})
	ch.decide("skill-choice:class:warlock:0", {"type": "skill-choice", "skills": ["arcana", "intimidation"]})
	ch.decide("spell-choice:class:warlock:0",
		{"type": "spell-choice", "spellIds": ["eldritch-blast", "mind-sliver"]})
	ch.decide("spell-choice:class:warlock:1",
		{"type": "spell-choice", "spellIds": ["hellish-rebuke", "dissonant-whispers"]})
	ch.decide("feature-choice:class:warlock:0", {"type": "feature-choice", "optionId": "tome"})
	ch.decide("subclass:class:warlock:0", {"type": "subclass", "subclassId": "fiendpatron"})
	ch.equipped = ["light-crossbow", "leather"]
	return ch

# #200: any preset by id, bare — no personality traits, exactly what vera() and
# the rest return. An unknown id is null.
static func build(which: String, levels := 3) -> Character:
	match which:
		"vera": return vera(levels)
		"pike": return pike(levels)
		"ilsa": return ilsa(levels)
		"brakka": return brakka(levels)
		"sael": return sael(levels)
		"marit": return marit(levels)
		"dagna": return dagna(levels)
	return null

# #200: the preset as the player gets it — the same build, with its temperament
# and origin picked. Only the creator comes through here; nothing that measures
# a fight may (see the header).
static func hero(which: String, levels := 3) -> Character:
	var ch := build(which, levels)
	if ch == null:
		return null
	var pick: Array = PERSONALITY.get(which, [])
	for i in mini(pick.size(), Traits.FAMILIES.size()):
		Traits.set_family(ch, Traits.FAMILIES[i], String(pick[i]), "born to it")
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

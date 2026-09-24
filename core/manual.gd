# The Field Manual: what the rules engine does, in the player's language. One
# page per class and one per fight mechanic, as BBCode for a RichTextLabel.
# Numbers come off the engine's own constants and data files wherever they
# exist (classes.json, subclasses.json, effects/conditions.json, adapter.gd,
# combat.gd) so a retune can't leave the manual lying; only the prose that
# explains *why* is hand-written. scenes/manual/manual.gd draws and searches it.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const World = preload("res://core/world.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const Encounter = preload("res://core/encounter.gd")

# Class blurbs — the one thing the export doesn't carry. Two lines each: what
# the class is for on this board, and the button you'll press most.
const CLASS_BLURB := {
	"barbarian": "Front line. Rage (a bonus action) halves the bludgeoning, piercing and slashing damage you take and adds to every STR hit while it lasts; Reckless Attack trades advantage for advantage against you. Wants to be adjacent to the worst thing on the board.",
	"bard": "A caster who makes the rest of the party better. Bardic Inspiration hands an ally a die to add to their next roll; the spell list leans on control (Hideous Laughter, Dissonant Whispers) rather than damage.",
	"cleric": "Armour, a mace and the healing. Cure Wounds brings a downed ally back up; Sacred Flame is the ranged option (DEX save, no attack roll, ignores cover). Domain picks the flavour — Light adds Burning Hands.",
	"druid": "Nature's caster: Thorn Whip drags an enemy 10 ft closer, Produce Flame is the ranged cantrip, and the higher levels are area control. Wild Shape is not modelled on this board.",
	"fighter": "The most swings per turn in the game. Second Wind heals as a bonus action, Action Surge buys a second action once per rest, and Extra Attack at 5 doubles the Attack action. Fighting Style and Weapon Mastery choices decide how the swings land.",
	"monk": "Unarmoured, fast, and hits with everything. Martial Arts makes the unarmed strike a real weapon and adds a bonus-action strike; Flurry of Blows spends a Focus point for two. Wants to be moving.",
	"paladin": "Armoured caster. Lay on Hands is a pool of healing spent in any amounts; Divine Smite spends a spell slot on a hit for radiant dice. The oath comes at level 3.",
	"ranger": "Ranged or two-weapon skirmisher. Hunter's Mark (bonus action, concentration) adds a d6 to every hit on one target; Favored Enemy keeps it free. Archery style is +2 to hit with every bow.",
	"rogue": "One big hit a turn. Sneak Attack adds dice whenever you have advantage or an ally is adjacent to the target — a shortbow from behind the fighter does it every round. Cunning Action makes Dash, Disengage and Hide bonus actions.",
	"sorcerer": "Raw arcane damage, fewer spells known than a wizard. Innate Sorcery (a bonus action, twice a day) sharpens every spell for a minute: +1 to the save DC and advantage on spell attacks. From level 2 Font of Magic burns a slot into sorcery points for free, and a bonus action turns points back into a slot. Metamagic arms your next spell for points: Quickened (an action spell on the bonus action), Twinned (one more target), Careful (spare your friends), Subtle (no Counterspell) and Seeking (reroll a miss) work on this board; the rest of the list does not yet.",
	"warlock": "Two slots that come back on a short rest, and Eldritch Blast every other turn. Hex (bonus action, concentration) adds a d6 per hit; the patron picks the tricks.",
	"wizard": "The widest spell list and the least HP. Fire Bolt at range, Sleep and Web for control, Fireball when it lands. Arcane Recovery gets slots back on a short rest.",
}

# Weapon mastery (2024 rules), as combat.gd's _mastery_rider actually plays them.
const MASTERY := {
	"cleave": "On a hit, one free swing at a second enemy adjacent to you, weapon dice only.",
	"graze": "On a miss, the target still takes your ability modifier in damage.",
	"nick": "Your off-hand attack is part of the Attack action instead of costing the bonus action.",
	"push": "On a hit, shove the target 10 ft (2 hexes) straight back — into a hazard, if one is there.",
	"sap": "On a hit, the target has disadvantage on its next attack roll.",
	"slow": "On a hit, the target loses 10 ft of speed until your next turn.",
	"topple": "On a hit, the target makes a CON save (DC 8 + your attack bonus) or falls prone.",
	"vex": "On a hit, you have advantage on your next attack against the same target.",
}

# --- the pages -------------------------------------------------------------

# [{id, section, title, tags, body}] — body is BBCode. Cached after first build.
static var _pages: Array = []

static func pages() -> Array:
	if _pages.is_empty():
		_pages = _mechanics() + _classes()
	return _pages

static func page(id: String) -> Dictionary:
	for p in pages():
		if p["id"] == id:
			return p
	return {}

# Pages whose title, tags or body contain every word of `query` (case-insensitive).
# An empty query is every page. Result order is the manual's own order.
static func search(query: String) -> Array:
	var words: Array = query.to_lower().split(" ", false)
	if words.is_empty():
		return pages()
	var out: Array = []
	for p in pages():
		var hay: String = ("%s %s %s" % [p["title"], " ".join(p["tags"]), _plain(p["body"])]).to_lower()
		if words.all(func(w): return hay.contains(w)):
			out.append(p)
	return out

# The first line of the body that mentions the query, for the result list.
static func snippet(p: Dictionary, query: String) -> String:
	var q := query.to_lower().strip_edges()
	if q == "":
		return ""
	var w: String = q.split(" ", false)[0]
	var plain := _plain(p["body"])
	var at := plain.to_lower().find(w)
	if at < 0:
		return ""
	# a window around the match, cut on word boundaries
	var start := maxi(0, at - 36)
	var stop := mini(plain.length(), at + w.length() + 54)
	var s := plain.substr(start, stop - start).replace("\n", " ")
	if start > 0:
		s = "…" + s.substr(s.find(" ") + 1)
	if stop < plain.length():
		s = s.substr(0, s.rfind(" ")) + "…"
	return s

# BBCode -> the words in it, for matching.
static func _plain(bb: String) -> String:
	var re := RegEx.new()
	re.compile("\\[/?[a-z_]+(=[^\\]]*)?\\]")
	return re.sub(bb, "", true)

# --- mechanics --------------------------------------------------------------

static func _h(s: String) -> String:
	return "[b][color=#c9a45a]%s[/color][/b]\n" % s

# One item of a list: the name lit, the rest plain, one per line. The ledger's
# "· " rather than [ul] — the same mark the creator's pending list uses.
static func _li(name: String, rest: String) -> String:
	return "· [b]%s[/b] — %s\n" % [name, rest]

# The list as a block: [indent] carries the wrapped lines in with the bullet.
static func _list(items: Array) -> String:
	return "[indent]" + "".join(items) + "[/indent]"

static func _mechanics() -> Array:
	var ft := Adapter.FT_PER_HEX
	var cap := Adapter.RANGE_CAP
	var out: Array = []
	out.append({"id": "turn", "section": "Fighting", "title": "Your turn",
		"tags": ["action", "bonus action", "reaction", "movement", "economy", "dash", "disengage", "dodge", "help", "hide", "shove", "end turn"],
		"body": _h("One action, one bonus action, one reaction, and your speed in movement.") +
		"Spend them in any order. The action line under the board shows what's left; when the action, bonus and movement are all gone the turn ends itself.\n\n" +
		"[b]Action[/b] — Attack (every swing the Attack action buys), cast a spell, or one of the basics:\n" +
		_list([_li("Dash", "another full move"),
			_li("Disengage", "leave reach without provoking"),
			_li("Dodge", "attacks against you have disadvantage until your next turn"),
			_li("Help", "an ally's next attack has advantage; on a downed ally it's First Aid — up at 1 HP"),
			_li("Hide", "Stealth vs the enemies' passive Perception; unseen means untargetable, and advantage on your next attack"),
			_li("Shove", "Athletics contest to push 5 ft or knock prone — into a brazier, if one's handy")]) + "\n" +
		"[b]Bonus action[/b] — only what a feature or spell names as one: Second Wind, Rage, Cunning Action, Healing Word, a Nimble Escape. Casting a bonus-action spell means the only other spell you can cast this turn is a cantrip.\n\n" +
		"[b]Reaction[/b] — one per round, and never a button. It comes back at the start of your turn.\n" +
		_list([_li("The free ones fire by themselves", "the moment something triggers them, on your turn or anyone else's: an opportunity attack when a foe walks out of your reach, Uncanny Dodge halving a hit."),
			_li("The ones that spend a spell slot stop the fight and ask you first", "Hellish Rebuke burning whoever just swung at you; [b]Counterspell[/b] unravelling an enemy spell mid-cast (a CON save at DC 10 + the spell's level; it costs you the slot either way, and a countered caster keeps theirs)."),
			_li("The question comes just before the roll", "so it names the hit chance you are deciding against, and a swing that misses costs you nothing. Turn the asking off under Settings if you would rather the engine always spend it.")]) + "\n" +
		"[b]Movement[/b] — %d ft per hex, so 30 ft of speed is %d hexes. Rough ground costs double. You can walk through allies but not stop on them; you can never pass through an enemy." % [ft, Adapter.hexes(30)]})
	out.append({"id": "attack", "section": "Fighting", "title": "Attacking",
		"tags": ["attack roll", "d20", "armor class", "ac", "critical", "crit", "advantage", "disadvantage", "to hit", "hit chance", "natural 20", "natural 1", "damage"],
		"body": _h("d20 + your attack bonus against the target's AC. Meet it or beat it.") +
		"A natural 20 always hits and is a [b]critical[/b]: every damage die is rolled twice (modifiers are not doubled). A natural 1 always misses. Champions crit on a 19 too.\n\n" +
		"[b]Advantage[/b] rolls two d20 and keeps the higher; [b]disadvantage[/b] keeps the lower. They never stack: any number of sources of each cancel to a single straight roll. The aiming chip on the board shows the resulting hit chance before you commit.\n\n" +
		"Sources of advantage you'll see most: attacking a prone target in melee, an unseen (hidden) attacker, Help, Reckless Attack, a Vex follow-up. Disadvantage: shooting with an enemy adjacent to you, shooting a prone target, being Sapped, attacking while poisoned or frightened, a Dodging target.\n\n" +
		"[b]Damage[/b] is the weapon's dice plus the ability modifier, plus riders: Sneak Attack, Rage, Hunter's Mark, a mastery. Resistance halves it. HP never goes above maximum, and healing a downed ally starts from 0."})
	out.append({"id": "moving", "section": "Fighting", "title": "Movement and opportunity attacks",
		"tags": ["opportunity attack", "oa", "provoke", "disengage", "reach", "rough terrain", "speed", "prone", "stand up", "frightened"],
		"body": _h("Leaving an enemy's reach lets it swing at you for free.") +
		"On your turn the blue hexes are everywhere you can still reach; the ⚠ ones are hexes whose path steps out of some enemy's reach. Every enemy you leave gets one [b]opportunity attack[/b] — a melee swing, rolled from the hex you were on when you stepped away, spending its reaction. An archer gets an unarmed punch, not a shot.\n\n" +
		"[b]Disengage[/b] (an action, or a bonus action for rogues and goblins) makes the whole move safe. So does being [b]hidden[/b]: nobody reacts to what they can't see. Dropping to 0 HP mid-walk leaves you where you were hit.\n\n" +
		"[b]Prone[/b] costs half your movement to stand (done automatically at the start of your turn). [b]Frightened[/b] means you can't end a step closer to what scares you. [b]Grappled[/b] or [b]restrained[/b] is speed 0.\n\n" +
		"Melee reach is %d hex. The Slow mastery and a few spells take 10 ft (%d hexes) off a target's speed until your next turn." % [Encounter.REACH_MELEE, Adapter.hexes(10)]})
	out.append({"id": "range", "section": "Fighting", "title": "Range, cover and shooting",
		"tags": ["range", "ranged", "bow", "crossbow", "thrown", "javelin", "cover", "half cover", "point blank", "adjacent", "line of sight", "hexes", "feet", "distance"],
		"body": _h("%d ft to a hex; every range is capped at %d hexes on this board." % [ft, cap]) +
		"A weapon's normal range in feet becomes hexes (30 ft = %d, 60 ft = %d, anything from %d ft up = %d). Spells are the same: 30-ft spells reach %d hexes, everything 60 ft and over reaches %d. Touch spells and melee are 1.\n\n" % [Adapter.hexes(30), mini(cap, Adapter.hexes(60)), cap * ft, cap, Adapter.hexes(30), mini(cap, Adapter.hexes(60))] +
		"[b]Point-blank[/b]: a ranged attack or spell attack made with an enemy adjacent to you has disadvantage. Step away first — and eat the opportunity attack — or let the fighter handle what's in your face. Enemy archers do exactly this.\n\n" +
		"[b]Solid props[/b] — trees, standing stones, pillars, ice columns — block movement and line of sight: nothing is aimed past one. [b]Stacked stalls, shelves and stake walls[/b] do the same until somebody smashes them (one action from beside it, or any blast that catches it).\n\n" +
		"[b]Half cover[/b] (reed banks — the board marks them) gives the occupant +2 AC and +2 on every saving throw. Sacred Flame and a few others ignore it. Reeds are tall, too: you can see into them and out of them, but not across.\n\n" +
		"[b]Thrown weapons[/b] — javelin, dagger, handaxe, spear, trident — appear twice in the wield toggle: in hand as melee, or thrown as a ranged attack at their listed range with the same STR/DEX bonus (no Archery bonus).\n\n" +
		"[b]Cones[/b] (Burning Hands, Fear) are aimed at a direction, not a target, and catch allies too. A 15-ft cone is a %d-hex wedge." % Adapter.area_hexes(15)})
	out.append({"id": "spells", "section": "Fighting", "title": "Spells, slots and concentration",
		"tags": ["spell", "slot", "cantrip", "concentration", "save", "dc", "spell attack", "upcast", "scorching ray", "hold person", "ritual"],
		"body": _h("Cantrips are free and scale with your level; everything else spends a slot.") +
		"The pips on your actor line are slots by level. A levelled spell can be [b]upcast[/b] from a higher slot (★ in the menu) for more dice, more rays, or more targets. Slots come back on a long rest; warlocks get theirs back on a short rest.\n\n" +
		"[b]Spell attacks[/b] (Fire Bolt, Guiding Bolt, Scorching Ray's three rays) roll to hit like a weapon. [b]Save spells[/b] (Sacred Flame, Hold Person, Burning Hands) make the target roll against your save DC — 8 + proficiency + casting ability — and the chip shows their chance to fail. Half-on-save spells still do half damage on a success.\n\n" +
		"[b]Concentration[/b]: one at a time. Casting a second concentration spell drops the first. Taking damage while concentrating forces a CON save at DC 10 or half the damage, whichever is higher; fail and the spell ends. Hunter's Mark, Hex, Web, Hold Person, Hideous Laughter, Moonbeam all concentrate.\n\n" +
		"A condition a spell inflicts (prone and incapacitated from Hideous Laughter, paralyzed from Hold Person) lasts until the target's next turn."})
	out.append({"id": "conditions", "section": "Fighting", "title": "Conditions",
		"tags": ["condition", "prone", "poisoned", "frightened", "restrained", "paralyzed", "unconscious", "blinded", "invisible", "grappled", "incapacitated", "stunned", "petrified", "charmed", "exhaustion", "status"],
		"body": _h("Every condition the engine knows, and exactly what it does.") + _conditions_body()})
	out.append({"id": "dying", "section": "Fighting", "title": "Dropping to 0 HP",
		"tags": ["death", "dying", "down", "death save", "death saving throw", "unconscious", "stable", "revive", "first aid", "healing word", "cure wounds", "dead", "mercy"],
		"body": _h("At 0 HP you're down and unconscious, and the dice decide from there.") +
		"At the start of each of your turns you roll a [b]death save[/b]: 10 or higher is a success, lower is a failure. A natural 20 puts you back on your feet at 1 HP; a natural 1 counts as two failures. [b]Three failures and you're dead[/b]; three successes and you're stable — still down, no more rolling, until a hit knocks you off it and the rolling starts again. A stable hero comes round at 1 HP when the fight ends.\n\n" +
		"Being [b]unconscious[/b] means attacks against you have advantage, you fail STR and DEX saves automatically, and any melee hit from reach is a critical. Damage while down is a failed save — a crit is two. Enemies won't finish a downed body while they can reach someone standing (the mercy rule), but a creature with nothing else to hit will.\n\n" +
		"Any healing brings you back up: Cure Wounds, Healing Word, a potion, or an ally's [b]Help[/b] action (First Aid: up at 1 HP, no roll). Healing a corpse does nothing.\n\n" +
		"Fights end when one side is entirely down or dead, or after %d rounds." % Combat.MAX_ROUNDS})
	out.append({"id": "rest", "section": "Fighting", "title": "Rests and resources",
		"tags": ["rest", "short rest", "long rest", "second wind", "action surge", "pool", "uses", "camp", "recover", "heal"],
		"body": _h("Short rests patch you up; long rests reset everything.") +
		"A [b]short rest[/b] restores half of your missing HP (rounded up) and every feature that recharges on one — Second Wind, Action Surge, Channel Divinity, warlock slots, a wizard's Arcane Recovery. A [b]long rest[/b] is full HP, all spell slots, all pools, and clears exhaustion by one level.\n\n" +
		"In a campaign run, rests are limited per run and taken at rest nodes; in the world, a settlement bed or a camp kit away from one. Feature uses show as pips on your actor line; a spent pip is greyed until the rest that brings it back."})
	out.append({"id": "night", "section": "Fighting", "title": "Night and darkness",
		"tags": ["night", "dark", "darkness", "darkvision", "torch", "light", "lit", "unseen", "ambush", "watch", "sight"],
		"body": _h("After dark the world closes in, and a fight is fought by torchlight.") +
		"On the map the party sees %d%% as far at night, and a hostile band can be on you before anyone can choose how to meet it — whoever is best at Perception or Survival rolls to hear them coming (DC %d); miss it and they take the first round.\n\n" % [int(World.NIGHT_SIGHT * 100), WorldCamp.AMBUSH_DC] +
		"A fight begun at night: a hex is [b]lit[/b] only within %d hexes of a torch, brazier or campfire, or within %d of a standing hero (you carry a torch). Anyone in an unlit hex is [b]unseen[/b] — attacks against them have disadvantage and their own attacks have advantage — unless the attacker has [b]darkvision[/b], which most monsters and several species do. Hiding in an unlit hex gets +%d on the Stealth roll." % [Combat.LIGHT_RADIUS, Combat.CARRIED_LIGHT, Combat.DARK_HIDE_BONUS]})
	out.append({"id": "mastery", "section": "Fighting", "title": "Weapon mastery",
		"tags": ["mastery", "weapon mastery", "cleave", "graze", "nick", "push", "sap", "slow", "topple", "vex", "fighter", "barbarian", "rogue", "ranger", "paladin"],
		"body": _h("Martial classes pick weapons whose special rider fires on every hit (or miss).") + _mastery_body()})
	return out

static func _conditions_body() -> String:
	var conds: Dictionary = Catalog.all("effects/conditions.json")
	var lines: Array = []
	var ids: Array = conds.keys()
	ids.sort()
	for id in ids:
		if String(id).begins_with("_"):
			continue
		var e: Dictionary = conds[id]
		var bits: Array = []
		var ag = e.get("attacks_against", "")
		if ag is Dictionary:
			bits.append("melee attacks against you have %s, ranged %s" % [_advd(ag.get("melee", "")), _advd(ag.get("ranged", ""))])
		elif ag != "":
			bits.append("attacks against you have %s" % _advd(ag))
		if e.get("own_attacks", "") != "":
			bits.append("your attacks have %s" % _advd(e["own_attacks"]))
		if e.has("speed") and int(e["speed"]) == 0:
			bits.append("speed 0")
		if e.get("no_action", false):
			bits.append("no actions" + (", bonus actions" if e.get("no_bonus", false) else "") + (" or reactions" if e.get("no_reaction", false) else ""))
		if e.has("auto_fail_saves"):
			bits.append("auto-fail %s saves" % " and ".join(e["auto_fail_saves"]).to_upper())
		if int(e.get("auto_crit_within_ft", 0)) > 0:
			bits.append("any melee hit from within %d ft is a critical" % int(e["auto_crit_within_ft"]))
		if e.get("resist_all", false):
			bits.append("resistance to all damage")
		if e.has("saves") and e["saves"] is Dictionary:
			for k in e["saves"]:
				bits.append("%s saves have %s" % [String(k).to_upper(), _advd(e["saves"][k])])
		if e.get("stand_costs", "") == "half_move":
			bits.append("standing up costs half your movement")
		if e.has("cannot_approach_source"):
			bits.append("you can't move closer to the source")
		if e.has("cannot_target_source"):
			bits.append("you can't attack the source")
		if e.has("per_level"):
			bits.append("per level: −%d on every d20 and −%d ft speed, up to level %d" % [
				int(e["per_level"].get("d20_penalty", 0)), int(e["per_level"].get("speed_penalty_ft", 0)), int(e.get("max_level", 6))])
		if e.has("auto_fail"):
			bits.append("auto-fail anything that needs %s" % " or ".join(e["auto_fail"]))
		lines.append("[b]%s[/b] — %s." % [String(id).capitalize(), "; ".join(bits) if not bits.is_empty() else "no mechanical effect on this board"])
	return "\n".join(lines)

static func _advd(s: String) -> String:
	return "advantage" if s == "adv" else ("disadvantage" if s == "dis" else "no change")

static func _mastery_body() -> String:
	var by_m := {}
	for w in Catalog.all("weapons.json"):
		var m := String(w.get("mastery", "") if w.get("mastery") != null else "")
		if m != "":
			by_m[m] = by_m.get(m, []) + [String(w["name"])]
	var lines: Array = []
	var ks: Array = MASTERY.keys()
	ks.sort()
	for m in ks:
		lines.append("[b]%s[/b] — %s\n[color=#8a7f6e]%s[/color]" % [String(m).capitalize(), MASTERY[m], ", ".join(by_m.get(m, []))])
	return "\n\n".join(lines) + "\n\nA rider only fires from a weapon you've chosen mastery in (the creator's Weapon Mastery pick); anyone else swings it plain."

# --- classes ----------------------------------------------------------------

# The level-table entries that are a choice rather than a named feature.
const LEVEL_LABELS := {
	"subclass": "Subclass", "spellcasting": "Spellcasting", "fighting-style-choice": "Fighting Style",
	"weapon-mastery-choice": "Weapon Mastery", "expertise-choice": "Expertise", "asi": "Ability Score Improvement",
	"feature-choice": "Feature choice", "spell-choice": "Spells",
}

static func _classes() -> Array:
	var out: Array = []
	var subs: Array = Catalog.all("subclasses.json")
	for c in Catalog.all("classes.json"):
		var id := String(c["id"])
		var body := _h(CLASS_BLURB.get(id, ""))
		body += "[b]Hit die[/b] d%d   [b]Primary[/b] %s   [b]Saves[/b] %s\n" % [
			int(c["hitDie"]), String(c["primaryAbility"]).to_upper(), " & ".join(c["savingThrows"]).to_upper()]
		body += "[b]Armour[/b] %s   [b]Weapons[/b] %s\n" % [
			", ".join(c["armorProficiencies"]) if not c["armorProficiencies"].is_empty() else "none",
			", ".join(c["weaponProficiencies"])]
		if c.get("spellcastingAbility") != null:
			body += "[b]Casts with[/b] %s" % String(c["spellcastingAbility"]).to_upper()
			var slots: Array = c.get("slots", c.get("spellSlots", []))
			if slots.size() >= 3 and not (slots[2] is Array and slots[2].is_empty()):
				body += "   [b]Slots at 3[/b] %s" % "/".join(Array(slots[2]).map(func(n): return str(int(n))))
			body += "\n"
		body += "\n[b]Features by level[/b]\n"
		var levels: Array = c.get("levels", [])
		for i in mini(levels.size(), 5):
			var feats: Array = []
			for e in levels[i]:
				var kind := String(e.get("type", ""))
				if kind == "feature":
					feats.append(Effects.verb_label(String(e["feature"]["id"])))
				elif LEVEL_LABELS.has(kind):
					feats.append(LEVEL_LABELS[kind])
			if not feats.is_empty():
				body += "%d — %s\n" % [i + 1, ", ".join(feats)]
		var mine: Array = subs.filter(func(s): return String(s.get("classId", "")) == id)
		if not mine.is_empty():
			body += "\n[b]Subclasses[/b]\n"
			for s in mine:
				var d := String(s.get("description", ""))
				var cut := d.find(". ")
				body += "[b]%s[/b] — %s\n" % [s["name"], d.substr(0, cut + 1) if cut > 0 else d]
		out.append({"id": "class-" + id, "section": "Classes", "title": String(c["name"]),
			"tags": [id, "class"] + Array(c["savingThrows"]), "body": body})
	return out

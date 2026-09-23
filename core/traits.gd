# Personality traits (#176) — who a hero is, and (later) what the road has done
# to them. The design is docs/superpowers/specs/2026-09-23-traits-design.md; the
# rows are data/traits.json. This is its step 1: the model, the pick, the save
# shape, and the half of a trait that can be decided before the first roll of a
# fight — where the fight is (biome, board, night, band, site) — stamped onto
# the hero's Combatant as a status the engine already sums.
#
#   Traits.row("marsh-bred")                  # the data row, {} for an unknown id
#   Traits.ids(ch)                            # ["brave", "marsh-bred"]
#   Traits.of(ch, "origin")                   # "marsh-bred", or ""
#   Traits.set_family(ch, "temperament", id)  # replaces that family's trait
#   Traits.default_for(background_id, family) # what a background starts with
#   Traits.needs_offer(ch)                    # an older hero who was never asked
#   Traits.effect_lines(id)                   # [{text, live}] for a page to print
#   Traits.stamp(combatants, board)           # Encounter.build, once, before Combat rolls initiative
#   Traits.roll(c, "to_hit", cb, target, dtype) # step 2: a term decided at the roll, {n, who}
#   Traits.save_mode(c, cb, ["frightened"])   # step 2: advantage on a save against a condition
#
# What it owns: which traits a hero has, what each one says, which of their
# effects this build applies, the fight-start stamp and the per-roll terms
# core/combat.gd asks for (step 2). What it does NOT own:
# the pages that show them (scenes/creator, scenes/profile, scenes/party,
# scenes/combat_card.gd), where a fight is (scenes/world/world.gd stamps
# spec["where"]), when a roll asks (core/combat.gd's four hooks: to_hit_bonus,
# effective_ac, _saving_throw, the damage sink), the road's checks (step 4), or
# earning one (step 3, which opens scenes/world/trait_moment.gd).
#
# State lives on the character, not the party (spec §2): ch.traits is
# [{"id", "why"}] and ch.traits_offered is whether an older hero has been asked
# once. Both go through core/character_save.gd, so the barracks, presets, the
# world save, the campaign save and co-op all carry them.
extends RefCounted

const Hex = preload("res://core/hex.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const PATH := "res://data/traits.json"
const FAMILIES := ["temperament", "origin"]   # the two a hero picks; marks, banes and wounds are earned (step 3)

# Bounded accuracy: however many traits agree, one number moves by at most this
# much in a fight (spec §3) — the fight-start stamp and the roll together.
# MEASURED 2026-09-23 (tests/sweep_traits.gd, 300 seeds, the preset trio all
# holding one trait, normal): baseline 88.7% win; no trait moves it more than
# +3.0 (Craven 91.7%, Calm and Night-owl 91.3%, the rest +0..+1). Calm's and
# Night-owl's rows are identical — the −1 initiative both carry by day only
# reshuffles the fight — which puts the seed noise floor at about 3 points, so
# at ±2 nothing here stands out of it. Re-run the sweep when CAP or a number in
# data/traits.json moves.
const CAP := 2

# The half of `when` that is known before the first roll: stamped once, at
# fight start (step 1).
const FIGHT_START_WHEN := ["biome", "board", "night", "band", "site"]
# ...and the half only the roll itself knows (step 2): the hero's own state,
# the round, who is on the other end of it, and what the blow is made of.
#   bloodied     under half HP                  first_round   round 1
#   alone        no conscious ally beside them  vs_faction    the other side's bestiary faction
#   vs_type      its bestiary type              dtype_in      the damage type coming in
#   dtype_out    the damage type of their own attack
#   guarding     a downed ally beside them      vs_size       the other side's size (step 3: Giant-killer)
#   vs_deals     what the other side's blows are made of (its damage type, or
#                what it is immune to — a fire giant swings a sword and is fire)
const ROLL_WHEN := ["bloodied", "first_round", "alone", "vs_faction", "vs_type", "dtype_in", "dtype_out",
	"guarding", "vs_size", "vs_deals"]
# The `gives` this build lands in a fight. Everything else is shown on the
# pages, marked not yet in play, so the player knows it is coming and never
# mistakes a line of text for a bonus they have. ac/to_hit/save/initiative
# with a fight-start `when` are stamped; with a roll `when` they are asked at
# the roll; damage, ward and save_adv are always asked at the roll.
# Step 3 adds speed (a Maimed hero's lost hex, stamped), death_save_adv (Hard
# to kill, asked by the death save), and the four a hardship's save reads —
# hardship_adv/_dis (Brave, Craven on a fear save), hardship_bonus (Calm's +2
# WIS) and grudge (Wrathful turning a haunting into a grudge).
# Step 4 adds the road's and the company's: skill, travel, forage, gold,
# sale_price, opinion, opinion_drift.
const LIVE_GIVES := ["ac", "to_hit", "save", "initiative", "damage", "ward", "save_adv",
	"speed", "death_save_adv", "hardship_adv", "hardship_dis", "hardship_bonus", "grudge",
	"skill", "travel", "forage", "gold", "sale_price", "opinion", "opinion_drift"]
const STAMPED := ["ac", "to_hit", "save", "initiative"]

const STATUS := "traits"   # the one status dict every live term is summed into

const BIOME_PHRASE := {"marsh": "in the marsh", "woods": "in the woods", "downs": "on the downs"}
const SITE_PHRASE := {"road": "on the road", "lair": "in a lair", "camp": "at camp", "town": "in town"}
const SKILL_NAME := {"avoid": "slipping past a band", "persuasion": "Persuasion", "survival": "Survival",
	"perception": "Perception", "stealth": "Stealth", "investigation": "Investigation"}
const ABIL := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}

static var _data := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var txt := FileAccess.get_file_as_string(PATH)
		var d = JSON.parse_string(txt) if txt != "" else null
		_data = d if d is Dictionary else {"traits": {}, "defaults": {}}
	return _data


static func all() -> Dictionary:
	return _load().get("traits", {})


# An id may be instanced, "grudge@goblinoid": the base row with its `$arg`
# tokens filled with the faction (spec §6's Grudge: <faction>, a bane). Built
# once per id and kept, so the hot path — the fight asks row() on every roll —
# is one dictionary lookup like any other trait.
static var _instanced := {}

static func row(id: String) -> Dictionary:
	if not "@" in id:
		return all().get(id, {})
	if not _instanced.has(id):
		var base: Dictionary = all().get(id.get_slice("@", 0), {})
		_instanced[id] = {} if base.is_empty() else _fill(base, id.get_slice("@", 1))
	return _instanced[id]


static func base_of(id: String) -> String:
	return id.get_slice("@", 0)


# Plural and singular for the handful of factions whose name is not "+s".
const FACTION_PLURAL := {"goblinoid": "goblins", "humanoid": "people", "undead": "the dead",
	"townsfolk": "townsfolk", "lizardfolk": "lizardfolk", "merfolk": "merfolk", "fey": "fey",
	"drow": "drow", "swarm": "swarms", "tribal": "tribesfolk", "bandit": "bandits",
	# the three the "+s" default gets wrong — tests/sweep_traits_earn.gd's run
	# printed "Haunted by monstrositys"
	"monstrosity": "monstrosities", "duergar": "duergar", "sahuagin": "sahuagin"}
const FACTION_ONE := {"goblinoid": "goblin", "humanoid": "person", "undead": "undead",
	"townsfolk": "townsfolk", "tribal": "tribal"}

static func faction_name(f: String, plural := true) -> String:
	if plural:
		return String(FACTION_PLURAL.get(f, f + "s"))
	return String(FACTION_ONE.get(f, f))


static func _fill(v, arg: String):
	if v is String:
		return v.replace("$arg", arg).replace("$Name", faction_name(arg).capitalize()) \
			.replace("$name", faction_name(arg)).replace("$One", faction_name(arg, false).capitalize())
	if v is Array:
		return v.map(func(x): return _fill(x, arg))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _fill(v[k], arg)
		return out
	return v


static func name_of(id: String) -> String:
	return String(row(id).get("name", id.capitalize()))


# Every trait of a family, in the file's order (the order the creator lists them).
static func of_family(family: String) -> Array:
	var out: Array = []
	for id in all():
		if String(all()[id].get("family", "")) == family:
			out.append(id)
	return out


# --- on a character -------------------------------------------------------------

static func ids(ch) -> Array:
	var out: Array = []
	if ch == null:
		return out
	for t in ch.traits:
		var id := String(t.get("id", "")) if t is Dictionary else String(t)
		if id != "" and not row(id).is_empty():
			out.append(id)   # an id the data no longer has (a pack removed) is skipped, not crashed on
	return out


static func has(ch, id: String) -> bool:
	return id in ids(ch)


static func of(ch, family: String) -> String:
	for id in ids(ch):
		if String(row(id).get("family", "")) == family:
			return id
	return ""


# A hero holds one of each picked family; setting it replaces the old one.
# "" clears the family.
static func set_family(ch, family: String, id: String, why := "chosen") -> void:
	if id != "" and String(row(id).get("family", "")) != family:
		return   # not a trait of this family: refuse, rather than clear the one they have
	var kept: Array = []
	for t in ch.traits:
		var tid := String(t.get("id", "")) if t is Dictionary else String(t)
		if String(row(tid).get("family", "")) != family:
			kept.append(t)
	if id != "":
		kept.append({"id": id, "why": why})
	ch.traits = kept


static func default_for(background_id: String, family: String) -> String:
	return String(_load().get("defaults", {}).get(family, {}).get(background_id, ""))


# What a new hero starts with: the background's defaults, for the creator to
# pre-select and the player to change. A family already picked is left alone.
static func fill_defaults(ch, prev_background := "") -> void:
	for fam in FAMILIES:
		var cur := of(ch, fam)
		# Follow the background only while the pick is still the old
		# background's default — a choice the player made stays made.
		if cur == "" or (prev_background != "" and cur == default_for(prev_background, fam)):
			var d := default_for(ch.background_id, fam)
			if d != "":
				set_family(ch, fam, d, "born to it")


# An older hero (a save from before traits) who has never been offered the
# pick. The offer is made once; closing it without choosing still counts
# (spec §8: an offer, not a gate).
static func needs_offer(ch) -> bool:
	return ch != null and not ch.dead and ids(ch).is_empty() and not ch.traits_offered


# The two opposed temperaments cannot both be held (Brave and Craven).
static func opposed(a: String, b: String) -> bool:
	return b in row(a).get("opposes", [])


# --- words ------------------------------------------------------------------------

static func is_live(e: Dictionary) -> bool:
	for k in e.get("when", {}):
		if not (k in FIGHT_START_WHEN or k in ROLL_WHEN):
			return false
	var g: Dictionary = e.get("gives", {})
	if g.is_empty():
		return false
	for k in g:
		if not k in LIVE_GIVES:
			return false
	return true


# [{text, live}] — every effect of a trait in plain words, and whether this
# build applies it. The pages print the not-yet-live ones muted with a note.
static func effect_lines(id: String) -> Array:
	var out: Array = []
	for e in row(id).get("effects", []):
		out.append({"text": describe(e), "live": is_live(e)})
	return out


static func describe(e: Dictionary) -> String:
	var what := String(e.get("text", ""))
	if what == "":
		what = _gives_text(e.get("gives", {}))
	var where := _when_text(e.get("when", {}))
	return what + (" " + where if where != "" else "")


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else ("−%d" % -n)


static func _gives_text(g: Dictionary) -> String:
	var parts: Array = []
	for k in g:
		var v = g[k]
		match k:
			"ac": parts.append("%s AC" % _signed(int(v)))
			"to_hit": parts.append("%s to hit" % _signed(int(v)))
			"initiative": parts.append("%s initiative" % _signed(int(v)))
			"damage": parts.append("%s damage" % _signed(int(v)))
			"travel": parts.append("%s on the road's checks" % _signed(int(v)))
			"forage": parts.append("%s to forage" % _signed(int(v)))
			"gold": parts.append("%s%% of a fight's purse" % _signed(int(v)))
			"save":
				if v is Dictionary:
					for a in v:
						parts.append("%s %s saves" % [_signed(int(v[a])), ABIL.get(a, a)])
				else:
					parts.append("%s to saves" % _signed(int(v)))
			"skill":
				for s in v:
					parts.append("%s %s" % [_signed(int(v[s])), SKILL_NAME.get(s, String(s).capitalize())])
			"save_adv":
				parts.append("Advantage on saves against being %s" % String(v.get("vs", "")))
			"ward":
				parts.append("%d less damage from every hit" % int(v))
			"speed":
				parts.append("%s hex of movement" % _signed(int(v)))
			_:
				parts.append(String(k).replace("_", " "))
	return ", ".join(parts)


static func _when_text(w: Dictionary) -> String:
	var parts: Array = []
	if w.has("biome"):
		parts.append(" or ".join(w["biome"].map(func(b): return String(BIOME_PHRASE.get(b, "in the " + b)))))
	if w.has("board"):
		var Enc = load("res://core/encounter.gd")   # load: encounter.gd preloads this file
		var names: Array = w["board"].map(func(t): return String(Enc.board_name(t)).replace("The ", "the "))
		parts.append("on " + (", ".join(names) if names.size() <= 2 else "an open board"))
	if w.has("night"):
		parts.append("at night" if w["night"] else "by day")
	if w.has("band"):
		parts.append("in " + ", ".join(w["band"]))
	if w.has("site"):
		parts.append(" or ".join(w["site"].map(func(s): return String(SITE_PHRASE.get(s, s)))))
	if w.get("bloodied", false):
		parts.append("while under half HP")
	if w.get("first_round", false):
		parts.append("in the first round")
	if w.get("alone", false):
		parts.append("with no ally beside them")
	if w.has("vs_faction"):
		parts.append("against " + " or ".join(w["vs_faction"].map(func(f): return faction_name(String(f)))))
	if w.has("vs_type"):
		parts.append("against " + " or ".join(w["vs_type"].map(func(t): return String(t) + "s")))
	if w.has("dtype_in"):
		parts.append("against " + " or ".join(w["dtype_in"]))
	if w.has("dtype_out"):
		parts.append("with " + " or ".join(w["dtype_out"]) + " attacks")
	if w.get("guarding", false):
		parts.append("while standing over a downed ally")
	if w.has("vs_size"):
		parts.append("against anything " + String(w["vs_size"][0]) + " or bigger")
	if w.has("vs_deals"):
		parts.append("against anything that deals " + " or ".join(w["vs_deals"]))
	return " ".join(parts)


# --- a fight ----------------------------------------------------------------------

# Where the fight is, as the `when` keys read it. The board and the night are
# always known (the board is stamped with its theme, core/encounter.gd); the
# biome, band and site only when the world screen put them on the spec
# (spec["where"] -> board["where"]). A fight without them — the demo, the
# linear campaign — still reads its board and its night.
static func where_of(board: Dictionary) -> Dictionary:
	var w: Dictionary = board.get("where", {}).duplicate()
	w["board"] = String(board.get("theme", ""))
	w["night"] = bool(board.get("night", false))
	return w


static func holds(when: Dictionary, where: Dictionary) -> bool:
	for k in when:
		if not k in FIGHT_START_WHEN:
			return false        # a per-roll condition: not this step's to decide
		var want = when[k]
		if not where.has(k):
			return false        # the fight does not know it, so it does not hold
		var have = where[k]
		if want is Array:
			if not have in want:
				return false
		elif want != have:
			return false
	return true


# The live terms one hero's traits add in this place: {"ac": 1, "to_hit": 0,
# "initiative": -1, "save": {"con": 1}}, each capped at ±CAP, and the names of
# the traits that contributed for the log line.
static func terms(trait_ids: Array, where: Dictionary) -> Dictionary:
	var sum := {"ac": 0, "to_hit": 0, "initiative": 0, "speed": 0, "save": {}}
	var who: Array = []
	for id in trait_ids:
		var used := false
		for e in row(id).get("effects", []):
			if not is_live(e) or _is_roll(e) or not holds(e.get("when", {}), where):
				continue
			var g: Dictionary = e["gives"]
			for k in ["ac", "to_hit", "initiative", "speed"]:
				if g.has(k):
					sum[k] += int(g[k])
					used = true
			if g.has("save"):
				var sv = g["save"]
				for a in (sv.keys() if sv is Dictionary else ["all"]):
					sum["save"][a] = int(sum["save"].get(a, 0)) + int(sv[a] if sv is Dictionary else sv)
				used = true
		if used:
			who.append(name_of(id))
	for k in ["ac", "to_hit", "initiative", "speed"]:
		sum[k] = clampi(sum[k], -CAP, CAP)
	for a in sum["save"]:
		sum["save"][a] = clampi(sum["save"][a], -CAP, CAP)
	sum["who"] = who
	return sum


# Once, from Encounter.build, BEFORE the Combat exists: Combat._init rolls
# initiative, so an initiative term stamped after it would move init_mod and
# miss the only roll that reads it (the first cut of this did exactly that —
# the fight's log printed the order, then the trait). Writes each hero's live
# terms where the engine already reads them: AC and to-hit as a status dict
# (combat.gd's _buff_sum reads "ac" and "bonus_to_hit" off any status), a save
# straight onto this fight's copy of the saves, initiative onto init_mod.
# Returns the log lines, one per hero whose traits count here, for the caller
# to put at the top of the fight's log — a +1 nobody is told about is a +1
# nobody believes.
static func stamp(combatants: Array, board: Dictionary) -> Array:
	var where := where_of(board)
	var lines: Array = []
	for c in combatants:
		if c.traits.is_empty():
			continue
		var t := terms(c.traits, where)
		var st := {"save_terms": t["save"].duplicate()}   # what the stamp already gave, for roll()'s cap
		if t["ac"] != 0:
			st["ac"] = t["ac"]
		if t["to_hit"] != 0:
			st["bonus_to_hit"] = t["to_hit"]
		if t["save"].has("all"):
			st["bonus_save"] = t["save"]["all"]
		if st.size() > 1 or not st["save_terms"].is_empty():
			c.statuses[STATUS] = st
		for a in t["save"]:
			if a != "all":
				c.saves[a] = int(c.saves.get(a, 0)) + int(t["save"][a])
		c.init_mod += int(t["initiative"])
		c.speed = maxi(1, int(c.speed) + int(t["speed"]))   # Maimed: a hex gone, never all of them
		var bits := _stamp_bits(t)
		if not bits.is_empty():
			lines.append("%s — %s here: %s." % [c.cname, " and ".join(t["who"]), ", ".join(bits)])
	return lines


static func _stamp_bits(t: Dictionary) -> Array:
	var bits: Array = []
	if t["ac"] != 0:
		bits.append("%s AC" % _signed(t["ac"]))
	if t["to_hit"] != 0:
		bits.append("%s to hit" % _signed(t["to_hit"]))
	if t["initiative"] != 0:
		bits.append("%s initiative" % _signed(t["initiative"]))
	if t["speed"] != 0:
		bits.append("%s hex of movement" % _signed(t["speed"]))
	for a in t["save"]:
		if t["save"][a] != 0:
			bits.append("%s %s" % [_signed(t["save"][a]), "to saves" if a == "all" else ABIL.get(a, a) + " saves"])
	return bits


# The traits that can count in this fight, for the combat card's chips: a live
# effect whose where-it-is half holds here (its roll half — bloodied, the foe —
# is decided later, at the roll, and does not dim the chip).
static func live_here(c, cb) -> Array:
	var where := where_of(cb.board)
	var out: Array = []
	for id in c.traits:
		for e in row(id).get("effects", []):
			if is_live(e) and holds(_static_part(e.get("when", {})), where):
				out.append(id)
				break
	return out


# --- the roll (step 2) --------------------------------------------------------------

static func _is_roll(e: Dictionary) -> bool:
	for k in e.get("when", {}):
		if k in ROLL_WHEN:
			return true
	return false


static func _static_part(when: Dictionary) -> Dictionary:
	var out := {}
	for k in when:
		if k in FIGHT_START_WHEN:
			out[k] = when[k]
	return out


# What the roll knows. `other` is whoever is on the far end of it — the target
# of c's attack, the attacker of c's AC, the source of c's save — or null.
static func _ctx(c, cb, other, dtype: String) -> Dictionary:
	var ctx := {
		"bloodied": c.hp * 2 < c.max_hp,
		"first_round": int(cb.round_num) <= 1,
		"alone": not cb.allies_of(c).any(func(a): return a != c and a.conscious() \
			and Hex.distance(a.pos, c.pos) <= 1),
		"dtype": dtype,
	}
	if other != null and String(other.src_id) != "":
		var m: Dictionary = Catalog.monster(String(other.src_id))
		ctx["foe_faction"] = String(m.get("faction", ""))
		ctx["foe_type"] = String(m.get("type", ""))
		ctx["foe_deals"] = deals(m)
	if other != null:
		ctx["foe_size"] = String(other.size)
	ctx["guarding"] = cb.allies_of(c).any(func(a): return a != c and a.is_down() and not a.is_dead() \
		and Hex.distance(a.pos, c.pos) <= 1)
	return ctx


# What a monster's blows are made of, for vs_deals and a scar's cure: its own
# attack's damage type, and what it is immune to (a fire giant swings a
# greatsword and stands in lava; to a Burn-shy hero it is fire either way).
static func deals(m: Dictionary) -> Array:
	var out: Array = []
	if String(m.get("damage_type", "")) != "":
		out.append(String(m["damage_type"]))
	for d in m.get("immune", []):
		if not String(d) in out:
			out.append(String(d))
	return out


static func _roll_holds(when: Dictionary, where: Dictionary, ctx: Dictionary, dtype_key: String) -> bool:
	if not holds(_static_part(when), where):
		return false
	for k in when:
		match k:
			"bloodied", "first_round", "alone", "guarding":
				if bool(when[k]) != bool(ctx[k]):
					return false
			"vs_size":
				if not String(ctx.get("foe_size", "")) in when[k]:
					return false
			"vs_deals":
				if not when[k].any(func(d): return d in ctx.get("foe_deals", [])):
					return false
			"vs_faction":
				if not String(ctx.get("foe_faction", "")) in when[k]:
					return false
			"vs_type":
				if not String(ctx.get("foe_type", "")) in when[k]:
					return false
			"dtype_in", "dtype_out":
				# the damage type is only the one the roll is about: dtype_in on a
				# hit taken, dtype_out on a swing made
				if k != dtype_key or not String(ctx["dtype"]) in when[k]:
					return false
	return true


# One term, asked at the roll: {"n": int, "who": [trait names]}. `key` is the
# gives key — "to_hit" (c attacking `other`), "ac" (c attacked by `other`),
# "save" (c saving, `ability`), "damage" (c hitting `other`), "ward" (c hit,
# `dtype` coming in). For the three the stamp also feeds (to_hit, ac, save),
# only roll-`when` effects are summed here — the rest were stamped — and the
# cap is taken over both together, so a stamped +2 and a roll +1 are +2, not +3.
static func roll(c, key: String, cb, other = null, dtype := "", ability := "") -> Dictionary:
	var out := {"n": 0, "who": []}
	if c == null or c.traits.is_empty():
		return out
	var where := where_of(cb.board)
	var ctx := _ctx(c, cb, other, dtype)
	var dtype_key := "dtype_in" if key in ["ac", "save", "ward"] else "dtype_out"
	var n := 0
	for id in c.traits:
		var used := false
		for e in row(id).get("effects", []):
			var g: Dictionary = e.get("gives", {})
			if not g.has(key) or not is_live(e):
				continue
			if key in STAMPED and not _is_roll(e):
				continue   # already on the Combatant from the stamp
			if not _roll_holds(e.get("when", {}), where, ctx, dtype_key):
				continue
			var v = g[key]
			if key == "save":
				v = v.get(ability, 0) if v is Dictionary else v
			n += int(v)
			used = true
		if used:
			out["who"].append(name_of(id))
	var st: Dictionary = c.statuses.get(STATUS, {}) if c.statuses.get(STATUS) is Dictionary else {}
	var stamped := 0
	match key:
		"to_hit": stamped = int(st.get("bonus_to_hit", 0))
		"ac": stamped = int(st.get("ac", 0))
		"save": stamped = int(st.get("bonus_save", 0)) + int(st.get("save_terms", {}).get(ability, 0))
	if key == "ward":
		# Not a roll, so not under the ±CAP a d20 is: a flat reduction per hit,
		# sized in the data (spec §3 — "3 less fire damage", the trait-sized
		# answer to 5e resistance). It only ever takes damage away.
		out["n"] = maxi(0, n)
	else:
		out["n"] = clampi(stamped + n, -CAP, CAP) - stamped
	return out


# Advantage (Dice.ADV) on a save against one of `conds`, from a save_adv trait
# (Brave against being frightened), else Dice.NORMAL.
static func save_mode(c, cb, conds: Array) -> Dictionary:
	var out := {"adv": false, "who": []}
	if c == null or c.traits.is_empty() or conds.is_empty():
		return out
	var where := where_of(cb.board)
	var ctx := _ctx(c, cb, null, "")
	for id in c.traits:
		for e in row(id).get("effects", []):
			var sa = e.get("gives", {}).get("save_adv")
			if sa is Dictionary and String(sa.get("vs", "")) in conds \
					and _roll_holds(e.get("when", {}), where, ctx, "dtype_in"):
				out["adv"] = true
				if not name_of(id) in out["who"]:
					out["who"].append(name_of(id))
	return out


# --- earning (step 3) -----------------------------------------------------------------
#
# What a fight (or a cleared lair) leaves on the people in it: spec §6. Every
# hero it touched rolls on their own, so the same fire can temper one of them
# and scar another, and leave a third untouched.
#   - A **triumph** is rolled on chance (the likelier kind, by the owner's
#     decision): a notable win, not every win — the company wins nine road
#     fights in ten, and a trait on each would bury them.
#   - A **hardship** is a saving throw on the hero's own save bonus, against a
#     DC off whatever did it (10 + half its CR, +2 per aggravation, ≤ 20), and
#     the degree decides: made by 5 or a nat 20 tempers them, made leaves them
#     as they were, failed scars them, failed by 5 or a nat 1 scars and wounds.
#     Temperament rides the save, not the table: Brave has advantage on a fear
#     save, Craven disadvantage, Calm +2 on WIS, and a Wrathful hero's failed
#     faction save turns outward into a grudge.
#   - A **cure** is the same save asked again, when a scarred hero meets the
#     thing again and wins.
#   - **Counted** marks need no roll: ten kills of one faction make a bane (three
#     for dragons), twenty won fights make a Veteran.
# Every roll is seeded off the hero, the event and the world minute, so a
# reload cannot reroll a scar the player did not want. Nothing is asked: what
# the event did is applied, and the caller shows it (§10 — no refusing).
#
# What it does NOT own: when a fight or a lair asks (scenes/world/world.gd),
# the moment that shows it (scenes/world/trait_moment.gd — the dicts this
# returns are that screen's), or the after-action page's layout.
#
# MEASURED 2026-09-23 (tests/sweep_traits_earn.gd, 200 seeds a difficulty, the
# preset trio holding nothing, a fresh party per fight, the real
# Encounter.resolve_outcome result). Changes per 100 hero-fights:
#
#               win%   triumph  resilience  scar  wound
#     easy       98       3.8       4.7      1.8   14.5
#     normal     94       4.8       6.2      3.7   19.7
#     hard       89      16.5       8.0      4.3   22.5
#     deadly     94      16.0       6.3      2.8   20.7
#
# Triumphs outnumber scars at every difficulty, which is the owner's rule: two
# to one on the road's easy fights, four to six to one where "flawless" can
# fire (hard and deadly only). The commonest change is a wound, and Wounded is
# the commonest trait of all (242 times in the 800 fights, Shaken next at 167):
# a downed hero who failed a death save, lapsing in three days. Of 480 hardship saves, 31% tempered, 24% shook
# it off, 28% scarred and 17% scarred and Shaken, so a save is close to a coin
# flip between a good and a bad mark.
#
# The same sweep's 30-day run (20 runs: a road fight a day at easy, a lair
# every fourth day of two normal rooms and a hard boss room, no inn) gains
# each hero 5.1 triumphs, 1.8 resiliences, 1.2 scars, 5.0 wounds and 0.75
# cures, and each ends it holding 8.0 earned traits: 0.5 scars, 0.75 wounds,
# and 6.8 of the rest (Veteran about halfway through, at 44 fights a run; two
# banes; grudges; Delver; Hardened). The chances, DCs and degrees stay as the spec set them: the rule
# they answer to holds.
# ponytail: nothing limits how many earned traits a hero holds (8 a hero in 30
# days), and one event can leave both of its outcomes on a hero over two lairs
# (Delver and Reckless). Revisit if the profile's list gets long enough that
# the player stops reading it; a cap per family is the cheap fix.

const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")

const DAY := 1440.0                 # world minutes
const DEGREE := 5                   # made or failed by this much, the save's second degree
const DC_MIN := 10
const DC_MAX := 20
const AGGRAVATION := 2              # per aggravation: the boss did it, a death save failed
const BANE_KILLS := 10
const BANE_KILLS_DRAGON := 3        # there are fewer dragons, and each one is a story
const BANE_CAP := 2                 # spec §2: two banes at most — the player chooses what the hero is known for
const WOUND_CAP := 2
const VETERAN_WINS := 20
const SHAKEN_CALM_DAYS := 2         # Calm heroes shed Shaken in two days, not five
# Cures, per hardship: what the hero has to meet again, and beat.
const CURE_DEALS := {"downed_fire": ["fire"], "downed_cold": ["cold"], "downed_storm": ["lightning", "thunder"]}


static func events() -> Dictionary:
	return _load().get("events", {})


static func family_of(id: String) -> String:
	return String(row(id).get("family", ""))


static func _count_family(ch, family: String) -> int:
	return ids(ch).filter(func(i): return family_of(i) == family).size()


static func count(ch, key: String) -> int:
	return int(ch.trait_counts.get(key, 0))


static func bump(ch, key: String, n := 1) -> int:
	ch.trait_counts[key] = count(ch, key) + n
	return count(ch, key)


static func _seed(s: String) -> int:
	return maxi(1, absi(hash(s)))


# Whether any trait the hero holds gives `key` unconditionally (a hardship's
# temperament hooks, Hard to kill). `ch_or_c` is a Character or a Combatant.
static func flag(ch_or_c, key: String):
	var list: Array = ch_or_c.traits.map(func(t): return String(t.get("id", "")) if t is Dictionary else String(t))
	for id in list:
		for e in row(id).get("effects", []):
			if e.get("when", {}).is_empty() and e.get("gives", {}).has(key):
				return e["gives"][key]
	return null


# Take a trait: {} when it is already held, the data has no such row, or its
# family is full. A lapsing one (Emboldened, a wound) carries `until`.
static func grant(ch, id: String, why: String, now: float, extra := {}) -> Dictionary:
	var r := row(id)
	if r.is_empty() or has(ch, id):
		return {}
	var fam := String(r.get("family", ""))
	if (fam == "bane" and _count_family(ch, "bane") >= BANE_CAP) \
			or (fam == "wound" and _count_family(ch, "wound") >= WOUND_CAP):
		return {}
	var t := {"id": id, "why": why, "since": now}
	var days := float(r.get("lasts_days", 0))
	if id == "shaken" and has(ch, "calm"):
		days = SHAKEN_CALM_DAYS
	if days > 0.0:
		t["until"] = now + days * DAY
	t.merge(extra)
	ch.traits.append(t)
	return t


# For a page: what would mend a scar or a wound, and how long a lapsing one
# has left — "" for a trait nothing mends.
static func mend_text(ch, id: String, now: float) -> String:
	var r := row(id)
	var how := String(r.get("cure", r.get("heals", "")))
	for t in ch.traits:
		if t is Dictionary and String(t.get("id", "")) == id and t.has("until"):
			var days := maxf(0.0, (float(t["until"]) - now) / DAY)
			var left := "less than a day left" if days < 1.0 else "%d day%s left" % [ceili(days), "" if ceili(days) == 1 else "s"]
			return (how + " — " + left) if how != "" else left.capitalize()
	return how


static func remove(ch, id: String) -> bool:
	var before: int = ch.traits.size()
	ch.traits = ch.traits.filter(func(t): return (String(t.get("id", "")) if t is Dictionary else String(t)) != id)
	return ch.traits.size() != before


# The ones whose time is up: Emboldened after three days, a wound when it has
# healed. Returns the names that lapsed, for a line.
static func expire(ch, now: float) -> Array:
	var gone: Array = []
	for t in ch.traits.duplicate():
		if t is Dictionary and t.has("until") and float(t["until"]) <= now:
			remove(ch, String(t["id"]))
			gone.append(name_of(String(t["id"])))
	return gone


# A long rest at an inn mends Wounded; one in a city, where the healers are,
# mends Maimed too (spec §6's wound table).
static func heal_rest(ch, city: bool) -> Array:
	var gone: Array = []
	for id in (["wounded", "maimed"] if city else ["wounded"]):
		if remove(ch, id):
			gone.append(name_of(id))
	return gone


static func _cr(monster_id: String) -> float:
	return 0.0 if monster_id == "" else float(Catalog.monster(monster_id).get("cr", 0.0))


static func _avg_level(chars: Array) -> float:
	var n := 0.0
	var sum := 0.0
	for ch in chars:
		if ch != null:
			sum += ch.level()
			n += 1.0
	return sum / n if n > 0.0 else 1.0


# The fight's worst: its highest-CR kill, when that is at least the company's
# level. A road of goblins has no boss.
static func _boss(kills: Array, level: float) -> String:
	var best := ""
	for k in kills:
		if best == "" or _cr(String(k)) > _cr(best):
			best = String(k)
	return best if best != "" and _cr(best) >= level else ""


static func _monster_name(id: String) -> String:
	return "" if id == "" else String(Catalog.monster(id).get("cname", id.capitalize()))


# What the moment screen (scenes/world/trait_moment.gd) and the after-action
# page need, from what happened.
static func _gain(out: Dictionary, ch, kind: String, id: String, event: String, sv := {}, verb := "is now") -> void:
	var r := row(id)
	var m := {"char_id": ch.id, "cname": ch.cname, "kind": kind, "event": event,
		"trait": {"name": name_of(id), "text": String(r.get("text", "")),
			"effects": effect_lines(id).map(func(l): return String(l["text"])),
			"cure": String(r.get("cure", r.get("heals", "")))},
		"line": "%s %s %s." % [ch.cname, verb, name_of(id)]}
	if not sv.is_empty():
		m["save"] = sv
	out["moments"].append(m)
	out["lines"].append("%s %s %s%s." % [ch.cname, verb, name_of(id), _save_words(sv)])


static func _save_words(sv: Dictionary) -> String:
	if sv.is_empty():
		return ""
	return " (%s %d + %d vs DC %d)" % [ABIL.get(String(sv["ability"]), sv["ability"]), int(sv["nat"]),
		int(sv["bonus"]), int(sv["dc"])]


# --- a fight ------------------------------------------------------------------------

# After a fight, win or lose: `chars` the heroes who were in it, `result`
# Encounter.resolve_outcome's, `ctx` {"now": world minutes, "difficulty":
# the roster's, "site"}. Changes the heroes' traits and counts, and returns
# {"moments": [trait_moment dicts], "lines": [one line each, for the page]}.
# At most one triumph and one hardship per hero per fight, the first that
# applies in the order below — a fight is one story per person, not four.
static func after_fight(chars: Array, result: Dictionary, ctx: Dictionary) -> Dictionary:
	var out := {"moments": [], "lines": []}
	var now := float(ctx.get("now", 0.0))
	var won := String(result.get("outcome", "")) == "Victory"
	var credit: Dictionary = result.get("credit", {})
	var dead: Array = result.get("deaths", [])
	var kills: Array = result.get("kills", [])
	var alive: Array = chars.filter(func(ch): return ch != null and not ch.dead and not ch.id in dead)
	var boss := _boss(kills, _avg_level(chars))
	var triumphed := {}
	# Counted, not rolled: a bane, Veteran.
	for ch in alive:
		var cr: Dictionary = credit.get(ch.id, {})
		for k in cr.get("kills", []):
			var f := String(Catalog.monster(String(k)).get("faction", ""))
			if f == "":
				continue
			var n := bump(ch, "kill:" + f)
			if triumphed.has(ch.id) or n < (BANE_KILLS_DRAGON if f == "dragon" else BANE_KILLS):
				continue
			var t := grant(ch, "bane@" + f, "%d %s killed" % [n, faction_name(f)], now)
			if not t.is_empty():
				_gain(out, ch, "triumph", String(t["id"]), "%d %s killed" % [n, faction_name(f)])
				triumphed[ch.id] = true
		if won and bump(ch, "wins") >= VETERAN_WINS and not triumphed.has(ch.id):
			if not grant(ch, "veteran", "%d fights won" % VETERAN_WINS, now).is_empty():
				_gain(out, ch, "triumph", "veteran", "%d fights won" % VETERAN_WINS)
				triumphed[ch.id] = true
	if won:
		for ch in alive:
			if triumphed.has(ch.id):
				continue
			var ks: Array = credit.get(ch.id, {}).get("kills", [])
			var ev := ""
			if boss != "" and boss in ks:
				ev = "boss_kill"
			elif ks.any(func(k): return _cr(String(k)) > ch.level()):
				ev = "giant_kill"
			elif credit.values().any(func(c): return ch.id in c.get("revived_by", [])):
				ev = "revived"
			elif String(ctx.get("difficulty", "")) in ["hard", "deadly"] and result.get("downed", []).is_empty():
				ev = "flawless"
			if ev != "":
				_triumph(out, ch, ev, now)
		for ch in alive:
			_cures(out, ch, kills, now)
	for ch in alive:
		var cr: Dictionary = credit.get(ch.id, {})
		var hit := _hardship_for(ch, cr, dead, credit, boss)
		var scarred := false
		if not hit.is_empty():
			scarred = _hardship(out, ch, hit, now)
		# Downed and a death save failed: Wounded, unless the hardship already
		# left a wound of its own.
		if int(cr.get("death_fails", 0)) >= 1 and not scarred:
			if not grant(ch, "wounded", "Went down and nearly stayed down", now).is_empty():
				_gain(out, ch, "wound", "wounded", "Went down and nearly stayed down", {}, "is")
	return out


# A cleared lair, for every hero standing at the bottom of it (spec §6's
# triumph table).
static func after_lair(chars: Array, now: float) -> Dictionary:
	var out := {"moments": [], "lines": []}
	for ch in chars:
		if ch != null and not ch.dead:
			_triumph(out, ch, "lair_cleared", now)
	return out


static func _triumph(out: Dictionary, ch, ev_id: String, now: float) -> bool:
	var ev: Dictionary = events().get(ev_id, {})
	if ev.is_empty():
		return false
	var rng := RNG.new(_seed("trait|%s|%s|%d" % [ch.id, ev_id, int(now)]))
	if rng.roll_die(100) > int(ev.get("chance", 0)):
		return false
	# A trait already held rolls as nothing, and a family at its cap drops its
	# outcomes before the roll (spec §6).
	var options: Array = ev.get("outcomes", []).filter(func(o): return not has(ch, String(o["trait"])))
	if options.is_empty():
		return false
	var mine := ids(ch)
	var weights: Array = options.map(func(o):
		var w := int(o.get("weight", 1))
		for t in mine:
			w += int(o.get("lean", {}).get(t, 0))
		return maxi(1, w))
	var total := 0
	for w in weights:
		total += int(w)
	var pick := rng.roll_die(total)
	for i in options.size():
		pick -= int(weights[i])
		if pick <= 0:
			var id := String(options[i]["trait"])
			if grant(ch, id, String(ev.get("label", "")), now).is_empty():
				return false
			_gain(out, ch, "triumph", id, String(ev.get("label", "")))
			return true
	return false


# Which hardship this fight asks of one hero, if any: {"event", "by" (monster
# id), "faction"?, "dc"}. The downs are counted for every hero whatever wins
# the precedence, so "put down by the same kind twice" counts across fights.
static func _hardship_for(ch, cr: Dictionary, dead: Array, credit: Dictionary, boss: String) -> Dictionary:
	var downs: Array = cr.get("downed_by", []).filter(func(d): return String(d.get("team", "")) == "foe")
	var twice := ""
	for d in downs:
		var f := String(Catalog.monster(String(d["by"])).get("faction", ""))
		if f != "" and bump(ch, "downed:" + f) == 2:
			twice = f
	var hit := {}
	var last: Dictionary = downs.back() if not downs.is_empty() else {}
	if int(cr.get("death_fails", 0)) >= 2 and not last.is_empty():
		hit = {"event": "death_door", "by": String(last["by"])}
	elif twice != "":
		hit = {"event": "downed_twice", "by": String(last["by"]), "faction": twice}
	elif not last.is_empty() and String(last.get("dtype", "")) in ["fire", "cold", "lightning", "thunder"]:
		var dt := String(last["dtype"])
		hit = {"event": "downed_fire" if dt == "fire" else ("downed_cold" if dt == "cold" else "downed_storm"),
			"by": String(last["by"])}
	elif not dead.is_empty():
		var their: Array = credit.get(String(dead[0]), {}).get("downed_by", [])
		hit = {"event": "ally_died", "by": String(their.back().get("by", "")) if not their.is_empty() else ""}
	if hit.is_empty():
		return hit
	var dc := maxi(DC_MIN, DC_MIN + int(floor(_cr(String(hit["by"])) / 2.0)))
	if String(hit["by"]) != "" and String(hit["by"]) == boss:
		dc += AGGRAVATION
	if int(cr.get("death_fails", 0)) >= 1 and String(hit["event"]) != "ally_died":
		dc += AGGRAVATION
	hit["dc"] = mini(DC_MAX, dc)
	return hit


# The hero's save against a hardship: their own bonus, Calm's +2 on WIS, and on
# a fear save Brave's advantage or Craven's disadvantage.
static func _save_roll(ch, ev: Dictionary, dc: int, seed_text: String) -> Dictionary:
	var ab := String(ev.get("ability", "wis"))
	var bonus := int(ch.sheet().saves.get(ab, 0))
	var hb = flag(ch, "hardship_bonus")
	if hb is Dictionary:
		bonus += int(hb.get(ab, 0))
	var adv := bool(ev.get("fear", false)) and flag(ch, "hardship_adv") != null
	var dis := bool(ev.get("fear", false)) and flag(ch, "hardship_dis") != null
	var mode := Dice.combine(adv, dis)
	var r: Dictionary = Dice.d20(RNG.new(_seed(seed_text)), mode)
	return {"ability": ab, "dc": dc, "nat": int(r["nat"]), "bonus": bonus, "dice": r["dice"],
		"mode": "adv" if mode == Dice.ADV else ("dis" if mode == Dice.DIS else "")}


# Rolls one hardship and applies what the degree leaves. True when it left a
# wound (so the caller does not add Wounded on top).
static func _hardship(out: Dictionary, ch, hit: Dictionary, now: float) -> bool:
	var ev_id := String(hit["event"])
	var ev: Dictionary = events().get(ev_id, {})
	var sv := _save_roll(ch, ev, int(hit["dc"]), "trait|%s|%s|%d" % [ch.id, ev_id, int(now)])
	var margin := int(sv["nat"]) + int(sv["bonus"]) - int(sv["dc"])
	var f := String(hit.get("faction", ""))
	var suffix := ("@" + f) if f != "" else ""
	var label := String(ev.get("label", ""))
	if _monster_name(String(hit["by"])) != "":
		label += " — " + _monster_name(String(hit["by"]))
	var res := String(ev.get("resilience", "")) + suffix
	var scar := String(ev.get("scar", "")) + suffix
	if int(sv["nat"]) == 20 or margin >= DEGREE:
		if has(ch, res):
			return false
		remove(ch, scar)   # tempered by the thing that scarred them: the scar goes
		grant(ch, res, label, now)
		_gain(out, ch, "resilience", res, label, sv)
		return false
	if margin >= 0:
		out["lines"].append("%s shakes it off%s." % [ch.cname, _save_words(sv)])
		return false
	if f != "" and flag(ch, "grudge") != null:
		scar = String(ev.get("resilience", "")) + suffix   # Wrathful: the fear turns outward
	var wounded := false
	if not has(ch, scar):
		var extra := {"event": ev_id, "dc": int(sv["dc"])}
		if CURE_DEALS.has(ev_id):
			extra["cure"] = {"deals": CURE_DEALS[ev_id]}
		elif f != "":
			extra["cure"] = {"faction": f}
		if family_of(scar) == "wound":
			extra.erase("cure")
			wounded = true
		if not grant(ch, scar, label, now, extra).is_empty():
			var kind := String(row(scar).get("kind", "scar"))
			_gain(out, ch, kind, scar, label, sv, "is" if kind == "wound" else "is now")
	if int(sv["nat"]) == 1 or margin <= -DEGREE:
		if not grant(ch, "shaken", label, now).is_empty():
			_gain(out, ch, "wound", "shaken", label, {}, "is")
			wounded = true
	return wounded


# A scarred hero who met the thing again and won: the same save once more, at
# the same DC, and made, the scar is gone (spec §6 — overcoming a fear is a
# roll the player watches, not a flag that quietly clears).
static func _cures(out: Dictionary, ch, kills: Array, now: float) -> void:
	for t in ch.traits.duplicate():
		if not t is Dictionary or not t.has("cure"):
			continue
		var cure: Dictionary = t["cure"]
		var met := kills.any(func(k):
			var m: Dictionary = Catalog.monster(String(k))
			if cure.has("faction"):
				return String(m.get("faction", "")) == String(cure["faction"])
			return deals(m).any(func(d): return d in cure.get("deals", [])))
		if not met:
			continue
		var ev: Dictionary = events().get(String(t.get("event", "")), {})
		var id := String(t["id"])
		var sv := _save_roll(ch, ev, int(t.get("dc", DC_MIN)), "cure|%s|%s|%d" % [ch.id, id, int(now)])
		if int(sv["nat"]) == 20 or int(sv["nat"]) + int(sv["bonus"]) >= int(sv["dc"]):
			remove(ch, id)
			_gain(out, ch, "cure", id, "Faced it again, and won", sv, "is no longer")
		else:
			out["lines"].append("%s is still %s%s." % [ch.cname, name_of(id), _save_words(sv)])


# --- the road (step 4) -----------------------------------------------------------------
#
# The half of a trait that is not about a fight: the road's checks, the purse,
# and how the company gets on (spec §5.3, §7). The world screen stamps where
# the party is on the party every frame (party.here: biome, band, site, night),
# the way it stamps world_now; a check reads it through Campaign.skill_bonus,
# so every overworld skill roll — the road's events, the approach, the search,
# the watch, the town's persuading and haggling — gets its trait term in one
# place. A term is capped at ±CAP like a fight's, and says who gave it, for
# the card's roll line ("+2 (Marsh-bred)").
#
# MEASURED 2026-09-23 (tests/sweep_traits_road.gd, 1,500 seeds a biome, the
# preset trio all holding the trait, normal pace, the best roller). The road's
# rolls pass 57.4% of the time with no trait. Change in the pass rate:
#     Downs-rider +4.8 (its +1 travel counts in every roll, in every biome)
#     Cautious −3.9 (−1 travel, every roll)
#     Marsh-bred +2.8 in the marsh and −1.3 on the downs (its survival terms
#       count in about a third of the rolls, the survival events)
#     Street-raised −3.1 in all three (−2 survival in the wild, 30% of rolls)
#     Woods-born, Cave-dweller, Night-owl: 0 (no road event rolls their skills)
# Every origin moves the road less than the pace does (Careful is +2 on every
# roll, twice Downs-rider's term), so the ±2 skill terms and the ±1 travel
# terms stay as the spec set them.

# Whether a road `when` holds here. Only the where-it-is keys can: a board or a
# per-roll key belongs to a fight, and never holds on the road.
static func _road_holds(when: Dictionary, here: Dictionary) -> bool:
	for k in when:
		if not k in ["biome", "band", "site", "night"] or not here.has(k):
			return false
		var want = when[k]
		if want is Array:
			if not here[k] in want:
				return false
		elif want != here[k]:
			return false
	return true


# The trait term on one skill check (or a named job — "avoid", the approach's
# slip-away): {"n": capped sum, "who": [trait names]}.
static func skill_term(ch, skill: String, here: Dictionary) -> Dictionary:
	var out := {"n": 0, "who": []}
	if ch == null:
		return out
	var n := 0
	for id in ids(ch):
		var used := false
		for e in row(id).get("effects", []):
			var sk = e.get("gives", {}).get("skill")
			if sk is Dictionary and sk.has(skill) and _road_holds(e.get("when", {}), here):
				n += int(sk[skill])
				used = true
		if used:
			out["who"].append(name_of(id))
	out["n"] = clampi(n, -CAP, CAP)
	return out


# The same, for a flat road key a trait gives outright: "travel" (the road's
# checks for whoever rolls them), "forage".
static func road_term(ch, key: String, here: Dictionary) -> Dictionary:
	var out := {"n": 0, "who": []}
	if ch == null:
		return out
	var n := 0
	for id in ids(ch):
		for e in row(id).get("effects", []):
			var g: Dictionary = e.get("gives", {})
			if g.has(key) and _road_holds(e.get("when", {}), here):
				n += int(g[key])
				if not name_of(id) in out["who"]:
					out["who"].append(name_of(id))
	out["n"] = clampi(n, -CAP, CAP)
	return out


# A company's percentage: "gold" (Greedy's +10% of a fight's purse), or
# "sale_price" (Generous's −10% on what they sell). One holder is enough, and
# two do not stack — it is the company's purse, not each hero's.
static func party_pct(party, key: String) -> int:
	var best := 0
	for ch in party.party_characters():
		for id in ids(ch):
			for e in row(id).get("effects", []):
				var v = e.get("gives", {}).get(key)
				if v != null and absi(int(v)) > absi(best):
					best = int(v)
	return best


# --- how the company gets on (§7) -----------------------------------------------------------

const SHARED_TEMPER := 5.0      # per temperament two heroes share
const OPPOSED_TEMPER := -10.0   # Brave and Craven do not get on
const WRATHFUL_FIRE := 1.5      # friendly fire from a Wrathful caster looks deliberate

# What two heroes' traits say about each other, on top of PartyOpinion's
# backgrounds and species: {"n", "why": [a phrase each]}. Greedy costs 5 with
# everyone who is not also Greedy; Arrogant costs 5 with everyone (a gives
# "opinion" on the trait, read from both sides).
static func opinion_terms(ca, cb) -> Dictionary:
	var out := {"n": 0.0, "why": []}
	if ca == null or cb == null:
		return out
	var a := ids(ca)
	var b := ids(cb)
	for t in a:
		if family_of(t) != "temperament":
			continue
		if t in b:
			out["n"] += SHARED_TEMPER
			out["why"].append("both " + name_of(t))
		for u in b:
			if opposed(t, u):
				out["n"] += OPPOSED_TEMPER
				out["why"].append("%s and %s" % [name_of(t), name_of(u)])
	for side in [[a, b], [b, a]]:
		for t in side[0]:
			for e in row(t).get("effects", []):
				var v = e.get("gives", {}).get("opinion")
				if v == null or (t in side[1]):
					continue   # two Greedy heroes understand each other
				out["n"] += float(v)
				out["why"].append(name_of(t))
	return out


static func warms_faster(ca, cb) -> bool:
	return flag(ca, "opinion_drift") != null or flag(cb, "opinion_drift") != null


# --- the camp beat ---------------------------------------------------------------------------

const CAMP_BEAT_DAYS := 3.0     # a trait earned more than this long ago is old news at the fire

# A line at the fire about a trait somebody earned since the last one was
# said: {"text", "kind", "char_id"}, or {} — and the trait is marked told, so
# each is said once. The row's `camp` line, with the hero's name.
static func camp_beat(chars: Array, now: float) -> Dictionary:
	for ch in chars:
		if ch == null or ch.dead:
			continue
		for t in ch.traits:
			if not t is Dictionary or bool(t.get("told", false)) or not t.has("since"):
				continue
			if now - float(t["since"]) > CAMP_BEAT_DAYS * DAY:
				continue
			var line := String(row(String(t["id"])).get("camp", ""))
			if line == "":
				continue
			t["told"] = true
			var kind := String(row(String(t["id"])).get("kind", ""))
			return {"text": line.replace("%s", ch.cname), "kind": "bad" if kind in ["scar", "wound"] else "good",
				"char_id": ch.id}
	return {}

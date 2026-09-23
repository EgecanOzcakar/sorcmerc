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
# much in a fight (spec §3). A placeholder like every other number here until
# the sweep (spec §9 step 2).
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
const ROLL_WHEN := ["bloodied", "first_round", "alone", "vs_faction", "vs_type", "dtype_in", "dtype_out"]
# The `gives` this build lands in a fight. Everything else is shown on the
# pages, marked not yet in play, so the player knows it is coming and never
# mistakes a line of text for a bonus they have. ac/to_hit/save/initiative
# with a fight-start `when` are stamped; with a roll `when` they are asked at
# the roll; damage, ward and save_adv are always asked at the roll.
const LIVE_GIVES := ["ac", "to_hit", "save", "initiative", "damage", "ward", "save_adv"]
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


static func row(id: String) -> Dictionary:
	return all().get(id, {})


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
		parts.append("against " + ", ".join(w["vs_faction"]))
	if w.has("vs_type"):
		parts.append("against " + " or ".join(w["vs_type"].map(func(t): return String(t) + "s")))
	if w.has("dtype_in"):
		parts.append("against " + " or ".join(w["dtype_in"]))
	if w.has("dtype_out"):
		parts.append("with " + " or ".join(w["dtype_out"]) + " attacks")
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
	var sum := {"ac": 0, "to_hit": 0, "initiative": 0, "save": {}}
	var who: Array = []
	for id in trait_ids:
		var used := false
		for e in row(id).get("effects", []):
			if not is_live(e) or _is_roll(e) or not holds(e.get("when", {}), where):
				continue
			var g: Dictionary = e["gives"]
			for k in ["ac", "to_hit", "initiative"]:
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
	for k in ["ac", "to_hit", "initiative"]:
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
	return ctx


static func _roll_holds(when: Dictionary, where: Dictionary, ctx: Dictionary, dtype_key: String) -> bool:
	if not holds(_static_part(when), where):
		return false
	for k in when:
		match k:
			"bloodied", "first_round", "alone":
				if bool(when[k]) != bool(ctx[k]):
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

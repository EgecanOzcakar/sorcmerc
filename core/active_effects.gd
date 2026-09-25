# What is riding on a combatant right now, said in words the action bar can
# show: one chip per buff, hindrance or held spell, and a short mark on each
# button that one of them changes ("ADV" on the attack a Hide set up, "✦" on
# the spells an armed Metamagic will ride).
#
# Why this exists: a status is otherwise invisible until it fires. An armed
# Quickened Spell, the Advantage a Help or a Vex left on the next swing, a
# Bless's +2, Poisoned's Disadvantage — all live in Combatant.statuses and all
# change what the next press does, but the only place any of them surfaced was
# the log line that set them, which scrolls away, and the token tags on the
# board, which say "poisoned" and not what that does to the button under your
# cursor. The bar is the one place a player is always looking when they decide.
#
# Pure and engine-free like the rest of core/: `of()` and `marks()` read the
# fight and return plain dictionaries, and scenes/main.gd draws them. Every
# number they quote comes from the payload the rules themselves read, and the
# Advantage marks come from Combat.cond_sources() — the list the attack roll
# weighs — so the bar cannot claim an edge the dice will not give.
#
# What it deliberately does not own: the effects themselves (core/combat.gd,
# core/potions.gd, core/traits.gd), the board's token tags (scenes/main.gd's
# HUD overlay, which is about everyone; this is about the one whose bar it is),
# and target-dependent odds (the hover card and the aim preview say those).
#
# Every status id the engine can set has to land somewhere here: a family below
# or HIDDEN. tests/test_active_effects.gd plays real fights across every kit and
# fails on an id that falls through to the generic chip, so a new mechanic
# cannot quietly add a buff the bar has no words for.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Potions = preload("res://core/potions.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Traits = preload("res://core/traits.gd")

# Tones, which is all the bar needs to colour a chip.
const EDGE := "edge"            # it helps you
const HINDRANCE := "hindrance"  # it hurts you
const MIXED := "mixed"          # both at once (Reckless Attack)
const HOLD := "hold"            # something you are keeping up (Concentration)

# Engine bookkeeping, never a chip: being dead, down or stable is the HP
# readout's job; the rest are flags other systems hang on a token.
const HIDDEN := ["dead", "down", "stable", "freed", "escaped", "captive", "bystander",
	"illusion", "summoned", "quarry",
	"withdrawn"]   # off the field (the audit's 3.5): not on the board, so no strip to draw it on

# The engine's own flags (Combat.ENGINE_CONDS and the handful set directly),
# in words. `clock` overrides the payload's clock, which for most of these is
# "until something spends it" rather than a count of rounds.
const ENGINE := {
	"dodging": {"label": "Dodging", "tone": EDGE, "clock": "until your turn",
		"detail": "Attacks against you have Disadvantage, and you make DEX saves with Advantage."},
	"disengaged": {"label": "Disengaged", "tone": EDGE, "clock": "this turn",
		"detail": "Moving away from enemies draws no opportunity attacks."},
	"hidden": {"label": "Hidden", "tone": EDGE, "clock": "next attack",
		"detail": "Your next attack has Advantage. Attacking gives your position away."},
	"helped": {"label": "Helped", "tone": EDGE, "clock": "next attack",
		"detail": "An ally's Help: Advantage on your next attack roll."},
	"reckless": {"label": "Reckless", "tone": MIXED, "clock": "until your turn",
		"detail": "Advantage on your attack rolls this turn, and attacks against you have Advantage until your next turn."},
	"sapped": {"label": "Sapped", "tone": HINDRANCE, "clock": "next attack",
		"detail": "Weapon mastery Sap: Disadvantage on your next attack roll."},
	"slowed": {"label": "Slowed", "tone": HINDRANCE,
		"detail": "Weapon mastery Slow: your speed is 10 feet lower."},
	"vex": {"label": "Vex", "tone": EDGE, "clock": "next attack",
		"detail": "Weapon mastery Vex: Advantage on your next attack against %s."},
	"inspired": {"label": "Inspired", "tone": EDGE, "clock": "one roll",
		"detail": "Bardic Inspiration: a d%d is added to your next failed attack roll or save."},
	"rallied": {"label": "Rallied", "tone": EDGE, "clock": "next attack",
		"detail": "A partner went down beside you: Advantage on your next attack."},
	"concentrating": {"label": "Concentrating", "tone": HOLD,
		"detail": "Taking damage calls for a CON save to keep %s going. A second concentration spell ends it."},
	"metamagic": {"label": "Metamagic", "tone": EDGE, "clock": "next spell",
		"detail": "%s is armed and rides the next spell it can. Unused by the end of the turn, the points come back."},
	"traits": {"label": "Traits", "tone": EDGE,
		"detail": "What this hero's traits add here: %s."},
}

# What each Metamagic option does, for the chip's tooltip.
const METAMAGIC_TEXT := {
	"quickened": "An action spell is cast as a Bonus Action. No other leveled spell this turn.",
	"twinned": "A spell that can target one more creature when upcast gets that extra target.",
	"careful": "Allies caught in the spell's area are spared.",
	"subtle": "Nobody sees it cast, so it cannot be Counterspelled.",
	"seeking": "If the spell attack misses, the d20 is rolled again, once.",
}

const TONE_ORDER := {EDGE: 0, MIXED: 1, HOLD: 2, HINDRANCE: 3}

# --- the chips ---------------------------------------------------------

# One chip per effect on `c`: {id, label, tone, clock, detail, family}.
# Ordered edges first, then mixed, held, and hindrances, each group by label,
# so a chip does not jump about as others come and go.
static func of(cb, c) -> Array:
	var out: Array = []
	for id in c.statuses:
		var chip := describe(cb, c, String(id))
		if not chip.is_empty():
			out.append(chip)
	out.sort_custom(func(a, b):
		var ta: int = TONE_ORDER.get(a["tone"], 9)
		var tb: int = TONE_ORDER.get(b["tone"], 9)
		return ta < tb or (ta == tb and String(a["label"]) < String(b["label"])))
	return out

# One status as a chip, {} for one the bar does not show.
static func describe(cb, c, id: String) -> Dictionary:
	if id in HIDDEN:
		return {}
	var s = c.statuses.get(id)
	var p: Dictionary = s if s is Dictionary else {}
	var chip := {"id": id, "label": id.capitalize(), "tone": EDGE, "clock": clock(cb, p), "detail": "", "family": ""}
	if ENGINE.has(id):
		var e: Dictionary = ENGINE[id]
		chip["family"] = "engine"
		chip["label"] = e["label"]
		chip["tone"] = e["tone"]
		if e.has("clock"):
			chip["clock"] = e["clock"]
		chip["detail"] = String(e["detail"])
		match id:
			"vex":
				var t = p.get("target")
				chip["detail"] = chip["detail"] % (t.cname if t != null and "cname" in t else "that target")
			"helped":
				var by = p.get("by")
				if by != null and "cname" in by:
					chip["detail"] = "%s's Help: Advantage on your next attack roll." % by.cname
			"inspired":
				chip["detail"] = chip["detail"] % int(p.get("dice_sides", 6))
				chip["label"] = "Inspired d%d" % int(p.get("dice_sides", 6))
			"concentrating":
				var sp := spell_name(String(p.get("spell", "")))
				chip["label"] = "Concentrating: %s" % sp
				chip["detail"] = chip["detail"] % sp
				if p.has("until_round"):
					chip["clock"] = rounds_text(int(p["until_round"]) - int(cb.round_num) + 1)
			"metamagic":
				var nm := String(p.get("label", "Metamagic"))
				chip["label"] = nm
				chip["detail"] = (chip["detail"] % nm) + " " + String(METAMAGIC_TEXT.get(String(p.get("option", "")), ""))
			"traits":
				var bits := phrases(p)
				if bits.is_empty():
					return {}
				chip["detail"] = chip["detail"] % ", ".join(bits)
				chip["tone"] = sign_tone(p)
		return chip
	if id.begins_with("spell:"):
		var sid := id.substr(6)
		chip["family"] = "spell"
		chip["label"] = spell_name(sid)
		chip["tone"] = _side_tone(c, p)
		chip["detail"] = _sentence(phrases(p))
		return chip
	if id.begins_with(Potions.STATUS_PREFIX):
		var pid := id.substr(Potions.STATUS_PREFIX.length())
		chip["family"] = "potion"
		chip["label"] = String(Catalog.magic_item(pid).get("name", pid.capitalize()))
		chip["tone"] = sign_tone(p)
		chip["detail"] = _sentence(phrases(p) if not phrases(p).is_empty() else [Potions.text(pid)])
		return chip
	var conds = Catalog.all("conditions.json")
	var cond: Dictionary = conds.get(id, {}) if conds is Dictionary else {}
	if not cond.is_empty() or id == "exhaustion":
		chip["family"] = "condition"
		chip["label"] = String(cond.get("name", id.capitalize()))
		chip["tone"] = EDGE if id == "invisible" else HINDRANCE
		chip["detail"] = String(cond.get("description", ""))
		if id == "exhaustion":
			chip["label"] = "Exhaustion %d" % int(p.get("level", 1))
		if p.has("held_by") and p["held_by"] != null and "cname" in p["held_by"]:
			chip["detail"] += " (%s)" % p["held_by"].cname
		return chip
	# A feature's buff: Rage, a Smite, Innate Sorcery... Named by the button that
	# set it, which is on this same combatant.
	var src := source_verb(c, id)
	if not src.is_empty() or not phrases(p).is_empty():
		chip["family"] = "feature"
		if not src.is_empty():
			chip["label"] = String(src.get("label", chip["label"]))
		chip["tone"] = sign_tone(p)
		if p.get("once", false):
			chip["clock"] = "next hit"
		elif String(p.get("duration", "")) == "rage":
			chip["clock"] = "while raging"
		chip["detail"] = _sentence(phrases(p))
		return chip
	chip["family"] = "unknown"   # tests/test_active_effects.gd fails on this
	return chip

# The verb on `c` whose status this is (a self_buff's `status`, or its id).
static func source_verb(c, id: String) -> Dictionary:
	for v in c.verbs:
		if String(v.get("status", "")) == id or String(v.get("id", "")) == id:
			return v
	return {}

static func spell_name(sid: String) -> String:
	if sid == "":
		return "a spell"
	return String(Catalog.spell(sid).get("name", sid.capitalize()))

# "3 rd", "next turn"... from an until_tick. Ticks run round * stride + turn.
static func clock(cb, p: Dictionary) -> String:
	if not p.has("until_tick"):
		return ""
	var left: int = int(p["until_tick"]) - int(cb._tick())
	return rounds_text(ceili(float(left) / float(cb.TICK_STRIDE)))

static func rounds_text(n: int) -> String:
	if n <= 1:
		return "1 round"
	return "%d rounds" % n

# The payload keys the rules read, as short phrases.
static func phrases(p: Dictionary) -> Array:
	var out: Array = []
	var signed := func(n: int) -> String: return ("+%d" % n) if n >= 0 else str(n)
	if int(p.get("bonus_to_hit", 0)) != 0:
		out.append("%s to hit" % signed.call(int(p["bonus_to_hit"])))
	if int(p.get("ac", 0)) != 0:
		out.append("%s AC" % signed.call(int(p["ac"])))
	if int(p.get("bonus_save", 0)) != 0:
		out.append("%s to saves" % signed.call(int(p["bonus_save"])))
	if int(p.get("bonus_damage", 0)) != 0:
		out.append("%s damage" % signed.call(int(p["bonus_damage"])))
	if int(p.get("dice_count", 0)) > 0:
		out.append("+%dd%d damage%s" % [int(p["dice_count"]), int(p.get("dice_sides", 6)),
			" on your next hit" if p.get("once", false) else ""])
	if p.get("resist", []) is Array and not p.get("resist", []).is_empty():
		out.append("resistance to %s" % ", ".join(p["resist"]))
	if int(p.get("extra_action", 0)) > 0:
		out.append("an extra action each turn")
	if float(p.get("speed_mult", 1.0)) != 1.0:
		out.append("speed ×%s" % str(p["speed_mult"]))
	if p.get("no_attack", false):
		out.append("cannot attack")
	if int(p.get("spell_dc_bonus", 0)) != 0:
		out.append("%s spell save DC" % signed.call(int(p["spell_dc_bonus"])))
	if p.get("spell_attack_adv", false):
		out.append("Advantage on spell attacks")
	var e: Dictionary = p.get("effects", {}) if p.get("effects", {}) is Dictionary else {}
	match String(e.get("own_attacks", "")):
		"adv": out.append("Advantage on your attacks")
		"dis": out.append("Disadvantage on your attacks")
	match String(e.get("attacks_against", "")):
		"adv": out.append("attacks against you have Advantage")
		"dis": out.append("attacks against you have Disadvantage")
	return out

static func _sentence(bits: Array) -> String:
	var t := "; ".join(bits.filter(func(b): return String(b) != ""))
	return (t.substr(0, 1).to_upper() + t.substr(1) + ".") if t != "" else ""

# Helps or hurts, by the sign of what it changes. Faerie Fire's "attacks
# against you have Advantage" hurts; Blur's Disadvantage helps.
static func sign_tone(p: Dictionary) -> String:
	var n := 0
	for k in ["bonus_to_hit", "ac", "bonus_save", "bonus_damage", "spell_dc_bonus"]:
		n += signi(int(p.get(k, 0)))
	var e: Dictionary = p.get("effects", {}) if p.get("effects", {}) is Dictionary else {}
	n += {"adv": 1, "dis": -1}.get(String(e.get("own_attacks", "")), 0)
	n += {"adv": -1, "dis": 1}.get(String(e.get("attacks_against", "")), 0)
	if p.get("no_attack", false):
		n -= 1
	return HINDRANCE if n < 0 else EDGE

# A spell on you: whose side cast it decides, where the payload says; the
# numbers decide where it does not (a concentration-free buff keeps no caster).
static func _side_tone(c, p: Dictionary) -> String:
	var by = p.get("held_by")
	if by != null and "team" in by:
		return EDGE if by.team == c.team else HINDRANCE
	return sign_tone(p)

# --- the marks on the buttons ------------------------------------------

# What the effects on `c` do to pressing `v` now: [{text, tone, why}], most
# telling first. Empty for a button nothing touches.
static func marks(cb, c, v: Dictionary) -> Array:
	var out: Array = []
	var kind := String(v.get("kind", ""))
	if kind in ["attack", "offhand_attack"]:
		var adv: Array = []
		var dis: Array = []
		for pair in cb.cond_sources(c):
			var o = pair[1].get("own_attacks", "")
			var who := _chip_label(cb, c, String(pair[0]))
			if o == "adv":
				adv.append(who)
			elif o == "dis":
				dis.append(who)
		if c.has(PartyOpinion.RALLY_STATUS):
			adv.append("Rallied")
		var vx = c.statuses.get("vex")
		if vx is Dictionary and vx.get("target") != null:
			adv.append("Vex (against %s only)" % vx["target"].cname)
		out.append_array(_mode_mark(adv, dis))
		for id in c.statuses:
			var s = c.statuses[id]
			if s is Dictionary and s.get("once", false) and int(s.get("dice_count", 0)) > 0:
				out.append({"text": "+%dd%d" % [int(s["dice_count"]), int(s.get("dice_sides", 6))], "tone": EDGE,
					"why": "%s adds %dd%d damage to this hit." % [_chip_label(cb, c, String(id)), int(s["dice_count"]), int(s.get("dice_sides", 6))]})
	elif kind == "spell":
		var opt: String = cb.metamagic_for(c, v)
		if opt != "":
			var nm := String(c.statuses.get("metamagic", {}).get("label", opt.capitalize()))
			out.append({"text": "✦", "tone": EDGE, "why": "%s will ride this spell. %s" % [nm, METAMAGIC_TEXT.get(opt, "")]})
		if v.has("attack_bonus"):
			var srcs: Array = []
			for id in c.statuses:
				var s = c.statuses[id]
				if s is Dictionary and s.get("spell_attack_adv", false):
					srcs.append(_chip_label(cb, c, String(id)))
			out.append_array(_mode_mark(srcs, []))
	return out

static func _mode_mark(adv: Array, dis: Array) -> Array:
	if not adv.is_empty() and not dis.is_empty():
		return [{"text": "±", "tone": MIXED,
			"why": "Advantage (%s) and Disadvantage (%s) cancel: a single d20." % [", ".join(adv), ", ".join(dis)]}]
	if not adv.is_empty():
		return [{"text": "ADV", "tone": EDGE, "why": "Advantage: %s." % ", ".join(adv)}]
	if not dis.is_empty():
		return [{"text": "DIS", "tone": HINDRANCE, "why": "Disadvantage: %s." % ", ".join(dis)}]
	return []

static func _chip_label(cb, c, id: String) -> String:
	var chip := describe(cb, c, id)
	return String(chip.get("label", id.capitalize())) if not chip.is_empty() else id.capitalize()

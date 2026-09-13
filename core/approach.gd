# D4 — meeting a band on the road is a decision, not an event.
#
# Until now a hostile party closing to within ENCOUNTER_RADIUS dropped the
# player straight into a fight: the encounter happened TO them. That is Mount &
# Blade's blob-bumps-blob, and it is the thing the 2026-09-13 scope revision set
# out to remove. Now the clock stops and the party picks how to meet them.
#
#   var opts := Approach.options(party, foe)        # what can be tried, and at what DC
#   var out := Approach.resolve(party, foe, "ambush")
#   if out["fight"]: world.gd launches the fight with out's surprise flags
#
# Four ways, and they are a real spread rather than four flavours of "fight":
#
#   engage   no roll, no edge, no risk of a worse one. The baseline.
#   ambush   a gamble for the biggest prize in 5e, the first round. Pass and the
#            party gets the drop; FAIL AND THEY DO. Without that downside ambush
#            would strictly dominate engage and there would be no decision here.
#   avoid    no fight at all, which also means no XP and no loot — that is the
#            cost, and it is why avoiding everything is a choice rather than an
#            exploit. Fail and they catch the party mid-slip, badly.
#   parley   talk past it. Anything that wants something can be offered it —
#            bandits most of all — and the toll is the price of the fight not
#            happening. The mindless are the exception; see MINDLESS below.
#
# Every one of them runs on machinery that already exists: the surprise flags
# are scenes/main.tscn's own `scouted_ahead`/`forced_ambush` (T39), the skill
# rolls are the same "name the check, name the roll" shape as world_lairs.search
# and world_camp.watch_check, and the standing orders from D3 (core/travel.gd)
# decide who rolls and at what bonus. Nothing new is invented; it is wiring.
#
# What this does NOT own: the fight (scenes/main.tscn, unchanged), what a won
# fight pays (world.gd's _bank), faction opinion, or any drawing.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Travel = preload("res://core/travel.gd")

# The DCs. Flat, not scaled to the band: what the party is rolling against is
# noticing and being noticed, which is about ground and care rather than about
# how hard the other side hits. Ambush is the hardest because it asks to be
# unseen while closing, avoid only asks to be unseen while leaving.
const AVOID_DC := 13
const AMBUSH_DC := 15
const PARLEY_DC := 14

# Which standing order does the job, and which skill it rolls. Scout for the
# two that are about reading ground; parley is nobody's standing order, so it
# falls to whoever in the party can actually talk.
# `win` and `lose` are what the card puts on the row, and they are not flavour:
# a row that shows only what a way BUYS makes every way that rolls look better
# than the one that does not, and engage — the only way that cannot go wrong —
# reads as the option with nothing on it. The gamble is the point of this card,
# so both halves of every gamble are stated, in the same words the resolution
# will use. Engage has no `lose` because there is nothing to fail.
const WAYS := {
	"engage": {"label": "Engage", "role": "", "skills": [], "dc": 0,
		"note": "Straight at them. No edge, no surprises.",
		"win": "An even fight, full XP and loot. Nothing can go wrong first."},
	"ambush": {"label": "Set an ambush", "role": "scout", "skills": ["stealth", "survival"],
		"dc": AMBUSH_DC, "note": "Take the first round — or hand it to them.",
		"win": "The party takes the first round.",
		"lose": "THEY take the first round, and the fight happens anyway."},
	"avoid": {"label": "Slip away", "role": "scout", "skills": ["stealth"], "dc": AVOID_DC,
		"note": "No fight, and nothing to show for it.",
		"win": "No fight — and no XP, no loot, nothing.",
		"lose": "Seen mid-slip: they take the first round, and you fight strung out."},
	"parley": {"label": "Parley", "role": "", "skills": ["persuasion", "deception"],
		"dc": PARLEY_DC, "note": "Buy your way past. They will want something.",
		"win": "No fight. The toll is %d gold, and there is no loot.",
		# A purse with nothing in it: _toll() caps at what the party actually has,
		# so the line has to stop saying "0 gold" and say what that means.
		"win_broke": "No fight. They take what you are carrying, which is nothing.",
		"lose": "They were never going to be talked to. A plain, even fight."},
}
# Order they are offered in: the safe one first, the gamble last, so the list
# reads as an escalation rather than a menu.
const ORDER := ["avoid", "parley", "ambush", "engage"]

# What talking past a band costs. A share of the purse rather than a flat fee —
# a toll that is trivial at 500 gold and impossible at 30 is not a decision.
const TOLL_PCT := 0.12
const TOLL_MIN := 15


# Who can be talked to is NOT the question WorldAI.CIVILIZED answers. That list
# is ["dwarf", "elf", "human"] and it decides whose settlements open their gates
# — by it a bandit is a "monster", and a bandit wanting paid is the most
# obviously bribable thing on the map. Undead and beasts are the ones that
# cannot be offered anything.
#
# So this is its own list, and it is a deny-list: most things that raid you want
# something, so a faction talks unless it is named here. Fey and dragons very
# much negotiate — that is most of what they are for.
const MINDLESS := ["beast", "undead", "monstrosity", "elemental", "construct"]

static func can_parley(foe) -> bool:
	return not MINDLESS.has(foe.faction)


# What this party can try against this band, each with the check it would roll
# and by whom — so the card can show "Vera Kord, Stealth vs DC 13" on the button
# BEFORE it is pressed. A choice you cannot price is not a choice.
static func options(party, foe) -> Array:
	var out: Array = []
	for id in ORDER:
		if id == "parley" and not can_parley(foe):
			continue
		var w: Dictionary = WAYS[id]
		var o: Dictionary = {"id": id, "label": String(w["label"]), "note": String(w["note"]),
			"dc": int(w["dc"])}
		if not w["skills"].is_empty():
			var who := _roller(party, w)
			if who.is_empty():
				continue          # nobody can roll it: do not offer it
			var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
			o.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
				"bonus": bonus, "named": bool(who["named"]),
				"needs": needs(int(w["dc"]), bonus)}, true)
		# What it buys and what it costs, both, before the press. The toll is the
		# real number the party would actually pay — "they will want something" is
		# not a price anybody can weigh against a fight.
		if id == "parley":
			var toll: int = _toll(party)
			o["win"] = String(w["win"]) % toll if toll > 0 else String(w["win_broke"])
		else:
			o["win"] = String(w.get("win", ""))
		if w.has("lose"):
			o["lose"] = String(w["lose"])
		if id == "parley":
			o["toll"] = _toll(party)
		out.append(o)
	return out


# The face the d20 has to come up, which is the only honest way to show odds in
# a game whose whole vocabulary is d20s. Ability checks have no natural 1/20
# rule in 5.5e, so a bonus big enough really is a certainty and a DC far enough
# out of reach really is impossible — and a card that showed "needs 23" as if it
# could happen would be lying about the only number on it that matters.
#
# 0 means it cannot fail; 21 means it cannot pass.
static func needs(dc: int, bonus: int) -> int:
	return clampi(dc - bonus, 0, 21)


# Take a way. Returns what happened and, crucially, what the fight should be if
# there is one — world.gd passes `scouted_ahead`/`forced_ambush` straight into
# the combat scene, which already knows what to do with them (T39).
#
#   {way, ok, fight, scouted_ahead, forced_ambush, text, + the roll, + toll}
static func resolve(party, foe, way: String, rng = null) -> Dictionary:
	if not WAYS.has(way):
		return {}
	var w: Dictionary = WAYS[way]
	var out: Dictionary = {"way": way, "fight": true,
		"scouted_ahead": false, "forced_ambush": false}
	if way == "engage":
		out["ok"] = true
		out["text"] = "The party goes straight at them."
		return out

	var who := _roller(party, w)
	if who.is_empty():
		# Nobody to roll: the attempt is simply not made, and it is a plain
		# fight rather than a silent failure the player cannot account for.
		out["ok"] = false
		out["text"] = "Nobody here can manage that. They are on you anyway."
		return out
	if rng == null:
		rng = RNG.new()
	var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= int(w["dc"])
	out.merge({"ok": ok, "char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
		"nat": nat, "bonus": bonus, "dc": int(w["dc"]), "named": bool(who["named"])}, true)

	match way:
		"avoid":
			out["fight"] = not ok
			out["forced_ambush"] = not ok
			out["text"] = ("%s takes them wide around it. Nobody ever knew they were there."
				% who["cname"]) if ok else (
				"%s is seen. They come in fast, and the party is still strung out."
				% who["cname"])
		"ambush":
			out["scouted_ahead"] = ok
			out["forced_ambush"] = not ok
			out["text"] = ("%s picks the ground and the party settles in to wait."
				% who["cname"]) if ok else (
				"%s moves too early. They see it coming and turn it around."
				% who["cname"])
		"parley":
			out["fight"] = not ok
			out["forced_ambush"] = false
			if ok:
				var toll: int = _toll(party)
				party.spend_gold(toll)
				out["toll"] = toll
				out["text"] = "%s talks them down. They take %d gold to have seen nobody." % [
					who["cname"], toll]
			else:
				out["text"] = "%s gets nowhere. They were never going to be talked to." % who["cname"]
	return out


# A share of what the party is carrying, floored so it is never pocket change.
# Capped at the purse: a band cannot take gold the party does not have, and the
# alternative to paying was a fight they just avoided.
static func _toll(party) -> int:
	return mini(party.gold, maxi(TOLL_MIN, int(round(party.gold * TOLL_PCT))))


# Who rolls: the standing order for the job if one is set (D3), otherwise the
# party's best at it. `named` says which, so the card can credit the player's
# own order — the same feedback loop core/travel.gd runs on.
static func _roller(party, w: Dictionary) -> Dictionary:
	var c = Campaign.new(party)
	var role := String(w.get("role", ""))
	var ordered := String(Travel.orders(party).get(role, "")) if role != "" else ""
	var best_id := ""
	var best_skill := ""
	var best_bonus := -99
	for skill in w["skills"]:
		if ordered != "":
			var ob: int = c.skill_bonus(ordered, String(skill))
			if ob > best_bonus:
				best_bonus = ob
				best_id = ordered
				best_skill = String(skill)
			continue
		var id: String = c.best_at(String(skill))
		if id == "":
			continue
		var b: int = c.skill_bonus(id, String(skill))
		if b > best_bonus:
			best_bonus = b
			best_id = id
			best_skill = String(skill)
	if best_id == "":
		return {}
	var ch = party.get_member(best_id)
	return {"id": best_id, "cname": ch.cname if ch != null else "Someone",
		"skill": best_skill, "bonus": best_bonus, "named": best_id == ordered and ordered != ""}

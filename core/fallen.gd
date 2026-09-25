# The fallen — what a merc's death does to the company, and the roll that
# remembers them.
#
# The design audit (docs/audit-game-design.md §2.1) found that a death barely
# registered: one line on the spoils page ("Vera Kord did not get up."), the
# witness's hardship asked of anyone at fifty-fifty whoever had died — a lover
# and yesterday's hire weighed the same — no opinion event, no memorial, and
# the achievement that counts deaths counted only in the linear campaign. The
# owner's call was all four parts of the fix, and this file is the one door
# the open world applies a death through, so all four happen together:
#
#   Fallen.apply(party, result, ctx)   # mark, bench, count, roll, grieve, mourn
#   Fallen.roll(party)                 # [entry], oldest first — the lodge's wall, the party page
#   Fallen.line(entry)                 # "Vera Kord, fighter 3. Fell to an ogre on the road near Riverhold, on day 6."
#   Fallen.raised(party, entry)        # raised since (a healer, Revivify): still on the roll, marked
#   Fallen.camp_beat(party, now)       # the fire's one line about the dead, once each
#   Fallen.to_dict(party) / from_dict(party, d)   # the save's party["fallen"]
#
# apply() takes Encounter.resolve_outcome's result and, for each of its
# `deaths` not already dead (so a second call on the same fight — the road's
# defeat path makes two — changes nothing):
#   1. reads who was close to them (PartyOpinion.close_to: bonded or lovers,
#      anywhere on the roster, the bench included) BEFORE anything moves;
#   2. marks them dead and benches them, as the old world.gd _apply_deaths did;
#   3. counts the death toward "The Cost of Doing Business" (Ach "deaths"),
#      which only the linear campaign used to bump;
#   4. writes them on the roll: who, what level and class, where and to what
#      they fell, and the world-day;
#   5. asks each of the close ones for grief (Traits.grieve): guaranteed, at a
#      higher DC than the witness's save, harder still for a lover;
#   6. and tells the relations web (PartyOpinion.mourn): the ones who grieve
#      together draw closer, and the ones who loved them hold it against
#      whoever walked away from that fight.
# ctx is {"now": world minutes, "where": a phrase — "on the road near
# Riverhold", "in The Vale Warren"}, and it returns {"moments", "lines"} in
# Traits.after_fight's shape, for the spoils page and the trait moment.
#
# The roll lives on the party (party.fallen), saved beside the lodge and the
# relations in core/world_save.gd and core/campaign_save.gd; a save from before
# it reads as an empty roll. A death is on it for good: a hero raised later is
# still listed, marked raised, because the company did lose them for a while.
#
# THE DEAD STAY OUT OF THE VETERAN POOL (§2.1's third part) is core/recruits.gd's
# rule, not this file's: the barracks file of a hero who died and was never
# raised still says dead, and an inn does not offer the dead.
#
# What this does NOT own: the witness's hardship for everyone else in the fight
# (core/traits.gd after_fight), raising the dead (core/party.gd resurrect, the
# healer in core/settlement_visit.gd), the defeat's revive of the downed
# (Party.revive_downed), the linear campaign's own death rule (core/campaign.gd
# finish_combat), or the pages (scenes/world/world.gd's lodge page and fire,
# scenes/party/party.gd).
extends RefCounted

const Traits = preload("res://core/traits.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const DAY := 1440.0   # world minutes

# The fire's line about the dead, said once for each (camp_beat). The
# mourner's lines need somebody at the fire — marching, and close to them —
# and name that one first; the company's are for a death nobody at the fire
# was close to.
const BEAT_MOURNER := [
	"%s sets out a cup for %s and does not drink from it.",
	"%s tells the others how %s came to be with the company. Nobody interrupts.",
	"%s takes %s's watch as well as their own, and does not ask anyone to share it.",
]
const BEAT_COMPANY := [
	"The company says %s's name once at the fire, and nothing else.",
	"Nobody sits where %s used to sit.",
]


static func roll(party) -> Array:
	return party.fallen


# --- the one door a death comes through ---------------------------------------

static func apply(party, result: Dictionary, ctx := {}) -> Dictionary:
	var out := {"moments": [], "lines": []}
	var now := float(ctx.get("now", 0.0))
	var dying: Array = []
	for id in result.get("deaths", []):
		var ch = party.get_member(String(id))
		if ch != null and not ch.dead:
			dying.append(String(id))
	if dying.is_empty():
		return out
	# Who marched in this fight and walked away from it: read before anyone is
	# benched, since bench() takes the dead out of `active`.
	var walked: Array = Array(party.active).filter(func(a): return not String(a) in dying)
	var credit: Dictionary = result.get("credit", {})
	# Everyone's bonds first, from the party as the fight left it: two heroes
	# who die in the same fight do not grieve each other.
	var close := {}
	for id in dying:
		close[id] = PartyOpinion.close_to(party, id).filter(func(c):
			var m = party.get_member(String(c))
			return m != null and not m.dead and not String(c) in dying)
	for id in dying:
		var ch = party.get_member(id)
		var by := _killer(credit, id)
		ch.dead = true
		party.bench(id)
		Ach.bump("deaths")
		party.fallen.append({"id": id, "name": ch.cname, "level": ch.level(), "class": ch.class_id(),
			"species": ch.species_id, "where": String(ctx.get("where", "")), "by": by,
			"day": int(now / DAY) + 1, "at": now, "told": false})
		for c in close[id]:
			var lover: bool = PartyOpinion.status(party, id, String(c)) == "lovers"
			var g: Dictionary = Traits.grieve(party.get_member(String(c)), ch, lover, by, now)
			out["moments"].append_array(g["moments"])
			out["lines"].append_array(g["lines"])
		PartyOpinion.mourn(party, id, close[id], walked)
	return out


# What killed them: the last thing to put them down (the fight's credit), a
# monster id or a hero's id for friendly fire; "" when nothing is credited.
static func _killer(credit: Dictionary, id: String) -> String:
	var downs: Array = credit.get(id, {}).get("downed_by", [])
	return String(downs.back().get("by", "")) if not downs.is_empty() else ""


# --- reading the roll ---------------------------------------------------------

static func raised(party, entry: Dictionary) -> bool:
	var ch = party.get_member(String(entry.get("id", "")))
	return ch != null and not ch.dead


# One line for the wall: "Vera Kord, fighter 3. Fell to an ogre on the road
# near Riverhold, on day 6." `party`, when given, names a hero who killed them
# by name and marks one raised since.
static func line(entry: Dictionary, party = null) -> String:
	var cls := String(entry.get("class", ""))
	var who := "%s, %s %d" % [String(entry.get("name", "")),
		String(Catalog.class_src(cls).get("name", cls.capitalize())).to_lower() if cls != "" else "merc",
		int(entry.get("level", 1))]
	var by := String(entry.get("by", ""))
	var what := "Fell"
	if by != "":
		var hero = party.get_member(by) if party != null else null
		what = "Fell to %s" % (hero.cname if hero != null else _a(String(Catalog.monster(by).get("cname", by.capitalize()))))
	var where := String(entry.get("where", ""))
	var text := "%s. %s%s, on day %d." % [who, what, (" " + where) if where != "" else "", int(entry.get("day", 1))]
	if party != null and raised(party, entry):
		text += " Raised since."
	return text


# "an ogre", "a goblin boss": a bestiary name as it reads mid-sentence.
static func _a(name: String) -> String:
	var n := name.to_lower()
	return ("an " if n.left(1) in ["a", "e", "i", "o", "u"] else "a ") + n


# --- the fire -------------------------------------------------------------------

# The first death the fire has not spoken of yet: {"text", "kind": "bad",
# "char_id"} or {}, and the entry is marked told, so each is said once. A
# mourner at the fire — marching, alive, and close to the dead (bonds read as
# they stand tonight) — says it; with none, the company does. A hero raised
# before the fire got to them needs no line, and is marked told unspoken.
# Seeded off the dead and the minute they fell, so a reload says the same line.
static func camp_beat(party, now: float) -> Dictionary:
	for e in party.fallen:
		if bool(e.get("told", false)) or float(e.get("at", 0.0)) > now:
			continue
		e["told"] = true
		if raised(party, e):
			continue
		var id := String(e["id"])
		var h := absi(hash("fallen|%s|%d" % [id, int(float(e.get("at", 0.0)))]))
		var mourner = null
		for a in party.active:
			var m = party.get_member(String(a))
			if m != null and not m.dead and PartyOpinion.is_close(party, id, String(a)):
				mourner = m
				break
		if mourner != null:
			return {"text": String(BEAT_MOURNER[h % BEAT_MOURNER.size()]) % [mourner.cname, String(e["name"])],
				"kind": "bad", "char_id": mourner.id}
		return {"text": String(BEAT_COMPANY[h % BEAT_COMPANY.size()]) % String(e["name"]), "kind": "bad", "char_id": ""}
	return {}


# --- persistence ------------------------------------------------------------------

static func to_dict(party) -> Array:
	return party.fallen.duplicate(true)

# JSON gives the level and the day back as floats; they are printed as ints.
static func from_dict(party, d) -> void:
	party.fallen = []
	if not d is Array:
		return
	for e in d:
		if not (e is Dictionary and e.has("id")):
			continue
		party.fallen.append({"id": String(e["id"]), "name": String(e.get("name", e["id"])),
			"level": int(e.get("level", 1)), "class": String(e.get("class", "")),
			"species": String(e.get("species", "")), "where": String(e.get("where", "")),
			"by": String(e.get("by", "")), "day": int(e.get("day", 1)), "at": float(e.get("at", 0.0)),
			"told": bool(e.get("told", false))})

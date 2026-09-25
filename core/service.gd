# The service record — what a merc has done, read back to the player.
#
# The design audit (docs/audit-game-design.md §2.2) found the counting already
# there and nobody reading it: core/traits.gd keeps kills per faction, won
# fights and downs on every hero (ch.trait_counts) because a bane is ten kills
# of one people and Veteran is twenty wins, but no page showed those numbers,
# so the player could not see a bane coming, and the earned traits kept their
# reason and their day where nothing printed them. This file is the reading:
# the profile's Service panel, a trait's origin line, the inn's record of a
# veteran from earlier runs, and who struck the blow on the spoils page.
#
#   Service.record(ch)             # {fights, wins, downs, kills: {faction: n}, kills_total, runs, scars}
#   Service.progress(ch)           # {banes: [{faction, name, kills, need, held, room}], veteran: {...}}
#   Service.origin_line(ch, id)    # "Earned on day 4: 10 goblins killed", "" for one they were born with
#   Service.veteran_line(ch)       # the inn's line for a veteran: "Two companies before this one: ..."
#   Service.enlist(ch)             # they have joined a company: one more run served
#   Service.kill_lines(result, party)   # the spoils page's kills, each with who struck the blow
#
# Progress is derived from the SAME constants the trait rules earn by —
# Traits.BANE_KILLS, BANE_KILLS_DRAGON, VETERAN_WINS and Traits.refusal(), the
# caps grant() obeys — so the panel can never promise a bane the rules would
# not hand over, and a retune of one moves both.
#
# The counts live in ch.trait_counts, saved by core/character_save.gd with
# every other count, so an old save reads a missing key as 0 and needs nothing
# new: "kill:<faction>", "wins" and "downed:<faction>" are core/traits.gd's own
# (after_fight); "fights" is counted there too, since this record exists, and
# "runs" is counted here, by enlist(), when a hero joins a company — the
# founder when the run begins (scenes/game/game.gd), a hire when the fee is
# paid (core/recruits.gd).
#
# What this does NOT own: the counting of kills, wins and downs (core/traits.gd
# after_fight), the traits themselves, the pages that draw it
# (scenes/profile/profile.gd, scenes/world/world.gd's inn row and spoils page),
# or the roll of the fallen (core/fallen.gd).
extends RefCounted

const Traits = preload("res://core/traits.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const DAY := 1440.0   # world minutes
const WORDS := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


static func _count(ch, key: String) -> int:
	return int(ch.trait_counts.get(key, 0))


static func word(n: int) -> String:
	return WORDS[n] if n >= 0 and n < WORDS.size() else str(n)


# What they have done, in numbers. `fights` is never below `wins`: a hero from
# before fights were counted has won more than the new count has seen, and a
# record that says "12 fights, 14 won" reads as a bug. `runs` is the companies
# they have served with, this one included once they are on its roster.
static func record(ch) -> Dictionary:
	var kills := {}
	var total := 0
	var downs := 0
	for k in ch.trait_counts:
		var key := String(k)
		if key.begins_with("kill:"):
			kills[key.substr(5)] = int(ch.trait_counts[k])
			total += int(ch.trait_counts[k])
		elif key.begins_with("downed:"):
			downs += int(ch.trait_counts[k])
	var wins := _count(ch, "wins")
	var scars: int = Traits.ids(ch).filter(func(i): return String(Traits.row(i).get("kind", "")) == "scar").size()
	return {"fights": maxi(_count(ch, "fights"), wins), "wins": wins, "downs": downs, "kills": kills,
		"kills_total": total, "runs": _count(ch, "runs"), "scars": scars}


# The factions they have killed, most first (ties by name, so the panel does
# not reshuffle between two looks).
static func kill_order(ch) -> Array:
	var kills: Dictionary = record(ch)["kills"]
	var fs: Array = kills.keys()
	fs.sort_custom(func(a, b): return kills[a] > kills[b] or (kills[a] == kills[b] and String(a) < String(b)))
	return fs


# How far each bane and Veteran are. A bane row per faction they have killed
# any of: `need` is the rules' count for it (three for dragons), `held` whether
# they carry it, and `room` "" or the reason grant() would turn it down now (two
# banes already, four triumphs already). A count at or past `need` with room and
# no bane yet is due: after_fight grants one mark a fight, so a bane that met
# its count in a fight that also brought another triumph comes with the next
# kill. Veteran is the same shape off `wins`.
static func progress(ch) -> Dictionary:
	var banes: Array = []
	for f in kill_order(ch):
		var id := "bane@" + String(f)
		var held := Traits.has(ch, id)
		banes.append({"faction": String(f), "name": Traits.name_of(id), "kills": _count(ch, "kill:" + String(f)),
			"need": Traits.BANE_KILLS_DRAGON if String(f) == "dragon" else Traits.BANE_KILLS,
			"held": held, "room": "" if held else Traits.refusal(ch, id)})
	var vet_held := Traits.has(ch, "veteran")
	return {"banes": banes, "veteran": {"wins": _count(ch, "wins"), "need": Traits.VETERAN_WINS,
		"held": vet_held, "room": "" if vet_held else Traits.refusal(ch, "veteran")}}


# Where an earned trait came from and when: "Earned on day 4: 10 goblins
# killed." Read off the trait's own stored "why" and "since" (core/traits.gd
# grant()). A trait they were born with or picked in the creator has no
# "since" and says nothing — its text is the whole story.
static func origin_line(ch, id: String) -> String:
	var t: Dictionary = Traits.entry(ch, id)
	if t.is_empty() or not t.has("since"):
		return ""
	var why := String(t.get("why", ""))
	var day := int(float(t["since"]) / DAY) + 1
	return "Earned on day %d: %s." % [day, why.left(1).to_lower() + why.substr(1)] if why != "" \
		else "Earned on day %d." % day


# They have signed on with a company — the founder as the run begins, a hire
# as the fee is paid. Counted once per joining, so a veteran hired into a new
# run has one more than the record the inn showed.
static func enlist(ch) -> int:
	return Traits.bump(ch, "runs")


# The inn's line for a veteran out of the barracks (core/recruits.gd): the
# record of their earlier runs, so the chair says who this is rather than
# "(a veteran)". A barracks hero from before runs were counted served at least
# the one run that filed them there.
static func veteran_line(ch) -> String:
	var r := record(ch)
	var runs: int = maxi(1, int(r["runs"]))
	var scars := "no scars" if int(r["scars"]) == 0 else "%s scar%s" % [word(int(r["scars"])), "" if int(r["scars"]) == 1 else "s"]
	return "%s %s before this one: %d fight%s, %d kill%s, %s." % [word(runs).capitalize(),
		"company" if runs == 1 else "companies", int(r["fights"]), "" if int(r["fights"]) == 1 else "s",
		int(r["kills_total"]), "" if int(r["kills_total"]) == 1 else "s", scars]


# The kills of one fight, each kind once with its count and what it was worth,
# and who struck the blow (result["credit"], Encounter.resolve_outcome): "Vera
# Kord ×2, Pike". A kill nobody on the party's side is credited with — a
# hazard, a summon's — counts in `count` and names nobody. Returns
# [{"id", "name", "count", "xp", "by"}], in the order the kills came.
static func kill_lines(result: Dictionary, party) -> Array:
	var counts := {}
	var order: Array = []
	for k in result.get("kills", []):
		var id := String(k)
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var by := {}    # monster id -> {hero id: n}, heroes in the order credit lists them
	var credit: Dictionary = result.get("credit", {})
	for hero in credit:
		for k in credit[hero].get("kills", []):
			var per: Dictionary = by.get(String(k), {})
			per[String(hero)] = int(per.get(String(hero), 0)) + 1
			by[String(k)] = per
	var out: Array = []
	for id in order:
		var m: Dictionary = Catalog.monster(id)
		var names: Array = []
		var per: Dictionary = by.get(id, {})
		for hero in per:
			var ch = party.get_member(String(hero)) if party != null else null
			var nm: String = ch.cname if ch != null else String(hero)
			names.append(nm if int(per[hero]) == 1 else "%s ×%d" % [nm, int(per[hero])])
		out.append({"id": id, "name": String(m.get("cname", id.capitalize())), "count": int(counts[id]),
			"xp": int(m.get("xp", 0)) * int(counts[id]), "by": ", ".join(names)})
	return out

# The bench — how long a merc has sat out, and what that does to them.
#
# The owner's call (the design audit, docs/audit-game-design.md §2.4): keep "no
# wages". A company that pays nobody by the day has no running cost for a
# roster of twelve, so the bench was free: hire a spare of every class, leave
# them in the wagon, and nothing ever asked about them. What asks now is the
# merc. They signed on to fight. Left out of the marching order long enough, a
# merc grows RESTLESS — the company is told, once, in words — and if they are
# still left out after that, one morning they may be gone.
#
#   Bench.tick(party, now)          # at most one told beat, or {}: {kind, id, name, text[, ch]}
#   Bench.sync(party, now)          # start the clock on the newly benched, stop it on the marching
#   Bench.days(party, id, now)      # whole days on the bench, 0 for anyone marching
#   Bench.restless(party, id)       # warned, and not marched since
#   Bench.founder(party)            # the one who never leaves
#   Bench.to_dict(party) / from_dict(party, d)   # the save's party["bench"]
#   Bench.rotation_refusal(world, under_roof, guest)   # "" where who marches may change, else why not
#
# The clock. party.bench_clock is id -> {"since": world-minute, "warned": bool}.
# It is kept LAZILY rather than stamped in every place the marching order
# changes (activate, bench, swap, a hire landing on a full four, a death, a
# defeat's reshuffle — six doors in three files): sync() looks at who is out
# and who is in, starts a clock for anyone out without one and drops the clock
# of anyone back in or dead. The world screen calls tick() every frame the map
# is its own, so the clock is never more than a frame late. Marching, even for
# a day, resets it: that is the whole cure, and it is meant to be cheap.
#
# The rules the owner set, and where each is held:
#   - a warning first, and a told moment for the leaving: tick() returns a beat
#     the screen puts on a card (scenes/world/world.gd's _check_bench);
#   - never mid-fight: tick() is only ever called over a clear map — no fight,
#     no site, no visit, no card — which is the same gate a calling's card waits
#     on; there is no path from a fight to here;
#   - never the founder: founder() is skipped outright, never even warned;
#   - never below a minimum roster: a restless merc stays, restless, while the
#     living roster is at MIN_ROSTER or under.
# The leaving is SEEDED off the merc and the world-day — hash("bench-leave|id|day")
# — so a reload replays the same morning, and a merc who stayed today is asked
# again tomorrow, not every frame.
#
# Where the swap itself may happen is here too (rotation_refusal, the owner's
# call of 2026-09-25), because it is the bench's price: see that section.
#
# What this does NOT own: the marching order itself (core/party.gd), who is
# hired or what they cost (core/recruits.gd — the fee is one-time and stays
# so), the card or the party page's words for a restless merc
# (scenes/world/world.gd, scenes/party/relations_web.gd), or the fire the bench
# now sits at when the company is under a roof (core/party_opinion.gd's
# camp_moment with `bench`).
extends RefCounted

const DAY := 1440.0   # world-minutes (core/faction_opinion.gd's DAY)

# TUNING: taste, not a sweep. Ten days is two or three long jobs in the
# Heartland — long enough that resting the wounded or keeping a specialist for
# the right lair never trips it, short enough that a spare nobody has marched
# since the last town will.
const RESTLESS_DAYS := 10
# TUNING: taste, not a sweep. Days after the warning before they may go — time
# to read the card, walk to a fight and put them in the line.
const LEAVE_AFTER_DAYS := 5
# TUNING: taste, not a sweep. Each day past that, one chance in three they are
# gone in the morning: not a timer the player can set a watch by, and not a
# week of grace either.
const LEAVE_PCT := 34
# TUNING: taste, not a sweep. Nobody walks out on a company that is down to a
# marching four (Party.MAX_ACTIVE) or fewer — the bench is for the extras, and
# a company that cannot field a full line has no extras.
const MIN_ROSTER := 4

const RESTLESS_LINES := [
	"%s has sat on the bench for %d days now, and has started asking at every inn who else is hiring.",
	"%s has not drawn a blade in anger for %d days. They clean it every night anyway, and have begun to ask what the company is keeping them for.",
	"%s has spent %d days watching the others march out without them, and has stopped pretending not to mind.",
]
const RESTLESS_RULE := " Put them in the marching order soon, or they may leave the company."
const LEAVE_LINES := [
	"%s is gone in the morning. A note on the bedroll says there is work with a company that fights, and thanks for the rest.",
	"%s settles up, shakes hands all round, and walks out to find a company with a place for them in the line.",
	"%s waited as long as they could. This morning they took their kit and went looking for a fight of their own.",
]

# The first name on the books: the founder in a run started since hiring
# (core/recruits.gd — only one hero is ever made, and made first), and in a
# grandfathered save the first hero it had, which is the nearest thing to one.
static func founder(party) -> String:
	return String(party.roster[0].id) if not party.roster.is_empty() else ""

static func _living(party) -> int:
	return party.roster.filter(func(ch): return not ch.dead).size()

static func sync(party, now: float) -> void:
	var out := {}
	for ch in party.roster:
		var id := String(ch.id)
		if ch.dead or party.is_active(id):
			continue
		out[id] = party.bench_clock.get(id, {"since": now, "warned": false})
	party.bench_clock = out

static func days(party, id: String, now: float) -> int:
	var e: Dictionary = party.bench_clock.get(id, {})
	if e.is_empty():
		return 0
	return maxi(0, int(floor((now - float(e["since"])) / DAY)))

static func restless(party, id: String) -> bool:
	return bool(party.bench_clock.get(id, {}).get("warned", false))

# Would they go today, if asked? Deterministic in the merc and the day.
static func leaves_today(id: String, now: float) -> bool:
	var day := int(floor(now / DAY))
	return absi(hash("bench-leave|%s|%d" % [id, day])) % 100 < LEAVE_PCT

# One beat at most per call, the roster's order deciding who is told first:
#   {"kind": "restless", "id", "name", "text", "days"}   — the warning; marks them
#   {"kind": "leaves", "id", "name", "text", "ch"}       — gone: off the roster already
# or {} when nobody has anything to say. The leaver's Character rides in "ch"
# so the screen can file them back in the barracks, where an inn may offer them
# again one day as a veteran (core/recruits.gd).
static func tick(party, now: float) -> Dictionary:
	sync(party, now)
	var boss := founder(party)
	for ch in party.roster:
		var id := String(ch.id)
		if id == boss or not party.bench_clock.has(id):
			continue
		var e: Dictionary = party.bench_clock[id]
		var d := days(party, id, now)
		var pick := absi(hash("bench-line|%s" % id))
		if not bool(e["warned"]):
			if d >= RESTLESS_DAYS:
				e["warned"] = true
				return {"kind": "restless", "id": id, "name": String(ch.cname), "days": d,
					"text": (String(RESTLESS_LINES[pick % RESTLESS_LINES.size()]) % [ch.cname, d]) + RESTLESS_RULE}
			continue
		if d >= RESTLESS_DAYS + LEAVE_AFTER_DAYS and _living(party) > MIN_ROSTER and leaves_today(id, now):
			leave(party, id)
			return {"kind": "leaves", "id": id, "name": String(ch.cname), "ch": ch,
				"text": String(LEAVE_LINES[pick % LEAVE_LINES.size()]) % ch.cname}
	return {}

# Off the books: the roster, their clock, what the company thought of them and
# the past they were carrying (party.callings) — a merc who walks out takes
# their own story with them.
static func leave(party, id: String) -> void:
	party.remove_member(id)
	party.bench_clock.erase(id)
	party.callings.erase(id)
	for k in party.relations.keys():
		if id in String(k).split("|"):
			party.relations.erase(k)

# --- where who marches may change (the owner's call, 2026-09-25) --------------
#
# The measured pass (core/party.gd's swap, tests/sweep_road_day.gd ROTATE)
# found the bench a second pool when it is worked: a fresh trio swapped in
# before nearly every road fight took a level-6 company's win rate from 88.4%
# to 97.0%, and the only price was the XP a benched hero does not earn. The
# owner's answer is that rotation costs more than XP: a hero comes into or
# goes out of the marching company only where the company stops — a camp it
# made and still stands at (World.camp_spot, set by core/world_camp.gd on a
# quiet night), or a settlement, which is where the inn and the lodge are —
# and never on the open road between two fights. Swapping before every fight
# now means a camp before every fight, and a camp is a long rest behind the
# 24-hour gate. Marching ORDER is not rotation: who walks first is a travel
# decision and stays live everywhere.
#
# `under_roof` is the caller's to say, because a settlement is a visit the map
# screen has open rather than a place in the model: world.gd passes true from
# the inn's and the lodge's own doors. `guest` is a co-op guest's screen, which
# never changes the host's company: the guest's map is a mirror rebuilt from
# the host's saves, and the host's inbox takes nothing from the road but a
# guest's own level-up (scenes/world/world.gd's _coop_share), so a roster
# change on the guest's side could not reach the host even if a screen allowed
# one. The refusal says so rather than leaving a button that does nothing.
#
# Core deaths, a defeat's reshuffle and a leaver (core/party.gd's
# revive_downed, core/fallen.gd, leave() above) move people in and out
# wherever they happen: they are not the player's rotation, and never ask.
const ROAD_TEXT := "The company changes who marches at a camp, a settlement or the lodge, not on the open road between fights."
const GUEST_TEXT := "Who marches is the host's to settle. This screen follows the host's company."

static func rotation_refusal(world, under_roof: bool, guest := false) -> String:
	if guest:
		return GUEST_TEXT
	if under_roof or (world != null and world.at_camp()):
		return ""
	return ROAD_TEXT

# --- the save -----------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.bench_clock.duplicate(true)

# No key at all (a save from before the bench counted) is {}: everyone on the
# bench starts their clock at the first frame after the load, the full
# RESTLESS_DAYS from then — nobody walks out on the first morning of an old save.
static func from_dict(party, d) -> void:
	party.bench_clock = {}
	if not d is Dictionary:
		return
	for id in d:
		var e = d[id]
		if e is Dictionary and e.has("since"):
			party.bench_clock[String(id)] = {"since": float(e["since"]), "warned": bool(e.get("warned", false))}

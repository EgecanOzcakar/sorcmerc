# The party: everyone you've recruited (roster), the <=4 who fight (active),
# shared gold and a shared stash. Holds `Character` objects in memory — disk
# persistence waits on T1's save format.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Presets = preload("res://core/presets.gd")
const Ach = preload("res://core/achievements.gd")
const Traits = preload("res://core/traits.gd")

const MAX_ACTIVE := 4

var roster: Array = []            # Character, in recruitment order
var active: Array[String] = []    # character ids, in marching order (<= MAX_ACTIVE)
var gold: int = 0
# [{item_id, quantity, identified}] — shared, not equipped. `identified` is true for
# everything except a magic item straight out of treasure (T13); mundane gear never
# carries an unidentified stack, so the flag is uniform but only ever false for magic.
var stash: Array[Dictionary] = []
var quests: Array = []            # T9's quest log — dicts owned by core/quest.gd
# T9x: RAW's "one long rest per 24h" gate, read against World.clock.elapsed by
# core/settlement_visit.gd's can_long_rest(). A huge negative default (not
# -INF — keeps the value a normal float through a JSON save round-trip) so a
# fresh party can always rest immediately.
var last_long_rest_at: float = -1e12
# #86: RAW allows two short rests per long rest. Bumped by Visit.rest("short-rest"),
# cleared by a long rest; Visit.can_short_rest() reads it.
var short_rests_since_long: int = 0
# Audit 4.3: an elf's Trance banks one short rest at a long rest, for later
# that day — this is the world-minute it lapses at, -1.0 when none is banked.
# Taken before the two counted above, and never counted against them. Owned by
# core/trance.gd; read by Visit.can_short_rest() and spent by Visit.rest().
var trance_rest_until := -1.0
# T9x: who stands for the party on the open-world map — the MEMBER ID of one
# of the active party (picked on the Party screen), resolved to that
# character's class figure (figures3d.gd's HERO_MODELS) only at render time,
# by scenes/world/party3d.gd. "" keeps the original flat PawnTex icon, same
# graceful-degrade contract every other model lookup this session uses.
# overworld_member() below is the one resolver both screens go through.
var overworld_figure := ""
# D3 standing orders: {"pace", "scout", "watch"} — see core/travel.gd, which
# owns every rule about them. A dict rather than three fields so the save format
# grows a key, not a column, when travel gains another order.
var travel_orders: Dictionary = {}
var here: Dictionary = {}   # #176 step 4: where the party is — biome, band, site, night — stamped by world.gd each frame for the road's trait terms; {} off the map
var world_now := 0.0        # world-minutes, stamped by world.gd each frame; potion buffs expire against it
var scouted_next := false   # Potion of Clairvoyance / Clairvoyance cast: the next fight starts scouted
var blessed := false        # a shrine's blessing: temp HP for every hero at the next fight (core/landmarks.gd)
var swift_until := 0.0      # Fly / Longstrider: forced-march speed, no road penalty, until this world-minute
var safe_camp := false      # Rope Trick: the next camp needs no kit (the ambush roll stands)
# A hermit's safe hollow (core/landmarks.gd, the hut's "Ask about the road"):
# the next camp needs no kit AND is not jumped — the hermit knows a place
# nothing finds. Its own flag since 2026-09-25: it shared Rope Trick's, so
# the audit's rule that Rope Trick keeps the ambush roll took the hollow's
# one promise away with it. Spent by WorldCamp.make_camp().
var hollow_camp := false
var alarm_set := false      # Alarm: the next camp's ambush is heard coming
# Audit 1.6: the slots Rope Trick and Alarm were cast from, [{id, level,
# spell}], held spent through every long rest until the camp they pay for is
# made — the spell buys the night, and the night does not give the slot back.
# Written by core/road_spells.gd, re-spent by Visit.rest(), let go by
# WorldCamp.make_camp().
var camp_holds: Array = []
# What members think of each other — "a|b" pair key -> {score, status}. Owned
# entirely by core/party_opinion.gd (docs/spike-party-opinions.md); read on the
# road, at camp and in the fight, saved beside the party since 2026-09-21.
var relations: Dictionary = {}
# The past each hero's background hands them — char_id -> {id, target_kind,
# target_id, state, told_at}. Owned entirely by core/callings.gd.
var callings: Dictionary = {}
# What the company has done in town that takes days — who trained, the
# once-a-visit stamps, the pit's bracket. Owned entirely by core/downtime.gd.
var downtime: Dictionary = {}
# The company's house — the town it is in, the rooms built onto it, the
# strongroom's gold, the garden's and the map room's clocks. {} until bought.
# Owned entirely by core/lodge.gd.
var lodge: Dictionary = {}
# How this company takes people on — {"rule": "hire"} for a run started since
# hiring pools (only the founder is ever made; everyone else is hired at an
# inn), {} for a save from before them (Create new still works, and the inns'
# pools too), plus which chairs were taken today. Owned entirely by
# core/recruits.gd.
var hiring: Dictionary = {}
# The company is finished (core/defeat.gd): the whole roster died after a
# defeat. {} for a run still going; otherwise Defeat.ending()'s record — who
# fell, days lasted, the renown title, the roll. Saved at the top of the world
# save as "finished" (core/world_save.gd), which is what stops the title
# screen resuming the slot. An old save has none, so it is not finished.
var finished: Dictionary = {}
# How long each benched merc has sat out — id -> {"since": world-minute,
# "warned": bool}. Owned entirely by core/bench.gd, which keeps it lazily off
# `active`; {} for a save from before the bench counted.
var bench_clock: Dictionary = {}

# --- roster ---------------------------------------------------------------

# T19: how big a bench this machine has ever kept, and who is on it. Called
# wherever the roster or the marching order changes.
func _note_roster() -> void:
	Ach.record("roster_size", roster.size())
	var species := {}
	for id in active:
		var ch = get_member(String(id))
		if ch != null:
			species[String(ch.species_id)] = true
	if active.size() >= MAX_ACTIVE and species.size() == 1:
		Ach.unlock("one_species")

func add_member(ch) -> bool:
	if ch == null or get_member(ch.id) != null:
		return false
	roster.append(ch)
	if active.size() < MAX_ACTIVE:
		active.append(ch.id)
	_note_roster()
	return true

func remove_member(id: String) -> bool:
	var ch = get_member(id)
	if ch == null:
		return false
	roster.erase(ch)
	active.erase(id)
	return true

func get_member(id: String):
	for ch in roster:
		if ch.id == id:
			return ch
	return null

func bench_list() -> Array:
	return roster.filter(func(ch): return not is_active(ch.id))

# --- active party ---------------------------------------------------------

func is_active(id: String) -> bool:
	return id in active

# The level the party is actually playing at: the highest among the <= 4 who
# fight. 1 while nobody is active, so the very first hero still starts where a
# first hero starts. A character created later joins here rather than at 1 —
# see scenes/creator/creator.gd's start_level.
func active_max_level() -> int:
	var best := 1
	for id in active:
		var ch = get_member(id)
		if ch != null:
			best = maxi(best, ch.level())
	return best

func activate(id: String) -> bool:
	var ch = get_member(id)
	if is_active(id) or ch == null or ch.dead or active.size() >= MAX_ACTIVE:
		return false
	active.append(id)
	_note_roster()
	return true

func bench(id: String) -> bool:
	if not is_active(id):
		return false
	active.erase(id)
	return true

# Swap a benched member in for an active one (the UI's slot click).
func swap(active_id: String, bench_id: String) -> bool:
	var i := active.find(active_id)
	var ch = get_member(bench_id)
	if i < 0 or is_active(bench_id) or ch == null or ch.dead:
		return false
	active[i] = bench_id
	_note_roster()
	return true

# --- overworld figure ------------------------------------------------------

# The member whose figure stands for the party on the open-world map: the
# player's pick while it is still marching, otherwise the highest-level active
# member (marching order breaks ties), and null only for an empty party — the
# plain gold-ringed pawn used to be the default, and a band of real people
# read as a green blob until somebody found the picker. (A removed member
# keeps their id in the field rather than clearing it — re-recruit them and
# the pick comes back; until then the default stands in.)
func overworld_member():
	var ch = overworld_pick()
	if ch != null:
		return ch
	for id in active:
		var m = get_member(id)
		if m != null and (ch == null or m.level() > ch.level()):
			ch = m
	return ch

# The explicit pick only, or null when there is none or it is not marching.
# The single place overworld_figure is resolved — the Party screen's picker
# and overworld_member() both come through here, so "is this pick still
# good?" has exactly one answer. It is an identity, not a class: benching or
# removing that character drops the pick even when somebody else in the party
# shares their class.
#
# ponytail: two shapes in one field. It holds a member id now, but saves
# written before that hold a CLASS id ("wizard") — and core/world_save.gd
# persists the field by name, so renaming it would strand every one of those
# saves. So an id matching nobody in the roster is retried as a class id
# against the active party, exactly the way the old code read it, and then
# rewritten to that member's id here: each save migrates the first time
# anything looks at it. The one ambiguity left is a character whose id happens
# to be a class id ("wizard"), which resolves as the member — the new shape
# wins, and that is the right way round.
func overworld_pick():
	if overworld_figure == "":
		return null
	var ch = get_member(overworld_figure)
	if ch != null:
		return ch if is_active(ch.id) else null
	for id in active:
		var legacy = get_member(id)
		if legacy != null and legacy.class_id() == overworld_figure:
			overworld_figure = legacy.id   # migrate at the first opportunity
			return legacy
	return null

# THE SEAM: the Characters combat gets, in marching order.
func party_characters() -> Array:
	var out := []
	for id in active:
		var ch = get_member(id)
		if ch != null:
			out.append(ch)
	return out

# Convenience for T5/T7: the same list already turned into Combatants.
func to_combatants(positions: Array, team := "party") -> Array:
	var out := []
	var chars := party_characters()
	for i in chars.size():
		var p: Vector2i = positions[i] if i < positions.size() else Vector2i.ZERO
		var c = Adapter.to_combatant(chars[i], team, p)
		if blessed:   # a shrine's blessing (core/landmarks.gd): something extra, at the next fight, once
			c.temp_hp = maxi(c.temp_hp, 2 * chars[i].level())   # RAW: temp HP takes the higher, never stacks
		out.append(c)
	blessed = false
	return out

# --- gold & stash ---------------------------------------------------------

func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	# T19: lifetime earnings and the fattest the purse has ever been. Losses go
	# through here too (the road takes gold with a negative `n`), and those are
	# nobody's income.
	if n > 0:
		Ach.bump("gold_earned", n)
	Ach.record("peak_gold", gold)

func spend_gold(n: int) -> bool:
	if n < 0 or n > gold:
		return false
	gold -= n
	if n > 0:
		Ach.bump("gold_spent", n)
	if gold == 0 and n > 0:
		Ach.unlock("broke")
	return true

# Identified and unidentified units of the same item stack separately.
func stash_add(item_id: String, quantity := 1, identified := true) -> void:
	if quantity <= 0:
		return
	for e in stash:
		if e["item_id"] == item_id and is_identified(e) == identified:
			e["quantity"] = int(e["quantity"]) + quantity
			return
	stash.append({"item_id": item_id, "quantity": quantity, "identified": identified})

static func is_identified(entry: Dictionary) -> bool:
	return bool(entry.get("identified", true))

func stash_count(item_id: String, identified_only := false) -> int:
	var n := 0
	for e in stash:
		if e["item_id"] == item_id and (is_identified(e) or not identified_only):
			n += int(e["quantity"])
	return n

# Spends identified units first — you use what you know before what you don't.
func stash_remove(item_id: String, quantity := 1) -> bool:
	if quantity <= 0 or stash_count(item_id) < quantity:
		return false
	var left := quantity
	for known in [true, false]:
		for e in stash.duplicate():
			if left <= 0:
				return true
			if e["item_id"] != item_id or is_identified(e) != known:
				continue
			var take: int = mini(left, int(e["quantity"]))
			e["quantity"] = int(e["quantity"]) - take
			left -= take
			if int(e["quantity"]) <= 0:
				stash.erase(e)
	return true

# --- identification (T13) -------------------------------------------------

const IDENTIFY_SCROLL := "scroll-of-identification"

# The stash entries still a mystery — what the identify UIs list.
func unidentified() -> Array:
	return stash.filter(func(e): return not is_identified(e))

# Move one unit of item_id from its unidentified stack to its identified one.
func stash_identify(item_id: String) -> bool:
	for e in stash:
		if e["item_id"] == item_id and not is_identified(e):
			e["quantity"] = int(e["quantity"]) - 1
			if int(e["quantity"]) <= 0:
				stash.erase(e)
			stash_add(item_id, 1, true)
			return true
	return false

# Burn one (already identified) Scroll of Identification: no roll, any time.
func use_identification_scroll(item_id: String) -> bool:
	if stash_count(IDENTIFY_SCROLL, true) < 1 or not stash_identify(item_id):
		return false
	stash_remove(IDENTIFY_SCROLL, 1)
	return true

# --- death & resurrection -------------------------------------------------
# 300 gp either way (Revivify's diamond, abstracted to coin — no material item).
# Statics taking the party, so a scene can ask "can I?" without holding a member.

const REVIVE_SPELL := "revivify"
const REVIVE_SCROLL := "scroll-of-resurrection"
const REVIVE_COST := 300
const REVIVE_SLOT := 3        # Revivify is 3rd level: any free slot of 3+ pays for it

# The first active member who knows any of `spell_ids`, or null. The road's
# "a spell you know changes the roll" hook (Revivify's pattern): Pass Without
# Trace on the approach, Detect Thoughts at the stall, a restoration spell
# behind the healer's counter.
func caster_of(spell_ids: Array):
	return caster_and_spell(spell_ids).get("ch")

# {ch, spell} for the first active member who knows any of `spell_ids`; {} if none.
func caster_and_spell(spell_ids: Array) -> Dictionary:
	for ch in party_characters():
		for sid in spell_ids:
			if _knows(ch, String(sid)):
				return {"ch": ch, "spell": String(sid)}
	return {}

static func _knows(ch, spell_id: String) -> bool:
	if spell_id in ch.prepared:
		return true
	var sc: Dictionary = ch.sheet().spellcasting
	if sc.is_empty():
		return false
	if spell_id in sc.get("always_prepared", []) or spell_id in sc.get("cantrips", []):
		return true
	for k in sc.get("known", []):
		if String(k["id"]) == spell_id:
			return true
	return false

# Lowest free slot level >= REVIVE_SLOT (1-based), or 0 when there is none.
static func _free_slot(ch) -> int:
	var full: Array = Adapter._full_slots(ch.sheet())
	for i in range(REVIVE_SLOT - 1, full.size()):
		var used: int = int(ch.slots_used[i]) if i < ch.slots_used.size() else 0
		if int(full[i]) - used > 0:
			return i + 1
	return 0

# Who can cast it right now: active, alive, knows it, has the slot. "" if nobody.
static func resurrection_caster(party) -> String:
	for ch in party.party_characters():
		if not ch.dead and _knows(ch, REVIVE_SPELL) and _free_slot(ch) > 0:
			return ch.id
	return ""

static func has_resurrection_scroll(party) -> bool:
	return party.stash_count(REVIVE_SCROLL) > 0

static func can_resurrect(party) -> bool:
	return party.gold >= REVIVE_COST \
		and (resurrection_caster(party) != "" or has_resurrection_scroll(party))

# method: "spell" (spends caster_id's slot) or "scroll" (consumes the stash item).
# Refuses and changes nothing unless the whole cost is payable.
static func resurrect(party, dead_id: String, method: String, caster_id: String = "") -> bool:
	var target = party.get_member(dead_id)
	if target == null or not target.dead or party.gold < REVIVE_COST:
		return false
	var caster = null
	var slot := 0
	if method == "spell":
		caster = party.get_member(caster_id if caster_id != "" else resurrection_caster(party))
		if caster == null or caster.dead or not _knows(caster, REVIVE_SPELL):
			return false
		slot = _free_slot(caster)
		if slot == 0:
			return false
	elif method == "scroll":
		if not has_resurrection_scroll(party):
			return false
	else:
		return false

	party.spend_gold(REVIVE_COST)
	if method == "spell":
		while caster.slots_used.size() < slot:
			caster.slots_used.append(0)
		caster.slots_used[slot - 1] = int(caster.slots_used[slot - 1]) + 1
		caster.dirty()
	else:
		party.stash_remove(REVIVE_SCROLL, 1)
	target.dead = false
	target.hp_current = 1
	target.dirty()
	Ach.unlock("resurrect_ally")   # T19 — spell or scroll, both route through here
	Ach.bump("resurrections")
	return true

# The LINEAR run's end (core/campaign.gd's _conclude): death is a within-run
# cost there, not permanent, and the run is over, so everyone walks home —
# the dead and the merely flattened alike. Leaves the benching alone. The open
# world does not come here any more: its defeat is revive_downed(), below,
# which leaves the dead dead (the design audit, docs/audit-game-design.md
# §1.2). This one keeps T10's locked rule for the node-route run.
static func auto_revive_all(party) -> void:
	for ch in party.roster:
		if ch.dead or (ch.hp_current >= 0 and ch.hp_current < 1):
			ch.dead = false
			ch.hp_current = maxi(1, ch.hp_current)
			ch.dirty()

# A lost fight in the open world (scenes/world/world.gd's _retreat, the pit's
# lost bout): the DOWNED come to, the DEAD stay dead. A dead hero is the price
# of the loss and comes back only the paid way — a healer's raise
# (core/settlement_visit.gd) or Revivify/a scroll (resurrect(), above), 300 ◉
# either way. Until 2026-09-24 this stood up every dead member of the roster,
# benched ones included, so conceding a fight was the cheapest resurrection in
# the game (the design audit, docs/audit-game-design.md §1.2).
#
# "Downed" is alive at under 1 HP. write_back (core/adapter.gd) already brings
# a stable hero out of a fight at 1, so this is mostly the guard behind it —
# but it is the guard that ended a soft-lock: a beaten party put down at the
# nearest settlement with nobody on their feet lost the next encounter on
# round 1, and if that settlement's garrison had beaten them, forever. The
# same soft-lock with the dead: if nobody who marched is left standing, the
# living bench marches in their place (roster order, up to MAX_ACTIVE), so
# the next fight has somebody in it.
#
# And if the WHOLE roster is dead, the company is finished (the owner's call,
# 2026-09-25): nobody is stood up, `finished` says so, and the caller ends the
# run (core/defeat.gd; scenes/world/world.gd's _end_company). Until then the
# open world had no end screen, so the highest-level hero came to alone.
#
# `carried_out` is ids a fight put on the ground without killing them, dead
# flag or not: the pit's lost bout (Downtime.pit_result), which is a brawl for
# a purse, not a death match. They come to with the downed; nobody else's
# death is undone by it.
#
# Returns {"came_to": [ids], "dead": [ids], "finished": bool}. Deterministic:
# no roll, only the roster's own order.
static func revive_downed(party, carried_out: Array = []) -> Dictionary:
	var came_to: Array[String] = []
	var dead: Array[String] = []
	for ch in party.roster:
		if ch.dead and String(ch.id) in carried_out:
			ch.dead = false
			ch.hp_current = 0   # comes to just below, like any of the downed
		if ch.dead:
			dead.append(String(ch.id))
		elif ch.hp_current >= 0 and ch.hp_current < 1:   # -1 is "full", not down
			ch.hp_current = 1
			ch.dirty()
			came_to.append(String(ch.id))
	var finished: bool = not party.roster.is_empty() and dead.size() == party.roster.size()
	var standing := false
	for id in party.active:
		var ch = party.get_member(id)
		if ch != null and not ch.dead:
			standing = true
	if not standing:
		for id in party.active.duplicate():
			party.bench(id)   # only the dead are left in it; they make no room otherwise
		for ch in party.roster:
			if not ch.dead and not party.is_active(ch.id):
				party.activate(ch.id)
	return {"came_to": came_to, "dead": dead, "finished": finished}

# The line a beaten company reads on the map, from revive_downed()'s answer
# and the ids this fight killed. Here rather than in the screen so the words
# and the rule are tested together: the dead are named, and the line says
# what brings them back. `days` is how long they lay there first
# (core/defeat.gd's DAYS_LOST; 0 for a caller that spends no time).
func defeat_line(revived: Dictionary, fell: Array, where: String, lost: int, days := 0) -> String:
	if bool(revived.get("finished", false)):
		return "The company is beaten, and nobody gets up."
	var later := "" if days <= 0 else (" a day later" if days == 1 else " %d days later" % days)
	var line := "The company is beaten and left for dead. The living come to at %s%s, %d ◉ lighter." % [where, later, lost]
	var names: Array = []
	for id in fell:
		var ch = get_member(String(id))
		if ch != null and ch.dead:
			names.append(ch.cname)
	if not names.is_empty():
		var who: String = names[0] if names.size() == 1 \
			else ", ".join(names.slice(0, names.size() - 1)) + " and " + String(names[-1])
		line += " %s did not get up. A healer can raise the dead, at %d ◉ a head." % [who, REVIVE_COST]
	return line

# --- display --------------------------------------------------------------

# At-a-glance line for the party/campaign UI. Everything derived comes off the
# resolved sheet — never recomputed here.
func summary(id: String) -> Dictionary:
	var ch = get_member(id)
	if ch == null:
		return {}
	var s = ch.sheet()
	var cid: String = ch.class_id()
	return {
		"id": ch.id,
		"name": ch.cname,
		"class_id": cid,
		"class_name": cid.capitalize(),
		"level": s.level,
		"ac": s.ac,
		"hp": ch.hp_current if ch.hp_current >= 0 else s.max_hp,
		"max_hp": s.max_hp,
		"active": is_active(id),
		"dead": ch.dead,
		# Issue #27: what a party page needs to say about somebody without
		# making the player open their sheet one at a time. Trained skills only
		# — all eighteen of them, most at +0, is the profile screen's job — and
		# what is actually on them, which is the thing a stash listing cannot
		# tell you. Ids and numbers; the names are the UI's business.
		"skills": trained_skills(s),
		"equipped": equipped_items(s),
		"traits": Traits.ids(ch),   # #176: personality trait ids; the names are the UI's business
		# Audit 4.1: the slots they have left against the sheet's maximum, the
		# same rows the sheet and the combat pips read (Adapter.slot_table).
		# [] for anyone who casts nothing from a slot.
		"slots": Adapter.slot_table(ch),
	}

# The skills this sheet is actually trained in, best first: [{id, mod, prof}]
# where prof is "expert" or "prof". Untrained skills are left out — a roster
# row that lists all eighteen says nothing.
static func trained_skills(s) -> Array:
	var out: Array = []
	for id in s.skill_prof:
		var how := String(s.skill_prof[id])
		if how != "prof" and how != "expert":
			continue
		out.append({"id": String(id), "mod": int(s.skills.get(id, 0)), "prof": how})
	out.sort_custom(func(a, b):
		if a["mod"] != b["mod"]:
			return a["mod"] > b["mod"]
		return a["id"] < b["id"])
	return out

# What is worn and wielded: [{id, kind, quantity}], in the order the sheet
# resolved it.
static func equipped_items(s) -> Array:
	var out: Array = []
	for it in s.equipment:
		out.append({"id": String(it["item_id"]), "kind": String(it.get("kind", "")),
			"quantity": int(it.get("quantity", 1))})
	return out

# --- fixtures -------------------------------------------------------------

# Five characters with no creator and no disk: the three presets plus two built
# by hand the presets.gd way. Used by tests/test_party.gd and the party scene's
# standalone demo; delete once T1 can save a real roster.
static func demo_roster() -> Array:
	var out := Presets.party()
	out.append(_demo_barbarian("thrun", "Thrun Stonefist", "dwarf"))
	out.append(_demo_barbarian("gera", "Gera Ashvein", "human"))
	return out

static func _demo_barbarian(id: String, name: String, species: String) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = name
	ch.species_id = species
	ch.background_id = "soldier"
	ch.base_abilities = {"str": 15, "dex": 12, "con": 14, "int": 8, "wis": 10, "cha": 10}
	ch.traits_offered = true   # #176: a fixture, like the presets it rides with — never asked
	ch.add_level("barbarian", -1, true)   # a demo hero, handed over the same way
	ch.add_level("barbarian", -1, true)
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	ch.decide("skill-choice:class:barbarian:0", {"type": "skill-choice", "skills": ["athletics", "survival"]})
	ch.decide("weapon-mastery-choice:class:barbarian:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["greataxe", "handaxe"]})
	ch.equipped = ["greataxe", "hide-armor"]
	return ch

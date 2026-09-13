# The party: everyone you've recruited (roster), the <=4 who fight (active),
# shared gold and a shared stash. Holds `Character` objects in memory — disk
# persistence waits on T1's save format.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Presets = preload("res://core/presets.gd")
const Ach = preload("res://core/achievements.gd")

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
# T9x: who stands for the party on the open-world map — the MEMBER ID of one
# of the active party (picked on the Party screen), resolved to that
# character's class figure (figures3d.gd's HERO_MODELS) only at render time,
# by scenes/world/party3d.gd. "" keeps the original flat PawnTex icon, same
# graceful-degrade contract every other model lookup this session uses.
# overworld_member() below is the one resolver both screens go through.
var overworld_figure := ""

# --- roster ---------------------------------------------------------------

func add_member(ch) -> bool:
	if ch == null or get_member(ch.id) != null:
		return false
	roster.append(ch)
	if active.size() < MAX_ACTIVE:
		active.append(ch.id)
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

func activate(id: String) -> bool:
	var ch = get_member(id)
	if is_active(id) or ch == null or ch.dead or active.size() >= MAX_ACTIVE:
		return false
	active.append(id)
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
	return true

# --- overworld figure ------------------------------------------------------

# The member whose figure stands for the party on the open-world map, or null
# for the plain gold-ringed pawn. The single place overworld_figure is
# resolved — the Party screen's picker and scenes/world/party3d.gd both come
# through here, so "is this pick still good?" has exactly one answer. It is an
# identity, not a class: benching or removing that character falls back to the
# pawn even when somebody else in the party shares their class. (A removed
# member keeps their id in the field rather than clearing it — re-recruit them
# and the pick comes back; until then it just reads as the pawn.)
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
func overworld_member():
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
		out.append(Adapter.to_combatant(chars[i], team, p))
	return out

# --- gold & stash ---------------------------------------------------------

func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)

func spend_gold(n: int) -> bool:
	if n < 0 or n > gold:
		return false
	gold -= n
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
	return true

# End of a run: death is a within-run cost, not permanent. Leaves the benching alone.
static func auto_revive_all(party) -> void:
	for ch in party.roster:
		if ch.dead:
			ch.dead = false
			ch.hp_current = maxi(1, ch.hp_current)
			ch.dirty()

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
	}

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
	ch.add_level("barbarian", -1)
	ch.add_level("barbarian", -1)
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	ch.decide("skill-choice:class:barbarian:0", {"type": "skill-choice", "skills": ["athletics", "survival"]})
	ch.decide("weapon-mastery-choice:class:barbarian:0",
		{"type": "weapon-mastery-choice", "weaponIds": ["greataxe", "handaxe"]})
	ch.equipped = ["greataxe", "hide-armor"]
	return ch

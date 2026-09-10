# The party: everyone you've recruited (roster), the <=4 who fight (active),
# shared gold and a shared stash. Holds `Character` objects in memory — disk
# persistence waits on T1's save format.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Presets = preload("res://core/presets.gd")

const MAX_ACTIVE := 4

var roster: Array = []            # Character, in recruitment order
var active: Array[String] = []    # character ids, in marching order (<= MAX_ACTIVE)
var gold: int = 0
var stash: Array[Dictionary] = [] # [{item_id, quantity}] — shared, not equipped
var quests: Array = []            # T9's quest log — dicts owned by core/quest.gd

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
	if is_active(id) or get_member(id) == null or active.size() >= MAX_ACTIVE:
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
	if i < 0 or is_active(bench_id) or get_member(bench_id) == null:
		return false
	active[i] = bench_id
	return true

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

func stash_add(item_id: String, quantity := 1) -> void:
	if quantity <= 0:
		return
	for e in stash:
		if e["item_id"] == item_id:
			e["quantity"] = int(e["quantity"]) + quantity
			return
	stash.append({"item_id": item_id, "quantity": quantity})

func stash_count(item_id: String) -> int:
	for e in stash:
		if e["item_id"] == item_id:
			return int(e["quantity"])
	return 0

func stash_remove(item_id: String, quantity := 1) -> bool:
	if quantity <= 0 or stash_count(item_id) < quantity:
		return false
	for e in stash:
		if e["item_id"] == item_id:
			e["quantity"] = int(e["quantity"]) - quantity
			if int(e["quantity"]) <= 0:
				stash.erase(e)
			return true
	return false

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

# T5 — the campaign: a straight line of stages, each offering 2-3 nodes. Pick one,
# resolve it, the line advances. Not a graph; the product ask was a route, not an editor.
#
#   var c = Campaign.new(party)
#   c.options()                       # the nodes on this stage
#   c.enter(i)                        # -> the node dict; state becomes visiting/combat
#   c.combat_spec()                   # combat nodes: what scenes/main.tscn wants
#   c.finish_combat(main.result)      # banks xp/gold/loot, quest progress, deaths
#   c.rest("long-rest") / c.buy(id) / c.sell(id) / c.offer() / c.accept() / c.turn_in(q)
#   c.leave()                         # -> next stage, or state "won"
extends RefCounted

const Quest = preload("res://core/quest.gd")
const Scaler = preload("res://core/scaler.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const RNG = preload("res://core/rng.gd")

# The route. Each entry is one stage's node choices; the last stage is the boss.
const STAGES := [
	[
		{"id": "road-ambush", "kind": "combat", "title": "Ambush on the road",
			"desc": "Something is moving in the gorse. Fight through.", "difficulty": "normal"},
		{"id": "wayside-camp", "kind": "merchant", "title": "The wayside camp",
			"desc": "A pedlar, a fire, and work for anyone with a sword."},
	],
	[
		{"id": "warband-camp", "kind": "combat", "title": "The warband camp (hard)",
			"desc": "More of them, and they are awake — but the camp is full of coin.",
			"difficulty": "hard", "gold": 90},
		{"id": "ridge-path", "kind": "combat", "title": "Skirt the ridge",
			"desc": "The long way round. Fewer of them.", "difficulty": "easy"},
		{"id": "milestone-camp", "kind": "rest", "title": "Camp by the milestone",
			"desc": "Cold, dry, and safe enough to sleep."},
	],
	[
		{"id": "hollow-market", "kind": "merchant", "title": "The Hollow Market",
			"desc": "Steel, straps and rumours, all overpriced."},
		{"id": "broken-cart", "kind": "treasure", "title": "The broken cart",
			"desc": "Someone else's bad day.", "gold": 60, "item_id": "handaxe"},
	],
	[
		{"id": "warrens", "kind": "combat", "title": "Into the warrens",
			"desc": "Low tunnels and too many corners.", "difficulty": "normal"},
		{"id": "falls-hoard", "kind": "treasure", "title": "The hoard behind the falls",
			"desc": "Wet, cold, and worth the swim.", "gold": 110, "item_id": "chain-shirt"},
		{"id": "falls-camp", "kind": "rest", "title": "Camp behind the falls",
			"desc": "Loud, but nothing can hear you either."},
	],
	[
		{"id": "sunken-shrine", "kind": "combat", "title": "THE SUNKEN SHRINE",
			"desc": "Whatever has been calling them lives down here.",
			"difficulty": "hard", "boss": true, "gold": 250},
	],
]

# What a merchant sells: a handful of ids out of data/weapons.json + armor.json.
# Price is the data cost, flat. No haggling, no stock depletion.
const STOCK := ["shortsword", "longsword", "greataxe", "shortbow", "leather", "chain-shirt", "shield"]
const SELL_RATE := 0.5

var party
var stage := 0
var node: Dictionary = {}
var state := "picking"        # picking | visiting | combat | won | lost
var xp := 0                   # banked here: Character has no xp field yet
var log: Array = []
var rng

func _init(p, seed_value := 0) -> void:
	party = p
	rng = RNG.new(seed_value)

# --- the route ------------------------------------------------------------

func options() -> Array:
	return STAGES[stage] if stage < STAGES.size() else []

func enter(i: int) -> Dictionary:
	var opts := options()
	if state != "picking" or i < 0 or i >= opts.size():
		return {}
	node = opts[i]
	state = "combat" if node["kind"] == "combat" else "visiting"
	say("→ %s" % node["title"])
	if node["kind"] == "treasure":
		_take_treasure()
	return node

func leave() -> void:
	if state == "lost":
		return
	node = {}
	stage += 1
	state = "won" if stage >= STAGES.size() else "picking"
	if state == "won":
		say("The road ends. The party lives.")

func say(line: String) -> void:
	log.append(line)

# --- combat ---------------------------------------------------------------

# Quest bias goes in here: unfulfilled targets show up more often from now on.
func combat_spec() -> Dictionary:
	return Scaler.roster_for(party.party_characters(), node.get("difficulty", "normal"),
		Quest.bias(party))

# `result` is Encounter.resolve_outcome()'s dict, straight off scenes/main.gd.
func finish_combat(result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.get("outcome", "") != "Victory":
		state = "lost"
		say("The party falls. The road ends here.")
		return
	xp += int(result.get("xp", 0))
	party.add_gold(int(result.get("gold", 0)) + int(node.get("gold", 0)))
	for item in result.get("loot", []):
		party.stash_add(String(item))
	say("Victory. +%d XP, +%d gold." % [int(result.get("xp", 0)),
		int(result.get("gold", 0)) + int(node.get("gold", 0))])
	for id in result.get("deaths", []):
		if party.bench(id):
			say("%s is carried off the field and sits out the rest of the run." % id)
	for line in Quest.record_kills(party, result.get("kills", []), rng):
		say(line)
	state = "visiting"   # the after-action panel; leave() moves on

# --- treasure -------------------------------------------------------------

func _take_treasure() -> void:
	party.add_gold(int(node.get("gold", 0)))
	say("+%d gold." % int(node.get("gold", 0)))
	if node.has("item_id"):
		party.stash_add(String(node["item_id"]))
		say("Found: %s." % item_name(String(node["item_id"])))

# --- rest -----------------------------------------------------------------

func rest(kind: String) -> void:
	if node.get("kind", "") != "rest":
		return
	var Adapter = load("res://core/adapter.gd")
	for ch in party.party_characters():
		Adapter.rest(ch, kind)
	say("The party takes a %s." % kind.replace("-", " "))

# --- merchant -------------------------------------------------------------

func stock() -> Array:
	var out: Array = []
	for id in STOCK:
		out.append({"item_id": id, "name": item_name(id), "price": item_price(id)})
	return out

func buy(item_id: String) -> bool:
	if node.get("kind", "") != "merchant" or not item_id in STOCK:
		return false
	if not party.spend_gold(item_price(item_id)):
		return false
	party.stash_add(item_id)
	say("Bought %s for %d gp." % [item_name(item_id), item_price(item_id)])
	return true

func sell(item_id: String) -> bool:
	if node.get("kind", "") != "merchant" or not party.stash_remove(item_id):
		return false
	var paid := maxi(1, int(item_price(item_id) * SELL_RATE))
	party.add_gold(paid)
	say("Sold %s for %d gp." % [item_name(item_id), paid])
	return true

# --- quests (merchants only) ----------------------------------------------

func offer() -> Dictionary:
	if node.get("kind", "") != "merchant":
		return {}
	return Quest.offer_for(party, String(node["id"]))

func accept(quest: Dictionary) -> bool:
	if node.get("kind", "") != "merchant" or not Quest.accept(party, quest):
		return false
	say("Quest accepted: %s" % quest["title"])
	return true

func turn_in(quest: Dictionary) -> bool:
	if node.get("kind", "") != "merchant" or not Quest.turn_in(party, quest):
		return false
	say("Quest complete: %s (+%d gp)" % [quest["title"], int(quest["reward"].get("gold", 0))])
	return true

# --- item lookup ----------------------------------------------------------

static func item_data(item_id: String) -> Dictionary:
	var d: Dictionary = Catalog.weapon(item_id)
	return d if not d.is_empty() else Catalog.armor(item_id)

static func item_name(item_id: String) -> String:
	return String(item_data(item_id).get("name", item_id.capitalize()))

static func item_price(item_id: String) -> int:
	return maxi(1, int(round(float(item_data(item_id).get("costGp", 5)))))

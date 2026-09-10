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
			"desc": "Something is moving in the gorse. Fight through.", "difficulty": "normal",
				"theme": "forest-clearing"},
		{"id": "wayside-camp", "kind": "merchant", "title": "The wayside camp",
			"desc": "A pedlar, a fire, and work for anyone with a sword."},
	],
	[
		{"id": "warband-camp", "kind": "combat", "title": "The warband camp (hard)",
			"desc": "More of them, and they are awake — but the camp is full of coin.",
			"difficulty": "hard", "gold": 90, "theme": "goblin-camp"},
		{"id": "ridge-path", "kind": "combat", "title": "Skirt the ridge",
			"desc": "The long way round. Fewer of them.", "difficulty": "easy", "theme": "goblin-camp"},
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
			"desc": "Low tunnels and too many corners.", "difficulty": "normal", "theme": "frozen-cave"},
		{"id": "falls-hoard", "kind": "treasure", "title": "The hoard behind the falls",
			"desc": "Wet, cold, and worth the swim.", "gold": 110, "item_id": "chain-shirt"},
		{"id": "falls-camp", "kind": "rest", "title": "Camp behind the falls",
			"desc": "Loud, but nothing can hear you either."},
	],
	[
		{"id": "sunken-shrine", "kind": "combat", "title": "THE SUNKEN SHRINE",
			"desc": "Whatever has been calling them lives down here.",
			"difficulty": "hard", "boss": true, "gold": 250, "theme": "sunken-shrine"},
	],
]

# What a merchant sells: a handful of ids out of data/weapons.json + armor.json,
# priced by item_price() below. No haggling, no stock depletion.
const STOCK := ["shortsword", "longsword", "greataxe", "shortbow", "leather", "chain-shirt", "shield"]
const SCROLL := "scroll-of-resurrection"
const SELL_RATE := 0.5

var party
var stage := 0
var node: Dictionary = {}
var state := "picking"        # picking | visiting | combat | won | lost
var xp := 0                   # run total, for the header; the real bank is ch.xp
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
	_autosave()
	return node

func leave() -> void:
	if state == "lost":
		return
	node = {}
	stage += 1
	state = "won" if stage >= STAGES.size() else "picking"
	if state == "won":
		say("The road ends. The party lives.")
		_conclude()
	_autosave()

func say(line: String) -> void:
	log.append(line)

# Every state-mutating method ends here: one rolling slot, overwritten each time.
# load()d rather than preloaded — campaign_save.gd preloads this file.
func _autosave() -> void:
	load("res://core/campaign_save.gd").save(self)

# The run is over, win or lose: the dead come back for free (T10's locked rule).
func _conclude() -> void:
	var Party = load("res://core/party.gd")
	for ch in party.roster:
		if ch.dead:
			say("%s is carried home and revived." % ch.id)
	Party.auto_revive_all(party)

# Revivify or a Scroll of Resurrection, 300 gp either way. The scene's button.
func resurrect(dead_id: String, method: String, caster_id: String = "") -> bool:
	var Party = load("res://core/party.gd")
	if not Party.resurrect(party, dead_id, method, caster_id):
		return false
	say("%s is brought back at 1 HP (−%d gp)." % [dead_id, Party.REVIVE_COST])
	_autosave()
	return true

# --- combat ---------------------------------------------------------------

# Quest bias goes in here: unfulfilled targets show up more often from now on.
func combat_spec() -> Dictionary:
	var spec: Dictionary = Scaler.roster_for(party.party_characters(), node.get("difficulty", "normal"),
		Quest.bias(party))
	spec["theme"] = node.get("theme", "sunken-shrine")   # T11: which board this fight is on
	return spec

# `result` is Encounter.resolve_outcome()'s dict, straight off scenes/main.gd.
func finish_combat(result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.get("outcome", "") != "Victory":
		state = "lost"
		say("The party falls. The road ends here.")
		_conclude()
		_autosave()
		return
	xp += int(result.get("xp", 0))
	_split_xp(int(result.get("xp", 0)))
	party.add_gold(int(result.get("gold", 0)) + int(node.get("gold", 0)))
	for item in result.get("loot", []):
		party.stash_add(String(item))
	say("Victory. +%d XP, +%d gold." % [int(result.get("xp", 0)),
		int(result.get("gold", 0)) + int(node.get("gold", 0))])
	for id in result.get("deaths", []):
		var fallen = party.get_member(id)
		if fallen != null:
			fallen.dead = true
		if party.bench(id):
			say("%s falls. Only a resurrection brings them back before the road ends." % id)
	for line in Quest.record_kills(party, result.get("kills", []), rng):
		say(line)
	state = "visiting"   # the after-action panel; leave() moves on
	_autosave()

# Split evenly among whoever was in the fight; the remainder is dropped.
func _split_xp(total: int) -> void:
	var fighters: Array = party.party_characters()
	if fighters.is_empty() or total <= 0:
		return
	var share: int = total / fighters.size()
	for ch in fighters:
		ch.xp += share

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
	_autosave()

# --- merchant -------------------------------------------------------------

# The steel and straps, plus — at some merchants — the one consumable that
# matters: a Scroll of Resurrection. Keyed off the node id, so a given merchant
# either has one or never does.
func stock_ids() -> Array:
	var ids: Array = STOCK.duplicate()
	if String(node.get("id", "")).hash() % 3 == 0:
		ids.append(SCROLL)
	return ids

func stock() -> Array:
	var out: Array = []
	for id in stock_ids():
		out.append({"item_id": id, "name": item_name(id), "price": item_price(id)})
	return out

func buy(item_id: String) -> bool:
	if node.get("kind", "") != "merchant" or not item_id in stock_ids():
		return false
	if not party.spend_gold(item_price(item_id)):
		return false
	party.stash_add(item_id)
	say("Bought %s for %d gp." % [item_name(item_id), item_price(item_id)])
	_autosave()
	return true

func sell(item_id: String) -> bool:
	if node.get("kind", "") != "merchant" or item_price(item_id) <= 0:
		return false      # artifacts and unknown junk have no market
	if not party.stash_remove(item_id):
		return false
	var paid := maxi(1, int(item_price(item_id) * SELL_RATE))
	party.add_gold(paid)
	say("Sold %s for %d gp." % [item_name(item_id), paid])
	_autosave()
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
	_autosave()
	return true

func turn_in(quest: Dictionary) -> bool:
	if node.get("kind", "") != "merchant" or not Quest.turn_in(party, quest):
		return false
	say("Quest complete: %s (+%d gp)" % [quest["title"], int(quest["reward"].get("gold", 0))])
	_autosave()
	return true

# --- item lookup & pricing ------------------------------------------------
#
# Mundane gear: the SRD `costGp` straight out of weapons/armor.json — already
# power-correlated inside its one (common) tier, so no second heuristic.
# Magic items: the export carries no structured power data (structuredBonuses is
# null on every entry, SCHEMA gap), so rarity is all there is. Price grows
# polynomially with the tier index: BASE * (index + 1) ^ EXPONENT, tuned so
# uncommon ≈ 256 gp, rare ≈ 2916, very-rare ≈ 16384, legendary ≈ 62500 gp.
# Artifacts are priced 0 — not for sale, not sellable.

const MAGIC_BASE := 4
const MAGIC_EXPONENT := 6
const RARITY_TIERS := ["common", "uncommon", "rare", "very-rare", "legendary"]
const VARIES_TIER := 2        # "varies" items (no single rarity) price as rare

static func item_data(item_id: String) -> Dictionary:
	for file in ["weapons.json", "armor.json", "magic-items.json"]:
		var d: Dictionary = Catalog.index(file).get(item_id, {})
		if not d.is_empty():
			return d
	return {}

static func item_name(item_id: String) -> String:
	return String(item_data(item_id).get("name", item_id.capitalize()))

# 0 = not tradeable (artifacts, and anything the catalog has never heard of).
static func item_price(item_id: String) -> int:
	var d := item_data(item_id)
	if d.has("costGp"):
		return maxi(1, int(round(float(d["costGp"]))))
	if not d.has("rarity"):
		return 0
	var rarity := String(d["rarity"])
	if rarity == "artifact":
		return 0
	var tier: int = RARITY_TIERS.find(rarity)
	if tier < 0:
		tier = VARIES_TIER
	return MAGIC_BASE * int(pow(tier + 1, MAGIC_EXPONENT))

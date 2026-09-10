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
const Icons = preload("res://core/ui_icons.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Settings = preload("res://core/settings.gd")

# T12 — the route is generated, not fixed. POOL is every node template; each one
# carries the stage positions it is eligible for. _build_route() seed-picks 2-3
# per stage out of the eligible templates, then bolts the boss on the end.
const STAGE_POSITIONS := ["early", "mid", "mid", "late"]   # + the boss stage
const STAGE_COUNT := 5                                     # STAGE_POSITIONS + boss
const PICK_MIN := 2
const PICK_MAX := 3
const SUPPORT_KINDS := ["merchant", "rest", "treasure"]   # one per stage, dealt out

const POOL := [
	# --- combat: early ----------------------------------------------------
	{"id": "road-ambush", "kind": "combat", "stage_position": ["early"],
		"title": "Ambush on the road", "desc": "Something is moving in the gorse. Fight through.",
		"difficulty": "normal", "theme": "forest-clearing"},
	{"id": "gorse-scouts", "kind": "combat", "stage_position": ["early"],
		"title": "Scouts in the gorse", "desc": "Two of them, and neither has seen you yet.",
		"difficulty": "easy", "theme": "forest-clearing"},
	{"id": "toll-bridge", "kind": "combat", "stage_position": ["early", "mid"],
		"title": "The toll bridge", "desc": "They want coin. You have a sword.",
		"difficulty": "normal", "gold": 40, "theme": "city-square"},
	{"id": "burnt-farm", "kind": "combat", "stage_position": ["early"],
		"title": "The burnt farm", "desc": "Whoever did this is still in the yard.",
		"difficulty": "easy", "theme": "forest-clearing"},
	{"id": "ridge-path", "kind": "combat", "stage_position": ["early", "mid"],
		"title": "Skirt the ridge", "desc": "The long way round. Fewer of them.",
		"difficulty": "easy", "theme": "goblin-camp"},
	{"id": "market-brawl", "kind": "combat", "stage_position": ["early"],
		"title": "Brawl in the square", "desc": "It started over a mule. It will not end there.",
		"difficulty": "normal", "gold": 50, "theme": "city-square"},
	# --- combat: mid ------------------------------------------------------
	{"id": "warband-camp", "kind": "combat", "stage_position": ["mid"],
		"title": "The warband camp (hard)",
		"desc": "More of them, and they are awake — but the camp is full of coin.",
		"difficulty": "hard", "gold": 90, "theme": "goblin-camp"},
	{"id": "warrens", "kind": "combat", "stage_position": ["mid"],
		"title": "Into the warrens", "desc": "Low tunnels and too many corners.",
		"difficulty": "normal", "theme": "frozen-cave"},
	{"id": "shop-raid", "kind": "combat", "stage_position": ["mid"],
		"title": "They came for the shop", "desc": "The tinker is under his own counter. Earn the stock.",
		"difficulty": "normal", "gold": 60, "theme": "merchant-shop"},
	{"id": "ice-gully", "kind": "combat", "stage_position": ["mid", "late"],
		"title": "The ice gully", "desc": "No cover, no footing, and they are above you.",
		"difficulty": "hard", "gold": 80, "theme": "frozen-cave"},
	{"id": "palisade", "kind": "combat", "stage_position": ["mid"],
		"title": "Over the palisade", "desc": "Sharpened stakes and a sleeping watch.",
		"difficulty": "normal", "theme": "goblin-camp"},
	{"id": "market-gate", "kind": "combat", "stage_position": ["mid"],
		"title": "The market gate", "desc": "A toll-taker with too few friends.",
		"difficulty": "easy", "theme": "city-square"},
	# --- combat: late -----------------------------------------------------
	{"id": "shrine-steps", "kind": "combat", "stage_position": ["late"],
		"title": "The shrine steps", "desc": "The last of them, camped on holy ground.",
		"difficulty": "hard", "gold": 100, "theme": "sunken-shrine"},
	{"id": "deep-warren", "kind": "combat", "stage_position": ["late"],
		"title": "The deep warren", "desc": "The ice hums. Something down there answers it.",
		"difficulty": "hard", "gold": 95, "theme": "frozen-cave"},
	{"id": "burned-quarter", "kind": "combat", "stage_position": ["late"],
		"title": "The burned quarter", "desc": "They took the town first. Take it back.",
		"difficulty": "normal", "gold": 70, "theme": "city-square"},
	{"id": "rearguard", "kind": "combat", "stage_position": ["late"],
		"title": "The pack's rearguard", "desc": "Left behind to buy their chief an hour.",
		"difficulty": "hard", "gold": 85, "theme": "goblin-camp"},
	# --- merchants (the two quest-givers first) ---------------------------
	{"id": "wayside-camp", "kind": "merchant", "stage_position": ["early", "mid"],
		"title": "The wayside camp", "desc": "A pedlar, a fire, and work for anyone with a sword."},
	{"id": "hollow-market", "kind": "merchant", "stage_position": ["mid", "late"],
		"title": "The Hollow Market", "desc": "Steel, straps and rumours, all overpriced."},
	{"id": "pack-mule", "kind": "merchant", "stage_position": ["early"],
		"title": "The pack mule", "desc": "One man, one mule, everything strapped to it."},
	{"id": "tinkers-wagon", "kind": "merchant", "stage_position": ["early", "mid"],
		"title": "The tinker's wagon", "desc": "He mends kettles. He also sells edges."},
	{"id": "shuttered-shop", "kind": "merchant", "stage_position": ["mid", "late"],
		"title": "The shuttered shop", "desc": "Knock twice. He opens for coin."},
	{"id": "caravanserai", "kind": "merchant", "stage_position": ["late"],
		"title": "The caravanserai", "desc": "The last honest stock before the shrine."},
	# --- treasure ---------------------------------------------------------
	{"id": "broken-cart", "kind": "treasure", "stage_position": ["early", "mid"],
		"title": "The broken cart", "desc": "Someone else's bad day.",
		"gold": 60, "item_id": "handaxe"},
	{"id": "dead-scout", "kind": "treasure", "stage_position": ["early"],
		"title": "The dead scout", "desc": "Face down, purse untouched.",
		"gold": 40, "item_id": "dagger"},
	{"id": "cairn-cache", "kind": "treasure", "stage_position": ["early", "mid"],
		"title": "The cairn cache", "desc": "Stones stacked by someone who meant to come back.",
		"gold": 75, "item_id": "leather"},
	{"id": "collapsed-shrine", "kind": "treasure", "stage_position": ["mid"],
		"title": "The collapsed shrine", "desc": "Half a roof, and offerings nobody dared take.",
		"gold": 90, "item_id": "shield"},
	{"id": "falls-hoard", "kind": "treasure", "stage_position": ["mid", "late"],
		"title": "The hoard behind the falls", "desc": "Wet, cold, and worth the swim.",
		"gold": 110, "item_id": "chain-shirt"},
	{"id": "drowned-barge", "kind": "treasure", "stage_position": ["late"],
		"title": "The drowned barge", "desc": "Still moored. Still loaded.",
		"gold": 120, "item_id": "longsword"},
	{"id": "tax-strongbox", "kind": "treasure", "stage_position": ["late"],
		"title": "The tax strongbox", "desc": "Nobody left alive to collect it.",
		"gold": 140, "item_id": "shortbow"},
	# --- rest -------------------------------------------------------------
	{"id": "milestone-camp", "kind": "rest", "stage_position": ["early", "mid"],
		"title": "Camp by the milestone", "desc": "Cold, dry, and safe enough to sleep."},
	{"id": "hayloft", "kind": "rest", "stage_position": ["early"],
		"title": "The hayloft", "desc": "Dusty, warm, and one ladder to defend."},
	{"id": "ferry-hut", "kind": "rest", "stage_position": ["early", "mid"],
		"title": "The ferryman's hut", "desc": "He is long gone. The stove is not."},
	{"id": "watchfire", "kind": "rest", "stage_position": ["mid", "late"],
		"title": "The watchfire", "desc": "Somebody else's fire, still burning. Take the watch."},
	{"id": "falls-camp", "kind": "rest", "stage_position": ["mid", "late"],
		"title": "Camp behind the falls", "desc": "Loud, but nothing can hear you either."},
	{"id": "chapel-floor", "kind": "rest", "stage_position": ["late"],
		"title": "The chapel floor", "desc": "Cold flagstones, thick doors, no windows."},
]

# The last stage is never a choice — but T18 made it not always the same fight.
# BOSS is the original, hand-tuned shrine fight (the four monsters.json archetypes,
# no lead); the rest of BOSS_POOL comes in two shapes:
#   "bestiary" — a rare, high-CR monster that carries a real special attack
#                (data/bestiary.json `_notes: implemented: …`), on a board whose
#                faction (scaler.THEME_FACTION) matches it, so its escort is its kin.
#   "elite"    — an ordinary early monster pumped into boss territory by the
#                scaler's own mult knob plus one extra attack (scaler.boss_for).
# build_route() seed-picks one, the same way it picks everything else.
const BOSS := {"id": "sunken-shrine", "kind": "combat", "stage_position": ["boss"],
	"title": "THE SUNKEN SHRINE", "desc": "Whatever has been calling them lives down here.",
	"difficulty": "hard", "boss": true, "archetype": "classic", "gold": 250,
	"theme": "sunken-shrine", "win_rate": 0.475}

# win_rate is each boss's measured sweep result (scaler.gd's TUNING header, T18)
# — how much harder it plays than a plain "hard" node. finish_combat() turns the
# gap under BOSS_REF_WIN_RATE into bonus XP (see there); a boss with no win_rate
# (there is none currently) would just award the plain amount.
const BOSS_POOL := [
	BOSS,
	{"id": "the-oni", "kind": "combat", "stage_position": ["boss"],
		"title": "THE ONI OF THE DEEP ICE", "desc": "It has worn a friendlier face all week.",
		"difficulty": "hard", "boss": true, "archetype": "bestiary", "gold": 250,
		"theme": "frozen-cave", "lead": "oni", "win_rate": 0.50},
	{"id": "the-assassin", "kind": "combat", "stage_position": ["boss"],
		"title": "THE KNIFE IN THE SQUARE", "desc": "Whoever paid the warband is here to collect.",
		"difficulty": "hard", "boss": true, "archetype": "bestiary", "gold": 250,
		"theme": "city-square", "lead": "assassin", "win_rate": 0.35},
	{"id": "the-mammoth", "kind": "combat", "stage_position": ["boss"],
		"title": "THE THING IN THE TREELINE", "desc": "The forest has been getting out of its way.",
		"difficulty": "hard", "boss": true, "archetype": "bestiary", "gold": 250,
		"theme": "forest-clearing", "lead": "mammoth", "win_rate": 0.22},
	{"id": "the-arrow-chief", "kind": "combat", "stage_position": ["boss"],
		"title": "THE ARROW-CHIEF", "desc": "The little archer from the road. He has been eating well.",
		"difficulty": "hard", "boss": true, "archetype": "elite", "gold": 250,
		"theme": "goblin-camp", "lead": "goblin-archer", "lead_features": ["monster-multiattack-2"],
		"win_rate": 0.68},
	{"id": "the-shop-captain", "kind": "combat", "stage_position": ["boss"],
		"title": "THE CAPTAIN COMES BACK", "desc": "He took the shop once. This time he brought the company.",
		"difficulty": "hard", "boss": true, "archetype": "elite", "gold": 250,
		"theme": "merchant-shop", "lead": "bandit", "lead_features": ["monster-multiattack-2"],
		"win_rate": 0.08},
]

# Reference win rate a boss's XP bonus is measured against: the average of the
# scaler's own easy/hard sweep results (92.5%/47.5%, scaler.gd's TUNING header)
# rather than normal's own 73.5% — CURVE was calibrated so normal sits near that
# average already, and it keeps this constant tied to the two extremes instead
# of a third independently-drifting number. A boss under this rate is harder
# than the curve's middle, and earns XP in proportion.
const BOSS_REF_WIN_RATE := 0.70
# ponytail: the win_rate spread above is power.gd's known control-underpricing
# ceiling showing through (shop-captain 8% vs arrow-chief 68%) — cap the bonus
# so that ceiling doesn't turn into a runaway XP multiplier. Retune alongside
# power.gd/BOSS_LEAD_SHARE.
const BOSS_XP_MULT_CAP := 2.5

# Quests are only ever offered by these merchants (quest.gd's giver_node_ids), so
# a route without one of them has nowhere to pick up work — see _ensure_giver().
const GIVER_IDS := ["wayside-camp", "hollow-market"]

# The run is over in these; nothing moves the road on afterwards.
const TERMINAL := ["won", "lost", "retired"]

# What a merchant sells: a handful of ids out of data/weapons.json + armor.json,
# priced by item_price() below. No haggling, no stock depletion.
const STOCK := ["shortsword", "longsword", "greataxe", "shortbow", "leather", "chain-shirt", "shield"]
const SCROLL := "scroll-of-resurrection"
const SELL_RATE := 0.5

var party
var stage := 0
var node: Dictionary = {}
var state := "picking"        # picking | visiting | combat | won | lost | retired
var xp := 0                   # run total, for the header; the real bank is ch.xp
var log: Array = []
var rng
var route: Array = []         # this run's stages, generated from the seed

func _init(p, seed_value := 0) -> void:
	party = p
	rng = RNG.new(seed_value)
	# Its own stream off the same seed: route generation must not shift the
	# loot/quest rolls the run rng makes, and both stay reproducible.
	route = build_route(RNG.new(rng.seed_value))

# --- the route ------------------------------------------------------------

# Deterministic in `r`: same seed, same route. Every stage is one "support" node
# (shop / camp / loot — pacing, and a road that is not a fight) plus 1-2 fights;
# the support kinds are dealt out so all three show up across the four stages.
static func build_route(r) -> Array:
	var support := _deal_support(r)
	var used := {}                   # no node template twice on one route
	var out: Array = []
	for i in STAGE_POSITIONS.size():
		var stage_nodes := _pick_stage(r, String(STAGE_POSITIONS[i]), String(support[i]), used)
		for n in stage_nodes:
			used[n["id"]] = true
		out.append(stage_nodes)
	_ensure_giver(r, out)
	out.append([BOSS_POOL[r.roll_die(BOSS_POOL.size()) - 1]])   # T18: which boss, this run
	return out

# One of each non-combat kind, shuffled, then a repeat to fill the fourth stage.
static func _deal_support(r) -> Array:
	var kinds := SUPPORT_KINDS.duplicate()
	var out: Array = []
	while not kinds.is_empty():
		out.append(kinds.pop_at(r.roll_die(kinds.size()) - 1))
	while out.size() < STAGE_POSITIONS.size():
		out.append(SUPPORT_KINDS[r.roll_die(SUPPORT_KINDS.size()) - 1])
	return out

static func _pick_stage(r, pos: String, support_kind: String, used: Dictionary) -> Array:
	var support := _eligible(pos, support_kind, used)
	if support.is_empty():           # a thin position: repeat rather than fail
		support = _eligible(pos, support_kind)
	var fights := _eligible(pos, "combat", used)
	var picked: Array = [support.pop_at(r.roll_die(support.size()) - 1)]
	var want: int = PICK_MIN + r.roll_die(PICK_MAX - PICK_MIN + 1) - 1
	while picked.size() < want and not fights.is_empty():
		picked.insert(r.roll_die(picked.size() + 1) - 1,
			fights.pop_at(r.roll_die(fights.size()) - 1))
	return picked

static func _eligible(pos: String, kind: String, used: Dictionary = {}) -> Array:
	return POOL.filter(func(n): return n["kind"] == kind and pos in n["stage_position"] and not used.has(n["id"]))

# The one invariant selection can violate: quests are only offered by two named
# merchants (quest.gd's giver_node_ids), so a route needs one of them before the
# boss. Swap it in over whichever merchant the route already has.
static func _ensure_giver(r, out: Array) -> void:
	var merchants: Array = []        # [stage index, slot index]
	for i in out.size():
		for j in out[i].size():
			if out[i][j]["id"] in GIVER_IDS:
				return
			if out[i][j]["kind"] == "merchant":
				merchants.append([i, j])
	if merchants.is_empty():
		return
	var at: Array = merchants[r.roll_die(merchants.size()) - 1]
	var givers: Array = _eligible(String(STAGE_POSITIONS[at[0]]), "merchant").filter(
		func(n): return n["id"] in GIVER_IDS)
	if not givers.is_empty():
		out[at[0]][at[1]] = givers[r.roll_die(givers.size()) - 1]

func options() -> Array:
	return route[stage] if stage < route.size() else []

func enter(i: int) -> Dictionary:
	var opts := options()
	if state != "picking" or i < 0 or i >= opts.size():
		return {}
	node = opts[i]
	identify_failed.clear()          # a new camp is a new chance to examine
	state = "combat" if node["kind"] == "combat" else "visiting"
	say("→ %s" % node["title"])
	if node["kind"] == "treasure":
		_take_treasure()
	_autosave()
	return node

func leave() -> void:
	if state in TERMINAL:
		return
	node = {}
	stage += 1
	state = "won" if stage >= route.size() else "picking"
	if state == "won":
		say("The road ends. The party lives.")
		_conclude()
	_autosave()

# T17 — walk away between nodes with everything already banked. Only ever legal
# while picking: never mid-visit, never mid-fight. Wraps up like a win does.
func retire() -> bool:
	if state != "picking":
		return false
	node = {}
	state = "retired"
	say("The party turns back, purses full. The run ends on their terms.")
	_conclude()
	_autosave()
	return true

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

# What this fight is worth: the node's authored difficulty, or — when a node
# doesn't name one — the player's setting. The one place that default is read.
func node_difficulty() -> String:
	return String(node.get("difficulty", Settings.current().default_difficulty))

# Quest bias goes in here: unfulfilled targets show up more often from now on.
func combat_spec() -> Dictionary:
	var theme: String = String(node.get("theme", "sunken-shrine"))
	# T16: theme picks the faction; the run seed + node id keeps the roster stable
	# across a reload of the same node.
	var seed: int = rng.seed_value + hash(node.get("id", ""))
	# T18: a boss with a named lead is built round that lead; everything else
	# (including the classic shrine boss) is a plain faction roster.
	var spec: Dictionary = Scaler.boss_for(party.party_characters(), node, seed) if node.has("lead") \
		else Scaler.roster_for(party.party_characters(), node_difficulty(),
			Quest.bias(party), theme, seed)
	spec["theme"] = theme   # T11: which board this fight is on
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
	var earned_xp: int = roundi(int(result.get("xp", 0)) * _xp_mult())
	xp += earned_xp
	_split_xp(earned_xp)
	party.add_gold(int(result.get("gold", 0)) + int(node.get("gold", 0)))
	for item in result.get("loot", []):
		party.stash_add(String(item))
	say("Victory. +%d XP, +%d gold." % [earned_xp,
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

# A boss node's win_rate under BOSS_REF_WIN_RATE means it plays harder than
# the curve's middle; the shortfall becomes bonus XP, capped at BOSS_XP_MULT_CAP.
# Every non-boss node (no "win_rate" key) gets a plain 1.0.
func _xp_mult() -> float:
	if not node.get("boss", false) or not node.has("win_rate"):
		return 1.0
	var wr: float = maxf(float(node["win_rate"]), 0.01)
	return clampf(BOSS_REF_WIN_RATE / wr, 1.0, BOSS_XP_MULT_CAP)

# Split evenly among whoever was in the fight; the remainder is dropped.
func _split_xp(total: int) -> void:
	var fighters: Array = party.party_characters()
	if fighters.is_empty() or total <= 0:
		return
	var share: int = total / fighters.size()
	for ch in fighters:
		ch.xp += share

# --- treasure -------------------------------------------------------------

# Loot is the only source of mysteries: a magic item out of a hoard arrives
# unidentified (T13), mundane steel arrives as itself. Merchants label what they sell.
func _take_treasure() -> void:
	party.add_gold(int(node.get("gold", 0)))
	say("+%d gold." % int(node.get("gold", 0)))
	if node.has("item_id"):
		_find_item(String(node["item_id"]))
	if rng.roll_die(SCROLL_DROP_ONE_IN) == 1:
		_find_item(IDENTIFY_SCROLL)

func _find_item(item_id: String) -> void:
	var magic := is_magic(item_id)
	party.stash_add(item_id, 1, not magic)
	# The journal is bbcode; the ramp tints the name so a legendary drop reads as one.
	say("Found: %s." % Icons.item_bb(item_id, mystery_name(item_id) if magic else item_name(item_id)))

# --- rest -----------------------------------------------------------------

func rest(kind: String) -> void:
	if node.get("kind", "") != "rest":
		return
	var Adapter = load("res://core/adapter.gd")
	for ch in party.party_characters():
		Adapter.rest(ch, kind)
	say("The party takes a %s." % kind.replace("-", " "))
	_autosave()

# --- identification (T13) -------------------------------------------------
#
# The real 5e optional rule: identifying by examination happens over a short rest,
# so the Arcana check is offered at rest nodes only. A failed examination is final
# for this node — walking on and camping again is another chance.

# DC is fixed per rarity, not per examiner — a real item has one difficulty to
# puzzle out, the same for everyone (matches how the rest of 5e's DCs work).
# Calibrated once against a reference +2 Arcana examiner (REFERENCE_ARCANA_BONUS)
# so the target rate below (rarer = harder) holds for a typical character;
# anyone better or worse than reference does correspondingly better or worse,
# same as real play. DC = 21 + REFERENCE_ARCANA_BONUS - 20*target, same linear
# d20+mod-vs-DC model as hit_chance/save_fail_chance elsewhere, rounded and
# clamped to a sane DC range.
const REFERENCE_ARCANA_BONUS := 2
const IDENTIFY_TARGET := {
	"uncommon": 0.90, "rare": 0.80, "very-rare": 0.60, "legendary": 0.35, "artifact": 0.15,
}
const IDENTIFY_DEFAULT_TARGET := 0.80   # "varies"/unlisted rarity falls back to rare's odds

# {rarity: dc} — uncommon 5, rare 7, very-rare 11, legendary 16, artifact 20 at
# the +2 reference. Hand-computed from IDENTIFY_TARGET so it stays a plain
# const (no runtime derivation); re-derive by hand if either constant above
# changes rather than letting the two drift apart silently.
const IDENTIFY_DC := {
	"uncommon": 5, "rare": 7, "very-rare": 11, "legendary": 16, "artifact": 20,
}
const IDENTIFY_DEFAULT_DC := 7   # matches IDENTIFY_DEFAULT_TARGET (rare's odds)

const IDENTIFY_SCROLL := "scroll-of-identification"
const SCROLL_DROP_ONE_IN := 4        # a hoard sometimes also holds an identify scroll

var identify_failed: Array = []      # item ids already flubbed at this node

# Whose Arcana the examination uses: the best of the active party. "" if nobody.
func arcana_examiner() -> String:
	var best := ""
	var best_bonus := -99
	for ch in party.party_characters():
		var b := int(ch.sheet().skills.get("arcana", 0))
		if b > best_bonus:
			best_bonus = b
			best = ch.id
	return best

func arcana_bonus(char_id: String) -> int:
	var ch = party.get_member(char_id)
	return int(ch.sheet().skills.get("arcana", 0)) if ch != null else 0

# The item's fixed identification DC (rarity-based, calibrated at the +2
# reference examiner — see IDENTIFY_DC above).
static func identify_dc(item_id: String) -> int:
	var rarity := String(item_data(item_id).get("rarity", ""))
	return int(IDENTIFY_DC.get(rarity, IDENTIFY_DEFAULT_DC))

# d20 + Arcana vs the item's fixed rarity DC, one attempt per item per rest node.
func identify_check(item_id: String, char_id: String) -> bool:
	var ch = party.get_member(char_id)
	if node.get("kind", "") != "rest" or ch == null or item_id in identify_failed:
		return false
	if party.stash_count(item_id) - party.stash_count(item_id, true) < 1:
		return false
	var bonus := arcana_bonus(char_id)
	var dc := identify_dc(item_id)
	var nat: int = int(Dice.d20(rng)["nat"])
	var total := nat + bonus
	if total < dc:
		identify_failed.append(item_id)
		say("%s examines it and learns nothing (%d+%d vs DC %d)." % [ch.cname, nat, bonus, dc])
		_autosave()
		return false
	party.stash_identify(item_id)
	say("%s identifies it: %s (%d+%d vs DC %d)." % [ch.cname, item_name(item_id), nat, bonus, dc])
	_autosave()
	return true

# The scroll: no roll, no rest needed. Profile screen's stash panel drives this.
func identify_with_scroll(item_id: String) -> bool:
	if not party.use_identification_scroll(item_id):
		return false
	say("The Scroll of Identification crumbles: %s." % item_name(item_id))
	_autosave()
	return true

# --- merchant -------------------------------------------------------------

# The steel and straps, plus — at some merchants — the one consumable that
# matters: a Scroll of Resurrection. Keyed off the node id, so a given merchant
# either has one or never does.
func stock_ids() -> Array:
	var ids: Array = STOCK.duplicate()
	ids.append(IDENTIFY_SCROLL)       # cheap and always worth carrying: every merchant has one
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

static func is_magic(item_id: String) -> bool:
	return Catalog.index("magic-items.json").has(item_id)

# What an unidentified item shows as: its rarity, nothing else.
static func mystery_name(item_id: String) -> String:
	return "Unidentified item (%s)" % String(item_data(item_id).get("rarity", "unknown"))

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

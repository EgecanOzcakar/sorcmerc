# Callings — the past each hero's background hands them, pointed at the map.
#
# Every companion in sorcmerc is player-made, so the companion with a past that
# comes calling has to be systemic: sixteen templates, one per background, each
# aimed at something the live world already holds — a landmark, a lair, a band,
# a town, a lord's hall. Told once at the fire, done on the road, paid in XP, an
# heirloom and a bond with whoever did the thing.
#   docs/superpowers/specs/2026-09-21-callings-relations-design.md
#
# What this owns: the templates, the choice of target, the telling, what
# completes one, the rewards, the save shape. What it does not: when any of it
# fires (scenes/world/world.gd), the drawing, the pictures.
#
# State lives on the party — party.callings: char_id -> {"id" (the background),
# "target_kind", "target_id", "state", "told_at"}; state "" (assigned, untold),
# "told" (spoken at the fire, the target marked), "done".
extends RefCounted

const PartyOpinion = preload("res://core/party_opinion.gd")
const Campaign = preload("res://core/campaign.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const CALLING_XP := 120

# What check() is told, and what each kind of target is done by.
const EVENT_KINDS := ["landmark_answered", "lair_cleared", "band_beaten", "visited", "audience"]
const DONE_BY := {"landmark": "landmark_answered", "lair": "lair_cleared", "band": "band_beaten",
	"settlement": "visited", "audience": "audience"}   # target kind -> the one event that completes it
const SETTLEMENT_SIZES := ["camp", "town", "city"]   # a missing kind falls back to a larger one

const TEMPLATES := {  # background -> template
	"acolyte":     {"title": "The defiled shrine", "target": {"kind": "landmark", "landmark": "shrine"}, "done_by": "landmark_answered",
		"item": "amulet-of-proof-against-detection-and-location",
		"tell": "You served at a shrine like %s once, before the road. Word at the fire is that this one has been used for something it was not raised for. You would know what to do about that.",
		"done": "%s is a shrine again. Whatever they did there is undone, and you did the undoing."},
	"artisan":     {"title": "The master's mark", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "gloves-of-swimming-and-climbing",
		"tell": "%s, they say, was a master's cart — the one whose mark is on your own tools. Whatever is left of the load is worth a look from someone who can read the work.",
		"done": "You found the master's mark on a broken chest at %s, and a set of tools you will not sell."},
	"charlatan":   {"title": "The old mark", "target": {"kind": "settlement", "settlement": "town"}, "done_by": "visited",
		"item": "hat-of-disguise",
		"tell": "Somebody in %s paid you once for something that was not what you said it was. You have been avoiding the place. It is time to walk in the front gate and see what that costs.",
		"done": "Nobody in %s remembered your face, or nobody said so. You bought the old mark a drink."},
	"criminal":    {"title": "An old debt", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "cloak-of-elvenkind",
		"tell": "The band called %s is asking after you by name, town to town. You know what you owe them and you know they will not take coin for it.",
		"done": "%s will not come asking again. The debt is paid in the only coin they took."},
	"entertainer": {"title": "A hall worth the song", "target": {"kind": "audience"}, "done_by": "audience",
		"item": "pipes-of-haunting",
		"tell": "You have played taverns and camps. You have never played a hall with a lord at the far end of it. The company is getting the kind of name that gets asked.",
		"done": "You played the hall. They will tell it wrong for years, and that is the point."},
	"farmer":      {"title": "The burned steading", "target": {"kind": "lair"}, "done_by": "lair_cleared",
		"item": "decanter-of-endless-water",
		"tell": "The thing that burned your family's steading came out of %s. You told nobody in this company. You did not have to.",
		"done": "%s is empty. It is not the steading back, but it is the thing that burned it gone."},
	"guard":       {"title": "The one that got away", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "shield-1",
		"tell": "Every guard has one they let past the gate. Yours is riding with %s now, and the company keeps crossing their road.",
		"done": "%s is finished, and the one that got away did not, this time."},
	"guide":       {"title": "The road not yet walked", "target": {"kind": "landmark", "landmark": "tower"}, "done_by": "landmark_answered",
		"item": "eyes-of-the-eagle",
		"tell": "There is one height in this country you have never stood on: %s. A guide who has not seen the whole of it is guessing about the rest.",
		"done": "From %s you saw the whole of it. You are not guessing any more."},
	"hermit":      {"title": "The stones that spoke", "target": {"kind": "landmark", "landmark": "stones"}, "done_by": "landmark_answered",
		"item": "ring-of-mind-shielding",
		"tell": "You went into the wild to hear something, and once, at a ring like %s, you did. You have not been back to ask what it meant.",
		"done": "%s said the rest of it. You are keeping that one."},
	"merchant":    {"title": "The lost consignment", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "bag-of-holding",
		"tell": "%s was carrying your consignment when it went over, the one that ended your trade. Nobody has been through it since.",
		"done": "The consignment at %s was mostly gone. What was left was worth the walk."},
	"noble":       {"title": "The rival envoy", "target": {"kind": "settlement", "settlement": "city"}, "done_by": "visited",
		"item": "cloak-of-protection",
		"tell": "A rival house's envoy is at %s, and the company's name has reached them. Your house's business is yours to conduct, sword or no sword.",
		"done": "The envoy at %s knows the company's name now, and whose company it is."},
	"sage":        {"title": "The lost library", "target": {"kind": "lair"}, "done_by": "lair_cleared",
		"item": "pearl-of-power",
		"tell": "The books you spent your youth looking for are under %s. Whatever lives in it now does not read.",
		"done": "The library under %s was mostly rot. Three books were not, and you carried them out yourself."},
	"sailor":      {"title": "The wreck of the Kestrel", "target": {"kind": "landmark", "landmark": "wreck"}, "done_by": "landmark_answered",
		"item": "cloak-of-the-manta-ray",
		"tell": "You have heard %s called by another name: the Kestrel, the one you got off in the dark and swore was lost with all hands. Somebody should go and see.",
		"done": "%s was the Kestrel. Nobody else got off. You put a stone on it."},
	"scribe":      {"title": "The unfinished chronicle", "target": {"kind": "landmark", "landmark": "ruins"}, "done_by": "landmark_answered",
		"item": "helm-of-comprehending-languages",
		"tell": "The chronicle you copied as an apprentice ended mid-sentence, at a place it called %s. The stones there might say how the sentence ends.",
		"done": "The stones at %s finished the sentence. You have written it down."},
	"soldier":     {"title": "The deserters", "target": {"kind": "band"}, "done_by": "band_beaten",
		"item": "javelin-of-lightning",
		"tell": "%s are deserters from a company you served in. You know their captain. He knows what you do to deserters.",
		"done": "%s are accounted for. You did not enjoy it, and you did not pretend to."},
	"wayfarer":    {"title": "The hut at the end of the road", "target": {"kind": "landmark", "landmark": "hut"}, "done_by": "landmark_answered",
		"item": "boots-of-striding-and-springing",
		"tell": "Every road you have walked, someone told you it ended at a hut like %s, and someone lived there who knew the way on. You have never reached it.",
		"done": "%s was the end of the road, and someone did live there. They knew the way on. So do you, now."},
}

# The built-in sixteen, with every live pack's callings.json merged over them
# by background — Registry.apply_data() pushes those here the way it pushes
# data overlays into the catalog, in scan order, so a later pack wins. Merged
# once, when the packs arrive: templates() is read every frame by assign().
static var _templates: Dictionary = TEMPLATES

static func set_packs(merged: Dictionary) -> void:
	_templates = TEMPLATES.duplicate(true)
	for k in merged:
		if not String(k).begins_with("_"):   # _note and friends: authoring comments
			_templates[String(k)] = merged[k]

static func templates() -> Dictionary:
	return _templates

# A pack's callings.json, checked at scan time the way a world is: the shape
# of one template per background, a target kind the game can point at, the
# event that kind is done by, and an item that exists (in the catalog or in
# the pack's own overlay — `own_items`). Returns the errors, empty when clean.
static func validate(src, own_items := {}) -> Array:
	var errors: Array = []
	if not (src is Dictionary):
		return ["callings.json must be an object of {background: calling}"]
	var Landmarks = load("res://core/landmarks.gd")
	var items: Dictionary = Catalog.index("magic-items.json")
	for key in src:
		var bg := String(key)
		if bg.begins_with("_"):
			continue          # _note and friends: authoring comments, by convention
		var t = src[key]
		if not (t is Dictionary):
			errors.append("calling \"%s\" must be an object" % bg)
			continue
		for k in ["title", "tell", "done", "item"]:
			if String(t.get(k, "")).is_empty():
				errors.append("calling \"%s\" needs a %s" % [bg, k])
		var item := String(t.get("item", ""))
		if item != "" and not items.has(item) and not own_items.has(item):
			errors.append("calling \"%s\": item \"%s\" is not a magic item in the catalog or in this pack" % [bg, item])
		var target = t.get("target", {})
		var kind := String(target.get("kind", "")) if target is Dictionary else ""
		if not DONE_BY.has(kind):
			errors.append("calling \"%s\": target kind \"%s\" is not one of %s" % [bg, kind, DONE_BY.keys()])
			continue
		if String(t.get("done_by", "")) != String(DONE_BY[kind]):
			errors.append("calling \"%s\": a %s is done by \"%s\", not \"%s\"" % [bg, kind, DONE_BY[kind], t.get("done_by", "")])
		if kind == "landmark" and not Landmarks.KINDS.has(String(target.get("landmark", ""))):
			errors.append("calling \"%s\": landmark \"%s\" is not one of %s" % [bg, target.get("landmark", ""), Landmarks.KINDS])
		if kind == "settlement" and not SETTLEMENT_SIZES.has(String(target.get("settlement", ""))):
			errors.append("calling \"%s\": settlement \"%s\" is not one of %s" % [bg, target.get("settlement", ""), SETTLEMENT_SIZES])
	return errors

# --- assign -----------------------------------------------------------------

# Every active hero with a template and no calling yet gets one, pointed at the
# nearest thing of the template's kind. No such thing on this map → no calling
# yet, tried again next call — so the screen can ask every frame and every
# camp. Returns the ids newly assigned, in marching order.
#
# The same pass re-reads every calling not yet done: a target the world has
# lost since — a shrine spent before the telling, a band beaten by someone
# else or gone home, a lair the map dropped — is re-picked the same way (a
# looted lair is not lost; it respawns). A told calling's new target is marked
# as the old one was, so the map never points at nothing; no fit yet leaves
# the entry with an empty target, which beat() and check() skip until the
# next pass finds one.
static func assign(party, world, _rng = null) -> Array:
	var out: Array = []
	var from: Vector2 = world.player().position if world.player() != null else Vector2.ZERO
	for id in party.active:
		var c: Dictionary = party.callings.get(id, {})
		if not c.is_empty():
			if String(c["state"]) != "done" and _gone(world, c):
				_retarget(world, c, from)
			continue
		var ch = party.get_member(id)
		if ch == null or not templates().has(ch.background_id):
			continue
		var spec: Dictionary = templates()[ch.background_id]["target"]
		var target_id := ""
		if spec["kind"] != "audience":
			var target = _nearest(world, spec, from)
			if target == null:
				continue
			target_id = target.id
		party.callings[id] = {"id": ch.background_id, "target_kind": spec["kind"], "target_id": target_id,
			"state": "", "told_at": -1.0}
		out.append(id)
	return out

# An audience needs no target; anything else is gone when the world no longer
# has it — or, a landmark, when it is spent (it can never fire landmark_answered again).
static func _gone(world, c: Dictionary) -> bool:
	if String(c["target_kind"]) == "audience":
		return false
	var target = _target(world, c)
	return target == null or ("spent" in target and target.spent)

static func _retarget(world, c: Dictionary, from: Vector2) -> void:
	var t: Dictionary = templates().get(String(c["id"]), {})
	var target = _nearest(world, t["target"], from) if not t.is_empty() else null
	c["target_id"] = "" if target == null else String(target.id)
	if target != null and String(c["state"]) == "told":
		_mark(world, target)

# A landmark of the kind, found or hidden (the telling finds it); a lair not yet
# looted; a monster band that is people (the copy is about deserters and debt
# collectors, so bandits before wolves), any monster band when the map has no
# people, never a raiding band (it is marching at a town and will be gone or
# dead before the party gets there); a civilized settlement of the kind, or of
# a larger one when the map has none (a charlatan's old mark can live in a city).
const PEOPLE := ["bandit", "goblinoid", "orc", "gnoll", "kobold", "cultist"]

static func _nearest(world, spec: Dictionary, from: Vector2):
	var WorldAI = load("res://core/world_ai.gd")
	var pool: Array = []
	match String(spec["kind"]):
		"landmark":
			# not spent — mirrors the lair's "not looted": a spent one can never fire landmark_answered again.
			pool = world.landmarks.filter(func(l): return l.kind == spec["landmark"] and not l.spent)
		"lair":
			pool = world.lairs.filter(func(l): return not l.looted)
		"band":
			var bands: Array = world.parties.filter(func(p): return not p.is_player and WorldAI.is_monster(p.faction) and String(p.ai.get("behavior", "")) != "raid")
			pool = bands.filter(func(p): return PEOPLE.has(p.faction))
			if pool.is_empty():
				pool = bands
		"settlement":
			var civ: Array = world.settlements.filter(func(s): return not WorldAI.is_monster(s.faction))
			var want: int = SETTLEMENT_SIZES.find(spec["settlement"])
			pool = civ.filter(func(s): return s.kind == spec["settlement"])
			if pool.is_empty():
				pool = civ.filter(func(s): return SETTLEMENT_SIZES.find(s.kind) > want)
	var best = null
	var best_d := INF
	for x in pool:
		var d: float = from.distance_to(x.position)
		if d < best_d:
			best = x
			best_d = d
	return best

# --- the telling ------------------------------------------------------------

# The first active hero whose calling is untold speaks: one paragraph, and the
# target is marked — a landmark found, a lair discovered, and the ground it
# stands on revealed, since every layer that would draw the mark gates on
# is_explored (a hidden mark is no mark); a band or a town is named in the
# line. A calling waiting on a target (assign() found none yet) is not told.
# Returns {} when nobody has anything to tell.
static func beat(party, world) -> Dictionary:
	for id in party.active:
		var c: Dictionary = party.callings.get(id, {})
		var t: Dictionary = templates().get(String(c.get("id", "")), {})
		if t.is_empty() or String(c["state"]) != "" or _waiting(c):
			continue
		var ch = party.get_member(id)
		if ch == null:
			continue
		var target = _target(world, c)
		if target != null:
			_mark(world, target)
		c["state"] = "told"
		c["told_at"] = world.clock.elapsed
		return {"char_id": id, "cname": ch.cname, "title": t["title"], "id": String(c["id"]),
			"text": _fmt(t["tell"], target_name(party, world, id))}
	return {}

static func _waiting(c: Dictionary) -> bool:
	return String(c["target_kind"]) != "audience" and String(c["target_id"]) == ""

static func _mark(world, target) -> void:
	if "found" in target:
		target.found = true
	elif "discovered" in target:
		target.discovered = true
	world.reveal(target.position)

# --- doing the thing --------------------------------------------------------

# The world screen says what just happened — {"kind": one of EVENT_KINDS, "id":
# the landmark / lair / band / settlement} — and this says whose told calling
# that was. Any audience is the entertainer's. A dead hero's past does not
# complete: the bond and the line are theirs to have. Deciding only: the
# screen calls complete() and shows the card.
static func check(party, world, event: Dictionary) -> Array:
	var out: Array = []
	for id in party.callings:
		var c: Dictionary = party.callings[id]
		var t: Dictionary = templates().get(String(c["id"]), {})
		if t.is_empty() or String(c["state"]) != "told" or String(t["done_by"]) != String(event.get("kind", "")) or _waiting(c):
			continue
		var ch = party.get_member(String(id))
		if ch == null or ch.dead:
			continue
		if String(c["target_kind"]) == "audience" or String(c["target_id"]) == String(event.get("id", "")):
			out.append(id)
	return out

# The rewards: the XP split, the heirloom identified into the stash, and the
# bond with `who` — the member who rolled the row, struck the blow, led the
# visit. When that was the hero themself (the acolyte is the party's best at
# Religion, so at the shrine it usually is) or nobody, the bond goes to
# whoever stands closest to them instead: the active companion they already
# think most of, ties by marching order. Alone, there is nobody to bond with.
# A calling completes once.
static func complete(party, world, char_id: String, who := "") -> Dictionary:
	var c: Dictionary = party.callings.get(char_id, {})
	var t: Dictionary = templates().get(String(c.get("id", "")), {})
	if t.is_empty() or String(c["state"]) != "told":
		return {}
	Campaign.new(party)._split_xp(CALLING_XP)
	var item := String(t["item"])
	party.stash_add(item)
	Campaign._note_rarity(item)
	var out := {"text": _fmt(t["done"], target_name(party, world, char_id)), "xp": CALLING_XP,
		"item": item, "item_name": Campaign.item_name(item), "bond_with": ""}
	if who == "" or who == char_id:
		who = _closest(party, char_id)
	if who != "":
		PartyOpinion.adjust(party, char_id, who, PartyOpinion.CALLING_BOND)
		out["bond_with"] = who
	c["state"] = "done"
	Ach.collect("callings", char_id)
	return out

# The active companion this hero's score is highest with; "" when alone.
static func _closest(party, char_id: String) -> String:
	var best := ""
	var best_s := -INF
	for id in party.active:
		var s: float = PartyOpinion.score(party, char_id, String(id))
		if String(id) != char_id and s > best_s:
			best = String(id)
			best_s = s
	return best

# --- reading it -------------------------------------------------------------

# One line for the party page and the quest log; nothing while untold.
static func describe(party, char_id: String) -> String:
	var c: Dictionary = party.callings.get(char_id, {})
	var t: Dictionary = templates().get(String(c.get("id", "")), {})
	if t.is_empty():
		return ""
	match String(c["state"]):
		"told":
			return "%s — told, marked on the map" % t["title"]
		"done":
			return "%s — done" % t["title"]
	return ""

# What the tell and the done line call the target. A band has no sname: its id.
static func target_name(party, world, char_id: String) -> String:
	var c: Dictionary = party.callings.get(char_id, {})
	if String(c.get("target_kind", "")) == "band":
		return String(c["target_id"]).capitalize()
	var target = _target(world, c)
	return "" if target == null else target.sname

# The audience template has no %s to fill.
static func _fmt(text: String, name: String) -> String:
	return text % name if "%s" in text else text

static func _target(world, c: Dictionary):
	var pool: Array = {"landmark": world.landmarks, "lair": world.lairs, "band": world.parties,
		"settlement": world.settlements}.get(String(c.get("target_kind", "")), [])
	for x in pool:
		if x.id == c["target_id"]:
			return x
	return null

# --- persistence ------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.callings.duplicate(true)

static func from_dict(party, d) -> void:
	party.callings = {}
	if not d is Dictionary:
		return
	for k in d:
		var e = d[k]
		if not (e is Dictionary and e.has("id")):
			continue
		party.callings[String(k)] = {"id": String(e["id"]), "target_kind": String(e.get("target_kind", "")),
			"target_id": String(e.get("target_id", "")), "state": String(e.get("state", "")),
			"told_at": float(e.get("told_at", -1.0))}

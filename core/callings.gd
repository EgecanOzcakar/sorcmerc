# Callings — the past each hero's background hands them, pointed at the map.
#
# sorcmerc has no authored companions — the founder is made in the creator and
# everyone after is a hire rolled at an inn (core/recruits.gd) — so the
# companion with a past that comes calling has to be systemic: templates per
# background — two or three each since the design audit (§2.5), picked per
# hero — each aimed at something the live world already holds — a landmark, a
# lair, a band, a town, a lord's hall. Told once at the fire, done on the road,
# paid in XP, an heirloom and a bond with whoever did the thing.
#   docs/superpowers/specs/2026-09-21-callings-relations-design.md
#
# What this owns: the templates, the choice of past and target, the telling,
# what completes one, the rewards, the save shape. What it does not: when any
# of it fires (scenes/world/world.gd), the drawing, the pictures.
#
# State lives on the party — party.callings: char_id -> {"id" (the background),
# "variant" (which of its pasts, variants(bg) index; 0 in an old save),
# "target_kind", "target_id", "state", "told_at"}; state "" (assigned, untold),
# "told" (spoken at the fire, the target marked), "done".
extends RefCounted

const PartyOpinion = preload("res://core/party_opinion.gd")
const Campaign = preload("res://core/campaign.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const EnemyNames = preload("res://core/enemy_names.gd")
const Scaler = preload("res://core/scaler.gd")

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
		"tell": "%s are asking after you by name, town to town. You know what you owe them and you know they will not take coin for it.",
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
		"done": "%s are finished, and the one that got away did not, this time."},
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
	"soldier":     {"title": "The deserters", "target": {"kind": "band", "factions": ["bandit", "soldier"]}, "done_by": "band_beaten",
		"item": "javelin-of-lightning",
		"tell": "%s are deserters from a company you served in. You know their captain. He knows what you do to deserters.",
		"done": "%s are accounted for. You did not enjoy it, and you did not pretend to."},
	"wayfarer":    {"title": "The hut at the end of the road", "target": {"kind": "landmark", "landmark": "hut"}, "done_by": "landmark_answered",
		"item": "boots-of-striding-and-springing",
		"tell": "Every road you have walked, someone told you it ended at a hut like %s, and someone lived there who knew the way on. You have never reached it.",
		"done": "%s was the end of the road, and someone did live there. They knew the way on. So do you, now."},
}

# More pasts for the same background (the design audit, docs/audit-game-design.md
# §2.5: "one calling per background" made every soldier's past the same
# deserters). TEMPLATES above is each background's first; these are its
# second and third, in the same shape and held to the same validator. A hero's
# is picked when it is assigned, seeded off the hero (assign(), below), and
# kept in the save as `variant` — the index into variants(bg), 0 being the
# first — so a reload tells the same past. A band variant that names people
# who keep papers or grudges says which ones in `factions`, the rule round one
# gave the deserters.
const VARIANTS := {  # background -> [template, ...]
	"acolyte": [
		{"title": "The taken novices", "target": {"kind": "band", "factions": ["cultist"]}, "done_by": "band_beaten",
			"item": "periapt-of-wound-closure",
			"tell": "%s preach a faith your order taught you to name as a lie. When they left the valley they took two of its novices with them. You would like the novices back, or the truth of what became of them.",
			"done": "%s are scattered. Of the novices there was no trace, but nobody else will be taken."}],
	"artisan": [
		{"title": "The stolen tools", "target": {"kind": "band"}, "done_by": "band_beaten",
			"item": "gauntlets-of-ogre-power",
			"tell": "%s robbed the workshop you learned your trade in, and burned what they could not carry. Your old master's tools went with them.",
			"done": "%s had your master's tools in a sack, most of them. You have been cleaning them by the fire since."}],
	"charlatan": [
		{"title": "The magistrate", "target": {"kind": "settlement", "settlement": "city"}, "done_by": "visited",
			"item": "eyes-of-charming",
			"tell": "There is a magistrate in %s who hanged the man you worked with and never caught you. You would like to walk past the courthouse once, as someone else.",
			"done": "You walked past the courthouse in %s twice. Nobody looked up."}],
	"criminal": [
		{"title": "The buried take", "target": {"kind": "landmark", "landmark": "ruins"}, "done_by": "landmark_answered",
			"item": "boots-of-elvenkind",
			"tell": "Before they caught you, you hid a take in %s. It has been a long time. It might still be there.",
			"done": "The take was still in %s, under the third stone. It is smaller than you remember."},
		{"title": "The fence's cellar", "target": {"kind": "lair"}, "done_by": "lair_cleared",
			"item": "dust-of-disappearance",
			"tell": "Your old fence kept his stock under %s. Something else keeps it now, and the fence's ledger with your name in it.",
			"done": "%s is empty. The ledger was there, with your name in it. It burned well."}],
	"entertainer": [
		{"title": "The stolen song", "target": {"kind": "settlement", "settlement": "town"}, "done_by": "visited",
			"item": "deck-of-illusions",
			"tell": "A troupe in %s is playing your song under somebody else's name. You would like a word with them, and with the crowd.",
			"done": "You played it in %s the way it was written. The troupe left before the second verse."}],
	"farmer": [
		{"title": "The driven herd", "target": {"kind": "band"}, "done_by": "band_beaten",
			"item": "bag-of-tricks",
			"tell": "%s drove off your village's herd the autumn before you left. The village went hungry that winter. You counted the graves.",
			"done": "%s will not drive off anyone's herd again. It feeds nobody back home, but it is something."}],
	"guard": [
		{"title": "The tower you ran from", "target": {"kind": "landmark", "landmark": "tower"}, "done_by": "landmark_answered",
			"item": "weapon-of-warning",
			"tell": "You stood watch at a tower like %s the night it was overrun, and you ran. You have wanted to go back up ever since.",
			"done": "You climbed %s to the top and stood the watch you left. Nothing came. That was the point."}],
	"guide": [
		{"title": "The party you left", "target": {"kind": "lair"}, "done_by": "lair_cleared",
			"item": "rope-of-climbing",
			"tell": "You once left a party at the mouth of %s because they would not turn back. You have told yourself since that they found another way out.",
			"done": "What was left of the party was in %s. You brought their names out, and a cloak you knew."}],
	"hermit": [
		{"title": "The one who taught you", "target": {"kind": "landmark", "landmark": "hut"}, "done_by": "landmark_answered",
			"item": "periapt-of-health",
			"tell": "The hermit who taught you lived in a place like %s, and one winter you left and did not go back. Somebody should know how that ended.",
			"done": "The hut at %s was empty and swept, and there was a note for whoever came. You were expected."}],
	"merchant": [
		{"title": "The bought note", "target": {"kind": "band", "factions": ["bandit", "soldier"]}, "done_by": "band_beaten",
			"item": "stone-of-good-luck-(luckstone)",
			"tell": "%s are holding a note of yours they bought cheap from a dead man. They mean to collect it in something other than coin.",
			"done": "%s will not collect. The note burned very easily."}],
	"noble": [
		{"title": "The family seat", "target": {"kind": "landmark", "landmark": "ruins"}, "done_by": "landmark_answered",
			"item": "brooch-of-shielding",
			"tell": "%s was a house your family held before the war took it. Your father never spoke of it. You would like to stand in the hall.",
			"done": "You stood in the hall at %s. There is no roof, and your family's arms are still over the door."}],
	"sage": [
		{"title": "The night at the stones", "target": {"kind": "landmark", "landmark": "stones"}, "done_by": "landmark_answered",
			"item": "headband-of-intellect",
			"tell": "An old text puts a reading at a ring like %s, one night in the year. You have worked out which night. You would like to be wrong in person.",
			"done": "The stones at %s lined up the way the text said. You were not wrong. That is worse."}],
	"sailor": [
		{"title": "The mutineers", "target": {"kind": "band", "factions": ["bandit"]}, "done_by": "band_beaten",
			"item": "trident-of-fish-command",
			"tell": "%s have a man among them who led the mutiny that put you over the side. You know his voice. You would know it anywhere.",
			"done": "%s are finished, and the man with the voice with them. You slept that night as if you were back at sea."}],
	"scribe": [
		{"title": "The carried-off archive", "target": {"kind": "lair"}, "done_by": "lair_cleared",
			"item": "wand-of-magic-detection",
			"tell": "The archive you trained in was carried off in a raid, and the raiders went to ground in %s. Paper does not last long in a lair. Some of it might.",
			"done": "Most of the archive in %s was nests and ash. You brought out a ledger and a map, and have not stopped reading."}],
	"soldier": [
		{"title": "The last stand", "target": {"kind": "landmark", "landmark": "ruins"}, "done_by": "landmark_answered",
			"item": "bracers-of-archery",
			"tell": "Your old company made its last stand at %s. You were not there; you were sick in the rear. You have never been to see it.",
			"done": "You found the company's standard at %s, what was left of it. You carry it now."},
		{"title": "The captain's price", "target": {"kind": "settlement", "settlement": "city"}, "done_by": "visited",
			"item": "shield-1",
			"tell": "The captain who sold your company to the other side lives in %s now, on the money. You do not mean to kill him. You mean for him to see you.",
			"done": "He saw you, in %s, across a crowded square. He left the city that night. That will do."}],
	"wayfarer": [
		{"title": "The debt of a meal", "target": {"kind": "settlement", "settlement": "camp"}, "done_by": "visited",
			"item": "boots-of-the-winterlands",
			"tell": "A stranger at %s once fed you for nothing when you had nothing. You told them you would come back and pay.",
			"done": "You paid at %s. The stranger was long gone, so you paid the next hungry traveller instead."}],
}

# The built-in sixteen, with every live pack's callings.json merged over them
# by background — Registry.apply_data() pushes those here the way it pushes
# data overlays into the catalog, in scan order, so a later pack wins. Merged
# once, when the packs arrive: templates() is read every frame by assign().
# A pack that writes a background's calling writes THE past for it: the
# built-in variants of that background step aside (`_replaced`), so a pack's
# soldier is every soldier's.
static var _templates: Dictionary = TEMPLATES
static var _replaced := {}

static func set_packs(merged: Dictionary) -> void:
	_templates = TEMPLATES.duplicate(true)
	_replaced = {}
	for k in merged:
		if not String(k).begins_with("_"):   # _note and friends: authoring comments
			_templates[String(k)] = merged[k]
			_replaced[String(k)] = true

static func templates() -> Dictionary:
	return _templates

# Every past a background can hand a hero, the first always templates()[bg].
# [] for a background with no calling at all.
static func variants(bg: String) -> Array:
	if not templates().has(bg):
		return []
	var out: Array = [templates()[bg]]
	if not _replaced.has(bg):
		out.append_array(VARIANTS.get(bg, []))
	return out

# The template a hero's calling entry is: its background's `variant`, or the
# first when the index no longer fits (a pack turned on since, which replaces
# the background's variants). {} for a background with no calling.
static func template_for(c: Dictionary) -> Dictionary:
	var vs := variants(String(c.get("id", "")))
	if vs.is_empty():
		return {}
	var i := int(c.get("variant", 0))
	return vs[i] if i >= 0 and i < vs.size() else vs[0]

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
		if kind == "band" and target.has("factions"):
			var fs = target["factions"]
			if not (fs is Array) or fs.is_empty():
				errors.append("calling \"%s\": factions must be a non-empty list" % bg)
			else:
				for f in fs:
					if not Scaler.FACTIONS.has(String(f)):
						errors.append("calling \"%s\": faction \"%s\" is not a monster band's faction (%s)" % [bg, f, Scaler.FACTIONS])
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
static func assign(party, world) -> Array:
	var out: Array = []
	var from: Vector2 = world.player().position if world.player() != null else Vector2.ZERO
	for id in party.active:
		var c: Dictionary = party.callings.get(id, {})
		if not c.is_empty():
			if String(c["state"]) != "done" and _gone(world, c):
				_retarget(world, c, from)
			continue
		var ch = party.get_member(id)
		var vs := variants(ch.background_id) if ch != null else []
		if vs.is_empty():
			continue
		# Which past: seeded off the hero, so the same merc always has the same
		# one; and when this map has nothing that past could point at, the next
		# in turn that it can, rather than none — a soldier on a map with no
		# bandits or soldiers is told the last stand instead of waiting forever.
		var start := absi(hash("calling|%s" % id)) % vs.size()
		for k in vs.size():
			var vi := (start + k) % vs.size()
			var spec: Dictionary = vs[vi]["target"]
			var target_id := ""
			if spec["kind"] != "audience":
				var target = _nearest(world, spec, from)
				if target == null:
					continue
				target_id = target.id
			party.callings[id] = {"id": ch.background_id, "variant": vi, "target_kind": spec["kind"],
				"target_id": target_id, "state": "", "told_at": -1.0}
			out.append(id)
			break
	return out

# An audience needs no target; anything else is gone when the world no longer
# has it — or, a landmark, when it is spent (it can never fire landmark_answered again).
static func _gone(world, c: Dictionary) -> bool:
	if String(c["target_kind"]) == "audience":
		return false
	var target = _target(world, c)
	return target == null or ("spent" in target and target.spent)

static func _retarget(world, c: Dictionary, from: Vector2) -> void:
	var t: Dictionary = template_for(c)
	var target = _nearest(world, t["target"], from) if not t.is_empty() else null
	c["target_id"] = "" if target == null else String(target.id)
	if target != null and String(c["state"]) == "told":
		_mark(world, target)

# A landmark of the kind, found or hidden (the telling finds it); a lair not yet
# looted; a monster band that is people (the copy is about deserters and debt
# collectors, so bandits before wolves), any monster band when the map has no
# people, never a raiding band (it is marching at a town and will be gone or
# dead before the party gets there) — and when the template names `factions`,
# only a band of one of those, or none at all: "deserters" are bandits or
# soldiers, never a gnoll pack (the design audit, docs/audit-game-design.md
# §6), so the soldier's calling waits for one rather than reading wrong; a civilized settlement of the kind, or of
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
			if spec.has("factions"):
				pool = bands.filter(func(p): return spec["factions"].has(p.faction))
			else:
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
		var t: Dictionary = template_for(c)
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
		var t: Dictionary = template_for(c)
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
	var t: Dictionary = template_for(c)
	if t.is_empty() or String(c["state"]) != "told":
		return {}
	Campaign.split_xp(party, CALLING_XP)
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
	var t: Dictionary = template_for(c)
	if t.is_empty():
		return ""
	match String(c["state"]):
		"told":
			if _waiting(c):
				return "%s — told, waiting for the road" % t["title"]
			return "%s — told, marked on the map" % t["title"]
		"done":
			return "%s — done" % t["title"]
	return ""

# What the tell and the done line call the target. A band is named by
# EnemyNames.band_name — and by the done line it is already off the map, so a
# beaten one is found again in world.fallen (WorldAI.fell keeps its id, faction
# and name there), which names it the same.
static func target_name(party, world, char_id: String) -> String:
	var c: Dictionary = party.callings.get(char_id, {})
	if String(c.get("target_kind", "")) == "band":
		var band = _target(world, c)
		if band == null:
			for f in world.fallen:
				if String(f["id"]) == String(c["target_id"]):
					band = f
		return EnemyNames.band_name(band if band != null else {"id": String(c["target_id"])}, world)
	var target = _target(world, c)
	return "" if target == null else target.sname

# The audience template has no %s to fill. A name that opens the line is
# capitalised: "the Low Fen gnolls" is mid-sentence everywhere else.
static func _fmt(text: String, name: String) -> String:
	if not ("%s" in text):
		return text
	return text % (EnemyNames.upper_first(name) if text.begins_with("%s") else name)

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
		# `variant`: which of the background's pasts, kept only when written —
		# a save from before there was more than one has none, and template_for
		# reads a missing one as 0, the past it was told — so an entry crosses
		# the co-op wire and a save exactly as it went in.
		if e.has("variant"):
			party.callings[String(k)]["variant"] = int(e["variant"])

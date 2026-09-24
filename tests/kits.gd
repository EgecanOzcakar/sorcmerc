# Every kit in the game, built the way a player builds one (not a test: the
# runner globs test_* and drive_*). Shared by the checks that have to see every
# class and subclass rather than the preset trio: tests/test_coop_kits.gd (the
# peers stay in lockstep whatever the party holds) and tests/test_active_effects.gd
# (the action bar has words for every status a kit can raise).
#
#   Kits.hero(class_id, subclass_id, level)   # one hero, every choice made
#   Kits.all(level)                           # one hero per subclass, 48 of them
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Leveling = preload("res://core/leveling.gd")

# The class to `lvl`, this subclass at 3, every other choice the first legal
# option — the creator's own choice model, so a kit here is a kit a player can
# reach.
static func hero(cid: String, sid: String, lvl: int):
	var ch = Creator.new_character()
	ch.id = "k-%s" % sid
	ch.cname = sid.capitalize()
	ch.species_id = "human"
	ch.background_id = String(Catalog.class_src(cid).get("quickBuild", {}).get("suggestedBackground", "soldier"))
	ch.base_abilities = Creator.recommended_array(cid)
	Leveling.grant_levels(ch, lvl, cid)
	for _step in 120:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			break
		var p: Dictionary = sheet.pending[0]
		var opts := Creator.options_for(p, sheet)
		var picks: Array = []
		if p["type"] == "subclass":
			picks = [sid]
		else:
			var i := 0
			while picks.size() < Creator.pick_count(p) and i < opts.size() * 3 and not opts.is_empty():
				picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
				i += 1
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	return ch

static func all(lvl: int) -> Array:
	var out: Array = []
	for sc in Catalog.all("subclasses.json"):
		out.append(hero(String(sc["classId"]), String(sc["id"]), lvl))
	return out

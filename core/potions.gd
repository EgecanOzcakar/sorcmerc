# Potions: data/effects/potions.json gives magic-items.json's potion-* ids a
# mechanic; this reads it and does the drinking. Two doors, one bottle:
#   in combat  — a "drink" verb (an action) combat.gd builds off the party stash,
#                resolved by drink_in_combat();
#   on the road — the profile stash's Drink button, drink_on_road(): heal now,
#                or hang a timed buff on the character that adapter.gd carries
#                into the next fight while the world clock says it still holds.
# Everything a buff does is a statuses entry combat.gd already reads (resist,
# bonus_damage) or one it reads for potions only (bonus_to_hit, bonus_save,
# extra_action, speed_mult, ac, no_attack, str_score).
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Dice = preload("res://core/dice.gd")
const Campaign = preload("res://core/campaign.gd")

const STATUS_PREFIX := "potion:"   # statuses key for a potion buff: "potion:potion-of-speed"

static func mechanics(item_id: String) -> Dictionary:
	var d = Catalog.all("effects/potions.json")
	var m = d.get(item_id) if d is Dictionary else null
	return m if m is Dictionary else {}

static func is_potion(item_id: String) -> bool:
	return not mechanics(item_id).is_empty()

static func ids() -> Array:
	var out: Array = []
	for k in Catalog.all("effects/potions.json").keys():
		if not String(k).begins_with("_"):
			out.append(String(k))
	out.sort()
	return out

static func text(item_id: String) -> String:
	return String(mechanics(item_id).get("text", ""))

# The statuses entry a potion hangs on its drinker; rolls the random parts.
static func buff(item_id: String, rng, sheet = null) -> Dictionary:
	var m := mechanics(item_id)
	var s: Dictionary = m.get("status", {}).duplicate()
	if s.has("resist_random"):
		var types: Array = s["resist_random"]
		s["resist"] = [types[rng.roll_die(types.size()) - 1]]
		s.erase("resist_random")
	if s.has("str_score"):
		# Giant strength sets the score; on this board that is the melee to-hit and
		# damage swing from the drinker's own STR mod to the potion's. Nothing if
		# they are already that strong (the potion says so).
		var mine: int = sheet.mod("str") if sheet != null else 0
		var gain: int = maxi(0, (int(s["str_score"]) - 10) / 2 - mine)
		s.erase("str_score")
		s["bonus_to_hit"] = gain
		s["bonus_damage"] = gain
	return s

# Combat: `cb` applies damage/heal/conditions through its own paths so the log
# and the sfx are the usual ones. `target` only matters for a targeted potion.
static func drink_in_combat(cb, actor, item_id: String, target = null) -> Dictionary:
	var m := mechanics(item_id)
	var name := Campaign.item_name(item_id)
	cb.log.append("%s drinks %s." % [actor.cname, name])
	if m.has("heal"):
		cb.heal(actor, Dice.roll(cb.rng, String(m["heal"])))
	if m.has("damage"):
		var dmg: int = Dice.roll(cb.rng, String(m["damage"]))
		cb.log.append("  %s takes %d %s — it was poison." % [actor.cname, dmg, m.get("damage_type", "")])
		cb._apply_damage(actor, dmg, String(m.get("damage_type", "")))
	var who = actor
	if m.has("target"):
		if target == null:
			return {"error": "needs a target"}
		who = target
		if m.has("save") and cb._saving_throw(who, int(m.get("save_dc", 13)), String(m["save"])):
			cb.log.append("  %s shrugs it off." % who.cname)
			return {"saved": true}
	var until: int = cb._tick() + int(m.get("rounds", 1)) * cb.TICK_STRIDE
	if m.has("condition"):
		var cond := String(m["condition"])
		cb.apply_condition(who, cond, actor if who != actor else null)
		# apply_condition may have refused it (immune) or built it with a source
		# (charmed: who it cannot turn on) — keep that, only add the clock.
		if who.has(cond):
			var s = who.statuses[cond]
			who.statuses[cond] = (s if s is Dictionary else {}).merged({"until_tick": until})
		cb.log.append("  %s is %s." % [who.cname, m["condition"]])
	if m.has("status"):
		var s := buff(item_id, cb.rng, actor.sheet)
		s["until_tick"] = until
		actor.statuses[STATUS_PREFIX + item_id] = s
	return {}

# The road: heal lands on hp_current; a timed potion becomes ch.buffs[id] =
# {"until": world-minute}, and "road" potions set the party flag they promise.
static func drink_on_road(party, ch, item_id: String, now: float, rng) -> void:
	var m := mechanics(item_id)
	if not party.stash_remove(item_id):
		return
	if m.has("heal"):
		var s = ch.sheet()
		var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
		ch.hp_current = mini(s.max_hp, cur + Dice.roll(rng, String(m["heal"])))
	if m.has("damage"):
		var s = ch.sheet()
		var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
		ch.hp_current = maxi(1, cur - Dice.roll(rng, String(m["damage"])))   # a trap, not a death
	if m.has("minutes") and (m.has("status") or m.has("condition") or m.has("road")):
		var b := {"until": now + float(m["minutes"])}
		if m.has("status"):
			b["status"] = buff(item_id, rng, ch.sheet())
		if m.has("condition"):
			b["condition"] = String(m["condition"])
		if m.has("road"):
			b["road"] = String(m["road"])
		ch.buffs[item_id] = b
	elif String(m.get("road", "")) == "scout":
		party.scouted_next = true

# Does `ch` hold a live road buff that does `road` (e.g. "persuasion_adv")?
static func road_buff(ch, road: String, now: float) -> bool:
	for id in ch.buffs:
		var b: Dictionary = ch.buffs[id]
		if String(b.get("road", "")) == road and float(b.get("until", 0.0)) >= now:
			return true
	return false

static func expire(ch, now: float) -> void:
	for id in ch.buffs.keys():
		if float(ch.buffs[id].get("until", 0.0)) < now:
			ch.buffs.erase(id)

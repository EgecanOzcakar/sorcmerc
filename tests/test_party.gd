# T4 party model — roster, active cap, gold/stash, and the Adapter seam.
#   godot --headless --path . -s tests/test_party.gd
extends SceneTree

const Party = preload("res://core/party.gd")
const Adapter = preload("res://core/adapter.gd")
const Leveling = preload("res://core/leveling.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var p := Party.new()

	# --- roster + auto-activation up to the cap --------------------------
	# Presets' Vera/Pike/Ilsa plus two characters built through the resolve
	# pipeline by hand — no creator UI, no disk.
	var five := Party.demo_roster()
	check(five.size() == 5, "5 fixture characters")
	for ch in five:
		check(p.add_member(ch), "add_member %s" % ch.id)
	check(p.roster.size() == 5, "roster holds 5")
	check(p.active.size() == Party.MAX_ACTIVE, "active auto-fills to the cap of 4")
	check(not p.add_member(five[0]), "duplicate id rejected")
	check(p.bench_list().size() == 1, "the 5th sits on the bench")

	# --- cap enforcement -------------------------------------------------
	var benched: String = p.bench_list()[0].id
	check(not p.activate(benched), "activate refused when the party is full")
	check(not p.activate("nobody"), "activate refused for a stranger")
	check(p.bench("vera"), "bench an active member")
	check(not p.is_active("vera"), "benched member is inactive")
	check(p.activate(benched), "activate fills the freed slot")
	check(p.active.size() == 4, "still capped at 4")
	check(not p.bench("vera"), "bench refused for an already-benched member")

	# --- swap ------------------------------------------------------------
	check(p.swap(benched, "vera"), "swap benched <-> active")
	check(p.is_active("vera") and not p.is_active(benched), "swap took effect")
	check(p.active.size() == 4, "swap preserves party size")
	check(not p.swap("vera", "pike"), "swap refused when both are active")

	# --- removal ---------------------------------------------------------
	check(p.remove_member("vera"), "remove an active member")
	check(p.roster.size() == 4 and p.active.size() == 3, "removal drops from roster and party")
	check(not p.remove_member("vera"), "removing twice fails")
	check(p.activate("vera") == false, "cannot activate a removed character")
	check(p.add_member(five[0]), "re-add the removed character")
	check(p.is_active("vera"), "re-added into the free slot")

	# --- gold ------------------------------------------------------------
	check(p.gold == 0, "party starts broke")
	p.add_gold(120)
	check(p.gold == 120, "gold added")
	check(p.spend_gold(50) and p.gold == 70, "gold spent")
	check(not p.spend_gold(1000) and p.gold == 70, "cannot overspend")
	check(not p.spend_gold(-5), "negative spend rejected")
	p.add_gold(-1000)
	check(p.gold == 0, "gold floors at 0")

	# --- stash -----------------------------------------------------------
	p.stash_add("potions-of-healing", 3)
	p.stash_add("potions-of-healing", 2)
	p.stash_add("longsword")
	check(p.stash_count("potions-of-healing") == 5, "stash stacks by item id")
	check(p.stash.size() == 2, "two distinct stash entries")
	check(p.stash_remove("potions-of-healing", 5), "remove the whole stack")
	check(p.stash_count("potions-of-healing") == 0, "stack gone")
	check(p.stash.size() == 1, "emptied entry dropped")
	check(not p.stash_remove("longsword", 2), "cannot remove more than held")
	p.stash_add("rope", 0)
	check(p.stash_count("rope") == 0, "zero-quantity add is a no-op")

	# --- summary ---------------------------------------------------------
	var sm := p.summary("pike")
	check(sm["name"] == "Pike Sallow" and sm["class_id"] == "rogue", "summary identity")
	check(sm["level"] == 3 and sm["ac"] > 0 and sm["max_hp"] > 0, "summary uses the resolved sheet")
	check(sm["hp"] == sm["max_hp"], "undamaged character reads full HP")
	check(p.summary("nobody").is_empty(), "summary of a stranger is empty")

	# --- THE SEAM: active party -> Adapter -> Combatant -------------------
	var chars := p.party_characters()
	check(chars.size() == p.active.size(), "party_characters matches the active list")
	for i in chars.size():
		check(chars[i].id == p.active[i], "party_characters keeps marching order")
	for ch in chars:
		var c = Adapter.to_combatant(ch, "party", Vector2i(0, 0))
		check(c != null and c.id == ch.id, "Adapter accepts %s" % ch.id)
		check(c.max_hp > 0 and c.hp == c.max_hp, "%s has valid HP" % ch.id)
		check(c.ac >= 10 and c.speed >= 1, "%s has valid AC/speed" % ch.id)
		check(c.team == "party", "%s is on the party team" % ch.id)
		check(not c.attacks.is_empty(), "%s has at least one attack" % ch.id)

	var pos := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var cbs := p.to_combatants(pos)
	check(cbs.size() == chars.size(), "to_combatants covers the active party")
	check(cbs[1].pos == Vector2i(1, 0), "to_combatants applies positions in order")
	check(p.to_combatants([]).size() == chars.size(), "missing positions default, not crash")

	test_death()
	test_revive_downed()
	test_identification()
	test_overworld_figure()
	test_active_max_level()
	print("test_party: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# T10: the dead stay benched until a Revivify or a scroll (300 gp either way),
# and come back for free when the run concludes.
func test_death() -> void:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	var ilsa = p.get_member("ilsa")
	var vera = p.get_member("vera")
	ilsa.prepared.append(Party.REVIVE_SPELL)
	for _i in 2:                      # level 5: the first level with 3rd-level slots
		ilsa.add_level("cleric")

	vera.dead = true
	p.bench("vera")
	check(not p.activate("vera"), "a dead member cannot be activated")
	check(not p.is_active("vera"), "the refusal changed nothing")
	check(not p.swap("ilsa", "vera"), "a dead member cannot be swapped in either")

	check(not Party.can_resurrect(p), "no gold, no resurrection")
	p.add_gold(1000)
	check(Party.resurrection_caster(p) == "ilsa", "Ilsa knows Revivify and has a 3rd+ slot")
	check(not Party.has_resurrection_scroll(p), "no scroll in the stash")
	check(Party.can_resurrect(p), "a caster plus 300 gp is enough")
	check(not Party.resurrect(p, "ilsa", "spell"), "cannot resurrect the living")
	check(not Party.resurrect(p, "vera", "prayer"), "unknown methods are refused")
	check(not Party.resurrect(p, "vera", "scroll"), "cannot read a scroll you do not have")
	check(p.gold == 1000 and vera.dead, "every refusal left the state alone")

	check(Party.resurrect(p, "vera", "spell", "ilsa"), "Revivify raises the dead")
	check(not vera.dead and vera.hp_current == 1, "back at 1 HP")
	check(p.gold == 1000 - Party.REVIVE_COST, "300 gp paid")
	check(not p.is_active("vera"), "the raised stay benched until reactivated")
	check(p.activate("vera"), "and can now be reactivated")
	var spent := 0
	for i in range(Party.REVIVE_SLOT - 1, ilsa.slots_used.size()):
		spent += int(ilsa.slots_used[i])
	check(spent == 1, "one slot of level 3+ was spent")

	# the scroll path
	vera.dead = true
	p.bench("vera")
	p.stash_add(Party.REVIVE_SCROLL)
	check(Party.has_resurrection_scroll(p), "scroll in the stash")
	check(Party.resurrect(p, "vera", "scroll"), "the scroll raises the dead")
	check(not vera.dead and p.stash_count(Party.REVIVE_SCROLL) == 0, "the scroll is consumed")
	check(p.gold == 1000 - 2 * Party.REVIVE_COST, "the scroll costs 300 gp too")

	# end of run: everyone comes back free
	vera.dead = true
	ilsa.dead = true
	ilsa.hp_current = 0
	var gold: int = p.gold
	Party.auto_revive_all(p)
	check(not vera.dead and not ilsa.dead, "the run's end revives everyone")
	check(ilsa.hp_current == 1, "revived at 1 HP, not full")
	check(p.gold == gold, "the free revival costs nothing")

# The open world's lost fight (the design audit §1.2): the downed come to at
# 1 HP, the dead stay dead — this fight's and every earlier fight's, benched or
# not. Nobody left standing puts the living bench on the road; a roster with
# nobody alive keeps exactly one, so the map is never a save with nobody in it.
func test_revive_downed() -> void:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	var vera = p.get_member("vera")
	var pike = p.get_member("pike")
	var ilsa = p.get_member("ilsa")
	# vera fell in an earlier fight and is on the bench; pike fell in this one
	# (the caller applies the fight's deaths first: dead and benched); ilsa is
	# down but alive at 0.
	vera.dead = true
	vera.hp_current = 0
	p.bench("vera")
	pike.dead = true
	pike.hp_current = 0
	p.bench("pike")
	ilsa.hp_current = 0
	var gold := p.gold
	var r: Dictionary = Party.revive_downed(p)
	check(vera.dead and pike.dead, "the dead stay dead, the earlier fallen and this fight's alike")
	check(not p.is_active("vera") and not p.is_active("pike"), "...and stay benched")
	check(not ilsa.dead and ilsa.hp_current == 1, "the downed come to at 1 HP (%d)" % ilsa.hp_current)
	check(r["came_to"] == ["ilsa"], "came_to names only the downed (%s)" % [r["came_to"]])
	check(r["dead"].size() == 2 and "vera" in r["dead"] and "pike" in r["dead"], "dead names both fallen")
	check(r["spared"] == "", "nobody is spared while somebody lives")
	check(p.gold == gold, "coming to costs nothing here; the retreat's tax is the screen's")
	var others = p.roster.filter(func(c): return not c.id in ["vera", "pike", "ilsa"])
	check(not others.is_empty() and others.all(func(c): return c.hp_current == -1), "a hero at full (-1) is not touched")
	var line := p.defeat_line(r, ["pike"], "Ashford", 12)
	check(line.contains("Ashford") and line.contains("12 ◉") and line.contains("Pike") and line.contains("healer"),
		"the line names the place, the tax, this fight's dead and the way back: %s" % line)
	check(not line.contains("Vera"), "...not an earlier fight's dead")
	print("  defeat line: ", line)

	# The pit's lost bout: its fallen were carried out, not buried; an earlier
	# fight's dead are not the pit's to give back.
	var brawler = p.get_member(p.active[0])
	brawler.dead = true
	brawler.hp_current = 0
	Party.revive_downed(p, [brawler.id])
	check(not brawler.dead and brawler.hp_current == 1, "carried out of the pit: comes to at 1 HP")
	check(vera.dead and pike.dead, "...and the dead of earlier fights stay dead")

	# Every marcher dead, one hero alive on the bench: the bench marches.
	var q := Party.new()
	for ch in Party.demo_roster():
		q.add_member(ch)
	var reserve: String = q.bench_list()[0].id
	for id in q.active.duplicate():
		q.get_member(id).dead = true
		q.bench(id)
	Party.revive_downed(q)
	check(Array(q.active) == [reserve], "nobody standing: the living bench marches (%s)" % [q.active])

	# The whole roster dead: the company is finished, and the open world has no
	# end screen, so the highest level of them comes to alone.
	var w := Party.new()
	for ch in Party.demo_roster():
		w.add_member(ch)
	for id in w.active.duplicate():
		w.bench(id)
	var best = w.roster[0]
	for ch in w.roster:
		ch.dead = true
		ch.hp_current = 0
		if ch.level() > best.level():
			best = ch
	var rw: Dictionary = Party.revive_downed(w)
	check(rw["spared"] == best.id and not best.dead and best.hp_current == 1, "one is spared: the highest level (%s)" % rw["spared"])
	check(w.roster.filter(func(c): return c.dead).size() == w.roster.size() - 1, "everyone else stays dead")
	check(Array(w.active) == [best.id], "and marches alone")
	var wl := w.defeat_line(rw, [], "Ashford", 0)
	check(wl.contains(best.cname) and wl.contains("alone"), "the line says who is left: %s" % wl)
	print("  wiped line: ", wl)

# T13: identified/unidentified units of one item stack apart, identified spend first,
# and a Scroll of Identification burns itself to reveal one item.
func test_identification() -> void:
	var p := Party.new()
	p.stash_add("longsword")
	check(Party.is_identified(p.stash[0]), "a plain stash_add is identified")
	check(p.stash[0].has("identified"), "every entry carries the flag")

	p.stash_add("cloak-of-elvenkind", 1, false)
	p.stash_add("cloak-of-elvenkind", 1, false)
	check(p.stash_count("cloak-of-elvenkind") == 2, "unidentified units stack together")
	check(p.stash_count("cloak-of-elvenkind", true) == 0, "none of them count as identified")
	check(p.unidentified().size() == 1, "one mystery entry")

	check(p.stash_identify("cloak-of-elvenkind"), "identify one unit")
	check(p.stash_count("cloak-of-elvenkind") == 2, "the total is unchanged")
	check(p.stash_count("cloak-of-elvenkind", true) == 1, "exactly one is now known")
	check(p.stash.size() == 3, "the known unit split into its own entry")
	check(not p.stash_identify("longsword"), "nothing to identify on a mundane item")

	# removal spends what you know first
	check(p.stash_remove("cloak-of-elvenkind"), "remove one cloak")
	check(p.stash_count("cloak-of-elvenkind", true) == 0, "the identified one went first")
	check(p.stash_count("cloak-of-elvenkind") == 1, "the mystery is still there")

	# the scroll: always works, always consumed, and must itself be identified
	p.stash_add(Party.IDENTIFY_SCROLL, 1, false)
	check(not p.use_identification_scroll("cloak-of-elvenkind"), "an unread scroll cannot be read")
	p.stash_add(Party.IDENTIFY_SCROLL, 1, true)
	check(p.use_identification_scroll("cloak-of-elvenkind"), "the scroll identifies with no roll")
	check(p.stash_count("cloak-of-elvenkind", true) == 1, "the cloak is known")
	check(p.stash_count(Party.IDENTIFY_SCROLL, true) == 0, "the scroll is consumed")
	check(p.stash_count(Party.IDENTIFY_SCROLL) == 1, "the unidentified one is untouched")
	check(not p.use_identification_scroll("cloak-of-elvenkind"), "nothing left to identify")

# T9x: overworld_figure names ONE character (scenes/world/party3d.gd renders
# their class figure on the map), and only counts while they are marching.
# The pre-identity shape — a class id, from a save written before the switch —
# resolves the old way and migrates on the first read; see overworld_pick().
# With no pick (or a stale one) the map shows the highest-level marcher.
func test_overworld_figure() -> void:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	check(p.overworld_figure == "", "a fresh party has picked nobody")
	check(p.overworld_pick() == null, "which is no explicit pick")
	var senior = p.overworld_member()
	var top := 0
	for id in p.active:
		top = maxi(top, p.get_member(id).level())
	check(senior != null and senior.level() == top and p.is_active(senior.id),
		"so the map shows the highest-level marcher, not the pawn")
	check(p.overworld_member().id == p.active[0] or p.get_member(p.active[0]).level() < top,
		"marching order breaks ties")
	check(Party.new().overworld_member() == null, "an empty party is the pawn")

	p.overworld_figure = "vera"
	var pick = p.overworld_member()
	check(pick != null and pick.id == "vera", "a member id resolves to that exact member")

	# Identity, not class: Thrun and the benched Gera are both barbarians.
	check(p.swap("ilsa", "gera"), "swap Gera in for Ilsa")   # active: vera, pike, gera, thrun
	p.overworld_figure = "thrun"
	var thrun = p.overworld_member()
	check(thrun != null and thrun.id == "thrun", "one of two barbarians is still his own pick")
	check(p.bench("thrun"), "bench him")
	check(p.overworld_pick() == null,
		"benching the pick drops it, even with another barbarian still marching")
	check(p.overworld_member() != null and p.overworld_member().id != "thrun",
		"and the map falls back to the default marcher")
	check(p.overworld_figure == "thrun", "the pick is remembered, not cleared, while he sits out")
	check(p.activate("thrun"), "bring him back")
	var back = p.overworld_member()
	check(back != null and back.id == "thrun", "and the pick comes back with him")
	check(p.remove_member("thrun"), "let him go for good")
	check(p.overworld_pick() == null, "a stranger's id is no pick")

	# The pre-identity shape: a class id, resolved against the active party.
	p.overworld_figure = "rogue"
	var legacy = p.overworld_member()
	check(legacy != null and legacy.id == "pike", "an old save's class id still resolves to a member")
	check(p.overworld_figure == "pike", "and is migrated to that member's id on the first read")
	p.overworld_figure = "wizard"
	check(p.overworld_pick() == null, "a class nobody active has is no pick")
	check(p.overworld_figure == "wizard", "and with nothing to migrate it to, it is left alone")
	p.overworld_figure = "not-an-id-and-not-a-class"
	check(p.overworld_pick() == null, "so is pure nonsense — no crash")

# The level a hero created now would join at (scenes/creator/creator.gd's
# start_level): the highest among the <= 4 who fight, and 1 while nobody does.
func test_active_max_level() -> void:
	var p := Party.new()
	check(p.active_max_level() == 1, "an empty party still starts a hero at level 1")
	var roster := Party.demo_roster()
	for ch in roster:
		p.add_member(ch)
	var best := 1
	var benched: String = p.bench_list()[0].id
	for id in p.active:
		best = maxi(best, p.get_member(id).level())
	check(p.active_max_level() == best, "reads the highest active member (%d)" % best)
	Leveling.grant_levels(p.get_member(p.active[0]), best + 2)
	check(p.active_max_level() == best + 2, "follows an active member levelling up")
	Leveling.grant_levels(p.get_member(benched), Leveling.MAX_LEVEL)
	check(p.active_max_level() == best + 2, "a benched veteran does not set it")
	p.swap(p.active[0], benched)
	check(p.active_max_level() == Leveling.MAX_LEVEL, "until they are put in the party")

# T4 party model — roster, active cap, gold/stash, and the Adapter seam.
#   godot --headless --path . -s tests/test_party.gd
extends SceneTree

const Party = preload("res://core/party.gd")
const Adapter = preload("res://core/adapter.gd")

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
	p.stash_add("potion-of-healing", 3)
	p.stash_add("potion-of-healing", 2)
	p.stash_add("longsword")
	check(p.stash_count("potion-of-healing") == 5, "stash stacks by item id")
	check(p.stash.size() == 2, "two distinct stash entries")
	check(p.stash_remove("potion-of-healing", 5), "remove the whole stack")
	check(p.stash_count("potion-of-healing") == 0, "stack gone")
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

	print("test_party: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

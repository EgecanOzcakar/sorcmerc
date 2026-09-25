# MEASUREMENT (2026-09-25) — what Metamagic is worth to a party once the
# autopilot arms it (core/ai.gd's _quicken and _twin; the design audit §7.4).
# Not a test, and not part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_metamagic.gd
#   SEEDS=100 LEVELS=5 DIFF=hard godot ... -s tests/sweep_metamagic.gd
#
# tests/sweep_sorcerer.gd measured Innate Sorcery and Font of Magic at about
# zero; Metamagic was left out because nothing armed it. This is the party it
# should show most in: the preset fighter beside TWO sorcerers at the same
# level (a draconic and an aberrant), each having picked Quickened and Twinned
# at level 2 (Seeking and Careful at 10), with a damage list prepared
# (Chromatic Orb, Magic Missile, Burning Hands, Scorching Ray, Fireball,
# Lightning Bolt...), ability increases into CHA, every other choice the first
# legal option. Each seed is fought twice:
#   off  the sorcerers picked Careful, Subtle (and at 10 Seeking and Distant):
#        options the autopilot never arms — what every sweep before this saw
#   on   they picked Quickened and Twinned, and the autopilot arms them
# Each column's roster is bought for its own party. Before core/rules/power.gd
# priced Quickened (quickened_turns) the two rosters were the same, so the gap
# was the options' whole unpriced worth; with the price in, "on" is sent the
# bigger fight and the gap is what is left over. UNPRICED=1 fights both
# columns on the rosters bought for the "off" party, which is the gap as it
# was. `score` is the column's party on power.gd's ruler; `quick` is
# Quickened casts a fight. Fight seed pinned.
#
# MEASURED 2026-09-25, 200 seeds a cell, off / on unpriced / on priced:
#   easy    level 3  85.0 / 85.5 / 83.5    level 5  93.0 / 98.0 / 95.0
#           level 10 79.5 / 88.0 / 83.0 (fights 9.5 -> 6.6 rounds)
#   normal  level 3  64.5 / 69.0 / 69.5    level 5  88.0 / 91.0 / 88.5
# The price is core/rules/power.gd's quickened_turns.
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const Prepare = preload("res://scenes/party/prepare.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

const OPTIONS := ["quickened-spell", "twinned-spell", "seeking-spell", "careful-spell"]
# The "off" sorcerers' picks: options the autopilot never arms and power.gd
# never prices (Distant is not on the board at all), so they fight as a
# sorcerer with no Metamagic would.
const OFF_OPTIONS := ["careful-spell", "subtle-spell", "seeking-spell", "distant-spell"]
const DAMAGE := ["fire-bolt", "ray-of-frost", "chromatic-orb", "magic-missile", "burning-hands",
	"scorching-ray", "fireball", "lightning-bolt", "ice-storm", "cone-of-cold", "shatter", "thunderwave"]

func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	var diff := OS.get_environment("DIFF") if OS.get_environment("DIFF") != "" else "normal"
	var levels: Array = [3, 5, 10]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("preset fighter + two built sorcerers (Quickened, Twinned), %s, %d seeds a cell, fight seed pinned" % [diff, seeds])
	print("  level    off: score  win%  rounds      on: score  win%  rounds  quick")
	for L in levels:
		var c = Adapter.to_combatant(_sorcerer(L, "draconicsorcery", "ember", OPTIONS), "party", Vector2i.ZERO)
		print("  level %d kit: %s, slots %s, %s" % [L, c.spell_ids, c.slots.slice(0, 5),
			c.verbs.filter(func(v): return String(v["kind"]) == "metamagic").map(func(v): return v["option"])])
	for L in levels:
		var a := _sweep(L, seeds, diff, false)
		var b := _sweep(L, seeds, diff, true)
		print("  %5d        %5.1f %5.1f%%   %5.1f         %5.1f %5.1f%%   %5.1f   %4.2f" % [
			L, a["score"], a["rate"], a["rounds"], b["score"], b["rate"], b["rounds"], b["quick"]])
	quit(0)

func _sorcerer(L: int, sub: String, id: String, options: Array) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 15}
	for i in L:
		ch.add_level("sorcerer", -1)
	var mm := 0
	for _step in 80:
		var pend: Array = ch.sheet().pending
		if pend.is_empty():
			break
		var p: Dictionary = pend[0]
		var picks: Array = []
		var ids: Array = Creator.options_for(p, ch.sheet()).map(func(o): return String(o["id"]))
		if p["type"] == "asi":
			for i in Creator.pick_count(p):
				picks.append("cha" if "cha" in ids else ids[i % ids.size()])
		elif p["type"] == "subclass":
			picks = [sub]
		elif String(p["key"]).begins_with("feature-choice:class:sorcerer:"):
			picks = [options[mm % options.size()]]
			mm += 1
		else:
			var opts := Creator.options_for(p, ch.sheet())
			# damage spells first, in DAMAGE's order, then the rest as offered
			opts.sort_custom(func(a, b):
				var ia := DAMAGE.find(String(a["id"]))
				var ib := DAMAGE.find(String(b["id"]))
				return (ia if ia >= 0 else 99) < (ib if ib >= 0 else 99))
			var i := 0
			while picks.size() < Creator.pick_count(p) and i < opts.size() * 3 and not opts.is_empty():
				picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
				i += 1
		ch.decide(p["key"], Creator.decision_for(p, picks))
		ch.dirty()
	# The class's spell picks stop at level 1 here (a known caster's later picks
	# are not choices in the export), so the damage list a sorcerer of this level
	# could know is handed over the way tests/test_sorcerer.gd hands its list:
	# every DAMAGE spell the sorcerer list has at a level there is a slot for.
	for lvl in Prepare.top_slot(ch):
		for sid in Effects.pick_pool("sorcerer", lvl + 1):
			if sid in DAMAGE and not sid in ch.prepared:
				ch.prepared.append(sid)
	ch.dirty()
	return ch

func _sweep(L: int, seeds: int, diff: String, on: bool) -> Dictionary:
	var wins := 0
	var rounds := 0
	var quick := 0
	var picks: Array = OPTIONS if on else OFF_OPTIONS
	var chars: Array = [Presets.party_at(L)[0], _sorcerer(L, "draconicsorcery", "ember", picks),
		_sorcerer(L, "aberrantsorcery", "whisper", picks)]
	# UNPRICED=1: both columns fight the rosters bought for the "off" party, so
	# the gap is Metamagic's whole worth whatever power.gd says of it.
	var buyer: Array = chars
	if OS.get_environment("UNPRICED") == "1":
		buyer = [Presets.party_at(L)[0], _sorcerer(L, "draconicsorcery", "ember", OFF_OPTIONS),
			_sorcerer(L, "aberrantsorcery", "whisper", OFF_OPTIONS)]
	for s in range(1, seeds + 1):
		var spec: Dictionary = Scaler.roster_for(buyer, diff, {}, "", s, 1.0)
		spec["seed"] = s
		var party: Array = []
		for i in chars.size():
			party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(spec, party)
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		rounds += cb.round_num
		for line in cb.log:
			if String(line).contains("(Quickened"):
				quick += 1
		if cb.outcome() == "Victory":
			wins += 1
	return {"rate": 100.0 * wins / seeds, "rounds": float(rounds) / seeds, "quick": float(quick) / seeds,
		"score": Scaler.party_score(chars)}

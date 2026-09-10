# Audit + regression coverage for short/long rest regen (see docs/expansion-plan.md
# status log): Warlock Pact Magic slots weren't wired into combat at all, and every
# feature-synthesized pool (Second Wind, Bardic Inspiration, ...) defaulted to
# short-rest regardless of what the real rule says.
#   godot --headless --path . -s tests/test_rest_mechanics.gd
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Adapter = preload("res://core/adapter.gd")
const Presets = preload("res://core/presets.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func autopick(p: Dictionary, sheet) -> Array:
	var opts := Creator.options_for(p, sheet)
	if opts.is_empty():
		return []
	var picks: Array = []
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3:
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

func resolve_all(ch) -> void:
	for _step in 40:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			return
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet)
		if picks.is_empty():
			return
		ch.decide(p["key"], Creator.decision_for(p, picks))

func build(species: String, cls: String, background: String, n: int):
	var ch = Creator.new_character()
	ch.species_id = species
	ch.background_id = background
	for i in n:
		ch.add_level(cls, -1)
	resolve_all(ch)
	return ch

func _init() -> void:
	test_pact_magic_wired()
	test_pact_magic_regens_on_short_rest()
	test_normal_slots_dont_regen_on_short_rest()
	test_long_rest_only_pool_waits_for_long_rest()
	test_short_rest_pool_unaffected()

	print("test_rest_mechanics: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_pact_magic_wired() -> void:
	var ch = build("human", "warlock", "hermit", 3)
	var sheet = ch.sheet()
	check(not sheet.spellcasting.get("pact", {}).is_empty(), "warlock 3 resolves a pact-magic block")
	var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	var pact: Dictionary = sheet.spellcasting["pact"]
	var lvl: int = int(pact["slotLevel"])
	check(c.slots[lvl - 1] == int(pact["count"]), "pact slots land in Combatant.slots at the pact's level")
	var has_spell_verb: bool = c.verbs.any(func(v): return v.get("kind", "") == "spell" and int(v.get("slot_level", 0)) == lvl)
	check(has_spell_verb, "a castable spell verb exists at the pact slot level")

func test_pact_magic_regens_on_short_rest() -> void:
	var ch = build("human", "warlock", "hermit", 3)
	var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	var lvl := int(ch.sheet().spellcasting["pact"]["slotLevel"])
	c.slots[lvl - 1] = 0   # spend every pact slot in the fight
	Adapter.write_back(c, ch)
	check(ch.slots_used[lvl - 1] > 0, "spending in combat records slots_used")
	Adapter.rest(ch, "short-rest")
	var c2 = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	check(c2.slots[lvl - 1] == int(ch.sheet().spellcasting["pact"]["count"]),
		"Pact Magic: a short rest refills every pact slot (the RAW exception)")

func test_normal_slots_dont_regen_on_short_rest() -> void:
	var ch = build("human", "wizard", "sage", 3)
	var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	var slot_idx: int = c.slots.find(c.slots.filter(func(n): return n > 0)[0]) if c.slots.any(func(n): return n > 0) else -1
	check(slot_idx >= 0, "wizard 3 has at least one spell slot")
	c.slots[slot_idx] -= 1
	Adapter.write_back(c, ch)
	Adapter.rest(ch, "short-rest")
	var c2 = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	check(c2.slots[slot_idx] < ch.sheet().spellcasting["slots"][slot_idx],
		"an ordinary caster's spent slot stays spent through a short rest")
	Adapter.rest(ch, "long-rest")
	var c3 = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	check(c3.slots[slot_idx] == ch.sheet().spellcasting["slots"][slot_idx],
		"...and comes back on a long rest")

func test_long_rest_only_pool_waits_for_long_rest() -> void:
	# Neither wizard-arcane-recovery nor bard-bardic-inspiration has a mechanical
	# effect in data/effects/features.json yet (SCHEMA gap #4 — they're flavour-only
	# today, humanize()'d with no verb), so there's no real character to drive this
	# through end-to-end. Prove the gating logic itself directly against the
	# override list instead; it's exercised for real the day either feature gets
	# an effects entry with "uses".
	var Combatant = load("res://core/combatant.gd")
	var c = Combatant.new()
	c.verbs = [{"id": "arcane-recovery", "pool": "wizard-arcane-recovery", "uses": 1}]
	Adapter._finish_verbs(c, {})
	check(c.pools.has("wizard-arcane-recovery"), "a synthetic pool is created from the verb")
	check(c.pools["wizard-arcane-recovery"]["regen"] == "long-rest",
		"...and tagged long-rest for a listed override, not the short-rest default")

	var c2 = Combatant.new()
	c2.verbs = [{"id": "second-wind", "pool": "fighter-second-wind", "uses": 1}]
	Adapter._finish_verbs(c2, {})
	check(c2.pools["fighter-second-wind"]["regen"] == "short-rest",
		"...while an unlisted synthetic feature still defaults to short-rest")

func test_short_rest_pool_unaffected() -> void:
	# Regression: Second Wind must keep working exactly as before this fix.
	var vera = Presets.vera()
	var c = Adapter.to_combatant(vera, "party", Vector2i.ZERO)
	var pool_id := "fighter-second-wind"
	check(c.pools.has(pool_id) and c.pools[pool_id]["regen"] == "short-rest",
		"Second Wind is still a short-rest synthetic pool")
	c.pools[pool_id]["cur"] = 0
	Adapter.write_back(c, vera)
	Adapter.rest(vera, "short-rest")
	check(int(vera.pools.get(pool_id, 0)) > 0, "...and a short rest still refills it")

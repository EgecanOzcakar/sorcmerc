# The daily-prep screen (scenes/party/prepare.gd), driven through its own model
# and then through the rendered page.
#
# The gap it closes is the one T-classes wrote down and left: the resolver has
# computed `prepared_count` since F2 and no screen ever spent it, so a cleric or
# druid carried their cantrips, their subclass's always-prepared list, and
# nothing else. The claim that matters here is the last one — that a spell
# chosen on this page becomes a button in a fight — because everything else is
# bookkeeping in service of it.
#   godot --headless --path . -s tests/test_prepare_spells.gd
extends SceneTree

const Prepare = preload("res://scenes/party/prepare.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Leveling = preload("res://core/leveling.gd")
const Adapter = preload("res://core/adapter.gd")
const Save = preload("res://core/character_save.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")   # #122: the spell badges on each row

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_who_prepares()
	test_the_pool()
	test_the_limit()
	test_it_reaches_the_action_bar()
	test_it_survives_a_save()
	test_the_page_renders()
	await test_the_party_screen_offers_it()
	print("test_prepare_spells: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The creator's own choice model, the way tests/test_class_abilities.gd drives it.
func autopick(p: Dictionary, sheet, prefer := "") -> Array:
	var opts := Creator.options_for(p, sheet)
	if opts.is_empty():
		return []
	for o in opts:
		if o["id"] == prefer:
			return [prefer]
	var picks: Array = []
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3:
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

func build(cid: String, sid: String, lvl: int):
	var ch = Creator.new_character()
	ch.id = "prep-%s-%s-%d" % [cid, sid, lvl]
	ch.cname = "%s/%s" % [cid, sid]
	ch.species_id = "human"
	ch.background_id = String(Catalog.class_src(cid).get("quickBuild", {}).get("suggestedBackground", "soldier"))
	ch.base_abilities = Creator.recommended_array(cid)
	Leveling.grant_levels(ch, lvl, cid)
	for _step in 120:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			break
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet, sid if p["type"] == "subclass" else "")
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	return ch

# --- who ------------------------------------------------------------------
#
# Five of the twelve prepare. The other seven are asserted too, because the
# button is on every roster row and the wrong answer there is an offer that
# leads to an empty page.
func test_who_prepares() -> void:
	var want := {
		"cleric/lifedomain": true, "druid/circlemoon": true, "wizard/evoker": true,
		"paladin/oathofdevotion": true, "ranger/hunter": true,
		"bard/collegelore": false, "sorcerer/wildmagicsorcery": false,
		"warlock/archfeypatron": false, "fighter/champion": false,
		"rogue/arcanetrickster": false, "barbarian/berserker": false,
		"monk/warrioropenhand": false,
	}
	for key in want:
		var parts: PackedStringArray = String(key).split("/")
		var ch = build(parts[0], parts[1], 8)
		check(Prepare.prepares(ch) == bool(want[key]),
			"%s %s prepare spells" % [key, "does" if want[key] else "does not"])

# --- what -----------------------------------------------------------------

func test_the_pool() -> void:
	var druid = build("druid", "circlemoon", 8)
	var pool := Prepare.pool(druid)
	check(pool.size() > 10, "a level-8 druid has a real list to choose from (%d)" % pool.size())

	# Nothing already castable is offered: paying a pick for a spell the
	# character has either way is a pick thrown away.
	var free := Prepare.free_list(druid)
	check(not free.is_empty(), "the druid's cantrips are listed as already theirs")
	for sid in pool:
		check(not sid in free, "%s is offered once, not twice" % sid)

	# Nothing above the character's top slot: a 5th-level pick a level-8 druid
	# can never cast is a pick that does nothing.
	check(Prepare.top_slot(druid) == 4, "a level-8 druid tops out at 4th-level slots")
	for sid in pool:
		check(int(Catalog.spell(sid).get("level", 9)) <= Prepare.top_slot(druid),
			"%s is castable with a slot this character has" % sid)

	# A wizard prepares from their spellbook and nowhere else, and the book is
	# already castable — so there is nothing to decide, rather than the whole
	# wizard list to decide from.
	var wiz = build("wizard", "evoker", 8)
	check(Prepare.pool(wiz).is_empty(), "a wizard is offered no picks beyond their book")
	check(Prepare.free_list(wiz).size() >= 6, "...and the book itself is shown (%d)"
		% Prepare.free_list(wiz).size())

func test_the_limit() -> void:
	var cleric = build("cleric", "lifedomain", 8)
	var cap := Prepare.limit(cleric)
	check(cap > 0, "a level-8 cleric can prepare something (%d)" % cap)
	var taken := 0
	for sid in Prepare.pool(cleric):
		if Prepare.toggle(cleric, sid):
			taken += 1
	check(taken <= cap, "the limit holds: %d taken against a cap of %d" % [taken, cap])
	check(Prepare.chosen(cleric).size() == taken, "...and the count agrees")

	# A full list still lets a pick come back off it.
	if taken > 0:
		var first: String = Prepare.chosen(cleric)[0]
		check(Prepare.toggle(cleric, first), "a prepared spell can be unprepared when full")
		check(not first in cleric.prepared, "...and it is gone")

	# And nothing outside the pool can be smuggled in.
	check(not Prepare.toggle(cleric, "fireball"), "a spell off the cleric's list is refused")

	Prepare.clear(cleric)
	check(Prepare.chosen(cleric).is_empty(), "Clear empties what this page chose")

# --- and the point of all of it -------------------------------------------
#
# T-classes measured this exact build as the symptom: 4/3/3/2 spell slots and
# nothing but cantrips to spend them on.
func test_it_reaches_the_action_bar() -> void:
	var druid = build("druid", "circlemoon", 8)
	var before = Adapter.to_combatant(druid, "party", Vector2i.ZERO)
	check(_leveled(before) == 0, "the Moon druid starts with no leveled spell on the bar")
	check(int(druid.sheet().spellcasting["slots"][0]) > 0, "...while holding slots to spend")

	for sid in Prepare.pool(druid).slice(0, 4):
		Prepare.toggle(druid, sid)
	var after = Adapter.to_combatant(druid, "party", Vector2i.ZERO)
	check(_leveled(after) > 0, "preparing puts leveled spells on the bar (%d)" % _leveled(after))
	# Every prepared spell is castable, at least at its own level.
	for sid in Prepare.chosen(druid):
		check(sid in after.spell_ids, "%s is castable once prepared" % sid)

func _leveled(c) -> int:
	return c.verbs.filter(func(v): return v["kind"] == "spell" and int(v.get("slot_level", 0)) > 0).size()

# A preparation that does not survive the walk to the next fight is no
# preparation at all. core/character_save.gd has carried `prepared` since F2;
# this is the check that the page writes the field it carries.
func test_it_survives_a_save() -> void:
	var cleric = build("cleric", "lightdomain", 8)
	var picks := Prepare.pool(cleric).slice(0, 3)
	for sid in picks:
		Prepare.toggle(cleric, sid)
	var back = Save.from_dict(Save.to_dict(cleric))
	check(back != null, "the character round-trips")
	if back == null:
		return
	for sid in picks:
		check(sid in back.prepared, "%s is still prepared after a save and load" % sid)

# --- the page -------------------------------------------------------------

func test_the_page_renders() -> void:
	var druid = build("druid", "circleland", 8)
	var page = load("res://scenes/party/prepare.tscn").instantiate()
	root.add_child(page)
	page.set_character(druid)
	check(page.field("count").begins_with("0 / "), "the header counts nothing prepared yet (%s)"
		% page.field("count"))
	check(page.field("dc").contains("DC"), "the header shows the save DC (%s)" % page.field("dc"))
	check(page.field("slots").contains("L1"), "the header shows the slots (%s)" % page.field("slots"))

	# Press a real row, and the header follows it.
	var sid: String = Prepare.pool(druid)[0]
	var button: Button = page.row(sid)
	check(button != null, "the pool row for %s is on the page" % sid)
	if button != null:
		button.pressed.emit()
		check(sid in druid.prepared, "pressing the row prepares the spell")
		check(page.field("count").begins_with("1 / "), "and the header says so (%s)"
			% page.field("count"))

	# A bard gets the page and is told why there is nothing on it, rather than
	# an empty screen with no explanation.
	var bard = load("res://scenes/party/prepare.tscn").instantiate()
	root.add_child(bard)
	bard.set_character(build("bard", "collegelore", 8))
	check(bard.field("count") == "", "a non-preparing class gets no counter")

	# Issue #122: every row wears the spell's own badge — the same art the
	# action bar puts on the button that casts it (assets/icons/skills, falling
	# back to the school disc), so the thing picked here is recognisable as the
	# thing pressed in the fight.
	var listed: Array = Prepare.free_list(druid) + Prepare.pool(druid)
	check(not listed.is_empty(), "the druid's page lists something to draw")
	var without: Array = listed.filter(func(s): return Icons.skill_icon({"spell": s}) == null)
	check(without.is_empty(), "every listed spell resolves to a badge (%s)" % str(without))
	var pics := _texture_rects(page)
	check(pics.size() == listed.size(),
		"one badge on the page per listed spell (%d for %d)" % [pics.size(), listed.size()])
	check(pics.all(func(t): return t.texture != null), "and none of them is an empty frame")

func _texture_rects(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is TextureRect and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(_texture_rects(c))
	return out

func test_the_party_screen_offers_it() -> void:
	var pty = Party.new()
	var druid = build("druid", "circlemoon", 8)
	var bard = build("bard", "collegelore", 8)
	pty.add_member(druid)
	pty.add_member(bard)
	var screen = load("res://scenes/party/party.tscn").instantiate()
	screen.party = pty
	root.add_child(screen)
	await process_frame          # the roster rows are built in _ready()
	var buttons := _spell_buttons(screen)
	check(buttons.size() == 2, "one Spells button per roster row (%d)" % buttons.size())
	var live: Array = buttons.filter(func(b): return not b.disabled)
	check(live.size() == 1, "only the druid's is live (%d)" % live.size())
	for b in buttons:
		if b.disabled:
			check(b.tooltip_text.contains("does not prepare"),
				"the greyed one says why: %s" % b.tooltip_text)

func _spell_buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button and String(node.text) == "Spells":
		out.append(node)
	for c in node.get_children():
		out.append_array(_spell_buttons(c))
	return out

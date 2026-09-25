# Party manager screen — roster on the left, the active <=4 on the right,
# shared gold + stash below. Built programmatically, same palette as the
# combat screen. All state lives in core/party.gd; this only draws it.
#
# Run standalone:  godot --path . scenes/party/party.tscn
extends Control

const Party = preload("res://core/party.gd")
const Adapter = preload("res://core/adapter.gd")   # audit 4.1: slot pips, drawn the way the fight draws them
const Icons = preload("res://core/ui_icons.gd")
const Sound = preload("res://core/audio.gd")
# D3: travel.gd owns every rule about the standing orders — the paces, their
# labels and notes, and the shape of party.travel_orders. This screen only sets
# them, and always through set_orders(), never by writing the dict.
const Travel = preload("res://core/travel.gd")
# T9x: the open-world map's own figure lookup (scenes/world/party3d.gd reads
# the same dict for the player) — reused here rather than duplicated so the
# picker can never drift out of sync with what actually has a model.
const HeroModels = preload("res://scenes/figures3d.gd").HERO_MODELS
const Portraits = preload("res://scenes/portraits.gd")
# Skill ids -> names/abilities, the same table the profile screen reads.
const Catalog = preload("res://core/rules/catalog.gd")
# The prepare page's own model: who prepares, what they may prepare, and the
# limit. Static and UI-free, so this screen can ask before offering the button.
const Prepare = preload("res://scenes/party/prepare.gd")
# #118: whether a roster row's Level up button is live, and what the tooltip
# says when it is not. Same source the profile's own button reads.
const Leveling = preload("res://core/leveling.gd")
const Coop = preload("res://core/coop.gd")
# What the party thinks of each other — one describe() line per active pair,
# under the standing orders. The model is core/party_opinion.gd's; this draws it.
const PartyOpinion = preload("res://core/party_opinion.gd")
const RelationsWeb = preload("res://scenes/party/relations_web.gd")
const Callings = preload("res://core/callings.gd")
const Fallen = preload("res://core/fallen.gd")   # audit 2.1: the roll of the fallen, under the roster
const Traits = preload("res://core/traits.gd")
const TraitOffer = preload("res://scenes/party/trait_offer.gd")
# Whether this company still makes people, or only hires them (a run started
# since hiring pools: the founder is the one hero ever made).
const Recruits = preload("res://core/recruits.gd")

const COL_BG := Icons.COL_BG
const COL_EDGE := Icons.COL_EDGE
const COL_GOLD := Icons.COL_GOLD
const COL_DIM := Icons.COL_MUTED
const COL_PARTY := Icons.COL_PARTY

var party: Party                          # injected by T5, or a demo roster
var _selected := ""                       # roster id armed for a slot click

# Issue #27: who is in the party and who is on the bench is settled where
# people are — an inn, a roster screen before a run starts — not standing in
# open country with the map paused. Whoever opens this screen says which it is:
# world.gd's HUD button opens it locked, the inn's own "Sort out the party"
# opens it unlocked, and the pre-run screens have never been anywhere else.
#
# What the lock covers is recruiting and benching. Marching ORDER, the standing
# orders and the map figure stay live everywhere: deciding who walks first is a
# travel decision, and travel is what you are doing out there.
var roster_locked := false
var locked_note := "Benching and recruiting happen at an inn."
const HIRED_NOTE := "The rest of the company is hired at an inn."

# Whoever opens this screen as an overlay names the way out and it is drawn
# here, top-right — the same corner the profile's and creator's own Back
# buttons use, so it has to sit UNDER those sub-screens rather than over them
# (world.gd's own button in that corner used to cover their Cancel/Back).
signal exit_requested
var exit_label := ""

var _roster_col := VBoxContainer.new()
var _slot_col := VBoxContainer.new()
var _hint := Label.new()
var _purse := Label.new()
var _stash := RichTextLabel.new()
var _fig_row := HBoxContainer.new()   # T9x: rebuilt on every _refresh() — its options are the active roster
# D3: pace / scout / watch, plus the line that says what the pace costs and
# buys. Rebuilt on every _refresh() for the same reason the figure picker is —
# who can be named for a job is the active roster, and that moves under it.
var _orders_row := VBoxContainer.new()
var _callings_row := HBoxContainer.new()   # the told callings, one line in the bottom strip
var _relations_row := VBoxContainer.new()  # the Relations caption and web, in their own card under the marching column
var _relations_card := PanelContainer.new()  # hidden for a party of one, which has no pairs
var _create_btn: Button        # greyed while roster_locked — see roster_locked above
var _offer: Control = null     # #176: the one-time personality-trait offer, while it is up

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	if party == null:
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
		party.add_gold(275)
		party.stash_add("potions-of-healing", 3)
		party.stash_add("rope-hempen")

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16; root.offset_top = 12
	root.offset_right = -16; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := Label.new()
	header.text = "The party"
	header.theme_type_variation = "Title"
	root.add_child(header)

	_hint.theme_type_variation = "Dim"
	root.add_child(_hint)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	_create_btn = Button.new()
	Icons.clicks(_create_btn)
	_create_btn.text = "Create new"
	_create_btn.theme_type_variation = "Primary"
	_create_btn.pressed.connect(func():
		if roster_locked or (Recruits.hire_only(party) and not party.roster.is_empty()):
			return
		_on_create_new())
	cols.add_child(_column("Roster", _roster_col, 1.4, _create_btn))   # #102: the button lives with the list it adds to
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 10)
	var marching := _column("Marching, up to %d" % Party.MAX_ACTIVE, _slot_col, 1.0)
	marching.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(marching)
	right.add_child(_relations_panel())
	cols.add_child(right)

	root.add_child(_footer())
	if exit_label != "":
		var out := Button.new()
		Icons.clicks(out)
		out.text = exit_label
		out.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		out.offset_left = -220; out.offset_top = 12; out.offset_right = -16
		out.pressed.connect(func(): exit_requested.emit())
		add_child(out)
	_refresh()

# A titled, scrolling column.
func _column(title: String, body: VBoxContainer, stretch: float, corner: Control = null) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = stretch
	var head := HBoxContainer.new()
	wrap.add_child(head)
	var cap := Label.new()
	cap.text = title
	cap.theme_type_variation = "Caption"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cap)
	if corner != null:   # #102: the column's own action, top-right of its list
		head.add_child(corner)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	scroll.add_child(body)
	wrap.add_child(scroll)
	return wrap

# The strip along the bottom, kept to as few lines as it can be: the purse,
# stash and map figure; D3's standing orders with the pace note beside them
# (cut to one line, the whole sentence on hover); and the Callings, one line
# too, only once one has been told. The Relations web is not here: it sits
# under the marching column, the same width as it, since it is about the
# same four people.
func _footer() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)

	_purse.theme_type_variation = "Head"
	_purse.add_theme_color_override("font_color", COL_GOLD)
	row.add_child(_purse)

	_stash.bbcode_enabled = true
	_stash.fit_content = true
	_stash.scroll_active = false
	_stash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	row.add_child(_stash)

	# T9x: which of the active party stands for the band on the open-world
	# map — a specific character, not a class. Rebuilt on every _refresh()
	# (see below) since swapping the active roster changes who's offered.
	_fig_row.name = "FigureRow"
	row.add_child(_fig_row)

	_orders_row.name = "OrdersRow"
	_orders_row.add_theme_constant_override("separation", 4)
	col.add_child(_orders_row)

	_callings_row.name = "CallingsRow"
	_callings_row.add_theme_constant_override("separation", 14)
	col.add_child(_callings_row)
	return panel

# The Relations card, under the marching column and as wide as it.
func _relations_panel() -> Control:
	_relations_card.theme_type_variation = "Card"
	_relations_card.name = "RelationsCard"
	_relations_row.name = "RelationsRow"
	_relations_row.add_theme_constant_override("separation", 2)
	_relations_card.add_child(_relations_row)
	return _relations_card

# Out of the tree now, not at the end of the frame: these rows hold NAMED
# controls, and a queue_free()d child still sitting there would make Godot
# rename its own replacement ("PacePicker2").
func _clear(row: Container) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()

# T9x: options are the active party's own members, one row each — a person,
# not a class. The row carries that character's id (what core/party.gd's
# overworld_figure stores), so two members of the same class are two separate
# rows that each stick, and benching the one you chose drops the party back to
# the pawn instead of silently handing the figure to their colleague. Rebuilt
# every _refresh() since swapping the active roster changes who's offered.
func _build_figure_picker() -> void:
	_clear(_fig_row)
	var label := Label.new()
	label.text = "Map figure"
	label.theme_type_variation = "Dim"
	_fig_row.add_child(label)

	# Asking the party who it resolves to (rather than reading the field raw)
	# is also what migrates a pre-identity save's class id — see
	# core/party.gd's overworld_member().
	var chosen = party.overworld_pick()
	var chosen_id: String = chosen.id if chosen != null else ""
	var ob := OptionButton.new()
	ob.name = "FigurePicker"      # the footer holds four pickers now; named so each is addressable
	ob.add_item("Default (highest level)")
	ob.set_item_metadata(0, "")
	for id in party.active:
		var ch = party.get_member(id)
		if ch == null:
			continue
		var cid: String = ch.class_id()
		if not HeroModels.has(cid):
			continue   # a class with no figure asset yet — not offered, same fallback contract as everywhere else
		ob.add_item("%s  %s" % [Icons.class_glyph(cid), ch.cname])
		ob.set_item_metadata(ob.item_count - 1, ch.id)
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == chosen_id:
			ob.select(i)
			break
	ob.item_selected.connect(func(i): party.overworld_figure = String(ob.get_item_metadata(i)))
	_fig_row.add_child(ob)

# --- D3 standing orders ----------------------------------------------------
#
# Set once here and then left alone: the open world's 1x-8x fast-forward only
# stays honest if the road never stops to ask a question, so these orders are
# what resolve whatever happens out there (core/travel.gd's two rules).
#
# Scout and watch are the two jobs travel.gd hands out by role. Naming somebody
# means their skill is rolled instead of the party's best at it — which is the
# entire point of naming them, so say so rather than leaving it to be guessed.
const SCOUT_HINT := "Reads the ground ahead — rough going, and tracks across the road.\n" \
	+ "Leave it to \"whoever is best\" and the party's best at it rolls."
const WATCH_HINT := "Notices what the road is about to do — foul water, and the like.\n" \
	+ "Leave it to \"whoever is best\" and the party's best at it rolls."
const BEST_LABEL := "Whoever is best"

func _build_orders() -> void:
	_clear(_orders_row)
	# Asking travel.gd (rather than reading party.travel_orders) is also what
	# drops an order naming somebody who has since been benched, so the control
	# never shows a name that is no longer marching.
	var o: Dictionary = Travel.orders(party)
	var pace: String = String(o["pace"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_orders_row.add_child(row)

	var cap := Label.new()
	cap.text = "Standing orders"
	cap.theme_type_variation = "Caption"
	row.add_child(cap)

	var pace_ob := OptionButton.new()
	pace_ob.name = "PacePicker"
	for p in Travel.PACES:
		var pid: String = String(p)
		pace_ob.add_item(Travel.pace_label(pid))
		pace_ob.set_item_metadata(pace_ob.item_count - 1, pid)
		pace_ob.set_item_tooltip(pace_ob.item_count - 1, Travel.pace_note(pid))
	_select_meta(pace_ob, pace)
	pace_ob.item_selected.connect(func(i): _set_order("pace", String(pace_ob.get_item_metadata(i))))
	row.add_child(_order_field("Pace:", pace_ob))

	for job in ["scout", "watch"]:
		var job_ob := _job_picker(String(job), String(o[job]))
		row.add_child(_order_field("%s:" % String(job).capitalize(), job_ob))

	# Both halves earn their place: the note is the sentence that sells the
	# trade, the numbers are the trade itself. A player should be able to see
	# that Careful is 0.70x and +2 without opening core/travel.gd.
	# On the pickers' own line, cut to fit, the whole of it on hover.
	var note := _one_line("%s  %.2f× travel speed, %s." % [
		Travel.pace_note(pace), Travel.speed_mult(party), _effect(Travel.pace_bonus(party))])
	note.name = "PaceNote"
	row.add_child(note)

	# #164: only shown when the slowest active member is under 30 ft — a
	# standard-speed party gets no extra line.
	var walk_note_text := Travel.walk_note(party)
	if walk_note_text != "":
		var walk_lbl := _one_line(walk_note_text)
		walk_lbl.name = "WalkNote"
		_orders_row.add_child(walk_lbl)

# A dim line that takes what width is left and ends in "…" rather than
# wrapping, with the whole text as its tooltip — what keeps the strip short.
func _one_line(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "Dim"
	l.text = text
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

# The Callings lines and the Relations web. Callings are words — each is a
# place and a state, and there are only ever a few. Relations were words too
# (docs/spike-party-opinions.md §5 had "Vera Kord and Pike Sallow — rivals
# (-44)", one line per pair) and are a picture now: scenes/party/relations_web.gd
# draws the marching party's faces joined by a line per pair, its colour and
# shape the band, with describe() one hover away — and, since the bench shares
# the fire at an inn (the design audit's §2.4b), the living bench in a row
# under them. A company of one has nobody to get on with, and the block is not
# drawn at all.
func _build_relations() -> void:
	_clear(_callings_row)
	_clear(_relations_row)
	# Callings (core/callings.gd): one line per active hero whose calling has
	# been told — "Ilsa Vane — The defiled shrine — told, marked on the map".
	# Nothing while untold, so a fresh party sees no caption.
	var lines: Array = []
	for id in party.active:
		var line: String = Callings.describe(party, String(id))
		if line != "":
			lines.append("%s — %s" % [party.get_member(id).cname, line])
	_callings_row.visible = not lines.is_empty()
	if not lines.is_empty():
		var ccap := Label.new()
		ccap.text = "Callings"
		ccap.theme_type_variation = "Caption"
		_callings_row.add_child(ccap)
		var l := _one_line("   ·   ".join(lines))
		l.tooltip_text = "\n".join(lines)
		_callings_row.add_child(l)
	_relations_card.visible = not PartyOpinion.pairs(PartyOpinion.fireside_ids(party, true)).is_empty()
	if not _relations_card.visible:
		return
	var cap := Label.new()
	cap.text = "Relations"
	cap.theme_type_variation = "Caption"
	_relations_row.add_child(cap)
	var web := RelationsWeb.new()
	web.setup(party)
	_relations_row.add_child(web)

# One job's picker: the active party by name, over a first row meaning "nobody
# named, use the party's best". Everybody active is offered — unlike the figure
# picker there is no asset to be missing, and travel.gd will roll whoever is
# named whether or not they are any good at it.
func _job_picker(job: String, chosen_id: String) -> OptionButton:
	var ob := OptionButton.new()
	ob.name = "%sPicker" % job.capitalize()
	ob.tooltip_text = SCOUT_HINT if job == "scout" else WATCH_HINT
	ob.add_item(BEST_LABEL)
	ob.set_item_metadata(0, "")
	for id in party.active:
		var ch = party.get_member(id)
		if ch == null:
			continue
		ob.add_item("%s  %s" % [Icons.class_glyph(ch.class_id()), ch.cname])
		ob.set_item_metadata(ob.item_count - 1, ch.id)
	_select_meta(ob, chosen_id)
	ob.item_selected.connect(func(i): _set_order(job, String(ob.get_item_metadata(i))))
	return ob

# One order written back. All three go through set_orders() together because the
# shape of party.travel_orders belongs to travel.gd, not to this screen.
func _set_order(key: String, value: String) -> void:
	var o: Dictionary = Travel.orders(party)
	o[key] = value
	Travel.set_orders(party, String(o["pace"]), String(o["scout"]), String(o["watch"]))
	_build_orders()          # the pace note is the only thing on screen that moves

func _select_meta(ob: OptionButton, value: String) -> void:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == value:
			ob.select(i)
			return

func _order_field(caption: String, ob: OptionButton) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", COL_DIM)
	box.add_child(label)
	box.add_child(ob)
	return box

# The pace's bonus as a clause. Zero gets words rather than "+0", which reads as
# a modifier that is there rather than one that is not.
func _effect(bonus: int) -> String:
	return "no modifier on the road" if bonus == 0 \
		else "%+d on every check the road makes" % bonus

# --- rendering ------------------------------------------------------------

func _refresh() -> void:
	for c in _roster_col.get_children():
		c.queue_free()
	for c in _slot_col.get_children():
		c.queue_free()

	# The bench first, under its own head: who you could swap in is what this
	# column is for, and with the marching party listed first (they usually
	# are, in roster order) the substitutes sat below the fold. The marching
	# party follows, in marching order, the same four as the column on the right.
	var benched: Array = party.roster.filter(func(ch): return not party.is_active(ch.id))
	_roster_col.add_child(_group_head("On the bench", benched.size(),
		"Nobody on the bench. A new face is hired at an inn." if Recruits.hire_only(party)
			else "Nobody on the bench. A new face is recruited at an inn, or made with Create new."))
	for ch in benched:
		_roster_col.add_child(_card(party.summary(ch.id)))
	_roster_col.add_child(_group_head("Marching", party.active.size(), ""))
	for id in party.active:
		_roster_col.add_child(_card(party.summary(id)))
	# Audit 2.1: the roll of the fallen (core/fallen.gd), under the living,
	# newest first — who, where and to what. Not drawn until someone is on it.
	var roll: Array = Fallen.roll(party)
	if not roll.is_empty():
		_roster_col.add_child(_group_head("The fallen", roll.size(), ""))
		for i in range(roll.size() - 1, -1, -1):
			var l := Label.new()
			l.text = Fallen.line(roll[i], party)
			l.theme_type_variation = "Dim"
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(240, 0)
			l.set_meta("fallen", String(roll[i]["id"]))
			_roster_col.add_child(l)

	for i in Party.MAX_ACTIVE:
		if i < party.active.size():
			_slot_col.add_child(_slot(i, party.summary(party.active[i])))
		else:
			_slot_col.add_child(_slot(i, {}))

	_build_figure_picker()
	_build_orders()
	_build_relations()
	_maybe_offer_traits()

	_purse.text = "%d ◉" % party.gold
	if party.stash.is_empty():
		_stash.text = "[color=#8f95a3]stash empty[/color]"
	else:
		var parts := []
		for e in party.stash:
			var id := String(e["item_id"])
			var nm: String = id.capitalize() if Party.is_identified(e) \
				else "Unidentified (%s)" % Icons.rarity_of(id)
			parts.append(Icons.item_bb(id, "%s ×%d" % [nm, int(e["quantity"])]))
		_stash.text = "[color=%s]Stash:[/color] %s" % [Icons.COL_BODY.to_html(false), ", ".join(parts)]

	# A hiring company makes exactly one hero, the founder, and only while the
	# roster is empty — every face after that is hired at an inn. The greyed
	# button says so on its tooltip, never a silent grey; the founding itself
	# gets the hint line.
	var founded: bool = Recruits.hire_only(party) and not party.roster.is_empty()
	if _create_btn != null:
		_create_btn.disabled = roster_locked or founded
		_create_btn.tooltip_text = locked_note if roster_locked else (HIRED_NOTE if founded else "")
	if Recruits.hire_only(party) and party.roster.is_empty():
		_hint.text = "Make the one who founds the company. Everyone after them is hired at an inn once you are on the road."
	elif roster_locked:
		_hint.text = "%s  Marching order, standing orders and the map figure still change here." % locked_note
	elif _selected == "":
		_hint.text = "Click anyone marching to bench them.  Or pick up a roster member, then click a slot to place or swap them."
	else:
		_hint.text = "%s selected — click a party slot to place them, or click them again to cancel." \
			% party.summary(_selected).get("name", "?")

# #176: a hero from before personality traits is offered the pick once, the
# first time this page opens with them on it (scenes/party/trait_offer.gd). One
# at a time, in roster order; in co-op only your own heroes — a friend's are
# offered on the friend's screen, the way their level-ups are.
func _maybe_offer_traits() -> void:
	if _offer != null:
		return
	for ch in party.roster:
		if Traits.needs_offer(ch) and Coop.mine(party, ch.id):
			_offer = TraitOffer.new()
			add_child(_offer)
			_offer.done.connect(func(_kept: bool):
				_offer.queue_free()
				_offer = null
				_refresh())   # re-draws the roster with the traits, and offers the next hero if any
			_offer.offer(ch)
			return

# A group's head in the roster column: its name and count, a rule, and (for an
# empty bench) the one line saying where a substitute comes from.
func _group_head(title: String, n: int, empty_note: String) -> Control:
	var box := VBoxContainer.new()
	# Tagged, not named: _refresh() queue_free()s the old column, and a new node
	# asking for a name the old one still holds gets renamed ("@VBoxContainer@12").
	box.set_meta("group", title)
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var l := Label.new()
	l.text = "%s · %d" % [title, n]
	l.theme_type_variation = "Gilt"
	l.add_theme_color_override("font_color", COL_PARTY if title == "Marching" else Icons.COL_ACCENT)
	head.add_child(l)
	var rule := HSeparator.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rule)
	if n == 0 and empty_note != "":
		var note := Label.new()
		note.text = empty_note
		note.theme_type_variation = "Dim"
		box.add_child(note)
	return box

# One roster row: summary + select/bench/profile/dismiss. A substitute's row
# wears a verdigris bar down its left edge and its To party button is the primary
# one while there is a slot free; a marching row is a step quieter, since the
# right-hand column already shows them.
func _card(sm: Dictionary) -> Control:
	# A ledger row, not a card: alternate rows take a faint tint, the picked
	# one a gilt bar down its left edge. The whole row is the pick button.
	var panel := PanelContainer.new()
	var picked: bool = sm["id"] == _selected
	panel.theme_type_variation = "RowPicked" if picked else ("RowAlt" if _roster_col.get_child_count() % 2 == 1 else "Row")
	if not picked and not sm["active"] and not sm.get("dead", false):
		var bar := Icons.box(Icons.COL_ROW, Color(0, 0, 0, 0), 0, 10, 6)
		bar.border_color = Icons.COL_ACCENT   # verdigris: the picked row keeps the gilt bar
		bar.border_width_left = 4
		panel.add_theme_stylebox_override("panel", bar)
	elif not picked and sm["active"]:
		panel.modulate = Color(1, 1, 1, 0.78)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	panel.tooltip_text = "Pick up, then click a marching slot"
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sound.play_sfx("click")
			_select(sm["id"]))
	row.add_child(_summary_label(sm))

	var bench := Button.new()
	Icons.clicks(bench)
	bench.text = "Bench" if sm["active"] else "To party"
	bench.disabled = roster_locked \
		or (not sm["active"] and party.active.size() >= Party.MAX_ACTIVE)
	if roster_locked:
		bench.tooltip_text = locked_note
	elif not sm["active"] and not bench.disabled:
		bench.theme_type_variation = "Primary"
	if sm.get("dead", false):   # #109: say so, and say what brings them back
		bench.text = "Dead"
		bench.disabled = true
		bench.tooltip_text = "Dead. A settlement healer raises them for %d ◉ (%d ◉ a level); so does a Revivify caster with a 3rd-level slot, or a Scroll of Resurrection, at the same price." % [Party.revive_cost(party.get_member(sm["id"])), Party.REVIVE_PER_LEVEL]
	bench.pressed.connect(func():
		if roster_locked:
			return
		if sm["active"]: party.bench(sm["id"])
		else: party.activate(sm["id"])
		_selected = ""
		_refresh())
	row.add_child(bench)

	var prof := Button.new()
	Icons.clicks(prof)
	prof.text = "View"
	prof.tooltip_text = "Open the character profile"
	prof.pressed.connect(func(): _on_view_profile(sm["id"]))
	row.add_child(prof)

	# Issue #118: a level is spent per character, so the button that spends it
	# belongs on the character's own row — the roster is the page that knows
	# who is owed one, and it used to be the page that could not say so. Greyed
	# with the reason rather than hidden, the same way Spells below is.
	var who = party.get_member(sm["id"])
	var ready: bool = who != null and not sm.get("dead", false) and Leveling.can_level_up(who)
	var theirs: bool = who != null and not Coop.mine(party, who.id)   # co-op: a friend's hero levels on the friend's screen
	var lvl := Button.new()
	Icons.clicks(lvl)
	lvl.text = "Level up"
	lvl.disabled = not ready or theirs
	if ready and theirs:
		lvl.tooltip_text = "%s is your friend's — the level is theirs to take." % sm["name"]
	elif ready:
		lvl.theme_type_variation = "Primary"
		lvl.tooltip_text = "%s has the XP for level %d" % [sm["name"], who.level() + 1]
	elif who == null or sm.get("dead", false):
		lvl.tooltip_text = "The dead do not level up."
	else:
		lvl.tooltip_text = "%d more XP to the next level" % Leveling.xp_to_next(who)
	lvl.pressed.connect(func(): _on_view_profile(sm["id"], true))
	row.add_child(lvl)

	# Preparing is a thing only five of the twelve classes do, so the button is
	# on every row and live on the rows it means something for — greyed with the
	# reason rather than hidden, so "where do I prepare spells" has an answer on
	# the page whoever is asking happens to be looking at.
	var member = party.get_member(sm["id"])
	var preps: bool = member != null and Prepare.prepares(member)
	var spells := Button.new()
	Icons.clicks(spells)
	spells.text = "Spells"
	spells.disabled = not preps
	spells.tooltip_text = "Choose which spells %s has prepared" % sm["name"] if preps \
		else "%s does not prepare spells — a bard, sorcerer or warlock knows theirs outright" % sm["name"]
	spells.pressed.connect(func(): _on_prepare_spells(sm["id"]))
	row.add_child(spells)

	# Dismissing is recruiting in reverse, so it shares the inn lock. The last
	# member stays: an empty roster has nobody to walk the map.
	var dismiss := Button.new()
	Icons.clicks(dismiss)
	dismiss.text = "Dismiss"
	dismiss.disabled = roster_locked or party.roster.size() <= 1
	dismiss.tooltip_text = locked_note if roster_locked \
		else ("The last member cannot be dismissed" if party.roster.size() <= 1 else "Remove %s from the roster for good" % sm["name"])
	dismiss.pressed.connect(func():
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Dismiss %s? They leave the company and cannot be recalled." % sm["name"]
		dlg.ok_button_text = "Dismiss"
		dlg.confirmed.connect(func():
			party.remove_member(sm["id"])
			_selected = ""
			_refresh())
		dlg.canceled.connect(dlg.queue_free)
		dlg.confirmed.connect(dlg.queue_free)
		add_child(dlg)
		dlg.popup_centered())
	row.add_child(dismiss)
	return panel

# One of the four marching-order slots. Clicking it places/swaps the selection.
# The slot's height is measured, not assumed. A Button does not grow for a
# child laid out by anchors, so the 56 that used to be hard-coded here was a
# standing bet that the summary would never be taller than two lines — and
# issue #27's gear and skills lines took it to four, which stacked the four
# marching slots on top of each other.
const SLOT_MIN_H := 56.0
const SLOT_PAD_H := 10.0

func _slot(index: int, sm: Dictionary) -> Control:
	var b := Button.new()
	Icons.clicks(b)
	b.custom_minimum_size = Vector2(0, SLOT_MIN_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if sm.is_empty():
		b.text = "%d.  Empty" % (index + 1)
		b.add_theme_color_override("font_color", COL_DIM)
	else:
		# The marching slots are numbered because the order IS the order — who
		# walks first is who the road meets first.
		b.add_theme_stylebox_override("normal", _slot_box())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 14; row.offset_top = 4; row.offset_bottom = -4
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := Label.new()
		num.text = "%d." % (index + 1)
		num.theme_type_variation = "Gilt"
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(num)
		var sum := _summary_label(sm)
		sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sum)
		b.add_child(row)
		b.custom_minimum_size.y = maxf(SLOT_MIN_H,
			sum.get_combined_minimum_size().y + SLOT_PAD_H)
		# What this click does depends on whether you are carrying somebody.
		b.tooltip_text = ("Click to bench %s" % sm["name"]) if not roster_locked \
			else locked_note
	b.pressed.connect(func(): _on_slot(index))
	return b

# The marching row: the normal button block with the party green down its
# left edge, the same bar the picked roster row wears in gilt.
func _slot_box() -> StyleBoxFlat:
	var s := Icons.box(Icons.COL_ROW, Color(0, 0, 0, 0), 0, 12, 6)
	s.border_color = COL_PARTY
	s.border_width_left = 3
	return s

func _summary_label(sm: Dictionary) -> Control:
	# Name in the serif, then the three numbers in fixed columns so a whole
	# roster's ACs line up under each other — a ledger, not a sentence.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = "%s  %s" % [Icons.class_glyph(sm["class_id"]), sm["name"]]
	name_l.theme_type_variation = "Head"
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sm["active"]:
		name_l.add_theme_color_override("font_color", COL_PARTY)
	col.add_child(name_l)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 0)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cell in [["%s %d" % [sm["class_name"], sm["level"]], 120], ["AC %d" % sm["ac"], 60],
			["HP %d/%d" % [sm["hp"], sm["max_hp"]], 0]]:
		var l := Label.new()
		l.text = cell[0]
		l.theme_type_variation = "Dim"
		l.custom_minimum_size.x = cell[1]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(l)
	col.add_child(stats)
	# Issue #27: what they are carrying and what they are good at, on the page
	# that is about the party rather than one click into each sheet. Trained
	# skills only and equipped gear only — the full eighteen-skill table and the
	# tiles you can click stay the profile screen's job.
	col.add_child(_detail_line("⚔", _gear_text(sm), COL_GOLD, "gear"))
	col.add_child(_detail_line("◆", _skills_text(sm), COL_PARTY, "skills"))
	# Audit 4.1: what a caster has left to spend, against the sheet's maximum —
	# the same pips the fight's actor line draws, so a slot spent on the road
	# reads as spent here before the next fight starts.
	if not sm.get("slots", []).is_empty():
		col.add_child(_detail_line("✧", _slots_text(sm), Icons.COL_ACCENT, "slots"))
	if not sm.get("traits", []).is_empty():   # #176: who they are, by name
		col.add_child(_detail_line("✦", ", ".join(sm["traits"].map(func(t): return Traits.name_of(t))), Icons.COL_BODY, "traits"))
	# #165: the class model's face beside the card when it has rendered; the
	# glyph in the name line stays either way.
	var face := Portraits.bust(String(HeroModels.get(sm["class_id"], "")), 48)
	if face == null:
		return col
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = face
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tr)
	row.add_child(col)
	return row

# One of the two lines under a roster row's numbers. Named so a test can find
# it without counting children.
func _detail_line(mark: String, text: String, tint: Color, id: String) -> Label:
	var l := Label.new()
	l.name = "Row%s" % id.capitalize()
	l.text = "%s %s" % [mark, text]
	l.theme_type_variation = "Dim"
	l.add_theme_color_override("font_color", tint)
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.clip_text = true                    # a ledger row keeps its height
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _slots_text(sm: Dictionary) -> String:
	return "  ".join(sm.get("slots", []).map(func(r): return Adapter.slot_pips(r)))

func _gear_text(sm: Dictionary) -> String:
	var worn: Array = sm.get("equipped", [])
	if worn.is_empty():
		return "nothing worn or wielded"
	var names: Array = []
	for it in worn:
		var nm: String = String(it["id"]).capitalize()
		names.append(nm if int(it["quantity"]) <= 1 else "%s x%d" % [nm, int(it["quantity"])])
	return ", ".join(names)

# Best first, which is the order core/party.gd sorted them in; expertise wears
# the filled mark the profile screen uses for it.
func _skills_text(sm: Dictionary) -> String:
	var trained: Array = sm.get("skills", [])
	if trained.is_empty():
		return "no trained skills"
	var defs: Dictionary = Catalog.skills()
	var bits: Array = []
	# A ledger row is one line and clips: five or six skills used to run off
	# the edge mid-word ("Intimidati"). Best first, as many as fit the row's
	# character budget, and the rest said as a count.
	var used := 0
	for sk in trained:
		var id := String(sk["id"])
		var nm: String = String(defs.get(id, {}).get("name", id.capitalize()))
		var bit := "%s%s %+d" % ["◆" if String(sk["prof"]) == "expert" else "", nm, int(sk["mod"])]
		if used + bit.length() > SKILLS_CHARS and not bits.is_empty():
			break
		bits.append(bit)
		used += bit.length() + 2
	if bits.size() < trained.size():
		bits.append("+%d more" % (trained.size() - bits.size()))
	return "  ".join(bits)

const SKILLS_CHARS := 44   # what the roster row shows before its clip, at FS_SMALL

# --- interaction ----------------------------------------------------------

func _select(id: String) -> void:
	_selected = "" if _selected == id else id
	_refresh()

func _on_slot(index: int) -> void:
	# Nothing picked up: a marching slot is the person standing in it, and
	# clicking them takes them out of the line. The roster column has always
	# had a Bench button; the side of the screen you are actually looking at
	# when you decide somebody should sit this one out did not, so the only
	# way to do it was to go and find their row again on the left.
	if _selected == "":
		if roster_locked or index >= party.active.size():
			return
		party.bench(party.active[index])
		_refresh()
		return
	if index < party.active.size():
		if party.is_active(_selected):
			# both in the party: reorder by exchanging slots
			var i := party.active.find(_selected)
			var other: String = party.active[index]
			party.active[index] = _selected
			party.active[i] = other
		elif roster_locked:
			return   # swapping somebody off the bench in is recruiting, not marching order
		else:
			party.swap(party.active[index], _selected)
	elif roster_locked:
		return
	else:
		party.activate(_selected)
	_selected = ""
	_refresh()

const CREATOR_SCENE := "res://scenes/creator/creator.tscn"

# T17: the creator as a full-screen overlay, same shape as the profile below.
# It saves the character itself; we only take the one it hands back.
func _on_create_new() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var creator = load(CREATOR_SCENE).instantiate()
	# A hero created once the party is under way joins at the level the party is
	# playing at, not at 1 — the creator asks for every choice those levels bring.
	creator.set_start_level(party.active_max_level())
	overlay.add_child(creator)
	creator.character_created.connect(func(ch):
		# add_member refuses a duplicate id, and used to refuse it silently: the
		# hero you just built was saved to disk and then simply was not on the
		# page, with nothing on screen to say why. The creator mints a free slug
		# now (core/character_save.gd's unique_slug), so this should not fire —
		# but a refusal must never again be invisible.
		var joined: bool = party.add_member(ch)   # auto-activates while there is a free slot
		overlay.queue_free()
		_refresh()
		if not joined:
			_hint.text = "%s is saved to the barracks but could not join the roster — id \"%s\" is already taken." \
				% [ch.cname, ch.id])
	var back := Button.new()
	Icons.clicks(back)
	back.text = "←  Cancel"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -180; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(func():
		overlay.queue_free()
		_refresh())
	overlay.add_child(back)

const PROFILE_SCENE := "res://scenes/profile/profile.tscn"

# T3's profile, opened as a full-screen overlay so the party state stays live.
# The profile can spend resources / damage the character, so we re-read on close.
# `and_level_up` is the row's own Level up button (#118): the same sheet, with
# the level-up page already open on top of it, so the level is two presses from
# the roster instead of four.
func _on_view_profile(id: String, and_level_up := false) -> void:
	var ch = party.get_member(id)
	if ch == null:
		return
	if not ResourceLoader.exists(PROFILE_SCENE):
		_hint.text = "Profile screen (T3) not available yet."
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var prof = load(PROFILE_SCENE).instantiate()
	# #118: the profile draws the way out in its own header now. Floating a
	# Button in the top-right corner instead put it exactly on top of that
	# screen's "Level up".
	prof.exit_label = "←  Back to party"
	prof.exit_requested.connect(func():
		overlay.queue_free()
		_refresh())
	overlay.add_child(prof)
	prof.set_party(party)          # equip pulls from the shared stash, not the character
	prof.set_character(ch)
	if and_level_up:
		prof.level_up()

const PREPARE_SCENE := "res://scenes/party/prepare.tscn"

# The daily-prep screen, as a full-screen overlay like the profile. Preparing
# rewrites ch.prepared and nothing else, and core/character_save.gd has always
# persisted that field — so there is nothing to save here, only to re-read.
func _on_prepare_spells(id: String) -> void:
	var ch = party.get_member(id)
	if ch == null or not Prepare.prepares(ch):
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var page = load(PREPARE_SCENE).instantiate()
	overlay.add_child(page)
	page.set_character(ch)
	var back := Button.new()
	Icons.clicks(back)
	back.text = "\u2190  Back to party"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -180; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(func():
		overlay.queue_free()
		_refresh())
	overlay.add_child(back)

# --- theme (mirrors scenes/main.gd's) -------------------------------------

func _build_theme() -> void:
	theme = Icons.dark_theme()

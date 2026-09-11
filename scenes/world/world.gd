# O2 — the open-world map screen: draws core/world.gd's free 2D map in the same
# dimetric projection the combat board uses, with a drag-pan / scroll-zoom camera,
# a pause button on the WorldClock, and right-click-to-move for the player party.
# All state lives in core/world.gd; this only draws it and feeds it goals.
#
# Run standalone:  godot --path . scenes/world/world.tscn
#
# The projection math below is a copy of scenes/main.gd's Board._iso/_ring/_fan/
# _soft_shadow (~25 lines). It is duplicated rather than shared because those
# helpers are methods of main.gd's nested `Board extends Control` — they call
# draw_* on themselves and read Board._origin/main.hex_px — so factoring them out
# would mean editing scenes/main.gd, which this phase may not touch. The numbers
# (yaw/squash/gain, light direction) are the contract; keep them equal if either
# side ever changes. ponytail: a shared `core/iso.gd` is the upgrade path, and is
# cheap to do the day main.gd is in scope for edits.
extends Control

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBattle = preload("res://core/world_battle.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Campaign = preload("res://core/campaign.gd")   # T25 item names/prices, and _split_xp
const Sound = preload("res://core/audio.gd")
const Quest = preload("res://core/quest.gd")
const RNG = preload("res://core/rng.gd")
const CharacterSave = preload("res://core/character_save.gd")

const COMBAT_SCENE := "res://scenes/main.tscn"
# O4 trigger distance, in world units. A party token draws at 9-11px before the
# projection's ISO_GAIN, i.e. ~6 world units of radius, so 24 is "the two tokens
# are visibly on top of each other" (~2 token diameters) at 1x, where a tick moves
# a party 4 units.
# O9 item 3: that "comfortably wider than a tick" reasoning only held at 1x. At 4x
# /8x a tick moves 16-32 units, so a pursuer matching the player's speed could sit
# a fixed 32 units behind forever and never trip a 24-unit trigger. _trigger() is
# the floor, widened to whatever the tick actually travelled.
const ENCOUNTER_RADIUS := 24.0
const ENCOUNTER_DIFFICULTY := "normal"
# O6 visit distance. Deliberately wider than ENCOUNTER_RADIUS: a settlement is a
# fixed landmark drawn at ~26 world units of radius (a city footprint) rather than
# a 6-unit token, so "close enough to walk in through the gate" is its own number.
# It is NOT widened by speed the way the encounter trigger is: a settlement is
# something you steer into on purpose, and marching past one at 8x without the
# market opening is the player's own choice, not a missed ambush.
const VISIT_RADIUS := 34.0
# The board an ambush happens on when the encountered faction has no theme of
# its own in Scaler.THEME_FACTION — open country, which is where the map is.
const DEFAULT_THEME := "forest-clearing"

const ISO_YAW := 35.0
const ISO_SQUASH := 0.38
const ISO_GAIN := 1.85
const LIGHT := Vector2(-0.30, -0.34)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
const CELL := 90.0          # ground patch size, in world units
const MAX_CELLS := 900      # cap the ground loop when zoomed far out

var world: World
var party: Party            # injected by whoever opens the map, or a demo roster
var _combat = null          # the live scenes/main.tscn instance, while fighting
var _combat_overlay: Control = null
var _pan := Vector2.ZERO
var _zoom := 1.0
var _origin := Vector2.ZERO
var _pause_btn: Button
var _speed_btn: Button
var _clock_lbl: Label
var _visit: Dictionary = {}      # the open market, or {}
var _visit_panel: Control = null
var _visit_log: Label = null
var _left: Object = null         # the settlement just left; no re-entry until out of range
var _party_overlay: Control = null   # T3's party/profile/inventory screen, full-screen
var _quest_panel: Control = null     # inline quest-log overlay, T9's Quest.active/describe

func _ready() -> void:
	if world == null:
		world = _demo_world()
	if party == null:               # same demo roster scenes/campaign/campaign.gd falls back to
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
	set_process(true)
	_build_hud()

# Hand-placed stand-ins so the scene has something to render and move. Real
# spawning is a later phase's job (O3 onward).
func _demo_world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "soldier", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "soldier", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "soldier", "town"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "cultist", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "soldier", true))
	WorldAI.hunt(w.add_party(World.RoamingParty.new("bandits", Vector2(-250, -120), "bandit")))
	WorldAI.hunt(w.add_party(World.RoamingParty.new("goblins", Vector2(380, 300), "goblinoid")))
	WorldAI.patrol(w.add_party(World.RoamingParty.new("patrol", Vector2(-120, 380), "soldier")),
		[Vector2(-120, 380), Vector2(-360, 260), Vector2(0, 0)])
	return w

# World.tick() advances the clock itself and gates movement on it, so one call
# per frame is the whole update.
func _process(delta: float) -> void:
	# O7: the clock's own advance (0 while paused) both drains O6's queued opinion
	# deltas off the settlements and runs the slow drift back toward neutral.
	var dt := world.tick(delta)
	FactionOpinion.tick(world, dt)
	WorldAI.update(world, delta)
	_check_encounter(dt)
	# O5: NPC-vs-NPC meetings resolve instantly, no scene, no pause — but not
	# while the player's own fight has the map frozen.
	if _combat == null and not world.clock.is_paused():
		# O6 feeds off the outcome: a settlement near the corpses reads differently
		# on the next visit. O5's resolution itself is untouched.
		for r in WorldBattle.check(world, _trigger(dt), encounter_spec):
			Visit.mark_battle(world, r["loser"].position, world.clock.elapsed)
	_check_visit()
	if _clock_lbl != null:
		_clock_lbl.text = "Day %d  %02d:%02d" % [
			int(world.clock.elapsed / 1440.0) + 1,
			int(world.clock.elapsed / 60.0) % 24, int(world.clock.elapsed) % 60]
	queue_redraw()

# --- HUD ---------------------------------------------------------------
func _build_hud() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	_pause_btn = Button.new()
	_pause_btn.text = "Pause"
	_pause_btn.pressed.connect(_toggle_pause)
	bar.add_child(_pause_btn)
	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.pressed.connect(_cycle_speed)
	bar.add_child(_speed_btn)
	_clock_lbl = Label.new()
	_clock_lbl.add_theme_color_override("font_color", Icons.COL_GOLD)
	bar.add_child(_clock_lbl)
	var party_btn := Button.new()
	party_btn.text = "Party"
	party_btn.pressed.connect(_open_party)
	bar.add_child(party_btn)
	var quests_btn := Button.new()
	quests_btn.text = "Quests"
	quests_btn.pressed.connect(_toggle_quests)
	bar.add_child(quests_btn)
	var title := Button.new()
	title.text = "←  Title"
	title.pressed.connect(_leave_world)
	bar.add_child(title)
	var hint := Label.new()
	hint.text = "right-click: march here   ·   drag: pan   ·   wheel: zoom"
	hint.add_theme_color_override("font_color", Icons.COL_MUTED)
	bar.add_child(hint)

# O9 item 2: the only way out of the open world, and the only thing that persists
# it. The map itself is not saved (no world save exists yet) — the characters are,
# which is what the barracks on the title screen counts. Opinion is per-run state
# (a process-global in faction_opinion.gd), so it clears with the run.
func _leave_world() -> void:
	for ch in party.roster:
		CharacterSave.save(ch)
	FactionOpinion.reset()
	# Duck-typed so world.tscn still runs standalone (godot --path . scenes/world/
	# world.tscn), where the parent is the scene root and has no title screen.
	var host := get_parent()
	if host != null and host.has_method("show_title"):
		host.show_title()

# O9 item 7: both are no-ops while a market panel is open. The visit owns the
# clock (it paused it); letting the button resume the world underneath an open
# panel desynced the label and set the map running behind it.
func _toggle_pause() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null:
		return
	if world.clock.is_paused():
		world.clock.resume()
	else:
		world.clock.pause()
	_pause_btn.text = "Resume" if world.clock.is_paused() else "Pause"

func _cycle_speed() -> void:
	if not _visit.is_empty() or _party_overlay != null or _quest_panel != null:
		return
	world.clock.cycle_speed()
	_speed_btn.text = "%dx" % int(world.clock.speed)   # every WorldClock.SPEEDS entry is a whole number

# --- party / profile / inventory ----------------------------------------
#
# Reuses T3's scenes/party/party.tscn as-is (per-character profile/inventory is
# already one click deeper from there) — same overlay shape campaign.gd's own
# _open_party() uses. Pauses the clock while open: browsing gear shouldn't cost
# world-time or let a hunt close in behind the menu.

const PARTY_SCENE := "res://scenes/party/party.tscn"

func _open_party() -> void:
	if _combat != null or not _visit.is_empty() or _party_overlay != null:
		return
	world.clock.pause()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_party_overlay = overlay
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	overlay.add_child(screen)
	var back := Button.new()
	back.text = "←  Back to the map"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -220; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(_close_party)
	overlay.add_child(back)

func _close_party() -> void:
	if _party_overlay != null:
		_party_overlay.queue_free()
		_party_overlay = null
	world.clock.resume()
	_pause_btn.text = "Pause"

# --- quest log ------------------------------------------------------------
#
# Same data campaign.gd's own quest panel reads (Quest.active/describe) — an
# inline toggle rather than a full-screen overlay, since it's just a list.

func _toggle_quests() -> void:
	if _quest_panel != null:
		_close_quests()
		return
	if _combat != null or not _visit.is_empty() or _party_overlay != null:
		return
	world.clock.pause()
	_build_quest_panel()

func _close_quests() -> void:
	if _quest_panel != null:
		_quest_panel.queue_free()
		_quest_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _build_quest_panel() -> void:
	if _quest_panel != null:
		_quest_panel.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = size * 0.5 - Vector2(200, 160)
	panel.custom_minimum_size = Vector2(400, 320)
	add_child(panel)
	_quest_panel = panel
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "Quest log"
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 240)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	var live: Array = Quest.active(party)
	if live.is_empty():
		var none := Label.new()
		none.text = "No quests. Settlements have work."
		none.add_theme_color_override("font_color", Icons.COL_MUTED)
		rows.add_child(none)
	for q in live:
		var l := Label.new()
		l.text = Quest.describe(q)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color",
			Icons.COL_GOLD if q["state"] == "complete" else Icons.COL_PARTY)
		rows.add_child(l)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_quests)
	box.add_child(close)

# --- O4: encounter trigger + combat hand-off ---------------------------

# O9 item 3: the trigger distance for this tick — never below ENCOUNTER_RADIUS,
# but at least as wide as the ground two parties covered in it, so a pursuit at a
# stable gap still closes at 4x/8x. Same number for the player's trigger and O5's
# NPC-vs-NPC one, since both are "two tokens met between two frames".
# ponytail: assumes every party moves at World.SPEED (RoamingParty.speed's default).
# Take the pair's own speeds the day a party moves at its own rate.
func _trigger(dt: float) -> float:
	return maxf(ENCOUNTER_RADIUS, World.SPEED * 2.0 * dt)

# ponytail: linear scan over 3-8 parties once a frame, same as world_ai.gd's hunt.
func _check_encounter(dt := 0.0) -> void:
	if _combat != null or world.clock.is_paused():
		return
	var p := world.player()
	if p == null:
		return
	var reach := _trigger(dt)
	for q in world.parties:
		if q == p or not WorldAI.is_hostile(q, p):
			continue
		if q.position.distance_to(p.position) <= reach:
			_launch_combat(q)
			return

# The roster the encountered party fights with. Scaler takes a *theme*, not a
# faction, so: THEME_FACTION reversed gives a matching board for the factions
# that have one; for the rest (soldier/orc/cultist/...) there is no theme, and
# _faction_order's other documented route — FACTIONS[seed % size] — is snapped
# onto this faction instead. Seeded off the party id, so meeting the same band
# twice is the same band.
func encounter_spec(foe) -> Dictionary:
	var theme := ""
	for t in Scaler.THEME_FACTION:
		if String(Scaler.THEME_FACTION[t]) == foe.faction:
			theme = String(t)
			break
	var seed_v: int = absi(hash(foe.id))
	if theme == "":
		var idx: int = Scaler.FACTIONS.find(foe.faction)
		if idx >= 0:
			seed_v = seed_v - seed_v % Scaler.FACTIONS.size() + idx
	var spec: Dictionary = Scaler.roster_for(
		party.party_characters(), ENCOUNTER_DIFFICULTY, {}, theme, seed_v)
	spec["theme"] = theme if theme != "" else DEFAULT_THEME
	return spec

# The same hand-off scenes/campaign/campaign.gd's _launch_combat() does: the map
# freezes, scenes/main.tscn runs the fight unchanged, `result` comes back.
func _launch_combat(foe) -> void:
	world.clock.pause()
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	_combat.spec = encounter_spec(foe)
	_combat.difficulty = ENCOUNTER_DIFFICULTY
	_combat_overlay.add_child(_combat)

	while _combat != null and _combat.result.is_empty():
		await get_tree().process_frame
	if _combat == null:
		return
	var result: Dictionary = _combat.result
	_combat = null
	_combat_overlay.queue_free()
	_combat_overlay = null
	if String(result.get("outcome", "")) == "Victory":
		_bank(result)
		world.parties.erase(foe)      # beaten; O5 will do the same for NPC-vs-NPC
		# O7 raise/lower event: putting down a monster band is a favour to whoever
		# lives near the bodies; putting down a faction's own band is not.
		if WorldAI.is_monster(foe.faction):
			FactionOpinion.credit_fight(world, foe.position, FactionOpinion.FOUGHT_FOR, foe.faction)
		else:
			FactionOpinion.lower(foe.faction, FactionOpinion.KILLED_THEIRS)
	else:
		_retreat()
	world.clock.resume()

# O9 item 2: a won fight has to actually pay, or the run is a dead end. The same
# four things core/campaign.gd's finish_combat() banks, minus the linear run's own
# bookkeeping (node gold, achievements, autosave, the journal):
#   XP  — Campaign._split_xp(), which is the even split *plus* T22's lifetime/class
#         progression and the level-up chime. It only touches `party`, so a bare
#         Campaign.new(party) is enough to reach it.
#         ponytail: it is an instance method on a file O9 may not edit. Make it
#         static (and drop the throwaway) the day campaign.gd is in scope.
#   gold, loot, quest progress — party-level calls, made directly.
func _bank(result: Dictionary) -> void:
	Campaign.new(party)._split_xp(int(result.get("xp", 0)))
	party.add_gold(int(result.get("gold", 0)))
	for item in result.get("loot", []):
		party.stash_add(String(item))
	# Without this an accepted quest can never reach "complete", so O9 item 4's
	# turn-in row would have nothing to turn in.
	Quest.record_kills(party, result.get("kills", []),
		RNG.new(maxi(1, int(world.clock.elapsed) + 1)))

# Defeat/retreat, deliberately the cheapest thing that keeps the map playable:
# the party falls back to the nearest settlement and stops there. No losses, no
# gold, no wound state — a real defeat-consequences system is O7's business once
# faction opinion exists to hang it on.
func _retreat() -> void:
	var p := world.player()
	if p == null or world.settlements.is_empty():
		return
	var safe: Vector2 = world.settlements[0].position
	for s in world.settlements:
		if p.position.distance_squared_to(s.position) < p.position.distance_squared_to(safe):
			safe = s.position
	p.position = safe
	world.set_goal(p, safe)

# --- O6: settlement visit ----------------------------------------------
# Same shape as _check_encounter above, against the settlement list instead of
# the party list. `_left` stops the panel reopening on the frame after Leave —
# it clears once the player is actually outside the radius again.
func _check_visit() -> void:
	if _combat != null or not _visit.is_empty() or world.clock.is_paused():
		return
	var p := world.player()
	if p == null:
		return
	for s in world.settlements:
		if s.position.distance_to(p.position) > VISIT_RADIUS:
			if s == _left:
				_left = null
			continue
		if s == _left:
			continue
		# O7 effect 3: past FactionOpinion.GUARDS_ATTACK the gate guards come out
		# instead of the market opening — O4's encounter path, with the garrison
		# standing in as the party (it is not on the map, so beating it just ends
		# the fight).
		# O9 item 5: that used to fire at HOSTILE, above REFUSE_TRADE, so the market's
		# refusal branch could never be reached. It has its own lower floor now.
		# O9 item 6: and a monster faction's town never trades at any opinion — its
		# own bands attack the player on sight (WorldAI.is_hostile), so its gate does
		# too. Same gate _check_encounter() uses.
		if WorldAI.is_monster(s.faction) or FactionOpinion.guards_attack(s.faction):
			_left = s
			_launch_combat(World.RoamingParty.new("%s-guard" % s.id, s.position, s.faction))
			return
		_open_visit(s)
		return

func _open_visit(s) -> void:
	world.clock.pause()
	world.set_goal(world.player(), world.player().position)   # stop at the gate
	_visit = Visit.visit(s, world)
	_build_visit_panel()

func _close_visit() -> void:
	_left = _visit.get("settlement")
	_visit = {}
	if _visit_panel != null:
		_visit_panel.queue_free()
		_visit_panel = null
	world.clock.resume()
	_pause_btn.text = "Pause"

func _buy(item_id: String) -> void:
	if Visit.buy(_visit, party, item_id):
		Sound.play_sfx("buy")
		_build_visit_panel()
	else:
		_say("Not enough gold.")

func _sell(item_id: String) -> void:
	if Visit.sell(_visit, party, item_id):
		_build_visit_panel()

# O9 item 1: one attempt per visit. The steal roll is seeded off (settlement, hour)
# and the clock is paused for the whole visit, so every press rolled the identical
# result — a nat 20 was an unlimited gold button. The mark lives on `_visit`, so
# Leave and come back is a fresh attempt (at a fresh hour).
func _steal() -> void:
	if _visit.get("stolen", false):
		_say("They are watching the stall now. Come back another day.")
		return
	var r: Dictionary = Visit.steal(_visit["settlement"], party, world, _visit)
	_visit["stolen"] = true
	if bool(r.get("ok", false)):
		Sound.play_sfx("pickup")
	_build_visit_panel()
	_say(String(r.get("text", "Nobody here has the hands for it.")))

# O9 item 2: the inn. Time is the cost — see SettlementVisit.rest — and the extra
# hours restock the shelf, so the market is re-read afterwards.
func _rest() -> void:
	var s = _visit["settlement"]
	var stolen: bool = _visit.get("stolen", false)
	Visit.rest(party, world)
	Sound.play_sfx("rest")
	_visit = Visit.visit(s, world)
	_visit["stolen"] = stolen
	_build_visit_panel()
	_say("The party takes a long rest. Eight hours pass and the stalls fill up again.")

# O9 item 4: T9's quest verbs, reached from a settlement at last.
func _take_quest() -> void:
	var q: Dictionary = Visit.quest_offer(_visit["settlement"], party)
	if Quest.accept(party, q):
		_build_visit_panel()
		_say("Job taken: %s" % q["title"])
	else:
		_say("No work here just now.")

func _turn_in(quest: Dictionary) -> void:
	var reward: int = int(quest.get("reward", {}).get("gold", 0))
	if Quest.turn_in(party, quest, _visit["settlement"].faction):
		Sound.play_sfx("buy")
		_build_visit_panel()
		_say("%s — paid, +%d gp. They will remember it." % [quest["title"], reward])

# The panel is rebuilt after every action, so the last line has to live on the
# visit rather than on the Label that just got freed.
func _say(text: String) -> void:
	if not _visit.is_empty():
		_visit["log"] = text
	if _visit_log != null:
		_visit_log.text = text

func _build_visit_panel() -> void:
	if _visit_panel != null:
		_visit_panel.queue_free()
	var s = _visit["settlement"]
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = size * 0.5 - Vector2(230, 230)
	panel.custom_minimum_size = Vector2(460, 460)
	add_child(panel)
	_visit_panel = panel
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "%s — %s" % [s.sname, ", ".join(_visit["services"])]
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	box.add_child(title)
	var mood := Label.new()
	mood.text = "Shelves %d/%d · prices x%.2f%s%s · your purse: %d gp" % [
		_visit["steps"], Visit.MAX_STEPS, _visit["markup"],
		"  (fighting nearby)" if _visit["battle"] else "",
		"  (they will not trade with you)" if _visit.get("refused", false) else "",
		party.gold]
	mood.add_theme_color_override("font_color", Icons.COL_MUTED)
	box.add_child(mood)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 320)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	for e in _visit["stock"]:
		_trade_row(rows, "%s — %d gp" % [e["name"], e["price"]], "Buy",
			_buy.bind(String(e["item_id"])))
	for entry in party.stash:
		var id := String(entry["item_id"])
		var paid := Visit.sell_price(_visit, id)
		if paid <= 0:
			continue
		_trade_row(rows, "%s x%d — sells for %d gp" % [
			Campaign.item_name(id), int(entry["quantity"]), paid], "Sell", _sell.bind(id))

	# O9 item 4: one offer, one row per finished job. Quest.offer_for()/turn_in() as
	# they stand; nothing here decides anything about quests.
	var offer: Dictionary = Visit.quest_offer(s, party)
	if not offer.is_empty():
		_trade_row(rows, "Job: %s — %d gp" % [
			offer["title"], int(offer.get("reward", {}).get("gold", 0))], "Take", _take_quest)
	for q in Visit.turn_ins(party):
		_trade_row(rows, "✔ %s" % Quest.describe(q), "Turn in", _turn_in.bind(q))

	_visit_log = Label.new()
	_visit_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_visit_log.custom_minimum_size = Vector2(440, 34)
	box.add_child(_visit_log)
	_visit_log.text = String(_visit.get("log", ""))
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var rest_btn := Button.new()
	rest_btn.text = "Rest the night"
	rest_btn.pressed.connect(_rest)
	bar.add_child(rest_btn)
	var steal_btn := Button.new()
	var spent: bool = _visit.get("stolen", false)
	steal_btn.text = "Stole from the market" if spent else "Steal from the market"
	steal_btn.disabled = spent
	steal_btn.pressed.connect(_steal)
	bar.add_child(steal_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_close_visit)
	bar.add_child(leave)

func _trade_row(rows: VBoxContainer, text: String, action: String, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(330, 0)
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = action
	btn.pressed.connect(on_press)
	row.add_child(btn)
	rows.add_child(row)

# --- projection (see header) -------------------------------------------
func _iso(v: Vector2) -> Vector2:
	var r := v.rotated(deg_to_rad(ISO_YAW)) * ISO_GAIN
	return Vector2(r.x, r.y * ISO_SQUASH)

func _iso_inv(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y / ISO_SQUASH).rotated(-deg_to_rad(ISO_YAW)) / ISO_GAIN

# world point -> screen point
func _pix(w: Vector2) -> Vector2:
	return _origin + _iso(w) * _zoom

# screen point -> world point, the inverse of _pix
func _unpix(sp: Vector2) -> Vector2:
	return _iso_inv((sp - _origin) / _zoom)

func _ring(center: Vector2, r: float, flat := true, closed := false, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var v := Vector2(cos(TAU * i / segs), sin(TAU * i / segs)) * r
		pts.append(center + (_iso(v) if flat else v))
	if closed:
		pts.append(pts[0])
	return pts

func _fan(apex: Vector2, rim: PackedVector2Array, inner: Color, outer: Color) -> void:
	var n := rim.size()
	var cols := PackedColorArray([inner, outer, outer])
	var uv := PackedVector2Array()
	for i in n:
		draw_primitive(PackedVector2Array([apex, rim[i], rim[(i + 1) % n]]), cols, uv)

func _soft_shadow(at: Vector2, r: float, strength := 1.0) -> void:
	for i in 3:
		draw_colored_polygon(_ring(at, r * (1.0 + 0.26 * i)),
			Color(0.02, 0.01, 0.04, strength * (0.20 - 0.05 * i)))

# Stable per-cell noise: same cell, same salt -> same value, every frame.
static func _rand(c: Vector2i, salt: int) -> float:
	var n: int = hash(Vector3i(c.x, c.y, salt))
	return float(n % 4096) / 4096.0 if n >= 0 else float(-n % 4096) / 4096.0

# A faction's colour, straight off its name's hash so no table needs maintaining
# as core/scaler.gd's FACTIONS list grows.
static func faction_color(faction: String, is_player := false) -> Color:
	if is_player:
		return Icons.COL_PARTY
	return Color.from_hsv(float(absi(hash(faction)) % 360) / 360.0, 0.52, 0.78)

# --- camera ------------------------------------------------------------
func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)

func pan_by(d: Vector2) -> void:
	_pan += d

# zoom keeping the world point under `sp` fixed
func zoom_at(sp: Vector2, factor: float) -> void:
	var anchor := _unpix(sp)
	set_zoom(_zoom * factor)
	_layout()
	pan_by(sp - _pix(anchor))
	_layout()      # _origin follows _pan; keep them in step for the next _unpix

func _layout() -> void:
	_origin = size * 0.5 + _pan

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			pan_by(e.relative)
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(e.position, 1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(e.position, 1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var p := world.player()
			if p != null:
				world.set_goal(p, _unpix(e.position))
		queue_redraw()

# --- drawing -----------------------------------------------------------
func _draw() -> void:
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Icons.COL_BG)
	_draw_ground()
	var p := world.player()
	if p != null and not p.at_goal():
		draw_polyline(_ring(_pix(p.goal), 9.0 * _zoom, true, true, 18), Icons.COL_GOLD, 1.5, true)

	# One painter's-order pass over everything standing on the ground.
	var props: Array = []
	for s in world.settlements:
		props.append({"at": _pix(s.position), "s": s})
	for q in world.parties:
		props.append({"at": _pix(q.position), "p": q})
	props.sort_custom(func(a, b): return a["at"].y < b["at"].y)
	for d in props:
		if d.has("s"):
			_draw_settlement(d["s"], d["at"])
		else:
			_draw_party(d["p"], d["at"])

# The same two-layer treatment the combat board gives a hex — a tinted slab, then
# a lighter blob drifting off-centre — on a coarse grid of the ground plane, so
# neighbouring patches overlap in tone instead of reading as hard-cut diamonds.
func _draw_ground() -> void:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var w := _unpix(corner)
		mn = mn.min(w); mx = mx.max(w)
	var i0 := int(floor(mn.x / CELL)); var i1 := int(ceil(mx.x / CELL))
	var j0 := int(floor(mn.y / CELL)); var j1 := int(ceil(mx.y / CELL))
	if (i1 - i0 + 1) * (j1 - j0 + 1) > MAX_CELLS:   # far-out zoom: don't paint the world
		draw_rect(Rect2(Vector2.ZERO, size), Color("2b3a2a"))
		return
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var cell := Vector2i(i, j)
			var c := _pix(Vector2(i + 0.5, j + 0.5) * CELL)
			var v := _rand(cell, 1)
			var tint := Color("35462f").lightened(0.06 * v).darkened(0.05 * (1.0 - v))
			# The patch itself tessellates exactly (a projected square, like the
			# board's hexes) — anything with a rim would show its own edge where it
			# overlapped its neighbour. The shading is the mottle on top.
			var quad := PackedVector2Array()
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				quad.append(_pix((Vector2(i, j) + corner) * CELL))
			draw_colored_polygon(quad, tint)
			var r := CELL * 0.72 * _zoom
			var blob := c + _iso(Vector2(_rand(cell, 2) - 0.5, _rand(cell, 3) - 0.5) * CELL * 0.7) * _zoom
			var br := r * (0.45 + 0.35 * _rand(cell, 4))
			var wash := tint.lightened(0.10) if v > 0.5 else tint.darkened(0.10)
			for k in 3:   # feathered out, so the patches blend instead of tiling visibly
				draw_colored_polygon(_ring(blob, br * (0.55 + 0.225 * k)),
					Color(wash.r, wash.g, wash.b, 0.09))

# A landmark, not art: a shaded footprint plus one block per building, taller and
# wider for a city than a town.
func _draw_settlement(s, at: Vector2) -> void:
	var col := faction_color(s.faction)
	var big: bool = s.kind == "city"
	var r := (26.0 if big else 17.0) * _zoom
	_soft_shadow(at, r * 0.9)
	_fan(at + _iso(LIGHT) * r * 0.5, _ring(at, r), col.darkened(0.35), col.darkened(0.62))
	draw_polyline(_ring(at, r, true, true), col.darkened(0.15), 1.5, true)
	var blocks := [Vector2(0, 0), Vector2(-0.5, 0.35), Vector2(0.5, 0.3)] if big \
		else [Vector2(0, 0), Vector2(0.45, 0.3)]
	for b in blocks:
		var base: Vector2 = at + _iso(b * r)
		var w := r * (0.38 if big else 0.34)
		var h := r * (1.05 if big else 0.75)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0),
			base + Vector2(w, -h), base + Vector2(-w, -h)]), col.darkened(0.12))
		draw_line(base + Vector2(-w, -h), base + Vector2(w, -h), col.lightened(0.35), 2.0)
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), s.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)

# A circular token, the same ball shading the combat board's char tokens use.
func _draw_party(p, at: Vector2) -> void:
	var col := faction_color(p.faction, p.is_player)
	var rad := (11.0 if p.is_player else 9.0) * _zoom
	_soft_shadow(at, rad * 0.8)
	_fan(at + _iso(LIGHT) * rad * 0.62, _ring(at, rad * 1.25),
		col.darkened(0.45), col.darkened(0.70))          # the flat base ring
	_fan(at + LIGHT * rad * 0.62, _ring(at, rad, false),
		col.lightened(0.26), col.darkened(0.20))         # the ball, facing the camera
	draw_polyline(_ring(at, rad, false, true), col.darkened(0.45), 1.5, true)
	if p.is_player:
		draw_polyline(_ring(at, rad * 1.7), Icons.COL_GOLD, 1.5, true)

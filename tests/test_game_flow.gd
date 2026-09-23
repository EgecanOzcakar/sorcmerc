# T17 — the run's end states at the model level: retirement, its guards, and the
# settings default finally reaching a fight. The UI routing is walked by
# tests/drive_game.gd.
#   godot --headless --path . -s tests/test_game_flow.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Party = preload("res://core/party.gd")
const Settings = preload("res://core/settings.gd")
const Game = preload("res://scenes/game/game.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Presets = preload("res://core/presets.gd")
const Tutorial = preload("res://core/tutorial.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _campaign() -> Campaign:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.add_gold(120)
	return Campaign.new(p, 7)

# A real left click at a viewport point, the way a player makes one — picked by
# Godot through whatever is over that pixel, rather than posted to a handler.
func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	# in_local_coords, or the root window puts the event through its screen
	# transform and it lands somewhere else entirely (nothing moves, and the
	# test passes for the wrong reason).
	root.push_input(motion, true)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		root.push_input(e, true)

func _press(under: Node, label: String) -> void:
	for b in under.find_children("*", "Button", true, false):
		if label in b.text:
			b.pressed.emit()
			return
	check(false, "no button labelled '%s'" % label)

func _find(c: Campaign, kind: String) -> int:
	for i in c.options().size():
		if c.options()[i]["kind"] == kind:
			return i
	return -1

func _init() -> void:
	# O17: this process's own autosave slots, so a concurrent godot run cannot
	# clobber them. randi() as well as the pid: under a sandboxed (flatpak)
	# godot every process sees pid 3, so the pid alone is not unique.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	CampaignSave.clear()

	# --- retire: only while picking --------------------------------------
	var c := _campaign()
	check(c.state == "picking", "a fresh run is picking")
	c.stage = 1   # stage 0 is combat-only now, no merchant to stand on
	c.enter(_find(c, "merchant"))
	check(c.state == "visiting", "standing on a merchant")
	check(not c.retire(), "cannot retire mid-visit")
	check(c.state == "visiting", "a refused retirement changes nothing")
	c.leave()
	check(c.retire(), "retiring between nodes is allowed")
	check(c.state == "retired", "the run's state is retired")
	check(c.node.is_empty(), "retiring steps off the road")
	check(not c.retire(), "cannot retire twice")
	check(c.state in Campaign.TERMINAL, "retired is a terminal state")

	# The road does not move on afterwards.
	var stage := c.stage
	c.leave()
	check(c.stage == stage and c.state == "retired", "leave() is inert once retired")
	check(c.enter(0).is_empty(), "no node can be entered once retired")

	# --- retire wraps up like a win: the dead come home -------------------
	var c2 := _campaign()
	var fallen = c2.party.roster[0]
	fallen.dead = true
	c2.party.bench(fallen.id)
	check(c2.retire(), "retiring with a body on the cart")
	check(not fallen.dead, "_conclude auto-revives the dead on retirement")
	# auto_revive_all deliberately leaves the benching alone — the party screen
	# is where you decide who marches next time.
	check(not c2.party.is_active(fallen.id), "the revived stay benched until the player says otherwise")

	# --- gold/xp are already banked, nothing special at the end ----------
	check(c2.party.gold == 120, "the purse is untouched by retiring")

	# --- the autosave survives, and the hub reads a finished run ---------
	check(CampaignSave.has_save(), "retiring autosaves")
	var reloaded = CampaignSave.load_latest()
	check(reloaded != null and reloaded.state == "retired", "a retired run round-trips through the save")

	# --- Settings.default_difficulty is what an unauthored node fights at -
	var s = Settings.current()
	var was: String = s.default_difficulty
	s.default_difficulty = "hard"
	var c3 := _campaign()
	c3.node = {"id": "nameless", "kind": "combat", "theme": "goblin-camp"}   # no authored difficulty
	check(c3.node_difficulty() == "hard", "an unauthored node fights at the settings default")
	c3.node = {"id": "authored", "kind": "combat", "difficulty": "easy"}
	check(c3.node_difficulty() == "easy", "an authored difficulty still wins")
	s.default_difficulty = was

	# --- the summary reads only what the run already tracked --------------
	var lines: Array = Game.summary_lines(c2)
	check(lines.size() >= 4, "the summary has stages, gold, xp and a loot line")
	check(String(lines[0]).contains("/ %d" % Campaign.STAGE_COUNT), "stages cleared out of the route length")
	check(String(lines[lines.size() - 1]).begins_with("Carried home:"), "loot is the last line")

	CampaignSave.clear()

	# --- a new run starts fresh, whatever shape the barracks saved you in ---
	CharacterSave.delete("vera-hp-test")
	var hurt = Presets.vera()
	hurt.id = "vera-hp-test"
	hurt.hp_current = 1
	CharacterSave.save(hurt)
	var game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	game.show_party_setup()
	var screen = game._screen.get_child(0)
	var loaded = screen.party.get_member("vera-hp-test")
	check(loaded != null, "the saved character loads into party setup")
	check(loaded.hp_current == -1, "a new run resets HP to full (the usual -1 sentinel)")
	game.queue_free()
	CharacterSave.delete("vera-hp-test")

	# --- O8: the mode switch reads the env var live, both ways ------------
	# (which screen each mode opens is drive_game.gd's walk)
	var was_flag := OS.get_environment("SORCMERC_LINEAR_CAMPAIGN")
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
	check(not Game.linear_campaign(), "no env var, no linear campaign")
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "1")
	check(Game.linear_campaign(), "the debug env var brings the linear campaign back")
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", was_flag)

	_tutorial_checks()

# T32. Split out and async: a node only reaches _ready once the loop turns, and
# the walkthrough is started by scenes/main.gd's _ready.
func _tutorial_checks() -> void:
	var tp = Tutorial.party()
	check(tp.party_characters().size() == 2, "the tutorial party is two pre-made heroes")
	var tcb = Encounter.build(Tutorial.SPEC, tp.to_combatants(Encounter.PARTY_STARTS))
	var foes: Array = tcb.team_of("foe")
	check(foes.size() == 1, "the tutorial fields exactly one foe")
	check(foes.size() == 1 and foes[0].max_hp <= 10, "...and a weak one")
	# Its trees are walls now (Encounter.SOLID_COVER) — the wood's own cover,
	# not furniture. What the tutorial must not spring is a hazard or a smash.
	check(tcb.board["objects"].all(func(o): return not o.has("hazard") and int(o.get("hp", 0)) == 0),
		"the tutorial board is plain — no hazards, nothing to smash")
	check(Tutorial.STEPS.size() >= 6, "the walkthrough covers every region of the combat screen")
	var game2 = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game2)
	await process_frame
	game2.show_tutorial()
	await process_frame
	var combat = game2._screen.get_child(0)
	check(combat.tutorial, "the title screen's Tutorial launches with the walkthrough on")
	# The walkthrough waits for the first HERO turn before it opens, so that the
	# bar its cards describe is the bar underneath them. Depending on the
	# surprise roll and initiative that is either this frame or a couple after
	# the goblin has swung, so this waits rather than asserting on frame one.
	for _i in 30:
		if combat._walk != null:
			break
		await process_frame
	check(combat._walk != null, "...and the first step comes up, blocking play")
	check(combat._mode != "deploy", "the guided fight never opens T39's deployment phase")
	# ...over the ordinary nine slots + Swap + End turn, not the deployment bar.
	check(combat._buttons.get_children().size() == combat.SLOTS.size() + 2,
		"the bar under the walkthrough is the fixed one the cards describe (%d buttons)"
		% combat._buttons.get_children().size())
	# Next walks every step and the last one hands the fight over; Skip does it at once.
	for n in Tutorial.STEPS.size():
		check(combat._walk != null, "step %d is up" % (n + 1))
		await process_frame
		_press(combat._walk, "→")
	check(combat._walk == null, "the last Next ends the walkthrough")
	combat._walk_show(0)
	_press(combat._walk, "Skip")
	check(combat._walk == null, "Skip tutorial drops straight into normal play")
	check(combat.cb != null and not combat.cb.is_over(), "the fight underneath was never touched")
	await _tutorial_practice_checks(combat)
	game2.queue_free()

	# T42: the title screen's debug "Random battle" cycles a fixed list rather
	# than rolling one, so consecutive presses are the deterministic sequence.
	var game3 = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game3)
	await process_frame
	var seen: Array = []
	for n in Game.TEST_FIGHTS.size() * 2:
		game3.show_random_battle()
		await process_frame
		var combat3 = game3._screen.get_child(0)
		check(combat3.cb != null and not combat3.cb.is_over(), "random battle #%d starts a live fight" % n)
		seen.append(combat3.spec["theme"])
	check(seen == seen.slice(0, Game.TEST_FIGHTS.size()) + seen.slice(0, Game.TEST_FIGHTS.size()),
		"the sequence repeats exactly, not just eventually reusing themes (%s)" % str(seen))
	game3.queue_free()

	print("test_game_flow: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# T32: the cards that name an action let it be done, through the ordinary
# handlers, while everything else on the screen stays blocked. Runs on the live
# tutorial screen the checks above built, after they have put the walkthrough
# away — every step below is re-opened by hand.
func _tutorial_practice_checks(combat) -> void:
	var acts := {}
	for n in Tutorial.STEPS.size():
		var t: Dictionary = Tutorial.STEPS[n].get("try", {})
		if t.is_empty():
			continue
		acts[String(t.get("act", ""))] = n
		check(t.has("hint") and t.has("done"),
			"step %d's practice carries both its lines" % (n + 1))
	for want in ["move", "inspect", "hover_slot", "open_list"]:
		check(acts.has(want), "the walkthrough invites the player to try '%s'" % want)

	# A card that only reads is deaf everywhere, its own region included.
	combat._walk_show(0)
	await process_frame
	check(not combat._walk.live, "the action-log card blocks the whole screen")
	check(combat._walk._has_point(combat._walk._spot().get_center()),
		"...the region it points at along with the rest")

	# A card with something to do is deaf everywhere BUT its own region.
	combat._walk_show(acts["move"])
	await process_frame
	check(combat._walk.live, "the board card hands the board back")
	check(not combat._walk._has_point(combat._walk._spot().get_center()),
		"...so a click inside the spotlight falls through to it")
	check(combat._walk._has_point(Vector2(2, 2)),
		"...while everything outside the spotlight is still blocked")

	# ...and the move it asks for is the ordinary move: the same handler a
	# click goes through in any other fight, off the real movement budget.
	var hero = combat.cb.current()
	var walked := Vector2i(999, 999)
	for hx in combat.cb.move_field(hero):
		if hx != hero.pos:
			walked = hx
			break
	check(walked != Vector2i(999, 999), "the hero has somewhere to walk")
	var move_left: int = hero.econ["move_left"]
	# Pushed at the viewport rather than handed to board_hex_clicked: what is
	# under test is whether the overlay lets a real click through to the board
	# at all, which is Walk._has_point and nothing the board knows about.
	var at: Vector2 = combat._board.global_position + combat._board._pix(walked)
	combat._walk_show(0)
	await process_frame
	_click(at)
	await process_frame
	check(hero.pos != walked, "a click on the board under a card that only reads goes nowhere")
	combat._walk_show(acts["move"])
	await process_frame
	_click(at)
	await process_frame
	check(hero.pos == walked and hero.econ["move_left"] < move_left,
		"...and the same click under the board card moves them for real")
	check(combat._walk != null and combat._walk.done,
		"...and the card heard about it")
	check(combat._walk.hint != null and combat._walk.hint.text.begins_with("✓"),
		"...and says so on its own line")

	# Hovering a token is the next card's practice; hovering a slot the bar's.
	combat._walk_show(acts["inspect"])
	await process_frame
	combat.board_hex_hovered(hero.pos)
	check(combat._walk.done, "hovering a token is what the stat-card step waits for")
	combat._walk_show(acts["hover_slot"])
	await process_frame
	check(not combat._walk.done, "the action-bar step starts undone")
	combat._buttons.get_child(0).mouse_entered.emit()
	check(combat._walk.done, "...and hovering a badge on the bar finishes it")

	# Keys: the view always, the bar only where a card asks for it, the end of
	# the turn never — _advance holds the goblin while a card is up.
	check(combat._walk_key_ok(KEY_HOME), "the view controls work under every card")
	check(not combat._walk_key_ok(KEY_2), "the bar's keys stay locked on a card that doesn't ask for them")
	check(not combat._walk_key_ok(KEY_SPACE), "no card lets the turn be handed over under it")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var turn: int = combat.cb.turn_idx
	combat._unhandled_key_input(space)
	check(combat.cb.turn_idx == turn, "...Space under a card really does nothing")

	combat._walk_show(acts["open_list"])
	await process_frame
	check(combat._walk_key_ok(KEY_2), "the list card unlocks the number row")
	var opened := false
	for idx in [1, 2, 3, 8]:   # the list slots, in bar order: 2, 3, 4, 9
		combat._press_hotkey(idx)
		await process_frame
		if combat._submenu != "":
			opened = true
			break
	check(opened, "a list slot's key opens its list from under the card")
	check(combat._walk.done, "...which is the practice that card was waiting for")
	combat._walk_show(acts["open_list"] + 1)
	await process_frame
	check(combat._submenu == "", "moving on puts the bar back where ordinary play expects it")
	combat._walk_end()
	check(combat.cb != null and not combat.cb.is_over(), "the fight survived the practice")

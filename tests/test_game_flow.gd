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

func _find(c: Campaign, kind: String) -> int:
	for i in c.options().size():
		if c.options()[i]["kind"] == kind:
			return i
	return -1

func _init() -> void:
	CampaignSave.clear()

	# --- retire: only while picking --------------------------------------
	var c := _campaign()
	check(c.state == "picking", "a fresh run is picking")
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

	print("test_game_flow: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

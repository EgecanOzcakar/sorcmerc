# Dev-only: the encounter objectives, one PNG each, into docs/shots/objectives/
# — the pictures behind PR #137. Needs a display (it renders); not part of
# run_tests.sh.
#   godot --path . --resolution 1400x860 -s tests/shot_objectives.gd
extends SceneTree

const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Quest = preload("res://core/quest.gd")
const Site = preload("res://core/site.gd")
const World = preload("res://core/world.gd")

const OUT := "res://docs/shots/objectives/%s.png"
var game
var _n := 0

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-obj-%d" % randi())
	OS.set_environment("SORCMERC_SEED", "7")

	# --- the fight, one kind at a time ------------------------------------
	var goblins := {"monsters": [{"id": "snik", "count": 3}, {"id": "grull", "count": 1}], "theme": "goblin-camp"}
	var fight = await _fight(goblins.merged({"objective": Objectives.make("hold", {"waves": [[{"id": "snik", "count": 2}]]})}))
	await shot("hold-brief")
	fight.cb._spawn_wave([{"id": "snik", "count": 2}])   # what round 2 looks like
	_redraw(fight)
	await shot("hold-wave")
	fight.queue_free()

	fight = await _fight(goblins.merged({"objective": Objectives.make("rescue")}))
	await shot("rescue-captive")
	var cap = fight.cb.with_status("captive")
	var h = fight.cb.heroes()[0]
	h.pos = Hex.neighbors(cap.pos)[0]
	fight.cb._objective_touch(h)
	_redraw(fight)
	await shot("rescue-freed")
	fight.queue_free()

	fight = await _fight(goblins.merged({"objective": Objectives.make("breakout")}))
	await shot("breakout-road")
	fight.queue_free()

	fight = await _fight(goblins.merged({"objective": Objectives.make("hunt")}))
	await shot("hunt-quarry")
	fight.cb._quarry_escape(fight.cb.with_status("quarry"))
	_redraw(fight)
	await shot("hunt-escaped")
	fight.queue_free()

	fight = await _fight({"monsters": [{"id": "snik", "count": 3}], "theme": "goblin-camp",
		"objective": Objectives.make("escort")})
	await shot("escort-carter")
	fight.queue_free()

	# --- the world: where the objectives come from ------------------------
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	var p = w.world.player()
	var s = w.world.settlements[0]

	# a lair with captives in it, a day's walk from the first town: the board posts a rescue
	var held = null
	for i in 400:
		var l = World.Lair.new("pens-%d" % i, s.position + Vector2(260, 120), "goblinoid")
		if Site.pens_ahead(l):
			held = l
			break
	held.discovered = true
	held.sname = "the Ash Warren"
	w.world.lairs.clear()   # only this one, and no bands to hunt, so the rescue row sits above the fold
	w.world.add_lair(held)
	for q in w.world.parties.duplicate():
		if not q.is_player:
			w.world.parties.erase(q)
	w._open_visit(s)
	w._goto_page("board")
	await shot("board-rescue-job")
	w._close_visit()

	# the approach card names the hunt when a job names the band
	var foe = w.world.add_party(World.RoamingParty.new("bandits", p.position + Vector2(90, 0), "bandit"))
	foe.troops.append({"role": "heavy", "level": 3})
	foe.troops.append({"role": "light", "level": 2})
	Quest.accept(w.party, {"id": "world:hunt_party:%s:0" % foe.id, "kind": "hunt_party", "state": "offered",
		"target_party_id": foe.id, "required": 1, "progress": 0,
		"title": "Hunt down the %s band" % foe.id.capitalize(), "reward": {"gold": 120},
		"chain_faction": foe.faction, "chain_tier": 0})
	w._open_approach(foe)
	await shot("approach-hunt")
	w._close_approach()
	w.world.clock.resume()

	# the spoils page: the objective's row, done and failed
	w._show_spoils({"outcome": "Victory", "xp": 260, "gold": 41, "loot": ["shortbow"], "kills": ["snik"],
		"deaths": [], "objective": {"kind": "hunt", "done": true, "xp": 60}})
	await shot("spoils-hunt-done")
	w._close_spoils()
	w._show_spoils({"outcome": "Victory", "xp": 90, "gold": 12, "loot": [], "kills": ["snik"],
		"deaths": [], "objective": {"kind": "escort", "done": false, "xp": 0}})
	await shot("spoils-escort-failed")
	w._close_spoils()

	# the site: the pens, picked from the room card; then the room itself
	var site = Site.for_lair(held, w.party, w.world)
	var pens_at := 0
	for d in site.rooms.size():
		for r in site.rooms[d]:
			if String(r.get("objective", "")) == "rescue":
				pens_at = d
	w._delve(held)
	# Every entry starts at the mouth (core/site.gd's for_lair), so the shot
	# walks the live site down to the pens' floor rather than the lair.
	w._site.depth = pens_at
	w._site_screen.refresh()
	await settle()
	await shot("site-pens-card")
	var opts: Array = w._site.options()
	for i in opts.size():
		if String(opts[i].get("objective", "")) == "rescue":
			w._on_site_room_chosen(i)
			break
	await settle(2.0)
	await shot("site-pens-fight")
	quit()

# The combat screen with this spec, the way the world would open it.
func _fight(spec: Dictionary):
	var f = load("res://scenes/main.tscn").instantiate()
	f.spec = spec
	root.add_child(f)
	await settle(2.0)
	return f

# After poking the model underneath the screen: the board, the figures, the
# log and the header all read it again.
func _redraw(f) -> void:
	f._board.reset(f.cb)
	f._figures.reset(f.cb)
	f._flush_log()
	f._refresh()

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	_n += 1
	root.get_viewport().get_texture().get_image().save_png(OUT % ("%02d-%s" % [_n, name]))
	print("saved %02d-%s.png" % [_n, name])

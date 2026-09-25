# A finished company ends on both screens of a co-op room (the owner's call,
# 2026-09-25; the build log's "Loose ends"). The whole roster dead after a
# defeat ends the run (core/defeat.gd), and until now only the host's screen
# said so: the host's _end_company autosaves with party.finished written, the
# autosave is what crosses the wire as the guest's full map, and the guest's
# game.gd rebuilt a map from it — the road of a company nobody is left in.
#
# Both halves, the way tests/test_coop_mirror.gd stands in for the link: the
# host's world screen over a stub that keeps what it sends, then the guest's
# front door over a stub holding that very message. The host's half proves the
# record is on the wire; the guest's half proves game.gd shows the closing
# screen from it, and that an ordinary full save still shows the map.
#   godot --headless --path . -s tests/test_coop_finished.gd
extends SceneTree

const Coop = preload("res://core/coop.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# Only what the world screen and game.gd read off a link.
class StubLink extends RefCounted:
	var role := "host"
	var code := "TESTRM"
	var map_latest: Dictionary = {}
	var visit_latest: Dictionary = {}
	var world_pending: Dictionary = {}
	var owners_latest: Dictionary = {}
	var arrivals := 1   # a guest sat down: the host sends the whole map on its first frame
	var sent: Array = []
	func send(m: Dictionary) -> void: sent.append(JSON.parse_string(JSON.stringify(m)))
	func take() -> Array: return []
	func pump() -> void: pass
	func open() -> bool: return true
	func other_here() -> bool: return true
	func close() -> void: pass

func _init() -> void:
	# The host writes its slot as it ends the company; keep that off the real saves.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/coop-finished-%d-%d" % [OS.get_process_id(), randi()])

	# --- the host: the record goes out on the wire ----------------------------
	var host_link := StubLink.new()
	Coop.link = host_link
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var ordinary: Dictionary = {}
	for m in host_link.sent:
		if String(m.get("t", "")) == "world":
			ordinary = m
	check(not ordinary.is_empty(), "the host sends the whole map when the guest is there")
	for ch in main.party.roster:
		ch.dead = true
		main.party.bench(ch.id)
	main._retreat([main.party.roster[0].id])
	check(not main.party.finished.is_empty(), "fixture: the whole roster dead is a finished company")
	host_link.sent.clear()
	main._end_company()
	var fin: Dictionary = {}
	for m in host_link.sent:
		if String(m.get("t", "")) == "world":
			fin = m
	check(not fin.is_empty(), "ending the company sends a full save to the guest")
	var record: Dictionary = fin.get("save", {}).get("finished", {})
	check(not record.is_empty() and (record.get("roll", []) as Array).size() == main.party.roster.size(),
		"...and the save carries the company's record, its whole roll (%d)" % (record.get("roll", []) as Array).size())
	main.queue_free()
	await process_frame

	# --- the guest: the same ending, not a map --------------------------------
	var g = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(g)
	for i in 5:
		await process_frame
	var guest_link := StubLink.new()
	guest_link.role = "guest"
	Coop.link = guest_link
	# An ordinary full save first: the guest watches the host's map, as before.
	guest_link.world_pending = ordinary["save"]
	for i in 10:
		await process_frame
	check(g._guest_on_map and guest_link.world_pending.is_empty(), "an ordinary full save puts the host's map up on the guest")
	# Then the one the host sent as it ended the company.
	guest_link.world_pending = fin["save"]
	for i in 10:
		await process_frame
	check(guest_link.world_pending.is_empty(), "the guest takes the finished save")
	check(g._screen_label == "company-finished page", "...and shows the company-finished page, as the host does (%s)" % g._screen_label)
	check(not g._guest_on_map, "...not the map of a company nobody is left in")
	var head := false
	for l in _labels(g._screen):
		if String(l.text) == "The company is finished":
			head = true
	check(head, "the guest's page reads the same heading the host's does")

	Coop.link = null
	print("test_coop_finished: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out

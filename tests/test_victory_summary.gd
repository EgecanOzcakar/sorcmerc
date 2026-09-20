# Issue #134, second half: what the combat screen says when a fight ends.
#
# The verdict is held behind a tinted wash the player clicks through (#74), and
# `result` — the dictionary the campaign, the road and the site room all wait
# for — is deliberately not filled in until they do. _finish() then read its XP
# and its loot off `result` anyway, which is empty at that moment: "Invalid
# access to key 'xp'", and the rest of _finish() never ran, so the log lost the
# spoils line and the loot line in every played game. Headless and SORCMERC_FAST
# skip the wash and fill `result` immediately, which is exactly why the whole
# suite was blind to it — so this test turns the wash back on.
#   godot --headless --path . -s tests/test_victory_summary.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 20:
		await process_frame
	check(main.cb != null, "a fight is up")

	# The last foe goes down. Nothing else about the fight matters here.
	for c in main.cb.combatants:
		if c.team == "foe":
			c.hp = 0
			c.statuses["dead"] = true
	check(main.cb.is_over() and main.cb.outcome() == "Victory", "the party has won it")

	# A played game, not a headless one: the verdict waits for a click.
	main._fx_on = true
	main._finish()
	check(main._wash != null, "the verdict is held behind the wash")
	check(main.result.is_empty(), "and `result` is not handed back before it is clicked through")

	# append_text() does not write back to .text — the parsed content is the log.
	var log_text: String = main._logbox.get_parsed_text()
	check(log_text.contains("Victory"), "the log says who won")
	check(log_text.contains("XP"), "and what the fight was worth — the line #134 lost")
	check(log_text.contains("gold"), "including the purse")

	main._dismiss_wash()
	check(main._wash == null, "clicking through takes the wash down")
	check(not main.result.is_empty(), "and hands the result to whoever put the fight up")
	check(int(main.result.get("xp", 0)) >= 0 and main.result.has("gold"),
		"with the spoils in it: %s" % str(main.result.keys()))

	main.queue_free()
	await process_frame
	print("test_victory_summary: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

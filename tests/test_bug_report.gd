# The bug reporter: the breadcrumb trail, the report body, the GitHub link and
# the copy on disk — plus the overlay standing up on its own.
#   godot --headless --path . -s tests/test_bug_report.gd
extends SceneTree

const Report = preload("res://core/bug_report.gd")
const Overlay = preload("res://scenes/bugreport/bug_report.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_trail()
	test_trail_dedupe()
	test_flatten()
	test_version_is_declared()
	test_body()
	test_issue_url()
	test_long_report_still_makes_a_link()
	test_save_copy()
	test_submit_never_opens_a_browser_headless()
	test_relay_config()
	test_relay_payload()
	test_relay_answers()
	await test_overlay()
	await test_overlay_without_a_relay()
	print("test_bug_report: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_trail() -> void:
	Report.clear_trail()
	check(Report.trail().is_empty(), "the trail starts empty")
	for i in 40:
		Report.note("thing %d" % i)
	var t := Report.trail()
	check(t.size() == Report.TRAIL_MAX, "the trail is capped at TRAIL_MAX")
	check(t[-1] == "thing 39", "the newest breadcrumb is last")
	check(t[0] == "thing %d" % (40 - Report.TRAIL_MAX), "the oldest fell off the front")
	# trail() hands back a copy: a caller mangling it must not mangle the ring.
	t.clear()
	check(Report.trail().size() == Report.TRAIL_MAX, "trail() returns a copy")
	Report.clear_trail()
	check(Report.trail().is_empty(), "clear_trail empties it")

func test_trail_dedupe() -> void:
	Report.clear_trail()
	Report.note("Goblin misses Vera")
	for i in 5:
		Report.note("Goblin misses Vera")
	check(Report.trail().size() == 1, "a repeated line stays one breadcrumb")
	check(Report.trail()[0] == "Goblin misses Vera  ×6", "...and counts instead")
	Report.note("Vera hits Goblin")
	check(Report.trail().size() == 2, "a different line starts a new breadcrumb")
	Report.note("Goblin misses Vera")
	check(Report.trail().size() == 3, "and the old line does not merge back into it")

func test_flatten() -> void:
	Report.clear_trail()
	Report.note("[color=#fff]Vera[/color] hits [b]Goblin[/b]")
	check(Report.trail()[0] == "Vera hits Goblin", "bbcode comes off a breadcrumb")
	Report.clear_trail()
	Report.note("a\nb\t c   d")
	check(Report.trail()[0] == "a b c d", "newlines and runs of space collapse")
	Report.clear_trail()
	Report.note("   ")
	check(Report.trail().is_empty(), "an empty line is not a breadcrumb")
	Report.clear_trail()
	Report.note("x".repeat(400))
	check(Report.trail()[0].length() == Report.NOTE_MAX, "a long line is clipped")

# Regression: project.godot takes `;` comments, not `#` — a `#` above the key
# makes Godot drop it and every report goes out stamped "dev".
#
# The shape is checked too, because it is a convention and not just a string:
# tools/build_version.sh stamps SemVer into every published build (0.2.1,
# 0.2.2-dev.7+g1a2b3c4) and the placeholder a run from source carries has to be
# the same kind of thing, or "0.1.0-dev" and "v0.1.0" are two conventions and a
# report cannot be compared against a build page.
func test_version_is_declared() -> void:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	check(v != "", "project.godot declares application/config/version")
	check(Report.version() != "dev", "...so no report goes out with the fallback version")
	# SemVer 2.0.0's own grammar, the same one tools/build_version.sh enforces.
	var semver := RegEx.create_from_string(
		r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)" +
		r"(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?" +
		r"(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$")
	check(semver.search(v) != null,
		"application/config/version is SemVer, like every build the release workflow stamps (got %s)" % v)

func test_body() -> void:
	Report.clear_trail()
	Report.note("walked into the inn")
	var b: String = Report.body("The door did nothing.", {"Screen": "open world", "Gold": "12 gp"})
	check("### What happened" in b and "The door did nothing." in b, "the description is in the body")
	check("- **Screen:** open world" in b, "the context is in the body")
	check("- **Gold:** 12 gp" in b, "...every key of it")
	check("### Recent activity" in b and "walked into the inn" in b, "the trail is in the body")
	check("### Build" in b and Report.version() in b, "the build is in the body")
	check("```" in b, "the trail is fenced so its punctuation stays punctuation")

	# A blank context and a blank trail simply drop their sections.
	Report.clear_trail()
	var bare: String = Report.body("just this", {})
	check(not ("### Where" in bare), "no context, no Where section")
	check(not ("### Recent activity" in bare), "no trail, no trail section")
	check("### Build" in bare, "the build is always there")
	# An empty description still produces a filable report rather than a hole.
	check("_(the reporter left this blank)_" in Report.body("", {}), "a blank description says so")
	# A context value that is empty is dropped, not rendered as a blank row.
	check(not ("**Empty:**" in Report.body("x", {"Empty": "   ", "Set": "y"})),
		"an empty context value is dropped")

func test_issue_url() -> void:
	Report.clear_trail()
	var url: String = Report.issue_url("Door does nothing", Report.body("d", {}))
	check(url.begins_with("https://github.com/%s/issues/new?" % Report.REPO), "points at the repo")
	check("labels=bug" in url, "asks for the bug label")
	check("title=Door%20does%20nothing" in url or "title=Door+does+nothing" in url,
		"the title is encoded into the query")
	check("body=" in url, "the body is encoded into the query")
	# The two characters that would end the query early if they went through raw.
	var tricky: String = Report.issue_url("a&b #3", "x&y=z")
	check(not ("&b" in tricky.get_slice("title=", 1).get_slice("&body=", 0)),
		"an ampersand in the title is encoded, not a new query parameter")
	check(not ("#" in tricky), "a hash is encoded, not a fragment")
	# A title longer than TITLE_MAX is a body, not a title.
	var long_title: String = Report.issue_url("t".repeat(400), "x")
	check(long_title.length() < 900, "an over-long title is clipped")

func test_long_report_still_makes_a_link() -> void:
	Report.clear_trail()
	for i in Report.TRAIL_MAX:
		Report.note("a very wordy log line number %d, with plenty of text on it" % i)
	var huge := "please help. ".repeat(4000)
	var url: String = Report.issue_url("Everything is broken", Report.body(huge, {"Screen": "combat"}))
	check(url.length() <= Report.URL_MAX, "a huge report is trimmed to fit the link")
	check("title=" in url and "body=" in url, "...and is still a well-formed link")
	check(Report.TRUNCATED.uri_encode().left(20) in url, "...and says that it was trimmed")
	# The trim must not leave a half-written %XX escape behind.
	check(not url.ends_with("%") and not url.ends_with("%2"), "no dangling escape at the end")

func test_save_copy() -> void:
	Report.clear_trail()
	var path: String = Report.save_copy("A title", "some body")
	check(path.begins_with(Report.DIR), "the copy lands in the reports directory")
	check(FileAccess.file_exists(path), "the copy is really on disk")
	var txt := FileAccess.get_file_as_string(path)
	check(txt.begins_with("# A title"), "the file leads with the title as a heading")
	check("some body" in txt, "and carries the body")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_submit_never_opens_a_browser_headless() -> void:
	Report.clear_trail()
	var r: Dictionary = Report.submit("Headless", "no browser here", {"Screen": "a test"})
	check(not r["opened"], "headless never tries to open a browser")
	check(r["title"] == "Headless", "the title comes back")
	check("no browser here" in r["body"], "the body comes back")
	check(r["url"].begins_with("https://github.com/"), "the url comes back")
	check(FileAccess.file_exists(r["path"]), "the report is written down even so")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(r["path"]))
	# open_browser=false is the same, minus the attempt — what "Copy instead" uses.
	var quiet: Dictionary = Report.submit("Quiet", "x", {}, false)
	check(not quiet["opened"], "open_browser=false does not open anything")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(String(quiet["path"])))

# --- the optional relay (tools/bug-relay/) --------------------------------

func test_relay_config() -> void:
	OS.set_environment("SORCMERC_BUG_RELAY", "")
	# The credential is the thing that must never be committed: the Worker holds
	# the GitHub token and the key is the shared secret in front of it. The URL
	# is a public endpoint, and a checkout with one deployed may bake it in — so
	# the contract is "the door is on exactly when a url resolves", not "there is
	# never a url here".
	check(Report.RELAY_KEY == "", "no relay key is committed")
	check(Report.has_relay() == Report.RELAY_URL.begins_with("http"),
		"out of the box the door follows whatever url is baked in")
	# The env var is the local override — a dev Worker without editing the const.
	OS.set_environment("SORCMERC_BUG_RELAY", "https://relay.test/report")
	check(Report.relay_url() == "https://relay.test/report", "the env var supplies the url")
	check(Report.has_relay(), "...and turns the second door on")
	# Something that is not a URL is not a relay, however it got there.
	OS.set_environment("SORCMERC_BUG_RELAY", "not-a-url")
	check(not Report.has_relay(), "a non-url is not a relay")
	# ...and the one value that means "no relay at all", so the shipped-without-one
	# build is reachable from a checkout that has a url compiled in.
	OS.set_environment("SORCMERC_BUG_RELAY", Report.RELAY_OFF)
	check(Report.relay_url() == "", "the off switch clears the url")
	check(not Report.has_relay(), "...and turns the door off")
	OS.set_environment("SORCMERC_BUG_RELAY", "")
	check(Report.has_relay() == Report.RELAY_URL.begins_with("http"),
		"clearing it falls back to the baked-in url")

func test_relay_payload() -> void:
	var p = JSON.parse_string(Report.relay_payload("A title", "A body"))
	check(p is Dictionary, "the payload is a json object")
	# Exactly the two fields the Worker validates. Anything else here is another
	# thing a stranger can make the Worker parse.
	check(p.keys().size() == 2, "the payload carries only title and body")
	check(p["title"] == "A title" and p["body"] == "A body", "...and carries them intact")
	check(String(JSON.parse_string(Report.relay_payload("t".repeat(400), "b"))["title"]).length()
		<= Report.TITLE_MAX, "an over-long title is clipped before it is sent")

# request_completed's [result, code, headers, body], every shape of it.
func test_relay_answers() -> void:
	var ok := Report._read_relay_answer([HTTPRequest.RESULT_SUCCESS, 201, [],
		'{"ok":true,"url":"https://github.com/o/r/issues/7","number":7}'.to_utf8_buffer()])
	check(ok["ok"], "a 201 with ok:true is a filed report")
	check(ok["url"] == "https://github.com/o/r/issues/7", "...and hands back where it landed")

	# The Worker writes its refusals to be read by a player, so they pass through.
	var limited := Report._read_relay_answer([HTTPRequest.RESULT_SUCCESS, 429, [],
		'{"ok":false,"error":"too many reports from here — try again in a few minutes"}'.to_utf8_buffer()])
	check(not limited["ok"], "a 429 is not a filed report")
	check("too many reports" in String(limited["error"]), "the relay's own message reaches the player")

	# No reply at all: offline, DNS, TLS, or the timeout.
	var dead := Report._read_relay_answer([HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray()])
	check(not dead["ok"], "a failed connection is not a filed report")
	check("Copy instead" in String(dead["error"]), "...and points at the fallback that still works")

	# A reply that is not JSON, or is JSON without the fields, must not crash or
	# be mistaken for success.
	for junk in ["<html>502 Bad Gateway</html>", "", "[]", '{"ok":true}']:
		var r := Report._read_relay_answer([HTTPRequest.RESULT_SUCCESS, 502, [], junk.to_utf8_buffer()])
		check(not r["ok"], "a 502 body of %s is not success" % JSON.stringify(junk))
		check(not String(r["error"]).is_empty(), "...and still says something")
	# A 200 that does not say ok:true is not a filed report either.
	var liar := Report._read_relay_answer([HTTPRequest.RESULT_SUCCESS, 200, [],
		'{"ok":false,"error":"nope"}'.to_utf8_buffer()])
	check(not liar["ok"], "a 200 without ok:true is not a filed report")

# The overlay builds, fills in, and hands back a report — the same path a
# player takes, minus the browser.
func test_overlay() -> void:
	OS.set_environment("SORCMERC_BUG_RELAY", "https://relay.test/report")
	Report.clear_trail()
	Report.note("stepped on the loose flagstone")
	var host := Control.new()
	root.add_child(host)
	var o = Overlay.toggle(host, {"Screen": "combat", "Round": "3"})
	check(o != null, "toggle opens the overlay")
	await process_frame
	check(host.get_node_or_null("BugReportOverlay") != null, "...as a child named for itself")
	check(o._send.disabled, "the send button is off until there is a summary")
	check(o._note.text == Overlay.HINT_NEED_TITLE, "...and the hint says why")
	o._title_edit.text = "The flagstone ate my turn"
	o._refresh_send()
	check(not o._send.disabled, "a summary turns it on")
	check(o._note.text == "", "...and the hint stops claiming otherwise")
	o._desc_edit.text = "Stepped on it, lost the turn."
	# _copy() with no prior submit builds the report itself; headless clipboard
	# is a no-op, but everything up to it is the real path.
	o._copy()
	check("The flagstone ate my turn" in String(o._last["title"]), "the title carries through")
	check("Stepped on it" in String(o._last["body"]), "the description carries through")
	check("**Screen:** combat" in String(o._last["body"]), "the screen's context carries through")
	check("stepped on the loose flagstone" in String(o._last["body"]), "the trail carries through")
	check(FileAccess.file_exists(String(o._last["path"])), "a copy was saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(String(o._last["path"])))

	# The preview shows the player exactly what the report will carry.
	var preview: String = o._attachment_text()
	check("Screen: combat" in preview and "Round: 3" in preview, "the preview shows the context")
	check("stepped on the loose flagstone" in preview, "the preview shows the trail")
	check(Report.version() in preview, "the preview shows the build")

	check(o._relay != null, "a build with a relay offers the second door")
	check(not o._relay.disabled, "...enabled, since there is a summary")

	check(Overlay.toggle(host) == null, "toggling again closes it")
	await process_frame
	host.queue_free()
	OS.set_environment("SORCMERC_BUG_RELAY", "")

# A build with no relay deployed: no button for one.
func test_overlay_without_a_relay() -> void:
	OS.set_environment("SORCMERC_BUG_RELAY", Report.RELAY_OFF)
	var host := Control.new()
	root.add_child(host)
	var o = Overlay.toggle(host, {"Screen": "title"})
	await process_frame
	check(o._relay == null, "no relay, no second-door button")
	# ...and the browser path is untouched by its absence.
	o._title_edit.text = "Still works"
	o._refresh_send()
	check(not o._send.disabled, "the browser path still works without a relay")
	o._copy()
	check("Still works" in String(o._last["title"]), "...and so does copying")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(String(o._last["path"])))
	host.queue_free()
	await process_frame
	OS.set_environment("SORCMERC_BUG_RELAY", "")

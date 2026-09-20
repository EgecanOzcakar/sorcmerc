# The bug reporter's model: everything a report is made of, and the one way out
# of the game with it. No UI — scenes/bugreport/bug_report.gd is the overlay
# that fills this in, and every screen reaches the overlay, not this.
#
# How a report leaves the game
# ----------------------------
# It opens the player's browser on GitHub's own "new issue" form with the title
# and body already filled in (issue_url()), and they press Submit there. That is
# deliberate and it is the whole reason there is no token anywhere in this repo:
#
#   * a GitHub token in a shipped game binary is a token the player owns —
#     the web export is a zip anyone can read, so there is no hiding one;
#   * the issue is filed by the reporter's own account, so they get the replies
#     and can answer a follow-up question;
#   * nothing has to be hosted, rate-limited or spam-filtered.
#
# The cost is that it needs a browser, so submit() ALWAYS writes the report to
# user://bug_reports/ first and hands back the path — on the web export, where a
# popup blocker can eat the tab, or on a machine with no handler for https,
# the player still has the text and the overlay offers it on the clipboard.
#
# The second door
# ---------------
# "Copy this text and paste it somewhere yourself" is a fallback most people
# will not take, so there is an optional one in front of it: post_to_relay()
# sends the report to a small Cloudflare Worker (tools/bug-relay/) that holds a
# repo-scoped token and files the issue. It is strictly the fallback — the issue
# arrives anonymous, with nobody to reply to, which is exactly what the first
# door buys and why it stays first.
#
# relay_url() is empty unless a relay has been deployed and wired up, and the
# overlay simply does not offer the button when it is. See the README in
# tools/bug-relay/ for the whole of it.
#
# The breadcrumb trail
# --------------------
# note() is a ring buffer of the last TRAIL_MAX things that happened, pushed
# from the handful of places the game already narrates itself (screen changes,
# the combat log, a settlement's one-liner). It is the answer to the question
# every bug report needs and almost none volunteer: what were you doing just
# before it went wrong.
extends RefCounted

const REPO := "EgecanOzcakar/sorcmerc"
const LABEL := "bug"              # exists on the repo; GitHub drops one that does not
const TRAIL_MAX := 24             # breadcrumbs kept; the oldest falls off the end
const NOTE_MAX := 160             # one breadcrumb, clipped
const TITLE_MAX := 120            # GitHub's own issue titles run longer, but a
                                  # one-line summary that needs more is a body
const DIR := "user://bug_reports"
# GitHub serves a GET issue form well past this, but proxies, browsers and the
# Windows shell have all historically stopped nearer 8k. Staying under it means
# a long report loses its tail rather than the whole link failing to open — and
# the tail is the diagnostics, which are also in the file on disk.
const URL_MAX := 6000
const TRUNCATED := "\n\n_(truncated to fit the link — the full report is saved on disk)_"

# --- the optional relay (tools/bug-relay/) --------------------------------
#
# .github/workflows/release.yml stamps these from the BUG_RELAY_URL /
# BUG_RELAY_KEY Actions variables at export time, the same way it stamps the
# version, and a deployed relay can also be baked in here — a build with none
# simply has none, and the overlay offers only the browser.
#
# The KEY is the part that must never be committed: the Worker holds the GitHub
# token, and this is the shared secret in front of it. The URL is not a secret —
# it is a public endpoint that only accepts what tools/bug-relay/ validates.
const RELAY_URL := "https://sorcmerc-bug-relay.egecanozcakar.workers.dev"
const RELAY_KEY := ""
const RELAY_TIMEOUT := 20.0    # seconds before we stop waiting and say so

# The value that turns a compiled-in relay off for one run. Without it there is
# no way to see (or test) the no-relay build from a checkout that has a URL
# baked in, since an empty env var means "fall back to the constant".
const RELAY_OFF := "off"

# The env var wins, so a local run or a test can point at a dev Worker
# (`wrangler dev`) without editing the constant, or turn the door off entirely.
static func relay_url() -> String:
	var env := OS.get_environment("SORCMERC_BUG_RELAY")
	if env == RELAY_OFF:
		return ""
	return env if not env.is_empty() else RELAY_URL

static func relay_key() -> String:
	var env := OS.get_environment("SORCMERC_BUG_RELAY_KEY")
	return env if not env.is_empty() else RELAY_KEY

static func has_relay() -> bool:
	return relay_url().begins_with("http")

# What goes on the wire. Kept to the two fields the Worker validates, because
# anything else here is something a stranger can make the Worker parse.
static func relay_payload(title: String, report: String) -> String:
	return JSON.stringify({"title": _clip(title.strip_edges(), TITLE_MAX), "body": report})

static var _trail: Array[String] = []

# --- the breadcrumb trail -------------------------------------------------

# Remember one thing that just happened. Cheap and total-order: called from the
# game's own narration, so it costs a string and an append per logged line.
static func note(line: String) -> void:
	var clean := _flatten(line)
	if clean.is_empty():
		return
	# A repeated line is a count, not TRAIL_MAX copies of "Goblin misses" —
	# a stuck loop is exactly the shape a bug report wants to show.
	if not _trail.is_empty():
		var last := _trail[-1]
		var base := last.get_slice("  ×", 0)
		if base == clean:
			var n := 2 if last == base else int(last.get_slice("  ×", 1)) + 1
			_trail[-1] = "%s  ×%d" % [base, n]
			return
	_trail.append(clean)
	if _trail.size() > TRAIL_MAX:
		_trail = _trail.slice(_trail.size() - TRAIL_MAX)

static func trail() -> Array[String]:
	return _trail.duplicate()

static func clear_trail() -> void:
	_trail.clear()

# BBCode out, newlines and runs of space in, clipped. The combat log is bbcode
# and a settlement line can wrap; a breadcrumb is one flat line either way.
static func _flatten(line: String) -> String:
	var s := line
	while true:
		var open := s.find("[")
		if open < 0:
			break
		var close := s.find("]", open)
		if close < 0:
			break
		s = s.substr(0, open) + s.substr(close + 1)
	s = s.replace("\n", " ").replace("\t", " ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	return _clip(s.strip_edges(), NOTE_MAX)

static func _clip(s: String, n: int) -> String:
	return s if s.length() <= n else s.left(maxi(0, n - 1)).strip_edges() + "…"

# --- what build this is ---------------------------------------------------

# project.godot's application/config/version. release.yml stamps a tag into the
# export; a run from source says "dev", which is itself worth knowing on a report.
static func version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if not v.is_empty() else "dev"

# The facts that decide whether a report is reproducible, and none that identify
# the machine: no username, no hostname, no paths.
static func build_lines() -> Array[String]:
	var out: Array[String] = []
	out.append("Game: %s" % version())
	out.append("Engine: Godot %s" % Engine.get_version_info().get("string", "?"))
	var platform := OS.get_name()
	if OS.has_feature("web"):
		platform += " (web export)"
	elif OS.has_feature("editor"):
		platform += " (from source)"
	out.append("Platform: %s" % platform)
	out.append("Renderer: %s" % ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"))
	# Headless has no adapter and no window — a test run, not a player's.
	if DisplayServer.get_name() != "headless":
		var adapter := RenderingServer.get_video_adapter_name()
		if not adapter.is_empty():
			out.append("Video adapter: %s" % adapter)
		var win := DisplayServer.window_get_size()
		out.append("Window: %d × %d" % [win.x, win.y])
	else:
		out.append("Display: headless")
	out.append("Locale: %s" % OS.get_locale())
	return out

# --- the report itself ----------------------------------------------------

# `context` is whatever the screen knew about itself — an ordered String -> String
# map, "Screen" first by convention (scenes/bugreport/bug_report.gd builds it).
# Nothing here is required: a report filed from the title screen has no state to
# describe and simply does not get that section.
static func body(description: String, context := {}) -> String:
	var parts: Array[String] = []
	var desc := description.strip_edges()
	parts.append("### What happened\n\n" + (desc if not desc.is_empty()
		else "_(the reporter left this blank)_"))

	if not context.is_empty():
		var rows: Array[String] = []
		for k in context:
			var v := String(context[k]).strip_edges()
			if not v.is_empty():
				rows.append("- **%s:** %s" % [String(k), v])
		if not rows.is_empty():
			parts.append("### Where\n\n" + "\n".join(rows))

	var crumbs := trail()
	if not crumbs.is_empty():
		# A fenced block, so a log line full of punctuation cannot turn itself
		# into markdown on the way through.
		parts.append("### Recent activity\n\n```\n%s\n```" % "\n".join(crumbs))

	parts.append("### Build\n\n" + "\n".join(build_lines().map(
		func(l: String) -> String: return "- " + l)))
	parts.append("<sub>Filed from the in-game bug reporter.</sub>")
	return "\n\n".join(parts)

# GitHub's new-issue form, prefilled. Long bodies lose their tail rather than
# the link failing to open — see URL_MAX.
static func issue_url(title: String, report: String) -> String:
	var t := _clip(title.strip_edges(), TITLE_MAX)
	var keep := report.length()
	var url := _compose(t, report)
	# uri_encode() spends 1-3 characters per source character, so there is no
	# character budget to compute up front: shrink by the overshoot and measure
	# again. The guard is belt and braces — it converges in two or three passes.
	var guard := 0
	while url.length() > URL_MAX and keep > 0 and guard < 32:
		keep = maxi(0, keep - maxi(64, int(ceil((url.length() - URL_MAX) / 3.0))))
		url = _compose(t, report.left(keep).strip_edges() + TRUNCATED)
		guard += 1
	return url

static func _compose(title: String, report: String) -> String:
	return "https://github.com/%s/issues/new?labels=%s&title=%s&body=%s" % [
		REPO, LABEL.uri_encode(), title.uri_encode(), report.uri_encode()]

# --- leaving the game with it ---------------------------------------------

# Every report is written down before the browser is asked for anything, so a
# blocked popup or a machine with no https handler costs the player nothing.
# Returns the path written, or "" if even that failed.
static func save_copy(title: String, report: String) -> String:
	if DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(DIR)) != OK and not DirAccess.dir_exists_absolute(DIR):
		return ""
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "")
	var path := "%s/bug-%s.md" % [DIR, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("# %s\n\n%s\n" % [_clip(title.strip_edges(), TITLE_MAX), report])
	f.close()
	return path

# Build the report, write it down, and (unless told not to, or there is nothing
# to open a browser with) send the player to GitHub with it.
#
# Returns  {title, body, url, path, opened}  — the overlay reports the path when
# the browser did not open, and offers the body on the clipboard either way.
# Post a report to the relay and wait for the answer. `host` is any node in the
# tree — HTTPRequest is a Node, and this module is not one.
#
# Returns  {ok, url, error}  — `url` is the filed issue when ok, and `error` is
# something the player can read when not. Never throws, never leaves the
# HTTPRequest behind.
static func post_to_relay(host: Node, title: String, report: String) -> Dictionary:
	if not has_relay():
		return {"ok": false, "url": "", "error": "No relay is configured in this build."}
	var http := HTTPRequest.new()
	http.timeout = RELAY_TIMEOUT
	host.add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var key := relay_key()
	if not key.is_empty():
		headers.append("X-Relay-Key: " + key)
	var started := http.request(relay_url(), headers, HTTPClient.METHOD_POST,
		relay_payload(title, report))
	if started != OK:
		http.queue_free()
		return {"ok": false, "url": "", "error": "Could not start the request (error %d)." % started}
	var answer: Array = await http.request_completed
	http.queue_free()
	return _read_relay_answer(answer)

# request_completed gives [result, code, headers, body]. Split out so a test can
# feed it every shape of failure without a network.
static func _read_relay_answer(answer: Array) -> Dictionary:
	var result: int = int(answer[0])
	var code: int = int(answer[1])
	var body: PackedByteArray = answer[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		# No reply at all: offline, DNS, TLS, or the timeout above.
		return {"ok": false, "url": "",
			"error": "Could not reach the bug relay. Check your connection, or press “Copy instead”."}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var d: Dictionary = parsed if parsed is Dictionary else {}
	if code >= 200 and code < 300 and bool(d.get("ok", false)):
		return {"ok": true, "url": String(d.get("url", "")), "error": ""}
	# The Worker's own message when it sent one — it is written to be read by a
	# player ("too many reports from here"), and it is the only part of the
	# answer worth showing.
	var why := String(d.get("error", ""))
	if why.is_empty():
		why = "The bug relay refused the report (%d)." % code
	return {"ok": false, "url": "", "error": why}

static func submit(title: String, description: String, context := {},
		open_browser := true) -> Dictionary:
	var t := _clip(title.strip_edges(), TITLE_MAX)
	var report := body(description, context)
	var url := issue_url(t, report)
	var path := save_copy(t, report)
	var opened := false
	if open_browser and DisplayServer.get_name() != "headless":
		opened = OS.shell_open(url) == OK
	return {"title": t, "body": report, "url": url, "path": path, "opened": opened}

# The build log's shape (docs/plan/README.md): one entry per file in docs/plan/,
# and docs/expansion-plan.md closed to new entries.
#
# Why it is a test: the log moved out of one file because every PR appended to
# that file's end, and any two open PRs conflicted there. The habit of appending
# is the thing to catch, so a dated section added below the closing heading of
# docs/expansion-plan.md fails here and says where the entry goes instead. The
# folder's files are held to the name and heading tools/plan_log.py reads.
#   godot --headless --path . -s tests/test_plan_entries.gd
extends SceneTree

const LEGACY := "res://docs/expansion-plan.md"
const FOLDER := "res://docs/plan"
const CLOSING := "## The log continues in docs/plan/"

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_legacy_is_closed()
	test_folder_entries()
	print("test_plan_entries: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_legacy_is_closed() -> void:
	var text := FileAccess.get_file_as_string(LEGACY)
	var at := text.find(CLOSING)
	check(at >= 0, "docs/expansion-plan.md ends with its closing section")
	if at < 0:
		return
	var after := text.substr(at + CLOSING.length())
	var dated := RegEx.create_from_string(r"(?m)^## .*\(\d{4}-\d{2}-\d{2}\)\s*$")
	for m in dated.search_all(after):
		check(false, "docs/expansion-plan.md takes no new entries: \"%s\" belongs in its own file, docs/plan/YYYY-MM-DD-slug.md (docs/plan/README.md)" % m.get_string().strip_edges())

func test_folder_entries() -> void:
	var name_re := RegEx.create_from_string(r"^(\d{4}-\d{2}-\d{2})-[a-z0-9-]+\.md$")
	var head_re := RegEx.create_from_string(r"(?m)^## (.+)\((\d{4}-\d{2}-\d{2})\)\s*$")
	var d := DirAccess.open(FOLDER)
	check(d != null, "docs/plan/ exists")
	if d == null:
		return
	var n := 0
	for f in d.get_files():
		if f == "README.md" or not f.ends_with(".md"):
			continue
		n += 1
		var m := name_re.search(f)
		check(m != null, "docs/plan/%s is named YYYY-MM-DD-slug.md (lowercase, hyphens)" % f)
		var text := FileAccess.get_file_as_string(FOLDER + "/" + f)
		var h := head_re.search(text)
		check(h != null, "docs/plan/%s opens with a \"## Title — subtitle (YYYY-MM-DD)\" heading" % f)
		if m != null and h != null:
			check(m.get_string(1) == h.get_string(2), "docs/plan/%s: the file's date matches its heading's (%s)" % [f, h.get_string(2)])
		check(head_re.search_all(text).size() == 1, "docs/plan/%s holds one entry" % f)
		check(text.contains("### Still open"), "docs/plan/%s has a \"### Still open\" section" % f)
	print("  %d entries in docs/plan/" % n)

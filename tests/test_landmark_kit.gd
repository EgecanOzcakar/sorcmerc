extends SceneTree
const LandmarkKit = preload("res://scenes/world/landmark_kit.gd")
const Landmarks = preload("res://core/landmarks.gd")
var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)
func _init() -> void:
	for k in Landmarks.KINDS:
		check(LandmarkKit.has(k), "%s has a diorama" % k)
		var plan: Array = LandmarkKit.plan(k)
		check(plan.size() >= 3, "%s: a plan with a few parts (%d)" % [k, plan.size()])
		check(LandmarkKit.triangles(k) <= 600, "%s: cheap (%d triangles)" % [k, LandmarkKit.triangles(k)])
		var n := LandmarkKit.build(k)
		check(n != null and n.get_child_count() > 0, "%s: builds" % k)
		n.free()
	check(LandmarkKit.plan("stones") == LandmarkKit.plan("stones"), "a plan is stable")
	print("test_landmark_kit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

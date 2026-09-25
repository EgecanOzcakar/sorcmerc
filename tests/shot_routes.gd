# #231 — a picture of core/world_routes.gd's network on each shipped map, for
# docs/spike-route-travel.md. Not a test, and not part of tools/run_tests.sh.
# Headless, because it draws into an Image rather than rendering anything:
#   godot --headless --path . -s tests/shot_routes.gd     # -> docs/shots/route-network-*.png
#
# What it draws, back to front: the four rings (core/regions.gd), the water,
# then the network — roads thick and brown, tracks to the lairs thinner and
# red-brown, paths to the landmarks pale, byways dotted blue, trails an outcome
# opened green, and anything still hidden dashed — and the places on top:
# settlements as white squares (orc holds orange), lairs as red diamonds,
# landmarks as blue dots (green if an outcome put them there), forks as small
# dark dots. No labels: an Image has no text, and the doc names what matters.
extends SceneTree

const WorldRoutes = preload("res://core/world_routes.gd")
const Regions = preload("res://core/regions.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

const SIZE := 900
const PAD := 40.0
const BG := Color(0.13, 0.14, 0.12)
const RING_INK := [Color(0.20, 0.24, 0.17), Color(0.18, 0.20, 0.15), Color(0.17, 0.16, 0.13), Color(0.16, 0.12, 0.12)]
const WATER := Color(0.20, 0.33, 0.47)
const INK := {"road": Color(0.80, 0.63, 0.38), "track": Color(0.72, 0.35, 0.25),
	"path": Color(0.62, 0.62, 0.58), "byway": Color(0.45, 0.62, 0.85), "trail": Color(0.45, 0.85, 0.40)}
const WIDTH := {"road": 5, "track": 3, "path": 2, "byway": 2, "trail": 3}

var _img: Image
var _lo := Vector2.ZERO
var _scale := 1.0

func _init() -> void:
	var scene = load("res://scenes/world/world.tscn").instantiate()
	_shot(scene._small_world(), "small")
	_opened(scene._small_world())
	scene.free()
	_shot(LargeWorld.build(), "large")
	_shot(ProceduralWorld.build(1), "procedural-1")
	quit(0)

func _px(p: Vector2) -> Vector2:
	return (p - _lo) * _scale + Vector2(PAD, PAD)

# The small map after play has opened some of it: two landmarks' leads (a
# trail from each to wherever lead_target() points) and a decision that put a
# new place on the map (scout_spot() + open_place() from Riverhold). Trails
# are green; where one crosses a road it makes a crossroads.
func _opened(w) -> void:
	var net = WorldRoutes.build(w)
	for m in w.landmarks.slice(0, 2):
		var from := WorldRoutes.poi_id("landmark", m.id)
		var to: String = net.lead_target(w, from, "%s|read" % m.id)
		if to != "":
			net.open_route(w, from, to, "landmark:%s" % m.id)
	var town := WorldRoutes.poi_id("settlement", "riverhold")
	var spot: Vector2 = net.scout_spot(w, town, "tracks|follow")
	if spot != Vector2.INF:
		net.open_place(w, "landmark", "smugglers-cave", spot, town, "event:smugglers")
	_shot(w, "small-opened", net)

func _shot(w, name: String, net = null) -> void:
	if net == null:
		net = WorldRoutes.build(w)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in net.nodes:
		var p: Vector2 = net.nodes[id]["position"]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	_lo = lo
	_scale = (SIZE - 2.0 * PAD) / maxf(hi.x - lo.x, hi.y - lo.y)
	_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	_img.fill(BG)
	# Rings, outermost first so each inner disc paints over the one outside it.
	var anchor := _px(Regions.anchor(w))
	var ext: float = Regions.extent(w) * _scale
	for i in range(Regions.BANDS.size() - 2, -1, -1):
		_disc(anchor, float(Regions.BANDS[i]["upto"]) * ext, RING_INK[i])
	for wat in w.waters:
		_disc(_px(wat["position"]), float(wat["radius"]) * _scale, WATER)
	for kind in ["path", "byway", "track", "road", "trail"]:
		for eid in net.edges:
			var e: Dictionary = net.edges[eid]
			if e["kind"] != kind:
				continue
			var pts: PackedVector2Array = e["points"]
			for i in range(1, pts.size()):
				var style := "dot" if kind == "byway" else ("dash" if not e["known"] else "")
				_line(_px(pts[i - 1]), _px(pts[i]), INK[kind], WIDTH[kind], style)
	for id in net.nodes:
		var n: Dictionary = net.nodes[id]
		var p := _px(n["position"])
		match String(n["kind"]):
			"settlement":
				var s = w.settlements.filter(func(x): return x.id == n["ref"])[0]
				var ink := Color(0.95, 0.55, 0.2) if s.faction == "orc" else Color(0.95, 0.93, 0.88)
				_img.fill_rect(Rect2i(int(p.x) - 8, int(p.y) - 8, 17, 17), Color.BLACK)
				_img.fill_rect(Rect2i(int(p.x) - 6, int(p.y) - 6, 13, 13), ink)
			"lair":
				_diamond(p, 9, Color.BLACK)
				_diamond(p, 7, Color(0.85, 0.18, 0.15))
			"landmark":
				_disc(p, 6.0, Color.BLACK)
				# A place an outcome put on the map is green, like its trail.
				_disc(p, 4.5, Color(0.45, 0.85, 0.40) if String(n.get("why", "")) != "" else Color(0.45, 0.65, 0.95))
			"fork":
				_disc(p, 3.0, Color(0.10, 0.08, 0.06))
	var out := "res://docs/shots/route-network-%s.png" % name
	_img.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out, "  ", net.stats())

func _disc(c: Vector2, r: float, ink: Color) -> void:
	var r2 := r * r
	for y in range(maxi(0, int(c.y - r)), mini(SIZE, int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(SIZE, int(c.x + r) + 1)):
			if Vector2(x, y).distance_squared_to(c) <= r2:
				_img.set_pixel(x, y, ink)

func _diamond(c: Vector2, r: int, ink: Color) -> void:
	for dy in range(-r, r + 1):
		var half := r - absi(dy)
		_img.fill_rect(Rect2i(int(c.x) - half, int(c.y) + dy, 2 * half + 1, 1), ink)

# A thick line as a run of squares; anything hidden is broken into dashes, and
# a byway into dots, so hidden reads as hidden without a legend.
func _line(a: Vector2, b: Vector2, ink: Color, width: int, style: String) -> void:
	var span := a.distance_to(b)
	var steps := maxi(1, int(span))
	for i in steps + 1:
		var t := float(i) / steps
		var along := t * span
		if style == "dash" and fmod(along, 12.0) > 7.0:
			continue
		if style == "dot" and fmod(along, 8.0) > 3.0:
			continue
		var p := a.lerp(b, t)
		var h := width / 2
		var rect := Rect2i(int(p.x) - h, int(p.y) - h, width, width).intersection(Rect2i(0, 0, SIZE, SIZE))
		if rect.size.x > 0 and rect.size.y > 0:
			_img.fill_rect(rect, ink)

# A Control that owns a 3D SubViewport and presents it at NATIVE pixel resolution.
#
# WHAT WAS WRONG. Both 3D layers in this game — the combat figures
# (scenes/figures3d.gd) and the overworld (scenes/world/world_view3d.gd) — were
# SubViewportContainers with `stretch = true`. That is the obvious way to lay a 3D
# viewport over a Control, and under this project's display settings it quietly
# renders all 3D at a fraction of the window's resolution.
#
# project.godot runs `window/stretch/mode="canvas_items"` on a 1280x800 base. In that
# mode Controls are laid out in BASE units, not screen pixels: on a 2560x1600 window a
# full-rect Control still reports `size` 1280x800, and the canvas transform scales the
# drawing up on its way to the screen. For 2D that is exactly right — the hex grid and
# the text re-rasterise crisp at native resolution. But a SubViewportContainer with
# `stretch = true` sizes its SubViewport to the container, so the 3D renders at 1280x800
# and is then stretched 2x like a photograph. Measured on the combat screen at
# 2560x1600: a 913x518 board rect, so the figures were drawn from 913x518 pixels into
# 1826x1036 of screen. MSAA does not save it — it anti-aliases inside the small render,
# and the upscale blurs that result anyway.
#
# WHY NOT THE OBVIOUS FIXES, all four of which were tried against 4.7:
#   - `stretch_shrink` is an int >= 1. It only ever lowers the resolution.
#   - Setting `_sub.size` by hand is refused while stretch is on — the engine prints
#     "Can't change the size of a SubViewport with a SubViewportContainer parent that
#     has stretch enabled" and keeps the old size.
#   - `Viewport.scaling_3d_scale` is accepted without complaint and does nothing under
#     the Compatibility renderer this project uses: the render target stays put and the
#     output is pixel-identical.
#   - Scaling the Control by 1/k and sizing it k times larger works, but fights the
#     anchor layout, which puts `size` back and leaves the content drawn at half size.
#
# WHAT THIS DOES INSTEAD. It stops being a SubViewportContainer. A plain Control does
# not present SubViewport children, so the viewport can stay a child without being
# auto-drawn, and this draws the texture itself into Rect2(0, size) — the logical rect,
# in canvas units, which the canvas transform then scales to the screen. The SubViewport
# is sized to `size * k`, k coming from the root viewport's own final transform, so the
# texture is 1:1 with screen pixels by the time it lands there.
#
# WHAT SUBCLASSES CAN RELY ON: `size` keeps its old meaning. It is still the logical
# rect in base units, so every piece of camera arithmetic built on it reads what it read
# before — world_view3d.gd's `_cam.size = size.y / ...` and `_visible_box()`,
# figures3d.gd's px_per_unit(). Only the pixel count behind it changed. A subclass
# creates its own `_sub` (the two want different transparency and different worlds) and
# calls present() once a frame, after it has set `size`.
extends Control

# How far above the base resolution we are willing to render. The whole point is to
# stop throwing pixels away, but the cost is quadratic and this project runs GL
# Compatibility with MSAA 4x: at 1080p the scale is ~1.35 (1.8x the pixels), at 1440p
# ~1.8 (3.2x), and an uncapped 4K window would ask for 2.7 (7.3x) — enough to cost
# frames on an integrated GPU for a sharpness difference nobody can see at that size.
# Two is where the returns flatten; raise it if a 4K machine has headroom to spare.
const MAX_SCALE := 2.0

var _sub: SubViewport
var _presented_at := Vector2i.ZERO    # the size we last sized the viewport to


# Size the viewport to the real pixels this rect covers. Call after setting `size`.
func present() -> void:
	if _sub == null:
		return
	# The root's final transform is the canvas->screen scale, whatever stretch mode and
	# aspect the project is set to; reading it is what keeps this correct on a resize
	# and on a display the game was not started on. Never below 1.0: a window smaller
	# than the base would otherwise render 3D below the size it is drawn at.
	var k: float = clampf(get_viewport().get_final_transform().get_scale().y, 1.0, MAX_SCALE)
	var want := Vector2i((size * k).round())
	if want.x < 1 or want.y < 1:
		return
	if want != _presented_at:
		_sub.size = want
		_presented_at = want
		queue_redraw()                # _draw() bakes `size` into the rect, so re-issue it


func _draw() -> void:
	if _sub != null:
		draw_texture_rect(_sub.get_texture(), Rect2(Vector2.ZERO, size), false)

#!/usr/bin/env python3
"""The action bar's icon set: one framed SVG badge per verb kind, spell school
and bar control.

    python3 tools/gen_action_icons.py           # write everything
    python3 tools/gen_action_icons.py --list    # what would be written
    python3 tools/gen_action_icons.py --check   # fail if any file is stale

Writes gilt-framed, full-colour skill badges under

    assets/icons/actions/*.svg   one per scenes/main.gd action-bar button kind
                                 (combat.gd's BASIC + OFFERABLE verb kinds) plus
                                 the four bar controls: end turn, back, wield
                                 swap, and the generic fallback
    assets/icons/schools/*.svg   one per Icons.SCHOOL_GLYPHS entry — a spell
                                 button is marked by its school, not by a
                                 generic wand (see core/ui_icons.gd)

The keys here ARE the lookup: core/ui_icons.gd builds the path from the verb
`kind` / school id, so adding a verb means adding a recipe below under the same
name and nothing else. tests/test_action_icons.gd fails if the two drift apart.

THE LOOK
Each icon is a badge, not a glyph: a gilt rounded frame, a dark inset panel, a
medallion disc, and a lit silhouette standing on it. Everything is built from
three flat tones per material — a light face, a body, and a shadow — with a
near-black outline holding the shape together. That is a deliberate substitute
for gradients: Godot rasterises SVG through ThorVG, a subset renderer, and flat
fills are the part of the format there is no doubt about. Three tones and an
outline read as modelled anyway at the size this ships at.

Colour is baked in, which is the one thing that changed about how these are
used. The bar draws them as they are (Button's icon_*_color defaults are white,
a no-op multiply) rather than tinting a monochrome master: a spell's school
still colours its badge, but the colour lives in the file. See MATERIALS for
the palette, which is core/ui_icons.gd's own — the same gold, the same steel,
the same eight school colours.

Drawing constraints, all of them learned from the size this renders at:
  * 64x64 viewBox. The frame owns the outer 5 px, the art lives inside a ~40 px
    circle centred on (32, 32), and anything that leaves the disc (a sword tip,
    a shield's shoulders) still stops short of the frame.
  * outlines at 1.2-1.6, never below 1.0 — a hairline vanishes when the bar
    scales the badge down to ~22 px (core/ui_icons.gd's ICON_PX).
  * geometry only: no <style>, no gradients, no filters, no text, no masks.
    A filter that looks right in a browser silently drops out in-game.

No image model was involved in any of this: every path below is coordinates in
source, the same "shapes, not sprites" line the rest of the project's assets are
drawn on. The coordinates were written with a coding assistant, which is the
exempt half of the disclosure — see the provenance table in README.md.
"""

import argparse
import hashlib
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


# --- palette ---------------------------------------------------------------
# core/ui_icons.gd's colours, plus the light/shadow tone of each material. The
# schools are SCHOOL_COLORS verbatim; their two other tones are derived, so
# changing a school colour there is a one-line change here.

INK = "#0d0f16"          # the few genuinely dark details: sockets, a crack
PANEL = "#141118"        # the badge's inset panel — near black, faintly warm
DISC = "#272120"         # the medallion a martial verb stands on
FRAME = "#c9a24a"        # the gilt edge (COL_GOLD, warmed)
FRAME_HI = "#d6b76e"
FRAME_LO = "#4b3a16"


def _rgb(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def mix(a: str, b: str, t: float) -> str:
    """`t` of the way from a to b. Every derived tone in this file comes from here."""
    ca, cb = _rgb(a), _rgb(b)
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(ca, cb))


def tones(base: str) -> tuple:
    """(light face, body, shadow) for a material, the three fills every shape uses."""
    return (mix(base, "#ffffff", 0.45), base, mix(base, INK, 0.45))


STEEL = tones("#c3cbdb")
GOLD = tones("#d0a95c")
LIFE = tones("#5fbf6a")          # COL_PARTY — healing
WOOD = tones("#7a5a3a")

SCHOOL_COLORS = {                # verbatim from core/ui_icons.gd
    "abjuration": "#6f9bd8", "conjuration": "#d98f4a",
    "divination": "#8fd0d8", "enchantment": "#d47fc0",
    "evocation": "#e0643c", "illusion": "#9d8fd8",
    "necromancy": "#79a86b", "transmutation": "#c8a75a",
}


# --- primitives ------------------------------------------------------------
# Everything below draws with these five. `fill` is a flat colour, `stroke` is
# always the same near-black, and nothing anywhere sets an opacity except the
# illusion school's ghost copy — which is the point of it.

def poly(points, fill: str, stroke: str = "auto", sw: float = 1.3, extra: str = "") -> str:
    pts = " ".join("%.1f,%.1f" % (x, y) for x, y in points)
    return '<polygon points="%s" fill="%s"%s%s/>' % (pts, fill, _rim(fill, stroke, sw), extra)


def path(d: str, fill: str, stroke: str = "auto", sw: float = 1.3, extra: str = "") -> str:
    return '<path d="%s" fill="%s"%s%s/>' % (d, fill, _rim(fill, stroke, sw), extra)


def circle(cx: float, cy: float, r: float, fill: str, stroke: str = "auto",
           sw: float = 1.3, extra: str = "") -> str:
    return '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"%s%s/>' % (
        cx, cy, r, fill, _rim(fill, stroke, sw), extra)


def rect(x: float, y: float, w: float, h: float, r: float, fill: str,
         stroke: str = "auto", sw: float = 1.3, extra: str = "") -> str:
    return '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"%s%s/>' % (
        x, y, w, h, r, fill, _rim(fill, stroke, sw), extra)


def stroke_path(d: str, color: str, w: float, cap: str = "round") -> str:
    """A drawn line rather than a filled shape — the spiral and the cracks."""
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" '
            'stroke-linecap="%s" stroke-linejoin="round"/>' % (d, color, w, cap))


def _lum(c: str) -> float:
    r, g, b = _rgb(c)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def _stroke(color: str, w: float) -> str:
    """No keyline unless one is asked for.

    A near-black outline round everything is what makes an icon set read as
    stickers; the reference these are drawn against separates shapes by tone and
    lifts the dark ones with a rim of their own colour. So: a fill dark enough to
    sink into the medallion gets that rim, a light one gets nothing, and the two
    or three places that genuinely want ink (a skull's sockets, a crack) pass it
    explicitly."""
    if color is None:
        return ''
    if color == "auto":
        return ''
    if color == "none" or w <= 0:
        return ''
    return ' stroke="%s" stroke-width="%.1f" stroke-linejoin="round"' % (color, w)


def _rim(fill: str, given: str, w: float) -> str:
    if given != "auto":
        return _stroke(given, w)
    if _lum(fill) >= 0.62:
        return ''
    return _stroke(mix(fill, "#ffffff", 0.22), 1.0)


def group(parts, tx: float = 0.0, ty: float = 0.0, rot: float = 0.0,
          scale: float = 1.0) -> str:
    t = "translate(%.1f %.1f)" % (tx, ty)
    if rot:
        t += " rotate(%.1f)" % rot
    if scale != 1.0:
        t += " scale(%.3f)" % scale
    return '<g transform="%s">%s</g>' % (t, "".join(parts))


def pt(cx: float, cy: float, r: float, deg: float) -> tuple:
    rad = math.radians(deg)
    return cx + r * math.cos(rad), cy + r * math.sin(rad)


def band(cx: float, cy: float, r_out: float, r_in: float, a0: float, a1: float,
         fill: str, stroke: str = INK, sw: float = 1.2) -> str:
    """An annular sector — cupped hands, curved arrows, the portal's rim.

    Angles are SVG's: 0 is +x and they run clockwise, because y is down."""
    large = 1 if abs(a1 - a0) > 180 else 0
    x0, y0 = pt(cx, cy, r_out, a0)
    x1, y1 = pt(cx, cy, r_out, a1)
    x2, y2 = pt(cx, cy, r_in, a1)
    x3, y3 = pt(cx, cy, r_in, a0)
    d = ("M%.1f %.1f A%.1f %.1f 0 %d 1 %.1f %.1f L%.1f %.1f A%.1f %.1f 0 %d 0 %.1f %.1fz"
         % (x0, y0, r_out, r_out, large, x1, y1, x2, y2, r_in, r_in, large, x3, y3))
    return path(d, fill, stroke, sw)


# --- the badge itself ------------------------------------------------------
# Frame, panel, medallion. Every icon is these three and then its art, which is
# what makes a bar of them read as one set however different the silhouettes.

def frame() -> str:
    """Outer line, gilt band, black panel, and a hairline set well inside it.

    Four rounded rects and no more: the band reads as bevelled because the light
    tone sits a pixel high in it, not because it is three bands stacked."""
    return (
        rect(1.6, 1.6, 60.8, 60.8, 12, FRAME_LO, stroke="none")
        + rect(2.4, 2.4, 59.2, 59.2, 11.4, FRAME_HI, stroke="none")
        + rect(2.4, 3.5, 59.2, 58.1, 11.4, FRAME, stroke="none")
        + rect(5.2, 5.2, 53.6, 53.6, 8.8, PANEL, stroke="none")
        + rect(8.4, 8.4, 47.2, 47.2, 6.4, "none", stroke=mix(FRAME, PANEL, 0.52), sw=1.2)
    )


def medallion(base: str = None, ring: str = None) -> str:
    """The disc the art stands on. A school tints its own; the martial verbs
    share the neutral one, which is what separates the two halves of the bar
    at a glance."""
    out = [circle(32, 32, 19.5, base or DISC, stroke="none")]
    if ring:
        out.append(circle(32, 32, 18, "none", stroke=ring, sw=1.1))
        for a in (215, 325, 35, 145):
            x, y = pt(32, 32, 18, a)
            out.append(circle(x, y, 1.4, ring, stroke="none"))
        for a in (250, 290, 70, 110):      # the short radial ticks on the rim
            x0, y0 = pt(32, 32, 15.5, a)
            x1, y1 = pt(32, 32, 18.5, a)
            out.append(stroke_path("M%.1f %.1f L%.1f %.1f" % (x0, y0, x1, y1), ring, 1.0))
    return "".join(out)


def badge(*art: str, disc: str = None, ring: str = None, art_scale: float = 0.92) -> str:
    # The art is drawn on the full 64 grid and then pulled in a little: the
    # reference keeps a clear margin between the silhouette and the gilt, and
    # scaling once here beats trimming 28 sets of coordinates. A school badge
    # comes in further still — its disc carries a ring the art has to clear.
    body = (frame() + medallion(disc, ring)
            + '<g transform="translate(32 32) scale(%.2f) translate(-32 -32)">%s</g>'
            % (art_scale, "".join(art)))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
            'viewBox="0 0 64 64">\n  %s\n</svg>\n' % body)


# --- the things the art is made of -----------------------------------------

def sword(x: float, y: float, rot: float = 0.0, length: float = 52.0,
          w: float = 8.4, steel: tuple = STEEL, hilt: tuple = GOLD) -> str:
    """A sword, point up, centred on (x, y) and rotated `rot` degrees clockwise.

    Parametrised because three icons carry one and hand-placing a crossguard
    square to a blade three times is how they end up not matching. Everything
    below the guard is sized off `length` too — a short sword with a longsword's
    hilt reads as a dagger someone dropped."""
    h = length / 2.0
    grip_len = length * 0.29          # guard, grip and pommel share this
    guard_y = h - grip_len
    guard_t = w * 0.44
    pommel = max(2.4, w * 0.31)
    return group([
        poly([(-w / 2, guard_y), (-w / 2, -h + w * 0.9), (0, -h), (w / 2, -h + w * 0.9),
              (w / 2, guard_y)], steel[1], sw=1.5),
        poly([(-w / 2 + w * 0.18, guard_y - 1.8), (-w / 2 + w * 0.18, -h + w * 1.05),
              (-w * 0.09, -h + w * 0.55), (-w * 0.09, guard_y - 1.8)], steel[0], stroke="none"),
        rect(-w * 1.55, guard_y, w * 3.1, guard_t, guard_t / 2.0, hilt[1], sw=1.3),
        rect(-w * 0.19, guard_y + guard_t, w * 0.38, grip_len - guard_t - pommel * 0.9,
             1.6, hilt[2], sw=1.2),
        circle(0, h - pommel * 0.9, pommel, hilt[1], sw=1.3),
    ], x, y, rot)


def arrow(x: float, y: float, rot: float, length: float, w: float, tone: tuple,
          head: float = 1.9) -> str:
    """A block arrow pointing up in local space: shaft, head, and a lit face."""
    h = length / 2.0
    hw = w * head / 2.0
    hy = -h + w * 1.5
    return group([
        poly([(-hw, hy), (0, -h), (hw, hy), (w / 2, hy), (w / 2, h), (-w / 2, h), (-w / 2, hy)],
             tone[1]),
        poly([(-hw + 1.6, hy - 0.4), (-0.8, -h + 2.4), (-0.8, h - 1.4), (-w / 2 + 1.3, h - 1.4),
              (-w / 2 + 1.3, hy - 0.4)], tone[0], stroke="none"),
    ], x, y, rot)


def chevron(x: float, y: float, rot: float, size: float, thick: float, tone: tuple) -> str:
    """A filled > — the speed marks and the fast-forward."""
    s, t = size, thick
    return group([
        poly([(-s * 0.55, -s), (s * 0.55, 0), (-s * 0.55, s), (-s * 0.55 + t, s),
              (s * 0.55 + t, 0), (-s * 0.55 + t, -s)], tone[1]),
    ], x, y, rot)


def heart(cx: float, cy: float, s: float, tone: tuple) -> str:
    """s is the half-width. Four curves: two lobes over, two flanks down to the
    point. Drawn from the centre out so both halves are the same curve."""
    def P(x, y):
        return cx + x * s, cy + y * s
    d = ("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f "
         "L%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1fz") % (
        *P(0, -0.3),
        *P(0, -0.62), *P(-0.38, -0.98), *P(-0.68, -0.76),
        *P(-1.02, -0.5), *P(-1.0, 0.0), *P(-0.62, 0.36),
        *P(0, 0.98),
        *P(0.62, 0.36), *P(1.0, 0.0), *P(1.02, -0.5),
        *P(0.68, -0.76), *P(0.38, -0.98), *P(0, -0.3))
    return path(d, tone[1], sw=1.4)


def band_head(cx: float, cy: float, r_out: float, r_in: float, a: float, span: float,
              fill: str) -> str:
    """The arrowhead on the end of a band(), tangent to it."""
    return poly([pt(cx, cy, (r_out + r_in) / 2.0, a + span),
                 pt(cx, cy, r_out + 3.6, a), pt(cx, cy, r_in - 3.6, a)], fill, sw=1.3)


def plus(cx: float, cy: float, s: float, t: float, tone: tuple) -> str:
    return poly([(cx - t, cy - s), (cx + t, cy - s), (cx + t, cy - t), (cx + s, cy - t),
                 (cx + s, cy + t), (cx + t, cy + t), (cx + t, cy + s), (cx - t, cy + s),
                 (cx - t, cy + t), (cx - s, cy + t), (cx - s, cy - t), (cx - t, cy - t)],
                tone[1], sw=1.3)


def star(cx: float, cy: float, r_out: float, r_in: float, points: int, tone: tuple,
         phase: float = -90.0, sw: float = 1.3) -> str:
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        pts.append(pt(cx, cy, r, phase + i * 180.0 / points))
    return poly(pts, tone[1], sw=sw)


def diamond(cx: float, cy: float, w: float, h: float, tone: tuple, sw: float = 1.3,
            extra: str = "") -> str:
    return poly([(cx, cy - h), (cx + w, cy), (cx, cy + h), (cx - w, cy)], tone[1],
                sw=sw, extra=extra)


def figure(x: float, y: float, rot: float, tone: tuple) -> str:
    """A person: head, torso, two legs. Used by shove, and nothing else needs
    to be more than that at this size."""
    return group([
        poly([(-4.4, 2), (4.4, 2), (3.2, 13), (-3.2, 13)], tone[0]),
        poly([(-3.4, 12), (-0.2, 12), (2.2, 22), (-1.8, 22)], tone[2]),
        poly([(1.2, 12), (4.2, 12), (8.2, 20), (5.0, 22)], tone[2]),
        circle(0, -3.6, 5.8, tone[1]),
        circle(-1.8, -5.2, 2.2, tone[0], stroke="none"),
    ], x, y, rot)


LIGHT = tones("#eef2fb")
BONE = tones("#e2dcc6")


def hexagon(cx: float, cy: float, r: float, tone_i: str, sw: float = 1.3) -> str:
    return poly([pt(cx, cy, r, -90 + i * 60) for i in range(6)], tone_i, sw=sw)


def school_badge(sid: str, *art: str) -> str:
    base = SCHOOL_COLORS[sid]
    return badge(*art, disc=mix(base, "#0b0a11", 0.74), ring=mix(base, PANEL, 0.52),
                 art_scale=0.80)


# --- the verbs -------------------------------------------------------------
# Keyed by scenes/main.gd's verb `kind` (Icons.VERB_GLYPHS), plus the four
# controls the bar builds itself. One recipe per key, nothing keyed by verb id:
# Shove → prone and Shove → back are one badge, their labels say which.

ACTIONS = {
    # The Attack action: one sword, lit down its near edge.
    "attack": badge(sword(32, 32, 45, length=54, w=8.6)),

    # The bonus-action second swing — the same sword twice, smaller, crossed.
    "offhand_attack": badge(
        sword(37, 33, 42, length=48, w=7),
        sword(27, 33, -42, length=48, w=7),
    ),

    # Force applied, and the figure already going over backwards from it.
    "shove": badge(
        group([figure(0, 0, 0, STEEL)], 44, 28, 20, scale=1.35),
        arrow(16, 32, 90, 24, 11, GOLD),
    ),

    # Grapple (2024: an Unarmed Strike): two figures locked together.
    "grapple": badge(
        group([figure(0, 0, 0, STEEL)], 26, 28, 14, scale=1.25),
        group([figure(0, 0, 0, GOLD)], 38, 28, -14, scale=1.25),
    ),
    # Break free: the held figure, and the hold flying apart either side.
    "escape": badge(
        group([figure(0, 0, 0, STEEL)], 32, 27, 0, scale=1.25),
        arrow(13, 34, -90, 16, 8, GOLD),
        arrow(51, 34, 90, 16, 8, GOLD),
    ),

    # A maul mid-swing, and the object coming apart under it.
    "smash": badge(
        group([
            rect(-3.4, 6, 6.8, 26, 2.8, WOOD[1], sw=1.4),
            rect(-13, -9, 26, 18, 3.5, GOLD[1], sw=1.5),
            rect(-10, -6.4, 20, 5.4, 2.2, GOLD[0], stroke="none"),
        ], 38, 22, 45),
        poly([(10, 48), (16.5, 43), (18.5, 51)], GOLD[1], sw=1.2),
        poly([(21, 54), (26, 49), (28.5, 55)], GOLD[0], sw=1.2),
        poly([(9, 36), (15.5, 37.5), (11.5, 42)], GOLD[1], sw=1.2),
    ),

    # Aid offered: the boon, held up in two cupped hands.
    "help": badge(
        plus(32, 21, 10, 3.4, LIFE),
        band(32, 25, 21, 15.5, 97, 158, GOLD[1]),
        band(32, 25, 21, 15.5, 22, 83, GOLD[1]),
        band(32, 25, 19.5, 17.5, 103, 152, GOLD[0], stroke="none"),
        band(32, 25, 19.5, 17.5, 28, 77, GOLD[0], stroke="none"),
    ),

    # A guard held: the doubled ward, with the old ◈ still legible in it.
    "dodge": badge(
        path("M32 11 L50 32 L32 53 L14 32z M32 19 L43.5 32 L32 45 L20.5 32z",
             STEEL[1], sw=1.4, extra=' fill-rule="evenodd"'),
        diamond(32, 32, 8, 10, GOLD),
        poly([(32, 25), (37, 32), (32, 32)], GOLD[0], stroke="none"),
    ),

    # Speed: two chevrons and the trails behind them.
    "dash": badge(
        chevron(38, 32, 0, 12, 5.5, GOLD),
        chevron(27, 32, 0, 12, 5.5, GOLD),
        rect(10, 20.5, 11, 3.4, 1.7, STEEL[1], stroke="none"),
        rect(7, 30.3, 12, 3.4, 1.7, STEEL[0], stroke="none"),
        rect(10, 40.1, 11, 3.4, 1.7, STEEL[1], stroke="none"),
    ),

    # Backing out of a threatened square, and the blades you back out of.
    "disengage": badge(
        band(32, 32, 20, 16, -58, -26, GOLD[2], sw=1.1),
        band(32, 32, 20, 16, -13, 13, GOLD[2], sw=1.1),
        band(32, 32, 20, 16, 26, 58, GOLD[2], sw=1.1),
        arrow(27, 32, -90, 28, 11, STEEL),
    ),

    # Unseen: the eye, struck out.
    "hide": badge(
        path("M12 32 Q32 13 52 32 Q32 51 12 32z", STEEL[0], sw=1.4),
        circle(32, 32, 7.6, "#2b3040", sw=1.3),
        circle(29.6, 29.6, 2.4, STEEL[0], stroke="none"),
        group([rect(-2.8, -19, 5.6, 38, 2.8, GOLD[1], sw=1.3)], 32, 32, -45),
    ),

    # Your own wounds closed.
    "heal_self": badge(
        heart(32, 31, 18, LIFE),
        plus(32, 28, 8.5, 3, LIGHT),
    ),

    # The same heart, handed to someone else.
    "heal_ally": badge(
        heart(32, 24, 13.5, LIFE),
        plus(32, 21.5, 6.2, 2.2, LIGHT),
        band(32, 23, 23, 17, 94, 156, GOLD[1]),
        band(32, 23, 23, 17, 24, 86, GOLD[1]),
    ),

    # A step up, on yourself.
    "self_buff": badge(
        arrow(32, 28, 0, 32, 13, GOLD),
        rect(17, 47, 30, 5.5, 2.2, GOLD[1]),
        star(48, 15, 6, 2, 4, LIGHT, sw=1.1),
    ),

    # The same step up, granted to the party: two of them.
    "ally_buff": badge(
        arrow(22, 29, 0, 26, 10, GOLD),
        arrow(42, 29, 0, 26, 10, GOLD),
        rect(12, 46, 40, 5.5, 2.2, GOLD[1]),
        star(32, 14, 6, 2, 4, LIGHT, sw=1.1),
    ),

    # Another action, right now: the fast-forward, plus one.
    "grant_action": badge(
        poly([(13, 17), (30, 32), (13, 47)], GOLD[1]),
        poly([(27, 17), (44, 32), (27, 47)], GOLD[1]),
        poly([(16, 22), (25, 30), (16, 38)], GOLD[0], stroke="none"),
        plus(48, 18, 6.5, 2.2, LIGHT),
    ),

    # Something changed about the roll: the reticle, marked.
    "attack_modifier": badge(
        circle(32, 32, 13.5, "none", stroke=INK, sw=6.6),
        circle(32, 32, 13.5, "none", stroke=STEEL[1], sw=4.2),
        rect(30.4, 9, 3.2, 8, 1.6, STEEL[1]),
        rect(30.4, 47, 3.2, 8, 1.6, STEEL[1]),
        rect(9, 30.4, 8, 3.2, 1.6, STEEL[1]),
        rect(47, 30.4, 8, 3.2, 1.6, STEEL[1]),
        circle(32, 32, 4.2, GOLD[1]),
    ),

    # Roll a save or wear it: the bolt against the shield.
    "save_effect": badge(
        path("M32 9 L51 15.5 C51 34 43 47 32 54.5 C21 47 13 34 13 15.5z", GOLD[1], sw=1.5),
        path("M32 14 L46.5 19 C46.5 33 40 43.5 32 49.5 C24 43.5 17.5 33 17.5 19z",
             GOLD[2], stroke="none"),
        poly([(35, 17), (23.5, 34), (30.5, 34), (27.5, 49), (40.5, 28.5), (32.5, 28.5)],
             LIGHT[1], sw=1.3),
    ),

    # T-summon. A second token arriving: the portal the ELEM family already
    # uses for "something comes through", with a figure standing in it. Kept
    # abstract on purpose — one kind covers a wolf and an illusion both.
    "summon": badge(
        band(32, 34, 21, 15, 200, 340, GOLD[1], sw=1.3),
        poly([(25.5, 27), (38.5, 27), (36.5, 48), (27.5, 48)], LIGHT[1], sw=1.3),
        circle(32, 20, 6.2, LIGHT[1], sw=1.2),
    ),

    # --- bar controls ---
    # The turn is spent.
    "end_turn": badge(
        poly([(19, 14), (45, 14), (34.5, 32), (45, 50), (19, 50), (29.5, 32)], STEEL[0], sw=1.4),
        poly([(23.5, 18), (40.5, 18), (32, 28)], GOLD[1], stroke="none"),
        poly([(32, 36), (41.5, 46.5), (22.5, 46.5)], GOLD[1], stroke="none"),
        rect(15, 8.5, 34, 6, 2.4, GOLD[1]),
        rect(15, 49.5, 34, 6, 2.4, GOLD[1]),
    ),

    # Out of a submenu.
    "back": badge(
        arrow(33, 32, -90, 30, 12, STEEL),
    ),

    # Melee ⇄ ranged: the other weapon comes up.
    "swap": badge(
        arrow(32, 23, 90, 28, 9, STEEL),
        arrow(32, 41, -90, 28, 9, GOLD),
    ),

    # Anything the bar offers that has no mark of its own.
    "generic": badge(
        star(32, 32, 19.5, 6.5, 4, GOLD, sw=1.4),
        circle(32, 32, 4.4, GOLD[0], stroke="none"),
        star(49, 16, 5.5, 1.8, 4, LIGHT, sw=1.0),
    ),
}


# --- the eight schools -----------------------------------------------------
# Keyed by Icons.SCHOOL_GLYPHS / SCHOOL_COLORS. Each stands on a disc of its own
# colour, which is what makes a caster's row of spells sort itself by eye.

def _s(sid: str) -> tuple:
    return tones(SCHOOL_COLORS[sid])


SCHOOLS = {
    # A ward that holds: the hex sigil, plated.
    "abjuration": school_badge(
        "abjuration",
        hexagon(32, 32, 19.5, _s("abjuration")[1], sw=1.4),
        hexagon(32, 32, 13.5, _s("abjuration")[2], sw=1.2),
        hexagon(32, 32, 7.5, _s("abjuration")[0], sw=1.1),
    ),

    # Something arrives: a star rising out of the circle that called it.
    "conjuration": school_badge(
        "conjuration",
        '<ellipse cx="32" cy="45" rx="17.5" ry="7.5" fill="none" stroke="%s" stroke-width="7.4"/>' % INK,
        '<ellipse cx="32" cy="45" rx="17.5" ry="7.5" fill="none" stroke="%s" stroke-width="4.6"/>'
        % _s("conjuration")[1],
        star(32, 25, 14, 4.8, 4, _s("conjuration"), sw=1.4),
        star(14, 35, 4.5, 1.6, 4, _s("conjuration"), sw=1.0),
        star(50, 35, 4.5, 1.6, 4, _s("conjuration"), sw=1.0),
    ),

    # Knowing: the scrying orb on its stand.
    "divination": school_badge(
        "divination",
        circle(32, 28, 15.5, _s("divination")[1], sw=1.4),
        band(32, 28, 12, 8, 190, 265, _s("divination")[0], stroke="none"),
        poly([(23, 44), (41, 44), (37.5, 51), (26.5, 51)], GOLD[1], sw=1.2),
        rect(20, 49.5, 24, 5.5, 2.2, GOLD[1]),
    ),

    # A will bent: the spiral.
    "enchantment": school_badge(
        "enchantment",
        stroke_path("M32 13 A19 19 0 1 1 13 32 A13 13 0 1 0 39 32 A7 7 0 1 1 25 32",
                    mix(SCHOOL_COLORS["enchantment"], INK, 0.62), 8.4),
        stroke_path("M32 13 A19 19 0 1 1 13 32 A13 13 0 1 0 39 32 A7 7 0 1 1 25 32",
                    _s("enchantment")[1], 5.2),
        star(49, 15, 6, 2, 4, LIGHT, sw=1.0),
    ),

    # Raw energy, thrown.
    "evocation": school_badge(
        "evocation",
        star(32, 32, 21, 8, 8, _s("evocation"), sw=1.4),
        circle(32, 32, 7, _s("evocation")[0], sw=1.2),
    ),

    # Which one is real: the shape, and the copy that isn't.
    "illusion": school_badge(
        "illusion",
        diamond(39, 32, 12, 15.5, _s("illusion"), sw=1.2, extra=' opacity="0.55"'),
        diamond(26, 32, 12, 15.5, _s("illusion"), sw=1.4),
        poly([(26, 20.5), (33, 32), (26, 32)], _s("illusion")[0], stroke="none"),
    ),

    # The dead put to work.
    "necromancy": school_badge(
        "necromancy",
        path("M32 11 C43 11 51 19.5 51 30 C51 36 48 40.5 45 43.5 L45 48.5 "
             "C45 50.5 43.5 52 41.5 52 L22.5 52 C20.5 52 19 50.5 19 48.5 L19 43.5 "
             "C16 40.5 13 36 13 30 C13 19.5 21 11 32 11z", _s("necromancy")[1], sw=1.4),
        circle(24, 30, 5.8, mix(_s("necromancy")[2], INK, 0.55), sw=1.1),
        circle(40, 30, 5.8, mix(_s("necromancy")[2], INK, 0.55), sw=1.1),
        poly([(32, 36), (35.5, 43), (28.5, 43)], mix(_s("necromancy")[2], INK, 0.55), sw=1.1),
        rect(25.5, 45, 4, 7, 1.2, _s("necromancy")[2], sw=1.0),
        rect(30.5, 45, 4, 7, 1.2, _s("necromancy")[2], sw=1.0),
        rect(35.5, 45, 4, 7, 1.2, _s("necromancy")[2], sw=1.0),
    ),

    # One thing made another: the turning ring.
    "transmutation": school_badge(
        "transmutation",
        band(32, 32, 18, 12.5, 200, 330, _s("transmutation")[0]),
        band_head(32, 32, 18, 12.5, 330, 26, _s("transmutation")[0]),
        band(32, 32, 18, 12.5, 20, 150, _s("transmutation")[0]),
        band_head(32, 32, 18, 12.5, 150, 26, _s("transmutation")[0]),
        hexagon(32, 32, 6.5, mix(SCHOOL_COLORS["transmutation"], "#ffffff", 0.7), sw=1.1),
    ),
}



# --- the elements ----------------------------------------------------------
# A skill's motif is coloured by what it DOES, not by its school: the school is
# already the disc under it. Two Evocation cantrips that throw fire and frost
# should not be the same badge in two shades of the same red.

ELEM = {
    "fire": "#e0643c", "cold": "#7fc4dd", "lightning": "#f0cf55", "acid": "#a8c740",
    "poison": "#79a86b", "necrotic": "#9d7fd8", "radiant": "#f2dfa6", "psychic": "#d47fc0",
    "force": "#b9c6e6", "thunder": "#c8a75a", "life": "#5fbf6a", "steel": "#c3cbdb",
    "gold": "#d0a95c", "shadow": "#7a6f96", "nature": "#8fbf5a", "stone": "#a39c8e",
}


def E(name: str) -> tuple:
    return tones(ELEM[name])


# --- motifs ----------------------------------------------------------------
# One builder per shape family, each drawing into a ~30-unit box centred on
# (32, 32) so any of them can stand on any disc. They are parametrised rather
# than one-per-skill because that is what makes 90 badges a registry instead of
# 90 drawings: Fire Bolt and Ray of Frost are the same dart in two elements,
# Scorching Ray is three of it.

def flame(t: tuple, cx: float = 32, cy: float = 33, s: float = 1.0) -> str:
    """A tongue of fire. The inner flame is the light tone, so it reads lit."""
    def P(x, y):
        return cx + x * s, cy + y * s
    return (path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f "
                 "C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
                     *P(0, -16), *P(7, -6), *P(11, -1), *P(11, 5),
                     *P(11, 13), *P(5, 17), *P(0, 17),
                     *P(-11, 17), *P(-11, 5), *P(-11, 1)), t[1], sw=1.3)
            + path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
                *P(0, -5), *P(5, 1), *P(5.5, 5), *P(5.5, 9),
                *P(4, 13), *P(-5.5, 13), *P(-5.5, 6)), t[0], stroke="none"))


def dart(t: tuple, rot: float = -45, n: int = 1, s: float = 1.0) -> str:
    """A bolt of something thrown: a tapered dart with a trailing tail. `n` of
    them fan out — one is Fire Bolt, three is Scorching Ray."""
    out = []
    spread = 13.0
    for i in range(n):
        off = (i - (n - 1) / 2.0) * spread
        out.append(group([
            poly([(0, -15 * s), (4.2 * s, -4 * s), (0, 9 * s), (-4.2 * s, -4 * s)], t[1], sw=1.2),
            poly([(0, -13 * s), (2.2 * s, -4 * s), (0, 5 * s)], t[0], stroke="none"),
            poly([(0, 9 * s), (2.4 * s, 15 * s), (-2.4 * s, 15 * s)], t[2], sw=1.0),
        ], 32 + off * 0.62, 32 + off * 0.28, rot))
    return "".join(out)


def beam(t: tuple, rot: float = -35, s: float = 1.0) -> str:
    """A held beam rather than a thrown bolt: a widening shaft from one corner."""
    return group([
        poly([(-3.5 * s, -18 * s), (3.5 * s, -18 * s), (7 * s, 18 * s), (-7 * s, 18 * s)], t[1], sw=1.2),
        poly([(-1.4 * s, -17 * s), (1.4 * s, -17 * s), (3 * s, 16 * s), (-3 * s, 16 * s)], t[0], stroke="none"),
    ], 32, 32, rot)


def cone_burst(t: tuple, rot: float = 0.0, s: float = 1.0) -> str:
    """A cone leaving the caster: Burning Hands, a breath weapon, Cone of Cold."""
    return group([
        poly([(0, -17 * s), (14 * s, 12 * s), (0, 17 * s), (-14 * s, 12 * s)], t[2], sw=1.1),
        poly([(0, -14 * s), (9 * s, 10 * s), (0, 14 * s), (-9 * s, 10 * s)], t[1], stroke="none"),
        poly([(0, -9 * s), (4.5 * s, 8 * s), (0, 10 * s), (-4.5 * s, 8 * s)], t[0], stroke="none"),
    ], 32, 32, rot)


def orb(t: tuple, s: float = 1.0, ring: bool = False) -> str:
    out = [circle(32, 32, 13 * s, t[1], sw=1.3),
           band(32, 32, 10 * s, 6.5 * s, 185, 260, t[0], stroke="none")]
    if ring:
        out.append(circle(32, 32, 16.5 * s, "none", stroke=t[2], sw=1.6))
    return "".join(out)


def droplets(t: tuple, n: int = 3, s: float = 1.0) -> str:
    """Acid, poison, venom — a fan of drops."""
    out = []
    for i in range(n):
        a = -60 + i * (120.0 / max(1, n - 1)) if n > 1 else 0
        x, y = pt(32, 30, 12 * s, a + 90)
        r = 5.2 * s if i == n // 2 else 4.2 * s
        out.append(path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
            x, y - r * 1.9, x + r, y - r * 0.2, x + r, y + r * 0.1, x, y + r * 1.2,
            x - r, y + r * 0.1, x - r, y - r * 0.2, x, y - r * 1.9), t[1], sw=1.1))
        out.append(circle(x - r * 0.3, y - r * 0.1, r * 0.32, t[0], stroke="none"))
    return "".join(out)


def snowflake(t: tuple, s: float = 1.0) -> str:
    out = []
    for a in (90, 150, 210, 270, 330, 30):
        x0, y0 = pt(32, 32, 3 * s, a)
        x1, y1 = pt(32, 32, 16 * s, a)
        out.append(stroke_path("M%.1f %.1f L%.1f %.1f" % (x0, y0, x1, y1), t[1], 3.0 * s))
        bx, by = pt(32, 32, 11 * s, a)
        for da in (-38, 38):
            tx, ty = pt(bx, by, 5.5 * s, a + da)
            out.append(stroke_path("M%.1f %.1f L%.1f %.1f" % (bx, by, tx, ty), t[1], 2.2 * s))
    out.append(circle(32, 32, 3.4 * s, t[0], stroke="none"))
    return "".join(out)


def bolt(t: tuple, s: float = 1.0) -> str:
    """The lightning zigzag."""
    def P(x, y):
        return 32 + x * s, 32 + y * s
    return (poly([P(4, -18), P(-9, 2), P(-1, 2), P(-5, 18), P(9, -3), P(1, -3)], t[1], sw=1.3)
            + poly([P(2.5, -14), P(-5, 1), P(-1.5, 1)], t[0], stroke="none"))


def skull(t: tuple, s: float = 1.0, cy: float = 31) -> str:
    """A cranium and a jaw, from computed points — the first version of this was
    one format string with a %.1f count nobody could check by eye."""
    dark = mix(t[2], INK, 0.55)
    def P(x, y):
        return "%.1f %.1f" % (32 + x * s, cy + y * s)
    d = ("M" + P(0, -15)
         + " C" + P(8.5, -15) + " " + P(14, -8.5) + " " + P(14, 0)
         + " C" + P(14, 4.5) + " " + P(11.5, 7) + " " + P(9.5, 9)
         + " L" + P(9.5, 13)
         + " C" + P(9.5, 15) + " " + P(8, 15.5) + " " + P(6.5, 15.5)
         + " L" + P(-6.5, 15.5)
         + " C" + P(-8, 15.5) + " " + P(-9.5, 15) + " " + P(-9.5, 13)
         + " L" + P(-9.5, 9)
         + " C" + P(-11.5, 7) + " " + P(-14, 4.5) + " " + P(-14, 0)
         + " C" + P(-14, -8.5) + " " + P(-8.5, -15) + " " + P(0, -15) + "z")
    return (path(d, t[1], sw=1.3)
            + circle(32 - 5.4 * s, cy - 2 * s, 4.0 * s, dark, sw=1.0)
            + circle(32 + 5.4 * s, cy - 2 * s, 4.0 * s, dark, sw=1.0)
            + poly([(32, cy + 2.5 * s), (32 + 2.6 * s, cy + 7 * s), (32 - 2.6 * s, cy + 7 * s)],
                   dark, sw=1.0))


def hand(t: tuple, rot: float = 0.0, s: float = 1.0, claw: bool = False) -> str:
    """A palm with three fingers — a touch spell, a grasp, a rebuke."""
    tip = t[0] if not claw else mix(t[0], "#ffffff", 0.4)
    parts = [
        path("M%.1f %.1f L%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f L%.1f %.1f z" % (
            32 - 9 * s, 32 + 2 * s, 32 - 9 * s, 32 + 8 * s,
            32 - 9 * s, 32 + 15 * s, 32 + 9 * s, 32 + 15 * s,
            32 + 9 * s, 32 + 8 * s, 32 + 9 * s, 32 + 2 * s), t[1], sw=1.3),
    ]
    for i, dx in enumerate((-6.2, 0, 6.2)):
        h = 13 if i == 1 else 10
        parts.append(rect(32 + dx * s - 2.6 * s, 32 - h * s, 5.2 * s, (h + 4) * s,
                          2.6 * s, t[1] if not claw else t[2], sw=1.2))

        if claw:
            parts.append(poly([(32 + dx * s - 2.4 * s, 32 - h * s),
                               (32 + dx * s + (6.5 if dx < 0 else -6.5 if dx > 0 else 0),
                                32 - (h + 8) * s),
                               (32 + dx * s + 2.4 * s, 32 - h * s)], tip, sw=1.0))
    return group(parts, 0, 0, 0) if rot == 0 else group(parts, 0, 0, 0)


def eye(t: tuple, s: float = 1.0, pupil: str = None) -> str:
    return (path("M%.1f 32 Q32 %.1f %.1f 32 Q32 %.1f %.1f 32z" % (
        32 - 17 * s, 32 - 12 * s, 32 + 17 * s, 32 + 12 * s, 32 - 17 * s), t[0], sw=1.3)
        + circle(32, 32, 6.6 * s, pupil or t[2], sw=1.2)
        + circle(32 - 2.2 * s, 32 - 2.2 * s, 2.1 * s, "#ffffff", stroke="none"))


def person(t: tuple, pose: str = "stand", s: float = 1.0) -> str:
    """A person, in the pose the skill leaves them in. Every pose keeps the
    head/torso/legs silhouette so it still reads as a body at 22 px."""
    if pose == "prone":
        return (rect(13, 45, 38, 5, 2.5, mix(t[2], INK, 0.35), sw=1.1)
                + circle(20, 37, 6.4 * s, t[1], sw=1.2)
                + poly([(26, 32), (43, 36), (42, 44), (25, 43)], t[1], sw=1.2)
                + poly([(41, 37), (52, 33), (54, 39), (43, 44)], t[2], sw=1.1))
    if pose == "held":
        bind = mix(t[2], INK, 0.25)
        return (circle(32, 17, 6.6 * s, t[1], sw=1.2)
                + poly([(25, 24), (39, 24), (37, 48), (27, 48)], t[1], sw=1.2)
                + rect(21, 28.6, 22, 3.0, 1.5, bind, sw=1.0)
                + rect(21, 36.6, 22, 3.0, 1.5, bind, sw=1.0)
                + circle(21, 30, 3.4, "none", stroke=bind, sw=2.2)
                + circle(43, 38, 3.4, "none", stroke=bind, sw=2.2))
    if pose == "sleep":
        return (circle(24, 34, 6.0 * s, t[1], sw=1.2)
                + rect(28, 38, 18, 6, 3, t[1], sw=1.2))
    return (circle(32, 18, 6.2 * s, t[1], sw=1.2)
            + poly([(25.5, 25), (38.5, 25), (36.5, 47), (27.5, 47)], t[1], sw=1.2))


def mask(t: tuple, mood: str = "laugh", s: float = 1.0) -> str:
    """A face — the enchantment/illusion family's shorthand for a mind touched.
    Big dark eyes and a mouth with a shape, because a line and two dots turn
    into a blob the moment the bar scales this down."""
    dark = mix(t[2], INK, 0.62)
    def P(x, y):
        return 32 + x * s, 32 + y * s
    out = [path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f "
                "C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
                    *P(0, -17), *P(11, -17), *P(15, -11), *P(15, -2),
                    *P(15, 8), *P(8, 17), *P(0, 17),
                    *P(-8, 17), *P(-15, 8), *P(-15, -2)), t[1], sw=1.3),
           path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
               *P(-13, -6), *P(-9, -13), *P(-1, -13), *P(-2, -6)), t[0], stroke="none")]
    for dx in (-6.4, 6.4):
        out.append(path("M%.1f %.1f a%.1f %.1f 0 1 0 0.1 0z" % (
            32 + dx * s, 32 - 6 * s, 3.4 * s, 4.2 * s), dark, stroke="none"))
    if mood == "laugh":
        out.append(path("M%.1f %.1f Q%.1f %.1f %.1f %.1f L%.1f %.1f Q%.1f %.1f %.1f %.1fz" % (
            *P(-8, 3), *P(0, 13), *P(8, 3), *P(6, 3), *P(0, 8), *P(-6, 3)), dark, sw=1.0))
    elif mood == "scream":
        out.append(path("M%.1f %.1f a%.1f %.1f 0 1 0 0.1 0z" % (
            32, 32 + 4 * s, 4.6 * s, 6.2 * s), dark, sw=1.0))
    else:
        out.append(rect(32 - 7 * s, 32 + 4 * s, 14 * s, 2.8 * s, 1.4 * s, dark, stroke="none"))
    return "".join(out)


def note(t: tuple, s: float = 1.0) -> str:
    return (rect(32 + 2 * s, 32 - 16 * s, 3.4 * s, 24 * s, 1.6 * s, t[1], sw=1.2)
            + poly([(32 + 5.4 * s, 32 - 16 * s), (32 + 14 * s, 32 - 12 * s),
                    (32 + 14 * s, 32 - 5 * s), (32 + 5.4 * s, 32 - 9 * s)], t[1], sw=1.2)
            + circle(32 - 2.5 * s, 32 + 8 * s, 6.2 * s, t[0], sw=1.3))


def fist(t: tuple, s: float = 1.0) -> str:
    """A closed fist, knuckles up. The knuckles are drawn in the body tone and
    the block over them — they are the silhouette, not stripes on it, which is
    the whole difference between a fist and a stack of bars at 22 px."""
    out = []
    for dx in (-8.4, -2.8, 2.8, 8.4):
        out.append(circle(32 + dx * s, 32 - 7 * s, 3.6 * s, t[1], stroke="none"))
    out.append(rect(32 - 12 * s, 32 - 7 * s, 24 * s, 15 * s, 3 * s, t[1], sw=1.3))
    out.append(poly([(32 - 12 * s, 32 - 4 * s), (32 - 5 * s, 32 - 4 * s),
                     (32 - 5 * s, 32 + 7 * s), (32 - 12 * s, 32 + 7 * s)], t[0], stroke="none"))
    out.append(path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f L%.1f %.1f "
                    "C%.1f %.1f %.1f %.1f %.1f %.1fz" % (
                        32 - 12 * s, 32 + 1 * s,
                        32 - 17 * s, 32 + 1 * s, 32 - 17 * s, 32 + 8 * s, 32 - 11 * s, 32 + 8 * s,
                        32 - 4 * s, 32 + 8 * s,
                        32 - 4 * s, 32 + 4 * s, 32 - 8 * s, 32 + 1 * s, 32 - 12 * s, 32 + 1 * s),
                    t[2], sw=1.2))
    out.append(rect(32 - 9 * s, 32 + 8 * s, 18 * s, 7 * s, 3 * s, t[2], sw=1.2))
    return "".join(out)


def fangs(t: tuple, s: float = 1.0) -> str:
    return (band(32, 30, 15 * s, 9 * s, 200, 340, t[1])
            + poly([(32 - 8 * s, 32 - 2 * s), (32 - 4 * s, 32 + 12 * s), (32 - 1 * s, 32 - 2 * s)],
                   t[0], sw=1.0)
            + poly([(32 + 1 * s, 32 - 2 * s), (32 + 4 * s, 32 + 12 * s), (32 + 8 * s, 32 - 2 * s)],
                   t[0], sw=1.0))


def web(t: tuple, s: float = 1.0) -> str:
    out = []
    for a in range(0, 360, 45):
        x, y = pt(32, 32, 17 * s, a)
        out.append(stroke_path("M32 32 L%.1f %.1f" % (x, y), t[1], 1.8))
    for r in (7 * s, 12 * s, 17 * s):
        pts = [pt(32, 32, r, a) for a in range(0, 405, 45)]
        d = "M%.1f %.1f " % pts[0] + " ".join("L%.1f %.1f" % p for p in pts[1:])
        out.append(stroke_path(d, t[0] if r == 12 * s else t[1], 1.6))
    return "".join(out)


def tentacles(t: tuple, s: float = 1.0) -> str:
    out = []
    for i, (x, h) in enumerate(((20, 12), (27, 18), (37, 18), (44, 12))):
        out.append(stroke_path("M%.1f 48 C%.1f %.1f %.1f %.1f %.1f %.1f" % (
            x, x, 48 - h, x + (4 if i % 2 else -4), 40 - h, x + (9 if i % 2 else -9), 34 - h),
            t[1] if i % 2 else t[2], 4.6 - 0.4 * i))
    out.append(rect(16, 46, 32, 6, 3, t[2], sw=1.1))
    return "".join(out)


def cloud(t: tuple, s: float = 1.0) -> str:
    return (path("M%.1f %.1f a9 9 0 0 1 17 -6 a8 8 0 0 1 14 6 a7 7 0 0 1 -2 13 h-27 "
                 "a7 7 0 0 1 -2 -13z" % (32 - 15 * s, 32 + 2 * s), t[1], sw=1.3)
            + circle(26, 30, 4.2, t[0], stroke="none")
            + circle(37, 32, 3.2, t[0], stroke="none"))


def swarm(t: tuple, s: float = 1.0) -> str:
    out = []
    spots = [(24, 22, 3.2), (33, 18, 2.6), (41, 25, 3.0), (20, 32, 2.6), (30, 30, 3.6),
             (42, 36, 2.8), (25, 42, 3.0), (35, 44, 2.4), (44, 44, 2.0), (16, 42, 2.0)]
    for i, (x, y, r) in enumerate(spots):
        out.append(circle(x, y, r * s, t[1] if i % 2 else t[0], sw=1.0))
    return "".join(out)


def chain(t: tuple, broken: bool = False, s: float = 1.0) -> str:
    out = []
    links = [(20, 20), (28, 27), (44, 45), (36, 38)] if broken else [(20, 20), (27, 27), (37, 37), (44, 44)]
    for i, (x, y) in enumerate(links):
        out.append(circle(x, y, 6.2 * s, "none", stroke=t[1], sw=3.4))
    if broken:
        out.append(stroke_path("M30 30 L34 26", t[0], 2.0))
        out.append(stroke_path("M34 38 L38 34", t[0], 2.0))
    return "".join(out)


def spiral(t: tuple, s: float = 1.0) -> str:
    d = "M32 15 A17 17 0 1 1 15 32 A12 12 0 1 0 39 32 A6 6 0 1 1 26 32"
    return (stroke_path(d, mix(t[1], INK, 0.55), 7.6) + stroke_path(d, t[1], 4.6))


def crescent(t: tuple, s: float = 1.0) -> str:
    return path("M%.1f %.1f A16 16 0 1 0 %.1f %.1f A12.5 12.5 0 1 1 %.1f %.1fz" % (
        38, 17, 38, 47, 38, 17), t[1], sw=1.3)


def banner(t: tuple, s: float = 1.0) -> str:
    return (rect(30, 14, 4, 34, 2, t[2], sw=1.2)
            + poly([(34, 16), (50, 20), (50, 34), (34, 30)], t[1], sw=1.3)
            + poly([(34, 19), (46, 22), (46, 27), (34, 24)], t[0], stroke="none")
            + circle(32, 13, 3.2, t[0], sw=1.1))


def reticle(t: tuple, s: float = 1.0) -> str:
    return (circle(32, 32, 13 * s, "none", stroke=t[1], sw=3.6)
            + circle(32, 32, 4 * s, t[0], sw=1.1)
            + stroke_path("M32 13 V19", t[1], 2.6) + stroke_path("M32 45 V51", t[1], 2.6)
            + stroke_path("M13 32 H19", t[1], 2.6) + stroke_path("M45 32 H51", t[1], 2.6))


def brain(t: tuple, s: float = 1.0) -> str:
    """Two lobes, a seam down the middle, a fold in each — the seam is what
    makes it a brain rather than a cloud."""
    out = [path("M32 %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f 32 %.1f "
                "C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f 32 %.1fz" % (
                    32 - 15 * s,
                    32 - 8 * s, 32 - 16 * s, 32 - 16 * s, 32 - 9 * s, 32 - 15 * s, 32 - 1 * s,
                    32 - 15 * s, 32 + 9 * s, 32 - 7 * s, 32 + 15 * s, 32 + 14 * s,
                    32 + 7 * s, 32 + 15 * s, 32 + 15 * s, 32 + 9 * s, 32 + 15 * s, 32 - 1 * s,
                    32 + 16 * s, 32 - 9 * s, 32 + 8 * s, 32 - 16 * s, 32 - 15 * s), t[1], sw=1.3),
           stroke_path("M32 %.1f V%.1f" % (32 - 14 * s, 32 + 13 * s), mix(t[2], INK, 0.3), 2.2),
           stroke_path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f" % (
               32 - 10 * s, 32 - 8 * s, 32 - 4 * s, 32 - 4 * s, 32 - 10 * s, 32 + 1 * s,
               32 - 5 * s, 32 + 7 * s), t[0], 2.0),
           stroke_path("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f" % (
               32 + 10 * s, 32 - 8 * s, 32 + 4 * s, 32 - 4 * s, 32 + 10 * s, 32 + 1 * s,
               32 + 5 * s, 32 + 7 * s), t[0], 2.0)]
    return "".join(out)


def puppet(t: tuple, s: float = 1.0) -> str:
    return (stroke_path("M22 12 L26 26", t[2], 1.6) + stroke_path("M42 12 L38 26", t[2], 1.6)
            + circle(32, 30, 7.5 * s, t[1], sw=1.3)
            + poly([(26, 37), (38, 37), (36, 50), (28, 50)], t[1], sw=1.2)
            + circle(29.5, 28, 1.8, mix(t[2], INK, 0.5), stroke="none")
            + circle(34.5, 28, 1.8, mix(t[2], INK, 0.5), stroke="none"))


def scroll(t: tuple, s: float = 1.0) -> str:
    return (rect(18, 16, 28, 32, 3, t[1], sw=1.3)
            + rect(15, 13, 34, 6, 3, t[2], sw=1.2)
            + rect(15, 45, 34, 6, 3, t[2], sw=1.2)
            + rect(23, 24, 18, 2.6, 1.3, t[0], stroke="none")
            + rect(23, 30, 18, 2.6, 1.3, t[0], stroke="none")
            + rect(23, 36, 11, 2.6, 1.3, t[0], stroke="none"))


def vines(t: tuple, s: float = 1.0) -> str:
    out = [stroke_path("M16 50 C20 36 30 32 32 20 C34 12 40 12 44 16", t[1], 4.0)]
    for i, (x, y, a) in enumerate(((22, 40, -40), (29, 30, 40), (34, 20, -30), (41, 15, 30))):
        out.append(poly([(x, y), (x + 7 * (1 if a > 0 else -1), y - 4), (x, y - 7)], t[0], sw=1.0))
    return "".join(out)


def slashes(t: tuple, n: int = 3, s: float = 1.0) -> str:
    out = []
    for i in range(n):
        off = (i - (n - 1) / 2.0) * 9
        out.append(poly([(20 + off, 46), (28 + off, 16), (32 + off, 18), (24 + off, 47)],
                        t[0] if i == n // 2 else t[1], sw=1.1))
    return "".join(out)


def waves(t: tuple, s: float = 1.0) -> str:
    out = []
    for i, r in enumerate((8, 13, 18)):
        out.append(band(20, 32, r + 2.2, r - 0.6, -52, 52, t[0] if i == 1 else t[1], sw=1.0))
    out.append(circle(19, 32, 4.6, t[1], sw=1.2))
    return "".join(out)


def zzz(t: tuple, s: float = 1.0) -> str:
    out = []
    for i, (x, y, sz) in enumerate(((22, 44, 9), (31, 32, 11), (42, 20, 13))):
        out.append(poly([(x - sz / 2, y - sz / 2), (x + sz / 2, y - sz / 2),
                         (x - sz / 2 + 2.6, y + sz / 2 - 2.6), (x + sz / 2, y + sz / 2 - 2.6),
                         (x + sz / 2, y + sz / 2), (x - sz / 2, y + sz / 2),
                         (x + sz / 2 - 2.6, y - sz / 2 + 2.6), (x - sz / 2, y - sz / 2 + 2.6)],
                        t[1] if i < 2 else t[0], sw=1.0))
    return "".join(out)


def portal(t: tuple, s: float = 1.0) -> str:
    return (circle(32, 32, 17 * s, "none", stroke=t[2], sw=3.4)
            + circle(32, 32, 11.5 * s, "none", stroke=t[1], sw=3.0)
            + circle(32, 32, 5.5 * s, mix(t[2], INK, 0.5), sw=1.2))


def wind(t: tuple, s: float = 1.0) -> str:
    """Three streaming lines with a curl on the end — breath, haste, freedom."""
    out = []
    for i, (y, x1, curl) in enumerate(((22, 42, 1), (32, 47, 1), (42, 38, -1))):
        out.append(stroke_path(
            "M14 %d H%d a5 5 0 1 %d %d %d" % (y, x1, 1 if curl > 0 else 0, -1, 7 * curl),
            t[1] if i != 1 else t[0], 3.6 - 0.4 * i))
    return "".join(out)


def halo(t: tuple, s: float = 1.0) -> str:
    """A radiant ring with rays — the divine family."""
    out = [circle(32, 32, 11 * s, "none", stroke=t[1], sw=3.4)]
    for a in range(0, 360, 45):
        x0, y0 = pt(32, 32, 14.5 * s, a)
        x1, y1 = pt(32, 32, 19 * s, a)
        out.append(stroke_path("M%.1f %.1f L%.1f %.1f" % (x0, y0, x1, y1), t[0], 2.4))
    return "".join(out)


def pillar(t: tuple, s: float = 1.0) -> str:
    """A column falling from above: Flame Strike, Moonbeam, Ice Storm."""
    return (poly([(24, 12), (40, 12), (44, 50), (20, 50)], t[1], sw=1.3)
            + poly([(28.5, 14), (35.5, 14), (37.5, 46), (26.5, 46)], t[0], stroke="none")
            + rect(16, 8, 32, 6, 3, t[2], sw=1.2))


def wall(t: tuple, s: float = 1.0) -> str:
    """A standing line of the element."""
    out = [rect(13, 42, 38, 6, 3, t[2], sw=1.2)]
    for i, x in enumerate((20, 32, 44)):
        out.append(flame(t, x, 34, 0.62 if i != 1 else 0.78))
    return "".join(out)


# --- the skills ------------------------------------------------------------
# One badge per thing the action bar can offer BY NAME: every combat-castable
# spell, every feature that becomes a button, and the three Shove variants that
# share one verb kind. The bar looks these up by id before it falls back to the
# kind or the school (core/ui_icons.gd skill_icon), so this table is what makes
# a row of a caster's spells read as ten different spells rather than ten
# evocation discs.
#
# A spell's disc comes from data/spells.json, so the two can't drift: change a
# spell's school there and the badge follows. The motif is coloured by what the
# skill DOES — the element, not the school.

SPELL_SCHOOLS = {
    s["id"]: s["school"]
    for s in __import__("json").loads((ROOT / "data" / "spells.json").read_text())
}

FEATURE_DISC = mix("#c8a75a", "#0b0a11", 0.86)      # a class feature: gilt, banked right down
FEATURE_RING = mix("#c8a75a", PANEL, 0.55)
FOE_DISC = mix("#d15750", "#0b0a11", 0.86)          # a monster's own: COL_FOE, same treatment
FOE_RING = mix("#d15750", PANEL, 0.55)


def spell_art(sid: str, *art: str) -> str:
    return school_badge(SPELL_SCHOOLS[sid], *art)


def feature_art(*art: str, foe: bool = False) -> str:
    return badge(*art, disc=FOE_DISC if foe else FEATURE_DISC,
                 ring=FOE_RING if foe else FEATURE_RING, art_scale=0.84)


# --- spells ----------------------------------------------------------------
# Grouped by school the way data/spells.json has them, so a gap is visible.

SPELLS = {
    # abjuration
    "resistance": (hexagon(32, 32, 15, E("steel")[1]), plus(32, 32, 6, 2.2, LIGHT)),
    "aid": (heart(32, 31, 14, E("life")), plus(46, 18, 5, 2, LIGHT)),
    "mass-healing-word": (heart(24, 30, 10, E("life")), heart(40, 30, 10, E("life")), plus(32, 44, 5, 2, LIGHT)),
    "mass-cure-wounds": (heart(22, 30, 9, E("life")), heart(32, 26, 9, E("life")), heart(42, 30, 9, E("life"))),
    "shield-of-faith": (hexagon(32, 32, 16, E("radiant")[1]), star(32, 32, 6, 2.4, 4, LIGHT, sw=1.0)),
    "beacon-of-hope": (pillar(E("radiant")), star(32, 16, 6.5, 2.2, 5, LIGHT, sw=1.0)),
    "protection-from-energy": (hexagon(32, 32, 16, E("force")[1]), flame(E("fire"), 32, 34, 0.4)),
    "stoneskin": (hexagon(32, 32, 16, E("stone")[1]), person(E("stone"), "stand", 0.6)),
    "cure-wounds": (heart(32, 31, 16, E("life")), plus(32, 28, 7.5, 2.7, LIGHT)),
    # A ward plate with somebody else's spell breaking on it — the one badge
    # that is about a spell that never arrives.
    "counterspell": (hexagon(32, 32, 20, mix(ELEM["force"], PANEL, 0.5), sw=1.6),
                     bolt(E("psychic"), 0.52), star(45, 18, 6, 2, 4, LIGHT, sw=1.0)),
    "freedom-of-movement": (chain(E("force"), broken=True),),
    "banishment": (portal(E("shadow")),),

    # conjuration
    "misty-step": (person(E("force"), "stand", 0.7), cloud(E("force"), 0.45)),
    "dimension-door": (portal(E("force")),),
    "fog-cloud": (cloud(E("steel")),),
    "summon-beast": (fangs(E("nature"), 0.9), star(46, 16, 6, 2, 4, LIGHT, sw=1.0)),
    "summon-fey": (crescent(E("nature")), star(46, 16, 6, 2, 4, LIGHT, sw=1.0)),
    "summon-aberration": (eye(E("psychic"), 0.9), tentacles(E("psychic"), 0.45)),
    "summon-construct": (hexagon(32, 32, 15, E("stone")[1]), fist(E("stone"), 0.5)),
    "summon-dragon": (flame(E("fire"), 32, 30, 0.7), fangs(E("fire"), 0.45)),
    "summon-celestial": (halo(E("radiant")), star(32, 32, 9, 3.5, 5, E("radiant"))),
    "spirit-guardians": (halo(E("radiant")), person(E("radiant"), "stand", 0.55)),
    "sleet-storm": (cloud(E("cold")), snowflake(E("cold"), 0.45)),
    "hunger-of-hadar": (orb(E("shadow"), 1.0, ring=True), tentacles(E("shadow"), 0.5)),
    "produce-flame": (hand(E("gold")), flame(E("fire"), 32, 20, 0.55)),
    "acid-splash": (droplets(E("acid"), 3),),
    "ensnaring-strike": (vines(E("nature")),),
    "arms-of-hadar": (tentacles(E("shadow")),),
    "web": (web(E("steel")),),
    "stinking-cloud": (cloud(E("poison")),),
    "evards-black-tentacles": (tentacles(E("necrotic")), circle(32, 52, 3, ELEM["necrotic"], stroke="none")),
    "steel-wind-strike": (slashes(E("steel"), 3),),
    "insect-plague": (swarm(E("nature")),),

    # divination
    "hunters-mark": (reticle(E("gold")), dart(E("nature"), -45, 1, 0.5)),

    # enchantment
    "bless": (star(32, 30, 12, 5, 5, E("radiant")), plus(46, 18, 5, 2, LIGHT)),
    "bane": (star(32, 30, 12, 5, 5, E("shadow")), skull(E("shadow"), 0.4, 44)),
    "command": (hand(E("gold"), 0.0, 0.9), banner(E("psychic"), 0.4)),
    "suggestion": (brain(E("psychic")), note(E("psychic"), 0.5)),
    "compulsion": (puppet(E("psychic")), spiral(E("psychic"), 0.4)),
    "confusion": (spiral(E("psychic")), eye(E("psychic"), 0.45)),
    "mind-sliver": (brain(E("psychic")), dart(E("psychic"), 25, 1, 0.55)),
    "charm-person": (mask(E("psychic"), "flat"), heart(44, 20, 6, E("life"))),
    "sleep": (zzz(E("psychic")),),
    "heroism": (fist(E("gold")), star(46, 16, 6, 2, 4, LIGHT, sw=1.0)),
    "dissonant-whispers": (waves(E("psychic")),),
    "hideous-laughter": (mask(E("psychic"), "laugh"),),
    "hold-person": (person(E("steel"), "held"),),
    "calm-emotions": (waves(E("cold")), circle(19, 32, 4.6, ELEM["life"], stroke="none")),
    "charm-monster": (mask(E("psychic"), "flat"), fangs(E("poison"), 0.42)),
    "dominate-beast": (puppet(E("nature")),),
    "dominate-person": (puppet(E("psychic")),),
    "modify-memory": (brain(E("psychic")),
                      band(32, 32, 21, 16, 205, 335, ELEM["shadow"]),
                      band_head(32, 32, 21, 16, 335, 24, ELEM["shadow"])),
    "hold-monster": (person(E("necrotic"), "held"), fangs(E("shadow"), 0.4)),
    "geas": (scroll(E("gold")),),

    # evocation
    "darkness": (orb(E("shadow"), 1.0, ring=True), crescent(E("shadow"), 0.4)),
    "faerie-fire": (person(E("force"), "stand", 0.8), star(46, 16, 6, 2, 4, E("lightning"), sw=1.0)),
    "spiritual-weapon": (sword(32, 32, -30, 44), halo(E("radiant"), 0.5)),
    "fire-bolt": (dart(E("fire"), -45, 1),),
    # 2026-09-19: the five the export lacked
    "magic-missile": (dart(E("force"), -45, 3),),
    "eldritch-blast": (beam(E("shadow")), star(45, 18, 5.5, 2, 4, LIGHT, sw=1.0)),
    "vicious-mockery": (mask(E("psychic"), "laugh", 0.8), waves(E("psychic"), 0.55)),
    "healing-word": (heart(32, 32, 13, E("life")), note(LIGHT, 0.55)),
    "shield": (hexagon(32, 32, 17, E("force")[1], sw=1.6), star(32, 32, 5, 2, 4, LIGHT, sw=1.0)),
    "ray-of-frost": (beam(E("cold")),),
    "shocking-grasp": (hand(E("steel")), bolt(E("lightning"), 0.55)),
    "sacred-flame": (halo(E("radiant")), flame(E("radiant"), 32, 34, 0.5)),
    "burning-hands": (cone_burst(E("fire"), -20),),
    "guiding-bolt": (dart(E("radiant"), -45, 1), star(46, 17, 6.5, 2.2, 4, LIGHT, sw=1.0)),
    "chromatic-orb": (orb(E("force"), ring=True), circle(27, 27, 3.2, ELEM["fire"], stroke="none"),
                      circle(37, 29, 3.2, ELEM["cold"], stroke="none"),
                      circle(32, 38, 3.2, ELEM["acid"], stroke="none")),
    "hellish-rebuke": (path("M32 12 L48 17 C48 32 41 42 32 47 C23 42 16 32 16 17z",
                            E("shadow")[1], sw=1.3), flame(E("fire"), 32, 32, 0.62)),
    "scorching-ray": (dart(E("fire"), -45, 3),),
    "moonbeam": (pillar(E("cold")), crescent(E("radiant"))),
    "fireball": (orb(E("fire")), flame(E("fire"), 32, 24, 0.5)),
    "crusaders-mantle": (banner(E("radiant")),),
    "lightning-bolt": (bolt(E("lightning")),),
    "wall-of-fire": (wall(E("fire")),),
    "ice-storm": (pillar(E("cold")), snowflake(E("cold"), 0.5)),
    "flame-strike": (pillar(E("fire")),),
    "cone-of-cold": (cone_burst(E("cold"), -20), snowflake(E("cold"), 0.36)),

    # illusion
    "blur": (person(E("force"), "stand", 0.8), waves(E("force"), 0.6)),
    "invisibility": (person(E("force"), "stand"), circle(32, 32, 19, "none",
                                                         stroke=ELEM["force"], sw=1.6)),
    "phantasmal-force": (mask(E("shadow"), "flat"), cloud(E("shadow"), 0.5)),
    "hypnotic-pattern": (spiral(E("psychic")),),
    "fear": (mask(E("shadow"), "scream"),),
    "greater-invisibility": (person(E("force"), "stand"),
                             circle(32, 32, 19, "none", stroke=ELEM["force"], sw=1.6),
                             star(48, 16, 6, 2, 4, LIGHT, sw=1.0)),

    # necromancy
    "false-life": (heart(32, 31, 14, E("necrotic")), skull(E("necrotic"), 0.35, 44)),
    "ray-of-enfeeblement": (beam(E("necrotic")), skull(E("necrotic"), 0.4, 46)),
    "poison-spray": (droplets(E("poison"), 3),),
    "chill-touch": (hand(E("necrotic")), skull(E("shadow"), 0.42, cy=22)),
    "ray-of-sickness": (beam(E("poison")),),
    "blight": (skull(E("necrotic")), vines(E("shadow"), 0.5)),

    # transmutation
    "magic-weapon": (sword(32, 32, -30, 44), star(46, 16, 6, 2, 4, LIGHT, sw=1.0)),
    "haste": (person(E("lightning"), "stand", 0.8), wind(E("lightning"), 0.6)),
    "polymorph": (mask(E("nature"), "flat"), fangs(E("nature"), 0.4)),
    "thorn-whip": (vines(E("nature")), circle(44, 16, 3.2, ELEM["nature"], stroke="none")),
}


# --- features --------------------------------------------------------------
# The class features and monster abilities that become their own button
# (data/effects/features.json, the kinds in combat.gd's OFFERABLE).

FEATURES = {
    "fighter-second-wind": (wind(E("life")), heart(46, 44, 8, E("life"))),
    "fighter-action-surge": (chevron(24, 32, 0, 13, 6, E("gold")),
                             chevron(38, 32, 0, 13, 6, E("gold")),
                             star(50, 16, 6, 2, 4, LIGHT, sw=1.0)),
    "barbarian-rage": (mask(E("fire"), "scream"), waves(E("fire"), 0.5)),
    "barbarian-reckless-attack": (slashes(E("steel"), 2), star(46, 18, 6, 2, 4, E("fire"), sw=1.0)),
    "monk-flurry-of-blows": (fist(E("steel")), chevron(52, 22, 0, 8, 4, E("gold"))),
    "monk-stunning-strike": (fist(E("gold")), star(48, 18, 7, 2.4, 4, LIGHT, sw=1.0),
                             star(16, 22, 5, 1.8, 4, LIGHT, sw=1.0)),
    "cleric-channel-divinity": (halo(E("radiant")),),
    "bard-bardic-inspiration": (note(E("gold")),),

    # T-classes-a. Five class/subclass features that became buttons. Assassinate
    # wears exactly the mark monster-assassinate wears — it is the same ability,
    # and a rogue's version of it should not be a different picture.
    "assassin-assassinate": (reticle(E("shadow")), dart(E("steel"), -45, 1, 0.85)),
    "wardomain-war-priest": (sword(32, 33, 0, length=40, w=6.6, steel=E("radiant")),
                             chevron(52, 22, 0, 8, 4, E("gold"))),
    # T-classes-d. A Smite is the sword coming down with the light on it, so it
    # is monster-divine-eminence's halo-and-blade read as a hero's: the same two
    # marks, the blade angled into the blow rather than held up.
    "paladin-divine-smite": (halo(E("radiant")),
                             sword(32, 34, 20, length=44, w=7.0, steel=E("radiant")),
                             star(18, 20, 6, 2, 4, LIGHT, sw=1.0)),
    "celestialpatron-healing-light": (halo(E("radiant")), heart(32, 43, 8, E("life"))),
    "warriorofmercy-hand-of-healing": (hand(E("life")), heart(46, 18, 7, E("life"))),
    "warrioropenhand-wholeness-of-body": (person(E("life"), "stand", 0.8),
                                          waves(E("life"), 0.45)),

    # T-summon. The beast is a claw rather than the fangs summon-beast wears:
    # the two land next to each other on a Beast Master's bar and must not read
    # as the same button. The double is two of the same silhouette, the one
    # behind in shadow — which is the whole feature in one picture.
    "beastmaster-primal-companion": (hand(BONE, claw=True),
                                     star(47, 16, 6, 2, 4, E("nature"), sw=1.0)),
    "trickerydomain-invoke-duplicity": (
        group([person(E("shadow"), "stand", 0.95)], 24.5, 12.3, scale=0.62),
        group([person(E("psychic"), "stand", 0.95)], 5.5, 12.3, scale=0.62)),

    "monster-poison-bite": (fangs(E("poison")), droplets(E("poison"), 1, 0.5)),
    "monster-venom-sting": (dart(E("poison"), 200, 1), droplets(E("poison"), 1, 0.42)),
    "monster-paralytic-touch": (hand(E("lightning")), bolt(E("lightning"), 0.5)),
    "monster-stunning-blow": (fist(E("thunder")), star(48, 18, 7, 2.4, 4, LIGHT, sw=1.0)),
    "monster-grappling-attack": (hand(E("steel"), claw=True),),
    "monster-constrict": (band(32, 34, 18, 12.5, 20, 300, E("nature")[1]),
                          band(32, 34, 11, 6, 40, 320, E("nature")[2]),
                          circle(45, 20, 6.2, ELEM["nature"], sw=1.2),
                          circle(47, 18.5, 1.6, INK, stroke="none"),
                          poly([(50, 22), (57, 24), (50, 26)], E("nature")[0], sw=1.0)),
    "monster-knockdown": (person(E("steel"), "prone"),),
    "monster-blinding-attack": (eye(E("steel")), stroke_path("M16 48 L48 16", ELEM["shadow"], 4.4)),
    "monster-life-drain": (skull(E("necrotic")), waves(E("necrotic"), 0.45)),
    "monster-frightful-presence": (mask(E("shadow"), "scream"), waves(E("shadow"), 0.42)),
    "monster-charm-gaze": (eye(E("psychic")), heart(46, 18, 7, E("psychic"))),
    "monster-petrifying-gaze": (eye(E("stone")), hexagon(46, 18, 7, ELEM["stone"], sw=1.1)),
    "monster-web-shot": (web(E("steel")), dart(E("steel"), -45, 1, 0.42)),
    "monster-breath-weapon": (cone_burst(E("fire"), -20),),
    "monster-breath-weapon-greater": (cone_burst(E("fire"), -20), fangs(E("fire"), 0.42)),
    "monster-innate-bolt": (orb(E("force")), bolt(E("lightning"), 0.55)),
    "monster-pack-tactics": (dart(E("steel"), -45, 1, 0.6), dart(E("steel"), 0, 1, 0.6),
                             dart(E("steel"), 45, 1, 0.6)),
    "monster-regeneration": (heart(32, 32, 15, E("life")),
                             band(32, 32, 19, 15.5, 200, 330, E("life")[1]),
                             band_head(32, 32, 19, 15.5, 330, 24, E("life")[1])),

    # T94. Only the five that are a button kind: the pass's passives (martial
    # advantage, sneak attack, keen senses, magic resistance, parry, the
    # survive_damage pair) never reach the bar and so never reach this table.
    "monster-assassinate": (reticle(E("shadow")), dart(E("steel"), -45, 1, 0.85)),
    "monster-divine-eminence": (halo(E("radiant")),
                                sword(32, 33, 0, length=40, w=6.6, steel=E("radiant"))),
    # The three bursts are one motif in three readings — the corpse is the
    # trigger, the accent is what comes out of it — because at the bar's ~22 px
    # a centred star swallows whatever is drawn inside it.
    "monster-death-burst": (skull(E("fire")),
                            star(47, 19, 7, 2.4, 5, E("fire"), sw=1.0),
                            star(18, 23, 5.5, 1.9, 5, E("fire"), sw=1.0)),
    "monster-death-burst-ice": (skull(E("cold")),
                                group([snowflake(E("cold"))], 33.8, 6.8, scale=0.38)),
    "monster-death-burst-greater": (star(32, 32, 22, 15.0, 12, E("fire"), sw=1.0),
                                    circle(32, 32, 14, mix(ELEM["fire"], INK, 0.8),
                                           stroke="none"),
                                    skull(E("fire"), 0.78)),
}


# --- the three Shoves ------------------------------------------------------
# One verb kind, three choices, and the choice is the whole point of the verb:
# they are the one place where an id-level badge says something the kind-level
# one cannot.

SHOVES = {
    "shove_prone": (arrow(14, 24, 135, 20, 9, GOLD), person(STEEL, "prone")),
    "shove_push": (arrow(16, 32, 90, 22, 10, GOLD),
                   group([person(STEEL, "stand")], 12, 2, 16, scale=0.8)),
    "shove_brazier": (arrow(13, 32, 90, 18, 8, GOLD),
                      group([person(STEEL, "stand")], 8, 0, 20, scale=0.66),
                      flame(E("fire"), 50, 38, 0.62)),
}


SKILLS = {}
for _sid, _art in SPELLS.items():
    SKILLS[_sid] = spell_art(_sid, *_art)
for _fid, _art in FEATURES.items():
    SKILLS[_fid] = feature_art(*_art, foe=_fid.startswith("monster-"))
for _bid, _art in SHOVES.items():
    SKILLS[_bid] = badge(*_art)

# --- the twelve classes ----------------------------------------------------
# One emblem per class, for the level ladder (scenes/creator/climb_view.gd):
# the fork at level 3 draws a branch per path, and the creator's class step
# reads as twelve tracks side by side. Both wanted a mark, and the only thing
# standing in for a class until now was a text glyph in Icons.CLASS_GLYPHS.
#
# Each is one motif, not a scene. A class emblem sits at 28-46 px beside a
# class name that is already on screen — it identifies, it does not illustrate,
# and a second object in the disc only muddies it at that size. Where two
# classes would reach for the same motif the tie is broken by what the class
# does rather than what it carries: the barbarian's fist against the monk's
# open hand, the sorcerer's flame against the wizard's worked orb.
CLASSES = {
    "barbarian": badge(fist(E("fire"), 1.05)),
    "bard": badge(note(E("gold"), 1.05)),
    "cleric": badge(star(32, 32, 19, 8, 8, E("radiant"), sw=1.0),
                    plus(32, 32, 9.5, 3.8, GOLD)),
    "druid": badge(crescent(E("nature"), 1.05)),
    "fighter": badge(sword(32, 39, 0, 46)),
    "monk": badge(hand(BONE, 0, 1.05)),
    "paladin": badge(hexagon(32, 32, 16, STEEL[1], sw=1.6),
                     star(32, 31, 8.5, 3.4, 4, GOLD, sw=1.0)),
    "ranger": badge(band(38, 36, 20, 18.2, 128, 232, WOOD[1], sw=1.5),
                    arrow(30, 34, -45, 38, 5.2, STEEL)),
    "rogue": badge(dart(STEEL, -45, 1, 1.15)),
    "sorcerer": badge(flame(E("fire"), 32, 33, 1.05)),
    "warlock": badge(eye(E("necrotic"), 1.1)),
    "wizard": badge(orb(E("force"), 0.92, ring=True),
                    star(32, 31, 7.5, 2.8, 4, BONE, sw=0.9)),
}


GROUPS = {"actions": ACTIONS, "schools": SCHOOLS, "skills": SKILLS,
          "classes": CLASSES}



# --- the Godot side --------------------------------------------------------
# Every other image in this repo has its .import committed next to it, so these
# do too — otherwise the first person to open the editor gets 28 files of
# incidental diff. Written here rather than by hand because two settings are
# deliberate and would quietly revert if someone re-imported at the defaults:
#
#   svg/scale=1.0        rasterise at 64 px and let the bar draw it at ~22.
#                        At 1.0 the master is the display size and every
#                        rounding of the button's layout softens a 2 px stroke.
#   mipmaps/generate     the bar redraws these at whatever the zoom slider
#                        says; a mip chain is what keeps 22 px off 64 px from
#                        crawling.
#
# The rest are Godot's texture defaults, spelled out because that is what the
# importer writes back. compress/mode was 0 here and 1 in all 161 committed
# sidecars — 4.7's importer writes 1 — so --check had been failing on every
# icon in the repo. Corrected to match what Godot actually produces. `path`/`dest_files` are not free-form: Godot addresses
# the imported file by md5 of the *source* res:// path (see
# EditorFileSystem::_get_import_base_path), so they are computed, not chosen.

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="{dest}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{src}"
dest_files=["{dest}"]

[params]

compress/mode=1
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
svg/scale=1.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
"""

UID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"


def uid_for(res_path: str) -> str:
    """A first uid:// for a brand-new icon, base-36 the way
    ResourceUID::id_to_text spells one.

    Only ever used once per file. Godot mints and normalises uids itself — it
    rewrote half of these the first time it imported them — so import_file()
    keeps whatever is already on disk and this is just a plausible value to
    start from. Deriving it from the path rather than rolling a random one
    keeps the tool deterministic for a fresh checkout."""
    n = int.from_bytes(hashlib.md5(res_path.encode()).digest()[:8], "big") >> 1
    out = ""
    while n:
        out = UID_CHARS[n % len(UID_CHARS)] + out
        n //= len(UID_CHARS)
    return "uid://" + out


def import_file(res_path: str, current: str = None) -> str:
    """The .import sidecar, keeping the uid Godot has already assigned.

    The uid is the one line in here this tool does not own: it is what every
    scene referencing the icon holds on to, and the editor rewrites it on its
    own terms. Everything else — the params, and the imported path, which is
    md5 of the source res:// path (EditorFileSystem::_get_import_base_path) —
    is ours and is regenerated."""
    digest = hashlib.md5(res_path.encode()).hexdigest()
    dest = "res://.godot/imported/%s-%s.ctex" % (res_path.rsplit("/", 1)[1], digest)
    uid = uid_for(res_path)
    if current:
        found = re.search(r'^uid="(uid://[^"]+)"$', current, re.M)
        if found:
            uid = found.group(1)
    return IMPORT_TEMPLATE.format(uid=uid, dest=dest, src=res_path)


def targets() -> list:
    """Every file this tool owns: each icon, and the .import Godot reads it through."""
    out = []
    for group, icons in GROUPS.items():
        for name in sorted(icons):
            rel = "assets/icons/%s/%s.svg" % (group, name)
            out.append((ROOT / rel, icons[name]))
            sidecar = ROOT / (rel + ".import")
            out.append((sidecar, import_file(
                "res://" + rel, sidecar.read_text() if sidecar.exists() else None)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list", action="store_true", help="print the paths and stop")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if any file on disk differs from what this would write")
    args = ap.parse_args()

    stale = []
    for path, body in targets():
        rel = path.relative_to(ROOT)
        if args.list:
            print(rel)
            continue
        current = path.read_text() if path.exists() else None
        if args.check:
            if current != body:
                stale.append(rel)
            continue
        if current == body:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        print("wrote %s" % rel)

    if args.check:
        for rel in stale:
            print("stale: %s" % rel, file=sys.stderr)
        if stale:
            print("%d file(s) differ — run tools/gen_action_icons.py" % len(stale),
                  file=sys.stderr)
            return 1
        print("%d file(s) up to date" % len(targets()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

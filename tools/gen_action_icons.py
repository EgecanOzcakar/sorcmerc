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
    scales the badge down to ~28 px.
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
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


# --- palette ---------------------------------------------------------------
# core/ui_icons.gd's colours, plus the light/shadow tone of each material. The
# schools are SCHOOL_COLORS verbatim; their two other tones are derived, so
# changing a school colour there is a one-line change here.

INK = "#0d0f16"          # every outline
PANEL = "#15161e"        # the badge's inset panel
DISC = "#23242f"         # the medallion a martial verb stands on
FRAME = "#c8a75a"        # COL_GOLD — the gilt edge
FRAME_HI = "#e8cf8a"
FRAME_LO = "#7a6130"


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

def poly(points, fill: str, stroke: str = INK, sw: float = 1.3, extra: str = "") -> str:
    pts = " ".join("%.1f,%.1f" % (x, y) for x, y in points)
    return '<polygon points="%s" fill="%s"%s%s/>' % (pts, fill, _stroke(stroke, sw), extra)


def path(d: str, fill: str, stroke: str = INK, sw: float = 1.3, extra: str = "") -> str:
    return '<path d="%s" fill="%s"%s%s/>' % (d, fill, _stroke(stroke, sw), extra)


def circle(cx: float, cy: float, r: float, fill: str, stroke: str = INK,
           sw: float = 1.3, extra: str = "") -> str:
    return '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"%s%s/>' % (
        cx, cy, r, fill, _stroke(stroke, sw), extra)


def rect(x: float, y: float, w: float, h: float, r: float, fill: str,
         stroke: str = INK, sw: float = 1.3, extra: str = "") -> str:
    return '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"%s%s/>' % (
        x, y, w, h, r, fill, _stroke(stroke, sw), extra)


def stroke_path(d: str, color: str, w: float, cap: str = "round") -> str:
    """A drawn line rather than a filled shape — the spiral and the cracks."""
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" '
            'stroke-linecap="%s" stroke-linejoin="round"/>' % (d, color, w, cap))


def _stroke(color: str, w: float) -> str:
    if color is None or color == "none" or w <= 0:
        return ''
    return ' stroke="%s" stroke-width="%.1f" stroke-linejoin="round"' % (color, w)


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
    return (
        rect(1.5, 1.5, 61, 61, 11.5, FRAME_LO, stroke="none")
        + rect(2.5, 2.5, 59, 58, 10.5, FRAME, stroke="none")
        + rect(3.5, 3.5, 57, 55, 9.5, FRAME_HI, stroke="none")
        + rect(4.5, 5.5, 55, 54, 9, FRAME, stroke="none")
        + rect(5, 5, 54, 54, 8, PANEL, stroke="none")
        + rect(7.5, 7.5, 49, 49, 6, "none", stroke=FRAME_LO, sw=1.1)
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
            out.append(circle(x, y, 1.3, ring, stroke="none"))
    return "".join(out)


def badge(*art: str, disc: str = None, ring: str = None) -> str:
    body = frame() + medallion(disc, ring) + "".join(art)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
            'viewBox="0 0 64 64">\n  %s\n</svg>\n' % body)


# --- the things the art is made of -----------------------------------------

def sword(x: float, y: float, rot: float = 0.0, length: float = 52.0,
          w: float = 10.0, steel: tuple = STEEL, hilt: tuple = GOLD) -> str:
    """A sword, point up, centred on (x, y) and rotated `rot` degrees clockwise.

    Parametrised because three icons carry one and hand-placing a crossguard
    square to a blade three times is how they end up not matching. Everything
    below the guard is sized off `length` too — a short sword with a longsword's
    hilt reads as a dagger someone dropped."""
    h = length / 2.0
    grip_len = length * 0.29          # guard, grip and pommel share this
    guard_y = h - grip_len
    guard_t = w * 0.52
    pommel = max(2.4, w * 0.31)
    return group([
        poly([(-w / 2, guard_y), (-w / 2, -h + w * 0.9), (0, -h), (w / 2, -h + w * 0.9),
              (w / 2, guard_y)], steel[1], sw=1.5),
        poly([(-w / 2 + w * 0.18, guard_y - 1.8), (-w / 2 + w * 0.18, -h + w * 1.05),
              (-w * 0.09, -h + w * 0.55), (-w * 0.09, guard_y - 1.8)], steel[0], stroke="none"),
        rect(-w * 1.3, guard_y, w * 2.6, guard_t, guard_t / 2.0, hilt[1], sw=1.3),
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
        poly([(-4.4, 2), (4.4, 2), (3.2, 13), (-3.2, 13)], tone[1]),
        poly([(-3.2, 12), (0.6, 12), (3.2, 22), (-1.2, 22)], tone[2]),
        poly([(0.2, 12), (3.8, 12), (7.8, 20), (4.2, 22)], tone[2]),
        circle(0, -3.6, 5.8, tone[1]),
        circle(-1.8, -5.2, 2.2, tone[0], stroke="none"),
    ], x, y, rot)


LIGHT = tones("#eef2fb")
BONE = tones("#e2dcc6")


def hexagon(cx: float, cy: float, r: float, tone_i: str, sw: float = 1.3) -> str:
    return poly([pt(cx, cy, r, -90 + i * 60) for i in range(6)], tone_i, sw=sw)


def school_badge(sid: str, *art: str) -> str:
    base = SCHOOL_COLORS[sid]
    return badge(*art, disc=mix(base, "#0e0f16", 0.80), ring=mix(base, PANEL, 0.30))


# --- the verbs -------------------------------------------------------------
# Keyed by scenes/main.gd's verb `kind` (Icons.VERB_GLYPHS), plus the four
# controls the bar builds itself. One recipe per key, nothing keyed by verb id:
# Shove → prone and Shove → back are one badge, their labels say which.

ACTIONS = {
    # The Attack action: one sword, lit down its near edge.
    "attack": badge(sword(32, 32, 45, length=52, w=10)),

    # The bonus-action second swing — the same sword twice, smaller, crossed.
    "offhand_attack": badge(
        sword(37, 33, 42, length=44, w=8),
        sword(27, 33, -42, length=44, w=8),
    ),

    # Force applied, and the figure already going over backwards from it.
    "shove": badge(
        group([figure(0, 0, 0, STEEL)], 44, 28, 20, scale=1.35),
        arrow(16, 32, 90, 24, 11, GOLD),
    ),

    # A maul mid-swing, and the object coming apart under it.
    "smash": badge(
        group([
            rect(-3.4, 6, 6.8, 26, 2.8, WOOD[1], sw=1.4),
            rect(-13, -9, 26, 18, 3.5, GOLD[1], sw=1.5),
            rect(-10, -6.4, 20, 5.4, 2.2, GOLD[0], stroke="none"),
        ], 38, 22, 45),
        poly([(10, 48), (16.5, 43), (18.5, 51)], GOLD[2], sw=1.2),
        poly([(21, 54), (26, 49), (28.5, 55)], GOLD[1], sw=1.2),
        poly([(9, 36), (15.5, 37.5), (11.5, 42)], GOLD[2], sw=1.2),
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
        rect(10, 20.5, 11, 3.4, 1.7, STEEL[2], stroke="none"),
        rect(7, 30.3, 12, 3.4, 1.7, STEEL[1], stroke="none"),
        rect(10, 40.1, 11, 3.4, 1.7, STEEL[2], stroke="none"),
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
        rect(17, 47, 30, 5.5, 2.2, GOLD[2]),
        star(48, 15, 6, 2, 4, LIGHT, sw=1.1),
    ),

    # The same step up, granted to the party: two of them.
    "ally_buff": badge(
        arrow(22, 29, 0, 26, 10, GOLD),
        arrow(42, 29, 0, 26, 10, GOLD),
        rect(12, 46, 40, 5.5, 2.2, GOLD[2]),
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
        rect(30.4, 9, 3.2, 8, 1.6, STEEL[2]),
        rect(30.4, 47, 3.2, 8, 1.6, STEEL[2]),
        rect(9, 30.4, 8, 3.2, 1.6, STEEL[2]),
        rect(47, 30.4, 8, 3.2, 1.6, STEEL[2]),
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
        poly([(23, 44), (41, 44), (37.5, 51), (26.5, 51)], GOLD[2], sw=1.2),
        rect(20, 49.5, 24, 5.5, 2.2, GOLD[1]),
    ),

    # A will bent: the spiral.
    "enchantment": school_badge(
        "enchantment",
        stroke_path("M32 13 A19 19 0 1 1 13 32 A13 13 0 1 0 39 32 A7 7 0 1 1 25 32", INK, 8.4),
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
        diamond(39, 32, 12, 15.5, _s("illusion"), sw=1.2, extra=' opacity="0.42"'),
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
        band(32, 32, 18, 12.5, 200, 330, _s("transmutation")[1]),
        band_head(32, 32, 18, 12.5, 330, 26, _s("transmutation")[1]),
        band(32, 32, 18, 12.5, 20, 150, _s("transmutation")[1]),
        band_head(32, 32, 18, 12.5, 150, 26, _s("transmutation")[1]),
        hexagon(32, 32, 6.5, _s("transmutation")[0], sw=1.1),
    ),
}

GROUPS = {"actions": ACTIONS, "schools": SCHOOLS}


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
#                        says; a mip chain is what keeps 28 px off 64 px from
#                        crawling.
#
# The rest are Godot's texture defaults, spelled out because that is what the
# importer writes back. `path`/`dest_files` are not free-form: Godot addresses
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

compress/mode=0
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
    """A stable uid://, base-36 the way ResourceUID::id_to_text spells one.

    The editor rolls a random one per file; deriving it from the path instead
    keeps this tool idempotent — regenerating an icon must not churn its uid,
    which is what every .tscn referencing it is holding on to."""
    n = int.from_bytes(hashlib.md5(res_path.encode()).digest()[:8], "big") >> 1
    out = ""
    while n:
        out = UID_CHARS[n % len(UID_CHARS)] + out
        n //= len(UID_CHARS)
    return "uid://" + out


def import_file(res_path: str) -> str:
    digest = hashlib.md5(res_path.encode()).hexdigest()
    dest = "res://.godot/imported/%s-%s.ctex" % (res_path.rsplit("/", 1)[1], digest)
    return IMPORT_TEMPLATE.format(uid=uid_for(res_path), dest=dest, src=res_path)


def targets() -> list:
    """Every file this tool owns: each icon, and the .import Godot reads it through."""
    out = []
    for group, icons in GROUPS.items():
        for name in sorted(icons):
            rel = "assets/icons/%s/%s.svg" % (group, name)
            out.append((ROOT / rel, icons[name]))
            out.append((ROOT / (rel + ".import"), import_file("res://" + rel)))
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

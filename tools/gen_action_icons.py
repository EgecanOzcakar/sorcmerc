#!/usr/bin/env python3
"""The action bar's icon set: one SVG per verb kind, spell school and bar control.

    python3 tools/gen_action_icons.py           # write everything
    python3 tools/gen_action_icons.py --list    # what would be written
    python3 tools/gen_action_icons.py --check   # fail if any file is stale

Writes flat, monochrome line icons under

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

Every icon is drawn in pure white on transparent and tinted at runtime
(`icon_normal_color` on the button) — gold for a verb, the school's own colour
for a spell. Authoring them monochrome is what makes that one-line tint
possible; it also keeps them legible on the dark panel at the ~22 px the bar
actually renders them at.

Drawing constraints, all of them learned from that size:
  * 32x32 viewBox, artwork inside 3..29 — the outer 3 px is the button's own
    breathing room and Godot's SVG rasteriser softens anything that touches
    the edge.
  * 2 px strokes, round caps and joins, no fill unless a shape needs weight.
    A 1 px stroke disappears at 22 px; a 3 px one closes up the small counters.
  * geometry only: no <style>, no gradients, no filters, no text. Godot imports
    SVG through ThorVG, which is a subset renderer — a filter that looks right
    in a browser silently drops out in-game.

No image model was involved in any of this: every path below is coordinates in
source, the same "shapes, not sprites" line the rest of the project's assets are
drawn on. The coordinates were written with a coding assistant, which is the
exempt half of the disclosure — see the provenance table in README.md.
"""

import argparse
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HEADER = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" '
    'viewBox="0 0 32 32">\n'
    '  <g fill="none" stroke="#ffffff" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round">\n'
)
FOOTER = "  </g>\n</svg>\n"


def svg(*parts: str) -> str:
    """Wrap element lines in the shared frame. Keeps every icon's stroke identical."""
    body = "".join("    %s\n" % p for p in parts)
    return HEADER + body + FOOTER


# --- shared shapes ---------------------------------------------------------
# A sword is the one shape three icons need (attack, offhand attack, the wield
# swap), and hand-placing a crossguard perpendicular to a blade three times is
# how they end up not matching. Parametrised once instead.


def blade(x1: float, y1: float, x2: float, y2: float, guard: float = 4.4,
          grip: float = 7.0, width: float = 2.8, pommel: float = 1.5) -> str:
    """A sword from hilt (x1,y1) toward tip (x2,y2): blade, crossguard, grip, pommel.

    The crossguard is what makes the shape read as a sword rather than a stick,
    and it has to be square to the blade — hence the maths instead of three
    hand-placed lines that nearly match."""
    dx, dy = x2 - x1, y2 - y1
    length = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / length, dy / length          # along the blade
    px, py = -uy, ux                           # across it
    gx, gy = x1 + ux * grip, y1 + uy * grip    # where the guard sits
    return (
        '<path d="M%.1f %.1f L%.1f %.1f" stroke-width="%.1f"/>'
        '<path d="M%.1f %.1f L%.1f %.1f"/>'
        '<path d="M%.1f %.1f L%.1f %.1f" stroke-width="%.1f"/>'
        '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#ffffff" stroke="none"/>'
        % (
            gx, gy, x2, y2, width,
            gx - px * guard, gy - py * guard, gx + px * guard, gy + py * guard,
            x1 + ux * 1.6, y1 + uy * 1.6, gx - ux * 1.2, gy - uy * 1.2, width * 0.75,
            x1, y1, pommel,
        )
    )


def spark(cx: float, cy: float, r: float = 3.2) -> str:
    """A four-point twinkle — the mark for 'and something extra happens'."""
    return ('<path d="M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f '
            'C%.1f %.1f %.1f %.1f %.1f %.1f '
            'C%.1f %.1f %.1f %.1f %.1f %.1f '
            'C%.1f %.1f %.1f %.1f %.1f %.1fz" stroke-width="1.6"/>'
            % (cx, cy - r,
               cx + r * 0.22, cy - r * 0.22, cx + r * 0.22, cy - r * 0.22, cx + r, cy,
               cx + r * 0.22, cy + r * 0.22, cx + r * 0.22, cy + r * 0.22, cx, cy + r,
               cx - r * 0.22, cy + r * 0.22, cx - r * 0.22, cy + r * 0.22, cx - r, cy,
               cx - r * 0.22, cy - r * 0.22, cx - r * 0.22, cy - r * 0.22, cx, cy - r))


HEART = ("M16 26 C7 19.5 4 15.6 4 11.8 A5.8 5.8 0 0 1 16 9.2 "
         "A5.8 5.8 0 0 1 28 11.8 C28 15.6 25 19.5 16 26z")
SHIELD = "M16 4 L27 8 C27 18 22.5 25 16 28.5 C9.5 25 5 18 5 8z"


# --- the verbs -------------------------------------------------------------
# Keyed by scenes/main.gd's verb `kind` (Icons.VERB_GLYPHS), plus the four
# controls the bar builds itself. One recipe per key, nothing keyed by verb id:
# Shove → prone and Shove → back are one shape, their labels say which.

ACTIONS = {
    # A single sword, tip high — the plain Attack action.
    "attack": svg(blade(6.5, 26, 26.5, 6)),

    # Two blades crossed: the bonus-action second swing with the off hand.
    "offhand_attack": svg(
        blade(6, 26, 21.5, 10.5, guard=3.4, grip=5.5, width=2.4, pommel=1.3),
        blade(26, 26, 10.5, 10.5, guard=3.4, grip=5.5, width=2.4, pommel=1.3),
    ),

    # Force, and the figure already going over backwards from it.
    "shove": svg(
        '<path d="M3 16 H14"/><path d="M10 11.5 L14.5 16 L10 20.5"/>',
        '<circle cx="22.5" cy="7.5" r="3" fill="#ffffff" stroke-width="1.4"/>',
        '<path d="M23 11 L19.5 20"/>',
        '<path d="M19.5 20 L16.5 25.5"/><path d="M19.5 20 L23.5 24.5"/>',
        '<path d="M28.5 10 A7 7 0 0 1 28.5 22"/>',
    ),

    # A maul mid-swing, and the object coming apart under it.
    "smash": svg(
        '<path d="M16.5 9.5 L21.5 4.5 L27.5 10.5 L22.5 15.5z"/>',
        '<path d="M19 13 L11 21" stroke-width="2.6"/>',
        '<path d="M4.5 27.5 L9 23"/><path d="M13.5 27.5 L11.5 24.5"/>',
        '<path d="M3.5 19 L6.5 21"/>',
    ),

    # Aid offered: the boon, held up in two cupped hands. The seam down the
    # middle is what keeps it from reading as a smile at 22 px.
    "help": svg(
        '<path d="M16 4 V14.5"/><path d="M10.5 9.5 H21.5"/>',
        '<path d="M4 17 A12 12 0 0 0 15 25.5"/>',
        '<path d="M28 17 A12 12 0 0 1 17 25.5"/>',
        '<path d="M4 17 V21"/><path d="M28 17 V21"/>',
    ),

    # A guard held: the doubled ward of the ◈ this replaces.
    "dodge": svg(
        '<path d="M16 3.5 L28.5 16 L16 28.5 L3.5 16z"/>',
        '<path d="M16 10 L22 16 L16 22 L10 16z"/>',
    ),

    # Speed: one arrow, three trails behind it.
    "dash": svg(
        '<path d="M11 16 H27"/>',
        '<path d="M22 11 L27 16 L22 21"/>',
        '<path d="M4 9.5 H13"/><path d="M3 16 H7"/><path d="M4 22.5 H13"/>',
    ),

    # Backing out of a threatened square — the reach you leave, dashed.
    "disengage": svg(
        '<path d="M21 4 A14 14 0 0 1 21 28" stroke-dasharray="3 3.5"/>',
        '<path d="M27 16 H7"/><path d="M12.5 10 L6.5 16 L12.5 22"/>',
    ),

    # Unseen: the eye, struck out.
    "hide": svg(
        '<path d="M3.5 16 C7 10.5 11.3 7.8 16 7.8 C20.7 7.8 25 10.5 28.5 16 '
        'C25 21.5 20.7 24.2 16 24.2 C11.3 24.2 7 21.5 3.5 16z"/>',
        '<circle cx="16" cy="16" r="3.4"/>',
        '<path d="M6 26 L26 6" stroke-width="2.4"/>',
    ),

    # Your own wounds closed.
    "heal_self": svg(
        '<path d="%s"/>' % HEART,
        '<path d="M16 11.5 V19.5"/><path d="M12 15.5 H20"/>',
    ),

    # The same heart, handed to someone else.
    "heal_ally": svg(
        '<path d="M16 21.5 C9.5 16.6 7.5 13.8 7.5 11 A4.2 4.2 0 0 1 16 8.9 '
        'A4.2 4.2 0 0 1 24.5 11 C24.5 13.8 22.5 16.6 16 21.5z"/>',
        '<path d="M16 12 V17"/><path d="M13.5 14.5 H18.5"/>',
        '<path d="M4.5 22 A11.5 11.5 0 0 0 27.5 22"/>',
    ),

    # A step up, on yourself: one rising arrow off a baseline.
    "self_buff": svg(
        '<path d="M16 27 V8"/>',
        '<path d="M10 14 L16 8 L22 14"/>',
        '<path d="M9 29 H23"/>',
        spark(26, 7, 2.8),
    ),

    # The same step up, granted to the party: two of them.
    "ally_buff": svg(
        '<path d="M10 27 V10"/><path d="M5.5 14.5 L10 10 L14.5 14.5"/>',
        '<path d="M22 27 V10"/><path d="M17.5 14.5 L22 10 L26.5 14.5"/>',
        '<path d="M4 29 H28"/>',
        spark(16, 6.5, 2.8),
    ),

    # Another action, right now: the fast-forward, plus one.
    "grant_action": svg(
        '<path d="M5 8.5 L14 16 L5 23.5z" fill="#ffffff" stroke-width="1.6"/>',
        '<path d="M15 8.5 L24 16 L15 23.5z" fill="#ffffff" stroke-width="1.6"/>',
        '<path d="M26.5 6.5 V13.5"/><path d="M23 10 H30"/>',
    ),

    # Something changed about the roll: the reticle, marked.
    "attack_modifier": svg(
        '<circle cx="16" cy="16" r="9"/>',
        '<circle cx="16" cy="16" r="2.4" fill="#ffffff" stroke="none"/>',
        '<path d="M16 3.5 V7.5"/><path d="M16 24.5 V28.5"/>',
        '<path d="M3.5 16 H7.5"/><path d="M24.5 16 H28.5"/>',
    ),

    # Roll a save or wear it: the bolt against the shield.
    "save_effect": svg(
        '<path d="%s"/>' % SHIELD,
        '<path d="M17.5 9 L12 17 H16 L14.5 24 L20.5 15.5 H16.5z"/>',
    ),

    # --- bar controls ---
    # The turn is spent.
    "end_turn": svg(
        '<path d="M8 4.5 H24"/><path d="M8 27.5 H24"/>',
        '<path d="M10.5 4.5 V9 L16 16 L21.5 9 V4.5"/>',
        '<path d="M10.5 27.5 V23 L16 16 L21.5 23 V27.5"/>',
        '<path d="M13 24.5 H19"/>',
    ),

    # Out of a submenu.
    "back": svg(
        '<path d="M13 9 L6 16 L13 23"/>',
        '<path d="M6 16 H20 A6 6 0 0 1 20 28"/>',
    ),

    # Melee ⇄ ranged: the other weapon comes up.
    "swap": svg(
        '<path d="M5 12 H27"/><path d="M23 8 L27 12 L23 16"/>',
        '<path d="M27 21 H5"/><path d="M9 17 L5 21 L9 25"/>',
    ),

    # Anything the bar offers that has no mark of its own.
    "generic": svg(spark(16, 16, 9.5), '<circle cx="16" cy="16" r="1.6" '
                   'fill="#ffffff" stroke="none"/>'),
}


# --- the eight schools -----------------------------------------------------
# Keyed by Icons.SCHOOL_GLYPHS / SCHOOL_COLORS. Each is tinted with its own
# school colour on the bar, so these read as a set of eight even though they
# share the verbs' stroke weight.

SCHOOLS = {
    # A ward that holds: the hex sigil, doubled.
    "abjuration": svg(
        '<path d="M16 3.5 L27 9.8 V22.2 L16 28.5 L5 22.2 V9.8z"/>',
        '<path d="M16 10 L22 13.4 V20.6 L16 24 L10 20.6 V13.4z"/>',
    ),

    # Something arrives: a spark rising out of the circle that called it.
    "conjuration": svg(
        '<ellipse cx="16" cy="23" rx="11" ry="4.5"/>',
        '<path d="M16 18.5 V5"/><path d="M11 10 L16 5 L21 10"/>',
        '<path d="M7 15.5 L9 13.5"/><path d="M25 15.5 L23 13.5"/>',
    ),

    # Knowing: the scrying orb on its stand.
    "divination": svg(
        '<circle cx="16" cy="14" r="9"/>',
        '<path d="M11 17.5 A6 6 0 0 1 15 10.5"/>',
        '<path d="M9 27 H23"/><path d="M12 23.5 L10.5 27"/><path d="M20 23.5 L21.5 27"/>',
    ),

    # A will bent: the spiral, and the heart it takes.
    "enchantment": svg(
        '<path d="M16 24 A8 8 0 1 0 8 16 A6 6 0 0 0 20 16 A4 4 0 0 1 12 16"/>',
        spark(26, 7, 2.8),
    ),

    # Raw energy, thrown: the burst.
    "evocation": svg(
        '<path d="M16 3.5 V9.5"/><path d="M16 22.5 V28.5"/>',
        '<path d="M3.5 16 H9.5"/><path d="M22.5 16 H28.5"/>',
        '<path d="M7.2 7.2 L11.4 11.4"/><path d="M20.6 20.6 L24.8 24.8"/>',
        '<path d="M24.8 7.2 L20.6 11.4"/><path d="M11.4 20.6 L7.2 24.8"/>',
        '<circle cx="16" cy="16" r="4" fill="#ffffff" stroke-width="1.6"/>',
    ),

    # Which one is real: the shape and the copy that isn't.
    "illusion": svg(
        '<path d="M12 4.5 L21.5 14 L12 23.5 L2.5 14z"/>',
        '<path d="M20 8.5 L29.5 18 L20 27.5 L10.5 18z" stroke-dasharray="3 3"/>',
    ),

    # The dead put to work.
    "necromancy": svg(
        '<path d="M8 21 A9.5 9.5 0 1 1 24 21 V24 A2.5 2.5 0 0 1 21.5 26.5 '
        'H10.5 A2.5 2.5 0 0 1 8 24z"/>',
        '<circle cx="12" cy="15.5" r="2.6" fill="#ffffff" stroke-width="1.4"/>',
        '<circle cx="20" cy="15.5" r="2.6" fill="#ffffff" stroke-width="1.4"/>',
        '<path d="M16 21.5 V26.5"/><path d="M12 22.5 V26.5"/><path d="M20 22.5 V26.5"/>',
    ),

    # One thing made another: the turning ring.
    "transmutation": svg(
        '<path d="M26 12.5 A11 11 0 0 0 5.5 12"/>',
        '<path d="M20.5 12.5 H26.5 V6.5"/>',
        '<path d="M6 19.5 A11 11 0 0 0 26.5 20"/>',
        '<path d="M11.5 19.5 H5.5 V25.5"/>',
        '<circle cx="16" cy="16" r="2.6" fill="#ffffff" stroke="none"/>',
    ),
}

GROUPS = {"actions": ACTIONS, "schools": SCHOOLS}


# --- the Godot side --------------------------------------------------------
# Every other image in this repo has its .import committed next to it, so these
# do too — otherwise the first person to open the editor gets 28 files of
# incidental diff. Written here rather than by hand because two settings are
# deliberate and would quietly revert if someone re-imported at the defaults:
#
#   svg/scale=2.0        rasterise at 64 px and let the bar draw it at ~22.
#                        At 1.0 the master is the display size and every
#                        rounding of the button's layout softens a 2 px stroke.
#   mipmaps/generate     the bar redraws these at whatever the zoom slider
#                        says; a mip chain is what keeps 22 px off 64 px from
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
svg/scale=2.0
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

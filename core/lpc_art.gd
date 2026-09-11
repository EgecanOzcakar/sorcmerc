# Which composited LPC sheet (if any) draws a given combatant, and which row of
# it. Tier 1 of the token ladder; anything this returns "" for keeps the flat
# vector token in Board._draw() exactly as before — that fallback is the design,
# not a gap to close.
#
# Scope, stated plainly: exactly one humanoid loadout exists, so every hero and
# every humanoid foe is drawn as merc_01 (T51). Per-class appearance needs more
# vendored loadouts, not more code here.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const HUMANOID := "merc_01"

# bestiary id -> loadout. The real matches for the three creatures vendored from
# [LPC] Monsters; everything else falls through to the vector token.
const BY_MONSTER := {
	"bat": "bat", "giant-bat": "bat",
	"ghost": "ghost", "specter": "ghost", "shadow": "ghost", "will-o-wisp": "ghost",
	"gray-ooze": "slime", "ochre-jelly": "slime", "black-pudding": "slime",
}

static var _cache := {}    # loadout id -> SpriteFrames (or null once, if missing)

static func loadout_for(c) -> String:
	if c.sheet != null:
		return HUMANOID              # every hero, one appearance, for now
	if c.src_id == "":
		return ""                    # never ask Catalog about a blank id
	if BY_MONSTER.has(c.src_id):
		return BY_MONSTER[c.src_id]
	return HUMANOID if String(Catalog.monster(c.src_id).get("type", "")) == "humanoid" else ""

static func frames(loadout: String) -> SpriteFrames:
	if loadout == "":
		return null
	if not _cache.has(loadout):
		var path := "res://assets/generated/%s.tres" % loadout
		_cache[loadout] = load(path) if ResourceLoader.exists(path) else null
	return _cache[loadout]

# LPC's 4 rows against a hex board: pick on the *projected* delta, not the axial
# one, because the board is yawed and squashed (ISO_SQUASH 0.38) before you see
# it — so the dominant screen axis is what reads as "facing", and in practice
# that is left/right for almost every hex pair, which is where the art is.
static func facing_between(from_px: Vector2, to_px: Vector2) -> String:
	var d := to_px - from_px
	if absf(d.x) >= absf(d.y):
		return "right" if d.x >= 0.0 else "left"
	return "down" if d.y >= 0.0 else "up"

# The animation row to use, and whether to mirror it. merc_01 only has
# slash_right, so a left-facing humanoid is that row flipped; creatures have all
# four rows and never flip.
static func row_for(sf: SpriteFrames, facing: String) -> Array:
	var names := sf.get_animation_names()
	for n in names:
		if n.ends_with("_" + facing):
			return [n, false]
	var opposite := String({"left": "right", "right": "left"}.get(facing, ""))
	if opposite != "":
		for n in names:
			if n.ends_with("_" + opposite):
				return [n, true]
	return [names[0], false]     # get_animation_names() is sorted, so deterministic

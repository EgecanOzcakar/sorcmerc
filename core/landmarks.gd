# Landmarks — places on the map that are not a fight.
#
# Ruins, a shrine, standing stones, a hermit's hut, a wreck, a watchtower: each
# a place the party walks up to and answers with a skill the world barely uses
# elsewhere. Two choices a kind, one visit, rewards that are not fights.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#
# What this owns: the kinds, the names, the cards (the choices and their
# checks), placement, discovery, and the reward doors. What it does not: the
# model (core/world.gd's Landmark), the drawing (scenes/world/), the save.
#
# world.gd load()s this file for a name at call time (never preloads it), so
# this side may preload world.gd for the Landmark class.
extends RefCounted

const World = preload("res://core/world.gd")

const KINDS := ["ruins", "shrine", "stones", "hut", "wreck", "tower"]
const HIDDEN := ["hut", "tower"]   # found the way lairs are; the rest are hard to miss

const NAMES := {
	"ruins": ["the Broken Chapel", "the Old Mill", "Kessel's Folly", "the Fallen Keep", "the Weir House"],
	"shrine": ["the Wayside Shrine", "the Three Saints", "the Drowned Shrine", "Mother Ash's Altar", "the Lantern Stone"],
	"stones": ["the Nine Sisters", "the Giant's Ring", "the Sleeping Stones", "the Moot Ring", "Harrow Stones"],
	"hut": ["Old Marrow's hut", "the Charcoal Hermit's hut", "Wren Hollow", "the Bee-keeper's hut", "Gallow's Hut"],
	"wreck": ["the Broken Wagon", "a wrecked barge", "the Salt Cart", "a tinker's overturned van", "the Lost Wain"],
	"tower": ["the Old Watch", "Beacon Tower", "the Broken Spire", "the Marcher's Tower", "Crow Tower"],
}

static func is_hidden(kind: String) -> bool:
	return HIDDEN.has(kind)

# Stable per id, so a reload names the same stones the same way.
static func name_for(id: String, kind: String) -> String:
	var pool: Array = NAMES.get(kind, ["a landmark"])
	return String(pool[absi(hash("landmark|%s" % id)) % pool.size()])

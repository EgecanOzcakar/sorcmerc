# T32 — the guided first fight. One hand-authored, unloseable encounter plus the
# script for the GUI walkthrough that runs over it. Data only: scenes/game/game.gd
# launches it, scenes/main.gd draws the overlay.
extends RefCounted

const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

# Same shape Campaign.combat_spec() hands scenes/main.gd: monsters + theme.
# One CR 1/4 goblin (7 HP) on the forest clearing — the only board with no
# hazards, props or chokes to explain.
const SPEC := {"monsters": [{"id": "goblin", "count": 1}], "theme": "forest-clearing"}
const DIFFICULTY := "easy"

# A sword and a healer: every button the walkthrough names is on one of them.
static func party() -> Party:
	var p := Party.new()
	p.add_member(Presets.vera())
	p.add_member(Presets.ilsa())
	return p

# One step per screen region, in reading order. `target` is resolved to a live
# Control by scenes/main.gd's _walk_target().
const STEPS := [
	{"target": "log", "title": "The action log",
	"text": "Every roll, hit, miss and heal is written down the left edge, newest at the bottom, split by round. Dice, damage numbers and names are colour-coded — if you ever wonder what just happened, it happened here."},
	{"target": "order", "title": "The turn order",
	"text": "One tile per combatant, in initiative order, with the roll in brackets. Blue is your party, red is the enemy; the gold box is whose turn it is right now. Under each name is its current and maximum HP. Faded tiles are down or dead."},
	{"target": "board", "title": "The board",
	"text": "Hexes. On your turn the blue tiles are everywhere you can still walk — click one to move there, and watch for the ⚠ tiles, which let an adjacent enemy swing at you as you leave. Pick an attack and the board switches to aiming: legal targets get a red ring and a chip showing your odds — hit chance, healing, or the enemy's chance to fail the save. Click the target to commit, right-click or Esc to back out."},
	{"target": "board", "title": "Reading a combatant",
	"text": "Each token carries its class or creature glyph, a bar under it for HP (green, amber, red as it drops) with the exact numbers beneath, and a row of glyphs above it for conditions — prone, poisoned, blinded, dying. Hover any token for the full stat card: AC, HP, speed and its whole kit."},
	{"target": "actions", "title": "Your actions",
	"text": "The same nine slots for every character: 1 Attack, 2 Spells, 3 Features, 4 Dash, 5 Disengage, 6 Dodge, 7 Help, 8 Hide, 9 Shove — then Tab to swap weapon and Space to end the turn. A slot this character can't use stays put, greyed. Spells and features open a list (numbered again, Esc backs out); hovering any badge explains it with its real numbers. Anything that spends a limited resource asks for a second press to confirm."},
	{"target": "actor", "title": "Your turn's economy",
	"text": "This line is what you have left: AC, HP, spell slots and feature uses as pips, then [action] and [bonus] while they're unspent, and how many hexes of movement remain. When all three run out the turn ends itself. That's everything — go win the fight."},
]

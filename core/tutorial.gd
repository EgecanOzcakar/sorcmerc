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

# A sword and a healer: between them the two bar shapes the walkthrough
# describes are both on screen. Vera's [3] Bonus actions is a real list (Second
# Wind and Action Surge); Ilsa's [4] is Channel Divinity itself rather than a
# "Features ▸" list, because a slot holding one thing fires it instead of
# opening a list of one. (It is greyed there — her channel-divinity pool comes
# out of the build engine with max 0, which is a rules gap of its own and not
# the bar's doing.) Her [2] holds five spells, three of them castable from two
# slot levels, which is what the tier picker is for.
static func party() -> Party:
	var p := Party.new()
	p.add_member(Presets.vera())
	p.add_member(Presets.ilsa())
	return p

# One step per screen region, in reading order. `target` is resolved to a live
# Control by scenes/main.gd's _walk_target(). The two "actions" steps describe
# the fixed bar scenes/main.gd builds in _slotted/_open_list/_spell_tier_menu —
# if that layout moves, these move with it.
#
# `try` is the practice a step invites, and only the steps that name an action
# carry one — the log and the turn order are read, not used, and the last card
# hands the whole fight over rather than asking for one more rehearsal. While
# such a step is up its own region is live instead of dimmed: the spotlight is
# a hole in the overlay (scenes/main.gd's Walk._has_point), so the board, or
# the bar, takes clicks and hovers exactly as it will once the walkthrough is
# gone. Nothing about the fight is faked for it — the move is a real move off
# a real movement budget, the list is the list.
#   act   what scenes/main.gd waits to see happen (see its _walk_try)
#   hint  the line under the card while it hasn't happened yet
#   done  what that line becomes once it has
#   keys  unlock the number row as well as the mouse for this step
# Every step stays skippable: the practice is never a gate, so a card can
# always be left with Next whether or not anybody did the thing.
const STEPS := [
	{"target": "log", "title": "The action log",
	"text": "Every roll, hit, miss and heal is written down the left edge, newest at the bottom, split by round. Dice, damage numbers and names are colour-coded — if you ever wonder what just happened, it happened here."},
	{"target": "order", "title": "The turn order",
	"text": "One tile per combatant, in initiative order, with the roll in brackets. Blue is your party, red is the enemy; the gold box is whose turn it is right now. Under each name is its current and maximum HP. Faded tiles are down or dead."},
	{"target": "board", "title": "The board",
	"text": "Hexes. On your turn the blue tiles are everywhere you can still walk — click one to move there, and watch for the ⚠ tiles, which let an adjacent enemy swing at you as you leave. Pick an attack and the board switches to aiming: legal targets get a red ring and a chip showing your odds — hit chance, healing, or the enemy's chance to fail the save. Click the target to commit, right-click or Esc to back out.",
	"try": {"act": "move",
		"hint": "Go on — click a blue hex. The goblin waits while this card is up.",
		"done": "That was a real move, off your real movement: the ➤ count on the line under the board just dropped."}},
	{"target": "board", "title": "Reading a combatant",
	"text": "Each token carries its class or creature glyph, a bar under it for HP (green, amber, red as it drops) with the exact numbers beneath, and a row of glyphs above it for conditions — prone, poisoned, blinded, dying. Hover any token for the full stat card: AC, HP, speed and its whole kit.",
	"try": {"act": "inspect",
		"hint": "Put the cursor on a token — one of yours, or the goblin.",
		"done": "That card is the whole creature. It's how you check what you're about to pick a fight with."}},
	{"target": "actions", "title": "Your action bar",
	"text": "The same nine slots for every character, in the same places every fight: 1 Attack, 2 Spells, 3 Bonus actions, 4 Features, 5 Dash, 6 Disengage, 7 Dodge, 8 Hide, 9 Help & Shove — then Tab to swap weapon and Space to end the turn. Each slot is that skill's own badge with its key in the corner; the name, what it does and its real numbers live in the popup you get by hovering it. Nothing on the bar ever moves: a slot this character can't use, or can't use this instant — Attack and Help & Shove with nobody in reach, a spent slot, a used-up feature — stays where it is, greyed, instead of closing the gap.",
	"try": {"act": "hover_slot",
		"hint": "Hover a slot — any of them — and read its popup.",
		"done": "Every slot answers like that. Hovering costs nothing, so read before you press."}},
	{"target": "actions", "title": "Lists, spell levels, confirms",
	"text": "Slots 2, 3, 4 and 9 usually hold several things, so pressing one opens its list: numbered from 1 again, Esc or the last badge goes back, and a list longer than nine pages on 9. A slot holding one thing is no choice at all, so its key fires that thing directly and no list opens. Slot 2 is every spell you can cast, in one list, cantrips first and then by level. Press one you can cast at more than one level — Burning Hands is — and a small picker asks which spell slot to spend it from, ★2 for the second-level one; Shift and the key jumps straight to that picker. Anything that burns a spell slot or a limited use arms on the first press (the badge goes warm) and fires on the second, on the same key, on whatever page you pressed it.",
	"try": {"act": "open_list", "keys": true,
		"hint": "Press [2] — or click the Spells badge — to open a list. Esc, or the last badge, comes back.",
		"done": "That's every list on the bar: numbered from 1 again, Esc to come back. Nothing you opened has been spent."}},
	{"target": "actor", "title": "Your turn's economy",
	"text": "This line is what you have left: AC, HP, then spell slots by level and feature uses as pips (● unspent, ○ spent), then Ⓐ and Ⓑ while your action and your bonus action are unspent, and ➤ with the hexes of movement still in you. When all three run out the turn ends itself. That's everything — go win the fight."},
]

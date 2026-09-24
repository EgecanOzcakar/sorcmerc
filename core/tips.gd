# #151 — one line of advice for the stop before a fight and the page after it.
# The approach card and the spoils page each show one; the picture on those
# pages is already the fight's own (the band's faction on the way in, victory
# or defeat on the way out), so this is the other half of a loading screen —
# the tip — without a screen to load. Prose only; nothing reads a tip back.
#
#   Tips.pick()   # -> String, a different one each call as far as randi allows
extends RefCounted

const TIPS := [
	"Resistance halves a spell's damage after the roll — the log's hit line says what landed; the line under it says what was rolled.",
	"A cleared lair is not a dead one: something moves back in after a day, and a band you put down is back on the roads in two.",
	"An open job's tile floats over what it names on the map. Off screen, look for the gold chevron at the frame's edge.",
	"At night the party sees as far as the light it carries. Darkvision does not need it — and neither does whatever is out there.",
	"A reaction is a question: [1] spends the slot, [2] or Space holds it. An opportunity attack costs nothing and fires on its own.",
	"Moving out of a foe's reach draws its opportunity attack. The ⚠ on a hex says so before you step.",
	"A downed hero rolls death saves each turn. Damage to a downed body is a failed save; a melee hit from reach is two.",
	"Concentration ends on a failed Con save when the caster is hit — DC 10, or half the damage if that is more.",
	"A raid stands at the town's gate for eight hours before it lands. Turn it there and the town remembers.",
	"Short rests spend Hit Dice; long rests need a settlement or a camp. The road home from a lair is where parties die.",
	"Wilderness bands scale down to a hurt party — and pay less for it. Staying wounded is not a bargain.",
	"Hover a target while aiming and the odds chip says the hit chance before you commit. A 30% swing is a 30% swing however good it feels.",
	"A hunt that got away keeps the job open: the band breaks off a day's march and the chief is still out there.",
	"Weapon mastery rides on the weapon, not the class. A Vex hit gives the next swing at that target advantage.",
	"A town's market halves after a raid and its board pays more for the lair that did it. Grief is a bounty.",
	"The party screen's Level up button is per character. A level owed is a level unspent.",
	"Prepared casters pick their list on the prepare page at the start of the day. The badge on each row is the spell's own.",
	"Surprise gives the whole side a round nobody answers. Stealth on the approach is what buys it.",
	"A tree, a standing stone or a stacked stall is a wall: nothing sees or shoots past it. Reeds are cover: stand in them for +2 AC.",
	"The field manual (F2) explains every rule the engine applies, in the words the log uses.",
]

static func pick() -> String:
	return TIPS[randi() % TIPS.size()]

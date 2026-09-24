# One-line combat barks (T26). Flavor text only — nothing here is read by any
# rule; combat.gd calls line() at a few trigger points and drops the result in a
# queue the board scene drains. Same shape as core/enemy_names.gd: a const dict,
# not a data/*.json, because it carries no mechanics to validate.
#
# Foe pools are keyed by data/bestiary.json's `faction` (T16); a faction with no
# pool, or a pool missing that trigger, falls back to FOE_GENERIC.
extends RefCounted

const CHANCE_PCT := 20   # ~1 in 5 eligible triggers speak; more than that is spam

const PARTY := {
	"hit": ["That's one.", "Hold still!", "Felt that, did you?", "Keep them off the wounded!",
		"Straight through the guard.", "Down you go — eventually."],
	"crit": ["Right through the gap!", "Found the gap.", "Bones don't bend that way.",
		"That went in.", "Couldn't miss if I tried."],
	"kill": ["One less.", "Stay down this time.", "Next.", "That's the last of your day.",
		"Rest easy. Or don't."],
	"low_hp": ["I'm hurt — cover me!", "That's a lot of blood. Mine.", "Someone patch me up!",
		"Still standing. Barely.", "Healer! Any time now!"],
	"down": ["Not… like this…", "Get up, damn you…", "Tell them I tried.", "Cold. It's cold."],
	"victory": ["Field's ours.", "Loot first, questions later.", "Everyone still breathing?",
		"That'll do. That'll do."],
}

const FOE_GENERIC := {
	"hit": ["Bleed!", "You'll tire before I do.", "Stay in range, little one."],
	"crit": ["That one will not close!", "Your bones are mine.", "Ruin!"],
	"kill": ["Another for the pile.", "Meat.", "You were nothing."],
	"low_hp": ["You will pay for that!", "Enough — ENOUGH!", "Cowards, all of you!"],
	"down": ["No… no…", "It ends…", "Aaagh!"],
	"victory": ["The ground drinks you.", "Was that all of them?", "Pick them clean."],
}

const FOE := {
	"goblinoid": {
		"hit": ["Gotcha, shiny one!", "Stick it! Stick it!", "Sharp, yes? Yes!"],
		"crit": ["That one leaks!", "Boss gonna love this!"],
		"kill": ["Mine! I get the boots!", "Squish! Ha ha!"],
		"low_hp": ["Owww! Not fair!", "Too big! TOO BIG!"],
		"down": ["No fair… no fair…", "Tell… boss…"],
		"victory": ["Loot! LOOT!", "Goblins win! Goblins always win!"],
	},
	"bandit": {
		"hit": ["Purse or blood, friend.", "Should've paid the toll.", "Nothing personal."],
		"crit": ["That's coming out of your hide!", "Clean as you like."],
		"kill": ["Your coin's mine now.", "Should've run."],
		"low_hp": ["Boys — BOYS! A hand here!", "Not worth this. Not worth this!"],
		"down": ["Tell my sister…", "Damn cheap steel…"],
		"victory": ["Strip 'em and go.", "Told you it'd be easy."],
	},
	"cultist": {
		"hit": ["The Deep One tastes you.", "Your blood is an offering.", "Kneel. Kneel!"],
		"crit": ["It moves through me!", "Witness the drowned truth!"],
		"kill": ["Accepted! The gift is accepted!", "Sink, and be welcomed."],
		"low_hp": ["Pain is a doorway…", "It hurts — it HURTS — good!"],
		"down": ["I come… I come to you…", "The tide… takes me…"],
		"victory": ["The shrine is fed.", "Praise the drowned dark."],
	},
	"undead": {
		"hit": ["Cold hands.", "Join. Us.", "Warm… still warm…"],
		"crit": ["Flesh parts so easily.", "Still. Be still."],
		"kill": ["Rise soon. Rise soon.", "One more for the dark."],
		"low_hp": ["Bones… mend…", "Cannot… be unmade…"],
		"down": ["Rest… at last…", "Quiet…"],
		"victory": ["The silence returns.", "Sleep with us."],
	},
	"beast": {
		"hit": ["*snarl*", "*snaps at you*", "*low growl*"],
		"crit": ["*savage tearing*", "*shrieks in triumph*"],
		"kill": ["*drags the body off*", "*howls*"],
		"low_hp": ["*whines, backing away*", "*bloodied, teeth bared*"],
		"down": ["*a last rattling breath*", "*whimper*"],
		"victory": ["*feeds*", "*calls to the pack*"],
	},
	"dragon": {
		"hit": ["Insect.", "You mar my scales?", "Small thing, small sting."],
		"crit": ["Now you understand.", "Centuries against your moments."],
		"kill": ["Your hoard is mine.", "Forgotten already."],
		"low_hp": ["Blood. You will not do that twice.", "This ends now, worm."],
		"down": ["Not… you…", "My hoard…"],
		"victory": ["As it was always going to be.", "Kneel, or be eaten."],
	},
}

# The bark for this trigger, or "" — most of the time it's "". `rng` must be a
# core/rng.gd so seeded runs stay reproducible.
static func line(rng, team: String, faction: String, trigger: String) -> String:
	if rng.roll_die(100) > CHANCE_PCT:
		return ""
	var pool: Array = pool_for(team, faction, trigger)
	if pool.is_empty():
		return ""
	return String(pool[rng.roll_die(pool.size()) - 1])

# T31 — which gibberish voice speaks the line. Four archetypes, VARIANTS files
# each (assets/audio/barks/<voice><n>.wav, written by tools/gen_audio.py).
const VARIANTS := 3
const VOICE := {
	"goblinoid": "squeak", "beast": "squeak",
	"cultist": "deep", "undead": "deep", "dragon": "deep",
}

static func voice(team: String, faction: String) -> String:
	if team == "party":
		return "hero"
	return String(VOICE.get(faction, "gruff"))   # bandit + anything unlisted

static func pool_for(team: String, faction: String, trigger: String) -> Array:
	if team == "party":
		return PARTY.get(trigger, [])
	var fac: Dictionary = FOE.get(faction, {})
	return fac.get(trigger, FOE_GENERIC.get(trigger, []))

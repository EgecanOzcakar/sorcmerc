# One-line combat barks (T26). Flavor text only — nothing here is read by any
# rule; combat.gd calls line() at a few trigger points and drops the result in a
# queue the board scene drains. Same shape as core/enemy_names.gd: a const dict,
# not a data/*.json, because it carries no mechanics to validate.
#
# Foe pools are keyed by data/bestiary.json's `faction` (T16); a faction with no
# pool, or a pool missing that trigger, falls back to FOE_GENERIC.
#
# Party pools are keyed by the speaker's TEMPERAMENT (the design audit,
# docs/audit-game-design.md §2.3; the eight are data/traits.json's
# `temperament` family, core/traits.gd). Until 2026-09-25 every hero drew from
# one shared pool, so a Craven thief and a Brave knight said the same five
# things in the same voice. Now each temperament has its own lines for every
# trigger, and a temperament with no line for a trigger — one a content pack
# added, or a hero from before traits, who has none — falls back to the shared
# PARTY pool. The shared pool stays, because it is also who speaks for them.
#
# One trigger names somebody: "partner_down", said by a hero whose bonded
# friend or lover (core/party_opinion.gd's is_close) just hit 0 HP. Its lines
# carry an {ally} slot, and line() is handed the fallen's name by the caller —
# combat.gd, off the Combatant that went down — so a named line always names an
# ally who is really in the fight, and one with no name to give never fires.
#
#   Barks.line(rng, "party", "", "hit", "brave")            # "" most of the time
#   Barks.line(rng, "party", "", "partner_down", "calm", "Vera")
#   Barks.pool_for("party", "", "kill", "greedy")           # what line() draws from
#   Barks.temperament(c.traits)                             # "brave", or "" for none
#
# What it does not own: when a trigger fires or who is close to whom
# (core/combat.gd, core/party_opinion.gd), the voices on disk (tools/gen_audio.py),
# or the board's speech bubbles (scenes/main.gd drains Combat.barks).
extends RefCounted

const Traits = preload("res://core/traits.gd")

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
	"partner_down": ["{ally}! Get up!", "Someone get to {ally}!", "{ally}'s down! Cover them!",
		"Not {ally}. Not today."],
}

# A partner going down is rare — a few times a campaign — and the line that
# names them is the point of the trigger, so it is not left to the 1-in-5 the
# rest take. Taste, not a sweep.
const CHANCE_BY_TRIGGER := {"partner_down": 100}

# The same triggers, said the way each temperament says them. Three a trigger
# is enough that a hero does not repeat themselves inside one fight at 20%.
const PARTY_TEMPER := {
	"brave": {
		"hit": ["Come on, then!", "Stand and take it.", "Again!"],
		"crit": ["Right where I meant it.", "That's how it's done!", "Straight in. Straight through."],
		"kill": ["Who's next?", "Down. Next one!", "That one won't get up."],
		"low_hp": ["I've had worse. I think.", "Still here! Still standing!", "Not done yet. Not close."],
		"down": ["Keep… going…", "Don't stop for me…", "Hold the line…"],
		"victory": ["Nobody ran. Good.", "We held. We held!", "That's the day won."],
		"partner_down": ["{ally}! I'm coming — hold on!", "Get away from {ally}!",
			"Stand over {ally}! Nobody touches them!"],
	},
	"craven": {
		"hit": ["Stay back! Please!", "Did that work? That worked.", "Just — fall down!"],
		"crit": ["Oh. Oh, that was good.", "I didn't even look!", "Gods, did I do that?"],
		"kill": ["Is it dead? Tell me it's dead.", "Thank everything.", "One fewer to run from."],
		"low_hp": ["I'm leaving. I'm leaving now!", "Somebody! Anybody!",
			"This is exactly what I said would happen!"],
		"down": ["Knew it… knew it…", "Should've… run…", "Don't leave me here…"],
		"victory": ["We're alive? We're alive.", "Can we go now?", "I'd like to never do that again."],
		"partner_down": ["{ally}? {ally}, get up!", "No, no — not {ally}!", "{ally}, don't you dare. Don't you dare!"],
	},
	"wrathful": {
		"hit": ["Feel that? There's more!", "Bleed for it!", "That's for starting this!"],
		"crit": ["How do you like it?", "That's what you get!", "Split you open!"],
		"kill": ["Stay down, you dog!", "Should've kept your distance.", "Who else wants some?"],
		"low_hp": ["You'll pay for every drop!", "Oh, now you've done it!", "That's it. That's it!"],
		"down": ["I'll… have you… for this…", "Not… finished…", "Damn… you…"],
		"victory": ["Is that all of them? Pity.", "Next time, send more.", "Let them tell that one."],
		"partner_down": ["You'll answer for {ally}!", "{ally}! Right. Every one of you goes down.",
			"Touch {ally} again. Try it!"],
	},
	"calm": {
		"hit": ["There.", "Steady.", "That'll slow it."],
		"crit": ["Clean.", "Exactly there.", "Well placed, if I say so."],
		"kill": ["Done. Next.", "That one's finished.", "Quiet now."],
		"low_hp": ["I need a moment. And a healer.", "Hurt. Not out.", "Someone watch my left."],
		"down": ["Keep… your heads…", "It's all right… go on…", "Mind… the others…"],
		"victory": ["Check the wounded first.", "It's over. Breathe.", "Good work. All of you."],
		"partner_down": ["{ally} is down. Cover me, I'm going to them.", "Easy. {ally} needs us steady.",
			"{ally}, stay with me. We're coming."],
	},
	"greedy": {
		"hit": ["That's a paid blow.", "Every scratch goes on the bill.", "Worth it."],
		"crit": ["Now that earned something.", "Mind the gear! That's mine after.", "Right in the purse."],
		"kill": ["Don't touch the boots. Mine.", "Somebody mark that one for me.", "Pockets, then questions."],
		"low_hp": ["I'm not paid enough for this!", "Nobody's taking my share!", "Who's paying for the healer?"],
		"down": ["My… purse…", "Don't… split my share…", "Tell them… I'm owed…"],
		"victory": ["Right. Pockets.", "Loot first. We said so.", "Now we get paid."],
		"partner_down": ["{ally}! Get up, you still owe me!", "{ally}'s down! Whoever did that pays double!",
			"Someone get to {ally} — I'll hold them off!"],
	},
	"generous": {
		"hit": ["For the wounded!", "That's one off you, friend.", "Stay behind me!"],
		"crit": ["That's for them!", "Got it! Everyone all right?", "Down it goes. Go on, help the others."],
		"kill": ["It's over for that one.", "Rest now.", "No more hurting anyone."],
		"low_hp": ["Help the others first!", "I'm fine. I'm — not fine.",
			"Don't waste the healing on — all right, do."],
		"down": ["Look after… the others…", "Share… my bread…", "Don't… stop for me…"],
		"victory": ["Everyone gets a drink. On me.", "Who's hurt? Let me see.", "We all came through. That's the prize."],
		"partner_down": ["{ally}! I've got you, I've got you!", "Somebody help me with {ally}!",
			"Hold on, {ally}. Hold on."],
	},
	"curious": {
		"hit": ["Oh, it bleeds like that?", "Interesting. Again.", "So that's where it's soft."],
		"crit": ["Found the weak spot!", "Knew there was a gap there.", "That's worth writing down."],
		"kill": ["I want a closer look at that later.", "Nobody burn that one.", "So that's how it dies."],
		"low_hp": ["Well, now I know how that feels.", "Not the lesson I wanted!", "Hurts more than the books said."],
		"down": ["What… is that… light…", "So this is… what it's like…", "Write… it down…"],
		"victory": ["Now, what did they have on them?", "Nobody touch anything till I've seen it.",
			"That was educational."],
		"partner_down": ["{ally}! Somebody see to {ally}!", "{ally}, talk to me! Say anything!",
			"That's {ally} down. Right. Think."],
	},
	"cautious": {
		"hit": ["Keep your distance and it's easy.", "Careful, careful — there.", "Slow and sure."],
		"crit": ["Waited for that one.", "Patience pays.", "Saw the opening. Took it."],
		"kill": ["Check it's dead. Properly.", "Poke it first.", "One down. Watch the rest."],
		"low_hp": ["Pulling back! Pulling back!", "Too close. Much too close.", "I said we should've scouted!"],
		"down": ["Knew… it was… a trap…", "Watch… the floor…", "Should've… checked…"],
		"victory": ["Nobody move till I've looked around.", "Could be more. Stay sharp.", "Right. Check the corners."],
		"partner_down": ["{ally}'s down! Nobody rush in!", "Get {ally} out of there — carefully!",
			"{ally}! Stay flat, I'm coming round."],
	},
}

const ALLY := "{ally}"

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
# core/rng.gd so seeded runs stay reproducible. `temper` is the speaker's
# temperament ("" for a foe or a hero with none); `ally` fills a named line's
# {ally} slot, and a named line with nobody to name is never said.
static func line(rng, team: String, faction: String, trigger: String, temper := "", ally := "") -> String:
	if rng.roll_die(100) > int(CHANCE_BY_TRIGGER.get(trigger, CHANCE_PCT)):
		return ""
	var pool: Array = pool_for(team, faction, trigger, temper)
	if pool.is_empty():
		return ""
	var text := String(pool[rng.roll_die(pool.size()) - 1])
	if ALLY in text:
		return text.replace(ALLY, ally) if ally != "" else ""
	return text

# The temperament among a hero's trait ids (Combatant.traits, Traits.ids(ch)),
# or "" — a monster, or a hero from before traits.
static func temperament(trait_ids: Array) -> String:
	for id in trait_ids:
		if Traits.family_of(String(id)) == "temperament":
			return String(id)
	return ""

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

static func pool_for(team: String, faction: String, trigger: String, temper := "") -> Array:
	if team == "party":
		var own: Array = PARTY_TEMPER.get(temper, {}).get(trigger, [])
		return own if not own.is_empty() else PARTY.get(trigger, [])
	var fac: Dictionary = FOE.get(faction, {})
	return fac.get(trigger, FOE_GENERIC.get(trigger, []))

# Local achievements. One small JSON file at  user://achievements.json  — same
# convention as core/settings.gd: a documented format, unknown keys ignored,
# unknown ids dropped on load.
#
# This is THIS MACHINE's profile, not a save: it is not per-character and not
# per-campaign, and it deliberately survives party wipes, deleted characters and
# finished runs. Nothing here is ever locked back.
#
# {
#   "format": "sorcmerc-achievements",   // literal, checked on load
#   "version": 2,                        // the shape below; a v1 file still loads
#   "unlocked": {                        // id -> ISO-8601 UTC unlock timestamp
#     "first_victory": "2026-09-10T14:02:11"
#   },
#   "counters": {"kills": 412},          // running tallies (v2)
#   "sets": {"bestiary": ["goblin"]}     // distinct things seen (v2)
# }
#
# A v1 file (no counters, no sets) loads clean: the tallies simply start at zero.
#
# --- what gameplay calls ---------------------------------------------------
#
#   Achievements.unlock("id")            idempotent, returns true the FIRST time
#   Achievements.bump("kills")           += 1, unlocks anything that threshold met
#   Achievements.record("biggest_hit", n) a high-water mark, same threshold rule
#   Achievements.collect("bestiary", id)  a distinct-things set, ditto
#
# Every one of them is a no-op when it has nothing to do, so a caller may fire
# them on every hit of every fight and still earn each achievement exactly once.
#
# --- how the toast gets on screen ------------------------------------------
#
# Anything newly earned lands in a small pending queue; the AchievementToasts
# autoload (scenes/achievements/toast.gd) drains it every frame and slides a card
# in from the top-right corner. core/*.gd owns no scene-tree nodes — same split
# core/audio.gd documents — so the model never touches the UI itself, and a
# headless run (where the autoload does not exist) just lets the queue cap out.
extends RefCounted

const SaveDir = preload("res://core/save_dir.gd")
static var PATH: String = SaveDir.path("achievements.json")
const FORMAT := "sorcmerc-achievements"
# v1 was unlocks only. v2 added the tallies, and load_state() reads both, so
# this is a record of the shape rather than a gate on it.
const VERSION := 2

# A counter write is not worth a file write: a busy fight bumps half a dozen of
# them a round. Unlocks always flush (they are rare and they are the thing you
# would be angry to lose); plain tallies coalesce into one write every few
# seconds, plus whatever flush() the toast layer does on the way out.
const SAVE_COALESCE_MS := 3000

# Nobody draining it (headless, a test, a fight that earned six things at once)
# must not grow it without bound.
const TOAST_QUEUE_MAX := 24

# --- the list --------------------------------------------------------------
#
# Every entry: id, title, desc, and a `group` (the viewer's section). Optional:
#   "counter" + "goal"  — earned when that tally reaches the goal. `counter` is
#                         a bump() key, a record() high-water mark or a collect()
#                         set; all three read back through count().
#   "hidden": true      — the viewer shows it as ??? until it is earned. For the
#                         ones that would be a spoiler, a joke spoiled, or a
#                         to-do list item ("go and lose a fight").
#
# Display order is this array's order. Ids are permanent: renaming one silently
# re-locks it on every machine that had it.
const GROUPS := [
	{"id": "blood", "label": "Blood and Steel"},
	{"id": "magic", "label": "Spellcraft"},
	{"id": "legend", "label": "Legends"},
	{"id": "coin", "label": "Coin and Commerce"},
	{"id": "road", "label": "The Road"},
	{"id": "depths", "label": "The Deep Places"},
	{"id": "company", "label": "The Company"},
	{"id": "odd", "label": "Curiosities"},
]

const DEFS := [
	# --- blood: the fight itself -------------------------------------------
	{"id": "first_victory", "group": "blood", "title": "First Blood",
		"desc": "Win your first combat."},
	{"id": "wins_25", "group": "blood", "title": "Veteran Company",
		"desc": "Win 25 fights.", "counter": "wins", "goal": 25},
	{"id": "wins_100", "group": "blood", "title": "Old Hands",
		"desc": "Win 100 fights.", "counter": "wins", "goal": 100},
	{"id": "death_save", "group": "blood", "title": "Not Today",
		"desc": "Have a character go down and survive their death saves."},
	{"id": "hard_flawless", "group": "blood", "title": "Untouchable",
		"desc": "Win a fight on hard difficulty with nobody downed."},
	{"id": "untouched", "group": "blood", "title": "Not a Scratch",
		"desc": "Win a fight without a single hero losing a hit point."},
	{"id": "kills_100", "group": "blood", "title": "Hundredfold",
		"desc": "Kill 100 enemies.", "counter": "kills", "goal": 100},
	{"id": "kills_500", "group": "blood", "title": "Butcher's Bill",
		"desc": "Kill 500 enemies.", "counter": "kills", "goal": 500},
	{"id": "kills_2000", "group": "blood", "title": "A Field of Bones",
		"desc": "Kill 2,000 enemies.", "counter": "kills", "goal": 2000},
	{"id": "crit_first", "group": "blood", "title": "Right in the Gap",
		"desc": "Land a critical hit.", "counter": "crits", "goal": 1},
	{"id": "crit_50", "group": "blood", "title": "Practised Eye",
		"desc": "Land 50 critical hits.", "counter": "crits", "goal": 50},
	{"id": "crit_250", "group": "blood", "title": "Surgeon",
		"desc": "Land 250 critical hits.", "counter": "crits", "goal": 250},
	{"id": "crit_kill", "group": "blood", "title": "Clean Finish",
		"desc": "Kill an enemy with a critical hit."},
	{"id": "fumble_first", "group": "blood", "title": "It Happens",
		"desc": "Roll a natural 1 on an attack.", "counter": "fumbles", "goal": 1},
	{"id": "fumble_50", "group": "blood", "title": "Butterfingers",
		"desc": "Roll 50 natural 1s. Statistically, this is fine.",
		"counter": "fumbles", "goal": 50},
	{"id": "both_ends", "group": "blood", "title": "Both Ends of the Die", "hidden": true,
		"desc": "Roll a natural 20 and a natural 1 in the same fight."},
	{"id": "big_hit_25", "group": "blood", "title": "Solid Connection",
		"desc": "Deal 25 damage with one blow.", "counter": "biggest_hit", "goal": 25},
	{"id": "big_hit_60", "group": "blood", "title": "Overwhelming Force",
		"desc": "Deal 60 damage with one blow.", "counter": "biggest_hit", "goal": 60},
	{"id": "big_hit_120", "group": "blood", "title": "Unmaking",
		"desc": "Deal 120 damage with one blow.", "counter": "biggest_hit", "goal": 120},
	{"id": "overkill", "group": "blood", "title": "Pulped", "hidden": true,
		"desc": "Kill something with a blow that does more than its whole health bar."},
	{"id": "oa_kill", "group": "blood", "title": "Never Turn Your Back",
		"desc": "Kill an enemy with an opportunity attack."},
	{"id": "triple_kill", "group": "blood", "title": "Reaping", "hidden": true,
		"desc": "Kill three enemies in a single turn."},
	{"id": "one_round", "group": "blood", "title": "Over Before It Started",
		"desc": "Win a fight in the first round."},
	{"id": "long_fight", "group": "blood", "title": "War of Attrition",
		"desc": "Win a fight that ran fifteen rounds or more."},
	{"id": "all_down_win", "group": "blood", "title": "All Four Knees", "hidden": true,
		"desc": "Win a fight every single hero was knocked down in."},
	{"id": "first_wipe", "group": "blood", "title": "Learning Experience", "hidden": true,
		"desc": "Lose a fight. It was always going to happen."},
	{"id": "surprise_win", "group": "blood", "title": "Nobody Saw Us Coming",
		"desc": "Win a fight that opened with a surprise round."},
	{"id": "ambush_win", "group": "blood", "title": "Rude Awakening",
		"desc": "Win a fight you were ambushed in."},
	{"id": "shove_hazard", "group": "blood", "title": "Mind the Brazier",
		"desc": "Shove an enemy into something that burns."},
	{"id": "shove_10", "group": "blood", "title": "Off You Go",
		"desc": "Win 10 shoving contests.", "counter": "shoves", "goal": 10},
	{"id": "smash_10", "group": "blood", "title": "Property Damage",
		"desc": "Smash 10 crates, barrels and the like.", "counter": "smashed", "goal": 10},
	{"id": "explosive", "group": "blood", "title": "Barrel of Laughs", "hidden": true,
		"desc": "Set off an explosive barrel."},
	{"id": "hide_first", "group": "blood", "title": "Out of Sight",
		"desc": "Slip out of sight in the middle of a fight."},
	{"id": "reaction_first", "group": "blood", "title": "Quick Hands",
		"desc": "Take a reaction.", "counter": "reactions", "goal": 1},
	{"id": "reaction_100", "group": "blood", "title": "Always Watching",
		"desc": "Take 100 reactions.", "counter": "reactions", "goal": 100},
	{"id": "parry", "group": "blood", "title": "Well Guarded",
		"desc": "Have something parry a blow of yours that was going to land."},
	{"id": "exhaust_death", "group": "blood", "title": "Spent", "hidden": true,
		"desc": "Watch something die of sheer exhaustion."},
	{"id": "bestiary_25", "group": "blood", "title": "Field Notes",
		"desc": "Kill 25 different kinds of creature.", "counter": "bestiary", "goal": 25},
	{"id": "bestiary_75", "group": "blood", "title": "Naturalist",
		"desc": "Kill 75 different kinds of creature.", "counter": "bestiary", "goal": 75},
	{"id": "bestiary_150", "group": "blood", "title": "The Compleat Bestiary",
		"desc": "Kill 150 different kinds of creature.", "counter": "bestiary", "goal": 150},
	{"id": "damage_types_6", "group": "blood", "title": "Every Flavour",
		"desc": "Deal six different types of damage.", "counter": "damage_types", "goal": 6},

	# --- magic --------------------------------------------------------------
	{"id": "spell_5th", "group": "magic", "title": "High Magic",
		"desc": "Have a character learn a spell of 5th level or higher."},
	{"id": "spells_1", "group": "magic", "title": "First Words",
		"desc": "Cast a spell in anger.", "counter": "spells", "goal": 1},
	{"id": "spells_100", "group": "magic", "title": "Well Practised",
		"desc": "Cast 100 spells.", "counter": "spells", "goal": 100},
	{"id": "spells_500", "group": "magic", "title": "An Archmage's Habit",
		"desc": "Cast 500 spells.", "counter": "spells", "goal": 500},
	{"id": "schools_8", "group": "magic", "title": "Every School",
		"desc": "Cast a spell from all eight schools of magic.",
		"counter": "schools", "goal": 8},
	{"id": "counterspell", "group": "magic", "title": "Not Today, Wizard",
		"desc": "Unravel an enemy spell as it is being cast.",
		"counter": "counterspells", "goal": 1},
	{"id": "counterspell_10", "group": "magic", "title": "Silence in the Weave",
		"desc": "Counter 10 spells.", "counter": "counterspells", "goal": 10},
	{"id": "summon_first", "group": "magic", "title": "You Are Not Alone",
		"desc": "Summon something to fight beside you.", "counter": "summons", "goal": 1},
	{"id": "summon_20", "group": "magic", "title": "Menagerie",
		"desc": "Summon 20 creatures.", "counter": "summons", "goal": 20},
	{"id": "big_heal", "group": "magic", "title": "Back on Their Feet",
		"desc": "Heal 40 hit points with a single casting.",
		"counter": "biggest_heal", "goal": 40},
	{"id": "resurrect_ally", "group": "magic", "title": "Back From the Dead",
		"desc": "Resurrect a fallen ally, by spell or by scroll."},
	{"id": "resurrect_5", "group": "magic", "title": "Death's Revolving Door",
		"desc": "Resurrect five fallen allies.", "counter": "resurrections", "goal": 5},
	{"id": "road_spell", "group": "magic", "title": "Magic on the March",
		"desc": "Cast a spell out on the road, with nothing to fight."},
	{"id": "potion_first", "group": "magic", "title": "Bottoms Up",
		"desc": "Drink a potion.", "counter": "potions", "goal": 1},
	{"id": "potion_25", "group": "magic", "title": "An Alchemist's Friend",
		"desc": "Drink 25 potions.", "counter": "potions", "goal": 25},
	{"id": "identify_item", "group": "magic", "title": "Arcane Appraiser",
		"desc": "Successfully identify a magic item."},
	{"id": "identify_25", "group": "magic", "title": "The Appraiser's Eye",
		"desc": "Identify 25 magic items.", "counter": "identified", "goal": 25},
	{"id": "identify_artifact", "group": "magic", "title": "What Have You Found", "hidden": true,
		"desc": "Identify an artifact."},
	{"id": "identify_fail_10", "group": "magic", "title": "Beyond Me", "hidden": true,
		"desc": "Fail to identify something ten times.", "counter": "identify_fails", "goal": 10},
	{"id": "trance_identify", "group": "magic", "title": "Elven Nights",
		"desc": "Have an elf puzzle out a magic item during their trance."},

	# --- legend: levels and the meta-progression ----------------------------
	{"id": "level_5", "group": "legend", "title": "Seasoned",
		"desc": "Bring a character to level 5."},
	{"id": "level_10", "group": "legend", "title": "Name Level",
		"desc": "Bring a character to level 10."},
	{"id": "level_15", "group": "legend", "title": "Peer of the Realm",
		"desc": "Bring a character to level 15."},
	{"id": "level_20", "group": "legend", "title": "Living Legend",
		"desc": "Bring a character to level 20, the highest there is."},
	{"id": "levels_50", "group": "legend", "title": "Climbing",
		"desc": "Gain 50 character levels all told.", "counter": "levels", "goal": 50},
	{"id": "levels_250", "group": "legend", "title": "The Long Climb",
		"desc": "Gain 250 character levels all told.", "counter": "levels", "goal": 250},
	{"id": "multiclass", "group": "legend", "title": "Two Roads",
		"desc": "Hold levels in two classes at once."},
	{"id": "multiclass_3", "group": "legend", "title": "Dilettante",
		"desc": "Hold levels in three classes at once."},
	{"id": "classes_6", "group": "legend", "title": "Jack of All Trades",
		"desc": "Take levels in six different classes.", "counter": "classes", "goal": 6},
	# The long one. `classes_5` is collected in core/leveling.gd's milestones()
	# and counts five levels IN a class (a fighter 3 / rogue 2 is neither), all
	# five of them EARNED at the level-up screen — the ones a preset hero opens
	# with and the ones the creator hands a new recruit are marked `granted` and
	# do not count. The goal is every playable class; tests/test_achievements.gd
	# holds it to core/progression.gd's list, so adding a thirteenth class
	# cannot quietly leave this one earnable a class short of what it claims.
	{"id": "classes_all_5", "group": "legend", "title": "The Whole Guild",
		"desc": "Keep a veteran of every class in the barracks — five levels earned in each, "
			+ "not handed over.", "counter": "classes_5", "goal": 12},
	{"id": "species_4", "group": "legend", "title": "All Walks of Life",
		"desc": "Field characters of four different species.", "counter": "species", "goal": 4},
	{"id": "created_10", "group": "legend", "title": "The Recruiter",
		"desc": "Make 10 characters.", "counter": "created", "goal": 10},
	{"id": "unlock_species", "group": "legend", "title": "New Blood",
		"desc": "Spend lifetime XP to unlock a species."},
	{"id": "unlock_class", "group": "legend", "title": "A New Calling",
		"desc": "Spend lifetime XP to unlock a class."},
	{"id": "unlock_subclass", "group": "legend", "title": "Deeper Study",
		"desc": "Spend lifetime XP to unlock a subclass."},
	{"id": "xp_100k", "group": "legend", "title": "A Career's Worth",
		"desc": "Bank 100,000 lifetime XP.", "counter": "lifetime_xp", "goal": 100000},
	{"id": "xp_500k", "group": "legend", "title": "Nothing Left to Learn",
		"desc": "Bank 500,000 lifetime XP — every species, every class, and change.",
		"counter": "lifetime_xp", "goal": 500000},

	# --- coin ---------------------------------------------------------------
	{"id": "big_spender", "group": "coin", "title": "Big Spender",
		"desc": "Spend 1,000 gold or more at merchants in a single run."},
	{"id": "gold_1000", "group": "coin", "title": "Purse Strings",
		"desc": "Have 1,000 gold at once.", "counter": "peak_gold", "goal": 1000},
	{"id": "gold_10000", "group": "coin", "title": "War Chest",
		"desc": "Have 10,000 gold at once.", "counter": "peak_gold", "goal": 10000},
	{"id": "gold_50000", "group": "coin", "title": "A Dragon's Problem",
		"desc": "Have 50,000 gold at once.", "counter": "peak_gold", "goal": 50000},
	{"id": "earned_100k", "group": "coin", "title": "The Wages of Adventure",
		"desc": "Earn 100,000 gold all told.", "counter": "gold_earned", "goal": 100000},
	{"id": "spent_25000", "group": "coin", "title": "Patron of Merchants",
		"desc": "Spend 25,000 gold all told.", "counter": "gold_spent", "goal": 25000},
	{"id": "broke", "group": "coin", "title": "Down to Coppers", "hidden": true,
		"desc": "Spend your very last gold piece."},
	{"id": "sell_500", "group": "coin", "title": "Fence",
		"desc": "Sell one item for 500 gold or more.", "counter": "best_sale", "goal": 500},
	{"id": "haggle_first", "group": "coin", "title": "Talked Down",
		"desc": "Haggle a merchant's prices down.", "counter": "haggles", "goal": 1},
	{"id": "haggle_25", "group": "coin", "title": "Never Pays List Price",
		"desc": "Win 25 haggles.", "counter": "haggles", "goal": 25},
	{"id": "persuade_market", "group": "coin", "title": "Talked Our Way In",
		"desc": "Talk a market that refused you into trading anyway."},
	{"id": "steal_first", "group": "coin", "title": "Sticky Fingers", "hidden": true,
		"desc": "Lift something off a market stall and get away with it."},
	{"id": "steal_caught", "group": "coin", "title": "Caught Red-Handed", "hidden": true,
		"desc": "Get caught with your hand on the merchandise."},
	{"id": "healer_work", "group": "coin", "title": "Honest Work",
		"desc": "Put in a morning at a healer's counter for the pay."},
	{"id": "investigate_battle", "group": "coin", "title": "Picking the Bones",
		"desc": "Turn a profit on somebody else's battlefield."},
	{"id": "loot_very_rare", "group": "coin", "title": "Treasure Hunter",
		"desc": "Loot an item of very rare quality or better."},
	{"id": "equip_legendary", "group": "coin", "title": "Wielding Legend",
		"desc": "Equip a legendary item."},
	{"id": "legendary_5", "group": "coin", "title": "Hoarder",
		"desc": "Get your hands on five different legendary items.",
		"counter": "legendaries", "goal": 5},

	# --- road: travel, quests, factions -------------------------------------
	{"id": "campaign_clear", "group": "road", "title": "The Long Road",
		"desc": "Finish a campaign: reach the boss and beat it."},
	{"id": "retire_run", "group": "road", "title": "Quit While Ahead",
		"desc": "Retire a run voluntarily instead of pushing your luck."},
	{"id": "runs_5", "group": "road", "title": "Repeat Offender",
		"desc": "Bring five runs to an end, one way or the other.",
		"counter": "runs", "goal": 5},
	{"id": "clean_run", "group": "road", "title": "Everyone Came Home",
		"desc": "Finish a campaign without losing anybody along the way."},
	{"id": "no_rest_run", "group": "road", "title": "No Time to Sit Down", "hidden": true,
		"desc": "Finish a campaign without taking a single rest."},
	{"id": "travel_event_1", "group": "road", "title": "Something on the Road",
		"desc": "Meet your first thing out between towns.",
		"counter": "road_events", "goal": 1},
	{"id": "travel_event_50", "group": "road", "title": "Well Travelled",
		"desc": "Weather 50 road events.", "counter": "road_events", "goal": 50},
	{"id": "every_road_event", "group": "road", "title": "Every Mile of It", "hidden": true,
		"desc": "See every kind of thing the road has to offer.",
		"counter": "road_event_kinds", "goal": 14},
	{"id": "forage_first", "group": "road", "title": "Living Off the Land",
		"desc": "Forage something worth having.", "counter": "forages", "goal": 1},
	{"id": "forage_25", "group": "road", "title": "Nothing Goes to Waste",
		"desc": "Forage successfully 25 times.", "counter": "forages", "goal": 25},
	{"id": "camp_first", "group": "road", "title": "Firelight",
		"desc": "Make camp out in the wild.", "counter": "camps", "goal": 1},
	{"id": "camp_ambush", "group": "road", "title": "Night Raiders", "hidden": true,
		"desc": "Have your camp jumped in the night."},
	{"id": "quest_first", "group": "road", "title": "On the Job",
		"desc": "Finish a job for somebody.", "counter": "quests", "goal": 1},
	{"id": "quests_25", "group": "road", "title": "Reliable",
		"desc": "Finish 25 jobs.", "counter": "quests", "goal": 25},
	{"id": "quest_chain", "group": "road", "title": "Trusted",
		"desc": "Work your way up a faction's chain of jobs."},
	{"id": "faction_loved", "group": "road", "title": "Friends in High Places",
		"desc": "Have a faction think the world of you.",
		"counter": "best_standing", "goal": 90},
	{"id": "faction_hated", "group": "road", "title": "Wanted", "hidden": true,
		"desc": "Have a faction want you dead on sight.",
		"counter": "worst_standing", "goal": 90},
	{"id": "settlements_6", "group": "road", "title": "Well Known",
		"desc": "Set foot in six different settlements.",
		"counter": "settlements", "goal": 6},
	{"id": "regions_4", "group": "road", "title": "Heartland to the Deeps",
		"desc": "Cross into all four of the map's regions.", "counter": "regions", "goal": 4},
	{"id": "landmarks_6", "group": "road", "title": "Surveyor",
		"desc": "Answer every kind of landmark once.", "counter": "landmark_kinds", "goal": 6},
	{"id": "landmarks_12", "group": "road", "title": "Antiquary",
		"desc": "Answer twelve landmarks.", "counter": "landmarks", "goal": 12},
	{"id": "explored_150", "group": "road", "title": "Cartographer",
		"desc": "Put 150 waypoints of one map behind you.",
		"counter": "explored", "goal": 150},

	# --- depths: lairs ------------------------------------------------------
	{"id": "lair_first", "group": "depths", "title": "Into the Dark",
		"desc": "Clear a lair out.", "counter": "lairs", "goal": 1},
	{"id": "lairs_10", "group": "depths", "title": "Warren Clearer",
		"desc": "Clear ten lairs.", "counter": "lairs", "goal": 10},
	{"id": "lair_deep", "group": "depths", "title": "Six Rooms Down",
		"desc": "Clear a lair six rooms deep.", "counter": "deepest_lair", "goal": 6},
	{"id": "lair_no_rest", "group": "depths", "title": "Straight Through",
		"desc": "Clear a lair without stopping to rest in it once."},
	{"id": "lair_wipe", "group": "depths", "title": "Dragged Out", "hidden": true,
		"desc": "Go down in a lair and get hauled back to daylight."},
	{"id": "lair_withdraw", "group": "depths", "title": "Discretion",
		"desc": "Back out of a lair with what you already have."},

	# --- company: the people ------------------------------------------------
	{"id": "bonded", "group": "company", "title": "Shoulder to Shoulder",
		"desc": "Have two of your people become genuinely close."},
	{"id": "lovers", "group": "company", "title": "Something in the Firelight",
		"desc": "Let a courtship at the campfire go somewhere."},
	{"id": "rivals", "group": "company", "title": "Bad Blood", "hidden": true,
		"desc": "Let two of your people come to loathe each other."},
	{"id": "breakup", "group": "company", "title": "It Ended Badly", "hidden": true,
		"desc": "Have a pair of lovers in the company fall out for good."},
	{"id": "friendly_fire", "group": "company", "title": "Sorry About That", "hidden": true,
		"desc": "Catch one of your own in your own spell."},
	{"id": "saved_ally", "group": "company", "title": "First Aid",
		"desc": "Pick an ally up off the floor mid-fight.",
		"counter": "allies_saved", "goal": 1},
	{"id": "saved_25", "group": "company", "title": "Field Medic",
		"desc": "Pick allies up off the floor 25 times.",
		"counter": "allies_saved", "goal": 25},
	{"id": "full_bench", "group": "company", "title": "A Full Bench",
		"desc": "Keep a roster of eight or more.", "counter": "roster_size", "goal": 8},
	{"id": "one_species", "group": "company", "title": "Family Business", "hidden": true,
		"desc": "March out with four heroes of the same species."},
	{"id": "deaths_10", "group": "company", "title": "The Cost of Doing Business", "hidden": true,
		"desc": "Lose ten characters for good.", "counter": "deaths", "goal": 10},

	# --- odd: the curiosity cabinet ----------------------------------------
	{"id": "taking_stock", "group": "odd", "title": "Taking Stock",
		"desc": "Open this very screen."},
	{"id": "read_manual", "group": "odd", "title": "Read the Manual",
		"desc": "Open the manual. Somebody had to."},
	{"id": "bug_hunter", "group": "odd", "title": "Bug Hunter",
		"desc": "File a bug report from inside the game."},
	{"id": "modded", "group": "odd", "title": "Someone Else's Map",
		"desc": "Start a campaign out of a content pack."},
	{"id": "night_owl", "group": "odd", "title": "Burning the Midnight Oil", "hidden": true,
		"desc": "Play between two and five in the morning."},
	{"id": "all_hallows", "group": "odd", "title": "All Hallows", "hidden": true,
		"desc": "Play on the thirty-first of October."},
	{"id": "new_year", "group": "odd", "title": "Another Year on the Road", "hidden": true,
		"desc": "Play on the first of January."},
	{"id": "completionist", "group": "odd", "title": "Nothing Left to Prove", "hidden": true,
		"desc": "Earn every other achievement in the game."},
]

var unlocked := {}   # id -> ISO timestamp
var counters := {}   # key -> int  (tallies and high-water marks)
var sets := {}       # key -> Array of distinct member strings

static var _current = null
static var _pending: Array = []      # newly-earned defs waiting for a toast
static var _dirty := false
static var _last_save_ms := 0
static var _by_counter := {}         # counter key -> Array of defs, built once

# The shared instance, loaded from disk on first use.
static func current():
	if _current == null:
		_current = load_state()
	return _current

static func load_state():
	var a = new()
	var txt := FileAccess.get_file_as_string(PATH)
	var d = JSON.parse_string(txt) if not txt.is_empty() else null
	if d is Dictionary and d.get("format") == FORMAT:
		var got = d.get("unlocked", {})
		if got is Dictionary:
			for def in DEFS:
				var at := String(got.get(def["id"], ""))
				if not at.is_empty():
					a.unlocked[def["id"]] = at
		# v1 files have neither of these; both simply start empty.
		var cs = d.get("counters", {})
		if cs is Dictionary:
			for k in cs:
				if cs[k] is float or cs[k] is int:
					a.counters[String(k)] = int(cs[k])
		var ss = d.get("sets", {})
		if ss is Dictionary:
			for k in ss:
				if ss[k] is Array:
					var members: Array = []
					for m in ss[k]:
						var s := String(m)
						if not s.is_empty() and not members.has(s):
							members.append(s)
					a.sets[String(k)] = members
	return a

static func to_dict(a) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "unlocked": a.unlocked,
		"counters": a.counters, "sets": a.sets}

# Returns the path written, or "" on failure.
static func save_state(a = null) -> String:
	if a == null:
		a = current()
	_current = a
	_dirty = false
	_last_save_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % PATH)
		return ""
	f.store_string(JSON.stringify(to_dict(a), "  "))
	f.close()
	return PATH

# A tally moved. Coalesced: see SAVE_COALESCE_MS.
static func _touch() -> void:
	_dirty = true
	if Time.get_ticks_msec() - _last_save_ms >= SAVE_COALESCE_MS:
		save_state()

# Write anything outstanding right now. The toast layer calls this on the way
# out; a test calls it when it wants the file to be true.
static func flush() -> void:
	if _dirty:
		save_state()

# --- unlocking -------------------------------------------------------------

# True only the first time: already-unlocked (or unknown) ids are a no-op, so a
# caller may fire this every frame it likes and still pop one toast.
static func unlock(id: String) -> bool:
	var def := find(id)
	if def.is_empty() or is_unlocked(id):
		return false
	current().unlocked[id] = Time.get_datetime_string_from_system(true)
	_queue(def)
	save_state()
	_check_completionist()
	return true

# Earning the last one earns the last one. Guarded against its own recursion by
# unlock()'s is_unlocked() check — completionist is never in the "every other"
# list it tests, so it cannot require itself.
static func _check_completionist() -> void:
	if is_unlocked("completionist"):
		return
	for def in DEFS:
		if def["id"] != "completionist" and not is_unlocked(def["id"]):
			return
	unlock("completionist")

static func is_unlocked(id: String) -> bool:
	return current().unlocked.has(id)

# ISO timestamp, or "" when locked.
static func unlocked_at(id: String) -> String:
	return String(current().unlocked.get(id, ""))

static func find(id: String) -> Dictionary:
	for def in DEFS:
		if def["id"] == id:
			return def
	return {}

# --- tallies ---------------------------------------------------------------
#
# Three shapes over one storage: a running total (bump), a high-water mark
# (record) and a set of distinct things (collect). All three land in count(),
# and all three check the same threshold defs afterwards, so a call site is
# always exactly one line and never mentions an achievement id.

static func _defs_for(key: String) -> Array:
	if _by_counter.is_empty():
		for def in DEFS:
			if def.has("counter"):
				var k := String(def["counter"])
				if not _by_counter.has(k):
					_by_counter[k] = []
				_by_counter[k].append(def)
	return _by_counter.get(key, [])

static func _check(key: String) -> void:
	var have := count(key)
	for def in _defs_for(key):
		if have >= int(def["goal"]):
			unlock(String(def["id"]))

# Add to a running tally. Returns the new total.
static func bump(key: String, n := 1) -> int:
	if n == 0:
		return count(key)
	var c = current()
	c.counters[key] = int(c.counters.get(key, 0)) + n
	_touch()
	_check(key)
	return int(c.counters[key])

# A high-water mark: the biggest single hit, the deepest lair, the fattest
# purse. Only ever moves up, and only writes when it does.
static func record(key: String, value: int) -> int:
	var c = current()
	if value <= int(c.counters.get(key, 0)):
		return int(c.counters.get(key, 0))
	c.counters[key] = value
	_touch()
	_check(key)
	return value

# A distinct-things set — monsters killed, schools cast, settlements walked
# into. Returns how many distinct members there are now.
static func collect(key: String, member: String) -> int:
	if member.is_empty():
		return count(key)
	var c = current()
	var arr: Array = c.sets.get(key, [])
	if arr.has(member):
		return arr.size()
	arr = arr.duplicate()
	arr.append(member)
	c.sets[key] = arr
	_touch()
	_check(key)
	return arr.size()

# What a threshold reads. A set's count is how many distinct members it holds.
static func count(key: String) -> int:
	var c = current()
	if c.sets.has(key):
		return (c.sets[key] as Array).size()
	return int(c.counters.get(key, 0))

static func members(key: String) -> Array:
	return (current().sets.get(key, []) as Array).duplicate()

# --- the toast queue -------------------------------------------------------

static func _queue(def: Dictionary) -> void:
	if _pending.size() >= TOAST_QUEUE_MAX:
		_pending.pop_front()
	_pending.append(def)

# Everything earned since the last call, oldest first. Drains the queue.
static func take_toasts() -> Array:
	var out := _pending
	_pending = []
	return out

static func pending_toasts() -> int:
	return _pending.size()

# --- the viewer's data -----------------------------------------------------

# Every achievement with its state, in display order — what the viewer draws.
# `have`/`goal` are 0 for the ones that are not a threshold, so a caller can
# test `goal > 0` to decide whether to draw a progress bar.
static func all() -> Array:
	var out := []
	for def in DEFS:
		var goal := int(def.get("goal", 0))
		var id := String(def["id"])
		out.append({"id": id, "title": def["title"], "desc": def["desc"],
			"group": String(def.get("group", "odd")),
			"hidden": bool(def.get("hidden", false)),
			"goal": goal, "have": mini(count(String(def.get("counter", ""))), goal) if goal > 0 else 0,
			"unlocked": is_unlocked(id), "at": unlocked_at(id)})
	return out

static func earned_count() -> int:
	var n := 0
	for def in DEFS:
		if is_unlocked(String(def["id"])):
			n += 1
	return n

static func group_label(id: String) -> String:
	for g in GROUPS:
		if g["id"] == id:
			return String(g["label"])
	return id.capitalize()

# --- the calendar oddities -------------------------------------------------
#
# Called once by the toast layer when the game starts (and by nothing else —
# core/*.gd never reads the wall clock for rules, only for these).
static func check_calendar() -> void:
	var t := Time.get_datetime_dict_from_system()
	if int(t["hour"]) >= 2 and int(t["hour"]) < 5:
		unlock("night_owl")
	if int(t["month"]) == 10 and int(t["day"]) == 31:
		unlock("all_hallows")
	if int(t["month"]) == 1 and int(t["day"]) == 1:
		unlock("new_year")

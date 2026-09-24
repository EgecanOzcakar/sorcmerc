# Which Metamagic options the board actually plays. The 2024 sorcerer picks
# from ten (data/classes.json offers all ten at levels 2, 10 and 17, because
# that is the book), but core/combat.gd resolves five of them: the ones whose
# rule is a question the board can answer about a single cast (_metamagic_option
# there). The other five are range, dice, duration, a save's advantage and a
# damage type, and each needs a hook the spell resolver does not have yet.
#
# Before this file the only record of the difference was prose (the sorcerer's
# manual page) and the match statement in combat, so the creator offered all
# ten and a player could spend a level-2 pick on Distant Spell, which then did
# nothing, silently, for the rest of the run (the design audit,
# docs/audit-game-design.md §8.5). Now there is one list, and everything that
# needs the answer reads it:
#
#   core/combat.gd         an armed option not on BUILT never takes a spell
#   core/rules/choice_pick.gd  unbuilt(p): the picker's greyed options, and why
#   core/recruits.gd       a hireling's auto-pick passes over the unbuilt ones
#   core/active_effects.gd METAMAGIC_TEXT has a line for each BUILT option
#
#   Metamagic.BUILT                        # ["quickened", ...], the option words
#   Metamagic.option_of("metamagic-twinned-spell")   # -> "twinned", "" if not one
#   Metamagic.is_built("metamagic-distant-spell")    # -> false
#
# Building a sixth option is: its rule in combat's _metamagic_option, its verb
# in data/effects/features.json (kind "metamagic"), its chip line in
# active_effects.gd, and its word here. tests/test_metamagic.gd holds the four
# together, so adding it to one and not the others fails.
#
# What this does NOT own: what an option does (core/combat.gd), its sorcery-
# point price (data/effects/features.json), or the choice itself — which
# options a level offers is the class data's, and a save that already holds an
# unbuilt pick keeps it (the creator greys only what is not picked).
extends RefCounted

# The option words, as combat's statuses["metamagic"]["option"] carries them.
const BUILT := ["quickened", "twinned", "careful", "subtle", "seeking"]

# The picker's tooltip on a greyed option.
const NOT_BUILT := "Not on the board yet"

const PREFIX := "metamagic-"
const SUFFIX := "-spell"

# "metamagic-quickened-spell" -> "quickened"; "" for a feature that is not a
# Metamagic option at all.
static func option_of(feature_id: String) -> String:
	if not (feature_id.begins_with(PREFIX) and feature_id.ends_with(SUFFIX)):
		return ""
	return feature_id.trim_prefix(PREFIX).trim_suffix(SUFFIX)

# False only for a Metamagic option the board does not play; any other feature
# is not this file's to refuse.
static func is_built(feature_id: String) -> bool:
	var opt := option_of(feature_id)
	return opt == "" or opt in BUILT

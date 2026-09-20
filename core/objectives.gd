# Encounter objectives — the same fight, asked a different question.
#
#   spec["objective"] = {"kind": "hold", "rounds": 5, "waves": [[{"id": "snik", "count": 2}]]}
#
# Absent or empty means rout (kill everyone), which is every fight the game had
# before this file. What a kind MEANS inside the fight lives in core/combat.gd
# (_objective_round / _objective_touch / _objective_over / objective_result);
# this file is what a kind IS: the knobs the sweep tunes, the tokens, the
# builders the world calls, and the words the screen shows.
#   docs/superpowers/specs/2026-09-20-encounter-objectives-design.md
#
# Preloads nothing that preloads core/encounter.gd (scaler.gd does): this file
# is preloaded by encounter.gd, combat.gd and ai.gd, so anything heavier goes
# through load() at call time.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")
const Hex = preload("res://core/hex.gd")

const KINDS := ["hold", "rescue", "breakout", "hunt", "escort"]

# --- knobs: the only things the sweep in tests/test_objectives.gd may turn ----
const HOLD_ROUNDS := 5          # hold: Victory at the top of round HOLD_ROUNDS + 1
const WAVE_ROUNDS := [2, 4]     # hold: a wave arrives at the top of each of these rounds
const WAVE_SCALE := 0.4         # hold: a wave's budget, as a share of an easy roster's
const RESCUE_DEADLINE := 4      # rescue: unfreed at the top of round RESCUE_DEADLINE + 1, the captive dies
const CAPTIVE_AC := 10
const CAPTIVE_HP := 4
const EXIT_W := 4               # breakout / hunt: how many far-edge hexes are the road out
const QUARRY_CORNERED := 3      # hunt: a hero this close makes the quarry fight rather than run
const CARTER_AC := 11
const CARTER_HP_BASE := 6
const CARTER_HP_PER_LEVEL := 2
const BONUS_XP_SHARE := 0.5     # an objective done pays this share of the whole roster's worth in XP

# --- tokens -----------------------------------------------------------------

# A bystander stands on the party's side of the board and does nothing: no
# turn, no orders, no death saves. Everything in combat.gd that keys on the
# `bystander` status is listed in the spec's §3.
static func bystander(id: String, cname: String, pos: Vector2i, ac: int, hp: int, extra: Array = []):
	var c = Combatant.new()
	c.id = id
	c.cname = cname
	c.short = cname
	c.team = "party"
	c.pos = pos
	c.ac = ac
	c.max_hp = hp
	c.hp = hp
	c.speed = 0
	c.statuses["bystander"] = true
	for s in extra:
		c.statuses[s] = true
	return c

static func captive(pos: Vector2i):
	return bystander("captive", "The captive", pos, CAPTIVE_AC, CAPTIVE_HP, ["captive"])

static func carter(pos: Vector2i, level: int):
	return bystander("carter", "The carter", pos, CARTER_AC, CARTER_HP_BASE + CARTER_HP_PER_LEVEL * maxi(1, level),
		["carter"])

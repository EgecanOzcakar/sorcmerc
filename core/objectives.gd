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

# --- builders ---------------------------------------------------------------

# An objective dict with the kind's defaults; `extra` overrides (a site passes
# its waves, a story its own deadline). Stays JSON-clean: it rides the spec
# over the co-op wire.
static func make(kind: String, extra: Dictionary = {}) -> Dictionary:
	var o := {"kind": kind}
	match kind:
		"hold":
			o["rounds"] = HOLD_ROUNDS
			o["waves"] = []
		"rescue":
			o["deadline"] = RESCUE_DEADLINE
	o.merge(extra, true)
	return o

# hold's reinforcements: one easy roster per WAVE_ROUNDS entry at WAVE_SCALE of
# its budget, on its own seed. `chars` are Characters (what Scaler wants).
static func waves_for(chars: Array, theme: String, seed: int, power_scale: float, exclude: Array = []) -> Array:
	var Scaler = load("res://core/scaler.gd")   # load: scaler.gd preloads encounter.gd, which preloads this file
	var out: Array = []
	for i in WAVE_ROUNDS.size():
		out.append(Scaler.roster_for(chars, "easy", {}, theme, seed + 17 * (i + 1), power_scale * WAVE_SCALE, exclude)["monsters"])
	return out

# The carter's HP scales with the party; `party_c` are combatants, whose sheet
# (null for a preset-less test party) carries the level.
static func party_level(party_c: Array) -> int:
	var total := 0
	var n := 0
	for c in party_c:
		if c.sheet != null:
			total += int(c.sheet.level)
			n += 1
	return maxi(1, roundi(float(total) / n)) if n > 0 else 1

# --- words ------------------------------------------------------------------

# One line, read before the board comes up: the question this fight asks.
static func brief(o: Dictionary) -> String:
	match String(o.get("kind", "")):
		"hold":
			return "Hold the passage for %d rounds. More of them will come from the far side." % int(o.get("rounds", HOLD_ROUNDS))
		"rescue":
			return "A captive is bound at the back of the room. Reach them by the end of round %d, or the captors will make sure you cannot." % int(o.get("deadline", RESCUE_DEADLINE))
		"breakout":
			return "Surrounded. Get everyone still standing to the road at the far edge — or cut your way through the lot of them."
		"hunt":
			return "Their leader will run for the far edge. Drop them before they reach it and the rest will scatter."
		"escort":
			return "The carter stands with you. If the carter dies, the delivery dies with them."
	return ""

const TITLES := {"hold": "Hold the line", "rescue": "Rescue", "breakout": "Break out",
	"hunt": "The hunt", "escort": "Escort"}

static func title(kind: String) -> String:
	return String(TITLES.get(kind, ""))

# The spoils page's row.
static func spoils_line(o: Dictionary) -> String:
	var done := bool(o.get("done", false))
	var text := ""
	match String(o.get("kind", "")):
		"hold": text = "the passage held" if done else "the passage was lost"
		"rescue": text = "the captive is out" if done else "the captive was not saved"
		"breakout": text = "the party got clear" if done else "nobody got clear"
		"hunt": text = "the quarry is down" if done else "the quarry got away"
		"escort": text = "the carter lived" if done else "the carter is dead"
	var xp := int(o.get("xp", 0))
	return "Objective — %s%s" % [text, ("  (+%d XP)" % xp) if done and xp > 0 else ""]

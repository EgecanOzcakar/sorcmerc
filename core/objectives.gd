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
#
# Measured (tests/test_objectives.gd test_sweep, 80 seeds a kind, presets at
# level 3, normal roster, autopilot with ai.gd's one rule per kind):
#   hold      done 44/80 (55.0%)   won 44/80
#   rescue    done 45/80 (56.2%)   won 62/80
#   breakout  done 46/80 (57.5%)   won 76/80
#   hunt      done 34/80 (42.5%)   won 75/80
#   escort    done 33/80 (41.2%)   won 72/80
# Re-measured 2026-09-23 after walls (Encounter.SOLID_COVER) and the AI that
# walks round them: every kind moved, escort out of the band (38.8%, 31/80) —
# monsters that used to stand against the camp's stakes now reach the carter.
# CARTER_HP_BASE 10 -> 12 put it back. It was 47.5% before.
# Re-measured 2026-09-24 after RAW death saves (three successes leave a hero
# stable and down, not up at 1 HP): escort fell to 35.0% (28/80) and every
# other kind stayed in the band. Bisected: with the old revive put back it is
# 41.2% again, so it is that rule alone — a hero who used to stand up beside
# the carter now stays on the ground. CARTER_HP_BASE 12 -> 15 put it back at
# 57.5% (46/80, won 62/80). 14 was 37.5% and 16 58.8%: there is a cliff at 15,
# the carter surviving one more goblin hit, so 15 is the smallest step in.
#   hold 56.2%  rescue 53.8%  breakout 46.2%  hunt 41.2%  escort 57.5%
# The band is 40–75%: an objective nearly free is a modifier, one nearly
# impossible is a trap. Tuned by the knobs below and never by the roster.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")

const KINDS := ["hold", "rescue", "breakout", "hunt", "escort"]

# --- knobs: the only things the sweep in tests/test_objectives.gd may turn ----
const HOLD_ROUNDS := 5          # hold: Victory at the top of round HOLD_ROUNDS + 1
const WAVE_ROUNDS := [2, 4]     # hold: a wave arrives at the top of each of these rounds
const WAVE_SCALE := 0.8         # hold: a wave's budget, as a share of an easy roster's
const RESCUE_DEADLINE := 4      # rescue: unfreed at the top of round RESCUE_DEADLINE + 1, the captive dies
const CAPTIVE_AC := 10
const CAPTIVE_HP := 4
const EXIT_W := 3               # breakout / hunt: how many far-edge hexes are the road out
const QUARRY_CORNERED := 4      # hunt: a hero this close makes the quarry fight rather than run
const CARTER_AC := 11
const CARTER_HP_BASE := 15
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
	c.statuses["bystander"] = {"no_attack": true}   # same mechanism as the illusion: never provokes, never swings
	c.econ["reaction"] = 0
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
#
# `faction` is the people the FIRST roster was drawn from, and it matters only
# when there is no theme: core/scaler.gd's _faction_order reads the faction off
# the seed itself in that case (FACTIONS[seed % size]), so the plain `+ 17` that
# gives each wave its own roll also walks it onto a different people. That is
# how an orc siege came to be reinforced by forest beasts. Re-pinned per wave,
# the roll still moves and the people do not. With a theme the theme already
# names the faction and this is a no-op.
static func waves_for(chars: Array, theme: String, seed: int, power_scale: float,
		exclude: Array = [], faction := "") -> Array:
	var Scaler = load("res://core/scaler.gd")   # load: scaler.gd preloads encounter.gd, which preloads this file
	var out: Array = []
	for i in WAVE_ROUNDS.size():
		var s: int = seed + 17 * (i + 1)
		if theme == "" and faction != "":
			s = Scaler.pin_faction(s, faction)
		out.append(Scaler.roster_for(chars, "easy", {}, theme, s, power_scale * WAVE_SCALE, exclude)["monsters"])
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
			return "Surrounded. Get everyone still standing to the road at the far edge."
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
		"breakout": text = "the company got clear" if done else "nobody got clear"
		"hunt": text = "the quarry is down" if done else "the quarry got away"
		"escort": text = "the carter lived" if done else "the carter is dead"
	var xp := int(o.get("xp", 0))
	return "Objective — %s%s" % [text, ("  (+%d XP)" % xp) if done and xp > 0 else ""]

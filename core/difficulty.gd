# T9c — the BG3-style difficulty layer. The roster generator (core/scaler.gd's
# easy/normal/hard TIER) decides WHO turns up; this decides what they are made
# of and what the road costs, as a stat overlay applied once per fight and once
# per price. Presets are BG3's shape: Explorer thins the enemy and cheapens the
# road, Tactician thickens it and taxes it, Balanced is the game as tuned.
# Custom is whatever the sliders say. Kept out of core/encounter.gd on purpose:
# every sweep and test builds fights through Encounter.build and must stay on
# Balanced regardless of what user://settings.json says — scenes/main.gd is
# the one caller that applies this, right after the build.
extends RefCounted

const PRESETS := {
	"explorer":  {"foe_hp": 0.7,  "foe_hit": 0, "foe_dmg": 0, "foe_crits": false, "camp_cost": 0.5, "trade_price": 0.8},
	"balanced":  {"foe_hp": 1.0,  "foe_hit": 0, "foe_dmg": 0, "foe_crits": true,  "camp_cost": 1.0, "trade_price": 1.0},
	"tactician": {"foe_hp": 1.25, "foe_hit": 2, "foe_dmg": 2, "foe_crits": true,  "camp_cost": 2.0, "trade_price": 1.5},
}
const KEYS := ["foe_hp", "foe_hit", "foe_dmg", "foe_crits", "camp_cost", "trade_price"]
# Slider ranges, mirrored on the settings screen.
const RANGE := {"foe_hp": [0.5, 2.0], "foe_hit": [-2, 4], "foe_dmg": [-2, 6],
	"camp_cost": [0.5, 3.0], "trade_price": [0.5, 4.0]}

# The preset whose every value matches `o`, or "custom".
static func preset_of(o: Dictionary) -> String:
	for name in PRESETS:
		var p: Dictionary = PRESETS[name]
		var same := true
		for k in KEYS:
			var v = o.get(k, PRESETS["balanced"][k])
			if p[k] is bool:
				same = same and bool(v) == bool(p[k])
			else:
				same = same and is_equal_approx(float(v), float(p[k]))
		if same:
			return name
	return "custom"

static func clamped(o: Dictionary) -> Dictionary:
	var out: Dictionary = PRESETS["balanced"].duplicate()
	for k in KEYS:
		if not o.has(k):
			continue
		if k == "foe_crits":
			out[k] = bool(o[k])
		elif k in ["foe_hit", "foe_dmg"]:
			out[k] = clampi(int(o[k]), int(RANGE[k][0]), int(RANGE[k][1]))
		else:
			out[k] = clampf(float(o[k]), float(RANGE[k][0]), float(RANGE[k][1]))
	return out

# Applied to a built Combat, before the first turn. Foes only; the party is
# untouched so Adapter.write_back stays honest.
static func apply(cb, o: Dictionary) -> void:
	var Enc = load("res://core/encounter.gd")
	cb.foe_crits = bool(o.get("foe_crits", true))
	for c in cb.combatants:
		if c.team != "foe":
			continue
		c.max_hp = maxi(1, roundi(c.max_hp * float(o.get("foe_hp", 1.0))))
		c.hp = c.max_hp
		var hit := int(o.get("foe_hit", 0))
		var dmg := int(o.get("foe_dmg", 0))
		c.atk_bonus += hit
		if c.save_dc > 0:
			c.save_dc += hit
		c.damage = Enc._bump(c.damage, dmg)
		for a in c.attacks:
			a["to_hit"] = int(a.get("to_hit", c.atk_bonus)) + hit
			a["dmg_bonus"] = int(a.get("dmg_bonus", 0)) + dmg
			a["notation"] = Enc._bump(a.get("notation", c.damage), dmg)

static func camp_cost(gp: int, o: Dictionary) -> int:
	return maxi(1, roundi(gp * float(o.get("camp_cost", 1.0))))

static func trade_scale(o: Dictionary) -> float:
	return float(o.get("trade_price", 1.0))

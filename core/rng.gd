# Seeded, deterministic RNG. xorshift32 — all shifts/xors, 32-bit safe, no overflow.
# "reproduce that fight" is the whole point in a dice game.
extends RefCounted

var seed_value: int
var _state: int

func _init(s: int = 0) -> void:
	if s == 0:
		s = int(Time.get_unix_time_from_system() * 1000.0) & 0xFFFFFFFF
	if s == 0:
		s = 1
	seed_value = s & 0xFFFFFFFF
	_state = seed_value

func _next_u32() -> int:
	var x: int = _state & 0xFFFFFFFF
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= (x >> 17)
	x ^= (x << 5) & 0xFFFFFFFF
	_state = x & 0xFFFFFFFF
	return _state

func roll_die(sides: int) -> int:
	return 1 + _next_u32() % sides

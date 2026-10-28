class_name DotNpcAiBlackboard
extends RefCounted

## What one NPC knows, as keyed values: the memory a tree or machine works over, in simulated seconds from the caller (never a wall clock, so a stalled server remembers the same).
## [b]Per NPC, not shared:[/b] a shared board turns one zombie's target into ninety zombies' target, so [member parent] is the explicit opt-in to a shared layer (reads fall through, writes never do).
## [b]Values expire:[/b] a five-minute-old sighting sends an NPC to a corner nobody has been near, so a write may carry a lifetime and a read past it is a miss.

## Read-through fallback: a squad's board, a director's board, a game's.
## [b]Never written through:[/b] one NPC's mistaken sighting would become the squad's belief.
var parent: DotNpcAiBlackboard = null

## Key -> {"value": Variant, "expires_at": float, "written_at": float}.
var _entries: Dictionary = {}


## Writes [param key]. [param lifetime] of 0 never expires.
func put(
	key: StringName, value: Variant, now: float = 0.0, lifetime: float = 0.0
) -> void:
	_entries[key] = {
		"value": value,
		"expires_at": now + lifetime if lifetime > 0.0 else 0.0,
		"written_at": now,
	}


## Reads [param key], or [param fallback] when it is missing or expired.
func get_value(key: StringName, now: float = 0.0, fallback: Variant = null) -> Variant:
	var found: Variant = _entries.get(key)

	if found is Dictionary:
		var entry: Dictionary = found
		var expires := float(entry["expires_at"])

		if expires <= 0.0 or now < expires:
			return entry["value"]

				# Removed on read rather than swept: a sweep is a pass over ninety dictionaries every tick to
				# delete things nobody would look at, and expiry on read is free and exact.
		_entries.erase(key)

	return parent.get_value(key, now, fallback) if parent != null else fallback


## Whether [param key] is present and unexpired. Falls through to [member parent].
## Asked structurally, not by comparing with a sentinel: `!=` between mismatched Variant types is a runtime ERROR in GDScript (`Vector3.ZERO != &"x"`), and `null` may be a stored value.
func has(key: StringName, now: float = 0.0) -> bool:
	var found: Variant = _entries.get(key)

	if found is Dictionary:
		var expires := float((found as Dictionary)["expires_at"])

		if expires <= 0.0 or now < expires:
			return true

		_entries.erase(key)

	return parent.has(key, now) if parent != null else false


func erase(key: StringName) -> bool:
	return _entries.erase(key)


func clear() -> void:
	_entries.clear()


## Simulated seconds since [param key] was written, or -1 when it is not there.
## What "how long since I last saw anybody" is asked with, hence a write records its own time.
func age_of(key: StringName, now: float) -> float:
	var found: Variant = _entries.get(key)

	if not (found is Dictionary):
		return parent.age_of(key, now) if parent != null else -1.0

	return now - float((found as Dictionary)["written_at"])


func get_float(key: StringName, now: float = 0.0, fallback: float = 0.0) -> float:
	var raw: Variant = get_value(key, now, null)
	return float(raw) if raw is float or raw is int else fallback


func get_int(key: StringName, now: float = 0.0, fallback: int = 0) -> int:
	var raw: Variant = get_value(key, now, null)
	return int(raw) if raw is float or raw is int else fallback


func get_bool(key: StringName, now: float = 0.0, fallback: bool = false) -> bool:
	var raw: Variant = get_value(key, now, null)
	return bool(raw) if raw is bool else fallback


func get_vector(
	key: StringName, now: float = 0.0, fallback: Vector3 = Vector3.ZERO
) -> Vector3:
	var raw: Variant = get_value(key, now, null)
	return raw if raw is Vector3 else fallback


func get_name(
	key: StringName, now: float = 0.0, fallback: StringName = &""
) -> StringName:
	var raw: Variant = get_value(key, now, null)
	return StringName(raw) if raw is StringName or raw is String else fallback


func size() -> int:
	return _entries.size()


func describe(now: float = 0.0) -> Dictionary:
	var out := {}

	for key in _entries:
		var entry: Dictionary = _entries[key]
		var expires := float(entry["expires_at"])
		out[String(key)] = "%s%s" % [
			str(entry["value"]),
			"" if expires <= 0.0 else " (%.1fs left)" % (expires - now),
		]

	return out


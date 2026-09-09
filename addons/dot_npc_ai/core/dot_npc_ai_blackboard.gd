class_name DotNpcAiBlackboard
extends RefCounted

## What one NPC knows, as keyed values. The memory a tree or a machine works over.
##
## [b]Per NPC, not shared, and that is the whole design.[/b] A shared blackboard is how
## a squad communicates and it is also how one zombie's target becomes ninety zombies'
## target — so this one is private and [member parent] is the explicit opt-in to a
## shared layer above it. A read falls through to the parent; a write never does.
##
## [b]Values expire.[/b] "I last saw the player at that corner" is the single most
## useful thing an NPC can know and the single most dangerous thing to keep: an NPC
## remembering a five-minute-old sighting walks to a corner nobody has been near since
## the round started. Every write may carry a lifetime, and a read past it is a miss.
##
## Times are simulated seconds, supplied by the caller. Never a wall clock: an NPC's
## memory must be the same on a server that stalls for a second as on one that does not.

## Read-through fallback: a squad's board, a director's board, a game's.
##
## [b]Never written through.[/b] An NPC that could write to its squad's board turns one
## NPC's mistaken sighting into the squad's belief, and every NPC in this family is
## capable of a mistaken sighting.
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

		# Removed on read rather than swept.
		#
		# A sweep needs somebody to call it every tick for every NPC, which is a pass
		# over ninety dictionaries to delete things nobody was going to look at. Expiry
		# on read costs nothing and is exact.
		_entries.erase(key)

	return parent.get_value(key, now, fallback) if parent != null else fallback


## Whether [param key] is present and unexpired. Falls through to [member parent].
##
## [b]Asked structurally rather than by comparing against a sentinel value.[/b] The
## first version returned `get_value(key, now, _MISSING) != _MISSING`, which is the
## textbook trick and does not work in GDScript: **`!=` between two mismatched Variant
## types is a runtime ERROR, not `true`.** Measured on 4.7.2 —
## `Vector3.ZERO != some_string_name` pushes
## `Invalid operands 'Vector3' and 'StringName' in operator '!='` and abandons the
## expression, so `has()` answered false for every value that was not a StringName. It
## was invisible in a suite that greps its own output, and it would have been invisible
## on a server.
##
## Comparing against `null` instead would be no better for the reason the sentinel
## existed: `null` is a value a caller may legitimately have stored, and `has` must not
## lie about it.
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
##
## What "how long since I last saw anybody" is asked with, and the reason a write
## records its own time rather than only its expiry.
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


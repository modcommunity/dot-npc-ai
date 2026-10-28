class_name DotNpcAiMemory
extends RefCounted

## What an NPC knows about its enemies: several of them, how it knows ([enum Source], so a rumour stays a rumour), and where they went.
## More than one because dot-npc's senses commit to one target; a second seen player should be known when the first dies. [method predicted] extrapolates the smoothed velocity, since the last-seen spot is a wall once the target has rounded two corners.
## Forgetting is on read, like [DotNpcAiBlackboard], from the last time anything was learned.

# No log channel: per-NPC knowledge, written and read every think.

enum Source { SIGHT, SOUND, SQUAD, DAMAGE }

## One remembered enemy.
class Entry:
	extends RefCounted

	var id: StringName = &""
	var position: Vector3 = Vector3.ZERO
	## Smoothed, from successive sightings. Zero until two of them.
	var velocity: Vector3 = Vector3.ZERO
	var first_seen: float = 0.0
	## When anything was last learned about it, by any source. What forgetting counts from.
	var last_known: float = 0.0
	## When this NPC last saw it with its own eyes. -INF if it never has.
	var last_sighted: float = -INF
	var source: Source = Source.SIGHT
	## Damage it has done to this NPC, ever. What vengeance and priority read.
	var hurt_me: float = 0.0

	func is_rumour() -> bool:
		return source == Source.SQUAD or source == Source.SOUND

	func describe(now: float) -> String:
		return "%s %s %.1fs ago at (%.1f, %.1f, %.1f)%s" % [
			String(id),
			Source.keys()[source].to_lower(),
			now - last_known,
			position.x, position.y, position.z,
			" moving %.1f m/s" % velocity.length() if velocity.length() > 0.1 else "",
		]


## Seconds an entry is kept after the last thing learned about it. From the character.
var forget_after: float = 5.0

## Longest an extrapolation runs for, in seconds. Past this a prediction is a guess.
var max_lead: float = 1.5

## Farthest an extrapolation may move a position, in metres.
## A cap stops a falling or knocked-back target being predicted into the next map.
var max_lead_distance: float = 10.0

## Sightings closer together than this are averaged for velocity; further apart they are
## two separate sightings and a velocity between them would be a guess.
var velocity_window: float = 0.6

var _entries: Dictionary = {}


## What this NPC's own eyes saw: [param id] at [param position].
func sighted(id: StringName, position: Vector3, now: float) -> Entry:
	var entry := _touch(id, now)

	if entry.last_sighted > -INF:
		var dt := now - entry.last_sighted

		if dt > 0.0001 and dt <= velocity_window:
			var measured := (position - entry.position) / dt
			# Half old, half new: a single jittery sighting cannot fling the prediction,
			# and a target that turns is followed within a few ticks.
			entry.velocity = entry.velocity.lerp(measured, 0.5)
		elif dt > velocity_window:
			entry.velocity = Vector3.ZERO

	entry.position = position
	entry.last_sighted = now
	entry.source = Source.SIGHT
	return entry


## Something heard at [param position], attributed to [param id].
## Never overrides a sighting from the same tick, and never touches velocity: a sound says where something was, not where it was going.
func heard(id: StringName, position: Vector3, now: float) -> Entry:
	var existing := get_entry(id, now)

	if existing != null and existing.last_sighted >= now:
		return existing

	var entry := _touch(id, now)
	entry.position = position
	entry.source = Source.SOUND
	return entry


## A squadmate's report. Taken only when newer than what this NPC knows.
## Never newer than first-hand knowledge from the same moment; the reporter's velocity lets a squad converge on where the target is going.
func informed(
	id: StringName, position: Vector3, velocity: Vector3, seen_at: float, now: float
) -> bool:
	var existing := get_entry(id, now)

	if existing != null and existing.last_known >= seen_at:
		return false

	var entry := _touch(id, seen_at)
	entry.position = position
	entry.velocity = velocity
	entry.source = Source.SQUAD
	return true


## [param id] hurt this NPC from [param position].
func hurt_by(id: StringName, position: Vector3, amount: float, now: float) -> Entry:
	var entry := _touch(id, now)
	entry.hurt_me += maxf(amount, 0.0)

	if entry.last_sighted < now:
		entry.position = position
		entry.source = Source.DAMAGE

	return entry


func _touch(id: StringName, now: float) -> Entry:
	var entry: Entry = _entries.get(id)

	if entry == null or _expired(entry, now):
		entry = Entry.new()
		entry.id = id
		entry.first_seen = now
		_entries[id] = entry

	entry.last_known = maxf(entry.last_known, now)
	return entry


func _expired(entry: Entry, now: float) -> bool:
	return forget_after <= 0.0 or now - entry.last_known > forget_after


## The entry for [param id], or null once it is forgotten.
func get_entry(id: StringName, now: float) -> Entry:
	var entry: Entry = _entries.get(id)

	if entry == null:
		return null

	if _expired(entry, now):
		_entries.erase(id)
		return null

	return entry


## The most recently updated entry, or null. What a search goes after with no target.
func freshest(now: float) -> Entry:
	var best: Entry = null

	for id in _entries.keys():
		var entry := get_entry(id, now)

		if entry != null and (best == null or entry.last_known > best.last_known):
			best = entry

	return best


## Where [param id] probably is now, leading its last known position by [param lead] (0..1 of [member max_lead]); [constant Vector3.INF] when forgotten.
## Horizontal only: a target that jumped is not predicted into the sky.
func predicted(id: StringName, now: float, lead: float = 1.0) -> Vector3:
	var entry := get_entry(id, now)

	if entry == null:
		return Vector3.INF

	return predict_entry(entry, now, lead)


func predict_entry(entry: Entry, now: float, lead: float = 1.0) -> Vector3:
	var flat := Vector3(entry.velocity.x, 0.0, entry.velocity.z)
	var seconds := clampf(now - entry.last_known, 0.0, max_lead) * clampf(lead, 0.0, 1.0)
	var offset := flat * seconds

	if offset.length() > max_lead_distance:
		offset = offset.normalized() * max_lead_distance

	return entry.position + offset


func forget(id: StringName) -> void:
	_entries.erase(id)


func clear() -> void:
	_entries.clear()


## Every entry still remembered.
func entries(now: float) -> Array[Entry]:
	var out: Array[Entry] = []

	for id in _entries.keys():
		var entry := get_entry(id, now)

		if entry != null:
			out.append(entry)

	return out


func size() -> int:
	return _entries.size()


func describe_lines(now: float) -> PackedStringArray:
	var out := PackedStringArray()

	for entry in entries(now):
		out.append(entry.describe(now))

	return out

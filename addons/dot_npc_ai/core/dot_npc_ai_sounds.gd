class_name DotNpcAiSounds
extends RefCounted

## Noises an NPC can hear: gunfire, footsteps, an explosion, a grenade landing. dot-npc's senses take a loudness per candidate and cannot say "somebody fired over there"; this is the world list of sounds (kind, place, radius, owner) every NPC listens to on its think.
## A game emits ([method emit]); brains listen, scaled by alertness. Events, not states: a brain hears each sound once, by id, so a half-second gunshot is not heard thirty times and an old sound is not heard on walking into its radius.
## One per world, on the director as metadata like [DotNpcAiSkill]: two servers in one process must not hear each other.

# No log channel: written by every shot and read by every NPC's think.

enum Kind {
	## Something happening in the world that is nobody's: a door, a crate breaking.
	WORLD,
	## Somebody moving. Worth turning toward; not worth running at.
	MOVEMENT,
	## Fighting: a shot, a blow, an explosion. Worth going to look at.
	COMBAT,
	## Something to get away from. The position is where the danger IS, and the radius is
	## how far it reaches — a grenade's blast, not how far its bounce is heard.
	DANGER,
}

const META := &"dot_npc_ai_sounds"

## The most sounds kept at once. The oldest go first. A firefight with sixty guns makes a
## lot of noise, and a list nobody prunes is a list every NPC walks every tick.
const CAPACITY := 128

## One noise.
class Sound:
	extends RefCounted

	var id: int = 0
	var kind: Kind = Kind.WORLD
	var position: Vector3 = Vector3.ZERO
	## How far away it can be heard, in world units, by an NPC of alertness 1.
	var radius: float = 0.0
	## How far a DANGER reaches — a blast radius — as against how far it is heard. A
	## grenade is heard across a room and only dangerous a few metres from where it lands.
	## Equal to [member radius] when not given.
	var extent: float = 0.0
	## Who made it, if anybody. A candidate id for a player; empty for the world.
	var owner: StringName = &""
	var made_at: float = 0.0
	var expires_at: float = 0.0

	func describe(now: float) -> String:
		return "#%d %s %.0fm %s %.1fs ago" % [
			id, Kind.keys()[kind].to_lower(), radius,
			String(owner) if owner != &"" else "-", now - made_at,
		]


var _sounds: Array[Sound] = []
var _next_id: int = 1


## Makes a noise. Returns its id.
## [param now] is the director's clock (`DotNpcSpawner.now()`) so expiry agrees with the listeners. [param duration] is how long it stays on the list for a brain that has not thought yet, not how long anybody hears it.
func emit(
	kind: Kind,
	position: Vector3,
	radius: float,
	now: float,
	duration: float = 0.5,
	owner: StringName = &"",
	extent: float = -1.0
) -> int:
	var sound := Sound.new()
	sound.id = _next_id
	sound.kind = kind
	sound.position = position
	sound.radius = maxf(radius, 0.0)
	sound.owner = owner
	sound.extent = sound.radius if extent < 0.0 else extent
	sound.made_at = now
	sound.expires_at = now + maxf(duration, 0.0)
	_next_id += 1

	_prune(now)
	_sounds.append(sound)

	if _sounds.size() > CAPACITY:
		_sounds.remove_at(0)

	return sound.id


## Every live sound newer than [param after_id] that a listener at [param at] can hear.
## [param hearing] scales every radius (a character's alertness), so an attentive NPC hears a shot further off.
func audible(at: Vector3, now: float, hearing: float = 1.0, after_id: int = 0) -> Array[Sound]:
	var out: Array[Sound] = []

	# Ids rise along the list (appended, dropped from the front), so start past after_id.
	var lo := 0
	var hi := _sounds.size()

	while lo < hi:
		var mid := (lo + hi) >> 1

		if _sounds[mid].id <= after_id:
			lo = mid + 1
		else:
			hi = mid

	for i in range(lo, _sounds.size()):
		var sound := _sounds[i]

		if sound.expires_at < now:
			continue

		var reach := sound.radius * maxf(hearing, 0.0)

		if at.distance_squared_to(sound.position) <= reach * reach:
			out.append(sound)

	return out


## The id the next sound will get, less one. A listener that has heard everything up to
## here passes it as `after_id` next time.
func last_id() -> int:
	return _next_id - 1


func _prune(now: float) -> void:
	var stale := false

	for sound in _sounds:
		if sound.expires_at < now:
			stale = true
			break

	if not stale:
		return

	var keep: Array[Sound] = []

	for sound in _sounds:
		if sound.expires_at >= now:
			keep.append(sound)

	_sounds = keep


func size() -> int:
	return _sounds.size()


func clear() -> void:
	_sounds.clear()


func attach(director: Node) -> void:
	if director != null:
		director.set_meta(META, self)


static func of(director: Object) -> DotNpcAiSounds:
	if director == null or not director.has_meta(META):
		return null

	return director.get_meta(META) as DotNpcAiSounds


func describe_lines(now: float) -> PackedStringArray:
	var out := PackedStringArray()

	for sound in _sounds:
		if sound.expires_at >= now:
			out.append(sound.describe(now))

	return out

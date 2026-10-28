class_name DotNpcAiSteering
extends RefCounted

## The steering an NPC needs once ninety of them path to the same door: the gap dot-npc's docs/navigation.md names, since separation is a behaviour, not a fact about the world. Without it a horde is one stack of bodies (and on rigid bodies a solver pushing them apart all tick).
## Every method returns a DESIRED DIRECTION and moves nothing, so the caller feeds `steer_toward`, a `CharacterBody3D` or a `NavigationAgent3D` and this addon needs no idea what a body is.
## All horizontal: the vertical is the ground's, and steering in Y walks an NPC into the air on a slope.

## Straight at [param goal]. The one everything else is a correction to.
static func seek(from: Vector3, goal: Vector3) -> Vector3:
	var direction := goal - from
	direction.y = 0.0

	return direction.normalized() if direction.length() > 0.001 else Vector3.ZERO


static func flee(from: Vector3, threat: Vector3) -> Vector3:
	return -seek(from, threat)


## Seek that slows inside [param radius], so an NPC stops on its target rather than orbiting it.
## Returns a direction scaled 0..1, so the caller's speed multiply is the braking; without it an NPC overshoots both ways and reads as indecisive.
static func arrive(from: Vector3, goal: Vector3, radius: float) -> Vector3:
	var direction := goal - from
	direction.y = 0.0

	var distance := direction.length()

	if distance < 0.001:
		return Vector3.ZERO

	var scale := 1.0 if radius <= 0.0 else clampf(distance / radius, 0.0, 1.0)

	return direction / distance * scale


## Away from anything within [param radius], weighted by 1/distance: linear weighting pushes a near-touching body no harder than one two metres off, so a crowd spreads evenly and still overlaps. [param others] is [Vector3] positions, not NPCs.
## [b][param tie_break] separates a STACK:[/b] one NPC directly above another has no horizontal offset, so the push is zero and they stay stacked. A caller passes its own direction ([DotNpcAiBrain] passes the NPC's right, which differs per NPC) and a degenerate pair is shoved along it.
static func separate(
	from: Vector3, others: Array, radius: float, tie_break: Vector3 = Vector3.ZERO
) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO

	var escape := Vector3(tie_break.x, 0.0, tie_break.z)
	escape = escape.normalized() if escape.length() > 0.001 else Vector3.ZERO

	var push := Vector3.ZERO

	for entry in others:
		if not (entry is Vector3):
			continue

		var offset := from - (entry as Vector3)
		var away := Vector3(offset.x, 0.0, offset.z)
		var distance := away.length()

				# The range test is HORIZONTAL: capsules one on another's head are 1.8 m apart in 3D and zero on the
				# floor, so a 1.6 m 3D range skips exactly the pair that most needs shoving. The vertical is only
				# consulted to rule out something far overhead.
		if distance > radius or absf(offset.y) > radius * 2.0:
			continue

		if distance < 0.05:
			push += escape
			continue

		push += away / distance * (1.0 - distance / radius)

	return push.normalized() if push.length() > 0.001 else Vector3.ZERO


## The average heading of everything nearby. For a group that moves as one.
static func align(headings: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0

	for entry in headings:
		if entry is Vector3:
			var flat := entry as Vector3
			flat.y = 0.0
			sum += flat
			count += 1

	if count == 0 or sum.length() < 0.001:
		return Vector3.ZERO

	return sum.normalized()


## Toward the centre of everything nearby. The other half of a flock.
static func cohere(from: Vector3, others: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0

	for entry in others:
		if entry is Vector3:
			sum += entry as Vector3
			count += 1

	if count == 0:
		return Vector3.ZERO

	return seek(from, sum / float(count))


## A heading that drifts rather than jumping. For an NPC with nothing to do.
## A random direction per tick averages to standing still (a seizure) and one every few seconds is a robot; an angle taking a small random step each tick reads as an animal.
## [param seed_value] makes it deterministic per NPC so a suite can replay a horde.
static func wander(current_angle: float, jitter: float, seed_value: int) -> float:
	# A hash rather than `randf()`, because a global RNG makes one NPC's wandering
	# depend on how many other NPCs wandered first — and that makes a replay of the
	# same inputs produce a different world.
	var mixed := hash(seed_value)
	var unit := float(mixed % 20011) / 20011.0 * 2.0 - 1.0

	return fposmod(current_angle + unit * jitter, TAU)


static func angle_to_direction(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle))


## Blends weighted directions into one. The last step of every steering pass.
## [param weighted] is `[Vector3, float]` pairs. Normalised, so weights decide balance and never speed: an un-normalised blend runs faster when two urges agree.
static func blend(weighted: Array) -> Vector3:
	var sum := Vector3.ZERO

	for entry in weighted:
		if not (entry is Array) or (entry as Array).size() < 2:
			continue

		var pair := entry as Array

		if pair[0] is Vector3:
			sum += (pair[0] as Vector3) * float(pair[1])

	sum.y = 0.0

	return sum.normalized() if sum.length() > 0.001 else Vector3.ZERO


## Heads for where a moving target is going to be, rather than where it is (Reynolds' pursuit): seeking a runner's current position is a tail chase that never closes.
## [param own_speed] of zero means "no idea" and gives a plain seek, since a chaser with no speed has no time to predict over.
static func pursue(
	from: Vector3, target: Vector3, target_velocity: Vector3, own_speed: float
) -> Vector3:
	if own_speed <= 0.0:
		return seek(from, target)

	var distance := from.distance_to(target)

	# The prediction horizon is capped. Extrapolating a target's current velocity three
	# seconds forward has it running through walls, and the NPC steers confidently at
	# somewhere nobody will ever be.
	var ahead := minf(distance / own_speed, 2.0)

	return seek(from, target + target_velocity * ahead)


## The mirror: away from where a threat is going to be.
static func evade(
	from: Vector3, threat: Vector3, threat_velocity: Vector3, own_speed: float
) -> Vector3:
	if own_speed <= 0.0:
		return flee(from, threat)

	var distance := from.distance_to(threat)
	var ahead := minf(distance / own_speed, 2.0)

	return flee(from, threat + threat_velocity * ahead)


## Deflects [param direction] around anything in the way. [param obstacles] is `{position: Vector3, radius: float}` (props, NPCs, a vehicle); returns a unit direction, or [param direction] when nothing matters.
## Not pathfinding: it looks only [param look_ahead] metres down the heading, so dot-npc's graph decides the route and this stops scraping the furniture.
## Deflects sideways rather than stopping: braking in front of an obstacle piles a crowd at a doorway for ever.
static func avoid(
	direction: Vector3,
	from: Vector3,
	obstacles: Array,
	look_ahead: float = 3.0,
	own_radius: float = 0.5
) -> Vector3:
	if direction.length_squared() <= 0.0001 or obstacles.is_empty():
		return direction

	var heading := direction.normalized()
	var worst_distance := INF
	var push := Vector3.ZERO

	for entry in obstacles:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var row: Dictionary = entry
		var position: Vector3 = row.get("position", Vector3.ZERO)
		var radius := float(row.get("radius", 0.5)) + own_radius

		var to_obstacle := position - from
		to_obstacle.y = 0.0

		var along := to_obstacle.dot(heading)

		# Behind, or too far ahead to be this move's problem.
		if along <= 0.0 or along > look_ahead + radius:
			continue

		# Distance from the obstacle's centre to the line being walked. Anything
		# further than its radius is not in the way, however close it is.
		var lateral := (to_obstacle - heading * along).length()

		if lateral > radius:
			continue

		if along >= worst_distance:
			continue

		worst_distance = along

		var side := (to_obstacle - heading * along)

		if side.length_squared() <= 0.0001:
						# Dead ahead: the cross product gives no side, so choose one from the obstacle's position, not at
						# random, so two NPCs approaching the same barrel from the same side go the same way instead of
						# dancing.
			side = heading.cross(Vector3.UP)
			if side.length_squared() <= 0.0001:
				side = Vector3.RIGHT

		# Strongest when the obstacle is directly in the path and when it is close.
		var urgency := (1.0 - lateral / radius) * (1.0 - along / (look_ahead + radius))
		push = -side.normalized() * urgency

	if push.length_squared() <= 0.0001:
		return heading

	return (heading + push).normalized()


## Whether anything in [param obstacles] blocks the next [param look_ahead] metres.
## What [method avoid] answers implicitly, exposed because "is my way clear" is a tree branch, not a steering force.
static func is_way_clear(
	direction: Vector3,
	from: Vector3,
	obstacles: Array,
	look_ahead: float = 3.0,
	own_radius: float = 0.5
) -> bool:
	if direction.length_squared() <= 0.0001:
		return true

	var heading := direction.normalized()

	for entry in obstacles:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var row: Dictionary = entry
		var position: Vector3 = row.get("position", Vector3.ZERO)
		var radius := float(row.get("radius", 0.5)) + own_radius

		var to_obstacle := position - from
		to_obstacle.y = 0.0

		var along := to_obstacle.dot(heading)

		if along <= 0.0 or along > look_ahead + radius:
			continue

		if (to_obstacle - heading * along).length() <= radius:
			return false

	return true

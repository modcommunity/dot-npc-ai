class_name DotNpcAiSteering
extends RefCounted

## The steering an NPC needs once there are ninety of them pathing to the same door.
##
## [b]This is the gap dot-npc's CLAUDE.md names.[/b] dot-npc paths and follows; it says
## nothing about two NPCs that want to be in the same place, because separation is a
## behaviour rather than a fact about the world. Without it a horde arriving at a
## doorway is a single NPC-shaped stack of ninety bodies, which is both the wrong look
## and, on rigid bodies, a solver spending the whole tick pushing them apart.
##
## [b]Every method returns a DESIRED DIRECTION, and moves nothing.[/b] The caller
## combines them and hands the result to whatever drives the body — dot-npc's
## `steer_toward`, a `CharacterBody3D`, a `NavigationAgent3D`. A steering library that
## moved things would have to know what a body is, and that is exactly the dependency
## this addon does not take.
##
## All of it is horizontal. The vertical is the ground's business, and an NPC that
## steered in Y walks into the air on a slope.

## Straight at [param goal]. The one everything else is a correction to.
static func seek(from: Vector3, goal: Vector3) -> Vector3:
	var direction := goal - from
	direction.y = 0.0

	return direction.normalized() if direction.length() > 0.001 else Vector3.ZERO


static func flee(from: Vector3, threat: Vector3) -> Vector3:
	return -seek(from, threat)


## Seek that slows inside [param radius], so an NPC stops on its target rather than
## orbiting it.
##
## Returns a direction scaled between 0 and 1, not a unit vector — the caller multiplies
## by a speed, so the scaling is the braking. An NPC without this overshoots, turns,
## overshoots the other way, and reads as indecisive rather than as un-braked.
static func arrive(from: Vector3, goal: Vector3, radius: float) -> Vector3:
	var direction := goal - from
	direction.y = 0.0

	var distance := direction.length()

	if distance < 0.001:
		return Vector3.ZERO

	var scale := 1.0 if radius <= 0.0 else clampf(distance / radius, 0.0, 1.0)

	return direction / distance * scale


## Away from anything within [param radius], weighted by how close it is.
##
## [param others] is an array of [Vector3] positions, which is deliberately not a list
## of NPCs: the caller already has the positions and this addon should not have to know
## what it is separating.
##
## [b]Weighted by 1/distance rather than by distance.[/b] Linear weighting makes the
## thing that is nearly touching you push about as hard as the one two metres away,
## which is a crowd that spreads evenly and still overlaps. What is wanted is a shove
## that is almost nothing at the edge of the radius and very strong at contact.
##
## [b][param tie_break] is what separates a STACK, and without it nothing does.[/b] This
## is horizontal, like everything else here — and two NPCs one directly above the other
## have a horizontal offset of nothing, so the push is nothing and they stay stacked for
## ever. That is not a hypothetical: twelve capsules converging on one point in this
## addon's own suite ended with one perched on another's head, chasing perfectly, at a
## dead stop, with every number about it correct. A caller passes a direction of its
## own — [DotNpcAiBrain] passes the NPC's right, which differs per NPC because they face
## different ways — and a degenerate pair is shoved along it instead.
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

		# The range test is HORIZONTAL, and that is the fix for the stack.
		#
		# A 3D test looks right and is wrong here: two capsules one on another's head
		# are about 1.8 m apart in 3D and zero apart on the floor, so a 1.6 m 3D range
		# skips exactly the pair that most needs shoving — which is how one of them
		# stayed perched, chasing perfectly, at a dead stop, in this addon's own suite.
		# The vertical is only consulted to rule out something far overhead.
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
##
## [b]The wander that works is a drifting angle, not a random direction per tick.[/b] A
## fresh random direction every tick averages to standing still and looks like a seizure;
## a random direction re-picked every few seconds looks like a robot on a patrol route.
## An angle that takes a small random step each tick gives the aimless drift that reads
## as an animal.
##
## [param seed_value] makes it deterministic per NPC, which is what lets a suite replay a
## horde and get the same horde.
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
##
## [param weighted] is an array of `[Vector3, float]` pairs. The result is normalised, so
## the weights decide the balance and never the speed — a caller multiplying an
## un-normalised blend by a speed gets an NPC that runs faster when two urges happen to
## agree, which is invisible until somebody wonders why fleeing is quicker than chasing.
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


## Heads for where a moving target is going to be, rather than where it is.
##
## [b]Seek at a moving target is a tail chase.[/b] An NPC that steers at a runner's
## current position approaches from behind for ever and never closes, which reads as an
## NPC that is slower than it is. Craig Reynolds' pursuit: estimate how long it will
## take to get there, and aim at where the target will be then.
##
## [param own_speed] of zero means "no idea", and the result is a plain seek — which is
## the right answer, because a chaser with no speed has no time to predict over.
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


## Deflects [param direction] around anything in the way.
##
## [param obstacles] is an array of [code]{position: Vector3, radius: float}[/code] —
## whatever the game already knows is solid: props, other NPCs, a vehicle. The result
## is a unit direction, or [param direction] when nothing is close enough to matter.
##
## [b]This is not pathfinding and must not be used as it.[/b] It only looks
## [param look_ahead] metres down the current heading, so it walks an NPC round a
## barrel and into a dead end — which is the correct division: dot-npc's graph decides
## the route and this stops the NPC scraping the furniture on the way.
##
## The deflection is sideways rather than a stop. Braking in front of an obstacle is
## what makes a crowd of NPCs pile up at a doorway and never resolve; stepping round it
## is what makes them flow.
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
			# Dead ahead, exactly. Any side will do and the cross product gives none,
			# so a fixed one is chosen — and it is chosen from the obstacle's position
			# rather than at random, so two NPCs approaching the same barrel from the
			# same side both go the same way instead of dancing.
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
##
## The question [method avoid] answers implicitly, exposed because a tree wants to ask
## it as a condition — "is my way clear" is a branch, not a steering force.
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

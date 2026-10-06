class_name DotNpcAiTactics
extends RefCounted

## Where to stand: around an enemy, behind it, and the best of a set of places.
##
## Like [DotNpcAiSteering], every function answers with a position or a score and moves
## nothing, so it can be used by a brain, a director placing an ambush, or a suite.
##
## [b]Surrounding is the behaviour this exists for.[/b] With [DotNpcAiSquad]'s attack slots,
## the NPCs that are not attacking need somewhere to be, and the two bad answers are "in a
## queue behind the attackers" and "standing still where they were". The good one is a ring
## round the enemy just out of reach, spread out, working round to the side the enemy is
## not facing — so when an attacker falls the next one is already close, and the player
## who turns to face one has turned their back on another.

# No log channel: pure functions.

## A point on a ring of [param radius] round [param center], for an NPC at [param from].
##
## The NPC holds its own bearing — the nearest point of the ring — so a crowd fans out by
## where each one already is rather than all heading for one spot. [param flank] (radians)
## places the point that far round toward the side opposite [param enemy_facing], at most:
## the NPC walks at it, its bearing advances, and next tick the point is further round, so
## it circles behind the enemy at walking pace rather than teleporting there.
##
## [b]A lead angle, not a per-tick step.[/b] The first version took `rate * delta`, which
## put the point a few centimetres ahead — inside any sensible "arrived" distance — so the
## NPC arrived, stopped, and never got round at all.
##
## [param enemy_facing] may be zero, and then there is no "behind" to work toward.
static func ring_point(
	center: Vector3,
	from: Vector3,
	radius: float,
	enemy_facing: Vector3 = Vector3.ZERO,
	flank: float = 0.0
) -> Vector3:
	var offset := from - center
	offset.y = 0.0

	if offset.length_squared() < 0.0001:
		# Standing on the enemy. Any bearing is as good; behind it is better.
		offset = -enemy_facing if enemy_facing.length_squared() > 0.0001 else Vector3.FORWARD

	var bearing := atan2(offset.z, offset.x)

	var facing := Vector3(enemy_facing.x, 0.0, enemy_facing.z)

	if flank > 0.0 and facing.length_squared() > 0.0001:
		var behind := atan2(-facing.z, -facing.x)
		var gap := wrapf(behind - bearing, -PI, PI)
		bearing += clampf(gap, -flank, flank)

	return center + Vector3(cos(bearing), 0.0, sin(bearing)) * radius


## A point on the ring of [param radius] round [param center], moved from [param from]'s
## bearing toward [param bearing] by at most [param max_step] radians.
##
## [method ring_point] with the destination given as a bearing rather than as "behind": what
## a squad member walks at once [method spread_bearings] has told it which place is its own.
static func ring_toward(
	center: Vector3, from: Vector3, radius: float, bearing: float, max_step: float
) -> Vector3:
	var offset := from - center
	offset.y = 0.0
	var own := atan2(offset.z, offset.x) if offset.length_squared() > 0.0001 else bearing
	var gap := wrapf(bearing - own, -PI, PI)
	var heading := own + clampf(gap, -max_step, max_step)
	return center + Vector3(cos(heading), 0.0, sin(heading)) * radius


## A bearing each for [param positions] round [param center], spread [param step] radians
## apart across an arc centred on [param focus]. Returned in the order of [param positions].
##
## [b]Handed out in the order they already stand[/b], measured round from the focus, so the
## NPC furthest round one way gets the place furthest round that way and no two cross each
## other's path to get to theirs. Without a share-out every NPC walks at "directly behind",
## they arrive at one point, and a surround is a heap — which is what the first version of
## this did, and a picture of it, not a check, is what showed it.
static func spread_bearings(
	center: Vector3, focus: float, positions: Array, step: float, max_arc: float = TAU * 0.85
) -> PackedFloat32Array:
	var n := positions.size()
	var out := PackedFloat32Array()
	out.resize(n)

	if n == 0:
		return out

	var order: Array = []

	for i in n:
		var offset: Vector3 = positions[i] - center
		var rel := wrapf(atan2(offset.z, offset.x) - focus, -PI, PI)
		order.append([rel, i])

	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var arc := minf(step * float(n - 1), max_arc)
	var gap := arc / float(n - 1) if n > 1 else 0.0

	for k in n:
		out[int(order[k][1])] = focus - arc * 0.5 + gap * float(k)

	return out


## The circular mean of where [param positions] stand round [param center], in radians.
static func mean_bearing(center: Vector3, positions: Array) -> float:
	var sum := Vector2.ZERO

	for at in positions:
		var offset: Vector3 = at - center
		var flat := Vector2(offset.x, offset.z)

		if flat.length_squared() > 0.0001:
			sum += flat.normalized()

	return sum.angle() if sum.length_squared() > 0.0001 else 0.0


## How far round from the enemy's back [param from] stands, in radians. 0 is directly
## behind; PI is in front of it. What a suite measures flanking with.
static func angle_from_behind(center: Vector3, enemy_facing: Vector3, from: Vector3) -> float:
	var offset := from - center
	offset.y = 0.0
	var behind := Vector3(-enemy_facing.x, 0.0, -enemy_facing.z)

	if offset.length_squared() < 0.0001 or behind.length_squared() < 0.0001:
		return 0.0

	return offset.normalized().angle_to(behind.normalized())


## The index of the best of [param candidates] by [param scorer], or -1.
##
## [param scorer] is `func(position: Vector3, index: int) -> float`; higher is better, and
## -INF rules a place out. Utility scoring rather than a fixed rule, because "the best place
## to stand" is always a trade — near against covered, close to the enemy against exposed to
## it — and a trade written as an if-chain is the one that stands in the open.
static func best_of(candidates: PackedVector3Array, scorer: Callable) -> int:
	var best := -1
	var best_score := -INF

	for i in candidates.size():
		var score := float(scorer.call(candidates[i], i))

		if score > best_score:
			best_score = score
			best = i

	return best

class_name DotNpcAiTactics
extends RefCounted

## Where to stand: around an enemy, behind it, and the best of a set of places.
##
## Like [DotNpcAiSteering], every function answers with a position or a score and moves nothing.
## Surrounding is the point: NPCs without an attack slot ([DotNpcAiSquad]) take a spread ring round the enemy,
## working round to the side it is not facing, so a player facing one has turned their back on another.

# No log channel: pure functions.

## A point on a ring of [param radius] round [param center], for an NPC at [param from], holding its own bearing.
## [param flank] radians toward the side opposite [param enemy_facing] is a lead angle, not a per-tick step
## (`rate * delta` lands inside any "arrived" distance); a zero [param enemy_facing] has no "behind".
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
## Handed out in the order they already stand, measured round from the focus, so no two cross paths;
## without a share-out every NPC walks at "directly behind" and a surround is a heap.
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
## -INF rules a place out. Scored rather than an if-chain, because "best place" is always a trade.
static func best_of(candidates: PackedVector3Array, scorer: Callable) -> int:
	var best := -1
	var best_score := -INF

	for i in candidates.size():
		var score := float(scorer.call(candidates[i], i))

		if score > best_score:
			best_score = score
			best = i

	return best


## The best place on a ring round [param center] for [param from] to flank from, or INF when there is none.
##
## Scored through [method best_of]: higher for being behind [param enemy_facing] (by [method angle_from_behind]),
## lower for each of [param allies] already within the ally radius and for the walk there. Weights are the
## token config's, so a game tunes flanking from a file.
static func best_flank(
	center: Vector3, enemy_facing: Vector3, from: Vector3, radius: float, allies: Array, cfg: DotNpcAiTokenConfig
) -> Vector3:
	var ring := PackedVector3Array()
	var count := maxi(cfg.flank_candidates, 3)

	for i in count:
		var bearing := TAU * float(i) / float(count)
		ring.append(center + Vector3(cos(bearing), 0.0, sin(bearing)) * radius)

	var half_ring := maxf(PI * radius, 0.001)
	var pick := best_of(ring, func(at: Vector3, _i: int) -> float:
		var score := cfg.flank_angle_weight * (1.0 - angle_from_behind(center, enemy_facing, at) / PI)

		for ally: Vector3 in allies:
			if ally.distance_to(at) < cfg.flank_ally_radius:
				score -= cfg.flank_spread_weight

		return score - cfg.flank_travel_weight * from.distance_to(at) / half_ring)

	return ring[pick] if pick >= 0 else Vector3.INF

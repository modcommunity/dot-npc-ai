extends "dot_npc_ai_brain_state.gd"

## Steering, pathing and the scheduler hookup of [DotNpcAiBrain]: how the NPC moves. Not a public class: extend [DotNpcAiBrain] (by path), never this.


## The scheduler on the registry, or null.
func _find_scheduler() -> DotNpcAiScheduler:
	var found: Object = DotNpcAiScheduler.find()
	return found as DotNpcAiScheduler if found != null and is_instance_valid(found) else null


func _join_scheduler() -> void:
	scheduler.register(self)
	if director != null and director.has_signal(&"target_changed") \
			and not director.is_connected(&"target_changed", scheduler.notice_target):
		director.connect(&"target_changed", scheduler.notice_target)


## The live scheduler or null: a freed one is dropped, and one registered after this brain was bound is found within a second.
func _sched() -> DotNpcAiScheduler:
	if scheduler != null:
		if is_instance_valid(scheduler):
			return scheduler
		scheduler = null

	_sched_probe -= 1
	if _sched_probe <= 0:
		_sched_probe = 60
		scheduler = _find_scheduler()
		if scheduler != null and context != null:
			_join_scheduler()
	return scheduler


## Records where this think steered, so a throttled tick can keep walking there.
func steer_toward(to: Vector3, speed: float, delta: float) -> void:
	if _thinking:
		delta = _step_delta

	if not _cruising:
		_cruise_on = true
		_cruise_to = to
		_cruise_speed = speed
		_cruise_dest = Vector3.INF

	super(to, speed, delta)


## [method DotNpcBrain.steer_along_path] that remembers the destination and asks the scheduler for the path.
func steer_along_path(to: Vector3, speed: float, delta: float) -> void:
	if npc == null or not npc.is_alive():
		return

	var goal := _steer_goal(to)
	_cruise_dest = to
	if goal == Vector3.INF:
		return
	steer_toward(goal, speed, delta)
	_cruise_dest = to


## One throttled tick: keep walking the last target. A reached waypoint asks for the next one through the path cache.
func _cruise(delta: float) -> void:
	if not cruise_between_thinks or not _cruise_on or npc == null or not npc.is_alive():
		return

	var here := npc.position()
	var flat := _cruise_to - here
	flat.y = 0.0

	if flat.length() < 1.0 and _cruise_dest != Vector3.INF:
		var rest := _cruise_dest - here
		rest.y = 0.0

		if rest.length() > 1.5:
			var next := _path_goal(_cruise_dest)

			if next != Vector3.INF:
				_cruise_to = next
				flat = next - here
				flat.y = 0.0

	if flat.length() < 0.3:
		return

	_cruising = true
	steer_toward(_cruise_to, _cruise_speed, delta)
	_cruising = false


## The next point on the way to [param to] from the director's path, or INF. Sets [member _path_denied] when the scheduler refused to compute one.
## Calmer tiers reuse a path while the destination drifts less than `path_reuse_m`; allocation-free.
func _path_goal(to: Vector3) -> Vector3:
	_path_denied = false
	if director == null or not director.has_method(&"path_toward"):
		return Vector3.INF

	var sched := _sched()
	if sched == null or not sched.config.enabled:
		return _as_goal(director.call(&"path_toward", npc, path, to))

	var capped := sched.config.cap_tier0_paths
	if sched.tier_of(self) == 0 and not capped:
		return _as_goal(director.call(&"path_toward", npc, path, to))

	var reuse := sched.config.path_reuse_m
	if sched.tick < _pg_until and _pg_to.distance_squared_to(to) <= reuse * reuse:
		sched.stats["cache_hits"] += 1
		return _pg_goal

	if not sched.take_path_slot():
		_path_denied = true
		return Vector3.INF

	var goal := _as_goal(director.call(&"path_toward", npc, path, to))
	if sched.tier_of(self) > 0:
		_pg_to = to
		_pg_goal = goal
		_pg_until = sched.tick + sched.config.path_cache_ticks
	return goal


func _as_goal(found: Variant) -> Vector3:
	if found is Vector3:
		_waypoint = found
		return found
	return Vector3.INF


## Where to steer for [param to]: the path's next point, the target itself when there is no path, the last waypoint
## when the scheduler refused a path this frame (a straight line would cut through walls), or INF to wait.
func _steer_goal(to: Vector3) -> Vector3:
	var goal := _path_goal(to)
	if goal != Vector3.INF:
		return goal
	return _waypoint if _path_denied else to


## Whether the line to [param to] is clear, reusing the answer for a few ticks under a scheduler.
## [param compute] is `func() -> bool`; a tier too calm for sight tests is told no.
func line_clear(to: Vector3, compute: Callable) -> bool:
	var sched := _sched()
	if sched == null or not sched.config.enabled:
		return compute.call()

	if not sched.los_allowed(self):
		sched.stats["los_blocked"] += 1
		return false

	if sched.tick < _los_until and _los_to.distance_squared_to(to) <= 1.0:
		sched.stats["cache_hits"] += 1
		return _los_val

	_los_val = compute.call()
	_los_to = to
	_los_until = sched.tick + sched.config.los_cache_ticks
	sched.stats["los_hits"] += 1
	return _los_val


## Stops the body and the between-thinks walk with it.
func halt() -> void:
	_cruise_on = false
	super()


## The director's clock, which is the one dot-npc's senses stamp targets with.
func _world_now() -> float:
	if director != null and director.has_method(&"now"):
		return float(director.call(&"now"))

	return context.now if context != null else 0.0


## Turns toward [param direction] no faster than this character can.
## Every turn the brain makes goes through here, steering included (dot-npc's `steer_toward` faces the way it moves), so the sight cone swings at [member DotNpcAiCharacter.view_turn_deg]; otherwise NPCs snap round in one tick and a player cannot get behind one.
## Limited from where the NPC faced at the START of the think, so a steer and then a look do not turn it twice as far.
func face(direction: Vector3) -> void:
	if character == null or context == null or context.delta <= 0.0 or npc == null:
		super(direction)
		return

	var flat := Vector3(direction.x, 0.0, direction.z)

	if flat.length_squared() < 0.000001:
		return

	var from := _facing_at_tick if _facing_at_tick.length_squared() > 0.0001 else npc.facing()
	super(character.turn_view(from, flat.normalized(), context.delta))


## The nearby positions a separation pass needs, asked of the director.
## Duck-typed so this file names one dot-npc class and no more: a host that publishes `npcs_near` gets crowd avoidance, one that does not gets an empty array (the same as nobody nearby).
func neighbours(radius: float) -> Array:
	var out: Array = []

	if director == null or npc == null or not npc.is_alive():
		return out

	if not director.has_method(&"npcs_near"):
		return out

		# Queried wider than the spacing, because `npcs_near` measures in 3D and a separation radius is
		# horizontal: an NPC on another's head is a body height away in 3D and nothing on the floor, so a
		# query at the spacing misses the pair that most needs pushing apart.
	var found: Variant = director.call(&"npcs_near", npc.position(), radius * 2.0)

	if not (found is Array):
		return out

	for entry in (found as Array):
		var other := entry as DotNpcInstance

		if other != null and other.instance_id != npc.instance_id:
			out.append(other.position())

	return out


## The push away from the neighbours within [param spacing] of [param here]: what
## [method steer_with_spacing] and [method surround] blend in. A host with its own crowd index
## overrides it (see [DotNpcAiCrowdGrid]) to skip building [method neighbours]' array.
func separation(here: Vector3, spacing: float, right: Vector3) -> Vector3:
	return DotNpcAiSteering.separate(here, neighbours(spacing), spacing, right)


## Steers toward [param to] while keeping [param spacing] metres from the neighbours.
## The combination almost every NPC wants: a path direction and a separation push, blended, then handed to the mover.
func steer_with_spacing(
	to: Vector3, speed: float, delta: float, spacing: float = 1.6
) -> void:
	if npc == null or not npc.is_alive():
		return

	var goal := _steer_goal(to)

	if goal == Vector3.INF:
		_cruise_dest = to
		return

	var here := npc.position()
	var wanted := DotNpcAiSteering.seek(here, goal)

		# The NPC's own right as the tie-break for a stack: it differs per NPC, so two stacked NPCs are shoved
		# apart in different directions, not travel as a tower. From `facing()` turned a quarter turn about Y,
		# not a basis: `global_transform` does not exist on a [Node2D], and a 2D game errored once per NPC per tick.
	var forward := npc.facing()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var apart := separation(here, spacing, right)

		# Separation is weighted below seeking: equal weights make a crowd that spreads out and stops arriving,
		# since at a doorway the pushes cancel the seek and the horde mills about outside, which reads as a
		# broken pathfinder.
	var direction := wanted * 1.0 + apart * 0.6
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.001 else Vector3.ZERO

	if direction.length() < 0.001:
		return

	var av := _avoider()
	if av != null:
		var tier := scheduler.tier_of(self) if scheduler != null and is_instance_valid(scheduler) else 0
		var safe: Vector3 = av.steer(npc.instance_id, npc, direction.normalized() * speed, tier)
		if safe.length() > 0.001:
			direction = safe.normalized()

	steer_toward(here + direction * 4.0, speed, delta)
	_cruise_to = goal
	_cruise_dest = to
	_watch_progress(here, to)


## The enabled avoidance node on the registry, or null; looked for about once a second.
func _avoider() -> DotNpcAiAvoidance:
	if _avoid_node != null and is_instance_valid(_avoid_node):
		return _avoid_node if _avoid_node.config.enabled else null
	_avoid_node = null
	_avoid_probe -= 1
	if _avoid_probe <= 0:
		_avoid_probe = 60
		_avoid_node = DotNpcAiAvoidance.find() as DotNpcAiAvoidance
	return _avoid_node if _avoid_node != null and _avoid_node.config.enabled else null


## Notices an NPC that is steering and not getting anywhere, and gives it the graph's own corners for a few seconds.
## A smoothed path on a coarse graph cuts a door jamb's corner thinner than its spacing and the NPC presses into the jamb for as long as the path lasts, so hordes stood at tunnel doors for minutes.
## Duck-typed, so an older dot-npc without it is left alone.
func _watch_progress(here: Vector3, goal: Vector3) -> void:
	var now := _world_now()

	# Measured flat: a body hopping on the spot against what stops it is not making headway.
	if _progress_at == Vector3.INF or _flat_length(here - _progress_at) > 0.5 or _flat_length(goal - here) < 2.0:
		_progress_at = here
		_progress_since = now
		return

	if now - _progress_since >= stuck_seconds and path != null and path.has_method(&"go_rough"):
		path.call(&"go_rough", now, 4.0)
		_progress_at = here
		_progress_since = now


static func _flat_length(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

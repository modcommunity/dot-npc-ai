extends RefCounted

## Cold, self-contained leaves of [DotNpcAiBrain], moved out so the brain stays a size a reader can hold.
## Each takes the brain as [param b]; the brain keeps a one-line wrapper per public leaf.
## The velocity aimed at is what the NPC SAW (a perfect lead is the aimbot tell); below CALLOUT_TACTICS it ignores friendly fire.

static func patrol_hot(
	b: DotNpcAiBrain, ctx: DotNpcAiContext, speed: float, radius: float = 40.0
) -> DotNpcAiNode.Status:
	if b.npc == null or not b.npc.is_alive() or b.blackboard == null:
		return DotNpcAiNode.Status.FAILURE

	if b.heatmap == null:
		b.heatmap = DotNpcAiHeatmap.of(b.director)

	if b.heatmap == null or b.tactics() < b.PATROL_TACTICS:
		return DotNpcAiNode.Status.FAILURE

	var here := b.npc.position()
	var goal: Variant = b.blackboard.get_value(b.KEY_PATROL_GOAL, ctx.now, null)

	if not (goal is Vector3):
		var hot := b.heatmap.hottest(DotNpcAiHeatmap.TRAFFIC, here, radius, b._world_now(), 4)

		if hot.is_empty():
			return DotNpcAiNode.Status.FAILURE

		# A pick among the top few, from the NPC's seed and visits, so a pack does not all stand on one cell.
		var visits := b.blackboard.get_int(b.KEY_PATROL_VISITS, ctx.now, 0)
		var pick := int(DotNpcAiNode.deterministic_unit(b.npc.seed, visits + 1) * hot.size())
		goal = Vector3(hot[mini(pick, hot.size() - 1)].x, here.y, hot[mini(pick, hot.size() - 1)].z)
		b.blackboard.put(b.KEY_PATROL_GOAL, goal, ctx.now)
		b.blackboard.erase(b.KEY_PATROL_ARRIVED)

	var flat: Vector3 = goal - here
	flat.y = 0.0

	if flat.length() > b.heatmap.cell_size * 0.5 and not b.blackboard.has(b.KEY_PATROL_ARRIVED, ctx.now):
		b.steer_with_spacing(goal, speed, ctx.delta)
		return DotNpcAiNode.Status.RUNNING

	if not b.blackboard.has(b.KEY_PATROL_ARRIVED, ctx.now):
		b.blackboard.put(b.KEY_PATROL_ARRIVED, ctx.now, ctx.now)

	b.halt()

	# Facing the way the traffic comes from: an ambusher watches the door, not the wall.
	var flow := b.heatmap.flow_at(DotNpcAiHeatmap.TRAFFIC, here, b._world_now())

	if flow.length_squared() > 0.0001:
		var look := flow
		if b.character != null:
			look = flow.rotated(Vector3.UP, b.character.glance_offset(ctx.now))
		b.face(look)

	var camper := b.character.camper if b.character != null else 0.2
	var hold := lerpf(2.0, 20.0, camper)

	if ctx.now - b.blackboard.get_float(b.KEY_PATROL_ARRIVED, ctx.now, ctx.now) >= hold:
		b.blackboard.erase(b.KEY_PATROL_GOAL)
		b.blackboard.erase(b.KEY_PATROL_ARRIVED)
		b.blackboard.put(b.KEY_PATROL_VISITS, b.blackboard.get_int(b.KEY_PATROL_VISITS, ctx.now, 0) + 1, ctx.now)

	return DotNpcAiNode.Status.RUNNING


static func flee_danger(b: DotNpcAiBrain, ctx: DotNpcAiContext, speed: float) -> DotNpcAiNode.Status:
	if b.npc == null or not b.npc.is_alive() or not b.in_danger():
		return DotNpcAiNode.Status.FAILURE

	var here := b.npc.position()
	var away := here - b._danger_at
	away.y = 0.0

	if away.length() > b._danger_extent + 1.5:
		b.halt()
		return DotNpcAiNode.Status.RUNNING

	if away.length_squared() < 0.0001:
		away = -b.npc.facing()

	b.steer_with_spacing(here + away.normalized() * 6.0, speed, ctx.delta)
	return DotNpcAiNode.Status.RUNNING


static func aim_solution(b: DotNpcAiBrain, muzzle: Vector3, travel_speed: float = 0.0) -> Vector3:
	if b.npc == null or not b.npc.has_target() or b.character == null:
		return b.target_position(Vector3.INF)

	var at := b.target_position(Vector3.INF)

	if at == Vector3.INF:
		return at

	var entry := b.memory.get_entry(b.npc.target_id, b.context.now) if b.memory != null else null
	var velocity := entry.velocity if entry != null else Vector3.ZERO
	b.shots_fired += 1
	b.character.track_velocity(velocity, b.context.now)
	return b.character.aim_point(muzzle, at, velocity, travel_speed, b.shots_fired)


static func ready_to_fire(b: DotNpcAiBrain, muzzle: Vector3, tolerance_deg: float = 12.0) -> bool:
	if b.npc == null or not b.npc.is_alive() or not b.npc.has_target() or b.context == null:
		return false

	if not b.context.has_condition(DotNpcAiConditions.SEE_ENEMY) or not b.has_reacted():
		return false

	var at := b.target_position(Vector3.INF)

	if at == Vector3.INF:
		return false

	var to := at - b.npc.position()
	to.y = 0.0

	if to.length_squared() < 0.0001:
		return true

	if rad_to_deg(b.npc.facing().angle_to(to.normalized())) > tolerance_deg:
		return false

	if not b.fire_lane_clear(muzzle, at):
		return false

	return b.character == null or b.character.should_fire(b.context.tick_index)


static func fire_lane_clear(b: DotNpcAiBrain, from: Vector3, to: Vector3, clearance: float = 0.8) -> bool:
	if b.squad == null or b.tactics() < b.CALLOUT_TACTICS:
		return true

	var lane := to - from
	var length := lane.length()

	if length < 0.001:
		return true

	var along := lane / length

	for member in b.squad.members():
		var other = member if is_instance_valid(member) else null

		if other == null or other == b or other.npc == null or not other.npc.is_alive():
			continue

		var offset: Vector3 = other.npc.position() - from
		var t: float = offset.dot(along)

		if t <= 0.0 or t >= length:
			continue

		var closest: Vector3 = from + along * t
		var flat: Vector3 = other.npc.position() - closest
		flat.y = 0.0

		if flat.length() < clearance:
			return false

	return true


static func hold_range(
	b: DotNpcAiBrain, ctx: DotNpcAiContext, speed: float, near: float = 8.0, far: float = 16.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if b.npc == null or not b.npc.is_alive() or not b.npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var at := b.target_position(Vector3.INF)

	if at == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var here := b.npc.position()
	var to := at - here
	to.y = 0.0
	var distance := to.length()

	if distance < 0.001:
		return DotNpcAiNode.Status.RUNNING

	if b.character != null and b.character.is_hesitating(b.npc.target_since, ctx.now):
		b.halt()
		b.face(to)
		return DotNpcAiNode.Status.RUNNING

	var toward := to / distance
	var side := Vector3(-toward.z, 0.0, toward.x)
	var period := 2.5 + 2.0 * DotNpcAiNode.deterministic_unit(b.npc.seed, 4421)
	var drift := b.character.strafe_drift(ctx.now, period) if b.character != null else (1.0 if fmod(ctx.now / period, 2.0) < 1.0 else -1.0)
	var wanted := side * drift * 0.6

	if distance > far:
		wanted += toward
	elif distance < near:
		wanted -= toward

	b.steer_with_spacing(here + wanted.normalized() * 4.0, speed, ctx.delta, spacing)
	b.face(to)
	return DotNpcAiNode.Status.RUNNING


static func _hurt_by(b: DotNpcAiBrain, by: StringName, amount: float) -> void:
	b._pending_damage += maxf(amount, 0.0)

	if by == &"" or b.npc == null or not b.npc.is_alive() or b.memory == null or b.context == null:
		return

	if b.director == null or not b.director.has_method(&"candidate_position"):
		return

	var found: Variant = b.director.call(&"candidate_position", by, Vector3.INF)

	if not (found is Vector3) or found == Vector3.INF:
		# Not something it could ever target — the world, a trap, another NPC.
		return

	var at: Vector3 = found
	b.memory.hurt_by(by, at, amount, b.context.now)

	if b.npc.target_id == by:
		return

	if not b.npc.has_target():
		var delay := b.character.hurt_turn_delay(b.context.tick_index * 17 + by.hash()) if b.character != null else 0.0
		if delay > 0.0:
			b._hurt_look_at = at
			b._hurt_look_due = b.context.now + delay
		else:
			b.face(at - b.npc.position())
		return

	if b.character == null or b.character.vengefulness <= 0.0:
		return

	var roll := b.character.unit(b.context.tick_index * 31 + by.hash())

	if roll < b.character.vengefulness:
		var now := b._world_now()
		b.npc.target_id = by
		b.npc.target_since = now
		b.npc.target_seen_at = now
		b.npc.engaged_at = now


static func surround(
	b: DotNpcAiBrain, ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if b.npc == null or not b.npc.is_alive() or not b.npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var center := b.target_position(Vector3.INF)

	if center == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	if b.character != null and b.character.is_hesitating(b.npc.target_since, b.context.now):
		b.halt()
		return DotNpcAiNode.Status.RUNNING

	var here := b.npc.position()
	var group: Array
	var positions: Array
	var facing: Vector3

	# Who is waiting on this target and which way it faces are the same answer for every
	# waiter in a tick: worked out by the first to ask and shared through the b.squad.
	var now := b._world_now()
	var key := &"" if b.squad == null else StringName("surround:" + String(b.npc.target_id))
	var shared: Variant = b.squad.memo(key, now) if b.squad != null else null

	if shared is Array and (shared[0] as Array).has(b):
		group = shared[0]
		positions = shared[1]
		facing = shared[2]
	else:
		group = b._waiting_with()
		positions = []

		for member in group:
			positions.append(member.npc.position())

		facing = b._enemy_facing(center)

		if b.squad != null:
			b.squad.remember(key, now, [group, positions, facing])

	var focus := DotNpcAiTactics.mean_bearing(center, positions)

	if facing.length_squared() > 0.0001:
		var behind := atan2(-facing.z, -facing.x)
		focus = lerp_angle(focus, behind, b.tactics())

	# One place per spacing of arc, measured at the ring's radius.
	var step := clampf(spacing * 1.4 / maxf(radius, 0.5), 0.2, PI)
	var bearings := DotNpcAiTactics.spread_bearings(center, focus, positions, step)
	var mine := group.find(b)
	var bearing := bearings[mine] if mine >= 0 else focus
	var point := DotNpcAiTactics.ring_toward(center, here, radius, bearing, b.flank_lead)

	var flat := point - here
	flat.y = 0.0

	if flat.length() < 0.6:
		# There — but still apart. A waiter that halts on its spot is one that stays wherever
		# the b.squad's last shove left it, which is how a ring becomes a heap.
		var forward := b.npc.facing()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var apart := b.separation(here, spacing, right)

		if apart.length() > 0.05:
			b.steer_toward(here + apart * 2.0, speed * 0.5, ctx.delta)
		else:
			b.halt()

		b.face(center - here)
		return DotNpcAiNode.Status.RUNNING

	b.steer_with_spacing(point, speed, ctx.delta, spacing)
	return DotNpcAiNode.Status.RUNNING


static func hold_off(
	b: DotNpcAiBrain, ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if b.squad == null or not b.squad.tokens.enabled:
		return b.surround(ctx, speed, radius, spacing)

	if b.npc == null or not b.npc.is_alive() or not b.npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var center := b.target_position(Vector3.INF)

	if center == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	if b.character != null and b.character.is_hesitating(b.npc.target_since, ctx.now):
		b.halt()
		return DotNpcAiNode.Status.RUNNING

	var here := b.npc.position()
	var allies: Array = []

	for member in b._waiting_with():
		if member != b:
			allies.append(member.npc.position())

	var point := DotNpcAiTactics.best_flank(center, b._enemy_facing(center), here, radius, allies, b.squad.tokens)

	if point == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var flat := point - here
	flat.y = 0.0

	if flat.length() < 0.6:
		var forward := b.npc.facing()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var apart := b.separation(here, spacing, right)

		if apart.length() > 0.05:
			b.steer_toward(here + apart * 2.0, speed * 0.5, ctx.delta)
		else:
			b.halt()

		b.face(center - here)
		return DotNpcAiNode.Status.RUNNING

	b.steer_with_spacing(point, speed, ctx.delta, spacing)
	return DotNpcAiNode.Status.RUNNING


static func _waiting_with(b: DotNpcAiBrain) -> Array:
	var out: Array = [b]

	if b.squad == null or not b.npc.has_target():
		return out

	var holding := b.squad.holder_ids(b._attack_slot())
	out.clear()

	for member in b.squad.members():
		var other = member if is_instance_valid(member) else null

		if other == null or other.npc == null or not other.npc.is_alive():
			continue

		if other.npc.target_id != b.npc.target_id or holding.has(other.get_instance_id()):
			continue

		out.append(other)

	if not out.has(b):
		out.append(b)

	return out


static func _enemy_facing(b: DotNpcAiBrain, center: Vector3) -> Vector3:
	if b.squad != null and b.npc.has_target():
		var holding := b.squad.holder_ids(b._attack_slot())
		var nearest := Vector3.INF

		for member in b.squad.members():
			var other = member if is_instance_valid(member) else null

			if other == null or other == b or other.npc == null or not other.npc.is_alive():
				continue

			if not holding.has(other.get_instance_id()):
				continue

			var at: Vector3 = other.npc.position()

			if nearest == Vector3.INF or at.distance_squared_to(center) < nearest.distance_squared_to(center):
				nearest = at

		if nearest != Vector3.INF:
			var look := nearest - center
			look.y = 0.0

			if look.length_squared() > 0.0001:
				return look.normalized()

	var entry := b.memory.get_entry(b.npc.target_id, b.context.now) if b.memory != null and b.npc.has_target() else null

	if entry != null:
		var moving := Vector3(entry.velocity.x, 0.0, entry.velocity.z)

		if moving.length() > 0.5:
			return moving.normalized()

	return Vector3.ZERO

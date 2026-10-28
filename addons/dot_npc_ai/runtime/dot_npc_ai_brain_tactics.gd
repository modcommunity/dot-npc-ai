extends "dot_npc_ai_brain_motion.gd"

## Memory, search, squad roles, cover and danger of [DotNpcAiBrain]: what it does about what it knows. Not a public class.


## How long this NPC keeps believing it knows where somebody is. From its character.
func memory_time() -> float:
	return character.memory_time if character != null else 5.0


## How much this NPC thinks ahead and works with others. From its character; 0.5 without.
func tactics() -> float:
	return character.tactics if character != null else 0.5


## Where its current target (or, with none, the most recent thing it knows about) was last known to be; [constant Vector3.INF] when there is nothing.
## Infinity, not zero, because zero is the middle of the map and an NPC searching the origin reads as a pathfinding bug.
func last_known_position() -> Vector3:
	var entry := _search_entry()
	return entry.position if entry != null else Vector3.INF


## Whether there is somewhere worth looking. The guard for a search branch.
func remembers_target() -> bool:
	return _search_entry() != null


## Forgets what a search would go after, and the search itself.
func forget_target_position() -> void:
	var entry := _search_entry()

	if entry != null:
		memory.forget(entry.id)

	_end_search()


func _search_entry() -> DotNpcAiMemory.Entry:
	if memory == null or context == null:
		return null

	if npc != null and npc.has_target():
		var current := memory.get_entry(npc.target_id, context.now)

		if current != null:
			return current

	return memory.freshest(context.now)


func _end_search() -> void:
	if blackboard == null:
		return

	blackboard.erase(KEY_SEARCH_ARRIVED)
	blackboard.erase(KEY_SEARCH_HEADING)
	blackboard.erase(KEY_SEARCH_ID)


## Goes to where a lost enemy probably is, then looks round. A ready-made leaf: RUNNING while walking or looking, SUCCESS once it found nothing (that enemy is then forgotten), FAILURE with nothing to look for. Between the fight and the idle branch of a reactive selector, a target perceived mid-search takes over the same tick.
## "Probably" by [method tactics]: [DotNpcAiMemory] keeps the velocity the enemy left with; tactics 0 walks to the spot they were lost, tactics 1 to where they were heading (turning two corners beats the first).
## The look-round sweeps either side of the arrival heading, longer the better its memory.
func search(ctx: DotNpcAiContext, speed: float, spacing: float = 1.6) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or blackboard == null or memory == null:
		return DotNpcAiNode.Status.FAILURE

	var entry := _search_entry()

	if entry == null:
		_end_search()
		return DotNpcAiNode.Status.FAILURE

	if blackboard.get_name(KEY_SEARCH_ID, ctx.now, &"") != entry.id:
		# A different thing to look for than last tick: start again.
		_end_search()
		blackboard.put(KEY_SEARCH_ID, entry.id, ctx.now)

	if not blackboard.has(KEY_SEARCH_ARRIVED, ctx.now):
		var goal := memory.predict_entry(entry, ctx.now, tactics())
		var flat := goal - npc.position()
		flat.y = 0.0

		if flat.length() > search_arrive_distance:
			steer_with_spacing(goal, speed, ctx.delta, spacing)
			return DotNpcAiNode.Status.RUNNING

		var facing := npc.facing()
		blackboard.put(KEY_SEARCH_ARRIVED, ctx.now, ctx.now)
		blackboard.put(KEY_SEARCH_HEADING, atan2(facing.z, facing.x), ctx.now)

	var looked := ctx.now - blackboard.get_float(KEY_SEARCH_ARRIVED, ctx.now, ctx.now)

	if looked >= look_round_time():
		memory.forget(entry.id)
		_end_search()
		halt()
		return DotNpcAiNode.Status.SUCCESS

	halt()

	# A sweep of about seventy degrees each way. Facing, not moving: the sight cone is what
	# finds somebody, and the cone points where the NPC faces.
	var heading := blackboard.get_float(KEY_SEARCH_HEADING, ctx.now, 0.0)
	var glance_yaw := character.glance_offset(ctx.now) if character != null else 0.0
	face(DotNpcAiSteering.angle_to_direction(heading + sin(looked * 2.2) * 1.2 + glance_yaw))

	return DotNpcAiNode.Status.RUNNING


## How long a search looks round once it arrives, from the character's memory.
func look_round_time() -> float:
	return clampf(memory_time() * 0.4, 1.0, 6.0)


## Asks the squad for one of the places attacking the current target; true when it has one. The question every attack branch asks first.
## With no squad always yes. [param capacity] defaults to [member attack_capacity] (a catalogue's `"attackers"`). Kept until the target changes, is lost, or this NPC dies.


func claim_attack_slot(capacity: int = -1) -> bool:
	return claim_role(ROLE_ATTACK, capacity if capacity >= 0 else attack_capacity)


func holds_attack_slot() -> bool:
	return holds_role(ROLE_ATTACK)


func release_attack_slot() -> void:
	release_role(ROLE_ATTACK)


func _attack_slot() -> StringName:
	return _role_slot(ROLE_ATTACK, npc.target_id)


## Asks the squad for one of [param capacity] places in [param role] against the current target. With no squad, always yes. Kept until the target changes or this NPC dies.
## Roles are attack slots with names: a tree asking in order (flank if nobody is, suppress if nobody is, else attack or wait) splits a squad's work without anybody giving an order.
func claim_role(role: StringName, capacity: int) -> bool:
	if npc == null or not npc.has_target():
		return false

	if squad == null:
		return true

	var slot := _role_slot(role, npc.target_id)

	if role == ROLE_ATTACK and squad.tokens.enabled:
		var held := squad.holds(slot, self)

		if not held and squad.holder_count(slot) >= capacity:
			return false

		if not squad.take_token(self, npc.target_id, _world_now()):
			# A slot taken before tokens were switched on does not outlive the refusal.
			if held:
				squad.release(slot, self)
			return false

		if not squad.claim(slot, self, capacity):
			squad.release_token(self, &"claim", _world_now())
			return false

		return true

	return squad.claim(slot, self, capacity)


func holds_role(role: StringName) -> bool:
	if npc == null or not npc.has_target():
		return false

	return squad == null or squad.holds(_role_slot(role, npc.target_id), self)


func release_role(role: StringName) -> void:
	if squad != null:
		squad.release_prefixed(String(role) + ":", self)


func _role_slot(role: StringName, target: StringName) -> StringName:
	if role != ROLE_ATTACK:
		return StringName(String(role) + ":" + String(target))

	# The attack slot is asked for several times a think; rebuilding its name was an allocation each time.
	if target != _attack_slot_target or _attack_slot_name == &"":
		_attack_slot_target = target
		_attack_slot_name = StringName(String(role) + ":" + String(target))

	return _attack_slot_name


func _release_roles_on(target: StringName) -> void:
	if squad != null and target != &"":
		squad.release_token(self, &"kill", _world_now())
		squad.release_suffixed(":" + String(target), self)


## The best cover from [param threat] within [param max_distance], or [constant Vector3.INF].
## From the navigation data dot-npc's generator marked (a cover spot records which way its wall is, so no raycast), scored by cover against distance. Claimed in the squad, one NPC per spot: otherwise two pick the same and the second stands in the open.
func find_cover(threat: Vector3, max_distance: float = 15.0) -> Vector3:
	var data := _nav_data()

	if data == null or data.cover_count() == 0 or npc == null:
		return Vector3.INF

	var here := npc.position()

	var scorer := func(spot: Vector3, index: int) -> float:
		if (data.cover_flags_of(index) & DotNpcNavData.Cover.IN_COVER) == 0:
			return -INF

		var away := spot.distance_to(here)

		if away > max_distance:
			return -INF

		var to_threat := threat - spot

		if to_threat.length_squared() <= 0.0001:
			return -INF

		var covered := data.cover_normals[index].dot(to_threat.normalized())

		if covered < 0.25:
			return -INF

		if squad != null:
			var slot := StringName("cover:%d" % index)

			if squad.holder_count(slot) > 0 and not squad.holds(slot, self):
				return -INF

		# dot-npc's own weighting: eight metres of walking per unit of facing.
		return covered * 8.0 - away

	var best := DotNpcAiTactics.best_of(data.cover_positions, scorer)

	if best < 0 or is_inf(float(scorer.call(data.cover_positions[best], best))):
		return Vector3.INF

	if squad != null:
		squad.release_prefixed("cover:", self)
		squad.claim(StringName("cover:%d" % best), self, 1)

	return data.cover_positions[best]


## Goes to cover from [param threat] — the target, or the freshest thing remembered, when
## omitted. SUCCESS once there, RUNNING on the way, FAILURE with no cover to go to.
func take_cover(
	ctx: DotNpcAiContext, speed: float, threat: Vector3 = Vector3.INF
) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive():
		return DotNpcAiNode.Status.FAILURE

	var from := threat if threat != Vector3.INF else last_known_position()

	if from == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var spot := find_cover(from)

	if spot == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var flat := spot - npc.position()
	flat.y = 0.0

	if flat.length() <= 0.75:
		halt()
		face(from - npc.position())
		return DotNpcAiNode.Status.SUCCESS

	steer_toward(spot, speed, ctx.delta)
	return DotNpcAiNode.Status.RUNNING


func _nav_data() -> DotNpcNavData:
	if director == null:
		return null

	var graph: Variant = director.get(&"nav")

	if graph is DotNpcNavGraph:
		return (graph as DotNpcNavGraph).data

	return null


## Whether a danger it heard is still live.
func in_danger() -> bool:
	return _danger_until >= _world_now()


## Where the live danger is, or [constant Vector3.INF].
func danger_position() -> Vector3:
	return _danger_at if in_danger() else Vector3.INF

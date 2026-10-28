class_name DotNpcAiBrain
extends "dot_npc_ai_brain_senses.gd"

## A [DotNpcBrain] that runs a behaviour tree or a state machine. The adapter: the ONLY file in dot-npc-ai that names anything from dot-npc, so the tree, machine, blackboard and steering stay liftable into a vehicle, a 2D game or a menu.
## A game subclasses it and builds its decision in [method _build] (once, at spawn), e.g. `tree = DotNpcAiSelector.new(&"root", [DotNpcAiSequence.new(&"chase", [...]), DotNpcAiLeaf.Action.new(&"wander", _wander)])`.
## Extended by PATH, like every brain: a script in a mounted dot-cloud pack cannot resolve a `class_name`, which is why `brain_script_path` is a path.

const _Leaves := preload("dot_npc_ai_brain_leaves.gd")


func _npc_ready() -> void:
	scheduler = _find_scheduler()
	blackboard = DotNpcAiBlackboard.new()
	context = DotNpcAiContext.make(npc, self, blackboard)
	memory = DotNpcAiMemory.new()
	sounds = DotNpcAiSounds.of(director)
	heatmap = DotNpcAiHeatmap.of(director)
	attack_capacity = int(tune(&"attackers", float(attack_capacity)))

		# The definition's squad only when it names one: a game that chose the squad before binding (each
		# player's NPCs in their own) must not have it wiped by a definition that says nothing.
	var named_squad := tune_string(&"squad", "")
	if named_squad != "":
		squad_name = StringName(named_squad)

		# The world's clock, not zero: a brain built ninety seconds in with a clock starting at zero measures
		# cooldowns, timeouts and memory lifetimes against a clock that disagrees with the spawner's, so some
		# NPCs seem to ignore cooldowns.
	if director != null and director.has_method(&"now"):
		context.now = float(director.call(&"now"))

	# A character named in the catalogue, for a brain that did not choose one. Opt-in: a
	# brain with no character and no `skill` in its definition is a legitimate NPC with no
	# reaction time, and turning that into a normal one would change every such game.
	if character == null:
		var named := tune_string(&"skill", "")

		if named != "":
			character = DotNpcAiCharacter.preset(named)

	skill = skill if skill != null else DotNpcAiSkill.of(director)
	_refresh_character()

	_build()

		# Again, for a brain that assigned its character in `_build`, too late for the seeding above (it left
		# `ctx.character` null for the whole tree).
	_refresh_character()

	# After `_build`, so a game may choose the squad there.
	if squad_name != &"":
		var squads := DotNpcAiSquads.of(director)

		if squads != null:
			squad = squads.squad(squad_name)
			squad.join(self)
			_report_seq = squad.report_seq()

	if machine != null and initial_state != &"":
		var started := machine.go_to(context, initial_state)

		if not started.ok:
			DotLog.warn("npc.ai", "an NPC's initial state does not exist", {
				"state": String(initial_state),
				"why": started.error.message,
			})

	if scheduler != null:
		_join_scheduler()


## Turns utility scoring on with [param config] (ignored unless it is enabled) and gives this NPC its personality for [param role]. Returns the scorer to add actions to.
func use_utility(config: DotNpcAiUtilityConfig, role: StringName = &"") -> DotNpcAiUtility:
	if config == null or not config.enabled:
		utility = null
		return null
	utility = DotNpcAiUtility.new()
	utility.config = config
	utility.npc_seed = npc.seed if npc != null else 0
	utility.personality = config.personality_for(utility.npc_seed, role)
	return utility


## The utility choice for this think, or an empty name with scoring off. Re-scored only once per think, so every gate in a tree shares it.
func utility_choose() -> StringName:
	if utility == null or context == null:
		return &""
	return utility.choose(context.now)


func _npc_think(delta: float) -> void:
	if context == null:
		return

	_thinking = false
	var sched := _sched()

	# The delta of every tick skipped since the last think, so cooldowns and timeouts keep real time.
	# Movement keeps the tick's own delta: the skipped ticks were walked by _cruise.
	if sched != null:
		var admitted := sched.admit(self, delta)
		if admitted < 0.0:
			_cruise(delta)
			return
		_step_delta = delta
		_thinking = true
		delta = admitted

	_cruise_on = false
	context.advance(delta)

	_refresh_character()
	_sense()

	if npc != null:
		_facing_at_tick = npc.facing()
		if _hurt_look_at != Vector3.INF and context.now >= _hurt_look_due:
			if not npc.has_target():
				face(_hurt_look_at - npc.position())
			_hurt_look_at = Vector3.INF
		if character != null and character.track_lag > 0.0 and npc.has_target() and memory != null:
			var entry := memory.get_entry(npc.target_id, context.now)
			if entry != null:
				character.track_velocity(entry.velocity, context.now)

	if tree != null:
		last_status = tree.tick(context)

	if machine != null:
		machine.tick(context)

	_thinking = false
	if sched != null and is_instance_valid(sched):
		sched.finish(self)


## Being hurt is information, and it arrives here whatever the subclass does with it.
## Overrides `damaged`, not `_npc_damaged`: game brains override the hook without calling `super`, so behaviour there would be lost in the brains that need it.
func damaged(amount: float, by: StringName) -> void:
	_hurt_by(by, amount)
	var sched := _sched()
	if sched != null:
		sched.wake(self)
	super(amount, by)


## A brain being told its NPC has been abandoned mid-action.
## An NPC that dies with a tree node RUNNING must release what it reserved (a door, a queue spot, an animation), or the reservation outlives it.
func _npc_died(_by: StringName) -> void:
	if tree != null and tree.is_running:
		tree.abort(context)

	# Its attack slot is the next NPC's. A squad whose slots belonged to the dead would
	# stand in a ring round a player for ever.
	if squad != null:
		squad.leave(self)


## The context points back at this brain and at the NPC, and this brain holds the
## context: a cycle [method DotNpcBrain.unbind] exists to break. The tree and the
## machine go too, because a node that cached the context would be a second one.
func _npc_unbound() -> void:
	if scheduler != null and is_instance_valid(scheduler):
		scheduler.unregister(self)
	scheduler = null
	_sched_probe = 1 << 30

	if context != null:
		context.brain = null
		context.agent = null

	context = null
	tree = null
	machine = null
	blackboard = null
	skill = null
	memory = null
	sounds = null
	heatmap = null

	if squad != null:
		squad.leave(self)

	squad = null


## Build [member tree] and/or [member machine] here. Called once, on spawn.
func _build() -> void:
	pass


## Whether this NPC has had time to react to its current target. The gate every "shoot at it" branch belongs behind.
## Measured from `target_since`, not `engaged_at`: `engaged_at` refreshes on every pass the target is perceived, so a reaction time against it never elapses for an NPC that can see someone, every branch behind it never runs and nothing errors.
## `target_since` moves when the target CHANGES, not while it is held.
func has_reacted() -> bool:
	if character == null or npc == null:
		return true
	return character.has_reacted(npc.target_since, context.now if context != null else 0.0)


## The character in force, worked out again only when something changed: the game assigned a different one, the server's [member skill] moved, or a skill was attached to the director after spawn.
## Each costs one comparison a tick when nothing did.
func _refresh_character() -> void:
	if skill == null and director != null:
		skill = DotNpcAiSkill.of(director)

	if character != _applied:
		# The game assigned one, at ready or since. It is the new authored character.
		base_character = _seeded(character)
		_skill_revision = -1

	var revision := skill.revision if skill != null else 0

	if _skill_revision == revision and character == _applied:
		return

	_skill_revision = revision
	character = skill.apply(base_character) if skill != null else base_character
	_applied = character

	if context != null:
		context.character = character

	# Alertness is how far THIS one sees, and dot-npc's senses are what look. Until this
	# line nothing read the field at all: every character's alertness was decoration.
	if npc != null:
		npc.sight_scale = character.alertness if character != null else 1.0


## [param from] with this NPC's own seed, unless the game already gave it one.
## A character still carrying the preset's seed is one of twenty identical shooters, and the symptom is a volley rather than a fight.
func _seeded(from: DotNpcAiCharacter) -> DotNpcAiCharacter:
	if from == null:
		return null

	# [member DotNpcInstance.seed], never `instance_id`: the object id moves when anything
	# else in the process is created first, and every choice drawn from it moved with it.
	if from.seed_value <= 1 and npc != null and npc.seed != 0:
		return from.with_seed(npc.seed)

	return from


## Holds a place on a ring round the target, sharing the ring out with the rest of the
## squad that is waiting. The leaf for a squad member that has not got an attack slot.
func surround(
	ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	return _Leaves.surround(self, ctx, speed, radius, spacing)


## What a member without an attack token does: take the best flanking place on a ring round the target and hold it
## at spacing. With tokens off it is [method surround]. RUNNING while there is a target; FAILURE without one.
func hold_off(
	ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	return _Leaves.hold_off(self, ctx, speed, radius, spacing)


## The squad members waiting on the same target as this one, this one included, in a fixed
## order. Alone, or with no squad, just this one.
func _waiting_with() -> Array:
	return _Leaves._waiting_with(self)


## Which way the enemy at [param center] is probably looking.
func _enemy_facing(center: Vector3) -> Vector3:
	return _Leaves._enemy_facing(self, center)


## Where to aim at the target from [param muzzle], leading it and missing by this character's aim.
## Fed the velocity this NPC's memory measured, not the true one; each call is a new shot. [constant Vector3.INF] with no target.
func aim_solution(muzzle: Vector3, travel_speed: float = 0.0) -> Vector3:
	return _Leaves.aim_solution(self, muzzle, travel_speed)


## Whether this NPC may shoot now: sees the target, has reacted, faces it, lane clear of squadmates, fire throttle open.
func ready_to_fire(muzzle: Vector3, tolerance_deg: float = 12.0) -> bool:
	return _Leaves.ready_to_fire(self, muzzle, tolerance_deg)


## Whether a shot from [param from] to [param to] passes clear of every squadmate.
func fire_lane_clear(from: Vector3, to: Vector3, clearance: float = 0.8) -> bool:
	return _Leaves.fire_lane_clear(self, from, to, clearance)


## Keeps between [param near] and [param far] metres from the target, strafing across it, facing it.
## RUNNING while there is a target, FAILURE without one.
func hold_range(
	ctx: DotNpcAiContext, speed: float, near: float = 8.0, far: float = 16.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	return _Leaves.hold_range(self, ctx, speed, near, far, spacing)


## Patrols the hottest cells near it and waits at each facing the traffic. FAILURE with no heat map, nothing hot, or too little tactics.
func patrol_hot(ctx: DotNpcAiContext, speed: float, radius: float = 40.0) -> DotNpcAiNode.Status:
	return _Leaves.patrol_hot(self, ctx, speed, radius)


## Gets out of a danger's reach and waits there until it is over. A ready-made leaf.
func flee_danger(ctx: DotNpcAiContext, speed: float) -> DotNpcAiNode.Status:
	return _Leaves.flee_danger(self, ctx, speed)


## What being hurt by [param by] tells this NPC: go and look, or (by vengefulness) switch target.
func _hurt_by(by: StringName, amount: float) -> void:
	_Leaves._hurt_by(self, by, amount)


func describe() -> Dictionary:
	var out := super.describe()

	out["tree"] = DotNpcAiNode.Status.keys()[last_status] if tree != null else "-"
	out["machine"] = machine.describe() if machine != null else "-"
	out["knows"] = blackboard.size() if blackboard != null else 0
	out["character"] = String(character.id) if character != null else "-"
	out["conditions"] = ", ".join(context.conditions.names()) if context != null else ""
	out["remembers"] = memory.size() if memory != null else 0
	out["squad"] = String(squad_name) if squad != null else "-"
	out["lod_tier"] = scheduler.tier_of(self) if scheduler != null and is_instance_valid(scheduler) else 0

	if utility != null:
		out["utility"] = utility.describe()

	if character != null:
		out["reaction"] = "%.2fs" % character.reaction_time

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if machine != null:
		out.append_array(machine.describe_lines(context.now if context != null else 0.0))

	if tree != null:
		out.append_array(tree.describe_lines())

	if context != null:
		out.append("conditions: %s" % ", ".join(context.conditions.names()))

	if memory != null and context != null:
		for line in memory.describe_lines(context.now):
			out.append("knows: %s" % line)

	if squad != null:
		out.append_array(squad.describe_lines())

	if utility != null:
		out.append_array(utility.describe_lines())

	return out

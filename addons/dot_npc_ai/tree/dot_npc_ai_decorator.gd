class_name DotNpcAiDecorator
extends DotNpcAiNode

## A node with exactly one child, which changes what that child means.
## The base for the small set below, each about three lines; written into a leaf instead, the same three lines make a tree unreadable.

var child: DotNpcAiNode = null


func _init(p_name: StringName = &"", p_child: DotNpcAiNode = null) -> void:
	super(p_name)
	child = p_child


func children() -> Array[DotNpcAiNode]:
	return [child] if child != null else []


func _abort(ctx: DotNpcAiContext) -> void:
	if child != null and child.is_running:
		child.abort(ctx)


## SUCCESS becomes FAILURE and back. RUNNING is untouched.
class Inverter:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		match child.tick(ctx):
			Status.SUCCESS:
				return Status.FAILURE
			Status.FAILURE:
				return Status.SUCCESS
			_:
				return Status.RUNNING


## Always SUCCESS once the child finishes, whatever it finished with.
## For a sequence step that may fail; without it "try this, and carry on either way" is a selector with a stub in it.
class Succeeder:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.SUCCESS

		var status := child.tick(ctx)

		return Status.RUNNING if status == Status.RUNNING else Status.SUCCESS


## Refuses to run its child again for [member cooldown] seconds after it finishes.
## Starts when the child FINISHES: from its start, a long action with a short cooldown re-enters before it ends (a machine gun). Simulated seconds, never a wall clock.
class Cooldown:
	extends DotNpcAiDecorator

	var cooldown: float = 1.0

	## Simulated seconds when the child last finished. Negative means never.
	var _last_finished: float = -1000000.0

	func _init(
		p_name: StringName = &"", p_child: DotNpcAiNode = null, p_cooldown: float = 1.0
	) -> void:
		super(p_name, p_child)
		cooldown = p_cooldown

	func is_ready(now: float) -> bool:
		return now - _last_finished >= cooldown

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		if not is_running and not is_ready(ctx.now):
			return Status.FAILURE

		var status := child.tick(ctx)

		if status != Status.RUNNING:
			_last_finished = ctx.now

		return status


## Runs its child up to [member times], failing when the child fails. 0 is for ever.
## Counts child runs that FINISHED, not its own ticks: counting ticks would make every frame of a walk a repetition.
class Repeat:
	extends DotNpcAiDecorator

	var times: int = 0

	var _done: int = 0

	func _init(
		p_name: StringName = &"", p_child: DotNpcAiNode = null, p_times: int = 0
	) -> void:
		super(p_name, p_child)
		times = p_times

	func _enter(_ctx: DotNpcAiContext) -> void:
		_done = 0

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

				# One repetition per tick, not a loop: a loop is infinite the first time the child succeeds without
				# suspending (every condition node), hanging the server. A thing that finishes synchronously breaks
				# a construct built for one that does not.
		var status := child.tick(ctx)

		if status == Status.RUNNING:
			return Status.RUNNING

		if status == Status.FAILURE:
			return Status.FAILURE

		_done += 1

		if times > 0 and _done >= times:
			return Status.SUCCESS

		return Status.RUNNING


## RUNNING until [member seconds] have passed, then SUCCESS. The delay every tree needs.
class Wait:
	extends DotNpcAiNode

	var seconds: float = 1.0

	var _started_at: float = 0.0

	func _init(p_name: StringName = &"", p_seconds: float = 1.0) -> void:
		super(p_name)
		seconds = p_seconds

	func _enter(ctx: DotNpcAiContext) -> void:
		_started_at = ctx.now

	func _tick(ctx: DotNpcAiContext) -> Status:
		return Status.SUCCESS if ctx.now - _started_at >= seconds else Status.RUNNING


## Always FAILURE once the child finishes. The mirror of [Succeeder].
## For a selector branch that must never be chosen: a probe that runs for its side effect and hands control to the branch below.
class Failer:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		var status := child.tick(ctx)

		return Status.RUNNING if status == Status.RUNNING else Status.FAILURE


## Abandons a child that has been RUNNING for longer than [member seconds] (simulated).
## Every RUNNING action can get stuck (a closed door, a teleported target, a corner), and without a limit "the zombie in the corner" is the bug report. The child is aborted so whatever it reserved is let go, and the selector above moves on.
class TimeLimit:
	extends DotNpcAiDecorator

	var seconds: float = 5.0

	var _started_at: float = 0.0

	func _init(
		p_name: StringName = &"", p_child: DotNpcAiNode = null, p_seconds: float = 5.0
	) -> void:
		super(p_name, p_child)
		seconds = p_seconds

	func _enter(ctx: DotNpcAiContext) -> void:
		_started_at = ctx.now

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		var status := child.tick(ctx)

		if status != Status.RUNNING:
			return status

		if seconds > 0.0 and ctx.now - _started_at >= seconds:
			child.abort(ctx)
			return Status.FAILURE

		return Status.RUNNING


## Lets its child run at most [member times] times, ever. FAILURE afterwards.
## Counted for the life of the node, not per entry, which is what "at most once" means (a greeting, a door opened once). [method reset] is for a game reusing a tree across rounds, since rebuilding loses every running state.
class Limit:
	extends DotNpcAiDecorator

	var times: int = 1

	var _used: int = 0

	func _init(
		p_name: StringName = &"", p_child: DotNpcAiNode = null, p_times: int = 1
	) -> void:
		super(p_name, p_child)
		times = p_times

	func used() -> int:
		return _used

	func reset() -> void:
		_used = 0

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		# Counted when it finishes, not when it starts. Counting on entry spends the
		# allowance on a child that was abandoned in its first tick, and "once" then
		# means "never" for any action long enough to be interrupted.
		if not is_running and times > 0 and _used >= times:
			return Status.FAILURE

		var status := child.tick(ctx)

		if status != Status.RUNNING:
			_used += 1

		return status


## Runs its child over and over until it fails, then SUCCESS. The loop a patrol is written with.
## One repetition per tick for [Repeat]'s reason: a real loop never returns when the child succeeds without suspending.
class UntilFail:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.SUCCESS

		var status := child.tick(ctx)

		if status == Status.RUNNING:
			return Status.RUNNING

		return Status.SUCCESS if status == Status.FAILURE else Status.RUNNING


## Runs its child only [member chance] of the time. FAILURE the rest.
## Reproducible, not random: the roll hashes the context's tick index and this node's salt, so a replay and a server rewind agree where [method randf] would diverge after ninety seconds.
## Rolled on entry only, so a RUNNING child is not re-rolled out of existence next tick.
class RandomChance:
	extends DotNpcAiDecorator

	var chance: float = 0.5

	## Mixed into the roll so two of these in one tree do not agree.
	var salt: int = 0

	var _rolled: bool = false

	func _init(
		p_name: StringName = &"",
		p_child: DotNpcAiNode = null,
		p_chance: float = 0.5,
		p_salt: int = 0
	) -> void:
		super(p_name, p_child)
		chance = p_chance
		salt = p_salt

	func _enter(ctx: DotNpcAiContext) -> void:
		var roll := DotNpcAiNode.deterministic_unit(ctx.tick_index, salt)
		_rolled = roll < chance

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null or not _rolled:
			return Status.FAILURE

		return child.tick(ctx)


## Runs its child until one of [member mask]'s conditions appears, then aborts it and fails: the schedule interrupt (a search ends on SEE_ENEMY, a walk to cover on HEAR_DANGER).
## Without it only a reactive guard ABOVE the action can stop it, putting every interrupt in one unreadable place.
## Checked BEFORE the child ticks, so it takes no extra step toward the grenade that just landed; fails, so the selector above moves on.
class Interrupt:
	extends DotNpcAiDecorator

	var mask: int = 0

		## Interrupts only on a condition that BECAME true, not one that is true. Off by default.
		## On is for an action that may start while the condition already holds: a flinch entered on
		## LIGHT_DAMAGE must not be interrupted by the damage it is reacting to.
	var only_new: bool = false

	var interrupt_count: int = 0

	func _init(
		p_name: StringName = &"", p_child: DotNpcAiNode = null, p_mask: int = 0,
		p_only_new: bool = false
	) -> void:
		super(p_name, p_child)
		mask = p_mask
		only_new = p_only_new

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		var hit := ctx.conditions.became(mask) if only_new else ctx.conditions.has(mask)

		if hit:
			interrupt_count += 1

			if child.is_running:
				child.abort(ctx)

			return Status.FAILURE

		return child.tick(ctx)

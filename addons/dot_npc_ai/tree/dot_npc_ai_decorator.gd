class_name DotNpcAiDecorator
extends DotNpcAiNode

## A node with exactly one child, which changes what that child means.
##
## The base for the small set below. All of them are three lines each and all of them
## exist because writing the same three lines into a leaf is how a tree stops being
## readable.

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
##
## What a sequence step that is allowed to fail is written with. Without it the only way
## to say "try this, and carry on either way" is a selector with a stub in it.
class Succeeder:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.SUCCESS

		var status := child.tick(ctx)

		return Status.RUNNING if status == Status.RUNNING else Status.SUCCESS


## Refuses to run its child again for [member cooldown] seconds after it finishes.
##
## [b]The cooldown starts when the child FINISHES, not when it starts.[/b] Started-from
## means a long action with a short cooldown can be re-entered before it has ended,
## which for an attack is a machine gun. Measured in simulated seconds, never a wall
## clock.
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
##
## [b]It counts ticks of a child that FINISHED, not ticks of this node.[/b] A repeater
## that counted its own ticks would run a RUNNING child once per repetition and count
## every frame of a walk as a repetition, so "do this three times" would be over in
## three frames.
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

		# One repetition per tick, not a loop.
		#
		# A loop here is an infinite one the first time the child succeeds without
		# suspending — which is every condition node — and it hangs the server rather
		# than misbehaving. This is the fan-out trap in a different costume: a thing
		# that finishes synchronously breaks the construct built for the one that does
		# not.
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
##
## What a selector branch that must never be chosen is written with — a probe that runs
## for its side effect and then hands control to the branch below it.
class Failer:
	extends DotNpcAiDecorator

	func _tick(ctx: DotNpcAiContext) -> Status:
		if child == null:
			return Status.FAILURE

		var status := child.tick(ctx)

		return Status.RUNNING if status == Status.RUNNING else Status.FAILURE


## Abandons a child that has been RUNNING for longer than [member seconds].
##
## [b]The one decorator a shipped NPC cannot do without.[/b] Every action that can
## return RUNNING can get stuck: a walk to a door somebody closed, an attack whose
## target teleported, a path that leads into a corner. Without a time limit the NPC
## does that one thing until the world changes, and "the zombie in the corner" is the
## bug report. With one it fails, the selector above it moves on, and nobody ever files
## anything.
##
## The child is aborted rather than merely abandoned, so whatever it reserved is let go.
## Measured in simulated seconds.
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
##
## [b]Counted for the life of the node, not per entry[/b], which is what "at most once"
## has to mean: a greeting, a one-off line, a door opened the first time an NPC reaches
## it. [method reset] is there for a game that reuses a tree across rounds, because the
## alternative is rebuilding the tree, and a tree rebuilt every round loses every
## running state in it.
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


## Runs its child over and over until it fails, then SUCCESS.
##
## The loop a patrol is written with. One repetition per tick for [Repeat]'s reason: a
## real loop here never returns when the child succeeds without suspending, and it hangs
## the server rather than misbehaving.
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
##
## [b]Reproducible, not random.[/b] The roll is a hash of the context's tick index and
## this node's salt, so a replay and a server rewind agree about what an NPC decided —
## which [method randf] does not, and which is the difference between a demo that plays
## back and one that diverges after ninety seconds.
##
## The roll happens on entry only: a child that returns RUNNING keeps running rather
## than being re-rolled out of existence on the next tick.
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

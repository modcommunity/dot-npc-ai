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

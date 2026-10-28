class_name DotNpcAiLeaf
extends DotNpcAiNode

## The two leaves a game actually writes: a condition and an action.
## Callables, not subclasses, for the ordinary case: a tree is mostly one-line questions and a class per question is a file per question. A leaf worth naming subclasses [DotNpcAiNode] directly.

## SUCCESS when the callable returns true. Never RUNNING: a question has an answer.
class Condition:
	extends DotNpcAiNode

	## `func(ctx: DotNpcAiContext) -> bool`.
	var test: Callable = Callable()

	func _init(p_name: StringName = &"", p_test: Callable = Callable()) -> void:
		super(p_name)
		test = p_test

	func _tick(ctx: DotNpcAiContext) -> Status:
		if not test.is_valid():
						# A condition with no test fails, not succeeds: a tree whose guards silently pass runs every branch
						# at once, which is harder to trace to a missing callable than a branch that never runs.
			return Status.FAILURE

		return Status.SUCCESS if bool(test.call(ctx)) else Status.FAILURE


## Runs a callable and returns whatever it returns.
## It may return a [enum DotNpcAiNode.Status] for several ticks' work or a [bool] for none; bool is the common case and writing `Status.SUCCESS` for "I moved a bit" is friction that stops people using the tree.
class Action:
	extends DotNpcAiNode

	## `func(ctx: DotNpcAiContext) -> Status | bool`.
	var act: Callable = Callable()

	## `func(ctx: DotNpcAiContext) -> void`, called when this is abandoned mid-action.
	var on_abort: Callable = Callable()

	func _init(p_name: StringName = &"", p_act: Callable = Callable()) -> void:
		super(p_name)
		act = p_act

	func _tick(ctx: DotNpcAiContext) -> Status:
		if not act.is_valid():
			return Status.FAILURE

		var result: Variant = act.call(ctx)

		if result is bool:
			return Status.SUCCESS if result else Status.FAILURE

		if result is int:
			var raw := int(result)
			return raw as Status if raw >= 0 and raw < Status.size() else Status.SUCCESS

				# A callable that returned nothing did its work and is done: a null as failure would make every
				# `func(_ctx) -> void:` action a branch that never continues, the commonest thing to write.
		return Status.SUCCESS

	func _abort(ctx: DotNpcAiContext) -> void:
		if on_abort.is_valid():
			on_abort.call(ctx)

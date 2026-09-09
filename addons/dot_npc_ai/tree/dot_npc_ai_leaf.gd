class_name DotNpcAiLeaf
extends DotNpcAiNode

## The two leaves a game actually writes: a condition and an action.
##
## [b]Callables rather than subclasses, for the ordinary case.[/b] A tree is mostly
## one-line questions — "do I have a target", "is it closer than four metres" — and a
## class per question is a file per question. A game with a leaf worth naming subclasses
## [DotNpcAiNode] directly, and that is the same thing this is built on.

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
			# A condition with no test fails rather than succeeding. A tree whose
			# guards silently pass is a tree where every branch runs, and the resulting
			# NPC does everything at once — which is much harder to read back to a
			# missing callable than a branch that never runs.
			return Status.FAILURE

		return Status.SUCCESS if bool(test.call(ctx)) else Status.FAILURE


## Runs a callable and returns whatever it returns.
##
## The callable may return a [enum DotNpcAiNode.Status] for something that takes several
## ticks, or a [bool] for something that does not — a bool is the common case and having
## to write `return DotNpcAiNode.Status.SUCCESS` for "I moved a bit" is the sort of
## friction that makes people not use the tree.
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

		# A callable that returned nothing did its work and is done. Treating a null as
		# a failure would make every `func(_ctx) -> void:` action a branch that never
		# continues, which is the commonest thing to write and would be wrong by
		# default.
		return Status.SUCCESS

	func _abort(ctx: DotNpcAiContext) -> void:
		if on_abort.is_valid():
			on_abort.call(ctx)

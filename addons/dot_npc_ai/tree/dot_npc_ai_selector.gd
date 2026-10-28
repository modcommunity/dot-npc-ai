class_name DotNpcAiSelector
extends DotNpcAiComposite

## Runs its children in order until one succeeds. "Try this, or that, or the other." SUCCESS on the first success, RUNNING while one runs, FAILURE only when all fail; order is priority.
## [b][member reactive] is the difference between an NPC that notices and one that does not:[/b] a plain selector never re-checks the children above the running one, so a wanderer ignores the player walking in front of it. Reactive re-runs from the first child each tick and aborts the running one when a higher branch becomes viable.
## It is the default despite costing more, being what almost every game wants at the root.

## Whether higher-priority children are re-checked while a lower one is running.
var reactive: bool = true


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name, p_children)


func _tick(ctx: DotNpcAiContext) -> Status:
	var resume := _resume_from()
	var from := 0 if reactive else resume

	for i in range(from, _children.size()):
		var status := _children[i].tick(ctx)

		if status == Status.RUNNING:
						# Something above the running child took over. Tell the old one it is being abandoned, or an
						# action holding a door, a reservation or an animation never lets go.
			if reactive and resume >= 0 and resume != i and resume < _children.size():
				if _children[resume].is_running:
					_children[resume].abort(ctx)

			_running_child = i
			return Status.RUNNING

		if status == Status.SUCCESS:
			if reactive and resume != i and resume < _children.size():
				if _children[resume].is_running:
					_children[resume].abort(ctx)

			return Status.SUCCESS

	return Status.FAILURE

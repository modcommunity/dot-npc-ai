class_name DotNpcAiSelector
extends DotNpcAiComposite

## Runs its children in order until one succeeds. "Try this, or that, or the other."
##
## SUCCESS on the first child that succeeds, RUNNING while one is running, FAILURE only
## when every child has failed. This is priority: put the most important behaviour
## first, because the first one that can run is the one that does.
##
## [b][member reactive] is the difference between an NPC that notices and one that does
## not.[/b] A plain selector resumes at the running child and never re-checks the ones
## above it, so a zombie that started wandering keeps wandering after the player walks
## in front of it — the "am I being shot at" branch at the top is never reached again
## until the wander finishes. Reactive re-runs from the first child every tick and
## aborts the running one when something above it becomes viable. That is what almost
## every game wants at the root of its tree, which is why it is the default here even
## though it is the more expensive of the two.

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
			# Something above the previously running child took over. Tell the old one
			# it is being abandoned, or an action holding a door, a reservation or an
			# animation never lets go.
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

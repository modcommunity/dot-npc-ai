class_name DotNpcAiSequence
extends DotNpcAiComposite

## Runs its children in order until one fails. "Do this, then that." FAILURE on the first failure, RUNNING while one runs, SUCCESS only when all succeed.
## By default it resumes at the running child and does NOT re-run earlier ones ("open the door, walk through, close it" must not re-open the door sixty times a second). [b][member reactive][/b] is for GUARD-then-BEHAVIOUR: a plain sequence resumes at the action and never asks the guard again, so the NPC chases a target it no longer has.
## Reactive is not the default because the door bug is louder than a guard never re-checked.

## Whether every child is re-run from the first each tick, rather than resumed.
##
## When a child before the running one fails, the running one is told it was abandoned.
var reactive: bool = false


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name, p_children)


func _tick(ctx: DotNpcAiContext) -> Status:
	var resume := _resume_from()
	var from := 0 if reactive else resume

	for i in range(from, _children.size()):
		var status := _children[i].tick(ctx)

		if status == Status.RUNNING:
			_running_child = i
			return Status.RUNNING

		if status == Status.FAILURE:
						# A guard that stopped holding, with the action behind it mid-way: it has to be told or whatever it
						# reserved is never released, and on a reactive sequence this is the ordinary path.
			if reactive and resume >= 0 and resume != i and resume < _children.size():
				if _children[resume].is_running:
					_children[resume].abort(ctx)

			return Status.FAILURE

	return Status.SUCCESS


## A guard-then-behaviour sequence, which is what a tree is mostly made of.
static func reactive_with(
	p_name: StringName, p_children: Array[DotNpcAiNode]
) -> DotNpcAiSequence:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var sequence := new(p_name, p_children)
	sequence.reactive = true
	return sequence

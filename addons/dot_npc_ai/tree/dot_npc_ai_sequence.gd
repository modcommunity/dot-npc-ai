class_name DotNpcAiSequence
extends DotNpcAiComposite

## Runs its children in order until one fails. "Do this, then that, then the other."
##
## FAILURE on the first child that fails, RUNNING while one is running, SUCCESS only
## when every child has succeeded.
##
## [b]By default it resumes at the running child and does NOT re-run the ones before
## it.[/b] That is the whole point and the thing hand-written trees get wrong: a
## sequence of "open the door, walk through, close it" whose middle step is RUNNING must
## not re-open the door sixty times a second.
##
## [b][member reactive] is the other half, and leaving it off is a real trap.[/b] The
## commonest thing anybody writes is a guard followed by an action —
## "have I got a target" then "walk at it" — where the action returns RUNNING for ever.
## A plain sequence resumes at the action and [i]never asks the guard again[/i], so the
## NPC chases a target it no longer has until something else interrupts it. This was
## written into this addon's own fixture on the first pass and the suite caught it as a
## zombie that would not go home.
##
## So: a sequence of STEPS is plain, and a sequence of GUARD-then-BEHAVIOUR is reactive.
## Reactive is not the default because getting it wrong the other way is the door bug
## above, which is louder and easier to see than a guard that is never re-checked.

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
			# A guard that has stopped holding, with the action behind it still mid-way
			# through something. It has to be told, or whatever it reserved is never
			# released — and on a reactive sequence this is the ordinary path rather
			# than the exceptional one.
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

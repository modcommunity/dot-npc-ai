class_name DotNpcAiParallel
extends DotNpcAiComposite

## Runs every child every tick. "Walk there while shooting and shouting."
##
## [b]Not concurrency.[/b] Nothing here is threaded and nothing suspends: every child is
## ticked in order within one call, and "parallel" names the fact that all of them get a
## tick rather than the first one that will take it. A tree that needed real concurrency
## would need a scheduler, and an NPC has never needed one.
##
## [member success_threshold] and [member failure_threshold] are how many children must
## end that way for the whole node to. The defaults are the useful pair: succeed when
## every child does, fail as soon as one does — which is "do all of these, and give up
## if any of them becomes impossible".

## How many children must succeed. 0 means all of them.
var success_threshold: int = 0

## How many must fail before this fails. 0 means one is enough.
var failure_threshold: int = 1


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name, p_children)


func _tick(ctx: DotNpcAiContext) -> Status:
	var succeeded := 0
	var failed := 0

	# Every child is ticked before anything is decided, deliberately. Returning early
	# on the first failure would leave the later children un-ticked while this node is
	# nominally running all of them, so an NPC that fails to find cover would also stop
	# shouting — and shouting is the half that was working.
	for child in _children:
		match child.tick(ctx):
			Status.SUCCESS:
				succeeded += 1
			Status.FAILURE:
				failed += 1
			_:
				pass

	var wanted_success := success_threshold if success_threshold > 0 else _children.size()
	var wanted_failure := failure_threshold if failure_threshold > 0 else _children.size()

	if failed >= wanted_failure:
		_abort_children(ctx)
		return Status.FAILURE

	if succeeded >= wanted_success:
		_abort_children(ctx)
		return Status.SUCCESS

	return Status.RUNNING


## Abandons every child still running. A parallel has no single running child, so
## [method DotNpcAiComposite._abort_running] is not enough here.
func _abort_children(ctx: DotNpcAiContext) -> void:
	for child in _children:
		if child.is_running:
			child.abort(ctx)


func _abort(ctx: DotNpcAiContext) -> void:
	_abort_children(ctx)

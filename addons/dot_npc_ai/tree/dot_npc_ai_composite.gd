class_name DotNpcAiComposite
extends DotNpcAiNode

## A node with children. The base for [DotNpcAiSelector] and [DotNpcAiSequence].
## It owns the running-child index, because the whole tree turns on that rule: a composite whose child returned RUNNING resumes there next tick, not at the first (see [DotNpcAiNode]).

var _children: Array[DotNpcAiNode] = []

## Which child is mid-way through something, or -1.
var _running_child: int = -1


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name)
	_children = p_children.duplicate()


func add(child: DotNpcAiNode) -> DotNpcAiComposite:
	# Returns self so a tree can be written as one expression, which is the only way a
	# tree written in code stays readable past about six nodes.
	_children.append(child)
	return self


func children() -> Array[DotNpcAiNode]:
	return _children


func child_count() -> int:
	return _children.size()


## Where to resume from this tick, and clears the memory.
## Reset before running, not after: a composite may return RUNNING again from a different child and would clear what it just recorded.
func _resume_from() -> int:
	var from := _running_child if _running_child >= 0 else 0
	_running_child = -1
	return from


## Abandons whatever child was running. Called when this composite gives up on it.
func _abort_running(ctx: DotNpcAiContext) -> void:
	if _running_child >= 0 and _running_child < _children.size():
		_children[_running_child].abort(ctx)

	_running_child = -1


func _abort(ctx: DotNpcAiContext) -> void:
	_abort_running(ctx)

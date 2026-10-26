extends Node

## The suite's harness: counters, [method _check], [method _section]; the test layers extend it.

const BODY := "res://fixtures/npc_body.tscn"
const BRAIN := "res://fixtures/zombie_brain.gd"
const SEARCHER := "res://fixtures/searcher_brain.gd"
const GUNNER := "res://fixtures/gunner_brain.gd"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

var _world: Node3D = null


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


func _context() -> DotNpcAiContext:
	return DotNpcAiContext.make(null, null)


## A leaf that returns RUNNING for [param ticks] ticks, then SUCCESS, and counts.
##
## Counters live in an Array because a GDScript lambda captures locals BY VALUE, so a
## plain int incremented inside one stays zero outside it — and a suite built on that
## reports a failure for a node that ran perfectly.
func _counting(ticks: int, log_into: Array, tag: String) -> DotNpcAiLeaf.Action:
	var state := {"left": ticks}

	return DotNpcAiLeaf.Action.new(StringName(tag), func(_ctx: DotNpcAiContext) -> int:
		log_into.append(tag)

		if int(state["left"]) > 0:
			state["left"] = int(state["left"]) - 1
			return DotNpcAiNode.Status.RUNNING

		state["left"] = ticks
		return DotNpcAiNode.Status.SUCCESS
	)

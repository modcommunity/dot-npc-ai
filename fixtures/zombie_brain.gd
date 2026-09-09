extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

## A brain for the self-test: a machine of three states over a tree of two branches.
##
## [b]Extends a PATH, not [code]DotNpcAiBrain[/code], and the suite asserts that this
## file loads through dot-npc's spawner.[/b] It is the shape a brain delivered inside a
## mounted dot-cloud pack must have, and writing the fixture the other way would make
## the suite pass for a shape the addon does not support.

var chases: int = 0
var wanders: int = 0
var heard_something: int = 0


func _build() -> void:
	initial_state = &"idle"

	machine = DotNpcAiMachine.new()
	machine.add(
		DotNpcAiState.make(&"idle")
			.when(func(_c: DotNpcAiContext) -> bool: return npc.has_target(), &"chasing")
	)
	machine.add(
		DotNpcAiState.make(&"chasing")
			.when(func(_c: DotNpcAiContext) -> bool: return not npc.has_target(), &"searching")
	)
	machine.add(
		DotNpcAiState.make(&"searching")
			.when(func(_c: DotNpcAiContext) -> bool: return npc.has_target(), &"chasing")
			.after(3.0, &"idle")
	)

	# REACTIVE, because this is a guard followed by an action that never finishes.
	# A plain sequence resumes at the action and never asks the guard again, so the
	# zombie chases a target it no longer has for ever. That is exactly what the first
	# version of this fixture did and what the suite caught.
	tree = DotNpcAiSelector.new(&"root", [
		DotNpcAiSequence.reactive_with(&"chase", [
			DotNpcAiLeaf.Condition.new(&"has a target", _has_target),
			DotNpcAiLeaf.Action.new(&"walk at it", _chase),
		]),
		DotNpcAiLeaf.Action.new(&"wander", _wander),
	])


func _has_target(_ctx: DotNpcAiContext) -> bool:
	return npc.has_target()


func _chase(ctx: DotNpcAiContext) -> int:
	chases += 1

	# The last seen position, remembered for six seconds. What "searching" walks to.
	ctx.put(&"last_seen", target_position(), 6.0)

	steer_with_spacing(target_position(), tune(&"speed", 4.0), ctx.delta)

	return DotNpcAiNode.Status.RUNNING


func _wander(ctx: DotNpcAiContext) -> int:
	wanders += 1

	if ctx.blackboard.has(&"last_seen", ctx.now):
		heard_something += 1

	halt()

	return DotNpcAiNode.Status.RUNNING

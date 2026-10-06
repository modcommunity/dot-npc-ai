extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

## A brain for the self-test: the shape a game's soldier takes, built from the base class's
## ready-made leaves rather than its own.
##
## [codeblock]
## selector (reactive)
##   flee danger                          a grenade beats everything
##   sequence (reactive)  has a target?
##     selector
##       sequence (reactive)  holds an attack slot?  -> walk at it
##       surround                          wait a turn on the ring, working round
##   search                               where the enemy probably went
##   idle
## [/codeblock]
##
## [b]No character of its own.[/b] The definition names one with `"skill"` in its meta, and
## its squad with `"squad"`, which are the catalogue paths the suite asserts.

var chases: int = 0
var searches: int = 0
var idles: int = 0
var flees: int = 0
var surrounds: int = 0


func _build() -> void:
	tree = DotNpcAiSelector.new(&"root", [
		DotNpcAiLeaf.Action.new(&"flee", _flee),
		DotNpcAiSequence.reactive_with(&"fight", [
			DotNpcAiLeaf.Condition.new(&"has a target", _has_target),
			DotNpcAiSelector.new(&"engage", [
				DotNpcAiSequence.reactive_with(&"attack", [
					DotNpcAiLeaf.Condition.new(&"has a slot", _has_slot),
					DotNpcAiLeaf.Action.new(&"walk at it", _chase),
				] as Array[DotNpcAiNode]),
				DotNpcAiLeaf.Action.new(&"surround", _surround),
			] as Array[DotNpcAiNode]),
		] as Array[DotNpcAiNode]),
		DotNpcAiLeaf.Action.new(&"search", _search),
		DotNpcAiLeaf.Action.new(&"idle", _idle),
	] as Array[DotNpcAiNode])


func _has_target(_ctx: DotNpcAiContext) -> bool:
	return npc.has_target()


func _has_slot(_ctx: DotNpcAiContext) -> bool:
	return claim_attack_slot()


func _flee(ctx: DotNpcAiContext) -> int:
	var status := flee_danger(ctx, tune(&"speed", 4.0) * 1.3)

	if status != DotNpcAiNode.Status.FAILURE:
		flees += 1

	return status


func _chase(ctx: DotNpcAiContext) -> int:
	chases += 1

	var at := target_position(Vector3.INF)

	if at == Vector3.INF:
		halt()
		return DotNpcAiNode.Status.RUNNING

	var flat := at - npc.position()
	flat.y = 0.0

	if flat.length() < 1.0:
		halt()
		return DotNpcAiNode.Status.RUNNING

	steer_toward(at, tune(&"speed", 4.0), ctx.delta)
	return DotNpcAiNode.Status.RUNNING


func _surround(ctx: DotNpcAiContext) -> int:
	var status := surround(ctx, tune(&"speed", 4.0), tune(&"ring", 4.0))

	if status != DotNpcAiNode.Status.FAILURE:
		surrounds += 1

	return status


func _search(ctx: DotNpcAiContext) -> int:
	var status := search(ctx, tune(&"speed", 4.0))

	if status != DotNpcAiNode.Status.FAILURE:
		searches += 1

	return status


func _idle(_ctx: DotNpcAiContext) -> int:
	idles += 1
	halt()
	return DotNpcAiNode.Status.RUNNING

extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

## A brain for the self-test: something that fights at range. Tree: reactive selector of flee danger, a reactive sequence on "has a target?" (the squad's one flank role goes round to its back, firing; otherwise suppress), search, idle.
## Counts the shots it was allowed to take, so the suite can ask whether it fired at all and whether it held fire when it should.

var shots: int = 0


func _build() -> void:
	tree = DotNpcAiSelector.new(&"root", [
		DotNpcAiLeaf.Action.new(&"flee", func(c: DotNpcAiContext) -> int: return flee_danger(c, 5.0)),
		DotNpcAiSequence.reactive_with(&"fight", [
			DotNpcAiLeaf.Condition.new(&"has a target", func(_c: DotNpcAiContext) -> bool: return npc.has_target()),
			DotNpcAiSelector.new(&"engage", [
				DotNpcAiSequence.reactive_with(&"flank", [
					DotNpcAiLeaf.Condition.new(&"flank role", func(_c: DotNpcAiContext) -> bool:
						return tactics() >= 0.5 and claim_role(ROLE_FLANK, 1)),
					DotNpcAiLeaf.Action.new(&"go round", _flank),
				] as Array[DotNpcAiNode]),
				DotNpcAiLeaf.Action.new(&"suppress", _engage),
			] as Array[DotNpcAiNode]),
		] as Array[DotNpcAiNode]),
		DotNpcAiLeaf.Action.new(&"search", func(c: DotNpcAiContext) -> int: return search(c, 4.0)),
		DotNpcAiLeaf.Action.new(&"idle", func(_c: DotNpcAiContext) -> int:
			halt()
			return DotNpcAiNode.Status.RUNNING),
	] as Array[DotNpcAiNode])


func _engage(ctx: DotNpcAiContext) -> int:
	var status := hold_range(ctx, tune(&"speed", 4.0), tune(&"near", 8.0), tune(&"far", 14.0))
	var muzzle := npc.position() + Vector3(0, 1.4, 0)

	if ready_to_fire(muzzle):
		var _aim := aim_solution(muzzle)
		shots += 1

	return status


var flanks: int = 0


func _flank(ctx: DotNpcAiContext) -> int:
	flanks += 1
	var center := target_position(Vector3.INF)

	if center == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var radius := (tune(&"near", 8.0) + tune(&"far", 14.0)) * 0.5
	var point := DotNpcAiTactics.ring_point(center, here, radius, _enemy_facing(center), flank_lead)
	var flat := point - here
	flat.y = 0.0

	if flat.length() > 1.0:
		steer_with_spacing(point, tune(&"speed", 4.0), ctx.delta)
	else:
		halt()

	face(center - here)
	var muzzle := here + Vector3(0, 1.4, 0)

	if ready_to_fire(muzzle):
		var _aim := aim_solution(muzzle)
		shots += 1

	return DotNpcAiNode.Status.RUNNING

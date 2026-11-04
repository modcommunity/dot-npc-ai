class_name DotNpcAiSteerBrain
extends "dot_npc_ai_brain.gd"

## A [DotNpcAiBrain] for a crowd that needs steering and no tree: seeks its target (wanders without one) and keeps its spacing.
## Thinks as gather, decide, apply: only the decide step is pure, so it is the one brain here that may run on [member DotNpcSpawner.think_workers].
## Extended by path, like every brain. Set `speed`, `spacing` and `wander_jitter` in the definition's meta.

var _ticks: int = 0
var _wander_angle: float = 0.0


func splits_think() -> bool:
	return true


func is_thread_safe() -> bool:
	return true


func _npc_gather(delta: float) -> Variant:
	if npc == null or not npc.is_alive():
		return null
	var spacing := tune(&"spacing", 1.6)
	var forward := npc.facing()
	return {
		"here": npc.position(),
		"goal": target_position() if npc.has_target() else Vector3.INF,
		"near": neighbours(spacing),
		"right": Vector3(-forward.z, 0.0, forward.x),
		"speed": tune(&"speed", 4.0),
		"spacing": spacing,
		"jitter": tune(&"wander_jitter", 0.3),
		"angle": _wander_angle,
		"seed": hash([npc.seed, _ticks]),
		"delta": delta,
	}


func _npc_decide(data: Variant) -> Variant:
	if data == null:
		return null
	var here: Vector3 = data["here"]
	var goal: Vector3 = data["goal"]
	var angle: float = data["angle"]
	var wanted := Vector3.ZERO
	if goal != Vector3.INF:
		wanted = DotNpcAiSteering.seek(here, goal)
	else:
		angle = DotNpcAiSteering.wander(angle, data["jitter"], data["seed"])
		wanted = DotNpcAiSteering.angle_to_direction(angle)
	var apart := DotNpcAiSteering.separate(here, data["near"], data["spacing"], data["right"])
	var dir := wanted + apart * 0.6
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.ZERO
	return {"dir": dir, "angle": angle, "speed": data["speed"], "delta": data["delta"]}


func _npc_apply(intent: Variant) -> void:
	_ticks += 1
	if intent == null:
		return
	_wander_angle = intent["angle"]
	var dir: Vector3 = intent["dir"]
	if dir.length() < 0.001:
		return
	steer_toward(npc.position() + dir * 4.0, intent["speed"], intent["delta"])

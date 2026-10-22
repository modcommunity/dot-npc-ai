class_name DotNpcAiUtilityGate
extends DotNpcAiNode

## SUCCESS while the brain's utility choice is [member action]: a guard to put in front of a branch.

var action: StringName = &""


func _init(p_action: StringName = &"") -> void:
	super(p_action)
	action = p_action


func _tick(ctx: DotNpcAiContext) -> Status:
	var brain := ctx.brain
	if brain == null or not brain.has_method(&"utility_choose"):
		return Status.FAILURE
	return Status.SUCCESS if StringName(brain.call(&"utility_choose")) == action else Status.FAILURE

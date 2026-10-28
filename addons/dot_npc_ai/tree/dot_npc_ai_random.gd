class_name DotNpcAiRandomSelector
extends DotNpcAiComposite

## Picks one child by weight and runs it: variety without a second decision model. Without chance every NPC of a kind does the same thing (three zombies searching one spot arrive together and stand in a row); weights say "usually chase, sometimes flank" where an even selector cannot.
## The choice is made on entry and kept: re-rolling a RUNNING child abandons it each tick, the addon's RUNNING-is-resumed rule from the tempting direction.
## `DotNpcAiRandomSelector.new(&"search", [go_left, go_right, wait])`, then `set_weights([2.0, 2.0, 1.0])` and `salt = npc.seed`.

## One weight per child. Missing or short, every child weighs 1.
var weights: PackedFloat32Array = PackedFloat32Array()

## Mixed into the roll so two of these in one tree, or on two NPCs, disagree.
## At zero every NPC in the world agrees, which this node exists to prevent. Set it to the NPC's seed ([member DotNpcInstance.seed]), never its instance id, which moves between runs.
var salt: int = 0

## Whether a chosen child that fails ends this node, or the next one is tried.
## Off: a choice, not a fallback chain. On is for "pick one, and if it will not run pick another" (a spawn point, a barked line).
var retry_on_failure: bool = false

var _chosen: int = -1
var _tried: Array[int] = []


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name, p_children)


func set_weights(values: Array) -> DotNpcAiRandomSelector:
	weights = PackedFloat32Array()

	for value in values:
				# A negative weight is not "never picked": it breaks the total the roll is scaled against and
				# shifts every later child's share. Clamped, not refused, because weights are written by hand.
		weights.append(maxf(float(value), 0.0))

	return self


func weight_of(index: int) -> float:
	if index < 0 or index >= _children.size():
		return 0.0
	if index >= weights.size():
		return 1.0
	return weights[index]


## Which child was chosen last time this node was entered. -1 before the first.
func chosen() -> int:
	return _chosen


func _enter(ctx: DotNpcAiContext) -> void:
	_tried.clear()
	_chosen = _roll(ctx, [])


func _tick(ctx: DotNpcAiContext) -> Status:
	if _children.is_empty():
		return Status.FAILURE

		# Resumed at whatever was running, not re-rolled. Reads [member _running_child] directly, not
		# [method DotNpcAiComposite._resume_from], whose default 0 is right for a selector and wrong here:
		# every roll would land on child zero (three hundred picks of three hundred went one way).
	if _running_child >= 0 and _running_child < _children.size():
		_chosen = _running_child

	_running_child = -1

	if _chosen < 0 or _chosen >= _children.size():
		return Status.FAILURE

	var status := _children[_chosen].tick(ctx)

	if status == Status.RUNNING:
		_running_child = _chosen
		return Status.RUNNING

	if status == Status.SUCCESS or not retry_on_failure:
		return status

	_tried.append(_chosen)

	if _tried.size() >= _children.size():
		return Status.FAILURE

	# One retry per tick rather than a loop, for [Repeat]'s reason: a loop here spins
	# for ever the first time every child fails without suspending, and that hangs the
	# server rather than misbehaving.
	_chosen = _roll(ctx, _tried)

	return Status.RUNNING if _chosen >= 0 else Status.FAILURE


## Picks a child by weight, skipping anything in [param exclude].
func _roll(ctx: DotNpcAiContext, exclude: Array) -> int:
	var total := 0.0

	for i in _children.size():
		if exclude.has(i):
			continue
		total += weight_of(i)

	if total <= 0.0:
		return -1

	var target := DotNpcAiNode.deterministic_unit(
		ctx.tick_index + salt, salt ^ 0x1b873593
	) * total
	var walked := 0.0

	for i in _children.size():
		if exclude.has(i):
			continue

		walked += weight_of(i)

		if target < walked:
			return i

	# Floating-point arithmetic can leave `target` a hair above the total. Falling
	# through to the last eligible child is right and returning -1 is not: the roll
	# picked something, and the loop lost it to rounding.
	for i in range(_children.size() - 1, -1, -1):
		if not exclude.has(i) and weight_of(i) > 0.0:
			return i

	return -1


func describe() -> Dictionary:
	return {
		"name": String(node_name),
		"children": _children.size(),
		"chosen": _chosen,
		"salt": salt,
	}

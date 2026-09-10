class_name DotNpcAiRandomSelector
extends DotNpcAiComposite

## Picks one child by weight and runs it. Variety, without a second decision model.
##
## [b]A tree with no chance in it makes every NPC of a kind do the same thing in the
## same situation.[/b] Three zombies that lose sight of a player all walk to the last
## place they saw them, arrive together, and stand in a row — which is not a bug in any
## of them and is obviously wrong to anybody watching. One of them searching left, one
## right and one waiting is the whole difference, and it is one node.
##
## Weights rather than an even roll, because "usually chase, sometimes flank" is the
## shape a designer wants and an even selector cannot say it.
##
## [b]The choice is made on entry and kept.[/b] Re-rolling a child that returned RUNNING
## abandons whatever it was doing on the next tick, so an NPC that chose to flank
## re-decides sixty times a second and goes nowhere. This is the same rule the whole
## addon is built on — a node that returned RUNNING is resumed, not restarted — reached
## from the one direction where it is tempting to break it.
##
## [codeblock]
## var search := DotNpcAiRandomSelector.new(&"search", [go_left, go_right, wait])
## search.set_weights([2.0, 2.0, 1.0])       # waiting is half as likely
## search.salt = npc.instance_id             # and these three do not agree
## [/codeblock]

## One weight per child. Missing or short, every child weighs 1.
var weights: PackedFloat32Array = PackedFloat32Array()

## Mixed into the roll so two of these in one tree — or on two NPCs — disagree.
##
## Leaving it at zero is a working selector that every NPC in the world agrees with,
## which is the thing this node exists to prevent. A game sets it to the instance id.
var salt: int = 0

## Whether a chosen child that fails ends this node, or the next one is tried.
##
## Off: a random selector is a choice, not a fallback chain. On is for "pick one at
## random, and if it will not run pick another", which is what a spawn point or a
## barked line wants.
var retry_on_failure: bool = false

var _chosen: int = -1
var _tried: Array[int] = []


func _init(p_name: StringName = &"", p_children: Array[DotNpcAiNode] = []) -> void:
	super(p_name, p_children)


func set_weights(values: Array) -> DotNpcAiRandomSelector:
	weights = PackedFloat32Array()

	for value in values:
		# A negative weight is not "never picked", it is a total that no longer sums to
		# what the roll is scaled against — and every child after it in the walk gets a
		# share it was not given. Clamped rather than refused, because a weight is
		# usually written by hand.
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

	# Resumed at whatever was running, not re-rolled. See the class documentation.
	#
	# [member _running_child] is read directly rather than through
	# [method DotNpcAiComposite._resume_from], which answers 0 when nothing was
	# running — the right default for a sequence or a selector, which both start at
	# their first child, and exactly wrong here: it makes every roll land on child
	# zero, which is a random selector that is not random. The suite caught it as
	# three hundred picks out of three hundred going the same way.
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

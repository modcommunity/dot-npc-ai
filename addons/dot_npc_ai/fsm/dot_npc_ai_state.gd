class_name DotNpcAiState
extends RefCounted

## One state of a [DotNpcAiMachine]: what to do, and what would make it stop.
## Here beside the behaviour tree because a tree is overkill for most NPCs (a zombie has four states): one branch and guard per state is a state machine with extra steps and worse debugging.
## Transitions live on the state, not in a table, so reading one state tells you when it stops as well as what it does.

## Stable id. What a transition names and what a debugger prints.
var id: StringName = &""

## `func(ctx: DotNpcAiContext) -> void`, on the tick this state begins.
var on_enter: Callable = Callable()

## `func(ctx: DotNpcAiContext) -> void`, every tick this state is current.
var on_tick: Callable = Callable()

## `func(ctx: DotNpcAiContext) -> void`, on the tick this state ends.
var on_exit: Callable = Callable()

## Transitions out, in priority order: the first whose test passes wins.
## Order is the priority, as in a selector: "flee when hurt" goes above "chase" or an NPC on one health point keeps chasing.
var transitions: Array = []

## Seconds after which [member timeout_to] is taken. 0 for never.
## A state with no way out (an attack whose target died, an unreachable search) is the commonest broken NPC; checked before ordinary transitions so an always-false one cannot starve it.
var timeout: float = 0.0

var timeout_to: StringName = &""


static func make(p_id: StringName, p_tick: Callable = Callable()) -> DotNpcAiState:
	var state := DotNpcAiState.new()
	state.id = p_id
	state.on_tick = p_tick
	return state


## Adds a transition. [param test] is `func(ctx) -> bool`.
func when(test: Callable, to: StringName) -> DotNpcAiState:
	# Returns self so a state and its exits are one expression.
	transitions.append({"test": test, "to": to})
	return self


## Adds a timeout. Returns self, for the same reason.
func after(seconds: float, to: StringName) -> DotNpcAiState:
	timeout = seconds
	timeout_to = to
	return self


## Which state to go to now, or empty to stay. [param elapsed] is seconds in this state.
func next_state(ctx: DotNpcAiContext, elapsed: float) -> StringName:
	if timeout > 0.0 and elapsed >= timeout and timeout_to != &"":
		return timeout_to

	for entry in transitions:
		var transition: Dictionary = entry
		var test: Callable = transition["test"]

		if test.is_valid() and bool(test.call(ctx)):
			return StringName(transition["to"])

	return &""


func describe() -> Dictionary:
	return {
		"state": String(id),
		"exits": transitions.size(),
		"timeout": "%.1fs -> %s" % [timeout, String(timeout_to)] if timeout > 0.0 else "-",
	}

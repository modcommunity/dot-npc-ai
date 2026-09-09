class_name DotNpcAiState
extends RefCounted

## One state of a [DotNpcAiMachine]: what to do, and what would make it stop.
##
## [b]A state machine is here beside the behaviour tree because a tree is overkill for
## most NPCs.[/b] A zombie has four states and a shopkeeper has two; expressing either
## as a tree is a tree with one branch per state and a guard on each, which is a state
## machine with extra steps and worse debugging. The tree earns its keep on the NPC with
## fifteen behaviours and priorities between them, and that NPC is the rare one.
##
## [b]Transitions live on the state, not in a table.[/b] The table is the textbook
## answer and it puts the reason a state ends somewhere other than the state — so
## reading one state tells you what it does and not when it stops, which is the half a
## person is usually looking for.

## Stable id. What a transition names and what a debugger prints.
var id: StringName = &""

## `func(ctx: DotNpcAiContext) -> void`, on the tick this state begins.
var on_enter: Callable = Callable()

## `func(ctx: DotNpcAiContext) -> void`, every tick this state is current.
var on_tick: Callable = Callable()

## `func(ctx: DotNpcAiContext) -> void`, on the tick this state ends.
var on_exit: Callable = Callable()

## Transitions out, in priority order: the first whose test passes wins.
##
## Order is the priority, exactly as a selector's child order is. "Flee when hurt" goes
## above "chase the target" or an NPC on one health point keeps chasing.
var transitions: Array = []

## Seconds after which [member timeout_to] is taken. 0 for never.
##
## [b]A state with no way out is the commonest broken NPC there is[/b] — an attack whose
## target died, a search whose destination is unreachable — and a timeout is the cheap
## guard against every one of them. It is checked before the ordinary transitions so it
## cannot be starved by one that is always false.
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

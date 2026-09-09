class_name DotNpcAiMachine
extends RefCounted

## A state machine over [DotNpcAiState]s. The simpler half of this addon.
##
## [b]Transitions are taken at most [member max_transitions_per_tick] times in one
## tick.[/b] Two states whose conditions each send the NPC to the other is an infinite
## loop that hangs the server rather than misbehaving — and it is written by accident
## every time somebody adds a state. The cap turns a hang into a warning and an NPC
## stuck in one of the two, which is a bug a person can see and report.

const CHANNEL := "npc.ai"

## The state changed. [param from] is empty on the first entry.
signal changed(from: StringName, to: StringName)

## How many transitions may be taken in one tick before the machine gives up.
##
## Four rather than one, because a legitimate chain does happen — "idle" to "alerted" to
## "chasing" on the tick a player appears — and a machine that only ever took one would
## make that take three ticks for no reason.
var max_transitions_per_tick: int = 4

## Id -> DotNpcAiState.
var _states: Dictionary = {}

var _current: StringName = &""

## Simulated seconds when the current state was entered.
var _entered_at: float = 0.0

var transition_count: int = 0

## How many times the per-tick cap has been hit. Nonzero means two states are fighting.
var thrash_count: int = 0


func add(state: DotNpcAiState) -> DotNpcAiMachine:
	if state != null and state.id != &"":
		_states[state.id] = state

	return self


func has(id: StringName) -> bool:
	return _states.has(id)


func state_count() -> int:
	return _states.size()


func current() -> StringName:
	return _current


func current_state() -> DotNpcAiState:
	var found: Variant = _states.get(_current)
	return found if found is DotNpcAiState else null


## Simulated seconds spent in the current state.
func elapsed(now: float) -> float:
	return now - _entered_at


## Puts the machine into [param id] without asking any transition.
##
## What a game calls to start the machine, and to force a state from outside — an NPC
## that has just been shot goes to "hurt" because it was shot, not because a condition
## noticed.
func go_to(ctx: DotNpcAiContext, id: StringName) -> DotResult:
	if not _states.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "No such state.", String(id))

	var from := _current
	var leaving := current_state()

	if leaving != null and leaving.on_exit.is_valid():
		leaving.on_exit.call(ctx)

	_current = id
	_entered_at = ctx.now
	transition_count += 1

	var entering: DotNpcAiState = _states[id]

	if entering.on_enter.is_valid():
		entering.on_enter.call(ctx)

	changed.emit(from, id)

	return DotResult.success(entering)


## One tick: take any transitions that apply, then run the state that is current.
##
## [b]Transitions first, then the tick.[/b] The other order runs a state for one tick
## after its own exit condition became true, which for "flee when hurt" is one more tick
## of walking toward the thing that is hurting you.
func tick(ctx: DotNpcAiContext) -> void:
	if _current == &"":
		return

	var taken := 0

	while taken < max_transitions_per_tick:
		var state := current_state()

		if state == null:
			return

		var next := state.next_state(ctx, elapsed(ctx.now))

		if next == &"" or next == _current:
			break

		if not _states.has(next):
			DotLog.warn(CHANNEL, "a transition names a state that does not exist", {
				"from": String(_current),
				"to": String(next),
			})
			break

		go_to(ctx, next)
		taken += 1

	if taken >= max_transitions_per_tick:
		# Two states sending the NPC to each other. Reported once per tick rather than
		# swallowed, because the alternative is an NPC that vibrates between two
		# behaviours and a server whose tick is mysteriously long.
		thrash_count += 1
		DotLog.warn(CHANNEL, "a state machine hit its transition cap", {
			"state": String(_current),
			"cap": max_transitions_per_tick,
		})

	var running := current_state()

	if running != null and running.on_tick.is_valid():
		running.on_tick.call(ctx)


func describe() -> Dictionary:
	return {
		"state": String(_current) if _current != &"" else "-",
		"states": _states.size(),
		"transitions": transition_count,
		"thrash": thrash_count,
	}


func describe_lines(now: float = 0.0) -> PackedStringArray:
	var out := PackedStringArray()

	out.append("state        %s (%.1fs)" % [
		String(_current) if _current != &"" else "-", elapsed(now)
	])
	out.append("transitions  %d, thrash %d" % [transition_count, thrash_count])

	for id in _states:
		var state: DotNpcAiState = _states[id]
		out.append("  %s%-14s %d exits" % [
			"* " if id == _current else "  ", String(id), state.transitions.size()
		])

	return out

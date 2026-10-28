class_name DotNpcAiContext
extends RefCounted

## Everything one tick of a decision needs, in one object: every node takes it, and a sixth argument would otherwise change fifteen places.
## [b]It names nothing from dot-npc:[/b] [member agent] is whatever the host drives and [member brain] whatever drives it, so the tree can be lifted into anything; only [DotNpcAiBrain] mentions dot-npc.

## What is being decided for. A [code]DotNpcInstance[/code] in the ordinary case.
var agent: Object = null

## What is running the decision. A [DotNpcAiBrain] in the ordinary case.
var brain: Object = null

## This agent's memory.
var blackboard: DotNpcAiBlackboard = null

## Who this agent is: reaction time, aim, aggression. Null for a character-less NPC.
## On the context, not reached through the brain, because a node two levels down a tree must not need to know which brain runs it.
var character: DotNpcAiCharacter = null

## What the NPC noticed this tick. Filled by the brain before anything runs, and read by
## guards and by [DotNpcAiDecorator.Interrupt]. Never null, so a node can ask without
## checking — a context built outside a brain simply never has anything set.
var conditions: DotNpcAiConditions = DotNpcAiConditions.new()

## Seconds in this tick.
var delta: float = 0.0

## Simulated seconds since the world began. Never a wall clock.
var now: float = 0.0

## How many ticks this context has been used for. For a node that acts every N.
var tick_index: int = 0

## Anything the game wants every node to be able to reach.
var meta: Dictionary = {}


static func make(
	p_agent: Object, p_brain: Object, p_blackboard: DotNpcAiBlackboard = null
) -> DotNpcAiContext:
	var ctx := DotNpcAiContext.new()
	ctx.agent = p_agent
	ctx.brain = p_brain
	ctx.blackboard = p_blackboard if p_blackboard != null else DotNpcAiBlackboard.new()
	return ctx


## Advances the clock. Called once per tick, before the tree runs.
func advance(p_delta: float) -> void:
	delta = p_delta
	now += p_delta
	tick_index += 1


func put(key: StringName, value: Variant, lifetime: float = 0.0) -> void:
	blackboard.put(key, value, now, lifetime)


func get_value(key: StringName, fallback: Variant = null) -> Variant:
	return blackboard.get_value(key, now, fallback)


## Whether any of [param mask] is among this tick's conditions.
func has_condition(mask: int) -> bool:
	return conditions.has(mask)


## Whether this agent has had time to act on something first seen at [param seen_at]; true with no character (nobody gave it a reaction time).
func has_reacted(seen_at: float) -> bool:
	return character == null or character.has_reacted(seen_at, now)


func describe() -> Dictionary:
	return {
		"now": "%.2f" % now,
		"tick": tick_index,
		"character": String(character.id) if character != null else "",
		"blackboard": blackboard.size() if blackboard != null else 0,
	}

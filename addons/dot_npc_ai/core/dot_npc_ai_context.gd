class_name DotNpcAiContext
extends RefCounted

## Everything one tick of a decision needs, in one object.
##
## [b]An object rather than five arguments, because every node in a tree takes it.[/b] A
## tree fifteen nodes deep passing five arguments is five arguments changed in fifteen
## places the day a sixth is needed, and behaviour trees always need a sixth.
##
## [b]It names nothing from dot-npc.[/b] [member agent] is whatever the host is driving —
## a [code]DotNpcInstance[/code], a vehicle, a 2D cell — and [member brain] is whatever
## is driving it. That is what lets the tree in this addon be lifted into anything, and
## it is why only [DotNpcAiBrain] mentions dot-npc at all.

## What is being decided for. A [code]DotNpcInstance[/code] in the ordinary case.
var agent: Object = null

## What is running the decision. A [DotNpcAiBrain] in the ordinary case.
var brain: Object = null

## This agent's memory.
var blackboard: DotNpcAiBlackboard = null

## Who this agent is: reaction time, aim, aggression. Null for a character-less NPC.
##
## [b]On the context rather than reached through the brain, because every node wants
## it.[/b] A condition asking "have I reacted yet" and an action asking "where do I
## aim" are both two levels down a tree, and a tree that has to know what kind of brain
## is running it is a tree that only runs under one.
var character: DotNpcAiCharacter = null

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


## Whether this agent has had time to act on something first seen at [param seen_at].
##
## True when there is no character, which is the right answer: an NPC nobody gave a
## reaction time to does not have one.
func has_reacted(seen_at: float) -> bool:
	return character == null or character.has_reacted(seen_at, now)


func describe() -> Dictionary:
	return {
		"now": "%.2f" % now,
		"tick": tick_index,
		"character": String(character.id) if character != null else "",
		"blackboard": blackboard.size() if blackboard != null else 0,
	}

class_name DotNpcAiConditions
extends RefCounted

## What an NPC has noticed THIS tick, as bits: the interrupts a running behaviour checks. A tree only asks the world when it reaches a node, so it misses what happened mid-action; long actions name the conditions that end them (a reload cut off by heavy damage).
## [b]Sensed once, read many times:[/b] [DotNpcAiBrain] fills this before the tree and machine run, so every guard and [DotNpcAiDecorator.Interrupt] sees the same facts.
## [b]Bits, not a dictionary,[/b] because "any of these" is one AND. Games define their own from [constant GAME_FIRST] up.

# No log channel: a bitset, set and read every think by every NPC.

## An enemy is perceived right now.
const SEE_ENEMY := 1 << 0
## The committed target changed this tick, from nothing or from somebody else.
const NEW_ENEMY := 1 << 1
## There is a target and it is not perceived this tick: dot-npc's grace is running.
const ENEMY_OCCLUDED := 1 << 2
## There was a target last tick and there is not one now.
const LOST_ENEMY := 1 << 3
## Hurt since the last think.
const LIGHT_DAMAGE := 1 << 4
## Hurt by more than [member DotNpcAiBrain.heavy_damage_fraction] of its health inside the
## damage window. The "break off" signal.
const HEAVY_DAMAGE := 1 << 5
## Below [member DotNpcAiBrain.low_health_fraction].
const LOW_HEALTH := 1 << 6
## Heard fighting: gunfire, a blow, an explosion.
const HEAR_COMBAT := 1 << 7
## Heard something to get away from — a grenade landing, a fire starting.
const HEAR_DANGER := 1 << 8
## Heard an enemy moving.
const HEAR_ENEMY := 1 << 9
## A squadmate reported an enemy this NPC did not already know about.
const SQUAD_INFORMED := 1 << 10
## Holds one of its squad's attack slots on the current target.
const HAS_ATTACK_SLOT := 1 << 11

## The first bit a game may use for its own.
const GAME_FIRST := 1 << 16

const NAMES := {
	SEE_ENEMY: "see_enemy",
	NEW_ENEMY: "new_enemy",
	ENEMY_OCCLUDED: "enemy_occluded",
	LOST_ENEMY: "lost_enemy",
	LIGHT_DAMAGE: "light_damage",
	HEAVY_DAMAGE: "heavy_damage",
	LOW_HEALTH: "low_health",
	HEAR_COMBAT: "hear_combat",
	HEAR_DANGER: "hear_danger",
	HEAR_ENEMY: "hear_enemy",
	SQUAD_INFORMED: "squad_informed",
	HAS_ATTACK_SLOT: "has_attack_slot",
}

var bits: int = 0

## Last tick's, so a guard can ask what CHANGED rather than what is.
var previous: int = 0


## Starts a think: what was is kept as [member previous], and the new set starts empty.
func begin_tick() -> void:
	previous = bits
	bits = 0


func set_flag(mask: int) -> void:
	bits |= mask


func clear_flag(mask: int) -> void:
	bits &= ~mask


## Whether any of [param mask] is set.
func has(mask: int) -> bool:
	return (bits & mask) != 0


func has_all(mask: int) -> bool:
	return (bits & mask) == mask


## Whether any of [param mask] is set now and was not last tick.
## For "react once": a HEAVY_DAMAGE guard starts a flinch on the hit, not on every tick of a damage window.
func became(mask: int) -> bool:
	return (bits & mask & ~previous) != 0


func names() -> PackedStringArray:
	var out := PackedStringArray()

	for bit in NAMES:
		if bits & int(bit):
			out.append(String(NAMES[bit]))

	return out


func _to_string() -> String:
	return "DotNpcAiConditions(%s)" % ", ".join(names())

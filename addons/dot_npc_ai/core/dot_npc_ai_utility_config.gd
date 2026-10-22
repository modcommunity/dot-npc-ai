class_name DotNpcAiUtilityConfig
extends DotConfig

## Every number of utility scoring and how personalities are handed out. Layered like any DotConfig.

## Off by default: with it off a brain keeps the tree and machine it always had and scores nothing.
@export var enabled: bool = false

@export_group("Choice")
## A held action's score is multiplied by 1 + this, so a challenger must clearly win.
@export_range(0.0, 2.0, 0.01) var hysteresis_bonus: float = 0.25
## Seconds an action is held before another may replace it (unless it scores zero).
@export_range(0.0, 60.0, 0.05) var min_hold_s: float = 0.5
## Evaluations closer together than this reuse the last choice; 0 only merges calls on the same clock reading.
@export_range(0.0, 60.0, 0.05) var cache_s: float = 0.0

@export_group("Personalities")
## How an NPC gets one: none, random (from pool by seed), or role (by role_map).
@export var assignment: String = "none"
## Personality ids random draws from; empty means every built-in and custom one.
@export var pool: PackedStringArray = PackedStringArray()
## Role id to personality id, for assignment role.
@export var role_map: Dictionary = {}
## Custom personalities: id to {actions: {action: multiplier}, shifts: {key: amount}, jitter}. Overrides a built-in of the same id.
@export var personalities: Dictionary = {}


func env_prefix() -> String:
	return "DOT_NPC_AI_UTILITY_"


func cli_prefix() -> String:
	return "--npc-ai-utility-"


func validate() -> DotResult:
	if not ["none", "random", "role"].has(assignment):
		return DotResult.fail(DotError.CODE_INVALID, "assignment must be none, random or role")
	for k in personalities:
		var r := DotNpcAiPersonality.from_dictionary(personalities[k], StringName(str(k)))
		if not r.ok:
			return r.wrap("personality '%s'" % str(k))
	return DotResult.success(null)


## Every personality by id: the built-ins with the custom ones over them.
func all_personalities() -> Dictionary:
	var out := DotNpcAiPersonality.builtin()
	for k in personalities:
		var r := DotNpcAiPersonality.from_dictionary(personalities[k], StringName(str(k)))
		if r.ok:
			out[StringName(str(k))] = r.value
	return out


## The personality for an NPC with [param npc_seed] and [param role], or null for none.
func personality_for(npc_seed: int, role: StringName = &"") -> DotNpcAiPersonality:
	var all := all_personalities()
	match assignment:
		"role":
			var wanted := StringName(str(role_map.get(String(role), role_map.get(role, ""))))
			return all.get(wanted, null)
		"random":
			var ids: Array = []
			for k in all:
				if pool.is_empty() or pool.has(String(k)):
					ids.append(k)
			if ids.is_empty():
				return null
			ids.sort()
			var x := ((npc_seed * 0x9E3779B1) ^ 0x7f4a7c15) & 0x7fffffff
			x = ((x ^ (x >> 15)) * 0x2c1b3c6d) & 0x7fffffff
			return all[ids[(x ^ (x >> 12)) % ids.size()]]
	return null

class_name DotNpcAiPersonality
extends RefCounted

## A weight set that bends utility scoring: action multipliers, curve shifts, and a seeded per-NPC wobble.

var id: StringName = &"neutral"
## Action id to multiplier on its score (missing is 1).
var action_weights: Dictionary = {}
## Consideration key to shift of every curve reading it (a brave NPC moves "flee at low health" left).
var shifts: Dictionary = {}
## Fraction (+/-) of per-NPC, per-action variation; fixed for the NPC's seed so it never flickers.
var jitter: float = 0.0


static func make(p_id: StringName, weights: Dictionary = {}, p_shifts: Dictionary = {}, p_jitter: float = 0.0) -> DotNpcAiPersonality:
	var p := DotNpcAiPersonality.new()
	p.id = p_id
	p.action_weights = weights
	p.shifts = p_shifts
	p.jitter = p_jitter
	return p


static func aggressive() -> DotNpcAiPersonality:
	return make(&"aggressive", {&"attack": 1.4, &"advance": 1.2, &"flee": 0.6, &"cover": 0.8}, {&"health": -0.2}, 0.1)


static func cautious() -> DotNpcAiPersonality:
	return make(&"cautious", {&"attack": 0.8, &"flee": 1.3, &"cover": 1.4, &"advance": 0.7}, {&"health": 0.2}, 0.1)


static func flanker() -> DotNpcAiPersonality:
	return make(&"flanker", {&"flank": 1.6, &"attack": 0.9, &"advance": 0.8, &"cover": 1.0}, {}, 0.1)


## The built-in presets by name.
static func builtin() -> Dictionary:
	return {&"aggressive": aggressive(), &"cautious": cautious(), &"flanker": flanker()}


func weight_of(action: StringName) -> float:
	return float(action_weights.get(action, 1.0))


func shift_of(key: StringName) -> float:
	return float(shifts.get(key, 0.0))


## The fixed wobble multiplier for [param action] on the NPC with [param npc_seed], in 1 +/- jitter.
func wobble(npc_seed: int, action: StringName) -> float:
	if jitter <= 0.0:
		return 1.0
	var x := ((npc_seed * 0x9E3779B1) ^ (hash(action) * 0x85EBCA6B)) & 0x7fffffff
	x = ((x ^ (x >> 15)) * 0x2c1b3c6d) & 0x7fffffff
	x = (x ^ (x >> 12)) & 0x7fffffff
	return 1.0 + (float(x % 20001) / 10000.0 - 1.0) * jitter


func to_dictionary() -> Dictionary:
	return {"id": String(id), "actions": action_weights.duplicate(), "shifts": shifts.duplicate(), "jitter": jitter}


## A personality from a dictionary; keys may be strings (JSON).
static func from_dictionary(d: Dictionary, p_id: StringName = &"") -> DotResult:
	var weights := {}
	var shifts_in := {}
	for k in d.get("actions", {}):
		weights[StringName(str(k))] = float(d["actions"][k])
	for k in d.get("shifts", {}):
		shifts_in[StringName(str(k))] = float(d["shifts"][k])
	var j := float(d.get("jitter", 0.0))
	if j < 0.0 or j > 1.0:
		return DotResult.fail(DotError.CODE_INVALID, "jitter must be within 0..1")
	var name := p_id if p_id != &"" else StringName(str(d.get("id", "custom")))
	return DotResult.success(make(name, weights, shifts_in, j))


func describe() -> String:
	return "%s (%d action weights, %d shifts, jitter %g)" % [id, action_weights.size(), shifts.size(), jitter]

class_name DotNpcAiUtility
extends RefCounted

## Scores candidate actions from response curves and picks one, holding it against flapping. Costs only when asked.

const CHANNEL := "npc.ai.utility"

## One input scored through a curve. [member weight] 1 counts fully, 0 ignores it.
class Consideration:
	extends RefCounted
	var key: StringName
	var curve: DotNpcAiCurve
	var weight: float = 1.0


## A candidate action: its considerations multiply (with the usual compensation for how many there are).
class Action:
	extends RefCounted
	var id: StringName
	var weight: float = 1.0
	var considerations: Array[Consideration] = []

	## Adds an input scored through [param curve]; returns self to chain.
	func consider(key: StringName, curve: DotNpcAiCurve, p_weight: float = 1.0) -> Action:
		var c := Consideration.new()
		c.key = key
		c.curve = curve
		c.weight = clampf(p_weight, 0.0, 1.0)
		considerations.append(c)
		return self


var config: DotNpcAiUtilityConfig = DotNpcAiUtilityConfig.new()
var personality: DotNpcAiPersonality = null
## Seeds the personality's wobble; the NPC's seed.
var npc_seed: int = 0
## `func(key: StringName) -> float`: the raw reading of a consideration. Called once per key per evaluation, and only for keys an action uses.
var inputs: Callable = Callable()

var actions: Array[Action] = []
## The action held now, or an empty name.
var current: StringName = &""
## Scores of the last evaluation, action id to score.
var last_scores: Dictionary = {}
## Full evaluations, cached answers, and considerations scored: the cost, for a tier test or a perf gate.
var evaluations: int = 0
var cache_hits: int = 0
var considerations_scored: int = 0

var _since: float = -INF
var _evaluated_at: float = -INF
var _readings: Dictionary = {}


## Adds a candidate action and returns it to hang considerations on. Order is the final tie-break.
func add_action(id: StringName, weight: float = 1.0) -> Action:
	var a := Action.new()
	a.id = id
	a.weight = weight
	actions.append(a)
	return a


## The action to run now. Re-scores only when [param now] is past the cache window; otherwise answers the held one.
func choose(now: float, p_inputs: Callable = Callable()) -> StringName:
	if now - _evaluated_at <= config.cache_s and _evaluated_at > -INF:
		cache_hits += 1
		return current
	_evaluated_at = now
	evaluations += 1
	_readings.clear()
	var reader := p_inputs if p_inputs.is_valid() else inputs
	last_scores.clear()

	var best: StringName = &""
	var best_score := 0.0
	var held_score := 0.0
	for a in actions:
		var s := _score(a, reader)
		last_scores[a.id] = s
		if a.id == current:
			held_score = s
			s *= 1.0 + config.hysteresis_bonus
		# Strictly greater: a tie keeps the earlier action, and a held one wins its ties by the bonus.
		if s > best_score or (s == best_score and a.id == current and s > 0.0):
			best = a.id
			best_score = s

	if best != current and current != &"" and held_score > 0.0 and now - _since < config.min_hold_s:
		return current
	if best != current:
		DotLog.debug(CHANNEL, "action changed", {"from": String(current), "to": String(best)})
		current = best
		_since = now
	return current


func _score(a: Action, reader: Callable) -> float:
	if a.considerations.is_empty():
		return a.weight * _multiplier(a.id)
	var n := a.considerations.size()
	var product := 1.0
	for c in a.considerations:
		var raw: float
		if _readings.has(c.key):
			raw = _readings[c.key]
		else:
			raw = float(reader.call(c.key)) if reader.is_valid() else 0.0
			_readings[c.key] = raw
		var shift := personality.shift_of(c.key) if personality != null else 0.0
		var v := c.curve.eval(raw, shift)
		considerations_scored += 1
		# A weight below 1 pulls the term toward 1 so it matters less.
		product *= lerpf(1.0, v, c.weight)
	# Compensation: more considerations multiply the score down, so give back (1 - 1/n) of the loss.
	var mod := 1.0 - 1.0 / float(n)
	product += (1.0 - product) * mod * product
	return product * a.weight * _multiplier(a.id)


func _multiplier(action: StringName) -> float:
	if personality == null:
		return 1.0
	return personality.weight_of(action) * personality.wobble(npc_seed, action)


## Forgets the held action and the cache, so the next choose starts clean.
func reset() -> void:
	current = &""
	_since = -INF
	_evaluated_at = -INF
	last_scores.clear()


func describe() -> Dictionary:
	return {
		"current": String(current),
		"personality": String(personality.id) if personality != null else "-",
		"actions": actions.size(),
		"evaluations": evaluations,
		"cache_hits": cache_hits,
		"considerations_scored": considerations_scored,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("utility: %s (personality %s)" % [current, personality.id if personality != null else "-"])
	for k in last_scores:
		out.append("  %s %.3f" % [k, last_scores[k]])
	return out

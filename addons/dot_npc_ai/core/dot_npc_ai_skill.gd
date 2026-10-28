class_name DotNpcAiSkill
extends RefCounted

## How good a server's NPCs are, set by the operator, on top of who each one is.
##
## [b]An adjustment, not a difficulty setting, and the difference is the design.[/b] A
## [DotNpcAiCharacter] is per kind and per NPC — a brute is slow to notice and impossible
## to shake, a stalker the other way round — and a global "difficulty 3" that REPLACED
## those numbers would make every monster the same monster at a different speed. This
## moves every character toward [method DotNpcAiCharacter.easy] or
## [method DotNpcAiCharacter.nightmare] by a fraction, so a brute on a hard server is
## still slower to notice than a stalker on the same server.
##
## [b]Ability moves; personality does not.[/b] Reaction, alertness, memory, aim, turning and tactics
## are how GOOD an NPC is. Aggression, self-preservation, vengefulness and the movement
## tendencies are who it IS, and a coward that turned brave on a hard server would be a
## different game rather than a harder one.
##
## [b]And only ever in the direction asked for.[/b] A stalker authored with a faster
## reaction than the nightmare preset is not made slower by turning skill UP, which a plain
## lerp toward the preset would do — a bug that reads as "hard mode made them worse" and
## only for the one kind that was already best.
##
## Three numbers, each a server cvar through [method bind_cvars]:
##
## [codeblock]
## npc_skill            -1 .. 1, or easy/normal/hard/nightmare. 0 is as authored.
## npc_reaction_scale   multiplies every reaction time. 0.5 reacts twice as fast.
## npc_reaction_min     the floor no reaction time goes under, in seconds.
## [/codeblock]
##
## One object per server, shared by every brain; [member revision] is how a brain learns it
## changed without a signal per NPC. [method attach] puts it on a director as node metadata
## rather than in [DotRegistry], because the registry is per process and two servers in one
## process — which this family runs in its suites — must not share a difficulty.

# No log channel: a few numbers and their parsing. The cvar that changed them logs.

## Emitted after any change.
signal changed

const CVAR_SKILL := "npc_skill"
const CVAR_REACTION_SCALE := "npc_reaction_scale"
const CVAR_REACTION_MIN := "npc_reaction_min"
const CVAR_HUMANISE := "npc_humanise"

## Where [method attach] keeps this on a director.
const META := &"dot_npc_ai_skill"

## The names [member skill] accepts as well as a number.
##
## Hard is half-way rather than all the way, because nightmare is the preset at the end of
## the scale and "hard" meaning "nightmare" leaves an operator nowhere to go.
const LEVELS := {
	"easy": -1.0,
	"normal": 0.0,
	"hard": 0.5,
	"nightmare": 1.0,
}

const REACTION_SCALE_MIN := 0.1
const REACTION_SCALE_MAX := 5.0
const REACTION_FLOOR_MAX := 3.0

## -1 toward easy, 0 as authored, 1 toward nightmare.
var skill: float = 0.0

## Multiplies every reaction time, after [member skill].
##
## Separate from skill on purpose: "smart" and "quick" are two different complaints. An
## operator whose players say the NPCs are unfair because they turn on you instantly wants
## this, and does not want them to also start missing.
var reaction_scale: float = 1.0

## No reaction time goes below this, in seconds.
##
## [b]0.05 by default and not zero, for the reason [method DotNpcAiCharacter.nightmare]
## keeps one above zero:[/b] an NPC that acts on the tick it sees you is not harder, it is
## inhuman, and [member reaction_scale] at its minimum would otherwise get there. A
## character authored with NO reaction time — a scripted NPC — is left alone; see
## [method apply].
var reaction_min: float = 0.05

## Scales every character's reaction_jitter, overshoot, track_lag, strafe_jitter, glance, hesitate and hurt_delay; 0 turns the human unevenness off.
var humanise: float = 1.0

## Bumped on every change. A brain compares it rather than connecting a signal per NPC.
var revision: int = 0


# --- The adjustment -----------------------------------------------------------

## [param base] as this server would have it. A new character; [param base] is not touched.
##
## The seed, id and personality are carried over unchanged, so an NPC's aim error is the
## same miss it would have been at a different skill, scaled — not a different one.
func apply(base: DotNpcAiCharacter) -> DotNpcAiCharacter:
	if base == null:
		return null

	var out: DotNpcAiCharacter = base.duplicate(true)
	var t := clampf(absf(skill), 0.0, 1.0)

	if t > 0.0:
		var improving := skill > 0.0
		var toward := DotNpcAiCharacter.nightmare() if improving else DotNpcAiCharacter.easy()

		out.reaction_time = _shift(base.reaction_time, toward.reaction_time, t, improving, false)
		out.alertness = _shift(base.alertness, toward.alertness, t, improving, true)
		out.memory_time = _shift(base.memory_time, toward.memory_time, t, improving, true)
		out.aim_accuracy = _shift(base.aim_accuracy, toward.aim_accuracy, t, improving, true)
		out.aim_skill = _shift(base.aim_skill, toward.aim_skill, t, improving, true)
		out.view_turn_deg = _shift(base.view_turn_deg, toward.view_turn_deg, t, improving, true)
		out.view_factor = _shift(base.view_factor, toward.view_factor, t, improving, true)
		out.fire_throttle = _shift(base.fire_throttle, toward.fire_throttle, t, improving, true)
		out.tactics = _shift(base.tactics, toward.tactics, t, improving, true)

	# A character authored with no reaction time is a scripted NPC — a cutscene, a turret
	# that is meant to be instant — and the floor would turn it into one that hesitates.
	if base.reaction_time > 0.0:
		out.reaction_time = maxf(out.reaction_time * reaction_scale, reaction_min)

	out.reaction_jitter = base.reaction_jitter * humanise
	out.overshoot = clampf(base.overshoot * humanise, 0.0, 1.0)
	out.track_lag = clampf(base.track_lag * humanise, 0.0, 0.5)
	out.strafe_jitter = clampf(base.strafe_jitter * humanise, 0.0, 1.0)
	out.glance = clampf(base.glance * humanise, 0.0, 1.0)
	out.hesitate = clampf(base.hesitate * humanise, 0.0, 2.0)
	out.hurt_delay = clampf(base.hurt_delay * humanise, 0.0, 1.0)
	return out


## [param value] moved toward [param target] by [param t], but only if that is the way asked.
static func _shift(
	value: float, target: float, t: float, improving: bool, higher_is_better: bool
) -> float:
	var target_is_better := target > value if higher_is_better else target < value

	if target_is_better != improving:
		return value

	return lerpf(value, target, t)


## Whether this changes nothing, so a caller can say "as authored".
func is_neutral() -> bool:
	return is_zero_approx(skill) and is_equal_approx(reaction_scale, 1.0) and is_equal_approx(humanise, 1.0)


# --- Setting it ---------------------------------------------------------------

func set_skill(value: float) -> void:
	_assign(clampf(value, -1.0, 1.0), reaction_scale, reaction_min)


func set_reaction_scale(value: float) -> void:
	_assign(skill, clampf(value, REACTION_SCALE_MIN, REACTION_SCALE_MAX), reaction_min)


func set_reaction_min(value: float) -> void:
	_assign(skill, reaction_scale, clampf(value, 0.0, REACTION_FLOOR_MAX))


func set_humanise(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if v != humanise:
		humanise = v
		revision += 1
		changed.emit()


func _assign(p_skill: float, p_scale: float, p_min: float) -> void:
	if p_skill == skill and p_scale == reaction_scale and p_min == reaction_min:
		return

	skill = p_skill
	reaction_scale = p_scale
	reaction_min = p_min
	revision += 1
	changed.emit()


## Parses what an operator typed into the number [member skill] takes.
##
## A name from [constant LEVELS] or a number. Numbers outside -1..1 are clamped rather than
## refused, which is what every other numeric cvar in the family does: `npc_skill 5` should
## give the maximum, not an error somebody has to look the range up to fix.
static func parse_skill(text: String) -> DotResult:
	var trimmed := text.strip_edges().to_lower()

	if LEVELS.has(trimmed):
		return DotResult.success(float(LEVELS[trimmed]))

	if trimmed.is_valid_float():
		return DotResult.success(clampf(trimmed.to_float(), -1.0, 1.0))

	return DotResult.fail(
		DotError.CODE_INVALID,
		"npc_skill takes easy, normal, hard, nightmare or a number from -1 to 1.",
		text
	)


## Applies one cvar's text. Returns whether the name was one of these.
func set_cvar(cvar_name: String, text: String) -> bool:
	match cvar_name:
		CVAR_SKILL:
			var parsed := parse_skill(text)
			if parsed.ok:
				set_skill(float(parsed.value))
			return true
		CVAR_REACTION_SCALE:
			if text.strip_edges().is_valid_float():
				set_reaction_scale(text.to_float())
			return true
		CVAR_REACTION_MIN:
			if text.strip_edges().is_valid_float():
				set_reaction_min(text.to_float())
			return true

		CVAR_HUMANISE:
			if text.strip_edges().is_valid_float():
				set_humanise(text.to_float())
			return true

	return false


## The three cvars, as data, for a host that registers them its own way.
func cvar_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{
			"name": CVAR_SKILL,
			"value": _number(skill),
			"description": "How good NPCs are, on top of each kind: easy, normal, hard, nightmare, or -1..1. 0 is as authored.",
		},
		{
			"name": CVAR_REACTION_SCALE,
			"value": _number(reaction_scale),
			"description": "Multiplies every NPC reaction time. 0.5 reacts twice as fast, 2 half as fast.",
			"min": REACTION_SCALE_MIN,
			"max": REACTION_SCALE_MAX,
		},
		{
			"name": CVAR_REACTION_MIN,
			"value": _number(reaction_min),
			"description": "Seconds no NPC reaction time goes below. 0 allows instant reactions.",
			"min": 0.0,
			"max": REACTION_FLOOR_MAX,
		},
		{
			"name": CVAR_HUMANISE,
			"value": _number(humanise),
			"description": "How uneven NPC reaction times are, 0 to 1. 0 is the plain authored reaction every time.",
			"min": 0.0,
			"max": 1.0,
		},
	]
	return out


## Registers the three cvars through [param add] and keeps this in step with them.
##
## [param add] is a server module's `add_cvar` — so the module unregisters them when it
## unloads, which a console's own `cvar` would not — or anything with its signature:
## `(name, default, description, flags) -> cvar`. Returns the cvars it made.
##
## [b]Duck-typed, because dot-server is not a dependency of this addon[/b] and a game with
## NPCs and no dedicated server must still be able to install it. What a cvar must have is
## a `changed(old, new)` signal and a `get_string()`; a range and a validator are used when
## it offers them.
##
## [b]The current value is read back after registering.[/b] A cvar set before this ran —
## from argv or a config file executed early — already holds the operator's value, and
## leaving this object at its default would be a server whose `npc_skill` says hard and
## whose NPCs are normal.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []

	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(
			cvar_name, String(spec["value"]), String(spec["description"]), flags
		)

		if not (made_cvar is Object) or made_cvar == null:
			continue

		var cv := made_cvar as Object

		if spec.has("min") and cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))

		if cvar_name == CVAR_SKILL and cv.has_method(&"with_validator"):
			# Refused at the console rather than ignored here: an operator who typed
			# `npc_skill hrad` should be told, not left with NPCs that quietly did not change.
			cv.call(&"with_validator", func(text: String) -> DotResult: return parse_skill(text))

		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))

		if cv.has_method(&"get_string"):
			set_cvar(cvar_name, String(cv.call(&"get_string")))

		made.append(cv)

	return made


func _on_cvar_changed(_old: String, new_value: String, cvar_name: String) -> void:
	set_cvar(cvar_name, new_value)


static func _number(value: float) -> String:
	# "1" rather than "1.0" for the defaults, which is what an operator would type and
	# what `cvarlist` then shows as unchanged.
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)


# --- Where brains find it -----------------------------------------------------

## Puts this on [param director], where every [DotNpcAiBrain] it spawns finds it.
##
## Before the first spawn, ideally; a brain that missed it looks again each tick until it
## finds one, so a late attach costs a tick rather than a whole NPC's life.
func attach(director: Node) -> void:
	if director != null:
		director.set_meta(META, self)


## The skill attached to [param director], or null.
static func of(director: Object) -> DotNpcAiSkill:
	if director == null or not director.has_meta(META):
		return null

	return director.get_meta(META) as DotNpcAiSkill


func describe() -> Dictionary:
	return {
		"skill": "%.2f" % skill,
		"reaction_scale": "%.2f" % reaction_scale,
		"reaction_min": "%.2fs" % reaction_min,
		"revision": revision,
	}


func describe_lines() -> PackedStringArray:
	var level := ""

	for key in LEVELS:
		if is_equal_approx(float(LEVELS[key]), skill):
			level = " (%s)" % key

	return PackedStringArray([
		"npc skill %.2f%s" % [skill, level],
		"reaction x%.2f, never under %.2fs" % [reaction_scale, reaction_min],
	])

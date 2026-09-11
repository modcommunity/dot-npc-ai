@tool
class_name DotNpcAiCharacter
extends Resource

## Who this NPC is, as numbers: how fast it notices, how well it shoots, how much it
## wants to fight.
##
## [b]This is the part that makes a bot feel like a person, and it is not the decision
## engine.[/b] A behaviour tree decides [i]what[/i] to do; two NPCs running the same
## tree with the same tree are the same NPC. The late-1990s arena shooters' bots —
## still the ones people compare against, twenty-five years on — got their character
## from a table of characteristics per bot: reaction time, aim accuracy, aim skill,
## aggression, self preservation, vengefulness, a tendency to camp. This is that table,
## read out of the open-sourced original and cut down to the parts that are not
## specific to that engine.
##
## What was left out and why:
##
## [codeblock]
## chat characteristics    a game's, and dot-chat's if it wants them
## weapon-specific aim     dot-combat owns weapons; this has no idea what one is
## item weights            goal selection is the tree's, not a table's
## grapple, weapon jumping that engine's movement, not a movement model this family has
## [/codeblock]
##
## [b]Three of these do work rather than describe intent[/b], and they are the reason
## this is a class instead of a dictionary of numbers a game reads:
## [method has_reacted] gates acting on what was just seen, [method aim_point] turns a
## target into somewhere to shoot, and [method turn_view] stops a bot snapping its head
## round in one tick. Everything else is a weight a tree consults.
##
## [codeblock]
## if not character.has_reacted(npc.target_seen_at, ctx.now):
##     return Status.RUNNING            # seen, not yet acted on
##
## var at := character.aim_point(muzzle, enemy.position, enemy.velocity, 900.0, shot)
## [/codeblock]

const CHANNEL := "npc.ai"

## The widest an inaccurate shot may miss by, in degrees, at
## [member aim_accuracy] 0.
##
## Twelve degrees is about a body width at fifteen metres. Wider and the worst bot
## cannot hit anything at all, which reads as broken rather than as bad.
const MAX_AIM_ERROR_DEG := 12.0

## Keeps the mixer in the positive half of a signed 64-bit int. See [method unit].
const MASK := 0x7FFFFFFFFFFFFFFF

@export_group("Identity")

@export var id: StringName = &""

@export var display_name: String = ""

## Fixed part of this character's deterministic randomness.
##
## [b]Aim error has to be reproducible.[/b] A server rewinding to check a shot, a
## replay, and a client predicting nothing at all must agree about where an NPC was
## pointing — and a bot whose error came from [method randf] disagrees with itself
## between two runs of the same demo. Everything random here is a hash of this, a
## caller-supplied number, and nothing else.
@export var seed_value: int = 1

@export_group("Perception")

## Seconds between something becoming visible and this NPC acting on it.
##
## [b]The single most important number in the file.[/b] A bot that reacts on the tick
## it sees you is not hard, it is inhuman — and it is the difference every player can
## feel and nobody can name. A person is about a quarter of a second; the original's
## easiest bots are set near a second and a half.
@export_range(0.0, 5.0, 0.01) var reaction_time: float = 0.35

## Multiplies the definition's sight range. 1.0 is "as far as the definition says".
##
## The original table calls it alertness and uses it for view distance. Scaling rather than
## replacing, because how far a kind of NPC can see is a property of the kind and how
## attentive this one is, is a property of the character.
@export_range(0.1, 2.0, 0.01) var alertness: float = 1.0

## Seconds a target stays "remembered" after it is lost from sight.
##
## Not the same as dot-npc's commitment grace, which decides whether to keep chasing.
## This decides whether the NPC still believes it knows where the target is, which is
## what a prediction shot and a search are made of.
@export_range(0.0, 60.0, 0.1) var memory_time: float = 5.0

@export_group("Aim")

## 0 misses by up to [constant MAX_AIM_ERROR_DEG]; 1 is exact.
@export_range(0.0, 1.0, 0.01) var aim_accuracy: float = 0.7

## How much of a moving target's motion is led.
##
## 0 aims where the target is, which never hits anything crossing. 1 aims where it
## will be. Between the two is the interesting range and it is where every bot worth
## playing against sits: the original's own thresholds are linear leading above 0.4 and
## exact leading above 0.8.
@export_range(0.0, 1.0, 0.01) var aim_skill: float = 0.5

## Fastest the view may turn, in degrees per second.
##
## [b]A bot with no limit here snaps its aim in one tick and is unplayable against.[/b]
## The original's equivalent is a maximum view change per frame; degrees per second is
## the same idea at a tick rate that is not fixed.
@export_range(30.0, 3600.0, 10.0) var view_turn_deg: float = 360.0

## Fraction of the remaining aim error corrected per second, before the turn limit.
##
## Below 1 the aim eases in rather than tracking rigidly, which is what makes a bot
## look like it is following rather than locked on.
@export_range(0.05, 1.0, 0.01) var view_factor: float = 0.6

@export_group("Fighting")

## How readily this closes with an enemy rather than holding position.
@export_range(0.0, 1.0, 0.01) var aggression: float = 0.5

## How readily it breaks off, takes cover and retreats when hurt.
@export_range(0.0, 1.0, 0.01) var self_preservation: float = 0.5

## How likely it is to go after whoever last hurt it, rather than the nearest thing.
@export_range(0.0, 1.0, 0.01) var vengefulness: float = 0.5

## Tendency to hold a position and wait rather than to go looking.
@export_range(0.0, 1.0, 0.01) var camper: float = 0.2

## How much of the time it is willing to shoot at all.
##
## 1 fires whenever it can; lower leaves gaps. It is what stops a line of NPCs sounding
## like one continuous noise, and it is a weight rather than a rate because the tree
## decides when a shot is possible.
@export_range(0.0, 1.0, 0.01) var fire_throttle: float = 0.8

@export_group("Movement")

@export_range(0.0, 1.0, 0.01) var croucher: float = 0.1
@export_range(0.0, 1.0, 0.01) var jumper: float = 0.2

## Tendency to walk rather than run when nothing is happening.
@export_range(0.0, 1.0, 0.01) var walker: float = 0.3

@export var meta: Dictionary = {}


# --- Presets ------------------------------------------------------------------

## The four a game actually ships. Named after what a player would call them.
static func easy() -> DotNpcAiCharacter:
	var out := DotNpcAiCharacter.new()
	out.id = &"easy"
	out.display_name = "Easy"
	out.reaction_time = 1.1
	out.alertness = 0.7
	out.aim_accuracy = 0.35
	out.aim_skill = 0.15
	out.view_turn_deg = 180.0
	out.view_factor = 0.35
	out.aggression = 0.3
	out.self_preservation = 0.7
	out.fire_throttle = 0.55
	return out


static func normal() -> DotNpcAiCharacter:
	var out := DotNpcAiCharacter.new()
	out.id = &"normal"
	out.display_name = "Normal"
	return out


static func hard() -> DotNpcAiCharacter:
	var out := DotNpcAiCharacter.new()
	out.id = &"hard"
	out.display_name = "Hard"
	out.reaction_time = 0.18
	out.alertness = 1.2
	out.aim_accuracy = 0.85
	out.aim_skill = 0.75
	out.view_turn_deg = 720.0
	out.view_factor = 0.8
	out.aggression = 0.7
	out.self_preservation = 0.4
	out.fire_throttle = 0.9
	return out


## As good as this gets, and deliberately not perfect.
##
## [b]Reaction time stays above zero and accuracy below one on purpose.[/b] A bot that
## reacts instantly and never misses is not a harder opponent, it is a different game —
## and every shooter that shipped one patched it out.
static func nightmare() -> DotNpcAiCharacter:
	var out := DotNpcAiCharacter.new()
	out.id = &"nightmare"
	out.display_name = "Nightmare"
	out.reaction_time = 0.08
	out.alertness = 1.5
	out.aim_accuracy = 0.95
	out.aim_skill = 0.95
	out.view_turn_deg = 1080.0
	out.view_factor = 0.95
	out.aggression = 0.9
	out.self_preservation = 0.25
	out.vengefulness = 0.8
	out.fire_throttle = 1.0
	return out


# --- Reacting -----------------------------------------------------------------

## Whether enough time has passed since [param seen_at] for this NPC to act.
##
## [param seen_at] is when the target was first perceived — dot-npc's
## [code]DotNpcInstance.engaged_at[/code] is exactly it. A negative or zero
## [member reaction_time] answers true immediately, which is what a scripted NPC in a
## cutscene wants.
func has_reacted(seen_at: float, now: float) -> bool:
	if reaction_time <= 0.0:
		return true
	return now - seen_at >= reaction_time


## How long is left before it may act. 0 once it has.
func reaction_remaining(seen_at: float, now: float) -> float:
	return maxf(0.0, reaction_time - (now - seen_at))


## Whether a target last seen at [param seen_at] is still believed to be findable.
func remembers(seen_at: float, now: float) -> bool:
	return now - seen_at <= memory_time


## The sight range this character actually has, from the definition's.
func sight_range(base: float) -> float:
	return base * alertness


# --- Aiming -------------------------------------------------------------------

## The widest this character misses by, in radians.
func aim_error() -> float:
	return deg_to_rad(MAX_AIM_ERROR_DEG * (1.0 - aim_accuracy))


## Where to shoot at a target, leading and error included.
##
## [param travel_speed] is how fast whatever is being fired travels; pass 0 for a
## hitscan weapon, which leads by nothing because it arrives instantly.
##
## [param shot_seed] is what makes the error reproducible: the same shot always misses
## the same way. A caller passes a shot counter, a tick number, anything monotonic —
## and passing a constant makes every shot miss identically, which is a bug that looks
## like a scope being off.
func aim_point(
	from: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	travel_speed: float,
	shot_seed: int
) -> Vector3:
	var aim := target_position

	if travel_speed > 0.0 and aim_skill > 0.0:
		var distance := from.distance_to(target_position)
		var flight := distance / travel_speed
		# Partial leading rather than a threshold. The original switches leading on above a
		# skill of 0.4 and exact leading above 0.8; a fraction is the same curve
		# without two cliffs in it, and a bot at 0.5 that leads half as far as it
		# should misses behind a runner, which is what a mediocre player does.
		aim += target_velocity * flight * aim_skill

	var spread := aim_error()

	if spread <= 0.0:
		return aim

	var direction := aim - from
	var distance_to_aim := direction.length()

	if distance_to_aim <= 0.001:
		return aim

	direction /= distance_to_aim

	# A point on a disc perpendicular to the aim, at the distance of the target, whose
	# radius is the tangent of the error angle. Doing it in world space rather than as
	# an angle keeps the miss proportional to range, which is how a real one behaves.
	var basis_up := Vector3.UP
	if absf(direction.dot(basis_up)) > 0.99:
		# Aiming straight up or down. Any perpendicular will do and UP is not one.
		basis_up = Vector3.RIGHT

	var right := direction.cross(basis_up).normalized()
	var up := right.cross(direction).normalized()

	var angle := unit(shot_seed) * TAU
	# sqrt of a uniform sample, or every miss clusters in the middle of the cone: the
	# area of a disc grows with the square of the radius, so a uniform radius is not a
	# uniform point.
	var radius := sqrt(unit(shot_seed ^ 0x5bf03635)) * tan(spread) * distance_to_aim

	return aim + (right * cos(angle) + up * sin(angle)) * radius


## Turns [param current] toward [param wanted], no faster than this character can.
##
## Both are directions. Returns the new direction, which is [param wanted] once the
## remaining angle is inside one tick's worth of turning.
func turn_view(current: Vector3, wanted: Vector3, delta: float) -> Vector3:
	if current.length_squared() <= 0.0001:
		return wanted
	if wanted.length_squared() <= 0.0001:
		return current

	var from := current.normalized()
	var to := wanted.normalized()
	var angle := from.angle_to(to)

	if angle <= 0.0001:
		return to

	# Eased, then clamped. The ease is what makes tracking look like following; the
	# clamp is what stops a bot snapping its head round in one tick, and a bot with
	# only the ease still snaps when the error is large.
	var wanted_step := angle * clampf(view_factor * delta * 8.0, 0.0, 1.0)
	var limit := deg_to_rad(view_turn_deg) * delta
	var step := minf(wanted_step, limit)

	if step >= angle:
		return to

	var axis := from.cross(to)

	if axis.length_squared() <= 0.000001:
		# Exactly opposite. Any axis perpendicular to `from` turns it the right amount
		# and none of them is more correct than another; without this the cross is zero
		# and the rotation is a no-op, so a bot with something directly behind it never
		# turns round.
		axis = from.cross(Vector3.UP)
		if axis.length_squared() <= 0.000001:
			axis = from.cross(Vector3.RIGHT)

	return from.rotated(axis.normalized(), step)


## Whether this character takes a shot it is otherwise able to take.
func should_fire(shot_seed: int) -> bool:
	if fire_throttle >= 1.0:
		return true
	return unit(shot_seed ^ 0x27d4eb2f) < fire_throttle


# --- Deterministic randomness -------------------------------------------------

## A reproducible number in [0, 1) from this character's seed and [param salt].
##
## [b]The whole range, and the suite checks it.[/b] dot-combat shipped a mixer whose
## output was shifted and masked down to 23 bits of a 24-bit field, so it never
## returned a value above 0.5 — every shotgun pattern was a half-moon on one side of
## the aim and nothing about a maximum-magnitude check could see it. A quadrant check
## can.
func unit(salt: int) -> float:
	# Kept positive at every step. GDScript ints are signed and `>>` on a negative one
	# sign-extends, so a mixer that is allowed to go negative shifts ones in from the
	# top and stops being uniform in a way no magnitude check can see.
	var x := ((seed_value * 0x9E3779B1) ^ (salt * 0x85EBCA6B)) & MASK
	x = (x ^ (x >> 33)) & MASK
	x = (x * 0xC2B2AE3D) & MASK
	x = (x ^ (x >> 29)) & MASK
	x = (x * 0x27D4EB2F) & MASK
	x = (x ^ (x >> 31)) & MASK

	# 53 bits, the mantissa of a double, taken from the top where the mixing is best.
	# Masking the bottom bits of a multiplicative mixer is how you get a value that is
	# reproducible and not uniform.
	var bits := (x >> 10) & 0x1FFFFFFFFFFFFF

	return float(bits) / float(0x20000000000000)


## A symmetric reproducible number in [-1, 1).
func signed_unit(salt: int) -> float:
	return unit(salt) * 2.0 - 1.0


# --- Housekeeping -------------------------------------------------------------

func validate() -> DotResult:
	if reaction_time < 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID, "Reaction time cannot be negative.", String(id)
		)

	if alertness <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Alertness of zero means an NPC that can never see anything.",
			String(id)
		)

	if view_turn_deg <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A view that cannot turn is an NPC that can never face anything.",
			String(id)
		)

	return DotResult.success(self)


func to_dictionary() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"seed": seed_value,
		"reaction_time": reaction_time,
		"alertness": alertness,
		"memory_time": memory_time,
		"aim_accuracy": aim_accuracy,
		"aim_skill": aim_skill,
		"view_turn_deg": view_turn_deg,
		"view_factor": view_factor,
		"aggression": aggression,
		"self_preservation": self_preservation,
		"vengefulness": vengefulness,
		"camper": camper,
		"fire_throttle": fire_throttle,
		"croucher": croucher,
		"jumper": jumper,
		"walker": walker,
		"meta": meta.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> DotResult:
	var out := DotNpcAiCharacter.new()

	out.id = StringName(str(data.get("id", "")))
	out.display_name = str(data.get("name", ""))
	out.seed_value = int(data.get("seed", 1))
	out.reaction_time = maxf(float(data.get("reaction_time", 0.35)), 0.0)
	out.alertness = maxf(float(data.get("alertness", 1.0)), 0.01)
	out.memory_time = maxf(float(data.get("memory_time", 5.0)), 0.0)
	out.aim_accuracy = clampf(float(data.get("aim_accuracy", 0.7)), 0.0, 1.0)
	out.aim_skill = clampf(float(data.get("aim_skill", 0.5)), 0.0, 1.0)
	out.view_turn_deg = maxf(float(data.get("view_turn_deg", 360.0)), 1.0)
	out.view_factor = clampf(float(data.get("view_factor", 0.6)), 0.05, 1.0)
	out.aggression = clampf(float(data.get("aggression", 0.5)), 0.0, 1.0)
	out.self_preservation = clampf(float(data.get("self_preservation", 0.5)), 0.0, 1.0)
	out.vengefulness = clampf(float(data.get("vengefulness", 0.5)), 0.0, 1.0)
	out.camper = clampf(float(data.get("camper", 0.2)), 0.0, 1.0)
	out.fire_throttle = clampf(float(data.get("fire_throttle", 0.8)), 0.0, 1.0)
	out.croucher = clampf(float(data.get("croucher", 0.1)), 0.0, 1.0)
	out.jumper = clampf(float(data.get("jumper", 0.2)), 0.0, 1.0)
	out.walker = clampf(float(data.get("walker", 0.3)), 0.0, 1.0)

	var meta_value: Variant = data.get("meta", {})
	out.meta = (
		(meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	)

	return out.validate()


## A copy with its own seed, so twenty NPCs of one preset do not miss identically.
##
## [b]Worth calling and easy to forget.[/b] A preset is one resource; handing it to
## twenty NPCs gives twenty NPCs one seed, and every one of them takes the same shot
## with the same error at the same moment. It reads as a firing squad.
func with_seed(new_seed: int) -> DotNpcAiCharacter:
	var out: DotNpcAiCharacter = duplicate(true)
	out.seed_value = new_seed
	return out


func describe() -> Dictionary:
	return {
		"id": String(id),
		"reaction": "%.2fs" % reaction_time,
		"accuracy": "%.2f" % aim_accuracy,
		"skill": "%.2f" % aim_skill,
		"aggression": "%.2f" % aggression,
	}


func _to_string() -> String:
	return "DotNpcAiCharacter(%s)" % String(id)

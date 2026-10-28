@tool
class_name DotNpcAiCharacter
extends Resource

## Who this NPC is, as numbers: reaction time, aim, aggression and the rest of a per-bot characteristics table, which is what makes two NPCs on one tree different people. Left out: chat, weapon-specific aim, item weights and grapple moves (owned by other addons or specific to one engine).
## Three do work rather than describe intent: [method has_reacted] gates acting on what was just seen, [method aim_point] turns a target into somewhere to shoot, [method turn_view] stops a head snapping round in one tick. The rest are weights a tree consults.
## `if not character.has_reacted(npc.target_seen_at, ctx.now): return Status.RUNNING`

# No log channel: a Resource of numbers and the pure functions over them, asked every
# think by every NPC. validate()/from_dictionary() return a DotResult for the loader.

## The widest an inaccurate shot may miss by, in degrees, at [member aim_accuracy] 0.
## Twelve degrees is a body width at fifteen metres; wider and the worst bot hits nothing, which reads as broken, not bad.
const MAX_AIM_ERROR_DEG := 12.0

## Keeps the mixer in the positive half of a signed 64-bit int. See [method unit].
const MASK := 0x7FFFFFFFFFFFFFFF

@export_group("Identity")

@export var id: StringName = &""

@export var display_name: String = ""

## Fixed part of this character's deterministic randomness.
## Aim error must be reproducible (a rewinding server, a replay), which [method randf] cannot be: everything random here is a hash of this and a caller-supplied number.
@export var seed_value: int = 1

@export_group("Perception")

## Seconds between something becoming visible and this NPC acting on it.
## The most important number here: reacting on the tick it sees you is inhuman, not hard. A person is about 0.25 s.
@export_range(0.0, 5.0, 0.01) var reaction_time: float = 0.35

## How unevenly the reaction varies between sightings; 0 is the plain [member reaction_time].
@export_range(0.0, 2.0, 0.01) var reaction_jitter: float = 0.3

## Multiplies the definition's sight range. 1.0 is "as far as the definition says".
## A scale, not a replacement: how far a kind can see belongs to the kind, how attentive this one is belongs to the character.
@export_range(0.1, 2.0, 0.01) var alertness: float = 1.0

## Seconds a target stays "remembered" after it is lost from sight.
## Not dot-npc's commitment grace (keep chasing?): this decides whether the NPC still believes it knows where the target is, which prediction shots and searches are made of.
@export_range(0.0, 60.0, 0.1) var memory_time: float = 5.0

@export_group("Aim")

## 0 misses by up to [constant MAX_AIM_ERROR_DEG]; 1 is exact.
@export_range(0.0, 1.0, 0.01) var aim_accuracy: float = 0.7

## How much of a moving target's motion is led.
## 0 aims where the target is and never hits a crosser; 1 aims where it will be. The interesting range is between.
@export_range(0.0, 1.0, 0.01) var aim_skill: float = 0.5

## Fastest the view may turn, in degrees per second.
## With no limit a bot snaps its aim in one tick and is unplayable against; per second, because the tick rate is not fixed.
@export_range(30.0, 3600.0, 10.0) var view_turn_deg: float = 360.0

## Fraction of the remaining aim error corrected per second, before the turn limit.
## Below 1 the aim eases in, so a bot looks like it is following rather than locked on.
@export_range(0.05, 1.0, 0.01) var view_factor: float = 0.6

## How far a big turn onto a target swings past it before coming back; 0 is none.
@export_range(0.0, 1.0, 0.01) var overshoot: float = 0.4

## Seconds before the aim notices a target changed velocity (it leads with the old one meanwhile).
@export_range(0.0, 0.5, 0.01) var track_lag: float = 0.05

## How irregular strafing is: uneven lengths, pauses, easing at a reversal; 0 is the plain metronome.
@export_range(0.0, 1.0, 0.01) var strafe_jitter: float = 0.5

## How often an idle NPC holding a place turns its head aside and holds the look; 0 never.
@export_range(0.0, 1.0, 0.01) var glance: float = 0.5

## Seconds it may stand still on first sighting somebody; never longer than the reaction itself.
@export_range(0.0, 2.0, 0.01) var hesitate: float = 0.2

## Seconds before an idle NPC that was hit turns toward the shooter; 0 is instant.
@export_range(0.0, 1.0, 0.01) var hurt_delay: float = 0.15

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
## 1 fires whenever it can; lower leaves gaps so a line of NPCs is not one continuous noise. A weight, not a rate, because the tree decides when a shot is possible.
@export_range(0.0, 1.0, 0.01) var fire_throttle: float = 0.8

## How much it works with others and thinks ahead, rather than walking straight at you.
## It decides whether this NPC calls out sightings to its squad, how far it leads a lost target, and how hard it works round to your back while waiting for an attack slot.
## Ability, not personality, so the server's skill moves it.
@export_range(0.0, 1.0, 0.01) var tactics: float = 0.5

@export_group("Movement")

@export_range(0.0, 1.0, 0.01) var croucher: float = 0.1
@export_range(0.0, 1.0, 0.01) var jumper: float = 0.2

## Tendency to walk rather than run when nothing is happening.
@export_range(0.0, 1.0, 0.01) var walker: float = 0.3

@export var meta: Dictionary = {}

var _vel_est: Vector3 = Vector3.ZERO
var _vel_at: float = -1.0
var _peak_turn: float = 0.0
var _over_amt: float = 0.0
var _over_axis: Vector3 = Vector3.UP
var _turns: int = 0



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
	# Forgets you quickly. An easy NPC that searched for twenty seconds would be one you
	# could not shake, which is the opposite of easy.
	out.memory_time = 2.5
	out.tactics = 0.1
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
	out.memory_time = 8.0
	out.tactics = 0.75
	return out


## As good as this gets, and deliberately not perfect.
## Reaction time stays above zero and accuracy below one: an instant, never-missing bot is a different game, not a harder one.
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
	out.memory_time = 15.0
	out.tactics = 0.95
	return out


## The preset a name means, or [method normal] for one it does not know.
## For a catalogue's `"skill": "hard"` in a definition's `meta`. Unknown names are normal, not an error: a typo should give an ordinary NPC, not a spawner that refuses to spawn one.
static func preset(preset_name: String) -> DotNpcAiCharacter:
	match preset_name.strip_edges().to_lower():
		"easy":
			return easy()
		"hard":
			return hard()
		"nightmare":
			return nightmare()
		_:
			return normal()



## Whether enough time has passed since [param seen_at] for this NPC to act.
## [param seen_at] is when the NPC committed to the target (`DotNpcInstance.target_since`), NOT `engaged_at`, which refreshes on every sighting and never lets a reaction elapse.
## A [member reaction_time] of zero or less answers true at once, for scripted NPCs.
func has_reacted(seen_at: float, now: float) -> bool:
	if reaction_time <= 0.0:
		return true
	return now - seen_at >= effective_reaction(seen_at)


## How long is left before it may act. 0 once it has.
func reaction_remaining(seen_at: float, now: float) -> float:
	return maxf(0.0, effective_reaction(seen_at) - (now - seen_at))


## The reaction to a sighting at [param seen_at]: [member reaction_time], stretched by a
## skewed amount that is the same every time it is asked (most sightings quick, now and then
## a slow one). Never shorter than the plain reaction; 0 [member reaction_jitter] is exactly it.
func effective_reaction(seen_at: float) -> float:
	if reaction_jitter <= 0.0 or reaction_time <= 0.0:
		return reaction_time
	var u := unit(int(seen_at * 1000.0) + 0x3a1c)
	return reaction_time * (1.0 + reaction_jitter * 1.2 * u * u)


## Whether a target last seen at [param seen_at] is still believed to be findable.
func remembers(seen_at: float, now: float) -> bool:
	return now - seen_at <= memory_time


## The sight range this character actually has, from the definition's.
func sight_range(base: float) -> float:
	return base * alertness


## How long it stands still after committing to a target at [param seen_at]. Capped by the
## effective reaction, so it only fills time the NPC was not going to act in anyway.
func hesitation(seen_at: float) -> float:
	if hesitate <= 0.0:
		return 0.0
	var h := hesitate * (0.3 + 0.7 * unit(int(seen_at * 1000.0) + 0x51ed))
	return minf(h, effective_reaction(seen_at))


func is_hesitating(seen_at: float, now: float) -> bool:
	return hesitate > 0.0 and now - seen_at < hesitation(seen_at)


## Delay before turning toward a shooter, the same for the same hit tick.
func hurt_turn_delay(hit_salt: int) -> float:
	if hurt_delay <= 0.0:
		return 0.0
	return hurt_delay * (0.6 + 0.8 * unit(hit_salt + 0x7e11))


## Strafe direction in [-1, 1] at [param now] for a nominal half-[param period]. Exactly the
## plain alternating square wave at 0 [member strafe_jitter]; above it the lengths vary, there
## are pauses, and a reversal eases through zero instead of flipping.
func strafe_drift(now: float, period: float) -> float:
	var base := 1.0 if fmod(now / period, 2.0) < 1.0 else -1.0
	if strafe_jitter <= 0.0:
		return base
	var p1 := unit(0x2a) * TAU
	var p2 := unit(0x2b) * TAU
	var v := sin(TAU * now / (period * 2.0) + p1) + 0.7 * sin(TAU * now / (period * 3.4) + p2)
	var eased := signf(v) * clampf((absf(v) - 0.25) * 2.0, 0.0, 1.0)
	return lerpf(base, eased, strafe_jitter)


## Yaw offset in radians an idle NPC holding a place looks aside by at [param now]; 0 most of the
## time. Windows of 3 to 6 seconds, each with a look (chance [member glance]) held 0.8 to 1.6s.
func glance_offset(now: float) -> float:
	if glance <= 0.0:
		return 0.0
	var window := 4.5
	var k := int(floor(now / window))
	var start := float(k) * window
	if unit(k * 7 + 0x61) >= glance:
		return 0.0
	var hold := 0.8 + 0.8 * unit(k * 7 + 0x62)
	var at := 3.0 * 0.5 * unit(k * 7 + 0x63)
	if now < start + at or now > start + at + hold:
		return 0.0
	var side := 1.0 if unit(k * 7 + 0x64) < 0.5 else -1.0
	return side * deg_to_rad(35.0 + 55.0 * unit(k * 7 + 0x65))


## Feeds the velocity the aim leads with; call each think while there is a target.
func track_velocity(velocity: Vector3, now: float) -> void:
	if track_lag <= 0.0 or _vel_at < 0.0 or now - _vel_at > 1.0 or now < _vel_at:
		_vel_est = velocity
	else:
		_vel_est = _vel_est.lerp(velocity, 1.0 - exp(-(now - _vel_at) / track_lag))
	_vel_at = now



## The widest this character misses by, in radians.
func aim_error() -> float:
	return deg_to_rad(MAX_AIM_ERROR_DEG * (1.0 - aim_accuracy))


## Where to shoot at a target, leading and error included.
## [param travel_speed] is the projectile's speed; 0 for hitscan, which leads by nothing.
## [param shot_seed] makes the error reproducible (same shot, same miss): pass a shot counter or tick; a constant makes every shot miss identically.
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
				# Partial leading, not a threshold: a fraction is the same curve as the original's 0.4 and 0.8
				# cliffs without the cliffs, and a bot at 0.5 leading half as far misses behind a runner
				# like a mediocre player.
		var lead := _vel_est if (track_lag > 0.0 and _vel_at >= 0.0) else target_velocity
		aim += lead * flight * aim_skill

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
## Both are directions. Returns the new direction, [param wanted] once within one tick's turn.
func turn_view(current: Vector3, wanted: Vector3, delta: float) -> Vector3:
	if current.length_squared() <= 0.0001:
		return wanted
	if wanted.length_squared() <= 0.0001:
		return current

	var from := current.normalized()
	var to := wanted.normalized()

	if _over_amt > 0.001:
		_over_amt *= exp(-delta * 3.0)
		to = to.rotated(_over_axis, _over_amt)

	var angle := from.angle_to(to)
	_peak_turn = maxf(_peak_turn, angle)

	if _peak_turn >= 0.35 and angle <= _peak_turn * 0.15:
		to = _arm_overshoot(to, from, _peak_turn)
		_peak_turn = 0.0
		angle = from.angle_to(to)

	if angle <= 0.0001:
		_peak_turn = 0.0
		return to

	# Eased, then clamped. The ease is what makes tracking look like following; the
	# clamp is what stops a bot snapping its head round in one tick, and a bot with
	# only the ease still snaps when the error is large.
	var wanted_step := angle * clampf(view_factor * delta * 8.0, 0.0, 1.0)
	var limit := deg_to_rad(view_turn_deg) * delta
	var step := minf(wanted_step, limit)

	if step >= angle:
		_peak_turn = 0.0
		return to

	var axis := from.cross(to)

	if axis.length_squared() <= 0.000001:
				# Exactly opposite: the cross is zero, so pick an axis. Not `from.cross(UP)`, a HORIZONTAL axis
				# for a level view, which tipped the head back a degree a tick instead of turning round.
				# Turn about UP unless the view is itself straight up or down.
		axis = Vector3.UP if absf(from.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT

	return from.rotated(axis.normalized(), step)


## Near the end of a big turn (the ease never quite arrives), aim a little past the target; the
## shifted target then decays back so the view returns.
func _arm_overshoot(to: Vector3, from: Vector3, peak: float) -> Vector3:
	if overshoot <= 0.0 or _over_amt > 0.001:
		return to
	var axis := from.cross(to)
	if axis.length_squared() <= 0.000001:
		return to
	_turns += 1
	_over_axis = axis.normalized()
	_over_amt = minf(peak, 1.57) * overshoot * (0.15 + 0.25 * unit(_turns * 13 + 0x71))
	return to.rotated(_over_axis, _over_amt)


## Whether this character takes a shot it is otherwise able to take.
func should_fire(shot_seed: int) -> bool:
	if fire_throttle >= 1.0:
		return true
	return unit(shot_seed ^ 0x27d4eb2f) < fire_throttle



## A reproducible number in [0, 1) from this character's seed and [param salt].
## Covers the whole range, and the suite checks a quadrant: a mixer that masked to 23 bits of 24 never passed 0.5, which a maximum-magnitude check cannot see.
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
		"overshoot": overshoot,
		"track_lag": track_lag,
		"strafe_jitter": strafe_jitter,
		"glance": glance,
		"hesitate": hesitate,
		"hurt_delay": hurt_delay,
		"aggression": aggression,
		"self_preservation": self_preservation,
		"vengefulness": vengefulness,
		"camper": camper,
		"fire_throttle": fire_throttle,
		"tactics": tactics,
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
	out.overshoot = clampf(float(data.get("overshoot", 0.4)), 0.0, 1.0)
	out.track_lag = clampf(float(data.get("track_lag", 0.05)), 0.0, 0.5)
	out.strafe_jitter = clampf(float(data.get("strafe_jitter", 0.5)), 0.0, 1.0)
	out.glance = clampf(float(data.get("glance", 0.5)), 0.0, 1.0)
	out.hesitate = clampf(float(data.get("hesitate", 0.2)), 0.0, 2.0)
	out.hurt_delay = clampf(float(data.get("hurt_delay", 0.15)), 0.0, 1.0)
	out.aggression = clampf(float(data.get("aggression", 0.5)), 0.0, 1.0)
	out.self_preservation = clampf(float(data.get("self_preservation", 0.5)), 0.0, 1.0)
	out.vengefulness = clampf(float(data.get("vengefulness", 0.5)), 0.0, 1.0)
	out.camper = clampf(float(data.get("camper", 0.2)), 0.0, 1.0)
	out.fire_throttle = clampf(float(data.get("fire_throttle", 0.8)), 0.0, 1.0)
	out.tactics = clampf(float(data.get("tactics", 0.5)), 0.0, 1.0)
	out.croucher = clampf(float(data.get("croucher", 0.1)), 0.0, 1.0)
	out.jumper = clampf(float(data.get("jumper", 0.2)), 0.0, 1.0)
	out.walker = clampf(float(data.get("walker", 0.3)), 0.0, 1.0)

	var meta_value: Variant = data.get("meta", {})
	out.meta = (
		(meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	)

	return out.validate()


## A copy with its own seed, so twenty NPCs of one preset do not miss identically.
## Easy to forget: one preset resource shared by twenty NPCs shares one seed, and they all take the same shot with the same error at once.
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
		"tactics": "%.2f" % tactics,
	}


func _to_string() -> String:
	return "DotNpcAiCharacter(%s)" % String(id)

extends "res://examples/selftest/selftest_base.gd"

## Decorator, random-selector and character sections.



func _test_more_decorators() -> void:
	_section("decorators: limits and chance")

	var ctx := _context()

	var failer := DotNpcAiDecorator.Failer.new(
		&"failer",
		DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true)
	)
	_check(
		failer.tick(ctx) == DotNpcAiNode.Status.FAILURE,
		"a Failer turns a success into a failure"
	)

	# A stuck action: RUNNING for ever. Without a time limit this is the zombie in the
	# corner that nobody can explain.
	var aborts := []
	var stuck := DotNpcAiLeaf.Action.new(&"stuck", func(_c: DotNpcAiContext) -> int:
		return DotNpcAiNode.Status.RUNNING)
	stuck.on_abort = func(_c: DotNpcAiContext) -> void: aborts.append("aborted")

	var limited := DotNpcAiDecorator.TimeLimit.new(&"limit", stuck, 1.0)

	ctx.advance(0.1)
	_check(limited.tick(ctx) == DotNpcAiNode.Status.RUNNING, "a time limit lets it run")

	ctx.advance(1.5)
	_check(
		limited.tick(ctx) == DotNpcAiNode.Status.FAILURE,
		"and fails it once it has taken too long"
	)
	_check(
		aborts.size() == 1,
		"aborting the child rather than dropping it, so whatever it reserved is let go"
	)

	var runs := []
	var once := DotNpcAiDecorator.Limit.new(
		&"once",
		DotNpcAiLeaf.Action.new(&"greet", func(_c: DotNpcAiContext) -> bool:
			runs.append("hello")
			return true),
		1
	)

	_check(once.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "a Limit runs its child")
	_check(once.tick(ctx) == DotNpcAiNode.Status.FAILURE, "and not a second time")
	_check(runs.size() == 1, "so the child ran exactly once")

	once.reset()
	_check(once.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "and a reset gives it back")

	var laps := []
	var patrol := DotNpcAiDecorator.UntilFail.new(
		&"patrol",
		DotNpcAiLeaf.Action.new(&"step", func(_c: DotNpcAiContext) -> bool:
			laps.append("step")
			return laps.size() < 3)
	)

	_check(patrol.tick(ctx) == DotNpcAiNode.Status.RUNNING, "UntilFail keeps going")
	patrol.tick(ctx)
	_check(
		patrol.tick(ctx) == DotNpcAiNode.Status.SUCCESS,
		"and succeeds once the child finally fails"
	)
	_check(laps.size() == 3, "having run it three times")

	# The same decision on the same tick must come out the same way twice, or a replay
	# and the server that recorded it disagree about what an NPC did.
	var coin := DotNpcAiDecorator.RandomChance.new(
		&"coin",
		DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true),
		0.5, 12345
	)
	var twin := DotNpcAiDecorator.RandomChance.new(
		&"coin",
		DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true),
		0.5, 12345
	)

	var same := true
	var heads := 0
	var probe := _context()

	for i in 200:
		probe.advance(0.1)
		var a := coin.tick(probe)
		var b := twin.tick(probe)
		if a != b:
			same = false
		if a == DotNpcAiNode.Status.SUCCESS:
			heads += 1

	_check(same, "two identical RandomChance nodes agree on every tick")
	_check(
		heads > 60 and heads < 140,
		"and a half chance comes up about half the time",
		"%d of 200" % heads
	)

	var never := DotNpcAiDecorator.RandomChance.new(
		&"never",
		DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true),
		0.0, 1
	)
	var always := DotNpcAiDecorator.RandomChance.new(
		&"always",
		DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true),
		1.0, 1
	)
	probe.advance(0.1)
	_check(never.tick(probe) == DotNpcAiNode.Status.FAILURE, "a chance of zero never runs")
	_check(always.tick(probe) == DotNpcAiNode.Status.SUCCESS, "and one of one always does")
	_done()


func _test_random_selector() -> void:
	_section("random selector")

	var picks := {}
	var children: Array[DotNpcAiNode] = []

	for i in 3:
		var tag := "child%d" % i
		children.append(DotNpcAiLeaf.Action.new(
			StringName(tag), func(_c: DotNpcAiContext) -> bool:
				picks[tag] = int(picks.get(tag, 0)) + 1
				return true
		))

	var selector := DotNpcAiRandomSelector.new(&"pick", children)
	selector.salt = 7

	var ctx := _context()
	for i in 300:
		ctx.advance(0.1)
		selector.tick(ctx)

	_check(picks.size() == 3, "every child gets picked sometimes", str(picks))

	var evenish := true
	for key in picks.keys():
		var count := int(picks[key])
		if count < 60 or count > 140:
			evenish = false
	_check(evenish, "and roughly evenly with no weights", str(picks))

	var weighted_picks := {}
	var weighted_children: Array[DotNpcAiNode] = []

	for i in 2:
		var tag := "w%d" % i
		weighted_children.append(DotNpcAiLeaf.Action.new(
			StringName(tag), func(_c: DotNpcAiContext) -> bool:
				weighted_picks[tag] = int(weighted_picks.get(tag, 0)) + 1
				return true
		))

	var weighted := DotNpcAiRandomSelector.new(&"weighted", weighted_children)
	weighted.set_weights([9.0, 1.0])
	weighted.salt = 3

	var wctx := _context()
	for i in 400:
		wctx.advance(0.1)
		weighted.tick(wctx)

	_check(
		int(weighted_picks.get("w0", 0)) > int(weighted_picks.get("w1", 0)) * 3,
		"a heavier child is picked far more often",
		str(weighted_picks)
	)
	_check(
		int(weighted_picks.get("w1", 0)) > 0,
		"and a lighter one is still picked"
	)

	# The rule the whole addon is built on, reached from the one direction where it is
	# tempting to break it: a chosen child that returns RUNNING is resumed, not
	# re-rolled out of existence next tick.
	var steps := []
	var slow: Array[DotNpcAiNode] = [
		_counting(4, steps, "slow"),
		_counting(0, steps, "quick"),
	]
	var sticky := DotNpcAiRandomSelector.new(&"sticky", slow)
	sticky.salt = 11

	var sctx := _context()
	sctx.advance(0.1)
	sticky.tick(sctx)
	var first: Variant = steps[0]

	for i in 3:
		sctx.advance(0.1)
		sticky.tick(sctx)

	var stayed := true
	for step in steps:
		if str(step) != str(first):
			stayed = false
	_check(stayed, "a running choice is kept rather than re-rolled every tick", str(steps))

	var empty := DotNpcAiRandomSelector.new(&"empty", [] as Array[DotNpcAiNode])
	_check(
		empty.tick(_context()) == DotNpcAiNode.Status.FAILURE,
		"a selector with no children fails rather than erroring"
	)

	var zeroed := DotNpcAiRandomSelector.new(&"zeroed", children)
	zeroed.set_weights([0.0, 0.0, 0.0])
	_check(
		zeroed.tick(_context()) == DotNpcAiNode.Status.FAILURE,
		"and one where nothing weighs anything does too"
	)

	var negative := DotNpcAiRandomSelector.new(&"negative", children)
	negative.set_weights([-5.0, 1.0, 1.0])
	_check(
		negative.weight_of(0) == 0.0,
		"a negative weight is clamped, not left to break the total the roll is scaled to"
	)
	_done()



func _test_character() -> void:
	_section("character")

	var normal := DotNpcAiCharacter.normal()
	_check(normal.validate().ok, "the normal preset validates")
	_check(DotNpcAiCharacter.easy().validate().ok, "so does easy")
	_check(DotNpcAiCharacter.hard().validate().ok, "and hard")

	var worst := DotNpcAiCharacter.nightmare()
	_check(worst.validate().ok, "and nightmare")
	_check(
		worst.reaction_time > 0.0 and worst.aim_accuracy < 1.0,
		"which still has a reaction time and still misses",
		"a bot that reacts instantly and never misses is a different game"
	)
	_check(
		DotNpcAiCharacter.easy().reaction_time > worst.reaction_time,
		"and easy is slower to react than nightmare"
	)

	# The number every player can feel and nobody can name.
	_check(not normal.has_reacted(10.0, 10.1), "an NPC has not reacted immediately")
	_check(normal.has_reacted(10.0, 10.5), "and has once its reaction time has passed")
	_check(
		normal.reaction_remaining(10.0, 10.1) > 0.0,
		"and can say how long is left"
	)

	var instant := DotNpcAiCharacter.new()
	instant.reaction_time = 0.0
	_check(
		instant.has_reacted(10.0, 10.0),
		"a reaction time of zero reacts at once, for a scripted NPC"
	)

	# [b]THE gate, against the field it is actually measured from.[/b] `has_reacted()` on
	# the brain used `DotNpcInstance.engaged_at`, which dot-npc refreshes on EVERY pass in
	# which the target is perceived — so it was false for ever for any NPC that could
	# currently see somebody, which is every NPC that would ever act on one. Every branch
	# behind it never ran and nothing errored: a bot that never acts on what it sees looks
	# like a bot that is bad rather than like one that is broken.
	#
	# `target_since` was added to dot-npc for this. It moves when the target CHANGES and
	# not while it is held, and the check below is the difference stated as a number.
	var instance := DotNpcInstance.new()
	instance.def = DotNpcDef.make(&"x", "res://fixtures/npc_body.tscn")
	instance.target_id = &"somebody"
	instance.target_since = 10.0
	instance.engaged_at = 10.0

	var brain := DotNpcAiBrain.new()
	brain.npc = instance
	brain.character = normal
	brain.blackboard = DotNpcAiBlackboard.new()
	brain.context = DotNpcAiContext.make(instance, brain, brain.blackboard)

	brain.context.now = 10.1
	_check(not brain.has_reacted(), "a brain has not reacted immediately")

	# A second of seeing the same person. `engaged_at` moves and `target_since` does not,
	# which is exactly the situation the old version could never get out of.
	brain.context.now = 11.0
	instance.engaged_at = 11.0

	_check(
		brain.has_reacted(),
		"and HAS after its reaction time, even though `engaged_at` kept moving",
		"this is the bug: measured against `engaged_at` it is false for ever"
	)

	# Built by hand, so let go of by hand: the context points back at the brain.
	brain.unbind()

	_check(normal.remembers(10.0, 12.0), "a target is remembered for a while")
	_check(not normal.remembers(10.0, 100.0), "and forgotten eventually")

	_check(
		is_equal_approx(DotNpcAiCharacter.hard().sight_range(30.0), 36.0),
		"alertness scales the definition's sight range rather than replacing it"
	)

	var bad := DotNpcAiCharacter.new()
	bad.alertness = 0.0
	_check(
		not bad.validate().ok,
		"an alertness of zero is refused: it is an NPC that can never see anything"
	)

	var back := DotNpcAiCharacter.from_dictionary(worst.to_dictionary())
	_check(back.ok, "a character round-trips")
	_check(
		is_equal_approx((back.value as DotNpcAiCharacter).aim_skill, worst.aim_skill),
		"with its numbers"
	)

	var seeded := normal.with_seed(4242)
	_check(seeded.seed_value == 4242, "a character can be reseeded")
	_check(normal.seed_value != 4242, "without touching the preset it came from")
	_done()


func _test_character_aim() -> void:
	_section("character aim")

	var perfect := DotNpcAiCharacter.new()
	perfect.aim_accuracy = 1.0
	perfect.aim_skill = 0.0

	var from := Vector3.ZERO
	var target := Vector3(0, 0, 20)

	_check(
		perfect.aim_point(from, target, Vector3.ZERO, 0.0, 1).is_equal_approx(target),
		"a perfect shot at a still target is the target"
	)

	var leading := DotNpcAiCharacter.new()
	leading.aim_accuracy = 1.0
	leading.aim_skill = 1.0

	var crossing := Vector3(8, 0, 0)
	var led := leading.aim_point(from, target, crossing, 100.0, 1)
	_check(led.x > 0.5, "a skilled shot leads a crossing target", "x = %.2f" % led.x)

	var unskilled := DotNpcAiCharacter.new()
	unskilled.aim_accuracy = 1.0
	unskilled.aim_skill = 0.0
	_check(
		unskilled.aim_point(from, target, crossing, 100.0, 1).is_equal_approx(target),
		"and an unskilled one does not"
	)

	_check(
		leading.aim_point(from, target, crossing, 0.0, 1).is_equal_approx(target),
		"a hitscan shot leads by nothing, because it arrives instantly"
	)

	# The half-moon check. dot-combat shipped a mixer that never returned above 0.5,
	# so every shotgun pattern sat on one side of the aim — and a maximum-magnitude
	# check passes for a half-moon. A quadrant check does not.
	var sloppy := DotNpcAiCharacter.new()
	sloppy.aim_accuracy = 0.0
	sloppy.seed_value = 99

	var quadrants := {"pp": 0, "pn": 0, "np": 0, "nn": 0}
	var worst_error := 0.0

	for shot in 400:
		var point := sloppy.aim_point(from, target, Vector3.ZERO, 0.0, shot)
		var offset := point - target

		var key := ("p" if offset.x >= 0.0 else "n") + ("p" if offset.y >= 0.0 else "n")
		quadrants[key] = int(quadrants[key]) + 1

		worst_error = maxf(worst_error, offset.length())

	var all_four := true
	for key in quadrants.keys():
		if int(quadrants[key]) < 40:
			all_four = false

	_check(all_four, "an inaccurate shot misses in every direction", str(quadrants))
	_check(
		worst_error > 1.0,
		"and misses by a real amount at twenty metres",
		"worst %.2f m" % worst_error
	)
	_check(
		worst_error < tan(sloppy.aim_error()) * 20.0 * 1.05,
		"but never by more than the cone it was given"
	)

	var repeat_a := sloppy.aim_point(from, target, Vector3.ZERO, 0.0, 77)
	var repeat_b := sloppy.aim_point(from, target, Vector3.ZERO, 0.0, 77)
	_check(
		repeat_a.is_equal_approx(repeat_b),
		"the same shot always misses the same way, so a replay agrees with the server"
	)
	_check(
		not sloppy.aim_point(from, target, Vector3.ZERO, 0.0, 78).is_equal_approx(repeat_a),
		"and a different shot does not"
	)

	var other := sloppy.with_seed(1234)
	_check(
		not other.aim_point(from, target, Vector3.ZERO, 0.0, 77).is_equal_approx(repeat_a),
		"two NPCs with different seeds miss differently: twenty sharing one is a volley"
	)

	# A view that can turn at any speed snaps round in one tick and is unplayable.
	var slow := DotNpcAiCharacter.new()
	slow.view_turn_deg = 90.0
	slow.view_factor = 1.0

	var facing := Vector3.FORWARD
	var wanted := Vector3.BACK
	var turned := slow.turn_view(facing, wanted, 0.1)

	_check(
		not turned.is_equal_approx(wanted),
		"a limited view does not snap round in one tick"
	)
	_check(
		facing.angle_to(turned) <= deg_to_rad(90.0) * 0.1 + 0.001,
		"and turns no further than it is allowed to",
		"%.1f degrees" % rad_to_deg(facing.angle_to(turned))
	)

	# Exactly behind. The cross product of two opposite directions is zero, so a
	# rotation built from it is a no-op and a bot with something directly behind it
	# never turns round at all.
	var behind := slow.turn_view(Vector3.FORWARD, Vector3.BACK, 0.5)
	_check(
		not behind.is_equal_approx(Vector3.FORWARD),
		"including when the target is exactly behind it"
	)

	var quick := DotNpcAiCharacter.new()
	quick.view_turn_deg = 3600.0
	quick.view_factor = 1.0
	quick.overshoot = 0.0
	_check(
		quick.turn_view(Vector3.FORWARD, Vector3.RIGHT, 1.0).is_equal_approx(Vector3.RIGHT),
		"and arrives exactly when the turn is within one tick"
	)

	var throttled := DotNpcAiCharacter.new()
	throttled.fire_throttle = 1.0
	_check(throttled.should_fire(1), "a full fire throttle always shoots")

	throttled.fire_throttle = 0.0
	_check(not throttled.should_fire(1), "and an empty one never does")
	_done()

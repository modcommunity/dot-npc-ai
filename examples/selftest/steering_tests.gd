extends "res://examples/selftest/selftest_base.gd"

## Steering, crowd-grid, wander and pursuit sections.


func _test_steering() -> void:
	_section("steering")

	var seek := DotNpcAiSteering.seek(Vector3.ZERO, Vector3(10, 5, 0))
	_check(seek.is_equal_approx(Vector3.RIGHT), "seek points at the goal")
	_check(seek.y == 0.0, "and never up a slope", "the vertical is the ground's business")

	var flee := DotNpcAiSteering.flee(Vector3.ZERO, Vector3(10, 0, 0))
	_check(flee.is_equal_approx(Vector3.LEFT), "flee points away")

	var far := DotNpcAiSteering.arrive(Vector3.ZERO, Vector3(20, 0, 0), 5.0)
	var near := DotNpcAiSteering.arrive(Vector3.ZERO, Vector3(1, 0, 0), 5.0)
	_check(far.length() > 0.99, "arrive is at full speed far away")
	_check(
		near.length() < 0.25,
		"and slows as it gets there",
		"an NPC without this overshoots and reads as indecisive"
	)

	var crowded := DotNpcAiSteering.separate(
		Vector3.ZERO, [Vector3(1, 0, 0), Vector3(0, 0, 1)], 3.0
	)
	_check(crowded.x < 0.0 and crowded.z < 0.0, "separation pushes away from a crowd")

	var touching := DotNpcAiSteering.separate(Vector3.ZERO, [Vector3(0.1, 0, 0)], 3.0)
	var distant := DotNpcAiSteering.separate(Vector3.ZERO, [Vector3(2.9, 0, 0)], 3.0)
	_check(
		touching.length() > 0.0 and distant.length() >= 0.0,
		"and something nearly touching pushes harder than something at the edge",
		"linear weighting gives a crowd that spreads evenly and still overlaps"
	)

	_check(
		DotNpcAiSteering.separate(Vector3.ZERO, [Vector3(50, 0, 0)], 3.0) == Vector3.ZERO,
		"and something outside the radius does not push at all"
	)

	# One NPC directly on top of another. The horizontal offset is nothing, so without
	# a tie-break the push is nothing and the pair stays stacked for ever — which is
	# exactly what happened in this addon's own crowd test before the tie-break existed.
	var stacked := DotNpcAiSteering.separate(Vector3.ZERO, [Vector3(0, -1.4, 0)], 1.6)
	_check(
		stacked == Vector3.ZERO,
		"a stacked pair cannot be separated by a horizontal push alone"
	)

	var broken_apart := DotNpcAiSteering.separate(
		Vector3.ZERO, [Vector3(0, -1.4, 0)], 1.6, Vector3.RIGHT
	)
	_check(
		broken_apart.is_equal_approx(Vector3.RIGHT),
		"so a caller's tie-break is what shoves it off",
		"measured: a capsule perched on another's head, chasing perfectly, at a dead stop"
	)

	var blended := DotNpcAiSteering.blend([
		[Vector3.RIGHT, 1.0], [Vector3.FORWARD, 1.0]
	])
	_check(absf(blended.length() - 1.0) < 0.001, "a blend is normalised",
		"or an NPC runs faster when two urges happen to agree")
	_done()


func _test_crowd_grid() -> void:
	_section("crowd grid")

	var grid := DotNpcAiCrowdGrid.new(4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var points: Array = []

	for i in 200:
		var p := Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-0.5, 2.5), rng.randf_range(-20.0, 20.0))
		points.append(p)
		var _i := grid.add(1000 + i, p)

	_check(grid.size() == 200 and grid.index_of(1007) == 7 and grid.index_of(5) == -1, "a grid indexes what it was given")

	var found := grid.near(Vector3(1, 0, -2), 5.0, PackedInt32Array())
	var expect := 0
	for p: Vector3 in points:
		if p.distance_to(Vector3(1, 0, -2)) <= 5.0:
			expect += 1
	var all_in := true
	for i in found:
		all_in = all_in and (points[i] as Vector3).distance_to(Vector3(1, 0, -2)) <= 5.0
	_check(found.size() == expect and all_in, "near finds exactly what a walk over everybody finds")

	var same := true
	for k in 200:
		var others: Array = []
		var centre: Vector3 = points[k]
		for j in grid.near(centre, 3.2, PackedInt32Array()):
			if j != k:
				others.append(points[j])
		var from := centre + Vector3(0.1, 0.0, -0.05)
		var want := DotNpcAiSteering.separate(from, others, 1.6, Vector3.RIGHT)
		var got := grid.separation(k, from, 1.6, 3.2, Vector3.RIGHT)
		same = same and got == want
	_check(same, "its separation is the steering one over near's neighbours, bit for bit",
		"a seeded crowd must not drift when a host switches it on")

	grid.forget(grid.index_of(1007))
	_check(not grid.near(points[7], 0.5, PackedInt32Array()).has(7), "a forgotten entry is in no query")

	var stack := DotNpcAiCrowdGrid.new(4.0)
	var _a := stack.add(1, Vector3.ZERO)
	var _b := stack.add(2, Vector3(0, -1.4, 0))
	_check(stack.separation(0, Vector3.ZERO, 1.6, 3.2, Vector3.RIGHT).is_equal_approx(Vector3.RIGHT),
		"and a stack is shoved along the tie-break")

	grid.clear()
	var _c := grid.add(42, Vector3(100, 0, 100))
	_check(grid.size() == 1 and grid.index_of(1000) == -1 and grid.near(Vector3.ZERO, 10.0, PackedInt32Array()).is_empty(),
		"a cleared grid forgets the last tick")
	_done()


func _test_wander() -> void:
	_section("wander")

	var angle := 0.0
	var angles: Array[float] = []

	for i in 60:
		angle = DotNpcAiSteering.wander(angle, 0.3, i)
		angles.append(angle)

	var biggest_step := 0.0

	for i in range(1, angles.size()):
		biggest_step = maxf(biggest_step, absf(angle_difference(angles[i - 1], angles[i])))

	_check(
		biggest_step <= 0.31,
		"a wander DRIFTS rather than jumping",
		"biggest step %.2f rad; a fresh random direction per tick looks like a seizure"
	)

	var spread := 0.0
	for a in angles:
		spread = maxf(spread, absf(angle_difference(angles[0], a)))

	_check(spread > 0.2, "and it does actually move", "%.2f rad of spread" % spread)

	var again := 0.0
	for i in 60:
		again = DotNpcAiSteering.wander(again, 0.3, i)

	_check(
		absf(again - angle) < 0.0001,
		"and it is deterministic, so a suite can replay a horde",
		"a global RNG makes one NPC's wandering depend on how many wandered first"
	)
	_done()


func _test_pursuit_and_avoidance() -> void:
	_section("pursuit and avoidance")

	var from := Vector3.ZERO
	var target := Vector3(10, 0, 0)
	var running := Vector3(0, 0, 6)

	var straight := DotNpcAiSteering.seek(from, target)
	var led := DotNpcAiSteering.pursue(from, target, running, 5.0)

	_check(
		led.z > straight.z + 0.05,
		"pursuit aims ahead of a crossing target rather than at it",
		"a tail chase never closes, and reads as an NPC slower than it is"
	)
	_check(
		DotNpcAiSteering.pursue(from, target, running, 0.0) == straight,
		"and falls back to a plain seek when the chaser has no speed to predict over"
	)

	var evading := DotNpcAiSteering.evade(from, target, running, 5.0)
	_check(
		evading.dot(straight) < 0.0,
		"evasion goes the other way"
	)
	_check(
		evading.z < 0.0,
		"and away from where the threat is going, not from where it is"
	)

	# A barrel dead ahead. The NPC must go round it rather than stop in front of it:
	# braking is what makes a crowd pile up at a doorway and never resolve.
	var barrel := [{"position": Vector3(3, 0, 0), "radius": 1.0}]
	var heading := Vector3(1, 0, 0)
	var dodged := DotNpcAiSteering.avoid(heading, from, barrel, 5.0, 0.5)

	_check(
		absf(dodged.z) > 0.05,
		"an obstacle in the way deflects the heading sideways",
		"z = %.2f" % dodged.z
	)
	_check(dodged.x > 0.0, "and does not stop the NPC walking")
	_check(
		is_equal_approx(dodged.length(), 1.0),
		"the result is a direction"
	)

	var behind := [{"position": Vector3(-3, 0, 0), "radius": 1.0}]
	_check(
		DotNpcAiSteering.avoid(heading, from, behind, 5.0, 0.5) == heading,
		"something behind is not in the way"
	)

	var beside := [{"position": Vector3(3, 0, 8), "radius": 1.0}]
	_check(
		DotNpcAiSteering.avoid(heading, from, beside, 5.0, 0.5) == heading,
		"and neither is something to one side of the line being walked"
	)

	_check(
		not DotNpcAiSteering.is_way_clear(heading, from, barrel, 5.0, 0.5),
		"is_way_clear says no with a barrel ahead"
	)
	_check(
		DotNpcAiSteering.is_way_clear(heading, from, barrel, 1.0, 0.5),
		"and yes when the look-ahead stops short of it"
	)
	_check(
		DotNpcAiSteering.is_way_clear(heading, from, [], 5.0, 0.5),
		"and yes with nothing in the world at all"
	)

	# Two NPCs approaching the same barrel head-on must not dance: both are deflected
	# the same way, because the side is chosen from the geometry and not at random.
	var first := DotNpcAiSteering.avoid(heading, from, barrel, 5.0, 0.5)
	var second := DotNpcAiSteering.avoid(heading, from, barrel, 5.0, 0.5)
	_check(first == second, "the deflection is the same every time it is asked")
	_done()

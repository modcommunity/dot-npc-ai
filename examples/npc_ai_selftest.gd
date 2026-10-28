extends "res://examples/selftest/world_tests.gd"

## Proves the tree resumes, the machine cannot spin, and a brain drives a real NPC.
##
## [codeblock]
## godot --headless --path . res://examples/npc_ai_selftest.tscn
## [/codeblock]
##
## [b]The tests that matter are about RUNNING.[/b] Everything else in a behaviour tree
## is three lines and obviously right; the resume rule is the one almost every
## hand-written tree gets wrong, and it fails silently — a sequence that restarts its
## first child every tick has an NPC that looks alive and never finishes anything. So
## there are checks that a sequence does not re-run a finished child, that a reactive
## selector aborts the branch it took over from, and that a repeater with a synchronous
## child does not hang the process.

const CHECKS := 464

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 44


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai self-test")
	print("")

	_world = Node3D.new()
	add_child(_world)

	_test_blackboard()
	_test_context()
	_test_leaves()
	_test_sequence_resume()
	_test_reactive_sequence()
	_test_selector_priority()
	_test_reactive_selector()
	_test_parallel()
	_test_decorators()
	_test_repeat_does_not_hang()
	_test_machine()
	_test_machine_thrash()
	_test_steering()
	_test_crowd_grid()
	_test_pursuit_and_avoidance()
	_test_wander()
	_test_more_decorators()
	_test_random_selector()
	_test_character()
	_test_character_aim()
	_test_brain_on_a_real_npc()
	_test_brain_under_a_scheduler()
	_test_throttled_cruise()
	_test_scheduler_review_gaps()
	_test_squad_review_gaps()
	_test_attack_tokens()
	_test_crowd_separation()
	_test_server_skill()
	_test_reaction_jitter()
	_test_humanising()
	_test_humanised_leaves()
	_test_brain_under_a_skill()
	_test_conditions()
	_test_memory()
	_test_sounds()
	_test_squad()
	_test_tactics()
	_test_brain_perception()
	_test_squad_on_real_npcs()
	_test_squad_pull_interval()
	_test_heatmap()
	_test_ranged_and_roles()
	await _test_nav_annotations()
	await _test_nav_annotator_budget()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _test_blackboard() -> void:
	_section("blackboard")

	var board := DotNpcAiBlackboard.new()
	board.put(&"target", Vector3(1, 2, 3), 0.0)

	_check(board.get_vector(&"target", 0.0) == Vector3(1, 2, 3), "a value is remembered")
	_check(board.has(&"target", 0.0), "and is there")
	_check(not board.has(&"nothing", 0.0), "and one that was never written is not")

	board.put(&"sighting", Vector3.ONE, 10.0, 5.0)
	_check(board.has(&"sighting", 12.0), "a value with a lifetime survives inside it")
	_check(
		not board.has(&"sighting", 16.0),
		"and is gone past it",
		"an NPC walking to a five-minute-old sighting is worse than one with no memory"
	)

	board.put(&"null_value", null, 0.0)
	_check(
		board.has(&"null_value", 0.0),
		"a stored null is present rather than missing",
		"has() compared against null would lie about it"
	)

	var squad := DotNpcAiBlackboard.new()
	squad.put(&"rally", Vector3(9, 0, 9), 0.0)
	board.parent = squad

	_check(
		board.get_vector(&"rally", 0.0) == Vector3(9, 0, 9),
		"a read falls through to a shared board"
	)

	board.put(&"rally", Vector3.ZERO, 0.0)
	_check(
		squad.get_vector(&"rally", 0.0) == Vector3(9, 0, 9),
		"and a write never does",
		"or one NPC's mistake becomes the squad's belief"
	)

	board.put(&"seen", true, 4.0)
	_check(
		absf(board.age_of(&"seen", 10.0) - 6.0) < 0.001,
		"and how long ago something was written can be asked",
		"%.1f" % board.age_of(&"seen", 10.0)
	)
	_done()


func _test_context() -> void:
	_section("context")

	var ctx := _context()
	ctx.advance(0.5)
	ctx.advance(0.5)

	_check(absf(ctx.now - 1.0) < 0.0001, "the clock advances", "%.2f" % ctx.now)
	_check(ctx.tick_index == 2, "and counts ticks")
	_check(ctx.delta == 0.5, "and holds this tick's delta")
	_done()


func _test_leaves() -> void:
	_section("leaves")

	var ctx := _context()

	var yes := DotNpcAiLeaf.Condition.new(&"yes", func(_c: DotNpcAiContext) -> bool: return true)
	_check(yes.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "a true condition succeeds")

	var no := DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false)
	_check(no.tick(ctx) == DotNpcAiNode.Status.FAILURE, "and a false one fails")

	var empty := DotNpcAiLeaf.Condition.new(&"empty")
	_check(
		empty.tick(ctx) == DotNpcAiNode.Status.FAILURE,
		"a condition with no test FAILS rather than passing",
		"a tree whose guards silently pass runs every branch at once"
	)

	var bool_action := DotNpcAiLeaf.Action.new(&"b", func(_c: DotNpcAiContext) -> bool: return true)
	_check(
		bool_action.tick(ctx) == DotNpcAiNode.Status.SUCCESS,
		"an action may return a bool"
	)

	var void_action := DotNpcAiLeaf.Action.new(&"v", func(_c: DotNpcAiContext) -> void: pass)
	_check(
		void_action.tick(ctx) == DotNpcAiNode.Status.SUCCESS,
		"and one that returns nothing succeeds",
		"the commonest thing to write; failing by default would be wrong for all of it"
	)
	_done()


func _test_sequence_resume() -> void:
	_section("a sequence resumes")

	var ctx := _context()
	var log: Array = []

	var sequence := DotNpcAiSequence.new(&"seq", [
		_counting(0, log, "open"),
		_counting(3, log, "walk"),
		_counting(0, log, "close"),
	])

	for i in 3:
		ctx.advance(0.1)
		_check(
			sequence.tick(ctx) == DotNpcAiNode.Status.RUNNING,
			"tick %d is still running" % (i + 1)
		)

	_check(
		log.count("open") == 1,
		"and the first child ran ONCE, not once per tick",
		"ran %d times; this is the bug that re-opens a door 60 times a second" % log.count("open")
	)
	_check(log.count("walk") == 3, "while the running one ran every tick")
	_check(log.count("close") == 0, "and the one after it has not started")

	ctx.advance(0.1)
	_check(sequence.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "and it finishes")
	_check(log.count("close") == 1, "having run the last child")

	var failing := DotNpcAiSequence.new(&"seq2", [
		DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false),
		_counting(0, log, "unreachable"),
	])

	_check(failing.tick(ctx) == DotNpcAiNode.Status.FAILURE, "a failed child fails the sequence")
	_check(log.count("unreachable") == 0, "and nothing after it runs")
	_done()


func _test_reactive_sequence() -> void:
	_section("a reactive sequence re-checks its guard")

	var ctx := _context()
	var log: Array = []
	var holding := {"on": true}
	var aborted: Array = []

	var guard := DotNpcAiLeaf.Condition.new(&"guard", func(_c: DotNpcAiContext) -> bool:
		return bool(holding["on"]))

	# An action that never finishes: "walk at the target" is one, and so is almost
	# every behaviour worth guarding.
	var forever := _counting(10000, log, "chase")
	forever.on_abort = func(_c: DotNpcAiContext) -> void: aborted.append("chase")

	var plain := DotNpcAiSequence.new(&"plain", [guard, forever])

	for i in 3:
		ctx.advance(0.1)
		plain.tick(ctx)

	holding["on"] = false
	ctx.advance(0.1)

	_check(
		plain.tick(ctx) == DotNpcAiNode.Status.RUNNING,
		"a PLAIN sequence keeps going after its guard stops holding",
		"correct, and the trap: it resumes at the action and never asks again"
	)

	log.clear()
	aborted.clear()
	holding["on"] = true

	var reactive := DotNpcAiSequence.reactive_with(&"reactive", [guard, forever])

	for i in 3:
		ctx.advance(0.1)
		reactive.tick(ctx)

	_check(log.count("chase") == 3, "a reactive one runs its action every tick")

	holding["on"] = false
	ctx.advance(0.1)

	_check(
		reactive.tick(ctx) == DotNpcAiNode.Status.FAILURE,
		"and stops the moment the guard stops holding"
	)
	_check(
		aborted.size() == 1,
		"and the action is TOLD it was abandoned",
		"it is the ordinary path here, not the exceptional one"
	)
	_done()


func _test_selector_priority() -> void:
	_section("a selector picks")

	var ctx := _context()
	var log: Array = []

	var selector := DotNpcAiSelector.new(&"sel", [
		DotNpcAiSequence.new(&"first", [
			DotNpcAiLeaf.Condition.new(&"never", func(_c: DotNpcAiContext) -> bool: return false),
			_counting(0, log, "first"),
		]),
		_counting(0, log, "second"),
		_counting(0, log, "third"),
	])

	_check(selector.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "it succeeds")
	_check(log.count("first") == 0, "skipping the branch whose guard failed")
	_check(log.count("second") == 1, "taking the first that could run")
	_check(log.count("third") == 0, "and stopping there")

	var all_fail := DotNpcAiSelector.new(&"none", [
		DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false),
	])
	_check(
		all_fail.tick(ctx) == DotNpcAiNode.Status.FAILURE,
		"and fails only when every child has"
	)
	_done()


func _test_reactive_selector() -> void:
	_section("a reactive selector interrupts")

	var ctx := _context()
	var log: Array = []
	var aborted: Array = []
	var alarm := {"on": false}

	var urgent := DotNpcAiSequence.new(&"urgent", [
		DotNpcAiLeaf.Condition.new(&"alarm", func(_c: DotNpcAiContext) -> bool:
			return bool(alarm["on"])),
		_counting(5, log, "flee"),
	])

	var wander := _counting(100, log, "wander")
	wander.on_abort = func(_c: DotNpcAiContext) -> void: aborted.append("wander")

	var selector := DotNpcAiSelector.new(&"root", [urgent, wander])

	for i in 3:
		ctx.advance(0.1)
		selector.tick(ctx)

	_check(log.count("wander") == 3, "the low-priority branch runs while nothing is urgent")

	alarm["on"] = true
	ctx.advance(0.1)
	selector.tick(ctx)

	_check(log.count("flee") == 1, "and the urgent one takes over the moment it can",
		"a plain selector would never look at it again until the wander finished")
	_check(
		aborted.size() == 1,
		"and the branch it took over from is TOLD it was abandoned",
		"or an action holding a door, a reservation or an animation never lets go"
	)
	_check(not wander.is_running, "so it is no longer running")

	var strict := DotNpcAiSelector.new(&"strict", [urgent, wander])
	strict.reactive = false
	_check(not strict.reactive, "and a game that wants the other behaviour can have it")
	_done()


func _test_parallel() -> void:
	_section("parallel")

	var ctx := _context()
	var log: Array = []

	var both := DotNpcAiParallel.new(&"both", [
		_counting(2, log, "walk"),
		_counting(2, log, "shout"),
	])

	ctx.advance(0.1)
	_check(both.tick(ctx) == DotNpcAiNode.Status.RUNNING, "it runs while its children do")
	_check(
		log.count("walk") == 1 and log.count("shout") == 1,
		"and every child gets a tick"
	)

	var failing := DotNpcAiParallel.new(&"mixed", [
		DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false),
		_counting(0, log, "still ticked"),
	])

	ctx.advance(0.1)
	_check(failing.tick(ctx) == DotNpcAiNode.Status.FAILURE, "one failure fails it")
	_check(
		log.count("still ticked") == 1,
		"but every child was ticked before it decided",
		"returning early would stop the half that was working"
	)
	_done()


func _test_decorators() -> void:
	_section("decorators")

	var ctx := _context()

	var inverter := DotNpcAiDecorator.Inverter.new(
		&"not",
		DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false)
	)
	_check(inverter.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "an inverter inverts")

	var succeeder := DotNpcAiDecorator.Succeeder.new(
		&"try",
		DotNpcAiLeaf.Condition.new(&"no", func(_c: DotNpcAiContext) -> bool: return false)
	)
	_check(succeeder.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "a succeeder swallows failure")

	var runs: Array = []
	var cooldown := DotNpcAiDecorator.Cooldown.new(
		&"attack",
		DotNpcAiLeaf.Action.new(&"swing", func(_c: DotNpcAiContext) -> bool:
			runs.append(1)
			return true),
		2.0
	)

	ctx.advance(0.1)
	_check(cooldown.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "a cooldown runs the first time")

	ctx.advance(0.1)
	_check(cooldown.tick(ctx) == DotNpcAiNode.Status.FAILURE, "and refuses inside the wait")
	_check(runs.size() == 1, "so the child did not run again")

	ctx.advance(3.0)
	_check(cooldown.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "and allows it once it has passed")

	var wait := DotNpcAiDecorator.Wait.new(&"pause", 1.0)
	ctx.advance(0.1)
	_check(wait.tick(ctx) == DotNpcAiNode.Status.RUNNING, "a wait waits")
	ctx.advance(2.0)
	_check(wait.tick(ctx) == DotNpcAiNode.Status.SUCCESS, "and then succeeds")
	_done()


func _test_repeat_does_not_hang() -> void:
	_section("repeat")

	var ctx := _context()
	var runs: Array = []

	# A child that succeeds WITHOUT ever suspending. A repeater written as a loop hangs
	# the process here rather than misbehaving, which is the fan-out trap in another
	# costume — and a hung headless run looks exactly like a slow one.
	var repeat := DotNpcAiDecorator.Repeat.new(
		&"three times",
		DotNpcAiLeaf.Action.new(&"count", func(_c: DotNpcAiContext) -> bool:
			runs.append(1)
			return true),
		3
	)

	var status := DotNpcAiNode.Status.RUNNING
	var ticks := 0

	while status == DotNpcAiNode.Status.RUNNING and ticks < 20:
		ctx.advance(0.1)
		status = repeat.tick(ctx)
		ticks += 1

	_check(status == DotNpcAiNode.Status.SUCCESS, "it finishes")
	_check(runs.size() == 3, "after exactly three repetitions", "%d" % runs.size())
	_check(ticks == 3, "one per tick, rather than looping inside one", "%d ticks" % ticks)
	_done()


func _test_machine() -> void:
	_section("state machine")

	var ctx := _context()
	var alerted := {"on": false}
	var ticked: Array = []
	var entered: Array = []

	var machine := DotNpcAiMachine.new()

	var idle := DotNpcAiState.make(&"idle", func(_c: DotNpcAiContext) -> void: ticked.append("idle"))
	idle.on_enter = func(_c: DotNpcAiContext) -> void: entered.append("idle")
	idle.when(func(_c: DotNpcAiContext) -> bool: return bool(alerted["on"]), &"chasing")

	var chasing := DotNpcAiState.make(&"chasing", func(_c: DotNpcAiContext) -> void: ticked.append("chasing"))
	chasing.after(2.0, &"idle")

	machine.add(idle).add(chasing)

	ctx.advance(0.1)
	machine.go_to(ctx, &"idle")
	_check(machine.current() == &"idle", "a machine starts where it is told")
	_check(entered.size() == 1, "and the state is told it began")

	machine.tick(ctx)
	_check(ticked.count("idle") == 1, "and is ticked")

	alerted["on"] = true
	ctx.advance(0.1)
	machine.tick(ctx)

	_check(machine.current() == &"chasing", "a transition is taken when its test passes")
	_check(
		ticked.count("chasing") == 1 and ticked.count("idle") == 1,
		"and the NEW state is what runs on that tick",
		"the other order gives one more tick of walking toward what is hurting you"
	)

	# The alert is lifted first. With it still on, `idle` transitions straight back to
	# `chasing` on the tick it is entered — which is correct behaviour and would make
	# this a test of the wrong thing.
	alerted["on"] = false

	for i in 30:
		ctx.advance(0.1)
		machine.tick(ctx)

	_check(machine.current() == &"idle", "and a timeout gets an NPC out of a dead end",
		"a state with no way out is the commonest broken NPC there is")

	_check(
		not machine.go_to(ctx, &"nowhere").ok,
		"a state that does not exist is refused"
	)
	_done()


func _test_machine_thrash() -> void:
	_section("state machine: two states fighting")

	var ctx := _context()
	var machine := DotNpcAiMachine.new()

	# Each sends the NPC to the other, unconditionally. Written by accident every time
	# somebody adds a state, and an uncapped machine hangs the server rather than
	# misbehaving.
	machine.add(
		DotNpcAiState.make(&"a")
			.when(func(_c: DotNpcAiContext) -> bool: return true, &"b")
	)
	machine.add(
		DotNpcAiState.make(&"b")
			.when(func(_c: DotNpcAiContext) -> bool: return true, &"a")
	)

	ctx.advance(0.1)
	machine.go_to(ctx, &"a")
	machine.tick(ctx)

	_check(machine.thrash_count == 1, "the cap fires rather than the process hanging")
	_check(
		machine.transition_count <= machine.max_transitions_per_tick + 1,
		"and no more than the cap is taken",
		"%d" % machine.transition_count
	)
	_done()


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


# --- Pursuit, evasion and getting round things --------------------------------

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

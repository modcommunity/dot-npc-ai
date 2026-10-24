extends Node

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

const BODY := "res://fixtures/npc_body.tscn"
const BRAIN := "res://fixtures/zombie_brain.gd"
const SEARCHER := "res://fixtures/searcher_brain.gd"
const GUNNER := "res://fixtures/gunner_brain.gd"

const CHECKS := 425

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 40

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

var _world: Node3D = null


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
	_test_brain_under_a_skill()
	_test_conditions()
	_test_memory()
	_test_sounds()
	_test_squad()
	_test_tactics()
	_test_brain_perception()
	_test_squad_on_real_npcs()
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


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


func _context() -> DotNpcAiContext:
	return DotNpcAiContext.make(null, null)


## A leaf that returns RUNNING for [param ticks] ticks, then SUCCESS, and counts.
##
## Counters live in an Array because a GDScript lambda captures locals BY VALUE, so a
## plain int incremented inside one stays zero outside it — and a suite built on that
## reports a failure for a node that ran perfectly.
func _counting(ticks: int, log_into: Array, tag: String) -> DotNpcAiLeaf.Action:
	var state := {"left": ticks}

	return DotNpcAiLeaf.Action.new(StringName(tag), func(_ctx: DotNpcAiContext) -> int:
		log_into.append(tag)

		if int(state["left"]) > 0:
			state["left"] = int(state["left"]) - 1
			return DotNpcAiNode.Status.RUNNING

		state["left"] = ticks
		return DotNpcAiNode.Status.SUCCESS
	)


# --- Memory -------------------------------------------------------------------

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


# --- The tree -----------------------------------------------------------------

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


# --- The machine --------------------------------------------------------------

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


# --- Steering -----------------------------------------------------------------

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
		for j in 200:
			if j != k and (points[j] as Vector3).distance_to(centre) <= 3.2:
				others.append(points[j])
		var from := centre + Vector3(0.1, 0.0, -0.05)
		var want := DotNpcAiSteering.separate(from, others, 1.6, Vector3.RIGHT)
		var got := grid.separation(k, from, 1.6, 3.2, Vector3.RIGHT)
		same = same and got.is_equal_approx(want)
	_check(same, "its separation is the steering one over the same neighbours",
		"a brain's spacing must not change when a host switches it on")

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


# --- Against a real NPC -------------------------------------------------------

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


# --- The rest of the decorators -----------------------------------------------

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


# --- Character ----------------------------------------------------------------

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


func _catalogue() -> DotNpcCatalogue:
	var cat := DotNpcCatalogue.new()

	var zombie := DotNpcDef.make(&"zombie", BODY)
	zombie.brain_script_path = BRAIN
	zombie.require_line_of_sight = false
	zombie.sight_half_angle_deg = 180.0
	# Far enough that a zombie on the far side of a spawn ring can still see a player
	# on the other side of the room. At the default 30 m the back half of a horde
	# simply stands there, which reads as broken separation rather than as eyesight.
	zombie.sight_range = 60.0
	zombie.meta = {"speed": 4.0}
	cat.add(zombie)

	# Chase, search, idle, with its character named in the catalogue rather than chosen by
	# its script — the half of a character an operator editing JSON can reach.
	# A body that moves by position alone, so the distance walked is exactly speed times the delta given.
	var plain := DotNpcDef.make(&"plain", "res://fixtures/npc_plain_body.tscn")
	plain.brain_script_path = BRAIN
	plain.require_line_of_sight = false
	plain.meta = {"speed": 4.0}
	cat.add(plain)

	var searcher := DotNpcDef.make(&"searcher", BODY)
	searcher.brain_script_path = SEARCHER
	searcher.require_line_of_sight = false
	searcher.sight_half_angle_deg = 180.0
	searcher.sight_range = 30.0
	searcher.meta = {"speed": 4.0, "skill": "normal"}
	cat.add(searcher)

	# The same brain as a squad member: a hard character, one attack slot per target, a ring
	# of four metres for the rest.
	var soldier := DotNpcDef.make(&"soldier", BODY)
	soldier.brain_script_path = SEARCHER
	soldier.require_line_of_sight = false
	soldier.sight_half_angle_deg = 180.0
	soldier.sight_range = 30.0
	soldier.meta = {
		"speed": 4.0, "skill": "hard", "squad": "pair", "attackers": 1, "ring": 4.0,
	}
	cat.add(soldier)

	var gunner := DotNpcDef.make(&"gunner", BODY)
	gunner.brain_script_path = GUNNER
	gunner.require_line_of_sight = false
	gunner.sight_half_angle_deg = 180.0
	gunner.sight_range = 40.0
	gunner.meta = {"speed": 4.0, "skill": "hard", "squad": "pair", "near": 8.0, "far": 14.0}
	cat.add(gunner)

	return cat


func _spawner() -> DotNpcSpawner:
	var spawner := DotNpcSpawner.new()
	spawner.catalogue = _catalogue()

	var limits := DotNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.sense_period_ticks = 1
	spawner.limits = limits
	spawner.authoritative = true

	_world.add_child(spawner)

	return spawner


func _test_brain_on_a_real_npc() -> void:
	_section("a brain on a real NPC")

	var spawner := _spawner()
	var npc := spawner.spawn(&"zombie", Vector3.ZERO)

	_check(npc.brain != null, "dot-npc loads a dot-npc-ai brain by PATH")
	_check(npc.brain is DotNpcAiBrain, "and it is one")

	var brain := npc.brain as DotNpcAiBrain
	_check(brain.machine != null and brain.tree != null, "with both halves built")
	_check(brain.machine.current() == &"idle", "starting in its initial state")

	# Steering at somewhere and getting nowhere for stuck_seconds asks for an unsmoothed path.
	if brain.path == null:
		brain.path = DotNpcPath.new()
	brain._watch_progress(Vector3.ZERO, Vector3(10, 0, 0))
	brain._progress_since -= brain.stuck_seconds + 0.1
	brain._watch_progress(Vector3(0.1, 0, 0), Vector3(10, 0, 0))
	_check(brain.path.rough_until > spawner.now(), "an NPC making no headway is given the graph's own corners",
		"rough until %.2f, now %.2f" % [brain.path.rough_until, spawner.now()])
	brain.path.rough_until = -INF

	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"player", Vector3(0, 0, -12), &"player")
	])

	for i in 30:
		spawner.tick(1.0 / 60.0)

	_check(npc.has_target(), "the NPC acquires a target")
	_check(brain.machine.current() == &"chasing", "and the machine follows it")
	_check(int(brain.get(&"chases")) > 0, "and the tree's chase branch is what ran")
	_check(
		npc.position().distance_to(Vector3(0, 0, -12)) < 12.0,
		"and it actually moved toward them",
		"%.2f m away" % npc.position().distance_to(Vector3(0, 0, -12))
	)

	spawner.set_candidates([])

	# Long enough for BOTH clocks: the senses hold a target they cannot see for
	# `commitment_grace` (3 s), and only then does `searching` start its own 3-second
	# timeout. Six hundred ticks is ten seconds, which clears both with room. A test
	# sized to one of the two passes or fails depending on which clock it forgot.
	for i in 600:
		spawner.tick(1.0 / 60.0)

	_check(
		brain.machine.current() == &"idle",
		"and it gives up and goes home once they are gone",
		"now in %s" % String(brain.machine.current())
	)
	_check(
		int(brain.get(&"wanders")) > 0,
		"having fallen through to the tree's other branch"
	)

	# [b]And the spawner going away takes the brain with it.[/b] The context points back at
	# the brain and the brain holds the context, and a world is torn down by freeing its
	# nodes, never by removing its NPCs — so this is the path that leaked, in every game
	# with hunters, at every exit. Freed rather than queued, so PREDELETE runs now.
	var brain_ref: WeakRef = weakref(brain)
	var context_ref: WeakRef = weakref(brain.context)
	var npc_ref: WeakRef = weakref(npc)
	brain = null
	npc = null
	_world.remove_child(spawner)
	spawner.free()

	_check(brain_ref.get_ref() == null, "a freed spawner's brains are freed with it",
		"DotNpcAiBrain._npc_unbound did not break the context <-> brain cycle")
	_check(context_ref.get_ref() == null, "and their contexts")
	_check(npc_ref.get_ref() == null, "and the NPCs they were driving")
	_done()


func _test_brain_under_a_scheduler() -> void:
	_section("a brain under the level-of-detail scheduler")

	var plain := _spawner().spawn(&"zombie", Vector3.ZERO).brain as DotNpcAiBrain
	_check(plain.scheduler == null, "with no scheduler registered a brain thinks as it always did")

	var sched := DotNpcAiScheduler.new()
	var cfg := DotNpcAiSchedulerConfig.new()
	cfg.enabled = true
	sched.apply_config(cfg)
	sched.auto_advance = false
	sched.players_source = func() -> Array: return [Vector3.ZERO]
	_world.add_child(sched)
	sched.register_service()

	var spawner := _spawner()
	var near := spawner.spawn(&"zombie", Vector3(5, 0, 0)).brain as DotNpcAiBrain
	var far := spawner.spawn(&"zombie", Vector3(200, 0, 0)).brain as DotNpcAiBrain
	_check(near.scheduler == sched and far.scheduler == sched, "a brain finds the scheduler on the registry")
	_check(sched.tier_of(near) == 0 and sched.tier_of(far) == 3, "and is tiered by its distance to the player",
		"%d and %d" % [sched.tier_of(near), sched.tier_of(far)])

	for i in 90:
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
	_check(sched.thinks_of(near) == 90, "the near brain thought every tick", str(sched.thinks_of(near)))
	_check(sched.thinks_of(far) == 3, "the far one every 30th", str(sched.thinks_of(far)))
	_check(near.context.now - far.context.now <= 30.0 / 60.0 + 0.05,
		"and its clock is at most one sleep behind the near one's, not three ticks' worth", "%.2f against %.2f" % [far.context.now, near.context.now])
	_check(far.describe()["lod_tier"] == 3, "describe() names the tier")

	var far_npc_id := far.npc.instance_id
	spawner.remove(far_npc_id)
	_check(sched.tier_counts()[3] == 0, "a removed NPC's brain leaves the scheduler")
	DotRegistry.unregister(DotNpcAiScheduler.SERVICE)
	_done()


class StubDirector extends Node:
	var path_calls := 0

	func path_toward(_npc: Object, _path: Object, to: Vector3) -> Variant:
		path_calls += 1
		return to


func _walker(spawner: DotNpcSpawner, at: Vector3, goal: Vector3) -> DotNpcAiBrain:
	var brain := spawner.spawn(&"zombie", at).brain as DotNpcAiBrain
	brain.machine = null
	brain.tree = DotNpcAiLeaf.Action.new(&"go", func(ctx: DotNpcAiContext) -> DotNpcAiNode.Status:
		brain.steer_with_spacing(goal, 6.0, ctx.delta)
		return DotNpcAiNode.Status.RUNNING)
	return brain


func _test_throttled_cruise() -> void:
	_section("a throttled NPC keeps walking between thinks")

	var sched := DotNpcAiScheduler.new()
	var cfg := DotNpcAiSchedulerConfig.new()
	cfg.enabled = true
	sched.apply_config(cfg)
	sched.auto_advance = false
	sched.players_source = func() -> Array: return [Vector3.ZERO]
	_world.add_child(sched)
	sched.register_service()

	var spawner := _spawner()
	var near := _walker(spawner, Vector3(5, 0, 0), Vector3(25, 0, 0))
	var far := _walker(spawner, Vector3(200, 0, 0), Vector3(220, 0, 0))
	var still := _walker(spawner, Vector3(300, 0, 0), Vector3(320, 0, 0))
	still.cruise_between_thinks = false
	_check(sched.tier_of(far) == 3, "the walker is in tier 3")

	var near_at := -1
	var far_at := -1
	for i in 600:
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
		if near_at < 0 and near.npc.position().x >= 24.5:
			near_at = i
		if far_at < 0 and far.npc.position().x >= 219.5:
			far_at = i

	_check(near_at > 0 and far_at > 0, "both reach a target 20 m away", "%d and %d" % [near_at, far_at])
	_check(far_at - near_at <= 35, "the tier 3 one is at most one think late", "%d ticks late" % (far_at - near_at))
	_check(far.npc.position().x < 221.0, "and does not run past it", str(far.npc.position().x))
	_check(still.npc.position().x < 310.0, "with cruising off it only moves on its thinks", str(still.npc.position().x))
	_check(sched.thinks_of(far) <= 21, "and thought only every 30th tick", str(sched.thinks_of(far)))

	var stub := StubDirector.new()
	far.director = stub
	for i in 20:
		far._path_goal(Vector3(240, 0, 0))
	_check(stub.path_calls <= 2 and stub.path_calls > 0, "a calm tier reuses a path through the cache", str(stub.path_calls))
	far.director = spawner

	var calls := [0]
	var probe := func() -> bool:
		calls[0] += 1
		return true
	for i in 6:
		near.line_clear(Vector3(9, 0, 0), probe)
		far.line_clear(Vector3(9, 0, 0), probe)
		sched.advance(1.0 / 60.0)
	_check(calls[0] >= 1 and calls[0] <= 2, "a line test is cached for near and refused for tier 3", str(calls[0]))

	stub.free()
	DotRegistry.unregister(DotNpcAiScheduler.SERVICE)
	_done()


class TokenMember extends RefCounted:
	pass


func _token_squad(pool: int, cap: int, seed_value: int = 1) -> DotNpcAiSquad:
	var squad := DotNpcAiSquad.new(&"t")
	squad.tokens.enabled = true
	squad.tokens.pool_size = pool
	squad.tokens.per_target_cap = cap
	squad.tokens.timeout_s = 2.0
	squad.tokens.retake_cooldown_s = 1.0
	squad.tokens.los_loss_s = 0.5
	squad.tokens.seed = seed_value
	return squad


func _token_members(squad: DotNpcAiSquad, n: int) -> Array:
	var out: Array = []
	for i in n:
		var m := TokenMember.new()
		squad.join(m)
		out.append(m)
	return out


## Everyone keeps asking every 0.1 s for [param seconds]; returns the grant log and the worst totals.
func _token_sim(seed_value: int, seconds: float) -> Dictionary:
	var squad := _token_squad(3, 2, seed_value)
	var members := _token_members(squad, 8)
	var log := PackedStringArray()
	var grants := {}
	var worst_total := 0
	var worst_target := 0
	var longest_wait := 0.0
	var waiting_since := {}
	var t := 0.0
	for step in int(seconds / 0.1):
		t += 0.1
		for i in members.size():
			var m: Object = members[i]
			var target := &"a" if i < 5 else &"b"
			squad.token_sight(m, true, t)
			var had := squad.has_token(m)
			if squad.take_token(m, target, t):
				if not had:
					grants[i] = int(grants.get(i, 0)) + 1
					log.append("%.1f:%d" % [t, i])
					longest_wait = maxf(longest_wait, t - float(waiting_since.get(i, t)))
				waiting_since[i] = INF
			elif not waiting_since.has(i) or is_inf(float(waiting_since[i])):
				waiting_since[i] = t
		worst_total = maxi(worst_total, squad.token_count())
		worst_target = maxi(worst_target, maxi(squad.token_count(&"a"), squad.token_count(&"b")))
	return {"log": log, "grants": grants, "total": worst_total, "target": worst_target, "wait": longest_wait}


func _test_attack_tokens() -> void:
	_section("attack tokens")

	var off := DotNpcAiSquad.new(&"off")
	_check(not off.tokens.enabled and DotNpcAiTokenConfig.new().enabled == false, "tokens ship off")
	_check(off.describe()["tokens"] == -1, "and describe() says so")
	_check(DotNpcAiTokenConfig.new().validate().ok, "the default config validates")
	var bad := DotNpcAiTokenConfig.new()
	bad.per_target_cap = bad.pool_size + 1
	_check(not bad.validate().ok, "a cap above the pool does not")

	var squad := _token_squad(3, 2)
	var m := _token_members(squad, 6)
	var taken := 0
	for i in 5:
		if squad.take_token(m[i], &"a", 0.0):
			taken += 1
	_check(taken == 2, "five ask for one target, the per-target cap lets two", str(taken))
	_check(squad.take_token(m[5], &"b", 0.0) and squad.token_count() == 3, "another target takes the last of the pool")
	_check(not squad.take_token(m[2], &"b", 0.0), "then the pool is dry", str(squad.token_count()))
	_check(squad.take_token(m[0], &"a", 0.1), "a holder asking again keeps its token")

	squad.release_target_tokens(&"a", 0.2)
	_check(squad.token_count(&"a") == 0 and squad.token_stats["kill"] == 2, "a kill frees every token on the target")
	_check(squad.take_token(m[0], &"c", 0.2), "and a kill starts no cooldown")

	squad.release_token(m[0], &"manual", 0.3)
	_check(not squad.take_token(m[0], &"c", 0.5) and squad.take_token(m[0], &"c", 1.4),
		"a given-up token cannot be re-taken until the cooldown has passed")

	var timed := _token_squad(3, 2)
	var tm := _token_members(timed, 3)
	timed.take_token(tm[0], &"a", 0.0)
	timed.sweep(1.0)
	_check(timed.has_token(tm[0]), "a token is kept inside its timeout")
	timed.sweep(2.1)
	_check(not timed.has_token(tm[0]) and timed.token_stats["timeout"] == 1, "and taken back after it")

	var sight := _token_squad(3, 2)
	var sm := _token_members(sight, 2)
	sight.take_token(sm[0], &"a", 0.0)
	sight.token_sight(sm[0], false, 0.2)
	sight.sweep(0.5)
	_check(sight.has_token(sm[0]), "briefly out of sight keeps the token")
	sight.token_sight(sm[0], true, 0.6)
	sight.token_sight(sm[0], false, 0.7)
	sight.sweep(1.1)
	_check(sight.has_token(sm[0]), "and seeing again restarts the count")
	sight.sweep(1.3)
	_check(not sight.has_token(sm[0]) and sight.token_stats["los"] == 1, "lost sight for too long gives it up")

	sight.take_token(sm[1], &"a", 5.0)
	sight.leave(sm[1])
	_check(sight.token_count() == 0 and sight.token_stats["left"] == 1, "leaving the squad gives it up")

	var run1 := _token_sim(5, 120.0)
	_check(run1["total"] <= 3 and run1["target"] <= 2, "over two minutes the pool and the cap are never exceeded",
		"%d and %d" % [run1["total"], run1["target"]])
	var starved := 0
	for i in 8:
		if int(run1["grants"].get(i, 0)) == 0:
			starved += 1
	_check(starved == 0, "every member gets a token sooner or later", str(run1["grants"]))
	_check(run1["wait"] < 15.0, "and none waits long", "%.1f s" % run1["wait"])
	var run2 := _token_sim(5, 120.0)
	_check(run1["log"] == run2["log"] and run1["log"].size() > 20, "the same seed gives the same grants in the same order")
	_check(run1["log"] != _token_sim(6, 120.0)["log"], "another seed gives another run")

	_check(squad.describe_lines().size() == 2 and "tokens" in squad.describe_lines()[1], "describe_lines() reports the pool")

	var cfg := DotNpcAiTokenConfig.new()
	var behind := DotNpcAiTactics.best_flank(Vector3.ZERO, Vector3(1, 0, 0), Vector3(3, 0, 0), 4.0, [], cfg)
	_check(DotNpcAiTactics.angle_from_behind(Vector3.ZERO, Vector3(1, 0, 0), behind) < 0.6,
		"flanking picks a place behind the target", str(behind))
	var crowded := DotNpcAiTactics.best_flank(Vector3.ZERO, Vector3(1, 0, 0), Vector3(3, 0, 0), 4.0, [behind], cfg)
	_check(crowded.distance_to(behind) >= cfg.flank_ally_radius, "and not the one an ally already holds", str(crowded))
	_done()


func _plain_walker(spawner: DotNpcSpawner, at: Vector3, goal: Vector3) -> DotNpcAiBrain:
	var brain := spawner.spawn(&"plain", at).brain as DotNpcAiBrain
	brain.machine = null
	brain.tree = DotNpcAiLeaf.Action.new(&"go", func(ctx: DotNpcAiContext) -> DotNpcAiNode.Status:
		brain.steer_toward(goal, 6.0, ctx.delta)
		return DotNpcAiNode.Status.RUNNING)
	return brain


func _sched_on(players: Array = [Vector3.ZERO]) -> DotNpcAiScheduler:
	var sched := DotNpcAiScheduler.new()
	var cfg := DotNpcAiSchedulerConfig.new()
	cfg.enabled = true
	sched.apply_config(cfg)
	sched.auto_advance = false
	sched.players_source = func() -> Array: return players
	_world.add_child(sched)
	sched.register_service()
	return sched


func _test_scheduler_review_gaps() -> void:
	_section("scheduler gaps a review found")

	var sched := _sched_on()
	var spawner := _spawner()
	var near := _plain_walker(spawner, Vector3(5, 0, 0), Vector3(900, 0, 0))
	var mid := _plain_walker(spawner, Vector3(0, 0, 45), Vector3(0, 0, 900))
	var calm := _plain_walker(spawner, Vector3(-100, 0, 0), Vector3(-900, 0, 0))
	_check(sched.tier_of(near) == 0 and sched.tier_of(mid) == 1 and sched.tier_of(calm) == 2, "walkers sit in tiers 0, 1 and 2")
	var near0 := near.npc.position()
	var mid0 := mid.npc.position()
	var calm0 := calm.npc.position()
	for i in 240:
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
	var d_near := near.npc.position().distance_to(near0)
	var d_mid := mid.npc.position().distance_to(mid0)
	var d_calm := calm.npc.position().distance_to(calm0)
	_check(absf(d_mid - d_near) <= 0.5 and absf(d_calm - d_near) <= 1.0,
		"a throttled walker covers the distance a tier 0 one does, not more", "%.1f, %.1f, %.1f m" % [d_near, d_mid, d_calm])

	# Hurt, or newly engaged, and a sleeper is tiered and thinks at once.
	var sleeper := _plain_walker(spawner, Vector3(300, 0, 0), Vector3(900, 0, 0))
	_check(sched.tier_of(sleeper) == 3, "a distant walker sleeps")
	sleeper.damaged(1.0, &"p")
	_check(sched.tier_of(sleeper) <= 1, "being hurt wakes it", str(sched.tier_of(sleeper)))
	var sleeper2 := _plain_walker(spawner, Vector3(300, 0, 5), Vector3(900, 0, 0))
	spawner.target_changed.emit(sleeper2.npc, &"p")
	_check(sched.tier_of(sleeper2) <= 1, "and so does the spawner reporting it a target", str(sched.tier_of(sleeper2)))

	# halt() stops a throttled walker from carrying on.
	var halted := _plain_walker(spawner, Vector3(0, 0, -100), Vector3(0, 0, -900))
	for i in 40:
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
	halted.tree = DotNpcAiLeaf.Action.new(&"stop", func(_c: DotNpcAiContext) -> DotNpcAiNode.Status:
		halted.halt()
		return DotNpcAiNode.Status.RUNNING)
	for i in 12:
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
	var drift := 0.0
	var skipped_ticks := 0
	for i in 8:
		var thought := sched.thinks_of(halted)
		var p0 := halted.npc.position()
		sched.advance(1.0 / 60.0)
		spawner.tick(1.0 / 60.0)
		if sched.thinks_of(halted) == thought:
			skipped_ticks += 1
			drift += p0.distance_to(halted.npc.position())
	_check(skipped_ticks > 0 and drift < 0.001, "halt() ends the cruise", "%.3f m over %d skipped ticks" % [drift, skipped_ticks])

	# Path denial falls back to the last waypoint, never a straight line.
	var stub := StubDirector.new()
	spawner = _spawner()
	var first := _plain_walker(spawner, Vector3(45, 0, 0), Vector3.ZERO)
	var second := _plain_walker(spawner, Vector3(45, 0, 3), Vector3.ZERO)
	sched.config.max_paths_per_frame = 1
	first.director = stub
	second.director = stub
	second._waypoint = Vector3(45, 0, 20)
	sched.advance(1.0 / 60.0)
	first.steer_with_spacing(Vector3(100, 0, 0), 6.0, 0.1)
	var before := second.npc.position()
	second.steer_with_spacing(Vector3(100, 0, 3), 6.0, 0.1)
	var moved := second.npc.position() - before
	_check(stub.path_calls == 1, "only the first of two path requests in a frame is computed", str(stub.path_calls))
	_check(moved.z > 0.1 and moved.x < 0.1, "the refused one keeps to its last waypoint instead of cutting straight to the target", str(moved))
	var nowhere := _plain_walker(spawner, Vector3(45, 0, 6), Vector3.ZERO)
	nowhere.director = stub
	var n0 := nowhere.npc.position()
	nowhere.steer_with_spacing(Vector3(100, 0, 6), 6.0, 0.1)
	_check(nowhere.npc.position().distance_to(n0) < 0.01, "and one with no waypoint at all waits for the next frame")

	# A path follows a target that moves a little.
	var moving := _plain_walker(spawner, Vector3(45, 0, 9), Vector3.ZERO)
	moving.director = stub
	stub.path_calls = 0
	for i in 8:
		sched.advance(1.0 / 60.0)
		moving._path_goal(Vector3(100 + 0.5 * i, 0, 9))
	_check(stub.path_calls <= 2 and stub.path_calls >= 1, "a path is reused while its destination only drifts", str(stub.path_calls))

	# Sight tests: cached for a tier that may test, refused (not stale) for one that may not.
	var calls := [0]
	var probe := func() -> bool:
		calls[0] += 1
		return true
	var seer := _plain_walker(spawner, Vector3(10, 0, 0), Vector3.ZERO)
	sched.advance(1.0 / 60.0)
	_check(seer.line_clear(Vector3(9, 0, 0), probe) and seer.line_clear(Vector3(9, 0, 0), probe) and calls[0] == 1, "a sight test is reused")
	seer.npc.node.global_position = Vector3(100, 0, 0)
	for i in 12:
		sched.advance(1.0 / 60.0)
	_check(sched.tier_of(seer) >= 2 and seer.line_clear(Vector3(9, 0, 0), probe) == false, "and a tier too calm for it gets no, not the old yes")

	# A scheduler registered after the brains were bound is found.
	DotRegistry.unregister(DotNpcAiScheduler.SERVICE)
	sched.free()
	var late_spawner := _spawner()
	var orphan := _plain_walker(late_spawner, Vector3(5, 0, 0), Vector3(900, 0, 0))
	var counted := [0]
	orphan.tree = DotNpcAiLeaf.Action.new(&"count", func(_c: DotNpcAiContext) -> DotNpcAiNode.Status:
		counted[0] += 1
		return DotNpcAiNode.Status.RUNNING)
	_check(orphan.scheduler == null, "a brain bound with no scheduler has none")
	var late := _sched_on()
	for i in 200:
		late.advance(1.0 / 60.0)
		late_spawner.tick(1.0 / 60.0)
	_check(orphan.scheduler == late and late.thinks_of(orphan) > 0, "and finds one registered later", str(late.thinks_of(orphan)))

	# A scheduler freed under the brains costs them nothing but its gating.
	DotRegistry.unregister(DotNpcAiScheduler.SERVICE)
	late.free()
	var before_count: int = counted[0]
	for i in 30:
		late_spawner.tick(1.0 / 60.0)
	_check(counted[0] - before_count == 30, "a freed scheduler leaves every brain thinking each tick", str(counted[0] - before_count))
	orphan.line_clear(Vector3.ONE, probe)
	orphan._path_goal(Vector3.ONE)
	stub.free()
	_done()


func _test_squad_review_gaps() -> void:
	_section("squad gaps a review found")

	# A departed member leaves no cooldown behind, and an expired one is dropped.
	var squad := _token_squad(2, 2)
	var m := _token_members(squad, 4)
	squad.take_token(m[0], &"a", 0.0)
	squad.release_token(m[0], &"manual", 0.1)
	squad.take_token(m[1], &"a", 0.1)
	squad.release_token(m[1], &"manual", 0.2)
	_check(squad._cooldown_until.size() == 2, "two given-up tokens leave two cooldowns")
	squad.leave(m[0])
	_check(squad._cooldown_until.size() == 1, "and leaving drops the leaver's")
	squad.sweep(5.0)
	_check(squad._cooldown_until.is_empty(), "an expired cooldown is dropped on the next sweep")

	# A refused first waiter that went quiet does not hold a free token.
	var q := _token_squad(1, 1)
	var qm := _token_members(q, 3)
	q.take_token(qm[0], &"a", 0.0)
	q.take_token(qm[1], &"a", 0.0)
	q.take_token(qm[2], &"a", 0.1)
	q.release_token(qm[0], &"kill", 0.2)
	_check(q.take_token(qm[2], &"a", 0.5), "a free token goes to an asker, not to a throttled waiter who has not asked for 0.5 s")
	var busy := _token_squad(1, 1)
	var bm := _token_members(busy, 3)
	busy.take_token(bm[0], &"a", 0.0)
	busy.take_token(bm[1], &"a", 0.0)
	busy.take_token(bm[2], &"a", 0.05)
	busy.release_token(bm[0], &"kill", 0.1)
	busy.take_token(bm[1], &"a", 0.1)
	_check(busy.has_token(bm[1]) and not busy.take_token(bm[2], &"a", 0.1), "while one still asking keeps its turn")

	# Tokens off: none are kept.
	var off := _token_squad(2, 2)
	var om := _token_members(off, 2)
	off.take_token(om[0], &"a", 0.0)
	off.tokens.enabled = false
	off.sweep(0.1)
	_check(off.token_count() == 0, "switching tokens off drops the ones held")

	# Tokens switched on while members already hold plain attack slots.
	var spawner := _spawner()
	DotNpcAiSquads.new().attach(spawner)
	var a := spawner.spawn(&"soldier", Vector3(0, 0, 0))
	var b := spawner.spawn(&"soldier", Vector3(3, 0, 0))
	var ba := a.brain as DotNpcAiBrain
	var bb := b.brain as DotNpcAiBrain
	a.target_id = &"p"
	b.target_id = &"p"
	_check(ba.claim_role(DotNpcAiBrain.ROLE_ATTACK, 2) and bb.claim_role(DotNpcAiBrain.ROLE_ATTACK, 2), "two attack slots are held without tokens")
	ba.squad.tokens.enabled = true
	ba.squad.tokens.pool_size = 1
	ba.squad.tokens.per_target_cap = 1
	var got_a := ba.claim_role(DotNpcAiBrain.ROLE_ATTACK, 2)
	var got_b := bb.claim_role(DotNpcAiBrain.ROLE_ATTACK, 2)
	_check(got_a != got_b, "with one token only one of them still attacks", "%s and %s" % [got_a, got_b])
	_check(ba.squad.holder_count(&"attack:p") == 1, "and the other's slot is given up with the refusal", str(ba.squad.holder_count(&"attack:p")))
	_done()


func _test_crowd_separation() -> void:
	_section("a crowd at one door")

	var spawner := _spawner()
	var goal := Vector3(0, 0, -30)

	# Twelve zombies on a ring, all sent at one point — which is a horde arriving at a
	# door, and the case dot-npc alone has nothing to say about.
	#
	# Deliberately NOT stacked in one spot: twelve CharacterBody3Ds spawned inside each
	# other cannot depenetrate and none of them moves at all, which is a test of
	# Godot's collision resolution rather than of separation. `spawn_group` is the
	# addon's own answer and is what a director would call.
	# A floor, because a CharacterBody3D with nothing under it falls at 9.8 m/s² and
	# `steer_toward` applies gravity by design. The first version of this test measured
	# a 3D distance to the goal on twelve bodies in free fall and reported that none of
	# them had arrived: after four seconds they were 78 metres BELOW the goal and about
	# fourteen from it horizontally, which is exactly where they should have been.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400, 1, 400)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -1.4, 0)

	spawner.spawn_group(&"zombie", Vector3.ZERO, 12, 4.0)

	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"player", goal, &"player")
	])

	# Six seconds. Four is enough for eleven of the twelve and leaves one straggler
	# that separation shoved wide of the ring — which is the behaviour working, not
	# failing, and a test sized to the fast ones would have called it a bug.
	for i in 360:
		spawner.tick(1.0 / 60.0)

	var closest := INF
	var npcs := spawner.all_npcs()

	for a in npcs:
		for b in npcs:
			if a.instance_id != b.instance_id:
				# HORIZONTALLY. A 3D distance calls two capsules stacked one on the
				# other's head "1.8 metres apart", which is the one arrangement this
				# check exists to catch — and it is the arrangement that actually
				# happens, because a crowd converging on a point climbs itself.
				var between := a.position() - b.position()
				between.y = 0.0
				closest = minf(closest, between.length())

	_check(npcs.size() == 12, "twelve of them arrive as twelve")
	_check(
		closest > 0.5,
		"and none of them is standing inside another",
		"closest pair %.2f m apart on the floor" % closest
	)

	var arrived := 0

	for npc in npcs:
		# Horizontally. An NPC's height is the ground's business and a 3D distance here
		# measures the floor as much as the walking.
		var to_goal := npc.position() - goal
		to_goal.y = 0.0

		if to_goal.length() < 20.0:
			arrived += 1

	_check(
		arrived == 12,
		"and separation did not stop them arriving",
		"%d of 12; equal weights give a horde that mills about outside the door" % arrived
	)

	floor_body.queue_free()
	spawner.queue_free()
	_done()


## A fake of the one cvar shape [method DotNpcAiSkill.bind_cvars] relies on, so this suite
## proves the binding without dot-server — which is not a dependency of this addon.
class FakeCvar:
	extends RefCounted

	signal changed(old_value: String, new_value: String)

	var cvar_name := ""
	var value := ""
	var validator: Callable = Callable()
	var ranged := false

	func get_string() -> String:
		return value

	func with_range(_lo: float, _hi: float) -> FakeCvar:
		ranged = true
		return self

	func with_validator(check: Callable) -> FakeCvar:
		validator = check
		return self

	## What a console does: validate, store, announce.
	func set_value(text: String) -> bool:
		if validator.is_valid():
			var checked: Variant = validator.call(text)
			if checked is DotResult and not (checked as DotResult).ok:
				return false
		var old := value
		value = text
		changed.emit(old, text)
		return true


func _test_server_skill() -> void:
	_section("a server's skill, over each character")

	var normal := DotNpcAiCharacter.normal().with_seed(4242)
	var skill := DotNpcAiSkill.new()

	var same := skill.apply(normal)
	_check(
		is_equal_approx(same.reaction_time, normal.reaction_time)
			and is_equal_approx(same.aim_accuracy, normal.aim_accuracy),
		"at skill 0 a character is as authored"
	)
	_check(same != normal, "and a copy, so the authored one survives every change")

	skill.set_skill(1.0)
	var best := skill.apply(normal)
	_check(
		best.reaction_time < normal.reaction_time and best.aim_accuracy > normal.aim_accuracy,
		"turning it up makes an NPC quicker and more accurate",
		"%.2fs, %.2f" % [best.reaction_time, best.aim_accuracy]
	)
	_check(
		best.alertness > normal.alertness and best.memory_time > normal.memory_time,
		"and more alert, with a longer memory"
	)
	_check(
		is_equal_approx(best.aggression, normal.aggression)
			and is_equal_approx(best.self_preservation, normal.self_preservation)
			and is_equal_approx(best.vengefulness, normal.vengefulness),
		"but its personality is left alone",
		"a coward that turned brave on a hard server is a different game"
	)
	_check(best.seed_value == 4242, "and it keeps its own seed")

	# A kind authored BETTER than the preset at the end of the scale. A plain lerp toward
	# nightmare would make it slower as skill went up.
	var quick := DotNpcAiCharacter.normal()
	quick.reaction_time = 0.06
	_check(
		is_equal_approx(skill.apply(quick).reaction_time, 0.06),
		"turning skill up never makes a kind worse at what it was already best at",
		"%.3fs" % skill.apply(quick).reaction_time
	)

	skill.set_skill(-1.0)
	var worst := skill.apply(normal)
	_check(
		is_equal_approx(worst.reaction_time, DotNpcAiCharacter.easy().reaction_time),
		"and all the way down reacts like the easy preset",
		"%.2fs" % worst.reaction_time
	)

	skill.set_skill(0.0)
	skill.set_reaction_scale(2.0)
	_check(
		is_equal_approx(skill.apply(normal).reaction_time, normal.reaction_time * 2.0),
		"the reaction scale is a multiplier on its own, separate from skill"
	)

	skill.set_reaction_scale(0.1)
	_check(
		is_equal_approx(skill.apply(DotNpcAiCharacter.nightmare()).reaction_time, 0.05),
		"and the floor stops it reaching an instant reaction",
		"%.3fs" % skill.apply(DotNpcAiCharacter.nightmare()).reaction_time
	)

	var scripted := DotNpcAiCharacter.normal()
	scripted.reaction_time = 0.0
	_check(
		is_zero_approx(skill.apply(scripted).reaction_time),
		"but a scripted NPC authored with no reaction time is not made to hesitate"
	)

	var before := skill.revision
	skill.set_reaction_scale(0.1)
	_check(skill.revision == before, "setting a value it already has is not a change")
	skill.set_reaction_scale(1.0)
	_check(skill.revision == before + 1, "and a real change bumps the revision once")

	_check(
		is_equal_approx(float(DotNpcAiSkill.parse_skill("hard").value), 0.5)
			and is_equal_approx(float(DotNpcAiSkill.parse_skill("Nightmare").value), 1.0),
		"an operator may type a level by name"
	)
	_check(
		is_equal_approx(float(DotNpcAiSkill.parse_skill("5").value), 1.0),
		"a number out of range is clamped rather than refused"
	)
	_check(not DotNpcAiSkill.parse_skill("hrad").ok, "and a typo is refused")

	# --- The cvars -----------------------------------------------------------------
	var bound := DotNpcAiSkill.new()
	var made: Array = []
	var preset_values := {DotNpcAiSkill.CVAR_SKILL: "hard"}

	var add := func(cvar_name: String, default_value: String, _description: String, _flags: int) -> Object:
		var cv := FakeCvar.new()
		cv.cvar_name = cvar_name
		# Already set by argv before the module registered it, which is the case a
		# binding that only listened for changes would miss.
		cv.value = str(preset_values.get(cvar_name, default_value))
		made.append(cv)
		return cv

	var returned := bound.bind_cvars(add)
	_check(made.size() == 3 and returned.size() == 3, "three cvars are registered")
	_check(
		is_equal_approx(bound.skill, 0.5),
		"and a value set before they were bound is read back",
		"%.2f" % bound.skill
	)

	var by_name := {}
	for cv in made:
		by_name[(cv as FakeCvar).cvar_name] = cv

	(by_name[DotNpcAiSkill.CVAR_REACTION_SCALE] as FakeCvar).set_value("0.5")
	_check(is_equal_approx(bound.reaction_scale, 0.5), "a change at the console reaches the skill")
	_check(
		(by_name[DotNpcAiSkill.CVAR_REACTION_MIN] as FakeCvar).ranged,
		"the numeric ones are given a range"
	)
	_check(
		not (by_name[DotNpcAiSkill.CVAR_SKILL] as FakeCvar).set_value("hrad")
			and is_equal_approx(bound.skill, 0.5),
		"and npc_skill refuses a typo at the console instead of ignoring it"
	)

	var holder := Node.new()
	bound.attach(holder)
	_check(DotNpcAiSkill.of(holder) == bound, "a skill attached to a director is found on it")
	var bare := Node.new()
	_check(DotNpcAiSkill.of(bare) == null, "and a director without one has none")
	holder.free()
	bare.free()

	_done()


func _test_brain_under_a_skill() -> void:
	_section("a brain under a server's skill")

	var spawner := _spawner()
	var skill := DotNpcAiSkill.new()
	skill.attach(spawner)

	var npc := spawner.spawn(&"searcher", Vector3.ZERO)
	var brain := npc.brain as DotNpcAiBrain

	_check(brain.skill == skill, "a brain finds the server's skill on its director")
	_check(
		brain.character != null and brain.character.id == &"normal",
		"and a character named in the catalogue is the one it has"
	)
	_check(
		brain.character.seed_value == npc.seed and npc.seed > 1,
		"seeded from the NPC's stable seed, not its object id",
		"seed %d, character %d" % [npc.seed, brain.character.seed_value]
	)
	_check(brain.context.character == brain.character, "and the tree sees the same one")

	var authored := brain.character.reaction_time

	skill.set_skill(1.0)
	spawner.tick(1.0 / 60.0)
	_check(
		brain.character.reaction_time < authored,
		"turning the server up reaches a live NPC on its next tick",
		"%.2fs from %.2fs" % [brain.character.reaction_time, authored]
	)
	_check(
		npc.sight_scale > 1.0,
		"and its alertness reaches dot-npc's senses, which nothing read before",
		"sight scale %.2f" % npc.sight_scale
	)

	skill.set_skill(0.0)
	spawner.tick(1.0 / 60.0)
	_check(
		is_equal_approx(brain.character.reaction_time, authored),
		"and turning it back comes back to what was authored, not to the last change"
	)

	var vengeful := DotNpcAiCharacter.normal()
	vengeful.vengefulness = 1.0
	vengeful.memory_time = 5.0
	brain.character = vengeful
	spawner.tick(1.0 / 60.0)
	_check(
		brain.base_character != null and brain.base_character.vengefulness == 1.0,
		"a character a game assigns mid-life is adopted rather than overwritten"
	)

	# --- Remembering, searching, giving up ------------------------------------------
	var hidden := npc.def.faction
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"player", Vector3(0, 0, -8), &"player")
	])

	for i in 30:
		spawner.tick(1.0 / 60.0)

	_check(npc.has_target(), "the searcher acquires somebody")
	_check(brain.remembers_target(), "and remembers where they are")

	# Out of sight without leaving: the same id, the same place, on the NPC's own side so
	# the senses cannot perceive it — which is a player behind a wall, as far as dot-npc
	# can tell. Emptying the candidates instead would also make the position unknowable,
	# and a game's players do not stop existing when they hide.
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"player", Vector3(0, 0, -8), hidden)
	])

	# The grace (3 s), and a little.
	for i in 200:
		spawner.tick(1.0 / 60.0)

	_check(not npc.has_target(), "once the grace has run out it is no longer chasing")
	_check(brain.remembers_target(), "but it still remembers where they were")

	var searches_before := int(brain.get(&"searches"))

	for i in 60:
		spawner.tick(1.0 / 60.0)

	_check(
		int(brain.get(&"searches")) > searches_before,
		"so it searches there rather than standing about"
	)

	# Look-round for normal's 5 s memory is 2 s. Four is plenty.
	for i in 240:
		spawner.tick(1.0 / 60.0)

	_check(not brain.remembers_target(), "and after looking round it forgets")
	_check(int(brain.get(&"idles")) > 0, "and goes back to doing nothing")

	# --- Being hurt by something it cannot see ---------------------------------------
	var shooter_at := npc.position() + Vector3(12, 0, 0)
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"sniper", shooter_at, hidden)
	])

	var start := npc.position()
	spawner.damage(npc.instance_id, 1.0, &"sniper")

	_check(
		brain.last_known_position().distance_to(shooter_at) < 0.01,
		"hurt from out of sight, it knows where the hurt came from"
	)

	for i in 120:
		spawner.tick(1.0 / 60.0)

	var was := start - shooter_at
	var now := npc.position() - shooter_at
	was.y = 0.0
	now.y = 0.0
	_check(
		now.length() < was.length() - 3.0,
		"and goes to look rather than carrying on",
		"%.1f m from %.1f m" % [now.length(), was.length()]
	)

	# --- Vengeance -------------------------------------------------------------------
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"near", npc.position() + Vector3(0, 0, -4), &"player"),
		# Not much further than the other. The senses' stickiness switches BACK to a rival
		# 40% nearer than the committed target, and that rule is right: the first version
		# of this check put the attacker half as far again away, the NPC had walked toward
		# the nearer one, and the senses took the vengeance back on the next pass.
		DotNpcSenses.Candidate.new(&"far", npc.position() + Vector3(0, 0, 4.5), &"player"),
	])

	for i in 5:
		spawner.tick(1.0 / 60.0)

	_check(npc.target_id == &"near", "it commits to the nearer of two")

	spawner.damage(npc.instance_id, 1.0, &"far")
	spawner.tick(1.0 / 60.0)
	_check(
		npc.target_id == &"far",
		"and a vengeful one turns on whoever hurt it",
		"target %s" % String(npc.target_id)
	)

	var forgiving := DotNpcAiCharacter.normal()
	forgiving.vengefulness = 0.0
	brain.character = forgiving

	for i in 30:
		spawner.tick(1.0 / 60.0)

	var held := npc.target_id
	spawner.damage(npc.instance_id, 1.0, &"near" if held == &"far" else &"far")
	spawner.tick(1.0 / 60.0)
	_check(npc.target_id == held, "and one with no vengefulness does not")

	_world.remove_child(spawner)
	spawner.free()
	_done()


## A node that runs for ever and counts how often it was told to stop.
class Endless:
	extends DotNpcAiNode

	var aborted := 0

	func _tick(_ctx: DotNpcAiContext) -> Status:
		return Status.RUNNING

	func _abort(_ctx: DotNpcAiContext) -> void:
		aborted += 1


## Something a squad can hold, with the report method a brain has.
class FakeMember:
	extends RefCounted

	var reports: Array = []

	func _squad_report(enemy: StringName, position: Vector3, _velocity: Vector3, _at: float) -> bool:
		reports.append([enemy, position])
		return true


func _test_conditions() -> void:
	_section("conditions, and the interrupt that reads them")

	var c := DotNpcAiConditions.new()
	c.set_flag(DotNpcAiConditions.SEE_ENEMY | DotNpcAiConditions.LIGHT_DAMAGE)
	_check(c.has(DotNpcAiConditions.SEE_ENEMY), "a condition set is a condition had")
	_check(
		c.has(DotNpcAiConditions.HEAR_DANGER | DotNpcAiConditions.LIGHT_DAMAGE)
			and not c.has_all(DotNpcAiConditions.HEAR_DANGER | DotNpcAiConditions.LIGHT_DAMAGE),
		"has is any of them, has_all is all of them"
	)
	_check(c.became(DotNpcAiConditions.SEE_ENEMY), "and it became true this tick")

	c.begin_tick()
	_check(not c.has(DotNpcAiConditions.SEE_ENEMY), "a new tick starts with nothing")
	c.set_flag(DotNpcAiConditions.SEE_ENEMY)
	_check(
		c.has(DotNpcAiConditions.SEE_ENEMY) and not c.became(DotNpcAiConditions.SEE_ENEMY),
		"and one still true is had, but did not become"
	)

	var ctx := _context()
	var endless := Endless.new(&"walk")
	var guard := DotNpcAiDecorator.Interrupt.new(&"until danger", endless, DotNpcAiConditions.HEAR_DANGER)

	_check(guard.tick(ctx) == DotNpcAiNode.Status.RUNNING, "an interrupt runs its child")
	_check(endless.is_running, "which is running")

	ctx.conditions.begin_tick()
	ctx.conditions.set_flag(DotNpcAiConditions.HEAR_DANGER)
	_check(guard.tick(ctx) == DotNpcAiNode.Status.FAILURE, "until the condition appears, when it fails")
	_check(endless.aborted == 1 and not endless.is_running, "and the child is told it was stopped")

	var flinch := Endless.new(&"flinch")
	var on_new := DotNpcAiDecorator.Interrupt.new(
		&"flinch", flinch, DotNpcAiConditions.LIGHT_DAMAGE, true
	)
	ctx.conditions.begin_tick()
	ctx.conditions.set_flag(DotNpcAiConditions.LIGHT_DAMAGE)
	ctx.conditions.begin_tick()
	ctx.conditions.set_flag(DotNpcAiConditions.LIGHT_DAMAGE)
	_check(
		on_new.tick(ctx) == DotNpcAiNode.Status.RUNNING,
		"only_new ignores a condition that was already true",
		"a flinch must not be interrupted by the damage it is reacting to"
	)
	_done()


func _test_memory() -> void:
	_section("memory of enemies")

	var m := DotNpcAiMemory.new()
	m.forget_after = 5.0

	m.sighted(&"a", Vector3(0, 0, 0), 0.0)
	m.sighted(&"a", Vector3(1, 0, 0), 0.25)
	m.sighted(&"a", Vector3(2, 0, 0), 0.5)

	var entry := m.get_entry(&"a", 0.5)
	_check(entry != null and entry.velocity.x > 2.0, "successive sightings give a velocity",
		"%.2f m/s" % (entry.velocity.x if entry != null else 0.0))

	var ahead := m.predicted(&"a", 1.5, 1.0)
	_check(ahead.x > 2.0 + 2.0, "a lost enemy is predicted along it",
		"x %.2f" % ahead.x)
	_check(
		is_equal_approx(m.predicted(&"a", 1.5, 0.0).x, 2.0),
		"and a lead of nothing is where it was last seen"
	)

	var far := m.predicted(&"a", 4.5, 1.0)
	_check(
		far.x - 2.0 <= m.max_lead * entry.velocity.length() + 0.001,
		"the prediction stops growing after max_lead",
		"%.2f m ahead" % (far.x - 2.0)
	)

	m.heard(&"a", Vector3(50, 0, 0), 0.5)
	_check(m.get_entry(&"a", 0.5).position.x == 2.0, "a sound never overrides a sighting from the same moment")

	_check(
		not m.informed(&"a", Vector3(9, 0, 0), Vector3.ZERO, 0.2, 0.6),
		"an older squad report is not news"
	)
	_check(
		m.informed(&"b", Vector3(9, 0, 0), Vector3(0, 0, 3), 0.6, 0.6)
			and m.get_entry(&"b", 0.6).is_rumour(),
		"a new one is, and is marked second-hand"
	)
	_check(m.freshest(0.6).id == &"b", "the freshest is what was learned last")

	m.hurt_by(&"c", Vector3(-4, 0, 0), 12.0, 0.7)
	_check(
		m.get_entry(&"c", 0.7).hurt_me == 12.0
			and m.get_entry(&"c", 0.7).source == DotNpcAiMemory.Source.DAMAGE,
		"being hurt is remembered, with how much"
	)

	_check(m.get_entry(&"a", 6.0) == null, "and everything is forgotten after forget_after")
	_check(m.size() == 2, "on read, not in a sweep", "%d left" % m.size())

	var never := DotNpcAiMemory.new()
	never.forget_after = 0.0
	never.sighted(&"x", Vector3.ZERO, 1.0)
	_check(never.get_entry(&"x", 1.0) == null, "a memory of zero remembers nothing, not everything")
	_done()


func _test_sounds() -> void:
	_section("sounds")

	var board := DotNpcAiSounds.new()
	var shot := board.emit(DotNpcAiSounds.Kind.COMBAT, Vector3(10, 0, 0), 20.0, 1.0, 0.5, &"p1")

	_check(board.audible(Vector3.ZERO, 1.0).size() == 1, "a shot is heard inside its radius")
	_check(board.audible(Vector3(40, 0, 0), 1.0).size() == 0, "and not outside it")
	_check(
		board.audible(Vector3(-15, 0, 0), 1.0, 1.0).size() == 0
			and board.audible(Vector3(-15, 0, 0), 1.0, 1.5).size() == 1,
		"an alert listener hears further than a dull one"
	)
	_check(board.audible(Vector3.ZERO, 1.0, 1.0, shot).is_empty(), "a sound already heard is not heard again")
	_check(board.audible(Vector3.ZERO, 2.0).is_empty(), "and one that has passed is not heard at all")

	var grenade := board.emit(DotNpcAiSounds.Kind.DANGER, Vector3.ZERO, 15.0, 2.0, 3.0, &"", 4.0)
	var found := board.audible(Vector3(10, 0, 0), 2.0, 1.0, shot)
	_check(
		found.size() == 1 and found[0].id == grenade and found[0].extent == 4.0,
		"a danger carries how far it reaches as well as how far it is heard"
	)

	for i in DotNpcAiSounds.CAPACITY + 20:
		board.emit(DotNpcAiSounds.Kind.WORLD, Vector3.ZERO, 1.0, 2.0, 60.0)
	_check(board.size() <= DotNpcAiSounds.CAPACITY, "the list is bounded",
		"%d kept" % board.size())
	_done()


func _test_squad() -> void:
	_section("squads and slots")

	var squad := DotNpcAiSquad.new(&"alpha")
	var a := FakeMember.new()
	var b := FakeMember.new()
	var c := FakeMember.new()
	squad.join(a)
	squad.join(b)
	squad.join(c)

	_check(squad.size() == 3, "three join")
	_check(squad.claim(&"attack:p", a, 2) and squad.claim(&"attack:p", b, 2), "two take the two attack slots")
	_check(not squad.claim(&"attack:p", c, 2), "and the third is refused")
	_check(squad.claim(&"attack:p", a, 2), "a holder asking again keeps it")

	squad.leave(a)
	_check(squad.claim(&"attack:p", c, 2), "when one leaves its slot is the next one's")

	var reported := squad.report(b, &"p", Vector3(1, 2, 3), Vector3.ZERO, 0.0)
	_check(reported == 1 and c.reports.size() == 1 and b.reports.is_empty(),
		"a report reaches every other member and not the one who made it")

	# A member freed without leaving — which is how a world ends — must not keep its slot.
	var squad2 := DotNpcAiSquad.new(&"beta")
	var keep := FakeMember.new()
	squad2.join(keep)
	var gone := FakeMember.new()
	squad2.join(gone)
	squad2.claim(&"attack:p", gone, 1)
	gone = null
	_check(squad2.claim(&"attack:p", keep, 1), "a freed member's slot is free",
		"a squad whose slots belonged to the dead never attacks again")
	_check(squad2.size() == 1, "and it is no longer a member")

	# The per-tick memo the surround shares: kept for one clock reading, gone at the next.
	squad2.remember(&"k", 5.0, 42)
	_check(squad2.memo(&"k", 5.0) == 42 and squad2.memo(&"k", 5.5) == null and squad2.memo(&"k", 5.0) == null,
		"a squad's memo answers for one clock reading and forgets at the next")
	_check(squad2.holder_ids(&"attack:p").size() == 1, "holder_ids lists who holds a slot")

	var registry := DotNpcAiSquads.new()
	_check(registry.squad(&"x") == registry.squad(&"x"), "one name is one squad")
	_check(registry.prune() == 1, "and an empty one is pruned")
	_done()


func _test_tactics() -> void:
	_section("tactics")

	var center := Vector3.ZERO
	var point := DotNpcAiTactics.ring_point(center, Vector3(10, 0, 0), 4.0)
	_check(point.distance_to(Vector3(4, 0, 0)) < 0.01, "a ring point holds the NPC's own bearing")

	# The enemy faces +X, so behind it is -X. An NPC beside it works round, a step at a time.
	var at := Vector3(0, 0, 4)
	var start := DotNpcAiTactics.angle_from_behind(center, Vector3(1, 0, 0), at)

	for i in 30:
		at = DotNpcAiTactics.ring_point(center, at, 4.0, Vector3(1, 0, 0), 0.1)

	var finish := DotNpcAiTactics.angle_from_behind(center, Vector3(1, 0, 0), at)
	_check(finish < start and finish < 0.05, "flanking works round to the back",
		"%.2f rad from behind, from %.2f" % [finish, start])
	_check(absf(at.length() - 4.0) < 0.01, "and stays on the ring")

	# Shared out in the order they stand: whoever is furthest round one way gets the place
	# furthest round that way, so no two cross to reach theirs.
	var standing := [Vector3(0, 0, 5), Vector3(5, 0, 0), Vector3(0, 0, -5)]
	var shared := DotNpcAiTactics.spread_bearings(Vector3.ZERO, 0.0, standing, 0.5)
	_check(
		shared[2] < shared[1] and shared[1] < shared[0]
			and is_equal_approx(shared[0] - shared[1], 0.5),
		"places round a ring are shared out in the order they stand, a step apart",
		str(shared)
	)

	var spots := PackedVector3Array([Vector3(1, 0, 0), Vector3(5, 0, 0), Vector3(3, 0, 0)])
	_check(
		DotNpcAiTactics.best_of(spots, func(p: Vector3, _i: int) -> float: return p.x) == 1,
		"the best of a set is the highest score"
	)
	_check(
		DotNpcAiTactics.best_of(spots, func(_p: Vector3, _i: int) -> float: return -INF) == -1,
		"and a set where everything is ruled out has none"
	)
	_done()


func _floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -1.4, 0)
	return floor_body


func _flat(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()


func _test_brain_perception() -> void:
	_section("a brain senses, hears, turns and predicts")

	var floor_body := _floor()
	var spawner := _spawner()
	var board := DotNpcAiSounds.new()
	board.attach(spawner)

	var npc := spawner.spawn(&"searcher", Vector3.ZERO)
	var brain := npc.brain as DotNpcAiBrain
	var hidden := npc.def.faction
	var ctx := brain.context

	spawner.set_candidates([DotNpcSenses.Candidate.new(&"p", Vector3(0, 0, -8), &"player")])
	spawner.tick(1.0 / 60.0)
	_check(ctx.has_condition(DotNpcAiConditions.SEE_ENEMY), "seeing somebody is SEE_ENEMY")
	_check(ctx.has_condition(DotNpcAiConditions.NEW_ENEMY), "and the first sight is NEW_ENEMY")
	spawner.tick(1.0 / 60.0)
	_check(not ctx.has_condition(DotNpcAiConditions.NEW_ENEMY), "and only the first")

	spawner.set_candidates([DotNpcSenses.Candidate.new(&"p", Vector3(0, 0, -8), hidden)])
	spawner.tick(1.0 / 60.0)
	_check(ctx.has_condition(DotNpcAiConditions.ENEMY_OCCLUDED), "out of sight but held is ENEMY_OCCLUDED")

	for i in 200:
		spawner.tick(1.0 / 60.0)
	_check(not npc.has_target(), "(the grace runs out)")

	spawner.damage(npc.instance_id, npc.def.max_health * 0.4, &"")
	spawner.tick(1.0 / 60.0)
	_check(
		ctx.has_condition(DotNpcAiConditions.LIGHT_DAMAGE | DotNpcAiConditions.HEAVY_DAMAGE)
			and ctx.conditions.has_all(DotNpcAiConditions.LIGHT_DAMAGE | DotNpcAiConditions.HEAVY_DAMAGE),
		"a big hit is LIGHT and HEAVY damage"
	)
	spawner.damage(npc.instance_id, npc.def.max_health * 0.35, &"")
	spawner.tick(1.0 / 60.0)
	_check(ctx.has_condition(DotNpcAiConditions.LOW_HEALTH), "and under a third of its health is LOW_HEALTH")

	# Forget everything the earlier part learned, so what follows is the sound's doing.
	brain.memory.clear()

	# --- Hearing -------------------------------------------------------------
	var shot_at := npc.position() + Vector3(14, 0, 0)
	spawner.set_candidates([DotNpcSenses.Candidate.new(&"q", shot_at, hidden)])
	board.emit(DotNpcAiSounds.Kind.COMBAT, shot_at, 30.0, spawner.now(), 0.5, &"q")
	spawner.tick(1.0 / 60.0)
	_check(ctx.has_condition(DotNpcAiConditions.HEAR_COMBAT), "a shot in range is HEAR_COMBAT")
	_check(
		brain.memory.get_entry(&"q", ctx.now) != null
			and brain.memory.get_entry(&"q", ctx.now).source == DotNpcAiMemory.Source.SOUND,
		"and the shooter is remembered as heard, not seen"
	)
	spawner.tick(1.0 / 60.0)
	_check(not ctx.has_condition(DotNpcAiConditions.HEAR_COMBAT), "a sound is heard once")

	var before := _flat(npc.position(), shot_at)
	for i in 120:
		spawner.tick(1.0 / 60.0)
	_check(
		_flat(npc.position(), shot_at) < before - 3.0,
		"it goes to look where the shot came from",
		"%.1f m from %.1f m" % [_flat(npc.position(), shot_at), before]
	)

	# --- Danger --------------------------------------------------------------
	brain.memory.clear()
	spawner.set_candidates([])
	var landed := npc.position() + Vector3(0.5, 0, 0)
	board.emit(DotNpcAiSounds.Kind.DANGER, landed, 20.0, spawner.now(), 3.0, &"", 4.0)
	spawner.tick(1.0 / 60.0)
	_check(ctx.has_condition(DotNpcAiConditions.HEAR_DANGER), "a grenade landing is HEAR_DANGER")

	for i in 90:
		spawner.tick(1.0 / 60.0)
	_check(
		_flat(npc.position(), landed) > 4.0,
		"and it is out of the blast before it goes off",
		"%.1f m from it" % _flat(npc.position(), landed)
	)
	_check(int(brain.get(&"flees")) > 0, "because fleeing came first in its tree")

	for i in 150:
		spawner.tick(1.0 / 60.0)
	_check(not brain.in_danger(), "and the danger is over when it is over")

	# --- Turning -------------------------------------------------------------
	var turner := DotNpcAiCharacter.normal()
	turner.view_turn_deg = 90.0
	turner.view_factor = 1.0
	brain.character = turner
	spawner.tick(1.0 / 60.0)

	var facing_before := npc.facing()
	brain._facing_at_tick = facing_before
	brain.face(-facing_before)
	var turned := rad_to_deg(facing_before.angle_to(npc.facing()))
	_check(
		turned > 0.0 and turned <= 90.0 / 60.0 + 0.05,
		"an NPC turns no faster than its character can",
		"%.2f deg in one tick at 90 deg/s" % turned
	)

	# --- Prediction ----------------------------------------------------------
	brain.memory.clear()
	var tactical := DotNpcAiCharacter.nightmare()
	tactical.memory_time = 6.0
	brain.character = tactical
	var runner := npc.position() + Vector3(0, 0, -6)
	for i in 30:
		runner += Vector3(4.0 / 60.0, 0, 0)
		spawner.set_candidates([DotNpcSenses.Candidate.new(&"r", runner, &"player")])
		spawner.tick(1.0 / 60.0)

	spawner.set_candidates([DotNpcSenses.Candidate.new(&"r", runner, hidden)])
	var entry := brain.memory.get_entry(&"r", ctx.now)
	_check(entry != null and entry.velocity.x > 2.0, "a runner's speed is measured while it is seen",
		"%.2f m/s" % (entry.velocity.x if entry != null else 0.0))

	var goal := brain.memory.predict_entry(entry, ctx.now + 1.0, brain.tactics())
	_check(
		goal.x > runner.x + 2.0,
		"and a tactical NPC looks for it where it was going, not where it was",
		"%.1f m ahead of the last sighting" % (goal.x - runner.x)
	)

	_world.remove_child(spawner)
	spawner.free()
	floor_body.queue_free()
	_done()


func _test_squad_on_real_npcs() -> void:
	_section("a squad on real NPCs")

	var floor_body := _floor()
	var spawner := _spawner()
	var squads := DotNpcAiSquads.new()
	squads.attach(spawner)

	# A spotter in range and a second one forty metres away, out of its sight.
	var spotter := spawner.spawn(&"soldier", Vector3(0, 0, 0))
	var distant := spawner.spawn(&"soldier", Vector3(40, 0, 0))
	var a := spotter.brain as DotNpcAiBrain
	var b := distant.brain as DotNpcAiBrain

	_check(a.squad != null and a.squad == b.squad, "a squad named in the catalogue is joined")
	_check(a.character.id == &"hard", "with the catalogue's character")

	spawner.set_candidates([DotNpcSenses.Candidate.new(&"p", Vector3(-6, 0, 0), &"player")])
	for i in 3:
		spawner.tick(1.0 / 60.0)

	_check(a.npc.has_target() and not b.npc.has_target(), "only the near one can see them")
	var told := b.memory.get_entry(&"p", b.context.now)
	_check(told != null and told.source == DotNpcAiMemory.Source.SQUAD,
		"but the far one knows where they are, second-hand")

	var start := _flat(distant.position(), Vector3(-6, 0, 0))
	for i in 120:
		spawner.tick(1.0 / 60.0)
	_check(
		_flat(distant.position(), Vector3(-6, 0, 0)) < start - 4.0,
		"and comes to help without ever having seen them",
		"%.1f m from %.1f m" % [_flat(distant.position(), Vector3(-6, 0, 0)), start]
	)
	_world.remove_child(spawner)
	spawner.free()

	# --- Slots, the ring, and the next one stepping in ---------------------------------
	var spawner2 := _spawner()
	DotNpcAiSquads.new().attach(spawner2)

	var player := Vector3(0, 0, -12)
	var soldiers: Array[DotNpcInstance] = []
	for x in [-3.0, 0.0, 3.0, 6.0]:
		soldiers.append(spawner2.spawn(&"soldier", Vector3(x, 0, 0)))

	spawner2.set_candidates([DotNpcSenses.Candidate.new(&"p", player, &"player")])

	for i in 360:
		spawner2.tick(1.0 / 60.0)

	var holders: Array[DotNpcInstance] = []
	for s in soldiers:
		if (s.brain as DotNpcAiBrain).holds_attack_slot():
			holders.append(s)

	_check(holders.size() == 1, "one attack slot, one attacker", "%d hold it" % holders.size())

	var on_ring := 0
	for s in soldiers:
		if not holders.has(s) and absf(_flat(s.position(), player) - 4.0) < 1.5:
			on_ring += 1
	_check(on_ring == 3, "and the rest wait on the ring rather than in a queue",
		"%d of 3 on it" % on_ring)

	# Apart, not merely on the ring. The first surround passed the check above with all
	# three waiters on one spot of it, forty centimetres apart: each walked at "directly
	# behind" and they arrived together. A trace, not a check, showed it — this is the check.
	var closest := INF
	for s1 in soldiers:
		for s2 in soldiers:
			if s1 != s2 and not holders.has(s1) and not holders.has(s2):
				closest = minf(closest, _flat(s1.position(), s2.position()))
	_check(closest > 1.2, "and spread round it rather than heaped on one spot of it",
		"closest pair %.2f m apart" % closest)

	var attacker := holders[0] if not holders.is_empty() else soldiers[0]
	var look := attacker.position() - player
	look.y = 0.0
	var behind := 0
	for s in soldiers:
		if s != attacker and DotNpcAiTactics.angle_from_behind(player, look.normalized(), s.position()) < PI * 0.5:
			behind += 1
	_check(behind >= 1, "and they have worked round the side the player is not looking at",
		"%d behind the player's shoulder line" % behind)

	spawner2.damage(attacker.instance_id, 99999.0, &"p")
	for i in 30:
		spawner2.tick(1.0 / 60.0)

	var next := 0
	for s in spawner2.all_npcs():
		if (s.brain as DotNpcAiBrain).holds_attack_slot():
			next += 1
	_check(next == 1, "and when the attacker falls, the next one steps in")

	# --- Cover, one NPC per spot -----------------------------------------------------
	var builder := DotNpcNavBuilder.new()
	builder.spacing = 2.0
	builder.add_floor(AABB(Vector3(-12, 0, -12), Vector3(24, 0, 24)), 0.0)
	builder.add_obstacle(AABB(Vector3(-1, 0, -10), Vector3(2, 3, 20)))
	var nav := builder.build(&"cover", "digest")
	var adopted := spawner2.set_nav_data(nav)

	var threat := Vector3(-10, 0, 0)
	var survivors := spawner2.all_npcs()
	var first := (survivors[0].brain as DotNpcAiBrain).find_cover(threat)
	var second := (survivors[1].brain as DotNpcAiBrain).find_cover(threat)
	_check(adopted.ok and first != Vector3.INF, "an NPC finds cover from a threat")
	var spot_index := nav.cover_positions.find(first)
	var covers := spot_index >= 0 and nav.cover_normals[spot_index].dot(
		(threat - first).normalized()
	) >= 0.25
	_check(covers, "with its wall between it and the threat", "spot %s" % str(first))
	_check(second != Vector3.INF and second.distance_to(first) > 0.5,
		"and its squadmate takes a different spot rather than the same one")

	_world.remove_child(spawner2)
	spawner2.free()
	floor_body.queue_free()
	_done()


func _test_heatmap() -> void:
	_section("learning where players go")

	var heat := DotNpcAiHeatmap.new()
	heat.cell_size = 3.0
	heat.half_life = 10.0

	for i in 20:
		heat.record(DotNpcAiHeatmap.TRAFFIC, Vector3(10, 0, 0), 0.0)
	heat.record(DotNpcAiHeatmap.TRAFFIC, Vector3(-10, 0, 0), 0.0)

	_check(
		is_equal_approx(heat.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(10.5, 0, 0.5), 0.0), 20.0),
		"recording adds up in a cell"
	)
	_check(
		is_equal_approx(heat.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(10, 0, 0), 10.0), 10.0),
		"and halves every half-life"
	)

	var hot := heat.hottest(DotNpcAiHeatmap.TRAFFIC, Vector3.ZERO, 30.0, 0.0, 2)
	_check(hot.size() == 2 and hot[0].distance_to(Vector3(10.5, 0, 1.5)) < 3.0,
		"the hottest place comes first", str(hot))
	_check(heat.hottest(DotNpcAiHeatmap.TRAFFIC, Vector3(100, 0, 0), 5.0, 0.0).is_empty(),
		"and nothing is hot where nobody has been")

	# A corridor: traffic heavier to the east. Somebody waiting in it watches the east.
	var lane := DotNpcAiHeatmap.new()
	for x in range(0, 8):
		for i in x + 1:
			lane.record(DotNpcAiHeatmap.TRAFFIC, Vector3(x * 3.0 + 1.0, 0, 1.0), 0.0)
	var flow := lane.flow_at(DotNpcAiHeatmap.TRAFFIC, Vector3(10, 0, 1), 0.0)
	_check(flow.x > 0.9, "the flow points to where the traffic comes from", str(flow))

	var path := "user://npc_ai_selftest_heat.json"
	var saved := heat.save(path, 0.0)
	var loaded := DotNpcAiHeatmap.load_from(path, 500.0)
	_check(saved.ok and loaded.ok, "a heat map is saved and loaded")
	_check(
		loaded.ok and is_equal_approx(
			(loaded.value as DotNpcAiHeatmap).value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(10, 0, 0), 500.0), 20.0
		),
		"carrying its weights onto a clock that started again"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(DotNpcAiHeatmap.load_from("user://never_played.json").ok, "a map nobody has played is an empty one, not an error")
	_check(not DotNpcAiHeatmap.from_dictionary({"cell_size": 0.0}).ok, "a cell size of nothing is refused")

	var small := DotNpcAiHeatmap.new()
	small.capacity = 4
	for i in 10:
		small.record(DotNpcAiHeatmap.TRAFFIC, Vector3(i * 10.0, 0, 0), 0.0, float(i + 1))
	_check(small.cell_count(DotNpcAiHeatmap.TRAFFIC) <= 5, "and it is bounded, the coldest going first")
	_check(small.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(90, 0, 0), 0.0) == 10.0, "keeping the hottest")

	# The keeper: per map, across a change of map and back, and a reload that does not save.
	var dir := "user://npc_ai_selftest_heat"
	var keeper := DotNpcAiHeatKeeper.new(dir, "test")
	keeper.save_every = 1000.0
	for i in 60:
		keeper.tick(1.0 / 60.0, &"a", [Vector3(3, 0, 3)], float(i) / 60.0)
	_check(keeper.heatmap.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(3, 0, 3), 1.0) > 0.5,
		"the keeper samples players on its interval")

	keeper.tick(1.0 / 60.0, &"b", [], 1.0)
	_check(keeper.map_id == &"b" and keeper.heatmap.cell_count(DotNpcAiHeatmap.TRAFFIC) == 0,
		"a new map starts with what that map has learned, not the last one's")
	keeper.tick(1.0 / 60.0, &"a", [], 1.1)
	_check(keeper.heatmap.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(3, 0, 3), 1.1) > 0.5,
		"and going back to the first map gets its learning back from disk")

	keeper.heatmap = DotNpcAiHeatmap.new()
	keeper.adopt(&"a", 1.2)
	_check(keeper.heatmap.value_at(DotNpcAiHeatmap.TRAFFIC, Vector3(3, 0, 3), 1.2) > 0.5,
		"re-adopting the map it holds reloads it without saving over the file first")

	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	_done()


func _test_ranged_and_roles() -> void:
	_section("shooting, roles and patrols on real NPCs")

	var floor_body := _floor()
	var spawner := _spawner()
	DotNpcAiSquads.new().attach(spawner)

	var a := spawner.spawn(&"soldier", Vector3(0, 0, 0))
	var b := spawner.spawn(&"soldier", Vector3(3, 0, 0))
	var ba := a.brain as DotNpcAiBrain
	var bb := b.brain as DotNpcAiBrain

	var runner := Vector3(0, 0, -15)
	for i in 30:
		runner += Vector3(5.0 / 60.0, 0, 0)
		spawner.set_candidates([DotNpcSenses.Candidate.new(&"p", runner, &"player")])
		spawner.tick(1.0 / 60.0)

	_check(ba.claim_role(DotNpcAiBrain.ROLE_SUPPRESS, 1) != bb.claim_role(DotNpcAiBrain.ROLE_SUPPRESS, 1),
		"one role of one place goes to one of two")

	var holder := ba if ba.holds_role(DotNpcAiBrain.ROLE_SUPPRESS) else bb
	var other := bb if holder == ba else ba
	spawner.set_candidates([DotNpcSenses.Candidate.new(&"q", Vector3(0, 0, 5), &"player")])
	for i in 200:
		spawner.tick(1.0 / 60.0)
	_check(other.claim_role(DotNpcAiBrain.ROLE_SUPPRESS, 1) and holder.npc.target_id == &"q",
		"and a new target lets go of every role on the old one")

	# Aim. A nightmare leads a runner by what it SAW of them.
	var shooter := DotNpcAiCharacter.nightmare()
	shooter.aim_accuracy = 1.0
	shooter.aim_skill = 1.0
	shooter.fire_throttle = 1.0
	ba.character = shooter
	var moving := Vector3(0, 0, -15)
	for i in 30:
		moving += Vector3(5.0 / 60.0, 0, 0)
		spawner.set_candidates([DotNpcSenses.Candidate.new(&"m", moving, &"player")])
		spawner.tick(1.0 / 60.0)
	var muzzle := a.position()
	var aimed := ba.aim_solution(muzzle, 30.0)
	_check(aimed.x > moving.x + 1.0, "aim leads a runner by the speed it saw",
		"aimed %.2f m ahead" % (aimed.x - moving.x))
	var before_shots := ba.shots_fired
	var _again := ba.aim_solution(muzzle, 30.0)
	_check(ba.shots_fired == before_shots + 1, "and every aim is a new shot")

	# Facing gates firing: turned away, it may not; once its turn rate brings it round, it may.
	ba._facing_at_tick = -a.facing()
	ba.face(-(moving - a.position()))
	_check(not ba.ready_to_fire(muzzle + Vector3(0, 1, 0)), "it cannot fire at what it is not facing")

	for i in 120:
		spawner.set_candidates([DotNpcSenses.Candidate.new(&"m", moving, &"player")])
		spawner.tick(1.0 / 60.0)
		ba.face(moving - a.position())
	_check(ba.ready_to_fire(a.position() + Vector3(0, 1, 0), 15.0),
		"and once it has turned to face them, it can")

	# A squadmate in the lane.
	var lane_from := a.position()
	var lane_to := lane_from + Vector3(0, 0, -20)
	b.node.global_position = lane_from + Vector3(0.2, 0, -10)
	_check(not ba.fire_lane_clear(lane_from, lane_to), "a squadmate in the lane blocks the shot")
	b.node.global_position = lane_from + Vector3(5, 0, -10)
	_check(ba.fire_lane_clear(lane_from, lane_to), "and one out of it does not")

	# A gunner, by its own tree: it backs off into its band and fires once it faces them.
	var gun := spawner.spawn(&"gunner", Vector3(-20, 0, 20))
	var bgun := gun.brain as DotNpcAiBrain
	var still := gun.position() + Vector3(0, 0, -4)
	for i in 240:
		spawner.set_candidates([DotNpcSenses.Candidate.new(&"s", still, &"player")])
		spawner.tick(1.0 / 60.0)
	var kept := _flat(gun.position(), still)
	_check(kept >= 7.0 and kept <= 15.0, "a gunner backs off into its range band",
		"%.1f m away" % kept)
	_check(int(bgun.get(&"shots")) > 0, "and fires from it", "%d shots" % int(bgun.get(&"shots")))

	_world.remove_child(spawner)
	spawner.free()

	# Patrolling what players use.
	var spawner2 := _spawner()
	var heat := DotNpcAiHeatmap.new()
	heat.attach(spawner2)
	var hot_spot := Vector3(12, 0, -9)
	for i in 50:
		heat.record(DotNpcAiHeatmap.TRAFFIC, hot_spot, 0.0)

	var guard := spawner2.spawn(&"soldier", Vector3(0, 0, 0))
	var bg := guard.brain as DotNpcAiBrain
	spawner2.set_candidates([])
	for i in 300:
		spawner2.tick(1.0 / 60.0)
		bg.patrol_hot(bg.context, 4.0)
	_check(_flat(guard.position(), hot_spot) < 3.0, "with nobody to fight, a smart NPC goes where players go",
		"%.1f m from the busiest cell" % _flat(guard.position(), hot_spot))

	bg.character = DotNpcAiCharacter.easy()
	spawner2.tick(1.0 / 60.0)
	_check(bg.patrol_hot(bg.context, 4.0) == DotNpcAiNode.Status.FAILURE,
		"and a dull one does not know the map")

	_world.remove_child(spawner2)
	spawner2.free()
	floor_body.queue_free()
	_done()


## The one cvar shape [method DotNpcAiNavAnnotator.read_cvars] reads (`name`, `get_string`),
## as dot-server's console variable has it.
class NavCvar:
	extends RefCounted

	var name := ""
	var value := ""
	var ranged := false

	func get_string() -> String:
		return value

	func with_range(_lo: float, _hi: float) -> NavCvar:
		ranged = true
		return self


const NavToy := preload("res://fixtures/nav_toy_level.gd")


static func _within(p: Vector3, box: AABB, margin: float = 0.0) -> bool:
	return p.x >= box.position.x - margin and p.x <= box.end.x + margin and p.z >= box.position.z - margin and p.z <= box.end.z + margin


static func _links_where(a: DotNpcAiNavAnnotations, kind: int, test: Callable) -> int:
	var n := 0
	for link in a.links_of(kind):
		if test.call(link["from"], link["to"]):
			n += 1
	return n


func _annotator(mesh: NavigationMesh, level: Node3D) -> DotNpcAiNavAnnotator:
	var job := DotNpcAiNavAnnotator.new(mesh, level.get_world_3d())
	job.agent_radius = 0.35
	job.stand_height = 1.8
	job.climb = 0.4
	job.jump_up = 1.0
	return job


func _test_nav_annotations() -> void:
	_section("navigation annotations on a level built in code")

	var level := NavToy.build()
	_world.add_child(level)
	# A ray sees a body only once the physics server has stepped with it in.
	for _k in range(3):
		await get_tree().physics_frame
	var mesh := NavToy.bake(level)
	_check(mesh.get_polygon_count() > 20, "the toy level bakes", "%d polygons" % mesh.get_polygon_count())

	var job := _annotator(mesh, level)
	var key := job.cache_key()
	var res := job.run_to_completion()
	_check(res.ok, "the annotator finishes", "" if res.ok else res.error.message)
	if not res.ok:
		level.queue_free()
		return
	var a: DotNpcAiNavAnnotations = res.value
	_check(a.key == key and key.length() == 64, "and the result carries the key it was asked for")

	var low := NavToy.LOW_PLATFORM
	var balcony := NavToy.BALCONY
	var top_of := func(box: AABB) -> Callable:
		return func(p: Vector3) -> bool: return _within(p, box, 0.2) and p.y > box.end.y - 0.3
	var on_floor := func(p: Vector3) -> bool: return p.y < 0.6
	var on_low: Callable = top_of.call(low)
	var on_balcony: Callable = top_of.call(balcony)
	var on_west: Callable = top_of.call(NavToy.GAP_WEST)
	var on_east: Callable = top_of.call(NavToy.GAP_EAST)

	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_JUMP_UP, func(f: Vector3, t: Vector3) -> bool: return on_floor.call(f) and on_low.call(t)) > 0,
		"a jump up onto the waist-high platform")
	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_DROP, func(f: Vector3, t: Vector3) -> bool: return on_low.call(f) and on_floor.call(t)) > 0,
		"and a drop off it")
	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_DROP, func(f: Vector3, t: Vector3) -> bool: return on_balcony.call(f) and on_floor.call(t)) > 0,
		"a drop off the balcony")
	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_JUMP_UP, func(_f: Vector3, t: Vector3) -> bool: return on_balcony.call(t)) == 0,
		"and no jump up onto it: three metres is above the jump")
	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_JUMP_GAP, func(f: Vector3, t: Vector3) -> bool: return on_west.call(f) and on_east.call(t)) > 0,
		"a jump across the gap one way")
	_check(_links_where(a, DotNpcAiNavAnnotations.LINK_JUMP_GAP, func(f: Vector3, t: Vector3) -> bool: return on_east.call(f) and on_west.call(t)) > 0,
		"and the other")
	var floor_gaps := _links_where(a, DotNpcAiNavAnnotations.LINK_JUMP_GAP, func(f: Vector3, t: Vector3) -> bool: return on_floor.call(f) or on_floor.call(t))
	_check(floor_gaps == 0, "no jump across from the floor to the floor (a corner is not a gap)", "%d" % floor_gaps)

	var in_room := false
	for spot in a.hiding_spots():
		if _within(spot["at"], NavToy.ROOM) and (spot["at"] as Vector3).y < 0.6:
			in_room = true
	_check(in_room, "a hiding place inside the closed room")
	# The bake walks the floor inside a solid block tall enough to stand in; that floor is
	# left out of what watchers, routes and spots are drawn from.
	var in_solid := 0
	var verts := mesh.get_vertices()
	for i in job.kept_polygons():
		var c := Vector3.ZERO
		for v in mesh.get_polygon(i):
			c += verts[v]
		c /= float(mesh.get_polygon(i).size())
		for box: AABB in [NavToy.GAP_WEST, NavToy.GAP_EAST, NavToy.BALCONY]:
			if _within(c, box, -0.1) and c.y < 0.6:
				in_solid += 1
	_check(in_solid == 0 and not job.kept_polygons().is_empty(), "and nothing is drawn from the floor the bake found inside a solid block", "%d" % in_solid)

	var door := false
	for choke in a.chokepoints:
		if (choke["at"] as Vector3).distance_to(NavToy.DOORWAY) < 1.5 and float(choke["width"]) < 2.0:
			door = true
	_check(door, "a chokepoint in the doorway between the halves", str(a.chokepoints))

	var crouch_only := 0
	var behind: Dictionary = {}
	for spot in a.spots:
		if _within(spot["at"], NavToy.LOW_WALL, 0.8) and (spot["at"] as Vector3).x < NavToy.LOW_WALL.position.x:
			if int(spot["low"]) != 0 and int(spot["high"]) == 0:
				crouch_only += 1
				behind = spot
	_check(crouch_only > 0, "the waist-high wall covers a crouched body and not a standing one")
	var covered := a.cover_from(Vector3(5, 1, 0), Vector3(-7, 0, 0), 3.0, "low")
	_check(not covered.is_empty() and (covered[0]["at"] as Vector3).x < NavToy.LOW_WALL.position.x,
		"cover from somebody east of it is found on its west side")
	_check(a.cover_from(Vector3(5, 1, 0), Vector3(-7, 0, 0), 3.0, "high").filter(
		func(sp: Dictionary) -> bool: return _within(sp["at"], NavToy.LOW_WALL, 0.8)).is_empty(),
		"and none standing there")
	_check(not behind.is_empty() and (behind["normal"] as Vector3).x < -0.5, "a spot's normal points away from its wall")

	# Kept as data: a round trip, a file, and the ways a file is refused.
	var back := DotNpcAiNavAnnotations.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	# Stats are the run's measurements and come back as JSON numbers (floats); the rest is exact.
	var before := a.to_dict()
	before.erase("stats")
	var after: Dictionary = (back.value as DotNpcAiNavAnnotations).to_dict() if back.ok else {}
	after.erase("stats")
	_check(back.ok and JSON.stringify(after) == JSON.stringify(before), "the annotations survive JSON")
	var path := "user://nav_selftest/%s.json" % a.key
	_check(a.save(path).ok, "and are saved")
	_check(DotNpcAiNavAnnotations.load_file(path, a.key).ok, "and load for their own key")
	var wrong := DotNpcAiNavAnnotations.load_file(path, "0".repeat(64))
	_check(not wrong.ok and wrong.error.code == DotError.CODE_INTEGRITY, "and are refused for another")
	var missing := DotNpcAiNavAnnotations.load_file("user://nav_selftest/none.json")
	_check(not missing.ok and missing.error.code == DotError.CODE_IO, "a missing file is a failure, not empty annotations")
	var old := a.to_dict()
	old["version"] = DotNpcAiNavAnnotations.VERSION + 1
	var stale := DotNpcAiNavAnnotations.from_dict(old)
	_check(not stale.ok and stale.error.code == DotError.CODE_VERSION, "and so is one of another version")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# The key, and the run in slices.
	var again := _annotator(mesh, level)
	_check(again.cache_key() == key, "the same mesh and settings give the same key")
	again.jump_up = 1.2
	_check(again.cache_key() != key, "and a changed setting another")
	var sliced := _annotator(mesh, level)
	sliced.slice = 3
	var steps := 0
	while sliced.step():
		steps += 1
	var sliced_a: DotNpcAiNavAnnotations = sliced.result.value if sliced.result != null and sliced.result.ok else null
	_check(sliced_a != null and steps > 50, "run three items at a time it takes many steps", "%d" % steps)
	if sliced_a != null:
		var x := a.to_dict()
		var y := sliced_a.to_dict()
		x.erase("stats")
		y.erase("stats")
		_check(JSON.stringify(x) == JSON.stringify(y), "and gives exactly what one go gives")
	else:
		_check(false, "and gives exactly what one go gives")

	# What a game adds, and what a server tunes.
	var declared := _annotator(mesh, level)
	declared.declare(Vector3(-18, 0.2, -13), Vector3(18, 0.2, 13), DotNpcAiNavAnnotations.LINK_TELEPORT, 2.0)
	_check(declared.cache_key() != key, "a declared link changes the key")
	var with_teleport: DotNpcAiNavAnnotations = declared.run_to_completion().value
	_check(with_teleport.links_of(DotNpcAiNavAnnotations.LINK_TELEPORT).size() == 1, "and is in the result as declared")
	var made: Array = []
	var add := func(cvar_name: String, default_value: String, _description: String, _flags: int) -> Object:
		var cv := NavCvar.new()
		cv.name = cvar_name
		cv.value = "0.5" if cvar_name == DotNpcAiNavAnnotator.CVAR_JUMP_UP else default_value
		made.append(cv)
		return cv
	var cvars := DotNpcAiNavAnnotator.bind_cvars(add)
	_check(cvars.size() == 4 and made.size() == 4 and (made[0] as NavCvar).ranged, "four ranged cvars are registered")
	var tuned := _annotator(mesh, level)
	tuned.read_cvars(cvars)
	_check(is_equal_approx(tuned.jump_up, 0.5) and is_equal_approx(tuned.drop_max, 6.0), "and read into an annotator")
	var short: DotNpcAiNavAnnotations = tuned.run_to_completion().value
	_check(short.links_of(DotNpcAiNavAnnotations.LINK_JUMP_UP).is_empty(), "where a half-metre jump links no jump up onto the platform")

	level.queue_free()
	_done()


## No one step of the annotator may be longer than the budget it is given: a server steps it
## inside a frame, and a step of 40 to 80 ms on a large map was one long tick. The old costs
## were in the 24-sample outline slices (a dense map's samples cost ten times a sparse one's)
## and in the one step that kept islands, so the level here is dense and wide.
func _test_nav_annotator_budget() -> void:
	_section("the annotator keeps every step inside its budget on a large level")
	var level := NavToy.build_large(12)
	_world.add_child(level)
	for _k in range(3):
		await get_tree().physics_frame
	var mesh := NavToy.bake(level)
	_check(mesh.get_polygon_count() > 1500, "the large level bakes to a large mesh", "%d polygons" % mesh.get_polygon_count())
	var spawn := Vector3(2.5, 1.0, 2.5)

	var budget := 4.0
	var job := _annotator(mesh, level)
	job.seeds = PackedVector3Array([spawn])
	job.slice_ms = budget
	var slowest := 0.0
	var slowest_phase := ""
	var steps := 0
	while true:
		var phase := String(job.describe()["phase"])
		var began := Time.get_ticks_usec()
		var more := job.step()
		var took := (Time.get_ticks_usec() - began) / 1000.0
		if took > slowest:
			slowest = took
			slowest_phase = phase
		steps += 1
		if not more:
			break
	var ok: bool = job.result != null and job.result.ok
	_check(ok, "the large level annotates", "" if ok else "no result")
	if not ok:
		level.queue_free()
		_done()
		return
	var a: DotNpcAiNavAnnotations = job.result.value
	# One item is the least a step can do and CI is noisy, so two budgets are allowed. The old
	# code's longest step here was several times over that.
	_check(slowest <= budget * 2.0, "no step is much longer than the %.0f ms budget" % budget,
		"%.1f ms in %s over %d steps" % [slowest, slowest_phase, steps])
	_check(float(a.stats.get("slowest_slice_ms", 999.0)) <= budget * 2.0, "and the job reports the same",
		"%s" % a.stats.get("slowest_slice_ms"))
	_check(a.links.size() > 20 and a.spots.size() > 50, "with real annotations to time", "%d links, %d spots" % [a.links.size(), a.spots.size()])

	# The same answer whatever the budget: the key is only valid if slicing changes nothing.
	var counted := _annotator(mesh, level)
	counted.seeds = PackedVector3Array([spawn])
	counted.slice_ms = 0.0
	counted.slice = 5000
	var whole: DotNpcAiNavAnnotations = counted.run_to_completion().value
	var x := a.to_dict()
	var y := whole.to_dict()
	x.erase("stats")
	y.erase("stats")
	_check(JSON.stringify(x) == JSON.stringify(y), "and the same links, spots and chokepoints as an unbudgeted run")
	_check(a.key == whole.key, "under the same key")
	level.queue_free()
	_done()

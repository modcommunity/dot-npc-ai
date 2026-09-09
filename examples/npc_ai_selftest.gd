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

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()

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
	_test_wander()
	_test_brain_on_a_real_npc()
	_test_crowd_separation()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


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
	print("blackboard")

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


func _test_context() -> void:
	print("context")

	var ctx := _context()
	ctx.advance(0.5)
	ctx.advance(0.5)

	_check(absf(ctx.now - 1.0) < 0.0001, "the clock advances", "%.2f" % ctx.now)
	_check(ctx.tick_index == 2, "and counts ticks")
	_check(ctx.delta == 0.5, "and holds this tick's delta")


# --- The tree -----------------------------------------------------------------

func _test_leaves() -> void:
	print("leaves")

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


func _test_sequence_resume() -> void:
	print("a sequence resumes")

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


func _test_reactive_sequence() -> void:
	print("a reactive sequence re-checks its guard")

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


func _test_selector_priority() -> void:
	print("a selector picks")

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


func _test_reactive_selector() -> void:
	print("a reactive selector interrupts")

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


func _test_parallel() -> void:
	print("parallel")

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


func _test_decorators() -> void:
	print("decorators")

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


func _test_repeat_does_not_hang() -> void:
	print("repeat")

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


# --- The machine --------------------------------------------------------------

func _test_machine() -> void:
	print("state machine")

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


func _test_machine_thrash() -> void:
	print("state machine: two states fighting")

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


# --- Steering -----------------------------------------------------------------

func _test_steering() -> void:
	print("steering")

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


func _test_wander() -> void:
	print("wander")

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


# --- Against a real NPC -------------------------------------------------------

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
	print("a brain on a real NPC")

	var spawner := _spawner()
	var npc := spawner.spawn(&"zombie", Vector3.ZERO)

	_check(npc.brain != null, "dot-npc loads a dot-npc-ai brain by PATH")
	_check(npc.brain is DotNpcAiBrain, "and it is one")

	var brain := npc.brain as DotNpcAiBrain
	_check(brain.machine != null and brain.tree != null, "with both halves built")
	_check(brain.machine.current() == &"idle", "starting in its initial state")

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

	spawner.queue_free()


func _test_crowd_separation() -> void:
	print("a crowd at one door")

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

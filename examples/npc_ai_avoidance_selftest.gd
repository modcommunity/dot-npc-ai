extends Node

## DotNpcAiAvoidance: head-on pass, corridor squeeze, crowd spread, tier skip, cost, the fallback and the RVO backend.

const CHECKS := 33
const SECTIONS := 9
const DT := 1.0 / 60.0
## Stated budget for advance plus 250 steers a frame; CI_SLACK covers shared runners (a real regression is far above 2x).
const BUDGET_MS := 2.0
const CI_SLACK := 2.0
const COST_REPEATS := 6

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _min_gap := 99.0


class Walker extends RefCounted:
	var pos := Vector3.ZERO
	var goal := Vector3.ZERO
	var speed := 3.0
	var tier := 0
	var arrived := false

	func position() -> Vector3:
		return pos


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai avoidance self-test")
	_test_off_by_default()
	_test_fallback()
	_test_head_on()
	await _test_corridor()
	_test_crowd()
	_test_tiers()
	_test_cost()
	await _test_rvo()
	_test_describe()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s (%s)" % [what, detail])
		print("  FAIL  %s %s" % [what, detail])


func _node(backend: String = "separation", enabled: bool = true, probe: Variant = null) -> DotNpcAiAvoidance:
	var av := DotNpcAiAvoidance.new()
	var c := DotNpcAiAvoidanceConfig.new()
	c.enabled = enabled
	c.backend = backend
	av.apply_config(c)
	av.auto_advance = false
	if probe != null:
		av.rvo_probe = probe
	add_child(av)
	return av


func _walker(from: Vector3, to: Vector3, speed: float = 3.0) -> Walker:
	var w := Walker.new()
	w.pos = from
	w.goal = to
	w.speed = speed
	return w


## One step of a crowd: advance, ask each walker's safe velocity, move it. [param half_width] > 0 clamps z like walls.
## Returns how many pairs are closer than 0.6 m (bodies are 0.9 m).
func _step(av: DotNpcAiAvoidance, walkers: Array, half_width: float = 0.0, avoid: bool = true) -> int:
	av.advance(DT)
	for i in walkers.size():
		var w: Walker = walkers[i]
		var flat := Vector3(w.goal.x - w.pos.x, 0.0, w.goal.z - w.pos.z)
		if flat.length() < 0.3:
			w.arrived = true
			if avoid:
				av.steer(i, w, Vector3.ZERO, w.tier)
			continue
		var want := flat.normalized() * w.speed
		var v := av.steer(i, w, want, w.tier) if avoid else want
		w.pos += v * DT
		if half_width > 0.0:
			w.pos.z = clampf(w.pos.z, -half_width, half_width)
	var overlaps := 0
	for i in walkers.size():
		if (walkers[i] as Walker).arrived:
			continue
		for j in range(i + 1, walkers.size()):
			if (walkers[j] as Walker).arrived:
				continue
			var d := (walkers[i] as Walker).pos.distance_to((walkers[j] as Walker).pos)
			_min_gap = minf(_min_gap, d)
			if d < 0.6:
				overlaps += 1
	return overlaps


func _test_off_by_default() -> void:
	_section("off by default")
	var av := _node("separation", false)
	var w := _walker(Vector3.ZERO, Vector3(10, 0, 0))
	var want := Vector3(3, 0, 0)
	_check(av.steer(1, w, want) == want, "disabled: the wanted velocity comes back untouched")
	_check(av.agent_count() == 0, "disabled: no agent is even created")
	_check(not DotNpcAiAvoidanceConfig.new().enabled, "the config ships disabled")
	av.queue_free()
	_done()


func _test_fallback() -> void:
	_section("fallback")
	var no_rvo := _node("rvo", true, func() -> bool: return false)
	_check(no_rvo.backend() == &"separation", "rvo asked, unsupported: falls back to the own pass")
	var forced := _node("separation", true, func() -> bool: return true)
	_check(forced.backend() == &"separation", "separation asked: stays on the own pass even where rvo exists")
	var auto := _node("auto", true, func() -> bool: return true)
	_check(auto.backend() == &"rvo", "auto with rvo available: uses rvo")
	var a := _walker(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	var b := _walker(Vector3(5, 0, 0), Vector3(-5, 0, 0))
	for i in 600:
		_step(no_rvo, [a, b])
	_check(a.arrived and b.arrived, "the fallback pass still gets a head-on pair across")
	for n in [no_rvo, forced, auto]:
		n.queue_free()
	_done()


func _test_head_on() -> void:
	_section("head-on pass")
	var av := _node()
	var a := _walker(Vector3(-8, 0, 0), Vector3(8, 0, 0))
	var b := _walker(Vector3(8, 0, 0), Vector3(-8, 0, 0))
	var closest := 99.0
	var steps := 0
	while steps < 900 and not (a.arrived and b.arrived):
		_step(av, [a, b])
		closest = minf(closest, a.pos.distance_to(b.pos))
		steps += 1
	_check(a.arrived and b.arrived, "both arrive", "steps %d" % steps)
	_check(closest > 0.8, "they never touch (closest %.2f m, bodies %.2f)" % [closest, 0.9], "%.2f" % closest)
	_check(steps < 480, "without losing much time (%d steps, straight line is 320)" % steps)
	var c := _walker(Vector3(-8, 0, 0), Vector3(8, 0, 0))
	var d := _walker(Vector3(8, 0, 0), Vector3(-8, 0, 0))
	var plain := 0
	for i in 400:
		_step(av, [c, d], 0.0, false)
		plain = maxi(plain, 1 if c.pos.distance_to(d.pos) < 0.5 else 0)
	_check(plain == 1, "control: without avoidance the same pair passes through each other")
	av.queue_free()
	_done()


func _test_corridor() -> void:
	_section("corridor squeeze")
	var av := _node()
	var walkers: Array = []
	for i in 4:
		walkers.append(_walker(Vector3(-10 - i * 1.5, 0, -0.5 + (i % 2)), Vector3(10 + i * 1.2, 0, -0.5 + (i % 2))))
		walkers.append(_walker(Vector3(10 + i * 1.5, 0, 0.5 - (i % 2)), Vector3(-10 - i * 1.2, 0, 0.5 - (i % 2))))
	var steps := 0
	_min_gap = 99.0
	while steps < 1800:
		_step(av, walkers, 1.1)
		steps += 1
		var all := true
		for w: Walker in walkers:
			all = all and w.arrived
		if all:
			break
	var arrived := 0
	for w: Walker in walkers:
		arrived += 1 if w.arrived else 0
	_check(arrived == walkers.size(), "all eight cross a 2.2 m corridor, four each way (%d of 8)" % arrived)
	_check(steps < 1500, "in finite time, no deadlock (%d steps = %.1f s)" % [steps, steps * DT])
	_check(_min_gap > 0.4, "without ever stacking (closest pair %.2f m of 0.90)" % _min_gap, "%.2f" % _min_gap)
	av.queue_free()
	await get_tree().process_frame
	_done()


func _test_crowd() -> void:
	_section("crowd spreads")
	var runs := {}
	for mode in [true, false]:
		var av := _node()
		var walkers: Array = []
		for i in 30:
			var ang := float(i) * 2.399963
			var rad := 0.55 * sqrt(float(i + 1))
			var from := Vector3(cos(ang), 0, sin(ang)) * rad
			walkers.append(_walker(from, Vector3(14.0 + (i % 5) * 0.2, 0, (i % 7) * 0.2 - 0.6), 2.5))
		var deep := 0
		var steps := 0
		while steps < 240:
			deep += _step(av, walkers, 0.0, mode)
			steps += 1
		var nearest := 0.0
		for i in walkers.size():
			var best := 99.0
			for j in walkers.size():
				if i != j:
					best = minf(best, (walkers[i] as Walker).pos.distance_to((walkers[j] as Walker).pos))
			nearest += best
		runs[mode] = [deep, nearest / walkers.size()]
		av.queue_free()
	print("        clump of 30: nearest neighbour %.2f m with avoidance, %.2f without; deep overlaps %d against %d" % [runs[true][1], runs[false][1], runs[true][0], runs[false][0]])
	_check(runs[true][0] * 3 < runs[false][0] * 2, "a clump of thirty has a third fewer deep overlaps (%d deep pair-ticks against %d)" % [runs[true][0], runs[false][0]])
	_check(runs[true][1] > runs[false][1] + 0.15, "and ends more spread out (%.2f m nearest neighbour against %.2f)" % [runs[true][1], runs[false][1]])
	var av2 := _node()
	var streams: Array = []
	for i in 20:
		var z := (float(i % 10) - 4.5) * 1.3
		var x := 12.0 + float(i / 10) * 1.6
		streams.append(_walker(Vector3(-x, 0, z), Vector3(x, 0, z), 2.5))
		streams.append(_walker(Vector3(x, 0, z + 0.65), Vector3(-x, 0, z + 0.65), 2.5))
	var steps2 := 0
	while steps2 < 1200:
		_step(av2, streams)
		steps2 += 1
		var all := true
		for w: Walker in streams:
			all = all and w.arrived
		if all:
			break
	_check(steps2 < 1200, "two dense opposing streams of twenty all arrive, no gridlock (%d steps)" % steps2)
	av2.queue_free()
	_done()


func _test_tiers() -> void:
	_section("low tier skips")
	var av := _node()
	var a := _walker(Vector3(-2, 0, 0), Vector3(8, 0, 0))
	var b := _walker(Vector3(2, 0, 0), Vector3(-8, 0, 0))
	a.tier = 2
	b.tier = 2
	var want := Vector3(3, 0, 0)
	av.advance(DT)
	var seen := av.steer(0, a, want, 2)
	av.advance(DT)
	_check(seen == want, "tier 2: the wanted velocity comes back")
	_check(av.n_skipped == 1 and av.n_steered == 0, "and it is counted as skipped, not steered")
	var hot := av.steer(1, b, Vector3(-3, 0, 0), 0)
	_check(hot != Vector3(-3, 0, 0) or av.n_steered == 1, "tier 0 is steered")
	var c := _walker(Vector3(-9, 0, 0), Vector3(8, 0, 0))
	var t1 := av.steer(2, c, want, 1)
	var again := av.steer(2, c, want, 1)
	_check(again == t1 and av.n_reused >= 1, "tier 1 reuses its answer inside calm_interval")
	av.queue_free()
	_done()


func _test_cost() -> void:
	_section("cost")
	var av := _node()
	var walkers: Array = []
	for i in 250:
		var x := float(i % 25) * 1.6 - 20.0
		var z := float(i / 25) * 1.6 - 8.0
		walkers.append(_walker(Vector3(x, 0, z), Vector3(-x * 0.9, 0, -z * 0.9 + 3.0), 2.0))
	for i in 20:
		_step(av, walkers)
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var frames := 180
	var per_frame_ms := INF
	for r in COST_REPEATS:
		var t0 := Time.get_ticks_usec()
		for i in frames / COST_REPEATS:
			_step_cost_only(av, walkers)
		per_frame_ms = minf(per_frame_ms, (Time.get_ticks_usec() - t0) / 1000.0 / (frames / COST_REPEATS))
	var objects_after := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	print("        250 agents: %.3f ms a frame, best of repeats (advance + 250 steers), peak %d us in the node's own count" % [per_frame_ms, av.peak_us])
	_check(av.agent_count() == 250, "250 agents tracked")
	_check(per_frame_ms < BUDGET_MS * CI_SLACK, "best of %d runs under the %.1f ms budget x%.1f (%.3f ms)" % [COST_REPEATS, BUDGET_MS, CI_SLACK, per_frame_ms], "%.3f" % per_frame_ms)
	_check(objects_after == objects_before, "no objects allocated per tick (%d before, %d after)" % [objects_before, objects_after])
	_check(mem_after - mem_before < 200000, "static memory flat over %d frames (+%d bytes)" % [frames, mem_after - mem_before])
	av.queue_free()
	_done()


## The same loop as _step, without the overlap count (which is O(n squared) and not what is being priced).
func _step_cost_only(av: DotNpcAiAvoidance, walkers: Array) -> void:
	av.advance(DT)
	for i in walkers.size():
		var w: Walker = walkers[i]
		var flat := Vector3(w.goal.x - w.pos.x, 0.0, w.goal.z - w.pos.z)
		if flat.length() < 0.3:
			w.pos = Vector3(-w.goal.x, 0, -w.goal.z)
			continue
		w.pos += av.steer(i, w, flat.normalized() * w.speed, 0) * DT


func _test_rvo() -> void:
	_section("rvo backend")
	if not DotNpcAiAvoidance.rvo_supported():
		print("  (navigation server cannot run agents here; the fallback section covered this path)")
		_check(true, "rvo unsupported: skipped")
		_check(true, "rvo unsupported: skipped")
		_check(true, "rvo unsupported: skipped")
		_done()
		return
	var av := _node("rvo")
	_check(av.backend() == &"rvo", "rvo is chosen when the server supports it")
	var a := _walker(Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var b := _walker(Vector3(6, 0, 0), Vector3(-6, 0, 0))
	var closest := 99.0
	var frames := 0
	while frames < 900 and not (a.arrived and b.arrived):
		await get_tree().physics_frame
		_step(av, [a, b])
		closest = minf(closest, a.pos.distance_to(b.pos))
		frames += 1
	_check(a.arrived and b.arrived, "a head-on pair arrives through the navigation server's avoidance", "frames %d" % frames)
	_check(closest > 0.6, "and does not pass through itself (closest %.2f m)" % closest, "%.2f" % closest)
	av.queue_free()
	await get_tree().process_frame
	_done()


func _test_describe() -> void:
	_section("describe and config")
	var av := _node()
	var w := _walker(Vector3.ZERO, Vector3(5, 0, 0))
	av.advance(DT)
	av.steer(1, w, Vector3(2, 0, 0))
	var d := av.describe()
	_check(d["agents"] == 1 and d["backend"] == "separation", "describe names the backend and the agent count")
	_check(av.describe_lines().size() == 3, "describe_lines is three lines")
	var c := DotNpcAiAvoidanceConfig.new()
	var applied := c.apply_dictionary({"enabled": true, "max_neighbours": 4, "max_tier": 2})
	_check(c.enabled and c.max_neighbours == 4 and c.max_tier == 2, "the config takes a dictionary like any DotConfig", str(applied))
	_check(c.validate().ok, "and validates")
	DotNpcAiAvoidance.new().queue_free()
	av.register_service()
	_check(DotNpcAiAvoidance.find() == av, "it registers as a service")
	DotRegistry.unregister(DotNpcAiAvoidance.SERVICE)
	av.queue_free()
	_done()

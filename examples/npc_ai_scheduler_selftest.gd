extends Node

## DotNpcAiScheduler against fake brains: tiers, stagger, the budget, the caches, and what it saves.

const CHECKS := 52
const SECTIONS := 8

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _fake_us := 0


class FakeNpc extends RefCounted:
	var seed: int = 0
	var pos := Vector3.ZERO
	var target := false

	func position() -> Vector3:
		return pos

	func has_target() -> bool:
		return target


class FakeBrain extends RefCounted:
	var npc := FakeNpc.new()
	var thinks := 0
	var last_delta := 0.0
	var last_tick := 0
	var worst_gap := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai scheduler self-test")
	_test_off_by_default()
	_test_tiers()
	_test_stagger()
	_test_delta()
	_test_budget()
	_test_queries()
	_test_config()
	_test_cost()

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


## A scheduler on, with the players where [param players] says, a fake clock and a 2 ms budget.
func _scheduler(enabled: bool = true, players: Array = [Vector3.ZERO], budget_ms: float = 2.0) -> DotNpcAiScheduler:
	var s := DotNpcAiScheduler.new()
	var c := DotNpcAiSchedulerConfig.new()
	c.enabled = enabled
	c.budget_ms = budget_ms
	s.apply_config(c)
	s.players_source = func() -> Array: return players
	s.clock = func() -> int: return _fake_us
	s.auto_advance = false
	add_child(s)
	return s


func _brain(s: DotNpcAiScheduler, at: Vector3, seed_value: int = 0) -> FakeBrain:
	var b := FakeBrain.new()
	b.npc.pos = at
	b.npc.seed = seed_value
	s.register(b)
	return b


## One frame the way a host runs it. [param cost_us] is what each think costs on the fake clock.
func _frame(s: DotNpcAiScheduler, brains: Array, cost_us: int = 0) -> void:
	s.advance(1.0 / 60.0)
	for b: FakeBrain in brains:
		var d := s.admit(b, 1.0 / 60.0)
		if d < 0.0:
			continue
		b.thinks += 1
		b.last_delta = d
		b.worst_gap = maxi(b.worst_gap, s.tick - b.last_tick)
		b.last_tick = s.tick
		_fake_us += cost_us
		s.finish(b)


func _test_off_by_default() -> void:
	_section("off by default")
	_check(DotNpcAiSchedulerConfig.new().enabled == false, "the config ships disabled")
	var s := _scheduler(false)
	var far := _brain(s, Vector3(500, 0, 0), 7)
	var frames := 0
	for i in 30:
		_frame(s, [far])
		frames += 1
	_check(far.thinks == 30, "a disabled scheduler lets a brain 500 m away think every tick", str(far.thinks))
	_check(is_equal_approx(s.admit(far, 0.25), 0.25), "and hands back the brain's own delta")
	_check(DotNpcAiScheduler.find() == null, "nothing is registered until the host does it")
	_done()


func _test_tiers() -> void:
	_section("tiers")
	var s := _scheduler()
	var near := _brain(s, Vector3(10, 0, 0), 1)
	var mid := _brain(s, Vector3(40, 0, 0), 2)
	var far := _brain(s, Vector3(90, 0, 0), 3)
	var gone := _brain(s, Vector3(300, 0, 0), 4)
	_check([s.tier_of(near), s.tier_of(mid), s.tier_of(far), s.tier_of(gone)] == [0, 1, 2, 3],
		"distance to the nearest player picks tiers 0, 1, 2, 3")

	var all := [near, mid, far, gone]
	for i in 600:
		_frame(s, all)
	_check(near.thinks == 600, "tier 0 thinks every tick", str(near.thinks))
	_check(mid.thinks == 200, "tier 1 every 3rd", str(mid.thinks))
	_check(far.thinks == 60, "tier 2 every 10th", str(far.thinks))
	_check(gone.thinks == 20, "tier 3 every 30th, asleep between", str(gone.thinks))
	_check(not s.los_allowed(far) and s.los_allowed(mid), "tier 2 may not test line of sight, tier 1 may")

	var two := _scheduler(true, [Vector3(1000, 0, 0), Vector3.ZERO])
	_check(two.tier_of(_brain(two, Vector3(10, 0, 0))) == 0, "any player counts: the nearest of two decides")

	var seen := [false]
	var vs := _scheduler()
	vs.visibility_source = func(_at: Vector3) -> bool: return seen[0]
	var hidden := _brain(vs, Vector3(10, 0, 0), 5)
	_check(vs.tier_of(hidden) == 1, "a brain no player can see drops one tier")
	seen[0] = true
	vs.advance(0.016)
	for i in vs.config.retier_interval:
		vs.advance(0.016)
	_check(vs.tier_of(hidden) == 0, "and is back in step once seen")

	var es := _scheduler()
	var fighter := _brain(es, Vector3(300, 0, 0), 6)
	_check(es.tier_of(fighter) == 3, "an idle brain far away sleeps")
	fighter.npc.target = true
	for i in es.config.retier_interval + 1:
		es.advance(0.016)
	_check(es.tier_of(fighter) == 1, "one with a target is never calmer than tier 1")

	var hs := _scheduler()
	var edge := _brain(hs, Vector3(31, 0, 0), 8)
	_check(hs.tier_of(edge) == 1, "31 m is tier 1")
	edge.npc.pos = Vector3(29, 0, 0)
	for i in 11:
		hs.advance(0.016)
	_check(hs.tier_of(edge) == 0, "29 m is tier 0")
	edge.npc.pos = Vector3(31, 0, 0)
	for i in 11:
		hs.advance(0.016)
	_check(hs.tier_of(edge) == 0, "31 m again stays tier 0: the hysteresis margin")
	edge.npc.pos = Vector3(34, 0, 0)
	for i in 11:
		hs.advance(0.016)
	_check(hs.tier_of(edge) == 1, "34 m is clear of it")

	var none := _scheduler(true, [])
	_check(none.tier_of(_brain(none, Vector3(900, 0, 0))) == 0, "with no player known everything thinks at full rate")

	s.unregister(near)
	_check(s.tier_counts() == PackedInt32Array([0, 1, 1, 1]), "an unregistered brain leaves the counts")
	_done()


func _test_stagger() -> void:
	_section("stagger")
	var s := _scheduler(true, [Vector3.ZERO], 1000.0)
	var brains: Array = []
	for i in 300:
		brains.append(_brain(s, Vector3(45, 0, 0), i + 1))
	var per_tick := PackedInt32Array()
	for t in 30:
		var before: int = s.stats["thinks"]
		_frame(s, brains)
		per_tick.append(s.stats["thinks"] - before)
	var low := 1000
	var high := 0
	for n in per_tick:
		low = mini(low, n)
		high = maxi(high, n)
	_check(low > 0, "no tick is empty", "min %d" % low)
	_check(high <= 140 and low >= 60, "300 tier-1 brains spread about 100 a tick, not 300 on one", "%d to %d" % [low, high])

	# Seeds that are all multiples of ten would bunch on a plain modulo.
	var s2 := _scheduler(true, [Vector3.ZERO], 1000.0)
	var tens: Array = []
	for i in 300:
		tens.append(_brain(s2, Vector3(45, 0, 0), (i + 1) * 10))
	var counts := PackedInt32Array()
	for t in 30:
		var before: int = s2.stats["thinks"]
		_frame(s2, tens)
		counts.append(s2.stats["thinks"] - before)
	var worst := 0
	for n in counts:
		worst = maxi(worst, n)
	_check(worst <= 140, "and seeds in steps of ten do not bunch", "worst %d" % worst)
	_done()


func _test_delta() -> void:
	_section("skipped ticks")
	var s := _scheduler()
	var b := _brain(s, Vector3(45, 0, 0), 9)
	var seen := PackedFloat32Array()
	for i in 12:
		_frame(s, [b])
		if b.last_tick == s.tick:
			seen.append(b.last_delta)
	_check(seen.size() == 4, "a tier-1 brain thought four times in twelve ticks", str(seen.size()))
	_check(is_equal_approx(seen[seen.size() - 1], 3.0 / 60.0), "each time with the three ticks' worth of time", str(seen))
	_done()


func _test_budget() -> void:
	_section("the budget")
	var s := _scheduler()
	var brains: Array = []
	for i in 1000:
		brains.append(_brain(s, Vector3(5 + (i % 20), 0, 0), i + 1))
	_check(s.tier_counts()[0] == 1000, "a thousand brains all in tier 0 want 20 ms a tick")

	for t in 120:
		_frame(s, brains, 20)
	var budget_us := int(s.config.budget_ms * 1000.0)
	_check(s.peak_used_us <= budget_us, "no frame spent more than the 2 ms budget", "peak %d us" % s.peak_used_us)
	_check(s.peak_used_us > budget_us / 2, "and the budget is used rather than ignored", "peak %d us" % s.peak_used_us)

	var starved := 0
	var worst := 0
	for b: FakeBrain in brains:
		if b.thinks == 0:
			starved += 1
		worst = maxi(worst, b.worst_gap)
	_check(starved == 0, "every brain got a turn", "%d never thought" % starved)
	_check(worst <= 14, "none waited much past the 10 ticks the budget implies", "worst gap %d ticks" % worst)
	_check(s.stats["deferred"] > 0, "the rest were deferred, not dropped")
	_check(s.describe_lines().size() > 3 and s.describe().has("peak_used_us"), "describe reports it")

	# A think that costs ten times the estimate must still not blow the budget through admits.
	var h := _scheduler()
	var heavy: Array = []
	for i in 200:
		heavy.append(_brain(h, Vector3(5, 0, 0), i + 1))
	for t in 30:
		_frame(h, heavy, 400)
	_check(h.peak_used_us <= int(h.config.budget_ms * 1000.0) + 400, "with 400 us thinks the overshoot is at most one think", str(h.peak_used_us))
	_done()


func _test_queries() -> void:
	_section("cached queries")
	var s := _scheduler()
	var near := _brain(s, Vector3(10, 0, 0), 1)
	var far := _brain(s, Vector3(90, 0, 0), 2)
	var calls := [0]
	var test := func() -> bool:
		calls[0] += 1
		return true

	s.advance(0.016)
	_check(s.cached_los(near, &"a", test) and calls[0] == 1, "a line-of-sight test runs once")
	s.cached_los(near, &"a", test)
	_check(calls[0] == 1, "and is reused inside its three ticks")
	for i in 3:
		s.advance(0.016)
	s.cached_los(near, &"a", test)
	_check(calls[0] == 2, "then asked again")
	_check(s.cached_los(far, &"b", test) == false and calls[0] == 2, "a tier-2 brain is refused the test and told no")

	s.advance(0.016)
	var paths := [0]
	var solve := func() -> Variant:
		paths[0] += 1
		return [paths[0]]
	for i in 6:
		s.cached_path("p%d" % i, solve)
	_check(paths[0] == 4, "six new path requests in a frame compute only four", str(paths[0]))
	_check(s.cached_path("p5", solve) == null, "the others get null, not a stale guess, when none exists")
	_check(s.cached_path("p0", solve) == [1] and paths[0] == 4, "a cached path costs no request")
	s.advance(0.016)
	_check(s.cached_path("p5", solve) != null, "and the next frame has its own allowance")

	var off := _scheduler(false)
	var n := [0]
	off.cached_los(null, 1, func() -> bool:
		n[0] += 1
		return true)
	off.cached_los(null, 1, func() -> bool:
		n[0] += 1
		return true)
	_check(n[0] == 2, "disabled, nothing is cached")
	_done()


func _test_config() -> void:
	_section("config")
	var c := DotNpcAiSchedulerConfig.new()
	var res := c.apply_dictionary({"budget_ms": 1.5, "tier1_interval": 5, "enabled": true})
	_check(c.budget_ms == 1.5 and c.tier1_interval == 5 and c.enabled, "a dictionary (a yml or json file) sets the numbers")
	c.full_range = 100.0
	_check(not c.validate().ok, "ranges that do not rise are refused")
	_check(c.config_keys().size() >= 17, "every number is a config key", str(c.config_keys().size()))
	var s := _scheduler()
	var cfg := DotNpcAiSchedulerConfig.new()
	cfg.enabled = true
	cfg.tier1_interval = 2
	cfg.mid_range = 60.0
	s.apply_config(cfg)
	var b := _brain(s, Vector3(40, 0, 0), 3)
	for i in 20:
		_frame(s, [b])
	_check(b.thinks == 10, "a changed interval changes the rate", str(b.thinks))
	s.register_service()
	_check(DotNpcAiScheduler.find() == s, "register_service puts it where brains look")
	DotRegistry.unregister(DotNpcAiScheduler.SERVICE)
	_check(res != null, "apply_dictionary reports what it did")
	_done()


func _test_cost() -> void:
	_section("cost of 1000 brains")
	var frames := 120
	var results := {}
	# The think is a stand-in of about 45 us, a plausible tree tick and sense pass.
	for mode in ["off", "tiers", "tiers+6ms"]:
		var s := _scheduler(mode != "off", [Vector3.ZERO, Vector3(150, 0, 0)], 6.0 if mode == "tiers+6ms" else 1000.0)
		s.clock = Callable()
		var brains: Array = []
		for i in 1000:
			brains.append(_brain(s, Vector3(float((i * 37) % 220), 0, float((i * 17) % 90)), i + 1))
		var work := 0.0
		var start := Time.get_ticks_usec()
		for f in frames:
			s.advance(1.0 / 60.0)
			for b: FakeBrain in brains:
				var d := s.admit(b, 1.0 / 60.0)
				if d < 0.0:
					continue
				for k in 1500:
					work += sin(float(k) + d)
				b.thinks += 1
				s.finish(b)
		var ms := float(Time.get_ticks_usec() - start) / 1000.0 / frames
		var thinks := 0
		for b: FakeBrain in brains:
			thinks += b.thinks
		results[mode] = ms
		results[mode + "_thinks"] = thinks / frames
		print("  %-9s %.3f ms a frame, %d thinks a frame, tiers %s, peak %d us" % [
			mode, ms, thinks / frames, str(Array(s.tier_counts())), s.peak_used_us])
		if work == -1.0:
			print(work)
	print("  1000 brains: %.2f ms off, %.2f ms tiered (%.1fx), %.2f ms tiered and capped (%.1fx)" % [
		results["off"], results["tiers"], results["off"] / results["tiers"],
		results["tiers+6ms"], results["off"] / results["tiers+6ms"]])
	_check(results["tiers_thinks"] < results["off_thinks"] / 2, "far fewer thinks a frame with tiers", "%d against %d" % [results["tiers_thinks"], results["off_thinks"]])
	_check(results["tiers"] < results["off"] / 2, "and under half the cost a frame, the scheduler's own included")
	_check(results["tiers+6ms"] < 7.5, "with the budget set to 6 ms the frame stays near it", "%.2f ms" % results["tiers+6ms"])
	_done()

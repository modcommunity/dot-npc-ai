extends Node

## Utility scoring: each curve, personalities, hysteresis, assignment, and the cost under the scheduler's tiers.

const CHECKS := 53
const SECTIONS := 7

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


class FakeNpc extends RefCounted:
	var seed: int = 0
	var pos := Vector3.ZERO
	func is_alive() -> bool:
		return true
	func position() -> Vector3:
		return pos
	func has_target() -> bool:
		return false


class FakeBrain extends RefCounted:
	var npc := FakeNpc.new()
	var utility: DotNpcAiUtility
	var thinks := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-npc-ai utility self-test")
	_test_off_by_default()
	_test_curves()
	_test_scoring()
	_test_personality()
	_test_hysteresis()
	_test_assignment()
	_test_tier_cost()

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


func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func _test_off_by_default() -> void:
	_section("off by default")
	_check(DotNpcAiUtilityConfig.new().enabled == false, "the config ships disabled")
	var brain := DotNpcAiBrain.new()
	_check(brain.utility == null, "a brain has no scorer")
	_check(brain.use_utility(DotNpcAiUtilityConfig.new()) == null and brain.utility == null, "use_utility with a disabled config stays off")
	_check(brain.utility_choose() == &"", "and chooses nothing")
	var cfg := DotNpcAiUtilityConfig.new()
	cfg.enabled = true
	var b2 := DotNpcAiBrain.new()
	_check(b2.use_utility(cfg) != null and b2.utility != null, "an enabled config gives a scorer")
	_done()


func _test_curves() -> void:
	_section("curves")
	var K := DotNpcAiCurve.Kind
	var lin := DotNpcAiCurve.make(K.LINEAR, 0.0, 100.0)
	_check(_near(lin.eval(0.0), 0.0) and _near(lin.eval(50.0), 0.5) and _near(lin.eval(100.0), 1.0), "linear maps the range to 0..1")
	_check(_near(lin.eval(-50.0), 0.0) and _near(lin.eval(500.0), 1.0), "linear clamps outside the range")
	var quad := DotNpcAiCurve.make(K.QUADRATIC, 0.0, 1.0)
	_check(_near(quad.eval(0.5), 0.25) and _near(quad.eval(1.0), 1.0), "quadratic squares")
	var inv := DotNpcAiCurve.make(K.INVERSE, 0.0, 100.0)
	_check(_near(inv.eval(0.0), 1.0) and _near(inv.eval(25.0), 0.75) and _near(inv.eval(100.0), 0.0), "inverse falls as the input rises")
	var step := DotNpcAiCurve.make(K.STEP, 0.0, 10.0)
	_check(step.eval(4.9) == 0.0 and step.eval(5.0) == 1.0, "step flips at the middle")
	var logi := DotNpcAiCurve.make(K.LOGISTIC, 0.0, 1.0)
	_check(_near(logi.eval(0.0), 0.0) and _near(logi.eval(1.0), 1.0) and _near(logi.eval(0.5), 0.5), "logistic runs 0 to 1 through the middle")
	_check(logi.eval(0.4) < 0.4 and logi.eval(0.6) > 0.6, "and is steeper than a line in the middle")
	_check(lin.eval(0.5, 0.25) < lin.eval(0.5), "a shift moves a linear curve along its input")
	_check(logi.eval(0.5, 0.2) < 0.5 and step.eval(5.0, 0.2) == 0.0, "a shift moves a logistic midpoint and a step threshold")
	var flat := DotNpcAiCurve.make(K.LINEAR, 5.0, 5.0)
	_check(flat.eval(5.0) == 0.0, "an empty range scores 0, not NaN")
	var back := DotNpcAiCurve.from_dictionary(logi.to_dictionary())
	_check(back.ok and back.value.kind == K.LOGISTIC and _near(back.value.eval(0.3), logi.eval(0.3)), "a curve round-trips through a dictionary")
	_check(not DotNpcAiCurve.from_dictionary({"kind": "wobbly"}).ok, "an unknown kind is refused")
	_done()


## Two actions on health and distance, shared by several sections.
func _build(u: DotNpcAiUtility) -> void:
	var K := DotNpcAiCurve.Kind
	u.add_action(&"attack").consider(&"health", DotNpcAiCurve.make(K.LINEAR, 0.0, 1.0)).consider(&"near", DotNpcAiCurve.make(K.INVERSE, 0.0, 30.0))
	u.add_action(&"flee").consider(&"health", DotNpcAiCurve.make(K.INVERSE, 0.0, 1.0))
	u.add_action(&"flank").consider(&"near", DotNpcAiCurve.make(K.LINEAR, 0.0, 30.0), 0.5)


func _utility(readings: Dictionary, cfg: DotNpcAiUtilityConfig = null) -> DotNpcAiUtility:
	var u := DotNpcAiUtility.new()
	if cfg != null:
		u.config = cfg
	_build(u)
	u.inputs = func(key: StringName) -> float: return readings.get(key, 0.0)
	return u


func _test_scoring() -> void:
	_section("scoring")
	var r := {&"health": 1.0, &"near": 5.0}
	var u := _utility(r)
	_check(u.choose(0.0) == &"attack", "a healthy NPC close to its target attacks")
	_check(u.last_scores[&"flee"] == 0.0, "and flee scores zero at full health")
	r[&"health"] = 0.1
	_check(u.choose(1.0) == &"flee", "a hurt one flees")
	_check(u.last_scores[&"attack"] < u.last_scores[&"flee"], "because flee outscored attack", str(u.last_scores))
	var solo := DotNpcAiUtility.new()
	solo.add_action(&"x").consider(&"a", DotNpcAiCurve.make(DotNpcAiCurve.Kind.LINEAR)).consider(&"b", DotNpcAiCurve.make(DotNpcAiCurve.Kind.LINEAR))
	solo.inputs = func(_k: StringName) -> float: return 0.5
	solo.choose(0.0)
	_check(solo.last_scores[&"x"] > 0.25, "compensation lifts a two-term product above 0.5 * 0.5", str(solo.last_scores))
	var calls := [0]
	var counted := DotNpcAiUtility.new()
	counted.add_action(&"a").consider(&"k", DotNpcAiCurve.make(DotNpcAiCurve.Kind.LINEAR))
	counted.add_action(&"b").consider(&"k", DotNpcAiCurve.make(DotNpcAiCurve.Kind.INVERSE))
	counted.inputs = func(_k: StringName) -> float:
		calls[0] += 1
		return 0.3
	counted.choose(0.0)
	_check(calls[0] == 1, "an input two actions share is read once", str(calls[0]))
	_check(DotNpcAiUtility.new().choose(0.0) == &"", "no actions chooses nothing")
	_done()


func _test_personality() -> void:
	_section("personalities")
	var r := {&"health": 0.6, &"near": 12.0}
	var neutral := _utility(r)
	var aggressive := _utility(r)
	aggressive.personality = DotNpcAiPersonality.aggressive()
	aggressive.personality.jitter = 0.0
	var cautious := _utility(r)
	cautious.personality = DotNpcAiPersonality.cautious()
	cautious.personality.jitter = 0.0
	var a := aggressive.choose(0.0)
	var c := cautious.choose(0.0)
	_check(a == &"attack" and c != &"attack", "the same readings: aggressive attacks, cautious does not", "%s %s" % [a, c])
	r[&"health"] = 0.45
	var shifted_a := _utility(r)
	shifted_a.personality = DotNpcAiPersonality.aggressive()
	shifted_a.personality.jitter = 0.0
	var shifted_c := _utility(r)
	shifted_c.personality = DotNpcAiPersonality.cautious()
	shifted_c.personality.jitter = 0.0
	shifted_a.choose(0.0)
	shifted_c.choose(0.0)
	_check(shifted_a.last_scores[&"attack"] > shifted_c.last_scores[&"attack"], "a brave curve shift raises attack's score over a cautious one's")
	var f := _utility({&"health": 0.9, &"near": 28.0})
	f.personality = DotNpcAiPersonality.flanker()
	f.personality.jitter = 0.0
	_check(f.choose(0.0) == &"flank", "a flanker flanks at range")
	neutral.choose(0.0)
	_check(neutral.last_scores.size() == 3, "scores are kept for describe")
	var p1 := DotNpcAiPersonality.aggressive()
	_check(p1.wobble(7, &"attack") == p1.wobble(7, &"attack"), "the wobble is fixed for a seed and action")
	_check(p1.wobble(7, &"attack") != p1.wobble(8, &"attack"), "and differs between seeds")
	var w := true
	for s in 50:
		w = w and absf(p1.wobble(s, &"attack") - 1.0) <= p1.jitter + 0.0001
	_check(w, "and stays within +/- jitter")
	var made := DotNpcAiPersonality.from_dictionary({"actions": {"attack": 2.0}, "shifts": {"health": -0.1}, "jitter": 0.05}, &"brute")
	_check(made.ok and made.value.weight_of(&"attack") == 2.0 and made.value.shift_of(&"health") == -0.1, "a personality loads from a dictionary")
	_check(not DotNpcAiPersonality.from_dictionary({"jitter": 3.0}).ok, "and a jitter above 1 is refused")
	_done()


func _test_hysteresis() -> void:
	_section("hysteresis")
	var K := DotNpcAiCurve.Kind
	var r := {&"a": 0.50, &"b": 0.48}
	var cfg := DotNpcAiUtilityConfig.new()
	cfg.min_hold_s = 0.0
	var u := DotNpcAiUtility.new()
	u.config = cfg
	u.add_action(&"A").consider(&"a", DotNpcAiCurve.make(K.LINEAR))
	u.add_action(&"B").consider(&"b", DotNpcAiCurve.make(K.LINEAR))
	u.inputs = func(k: StringName) -> float: return r[k]
	u.choose(0.0)
	var flips := 0
	var last := u.current
	for i in 100:
		r[&"a"] = 0.50 + (0.02 if i % 2 == 0 else -0.02)
		r[&"b"] = 0.50 + (-0.02 if i % 2 == 0 else 0.02)
		var now := u.choose(1.0 + i)
		if now != last:
			flips += 1
			last = now
	_check(flips == 0, "readings wobbling inside the bonus do not flip the choice", str(flips))
	r[&"a"] = 0.1
	r[&"b"] = 0.9
	_check(u.choose(200.0) == &"B", "a clear win still switches")
	var plain_cfg := DotNpcAiUtilityConfig.new()
	plain_cfg.hysteresis_bonus = 0.0
	plain_cfg.min_hold_s = 0.0
	var plain := DotNpcAiUtility.new()
	plain.config = plain_cfg
	plain.add_action(&"A").consider(&"a", DotNpcAiCurve.make(K.LINEAR))
	plain.add_action(&"B").consider(&"b", DotNpcAiCurve.make(K.LINEAR))
	plain.inputs = func(k: StringName) -> float: return r[k]
	var pf := 0
	var pl := &""
	for i in 100:
		r[&"a"] = 0.50 + (0.02 if i % 2 == 0 else -0.02)
		r[&"b"] = 0.50 + (-0.02 if i % 2 == 0 else 0.02)
		var n := plain.choose(float(i))
		if n != pl:
			pf += 1
			pl = n
	_check(pf > 50, "the same wobble flaps every tick without it", str(pf))
	var tie := DotNpcAiUtility.new()
	tie.config.min_hold_s = 0.0
	tie.add_action(&"first").consider(&"k", DotNpcAiCurve.make(K.LINEAR))
	tie.add_action(&"second").consider(&"k", DotNpcAiCurve.make(K.LINEAR))
	tie.inputs = func(_k: StringName) -> float: return 0.5
	_check(tie.choose(0.0) == &"first" and tie.choose(1.0) == &"first", "an exact tie goes to the earlier action, every time")
	var hold_cfg := DotNpcAiUtilityConfig.new()
	hold_cfg.min_hold_s = 2.0
	hold_cfg.hysteresis_bonus = 0.0
	var h := DotNpcAiUtility.new()
	h.config = hold_cfg
	var hr := {&"a": 0.9, &"b": 0.1}
	h.add_action(&"A").consider(&"a", DotNpcAiCurve.make(K.LINEAR))
	h.add_action(&"B").consider(&"b", DotNpcAiCurve.make(K.LINEAR))
	h.inputs = func(k: StringName) -> float: return hr[k]
	h.choose(0.0)
	hr[&"a"] = 0.2
	hr[&"b"] = 0.8
	_check(h.choose(1.0) == &"A", "a held action is kept for min_hold_s")
	_check(h.choose(2.5) == &"B", "and replaced after it")
	hr[&"a"] = 0.0
	hr[&"b"] = 0.0
	hr[&"a"] = 0.8
	hr[&"b"] = 0.0
	h.choose(10.0)
	hr[&"a"] = 0.0
	hr[&"b"] = 0.5
	var fresh := h.choose(10.1)
	_check(fresh == &"B", "an action scoring zero is dropped inside the hold", String(fresh))
	_done()


func _test_assignment() -> void:
	_section("assignment")
	var cfg := DotNpcAiUtilityConfig.new()
	_check(cfg.personality_for(5) == null, "none assigns nothing")
	cfg.assignment = "random"
	var seen := {}
	for s in 60:
		var p := cfg.personality_for(s)
		seen[p.id] = true
	_check(seen.size() == 3, "random reaches every built-in", str(seen.keys()))
	_check(cfg.personality_for(9).id == cfg.personality_for(9).id, "and is the same for a seed every time")
	cfg.pool = PackedStringArray(["cautious"])
	_check(cfg.personality_for(1).id == &"cautious" and cfg.personality_for(2).id == &"cautious", "a pool limits the draw")
	cfg.assignment = "role"
	cfg.role_map = {"sniper": "cautious", "rusher": "aggressive"}
	_check(cfg.personality_for(1, &"sniper").id == &"cautious" and cfg.personality_for(1, &"rusher").id == &"aggressive", "role picks by the map")
	_check(cfg.personality_for(1, &"medic") == null, "an unmapped role gets none")
	var loaded := DotNpcAiUtilityConfig.new()
	var applied := loaded.apply_dictionary({"enabled": true, "assignment": "role", "hysteresis_bonus": 0.4,
		"role_map": {"boss": "brute"}, "personalities": {"brute": {"actions": {"attack": 2.0}, "jitter": 0.0}}})
	_check(applied.size() == 5 and loaded.enabled and is_equal_approx(loaded.hysteresis_bonus, 0.4), "the config loads from a dictionary (JSON or YAML)", str(applied))
	_check(loaded.validate().ok and loaded.personality_for(1, &"boss").weight_of(&"attack") == 2.0, "with a custom personality")
	var bad := DotNpcAiUtilityConfig.new()
	bad.assignment = "dice"
	_check(not bad.validate().ok, "an unknown assignment is refused")
	_done()


func _test_tier_cost() -> void:
	_section("tier cost")
	var s := DotNpcAiScheduler.new()
	var sc := DotNpcAiSchedulerConfig.new()
	sc.enabled = true
	sc.budget_ms = 1000.0
	s.apply_config(sc)
	s.players_source = func() -> Array: return [Vector3.ZERO]
	s.clock = func() -> int: return 0
	s.auto_advance = false
	add_child(s)
	var ucfg := DotNpcAiUtilityConfig.new()
	var brains: Array = []
	for i in 30:
		var b := FakeBrain.new()
		b.npc.pos = Vector3([10.0, 40.0, 90.0][i % 3], 0, 0)
		b.npc.seed = i
		b.utility = DotNpcAiUtility.new()
		b.utility.config = ucfg
		_build(b.utility)
		b.utility.inputs = func(_k: StringName) -> float: return 0.5
		s.register(b)
		brains.append(b)
	var now := 0.0
	for tick in 600:
		s.advance(1.0 / 60.0)
		now += 1.0 / 60.0
		for b: FakeBrain in brains:
			if s.admit(b, 1.0 / 60.0) < 0.0:
				continue
			b.thinks += 1
			b.utility.choose(now)
			b.utility.choose(now)
			s.finish(b)
	var by_tier := [0, 0, 0]
	for b: FakeBrain in brains:
		by_tier[s.tier_of(b)] += b.utility.evaluations
	_check(by_tier[0] == 10 * 600 and by_tier[1] == 10 * 200 and by_tier[2] == 10 * 60, "evaluations follow the tiers: every tick, 1 in 3, 1 in 10", str(by_tier))
	var hits := 0
	for b: FakeBrain in brains:
		hits += b.utility.cache_hits
	_check(hits == by_tier[0] + by_tier[1] + by_tier[2], "a second ask in the same think is a cache hit, not a score")
	var tier0: FakeBrain = brains[0]
	_check(tier0.utility.considerations_scored == tier0.utility.evaluations * 4, "four considerations scored per evaluation, none per skipped tick", str(tier0.utility.considerations_scored))
	var cached_cfg := DotNpcAiUtilityConfig.new()
	cached_cfg.cache_s = 0.5
	var cu := DotNpcAiUtility.new()
	cu.config = cached_cfg
	_build(cu)
	cu.inputs = func(_k: StringName) -> float: return 0.5
	for i in 60:
		cu.choose(i / 60.0)
	_check(cu.evaluations == 2, "cache_s reuses a score across ticks: a second of ticks costs two evaluations", str(cu.evaluations))
	_done()

extends "res://examples/selftest/conditions_tests.gd"

## Brain-on-a-real-NPC, scheduler, token and crowd sections.


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


func _check_stuck_progress(brain: DotNpcAiBrain, spawner: DotNpcSpawner) -> void:
	# Steering at somewhere and getting nowhere for stuck_seconds asks for an unsmoothed path.
	if brain.path == null:
		brain.path = DotNpcPath.new()
	brain._watch_progress(Vector3.ZERO, Vector3(10, 0, 0))
	brain._progress_since -= brain.stuck_seconds + 0.1
	brain._watch_progress(Vector3(0.1, 0, 0), Vector3(10, 0, 0))
	_check(brain.path.rough_until > spawner.now(), "an NPC making no headway is given the graph's own corners",
		"rough until %.2f, now %.2f" % [brain.path.rough_until, spawner.now()])
	brain.path.rough_until = -INF
	brain._watch_progress(Vector3.ZERO, Vector3(10, 0, 0))
	brain._progress_since -= brain.stuck_seconds + 0.1
	brain._watch_progress(Vector3(0.1, 1.4, 0), Vector3(10, 0, 0))
	_check(brain.path.rough_until > spawner.now(), "and so is one hopping on the spot: height is not headway",
		"rough until %.2f, now %.2f" % [brain.path.rough_until, spawner.now()])
	brain.path.rough_until = -INF


func _test_brain_on_a_real_npc() -> void:
	_section("a brain on a real NPC")

	var spawner := _spawner()
	var npc := spawner.spawn(&"zombie", Vector3.ZERO)

	_check(npc.brain != null, "dot-npc loads a dot-npc-ai brain by PATH")
	_check(npc.brain is DotNpcAiBrain, "and it is one")

	var brain := npc.brain as DotNpcAiBrain
	_check(brain.machine != null and brain.tree != null, "with both halves built")
	_check(brain.machine.current() == &"idle", "starting in its initial state")

	_check_stuck_progress(brain, spawner)

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


class CountingSquad extends DotNpcAiSquad:
	var pulls := 0

	func pull(member: Object, since: int) -> int:
		pulls += 1
		return super.pull(member, since)


func _test_squad_pull_interval() -> void:
	_section("a brain reads its squad's log at most every squad_pull_interval")

	var spawner := _spawner()
	var brain := spawner.spawn(&"zombie", Vector3.ZERO).brain as DotNpcAiBrain
	var squad := CountingSquad.new(&"counted")
	squad.pull_reports = true
	var mate := FakeMember.new()
	squad.join(mate)
	squad.join(brain)
	brain.squad = squad

	for i in 30:
		spawner.tick(1.0 / 60.0)
	var open := squad.pulls
	_check(open >= 25, "with no interval it reads on every think", "%d reads in 30 ticks" % open)

	brain.squad_pull_interval = 0.5
	brain._pulled_at = -INF
	squad.pulls = 0
	for i in 60:
		spawner.tick(1.0 / 60.0)
	_check(squad.pulls >= 2 and squad.pulls <= 3, "at 0.5 s it reads two or three times a second",
		"%d reads in 60 ticks" % squad.pulls)

	# A report made between reads is in the log and arrives at the next one.
	var cursor := brain._report_seq
	squad.report(mate, &"far_enemy", Vector3(5, 0, 5), Vector3.ZERO, spawner.now())
	for i in 40:
		spawner.tick(1.0 / 60.0)
	_check(brain._report_seq > cursor, "and a report made between reads is not lost",
		"cursor %d -> %d" % [cursor, brain._report_seq])

	_world.remove_child(spawner)
	spawner.free()
	_done()


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

	var stub := StubDirector.new()
	spawner = _spawner()
	_gaps_paths(sched, stub, spawner)
	var probe := _gaps_sight(sched, spawner)
	_gaps_late_scheduler(sched, stub, probe)
	_done()


func _gaps_paths(sched: DotNpcAiScheduler, stub: StubDirector, spawner: DotNpcSpawner) -> void:
	# Path denial falls back to the last waypoint, never a straight line.
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


func _gaps_sight(sched: DotNpcAiScheduler, spawner: DotNpcSpawner) -> Callable:
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
	return probe


func _gaps_late_scheduler(sched: DotNpcAiScheduler, stub: StubDirector, probe: Callable) -> void:
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

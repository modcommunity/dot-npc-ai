extends "res://examples/selftest/conditions_tests.gd"

## The NPC catalogue and spawner the brain sections build on, and the real-NPC, scheduler and
## crowd sections; brain_tests.gd extends this.


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

		# Long enough for BOTH clocks: the senses hold an unseen target for `commitment_grace` (3 s), then
		# `searching` starts its own 3 s timeout. Six hundred ticks is ten seconds; a test sized to one
		# clock passes or fails depending on which it forgot.
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

		# The spawner going away takes the brain with it: context and brain point at each other and a world is
		# torn down by freeing nodes, not removing NPCs, so this path leaked in every game with hunters.
		# Freed, not queued, so PREDELETE runs now.
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


func _walker(spawner: DotNpcSpawner, at: Vector3, goal: Vector3) -> DotNpcAiBrain:
	var brain := spawner.spawn(&"zombie", at).brain as DotNpcAiBrain
	brain.machine = null
	brain.tree = DotNpcAiLeaf.Action.new(&"go", func(ctx: DotNpcAiContext) -> DotNpcAiNode.Status:
		brain.steer_with_spacing(goal, 6.0, ctx.delta)
		return DotNpcAiNode.Status.RUNNING)
	return brain


func _test_crowd_separation() -> void:
	_section("a crowd at one door")

	var spawner := _spawner()
	var goal := Vector3(0, 0, -30)

	# Twelve zombies on a ring sent at one point, a horde at a door. Not stacked (bodies spawned
	# inside each other cannot depenetrate), and on a floor (`steer_toward` applies gravity).
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
								# HORIZONTALLY: a 3D distance calls two capsules stacked on each other's head 1.8 m apart,
								# the one arrangement this check exists to catch, and the one that happens when a crowd
								# converging on a point climbs itself.
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

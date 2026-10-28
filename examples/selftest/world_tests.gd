extends "res://examples/selftest/skill_tests.gd"

## Squad, heatmap, role and nav-annotation sections.


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

	var holder: DotNpcAiBrain = ba if ba.holds_role(DotNpcAiBrain.ROLE_SUPPRESS) else bb
	var other: DotNpcAiBrain = bb if holder == ba else ba
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

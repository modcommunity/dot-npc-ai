extends "res://examples/selftest/brain_tests.gd"

## Humanising, server skill, and perception sections.


func _test_reaction_jitter() -> void:
	_section("reaction jitter and npc_humanise")

	var plain := DotNpcAiCharacter.normal().with_seed(11)
	plain.reaction_jitter = 0.0
	var jittered := DotNpcAiCharacter.normal().with_seed(11)
	jittered.reaction_jitter = 0.5

	var plain_times: Array[float] = []
	var jitter_times: Array[float] = []
	for i in range(60):
		plain_times.append(plain.effective_reaction(float(i) * 1.7))
		jitter_times.append(jittered.effective_reaction(float(i) * 1.7))
	_check(plain_times.min() == plain_times.max() and is_equal_approx(plain_times[0], plain.reaction_time), "jitter 0 is the plain reaction every time")
	_check(jitter_times.min() >= jittered.reaction_time - 0.0001 and jitter_times.max() > jittered.reaction_time * 1.2, "jitter only ever slows it, sometimes noticeably")
	_check(jittered.effective_reaction(3.3) == jittered.effective_reaction(3.3), "and the same sighting always reacts the same")
	_check(not jittered.has_reacted(0.0, jittered.reaction_time * 0.99) and jittered.has_reacted(0.0, jittered.reaction_time * 2.0), "has_reacted follows the stretched reaction")

	var skill := DotNpcAiSkill.new()
	_check(is_equal_approx(skill.apply(jittered).reaction_jitter, 0.5), "npc_humanise 1 leaves a character's jitter")
	_check(skill.set_cvar("npc_humanise", "0") and skill.apply(jittered).reaction_jitter == 0.0, "npc_humanise 0 removes it")
	_done()


func _test_humanising() -> void:
	_section("humanising: overshoot, tracking lag, strafe, glance, hesitate, hurt delay")

	var off := DotNpcAiCharacter.normal().with_seed(5)
	off.overshoot = 0.0
	off.track_lag = 0.0
	off.strafe_jitter = 0.0
	off.glance = 0.0
	off.hesitate = 0.0
	off.hurt_delay = 0.0
	off.aim_accuracy = 1.0
	off.aim_skill = 1.0
	var on := DotNpcAiCharacter.normal().with_seed(5)
	on.overshoot = 1.0
	on.view_turn_deg = 720.0

	# Overshoot: a big turn passes the target, then returns to it; 0 never passes.
	var want := Vector3(0, 0, -1)
	var v_on := Vector3(1, 0, 0)
	var v_off := Vector3(1, 0, 0)
	var passed := false
	for i in range(200):
		v_on = on.turn_view(v_on, want, 0.016)
		v_off = off.turn_view(v_off, want, 0.016)
		if v_on.x < -0.02:
			passed = true
	_check(passed, "a big turn swings past the target with overshoot")
	_check(v_on.angle_to(want) < 0.05, "and comes back onto it", "%.3f" % v_on.angle_to(want))
	var never := true
	v_off = Vector3(1, 0, 0)
	for i in range(200):
		v_off = off.turn_view(v_off, want, 0.016)
		if v_off.x < -0.0001:
			never = false
	_check(never, "overshoot 0 never passes it")

	# Tracking lag: the lead follows a velocity change late; without lag it is immediate.
	var lag := DotNpcAiCharacter.normal().with_seed(5)
	lag.track_lag = 0.3
	lag.aim_accuracy = 1.0
	lag.aim_skill = 1.0
	lag.track_velocity(Vector3(5, 0, 0), 0.0)
	lag.track_velocity(Vector3(-5, 0, 0), 0.05)
	var lagged := lag.aim_point(Vector3.ZERO, Vector3(0, 0, -10), Vector3(-5, 0, 0), 10.0, 1)
	var exact := off.aim_point(Vector3.ZERO, Vector3(0, 0, -10), Vector3(-5, 0, 0), 10.0, 1)
	_check(lagged.x > exact.x + 0.5, "aim leads with the old velocity for a moment", "%.2f vs %.2f" % [lagged.x, exact.x])
	for i in range(1, 40):
		lag.track_velocity(Vector3(-5, 0, 0), 0.05 + 0.05 * i)
	_check(is_equal_approx(lag.aim_point(Vector3.ZERO, Vector3(0, 0, -10), Vector3(-5, 0, 0), 10.0, 1).x, exact.x) or absf(lag.aim_point(Vector3.ZERO, Vector3(0, 0, -10), Vector3(-5, 0, 0), 10.0, 1).x - exact.x) < 0.05, "and catches up")

	_humanising_strafe_onward(off, on)
	_done()


func _humanising_strafe_onward(off: DotNpcAiCharacter, on: DotNpcAiCharacter) -> void:
	# Strafe: 0 is the square wave, jitter varies lengths, pauses and eases.
	var square_ok := true
	for i in range(100):
		var t := float(i) * 0.37
		var plain := 1.0 if fmod(t / 3.0, 2.0) < 1.0 else -1.0
		if off.strafe_drift(t, 3.0) != plain:
			square_ok = false
	_check(square_ok, "strafe_jitter 0 is exactly the plain alternation")
	var jit := DotNpcAiCharacter.normal().with_seed(5)
	jit.strafe_jitter = 1.0
	var mid := 0
	var flips := 0
	var last := 0.0
	for i in range(600):
		var d := jit.strafe_drift(float(i) * 0.05, 3.0)
		if absf(d) > 0.05 and absf(d) < 0.95:
			mid += 1
		if d != 0.0 and last != 0.0 and signf(d) != signf(last):
			flips += 1
		if d != 0.0:
			last = d
	_check(mid > 30, "jittered strafing eases between directions", str(mid))
	_check(flips >= 2 and jit.strafe_drift(7.7, 3.0) == jit.strafe_drift(7.7, 3.0), "still reverses, and the same moment always agrees", str(flips))

	# Glance.
	var glances := 0
	var worst := 0.0
	for i in range(2000):
		var g := on.glance_offset(float(i) * 0.1)
		if g != 0.0:
			glances += 1
		worst = maxf(worst, absf(g))
	_check(glances > 100 and worst <= deg_to_rad(90.0) + 0.001, "a glance happens now and then and stays within 90 degrees", "%d, %.2f" % [glances, worst])
	var none := true
	for i in range(500):
		if off.glance_offset(float(i) * 0.1) != 0.0:
			none = false
	_check(none, "glance 0 never looks aside")

	# Hesitate: bounded by the reaction, deterministic, off at 0.
	var h := DotNpcAiCharacter.normal().with_seed(5)
	h.hesitate = 2.0
	h.reaction_jitter = 0.0
	var bounded := true
	for i in range(50):
		if h.hesitation(float(i) * 1.3) > h.reaction_time + 0.0001:
			bounded = false
	_check(bounded, "hesitation never outlasts the reaction")
	_check(h.is_hesitating(1.0, 1.0) and not h.is_hesitating(1.0, 1.0 + h.reaction_time + 0.01) and not off.is_hesitating(1.0, 1.0), "hesitating at first, not after, never at 0")
	_check(h.hesitation(2.2) == h.hesitation(2.2), "the same sighting hesitates the same")

	# Hurt delay.
	_check(off.hurt_turn_delay(9) == 0.0 and on.hurt_turn_delay(9) > 0.0 and on.hurt_turn_delay(9) <= on.hurt_delay * 1.4 + 0.0001, "hurt turn is instant at 0 and a short delay otherwise")

	# npc_humanise.
	var skill := DotNpcAiSkill.new()
	var applied := skill.apply(on)
	_check(is_equal_approx(applied.overshoot, 1.0) and is_equal_approx(applied.hurt_delay, on.hurt_delay) and is_equal_approx(applied.hesitate, on.hesitate), "npc_humanise 1 leaves them")
	skill.set_cvar("npc_humanise", "0")
	var zero := skill.apply(on)
	_check(zero.overshoot == 0.0 and zero.track_lag == 0.0 and zero.strafe_jitter == 0.0 and zero.glance == 0.0 and zero.hesitate == 0.0 and zero.hurt_delay == 0.0, "npc_humanise 0 turns all six off")


func _test_humanised_leaves() -> void:
	_section("humanising reaches hold_off (hesitate) and search (glance)")

	var gd := GDScript.new()
	gd.source_code = "extends Node\nfunc candidate_position(_id):\n\treturn Vector3(0, 0, -10)\n"
	gd.reload()
	var director: Node = gd.new()
	add_child(director)
	var body := Node3D.new()
	add_child(body)
	var inst := DotNpcInstance.new()
	inst.def = DotNpcDef.make(&"x", BODY)
	inst.node = body
	inst.alive = true
	inst.target_id = &"somebody"
	inst.target_since = 5.0

	var brain := DotNpcAiBrain.new()
	brain.npc = inst
	brain.director = director
	brain.blackboard = DotNpcAiBlackboard.new()
	brain.context = DotNpcAiContext.make(inst, brain, brain.blackboard)
	brain.squad = DotNpcAiSquad.new()
	brain.squad.tokens.enabled = true
	var ch := DotNpcAiCharacter.normal().with_seed(5)
	ch.hesitate = 2.0
	ch.reaction_jitter = 0.0
	brain.character = ch
	brain.context.now = 5.0
	brain.context.delta = 0.016

	_check(ch.is_hesitating(5.0, 5.0), "the character is hesitating at the moment of the sighting")
	_check(brain.hold_off(brain.context, 3.0) == DotNpcAiNode.Status.RUNNING, "hold_off with tokens on holds (running) while hesitating")
	_check(body.global_position.is_equal_approx(Vector3.ZERO), "and does not move")
	ch.hesitate = 0.0
	_check(not ch.is_hesitating(5.0, 5.0), "hesitate 0 does not hold it, so hold_off goes on to pick a place")

	# search(): the look-round gains the glance offset, so it differs from the plain sweep.
	var glancing := DotNpcAiCharacter.normal().with_seed(5)
	glancing.glance = 1.0
	var t_glance := -1.0
	for i in range(2000):
		if glancing.glance_offset(float(i) * 0.05) != 0.0:
			t_glance = float(i) * 0.05
			break
	_check(t_glance >= 0.0, "a glancing character looks aside at some time", "%.2f" % t_glance)
	var src := FileAccess.get_file_as_string("res://addons/dot_npc_ai/runtime/dot_npc_ai_brain_tactics.gd")
	_check(src.contains("glance_offset(ctx.now)"), "search() adds the glance to its sweep")

	brain.unbind()
	body.free()
	director.free()
	_done()


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

	_server_skill_parse(skill)

	_server_skill_cvars()


	_done()


func _server_skill_parse(skill: DotNpcAiSkill) -> void:
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


func _server_skill_cvars() -> void:
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
	_check(made.size() == 4 and returned.size() == 4, "four cvars are registered")
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

	_skill_memory(spawner, npc, brain, skill)

	_skill_hurt(spawner, npc, brain, skill)

	_skill_vengeance(spawner, npc, brain, skill)


	_world.remove_child(spawner)
	spawner.free()
	_done()


func _skill_memory(spawner: DotNpcSpawner, npc: DotNpcInstance, brain: DotNpcAiBrain, skill: DotNpcAiSkill) -> void:
	var hidden := npc.def.faction
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"player", Vector3(0, 0, -8), &"player")
	])

	for i in 30:
		spawner.tick(1.0 / 60.0)

	_check(npc.has_target(), "the searcher acquires somebody")
	_check(brain.remembers_target(), "and remembers where they are")

		# Out of sight without leaving: same id and place, on the NPC's own side so the senses cannot perceive
		# it (a player behind a wall). Emptying the candidates would also make the position unknowable, and
		# players do not stop existing when they hide.
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


func _skill_hurt(spawner: DotNpcSpawner, npc: DotNpcInstance, brain: DotNpcAiBrain, skill: DotNpcAiSkill) -> void:
	var hidden := npc.def.faction
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


func _skill_vengeance(spawner: DotNpcSpawner, npc: DotNpcInstance, brain: DotNpcAiBrain, skill: DotNpcAiSkill) -> void:
	spawner.set_candidates([
		DotNpcSenses.Candidate.new(&"near", npc.position() + Vector3(0, 0, -4), &"player"),
				# Not much further than the other: the senses' stickiness switches BACK to a rival 40% nearer than
				# the committed target, which is right, so an attacker half as far again away lost the vengeance
				# on the next pass.
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


## A node that runs for ever and counts how often it was told to stop.
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

	_perception_hearing_danger_turning(spawner, npc, brain, board, ctx, hidden)

	_perception_prediction(spawner, npc, brain, board, ctx, hidden)

	_world.remove_child(spawner)
	spawner.free()
	floor_body.queue_free()
	_done()


func _perception_hearing_danger_turning(spawner: DotNpcSpawner, npc: DotNpcInstance, brain: DotNpcAiBrain, board: DotNpcAiSounds, ctx: DotNpcAiContext, hidden: StringName) -> void:
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


func _perception_prediction(spawner: DotNpcSpawner, npc: DotNpcInstance, brain: DotNpcAiBrain, board: DotNpcAiSounds, ctx: DotNpcAiContext, hidden: StringName) -> void:
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

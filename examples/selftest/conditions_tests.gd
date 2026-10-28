extends "res://examples/selftest/character_tests.gd"

## Conditions, memory, sounds, squad and tactics sections.


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

	# Pull: reports are logged, and a member reads the newest per enemy when it thinks.
	var pulled := DotNpcAiSquad.new(&"pull")
	pulled.pull_reports = true
	var p1 := FakeMember.new()
	var p2 := FakeMember.new()
	pulled.join(p1)
	pulled.join(p2)
	var seq := pulled.report_seq()
	pulled.report(p1, &"p", Vector3(1, 0, 0), Vector3.ZERO, 1.0)
	pulled.report(p1, &"p", Vector3(2, 0, 0), Vector3.ZERO, 2.0)
	pulled.report(p2, &"q", Vector3(3, 0, 0), Vector3.ZERO, 2.0)
	_check(p2.reports.is_empty(), "a pulled report calls nobody when it is made")
	var next := pulled.pull(p2, seq)
	_check(p2.reports.size() == 1 and p2.reports[0][1] == Vector3(2, 0, 0),
		"a pull delivers only the newest report per enemy, never the member's own", str(p2.reports))
	_check(pulled.pull(p2, next) == next and p2.reports.size() == 1, "and nothing twice")
	for i in DotNpcAiSquad.LOG_KEEP * 3:
		pulled.report(p1, StringName("e%d" % (i % 5)), Vector3(i, 0, 0), Vector3.ZERO, 3.0 + i)
	p2.reports.clear()
	pulled.pull(p2, 0)
	_check(p2.reports.size() == 5, "a trimmed log still holds the newest of each enemy", str(p2.reports.size()))

	# Both pull paths (a short stretch of log walked by row, a long one by enemy) give what a
	# brute-force reading of the same reports gives, in the same order, at 100 enemies.
	_squad_reports()
	_done()


func _squad_reports() -> void:
	var crowd := DotNpcAiSquad.new(&"crowd")
	crowd.pull_reports = true
	var maker := FakeMember.new()
	var reader := FakeMember.new()
	crowd.join(maker)
	crowd.join(reader)
	var cursor := crowd.report_seq()
	var newest := {}
	var order: Array = []
	var agree := true
	var rounds := 0
	var spent := 0

	for burst in [3, 40, 100, 250, 7, 100]:
		for i in burst:
			var enemy := StringName("s%d" % ((rounds * 31 + i * 7) % 100))
			var at := float(rounds * 1000 + i)
			crowd.report(maker, enemy, Vector3(at, 0, 0), Vector3.ZERO, at)
			newest[enemy] = at

		order = []
		for enemy in newest:
			order.append([newest[enemy], enemy])
		order.sort()
		reader.reports.clear()
		var t0 := Time.get_ticks_usec()
		cursor = crowd.pull(reader, cursor)
		spent += Time.get_ticks_usec() - t0
		var got: Array = []
		for r in reader.reports:
			got.append([r[1].x, r[0]])
		agree = agree and got == order
		newest = {}
		rounds += 1

	_check(agree, "a pull gives the newest report per enemy in log order, short stretch or long")
	_check(crowd.pull(reader, cursor) == cursor, "and a second pull at the end is empty")
	print("squad pull, 6 pulls over 100 enemies: %d us" % spent)

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

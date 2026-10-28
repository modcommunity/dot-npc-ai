extends SceneTree

## Writes a top-down trace of four squad soldiers closing on one player, as CSV.
##
## [b]A picture, not a check.[/b] The suite asserts where a squad ends up; it cannot see how
## it got there, or that three NPCs all "on the ring" are standing on one spot of it. The
## first surround passed every check with its three waiters stacked forty centimetres
## apart, and this trace is what showed it. Render it with `tools/plot_trace.py`.
##
## [codeblock]
## TRACE_OUT=/tmp/trace.csv godot --headless --path . -s tools/trace_surround.gd
## TRACE_KIND=gunner TRACE_OUT=/tmp/guns.csv godot --headless --path . -s tools/trace_surround.gd
## python3 tools/plot_trace.py /tmp/trace.csv /tmp/trace.png
## [/codeblock]
##
## Columns: tick, player x, player z, then x, z and holds-the-attack-slot (0/1) per soldier.
## The player stands for three seconds and then strafes toward +X, so the ring has to follow.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -1.4, 0)

	var kind := OS.get_environment("TRACE_KIND") if OS.get_environment("TRACE_KIND") != "" else "soldier"
	var cat := DotNpcCatalogue.new()
	var soldier := DotNpcDef.make(&"soldier", "res://fixtures/npc_body.tscn")
	soldier.brain_script_path = "res://fixtures/searcher_brain.gd"
	soldier.require_line_of_sight = false
	soldier.sight_half_angle_deg = 180.0
	soldier.sight_range = 30.0
	soldier.meta = {
		"speed": 4.0, "skill": OS.get_environment("TRACE_SKILL") if OS.get_environment("TRACE_SKILL") != "" else "hard",
		"squad": "pair", "attackers": 1, "ring": 4.0,
	}
	cat.add(soldier)

	# TRACE_KIND=gunner: two gunners, one flanking and one holding the front; a gunner is not an
	# attacker, so this shows what flanking does with no melee in front.
	var gunner := DotNpcDef.make(&"gunner", "res://fixtures/npc_body.tscn")
	gunner.brain_script_path = "res://fixtures/gunner_brain.gd"
	gunner.require_line_of_sight = false
	gunner.sight_half_angle_deg = 180.0
	gunner.sight_range = 40.0
	gunner.meta = {"speed": 4.0, "skill": "hard", "squad": "pair", "near": 8.0, "far": 14.0, "attackers": 1}
	cat.add(gunner)

	var spawner := DotNpcSpawner.new()
	spawner.catalogue = cat
	var limits := DotNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.sense_period_ticks = 1
	spawner.limits = limits
	spawner.authoritative = true
	world.add_child(spawner)
	DotNpcAiSquads.new().attach(spawner)

	var all: Array = []
	if kind == "gunner":
		# A soldier to attack, so the gunners' "behind" means something, and two gunners.
		all.append(spawner.spawn(&"soldier", Vector3(0, 0, 0)))
		all.append(spawner.spawn(&"gunner", Vector3(-4, 0, 2)))
		all.append(spawner.spawn(&"gunner", Vector3(4, 0, 2)))
	else:
		for x in [-3.0, 0.0, 3.0, 6.0]:
			all.append(spawner.spawn(&"soldier", Vector3(x, 0, 0)))

	var player := Vector3(0, 0, -12)
	var path := OS.get_environment("TRACE_OUT")
	var out := FileAccess.open(path if path != "" else "user://trace.csv", FileAccess.WRITE)

	for i in 600:
		if i > 180:
			player.x += 2.0 / 60.0

		spawner.set_candidates([DotNpcSenses.Candidate.new(&"p", player, &"player")])
		spawner.tick(1.0 / 60.0)

		if i % 6 == 0:
			var row := PackedStringArray([str(i), str(player.x), str(player.z)])

			for n in all:
				var at: Vector3 = n.position()
				var brain := n.brain as DotNpcAiBrain
				row.append_array([str(at.x), str(at.z), "1" if brain.holds_attack_slot() else "0"])

			out.store_line(",".join(row))

	out.close()
	quit()

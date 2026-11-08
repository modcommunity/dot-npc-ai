extends Node

## What reusing a path's waypoint across thinks (DotNpcAiBrain.path_reuse_thoughts) saves a chasing crowd.
## `godot --headless --path . res://examples/path_reuse_bench.tscn -- [--npcs=56] [--ticks=1200] [--reuse=5] [--rounds=3]`
## 56 brains chase a target circling a walled 180 m square, each thinking every tick; times spawner.tick() with the
## reuse off then on (alternating, so a shared box hits both alike) and prints one RESULT line. Compare the ratio, not the ms.

const BODY := "res://fixtures/npc_plain_body.tscn"
const BRAIN := "res://fixtures/zombie_brain.gd"

var _npcs := 56
var _ticks := 1200
var _reuse := 5
var _rounds := 3


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--npcs="):
			_npcs = arg.trim_prefix("--npcs=").to_int()
		elif arg.begins_with("--ticks="):
			_ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--reuse="):
			_reuse = arg.trim_prefix("--reuse=").to_int()
		elif arg.begins_with("--rounds="):
			_rounds = arg.trim_prefix("--rounds=").to_int()

	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var off := {"ms": 0.0, "asks": 0, "gap": 0.0}
	var on := {"ms": 0.0, "asks": 0, "gap": 0.0}
	_one(0)  # warm the native graph

	for r in _rounds:
		var a := _one(0)
		var b := _one(_reuse)
		for k in ["ms", "asks", "gap"]:
			off[k] += a[k] / _rounds
			on[k] += b[k] / _rounds

	print("RESULT %s" % JSON.stringify({
		"npcs": _npcs, "ticks": _ticks, "reuse": _reuse,
		"off_ms": snappedf(off["ms"], 0.1), "on_ms": snappedf(on["ms"], 0.1),
		"time_ratio": snappedf(on["ms"] / maxf(off["ms"], 0.001), 0.001),
		"off_path_toward": int(off["asks"]), "on_path_toward": int(on["asks"]),
		"ask_ratio": snappedf(on["asks"] / maxf(off["asks"], 1.0), 0.001),
		"off_mean_gap_m": snappedf(off["gap"], 0.01), "on_mean_gap_m": snappedf(on["gap"], 0.01),
	}))
	get_tree().quit()


class Counting extends DotNpcSpawner:
	var asks := 0

	func path_toward(npc: DotNpcInstance, p: DotNpcPath, goal: Vector3) -> Vector3:
		asks += 1
		return super(npc, p, goal)


func _one(reuse: int) -> Dictionary:
	var builder := DotNpcNavBuilder.new()
	builder.spacing = 2.0
	builder.add_floor(AABB(Vector3(-90, 0, -90), Vector3(180, 0, 180)), 0.0)
	for k in 8:
		builder.add_obstacle(AABB(Vector3(-70 + k * 18, 0, -80 + (k % 2) * 20), Vector3(2, 3, 120)))

	var def := DotNpcDef.make(&"zombie", BODY)
	def.brain_script_path = BRAIN
	def.require_line_of_sight = false
	def.meta = {"speed": 4.0}
	var cat := DotNpcCatalogue.new()
	cat.add(def)

	var sp := Counting.new()
	sp.catalogue = cat
	var limits := DotNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.world_budget = _npcs + 8
	limits.per_kind_cap = _npcs + 8
	limits.burst_cap = 200
	limits.sense_period_ticks = 4
	sp.limits = limits
	sp.authoritative = true
	add_child(sp)
	sp.set_nav_data(builder.build(&"reuse", "reuse"))

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var brains: Array[DotNpcAiBrain] = []
	var target := [Vector3(60, 0, 60)]

	for i in _npcs:
		var at := Vector3(rng.randf_range(-80, -20), 0, rng.randf_range(-80, 80))
		var b := sp.spawn(&"zombie", at).brain as DotNpcAiBrain
		b.machine = null
		b.path_reuse_thoughts = reuse
		b.tree = DotNpcAiLeaf.Action.new(&"chase", func(ctx: DotNpcAiContext) -> DotNpcAiNode.Status:
			b.steer_with_spacing(target[0], 5.0, ctx.delta)
			return DotNpcAiNode.Status.RUNNING)
		brains.append(b)

	var spent := 0
	for t in _ticks:
		var ang := t / 60.0 * 0.4
		target[0] = Vector3(50.0 * cos(ang), 0, 70.0 * sin(ang))
		var started := Time.get_ticks_usec()
		sp.tick(1.0 / 60.0)
		spent += Time.get_ticks_usec() - started

	var gap := 0.0
	for b in brains:
		gap += b.npc.position().distance_to(target[0])

	var out := {"ms": spent / 1000.0, "asks": sp.asks, "gap": gap / brains.size()}
	remove_child(sp)
	sp.free()
	return out

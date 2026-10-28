class_name DotNpcAiNode
extends RefCounted

## One node of a behaviour tree. The base every composite, decorator and leaf extends.
## A tree is SUCCESS, FAILURE, RUNNING and one rule: a node that returned RUNNING is resumed next tick, not restarted. Hand-written trees get this wrong silently (an NPC re-opens the door sixty times a second), so [method tick] is not overridden: it records what happened, and a subclass writes [method _tick].
## A RUNNING node that is then abandoned must be told ([method abort], propagated by composites) so an action holding a door, a reservation or an animation lets go.

enum Status {
	## Finished, and it worked.
	SUCCESS,
	## Finished, and it did not.
	FAILURE,
	## Not finished. Resume me next tick.
	RUNNING,
}

## For a debugger, a log line and a console command. Never used for behaviour.
var node_name: StringName = &""

## What this returned last time it was ticked.
var last_status: Status = Status.FAILURE

## Whether this node is mid-way through something.
##
## Set by [method tick] rather than by subclasses, so a subclass cannot forget.
var is_running: bool = false


func _init(p_name: StringName = &"") -> void:
	node_name = p_name


## Runs this node for one tick. Not overridden — override [method _tick].
func tick(ctx: DotNpcAiContext) -> Status:
	if not is_running:
		_enter(ctx)

	var status := _tick(ctx)

	is_running = status == Status.RUNNING
	last_status = status

	if not is_running:
		_exit(ctx, status)

	return status


## Abandons this node mid-action. Safe to call on a node that is not running.
## Composites must call this on their running child before returning something else, or whatever it reserved is never released; a game writing its own composite must too.
func abort(ctx: DotNpcAiContext) -> void:
	if not is_running:
		return

	is_running = false
	last_status = Status.FAILURE

	_abort(ctx)
	_exit(ctx, Status.FAILURE)


## A reproducible number in [0, 1) from two integers, shared by every node that decides by chance. Not [method randf]: a server rewind, a replay and a second headless run must agree, and a global RNG depends on how many others asked first.
## Kept positive at every step: `>>` on a negative GDScript int shifts ones in, which is reproducible but not uniform (dot-combat's shotgun patterns were a half-moon).
static func deterministic_unit(a: int, b: int) -> float:
	const MASK := 0x7FFFFFFFFFFFFFFF

	var x := ((a * 0x9E3779B1) ^ (b * 0x85EBCA6B)) & MASK
	x = (x ^ (x >> 33)) & MASK
	x = (x * 0xC2B2AE3D) & MASK
	x = (x ^ (x >> 29)) & MASK
	x = (x * 0x27D4EB2F) & MASK
	x = (x ^ (x >> 31)) & MASK

	return float((x >> 10) & 0x1FFFFFFFFFFFFF) / float(0x20000000000000)


## Every child of this node. Empty for a leaf.
func children() -> Array[DotNpcAiNode]:
	return []



## Called on the tick this node starts, before [method _tick].
func _enter(_ctx: DotNpcAiContext) -> void:
	pass


## The behaviour. Must return one of [enum Status].
func _tick(_ctx: DotNpcAiContext) -> Status:
	return Status.FAILURE


## Called on the tick this node stops, whatever it stopped with.
func _exit(_ctx: DotNpcAiContext, _status: Status) -> void:
	pass


## Called when this node is abandoned mid-action. Release things here.
func _abort(_ctx: DotNpcAiContext) -> void:
	pass



func status_name() -> String:
	return Status.keys()[last_status]


func describe() -> Dictionary:
	return {
		"node": String(node_name) if node_name != &"" else _type_name(),
		"status": status_name(),
		"running": is_running,
	}


## The tree below this node, one line per node, indented. For a console command.
## The only way to debug a behaviour tree, which has no stack trace: a person needs the shape and what each node did last tick.
func describe_lines(depth: int = 0) -> PackedStringArray:
	var out := PackedStringArray()

	out.append("%s%s  %s" % [
		"  ".repeat(depth),
		String(node_name) if node_name != &"" else _type_name(),
		status_name(),
	])

	for child in children():
		out.append_array(child.describe_lines(depth + 1))

	return out


func _type_name() -> String:
	var script := get_script() as GDScript

	if script == null:
		return "node"

	return script.resource_path.get_file().get_basename().replace("dot_npc_ai_", "")


func _to_string() -> String:
	return "%s(%s)" % [_type_name(), String(node_name)]

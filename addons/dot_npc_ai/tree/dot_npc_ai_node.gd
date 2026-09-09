class_name DotNpcAiNode
extends RefCounted

## One node of a behaviour tree. The base every composite, decorator and leaf extends.
##
## [b]A behaviour tree is three return values and one hard rule.[/b] The values are
## SUCCESS, FAILURE and RUNNING; the rule is that a node which returned RUNNING must be
## [i]resumed[/i] next tick rather than restarted. Almost every hand-written tree gets
## the rule wrong, and the symptom is not an error: a sequence whose second child is
## RUNNING re-runs the first child every tick, so an NPC that was walking to a door
## re-opens the door sixty times a second, or an attack that takes half a second never
## finishes because its wind-up restarts. Everything looks alive and nothing completes.
##
## So [method tick] is not overridden. It records what happened, and [method _tick] is
## what a subclass writes.
##
## [b]And a node that was RUNNING and is then abandoned must be told.[/b] A selector
## whose higher-priority child becomes viable abandons the running one mid-action, and
## an action holding a door open, a reservation or an animation has to let go.
## [method abort] is that, and composites propagate it.

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
##
## [b]Composites must call this on their running child before returning something
## else[/b], or an action that reserved something never releases it. Every composite in
## this addon does; a game writing its own must too, and this comment is the only place
## that will say so.
func abort(ctx: DotNpcAiContext) -> void:
	if not is_running:
		return

	is_running = false
	last_status = Status.FAILURE

	_abort(ctx)
	_exit(ctx, Status.FAILURE)


## Every child of this node. Empty for a leaf.
func children() -> Array[DotNpcAiNode]:
	return []


# --- Subclass interface -------------------------------------------------------

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


# --- Reporting ----------------------------------------------------------------

func status_name() -> String:
	return Status.keys()[last_status]


func describe() -> Dictionary:
	return {
		"node": String(node_name) if node_name != &"" else _type_name(),
		"status": status_name(),
		"running": is_running,
	}


## The tree below this node, one line per node, indented. For a console command.
##
## [b]The only way anybody debugs a behaviour tree.[/b] A tree has no stack trace and no
## breakpoint that means anything: what a person needs is the shape and what each node
## did on the last tick, which is exactly this.
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

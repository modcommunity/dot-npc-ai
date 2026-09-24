class_name DotNpcAiBrain
extends DotNpcBrain

## A [DotNpcBrain] that runs a behaviour tree or a state machine. The adapter.
##
## [b]This is the ONLY file in dot-npc-ai that names anything from dot-npc.[/b] The tree,
## the machine, the blackboard and the steering are dot-core-only and could be lifted
## into a vehicle, a 2D game or a menu; this is the twenty lines that join them to an
## NPC. That is deliberate, and it is why the split in `nightly-todo.md` asked for two
## addons rather than one big one.
##
## A game subclasses this and builds its decision in [method _build], which is called
## once when the NPC spawns:
##
## [codeblock]
## extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"
##
## func _build() -> void:
##     tree = DotNpcAiSelector.new(&"root", [
##         DotNpcAiSequence.new(&"chase", [
##             DotNpcAiLeaf.Condition.new(&"has target", func(_c): return npc.has_target()),
##             DotNpcAiLeaf.Action.new(&"walk", _walk),
##         ]),
##         DotNpcAiLeaf.Action.new(&"wander", _wander),
##     ])
## [/codeblock]
##
## [b]Extended by PATH, like every brain.[/b] A script inside a mounted dot-cloud pack
## cannot resolve a `class_name` — which is the whole reason `brain_script_path` is a
## path — and a game's brain extending this by name works in a build only.

## The tree, or null for a game using only the machine.
var tree: DotNpcAiNode = null

## The machine, or null for a game using only the tree.
##
## [b]Both may be set, and the tree runs first.[/b] That is the useful combination
## rather than an oversight: a machine holds what the NPC IS — patrolling, alerted,
## fleeing — and a tree decides what it does within that. Running the tree first means a
## reactive branch can write to the blackboard and the machine's transitions see it on
## the same tick, rather than a tick later.
var machine: DotNpcAiMachine = null

## This NPC's memory. Built here so a subclass always has one.
var blackboard: DotNpcAiBlackboard = null

## What the tree and the machine are handed. Built once and advanced, never rebuilt.
var context: DotNpcAiContext = null

## Who this NPC is. Handed to the context, where every node can reach it.
##
## [b]Give each NPC its own seed.[/b] A preset is one resource, and twenty NPCs sharing
## it share a seed — so every one of them takes the same shot with the same error at the
## same moment, which reads as a firing squad. [method DotNpcAiCharacter.with_seed] is
## the one call that prevents it, and `_npc_ready` makes it for a brain that did not.
var character: DotNpcAiCharacter = null

## Which state the machine starts in. Empty to leave it stopped.
var initial_state: StringName = &""

## What the tree returned on the last tick. For a console command.
var last_status: DotNpcAiNode.Status = DotNpcAiNode.Status.FAILURE


func _npc_ready() -> void:
	blackboard = DotNpcAiBlackboard.new()
	context = DotNpcAiContext.make(npc, self, blackboard)

	# The world's clock, not zero.
	#
	# A brain built ninety seconds into a round with a context starting at zero has
	# every cooldown, timeout and memory lifetime measured against a clock that
	# disagrees with the spawner's — so an NPC spawned late is briefly able to do
	# everything at once, and one spawned early is not. It reads as the cooldowns being
	# ignored on some NPCs and not others.
	if director != null and director.has_method(&"now"):
		context.now = float(director.call(&"now"))

	if character != null:
		# Seeded from the instance unless the game already did it. An NPC whose
		# character still carries the preset's seed is one of twenty identical
		# shooters, and the symptom is a volley rather than a fight.
		if character.seed_value <= 1 and npc != null and npc.instance_id != 0:
			character = character.with_seed(npc.instance_id)

		context.character = character

	_build()

	if machine != null and initial_state != &"":
		var started := machine.go_to(context, initial_state)

		if not started.ok:
			DotLog.warn("npc.ai", "an NPC's initial state does not exist", {
				"state": String(initial_state),
				"why": started.error.message,
			})


func _npc_think(delta: float) -> void:
	if context == null:
		return

	context.advance(delta)

	if tree != null:
		last_status = tree.tick(context)

	if machine != null:
		machine.tick(context)


## A brain being told its NPC has been abandoned mid-action.
##
## An NPC that dies with a tree node RUNNING has to release whatever that node reserved
## — a door it was holding, a spot in a queue, an animation. Without this the reservation
## outlives the NPC and nothing ever clears it.
func _npc_died(_by: StringName) -> void:
	if tree != null and tree.is_running:
		tree.abort(context)


## The context points back at this brain and at the NPC, and this brain holds the
## context: a cycle [method DotNpcBrain.unbind] exists to break. The tree and the
## machine go too, because a node that cached the context would be a second one.
func _npc_unbound() -> void:
	if context != null:
		context.brain = null
		context.agent = null

	context = null
	tree = null
	machine = null
	blackboard = null


# --- Subclass interface -------------------------------------------------------

## Build [member tree] and/or [member machine] here. Called once, on spawn.
func _build() -> void:
	pass


# --- Helpers ------------------------------------------------------------------

## Whether this NPC has had time to react to its current target.
##
## The gate every "shoot at it" branch belongs behind.
##
## [b]Measured from `target_since`, and it used to be `engaged_at`.[/b] Those look like the
## same thing and are not: `engaged_at` is refreshed on EVERY pass in which the target is
## perceived — that is what it is for, because it is what a reclaim asks about — so a
## reaction time measured against it can never elapse for an NPC that can currently see
## somebody. Which is every NPC that would ever act on one.
##
## So this returned **false for ever**, every branch behind it never ran, and nothing
## errored: a bot that never acts on what it sees looks like a bot that is bad rather than
## like one that is broken. `DotNpcInstance.target_since` was added to dot-npc for exactly
## this — it moves when the target CHANGES and not while it is held — and it was found by
## game-playground putting a brain behind dot-npc's senses and watching a hunter sit in
## its ALERT state for ever.
func has_reacted() -> bool:
	if character == null or npc == null:
		return true
	return character.has_reacted(npc.target_since, context.now if context != null else 0.0)


## The nearby positions a separation pass needs, asked of the director.
##
## Duck-typed rather than typed, so this file names one dot-npc class and no more: a
## host that publishes `npcs_near` gets crowd avoidance and one that does not gets an
## empty array, which is the same behaviour as having nobody nearby.
func neighbours(radius: float) -> Array:
	var out: Array = []

	if director == null or npc == null or not npc.is_alive():
		return out

	if not director.has_method(&"npcs_near"):
		return out

	# Queried wider than the spacing, because `npcs_near` measures in 3D and a
	# separation radius is horizontal: an NPC standing on another's head is a body
	# height away in 3D and nothing at all on the floor, so a query at the spacing
	# itself does not return the one pair that most needs pushing apart.
	var found: Variant = director.call(&"npcs_near", npc.position(), radius * 2.0)

	if not (found is Array):
		return out

	for entry in (found as Array):
		var other := entry as DotNpcInstance

		if other != null and other.instance_id != npc.instance_id:
			out.append(other.position())

	return out


## Steers toward [param to] while keeping [param spacing] metres from the neighbours.
##
## The one combination almost every NPC wants and nobody writes correctly the first
## time: a path direction and a separation push, blended, then handed to the mover.
func steer_with_spacing(
	to: Vector3, speed: float, delta: float, spacing: float = 1.6
) -> void:
	if npc == null or not npc.is_alive():
		return

	var goal := to

	if director != null and director.has_method(&"path_toward"):
		var found: Variant = director.call(&"path_toward", npc, path, to)

		if found is Vector3:
			goal = found

	var here := npc.position()
	var wanted := DotNpcAiSteering.seek(here, goal)

	# The NPC's own right as the tie-break for a stack. It differs per NPC because they
	# are facing different ways, so two that end up one on top of the other are shoved
	# in two different directions rather than in the same one — which is what makes them
	# come apart rather than travel as a tower.
	# [b]Derived from `facing()` rather than read off a basis, because an NPC is not
	# always a 3D one.[/b] `node.global_transform.basis.x` does not exist on a [Node2D],
	# and a 2D game reaching this line got "Invalid access to property 'global_transform'"
	# once per NPC per tick. The right of a heading in this addon's plane — see
	# [member DotNpcInstance.node] — is that heading turned a quarter turn about Y, which
	# is the same vector for a 3D body and is defined for both.
	var forward := npc.facing()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var apart := DotNpcAiSteering.separate(here, neighbours(spacing), spacing, right)

	# Separation is weighted below seeking, deliberately. Equal weights give a crowd
	# that spreads out and stops arriving: at a doorway the pushes cancel the seek and
	# the horde mills about outside, which reads as the pathfinder being broken.
	var direction := DotNpcAiSteering.blend([[wanted, 1.0], [apart, 0.6]])

	if direction.length() < 0.001:
		return

	steer_toward(here + direction * 4.0, speed, delta)


func describe() -> Dictionary:
	var out := super.describe()

	out["tree"] = DotNpcAiNode.Status.keys()[last_status] if tree != null else "-"
	out["machine"] = machine.describe() if machine != null else "-"
	out["knows"] = blackboard.size() if blackboard != null else 0

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if machine != null:
		out.append_array(machine.describe_lines(context.now if context != null else 0.0))

	if tree != null:
		out.append_array(tree.describe_lines())

	return out

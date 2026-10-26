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

## The character as the game made it, before the server's [member skill] moved it.
##
## [member character] is the one in force and the one everything reads. This is kept so a
## change to the server's skill is applied to what was authored rather than to what the
## LAST change produced — or turning skill up and back down would not come back.
var base_character: DotNpcAiCharacter = null

## The server's adjustment, or null for "as authored". Found on the director — see
## [method DotNpcAiSkill.attach] — or assigned by a game that keeps its own.
var skill: DotNpcAiSkill = null

## Which state the machine starts in. Empty to leave it stopped.
var initial_state: StringName = &""

## What the tree returned on the last tick. For a console command.
var last_status: DotNpcAiNode.Status = DotNpcAiNode.Status.FAILURE

## When a search reached where it was going and started looking round.
const KEY_SEARCH_ARRIVED := &"ai.search_arrived"

## Which remembered enemy a search is after, so a change of quarry restarts it.
const KEY_SEARCH_ID := &"ai.search_id"

## The heading it arrived on, which the look-round sweeps either side of.
const KEY_SEARCH_HEADING := &"ai.search_heading"

## How close to the last known position counts as having got there, horizontally.
var search_arrive_distance: float = 1.5

## The memory id a fight heard but not attributed — an explosion, an ally's brawl — is
## kept under. Somewhere worth going to look, and nobody in particular.
const NOISE := &"#noise"

## Below this [method tactics] an NPC does not call out to its squad, and does not check
## its fire lane for squadmates.
const CALLOUT_TACTICS := 0.2

## Below this [method tactics] an NPC does not know the map: [method patrol_hot] fails.
const PATROL_TACTICS := 0.3

## The squad role every melee or ranged attack branch asks for. See [method claim_role].
const ROLE_ATTACK := &"attack"
const ROLE_SUPPRESS := &"suppress"
const ROLE_FLANK := &"flank"

const KEY_PATROL_GOAL := &"ai.patrol_goal"
const KEY_PATROL_ARRIVED := &"ai.patrol_arrived"
const KEY_PATROL_VISITS := &"ai.patrol_visits"

## What this NPC knows about its enemies — several, how it knows, and where they went.
var memory: DotNpcAiMemory = null

## The world's sounds, found on the director. Null hears nothing.
var sounds: DotNpcAiSounds = null

## Where players go on this map, found on the director. Null patrols nothing.
var heatmap: DotNpcAiHeatmap = null

## Shots this NPC has taken. The seed of each shot's error, so the same shot misses the
## same way on a replay and two shots never miss identically.
var shots_fired: int = 0

## This NPC's squad, or null to fight alone. Joined after `_build` from [member squad_name].
var squad: DotNpcAiSquad = null

## The squad to join. From `"squad"` in the definition's meta unless a game sets it in
## `_build`; empty fights alone. Needs a [DotNpcAiSquads] on the director.
var squad_name: StringName = &""

## How many of a squad may attack one target at once. `"attackers"` in the meta.
var attack_capacity: int = 2

## Fraction of health lost inside [member heavy_damage_window] that is HEAVY_DAMAGE.
var heavy_damage_fraction: float = 0.25

var heavy_damage_window: float = 1.5

## At or below this fraction of health, LOW_HEALTH.
var low_health_fraction: float = 0.3

## Seconds between two reports to the squad about a target still in sight.
var report_interval: float = 0.5

## How far round toward an enemy's back [method surround] aims, in radians, at tactics 1.
## The NPC circles at walking pace; this is how far ahead of it the point it walks at is.
var flank_lead: float = 0.8

## The level-of-detail scheduler this brain asks before thinking, found on [DotRegistry]. Null thinks every tick.
var scheduler: DotNpcAiScheduler = null

## Whether a skipped think keeps walking the last steering target (cheap movement, no sensing).
var cruise_between_thinks: bool = true

## The utility scorer, or null (the default: off). See [method use_utility].
var utility: DotNpcAiUtility = null

var _cruise_on: bool = false
var _thinking: bool = false
var _step_delta: float = 0.0
var _sched_probe: int = 60
var _waypoint: Vector3 = Vector3.INF
var _path_denied: bool = false
var _pg_to: Vector3 = Vector3.ZERO
var _pg_goal: Vector3 = Vector3.INF
var _pg_until: int = -1
var _los_to: Vector3 = Vector3.ZERO
var _los_val: bool = false
var _los_until: int = -1
var _cruising: bool = false
var _cruise_to: Vector3 = Vector3.ZERO
var _cruise_speed: float = 0.0
var _cruise_dest: Vector3 = Vector3.INF
var _had_target: bool = false
var _last_target: StringName = &""
var _pending_damage: float = 0.0
var _damage_log: Array = []
var _last_heard_id: int = 0
var _last_report: float = -INF
var _informed_pending: bool = false
var _report_seq: int = 0
var _danger_at: Vector3 = Vector3.ZERO
var _danger_extent: float = 0.0
var _danger_until: float = -INF
var _facing_at_tick: Vector3 = Vector3.ZERO

## [member skill]'s revision when [member character] was last worked out. -1 for never.
var _skill_revision: int = -1

## The character [method _refresh_character] last produced, so a game that assigns a new
## one mid-life is noticed rather than silently overwritten on the next skill change.
var _applied: DotNpcAiCharacter = null


func _npc_ready() -> void:
	scheduler = _find_scheduler()
	blackboard = DotNpcAiBlackboard.new()
	context = DotNpcAiContext.make(npc, self, blackboard)
	memory = DotNpcAiMemory.new()
	sounds = DotNpcAiSounds.of(director)
	heatmap = DotNpcAiHeatmap.of(director)
	attack_capacity = int(tune(&"attackers", float(attack_capacity)))

	# The definition's squad only when it names one. A game that chose the squad before
	# binding — game-playground puts each player's NPCs in their own — must not have it
	# wiped by a definition that says nothing, which is what this line used to do.
	var named_squad := tune_string(&"squad", "")
	if named_squad != "":
		squad_name = StringName(named_squad)

	# The world's clock, not zero.
	#
	# A brain built ninety seconds into a round with a context starting at zero has
	# every cooldown, timeout and memory lifetime measured against a clock that
	# disagrees with the spawner's — so an NPC spawned late is briefly able to do
	# everything at once, and one spawned early is not. It reads as the cooldowns being
	# ignored on some NPCs and not others.
	if director != null and director.has_method(&"now"):
		context.now = float(director.call(&"now"))

	# A character named in the catalogue, for a brain that did not choose one. Opt-in: a
	# brain with no character and no `skill` in its definition is a legitimate NPC with no
	# reaction time, and turning that into a normal one would change every such game.
	if character == null:
		var named := tune_string(&"skill", "")

		if named != "":
			character = DotNpcAiCharacter.preset(named)

	skill = skill if skill != null else DotNpcAiSkill.of(director)
	_refresh_character()

	_build()

	# Again, for a brain that assigned its character in `_build` — which is too late for
	# the seeding above and used to leave `ctx.character` null for the whole tree. Noticed
	# here rather than documented as a trap: two games' brains carry a paragraph about it.
	_refresh_character()

	# After `_build`, so a game may choose the squad there.
	if squad_name != &"":
		var squads := DotNpcAiSquads.of(director)

		if squads != null:
			squad = squads.squad(squad_name)
			squad.join(self)
			_report_seq = squad.report_seq()

	if machine != null and initial_state != &"":
		var started := machine.go_to(context, initial_state)

		if not started.ok:
			DotLog.warn("npc.ai", "an NPC's initial state does not exist", {
				"state": String(initial_state),
				"why": started.error.message,
			})

	if scheduler != null:
		_join_scheduler()


## Turns utility scoring on with [param config] (ignored unless it is enabled) and gives this NPC its personality for [param role]. Returns the scorer to add actions to.
func use_utility(config: DotNpcAiUtilityConfig, role: StringName = &"") -> DotNpcAiUtility:
	if config == null or not config.enabled:
		utility = null
		return null
	utility = DotNpcAiUtility.new()
	utility.config = config
	utility.npc_seed = npc.seed if npc != null else 0
	utility.personality = config.personality_for(utility.npc_seed, role)
	return utility


## The utility choice for this think, or an empty name with scoring off. Re-scored only once per think, so every gate in a tree shares it.
func utility_choose() -> StringName:
	if utility == null or context == null:
		return &""
	return utility.choose(context.now)


## The scheduler on the registry, or null.
func _find_scheduler() -> DotNpcAiScheduler:
	var found: Object = DotNpcAiScheduler.find()
	return found as DotNpcAiScheduler if found != null and is_instance_valid(found) else null


func _join_scheduler() -> void:
	scheduler.register(self)
	if director != null and director.has_signal(&"target_changed") \
			and not director.is_connected(&"target_changed", scheduler.notice_target):
		director.connect(&"target_changed", scheduler.notice_target)


## The live scheduler or null: a freed one is dropped, and one registered after this brain was bound is found within a second.
func _sched() -> DotNpcAiScheduler:
	if scheduler != null:
		if is_instance_valid(scheduler):
			return scheduler
		scheduler = null

	_sched_probe -= 1
	if _sched_probe <= 0:
		_sched_probe = 60
		scheduler = _find_scheduler()
		if scheduler != null and context != null:
			_join_scheduler()
	return scheduler


func _npc_think(delta: float) -> void:
	if context == null:
		return

	_thinking = false
	var sched := _sched()

	# The delta of every tick skipped since the last think, so cooldowns and timeouts keep real time.
	# Movement keeps the tick's own delta: the skipped ticks were walked by _cruise.
	if sched != null:
		var admitted := sched.admit(self, delta)
		if admitted < 0.0:
			_cruise(delta)
			return
		_step_delta = delta
		_thinking = true
		delta = admitted

	_cruise_on = false
	context.advance(delta)

	_refresh_character()
	_sense()

	if npc != null:
		_facing_at_tick = npc.facing()

	if tree != null:
		last_status = tree.tick(context)

	if machine != null:
		machine.tick(context)

	_thinking = false
	if sched != null and is_instance_valid(sched):
		sched.finish(self)


## Records where this think steered, so a throttled tick can keep walking there.
func steer_toward(to: Vector3, speed: float, delta: float) -> void:
	if _thinking:
		delta = _step_delta

	if not _cruising:
		_cruise_on = true
		_cruise_to = to
		_cruise_speed = speed
		_cruise_dest = Vector3.INF

	super(to, speed, delta)


## [method DotNpcBrain.steer_along_path] that remembers the destination and asks the scheduler for the path.
func steer_along_path(to: Vector3, speed: float, delta: float) -> void:
	if npc == null or not npc.is_alive():
		return

	var goal := _steer_goal(to)
	_cruise_dest = to
	if goal == Vector3.INF:
		return
	steer_toward(goal, speed, delta)
	_cruise_dest = to


## One throttled tick: keep walking the last target. A reached waypoint asks for the next one through the path cache.
func _cruise(delta: float) -> void:
	if not cruise_between_thinks or not _cruise_on or npc == null or not npc.is_alive():
		return

	var here := npc.position()
	var flat := _cruise_to - here
	flat.y = 0.0

	if flat.length() < 1.0 and _cruise_dest != Vector3.INF:
		var rest := _cruise_dest - here
		rest.y = 0.0

		if rest.length() > 1.5:
			var next := _path_goal(_cruise_dest)

			if next != Vector3.INF:
				_cruise_to = next
				flat = next - here
				flat.y = 0.0

	if flat.length() < 0.3:
		return

	_cruising = true
	steer_toward(_cruise_to, _cruise_speed, delta)
	_cruising = false


## The next point on the way to [param to] from the director's path, or INF. Sets [member _path_denied] when the scheduler refused to compute one.
## Calmer tiers reuse a path while the destination drifts less than `path_reuse_m`; allocation-free.
func _path_goal(to: Vector3) -> Vector3:
	_path_denied = false
	if director == null or not director.has_method(&"path_toward"):
		return Vector3.INF

	var sched := _sched()
	if sched == null or not sched.config.enabled:
		return _as_goal(director.call(&"path_toward", npc, path, to))

	var capped := sched.config.cap_tier0_paths
	if sched.tier_of(self) == 0 and not capped:
		return _as_goal(director.call(&"path_toward", npc, path, to))

	var reuse := sched.config.path_reuse_m
	if sched.tick < _pg_until and _pg_to.distance_squared_to(to) <= reuse * reuse:
		sched.stats["cache_hits"] += 1
		return _pg_goal

	if not sched.take_path_slot():
		_path_denied = true
		return Vector3.INF

	var goal := _as_goal(director.call(&"path_toward", npc, path, to))
	if sched.tier_of(self) > 0:
		_pg_to = to
		_pg_goal = goal
		_pg_until = sched.tick + sched.config.path_cache_ticks
	return goal


func _as_goal(found: Variant) -> Vector3:
	if found is Vector3:
		_waypoint = found
		return found
	return Vector3.INF


## Where to steer for [param to]: the path's next point, the target itself when there is no path, the last waypoint
## when the scheduler refused a path this frame (a straight line would cut through walls), or INF to wait.
func _steer_goal(to: Vector3) -> Vector3:
	var goal := _path_goal(to)
	if goal != Vector3.INF:
		return goal
	return _waypoint if _path_denied else to


## Whether the line to [param to] is clear, reusing the answer for a few ticks under a scheduler.
## [param compute] is `func() -> bool`; a tier too calm for sight tests is told no.
func line_clear(to: Vector3, compute: Callable) -> bool:
	var sched := _sched()
	if sched == null or not sched.config.enabled:
		return compute.call()

	if not sched.los_allowed(self):
		sched.stats["los_blocked"] += 1
		return false

	if sched.tick < _los_until and _los_to.distance_squared_to(to) <= 1.0:
		sched.stats["cache_hits"] += 1
		return _los_val

	_los_val = compute.call()
	_los_to = to
	_los_until = sched.tick + sched.config.los_cache_ticks
	sched.stats["los_hits"] += 1
	return _los_val


## Stops the body and the between-thinks walk with it.
func halt() -> void:
	_cruise_on = false
	super()


## Being hurt is information, and it arrives here whatever the subclass does with it.
##
## [b]Overrides `damaged` rather than `_npc_damaged`, deliberately.[/b] Every game brain
## overrides the hook and none of them calls `super`, so behaviour put there would be lost
## in exactly the brains that need it.
func damaged(amount: float, by: StringName) -> void:
	_hurt_by(by, amount)
	var sched := _sched()
	if sched != null:
		sched.wake(self)
	super(amount, by)


## A brain being told its NPC has been abandoned mid-action.
##
## An NPC that dies with a tree node RUNNING has to release whatever that node reserved
## — a door it was holding, a spot in a queue, an animation. Without this the reservation
## outlives the NPC and nothing ever clears it.
func _npc_died(_by: StringName) -> void:
	if tree != null and tree.is_running:
		tree.abort(context)

	# Its attack slot is the next NPC's. A squad whose slots belonged to the dead would
	# stand in a ring round a player for ever.
	if squad != null:
		squad.leave(self)


## The context points back at this brain and at the NPC, and this brain holds the
## context: a cycle [method DotNpcBrain.unbind] exists to break. The tree and the
## machine go too, because a node that cached the context would be a second one.
func _npc_unbound() -> void:
	if scheduler != null and is_instance_valid(scheduler):
		scheduler.unregister(self)
	scheduler = null
	_sched_probe = 1 << 30

	if context != null:
		context.brain = null
		context.agent = null

	context = null
	tree = null
	machine = null
	blackboard = null
	skill = null
	memory = null
	sounds = null
	heatmap = null

	if squad != null:
		squad.leave(self)

	squad = null


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


## The character in force, worked out again only when something changed.
##
## Three things can change it: the game assigned a different one, the server's
## [member skill] moved, or a skill was attached to the director after this NPC spawned.
## Each costs one comparison a tick when nothing did.
func _refresh_character() -> void:
	if skill == null and director != null:
		skill = DotNpcAiSkill.of(director)

	if character != _applied:
		# The game assigned one, at ready or since. It is the new authored character.
		base_character = _seeded(character)
		_skill_revision = -1

	var revision := skill.revision if skill != null else 0

	if _skill_revision == revision and character == _applied:
		return

	_skill_revision = revision
	character = skill.apply(base_character) if skill != null else base_character
	_applied = character

	if context != null:
		context.character = character

	# Alertness is how far THIS one sees, and dot-npc's senses are what look. Until this
	# line nothing read the field at all: every character's alertness was decoration.
	if npc != null:
		npc.sight_scale = character.alertness if character != null else 1.0


## [param from] with this NPC's own seed, unless the game already gave it one.
##
## An NPC whose character still carries the preset's seed is one of twenty identical
## shooters, and the symptom is a volley rather than a fight.
func _seeded(from: DotNpcAiCharacter) -> DotNpcAiCharacter:
	if from == null:
		return null

	# [member DotNpcInstance.seed], never `instance_id`: the object id moves when anything
	# else in the process is created first, and every choice drawn from it moved with it.
	if from.seed_value <= 1 and npc != null and npc.seed != 0:
		return from.with_seed(npc.seed)

	return from


## How long this NPC keeps believing it knows where somebody is. From its character.
func memory_time() -> float:
	return character.memory_time if character != null else 5.0


## How much this NPC thinks ahead and works with others. From its character; 0.5 without.
func tactics() -> float:
	return character.tactics if character != null else 0.5


# --- Sensing ------------------------------------------------------------------

## Everything this NPC notices this tick, before anything decides.
##
## In this order, because each step reads the last: the target (dot-npc's senses have run),
## damage taken since the last think, what can be heard, and what the squad said. The
## conditions it sets are what every guard and [DotNpcAiDecorator.Interrupt] reads.
func _sense() -> void:
	var c := context.conditions
	c.begin_tick()

	if npc == null or not npc.is_alive() or memory == null:
		return

	memory.forget_after = memory_time()

	var now := context.now
	var has_target := npc.has_target()

	if has_target:
		var at := target_position(Vector3.INF)

		# Perceived on this pass, as against held through dot-npc's commitment grace. The
		# senses stamp `target_seen_at` with the director's clock on every pass that sees it.
		var seen := absf(npc.target_seen_at - _world_now()) < 0.0001

		if at != Vector3.INF:
			# Tracked through the grace as well as when seen. During the grace the senses
			# hand the brain the target's position — dot-npc's "follow them round the
			# corner" — and a memory that stopped at the last true sighting would send the
			# NPC BACK to that corner when the grace ran out, which reads as it changing its
			# mind. Remembering what it was acting on means the search starts where the chase
			# ended, and the velocity it carries is the one the target left with.
			var entry := memory.sighted(npc.target_id, at, now)

			if seen:
				_report(entry, now)

		c.set_flag(DotNpcAiConditions.SEE_ENEMY if seen else DotNpcAiConditions.ENEMY_OCCLUDED)

		if npc.target_id != _last_target:
			c.set_flag(DotNpcAiConditions.NEW_ENEMY)
			# Every role on the old one is let go, or a squad's slots fill with NPCs that
			# are attacking somebody else.
			_release_roles_on(_last_target)
			# A new target is a new fight; a search half done for the old one is over.
			_end_search()
	elif _had_target:
		c.set_flag(DotNpcAiConditions.LOST_ENEMY)
		_release_roles_on(_last_target)

	_had_target = has_target
	_last_target = npc.target_id if has_target else &""

	_sense_damage(c)

	if npc.def != null and npc.health_fraction() <= low_health_fraction:
		c.set_flag(DotNpcAiConditions.LOW_HEALTH)

	_listen(c)

	if squad != null and squad.pull_reports:
		_report_seq = squad.pull(self, _report_seq)

	if _informed_pending:
		c.set_flag(DotNpcAiConditions.SQUAD_INFORMED)
		_informed_pending = false

	if has_target and holds_attack_slot():
		c.set_flag(DotNpcAiConditions.HAS_ATTACK_SLOT)

	if squad != null:
		if squad.tokens.enabled:
			squad.token_sight(self, c.has(DotNpcAiConditions.SEE_ENEMY), _world_now())
		squad.sweep(_world_now())


## LIGHT_DAMAGE for any hurt since the last think; HEAVY_DAMAGE when the hurt inside the
## window adds up to [member heavy_damage_fraction] of its health.
##
## A window rather than one hit, because "heavy" is about how fast health is going: three
## quick hits of ten percent are a reason to break off, and one hit of ten percent a minute
## for three minutes is not.
func _sense_damage(c: DotNpcAiConditions) -> void:
	var now := context.now

	if _pending_damage > 0.0:
		c.set_flag(DotNpcAiConditions.LIGHT_DAMAGE)
		_damage_log.append([now, _pending_damage])
		_pending_damage = 0.0

	if _damage_log.is_empty():
		return

	var total := 0.0
	var kept: Array = []

	for hit in _damage_log:
		if now - float(hit[0]) <= heavy_damage_window:
			kept.append(hit)
			total += float(hit[1])

	_damage_log = kept

	var max_health := npc.def.max_health if npc.def != null else 0.0

	if max_health > 0.0 and total >= max_health * heavy_damage_fraction:
		c.set_flag(DotNpcAiConditions.HEAVY_DAMAGE)


## Hears what the world's [DotNpcAiSounds] has said since the last think.
func _listen(c: DotNpcAiConditions) -> void:
	if sounds == null:
		sounds = DotNpcAiSounds.of(director)

		if sounds == null:
			return

	# Nothing said since it last listened: `audible` would return nothing.
	if sounds.last_id() == _last_heard_id:
		if in_danger():
			c.set_flag(DotNpcAiConditions.HEAR_DANGER)
		return

	var world_now := _world_now()
	var hearing := character.alertness if character != null else 1.0
	var here := npc.position()
	var turn_to := Vector3.INF

	for sound in sounds.audible(here, world_now, hearing, _last_heard_id):
		match sound.kind:
			DotNpcAiSounds.Kind.DANGER:
				# The nearest danger wins. A reflex rather than a decision, so there is no
				# reaction gate: an NPC that stood still for its reaction time with a
				# grenade at its feet would read as one that had not noticed.
				if _danger_until < world_now or here.distance_to(sound.position) < here.distance_to(_danger_at):
					_danger_at = sound.position
					_danger_extent = sound.extent
					_danger_until = sound.expires_at

			DotNpcAiSounds.Kind.COMBAT:
				c.set_flag(DotNpcAiConditions.HEAR_COMBAT)
				# Attributed to its maker when the maker is somebody this NPC could fight;
				# otherwise it is a fight somewhere — an ally's, an explosion — and that is
				# still worth going to see.
				var who := sound.owner if _is_enemy(sound.owner) else NOISE
				memory.heard(who, sound.position, context.now)
				turn_to = sound.position

			DotNpcAiSounds.Kind.MOVEMENT:
				if _is_enemy(sound.owner):
					c.set_flag(DotNpcAiConditions.HEAR_ENEMY)
					memory.heard(sound.owner, sound.position, context.now)
					turn_to = sound.position

	_last_heard_id = sounds.last_id()

	if in_danger():
		c.set_flag(DotNpcAiConditions.HEAR_DANGER)

	# Turns toward what it heard when it has nothing better to look at, so its eyes — the
	# sight cone dot-npc checks — can find what its ears did.
	if turn_to != Vector3.INF and not npc.has_target():
		face(turn_to - here)


## Whether [param id] is somebody this NPC could fight: a candidate its director knows.
func _is_enemy(id: StringName) -> bool:
	if id == &"" or director == null or not director.has_method(&"candidate_position"):
		return false

	var found: Variant = director.call(&"candidate_position", id, Vector3.INF)
	return found is Vector3 and found != Vector3.INF


## Tells the squad what it sees, at most every [member report_interval].
##
## [b]Only an NPC with some tactics calls out.[/b] Below [constant CALLOUT_TACTICS] it fights
## alone — the easy preset's dull monster that never tells anybody anything, which is half
## of what makes it easy.
func _report(entry: DotNpcAiMemory.Entry, now: float) -> void:
	if squad == null or tactics() < CALLOUT_TACTICS:
		return

	if now - _last_report < report_interval:
		return

	_last_report = now
	squad.report(self, entry.id, entry.position, entry.velocity, now)


## Called by [DotNpcAiSquad.report] when a squadmate saw something. True when it was news.
func _squad_report(
	enemy: StringName, position: Vector3, velocity: Vector3, seen_at: float
) -> bool:
	if memory == null or context == null:
		return false

	var news := memory.informed(enemy, position, velocity, seen_at, context.now)

	if news:
		# A flag rather than the condition itself: this is called during ANOTHER member's
		# think, which may come after this one's, and the condition would be wiped by the
		# next `begin_tick` before anything read it.
		_informed_pending = true

	return news


# --- What it knows ------------------------------------------------------------

## Where its current target — or, with none, the most recent thing it knows about — was
## last known to be. [constant Vector3.INF] when there is nothing.
##
## Infinity rather than zero for "nothing", because zero is the middle of the map: an NPC
## that went looking at the origin would read as a pathfinding bug.
func last_known_position() -> Vector3:
	var entry := _search_entry()
	return entry.position if entry != null else Vector3.INF


## Whether there is somewhere worth looking. The guard for a search branch.
func remembers_target() -> bool:
	return _search_entry() != null


## Forgets what a search would go after, and the search itself.
func forget_target_position() -> void:
	var entry := _search_entry()

	if entry != null:
		memory.forget(entry.id)

	_end_search()


func _search_entry() -> DotNpcAiMemory.Entry:
	if memory == null or context == null:
		return null

	if npc != null and npc.has_target():
		var current := memory.get_entry(npc.target_id, context.now)

		if current != null:
			return current

	return memory.freshest(context.now)


func _end_search() -> void:
	if blackboard == null:
		return

	blackboard.erase(KEY_SEARCH_ARRIVED)
	blackboard.erase(KEY_SEARCH_HEADING)
	blackboard.erase(KEY_SEARCH_ID)


# --- Leaves a game can use ----------------------------------------------------

## Goes to where a lost enemy probably is, then looks round. A ready-made leaf.
##
## RUNNING while walking or looking, SUCCESS once it has looked and found nothing — that
## enemy is forgotten then, so the branch moves on to the next thing remembered or fails —
## and FAILURE when there was nothing to look for. Put it between the fight and the idle
## branch of a reactive selector, and a target perceived during the search takes over on
## the same tick.
##
## [b]Where it PROBABLY is, by [method tactics].[/b] [DotNpcAiMemory] keeps the velocity the
## enemy left with; an NPC with tactics 0 walks to the spot it lost them, and one with
## tactics 1 walks to where they were heading. The first is what players have escaped from
## for twenty-five years by turning two corners. The second is not.
##
## The look-round sweeps either side of the heading it arrived on, for longer the better
## its memory is.
func search(ctx: DotNpcAiContext, speed: float, spacing: float = 1.6) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or blackboard == null or memory == null:
		return DotNpcAiNode.Status.FAILURE

	var entry := _search_entry()

	if entry == null:
		_end_search()
		return DotNpcAiNode.Status.FAILURE

	if blackboard.get_name(KEY_SEARCH_ID, ctx.now, &"") != entry.id:
		# A different thing to look for than last tick: start again.
		_end_search()
		blackboard.put(KEY_SEARCH_ID, entry.id, ctx.now)

	if not blackboard.has(KEY_SEARCH_ARRIVED, ctx.now):
		var goal := memory.predict_entry(entry, ctx.now, tactics())
		var flat := goal - npc.position()
		flat.y = 0.0

		if flat.length() > search_arrive_distance:
			steer_with_spacing(goal, speed, ctx.delta, spacing)
			return DotNpcAiNode.Status.RUNNING

		var facing := npc.facing()
		blackboard.put(KEY_SEARCH_ARRIVED, ctx.now, ctx.now)
		blackboard.put(KEY_SEARCH_HEADING, atan2(facing.z, facing.x), ctx.now)

	var looked := ctx.now - blackboard.get_float(KEY_SEARCH_ARRIVED, ctx.now, ctx.now)

	if looked >= look_round_time():
		memory.forget(entry.id)
		_end_search()
		halt()
		return DotNpcAiNode.Status.SUCCESS

	halt()

	# A sweep of about seventy degrees each way. Facing, not moving: the sight cone is what
	# finds somebody, and the cone points where the NPC faces.
	var heading := blackboard.get_float(KEY_SEARCH_HEADING, ctx.now, 0.0)
	face(DotNpcAiSteering.angle_to_direction(heading + sin(looked * 2.2) * 1.2))

	return DotNpcAiNode.Status.RUNNING


## How long a search looks round once it arrives, from the character's memory.
func look_round_time() -> float:
	return clampf(memory_time() * 0.4, 1.0, 6.0)


## Asks the squad for one of the places attacking the current target. True when it has one.
##
## [b]The question every attack branch should ask first.[/b] With no squad it is always
## yes. [param capacity] defaults to [member attack_capacity], which a catalogue sets with
## `"attackers"`. The slot is kept until the target changes, is lost, or this NPC dies.
var _attack_slot_target: StringName = &""
var _attack_slot_name: StringName = &""


func claim_attack_slot(capacity: int = -1) -> bool:
	return claim_role(ROLE_ATTACK, capacity if capacity >= 0 else attack_capacity)


func holds_attack_slot() -> bool:
	return holds_role(ROLE_ATTACK)


func release_attack_slot() -> void:
	release_role(ROLE_ATTACK)


func _attack_slot() -> StringName:
	return _role_slot(ROLE_ATTACK, npc.target_id)


## Asks the squad for one of [param capacity] places in [param role] against the current
## target. With no squad, always yes. Kept until the target changes or this NPC dies.
##
## [b]Roles are attack slots with names.[/b] A squad that may have two attacking, one
## suppressing and one flanking is four questions with one answer each, and a tree that
## asks them in order — flank if nobody is, suppress if nobody is, otherwise attack or wait
## — gets a squad that splits its work without anybody giving an order.
func claim_role(role: StringName, capacity: int) -> bool:
	if npc == null or not npc.has_target():
		return false

	if squad == null:
		return true

	var slot := _role_slot(role, npc.target_id)

	if role == ROLE_ATTACK and squad.tokens.enabled:
		var held := squad.holds(slot, self)

		if not held and squad.holder_count(slot) >= capacity:
			return false

		if not squad.take_token(self, npc.target_id, _world_now()):
			# A slot taken before tokens were switched on does not outlive the refusal.
			if held:
				squad.release(slot, self)
			return false

		if not squad.claim(slot, self, capacity):
			squad.release_token(self, &"claim", _world_now())
			return false

		return true

	return squad.claim(slot, self, capacity)


func holds_role(role: StringName) -> bool:
	if npc == null or not npc.has_target():
		return false

	return squad == null or squad.holds(_role_slot(role, npc.target_id), self)


func release_role(role: StringName) -> void:
	if squad != null:
		squad.release_prefixed(String(role) + ":", self)


func _role_slot(role: StringName, target: StringName) -> StringName:
	if role != ROLE_ATTACK:
		return StringName(String(role) + ":" + String(target))

	# The attack slot is asked for several times a think; rebuilding its name was an allocation each time.
	if target != _attack_slot_target or _attack_slot_name == &"":
		_attack_slot_target = target
		_attack_slot_name = StringName(String(role) + ":" + String(target))

	return _attack_slot_name


func _release_roles_on(target: StringName) -> void:
	if squad != null and target != &"":
		squad.release_token(self, &"kill", _world_now())
		squad.release_suffixed(":" + String(target), self)


## Holds a place on a ring round the target, sharing the ring out with the rest of the
## squad that is waiting. The leaf for a squad member that has not got an attack slot.
##
## [b]Shared out, not each for itself.[/b] Every waiter on the same target gets its own
## bearing across an arc ([method DotNpcAiTactics.spread_bearings]), so they stand apart
## rather than arriving at one point and stacking. Where the arc is centred is
## [method tactics]: round where the squad already is for a dull one, and round the enemy's
## back — the side away from whoever is hitting it, which is where it is looking — for a
## smart one. A player who turns to face one has turned their back on the attacker.
##
## RUNNING while there is a target; FAILURE when there is none.
func surround(
	ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or not npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var center := target_position(Vector3.INF)

	if center == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var group: Array
	var positions: Array
	var facing: Vector3

	# Who is waiting on this target and which way it faces are the same answer for every
	# waiter in a tick: worked out by the first to ask and shared through the squad.
	var now := _world_now()
	var key := &"" if squad == null else StringName("surround:" + String(npc.target_id))
	var shared: Variant = squad.memo(key, now) if squad != null else null

	if shared is Array and (shared[0] as Array).has(self):
		group = shared[0]
		positions = shared[1]
		facing = shared[2]
	else:
		group = _waiting_with()
		positions = []

		for member in group:
			positions.append(member.npc.position())

		facing = _enemy_facing(center)

		if squad != null:
			squad.remember(key, now, [group, positions, facing])

	var focus := DotNpcAiTactics.mean_bearing(center, positions)

	if facing.length_squared() > 0.0001:
		var behind := atan2(-facing.z, -facing.x)
		focus = lerp_angle(focus, behind, tactics())

	# One place per spacing of arc, measured at the ring's radius.
	var step := clampf(spacing * 1.4 / maxf(radius, 0.5), 0.2, PI)
	var bearings := DotNpcAiTactics.spread_bearings(center, focus, positions, step)
	var mine := group.find(self)
	var bearing := bearings[mine] if mine >= 0 else focus
	var point := DotNpcAiTactics.ring_toward(center, here, radius, bearing, flank_lead)

	var flat := point - here
	flat.y = 0.0

	if flat.length() < 0.6:
		# There — but still apart. A waiter that halts on its spot is one that stays wherever
		# the squad's last shove left it, which is how a ring becomes a heap.
		var forward := npc.facing()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var apart := separation(here, spacing, right)

		if apart.length() > 0.05:
			steer_toward(here + apart * 2.0, speed * 0.5, ctx.delta)
		else:
			halt()

		face(center - here)
		return DotNpcAiNode.Status.RUNNING

	steer_with_spacing(point, speed, ctx.delta, spacing)
	return DotNpcAiNode.Status.RUNNING


## What a member without an attack token does: take the best flanking place on a ring round the target and hold it
## at spacing. With tokens off it is [method surround]. RUNNING while there is a target; FAILURE without one.
func hold_off(
	ctx: DotNpcAiContext, speed: float, radius: float = 4.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if squad == null or not squad.tokens.enabled:
		return surround(ctx, speed, radius, spacing)

	if npc == null or not npc.is_alive() or not npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var center := target_position(Vector3.INF)

	if center == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var allies: Array = []

	for member in _waiting_with():
		if member != self:
			allies.append(member.npc.position())

	var point := DotNpcAiTactics.best_flank(center, _enemy_facing(center), here, radius, allies, squad.tokens)

	if point == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var flat := point - here
	flat.y = 0.0

	if flat.length() < 0.6:
		var forward := npc.facing()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var apart := separation(here, spacing, right)

		if apart.length() > 0.05:
			steer_toward(here + apart * 2.0, speed * 0.5, ctx.delta)
		else:
			halt()

		face(center - here)
		return DotNpcAiNode.Status.RUNNING

	steer_with_spacing(point, speed, ctx.delta, spacing)
	return DotNpcAiNode.Status.RUNNING


## The squad members waiting on the same target as this one, this one included, in a fixed
## order. Alone, or with no squad, just this one.
func _waiting_with() -> Array:
	var out: Array = [self]

	if squad == null or not npc.has_target():
		return out

	var holding := squad.holder_ids(_attack_slot())
	out.clear()

	for member in squad.members():
		var other = member if is_instance_valid(member) else null

		if other == null or other.npc == null or not other.npc.is_alive():
			continue

		if other.npc.target_id != npc.target_id or holding.has(other.get_instance_id()):
			continue

		out.append(other)

	if not out.has(self):
		out.append(self)

	return out


## Which way the enemy at [param center] is probably looking.
##
## At its nearest attacker if a squadmate holds the attack — a player being hit looks at
## what is hitting them — or along its velocity, or nowhere.
func _enemy_facing(center: Vector3) -> Vector3:
	if squad != null and npc.has_target():
		var holding := squad.holder_ids(_attack_slot())
		var nearest := Vector3.INF

		for member in squad.members():
			var other = member if is_instance_valid(member) else null

			if other == null or other == self or other.npc == null or not other.npc.is_alive():
				continue

			if not holding.has(other.get_instance_id()):
				continue

			var at: Vector3 = other.npc.position()

			if nearest == Vector3.INF or at.distance_squared_to(center) < nearest.distance_squared_to(center):
				nearest = at

		if nearest != Vector3.INF:
			var look := nearest - center
			look.y = 0.0

			if look.length_squared() > 0.0001:
				return look.normalized()

	var entry := memory.get_entry(npc.target_id, context.now) if memory != null and npc.has_target() else null

	if entry != null:
		var moving := Vector3(entry.velocity.x, 0.0, entry.velocity.z)

		if moving.length() > 0.5:
			return moving.normalized()

	return Vector3.ZERO


## The best cover from [param threat] within [param max_distance], or [constant Vector3.INF].
##
## From the navigation data dot-npc's generator marked — a cover spot records which way its
## wall is, so "covered from there" needs no raycast — scored by how well it covers against
## how far away it is. [b]Claimed in the squad[/b], one NPC per spot: two NPCs that each pick
## the best cover pick the same one, and the second stands in the open next to the first.
func find_cover(threat: Vector3, max_distance: float = 15.0) -> Vector3:
	var data := _nav_data()

	if data == null or data.cover_count() == 0 or npc == null:
		return Vector3.INF

	var here := npc.position()

	var scorer := func(spot: Vector3, index: int) -> float:
		if (data.cover_flags_of(index) & DotNpcNavData.Cover.IN_COVER) == 0:
			return -INF

		var away := spot.distance_to(here)

		if away > max_distance:
			return -INF

		var to_threat := threat - spot

		if to_threat.length_squared() <= 0.0001:
			return -INF

		var covered := data.cover_normals[index].dot(to_threat.normalized())

		if covered < 0.25:
			return -INF

		if squad != null:
			var slot := StringName("cover:%d" % index)

			if squad.holder_count(slot) > 0 and not squad.holds(slot, self):
				return -INF

		# dot-npc's own weighting: eight metres of walking per unit of facing.
		return covered * 8.0 - away

	var best := DotNpcAiTactics.best_of(data.cover_positions, scorer)

	if best < 0 or is_inf(float(scorer.call(data.cover_positions[best], best))):
		return Vector3.INF

	if squad != null:
		squad.release_prefixed("cover:", self)
		squad.claim(StringName("cover:%d" % best), self, 1)

	return data.cover_positions[best]


## Goes to cover from [param threat] — the target, or the freshest thing remembered, when
## omitted. SUCCESS once there, RUNNING on the way, FAILURE with no cover to go to.
func take_cover(
	ctx: DotNpcAiContext, speed: float, threat: Vector3 = Vector3.INF
) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive():
		return DotNpcAiNode.Status.FAILURE

	var from := threat if threat != Vector3.INF else last_known_position()

	if from == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var spot := find_cover(from)

	if spot == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var flat := spot - npc.position()
	flat.y = 0.0

	if flat.length() <= 0.75:
		halt()
		face(from - npc.position())
		return DotNpcAiNode.Status.SUCCESS

	steer_toward(spot, speed, ctx.delta)
	return DotNpcAiNode.Status.RUNNING


func _nav_data() -> DotNpcNavData:
	if director == null:
		return null

	var graph: Variant = director.get(&"nav")

	if graph is DotNpcNavGraph:
		return (graph as DotNpcNavGraph).data

	return null


# --- Shooting -----------------------------------------------------------------

## Where to aim at the current target from [param muzzle], leading it and missing by this
## character's aim — [method DotNpcAiCharacter.aim_point], fed the velocity this NPC's own
## memory measured rather than the target's true one. [constant Vector3.INF] with no target.
##
## [b]The velocity is what it SAW.[/b] A bot handed the target's real velocity leads a
## player who has just changed direction perfectly, which is the aimbot tell; one leading
## from its own last few sightings is a beat behind a juke, which is what a person is.
##
## Each call is a new shot: the error seed advances, so it is called once per shot taken.
func aim_solution(muzzle: Vector3, travel_speed: float = 0.0) -> Vector3:
	if npc == null or not npc.has_target() or character == null:
		return target_position(Vector3.INF)

	var at := target_position(Vector3.INF)

	if at == Vector3.INF:
		return at

	var entry := memory.get_entry(npc.target_id, context.now) if memory != null else null
	var velocity := entry.velocity if entry != null else Vector3.ZERO
	shots_fired += 1
	return character.aim_point(muzzle, at, velocity, travel_speed, shots_fired)


## Whether this NPC may shoot at its target now.
##
## Every gate a human has, in the order they bite: it can SEE the target (not merely
## remember it), it has had time to react, it is FACING it — within [param tolerance_deg],
## so the turn rate limits how fast it can bring a weapon round — the lane is clear of its
## own squad, and its character's fire throttle lets this one through.
func ready_to_fire(muzzle: Vector3, tolerance_deg: float = 12.0) -> bool:
	if npc == null or not npc.is_alive() or not npc.has_target() or context == null:
		return false

	if not context.has_condition(DotNpcAiConditions.SEE_ENEMY) or not has_reacted():
		return false

	var at := target_position(Vector3.INF)

	if at == Vector3.INF:
		return false

	var to := at - npc.position()
	to.y = 0.0

	if to.length_squared() < 0.0001:
		return true

	if rad_to_deg(npc.facing().angle_to(to.normalized())) > tolerance_deg:
		return false

	if not fire_lane_clear(muzzle, at):
		return false

	return character == null or character.should_fire(context.tick_index)


## Whether a shot from [param from] to [param to] passes clear of every squadmate.
##
## [b]The friendly-fire check, and it is a tactics question.[/b] Below
## [constant CALLOUT_TACTICS] an NPC does not look, and shoots its own squad in the back —
## which is what a dull one does, and what makes a horde of them dangerous to itself.
func fire_lane_clear(from: Vector3, to: Vector3, clearance: float = 0.8) -> bool:
	if squad == null or tactics() < CALLOUT_TACTICS:
		return true

	var lane := to - from
	var length := lane.length()

	if length < 0.001:
		return true

	var along := lane / length

	for member in squad.members():
		var other = member if is_instance_valid(member) else null

		if other == null or other == self or other.npc == null or not other.npc.is_alive():
			continue

		var offset: Vector3 = other.npc.position() - from
		var t: float = offset.dot(along)

		if t <= 0.0 or t >= length:
			continue

		var closest: Vector3 = from + along * t
		var flat: Vector3 = other.npc.position() - closest
		flat.y = 0.0

		if flat.length() < clearance:
			return false

	return true


## Keeps between [param near] and [param far] metres from the target, strafing across it,
## and faces it the whole time. The leaf for anything that fights at range. RUNNING while
## there is a target, FAILURE without one.
##
## [b]Strafing, not standing.[/b] A gunner that stands still at range is a target; one that
## drifts sideways is a harder one, and the direction of the drift flips on a period from
## its own seed so twenty of them do not all slide the same way.
func hold_range(
	ctx: DotNpcAiContext, speed: float, near: float = 8.0, far: float = 16.0, spacing: float = 1.6
) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or not npc.has_target():
		return DotNpcAiNode.Status.FAILURE

	var at := target_position(Vector3.INF)

	if at == Vector3.INF:
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var to := at - here
	to.y = 0.0
	var distance := to.length()

	if distance < 0.001:
		return DotNpcAiNode.Status.RUNNING

	var toward := to / distance
	var side := Vector3(-toward.z, 0.0, toward.x)
	var period := 2.5 + 2.0 * DotNpcAiNode.deterministic_unit(npc.seed, 4421)
	var drift := 1.0 if fmod(ctx.now / period, 2.0) < 1.0 else -1.0
	var wanted := side * drift * 0.6

	if distance > far:
		wanted += toward
	elif distance < near:
		wanted -= toward

	steer_with_spacing(here + wanted.normalized() * 4.0, speed, ctx.delta, spacing)
	face(to)
	return DotNpcAiNode.Status.RUNNING


# --- Learning the map -----------------------------------------------------------

## Walks the places players actually go on this map, and waits at each one facing the way
## they come. A ready-made leaf for when there is nobody to fight and nothing to search.
##
## [b]Knowledge a wanderer does not have.[/b] [DotNpcAiHeatmap] is what the game has learned
## of where players walk; an NPC with [method tactics] of [constant PATROL_TACTICS] or more
## patrols its hottest cells near it, and one below wanders — the dull monster does not
## know the map, which is half of why it is dull. How long it waits at each is its
## character's `camper`: a camper sets up and holds a corridor, a roamer moves on.
##
## RUNNING while patrolling; FAILURE with no heat map, nothing hot near, or too little
## tactics, which hands a selector on to its wander.
func patrol_hot(ctx: DotNpcAiContext, speed: float, radius: float = 40.0) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or blackboard == null:
		return DotNpcAiNode.Status.FAILURE

	if heatmap == null:
		heatmap = DotNpcAiHeatmap.of(director)

	if heatmap == null or tactics() < PATROL_TACTICS:
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var goal: Variant = blackboard.get_value(KEY_PATROL_GOAL, ctx.now, null)

	if not (goal is Vector3):
		var hot := heatmap.hottest(DotNpcAiHeatmap.TRAFFIC, here, radius, _world_now(), 4)

		if hot.is_empty():
			return DotNpcAiNode.Status.FAILURE

		# Not always the hottest: a pick among the top few, from the NPC's own seed and how
		# many it has visited, so a pack does not all stand on one cell and one NPC does not
		# guard the same doorway for ever.
		var visits := blackboard.get_int(KEY_PATROL_VISITS, ctx.now, 0)
		var pick := int(DotNpcAiNode.deterministic_unit(npc.seed, visits + 1) * hot.size())
		goal = Vector3(hot[mini(pick, hot.size() - 1)].x, here.y, hot[mini(pick, hot.size() - 1)].z)
		blackboard.put(KEY_PATROL_GOAL, goal, ctx.now)
		blackboard.erase(KEY_PATROL_ARRIVED)

	var flat: Vector3 = goal - here
	flat.y = 0.0

	if flat.length() > heatmap.cell_size * 0.5 and not blackboard.has(KEY_PATROL_ARRIVED, ctx.now):
		steer_with_spacing(goal, speed, ctx.delta)
		return DotNpcAiNode.Status.RUNNING

	if not blackboard.has(KEY_PATROL_ARRIVED, ctx.now):
		blackboard.put(KEY_PATROL_ARRIVED, ctx.now, ctx.now)

	halt()

	# Facing the way the traffic comes from: an ambusher watches the door, not the wall.
	var flow := heatmap.flow_at(DotNpcAiHeatmap.TRAFFIC, here, _world_now())

	if flow.length_squared() > 0.0001:
		face(flow)

	var camper := character.camper if character != null else 0.2
	var hold := lerpf(2.0, 20.0, camper)

	if ctx.now - blackboard.get_float(KEY_PATROL_ARRIVED, ctx.now, ctx.now) >= hold:
		blackboard.erase(KEY_PATROL_GOAL)
		blackboard.erase(KEY_PATROL_ARRIVED)
		blackboard.put(KEY_PATROL_VISITS, blackboard.get_int(KEY_PATROL_VISITS, ctx.now, 0) + 1, ctx.now)

	return DotNpcAiNode.Status.RUNNING


## Whether a danger it heard is still live.
func in_danger() -> bool:
	return _danger_until >= _world_now()


## Where the live danger is, or [constant Vector3.INF].
func danger_position() -> Vector3:
	return _danger_at if in_danger() else Vector3.INF


## Gets out of a danger's reach and waits there until it is over. A ready-made leaf.
##
## RUNNING while there is a live danger — moving while inside its reach, standing outside
## it — and FAILURE when there is none. Put it first under a reactive root: nothing an NPC
## is doing is worth standing on a grenade for.
func flee_danger(ctx: DotNpcAiContext, speed: float) -> DotNpcAiNode.Status:
	if npc == null or not npc.is_alive() or not in_danger():
		return DotNpcAiNode.Status.FAILURE

	var here := npc.position()
	var away := here - _danger_at
	away.y = 0.0

	if away.length() > _danger_extent + 1.5:
		halt()
		return DotNpcAiNode.Status.RUNNING

	if away.length_squared() < 0.0001:
		away = -npc.facing()

	steer_with_spacing(here + away.normalized() * 6.0, speed, ctx.delta)
	return DotNpcAiNode.Status.RUNNING


# --- Being hurt ---------------------------------------------------------------

## What being hurt by [param by] tells this NPC.
##
## Two things, and neither is "knows exactly where everybody is":
##
## - **With nothing to chase, it turns and goes to look** where the hurt came from. An NPC
##   that keeps wandering while it is shot from behind is one you can farm, and the bug
##   report is "they don't fight back".
## - **Chasing somebody else, it may switch** — by its character's vengefulness, rolled
##   from its own seed so a replay agrees. dot-npc's senses then hold the switch only if
##   the attacker is actually perceived: a rival in sight takes the commitment back on the
##   next pass, so a vengeful NPC cannot be led away from a target it can see by somebody
##   it cannot.
func _hurt_by(by: StringName, amount: float) -> void:
	_pending_damage += maxf(amount, 0.0)

	if by == &"" or npc == null or not npc.is_alive() or memory == null or context == null:
		return

	if director == null or not director.has_method(&"candidate_position"):
		return

	var found: Variant = director.call(&"candidate_position", by, Vector3.INF)

	if not (found is Vector3) or found == Vector3.INF:
		# Not something it could ever target — the world, a trap, another NPC.
		return

	var at: Vector3 = found
	memory.hurt_by(by, at, amount, context.now)

	if npc.target_id == by:
		return

	if not npc.has_target():
		face(at - npc.position())
		return

	if character == null or character.vengefulness <= 0.0:
		return

	var roll := character.unit(context.tick_index * 31 + by.hash())

	if roll < character.vengefulness:
		var now := _world_now()
		npc.target_id = by
		npc.target_since = now
		npc.target_seen_at = now
		npc.engaged_at = now


## The director's clock, which is the one dot-npc's senses stamp targets with.
func _world_now() -> float:
	if director != null and director.has_method(&"now"):
		return float(director.call(&"now"))

	return context.now if context != null else 0.0


# --- Turning ------------------------------------------------------------------

## Turns toward [param direction] no faster than this character can.
##
## [b]Every turn the brain makes goes through here, steering included[/b] — dot-npc's
## `steer_toward` faces the way it moves — so an NPC's sight cone swings at the character's
## [member DotNpcAiCharacter.view_turn_deg]. Without it every NPC snapped round in one tick:
## shot from behind, it faced you before the sound of the shot had finished, and a player
## could not get behind one at all.
##
## Limited from where the NPC faced at the START of the think, so two calls in one tick —
## a steer and then a look — do not turn it twice as far.
func face(direction: Vector3) -> void:
	if character == null or context == null or context.delta <= 0.0 or npc == null:
		super(direction)
		return

	var flat := Vector3(direction.x, 0.0, direction.z)

	if flat.length_squared() < 0.000001:
		return

	var from := _facing_at_tick if _facing_at_tick.length_squared() > 0.0001 else npc.facing()
	super(character.turn_view(from, flat.normalized(), context.delta))



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


## The push away from the neighbours within [param spacing] of [param here]: what
## [method steer_with_spacing] and [method surround] blend in. A host with its own crowd index
## overrides it (see [DotNpcAiCrowdGrid]) to skip building [method neighbours]' array.
func separation(here: Vector3, spacing: float, right: Vector3) -> Vector3:
	return DotNpcAiSteering.separate(here, neighbours(spacing), spacing, right)


## Steers toward [param to] while keeping [param spacing] metres from the neighbours.
##
## The one combination almost every NPC wants and nobody writes correctly the first
## time: a path direction and a separation push, blended, then handed to the mover.
func steer_with_spacing(
	to: Vector3, speed: float, delta: float, spacing: float = 1.6
) -> void:
	if npc == null or not npc.is_alive():
		return

	var goal := _steer_goal(to)

	if goal == Vector3.INF:
		_cruise_dest = to
		return

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
	var apart := separation(here, spacing, right)

	# Separation is weighted below seeking, deliberately. Equal weights give a crowd
	# that spreads out and stops arriving: at a doorway the pushes cancel the seek and
	# the horde mills about outside, which reads as the pathfinder being broken.
	# `DotNpcAiSteering.blend([[wanted, 1.0], [apart, 0.6]])` without its nested arrays.
	var direction := wanted * 1.0 + apart * 0.6
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.001 else Vector3.ZERO

	if direction.length() < 0.001:
		return

	var av := _avoider()
	if av != null:
		var tier := scheduler.tier_of(self) if scheduler != null and is_instance_valid(scheduler) else 0
		var safe: Vector3 = av.steer(npc.instance_id, npc, direction.normalized() * speed, tier)
		if safe.length() > 0.001:
			direction = safe.normalized()

	steer_toward(here + direction * 4.0, speed, delta)
	_cruise_to = goal
	_cruise_dest = to
	_watch_progress(here, to)


## The enabled avoidance node on the registry, or null; looked for about once a second.
func _avoider() -> DotNpcAiAvoidance:
	if _avoid_node != null and is_instance_valid(_avoid_node):
		return _avoid_node if _avoid_node.config.enabled else null
	_avoid_node = null
	_avoid_probe -= 1
	if _avoid_probe <= 0:
		_avoid_probe = 60
		_avoid_node = DotNpcAiAvoidance.find() as DotNpcAiAvoidance
	return _avoid_node if _avoid_node != null and _avoid_node.config.enabled else null


## Seconds an NPC steering at somewhere more than a couple of metres off may make no headway
## before its path is asked for again without smoothing (dot-npc's `DotNpcPath.go_rough`).
var stuck_seconds: float = 1.5

var _progress_at: Vector3 = Vector3.INF
var _avoid_node: DotNpcAiAvoidance = null
var _avoid_probe: int = 0
var _progress_since: float = 0.0


## Notices an NPC that is steering and not getting anywhere, and gives it the graph's own corners
## for a few seconds. A smoothed path on a coarse graph cuts the corner of a door jamb thinner
## than its spacing, and the NPC presses into the jamb for as long as the path lasts: on
## game-zombie-zone's ballpark, specials and commons stood at the tunnels' doors for minutes and
## the waves ended on their overtime. Duck-typed, so an older dot-npc without it is left alone.
func _watch_progress(here: Vector3, goal: Vector3) -> void:
	var now := _world_now()

	# Measured flat: a body hopping on the spot against what stops it is not making headway.
	if _progress_at == Vector3.INF or _flat_length(here - _progress_at) > 0.5 or _flat_length(goal - here) < 2.0:
		_progress_at = here
		_progress_since = now
		return

	if now - _progress_since >= stuck_seconds and path != null and path.has_method(&"go_rough"):
		path.call(&"go_rough", now, 4.0)
		_progress_at = here
		_progress_since = now


static func _flat_length(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func describe() -> Dictionary:
	var out := super.describe()

	out["tree"] = DotNpcAiNode.Status.keys()[last_status] if tree != null else "-"
	out["machine"] = machine.describe() if machine != null else "-"
	out["knows"] = blackboard.size() if blackboard != null else 0
	out["character"] = String(character.id) if character != null else "-"
	out["conditions"] = ", ".join(context.conditions.names()) if context != null else ""
	out["remembers"] = memory.size() if memory != null else 0
	out["squad"] = String(squad_name) if squad != null else "-"
	out["lod_tier"] = scheduler.tier_of(self) if scheduler != null and is_instance_valid(scheduler) else 0

	if utility != null:
		out["utility"] = utility.describe()

	if character != null:
		out["reaction"] = "%.2fs" % character.reaction_time

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if machine != null:
		out.append_array(machine.describe_lines(context.now if context != null else 0.0))

	if tree != null:
		out.append_array(tree.describe_lines())

	if context != null:
		out.append("conditions: %s" % ", ".join(context.conditions.names()))

	if memory != null and context != null:
		for line in memory.describe_lines(context.now):
			out.append("knows: %s" % line)

	if squad != null:
		out.append_array(squad.describe_lines())

	if utility != null:
		out.append_array(utility.describe_lines())

	return out

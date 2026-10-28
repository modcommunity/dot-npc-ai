extends DotNpcBrain

## The fields and constants of [DotNpcAiBrain], split out so the brain file holds behaviour only.
##
## Not a public class: extend [DotNpcAiBrain] (by path, like every brain), never this.

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

## Seconds between reads of the squad's report log under `pull_reports`; 0 reads on every think.
## The log keeps what was missed, so a longer gap only delays news by that much.
var squad_pull_interval: float = 0.0
var _pulled_at: float = -INF
var _danger_at: Vector3 = Vector3.ZERO
var _danger_extent: float = 0.0
var _danger_until: float = -INF
var _facing_at_tick: Vector3 = Vector3.ZERO
var _hurt_look_at: Vector3 = Vector3.INF
var _hurt_look_due: float = 0.0

## [member skill]'s revision when [member character] was last worked out. -1 for never.
var _skill_revision: int = -1

## The character [method _refresh_character] last produced, so a game that assigns a new
## one mid-life is noticed rather than silently overwritten on the next skill change.
var _applied: DotNpcAiCharacter = null

var _attack_slot_target: StringName = &""
var _attack_slot_name: StringName = &""

## Seconds an NPC steering at somewhere more than a couple of metres off may make no headway
## before its path is asked for again without smoothing (dot-npc's `DotNpcPath.go_rough`).
var stuck_seconds: float = 1.5

var _progress_at: Vector3 = Vector3.INF
var _avoid_node: DotNpcAiAvoidance = null
var _avoid_probe: int = 0
var _progress_since: float = 0.0

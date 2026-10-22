class_name DotNpcAiSchedulerConfig
extends DotConfig

## Every number of [DotNpcAiScheduler]. Layered like any DotConfig: defaults, JSON, environment, command line.

## Off by default: a scheduler that is registered but disabled lets every brain think every tick, as before.
@export var enabled: bool = false

@export_group("Budget")
## Milliseconds per frame all admitted brains may spend thinking together.
@export_range(0.1, 100.0, 0.1) var budget_ms: float = 4.0
## Assumed microseconds one think costs until a real one has been measured.
@export_range(1.0, 100000.0, 1.0) var initial_cost_us: float = 100.0

@export_group("Tiers")
## Nearest player closer than this (metres): tier 0, every tick.
@export_range(0.0, 10000.0, 0.5) var full_range: float = 30.0
## Closer than this: tier 1.
@export_range(0.0, 10000.0, 0.5) var mid_range: float = 60.0
## Closer than this: tier 2. Beyond it, tier 3 (asleep).
@export_range(0.0, 10000.0, 0.5) var far_range: float = 120.0
## Extra metres a brain must cross before it moves to a calmer tier, so one on a boundary does not flap.
@export_range(0.0, 100.0, 0.5) var hysteresis: float = 3.0
## Ticks between one brain's thinks at tier 1.
@export_range(1, 1000, 1) var tier1_interval: int = 3
## Ticks between thinks at tier 2.
@export_range(1, 1000, 1) var tier2_interval: int = 10
## Ticks between thinks at tier 3; 0 never thinks at all.
@export_range(0, 10000, 1) var tier3_interval: int = 30
## A brain out of sight of every player is moved this many tiers calmer (needs a visibility source).
@export_range(0, 3, 1) var unseen_penalty: int = 1
## A brain with a target is never calmer than this tier.
@export_range(0, 3, 1) var engaged_max_tier: int = 1
## Ticks between re-working out one brain's tier.
@export_range(1, 1000, 1) var retier_interval: int = 10
## Group the default player lookup reads when no source callable is set.
@export var player_group: String = "players"

@export_group("Queries")
## Tiers above this one are not allowed line-of-sight tests.
@export_range(0, 3, 1) var los_max_tier: int = 1
## Ticks a line-of-sight answer is reused; 0 disables the cache.
@export_range(0, 1000, 1) var los_cache_ticks: int = 3
## Ticks a path is reused; 0 disables the cache.
@export_range(0, 1000, 1) var path_cache_ticks: int = 10
## New path computations allowed per frame, over every brain.
@export_range(1, 1000, 1) var max_paths_per_frame: int = 4


func env_prefix() -> String:
	return "DOT_NPC_AI_SCHED_"


func cli_prefix() -> String:
	return "--npc-ai-sched-"


func validate() -> DotResult:
	if not (full_range <= mid_range and mid_range <= far_range):
		return DotResult.fail(DotError.CODE_INVALID, "tier ranges must rise: full <= mid <= far")
	return DotResult.success(null)

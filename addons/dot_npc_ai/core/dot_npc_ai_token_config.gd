class_name DotNpcAiTokenConfig
extends DotConfig

## Every number of [DotNpcAiSquad]'s attack tokens and flanking. Layered like any DotConfig: defaults, JSON, environment, command line.

## Off by default: with it off a squad hands out only its plain slots, as before.
@export var enabled: bool = false

@export_group("Tokens")
## Attack permissions a squad has in all.
@export_range(0, 64, 1) var pool_size: int = 3
## Most tokens held against one target at once.
@export_range(0, 64, 1) var per_target_cap: int = 2
## Seconds a token may be held before it is taken back.
@export_range(0.1, 600.0, 0.1) var timeout_s: float = 8.0
## Fraction of the timeout randomly shaved per grant, so a squad's tokens do not all expire together.
@export_range(0.0, 0.9, 0.05) var timeout_jitter: float = 0.2
## Seconds without line of sight before the token is taken back.
@export_range(0.0, 60.0, 0.1) var los_loss_s: float = 1.0
## Seconds a member that gave up (or lost) a token must wait before taking one again.
@export_range(0.0, 600.0, 0.1) var retake_cooldown_s: float = 3.0
## Seconds a refused member counts as still waiting; the longest waiter is served first.
@export_range(0.1, 60.0, 0.1) var wait_window_s: float = 1.5
## A refused member that has not asked again within this long (throttled, or gone) does not hold a free token back.
@export_range(0.0, 60.0, 0.05) var waiter_grace_s: float = 0.25
## Seed of the jitter, so a recorded fight replays.
@export var seed: int = 1

@export_group("Flanking")
## Places tried round the target.
@export_range(3, 64, 1) var flank_candidates: int = 12
## Score for being behind the target, against its facing.
@export_range(0.0, 10.0, 0.05) var flank_angle_weight: float = 1.0
## Score taken for each place an ally already stands near.
@export_range(0.0, 10.0, 0.05) var flank_spread_weight: float = 0.8
## Score taken for the walk there, as a fraction of half the ring.
@export_range(0.0, 10.0, 0.05) var flank_travel_weight: float = 0.3
## Metres within which an ally counts as standing at a place.
@export_range(0.1, 20.0, 0.1) var flank_ally_radius: float = 1.6


func env_prefix() -> String:
	return "DOT_NPC_AI_TOKENS_"


func cli_prefix() -> String:
	return "--npc-ai-tokens-"


func validate() -> DotResult:
	if per_target_cap > pool_size:
		return DotResult.fail(DotError.CODE_INVALID, "per_target_cap cannot exceed pool_size")
	return DotResult.success(null)

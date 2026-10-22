# The level-of-detail scheduler

`DotNpcAiScheduler` decides which brains think this frame and how long they may take, so a thousand NPCs cost what the ones a player can notice cost. It is opt-in: with no scheduler registered, or one whose config says `enabled: false` (the default), every brain thinks every tick exactly as before.

## Wiring

The host adds one `DotNpcAiScheduler` node, gives it a `DotNpcAiSchedulerConfig` (`apply_config`), points `players_source` at the players' positions (or puts players in the `players` group) and calls `register_service()`. A `DotNpcAiBrain` finds it on `DotRegistry` when it is bound, registers itself, asks `admit()` before each think and calls `finish()` after. The scheduler's `advance()` runs from an early physics priority; a host that ticks its NPCs elsewhere sets `auto_advance = false` and calls it first.

## Tiers

| Tier | Where | Thinks |
| --- | --- | --- |
| 0 | nearest player within `full_range` | every tick |
| 1 | within `mid_range` | every `tier1_interval` ticks |
| 2 | within `far_range` | every `tier2_interval` ticks, and `los_allowed()` is false |
| 3 | beyond | every `tier3_interval` ticks (0 never) |

A brain no player can see (`visibility_source`) is moved `unseen_penalty` tiers calmer; one with a target is never calmer than `engaged_max_tier`. A brain crosses into a calmer tier only `hysteresis` metres past the edge. Phases come from a hash of the NPC's seed, so thinks spread over the ticks and seeds in steps of ten do not bunch.

A skipped brain returns early from `_npc_think`; the next think gets the time of every tick it missed (at most `max_catchup_s`, and none of the time the scheduler was off), so cooldowns and timeouts keep real time. A grant to think stays until the brain asks, so a host ticking its NPCs slower than `advance()` starves none. Dead brains are granted nothing. With no player known every brain is in `idle_tier` (3), engaged ones at their cap. `wake(brain)` retiers one at once and lets it think this tick; the brain calls it when hurt and when the spawner reports a new target.

## Budget

`budget_ms` is the most all brains together may spend in a frame. `advance()` admits as many as the measured cost of a think allows; `admit()` refuses the rest if the frame's running total would pass the budget. Refused brains are owed a turn and go first next frame, so none starves. Overshoot is at most one think costing more than its estimate.

## Queries

`cached_los(brain, key, compute)` reuses a line-of-sight answer for `los_cache_ticks`, and a tier above `los_max_tier` is told no without a test. `cached_path(key, compute)` reuses a path for `path_cache_ticks` and computes at most `max_paths_per_frame` new ones a frame; past that it returns the stale path or null and sets `path_denied`. `take_path_slot()` spends the same allowance for a caller with its own cache (the brain does, reusing a path while its destination moves less than `path_reuse_m`; `cap_tier0_paths` makes tier 0 spend it too). A tier above `los_max_tier` is told no even when a yes is cached. The brain uses them itself: `steer_with_spacing` and `steer_along_path` reuse a path at tiers 1 and up, and `line_clear(to, compute)` is the cached sight test a game's tree calls.

## Numbers

`examples/npc_ai_scheduler_selftest.tscn`, 1000 fake brains of about 45 us each, players at two points: 46.5 ms a frame unscheduled, 13.7 ms tiered (3.4x), 6.7 ms tiered and capped at 6 ms (7x). Real brains cost differently; the suite prints its own figures every run.

## Between thinks

A throttled brain keeps walking the last point it steered at (`cruise_between_thinks`, on by default): movement only, no sensing, no tree. On reaching a waypoint it asks for the next through the path cache. The next real think clears it, and so does `halt()`, so a tree that stops stops. Movement always uses the tick's own delta, never the catch-up one (that is for cooldowns and timeouts). A refused path request falls back to the last waypoint, or waits a frame, never a straight line through walls. A scheduler registered after a brain was bound is found within about a second; a freed one is dropped.

## Not done

Wiring it into a game is that game's step: the zombie NPC brains first.

# Local avoidance

`DotNpcAiAvoidance` turns the velocity an NPC wants into one that does not walk through the NPCs around it. It is opt-in: with no node registered, or `DotNpcAiAvoidanceConfig.enabled` false (the default), `steer_with_spacing` behaves exactly as before. It sits on top of `DotNpcAiSteering.separate`, which still keeps the resting spacing; this pass is for NPCs that are moving.

## Wiring

The host adds one `DotNpcAiAvoidance` node, gives it a config (`apply_config`) and calls `register_service()`. `DotNpcAiBrain.steer_with_spacing` finds it (looked for about once a second), passes its blended direction through `steer(key, source, want, tier)` and steers to the answer. A game that moves NPCs itself calls `steer()` the same way; `source` is anything with `position()`. Agents are created on their first `steer()` and forgotten `forget_ticks` after their last, so there is nothing to register or free. Walls stay the physics world's job: avoidance sees only other agents.

## Two backends, one call

| Backend | What | Chosen when |
| --- | --- | --- |
| `rvo` | The navigation server's agents (RVO/ORCA in C++): `agent_set_avoidance_enabled`, a velocity in, a safe velocity out by callback one to two physics frames later. No scene nodes. | `backend` is `auto` or `rvo` and `rvo_supported()` is true |
| `separation` | An own pass: a hashed grid, the `max_neighbours` nearest of at most `max_scan` candidates, for each a ray-circle time to collision inside `horizon`, a sidestep scaled by how soon, and a forward floor (`min_forward`) so a pair never both stop. Overlapping bodies are pushed apart. | otherwise |

`rvo_supported()` asks the navigation server for a map and an agent and checks both RIDs are valid (a build without the navigation module, or the dummy server, returns invalid ones). It never looks at a platform name. `backend()` reports what is in use; `rvo_probe` replaces the probe in tests.

### What was verified in Godot 4.7.2

- The classes and the server calls are compiled into the stock web templates: `agent_set_avoidance_callback`, `agent_set_use_3d_avoidance`, `NavigationAgent3D` and `avoidance_enabled` all occur in the `godot.wasm` of both `web_release.zip` (threads) and `web_nothreads_release.zip` in the 4.7.2 export templates. RVO runs inside the navigation server and needs no thread of its own.
- Headless on Linux, two server agents head-on at 4 m/s with a 1.5 s horizon were deflected by the fifth physics frame (`(3.84, 0, -0.79)` and `(-3.92, 0, 0.40)`); the suite's rvo section sends a pair through each other's lane with real physics frames.
- Not verified: a browser run. No web build was executed, so whether the web backend delivers the callback at the same cadence is unmeasured. `auto` therefore picks rvo wherever the probe passes, and `backend: "separation"` is the switch for a game that wants the own pass in the browser. Measure with `describe()` there before relying on it.
- RVO's own cost runs inside the navigation server's physics step and is not in the figures below. The two-frame latency means an NPC reacts a little later than with the own pass.

## Cost

`max_tier` (default 1) is the calmest scheduler tier that is avoided at all; NPCs above it keep their wanted velocity and cost one counter. Tier 1 recomputes every `calm_interval` ticks and reuses its answer between. Per agent the own pass does at most `max_scan` candidate visits and `max_neighbours` contributions, so a pile of two hundred costs what ten do. The grid is a fixed table (`PackedInt32Array` heads and next links) refilled each tick, and positions and velocities sit in packed arrays: nothing is allocated per tick (the suite checks the object count and static memory over 180 frames).

Measured by the suite's cost section, own pass, 250 agents packed 1.6 m apart (all tier 0, the worst case): about 1.6 ms a frame for `advance()` plus 250 `steer()` calls, 0.1 ms of it `advance()`; a tier-skipped `steer()` costs under 0.5 us. The stated budget is 2 ms for 250 on this box under load. Tiering takes that to the NPCs near a player.

## What it does and does not do

- Head-on pair: both take their own right, pass at body width, lose about 1% of the straight-line time.
- A 2.2 m corridor with four each way: all cross, nobody stacks (closest pair 0.78 m of 0.9).
- A clump of thirty starting inside each other: a third fewer deep overlaps and a nearest neighbour of 0.54 m against 0.36 without. This is weaker than a proper separation pass for NPCs that are not moving, which is why `separate` stays.
- Two dense opposing streams of twenty in interleaved lanes arrive without gridlock, but the sidestep can nudge an NPC into the next lane, so some shallow overlaps remain. Wider lanes, or RVO, do better.
- A corridor exactly one body wide has no solution for any local method; that wants a path-level yield.

## Tunables

All in `DotNpcAiAvoidanceConfig` (defaults, JSON, environment, command line): `enabled`, `backend`, `radius`, `horizon`, `max_neighbours`, `neighbour_range`, `max_scan`, `min_forward`, `max_tier`, `calm_interval`, `forget_ticks`, `cell_size`. `describe()` and `describe_lines()` give the backend, agent count, frame cost and the steered, reused, skipped, avoided and pushed counters; the DotLog channel is `npc.ai.avoid`.

## Not done

Wiring it into a game is that game's step (add the node, enable the config). The brain hook is in `steer_with_spacing` only; the other `steer_toward` callers (`surround`, `hold_range`, cover) are not routed through it yet. No browser measurement.

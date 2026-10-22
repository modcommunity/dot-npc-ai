# Utility scoring and personalities

An opt-in layer that scores candidate actions from response curves and picks one, beside the tree and machine rather than replacing them. Off by default: `DotNpcAiUtilityConfig.enabled` is false, and `DotNpcAiBrain.use_utility()` returns null and leaves the brain as it was.

## Pieces

- `DotNpcAiCurve`: linear, quadratic, logistic, inverse and step. The input is mapped from `lo..hi` to 0..1; `shift` moves the curve (a logistic's midpoint, a step's threshold).
- `DotNpcAiUtility`: actions, each a list of considerations (an input key, a curve, a weight 0..1 that pulls a term toward 1). Terms multiply with the compensation factor, so an action with four considerations is not unfairly smaller than one with two. `inputs` is a callable read once per key per evaluation.
- `DotNpcAiPersonality`: action multipliers, curve shifts per consideration key, and a seeded per-NPC wobble fixed for the seed. Built-ins: aggressive, cautious, flanker.
- `DotNpcAiUtilityConfig`: a `DotConfig`, so layered from JSON, environment and command line. Custom personalities are a dictionary (`personalities`), and `assignment` is `none`, `random` (from `pool`, by seed) or `role` (by `role_map`).
- `DotNpcAiUtilityGate`: a tree guard that succeeds while the brain's choice is its action.

## Not flapping

The held action's score is multiplied by `1 + hysteresis_bonus`, and it is kept for `min_hold_s` unless it falls to zero. An exact tie goes to the held action, then to the earlier one.

## Cost

Scoring happens in `choose(now)`, which the brain calls from its think, so a throttled brain scores nothing. Several gates in one think share one evaluation; `cache_s` widens that across thinks. `evaluations`, `cache_hits` and `considerations_scored` count the cost.

## Not done

No game's brain uses it yet; a game builds its actions in `_build` with `use_utility()` and puts gates in its tree. dot-bot's rule choice is not wired.

extends RefCounted

## dot-npc-ai's API level. The rule for bumping it is on [DotAddonApi].
## LEVEL rises by one for anything new a game could call; OLDEST is raised to LEVEL when something callable is removed or changes meaning, since older packs no longer compile.

# 1: before this file existed. 2: map annotations (DotNpcAiNavAnnotations, DotNpcAiNavAnnotator, DotNpcAiNavDebug). 3: DotNpcAiTokenConfig, attack tokens on DotNpcAiSquad, DotNpcAiTactics.best_flank,
# DotNpcAiBrain.hold_off, line_clear and cruise_between_thinks, DotNpcAiScheduler. 4: utility scoring (DotNpcAiCurve, Personality, Utility, UtilityConfig, UtilityGate; DotNpcAiBrain.use_utility, utility_choose).
# 5: DotNpcAiCrowdGrid (per-tick spatial hash), DotNpcAiBrain.separation to override.
const LEVEL := 5
const OLDEST := 1

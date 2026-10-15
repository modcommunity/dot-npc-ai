extends RefCounted

## dot-npc-ai's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: map annotations. DotNpcAiNavAnnotations (links, spots, hiding, chokepoints; to_dict,
#    from_dict, save, load_file, hiding_spots, cover_from, links_of), DotNpcAiNavAnnotator (a
#    DotJob: settings, seeds, declare, cache_key, key_for, kept_polygons, bind_cvars, read_cvars,
#    _keep_link and _hide_score to override, los_fn to assign), DotNpcAiNavDebug.
const LEVEL := 2
const OLDEST := 1

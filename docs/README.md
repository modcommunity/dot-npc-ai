# dot-npc-ai docs

The reasoning behind how an NPC decides, one subject per file. [CLAUDE.md](../CLAUDE.md) has the short rules; these say why.

| File | What it covers |
| --- | --- |
| [decisions.md](decisions.md) | Why a separate addon, the RUNNING rule and `abort()`, reactive selectors and sequences, the state machine, the decorators, the blackboard, steering, why NPCs do not collide with each other, the brain's clock, what is deliberately not here |
| [character.md](character.md) | `DotNpcAiCharacter`, the reaction clock, reproducible randomness and per-NPC seeds, `DotNpcAiSkill` and its cvars, alertness and memory, `search()` and being hurt |
| [tactics.md](tactics.md) | Conditions, memory, sounds, squads, cover and turning; shooting gates and aim; roles; the heatmap and its keeper |
| [navigation-annotations.md](navigation-annotations.md) | What a map means to a body walking it, found from any map: drop, jump-up and gap links, hiding spots and cover, chokepoints, which floors count, the cache key, the frame budget, measured results and the next step per game |
| [scheduler.md](scheduler.md) | The opt-in level-of-detail scheduler: tiers, budget, staggered phases, cached line-of-sight and path queries, measured cost |
| [history.md](history.md) | The bugs, and how each looked |

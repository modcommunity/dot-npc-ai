# dot-npc-ai docs

The reasoning behind how an NPC decides, one subject per file. [CLAUDE.md](../CLAUDE.md) has the short rules; these say why.

| File | What it covers |
| --- | --- |
| [decisions.md](decisions.md) | Why a separate addon, the RUNNING rule and `abort()`, reactive selectors and sequences, the state machine, the decorators, the blackboard, steering, why NPCs do not collide with each other, the brain's clock, what is deliberately not here |
| [character.md](character.md) | `DotNpcAiCharacter`, the reaction clock, reproducible randomness and per-NPC seeds, `DotNpcAiSkill` and its cvars, alertness and memory, `search()` and being hurt |
| [tactics.md](tactics.md) | Conditions, memory, sounds, squads, cover and turning; shooting gates and aim; roles; the heatmap and its keeper |
| [history.md](history.md) | The bugs, and how each looked |

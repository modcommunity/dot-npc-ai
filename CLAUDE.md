# dot-npc-ai

**How an NPC decides.** A behaviour tree with real running-state memory, a state machine for the many cases a tree is overkill for, a per-NPC blackboard that forgets, a character table that makes two NPCs on one tree different, the tactical layer (squads, sounds, cover, shooting, a learned heatmap), and the steering an NPC needs once there are ninety of them walking at the same door.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to NPC decisions. The reasoning is in [docs/](docs/README.md).

**Depends on dot-core and dot-npc, and only one file names dot-npc** (`runtime/dot_npc_ai_brain.gd`). Keep it that way: the decision engine is meant to be liftable. [decisions](docs/decisions.md#why-it-is-a-separate-addon)

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/decisions.md](docs/decisions.md) | the tree, the machine, decorators, the blackboard, steering, collision between NPCs, what is deliberately not here |
| [docs/character.md](docs/character.md) | `DotNpcAiCharacter`, randomness, `DotNpcAiSkill`, memory, `search()`, `damaged` |
| [docs/tactics.md](docs/tactics.md) | conditions, sounds, squads, cover, shooting, roles, the heatmap |
| [docs/navigation-annotations.md](docs/navigation-annotations.md) | map annotations: links, hiding spots, cover, chokepoints, islands, the cache |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_npc_ai/tree/` | `DotNpcAiNode`, composites (selector, sequence, random selector, parallel), decorators, leaves |
| `addons/dot_npc_ai/fsm/` | `DotNpcAiMachine`, `DotNpcAiState` |
| `addons/dot_npc_ai/core/` | blackboard, context, conditions, character, skill, memory, sounds, squad(s), heatmap and heat keeper |
| `addons/dot_npc_ai/steer/` | `DotNpcAiSteering` (directions only), `DotNpcAiTactics` (scoring places to stand) |
| `addons/dot_npc_ai/runtime/` | `DotNpcAiBrain`: the one file that joins this to dot-npc |
| `addons/dot_npc_ai/annotate/` | `DotNpcAiNavAnnotator` (a `DotJob` over a `NavigationMesh` and a `World3D`), `DotNpcAiNavAnnotations` (the result, saved per cache key), `DotNpcAiNavDebug` (draws it) |
| `addons/dot_npc_ai/dot_npc_ai_api.gd` | the API level (2: map annotations), preloaded by path like every addon's |
| `fixtures/nav_toy_level.gd` | a level built in code with one of everything the annotator looks for, and the bake DotBotNav would do |
| `tools/annotate_map.gd` | annotates the toy or a saved map (`--source map.res --meta map_meta.json`), prints counts and the slowest slice, photographs it (`--out PREFIX`, under xvfb-run) |
| `examples/npc_ai_selftest.tscn` | the suite; its last sections run twelve real NPCs through a real physics world |
| `tools/trace_surround.gd`, `tools/plot_trace.py` | a top-down trace of a squad moving (`TRACE_KIND=gunner` for the gunner) |

## Running and testing

- Link `addons/dot_core` and `addons/dot_npc` from their repos once ([development setup](../../docs/development-setup.md)), then the family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)) and `timeout 180 godot --headless --path . res://examples/npc_ai_selftest.tscn`. It exits non-zero on failure and takes tens of seconds because of the physics sections.
- **Any change to how a squad moves wants the trace plotted and looked at.** The first surround heaped with every check passing. [tactics](docs/tactics.md#everything-is-automatic-once-the-director-carries-it)
- A change to the brain is not done until the games that use it (game-arena, game-g2gfast, game-playground) still pass; `has_reacted` being false for ever was found from a game.

## Rules that bite

**The tree**

- A node that returned RUNNING is resumed, never restarted. `DotNpcAiNode.tick()` is not overridable: write `_tick`. Composites own the running index. [decisions](docs/decisions.md#the-one-idea)
- An abandoned running node gets `abort()`, and every composite propagates it. A new composite must too. [decisions](docs/decisions.md#the-one-idea)
- Selectors are reactive by default; sequences are not. A guard followed by a RUNNING action is `DotNpcAiSequence.reactive_with()`, or the guard is never asked again. [decisions](docs/decisions.md#reactive-and-the-trap-that-goes-with-it)
- Tree and machine on one brain: the tree runs first. [decisions](docs/decisions.md#the-state-machine-is-not-the-poor-relation)
- Every state that can get stuck wants `DotNpcAiState.timeout`; `max_transitions_per_tick` turns a two-state ping-pong from a server hang into a warning. [decisions](docs/decisions.md#the-state-machine-is-not-the-poor-relation)
- Every RUNNING action that can get stuck wants `TimeLimit` (it aborts, not drops). `Limit` counts finishes; `Repeat`/`UntilFail` run one repetition per tick, never a loop. [decisions](docs/decisions.md#the-decorators)
- `DotNpcAiRandomSelector` chooses on entry and keeps the choice. [decisions](docs/decisions.md#the-decorators)

**Memory and steering**

- Blackboard expiry is on read; a lifetime of 0 means never. A read falls through to `parent`, a write never does. `put(key, value, now, lifetime)`: mind the order. [decisions](docs/decisions.md#memory-that-forgets)
- Never compare a Variant against a sentinel with `!=`; mismatched types are a runtime error. [history](docs/history.md#in-the-addon)
- Steering returns directions and moves nothing. Separation 0.6 against seek 1.0; `blend` normalises; `wander` is a seeded drifting angle. [decisions](docs/decisions.md#steering-and-the-gap-it-fills)
- Separation is horizontal with a `tie_break` from `facing()`, never from a node's basis (2D has none). [decisions](docs/decisions.md#steering-and-the-gap-it-fills)
- `steer_with_spacing` asks for unsmoothed corners after `stuck_seconds` of no headway; what every waiter on one target asks is shared per tick through `DotNpcAiSquad.memo`, keyed by the director's clock. [decisions](docs/decisions.md#steering-and-the-gap-it-fills)
- NPCs go on their own collision layer and do not collide with each other; separation keeps them apart. [decisions](docs/decisions.md#npcs-should-not-collide-with-each-other)
- The brain takes the world's clock from the director, never its own from zero. [decisions](docs/decisions.md#the-brains-clock)

**Character and skill**

- Chance goes through the seeded integer hash, never `randf`; keep the mixer non-negative (`>>` sign-extends). Each NPC gets its own seed (`with_seed()`) from dot-npc's `npc.seed`, never `instance_id` (the object id moves between runs). [character](docs/character.md#the-randomness-is-reproducible-and-that-was-not-free)
- `has_reacted()` measures from `target_since`, never `engaged_at`. [character](docs/character.md#the-reaction-clock-is-target_since-not-engaged_at)
- `nightmare()` keeps reaction above zero and accuracy below one; `npc_reaction_min` floors it. [character](docs/character.md#why-a-tree-alone-is-not-an-npc)
- `DotNpcAiSkill` moves ability, never personality, only in the direction asked, from `base_character`, and lives on the director as metadata, never in `DotRegistry`. `bind_cvars` reads the value back after registering. [character](docs/character.md#the-servers-skill-which-is-not-a-difficulty-setting)
- A new character field must be read by something; `alertness` and `memory_time` were decoration until they were wired to `sight_scale` and memory. [character](docs/character.md#alertness-and-memory_time-reach-the-senses)
- Being hurt is handled in the brain's `damaged`; game brains override `_npc_damaged` without `super`. [character](docs/character.md#memory-search-and-being-hurt)

**Map annotations**

- The annotator takes engine types only; it never names a navigation class of dot-npc or dot-bot. [navigation-annotations](docs/navigation-annotations.md#where-it-sits)
- Rays see a body only after the physics server has stepped with it: wait physics frames before running it. A trimesh with backface collision gives no usable normal; a box hit from inside reports its own start with a zero normal (the solid test uses that). [navigation-annotations](docs/navigation-annotations.md#what-it-finds-and-how)
- Drop and jump-up depth is mesh floor to mesh floor, never to a ray's hit; a lip within a step is not a gap. Both were wrong with every count passing. [navigation-annotations](docs/navigation-annotations.md#looked-at)
- Give it `seeds` (spawns, teleport destinations): without them a sealed map's roof is its largest island. [navigation-annotations](docs/navigation-annotations.md#what-it-finds-and-how)
- Every phase is sliced; a new phase must be too (a browser has only the main thread). Anything that changes the output goes in `settings()` or bumps `VERSION`, or a stale cache is served. [navigation-annotations](docs/navigation-annotations.md#the-frame-budget-and-the-browser)
- Any change to it wants `tools/annotate_map.gd --out` rendered and looked at.

**Tactics**

- Squads and sounds go on the director as metadata (two servers per process). [tactics](docs/tactics.md#everything-is-automatic-once-the-director-carries-it)
- `ready_to_fire` gates in order (seen, reacted, facing, lane, throttle); `aim_solution` leads by the remembered velocity, never the true one. [tactics](docs/tactics.md#shooting-is-gates-then-aim)
- A shot a game builds by hand has no pellets and hits nothing; build it with `DotShot.scatter()`. [tactics](docs/tactics.md#shooting-is-gates-then-aim)
- Heatmap persistence is the server module's decision, never the default; re-adopting the current map reloads without saving. [tactics](docs/tactics.md#learning-the-map)

## Where a game plugs in

| To change | Where |
| --- | --- |
| What an NPC decides | `DotNpcAiBrain` subclass, `_build()`, named by path in the definition |
| Whether it is a tree, a machine, or both | `tree` and `machine` on that brain |
| Whether a branch interrupts a running one | `reactive` on the selector or the sequence |
| A leaf worth naming | `DotNpcAiNode` subclass; the callable leaves are for one-liners |
| What an NPC remembers, and for how long | `DotNpcAiBlackboard.put(key, value, now, lifetime)` |
| What a squad shares | `DotNpcAiBlackboard.parent` |
| How a crowd spaces itself | `DotNpcAiBrain.steer_with_spacing`, and the weights in it |
| How aimless movement looks | `DotNpcAiSteering.wander` |
| Who an NPC is (how fast it notices, how well it shoots) | `DotNpcAiCharacter`, one of its four presets, or `"skill"` in the definition's meta |
| How hard the game is | the character, per NPC; a server moves all of them with `DotNpcAiSkill` (`npc_skill`, `npc_reaction_scale`, `npc_reaction_min`) |
| Where a lost target is looked for, and for how long | `DotNpcAiBrain.search`, and the character's `memory_time` |
| What being hurt by somebody unseen does | `DotNpcAiBrain.damaged` → `_hurt_by`, and the character's `vengefulness` |
| How a chaser closes on a runner | `DotNpcAiSteering.pursue` / `evade` |
| How an NPC gets round the furniture | `DotNpcAiSteering.avoid` / `is_way_clear` |
| What happens when an action gets stuck | `DotNpcAiDecorator.TimeLimit` |
| How an NPC varies what it does | `DotNpcAiRandomSelector`, or `RandomChance` |
| What ends a long action | `DotNpcAiDecorator.Interrupt` over `DotNpcAiConditions`; a game's own conditions from `GAME_FIRST` |
| What an NPC hears | `DotNpcAiSounds.emit` from the game, attached to the director |
| Who fights together, and how many attack at once | `"squad"` and `"attackers"` in the definition's meta, `DotNpcAiSquads` on the director |
| Where the ones not attacking stand | `DotNpcAiBrain.surround`, `flank_lead`, the character's `tactics` |
| Where an NPC hides | `DotNpcAiBrain.find_cover` / `take_cover`, over dot-npc's cover spots |
| How fast an NPC turns | the character's `view_turn_deg` and `view_factor`, through `face` |
| Whether and where it shoots | `ready_to_fire`, `aim_solution`, `fire_lane_clear`; the game resolves the shot |
| How a squad splits the work | `claim_role` with `ROLE_ATTACK`, `ROLE_SUPPRESS`, `ROLE_FLANK` or a game's own |
| How a ranged NPC keeps its distance | `hold_range` |
| What the NPCs learn of a map | `DotNpcAiHeatmap`, kept per map by `DotNpcAiHeatKeeper`; patrolled with `patrol_hot` |
| What a map offers (drops, jumps, hiding spots, cover, chokepoints) | `DotNpcAiNavAnnotator` over the bake, cached by `cache_key()`; `_keep_link`, `_hide_score`, `los_fn`, `declare`, `seeds`, the `npc_nav_*` cvars |

Deliberately not here: an editor, utility scoring of decisions, chat and barks, weapon knowledge, population and pacing (dot-npc-ai-director), formations and orders, animation, pathfinding (dot-npc and dot-bot's DotBotNav; the annotations here only add links and places to them), threading. [decisions](docs/decisions.md#deliberately-not-here)

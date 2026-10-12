# Deciding: the tree, the machine, memory and steering

## Why it is a separate addon

A game that wants a catalogue, a population budget and a chaser does not need a behaviour tree, and making it install one is how an addon family gets a reputation for being heavy. dot-npc's own `DotNpcBrain` is enough for most NPCs in most games.

**Only one file names dot-npc.** Everything in `tree/`, `fsm/`, `steer/` and `core/` names dot-core and nothing else; only `runtime/dot_npc_ai_brain.gd` mentions dot-npc. The decision engine could be lifted into a vehicle, a 2D game or a menu, and the lines that join it to an NPC are the part that could not.

## The one idea

**A behaviour tree is three return values and one hard rule.** The values are SUCCESS, FAILURE and RUNNING; the rule is that a node which returned RUNNING must be *resumed* next tick rather than restarted.

Almost every hand-written tree gets that wrong and it fails **silently**: a sequence whose second child is RUNNING re-runs the first child every tick, so an NPC that was walking through a door re-opens the door sixty times a second, or an attack never finishes because its wind-up restarts. Everything looks alive and nothing completes.

So `DotNpcAiNode.tick()` is not overridable. It records what happened and calls `_tick`, which is what a subclass writes, and `DotNpcAiComposite` owns the running-child index so no composite can forget to.

**And a node abandoned mid-action must be told.** A selector whose higher-priority child becomes viable drops the running one, and an action holding a door, a reservation or an animation has to let go. That is `abort()`, and every composite here propagates it.

## Reactive, and the trap that goes with it

| | |
| --- | --- |
| `DotNpcAiSelector.reactive` | **Default on.** A plain selector resumes at the running child and never re-checks the ones above it, so a zombie that started wandering keeps wandering after a player walks in front of it. Reactive is what almost every game wants at the root. |
| `DotNpcAiSequence.reactive` | **Default off**, and leaving it off is a real trap. |

The commonest thing anybody writes is a guard followed by an action ("have I got a target", then "walk at it") where the action returns RUNNING for ever. A plain sequence resumes at the action and **never asks the guard again**, so the NPC chases a target it no longer has until something else interrupts.

`DotNpcAiSequence.reactive_with()` is the guard idiom; a plain sequence is for steps in order. Reactive is not the default because getting it wrong the other way is the re-opening-door bug, which is louder and easier to see than a guard that is never re-checked.

## The state machine is not the poor relation

A zombie has four states and a shopkeeper has two. Expressing either as a tree gives one branch per state with a guard on each, which is a state machine with extra steps and worse debugging. The tree earns its keep on the NPC with fifteen behaviours and priorities between them, and that NPC is the rare one.

Both may be set on one brain, and **the tree runs first**: a machine holds what the NPC *is* and a tree decides what it does within that, so a reactive branch writing to the blackboard is seen by the machine's transitions on the same tick rather than a tick later.

Two things in `DotNpcAiMachine` that are not decoration:

- **`DotNpcAiState.timeout`.** A state with no way out is the commonest broken NPC there is: an attack whose target died, a search whose destination is unreachable. It is checked before the ordinary transitions so it cannot be starved by one that is always false.
- **`max_transitions_per_tick`.** Two states whose conditions each send the NPC to the other is an infinite loop that **hangs the server** rather than misbehaving, and it is written by accident every time somebody adds a state. The cap turns a hang into a warning, a `thrash_count` and an NPC stuck in one of the two: a bug a person can see.

## The decorators

`TimeLimit` is the one no shipped NPC can do without. Every action that can return RUNNING can get stuck: a walk to a door somebody closed, an attack whose target teleported, a path into a corner. Without a limit the NPC does that one thing until the world changes, and "the zombie in the corner" is the bug report. With one it fails, the selector above it moves on, and nobody files anything. It **aborts** the child rather than dropping it, so whatever the action reserved is let go.

`Limit` counts a child that **finished**, not one that started: counting on entry spends the allowance on a child abandoned in its first tick, and "once" then means "never" for any action long enough to be interrupted. `UntilFail` and `Repeat` both run one repetition per tick rather than looping: a loop here never returns the first time a child succeeds without suspending, and that hangs the server rather than misbehaving.

`DotNpcAiRandomSelector` is the variety a tree with no chance in it cannot have. Three zombies that lose sight of a player all walk to the last place they saw them, arrive together and stand in a row: not a bug in any of them, and obviously wrong to anybody watching. One searching left, one right and one waiting is the whole difference.

**Its choice is made on entry and kept.** Re-rolling a child that returned RUNNING is the addon's own rule broken from the one direction where breaking it is tempting: an NPC that chose to flank re-decides sixty times a second and goes nowhere.

## Memory that forgets

"I last saw the player at that corner" is the most useful thing an NPC can know and the most dangerous thing to keep. An NPC acting on a five-minute-old sighting walks to a corner nobody has been near since the round started, which reads as a broken pathfinder.

So every `DotNpcAiBlackboard` write may carry a lifetime and a read past it is a miss. Expiry happens **on read** rather than in a sweep: a sweep needs somebody to walk ninety dictionaries a tick deleting things nobody was going to look at. A lifetime of 0 means "never expires" (see [character.md](character.md#memory-search-and-being-hurt) for what that does to a forgetful character).

`parent` is the opt-in to a shared board (a squad's, a director's). A read falls through and **a write never does**, because an NPC that could write to its squad's board turns one NPC's mistaken sighting into the squad's belief.

`has()` is asked structurally, never as `get_value(key, now, _MISSING) != _MISSING`: `!=` between mismatched Variant types is a runtime error in GDScript, and comparing against `null` is no better because `null` is a value a caller may store. See [history.md](history.md).

## Steering, and the gap it fills

dot-npc paths and follows; it says nothing about two NPCs that want to be in the same place, because separation is a behaviour rather than a fact about the world. dot-npc names that as a deliberate gap and this is where it is filled.

Every method returns a **desired direction** and moves nothing. A steering library that moved things would have to know what a body is, and that is exactly the dependency this addon does not take.

- **Separation is weighted below seeking** in `DotNpcAiBrain.steer_with_spacing` (0.6 against 1.0). Equal weights give a crowd that spreads out and stops arriving: at a doorway the pushes cancel the seek and the horde mills about outside, which reads as the pathfinder being broken.
- **A horizontal separation cannot separate a stack.** Two NPCs one above the other have a horizontal offset of nothing. `separate()` takes a `tie_break` direction for a degenerate pair, and its range test is horizontal: a 3D test calls a stacked pair "1.8 metres apart" and skips exactly the pair that most needs shoving.
- **The tie-break is the right of the NPC's heading, from `facing()`**, never `node.global_transform.basis.x`: that property does not exist on a `Node2D`, and dot-npc maps 2D bodies onto the XZ plane. Nothing else here touches a node.
- **`wander` is a drifting angle, not a random direction.** A fresh random direction per tick averages to standing still and looks like a seizure; one re-picked every few seconds looks like a patrol route. It is seeded per NPC rather than using a global RNG, because a global one makes an NPC's wandering depend on how many others wandered first, and a replay of the same inputs then produces a different world.
- **`blend` normalises.** Without it an NPC runs faster when two urges happen to agree, which is invisible until somebody wonders why fleeing is quicker than chasing.
- **No headway means rough corners.** `steer_with_spacing` watches its NPC: steering at somewhere over two metres off and not moving half a metre in `stuck_seconds` (1.5), it calls dot-npc's `DotNpcPath.go_rough`, and for four seconds the path is the graph's own corners. A smoothed path on a coarse graph clips a door jamb thinner than its spacing, and game-zombie-zone's specials, which have no climb of their own, pressed into the ballpark's doors until each wave's overtime.
- **What a crowd asks about one target is asked once a tick.** `surround` needs who else waits on the target and which way it faces; each waiter walked the whole squad for both, and asked every member's slots, copying the holder list each time: eighty zombies on twelve survivors was six thousand slot lookups a tick. The first waiter works it out and shares it through `DotNpcAiSquad.memo` / `remember`, keyed by the director's clock (one reading for every member, never a brain's own). The trace (`tools/trace_surround.gd`) ends within centimetres of where it did.

## NPCs should not collide with each other

Not a rule this addon can enforce, and the reason its own fixture puts NPCs on their own collision layer with the world in their mask and not themselves.

Twelve capsules converging on one point **climb each other**. One ends up perched on another's head, `is_on_floor()` says true, the horizontal push is nothing because the horizontal offset is nothing, and it chases perfectly at a dead stop with every number about it correct. Rigid capsule-versus-capsule collision between NPCs also deadlocks a doorway, which is why the horde games that ship do soft avoidance instead.

So: separation keeps NPCs apart, and the physics keeps them out of the walls.

## The brain's clock

`DotNpcAiBrain` takes the world's clock from the director. A brain that started its own at zero measured every cooldown, timeout and memory lifetime against a clock that disagreed with the spawner's, so an NPC spawned late could briefly do everything at once and one spawned early could not. It reads as cooldowns being ignored on some NPCs and not others.

## Deliberately not here

- **No editor.** A behaviour tree built in a graph editor is a real convenience and a real pile of tooling; this family ships pure GDScript with no build step, and `describe_lines()` is what a tree is debugged with instead.
- **No utility scoring of decisions.** A third decision model on top of two is a choice nobody needs before they have shipped an NPC. `DotNpcAiCharacter` is a table of weights and not a scorer: it says what an NPC is like, and the tree still decides. Positions are the exception: `DotNpcAiTactics.best_of` scores places to stand, because "where" is always a trade and a trade written as an if-chain stands in the open.
- **No chat, no barks, no personality beyond the numbers.** That is a game's, and dot-chat's if it wants it.
- **No weapon knowledge in the character.** `aim_point` takes a travel speed and knows nothing else. dot-combat is where a weapon lives, and naming it here would make this addon fail to parse without it.
- **No population or pacing.** That is `dot-npc-ai-director`.
- **No formations or orders.** A squad here shares what it sees, hands out named roles, shares a ring and claims cover; the roles are claimed, never assigned, so there is no leader issuing a plan. Anything that is one ("you two hold the door") is a game's, and roles are the seam it hangs off.
- **No animation.** `DotNpcNetSync.State` is what a client picks one with.
- **No pathfinding.** dot-npc owns that; this steers between the waypoints it gives.
- **No threading.** `DotNpcAiParallel` names the fact that every child gets a tick, not concurrency. An NPC has never needed a scheduler.

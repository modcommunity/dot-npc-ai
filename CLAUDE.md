# dot-npc-ai

**How an NPC decides.** A behaviour tree with real running-state memory, a state machine
for the many cases a tree is overkill for, a per-NPC blackboard that forgets, and the
steering an NPC needs once there are ninety of them walking at the same door.

Depends on **dot-core and dot-npc**. The second dependency is one file: everything in
`tree/`, `fsm/`, `steer/` and `core/` names dot-core and nothing else, and only
`runtime/dot_npc_ai_brain.gd` mentions dot-npc at all. That is deliberate — the decision
engine could be lifted into a vehicle, a 2D game or a menu, and the twenty lines that
join it to an NPC are the part that could not.

## Why it is a separate addon

`nightly-todo.md`'s `[npc-1]` asked for the split and the reason holds: a game that wants
a catalogue, a population budget and a chaser does not need a behaviour tree, and making
it install one is how an addon family gets a reputation for being heavy. dot-npc's own
`DotNpcBrain` is enough for most NPCs in most games.

## The one idea

**A behaviour tree is three return values and one hard rule.** The values are SUCCESS,
FAILURE and RUNNING; the rule is that a node which returned RUNNING must be *resumed*
next tick rather than restarted.

Almost every hand-written tree gets that wrong and it fails **silently**: a sequence
whose second child is RUNNING re-runs the first child every tick, so an NPC that was
walking through a door re-opens the door sixty times a second, or an attack never
finishes because its wind-up restarts. Everything looks alive and nothing completes.

So `DotNpcAiNode.tick()` is not overridable. It records what happened and calls `_tick`,
which is what a subclass writes, and `DotNpcAiComposite` owns the running-child index so
no composite can forget to.

**And a node abandoned mid-action must be told.** A selector whose higher-priority child
becomes viable drops the running one, and an action holding a door, a reservation or an
animation has to let go. That is `abort()`, and every composite here propagates it.

## Reactive, and the trap that goes with it

| | |
| --- | --- |
| `DotNpcAiSelector.reactive` | **Default on.** A plain selector resumes at the running child and never re-checks the ones above it, so a zombie that started wandering keeps wandering after a player walks in front of it. Reactive is what almost every game wants at the root. |
| `DotNpcAiSequence.reactive` | **Default off**, and leaving it off is a real trap. |

The commonest thing anybody writes is a guard followed by an action — "have I got a
target", then "walk at it" — where the action returns RUNNING for ever. A plain sequence
resumes at the action and **never asks the guard again**, so the NPC chases a target it
no longer has until something else interrupts.

That was written into this addon's own fixture on the first pass and the suite caught it
as a zombie that would not go home. `DotNpcAiSequence.reactive_with()` is the guard
idiom; a plain sequence is for steps in order. Reactive is not the default because
getting it wrong the other way is the re-opening-door bug, which is louder and easier to
see than a guard that is never re-checked.

## The state machine is not the poor relation

A zombie has four states and a shopkeeper has two. Expressing either as a tree gives one
branch per state with a guard on each, which is a state machine with extra steps and
worse debugging. The tree earns its keep on the NPC with fifteen behaviours and
priorities between them, and that NPC is the rare one.

Both may be set on one brain, and **the tree runs first**: a machine holds what the NPC
*is* and a tree decides what it does within that, so a reactive branch writing to the
blackboard is seen by the machine's transitions on the same tick rather than a tick
later.

Two things in `DotNpcAiMachine` that are not decoration:

- **`DotNpcAiState.timeout`.** A state with no way out is the commonest broken NPC there
  is — an attack whose target died, a search whose destination is unreachable. It is
  checked before the ordinary transitions so it cannot be starved by one that is always
  false.
- **`max_transitions_per_tick`.** Two states whose conditions each send the NPC to the
  other is an infinite loop that **hangs the server** rather than misbehaving, and it is
  written by accident every time somebody adds a state. The cap turns a hang into a
  warning, a `thrash_count` and an NPC stuck in one of the two — a bug a person can see.

## Memory that forgets

"I last saw the player at that corner" is the most useful thing an NPC can know and the
most dangerous thing to keep. An NPC acting on a five-minute-old sighting walks to a
corner nobody has been near since the round started, which reads as a broken pathfinder.

So every `DotNpcAiBlackboard` write may carry a lifetime and a read past it is a miss.
Expiry happens **on read** rather than in a sweep: a sweep needs somebody to walk ninety
dictionaries a tick deleting things nobody was going to look at.

`parent` is the opt-in to a shared board — a squad's, a director's. A read falls through
and **a write never does**, because an NPC that could write to its squad's board turns
one NPC's mistaken sighting into the squad's belief.

## Steering, and the gap it fills

dot-npc paths and follows; it says nothing about two NPCs that want to be in the same
place, because separation is a behaviour rather than a fact about the world. Its
CLAUDE.md names that as a deliberate gap and this is where it is filled.

Every method returns a **desired direction** and moves nothing. A steering library that
moved things would have to know what a body is, and that is exactly the dependency this
addon does not take.

Three things that are not obvious:

- **Separation is weighted below seeking** in `DotNpcAiBrain.steer_with_spacing` (0.6
  against 1.0). Equal weights give a crowd that spreads out and stops arriving: at a
  doorway the pushes cancel the seek and the horde mills about outside, which reads as
  the pathfinder being broken.
- **`wander` is a drifting angle, not a random direction.** A fresh random direction per
  tick averages to standing still and looks like a seizure; one re-picked every few
  seconds looks like a patrol route. It is also seeded per NPC rather than using a global
  RNG, because a global one makes an NPC's wandering depend on how many others wandered
  first — and a replay of the same inputs then produces a different world.
- **`blend` normalises.** Without it an NPC runs faster when two urges happen to agree,
  which is invisible until somebody wonders why fleeing is quicker than chasing.

## Character, and why a tree alone is not an NPC

A behaviour tree decides *what* to do. Two NPCs running the same tree are the same
NPC — they notice at the same instant, shoot with the same accuracy, and pick the same
branch every time. That is not a tuning problem, it is a missing layer, and every
game that shipped good bots has it.

`DotNpcAiCharacter` is the late-1990s arena shooters' table, read out of the
open-sourced original — which was cloned for this addon and, until now, read for
nothing. Cut down to what is not specific to that engine: the chat characteristics
belong to a game, the weapon-specific aim to
dot-combat, the item weights to the tree, and grapple and weapon-jumping to a movement
model this family does not have.

Three of the fields do work rather than describe intent, and they are the reason it is
a class:

- **`has_reacted`** is the single most important number in the file. A bot that acts on
  the tick it sees you is not hard, it is inhuman — it is the difference every player
  can feel and nobody can name. The original's easiest bots sit near a second and a half; a
  person is about a quarter of one.
- **`aim_point`** leads a moving target by `aim_skill` and misses by `aim_accuracy`,
  as a point on a disc perpendicular to the aim. Partial leading rather than the original's
  thresholds, because a bot at 0.5 that leads half as far as it should misses behind a
  runner — which is what a mediocre player does.
- **`turn_view`** eases toward the wanted direction and then clamps the step. **A bot
  with no turn limit snaps its aim in one tick and is unplayable against**; one with
  only the ease still snaps when the error is large, so both halves are needed.

`nightmare()` deliberately keeps a reaction time above zero and an accuracy below one.
A bot that reacts instantly and never misses is not a harder opponent, it is a
different game, and every shooter that shipped one patched it out.

### The randomness is reproducible, and that was not free

Everything that decides by chance here — aim error, `RandomChance`, the weighted
selector — goes through a hash of two integers rather than `randf`. A server rewinding
to check a shot, a replay being scrubbed and a second run of the same headless test
must agree about what an NPC chose, and a global RNG agrees with none of them: what it
hands out depends on how many other things asked first.

The mixer is kept in the positive half of a signed 64-bit int at every step. GDScript's
`>>` sign-extends, so one that is allowed to go negative shifts ones in from the top and
stops being uniform — which is dot-combat's half-moon bug in a different costume, and
the suite checks all four quadrants rather than the magnitude, because a magnitude check
passes for a half-moon.

**And give each NPC its own seed.** A preset is one resource; twenty NPCs sharing it
share a seed, so every one takes the same shot with the same error at the same moment.
It reads as a firing squad. `with_seed()` is the call, and `DotNpcAiBrain` makes it for
a brain that did not.

## NPCs should not collide with each other

Not a rule this addon can enforce, and the reason its own fixture puts NPCs on their own
collision layer with the world in their mask and not themselves.

Twelve capsules converging on one point **climb each other**. One ends up perched on
another's head, `is_on_floor()` says true, the horizontal push is nothing because the
horizontal offset is nothing, and it chases perfectly at a dead stop with every number
about it correct. Rigid capsule-versus-capsule collision between NPCs also deadlocks a
doorway, which is why the horde games that ship do soft avoidance instead.

So: separation keeps NPCs apart, and the physics keeps them out of the walls.

## The decorators, and the one no shipped NPC can do without

`TimeLimit` is that one. Every action that can return RUNNING can get stuck: a walk to
a door somebody closed, an attack whose target teleported, a path into a corner.
Without a limit the NPC does that one thing until the world changes, and "the zombie in
the corner" is the bug report. With one it fails, the selector above it moves on, and
nobody files anything. It **aborts** the child rather than dropping it, so whatever the
action reserved is let go.

`Limit` counts a child that **finished**, not one that started: counting on entry spends
the allowance on a child abandoned in its first tick, and "once" then means "never" for
any action long enough to be interrupted. `UntilFail` and `Repeat` both run one
repetition per tick rather than looping, for the same reason — a loop here never returns
the first time a child succeeds without suspending, and that hangs the server rather
than misbehaving.

`DotNpcAiRandomSelector` is the variety a tree with no chance in it cannot have. Three
zombies that lose sight of a player all walk to the last place they saw them, arrive
together and stand in a row: not a bug in any of them, and obviously wrong to anybody
watching. One searching left, one right and one waiting is the whole difference.

**Its choice is made on entry and kept.** Re-rolling a child that returned RUNNING is
the addon's own rule broken from the one direction where breaking it is tempting — an
NPC that chose to flank re-decides sixty times a second and goes nowhere.

## Four bugs the suite found while this was being written

All four parsed cleanly.

- **`!=` between two mismatched Variant types is a runtime ERROR in GDScript, not
  `true`.** `DotNpcAiBlackboard.has()` was the textbook sentinel comparison —
  `get_value(key, now, _MISSING) != _MISSING` — and on 4.7.2
  `Vector3.ZERO != some_string_name` pushes
  `Invalid operands 'Vector3' and 'StringName' in operator '!='` and abandons the
  expression. `has()` answered false for every value that was not a StringName. It is now
  asked structurally, and comparing against `null` would have been no better, because
  `null` is a value a caller may legitimately have stored.
- **A guard behind a plain sequence is never re-checked** — the reactive-sequence trap
  above, found as a zombie that would not go home.
- **A horizontal separation cannot separate a stack.** Two NPCs one above the other have
  a horizontal offset of nothing, so the push is nothing. `separate()` now takes a
  `tie_break` direction for a degenerate pair, and its range test is horizontal — a 3D
  test calls a stacked pair "1.8 metres apart" and skips exactly the pair that most needs
  shoving.
- **`DotNpcAiBrain` started its context clock at zero.** A brain built ninety seconds
  into a round measured every cooldown, timeout and memory lifetime against a clock that
  disagreed with the spawner's, so an NPC spawned late could briefly do everything at
  once and one spawned early could not. It reads as cooldowns being ignored on some NPCs
  and not others. It takes the world's clock from the director now.

And two in the suite, both worth as much:

- **A test measured a 3D distance on twelve bodies in free fall** and reported that none
  had arrived. After four seconds they were 78 metres *below* the goal and about fourteen
  from it horizontally, which is exactly where they should have been. It needed a floor
  and a horizontal measure.
- **A timeout test kept its alert switch on**, so the state it timed out into
  transitioned straight back. Correct behaviour, and a test of the wrong thing.

## Validating

```bash
cd godot/dot-npc-ai
ln -s ../../dot-core/addons/dot_core addons/dot_core   # once
ln -s ../../dot-npc/addons/dot_npc addons/dot_npc      # once

godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/dot_core/*' \
  -not -path './addons/dot_npc/*' | \
  while read f; do godot --headless --path . --check-only --script "res://${f#./}"; done

timeout 180 godot --headless --path . res://examples/npc_ai_selftest.tscn
```

164 checks. Exits non-zero on failure. The last two run twelve real NPCs through a real
physics world, which is why the suite takes tens of seconds rather than one.

## `has_reacted()` was false for ever, and nothing errored

**The gate every "act on what you see" branch belongs behind never opened.**
`DotNpcAiBrain.has_reacted()` measured a reaction time from `DotNpcInstance.engaged_at` —
and dot-npc refreshes that field on **every pass in which the target is perceived**, which
is what it is for: `engaged_at` answers "is this NPC still busy", which is the question a
reclaim asks. So `now - engaged_at` was approximately zero on every tick an NPC could see
somebody, which is every tick an NPC would ever act on one.

Every branch behind the gate never ran. Nothing errored anywhere: **a bot that never acts
on what it sees looks like a bot that is bad rather than like one that is broken**, which
is why this survived a suite that tests `DotNpcAiCharacter.has_reacted` directly and
correctly — the character's arithmetic was right the whole time, and the field it was being
handed was the wrong one.

`DotNpcInstance.target_since` was added to dot-npc for this. It is set when `target_id`
**changes** and not while it is held — including the case that looks the same and is not,
re-perceiving the *same* target after a gap, which is not a new commitment and must not
restart the clock or an NPC never finishes reacting to somebody who keeps stepping behind
a pillar.

Found by game-playground putting a `DotNpcAiBrain` behind dot-npc's senses and watching a
hunter sit in its `ALERT` state for ever. The suite now asserts the difference as a number:
`engaged_at` moves, `target_since` does not, and `has_reacted()` becomes true.

## The right of a heading, not the right of a basis

`DotNpcAiBrain.steer_with_spacing` used `npc.node.global_transform.basis.x` as the
tie-break direction for a stack. That property does not exist on a `Node2D`, so a 2D game
reaching this line got "Invalid access to property 'global_transform'" once per NPC per
tick — and dot-npc now supports 2D bodies, mapping them onto the XZ plane.

It is derived from `facing()` now: the right of a heading is that heading turned a quarter
turn about Y, which is the same vector for a 3D body and is defined for both. Nothing else
in this addon touches a node at all, which is what "only one file in it names dot-npc" was
always meant to buy.

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
| Who an NPC is — how fast it notices, how well it shoots | `DotNpcAiCharacter`, or one of its four presets |
| How hard the game is | the character, per NPC. There is no difficulty setting |
| How a chaser closes on a runner | `DotNpcAiSteering.pursue` / `evade` |
| How an NPC gets round the furniture | `DotNpcAiSteering.avoid` / `is_way_clear` |
| What happens when an action gets stuck | `DotNpcAiDecorator.TimeLimit` |
| How an NPC varies what it does | `DotNpcAiRandomSelector`, or `RandomChance` |

## Things deliberately not here

- **No editor.** A behaviour tree built in a graph editor is a real convenience and a
  real pile of tooling; this family ships pure GDScript with no build step, and
  `describe_lines()` is what a tree is debugged with instead.
- **No utility scoring.** A third decision model on top of two is a choice nobody needs
  before they have shipped an NPC. `DotNpcAiCharacter` is a table of weights and not a
  scorer: it says what an NPC is like, and the tree still decides.
- **No chat, no barks, no personality beyond the numbers.** The original's characteristics
  carry a chat file and a typing speed; that is a game's, and dot-chat's if it wants it.
- **No weapon knowledge in the character.** `aim_point` takes a travel speed and knows
  nothing else. The original has per-weapon accuracy tables; dot-combat is where a weapon
  lives, and naming it here would make this addon fail to parse without it.
- **No population or pacing.** That is `dot-npc-ai-director`.
- **No squads beyond a shared blackboard.** Formations, roles and orders are a game's,
  and the shared board is the seam they hang off.
- **No animation.** `DotNpcNetSync.State` is what a client picks one with.
- **No pathfinding.** dot-npc owns that; this steers between the waypoints it gives.
- **No threading.** `DotNpcAiParallel` names the fact that every child gets a tick, not
  concurrency. An NPC has never needed a scheduler.

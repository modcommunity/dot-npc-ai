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

## The server's skill, which is not a difficulty setting

The user-facing ask was "let the server make NPCs smarter or quicker to react", as cvars. The trap is the obvious implementation: a global difficulty that **replaces** each NPC's numbers makes every monster the same monster at a different speed, and the characteristics table exists so that a brute and a stalker are wrong to fight the same way. Two game brains carried a paragraph saying exactly that.

So `DotNpcAiSkill` **moves** each character toward `easy()` or `nightmare()` by a fraction (`npc_skill`, -1..1 or a level name), multiplies reaction times separately (`npc_reaction_scale`, because "too smart" and "too quick" are different complaints), and floors them (`npc_reaction_min`, 0.05 s, for the reason nightmare keeps one above zero). Four things about it are not obvious:

- **Ability moves; personality does not.** Reaction, alertness, memory, aim and turning are how good an NPC is. Aggression, self-preservation and vengefulness are who it is, and a coward that turned brave on a hard server would be a different game.
- **Only in the direction asked for.** A plain lerp toward nightmare makes a kind authored *better* than nightmare at something worse at it as skill goes up — "hard mode made the stalkers slower", for the one kind that was already best. The suite pins it.
- **Applied to what was authored, not to the last result.** The brain keeps `base_character` and re-applies on every `revision` change, or turning skill up and back down would not come back.
- **On the director as node metadata, not in `DotRegistry`.** The registry is per process, and two servers in one process — which every game's suite runs — must not share a difficulty. A brain that spawned before the attach finds it on its next tick.

`bind_cvars` takes a module's `add_cvar` as a Callable and duck-types the cvar it returns, because dot-server is not a dependency of this addon. It reads the value back after registering: a value set from argv before the module loaded is already in the cvar, and a binding that only listened for changes would leave the server saying `hard` while its NPCs are normal. That read-back is a check in the suite, against a fake cvar that starts pre-set.

## Alertness was decoration

Until the skill work, `alertness` was declared, documented ("multiplies the definition's sight range"), carried by every preset — and read by nothing. dot-npc's senses only knew the definition. `DotNpcInstance.sight_scale` was added to dot-npc for it and the brain writes it from the character on every change, so `npc_skill` reaches how far an NPC sees and not only how fast it reacts. Same for `memory_time`: two game brains authored it per kind ("the brute is impossible to shake: twenty seconds") and nothing ever read it.

## Memory, search, and being hurt

The search-the-last-known-spot branch was written three times — game-playground's wave brain and hunter, and this addon's own zombie fixture — each with its own hard-coded lifetime (6, 8, 10 s), none of them the character's. It is the brain's now:

- **The last known position is kept every tick there is a target, including through dot-npc's commitment grace.** During the grace the senses hold the target and `target_position()` answers where they are — dot-npc's existing "follow them round the corner". A memory that stopped at the last true sighting would send the NPC *back* to that corner when the grace ran out, which reads as it changing its mind.
- **A memory of zero is no memory.** The blackboard reads a lifetime of 0 as "never expires", so a forgetful character written straight through would hold a grudge for ever. game-playground's hunter had the neighbouring bug for real: `put(&"last_seen", pos, 8.0)` passed 8.0 as *now* and no lifetime, so its memory never expired.
- **`search()` sweeps, then forgets.** It walks to the spot, faces either side of its arrival heading for `memory_time * 0.4` (clamped 1-6 s), then returns SUCCESS and erases the memory so the branch does not restart. Stopping dead on arrival — what the wave brain did — reads as the NPC never having looked.
- **Being hurt is handled in `damaged`, not `_npc_damaged`.** Every game brain overrides the hook and none calls `super`. With no target the NPC remembers where the hurt came from and turns to it, so the search branch goes to look; chasing somebody else, it switches by a `vengefulness` roll from its own seed. dot-npc's senses then keep the switch only if the attacker is actually perceived, so a vengeful NPC cannot be led away from a target it can see by somebody it cannot. The suite's first version of that check put the attacker 50% further away; the NPC had walked toward the nearer one, the 0.6 switch ratio took the vengeance back on the next pass, and that was the senses being right.

## The tactical layer

The bar was "at least as good as the tactical single-player shooters' NPCs", and those are a handful of systems working together rather than a better tree. Each now has a counterpart here, and each does something theirs did not:

| Theirs | Here | And past it |
| --- | --- | --- |
| Conditions set by sensing, read as schedule interrupts | `DotNpcAiConditions` on the context, filled by the brain before anything runs; `DotNpcAiDecorator.Interrupt` | `became()` for "react once", so a flinch is not interrupted by the hit it is reacting to |
| An enemy memory, several enemies, last known positions | `DotNpcAiMemory`, with how each fact was learned (sight, sound, squad, damage) | A smoothed velocity per enemy, and `search()` goes where a lost enemy was HEADING, by `tactics`. Turning two corners no longer escapes a smart NPC |
| A world sound list: combat, danger, player | `DotNpcAiSounds`, emitted by the game, heard once per sound, scaled by alertness | A danger carries its reach separately from how far it is heard, so a grenade heard across a room is fled only by those inside its blast |
| Squads with attack slots | `DotNpcAiSquad`: slots, shared sightings, a leader by lowest id | Waiters share the ring out (`spread_bearings`) in the order they stand, and a smart squad's arc centres on the enemy's back — "behind" being the side away from whoever is hitting it |
| Cover from hint nodes | `find_cover` over dot-npc's generated cover spots | Claimed per squad, one NPC per spot |
| A maximum yaw speed | `DotNpcAiBrain.face` goes through the character's `turn_view` | Limited from the facing at the start of the think, so a steer and a look in one tick do not turn twice as far |

`DotNpcAiCharacter.tactics` is the one new trait, and the server's skill moves it: whether an NPC calls out to its squad (below 0.2 it does not), how far ahead it predicts a lost enemy, and how hard it works round to a player's back. Easy NPCs are brave idiots; nightmare ones are why a player checks behind them.

**Everything is automatic once the director carries it.** `DotNpcAiSquads` and `DotNpcAiSounds` go on the spawner as metadata (two servers in one process must not share either), a definition names its squad and attack capacity in its meta (`"squad"`, `"attackers"`), and the brain senses, remembers, hears and reports with no game code. What a game writes is the tree: `claim_attack_slot()` as the attack branch's guard, `surround()` beside it, `search()` after the fight, `flee_danger()` first. game-arena, game-g2gfast and game-playground's waves are all built that way now; the arena also turns every rocket in the air into a danger with its splash as the reach, and every player's shot into combat noise owned by the shooter.

Five things found building it, all of which a passing suite had missed or could not see:

- **dot-npc's `face()` turned every 3D NPC's back to where it was going.** `look_at(position - direction)` points -Z — which `facing()` reads — away from the direction, so the sight cone the senses test pointed behind a chasing monster, and arena's 60-to-100-degree monsters lost the player they were running at. Clients never showed it because `DotNpcNetSync.yaw_of` was half a turn out the other way and the two cancelled on screen. Found by this addon's turn-rate check, which asked how far an NPC turned in one tick and was told 180 degrees. Both are fixed together and dot-npc's suite asserts the round trip.
- **`turn_view` could not turn round.** For a target directly behind it rotated about `from × UP` — a horizontal axis — so the bot tipped its head back instead of turning; its own comment said that case had been fixed. Turning round is about UP.
- **`surround` aimed one tick of angle ahead.** The point was a few centimetres away, inside the arrival distance, so a flanker arrived, stopped, and never got round.
- **The first surround heaped.** Every waiter walked at "directly behind", they arrived at one point and halted forty centimetres apart, and every check passed — "on the ring" was true of all three. `tools/trace_surround.gd` plus `tools/plot_trace.py` (standard library only) draw it top-down, and the picture is what showed it; the suite now also asserts the waiters are apart. **Any change to how a squad moves wants that picture looked at**, for the reason the family's notes give for interfaces: motion is a thing no assertion reaches.
- **The vengeance check put the attacker 50% further away** than the NPC's current target; the NPC had walked toward the nearer one, dot-npc's 0.6 switch ratio took the vengeance back on the next pass, and that was the senses being right.

## Shooting, roles, and learning the map

The second round past the tactical shooters' baseline, and the two things a game's NPCs most obviously lacked: they could not fight at range, and they knew nothing about the map they were on.

**Shooting is gates, then aim.** `ready_to_fire` is every gate a person has, in the order they bite: the target is SEEN this tick (not merely remembered), the reaction time has elapsed, the NPC is FACING it within a tolerance — so the turn rate decides how fast it can bring a weapon round, which is the single biggest thing that separates a fair bot from an aimbot — the lane is clear of its own squad, and the character's fire throttle lets the shot through. `aim_solution` then leads the target by the velocity the NPC's own memory measured, not the target's true one: a bot handed the real velocity leads a player who has just juked perfectly, which is the tell; one leading from its last few sightings is a beat behind, which is what a person is.

**The friendly-fire lane is a tactics question.** Below 0.2 an NPC does not check it and shoots its own squad in the back, which is what a dull horde does and what makes it a danger to itself.

**Roles are attack slots with names.** `claim_role(role, capacity)` per target, released together when the target changes (`DotNpcAiSquad.release_suffixed`). A tree that asks in order — break off if hurt, flank if nobody is, otherwise suppress — gets a squad that splits its work with nobody giving an order. game-arena's gunner is exactly that tree, and `tools/trace_surround.gd` with `TRACE_KIND=gunner` draws it: one gunner swings wide round to the far side of the player, the other holds its band and strafes.

**`hold_range` strafes.** A gunner standing still at range is a target; the drift flips on a period from its own seed, so twenty of them do not all slide the same way.

**`DotNpcAiHeatmap` is what the game has learned of where players go** — cells of a few metres, a half-life of ten minutes so it is a picture of recent play, channels by name (`traffic`, `deaths`, or a game's own), `flow_at` for which way the traffic comes from, and JSON in and out. `patrol_hot` walks an NPC's hottest cells near it and waits at each facing the flow — an ambush — for as long as its `camper` says, which is the first thing that ever read `camper`. Below 0.3 tactics an NPC does not know the map and wanders, which is half of what makes the easy preset easy.

**`DotNpcAiHeatKeeper` keeps one per map** — sample on an interval, save on an interval and on the way out, swap on a map change — because every game would write those forty lines and the one that forgets to save before swapping trains map B on map A's corridors. Two things it does that are not obvious, both from building it:

- **Re-adopting the map it already holds reloads without saving first.** A game turns persistence on after the map was adopted with it off (arena's horde is built before its server module loads); saving there would overwrite the file with the few seconds learned since, and a server would forget every map on every restart.
- **Persistence is the server's decision, never the default.** Every suite builds the game, and one that saved would have each run's bots train the next run's NPCs — a suite whose results depend on how many times it has run. game-arena's and game-playground's server modules turn it on; their suites leave nothing in `user://`, and playground's `dedicated`, which loads the module, clears the directory before and after.

Found building it:

- **A shot made by hand traces nothing.** dot-combat traces `pellets`, which a weapon fills and `DotShot.scatter()` builds; arena's first `npc_shoot` resolved, counted and hit nobody. The suite asks "did it hit a player", which is the only question that catches it.
- **dot-combat relocates a shot to where the server believes the shooter is.** The first check fired from a made-up point six metres off and hit the floor at the gunner's feet: the anti-cheat working, and a test of the wrong thing.

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

313 checks. Exits non-zero on failure. The last two run twelve real NPCs through a real
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
| Who an NPC is — how fast it notices, how well it shoots | `DotNpcAiCharacter`, one of its four presets, or `"skill"` in the definition's meta |
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

## Things deliberately not here

- **No editor.** A behaviour tree built in a graph editor is a real convenience and a
  real pile of tooling; this family ships pure GDScript with no build step, and
  `describe_lines()` is what a tree is debugged with instead.
- **No utility scoring of decisions.** A third decision model on top of two is a choice nobody needs before they have shipped an NPC. `DotNpcAiCharacter` is a table of weights and not a scorer: it says what an NPC is like, and the tree still decides. Positions are the exception — `DotNpcAiTactics.best_of` scores places to stand, because "where" is always a trade and a trade written as an if-chain stands in the open.
- **No chat, no barks, no personality beyond the numbers.** The original's characteristics
  carry a chat file and a typing speed; that is a game's, and dot-chat's if it wants it.
- **No weapon knowledge in the character.** `aim_point` takes a travel speed and knows
  nothing else. The original has per-weapon accuracy tables; dot-combat is where a weapon
  lives, and naming it here would make this addon fail to parse without it.
- **No population or pacing.** That is `dot-npc-ai-director`.
- **No formations or orders.** A squad here shares what it sees, hands out named roles, shares a ring and claims cover; the roles are claimed, never assigned, so there is no leader issuing a plan — anything that is one ("you two hold the door") is a game's, and roles are the seam it hangs off.
- **No animation.** `DotNpcNetSync.State` is what a client picks one with.
- **No pathfinding.** dot-npc owns that; this steers between the waypoints it gives.
- **No threading.** `DotNpcAiParallel` names the fact that every child gets a tick, not
  concurrency. An NPC has never needed a scheduler.

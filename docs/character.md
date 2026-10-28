# Character, skill, and memory

## Why a tree alone is not an NPC

A behaviour tree decides *what* to do. Two NPCs running the same tree are the same NPC: they notice at the same instant, shoot with the same accuracy, and pick the same branch every time. That is not a tuning problem, it is a missing layer, and every game that shipped good bots has it.

`DotNpcAiCharacter` is the characteristics table of the late-1990s arena shooters' bots, read out of an open-sourced original. It is cut down to what is not specific to that engine: the chat characteristics belong to a game, the weapon-specific aim to dot-combat, the item weights to the tree, and grapple and weapon-jumping to a movement model this family does not have.

Three of the fields do work rather than describe intent, and they are the reason it is a class:

- **`has_reacted`** is the single most important number in the file. A bot that acts on the tick it sees you is not hard, it is inhuman: it is the difference every player can feel and nobody can name. The original's easiest bots sit near a second and a half; a person is about a quarter of one.
- **`aim_point`** leads a moving target by `aim_skill` and misses by `aim_accuracy`, as a point on a disc perpendicular to the aim. Partial leading rather than thresholds, because a bot at 0.5 that leads half as far as it should misses behind a runner, which is what a mediocre player does.
- **`turn_view`** eases toward the wanted direction and then clamps the step. **A bot with no turn limit snaps its aim in one tick and is unplayable against**; one with only the ease still snaps when the error is large, so both halves are needed. Turning round (a target directly behind) is a rotation about UP, never about `from × UP`, which tips the head back instead.

`nightmare()` deliberately keeps a reaction time above zero and an accuracy below one. A bot that reacts instantly and never misses is not a harder opponent, it is a different game, and every shooter that shipped one patched it out.

## The reaction clock is `target_since`, not `engaged_at`

`DotNpcAiBrain.has_reacted()` measures from `DotNpcInstance.target_since`, which dot-npc sets when `target_id` **changes** and not while it is held, including re-perceiving the *same* target after a gap (not a new commitment; restarting the clock would mean an NPC never finishes reacting to somebody who keeps stepping behind a pillar). `engaged_at` is refreshed on every pass the target is perceived, because it answers "is this NPC still busy"; measuring from it kept the gate shut for ever. The story is in [history.md](history.md#has_reacted-was-false-for-ever).

## The randomness is reproducible, and that was not free

Everything that decides by chance here (aim error, `RandomChance`, the weighted selector) goes through a hash of two integers rather than `randf`. A server rewinding to check a shot, a replay being scrubbed and a second run of the same headless test must agree about what an NPC chose, and a global RNG agrees with none of them: what it hands out depends on how many other things asked first.

The mixer is kept in the positive half of a signed 64-bit int at every step. GDScript's `>>` sign-extends, so one that is allowed to go negative shifts ones in from the top and stops being uniform: dot-combat's half-moon bug in a different costume. The suite checks all four quadrants rather than the magnitude, because a magnitude check passes for a half-moon.

**Give each NPC its own seed.** A preset is one resource; twenty NPCs sharing it share a seed, so every one takes the same shot with the same error at the same moment. It reads as a firing squad. `with_seed()` is the call, and `DotNpcAiBrain` makes it for a brain that did not, from `npc.seed`. That is dot-npc's per-spawn seed and never the engine object id, which moves whenever anything else is allocated first, so a replay would disagree with its recording. A brain that seeds itself does the same: `with_seed(npc.seed)`, and `deterministic_unit(npc.seed, salt)` for its own rolls.

## The server's skill, which is not a difficulty setting

The ask was "let the server make NPCs smarter or quicker to react", as cvars. The trap is the obvious implementation: a global difficulty that **replaces** each NPC's numbers makes every monster the same monster at a different speed, and the characteristics table exists so that a brute and a stalker are wrong to fight the same way.

So `DotNpcAiSkill` **moves** each character toward `easy()` or `nightmare()` by a fraction (`npc_skill`, -1..1 or a level name), multiplies reaction times separately (`npc_reaction_scale`, because "too smart" and "too quick" are different complaints), and floors them (`npc_reaction_min`, 0.05 s, for the reason nightmare keeps one above zero).

- **Ability moves; personality does not.** Reaction, alertness, memory, aim, turning and `tactics` are how good an NPC is. Aggression, self-preservation and vengefulness are who it is, and a coward that turned brave on a hard server would be a different game.
- **Only in the direction asked for.** A plain lerp toward nightmare makes a kind authored *better* than nightmare at something worse at it as skill goes up ("hard mode made the stalkers slower"). The suite pins it.
- **Applied to what was authored, not to the last result.** The brain keeps `base_character` and re-applies on every `revision` change, or turning skill up and back down would not come back.
- **On the director as node metadata, not in `DotRegistry`.** The registry is per process, and two servers in one process (which every game's suite runs) must not share a difficulty. A brain that spawned before the attach finds it on its next tick.

`bind_cvars` takes a module's `add_cvar` as a Callable and duck-types the cvar it returns, because dot-server is not a dependency. It **reads the value back after registering**: a value set from argv before the module loaded is already in the cvar, and a binding that only listened for changes would leave the server saying `hard` while its NPCs are normal. The suite checks it against a fake cvar that starts pre-set.

## Alertness and memory_time reach the senses

The brain writes `DotNpcInstance.sight_scale` from the character's `alertness` on every change, so `npc_skill` reaches how far an NPC sees and not only how fast it reacts. `memory_time` sets how long the brain's memory holds a lost enemy. Both were once declared, documented, carried by every preset and read by nothing; a character field that nothing reads is the thing to check for when adding one.

## Memory, search, and being hurt

The search-the-last-known-spot branch is the brain's, so games stop writing it with their own hard-coded lifetimes:

- **The last known position is kept every tick there is a target, including through dot-npc's commitment grace.** During the grace the senses hold the target and `target_position()` answers where they are (dot-npc's "follow them round the corner"). A memory that stopped at the last true sighting would send the NPC *back* to that corner when the grace ran out, which reads as it changing its mind.
- **A memory of zero is no memory.** The blackboard reads a lifetime of 0 as "never expires", so a forgetful character written straight through would hold a grudge for ever. Also watch the argument order of `put(key, value, now, lifetime)`: passing the lifetime as `now` leaves a memory that never expires.
- **`search()` sweeps, then forgets.** It walks to the spot, faces either side of its arrival heading for `memory_time * 0.4` (clamped 1-6 s), then returns SUCCESS and erases the memory so the branch does not restart. Stopping dead on arrival reads as the NPC never having looked.
- **Being hurt is handled in `damaged`, not `_npc_damaged`.** Game brains override the hook and none calls `super`. With no target the NPC remembers where the hurt came from and turns to it, so the search branch goes to look; chasing somebody else, it switches by a `vengefulness` roll from its own seed. dot-npc's senses then keep the switch only if the attacker is actually perceived, so a vengeful NPC cannot be led away from a target it can see by somebody it cannot. A test of this must put the attacker no further than the current target, or dot-npc's 0.6 switch ratio correctly takes the vengeance back.

## Human unevenness: hesitate, glance and their friends

Characters carry `reaction_jitter`, `overshoot`, `track_lag`, `strafe_jitter`, `glance`, `hesitate` and `hurt_delay`, all multiplied by the server cvar `npc_humanise` (default 1; 0 restores the plain behaviour exactly, and the suite pins it). Every roll comes from the NPC's own seed, so a replay agrees.

- **`hesitate`** is a short stand-still after committing to a target, measured from `target_since` and capped by the effective reaction so it only fills time the NPC was not going to act in. It is honoured by `hold_range`, `surround` and `hold_off` (both the token path and the one that delegates to `surround`). `flee_danger` and `patrol_hot` do not hesitate: running from danger must not wait.
- **`glance`** is a look aside held for about a second, in windows of 3 to 6 seconds, up to 90 degrees. It is applied by `patrol_hot` while holding an ambush place and by the `search()` look-round, where it is added to the sweep. Leaves that are moving never glance, because the body faces where it goes.
- A new leaf that stands still should ask `character.glance_offset(now)`, and one that starts an attack should ask `character.is_hesitating(npc.target_since, now)`.

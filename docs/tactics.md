# The tactical layer: squads, sound, shooting, and the map

## Against the tactical shooters' NPCs

The bar was "at least as good as the tactical single-player shooters' NPCs", and those are a handful of systems working together rather than a better tree. Each has a counterpart here, and each does something theirs did not:

| Theirs | Here | And past it |
| --- | --- | --- |
| Conditions set by sensing, read as schedule interrupts | `DotNpcAiConditions` on the context, filled by the brain before anything runs; `DotNpcAiDecorator.Interrupt` | `became()` for "react once", so a flinch is not interrupted by the hit it is reacting to |
| An enemy memory, several enemies, last known positions | `DotNpcAiMemory`, with how each fact was learned (sight, sound, squad, damage) | A smoothed velocity per enemy, and `search()` goes where a lost enemy was HEADING, by `tactics`. Turning two corners does not escape a smart NPC |
| A world sound list: combat, danger, player | `DotNpcAiSounds`, emitted by the game, heard once per sound, scaled by alertness | A danger carries its reach separately from how far it is heard, so a grenade heard across a room is fled only by those inside its blast |
| Squads with attack slots | `DotNpcAiSquad`: slots, shared sightings, a leader by lowest id | Waiters share the ring out (`spread_bearings`) in the order they stand, and a smart squad's arc centres on the enemy's back ("behind" being the side away from whoever is hitting it) |
| Cover from hint nodes | `find_cover` over dot-npc's generated cover spots | Claimed per squad, one NPC per spot |
| A maximum yaw speed | `DotNpcAiBrain.face` goes through the character's `turn_view` | Limited from the facing at the start of the think, so a steer and a look in one tick do not turn twice as far |

`DotNpcAiCharacter.tactics` is the one trait added for this, and the server's skill moves it: whether an NPC calls out to its squad (below 0.2 it does not), how far ahead it predicts a lost enemy, and how hard it works round to a player's back. Easy NPCs are brave idiots; nightmare ones are why a player checks behind them.

## Everything is automatic once the director carries it

`DotNpcAiSquads` and `DotNpcAiSounds` go on the spawner as metadata (two servers in one process must not share either), a definition names its squad and attack capacity in its meta (`"squad"`, `"attackers"`), and the brain senses, remembers, hears and reports with no game code. What a game writes is the tree: `claim_attack_slot()` as the attack branch's guard, `surround()` beside it, `search()` after the fight, `flee_danger()` first. game-arena, game-g2gfast and game-playground's waves are built that way; the arena also turns every rocket in the air into a danger with its splash as the reach, and every player's shot into combat noise owned by the shooter.

`surround` aims at a point on the ring far enough ahead to be outside the arrival distance; one tick of angle ahead is a few centimetres, so a flanker arrives, stops, and never gets round.

**Any change to how a squad moves wants a picture looked at.** `tools/trace_surround.gd` plus `tools/plot_trace.py` (standard library only) draw it top-down (`TRACE_KIND=gunner` for the gunner). The first surround heaped: every waiter walked at "directly behind", they halted forty centimetres apart, and every check passed because "on the ring" was true of all three. The suite now also asserts the waiters are apart, but motion is a thing no assertion reaches ([family testing notes](../../../docs/testing.md)).

## Shooting is gates, then aim

`ready_to_fire` is every gate a person has, in the order they bite: the target is SEEN this tick (not merely remembered), the reaction time has elapsed, the NPC is FACING it within a tolerance (so the turn rate decides how fast it can bring a weapon round, which is the biggest thing that separates a fair bot from an aimbot), the lane is clear of its own squad, and the character's fire throttle lets the shot through. `aim_solution` then leads the target by the velocity the NPC's own memory measured, not the target's true one: a bot handed the real velocity leads a player who has just juked perfectly, which is the tell; one leading from its last few sightings is a beat behind, which is what a person is.

**The friendly-fire lane is a tactics question.** Below 0.2 an NPC does not check `fire_lane_clear` and shoots its own squad in the back, which is what a dull horde does.

The game resolves the shot. Two things about doing that through dot-combat: a shot made by hand traces nothing (dot-combat traces `pellets`, which a weapon fills and `DotShot.scatter()` builds), and dot-combat relocates a shot to where the server believes the shooter is, so a test must fire from the NPC, not a made-up point. Ask "did it hit a player", the only question that catches the first.

## Roles are attack slots with names

`claim_role(role, capacity)` per target, released together when the target changes (`DotNpcAiSquad.release_suffixed`). A tree that asks in order (break off if hurt, flank if nobody is, otherwise suppress) gets a squad that splits its work with nobody giving an order. game-arena's gunner is exactly that tree.

**`hold_range` strafes.** A gunner standing still at range is a target; the drift flips on a period from its own seed, so twenty of them do not all slide the same way.

## Learning the map

**`DotNpcAiHeatmap` is what the game has learned of where players go:** cells of a few metres, a half-life of ten minutes so it is a picture of recent play, channels by name (`traffic`, `deaths`, or a game's own), `flow_at` for which way the traffic comes from, and JSON in and out. `patrol_hot` walks an NPC's hottest cells near it and waits at each facing the flow (an ambush) for as long as its `camper` says. Below 0.3 tactics an NPC does not know the map and wanders, which is half of what makes the easy preset easy.

**`DotNpcAiHeatKeeper` keeps one per map:** sample on an interval, save on an interval and on the way out, swap on a map change. Every game would write those lines and the one that forgets to save before swapping trains map B on map A's corridors.

- **Re-adopting the map it already holds reloads without saving first.** A game turns persistence on after the map was adopted with it off (arena's horde is built before its server module loads); saving there would overwrite the file with the few seconds learned since, and a server would forget every map on every restart.
- **Persistence is the server's decision, never the default.** Every suite builds the game, and one that saved would have each run's bots train the next run's NPCs: a suite whose results depend on how many times it has run. game-arena's and game-playground's server modules turn it on; their suites leave nothing in `user://`.

## Attack tokens

Off by default (`DotNpcAiTokenConfig.enabled`); set `squad.tokens` (or `DotNpcAiSquads.tokens` before squads are made) to turn it on. A squad then has `pool_size` attack permissions with `per_target_cap` on any one target, layered on the plain attack slot: `claim_attack_slot()` also needs a token. A token comes back on a kill (the target changed or went), after `timeout_s` (jittered from `seed`), or when the member has not seen its target for `los_loss_s`; a timeout or a lost sight also keeps the member from taking one again for `retake_cooldown_s`, which rotates the attackers. A refused member is queued: the longest waiter on a target is served first, so none starves. `hold_off()` is the leaf for a member without a token: it takes the best place on a ring round the target from `DotNpcAiTactics.best_flank` (behind the target, away from allies, not far to walk) and holds it at spacing. Every weight is in the config; `describe_lines()` on the squad shows the pool and the release counts.

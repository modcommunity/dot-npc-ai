This is the **NPC decision** asset for TMC's **Dot** collection. It is what you add when the things that move about have to make up their minds.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Behaviour, for NPCs
**The decision half of [dot-npc](https://github.com/modcommunity/dot-npc).** A behaviour tree with real running-state memory, a state machine for the many cases a tree is overkill for, a per-NPC blackboard that forgets, and the steering a crowd needs.

Depends on **dot-core** and **dot-npc**.

## Installing

Copy `addons/dot_npc_ai/`, `addons/dot_npc/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project, and enable them in *Project → Project Settings → Plugins*.

## Five minutes

```gdscript
extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

func _build() -> void:
    initial_state = &"idle"

    machine = DotNpcAiMachine.new()
    machine.add(DotNpcAiState.make(&"idle")
        .when(func(_c): return npc.has_target(), &"chasing"))
    machine.add(DotNpcAiState.make(&"chasing")
        .when(func(_c): return not npc.has_target(), &"searching"))
    machine.add(DotNpcAiState.make(&"searching")
        .when(func(_c): return npc.has_target(), &"chasing")
        .after(3.0, &"idle"))

    # REACTIVE, because this is a guard followed by an action that never finishes.
    tree = DotNpcAiSelector.new(&"root", [
        DotNpcAiSequence.reactive_with(&"chase", [
            DotNpcAiLeaf.Condition.new(&"has a target", func(_c): return npc.has_target()),
            DotNpcAiLeaf.Action.new(&"walk at it", _chase),
        ]),
        DotNpcAiLeaf.Action.new(&"wander", _wander),
    ])

func _chase(ctx: DotNpcAiContext) -> int:
    ctx.put(&"last_seen", target_position(), 6.0)      # remembered for six seconds
    steer_with_spacing(target_position(), 4.0, ctx.delta)
    return DotNpcAiNode.Status.RUNNING
```

## The rule everybody gets wrong

A node that returned RUNNING must be **resumed** next tick, not restarted. Get it wrong and nothing errors: an NPC re-opens the same door sixty times a second, or an attack never finishes because its wind-up keeps restarting. Everything looks alive and nothing completes.

`tick()` is not overridable here, and the composites own the resume index, so no node can forget.

## The other rule, which is this addon's own trap

A guard followed by an action that never finishes needs a **reactive** sequence, or the guard is asked exactly once. `DotNpcAiSequence.reactive_with()` is that. A plain sequence is for steps in order.

## Character

A tree decides what an NPC does. It does not make two of them feel like different people. Same tree, same NPC: they notice at the same instant and shoot with the same accuracy.

```gdscript
brain.character = DotNpcAiCharacter.hard().with_seed(npc.instance_id)

# In the "shoot at it" branch:
if not ctx.has_reacted(npc.target_since):   # NOT engaged_at: that moves every tick it is seen
    return DotNpcAiNode.Status.RUNNING       # seen it, not acted on it yet

var at := ctx.character.aim_point(muzzle, target.position, target.velocity, 900.0, shot)
```

`DotNpcAiCharacter` gives an NPC a character rather than a difficulty tier, setting reaction time, alertness, memory, aim accuracy, aim skill, view turn rate, aggression, self preservation, vengefulness and a tendency to camp, with four presets from `easy()` to `nightmare()`. The character *is* the difficulty, per NPC, so a game can mix them. A catalogue can name one with `"skill": "hard"` in a definition's `meta`, and `DotNpcAiBrain` picks it up.

## Server-side skill

`DotNpcAiSkill` is how an operator makes every NPC on a server smarter or slower to react without editing a catalogue, and it changes live NPCs on their next tick. It **moves** each character rather than replacing it, so a brute on a hard server is still slower to notice than a stalker on the same server:

| Cvar | Default | What it does |
| --- | --- | --- |
| `npc_skill` | `0` | `easy`, `normal`, `hard`, `nightmare`, or a number from -1 to 1. Moves reaction time, alertness (sight range), memory, aim and turning toward the easy or the nightmare preset. 0 is as authored. Personality (aggression, self preservation, vengefulness) is never touched. |
| `npc_reaction_scale` | `1` | Multiplies every reaction time after `npc_skill`. 0.5 reacts twice as fast. |
| `npc_reaction_min` | `0.05` | No reaction time goes below this many seconds. 0 allows instant reactions. An NPC authored with no reaction time (a scripted one) is left alone. |

```gdscript
# In a dot-server module, once:
game.npc_skill.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY)

# Where the spawner is built, before the first spawn:
game.npc_skill.attach(spawner)
```

dot-server is not a dependency: `bind_cvars` takes anything shaped like `add_cvar`, and `cvar_specs()` / `set_cvar()` are there for a host that registers its own.

## The tactical layer

Attach a `DotNpcAiSquads` and a `DotNpcAiSounds` to the spawner, name a squad in the definition's meta, and every `DotNpcAiBrain` does the following with no game code:

- **Senses into conditions** each think (`SEE_ENEMY`, `NEW_ENEMY`, `ENEMY_OCCLUDED`, `LOST_ENEMY`, `LIGHT_DAMAGE`, `HEAVY_DAMAGE`, `LOW_HEALTH`, `HEAR_COMBAT`, `HEAR_DANGER`, `HEAR_ENEMY`, `SQUAD_INFORMED`, `HAS_ATTACK_SLOT`), which guards and `DotNpcAiDecorator.Interrupt` read.
- **Remembers several enemies** in a `DotNpcAiMemory`: where, how it knows, how fast they were moving, and who has hurt it.
- **Hears** gunfire, footsteps and danger the game emits, scaled by its alertness.
- **Calls out** what it sees to its squad, so squadmates who have never seen you come to help.
- **Turns** no faster than its character can.

And a game's tree picks from ready-made leaves:

```gdscript
tree = DotNpcAiSelector.new(&"root", [
    DotNpcAiLeaf.Action.new(&"dodge", func(c): return flee_danger(c, speed)),
    DotNpcAiSequence.reactive_with(&"fight", [
        DotNpcAiLeaf.Condition.new(&"target", func(_c): return npc.has_target()),
        DotNpcAiSelector.new(&"engage", [
            DotNpcAiSequence.reactive_with(&"attack", [
                DotNpcAiLeaf.Condition.new(&"slot", func(_c): return claim_attack_slot()),
                DotNpcAiLeaf.Action.new(&"close in", _close_in),
            ]),
            DotNpcAiLeaf.Action.new(&"surround", func(c): return surround(c, speed)),
        ]),
    ]),
    DotNpcAiLeaf.Action.new(&"search", func(c): return search(c, speed)),
    DotNpcAiLeaf.Action.new(&"wander", _wander),
])
```

Only `"attackers"` of a squad go at one target; the rest share a ring round it, and a squad with high `tactics` centres that ring on the target's back. `search` goes where a lost enemy was heading rather than where it was last seen. `find_cover` / `take_cover` use dot-npc's generated cover spots, one NPC per spot. The character's new `tactics` trait, moved by `npc_skill`, decides how much of this an NPC uses.

For NPCs that fight at range, `ready_to_fire(muzzle)` opens only when the target is seen, the reaction time has passed, the NPC has turned to face it, no squadmate is in the lane and the character's fire throttle allows it; `aim_solution(muzzle)` leads the target by the velocity the NPC itself observed and misses by its character's accuracy; `hold_range(ctx, speed, near, far)` keeps a distance band and strafes. `claim_role(role, capacity)` generalises attack slots, so a squad splits into attackers, suppressors and a flanker without anybody giving orders.

`DotNpcAiHeatmap` learns where players go on a map, and `DotNpcAiHeatKeeper` keeps one per map on disk across restarts. `patrol_hot(ctx, speed)` sends NPCs with enough `tactics` to the busiest places, to wait there facing the way the traffic comes, for as long as their `camper` trait says.

`tools/trace_surround.gd` and `tools/plot_trace.py` draw a squad's movement top-down, for the things a suite cannot see (`TRACE_KIND=gunner` for a ranged squad).

Everything random in it is a hash of the character's seed and a number you pass, so the same shot always misses the same way, and a replay and the server that recorded it agree. Give each NPC its own seed, or twenty of them fire one volley.

## Validating

```bash
godot --headless --path . --import
timeout 180 godot --headless --path . res://examples/npc_ai_selftest.tscn
```

313 checks, exits non-zero on failure.

## Licence

MIT. See [LICENSE](LICENSE).

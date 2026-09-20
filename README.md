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
if not ctx.has_reacted(npc.engaged_at):
    return DotNpcAiNode.Status.RUNNING       # seen it, not acted on it yet

var at := ctx.character.aim_point(muzzle, target.position, target.velocity, 900.0, shot)
```

`DotNpcAiCharacter` gives an NPC a character rather than a difficulty tier, setting reaction time, aim accuracy, aim skill, view turn rate, aggression, self preservation, vengefulness and a tendency to camp, with four presets from `easy()` to `nightmare()`. **There is no difficulty setting**: the character *is* the difficulty, per NPC, so a game can mix them.

Everything random in it is a hash of the character's seed and a number you pass, so the same shot always misses the same way, and a replay and the server that recorded it agree. Give each NPC its own seed, or twenty of them fire one volley.

## Validating

```bash
godot --headless --path . --import
timeout 180 godot --headless --path . res://examples/npc_ai_selftest.tscn
```

162 checks, exits non-zero on failure.

## Licence

MIT. See [LICENSE](LICENSE).

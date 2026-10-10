# History

Bugs worth recognising if they come back. Every one parsed cleanly; most errored nowhere. The rule each left is in [decisions.md](decisions.md), [character.md](character.md) or [tactics.md](tactics.md).

## has_reacted() was false for ever

The gate every "act on what you see" branch belongs behind never opened. `has_reacted()` measured a reaction time from `DotNpcInstance.engaged_at`, and dot-npc refreshes that field on every pass in which the target is perceived, which is what it is for. So `now - engaged_at` was about zero on every tick an NPC could see somebody.

Nothing errored: **a bot that never acts on what it sees looks like a bot that is bad rather than one that is broken**, which is why it survived a suite that tested `DotNpcAiCharacter.has_reacted` directly and correctly. The character's arithmetic was right; the field it was handed was wrong. `DotNpcInstance.target_since` was added to dot-npc for it. Found by game-playground watching a hunter sit in `ALERT` for ever; the suite now asserts that `engaged_at` moves, `target_since` does not, and `has_reacted()` becomes true.

## In the addon

- **The blackboard's `has()` answered false for every value that was not a StringName.** `get_value(key, now, _MISSING) != _MISSING` with a `Vector3` pushes `Invalid operands 'Vector3' and 'StringName' in operator '!='` and abandons the expression. See [gdscript-hazards](../../../docs/gdscript-hazards.md).
- **A guard behind a plain sequence was never re-checked**, written into this addon's own fixture on the first pass; found as a zombie that would not go home.
- **A stacked pair was never separated**: a horizontal push between two NPCs one above the other is nothing. Hence `tie_break`.
- **The brain's clock started at zero**, so late-spawned NPCs ignored cooldowns briefly.
- **The tie-break read `basis.x` off the node**, which fails once per NPC per tick on a `Node2D`.
- **dot-npc's `face()` turned every 3D NPC's back to where it was going** (`look_at(position - direction)` points -Z, which `facing()` reads, away). The sight cone pointed behind a chasing monster, and clients never showed it because `DotNpcNetSync.yaw_of` was half a turn out the other way and the two cancelled on screen. Found by this addon's turn-rate check, which was told an NPC turned 180 degrees in one tick. Fixed in dot-npc, whose suite asserts the round trip.
- **`turn_view` could not turn round**: for a target directly behind it rotated about `from × UP`, a horizontal axis, and the bot tipped its head back; its own comment said that case had been fixed.
- **`surround` aimed one tick of angle ahead**, inside the arrival distance, so a flanker never got round.
- **The first surround heaped**, with every check passing; only the plotted trace showed it.
- **`alertness` and `memory_time` were read by nothing**: declared, documented and carried by every preset. Two game brains authored `memory_time` per kind.
- **A game brain's `put(&"last_seen", pos, 8.0)`** passed 8.0 as *now* and no lifetime, so its memory never expired (game-playground's hunter).
- **The search branch was written three times** with three hard-coded lifetimes before it became the brain's.
- **arena's first `npc_shoot` resolved, counted and hit nobody**: a shot made by hand has no pellets.

## In the suite

- **A test measured a 3D distance on twelve bodies in free fall** and reported none had arrived; they were 78 metres below the goal and where they should have been horizontally. It needed a floor and a horizontal measure.
- **A timeout test kept its alert switch on**, so the state it timed out into transitioned straight back. Correct behaviour, and a test of the wrong thing.
- **A dot-combat test fired from a made-up point six metres off** and hit the floor at the gunner's feet: dot-combat relocating the shot, which is the anti-cheat working.
- **The vengeance check put the attacker 50% further away** than the current target; the NPC walked toward the nearer one, and the 0.6 switch ratio took the vengeance back. That was the senses being right.

# Navigation annotations

What a map means to somebody walking it, worked out from any map with nobody authoring anything: where a body can drop, jump up or jump across that the navigation mesh does not join, where it can stand out of sight or behind something, and the narrow places most routes go through. One layer, made once per map and cached, that every game's bots and NPCs read.

## The problem it answers

A bot that only has the walkable mesh is generic and stupid in the same three ways on every map. It walks to the edge of a balcony and stops, because the mesh has no polygon in the air between the balcony and the floor. It hides in the middle of a room, because nothing told it where the walls are that a seeker cannot see past. It wanders, because nothing told it where the fights happen. Imported maps make it worse: they arrive as brushes and nothing else, so there is nobody to place a jump link or a hiding spot by hand, and there are hundreds of them.

Everything here is measured from two things every map has once it is loaded: the navigation mesh (where a body stands) and the physics space (what a ray hits).

## Where it sits

| Part | Owner |
| --- | --- |
| Baking the mesh from the level's colliders | dot-bot's `DotBotNav` (on a worker thread where there are threads), or anything else that makes a `NavigationMesh` |
| Annotating it | `DotNpcAiNavAnnotator` here, a `DotJob` |
| Holding, saving and querying the result | `DotNpcAiNavAnnotations` here, data only |
| Seeing it | `DotNpcAiNavDebug` here, and `tools/annotate_map.gd` |
| Using it | the game: it hands the links to its planner (`DotBotNav.add_ride`, dot-npc's `add_link`) and the spots to its choose step (`DotBotHiding`, `DotNpcAiTactics`) |

The annotator takes engine types only (a `NavigationMesh` and a `World3D`) and names no navigation class of any addon. Points come out as `Vector3`s in the map's space, so dot-bot's mesh, dot-npc's graph and a game's own pathing read the same annotations, and dot-npc-ai stays liftable. Spots are dictionaries with dot-bot's hiding fields (`at`, `exposure`, `seen_by`), so `hiding_spots()` goes straight into `DotBotHiding.choose`.

## What it finds, and how

**The outline.** Every polygon edge only one polygon has is the mesh's outline. Each is sampled about every `sample_spacing` metres (1 m), with the normal pointing out of its polygon, and each sample is asked one question with a ray at knee height: is there a wall just past it? If so it is a place beside a wall, a spot candidate. If not it is a ledge.

**Links**, from the ledges:

- A ray straight down just past the edge finds what is below. If that floor is within a step of this one, it is a lip or a rounded corner the bake left out, and nothing. Otherwise, if a polygon of the mesh is under the landing within `drop_max` (6 m), it is a `LINK_DROP`, and when the depth is no more than `jump_up` (1 m; the arena body's 1.25 m), a `LINK_JUMP_UP` back the other way. Depth is measured between the two floors of the mesh, not to the ray's hit, because the mesh floats up to a cell above what it was baked from on both sides; measured to the hit, a 0.9 m platform read as 1.1 m and got no jump up.
- Before the drop, points further out along the normal, to `gap_max` (3 m), are tried for a landing at about this height with a clear line between the two at waist height: a `LINK_JUMP_GAP`. A wall top in the way (something at this height that is not on the mesh) ends the search.
- A link a walk on the mesh already covers (within half again its length plus three metres) is dropped, and links along one stretch of edge are thinned to one per `link_spacing` (2 m) at both ends. `_keep_link` is the judgement a game overrides.
- `declare(from, to, kind, cost)` adds what geometry cannot see: ladders, teleports (a map's teleport volumes, to where they send), lifts, and surf ride edges. A declared link is in the cache key.

**Spots**, from the wall samples, thinned to under half of `spot_spacing` apart and capped at `max_candidates` (1500):

- `exposure`: the share of `watchers` (96 random places on the walkable floor at eye height, weighted by area) within `reach` (30 m) that see a crouched head there. Line of sight is a ray unless a game assigns `los_fn` (glass, foliage).
- `enclosure`: the share of 16 directions blocked within 2 m at that head.
- `low` and `high`: cover masks, one bit per eighth of a turn, at a crouched waist and a standing chest. `cover_from(threat, near)` answers "where near here hides me from them", crouched or standing. Heights are taken from the floor under the spot, not the mesh, since a crouched head behind a waist-high wall is a matter of centimetres.
- The hiding places (`hiding`) are the best by `_hide_score` (out of sight first, then tucked in; a game that hides in the open among props overrides it), the better third or anything seen by under a third of its watchers, kept `spot_spacing` apart, at most `max_hiding`.

**Chokepoints.** `routes` (48) random pairs of points on one island are routed over the polygon graph; each route counts once per 2 m cell of the portals it crosses, with the walkable width across the travel direction measured against the outline. A cell crossed by at least `choke_traffic` of the routes and no wider than `choke_width` (3 m) is a chokepoint; they are kept 5 m apart.

**Islands.** A bake walks floors nobody can reach: the top of a sealed map's shell, and the floor inside a solid block tall enough to stand in. Watchers, routes and spots are drawn only from kept islands, and links that start elsewhere are dropped:

- Islands the `seeds` (spawns, teleport destinations) reach through the mesh and the links are kept.
- An island inside a convex solid (a ray up from it starts inside something) is dropped.
- When the seeds are under a roof, islands open to the sky are dropped: on a sealed map, that is the roof of its shell. An imported combat map's roof was its largest island; drawn from, it was most of the watchers and all of the picture.
- Of the rest, an island a link touches or of at least `min_island_area` (6 m²) is kept. `reach_only` keeps only what the seeds reach, which is right once a game declares its ride links and wrong before: a surf map crossed by ramps is mostly unreached from its spawns without them.

`kept_polygons()` is what a game should draw its own random points from.

## Cached per map

`cache_key()` is a SHA-256 of `VERSION`, the mesh's vertices and polygons, the sorted settings, the seeds and the declared links. The colliders are not in it: the mesh was baked from them, so a changed wall is a changed mesh. The same map baked the same way gets the same key on every machine, so a server keeps one `user://nav/<key>.json` per map and pays nothing on a map it has seen. `load_file(path, key)` refuses a file made for another key (`CODE_INTEGRITY`) or another `VERSION` (`CODE_VERSION`), and a missing file is `CODE_IO`, never empty annotations. `VERSION` rises whenever the annotator would produce something different from the same input.

## The frame budget, and the browser

A physics query is main-thread only, and a browser without threads has nothing else. So the annotator is a `DotJob` stepped in slices of `slice` items (24), and a `DotScheduler` runs it inside its frame budget; every phase is sliced, including the two that were not at first (thinning the wall samples, and the sky test per island, each 30 to 80 ms in one go on a large map). `run_to_completion()` is for tools and tests. It is deterministic: the same mesh, colliders, settings and `random_seed` give the same annotations, sliced or in one go (the suite checks both).

## Measured

`tools/annotate_map.gd` bakes with dot-bot's numbers and steps the job as a scheduler would. Body radius 0.35 m, height 1.8, step 0.4, jump 1.25 (1.0 for the toy).

| Map | Mesh | Links | Spots | Hiding | Chokepoints | Total | Slowest slice |
| --- | --- | --- | --- | --- | --- | --- | --- |
| The suite's toy level | 106 polygons | 47: drop 35, jump up 8, gap 4 | 240 | 38 | 1 (the doorway) | 44 ms | 1.0 ms |
| An imported surf course, 12k triangles | 415 polygons, 60 islands, 49 kept | 138: drop 118, jump up 4, gap 2, teleport 14 | 863 | 130 | 0 | 107 ms | 4.2 ms |
| An imported combat surf map, 37k triangles | 2760 polygons, 309 islands, 171 kept | 292: drop 141, gap 57, jump up 51, teleport 43 | 1500 (the cap) | 200 (the cap) | 0 | 334 ms | 8.4 ms |

At 24 items a slice the largest map's slowest slice is 8.4 ms (the outline, where each sample casts up to a dozen rays against the whole trimesh); a browser build wants `slice` nearer 8. Surf maps have no chokepoints, correctly: their routes are ramps, not doors.

## Looked at

No assertion reaches a link that lands on the wrong floor or a hiding spot in the middle of a room. `DotNpcAiNavDebug` draws links as bent arrows coloured by kind (drop red, jump up green, gap yellow, ladder purple, teleport pink, ride cyan), hiding spots as tall blue markers, other spots as small light ones, chokepoints as orange bars and the kept mesh in translucent green. `tools/annotate_map.gd --out PREFIX` under a renderer photographs it from above with the level hidden (a map is usually roofed), close up on the busiest 16 m, and from two corners:

```bash
xvfb-run -a godot --path . --resolution 1600x900 --script res://tools/annotate_map.gd -- --toy --out /tmp/toy
xvfb-run -a godot --path . --resolution 1600x900 --script res://tools/annotate_map.gd -- \
    --source map.res --meta map_meta.json --jump 1.25 --out /tmp/map
```

A game saves `map.res` from its loaded map (`NavigationServer3D.parse_source_geometry_data` over the static colliders, then `ResourceSaver.save`) and `map_meta.json` from what the map knows that its geometry does not (`{"spawns": [[x, y, z]], "teleports": [{"min", "max", "to"}]}`). An imported map's geometry stays in the game's own checkout and never in this repository.

What looking found, that every count had passed: floor-level gap links across every corner of a box (a lip, not a gap); no jump up onto a 0.9 m platform (depth measured to the hit); spot normals pointing into the wall; a combat map's whole picture being its roof.

## Subclass or assign

| To change | Where |
| --- | --- |
| Which links are worth having | `_keep_link(from, to, kind)` |
| What a good hiding place is | `_hide_score(spot)` |
| What blocks sight | `los_fn` (`(from, to) -> bool`) |
| Ladders, teleports, lifts, ride edges | `declare(from, to, kind, cost)`; a game's own kinds from `LINK_GAME_FIRST` |
| Which floors count | `seeds`, `reach_only`, `min_island_area` |
| How far a body jumps and drops, how far apart spots are | the cvars `npc_nav_jump_up`, `npc_nav_drop`, `npc_nav_gap`, `npc_nav_spot_spacing` (`bind_cvars`, `read_cvars`), or the fields |
| Which layers are walls | `collision_mask`, `exclude` |

## Not yet

- **Ladders** are declared, not found: a ladder is a volume a map marks, and an imported map's ladder brushes come through its entity list, which the game reads.
- **Surf ramps** stay with dot-bot's surf planner, which already derives ride edges from the ramp geometry; a game declares them here so they count for reachability and the key.
- **Sightlines** beyond a spot's exposure (the long lanes a sniper holds) want watchers paired with each other, the same rays turned around; the watchers are already drawn.
- **Walkable surfaces the bake refuses** (a slope over 46 degrees) are not linked; that is the surf case again.

## Next, per game

| Game | Next step |
| --- | --- |
| game-arena | After its `DotBotNav` bake, run the annotator on `nav.mesh` with the map's spawns as seeds and its pits as declared teleports, cache by key, and hand drops, jump ups and gaps to `add_ride`; its ride edges go in as declared links |
| game-hide-n-seek | Replace HsBots' random-point survey with `hiding_spots()` for hiders, and use `cover_from` for a hider that has been seen; seekers walk the chokepoints first |
| mg-prop-hunt | Override `_hide_score` to prefer spots beside props (enclosure low, a prop within a metre), and declare nothing |
| game-zombie-zone | Hold chokepoints for the defenders; zombies take drops (never jump ups) so a tower is defensible |
| mg-buses-from-hell | Its grid route is not a mesh; use only the spots and chokepoints, from a mesh baked for the bot's body |
| game-g2gfast | Nothing for its timer runs; its bots ride the surf planner. Drops and gaps help a bhop course's bots between stages |

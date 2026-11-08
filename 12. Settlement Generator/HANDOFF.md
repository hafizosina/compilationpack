# Module 12 — Settlement Generator: state of the build

A whole settlement from a seed, on module 10's town grid. The plan is `PLAN.md` (nine steps);
this file is what exists. Module 9's ECS and module 10's grid, build commands, pathfinding and
catalogs are **borrowed, never copied**; new terrains and blueprints went into module 10's
catalogs, by decision (2026-11-08), so module 10's builder can place them too.

**Status (2026-11-08):** step 1, terrain and resource nodes, is done, on two levels: an **L2
region** and **L1 windows** zoomed 8× into it. Towns and buildings (steps 2–9) will be L1 only.

```bash
# 34 checks, ~60 s; exit 0 only if all pass. Prints plan and load costs.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/terrain_test.tscn"
# The viewer: pick hamlet, village, town or Region (L2), press Generate (it plans on a worker
# thread); click the region to zoom into L1 there.
"$GODOT" --path . "res://12. Settlement Generator/generator.tscn"
```

---

## 1. Layout

| Path | Role |
|---|---|
| `defs/` | `EcsSettlementDef` (a kind of map), `EcsNodeSpawnDef` (where a node grows); `settlements/`: `hamlet`, `village`, `town`, `region` |
| `ecs/` | `EcsTerrainGenerator` (pure: `plan`, `refine`), `EcsTerrainCheck` (pure: `problems`, `follows`) |
| `generator.tscn` | The viewer (`generator_view.gd`); its panel is built in code |
| `tests/` | `terrain_test.tscn` |
| `PLAN.md` | The nine steps |

Module 10 additions for it (module 10's HANDOFF §13): the `rock` and `forest` terrains, the
`EcsResourceNodeComponent`, 15 node blueprints on a new `nodes.png` sheet, and the builder's
Resources tool.

---

## 2. Step 1 — terrain and resource nodes (2026-11-08)

**The output is build commands**: `SET_TERRAIN` for every cell that isn't grass, then
`PLACE_OBJECT` per node. Loading a map goes through module 10's build system, so the rules that
check a hand-built town check a generated one. The same def and seed give the same commands, and
each stage (water, rock, forest, nodes, refine noise) has its own seed.

**`EcsTerrainGenerator.plan(def, seed, …)`**, a whole map:
1. **Water**, by `EcsSettlementDef.Water`:
   - a **lake**: a noise blob round a random centre, cut at the share, largest piece kept;
   - a **river** edge to edge: a noise-bent centreline, painted as discs every half cell along
     straight segments between points;
   - a **coast** along one random side, its line noisy;
   - **river to the sea**: a coast, and a river from the far edge into it.

   A river's line (`points`, `radii`, in cells) is kept in the plan, as is a mask of the cells it
   made water and the coast's side.
2. **Shore**: land within `shore_width` of water becomes sand.
3. **Rock**: noise on land away from the water, cut at `rock_share`; blobs under 12 cells dropped.
4. **Forest**: noise on the remaining land, cut at `forest_share`.
5. **Zones**: each cell's bits from `EcsNodeSpawnDef.Zone`, read off the kinds and distances.
   MEADOW, FOREST, FOREST_EDGE (≤2 in), DEEP_FOREST (≥4 in), ROCK, ROCK_INNER (≥2 in), SHORE,
   SHALLOW (water touching land).
6. **Nodes**: each spawn def in order scatters clumps over its zone (`density` per cell; a clump
   grows `cluster` nodes by random walk, keeping `keep_clear` round each). Then it **tops up**
   with clumps at random cells of the zone until `min_count` is met, while the zone has room.

**`refine(parent, parent_def, def, origin, scale, seed, …)`**, an L1 window into an L2 plan.
The child adds detail but never contradicts the parent:
- **Blend.** Each parent kind is read as 0/1 per cell and blended between cell centres. Detail
  noise of ±0.3 is added, and the strongest kind wins. Under 0.5, so a child cell whose parent
  neighbourhood is all one kind can't become another.
- **Rivers** are redrawn from the parent's own line, scaled, their centre wandering ±1.5 cells.
  For the blend a river cell counts as sand (its bank), except where it touches other water, so
  the mouth stays joined to the sea. The parent paints along the same segments the child
  redraws, so both trace one course.
- **Seams.** Noise is read in whole-region coordinates, and the window is worked 4 cells wider
  each side, then cropped, so the shore sees water just outside. Two windows side by side are
  cell for cell the halves of one twice as wide (tested).
- The child's own shore (its def's `shore_width`) and nodes follow, as in `plan`. A refine reads
  only the child def's size, shore width and nodes.

**`EcsTerrainCheck.problems(def, plan, refined)`** reports:
- water not in one body; a river that doesn't reach both edges, or the far edge for river to the
  sea;
- a share more than 25% off;
- a node kind short of `min_count`, or a node out of its zone;
- nodes walling off more than 5% of any land area cut off by water. Islets under 50 cells are
  exempt.

A refined child is checked only for zones and staying open. **`follows(...)`** checks it against
its parent: every parent cell whose 3×3 neighbourhood is one kind has an 8×8 block all of that
kind, and at least 90% of blocks' most common kind is their parent cell's.

**Defs:**

| Def | Size | Water | Notes |
|---|---|---|---|
| `hamlet` | 160×120 | lake | |
| `village` | 256×192 | river | |
| `town` | 384×288 | coast | also the size, shore and nodes of every L1 window |
| `region` | 256×192 | river to the sea | the L2 map. 8 m a cell, so 2 km × 1.5 km; an L1 window is 48×36 of its cells. No nodes, since they are L1 things |

The cell sizes follow the September L3/L2/L1 notes: L1 is 1 m a cell (a module 10 cell holds a
chair), L2 8 m. L3 isn't built. **The world is finite** (decided 2026-11-08), so a future L3 can
see whole basins.

**The viewer** offers the four maps, the water kind and the seed.
- **Generate** plans them; changing an input doesn't. Next and Random set the seed and generate.
- **Planning runs on a `WorkerThreadPool` task**, both the plan and a zoom's refine. The button
  reads "Planning on a worker thread…" and the window keeps drawing: about 60 FPS, worst frame
  18 ms, while a ~1 s window is planned. Loading the result (entities and tiles) stays on the main
  thread, since it touches the scene tree.
- The worker only reads the catalogs: the entity catalog's lookup is built in `_ready`, so the
  worker never fills it.
- On the **region**, an outline follows the mouse, and a click zooms into that L1 window, with the
  region's own seed whatever the seed box now shows. **Back** returns.
- Nodes and a zone tint toggle.
- It reports the shares, node counts, plan time, commands refused, the seed used, and the checks
  (for a window, that it follows its region).

**Tests** (`terrain_test`, 34):
- every size × lake, river and coast over 20 / 10 / 5 seeds;
- the same seed gives the same commands, and the next seed others;
- one map per size, and one L1 window, through module 10's build system: every command
  accepted, the grid's terrain the plan's, every node born on its cell;
- the region over 10 seeds;
- nine L1 windows (on the river, on the coast, inland, for three seeds) follow their region and
  are sound;
- two neighbouring windows meet without a seam.

**Measured** (headless, 2026-11-08):

| Map | Plan | Commands | Load (4 ticks) |
|---|---|---|---|
| hamlet 160×120 | ~75 ms | ~10k | ~0.6 s, two-thirds of it the first tile sync |
| village 256×192 | ~200 ms | ~22k | ~1.6 s |
| town 384×288 | ~450 ms | ~62k | ~4 s |
| region 256×192 | ~210 ms | ~29k | — |
| L1 window 384×288 | ~1 s | ~58–76k | ~5 s |

The window's plan is half the blend (5 kinds × 120k cells in GDScript), plus building the
commands. Fine for a generator. If windows are ever streamed while playing, the blend and the
command list are where to look.

**Not yet**:
- no L3, and L2 isn't height-based. The September notes' heightmap, Priority-Flood lakes and D8
  rivers would replace the noise water;
- a refined window has no rivers of its own beyond its parent's (no tributaries);
- the coast's sand is thin on big maps.

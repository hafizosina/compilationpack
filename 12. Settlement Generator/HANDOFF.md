# Module 12 — Settlement Generator: state of the build

A whole settlement from a seed, on module 10's town grid. The plan is `PLAN.md` (nine steps);
this file is what exists. Module 9's ECS and module 10's grid, build commands, pathfinding and
catalogs are **borrowed, never copied**; new terrains and blueprints went into module 10's
catalogs, by decision (2026-11-08), so module 10's builder can place them too.

**Status (2026-11-08):** step 1, terrain and resource nodes, is done, on two levels: an **L2
region** and **L1 windows** zoomed 8× into it. Towns and buildings (steps 2–9) will be L1 only.

```bash
# 38 checks, ~60 s; exit 0 only if all pass. Prints plan and load costs.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/terrain_test.tscn"
# The viewer: Generate makes the L2 region; the wheel zooms in until L1 streams in chunk by chunk.
"$GODOT" --path . "res://12. Settlement Generator/generator.tscn"
```

---

## 1. Layout

| Path | Role |
|---|---|
| `defs/` | `EcsSettlementDef` (a kind of map), `EcsNodeSpawnDef` (where a node grows); `settlements/`: `hamlet`, `village`, `town`, `region` |
| `ecs/` | `EcsTerrainGenerator` (pure: `plan`, `refine`, and the chunk stages `refine_terrain`, `refine_nodes`), `EcsTerrainCheck` (pure: `problems`, `follows`), `EcsTerrainChunks` (the L1 chunks kept in memory and what to make next) |
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

**L1 in chunks** (2026-11-08). `refine` is two stages a chunk can run apart:
- **`refine_terrain(parent, …, size, shore, at, scale, seed, border, shares)`** gives a child area's
  kinds and river with `border` extra cells all round, and its zones.
  - It works MARGIN (5) cells wider, so zones near the edge are the same as in a bigger area.
  - `blend_shares` is made once per region and passed in.
  - **Any two areas agree cell for cell where they overlap** (tested: two 32-cell chunks with a
    border match one 64-wide area, and each border is the neighbour's own cells).
- **`refine_nodes(def, zones, seed, key, …)`** places nodes, seeded by the chunk.

A node never crosses a chunk's edge, and its keep-clear ring doesn't reach into the next chunk.

**`EcsTerrainChunks`** keeps every chunk's plans in memory and says what to do next. First the
chunks in view, nearest the centre first, each through its stages in order:
1. terrain planned;
2. terrain drawn;
3. objects planned;
4. objects drawn.

Then the same for one ring of chunks round them. It also lists drawn chunks far outside the view;
those free their nodes but keep their plans, so coming back only redraws them.

**The viewer** streams L1 with it:
- **Generate** plans the L2 region (always; the water kind and seed are its inputs).
- The wheel zooms by a factor toward the mouse. The shared camera's own wheel step is set to 0 in
  this scene; it still pans.
- **From zoom ×1, L1 fades in over the region and streams.**
  - Up to 3 worker tasks at once plan chunks and build their worlds off the scene tree: module
    10's pipeline, run until settled.
  - Drawing objects rebuilds the chunk on a worker with terrain and objects together, and fades it
    in over the terrain-only one. The main thread only ever adds a finished chunk.
  - A chunk is drawn with a one-cell border of its neighbours' cells, and its outer ring of ground
    tiles is erased. The dual-grid tiles left at an edge are drawn the same by both neighbours,
    so there is no seam.
- Below ×0.75, L1 fades out, but its chunks stay made.
- Changing the chunk size (32, 64, 128) starts L1 afresh.
- **A left click picks a cell.** It's L1's where its chunk is drawn and L1 shows, else L2's. The
  cell is outlined, and a panel top right shows its details, kept current as its chunk is made:
  - **L2:** position, ground (river or sea), zones, walk cost, and the L1 cells it holds.
  - **L1:** position, chunk and place in it, ground, zones, walk cost, the object covering it
    (name, kind, what it gives, size and origin if larger than a cell), its L2 cell's ground, and
    which stages its chunk has reached.

  × closes the panel; a new region or chunk size clears it.

**Measured** (window, 8 cores, zooming into a river):
- My code on the main thread costs ~8 ms when a chunk's terrain arrives, ~5–7 ms when its objects
  do, and ~25 ms when the region does (once).
- The rest of a slow frame is the engine building the new tile layers. It grows with chunk area.
  **With 64×64 chunks, 34 of 1,391 frames went over 33 ms (some 40–70 ms); with 32×32, none did**,
  so 32 is the default.
- A view's worth of chunks (about 45) is fully made in ~10 s, nearest first, with terrain
  visible within a second or two.

**Tests** (`terrain_test`, 38):
- every size × lake, river and coast over 20 / 10 / 5 seeds;
- the same seed gives the same commands, and the next seed others;
- one map per size, and one L1 window, through module 10's build system: every command
  accepted, the grid's terrain the plan's, every node born on its cell;
- the region over 10 seeds;
- nine L1 windows (on the river, on the coast, inland, for three seeds) follow their region and
  are sound;
- two neighbouring windows meet without a seam;
- a chunk's border cells are its neighbour's, and chunks are one area cut up;
- chunks in view get all four stages in order before the ring, nothing is planned twice, and far
  drawn chunks are offered up to free.

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
- the chunk store has no cap: a chunk's plans stay for the whole session (small: a few KB a chunk);
- the coast's sand is thin on big maps.

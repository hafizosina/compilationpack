# Module 12 — Settlement Generator: state of the build

A whole settlement from a seed, on module 10's town grid. The plan is `PLAN.md` (nine steps);
this file is what exists. Module 9's ECS and module 10's grid, build commands, pathfinding and
catalogs are **borrowed, never copied**; new terrains and blueprints went into module 10's
catalogs, by decision (2026-11-08), so module 10's builder can place them too.

**Status (2026-11-10):** step 1 (terrain and resource nodes, on an **L2 region** with **L1**
streamed 8× into it in chunks), step 2 (the town's site, plaza and well, §3), step 3 (its main
roads, §4) and step 4 (plots, then the lanes they need, §5) are done. Steps 5–9 work on L1 only,
inside the town's area.

```bash
# 38 checks, ~60 s; exit 0 only if all pass. Prints plan and load costs.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/terrain_test.tscn"
# Step 2: 14 checks, ~60 s. Prints how long picking a site takes.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/site_test.tscn"
# Step 3: 11 checks, ~60 s. Prints how long a town with its roads takes.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/road_test.tscn"
# Step 4: 7 checks, ~50 s. Prints how long a town with its roads and plots takes.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/plot_test.tscn"
# The viewer: Generate makes the L2 region; the wheel zooms in until L1 streams in chunk by chunk.
"$GODOT" --path . "res://12. Settlement Generator/generator.tscn"
```

---

## 1. Layout

| Path | Role |
|---|---|
| `defs/` | `EcsSettlementDef` (a kind of map), `EcsNodeSpawnDef` (where a node grows); `settlements/`: `hamlet`, `village`, `town`, `region` |
| `ecs/` | `EcsTerrainGenerator` (pure: `plan`, `refine`, and the chunk stages `refine_terrain`, `refine_nodes`), `EcsTerrainCheck` (pure: `problems`, `follows`), `EcsTerrainChunks` (the L1 chunks kept in memory, what to make next, and the town's overlay), `EcsSitePicker` and `EcsSiteCheck` (pure: the town's site and centre), `EcsRoadPlanner` and `EcsRoadCheck` (pure: its roads), `EcsPlotPlanner` and `EcsPlotCheck` (pure: its plots and lanes), `EcsSettlementSite` (the record) |
| `generator.tscn` | The viewer (`generator_view.gd`); its panel is built in code |
| `tests/` | `terrain_test.tscn`, `site_test.tscn`, `road_test.tscn`, `plot_test.tscn` |
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

---

## 3. Step 2 — the town's site and centre (2026-11-08)

One town per region (decided). The generator picks its site; a right-click in the viewer moves it;
the **Town** option sets its size from the shipped defs (hamlet 160×120, village 256×192, town
384×288 L1 cells; plaza 8, 12, 16 cells a side).

**`EcsSettlementDef`** gained two groups:
- **Town:** `plaza_size`, `plaza_floor` (`stone`), `well` (`well`), `clear_margin` (2).
- **Site:** `water_near` (2–10 region cells), `water_weight`, `open_weight`, `edge_margin_cells` (4).

**`EcsSitePicker.pick(region_plan, region_def, def, seed, scale, catalog, shares)`** scores every
region cell (pure, L2 only).
- **Refused:**
  - on water;
  - a town area that would come within `edge_margin_cells` of the region's edge;
  - an area under 70% land;
  - land that doesn't reach the region's edge, which roads (step 3) will need.
- **Score:**
  - *water*: full marks between `water_near` cells, falling off nearer or further;
  - *open*: grass and sand round the site, forest and rock at half;
  - *room*: the land share under the area;
  - +0.2 for a river within reach.
- Sums over windows come from summed-area tables, so scoring all 49k cells is one pass.
- The best is taken; ties go to the cell nearest the region's centre, then the cell itself, so the
  same seed gives the same town.
- The top 20 are tried in turn until one's centre works out.

**`place(…, cell, …)`** does the same at a chosen cell and returns `{site}` or `{refused: why}`.

**The centre**, on L1:
- The town's area is refined with `refine_terrain`, the same cells the chunks draw.
- The plaza is the `plaza_size` rect within a quarter of the area from the site, on no water, with
  the fewest forest and rock cells, nearest first.
- Its land must reach the area's edge.
- The well is its middle cell.
- **`EcsSettlementSite`** holds:
  - the region cell, the L1 area, the plaza and the well;
  - the commands (`SET_FLOOR` stone on every plaza cell, `PLACE_OBJECT` the well);
  - the cleared rects (the plaza grown by `clear_margin`);
  - the score parts.

The plaza is a floor, so the ground under it, and the L2 ↔ L1 rule, are untouched.

**Into the chunks**: `EcsTerrainChunks.site` holds the town.
- `overlay(at, objects)` gives a chunk the town's floors on its cells and border, so a plaza split
  across chunks joins, and its objects on its own cells only, so the well is placed once.
- `blocked(at)` marks the chunk's cleared cells. `refine_nodes` takes it, so no node is planned
  there; `_nodes` starts from it as kept-clear.
- `touching(rect)` lists the chunks under a town.
- A new site makes those chunks under the old and new towns drop their nodes and drawing (their
  terrain stays) and be made again. Jobs still running for them are thrown away, by a per-chunk
  `rev`.

**`EcsSiteCheck.problems(…)`** reports:
- an area leaving the region, or a site on water;
- a plaza leaving the area, or water under it;
- a well outside the plaza;
- the plaza's land not reaching the area's edge;
- given planned nodes, any on cleared ground.

The walk check is on water only. Nodes are planned per chunk, and step 1's check keeps them from
walling land off.

**Viewer:**
- The Town option re-sites the town at its cell (or picks afresh).
- The region shows the town's area (pale) and plaza (orange) outlined.
- The info panel gives the site's score parts, or the reason a move was refused.
- A right-click moves the town; the move is planned on a worker.
- The cell panel says when an L1 cell is the well, the plaza, cleared ground or in the town's area,
  and gives the site's score on the site's L2 cell.

**Tests** (`site_test`, 14):
- every town size over 10 seeds is sound;
- the same seed gives the same town;
- moving it onto water or by the edge is refused with the reason, and onto good land it goes there;
- a hamlet's area with its plaza and nodes goes through module 10's build system: all 1,200
  commands accepted, stone on every plaza cell, the well born, no node on cleared ground;
- a plaza crossing 9 (8-cell) chunks draws the town's floor on every chunk's cells and border, the
  well is placed by one chunk, and no chunk plans a node on cleared ground.

**Measured:** picking a site takes ~0.7 s for a hamlet, ~0.9 s for a village and ~1.3 s for a
town, on a worker. Most of it is scoring 49k cells in GDScript and refining the area for the
plaza search. Fine for generation; scoring only cells near water first would cut it if needed.

**Not yet:**
- a second settlement;
- height or slope;
- plaza shapes other than a rectangle;
- the plaza is a floor, not cleared terrain: forest under it stays forest under the stone.

---

## 4. Step 3 — roads (2026-11-08)

> **Lanes changed in step 4 (§5):** the lane walker in point 4 below is deleted; lanes are now
> routed from plots. Main roads, exits and bridges are as described.

Decided:
- **main roads run to the region's edge**;
- the layout is **organic**;
- **bridges where needed**.

`EcsSitePicker._centre` calls **`EcsRoadPlanner.plan`** after the plaza. A site whose roads can't
reach an exit fails, and the next is tried, so a picked or placed town always has roads.

**`EcsSettlementDef`, Roads group:**
- `exits` (2–4);
- `main_width` 2, `lane_width` 1;
- `road_floor` `road`, `bridge_floor` `wood`;
- `road_costs` in kind order: grass 1, water 30, sand 1.2, rock 4, forest 3;
- `reuse_cost` 0.3;
- `lane_spacing` 12–20, `lane_length` 8–40, `lane_turn` 12°, `lane_branch_chance` 0.6;
- `verge` 1;
- `max_bridges` 3.

**The site record gained:**
- `roads` ({kind, points in L1, l2_points for main roads, width});
- `exits`;
- `road_cells` (cell → main, lane or bridge);
- `cleared_cells`;
- `bridges`.

**The planner:**
1. **Exits.** One Dijkstra from the site over the region gives every cell's cheapest cost. GDScript,
   binary heap, 8-way. The edge, sampled every 4 cells, is split into `exits` sectors by angle (the
   count and start angle seeded). Each sector takes its cheapest land edge cell. Sectors the sea cuts
   off are dropped.
2. **Main roads on L2,** nearest exit first: an `AStarGrid2D` route over the ground costs. Each
   routed cell's weight is multiplied by `reuse_cost`, so the next road follows it out of town and
   then forks. Routes are smoothed by two rounds of Chaikin. Tested: up to 70 region cells of trunk
   shared.
3. **Main roads on L1:** the line scaled 8×, wandering ±1.5 cells by noise read in region
   coordinates, brushed `main_width` square, the plaza left as it is. A road cell on L1 water is a
   bridge.
   - `WaterAt` refines the 8×8 block under a cell only when its region cell or a neighbour is water.
     Otherwise it is land, by step 1's rule.
   - So a road across the whole region costs a few dozen tiny refines.
4. **Lanes on L1,** in the town's area, on the area's refined ground:
   - **Where they start:**
     - off the main roads every `lane_spacing` cells, either side by chance, away from the plaza;
     - off each side of the plaza by chance;
     - one more level off a lane at half the chance and half the length.
   - **How they walk:** a cell a step, turning by up to `lane_turn`. A diagonal step also takes a
     side cell, so lanes are joined edge to edge. A lane starts on the road it leaves and walks out
     through it, so its first cell touches it.
   - **Where they stop:** at the area's edge, at water (lanes never bridge), at their length, or
     beside another road within 2 cells, which they join with a short straight piece. They never
     join the road they left within their first 12 cells; before that rule, most lanes rejoined
     their own road at once.
   - Lanes under 4 cells are dropped.
5. **Floors and clearing.** Every road cell is a `SET_FLOOR` (road, or wood for a bridge) in the
   site's commands. Road cells, and a `verge` round main road and bridge cells, go into
   `cleared_cells`, which `EcsTerrainChunks.blocked` marks.

The chunks needed nothing else: road floors are drawn by the overlay like the plaza, across chunk
borders.

**A bridge is a wood floor over water.** Module 10's walk costs take the floor's over the terrain's,
so it is walkable with no new rule (tested through module 10's nav).

**`EcsRoadCheck.problems(…)`** reports:
- a main road not starting at the site or not ending on the region's edge;
- more bridges than `max_bridges`;
- a road cell on L1 water that isn't a bridge, or a bridge on land (the area's own ground inside it,
  `WaterAt` outside);
- road cells not joined to the plaza (a 4-way flood from the well);
- given planned nodes, any on a road or verge.

**Viewer:**
- **Roads drawn over the region:** main roads dark and thick, lanes thin, bridge runs pale, exits
  marked with a red cross. Lines keep a few screen pixels' width when zoomed out.
- They fade out as L1 fades in, where the chunks draw the real floors.
- The info panel gives exits, metres of main road, lanes and their metres, and bridges.
- The cell panel says main road, lane or bridge on L1, and "a main road passes through" on L2.

**Tests** (`road_test`, 11):
- every town size over 6 seeds has sound roads and lanes;
- a coast-only region has no exit on the sea and sound roads;
- the same seed gives the same roads;
- main roads share a trunk;
- a bridge cell is water under wood and walkable in module 10's nav;
- a hamlet's area with plaza, roads, lanes and 542 nodes: all 3,772 commands accepted, every road cell
  floored, no node on a road or verge;
- the roads cross 124 chunks, and each draws the town's floors on its cells and border.

`site_test` now builds only the area's commands (main roads run past it) and keeps its nodes off road
cells, as the chunks do.

**Measured:** a town with its roads takes ~1.3 s for a hamlet or village and ~1.5 s for a town, on a
worker. That's ~0.5 s more than the site alone: the Dijkstra and the A* weights over the region in
GDScript. The check takes ~0.3–1 s.

**Not yet:**
- roads between settlements;
- road ranks beyond main and lane;
- slopes;
- main roads drawn as 2-cell square brushes, so a diagonal road reads as a staircase at L1;
- lanes 1 cell wide.

---

## 5. Step 4 — plots, then the lanes they need (2026-11-10)

Decided: **inside the town, buildings dictate the roads, not the other way round.** Plots are
placed first, square to the grid (module 10's walls, rooms and doors are grid-aligned), and lanes
are routed between them, so buildings stay square and roads stay natural. Then each plot's yard
grows out to meet its lane.

`EcsSitePicker._centre` now runs:
1. `EcsRoadPlanner.plan`: exits and main roads only;
2. **`EcsPlotPlanner.plan`**: plots, lanes, yards;
3. `EcsRoadPlanner.lay`: every road cell's floor into the commands, road cells and verges into
   `cleared_cells` (split out of `plan` so lanes are floored too).

**`EcsSettlementDef`, Plots group:** `plots` (count: hamlet 12–18, village 30–45, town 70–100),
`plot_size_centre` 7–10 and `plot_size_edge` 5–8 (sides, blended by distance from the plaza),
`plot_gap` 2, `yard_depth` 4, `lane_reach` 80. The old `lane_spacing`, `lane_length`, `lane_turn`
and `lane_branch_chance` are gone.

**The site record gained** `plots` ([{footprint, front, door, yard}]) and `plot_at` (cell → plot,
footprints and yards). Lanes are in `roads` and `road_cells` as before.

**The planner** works on the area's refined ground, marking each cell free, road (main roads,
bridges, plaza), water or footprint:
1. **Plots.** Spots are drawn half beside main roads (nearer the plaza more often, 4–10 cells off
   the road) and half round the plaza (radius biased inwards). A footprint fits when it is on free
   land, has land round it, is `plot_gap` from other footprints and 3 cells from the area's edge.
   Its **front** is the side whose door cell is fewest steps from a road (a 4-way BFS from roads,
   done once); the **door** is that side's middle cell. Up to 40 attempts per plot wanted.
2. **Lanes.** Plots nearest a road first. From the cell before the door, an 8-way A* (no corner
   cutting, ground costs from `road_costs` plus noise so lanes bend, guided by the BFS steps) runs
   to the **first road cell it reaches**, lanes already routed included — that is what merges
   them, with no reuse cost. A diagonal step takes a side cell, so lanes join edge to edge. A door
   already on a road needs no lane; a plot no lane reaches within `lane_reach` is dropped.
3. **Yards.** All footprints grow at once, a ring at a time over free land, to `yard_depth`
   rings; a cell goes to whichever plot reaches it first. Yards stop at roads, water and other
   yards, and the door's lane always touches.

Footprints and yards go into `cleared_cells`, so no node is planned on them. Nothing new is
drawn by the chunks: lanes are road floors; plots are only a record until buildings (step 6).

**`EcsPlotCheck.problems(…)`** reports a footprint outside the area, on water, a road, the plaza or
another plot; a door not on its front side or facing no road; a yard cell taken twice, on a road
or water, or cut off from its plot. `EcsRoadCheck` still checks every road cell, lanes included,
joins the plaza.

**Viewer:** footprints shaded brown with the door dark, yards tinted green, at both levels. The
info panel counts plots; the cell panel names a plot's footprint, door or yard, its size and
facing.

**Tests** (`plot_test`, 7): every town size over 6 seeds has sound plots and roads, with at least
80% of the plots wanted (measured: hamlet 88 for 72, village 204 for 180, town 447 for 420); the
same seed gives the same plots; a hamlet's area through module 10's build system, every command
accepted, every lane floored, no node on a footprint or yard.

**Measured** (stages timed alone): plots and lanes take ~0.1 s for a hamlet, ~0.45 s for a village,
~1.3 s for a town; the main roads' ~0.5–1.4 s is step 3's. Most of a town's plot time is placement
attempts (100 plots × 40 tries over footprint-sized rects) and the yard and BFS passes over its
110,000 cells.

**Not yet:**
- zones (step 5): sizes come from distance to the plaza;
- lanes wider than 1 (`lane_width` is not read by the plot planner);
- plots facing a road at a slant still face north, south, east or west: by design;
- yards are irregular; fences round them are step 7's question.


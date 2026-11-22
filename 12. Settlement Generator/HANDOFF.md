# Module 12 — Settlement Generator: state of the build

A whole settlement from a seed, on module 10's town grid. The plan is `PLAN.md` (nine steps);
this file is what exists. Module 9's ECS and module 10's grid, build commands, pathfinding and
catalogs are **borrowed, never copied**; new terrains and blueprints went into module 10's
catalogs, by decision (2026-11-08), so module 10's builder can place them too.

**Status (2026-11-10):** step 1 (terrain and resource nodes, on an **L2 region** with **L1**
streamed 8× into it in chunks), step 2 (the town's site, plaza and well, §3), step 3 (its main
roads, §4) and step 4 (plots, then the lanes they need, §5) are done. Steps 5–9 work on L1 only,
inside the town's area. Step 5 (what the town lives on and its building list, §6), step 5b
(each building places its own plot, works out at their resource, §7) and step 6 (its buildings,
§8) are done. Step 7a (outdoor works, fenced fields and pens, docks, wheels, §10) is done; 7b (plaza
dressing, gardens, house yards, dirt paths) is next.

```bash
# 41 checks, ~60 s; exit 0 only if all pass. Prints plan and load costs.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/terrain_test.tscn"
# Step 2: 14 checks, ~60 s. Prints how long picking a site takes.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/site_test.tscn"
# Step 3: 11 checks, ~60 s. Prints how long a town with its roads takes.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/road_test.tscn"
# Step 7a: 7 checks, ~60 s. Outdoor works, fences with gates, docks, wheels, every entrance walkable.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/outdoor_test.tscn"
# Step 6: 4 checks, ~60 s. Builds every town's buildings through module 10 and checks them.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/building_test.tscn"
# Steps 4, 5b and fields: 10 checks, ~70 s. Prints how long a town takes and what came up short.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/plot_test.tscn"
# Step 5: 7 checks, ~90 s. Prints what each town lives on and its mean survey.
"$GODOT" --headless --path . "res://12. Settlement Generator/tests/economy_test.tscn"
# The viewer: Generate makes the L2 region; the wheel zooms in until L1 streams in chunk by chunk.
"$GODOT" --path . "res://12. Settlement Generator/generator.tscn"
```

---

## 1. Layout

| Path | Role |
|---|---|
| `defs/` | `EcsLandDef` (what the land is: size, water, shares, shore, nodes, deposits, its L1 `child`), `EcsSettlementDef` (a tier of town: area, plaza, site, roads, economy, plot gap and yards), `EcsNodeSpawnDef` (where a node grows), `EcsDepositDef` (an ore or clay deposit), `EcsSettlementRoleDef` and `EcsSettlementCharacterDef` in `EcsEconomyCatalog` (`economy.tres`); `lands/`: `region` (L2), `l1` (its child); `settlements/`: `hamlet`, `village`, `town` |
| `ecs/` | `EcsTerrainGenerator` (pure: `plan`, `refine`, and the chunk stages `refine_terrain`, `refine_nodes`), `EcsTerrainCheck` (pure: `problems`, `follows`), `EcsTerrainChunks` (the L1 chunks kept in memory, what to make next, and the town's overlay), `EcsSitePicker` and `EcsSiteCheck` (pure: the town's site and centre), `EcsRoadPlanner` and `EcsRoadCheck` (pure: its roads), `EcsPlotPlanner` and `EcsPlotCheck` (pure: its plots and lanes), `EcsResourceSurvey` and `EcsTownEconomy` (pure: what is in reach, what the town lives on and builds), `EcsTownBuilder` (pure: its buildings, annexes, docks), `EcsOutdoorBuilder` (pure: a rule per outdoor work), `EcsProgress` (the viewer's progress record), `EcsSettlementSite` (the record) |
| `generator.tscn` | The viewer (`generator_view.gd`); its panel is built in code |
| `tests/` | `terrain_test.tscn`, `site_test.tscn`, `road_test.tscn`, `plot_test.tscn`, `economy_test.tscn`, `building_test.tscn`, `outdoor_test.tscn` |
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
1. **Water**, by `EcsLandDef.Water`:
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

| Land (`lands/`) | Size | Water | Notes |
|---|---|---|---|
| `region` | 256×192 | river to the sea | the L2 map. 8 m a cell, so 2 km × 1.5 km; an L1 window is 48×36 of its cells. No nodes, since they are L1 things; its deposits; `child` is `l1` |
| `l1` | (set by the caller) | — | the shore width and nodes of every L1 chunk and town area |

`terrain_test` also plans L1 land on its own at the three town sizes (160×120 lake, 256×192 river,
384×288 coast) from `l1`.

**Split (2026-11-10):** these were all `EcsSettlementDef`s, one class serving as the L2 recipe, the
L1 recipe and the town tier. Land is now `EcsLandDef` and a settlement has no water or nodes; a
town's L1 shore width is `region.child.shore_width`, the same land the chunks draw.

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

---

## 6. Step 5 — what the town is: deposits, survey, character, buildings (2026-11-10)

Decided: the building list is worked out before anything is placed, from what the town lives on
(its **character**), how big it is (its **tier**) and what is within reach. Tiers are Hamlet,
Village, Town, City, Great City (City and up later). **The character is always derived**, never
chosen.

**Deposits on L2 (a step 1 change).** Veins used to grow wherever their zone was, so every rocky
area had iron. Now:
- `EcsDepositDef` (key, ground, count, radius); the region def lists five: iron, coal, copper,
  gold on rock, clay on sand. `plan` adds `deposits` {ids per cell, keys, blobs}, on its own seed
  stage (8), so nothing else in a plan changed.
- `refine_terrain` returns the child's `deposits`: each cell its parent cell's.
- `EcsNodeSpawnDef.deposit` names the deposit a spawn grows in; `refine_nodes` takes `deposits`
  and clears every zone bit outside that deposit for that spawn, so neither starts nor a clump's
  walk leave it. The vein and clay pit spawns of hamlet, village and town name theirs.
- A map planned on its own (no region) has no deposits, so its veins grow anywhere in their zone
  as before.
- Viewer: deposits tinted over L2, fading with the roads; the cell panel names a cell's deposit.
- `terrain_test` (41 now): deposits lie on their ground; round each iron deposit L1 grows 111–148
  iron veins; none grows outside a deposit of its kind.

**`EcsResourceSurvey.of(site, …)`** (pure): the catchment is every region cell a walk of
`def.catchment` (hamlet 40, village 60, town 80, by `road_costs`) reaches, using the route costs
the road planner already made (`site.costs`). Scores 0–1: `arable`, `pasture`, `forest`, `rock`
(shares of the land), `fish`, `open_water`, `sea` and `river` (counted from land in reach that
touches water: a walk barely enters water, so counting water cells saw almost none), `trade`
(exits, plus sea or river), and one per deposit key (cells in reach / 24). A fact is present at
0.1; `holds(facts, all, any, absent)` is the one test of requirements.

**`EcsTownEconomy.plan(facts, def, seed, cell)`** (pure, seeded):
1. every character its tier allows and its facts hold is scored (weights × survey); the best is
   the main trade;
2. others at their `side_at` or more are side lines, at most 2, those clearing it furthest first;
3. roles: the tier's `base_roles`, the main trade's `core` × `trade_scale`, each side line's `side`
   set; a role the tier or facts don't allow is listed in `left_out`;
4. food: while residents outnumber what the roles feed, the first allowed of `food_roles`
   (farmhouse, fishing hut, herder) is added; a trading town buys 30%.

Result on `site.economy`: {character, scores, sides, roles [{role, count, from}], left_out,
population, fed}. It runs in `EcsSitePicker._centre` after the main roads, before the plots.

**Data** (`defs/economy.tres`): 48 roles (key, building type, min tier, requires / requires_any /
absent facts, residents, feeds) and 9 characters (farming, herding, fishing, timber, mining,
quarrying, pottery, trading, port), each with weights, requirements, core and side sets. A
windmill is `absent: river`, so a river town gets a watermill instead. Most roles name building
types module 10 doesn't have yet (step 6).

**Viewer:** the info panel gives what the town lives on, its people and food, the facts in reach
and its buildings.

**Tests** (`economy_test`, 7): 3 sizes × 3 kinds of water × 4 seeds — every town's main trade is
one its facts allow, its core is built, every role is allowed, everyone is fed; 5 main trades
among them (farming, fishing, timber, mining, trading); 3 towns mine on the side, each with a
mine, and a toolsmith who smelts where iron or copper is; same seed, same town; no deposits, no
mining.

**Measured:** survey and economy 5–17 ms a town (they took ~370 ms before reusing the road
planner's route costs).

**Not yet:**
- plots don't follow the list: their count is still `plots`, and nothing says which plot is which
  building (step 5b, role-led placement);
- herding, quarrying and port were never the main trade in the test's 36 towns; pottery was before
  the weights were tuned. The weights are a first pass;
- the info panel runs off the screen for a town's long building list;
- City and Great City.

---

## 7. Step 5b — plots placed by role (2026-11-10)

Decided: **each building on the economy's list places its own plot**, and **the town's area is a
guideline, not a border**. A work whose resource isn't in the area goes out to it; anything else
that fits nowhere grows the area.

**Data.** `EcsSettlementRoleDef` gained:
- `group` (home, food, craft, faith, trade, water, works), for the viewer;
- `size_min` and `size_max`;
- `priority`;
- `sites` (rule → weight);
- `must` and `must_any` (rules that must score 0.5);
- `yard_depth` (farmhouse 8, herder 6).

All 48 roles in `economy.tres` have them. `EcsSettlementDef` lost `plots`, `plot_size_centre` and
`plot_size_edge`. `lane_reach` went from 80 to 250, because outskirts farms are far from a road.

**Rules** (`EcsPlotPlanner.score_rule`, 0–1 at a footprint and its front):
- `plaza`: the door's cell is on the plaza or beside it.
- `centre` and `outskirts`: the footprint's distance from the well.
- `main_road`: from the door.
- `water`, `river`, `forest`, `rock` and each deposit key: the fewest steps from the footprint's
  ring to that ground. They use distance fields worked once per grid (`distance_from`), falling from
  1 to 0 over `NEAR`.
- `open`: no forest or rock within 6.
- `apart`: the gap to the nearest other footprint.

**The planner** (`EcsPlotPlanner.plan(site, def, terrain, ctx)`, rewritten round a `Grid`: rect,
kinds, river, deposits, use, reach, fields):
1. The role list is expanded to one entry per building, highest `priority` first.
2. **Each entry is placed in the area:**
   - 40 tries at the role's size, drawn round the plaza (flush against a side, so a wide manor
     can face it), beside a main road, or anywhere;
   - each fitting footprint is weighed **on every side whose door could reach a road**, by the
     role's `sites` plus a little noise; `must` and `must_any` refuse;
   - the best is kept.
3. **A work that fits nowhere inside goes out** (`_go_out`). A work is a role whose `must` or
   `must_any` names a resource: river, water, forest, rock or a deposit key.
   - First it tries a window already opened for its resource.
   - Then it tries new 32×32 L1 windows round the catchment's cells of that resource, nearest by
     route first, up to 6.
   - Each window gets a **track** first (`_track`): from its border cell nearest the well, routed
     by `AStarGrid2D` on L2 round the area and other windows to the nearest main road, drawn 1 cell
     wide on L1. A cell on water is a bridge.
   - **A window where nothing fits is undone with its track**, so no track leads nowhere.
4. **Anything else that fits nowhere grows the area** 16 cells a side, up to 4 times, re-refined.
   This never triggered in the tests' 18 towns, so it is untested.
5. Whatever still fits nowhere goes to `site.economy.short`.
6. **Lanes** run per grid, as in step 4. Lanes may step onto a road on a grid's border, which is
   where a track enters a window. A plot no lane reaches is dropped and counted short.
7. **Yards** run per grid, to each role's depth.
8. `site.outlying` records each window: {rect, resource, terrain}. `site.bridges` is recounted.

**`EcsPlotCheck`** also reports:
- a plot for no building;
- a plot outside the area and every window;
- a plot whose role's `must` rules don't hold where it stands.

**Viewer:**
- footprints tinted by group;
- outlying windows outlined in orange;
- tracks drawn paler than lanes;
- the info panel gives metres of track, outlying plots and windows, and what is short;
- the cell panel names a plot's building;
- moving the town also redraws chunks under its roads and windows, not only its area.

**Tests** (`plot_test`, 9), 6 seeds each:

| Size | Buildings placed | Short | Plots outside the area |
|---|---|---|---|
| hamlet | 73 of 73 | 0 | 3, in 2 windows |
| village | 197 of 197 | 0 | 11, in 6 windows |
| town | 533 of 540 | 5 miners' huts, a mine, a farmhouse | 11, in 7 windows |

- every plot sound and every road joined;
- 12 of 12 manors face the plaza;
- houses stand 60 cells from the well on average, farmhouses 146;
- same seed, same plots and roles;
- the hamlet's area through module 10's build system.

**Measured** (one hamlet and one town, stages timed alone):

| Stage | Hamlet | Town |
|---|---|---|
| placing in the area | 0.16–0.19 s | 0.5 s |
| windows and tracks | 0 | 0.1–0.3 s |
| lanes | 0.35–0.66 s | 0.9–1.65 s |
| yards | ~0.01 s | ~0.04 s |

Lanes are the largest part, with `lane_reach` at 250. A whole town pick in the test took ~2.2 s for
a hamlet, ~2.7 s for a village and ~4.6 s for a town, including the region plan; the main roads alone took 1–2 s, so this
machine was slower than at step 4.

**Not yet:**
- area growth is untested (it never triggered);
- a few works still come up short in big towns (no fit in 6 windows) and get no third try;
- lanes route with dictionaries in GDScript; they are the first thing to speed up;
- fields, pens and docks are only yards until step 7.

---

## 8. Step 6 — buildings (2026-11-10)

Decided:
- **rooms by role**, on few building types;
- **buildings split across chunks**;
- **module 10's generator takes the door cell**;
- **a building of more than one room isn't just a rectangle**.

Module 10's side is its HANDOFF §13b: shapes, the preferred entrance, cut sides, 9 building types,
14 room types and 24 furniture placeholders.

**Roles** (`EcsSettlementRoleDef`) gained:
- `rooms`: room roles that replace the building type's;
- `wealth`: −1 takes it from the place.

The `building` keys now name module 10 types. Market, mine, quarry, lumber camp, clay pit, harbour
and shrine have none: they are outdoor works for step 7. House, headman, merchant house, tavern,
inn and farmhouse grew, so their footprints have room for a shape.

**`EcsTownBuilder.build(site, catalog, seed)`** runs in `EcsSitePicker._centre` after the plots
and before `EcsRoadPlanner.lay`. For each walled plot:
1. Its type: a copy whose `roles` are the role's `rooms`, when it lists any.
2. Its wealth: the role's, or rich, middling or poor by the `centre` rule at ⅔ and ⅓.
3. `EcsBuildingGenerator.plan` on the footprint, facing the front, the door cell preferred. The
   commands go into `site.commands`.
4. The plot gains `building`: {type, wealth, entrance, shape, cells}.
5. When the entrance isn't the door cell, the lane is carried along the front to it, `door`
   becomes the entrance, and yard cells the carried lane cut off are dropped.

Roles whose type the catalog lacks go to `economy.unbuilt`.

**Chunks** (`EcsTerrainChunks.clip(site, own, border, objects)`, which `overlay` and the tests share):
- CREATE_BUILDING is clipped to the chunk's cells plus border, its sides that go on marked
  **cut**.
- Walls, doors and floors go to every chunk holding them.
- Furniture goes only to the chunk holding its origin. A piece is at most 2 cells, so it stays
  within that chunk's border.
- The viewer's chunk worlds now run room detection and roofs, and their roofs draw above pieces
  and walls. The border trim erases roof tiles too. The **Roofs** box shows or hides them. Plot
  tints fade as L1 shows the real buildings, and the cell panel names a cell's building (type,
  wealth, shape) and room.

**Tests** (`building_test`, 4), 3 seeds each:

| Size | Buildings | Plain | L | T |
|---|---|---|---|---|
| hamlet | 38 | 36 | 2 | 0 |
| village | 100 | 88 | 11 | 1 |
| town | 258 | 221 | 36 | 1 |

- every building's commands are accepted by module 10 in a world of the town's area or window;
- every building passes `EcsBuildingCheck`;
- every building is entered from a road;
- a chapel across 2 chunks: every clipped command accepted, and walls, floors and roof the same
  per chunk as built whole, on all 72 roofed cells.

`plot_test`, `site_test` and `road_test` now build the area through `clip`, which keeps a
building's rect; their floor checks read floors only. Module 10's `town_test` (142) and
`generator_test` (111) pass.

**Measured:** a whole town pick (region plan included) took ~2.3 s for a hamlet, ~2.6 s for a
village and ~4.1 s for a town. The generator adds 0.3–2.5 ms a building, ~0.3 s for a town.

**Not yet:**
- most houses are plain: a poor house has one room, and only multi-room buildings take shapes;
- a few more buildings come up short than in step 5b (village 6, town 12), as farmhouses and
  houses grew;
- outdoor works, fences and gardens: step 7.

### Farm fields (2026-11-10, pulled forward from step 7)

A farmhouse has a **field**: dirt ground with crop rows, beside it.
- **Data:** `EcsSettlementRoleDef.field_min` and `field_max` (farmhouse 8×6 to 14×10; zero means
  none). `EcsSettlementDef.field_terrain` is `dirt` and `field_crop` is `crop`.
- **Placing** (`EcsPlotPlanner._field_for`): a farmhouse spot is taken only when a field fits
  beside it.
  - The field goes on a side other than its front, one cell clear of the house so a yard path
    runs between, its long side along the house.
  - It is the largest of three sizes in the range that fits on any side, sides in random order.
  - It must be on free land, a cell clear of every footprint and field.
  - Fields are `Use.FIELD`, which blocks plots, lanes and yards.
  - The plot gains `field`, and its cells go into `plot_at` and `cleared_cells`.
- **Building** (`EcsTownBuilder._sow`): SET_TERRAIN dirt on every cell, then a crop on every other
  row along the long side. No module 10 rule changed: a crop may not stand on a floor, but dirt is
  terrain.
- **Check:** every farmhouse has a field, within its ground, beside it and not by its door, on cells
  no road, water, plaza or other plot takes.
- **Viewer:** fields tinted over the region; the cell panel names a plot's field.
- **Tests** (`plot_test`, 10 now): all 171 farmhouses over 18 towns have a field; a hamlet's area
  with its fields and crops is accepted by module 10 (4,562 commands). Fewer buildings came up
  short than without fields: village 2, town 6.

---

## 9. Viewer: progress bar (2026-11-10)

A bar and a line under **Generate** say what is being made and how far along it is.
- **`EcsProgress`** (`ecs/`) is a small mutex-guarded record: `report(stage, part)` from the
  worker, `read()` from the viewer each frame, and `within(from, to)` maps the reports that follow
  onto a share of the bar.
- **Optional `progress` parameters:** `EcsTerrainGenerator.plan`, `EcsSitePicker.pick` and
  `place`, `EcsPlotPlanner.plan` (through `ctx`) and `EcsTownBuilder.build` take one and report
  through `EcsProgress.say`, which does nothing without one. So the tests are unchanged.
- **Stages:**
  - the region: water, shore, rocky ground, forest, deposits, nodes and commands;
  - the region's tiles, then the terrain check;
  - the town: scoring sites, refining its ground and plaza (and which site is being tried), main
    roads, the survey, each plot by name and count, lanes (per outlying work), yards, each building
    by name and count, road floors.
- **Shares** follow measured time: the region plan 5%, its tiles 37%, the town 58%. Within the
  town, its main roads and site scoring are the long parts.
- **Moving the town** (right-click or Town size) shows the town's stages over the whole bar.
- **At L1, with no job running,** it counts the chunks in view that are made ("Streaming L1 ground
  into view: n of m chunks made") and hides when they all are.

---

## 10. Step 7a — outdoor works, fences, pens, docks, wheels (2026-11-10)

Decided:
- **a small rule per outdoor work**, in code;
- a **dirt path floor**, and **house yards fenced and gardened by wealth** (both 7b);
- **7 in two halves.**

**Annexes** generalise step 6's fields. `EcsSettlementRoleDef.annex` is `field`, `pen` or `dock`,
with `annex_min` and `annex_max`:
- farmhouse: field;
- herder, barn and stable: pen, 6×5 to 9×7;
- fishing hut, boatwright and harbour: dock.

A field or pen is placed as fields were (`_annex_for`). The plot gains `annex` and `annex_kind`
(the old `field` key is gone).

`EcsTownBuilder._annex`:
- A **fence** (module 10 objects, one a cell, turned along its edge) runs round the edge, but for
  a **2-cell gate** in the middle of the side facing the house. The cells inside the gate are kept
  clear.
- A **field** is dirt, with a scarecrow at its middle, a haystack in a corner, and crops on every
  other row inside the fence.
- A **pen** holds a trough at its back and hay in a corner.

**Docks** (`EcsPlotPlanner._dock`, after yards). Sides are tried back, sides, then front. From the
middle of a side, the walk goes out up to 8 cells over land no footprint or annex takes until both
cells of a 2-wide pair are water. Then the pier runs out while the water allows, up to 6. Under 2
pairs, that side is skipped.
- The plot gains `dock` {cells, boat, boat_turns, post}.
- The builder lays a wood floor (`bridge_floor`), so module 10's nav walks it as it walks bridges.
- A mooring post goes on the pier's end, and a 2×1 boat past it along its run when that is water.

**The watermill's wheel** (`_wheel`) is the river cell nearest its footprint within 6, as its
`river` rule lets it stand ~5 away. The builder places a `water_wheel` there.

**Outdoor works** (`EcsOutdoorBuilder.lay`, one `match` arm per work). The rules are built from a
`Lot`'s helpers: `ring` (along the back and sides every n cells), `middle` (or nearest spot back
from the way in), `at_back`, `scatter`, `beside_door`, `lay_floor`, `lay_ground`. The door's cell
and the one inside it are never used.

| Work | Ground | Pieces |
|---|---|---|
| market | stone | stalls in the ring, crates, a notice board |
| mine | — | entrance at the back, ore cart, stone piles |
| quarry | — | stone piles in the ring, a sawhorse, crates |
| lumber camp | dirt | log piles in the ring, chopping block, stumps |
| clay pit | dirt | clay pits, drying racks |
| harbour | — | crates and mooring posts (plus its dock) |
| shrine | stone | the shrine |

A work with no rule goes to `economy.unbuilt`.

**Module 10 content:** 14 objects on a new `outdoor.png` sheet: fence, scarecrow, haystack, market
stall (2×1), notice board, chopping block, stump, stone pile, mine entrance (2×2), drying rack,
boat (2×1), mooring post, water wheel, shrine. Trough, hay pile, crate, ore cart, lumber pile and
sawhorse are step 6's.

**Viewer:** pens tinted green, fields gold and docks brown over the region; the cell panel names a
plot's field or pen.

**Tests** (`outdoor_test`, 7), over 9 towns:
- the outdoor works found (5 markets, a mine, a quarry) are laid with their way in clear;
- every work's rule, on a plot facing every way, lays its pieces (278) inside it, none on the way
  in. This covers works the towns lacked;
- 99 of 99 fields and pens are fenced with a 2-cell gate by their house;
- 5 of 5 docks are laid, and 47 of 47 pier cells (all but the posts) are water under wood and
  walkable by module 10's nav;
- 7 of 7 watermills have a wheel;
- every command of the 9 towns' areas, with terrain, is accepted by module 10;
- **390 of 390 entrances can be walked to from the well past every fence.**

`plot_test` now checks all 201 farmhouses, herders, barns and stables have their field or pen.


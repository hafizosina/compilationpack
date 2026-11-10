# Module 12 — Settlement Generator: plan (draft, 2026-11-08)

A whole town from a seed: terrain, a centre, roads, plots, and the right building on each plot —
farmhouses on the outskirts with fields, fishing huts on the shore, a manor near the centre.
Module 10 makes one building; module 12 decides **where every building goes and why**.

**Status (2026-11-08): step 1 is done** — on two levels, an L2 region and L1 windows zoomed into
it (see `HANDOFF.md`). Steps 2–9 are planned for L1 only. Answered: question 4 (terrain is
generated here), question 5 (new content goes into module 10's catalogs), the map sizes
(160×120 / 256×192 / 384×288), the name, and the world is finite.

---

## Rules carried over

- **Borrow, never copy.** Module 9's ECS and module 10's grid, build commands, building
  generator, room detection and pathfinding are used as they are. Module 10 changes only through
  a hook the author approves first.
- **The output is build commands.** Like module 10's generator, the planner is pure and seeded
  and gives back the commands the player's tools send. Every building goes through the build system's
  own checks, and anything that works for a hand-built town works for a generated one: rooms,
  roofs, saves, pathfinding.
- **Same seed, same town.** One `RandomNumberGenerator`, seeded once per stage.
- **Data first.** What a town has, and where each kind of building likes to stand, is in `.tres`
  defs, not code. A new kind of hut is a def.

---

## The pipeline

Each stage reads the stages before it and adds one layer. Each is a pure function with a viewer
toggle and a test.

### Step 1 — Terrain ✅ (2026-11-08, `HANDOFF.md` §2; also an L2 region with L1 zoom)
Seeded noise (`FastNoiseLite`) over the map: **water** (a lake, a river or a coast — one per
town def), **sand** along the shore, **forest** zones, **rocky ground** (a hill or an outcrop,
where the mine nodes are) and open grass for fields. Then the **resource nodes** are scattered
over it (see *Resource nodes* below): trees and bushes in the forest, stone and ore on the rocks,
reeds and clay at the water.
- *Done when:* the same seed gives the same map; the water is one body (or one river edge to
  edge); land is within the def's share; there's room for the town's plots; every node kind the
  town def asks for is present.

### Step 2 — Site and centre ✅ (done 2026-11-08, `HANDOFF.md` §3)

**Goal.** One town per region. A site is picked on the L2 region, the town gets a fixed L1 area
there, and the centre of that area becomes a stone plaza with the well. Steps 3–9 then work inside
that area, on L1 only.

**Decided (2026-11-08):**
- one town per region;
- the generator scores and picks the site, and a right-click in the viewer moves the town;
- a **Town size** option on the panel sets the town's L1 area, from the shipped defs: hamlet
  160×120, village 256×192, town 384×288.

#### 2.1 What it builds on
- The L2 region plan: kinds, zones, river mask, coast side (step 1).
- L1 is streamed in chunks (`EcsTerrainChunks`), and `refine_terrain` gives any L1 area cell for
  cell the same as the chunks. **So the town is an overlay on the chunks, not a separate map.**
  - Its commands are kept by L1 cell.
  - A chunk drawn over the town takes the town's commands for its cells.
  - Node planning skips cells the town clears.
- Module 10's `well` blueprint and `stone` floor exist. The plaza needs no new art.

#### 2.2 Data
**`EcsSettlementDef` gains**:
- `plaza_size` (Vector2i): hamlet 8×8, village 12×12, town 16×16;
- `plaza_floor` (`&"stone"`) and `well` (`&"well"`);
- `clear_margin` (int, default 2): node-free cells kept round the plaza;
- the site weights, so tuning a town is data:
  - `water_near` (Vector2i, min–max distance in L2 cells, default 2–10);
  - `water_weight`, `open_weight`, `edge_margin_cells`.

**`EcsSettlementSite`** (a plain `RefCounted` record, the town's plan from here on):
- `l2_cell`: the site;
- `area`: the town's L1 rect, centred on the site and kept inside the region;
- `plaza`: L1 rect;
- `well`: L1 cell;
- `commands`: L1-cell build commands, plaza floor then well;
- `cleared`: a `Rect2i` list nodes must stay out of;
- `score` and its parts, for the viewer.

#### 2.3 Picking the site — `EcsSitePicker.pick(region_plan, region_def, def, rng_seed)` (pure)
Runs on L2 only (49k cells; tens of ms), so it can rescore on a click.
1. **Candidates:** L2 cells that are land (not water), whose whole town area fits inside the
   region with `edge_margin_cells` to spare.
2. **Score**, each part 0–1, summed by weight:
   - **Water near:** BFS distance from water. Full marks between `water_near.x` and `.y`, falling to
     0 outside. A river or coast both count, and a river adds a little, since mills want one.
   - **Open land:** the share of grass and sand within the plaza-sized L2 neighbourhood
     (plaza_size / 8, at least 3×3). Forest and rock count half, water nothing.
   - **Room:** the share of land, not water, in the whole town area. Below 70% the candidate is
     dropped.
   - **Reach:** the candidate's land area (4-connected, not water) must touch the region's edge, so
     roads can leave (step 3). Done once with `EcsTerrainGenerator.areas`.
3. **Best:** the highest score; ties go to the cell nearest the region's centre, then the seeded
   RNG, so the same seed gives the same site.
4. **Moved by hand:** `place(region_plan, region_def, def, l2_cell)` builds the same record at a
   chosen cell. It refuses water, or a town area that doesn't fit, with the reason.

#### 2.4 The plaza and well on L1 — `EcsSitePicker.centre(site, region_plan, …)`
1. Refine the town area's terrain (`refine_terrain`, with the region's `blend_shares`). That's one
   area, the same cells the chunks will draw.
2. **The plaza rect:** search outward from the site's centre cell in a spiral, within 1/4 of the
   area. Take the first `plaza_size` rect with:
   - no water;
   - the fewest forest and rock cells, all of which it clears.
   It is never placed on water. If none fits, the site fails and the picker takes the next best.
3. **The well:** the plaza's centre cell.
4. **Commands** (L1 cells):
   - `SET_FLOOR` stone on every plaza cell;
   - `PLACE_OBJECT` well.

   No terrain changes: the plaza is a floor over the ground, so the L2 ↔ L1 rules still hold.
5. **Cleared:** the plaza grown by `clear_margin`. No node is planned there.
6. **Reach check:** an `AStarGrid2D` over the town area, with nodes treated as solid after the
   clearing. A path must run from the plaza's edge to the area's edge. If none does, the cleared
   ring is widened toward the nearest edge, or the next site is tried.

#### 2.5 Into the chunks (viewer and later the game)
- `EcsTerrainChunks` gets an **overlay**: L1 cell → commands, plus a cleared mask. The site
  registers its commands and cleared rects.
- **Objects stage:** `refine_nodes` gets a `skip` callable, or a cleared mask over the chunk, so no
  node lands in a cleared rect.
- **Draw stages:** after its terrain commands, a chunk takes the overlay commands for its cells,
  moved by its border offset. A plaza split across chunks draws as one: the floor is dual-grid,
  and the borders are each other's cells.
- A new site, after Generate or a right-click, drops the chunks that overlap the old and new town
  areas, so they redraw. Other chunks stay.

#### 2.6 Viewer
- **Town size** option (hamlet, village, town).
- **On L2:** an outline of the town area and of the plaza, and the score in the info panel.
- **Right-click** on L2 or L1 moves the town to that cell (`place`); a refusal shows its reason.
- **The cell panel** says when a cell is in the town, the plaza or a cleared ring, and shows the
  site's score parts when the site cell is picked.

#### 2.7 Check — `EcsSiteCheck.problems(site, region_plan, region_def, def)` (pure)
- The town area is inside the region; the site cell is land.
- The plaza is inside the area, with no water under it; the well is in the plaza.
- No planned node in a cleared rect (checked against the chunks' nodes in the test).
- A walkable path from the plaza to the area's edge, and the site's land touches the region's edge.
- The same seed gives the same site and commands.

#### 2.8 Tests (`tests/site_test.tscn`, or new checks in `terrain_test`)
- **Sites:** 30 seeds × 3 town sizes × the region's water kinds; every site sound.
- **Moving by hand:** onto water is refused, onto an edge cell where the area doesn't fit is
  refused, and a good cell is accepted.
- **Through module 10's build system:** the town area with its plaza commands, every command
  accepted. The stone floor covers the plaza, the well is born on its cell, and no node sits in
  the cleared ring.
- **Seams:** a plaza drawn across 4 chunks gives the same floor and well as the area drawn whole.
- **Measured:** site scoring on L2, the plaza search on L1, and the extra cost per chunk.

#### 2.9 Not in step 2
Roads (step 3) — the reach check only proves one can be built. Buildings, plots, a second
settlement, height or slope (L2 has no height yet), and a plaza shape other than a rectangle.

- *Done when:* every seed's town has a sound site, a stone plaza with the well on land,
  reachable from the area's edge, drawn the same across chunks. The viewer shows it, and a
  right-click moves it.

### Step 3 — Roads ✅ (done 2026-11-08, `HANDOFF.md` §4)

**Goal.** The town's roads:
- **main roads** from the plaza to 2–4 exits on the region's edge, routed on L2 and drawn on L1
  wherever they pass;
- **lanes** branching off them inside the town's area, on L1.

Every later step hangs off these: plots line them (step 4), buildings face them (step 6), paths join
doors to them (step 7).

**Decided (2026-11-08):**
- main roads run to the region's edge, not only the town's;
- the layout is **organic**: roads follow the terrain, and lanes branch and bend round obstacles;
- **bridges where needed**: a road may cross water at a high cost.

#### 3.1 What it builds on
- **The site (step 2):** the plaza, the town's L1 area, and the overlay the chunks draw (floors on
  their cells and border, objects once, nodes kept off cleared ground).
- **The region plan (step 1):** kinds, the river mask and lines, the coast side.
- **Module 10:** the `road` floor (`walk_cost` 0.6) and `wood` floor already exist. A floor laid
  over water is walkable there (its own walk cost replaces the terrain's), so **a bridge is a wood
  floor over water**, with no new rule and no new art.

#### 3.2 Data
**`EcsSettlementDef`, a Roads group:**
- `exits` (Vector2i, 2–4): how many main roads leave;
- `main_width` (2) and `lane_width` (1), in L1 cells;
- `road_floor` (`road`) and `bridge_floor` (`wood`);
- `road_costs`: a step's cost by ground for routing — grass 1, sand 1.2, forest 3, rock 4, water 30.
  High enough that a bridge is taken only when going round is far longer;
- `reuse_cost` (0.3): a step on a road already routed costs this share, so main roads share a
  trunk out of town before forking, as real ones do;
- `lane_spacing` (12–20 L1 cells between branches), `lane_length` (8–40), `lane_turn` (degrees a
  step may bend), `lane_branch_chance`;
- `verge` (1): node-free cells kept beside main roads.

**`EcsSettlementSite` gains**:
- `roads`: [{kind: main or lane, points: L1 polyline, width}];
- `exits`: L2 cells;
- `road_cells`: L1 cell → main, lane or bridge;
- `cleared_cells`: cells nodes must stay off, beside the existing cleared rects.

Road and bridge floors are appended to `commands`, so the chunks' overlay needs no change for drawing.

#### 3.3 Exits — `EcsRoadPlanner` (pure; new file)
1. The region's edge cells are split into `exits.y` sectors by angle round the site. The number
   used is picked by the seed in `exits`.
2. In each sector, land edge cells are sampled (every 8th), and the one whose route from the site
   is cheapest is kept. Routing uses an `AStarGrid2D` over L2: 8 directions, no corner cutting,
   weights from `road_costs`.
3. Sectors whose cheapest exit is unreachable (cut off by the sea) are dropped. At least one exit
   must remain, which step 2's reach check guarantees.

#### 3.4 Main roads on L2
- Routed one exit at a time, nearest first, with the cells of roads already routed costing
  `reuse_cost`, so they merge into a trunk.
- Kept as polylines in L2 cells, like rivers, then smoothed (two rounds of Chaikin) so the L1
  course curves.
- **Bridges:** an L2 water cell on a route is a crossing. Allowed, but its cost keeps crossings
  short and few. The count is reported.

#### 3.5 Main roads on L1
- Each L2 polyline is scaled 8× into L1 cells, with the same seeded wander as rivers (±1.5 cells,
  read in region coordinates, so chunks agree). It is drawn `main_width` wide.
- Inside the town's area it starts at the plaza's nearest edge, not its centre.
- Each L1 road cell on water is a **bridge** (`bridge_floor`); else a road (`road_floor`). Plaza
  cells keep their stone.
- The whole region's main road cells are worked out at once: a few thousand cells, so chunks only
  look them up.

#### 3.6 Lanes on L1 (inside the town's area)
> **Superseded by step 4 (2026-11-10):** lanes will be routed from plots, not walked off roads.

- Grown from the main roads and the plaza's sides. Every `lane_spacing` cells along a main road
  inside the area, by `lane_branch_chance`, a lane leaves to one side or both.
- A lane walks one cell at a time from its heading, turning at most `lane_turn` a step, nudged by
  noise. It stops at:
  - the area's edge;
  - `lane_length`;
  - water (lanes never bridge);
  - a road or lane within 2 cells, which it joins, making a loop.
- Forest and rock are crossed and cleared.
- One more level: a lane may branch once more at half the chance, so the town thickens near the
  centre.
- Lanes are worked on the area's own refined terrain (`refine_terrain`, as the plaza search), so
  they avoid exactly the L1 water the chunks draw.

#### 3.7 Clearing
- Road and lane cells, and a `verge` beside main roads, go into `cleared_cells`.
- `EcsTerrainChunks.blocked` marks them too, so no tree or rock is planned on a road or right at
  its side.

#### 3.8 Into the chunks and the viewer
- **Chunks:** nothing new to draw. Road and bridge floors are in the site's commands, and the
  overlay already gives each chunk its cells and border. Only `blocked` learns `cleared_cells`.
- **L2 view:** the region's tiles can't show a 2-cell road, so main roads and lanes are drawn as
  lines over the region (`Line2D` per polyline, main roads thicker) and the exits marked.
  Bridges show as a lighter segment.
- **The cell panel:** "main road", "lane" or "bridge" on L1 cells. On L2 cells, a road passing
  through.
- **The info panel:** exits, main road length in metres, lanes, bridges.
- **A moved town** (right-click or Town size) re-plans its roads with its site, in the same worker
  job.

#### 3.9 Check — `EcsRoadCheck.problems(site, region_plan, …)` (pure)
- Every main road joins the plaza to an exit on the region's edge.
- Every road cell is land or a bridge, and lanes never bridge.
- All road cells are one network, joined to the plaza: a flood over road cells.
- Bridges are under a cap (default 3 per town).
- Given planned nodes, none on a road cell or verge.
- The same seed gives the same roads.

#### 3.10 Tests (`tests/road_test.tscn`)
- **Roads sound:** 10 seeds × 3 town sizes (and the coast and river water kinds).
- **Merging:** two exits close together share a trunk. The overlap of their L2 routes is above zero.
- **A river crossing** (on a seed whose exit is across the river) gives a bridge of `bridge_floor`
  cells, and the bridge is walkable in module 10's nav.
- **Through module 10's build system:** the town's area with plaza, roads and lanes. Every command
  accepted, road floor on every road cell, no node on a road or verge.
- **Chunks:** roads crossing several chunks draw the same floors in each chunk's cells and border.
- **Measured:** exits and main roads on L2, the L1 rasterising, lanes, the cost per chunk.

#### 3.11 Not in step 3
- plots (step 4) and buildings;
- roads between settlements (one town per region);
- road ranks beyond main and lane;
- crossroads features, slopes and gradients (no height yet);
- traffic.

- *Done when:* every seed's town has 2–4 main roads to the region's edge and organic lanes in its
  area, all joined to the plaza, bridged only where they must be, drawn the same across chunks,
  kept clear of nodes, shown on both levels, and re-planned when the town moves.

### Step 4 — Plots, then the lanes they need ✅ (done 2026-11-10, `HANDOFF.md` §5)

**Goal.** Inside the town, **buildings dictate the roads, not the other way round**: plots are
placed first, square to the grid, and lanes are routed between them, so buildings stay square
(module 10's walls, rooms and doors are all grid-aligned) and roads stay natural. Then each plot
grows out to meet its lane.

**Decided (2026-11-10):**
- plots are placed before lanes; **plot-led lanes replace step 3's lane walker** (§3.6);
- main roads, exits and bridges stay as step 3 built them: the spine, fixed before any plot;
- a plot's building footprint is a grid-aligned rectangle; its yard may be irregular.

#### 4.1 What it builds on
- **Step 3:** main roads on L1, their verge, bridges, `road_cells`, `cleared_cells`, and
  `EcsRoadCheck`'s flood from the well.
- **Step 2:** the plaza, the town's L1 area and its refined ground.
- **Module 10:** buildings take an entrance side; its generator fills a footprint.

#### 4.2 Data
**`EcsSettlementDef`, a Plots group:**
- `plots` (count range: hamlet 12–18, village 30–45, town 70–100);
- `plot_size_centre` (7–10) and `plot_size_edge` (5–8), L1 cells a side: blended by distance from
  the plaza — a stand-in until step 5's zones;
- `plot_gap` (2): cells kept between footprints, so a lane fits;
- `yard_depth` (4): rings a yard may grow;
- `lane_reach` (80): the dearest route a lane may take; a plot further out is dropped.

Built differently from first planned: a count instead of a density (thinning comes from where
spots are drawn), and no `lane_reuse_cost` — a lane stops at the first road it reaches, so lanes
merge without one.

**`EcsSettlementSite` gains:**
- `plots`: [{footprint: Rect2i, front: N/E/S/W, door: L1 cell, yard: cells}];
- lanes join `roads` as `kind: lane`, as before.

#### 4.3 Placing plots — `EcsPlotPlanner` (pure; new file)
1. Candidate spots are drawn round the plaza and along main roads, densest near the centre.
2. Each gets a footprint size by its distance from the plaza.
3. Its **front** is the side facing the plaza or the nearest main road; its **door** is a cell
   on that side.
4. It is kept only if the footprint plus `plot_gap` overlaps no road, verge, plaza, water or
   other plot. Forest and rock under it are cleared, as roads clear them.

#### 4.4 Lanes from the plots
- Plots are taken nearest the network first. From the cell in front of each door, a path is
  found (8-way A* on the area's ground, footprints and their gap blocked, water blocked: lanes
  never bridge) to the nearest road cell.
- Road cells cost `lane_reuse_cost`, so neighbours' paths merge into shared lanes; each lane
  routed is road for the next.
- Lanes are `lane_width` wide, floored `road_floor`, cleared like roads.
- A plot whose door can't reach a road is dropped.

#### 4.5 Plots meet the road
- Each plot's yard grows from its footprint outwards, a ring at a time, over free cells, until it
  touches its lane or a neighbour's yard. The footprint stays square inside it.
- Cells no yard claims stay green space.
- Yards are where step 7 puts fences and gardens.

#### 4.6 Check — `EcsPlotCheck.problems(site, …)` (pure)
- No footprint overlaps a road, water, the plaza or another footprint.
- Every door has a road cell in front of it.
- Every road cell is joined to the plaza (`EcsRoadCheck`'s flood).
- Every yard touches its plot's lane, and no yard overlaps another.
- The same seed gives the same plots.

#### 4.7 Viewer and tests
- **Viewer:** footprints outlined, doors marked, yards tinted; the info panel counts plots and
  lane metres.
- **Tests:** every town size over several seeds passes the check; plots and lanes through module
  10's build system, every command accepted; the same seed, the same plots; measured cost.

#### 4.8 Not in step 4
- zones and building types (step 5): sizes come from distance for now;
- buildings themselves (step 6);
- fences and gardens on yards (step 7).

#### 4.9 Open
- **Yard shape:** irregular to meet a curved lane (proposed above), or grown as a rectangle until
  it touches, the gap left as verge.
- ~~Step 3's lane walker~~: deleted with step 4.

- *Done when:* every plot's footprint is square and clear, its door faces a road cell, its yard
  meets its lane, and every lane joins the plaza.

### Step 5 — Zoning: which building goes where
Each building kind is a **`EcsSettlementRoleDef`**: its building type, how many (fixed or per
population), its plot size, where it likes to stand, and its wealth.

| Role | Count | Where it stands | Wealth |
|---|---|---|---|
| Manor | 1 | Next to the plaza, the largest plot, with a garden | rich |
| House | per population | Rings round the centre | falls with distance from the centre |
| Tavern / inn | 1 (2 in a town) | On the plaza or a main road | middling |
| Market | 1 | On the plaza: stalls, no building | — |
| Blacksmith | 1–2 | On a main road, away from the houses' rings | middling |
| Carpenter | 1–2 | On a main road, near the forest side | middling |
| Bakery | 1 per ~20 houses | Near the plaza, close to the mill's road | middling |
| Storehouse / granary | 1–2 | Between the fields and the centre | — |
| Farmhouse | per population | The outskirts, with a **farm plot** beside it | poor–middling |
| Barn / stable | 1 per 2–3 farms | Beside a farm plot, with an **animal pen** | poor |
| Mill | 1 | A **watermill** on a river bank, else a **windmill** on open ground at the outskirts | middling |
| Fishing hut | 1–3 | On the **shoreline**, with a **dock** | poor |
| Gathering hut | 1–2 | At the forest's edge | poor |
| Hunting hut | 1 | At the forest's edge, away from the centre | poor |
| Lumber camp | 1 | Inside the forest's edge: a log pile and a chopping block, no walls | — |
| Miner's hut | 1 (village and up) | At the rocky ground's edge, by the mine entrance | poor |
| Quarry | 1 | On rocky ground: stone nodes cleared to a pit, a stone pile, no walls | — |
| Chapel | 1 (village and up) | Near the plaza, on its own plot | middling |
| Well | 1 + 1 per district | The plaza, then district centres | — |

Site rules are a small fixed set, each a score: near the centre, near water, at the forest's
edge, on a main road, on the outskirts. A role lists the ones it wants with weights. Plots are
handed out in role priority order, each to its best-scoring free plot.
- *Done when:* every role's count is met (or reported short), and every hut is where its rule
  says.

### Step 6 — Buildings
Each assigned plot calls module 10's `EcsBuildingGenerator` with the role's type, wealth, plot
size and facing. Every new type, its room types and its furniture are listed under **Content to
add** below.
- *Done when:* every building passes module 10's `EcsBuildingCheck` (sound, every room reachable
  from its entrance).

### Step 7 — Outdoors
Outdoor areas are **yards**: a plot with no walls, filled by its own small layout rule.
- **Farm plots** beside farmhouses: rows of crops with a 1-cell path between rows, a fence round
  the edge with a gap facing the farmhouse, a scarecrow and a haystack.
- **Animal pens** beside barns: fenced, with a trough.
- **Shoreline:** sand along the water. A fishing hut gets a **dock**, a wooden floor laid over
  water, which module 10's walk costs already treat as walkable, with a boat moored beside it.
- **The mill:** a watermill straddles a river bank with a water wheel on the water side; a
  windmill stands alone on open ground.
- **The market:** stalls and crates round the plaza's edge, leaving the middle and the well
  clear.
- **The manor's garden:** a hedge round it, bushes, a bench.
- **Lumber camp:** a log pile and a chopping block at the forest's edge.
- **A short dirt path** from each entrance to its road.
- **Wells** at the plaza and district centres; **lamp posts** along main roads; a **notice
  board** on the plaza.
- **Trees** kept in the forest and cleared from plots and roads.
- *Done when:* nothing outdoors blocks an entrance, a road, a field row or a dock.

### Step 8 — The whole-town check and tests
`EcsSettlementCheck`, pure like `EcsBuildingCheck`:
- Every building's entrance is reachable from the plaza **using module 10's pathfinding**.
- No building or road is on water, except bridges.
- Every road is connected, and the role counts are met.
- The same seed gives the same commands.
- *Test:* 200 seeds × 3 town sizes, all checks passing.

### Step 9 — Viewer and measurements
- **Viewer** (`generator.tscn`): seed, size and town def on the left, plus a toggle per stage
  (terrain, roads, plots, zones, buildings) to see each layer.
- **Measure** generation time and the first tile sync for a hamlet (~10 buildings), a village
  (~40) and a town (~120).

---

## Content to add

Module 10's placeholder art comes from `art/placeholder/make_placeholders.py`. New pieces get
placeholder tiles the same way, in one new sheet, until real art replaces them; a new piece is a
blueprint and a tile. **Exists** means module 10 already ships it.

### Building types (`EcsBuildingTypeDef`)

| Type | Rooms (largest first) | Notes |
|---|---|---|
| House | *exists* | |
| Workshop | *exists* | |
| Farmhouse | kitchen, bedroom, store | wood, poor floors |
| Manor | hall, bedroom ×2–4, kitchen, store, study | stone, rich |
| Tavern / inn | common room, kitchen, store, guest rooms | the common room is large |
| Blacksmith | forge room, store | stone walls; the forge room has a wide entrance |
| Carpenter | workshop, lumber store | |
| Bakery | bakehouse, store | |
| Storehouse / granary | store ×1–3 | no beds, no kitchen |
| Barn / stable | stalls, hay store | wide, few inner walls |
| Mill | mill room, grain store | watermill or windmill: one type, the outdoor rule differs |
| Chapel | nave | one large room |
| Fishing hut | one room | small |
| Gathering hut | one room | small |
| Hunting hut | one room | small |
| Miner's hut | one room, store | small, stone walls |

### Room types (`EcsRoomTypeDef`)

**Exist:** bedroom, kitchen, workshop, dining, store. **New**, each typed by its key piece:

| Room | Key piece | Others |
|---|---|---|
| Hall | long table | chairs, banner |
| Study | desk | bookshelf |
| Common room | bar counter | tables, chairs, barrels |
| Forge room | forge | anvil, quench barrel, tool rack |
| Lumber store | lumber pile | |
| Bakehouse | oven | flour sacks, kneading table |
| Stalls | trough | hay |
| Mill room | millstone | grain sacks |
| Nave | altar | pews |
| Fishery | net rack | fish drying rack, barrel |
| Gatherer's room | herb drying rack | baskets |
| Hunter's room | skinning table | hide rack, trophy (a wall attachment) |
| Miner's room | pick rack | ore cart, lantern (an attachment) |

### Furniture and attachments (indoors)

**Exist:** anvil, barrel, bed, double bed, chair, chest, hearth, long table, shelf, stove, table,
workbench, sawmill, and the attachments banner, book, candle, mug, plate, wall lamp.

**New placeholders:**
- **Forge and smithy:** forge, quench barrel, tool rack, grindstone.
- **Carpentry:** sawhorse, lumber pile.
- **Baking and the mill:** oven, kneading table, flour sack, grain sack, millstone.
- **Tavern:** bar counter, tankard (an attachment).
- **Manor:** desk, bookshelf.
- **Chapel:** pew, altar.
- **Stable:** trough, hay pile.
- **Huts:** net rack, fish drying rack, herb drying rack, basket, skinning table, hide rack,
  trophy (an attachment).
- **General:** crate, sack.

### Outdoor objects

**Exist:** well, tree, bush, crop. **New placeholders:**
- **Farm:** wheat, vegetable (crop variants), scarecrow, haystack.
- **Fences:** a fence piece and a hedge. These are objects, not walls, because module 10's walls
  must stand inside a building's footprint. A gate in a fence is a later question.
- **Water's edge:** boat, mooring post, water wheel (the watermill's outdoor half).
- **Plaza:** market stall (2×1), notice board, bench, lamp post.
- **Forest:** log pile, chopping block, stump.
- **Mining:** mine entrance (2×2, set into the rock), ore cart, stone pile.

### Resource nodes

Things in the world that something can be gathered from. For now each is a placeholder object
that blocks walking. Gathering, regrowth and running out come later, with villagers and
`EcsProficiencyComponent`. Module 9's bushes already work this way for animals: harvested, not
spawners.

| Node | Where | Kinds | Exists? |
|---|---|---|---|
| Tree | Forest, thinning at its edge; a few lone ones on grass | oak, pine, birch; a fruit tree in gardens and orchards | tree exists; kinds new |
| Bush | Forest edge, meadows | berry bush, herb bush | bush exists; kinds new |
| Rock | Rocky ground, a few on grass | boulder, stone outcrop (2×2) | new |
| Ore vein | Inside rocky ground, rarer the richer it is | iron, copper, coal, gold (rare) | new |
| Clay pit | Riverbank or lakeshore | clay | new |
| Reeds | Shallow water's edge | reeds | new |
| Mushroom patch | Deep forest | mushrooms | new |

How a node is placed is data too, on an **`EcsNodeSpawnDef`**:
- which terrain or zone it grows in;
- how dense it is, with an optional cluster size, so ore forms veins and trees form groves;
- how far it keeps from roads and plots.

Step 1 scatters the nodes; steps 3–5 clear them from roads and plots; the forest's edge, the
rocky ground's edge and the shore are what the huts' site rules look for.

### Floors and terrain

**Exist:** grass, dirt, sand, water; wood, stone, road, rug. **New:**
- **Dirt path:** a floor cheaper than grass and dearer than road, for door-to-road paths and
  field rows.
- **Tilled soil:** a floor for farm plots. Crops stand on it, which needs a rule change: today
  module 10 refuses a plant on a floor (`plant_on_floor`). Either soil is let through, or tilled
  soil becomes a terrain instead.
- **Plaza stone:** plain `stone` is enough unless real art wants its own.
- **Forest floor:** an optional darker grass terrain under the forest.
- **Rock ground:** a terrain for hills and outcrops, walkable but dear, where stone and ore
  nodes grow.

---

## Not in this plan (later)

- **A living town:** villagers given a home and a job by role (`EcsProficiencyComponent`, see
  `TODO.md`), walking roads to work.
- **The town growing** over time: new plots claimed, buildings upgraded.
- Town walls and gates, districts by trade, an economy.

---

## Open questions — decide before step 1

1. **Module name:** "12. Settlement Generator" is a working title.
2. **Town sizes:** are hamlet, village and town (~10 / 40 / 120 buildings) the right targets?
   That decides the map size, about 150×100 to 400×300 cells.
3. **Layout style:** organic medieval (roads follow terrain, lanes branch off) as planned, or a
   planned grid?
4. **Terrain:** generated by module 12 as planned, or painted by hand in module 10 with the town
   generated onto it?
5. **New building types and furniture:** add them to module 10's catalog (a module 10 change, so
   your approval), or keep a module 12 catalog that lists module 10's defs plus its own?
6. **After generating:** should the town open in module 10's builder for hand edits? A town save
   is already commands, so this is close to free.
7. **Crops on tilled soil:** let crops stand on a soil floor (a change to module 10's
   `plant_on_floor` rule), or make tilled soil a terrain?
8. **Fences:** objects for now, as planned, or a real fence structure with gates?

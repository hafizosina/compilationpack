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

### Step 5 — What the town is: character, tier, resources, building list ✅ (done 2026-11-10, `HANDOFF.md` §6)

**Goal.** Before any building is placed, work out what the town *is*, and from that which
buildings it must or may have:
1. its **character**, what it lives on (farming, mining, fishing…);
2. its **tier**, how big it is;
3. the **resources** within reach;
4. so its **building list**.

For example, a farming village with iron nearby gets a small mine and a toolsmith who smelts. A
town by a river or the sea gets a small fishing operation.

**Decided (2026-11-10):**
- tiers are Hamlet, Village, Town, **City, Great City**;
- **ore deposits on L2**: today veins are sprinkled on L1 by zone density, so every rocky area has
  iron and "iron nearby" means nothing. The region plan gains a few seeded deposits per ore (and
  clay) on rock, and L1 places a vein mainly inside its deposit, so a child level still follows its
  parent. This is a change to step 1;
- the character is **always derived** from the survey, with no override.

Built as data: `EcsSettlementCharacterDef` and `EcsSettlementRoleDef` in one catalog
(`defs/economy.tres`), and two pure files, `EcsResourceSurvey` and `EcsTownEconomy`.
`EcsSettlementSite` gains `survey` and `economy`; the viewer shows them. **The tier is not its own
def:** `hamlet`, `village` and `town` already are the tiers (area, plaza, plots), so their
`EcsSettlementDef` gained an Economy group (tier, catchment, base roles, trade scale). The first
role set is 48 roles, not all of 5.0's list; the rest are added as they are needed.

- *Done when:* every seed's town has a character its survey supports, its core roles, side
  operations only for resources within reach, and a building list that feeds its population.

#### 5.0 Every building a medieval settlement might have
Lowest tier: H hamlet, V village, T town, C city, G great city. "Needs" = survey fact.

**Homes:** peasant hut (H), cottage / house (H), longhouse (H), townhouse (T), merchant's house (T),
manor house (V), guildhall-house (T), tenement (C), noble's palace (C).

**Food & farming:** farmhouse + field (H, arable), barn (H), granary (V), animal pen / fold (H,
pasture), stable (V), dovecote (V), beehives / apiary (H), orchard (H), vineyard + winepress (V,
warm slopes), watermill (V, river), windmill (V, open ground), bakery (V), brewery / alehouse (V),
malthouse (T), butcher / shambles (T), smokehouse (V, fish or game), dairy (V, pasture),
fishmonger (T).

**Water & fishing:** well (H), fishing hut (H, shore), dock / jetty (H, shore), net & boat shed (V,
shore), fish weir (V, river), harbour (T, sea), boatwright / shipyard (T, sea or lake), ferry
house (V, wide river), bathhouse (T), cistern / fountain (C).

**Wood:** woodcutter's hut (H, forest), lumber camp (V, forest), sawmill (T, forest + river),
carpenter (V), cooper (T), wheelwright / cartwright (V), charcoal burner's clearing (V, forest),
bowyer / fletcher (T).

**Stone, clay & earth:** quarry (V, rock), stonemason (V), potter + kiln (V, clay), brickworks (T,
clay), lime kiln (T, rock), salt works (T, sea or salt spring).

**Metal:** mine entrance + miner's hut (V, ore deposit), smelter / bloomery (V, ore + charcoal),
blacksmith (V), toolsmith (V), farrier (V, horses), armourer / weaponsmith (T), goldsmith /
jeweller (C, gold), bellfounder (C), mint (G).

**Cloth & leather:** weaver (V, wool or flax), dyer (T, river), fuller / fulling mill (T, river),
tailor (T), tannery (V, livestock; downwind, by water), cobbler / shoemaker (V), saddler (T),
rope maker (T, hemp or near docks), chandler (candles, T).

**Trade & travel:** market square (V), market stalls (V), market hall (T), inn (V), tavern (V),
warehouse (T), merchant's counting house (T), customs / toll house (T, main road or river),
waystation / coaching inn (V, main road), bridge-keeper's house (V, bridge), caravan yard (C).

**Faith:** wayside shrine (H), chapel (V), parish church + graveyard (T), monastery / abbey (T,
own grounds), cathedral (C), almshouse (T), hospital / infirmary (T).

**Rule & law:** headman's house (H), manor (V), town hall / moot hall (T), guildhall (T), courthouse
(C), gaol / stocks (V), tax house (T), keep (T), castle (C), palace (G).

**Defence:** palisade (V), watchtower (V), town wall + gatehouse (T), barracks (C), armoury (C),
garrison fort (border region, later).

**Learning & craft:** scribe (T), apothecary / herbalist (V, herbs), physician (T), school (C),
university (G), library (G), printer / bookbinder (G).

**Outdoor works (no walls):** fields, pastures, orchard rows, log piles, chopping block, stone
pile, clay pit, quarry pit, drying racks (fish or hides), compost / midden, cemetery.

#### 5.1 Character — what the town lives on
One **primary** character, always derived from the survey, plus **side operations** for
every other resource that is strong enough.

| Character | Lives on | Needs (survey) | Core buildings |
|---|---|---|---|
| Farming | grain | open grass; river or lake helps | farmhouses + fields, mill (water or wind), granary, barn |
| Herding | livestock, wool | open grass, little forest | herder huts + pens, barns, tannery, weaver |
| Fishing | fish | coast or a large lake, shallow water | fishing huts + docks, smokehouse, net maker |
| Timber | wood | lots of forest | lumber camp, sawmill (on a river), carpenter, charcoal burner |
| Mining | ore | an ore deposit in rock | mine entrance, miners' huts, smelter, smithy, charcoal |
| Quarrying | stone | rock, a stone outcrop | quarry, stonemason, cart shed |
| Pottery | clay | clay pits, river or shore | clay pit, potter, kiln / brickworks |
| Trading | passing trade | main roads meeting (3–4 exits), a river mouth or a coast | market, inn, warehouses, merchant houses, stables |
| Port (town+) | sea trade | coast + trading | harbour, docks, warehouses, boatwright |

Later, needing more than one region (L3): Monastery / pilgrim, Garrison / border fort.

**Side operation** = a small operation for a resource the town doesn't live on. A resource above a lower threshold that isn't the
primary character adds a *small* set, sized to the town's own needs:
- iron → a small mine + a toolsmith who smelts;
- fish → 1–2 fishing huts + a dock;
- forest → a woodcutter hut;
- clay → a potter.

#### 5.2 Tier — how big it is
| Tier | Buildings | Area (L1 cells) | What it adds |
|---|---|---|---|
| Hamlet | ~5–15 | 160×120 | houses, a well; its core trade only, tiny |
| Village | ~20–50 | 256×192 | + chapel, tavern, smithy, mill |
| Town | ~60–150 | 384×288 | + market, inn, guild shops, granary, more of everything |
| City | ~200–500 | ~640×480 | + districts, walls, church, keep, several markets |
| Great City | 500+ | ~1024×768 | + castle, cathedral, palace quarter |

City and above come later (area, districts, walls). The region's L1 is 2048×1536, so they fit.

#### 5.3 Resource survey — what is within reach
A pure `EcsResourceSurvey` over the site's **catchment**: L2 cells within walking cost N of the
site. It reuses the Dijkstra that `EcsRoadPlanner` already runs (`_dijkstra`), and N grows with
the tier. It returns 0–1 scores and facts:
- **Land:** arable (grass), pasture (grass far from forest), forest, rock.
- **Water:** river (yes/no, and distance), lake, sea, shallow-water cells (fish).
- **Deposits:** per ore (iron, coal, copper, gold) and clay, in L2 deposits within reach (new,
  see Context).
- **Trade:** main-road exits, whether the river reaches the sea, coast length.

#### 5.4 From all that to a building list
Data, not code: each building is an **`EcsSettlementRoleDef`**:
- its module 10 building type;
- the lowest tier it can appear at;
- **requires**: survey facts, e.g. watermill needs a river, dock needs sea or lake;
- **count**: fixed, or per population, by tier;
- **site rules**: near the centre, near water, forest's edge, on a main road, outskirts; used
  later by placement.

Each character def lists its **core** roles (must, scaled by tier) and **side** roles (small set).
Each tier def lists its **base** roles (houses, well, chapel…) and a population range.

`EcsTownEconomy.plan(survey, tier, def) -> {character, sides, roles: [{role, count}]}`, pure and
seeded:
1. Score every character from the survey; the best is primary.
2. Every other resource above its side threshold → that side operation.
3. Roles = tier base + primary core × tier scale + sides, each filtered by its `requires`.
4. **Food rule:** a town must feed its population. If neither farming nor fishing covers it, add
   farms or fishing huts on the outskirts until it does. Trade towns can make up part of the gap
   with a market.

Example: a farming village by a river with an iron deposit 600 m off:
- base: 12 houses, well, chapel, tavern;
- core: 6 farmhouses + fields, watermill, granary, barn;
- side, from the iron: small mine, toolsmith-smelter.

The fish in the river aren't strong enough for a side operation, so there are no fishing huts.

#### 5.5 What follows (later steps, not this one)
- **Step 5b, role-led plots:** each building places its own plot by its site rules (below).
- **Step 6:** module 10 building types for the new roles (most are 1–2 room huts).

### Step 5b — Plots placed by role ✅ (done 2026-11-10, `HANDOFF.md` §7)

**Goal.** Step 4 places as many plots as `plots` says, sized by distance from the plaza, and none
knows what it is for. Step 5 now gives the town a building list. 5b joins them: **each building on
the list places its own plot**, at its own size, where its site rules say. A watermill lands on the
river bank, a quarry by rock, the manor beside the plaza, farmhouses on the outskirts and houses
round the centre. Lanes and yards then run exactly as step 4 built them.

#### 5b.1 What it builds on
- **Step 5:** `site.economy.roles` [{role, count}], and the survey.
- **Step 4:** `EcsPlotPlanner`: footprints that fit (`_fits`), facing the nearest road (`_front`),
  lanes routed from doors, yards grown to meet them. Only *where spots come from* and *how one is
  chosen* change.
- **The area's refined ground** (`kinds`), as now.

#### 5b.2 Data — `EcsSettlementRoleDef` gains
- `size_min`, `size_max` (Vector2i): its footprint's width and height range, in L1 cells. A hut
  5×4–6×5, a house 6×5–8×7, a farmhouse 7×6–9×8, a manor 12×10–16×12, a church 10×8–14×10.
- `priority` (int): placing order, highest first. Unique and large buildings go before many small
  ones, so the manor gets the plaza's side before houses fill it.
- `sites` (Dictionary[StringName, float]): site rule → weight. Its score at a spot is the
  weighted sum.
- `must` (Array[StringName]): rules that must score at least 0.5, or the spot is refused. A
  watermill must be `river`, a fishing hut `water`, a quarry `rock`.
- `yard_depth` (int, 0 = the settlement's): a farmhouse's yard is its field, so it grows further.

`EcsSettlementDef` loses `plots`, `plot_size_centre` and `plot_size_edge`, because the role list
and role sizes replace them. `plot_gap`, `yard_depth` and `lane_reach` stay.

#### 5b.3 Site rules (pure, scored 0–1 at a footprint)
Worked once per town as distance fields over the area's L1 cells (BFS from each kind), then read
at the footprint's door side:

| Rule | Scores 1 when | Used by |
|---|---|---|
| `plaza` | its door faces the plaza | manor, church, chapel, tavern, inn, market, town hall |
| `centre` | near the plaza, falling to 0 at the area's edge | houses, bakery, merchant houses |
| `main_road` | its door within 3 cells of a main road | inn, waystation, blacksmith, toll house, warehouse |
| `outskirts` | near the area's edge | farmhouse, herder, barn, tannery, charcoal |
| `water` | within 3 cells of lake, sea or river water | fishing hut, smokehouse, net shed, boatwright, harbour |
| `river` | within 2 cells of the river | watermill, sawmill, dyer, tannery |
| `forest` | within 4 cells of forest | woodcutter, lumber camp, carpenter, charcoal |
| `rock` | within 4 cells of rock | quarry, stonemason, miner's hut, mine |
| `open` | on open grass, no forest or rock within 6 | windmill, granary, farmhouse |
| `apart` | far from other plots | tannery, smelter, lime kiln (smell and smoke) |

#### 5b.4 Placing
1. **Expand the role list** into one entry per building, sorted by `priority`, then by role key
   for ties.
2. **For each**, draw candidate spots the same three ways as now: round the plaza, beside main
   roads, and anywhere in the area. Each gets a size from the role's range. Footprints that don't
   fit, or that fail a `must`, are dropped.
3. **Score** each surviving spot by the role's `sites`, plus a little seeded noise so towns
   differ, and keep the best of up to 40 tries.
4. **None fits inside:** a work goes out to its resource (5b.7). Anything else is **reported
   short** (`site.economy.short`: [{role, count}]), not forced.
5. **Each plot records its role:** `plots[k].role`.

Then lanes (nearest road first) and yards (per-role depth) run as in step 4.

#### 5b.5 Check, viewer and tests
- **`EcsPlotCheck`** also reports a plot with no role, and a plot whose role's `must` fails.
- **Viewer:** footprints tinted by role group (homes, food, craft, faith and rule, trade, water,
  resource works). The cell panel names the plot's role. The info panel lists the buildings
  reported short.
- **Tests:**
  - every town's plots match its role list, less what is reported short;
  - every watermill is within 2 cells of the river; every fishing hut within 3 of water;
  - the manor faces the plaza;
  - houses are nearer the plaza than farmhouses, on average;
  - the same seed gives the same plots;
  - measured cost per town size.

#### 5b.6 Not in 5b
- Building interiors and module 10 building types for the new roles (step 6).
- Fields, pens, docks and log piles as outdoor objects (step 7). The yard is their place for now.

#### 5b.7 Works outside the town's area
**Decided (2026-11-10): the town's area is a guideline, not a border.** The survey reaches further
than the area: a hamlet's area is 160×120 m, but its catchment walks about 320 m. So a work whose
resource lies outside the area goes **out to its resource**, and the town grows to include it.
This replaces the "reported short" outcome for anything its catchment has.

- **Which roles:** those with a resource `must` (`river`, `water`, `forest`, `rock`, or a deposit
  key such as `iron` or `clay`): mine, miner's hut, quarry, lumber camp, woodcutter, clay pit,
  fishing hut, watermill, sawmill.
- **Inside first:** such a role first tries the area, as in 5b.4. Only when no spot there passes
  its `must` does it go out.
- **Out to the resource:**
  1. The candidate region cells are the catchment's cells that hold its resource: a deposit cell
     of its key, rock, a forest edge, a river or shore bank. They are ranked by route cost from the
     site (`site.costs`), so the nearest goes first.
  2. An **outlying window** is refined round the best cell: 32×32 L1 cells (`refine_terrain`, the
     chunks' ground). The plot is placed in it by the same `_fits`, `_front` and `must` as inside.
     Works of the same resource share a window, so a mine and its miners' huts stand together.
  3. If the window has no fit, the next cell is tried, up to 6.
- **A track joins it to the town:**
  - routed on L2 from the window to the nearest main road cell, or the site, by A* over
    `road_costs`, with main road cells cheap so it joins one;
  - drawn on L1 like a main road but 1 cell wide and of kind `track` (road floor). A track
    may bridge, like a main road;
  - its cells join `road_cells`, so `EcsRoadCheck`'s network check covers it.
- **The record:** `site.outlying` [{rect: L1 window, kinds}]. A plot outside `site.area` lies in
  one of them. `site.area` stays the core: plaza, houses and the lanes' grid.
- **Lanes and yards** run in each window as in the area, from the window's plots to the track.
- **The core grows too.** If a building that isn't a work fits nowhere in the area, say houses
  once it is full, the area grows by 16 L1 cells a side, as far as the region allows. It is
  re-refined, and placing carries on. So the area's size in the def is where a town starts, not
  where it must stop.
- **Short:** a role is reported short only when its catchment has none of its resource, 6 windows
  found no fit, or the area can't grow further.
- **Viewer:** outlying windows outlined like the area; tracks drawn on L2 thinner than lanes.
- **Tests:** a mine's plot lies on or beside its deposit; every outlying plot's track joins the
  network; nothing is short when the catchment has the resource.

- *Done when:* every building on the list has a plot where its rules say, inside the area or out
  at its resource with a track to the town, or is reported short for lack of the resource; lanes,
  tracks and yards pass step 3 and 4's checks.

### Step 6 — Buildings ✅ (done 2026-11-10, `HANDOFF.md` §8)

**Goal.** Every plot from step 5b gets its building: module 10's `EcsBuildingGenerator`, run on
the plot's footprint, facing its door, at a wealth, with rooms fit for its role. The town is then
real walls, doors, floors and furniture, drawn chunk by chunk and walkable by module 10's nav.

**Decided (2026-11-10):**
- **rooms by role**: few building types, and each role lists its rooms (6.3);
- **buildings are split across chunks**, not kept inside one (6.6);
- **module 10's generator takes the door cell** as its preferred entrance (6.5);
- **a building with more than one room isn't just a rectangle**: L, T and U shapes and wings
  (6.5b).

#### 6.1 What it builds on
- **Step 5b:** `site.plots` [{role, footprint, front, door, yard}]. The footprint is the
  building's size, and the front is its `facing`.
- **Module 10:** `EcsBuildingGenerator.generate(type, size, wealth, facing, seed, catalog,
  entities, at)` gives build commands, the same the player's tools send. `EcsBuildingCheck`
  checks a built building: no sealed room, every room and door reachable from the entrance, no
  furniture on a door's inside cell. It already handles any size and 1–4 rooms; `generator_test`
  runs 1,000 seeds per type.
- **The chunks:** the site's commands are handed to each chunk through `overlay`.

#### 6.2 Which roles get walls
- **Walled (step 6):** every role but those below. That is 41 of 48.
- **Outdoor (step 7):** market, mine, quarry, lumber camp, clay pit, harbour and shrine. Their
  plots stay, with no building yet.

#### 6.3 Building types — few types, rooms by role
Decided: **a building type says what it is built of and how it splits; the role says what its
rooms are for.** `EcsSettlementRoleDef` gains:
- `rooms` (Array[StringName], optional): its room roles, largest first. These replace the type's
  `roles` for that building.

This keeps the types few and keeps each trade's knowledge on its role, not in a shared type. A
blacksmith and a cobbler share `workshop`, and differ by `rooms`.

| Type (module 10) | New? | Rooms by wealth | Built of (poor → rich) | Roles that use it, and their `rooms` |
|---|---|---|---|---|
| `house` | exists | 1/3/4 | wood → stone | house, headman, merchant house |
| `workshop` | exists | 1/2/3 | wood → stone | blacksmith, toolsmith, smelter [forge, store]; carpenter [carpentry, lumber store]; bakery [bakehouse, store]; the other crafts [workshop, store] |
| `manor` | new | 4/5/6 | stone | manor [hall, bedroom, kitchen, study, bedroom, store] |
| `tavern` | new | 3/4/5 | wood → stone | tavern [common room, kitchen, store]; inn and waystation add bedrooms |
| `chapel` | new | 1/1/2 | stone | chapel [nave]; church [nave, vestry] |
| `hall` | new | 2/3/3 | stone | town hall [hall, study, store] |
| `farmhouse` | new | 2/3/3 | wood | farmhouse [kitchen, bedroom, store] |
| `barn` | new | 1/2/2 | wood, few inner walls | barn [hay store]; stable [stalls, hay store] |
| `storehouse` | new | 1/2/3 | wood → stone | granary, warehouse [store …] |
| `mill` | new | 2/2/2 | wood → stone | watermill, windmill, sawmill [mill room, grain store] |
| `hut` | new | 1/1/2 | wood | woodcutter [woodshed]; herder [hut room]; fishing hut, net maker, smokehouse [fishery]; miner's hut [miner's room]; charcoal [hut room] |

Role `building` keys change to these, and the bakery, inn, storehouse, herder hut and fishing hut
keys fold into the table above.

#### 6.4 Wealth
`EcsSettlementRoleDef` gains `wealth` (−1 = from its place):
- the manor, church and town hall are rich;
- crafts and trades are middling;
- huts, barns and farmhouses are poor;
- **houses take it from where they stand:** rich by the plaza, middling in the inner ring, poor at
  the edge (the `centre` rule at ⅔ and ⅓).

#### 6.5 Generating
- **When:** after plots, lanes and yards, in `EcsSitePicker._centre`, before
  `EcsRoadPlanner.lay`.
- **For each walled plot:**
  - `generate(type, footprint.size, wealth, front, hash([seed, plot index]), …, at = footprint.position)`;
  - the role's `rooms` are passed by a type copy whose `roles` are the role's;
  - the commands go into `site.commands`;
  - the plan's entrance is kept on the plot, as `entrance`.
- **The entrance is the plot's door cell,** so the lane meets it. This is a small module 10
  change: `generate` and `plan` take an optional preferred entrance cell. `_entrance` uses it when
  it is valid (on the facing side, not a corner, a room inside), and otherwise picks one as now.
  The splits are drawn first, so the door's inside cell can be a split line. In that case the
  nearest valid cell is used and the lane is extended to it.
- **Footprint and yard cells are already node-free.**

#### 6.5b Shaped buildings (a module 10 generator change)
Decided: a building with more than one room takes a **natural shape**, not the plot's rectangle.
One-room buildings (huts, chapels, barns) stay rectangular.
- **Module 10 already allows it.** Room detection calls a flood that reaches the footprint's
  edge "open, not a room", and roofs cover only rooms and the walls round them. So walls traced
  along an L inside the footprint leave the cut corner as open ground, with no room and no roof,
  with no change to rooms or roofs. Only the generator changes.
- **`EcsBuildingTypeDef` gains `shapes`**: shape → weight, by wealth (plain, L, T, U, wing), plus
  `notch`, the smallest and largest cut as a share of each side.
  - A house is mostly plain or L.
  - A manor takes T, U or wings.
  - A tavern and a farmhouse take L or a wing.
- **The generator, before splitting,** cuts the footprint into its shape:
  - **L:** a corner rectangle cut away.
  - **T:** both corners of one side cut.
  - **U:** a notch from the middle of one side.
  - **Wing:** a narrower rectangle added to a side, so the main block is cut back to make room
    for it.
  - Every part left keeps at least `min_room` + walls. The facing side must keep a wall stretch
    with a room inside it for the entrance, or the shape is redrawn.
- **Then as now, per part:** BSP rooms inside each part; walls on the shape's outline and the
  splits; a door between parts as an inner door, along the same spanning tree. The entrance is on
  the facing side, at the plot's door cell when that is on the outline, else the nearest outline
  cell facing that way, with the lane extended to it (6.5).
- **Furniture** is placed only inside rooms, as now, so never in a cut corner.
- **Module 12:** the plot's footprint is still the building's rect. Its cut corners are open
  ground owned by the building. The viewer draws the building's walls and roof, and the yard runs
  round the rect as now. The plot record gains `building_cells` (the shape's cells), for the
  viewer and for step 7's gardens.
- **Tests:** module 10's `generator_test` runs every shape over its 1,000 seeds per type. The
  check is unchanged: no sealed room, every room and door reachable. Also checked: a cut corner is
  never a room and never roofed.

#### 6.6 Buildings and chunks — split, clipped per chunk
Decided: **a building may cross chunk lines.** Each chunk is its own module 10 world, so each gets
its part of the building, clipped by `EcsTerrainChunks.overlay` with no change to module 10's build
system:
- **CREATE_BUILDING** is clipped to the chunk's own cells plus its border ring (`own.grow(1)`). The
  build system fills only that, so rooms flood within the clipped footprint.
- **One module 10 change is needed for it:** room detection calls a flood that reaches the
  footprint's edge open, so a room cut by the chunk line would lose its room and roof. The
  clipped CREATE_BUILDING carries the sides where the building continues past the grid
  (`EcsBuildingComponent.cut`). A step across a cut side counts as a wall for room detection,
  not a leak.
- **Walls, doors and floors** go to every chunk whose cells or border hold them, as floors already
  do. A wall or door on the border is in both chunks, so the cut lines up.
- **Furniture and attachments** go only to the chunk holding their origin, as nodes and the well
  already do. Pieces are at most 2 cells, so a piece whose origin is in the chunk lies within its
  border ring and is never refused.
- **Roofs:** the cut edge of a clipped footprint would draw a roof edge. The chunk's trim, which
  already erases its ring of ground tiles, also erases its ring of roof tiles, so the roof reads
  as one across the line.
- **Each chunk has its own copy of the building**, a separate entity, as a chunk is a separate
  world. Its rooms are typed by the furniture that chunk holds. That is display only. The whole
  building is checked in one world in the tests (6.8).

#### 6.7 Content (module 10's catalogs)
- **9 building types** (table above), in `defs/building_type/` and the catalog's
  `building_types`.
- **Room types:** hall, study, common room, forge, carpentry, lumber store, bakehouse, nave,
  vestry, stalls, hay store, mill room, grain store, woodshed, fishery, miner's room, hut room.
  Each is typed by its key piece (see Content to add).
- **Furniture:** about 23 placeholder blueprints: forge, quench barrel, tool rack, oven, kneading
  table, flour sack, grain sack, millstone, bar counter, desk, bookshelf, pew, altar, trough, hay
  pile, net rack, fish rack, pick rack, ore cart, lumber pile, sawhorse, crate, sack. Their art
  goes on a new `furniture.png` sheet from `make_placeholders.py`.

#### 6.8 Check, viewer and tests
- **Check:** every walled plot has a building, generated without refusal; every building passes
  `EcsBuildingCheck`; every entrance faces its plot's lane.
- **Viewer:** L1 chunks draw the buildings through module 10. The cell panel names a cell's
  building and room.
- **Tests:**
  - module 10's `generator_test` takes the 9 new types, 1,000 seeds each;
  - module 12's new `building_test` covers every town size over seeds: the town's area and
    outlying windows built through module 10's pipeline, every command accepted, every building
    checked, every entrance on a lane;
  - a building crossing chunk lines: every chunk's clipped commands are accepted, and its walls,
    floors and roof cells are the whole building's on each chunk's cells and border;
  - measured cost per town.

#### 6.9 Not in step 6
- Outdoor works (step 7): market stalls, mine entrance, quarry pit, harbour, shrine.
- Fences and gardens on yards (step 7). **Farm fields were pulled forward** (2026-11-10,
  `HANDOFF.md` §8): dirt with crop rows beside each farmhouse.

- *Done when:* every walled plot has a building that passes `EcsBuildingCheck`, with its entrance
  on its lane, and a building crossing chunks draws as one.

### Step 7 — Outdoors (7a ✅ done 2026-11-10, `HANDOFF.md` §10; 7b to do)

**Goal.** Everything outside the walls:
- the seven **outdoor works** that have plots but no building yet;
- the **annexes** beside buildings: fields (done in step 6), pens and docks;
- **dressing** for yards and the plaza.

All of it is module 10 objects, floors and terrain, sent as build commands and drawn by the chunks
as everything else is.

**Decided (2026-11-10):**
- **a small rule per outdoor work**, in code, not a data list of pieces (7.2);
- **a dirt path floor** for lanes and tracks (7.4);
- **house yards fenced and gardened by wealth** (7.4);
- **two halves**:
  - **7a:** outdoor works, fences on fields, pens, docks, the water wheel;
  - **7b:** plaza dressing, the manor's garden, house yards, dirt paths.

#### 7.1 What it builds on
- **Plots (5b):** an outdoor work's footprint, front and door; every plot's yard.
- **Fields (6):** an annex on a free side of a farmhouse, one cell clear, blocking plots, lanes and
  yards (`_field_for`, `Use.FIELD`). Pens and docks reuse this machinery.
- **Module 10:** objects stand on terrain, and a plant never on a floor. A wood floor over water is
  walkable (the bridges). Objects at most 2 cells keep chunk clipping simple (6.6). Walls must be
  inside a building, so **fences and hedges are objects**, one a cell.

#### 7.2 Outdoor works — a small rule each (7a)
Decided: each outdoor work has its own small layout rule in `EcsOutdoorBuilder`, picked by the
role's key, as `layout` names. A role with no `building` and no rule is reported.
- The rules share helpers: a piece by the edge, round the ring leaving the front clear, at the
  centre, scattered.
- A piece never stands on the door's cell or the cell inside it, and the free cells stay one
  area, as module 10's furniture rule does.

| Role | Ground | Pieces |
|---|---|---|
| market | stone floor | stalls (2×1) round the ring, crates scattered, a notice board by the front |
| mine | rock ground | mine entrance (2×2) at the centre, ore cart, stone pile |
| quarry | rock ground, stone cleared | stone piles round the edge, a sawhorse, crates |
| lumber camp | dirt | log piles round the edge, a chopping block, stumps scattered |
| clay pit | dirt | clay pits (the node) at the centre, drying racks round it |
| harbour | — | a dock (7.4), boats, mooring posts, crates |
| shrine | stone floor | a shrine at the centre, candles |

#### 7.3 Annexes: fields, pens, docks (7a)
One rule, generalised from fields. A role names its **annex** (`field`, `pen` or `dock`) and its
size range. The annex is placed beside the building, off its front, a cell clear.
- **Field (done):** dirt, crop rows. **Adds** a fence round its edge with a gap facing the
  farmhouse, a scarecrow and a haystack.
- **Pen** (herder, barn, stable): grass, a fence round it with a gate gap facing the building,
  a trough and a hay pile inside.
- **Dock** (fishing hut, boatwright, harbour): a pier, not a fenced plot.
  - It runs from the plot's yard edge nearest water straight out over water, 2 wide, 3–6 cells,
    as a wood floor.
  - A boat is moored beside its end and a mooring post on it.
  - Its side and length are the first of the 4 sides where it reaches water within 3 cells of
    the yard. When none does, there is no dock and it is reported.
- **Watermill:** a water wheel object on the first river cell beside its wall.

#### 7.4 Dressing (7b)
- **The plaza:** benches and a notice board round its edge, keeping the well's ring clear and
  never on a road's mouth. Lamp posts every ~12 cells along main roads inside the area, on the
  verge.
- **The manor's garden:** a hedge round its yard with a gap at its lane, bushes and a bench inside.
- **House yards (decided, by wealth):** a chance of a fence round the yard (gate at the lane) and a
  garden bed in it. Richer houses are likelier to have them, and poor yards mostly stay open.
- **Paths (decided):** lanes are 1 cell of road floor today. A new **dirt path** floor (module 10),
  cheaper to walk than grass, for lanes and tracks. Main roads keep the road floor.

#### 7.5 Content (module 10)
New placeholders on an `outdoor.png` sheet:
- fence and hedge (1×1, turned for direction, a post where they meet);
- scarecrow, haystack, vegetable bed (2×1);
- market stall (2×1), notice board, bench, lamp post;
- log pile (lumber pile reused), chopping block, stump, stone pile;
- mine entrance (2×2), drying rack, boat (2×1), mooring post, water wheel, shrine.

Plus a dirt path floor sheet.

#### 7.6 Check and tests
- **The rule:** nothing outdoors blocks an entrance, a road, a field row's path or a dock. Every
  building's entrance is still walkable from the plaza through module 10's nav, gates included.
- **Tests (`outdoor_test`):**
  - every outdoor work laid with its pieces;
  - every field and pen fenced with a gate;
  - every dock on water and walkable;
  - the town's area through module 10, every command accepted;
  - every entrance reachable from the well by nav;
  - chunks draw fences and docks the same across lines.

- *Done when:* every outdoor work, annex and dressing is laid, nothing blocks an entrance, road,
  path or dock, and every building can still be walked to.

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

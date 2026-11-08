# Module 12 — Settlement Generator: plan (draft, 2026-11-08)

A whole town from a seed: terrain, a centre, roads, plots, and the right building on each plot —
farmhouses on the outskirts with fields, fishing huts on the shore, a manor near the centre.
Module 10 makes one building; module 12 decides **where every building goes and why**.

**Status: a draft for review. Nothing is built.** The open questions at the end come first.

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

### Step 1 — Terrain
Seeded noise (`FastNoiseLite`) over the map: **water** (a lake, a river or a coast — one per
town def), **sand** along the shore, **forest** zones (trees placed as plant objects) and open
grass for fields.
- *Done when:* the same seed gives the same map; the water is one body (or one river edge to
  edge); land is within the def's share; there's room for the town's plots.

### Step 2 — Site and centre
The town centre: a land cell away from the map's edge, near water but not on it, with flat open
ground around. It becomes a **plaza** (a stone floor) with the **well**.
- *Done when:* the plaza is all land, and the centre can reach the map edge by land.

### Step 3 — Roads
- **Main roads** from the centre to two to four exits at the map's edge, routed by A* over
  terrain cost (land cheap, water dear, so a crossing becomes a **bridge**, a road over water).
  This reuses module 10's walk costs.
- **Lanes** branch off the main roads at intervals, perpendicular, organic rather than a strict grid.
- Roads are module 10's `road` floor, 2 cells wide for main roads and 1 for lanes.
- *Done when:* every road cell connects to the centre, and roads never cut through each other's
  plots.

### Step 4 — Plots
Plots line the roads (frontage), each one **facing its road**. The facing becomes the building's
entrance side, which module 10's generator already takes. Plot size depends on the zone. Plots
never overlap a road, water or another plot.
- *Done when:* every plot touches a road on its facing side.

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

### Floors and terrain

**Exist:** grass, dirt, sand, water; wood, stone, road, rug. **New:**
- **Dirt path:** a floor cheaper than grass and dearer than road, for door-to-road paths and
  field rows.
- **Tilled soil:** a floor for farm plots. Crops stand on it, which needs a rule change: today
  module 10 refuses a plant on a floor (`plant_on_floor`). Either soil is let through, or tilled
  soil becomes a terrain instead.
- **Plaza stone:** plain `stone` is enough unless real art wants its own.
- **Forest floor:** an optional darker grass terrain under the forest.

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

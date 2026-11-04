# Module 10 — Town Generator: state of the build

Town building on module 9's ECS. **The focus is procedural generation**: a building generator
whose output is the same build commands a player's tools would send. Module 9's world,
scheduler and systems are **borrowed, never copied**; everything new lives in this folder, and
module 9 changes only through a hook the author approves first. The plan is the brief
(`MODULE10_BRIEF.md`, kept outside the repo); started from tag `ecs-baseline`.

**Not in this module, by decision:** live edit, the inspector, selection HUD. Its pipeline is
module 9's ECS core plus the town systems.

```bash
# Tools: 1-4 terrain and 5-8 floor brushes, 0 clears floor, [ ] brush size; B drags a building,
# W/E drag a wood/stone wall line, X a removal line, C closes the building under the mouse.
"$GODOT" --path .   # main.tscn is the main scene

# 44 checks; exit 0 only if all pass. Also prints tile sync and command costs.
"$GODOT" --headless --path . "res://10. Town Generator/tests/town_test.tscn"
```

`main.tscn` is the ECS scene (`main.gd`). **Every TileMapLayer is in the scene**, under
`World/TilemapGroup`, with its TileSet configured there; code fills them and never creates one.

---

## 1. Layout

| Path | Role |
|---|---|
| `singletons/` | `EcsTownGridSingleton` — the grid |
| `components/` | `EcsBuildingComponent` |
| `ecs/` | `EcsTownGrid` (cell maths, making a grid), `EcsDualGrid` (masks, layout, TileSet), `EcsBuildCommand` |
| `systems/` | `EcsBuildCommandSystem`, `EcsTileSyncSystem`, `EcsTownOverlaySystem` |
| `town_overlay.gd` | `EcsTownOverlay`, the view that draws footprints and drag previews |
| `defs/` | `EcsTileDef` → `EcsTerrainDef`, `EcsFloorDef`; `EcsWallDef`; `EcsTownCatalog`; `town_catalog.tres` and one `.tres` per type; `entity_catalog.tres` (module 9's `EcsEntityCatalog`) and `blueprints/` |
| `art/placeholder/` | Generated placeholder sheets, `make_placeholders.py`, layout in its README |
| `tests/` | `town_test.tscn` |

Pipeline (`main.gd`): `lifecycle > build > tile_sync > overlay`. Lifecycle is module 9's, with its
`EcsEntityManager` rooted at `World/Entities`; buildings declare no node, so it builds none.

---

## 2. Step 1 — grid and rendering (2026-11-04)

**The grid is a singleton of flat arrays.** `EcsTownGridSingleton` holds one `PackedInt32Array`
per layer, indexed `y * width + x`: `terrain`, `floor` (0 = none), `structure` (NONE / WALL /
DOOR), `wall_type`, `building_id`, `object_id`, `room_id` (-1 = none), `roof`; plus `wall_hp`,
the `commands` inbox and `dirty` (cell index → which layers changed). All of the brief's layers
exist now so later steps add behaviour, not storage. Cells are 32 px (`EcsTownGrid.CELL`).
Not `changed`: the singleton is a `Resource`, and a `changed` field collides with its signal —
the parse error hangs a headless run, since the script never reaches `quit()`.

**Only `EcsBuildCommandSystem` writes cells.** Anything that wants a cell changed appends an
`EcsBuildCommand{kind, cell, value}`; the system validates it, applies it, sets its `result`
(`ok`, `out_of_bounds`, `unknown_terrain`, `unknown_floor`) and marks the cell dirty. Setting a
cell to what it already holds is `ok` and marks nothing. Step 1's kinds are `SET_TERRAIN`,
`SET_FLOOR`, `CLEAR_FLOOR`; the debug brush sends them, and so will the generator.

**Catalog ids are authored**, in each def's `.tres`, never load order; 0 is none. Terrain:
grass 1, dirt 2, sand 3, water 4. Floor: wood 1, stone 2, road 3, rug 4. Walls: wood 1, stone 2.

**The layers are the scene's.** A terrain or floor def names its TileMapLayer (`layer`); a wall
def names a source in the wall layer's TileSet (`source_id`). The art, tile size, half-cell offset
and scale are all set on the layer in `main.tscn`, and **draw order is the layers' order among
their siblings** — the one place it is set. The tile sync finds the layers by name, clears them,
and fills them. A missing layer is an error, a terrain or floor layer not at (-16, -16) a warning.
The author's art is used wherever it exists; placeholders fill only the slots without any:

| Layer, in draw order | Draws | TileSet |
|---|---|---|
| `GroundLayer` | grass | author's `grassTileset.png`, 16 px, layer scale 2 |
| `DirtLayer`, `SandLayer`, `WaterLayer` | terrain | placeholders |
| `FloorLayer` | wood | author's WoodFloor TileSet, peering bits painted |
| `StoneLayer`, `RoadLayer`, `RugLayer` | floor | placeholders |
| `ObjectLayer` | walls (doors at step 3) | author's: source 1 WoodWall, 2 WoodenDoor; 3 `BaseWall` (stone) added |

**The dual grid.** Terrain and floor are drawn on a grid offset half a cell, so each render tile
sits on a cell corner and shows a quarter of each of its four cells; the 4-bit mask of which
quarters are filled picks the tile. **A type's layer also fills under every later type** (bit set
when the cell's type draws at or after the layer), so a higher type's rounded edge never shows a
hole. Terrain off the map repeats the edge cell; floor off the map is none. Full tiles have
variants, picked by a hash of the position so a redraw never flickers.

**Layouts are read from the TileSet.** `EcsDualGrid.corner_layout` / `side_layout` use the
author's terrain peering bits when painted (WoodFloor's corners, WoodWall's sides), else the
sheet's transparency — a quarter counts when over half of it is opaque, a wall side when the
middle of that edge is — so any arrangement and tile size works: the grass is 16 px, 8×3, with
diagonals at 3:2 and 4:2 and ten full variants. A sheet that reads incomplete falls back to
WoodFloor's or WoodWall's table, with a warning.

**Walls** are drawn on the cell grid from their type's source (16 shapes: ends, runs, corners,
T-junctions, a cross, a lone post). A change redraws the cell and its four neighbours. Placing
them is step 2 (§3).

**Redraws are local.** The first run draws everything; after that each dirty cell redraws only
the four render tiles at its corners, on the layer group that changed — terrain or floor, never
both. An idle tick redraws nothing.

**Not done in step 1, on purpose:** roofs. Nothing writes `roof` until step 4.

**Measured** (2026-11-04, `town_test`; machine busy, as in module 9 §14):

| grid | first draw | one cell changed: tile sync | command | idle tick |
|---|---|---|---|---|
| 64×64 | 67 ms | 35 µs | 3.2 µs | 3.8 µs |
| 128×128 | 240 ms | 36 µs | 3.8 µs | 3.4 µs |
| 256×256 | 938 ms | 39 µs | 4.8 µs | 3.2 µs |

A change costs the same at any size; the first draw is linear in cells × layers (eight layers,
one `set_cell` per filled render tile). If load time matters, skip layers a cell can't reach
(a grass-only map draws only the grass layer's full tiles) or draw the first frame in chunks.

**Tests** (on `main.tscn`'s own layers): the scene's layers filled in scene order; the author's
sheets used and placeholders only without one; every layout complete; WoodFloor's peering bits read
as its table; the grass's diagonals and variants; both wall sheets read 16 shapes; walls join,
removing one ends its neighbours and redraws five cells at most, the stone type uses its source,
unknown types and occupied cells are refused; validation (off the grid, unknown ids, the inbox emptied); one cell redraws 4 corners
per layer of its group only, a no-op redraws nothing; water's four corners and nothing else, with
grass and dirt filling under it; wood covers exactly its cells over the whole grid, including a
rug inside it and two cells touching at a corner (the diagonal tile); clearing erases. Seen in
`main.tscn`: blends, the rug inside planks, the diagonal, road over water.

---

## 3. Step 2 — buildings and walls (2026-11-04)

**A building is an entity** with `EcsBuildingComponent{footprint, rooms, children, closed, quality,
owner_id, builder_id}` (blueprint `building`), born through module 9's lifecycle at the footprint's
centre. It declares no node. Its walls are the wall cells inside its footprint; `building_id` names
it on every footprint cell.

**A footprint is reserved before its building exists.** The entity id only exists after the next
lifecycle stage, but the generator will send a building and its walls in one batch. So
`CREATE_BUILDING(rect)` checks the rectangle, writes a reservation token (−2, −3, …) into
`building_id` across it, asks lifecycle for the building and keeps the request in `grid.pending`;
the command's `building` carries the token. The next run, after lifecycle, swaps the token for
the born id on every footprint cell. The grid's "none" is `EcsTownGridSingleton.NO_ID = -1` —
not `EcsWorld.NO_ENTITY`, which is 0 and is a valid-looking cell value.

**Validation**, in the build system only: a footprint inside the grid that overlaps no other —
**touching is allowed** (row houses), overlapping is not, even in the same batch;
`PLACE_WALL(cell, type)` on a footprint cell (`outside_building` otherwise), optionally naming
the building it must belong to (`not_its_building`), on a cell with no object (`occupied`).
**A wall's building is the footprint it stands in**: footprints never overlap, so the cell says
whose it is. `CLOSE_BUILDING(id)` sets `closed`; it needs no room. Refusals are counted and the
last reason is shown in the status line.

**Walls join only their own building's walls.** Two touching buildings keep a wall each along
the shared edge — walls are never shared, every cell has one owner.

**Tools** (`main.gd`): B drags a footprint (preview red when it would overlap), W/E drag a
straight wall line along the axis moved more, X drags a removal line, C closes the building under
the mouse. `EcsTownOverlay` draws footprints — **dashed while open, solid with a light fill once closed** —
and the drag preview. `EcsTownOverlaySystem` hands it footprints only when buildings come or go
or `grid.building_revision` moves; the build system bumps that when it closes one, so a change
redraws without scanning every building each tick. The overlay sits at `z_index` 10, since the tile layers'
parent is a plain `Node` and they would otherwise draw over it.

**Measured** (`town_test`): a 20×20 building with its 80 perimeter walls costs ~0.5 ms of commands
and ~0.8 ms of tile sync, at any grid size. The idle tick went from ~3 to ~7.5 µs: lifecycle's
drain now runs every tick.

**Tests:** reserved at once and a same-batch wall is its; next tick an entity whose footprint
covers all its cells, at its centre; closing; touching allowed, overlapping and off-grid refused;
the overlay showing it closed; walls outside every footprint or named for another building refused; touching buildings' walls
on the shared edge don't join. The step-1 wall tests now build inside a building.


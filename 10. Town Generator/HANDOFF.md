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
# W/E drag a wood/stone wall line, X a removal line, C closes the building under the mouse,
# D/F click a wood/stone door into a straight wall, T opens or closes one; R shows/hides roofs,
# O the room colours.
"$GODOT" --path .   # main.tscn is the main scene

# 71 checks; exit 0 only if all pass. Also prints tile sync and command costs.
"$GODOT" --headless --path . "res://10. Town Generator/tests/town_test.tscn"
```

`main.tscn` is the ECS scene (`main.gd`). **Every TileMapLayer is in the scene**, under
`World/TilemapGroup`, with its TileSet configured there; code fills them and never creates one.

---

## 1. Layout

| Path | Role |
|---|---|
| `singletons/` | `EcsTownGridSingleton` — the grid |
| `components/` | `EcsBuildingComponent`, `EcsGridPositionComponent`, `EcsDoorComponent` |
| `ecs/` | `EcsTownGrid` (cell maths, making a grid), `EcsDualGrid` (masks, layout, TileSet), `EcsBuildCommand` |
| `systems/` | `EcsBuildCommandSystem`, `EcsRoomDetectionSystem`, `EcsRoofSystem`, `EcsTileSyncSystem`, `EcsTownOverlaySystem` |
| `ui/` | `build_panel.tscn` (`EcsBuildPanel`), the build HUD on the left |
| `town_overlay.gd` | `EcsTownOverlay`, the view that draws footprints and drag previews |
| `defs/` | `EcsTileDef` → `EcsTerrainDef`, `EcsFloorDef`; `EcsWallDef`; `EcsTownCatalog`; `town_catalog.tres` and one `.tres` per type; `entity_catalog.tres` (module 9's `EcsEntityCatalog`) and `blueprints/` |
| `art/placeholder/` | Generated placeholder sheets, `make_placeholders.py`, layout in its README |
| `tests/` | `town_test.tscn` |

Pipeline (`main.gd`): `lifecycle > build > rooms > roof > tile_sync > overlay`. Lifecycle is module 9's, with its
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
| `RoofLayer` (after `ObjectLayer`) | roofs, dual grid | placeholder `roof.png` |
| `ObjectLayer` | walls and doors | author's: 1 WoodWall, 2 WoodenDoor, 3 `BaseWall` (stone wall), 5 `BaseDoor` (stone door); 4 `door_states.png` placeholder for open doors |

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

Roofs came with step 4 (§5).

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

---

## 4. Step 3 — doors (2026-11-04)

**A door is an entity and a grid cell.** `PLACE_DOOR(cell, type)` turns a wall cell into `DOOR`
(`wall_type` holds the `EcsDoorDef` id) and asks lifecycle for the def's blueprint, `door`:
`EcsGridPositionComponent{cell, size}` and `EcsDoorComponent{is_open, is_locked}`, no sprite, so no
nodes; its `EcsPositionComponent` is the cell's centre. Until it is born, `object_id` on the cell
holds a reservation token, as a building's footprint does; binding swaps in the id and adds the door
to its building's `children`. `grid.pending` now serves both, told apart by the spawn note's
override key (`building` or `grid_position`).

**Doors go only into a straight wall** of their own building: the cell must be a wall
(`not_on_wall`), with a wall or door of that building on both sides along exactly one axis — a
corner, a wall's end, a T-junction or a cross is `not_a_straight_wall`. A wall can't be placed over a
door (`occupied`).

**Drawn on the wall layer.** A door lies along its wall: horizontal when its building's wall or
door is beside it left or right. Closed uses the author's `WoodenDoor` (source 2) or `BaseDoor`
(source 5), 0:0 across and 1:0 down; open uses `door_states.png` (source 4), 2:0 and 3:0, since there
is no open-door art yet. Each `EcsDoorDef` names its sources and tiles. **Walls join only walls,** so
a wall beside a door ends in a post and the door sits between two.

**Open and closed are a tile swap.** `TOGGLE_DOOR(cell)` flips `is_open` (refused on a non-door,
`not_a_door`, or before the door is born, `not_built_yet`) and marks the cell `CHANGED_OBJECT`, which
redraws that one cell — a structure change redraws the cell and its four neighbours. This is the
brief's redraw rule for doors: they are tiles, so the dirty cell is the signal, not
`EcsEditSingleton.applied` (that is for sprites).

**Removing** a door (`REMOVE_STRUCTURE`) frees the cell and gives the entity `EcsDyingFlag` with
cause `removed`, out of its building's children; it dies at the next lifecycle and leaves nothing. A
door removed in the same batch it was placed is killed when it is born, so it never outlives its
cell.

**Tests:** placed across and down; refused at a corner, a wall's end, an empty cell, an unknown type;
a token at once, an entity on its cell and a child of its building next tick; drawn with the author's
closed tiles, the walls beside it ending in posts; no wall over a door; no toggling before birth or of
a wall; toggling swaps the tile and redraws one cell, twice back to closed; removal frees the cell,
kills the door with cause `removed`, and the walls end at the gap; a door removed before birth.

---

## 5. Step 4 — rooms and roofs (2026-11-04)

**Only `EcsRoomDetectionSystem` writes `room_id` and a building's `rooms`.** The build system queues
a building in `grid.dirty_buildings` whenever a wall or door in its footprint changes, and when it is
born (walls placed under its token had no id to queue). Room detection clears that building's rooms
and `room_id`s and flood-fills its footprint, 4-connected, walls and doors as boundaries:
- a fill that **leaves the footprint is open** and not kept;
- an enclosed fill with **a door on its boundary is a room**: a town-unique id (`next_room_id`)
  written to its cells, and a record `{id, cells, door_cells, sealed: false, type}`;
- one with **no door is sealed**: recorded with `sealed: true`, no `room_id`.

Four-connected means **a corner missing only diagonally still seals**. The whole building is
recomputed on every change — no incremental patching — and only the buildings that changed. It
then queues the building in `grid.dirty_roofs` and bumps `building_revision` so the overlay redraws.
`type` is empty until step 5 types rooms from their contents.

**Only `EcsRoofSystem` writes `roof`.** For each queued building it roofs every enclosed region,
room or sealed, plus the building's walls and doors around it, and clears the rest of its footprint;
changed cells are marked `CHANGED_ROOF`. One roof type for now (`EcsRoofDef` thatch, id 1); per
building type when the generator picks roofs.

**Roofs are drawn on the dual grid**, on `RoofLayer` above the walls, like a floor — a deviation from
the brief's cell grid, for rounded, joined edges. Two touching roofed buildings therefore read as one
roof. **R** hides or shows the layer (hiding around the ruler comes later); **O** the room colours.
The overlay tints each room by its id and sealed areas red.

**Measured** (`town_test`, one wall placed or removed, averaged over 20): room recompute 136 µs for a
10×10 building, 669 µs for 20×20, 2.7 ms for 40×40 — linear in the footprint, the cost of recomputing
the whole building. Idle buildings cost nothing: nothing is queued.

**Tests:** enclosed with a door (12 cells, the door on its boundary, `room_id` written); an open gap
keeps nothing; no door is sealed with no `room_id`; a corner missing diagonally still encloses; a wall
across a room makes two, each with its own door, and removing one of its cells merges them, with only
that building recomputed; two touching buildings each with their own room inside their own footprint;
a room roofed with its walls and door (all 30 cells of a 6×5 house), drawn, and opening the wall takes
the roof off.

---

## 6. The build panel (2026-11-04)

The tools were keys only; step 5 adds furniture and attachments, too many for that. **A left side
panel**, desktop first (mouse and keyboard; buttons sized so touch can follow without a redesign),
dressed in module 9's HUD styles from `main_theme` — `DockPanel`, `DockButton`, `DockTitle`,
`DockLabel`, `DockHint`, `DockChip`, `TopBar` — as type variations, never per-node overrides.

**Layout, top to bottom:** a 4-wide grid of tool icons (tooltips give the name and shortcut); the
tool's name and a one-line hint; **swatches of its types cut from the scene's own tiles** —
`AtlasTexture` regions of each layer's TileSet, so the author's grass, WoodFloor, WoodWall/BaseWall
(the cross tile, which reads best) and closed doors show as they draw, and a placeholder only where
there is no art; a brush-size row for the brushes only; Roofs / Rooms view toggles at the foot (roofs start hidden: `RoofLayer` is off in the scene). The
status line is a `TopBar` strip right of the panel. Tool icons are generated parchment line icons,
`art/placeholder/icons/`, from `make_placeholders.py`.

**`ui/build_panel.tscn` (`EcsBuildPanel`) is a dumb view.** `main.gd` builds its tools and swatches
from the catalogs and the scene with `setup()` — a new type in a catalog appears with no panel edit —
and listens to its signals: `tool_picked(tool, id)`, `brush_size_changed`, `view_toggled`. They stay on
the panel rather than on the global `EventBus`, so module 10 is self-contained.

**Shortcuts stay** (1–4, 5–8, 0, `[ ]`, B, C, W/E, D/F, T, X, R, O) and keep the panel in step through
`select()`, `set_brush_size()` and `set_views()`; `set_pressed_no_signal` skips a `ButtonGroup`, so
`select()` releases the other tools itself. Tools are named (`&"terrain"`, `&"wall"`, …) and grouped by
how they use the mouse: brushes paint while held, building drags a rectangle, wall and remove drag a
line, close/door/toggle act on a click. Clicks on the panel never reach the map: it stops the mouse and
the map listens in `_unhandled_input`.

# Module 10 — Town Generator: state of the build

Town building on module 9's ECS. **The focus is procedural generation**: a building generator
whose output is the same build commands a player's tools would send. Module 9's world,
scheduler and systems are **borrowed, never copied**; everything new lives in this folder, and
module 9 changes only through a hook the author approves first. The plan is the brief
(`MODULE10_BRIEF.md`, kept outside the repo); started from tag `ecs-baseline`.

**Not in this module, by decision:** live edit, the inspector, selection HUD. Its pipeline is
module 9's ECS core plus the town systems.

```bash
# Tools, types, brush size and views are on the build panel; right-click puts the tool down.
# Keys: Q turns a piece or a stamp; F5 saves the town, F9 loads it. WASD or a middle-drag moves the camera, the wheel zooms.
"$GODOT" --path .   # main.tscn is the main scene

# 124 checks; exit 0 only if all pass. Also prints tile sync and command costs.
"$GODOT" --headless --path . "res://10. Town Generator/tests/town_test.tscn"

# The generator: 1,000 seeds per building type, 18 checks, ~12 s; and its viewer.
"$GODOT" --headless --path . "res://10. Town Generator/tests/generator_test.tscn"
"$GODOT" --path . "res://10. Town Generator/generator.tscn"
```

`main.tscn` is the ECS scene (`main.gd`). **The tile layers are data**: every def and tile
component is a sheet (a PNG) and a tile size; the TileSets are made from them at start, and
`EcsTileSyncSystem` builds the layers from the catalog under the empty `World/TilemapGroup` (2026-11-05, §1 "The layers are built from data").

---

## 1. Layout

| Path | Role |
|---|---|
| `singletons/` | `EcsTownGridSingleton` — the grid |
| `components/` | `EcsBuildingComponent`, `EcsGridPositionComponent`, `EcsDoorComponent`, `EcsTileComponent`, `EcsFurnitureComponent`, `EcsPlantComponent`, `EcsAttachableComponent`, `EcsAttachedToComponent` |
| `ecs/` | `EcsTownGrid` (cell maths, making a grid), `EcsDualGrid` (masks, layout, TileSet), `EcsBuildCommand`, `EcsBuildRules` (every check, changing nothing), `EcsBuildingStamp` (capture a building, stamp a def as commands), `EcsBuildingGenerator` (a building from a seed, as commands), `EcsBuildingCheck` (is a built building sound) |
| `generator.tscn` | The generator's viewer (`generator_view.gd`) |
| `save/` | `EcsTownSave`, a saved town by key |
| `systems/` | `EcsBuildCommandSystem`, `EcsRoomDetectionSystem`, `EcsRoofSystem`, `EcsTileSyncSystem`, `EcsTownOverlaySystem` |
| `ui/` | `town_ui.gd` (`EcsTownUI`, on main.tscn's `UI` CanvasLayer): the HUD's code; `build_panel.tscn` (`EcsBuildPanel`), the build panel on the left |
| `town_overlay.gd` | `EcsTownOverlay`, the view that draws footprints and drag previews |
| `defs/` | `EcsTileDef` (a sheet and a tile size) → `EcsTerrainDef`, `EcsFloorDef`, `EcsRoofDef`, `EcsWallDef` (+ hp, rubble); `EcsTownCatalog`; `town_catalog.tres` and one `.tres` per type; `EcsBuildingDef` and `buildings/` (cottage, workshop); `EcsBuildingTypeDef` and `building_type/` (house, workshop); `entity_catalog.tres` (module 9's `EcsEntityCatalog`) and `blueprints/` |
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

**Types are named, not numbered by hand.** Each terrain, floor, wall, door and roof def has a `key`
(`&"dirt"`, `&"stone"`), unique within its list — that is its identity. The grid still stores ints
(`PackedInt32Array`, 4 bytes a cell), but **the catalog assigns them**: `number()` gives each list
1, 2, 3, … in order, once, and warns on a repeated key; every lookup calls it. `terrain_id(&"dirt")`
and its siblings turn a name into the grid's number. So adding a type is adding a def to the
catalog — no last number to remember. **Anything kept stores keys, never these numbers**: saves and
building defs (step 6) will write `&"dirt"`, so reordering a list can't break them. This replaces the
brief's "stable ids authored in each `.tres`" with stable names, which meets the same need. Room types
and blueprints were already named.

**The layers are built from data** (2026-11-05; from step 1 to step 6 they were nodes in
`main.tscn`, then TileSet files in `art/tilesets/`, now gone). **Everything drawn is a sheet and a
tile size, and no TileSet is stored.** A terrain, floor or roof def is `texture` and `tile_size`; its TileSet is made at start by `EcsDualGrid.make_tile_set` — every tile of the sheet in
one source — and which tile is which corner shape is read from the pixels (`corner_layout`), so a new
type is a def and a PNG, with no TileSet, peering bits or atlas to set up. `EcsTownCatalog.tiles(def)`
makes it the first time it is asked for and keeps it for the run (the swatches and the tile sync share
it). **Made at every start, never stored**: all nine take ~13 ms (measured in `town_test`, against an
82 ms first draw of a 64x64 town), so a cache file regenerated when the data changes would save little and
could go stale; revisit if a sheet gets large (the pixel scan is per pixel). Every sheet read from its
pixels gives the same layout as the TileSets painted by hand before it (2026-11-05, checked for all
nine and both wall sheets), WoodFloor's and WoodWall's peering bits included.

On the cell grid: **a wall def** is `texture` and `tile_size`, its 16 shapes read from the pixels
(`side_layout`); **a door def** is a sheet per state (`closed_texture`, `open_texture`), each with its
`margins` (8 px on WoodenDoor and BaseDoor) and the tile for each direction, and one `tile_size` (48:
door tiles are bigger than a cell and drawn centred). The catalog makes one walls-and-doors TileSet
(`wall_tiles()`) when it numbers its defs, a source per sheet — a sheet two doors share is one source
(`door_states.png`, the open doors) — and writes the source ids on the defs (`source_id`,
`closed_source_id`, `open_source_id`, runtime, never authored). **Furniture, plants and attachments
carry their sheet on their blueprint**: `EcsTileComponent{texture, tile_size, atlas}`; the tile sync
gives their layers empty TileSets and adds a source for a sheet the first time a piece from it is
drawn, so a blueprint with a new sheet needs nothing else (attachments are 16 px tiles, drawn centred
in their cell). **Draw order is
list order in the catalog**, the same order that numbers the types: terrains, then floors, then
furniture, walls, attachments, then roofs. `EcsTileSyncSystem` owns `World/TilemapGroup`: its first run
clears it and makes one `TileMapLayer` per type, scaled so a tile spans one 32 px cell (the 16 px grass
at 2x, from its TileSet's tile size), dual-grid layers half a cell up and left; a load rebuilds them.
Nothing about drawing is set on a node, so a generated or loaded town needs no scene edit, and a new
type is a def and a PNG. The author's art is used wherever it exists; placeholders fill only the
slots without any:

| Layer, in draw order | Draws | Art |
|---|---|---|
| `Terrain_grass` | grass | sheet: author's `grassTileset.png`, 16 px, drawn at 2x |
| `Terrain_dirt`, `_sand`, `_water` | terrain | sheets: placeholders |
| `Floor_wood` | wood | sheet: author's `WoodFloor.png` |
| `Floor_stone`, `_road`, `_rug` | floor | sheets: placeholders |
| `Furniture` | furniture and plants, cell grid | `furniture` — placeholder `objects.png`, 32 px |
| `Walls` | walls and doors | `walls` — author's: 1 WoodWall, 2 WoodenDoor, 3 `BaseWall` (stone wall), 5 `BaseDoor` (stone door); 4 `door_states.png` placeholder for open doors |
| `Attachments` | attachments, cell grid | `attachments` — placeholder `attachments.png`, 16 px icons centred |
| `Roof_thatch` (last) | roofs, dual grid, hidden by default | sheet: placeholder `roof.png` |

**The dual grid.** Terrain and floor are drawn on a grid offset half a cell, so each render tile
sits on a cell corner and shows a quarter of each of its four cells; the 4-bit mask of which
quarters are filled picks the tile. **A type's layer also fills under every later type** (bit set
when the cell's type draws at or after the layer), so a higher type's rounded edge never shows a
hole. Terrain off the map repeats the edge cell; floor off the map is none. **A floor runs under its walls**
(2026-11-05): when floors are drawn, a wall or door cell is drawn, in each render tile, with the
highest floor among the open cells beside it — never its own — so a floor fills right to the wall's
middle, where the wall's art covers its edge, instead of stopping short and showing ground between floor
and wall; on the wall's outer side the tile has no floor beside it and stays bare. A floor laid before
the wall went up behaves the same: it stays in the grid under the wall (and shows again if the wall is
removed) but is not drawn past the wall's middle. Only the drawing does this: the grid's `floor` is
unchanged. A wall placed or removed next to a floor redraws the floor's four
corner tiles there too (not on bare ground, so a wall alone still redraws five cells at most). Full tiles have
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

**Tests**: a layer per type built from its def's TileSet in catalog order, and none in `main.tscn`; the author's
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

**Tools** (`main.gd`): Building drags a footprint (preview red when it would overlap), Wall drags a
straight wall line along the axis moved more, Remove drags a removal line, Close building closes the
building clicked. `EcsTownOverlay` draws footprints — **dashed while open, solid with a light fill once closed** —
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

**Roofs are drawn on the dual grid**, on the roof layer above the walls, like a floor — a deviation from
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

## 6. Step 5 — floors, furniture, attachments, room types (2026-11-04)

**Floors** were already paintable inside and outside buildings (step 1); a floor can't go under a
plant (`plant_here`).

**Furniture and plants are entities on the grid**: blueprints in `defs/blueprints/` with
`EcsGridPositionComponent{cell, size}`, `EcsTileComponent{texture, tile_size, atlas}` (its sheet,
and the tile of its top-left cell) and `EcsFurnitureComponent{tags, holds}` or the `EcsPlantComponent` tag. 14 pieces and 3
plants, generated over `objects.png`'s 32 px grid. **A multi-cell piece fills `object_id` on every
cell it covers**, and each cell draws its own 32 px slice (the bed is two tiles, the sawmill four), so
no oversized tile or texture origin is needed. `PLACE_OBJECT(cell, blueprint)` puts the top-left on
`cell`; every covered cell must be free of walls, doors and objects (`occupied`), all in one building
or none (`straddles` — a sawmill in a field is fine, `building_id -1`), a plant on no floor
(`plant_on_floor`). `REMOVE_OBJECT` by any of its cells frees all of them.

**Pieces turn** (2026-11-05), in quarter turns clockwise: `PLACE_OBJECT`'s `value` is the turns, and
the placed piece's `EcsGridPositionComponent` keeps them in `turns`, its `size` becoming the cells it
covers once turned (a blueprint's `size` stays as drawn). The rules and the build system check and fill
the turned rect. **No turned art is needed**: each covered cell draws the slice that turned onto it
(`EcsTownGrid.turn` backwards), with the tile flags for the turn — transpose and flip, set on the cell
through its alternative id (`EcsTileSyncSystem.TURN_FLAGS`). Q turns the piece in hand; the ghost turns
with it. Art drawn with a light direction or a front will show its turn; a piece needing real turned
art would want a per-turn atlas on its tile component.

**Attachments** are entities too — `EcsAttachableComponent{on_wall, on_furniture}`,
`EcsAttachedToComponent{host_kind, host_cell, host_id}` — six, on `attachments.png`. **One per cell
slot**: a wall cell, or one cell of furniture that `holds` (table, long table, stove, chest,
workbench, shelf). The grid gained one layer the brief doesn't list, **`attachment_id`**, so a slot
check and a redraw are one lookup. `ATTACH(cell, blueprint)` refuses a taken slot (`slot_taken`), a
host that takes no attachments (`no_host`: a barrel, bare floor) and the wrong kind of host
(`not_for_this_host`: a candle on a wall, a wall lamp on a stove). `DETACH(cell)` takes one off.
**Removing a host removes its attachments first** — a table its candle, a wall its lamp.

**Everything placed reserves under a token**, as buildings and doors do, so a generator's batch —
table, then the candle on it — works in one go. `grid.pending` now binds three kinds, told apart by the
spawn note's overrides: a building's footprint, an object's covered cells (with `size`), an attachment's
slot (setting its `host_id` from the table born the same tick). Born things join their building's
`children`; one removed before it was born is killed when it binds.

**Rooms are typed from their contents.** `EcsRoomTypeDef{id, needs, priority}` in `defs/room/`:
bedroom (bed, 5), kitchen (stove or hearth, 4), workshop (workbench, 3), dining room (table, 2), store
room (storage, 1). Room detection gathers the tags of the furniture in each room and gives it the
highest-priority type any tag satisfies, else none; placing or removing furniture queues its building,
so the type follows. The overlay prints each typed room's name at its centre.

**Drawn** on two layers of their own: furniture under the walls, attachments above them; each
piece's sheet is on its blueprint (§1). A dirty
`CHANGED_OBJECT` cell redraws its furniture slice and its attachment.

**In the panel:** Furniture, Plant and Attach tools, their lists read from the entity catalog and
their swatches cut from those layers (a multi-cell piece shows whole). Remove now takes off whatever is
on top of each cell — an attachment, else furniture, else a wall or door. The type swatches sit in a
scroll area, so a long list never pushes the panel off the screen.

**Tests:** pieces cover and draw every cell; occupied, on a wall, straddling, a plant on a floor and an
unknown piece refused; outdoors allowed; removal by any cell. Attachments: on a table placed the same
batch and on a wall; slot taken, wrong host, no host refused; the candle knows its table; removing the
table and the wall takes their attachments. Types: bedroom, kitchen, a bed outranking a table, dining
without the bed, none when empty. **The brief's "done": a house built entirely by hand in one batch —
walls, door, floor, bed, a table with a candle on it — every command accepted, one room, a bedroom.**

---

## 7. The build panel (2026-11-04)

The tools were keys only; step 5 adds furniture and attachments, too many for that. **A left side
panel**, desktop first (mouse and keyboard; buttons sized so touch can follow without a redesign),
dressed in module 9's HUD styles from `main_theme` — `DockPanel`, `DockButton`, `DockTitle`,
`DockLabel`, `DockHint`, `DockChip`, `TopBar` — as type variations, never per-node overrides.

**Layout, top to bottom:** a 4-wide grid of tool icons (tooltips give the name and shortcut); the
tool's name and a one-line hint; **swatches of its types cut from their own tiles** —
`AtlasTexture` regions of each type's TileSet, so the author's grass, WoodFloor, WoodWall/BaseWall
(the cross tile, which reads best) and closed doors show as they draw, and a placeholder only where
there is no art; a brush-size row for the brushes only; Roofs / Rooms view toggles at the foot (roofs start hidden: `main.gd` sets the tile sync's `roofs_visible`). The
status line is a `TopBar` strip right of the panel. Tool icons are generated parchment line icons,
`art/placeholder/icons/`, from `make_placeholders.py`.

**All UI code is on the `UI` CanvasLayer** (`ui/town_ui.gd`, `EcsTownUI`; 2026-11-05, moved out of
`main.gd`). It builds the panel's tools from the catalogs, each swatch cut from its sheet — a new type
in a catalog appears with no panel edit — writes the status bar and its timed notices, and turns a
panel choice back into what it means (`blueprint(tool, id)`, `ghost(tool, id)`). It never touches the
world: `main.gd` keeps the world, map input, the ghost preview, commands and saving, hears the UI's
signals (`tool_picked(tool, id)`, `brush_size_changed`, `view_toggled`, `town_requested`) and calls
`setup()`, `set_stamps()`, `show_status()` and `tell()`. **`ui/build_panel.tscn`
(`EcsBuildPanel`) is a dumb view** under it. The signals stay on the UI rather than the global
`EventBus`, so module 10 is self-contained.

**The panel is the only way to pick a tool, type, brush size or view** (2026-11-05: the keys from
before it — 1–8, 0, `[ ]`, B, C, W/E, D/F, T, X, R, O — were removed). S and P (save building,
stamp) went too, S because WASD moves the camera. The keys left have no panel button: Q (turn), F5,
F9. **Right-click on the map puts the tool in hand down** (2026-11-05): no tool picked on the panel
(`clear_tool()`), no ghost, any drag dropped, and left clicks do nothing until a tool is picked again; a
right-click over the panel is the panel's and changes nothing. `select()` shows the starting tool; `set_pressed_no_signal` skips a `ButtonGroup`, so it releases
the other tools itself. Tools are named (`&"terrain"`, `&"wall"`, …) and grouped by
how they use the mouse: brushes paint while held, building drags a rectangle, wall and remove drag a
line, close/door/toggle act on a click. **Walls and doors are one tool on the panel** (2026-11-05):
its types are the walls then the doors, each labelled "Wood wall", "Wood door"…; a door's choice id is
`EcsTownUI.DOOR_CHOICE` (100) plus its door id, and the UI hands `main.gd` a door choice as the door tool,
so placing doors, their ghost and their refusals are as before — a wall type drags a line, a door type
clicks. The defs stay apart: a door has two sheets, fixed tiles and a blueprint, so it does not share
`EcsTileDef`'s promise that a type's shapes are read from its sheet. Swatch labels wrap to two lines
(swatches 68x84) rather than widen the panel. **The HUD eats the mouse** (2026-11-05): the panel and the status bar
stop it and `EcsTownUI` accepts every mouse event that lands on them, so a click, wheel or middle-drag
over them never reaches the map (which listens in `_unhandled_input`) or the camera. The shared camera
(`Global/Scene/camera_2d.tscn`) reads the wheel and **a pan's start** in `_unhandled_input` for the same
reason — a pan started over the panel used to move the map — and the drag and release in `_input`, so a
pan begun on the map follows the mouse anywhere. Checked by pushing real events at the panel's empty
area, a tool button, a swatch, a label and the status bar: none zooms, pans or builds, the map still
does all three, a tool button still picks its tool and the type list still scrolls.

**Placement preview** (2026-11-04). With a tool picked, the cell under the mouse shows what a click
would do before it is made: the piece's tiles across every cell it would cover (furniture, plants),
the icon in its slot (attachments), the door turned to its wall, the brush square, or the cell
outline (wall, building, close, open/close). **Red, with the reason beside it** (`occupied`, `plant on
floor`, `not a straight wall`, …) when the build system would refuse it; a dragged wall line marks
each refused cell red. **The preview asks the build system's own rules**: every check now lives in
`EcsBuildRules.refusal(world, grid, catalog, entities, command)`, which changes nothing; the build
system calls it before applying and applies only what it accepts, and `main.gd` calls it on hover —
so the two can't drift, and a test sends a dozen mixed commands and checks each predicted verdict is
the result. **What a click would send is written once**: `main.gd`'s `_commands_at(cell)` turns the tool
in hand into commands, `_click` sends them and the hover checks the first (2026-11-05; the two used to
build their commands separately). How the ghost is drawn — a piece filling its turned cells, an icon or
a door's oversized tile centred, the red reason, a stamp's walls marked — is the overlay's
(`EcsTownOverlay.show_ghost()`); `main.gd` hands it cells, picture and verdict. The hover is recomputed each physics frame but redrawn only when the cell, tool, choice,
brush or grid changed, and hidden while the mouse is over the panel.

---

## 8. Step 6 — building defs, stamps, town saves (2026-11-04)

**`EcsBuildingDef`** (`defs/ecs_building_def.gd`) is a building as data: `size`, `closed`, and typed
dictionaries from a cell relative to the footprint's top-left to a key — `walls`, `doors` and `floors`
to catalog keys, `objects` (a piece's top-left) and `attachments` (a slot) to blueprints. **Keys, never
numbers**, so reordering a catalog list can't break one. The shipped ones are `defs/buildings/`
(`cottage`: bedroom and kitchen through an inner door; `workshop`), each built by hand with commands
and captured, not written by hand.

**`EcsBuildingStamp`** (`ecs/`) is pure. `capture(world, grid, catalog, building_id)` reads a building
off the grid; `commands(def, catalog, entities, at, turns)` gives back **the same commands the tools
send**, so a stamp is checked by `EcsBuildRules` like anything else and every refusal is a result on its
command. Order: building, floors, walls (one under each door, of a neighbouring wall's type, since a
door goes into a wall), doors, pieces, attachments. `CREATE_BUILDING` gained one option, `closed`
(`value` 1), because `CLOSE_BUILDING` needs a born building and a stamp is one batch.

**Turning is in quarter turns clockwise.** Cells and rects turn round the footprint
(`EcsTownGrid.turn`, `turn_rect`, `turned`). **Each piece turns with the building** — its own turns
(`object_turns`, kept only when not 0) plus the stamp's — so every piece lands exactly on its turned
cells and every attachment on a piece or wall turns with its cell. (Before pieces could turn, a stamp
fitted unturned pieces near their turned place, and on a quarter turn the cottage's long table took its
chair's cell; the test over every shipped def in every turn came from that.)

**`EcsTownSave`** (`save/`) is a town by key: terrain as a palette plus an index per cell, floors,
pieces and attachments outside buildings, and every building as an `EcsBuildingDef` with its top-left.
**Loading is commands too** — a new world, the grid made empty, then `save.commands()` sent as one
batch — so a load is checked exactly like building by hand and nothing restores ids. Saved as `.tres`
under `user://towns/`. **Not kept:** whether a door is open (they come back closed), and anything
still unborn when saved.

**In the scene:** *Save building* (S) captures the clicked building into
`user://buildings/building_N.tres` and adds it to the stamps; *Stamp* (P) lists the shipped and saved
defs, each swatch a small plan of the building, places the chosen one top-left on the click, **Q turns
it**; its ghost is the turned footprint with its walls and doors marked, red with the reason when the
footprint would be refused. The panel's *Town* row (and F5 / F9) saves and loads `user://towns/town.tres`;
`main.gd` rebuilds the world through `_start()`, which `_ready()` uses too.

**Tests (16):** a turn moves cells round the footprint and four are none; **the brief's "done": a
two-room house built by hand, captured, stamped ten times across all four turns, every command
accepted, every copy with the same rooms of the same types and sizes and its lamp and candle**; a town
of two buildings (one turned, one closed), water, a road and a tree saved to a file, read back and
loaded into a fresh world: every cell's terrain, floor, structure, type and roof the same, every
object, attachment, footprint and room where it was, and the buildings' footprints, closed flag, rooms
and children intact (a turned table outside among them); both shipped defs stamp clean in every turn.
Turned pieces: a bed turned once covers 2x1, draws its foot left and head right with the clockwise
flags, each turn its own flags, refused when turned into a wall but fitting upright, removed whole.

**Measured** (`town_test`, three runs): ten stamped cottages, 620 commands, apply in ~4.1 ms and their
tile sync takes ~4.7–5.3 ms on the tick they're sent — about 0.4 + 0.5 ms a house, in line with step 2's
hand-built building. (Re-run on 2026-11-05: 5.7 + 6.3 ms, with every older figure in the test ~1.5x up
too — the machine, not the change.)

---

## 9. Step 7 — the building generator (2026-11-05)

**`EcsBuildingGenerator`** (`ecs/`) is pure and seeded, not a system: `generate(type, size, wealth,
facing, seed, catalog, entities, at)` gives back the commands the player's tools send, so the build
system checks a generated building exactly as a hand-built one; `plan(...)` is the same with the
layout beside it (rooms and their roles, the entrance, the doors, pieces that found no place), for
checks and the viewer. All randomness is one `RandomNumberGenerator` seeded once, so the same inputs
give the same commands.

1. **Rooms**: binary space partition of the footprint inside its walls — the largest room that can
   still split is split across its longer side (a square one by a coin), never leaving a room smaller
   than the type's `min_room` (3x3 inside), until the type's room count for the wealth.
2. **Walls**: the perimeter and each split's line, wall to wall.
3. **Doors**: the entrance on a perimeter cell of the facing side with a room right inside it (never a
   corner or where a split meets it); inner doors along a random spanning tree grown from the entrance
   room over pairs of rooms that share a straight stretch of wall, one door per tree edge on a cell with
   wall on both sides along it and a room on each side across; by `loop_chance` one more on a pair the
   tree skipped.
4. **Roles** from the type's list, largest room first (the first is the main room; past the end, the
   last repeats).
5. **Floor** on every room cell, by wealth; the poorest's floor key is empty, so it stays bare ground.
6. **Furniture**: a room's type (`EcsRoomTypeDef`) now lists `required` and `optional` blueprints; all
   required ones go in, each optional one by the type's `optional_chance` for the wealth. A piece that
   stands **against a wall** says so on its own furniture component (`against_wall`: beds, stove, hearth,
   chest, shelf, barrel, workbench), and goes with its back — its top edge as drawn — on the room's edge,
   turned as needed (pieces turn, §6); others prefer the middle and touch an edge only when nothing
   else fits. A door's inside neighbour is never furnished, and **a piece is never placed where it would
   cut the room's free cells in two** — so every door stays reachable inside its room. Candidates are
   drawn at random and only the drawn one is flood-filled, re-drawing if it would split the room
   (checking every candidate cost 17 ms a building; this 1.4 ms).

**`EcsBuildingTypeDef`** (`defs/building_type/`, listed in the catalog as `building_types`): size range,
`min_room`, room count, wall, door and floor keys and optional chance **by wealth** (one entry per level,
poorest first: poor, middling, rich), roles, loop chance. **house**: 1/3/4 rooms, bedroom, kitchen,
store, bedroom; wood, wood, stone; no floor, wood, wood. **workshop**: 1/2/3 rooms, workshop, store,
kitchen; wood then stone, stone floors. Two types at three wealths cover the brief's "a poor house, a rich
house and a workshop".

**`EcsBuildingCheck.problems(world, grid, building, entrance)`** (`ecs/`) reads a built building and
says what is wrong, changing nothing: a sealed area (a room with no door), a room or a door that can't be
walked to from the entrance (walking through doors and cells with no wall and no object), furniture on a
door's inside neighbour, no entrance.

**The viewer** (`generator.tscn`): type, wealth, facing, width, height and seed on the left; every change
regenerates into a new world through the real pipeline, with rooms coloured and named by room detection;
Regenerate takes the next seed. It frames the building, and once it has settled reports the rooms and
roles, commands and refusals, the generator's time, pieces with no room, and the check — "Sound" or the
problems.

**Tests** (`tests/generator_test.tscn`, separate because it takes ~12 s): for each type, 1,000 seeds,
each drawing its size from the type's range, wealth from `seed % 3` and facing from the seed; generated,
sent through lifecycle, the build system and room detection on its own grid, and checked. **The brief's
"done": every command accepted, no sealed area, every room and every door reachable from the entrance,
no furniture on a door's inside neighbour, an entrance on the facing side, and the same seed giving the
same commands — for 2,000 buildings; also every room typed by room detection as the role it was given**
(3,701 rooms, none mistyped). 18 checks.

**Measured** (`generator_test`): 1.4 ms a house and 1.3 ms a workshop on average, 5 ms at worst (a
14x11 rich house); 7 optional pieces in 1,000 houses found no room. The viewer's first generation plus
pipeline is a few ms.

---

## 10. Step 8 — a wall can be hit (2026-11-05)

A proof of concept; real wall combat is module 11. **`EcsTownGridSingleton.wall_hits`** is a queue of
`{cell, amount}`, and **the build command system applies it**, after the tick's commands — it stays the
only writer of cells. Each hit on a WALL cell takes its amount off the cell's hp, kept in `wall_hp`
(cell index -> hp, damaged walls only; a wall not in it is at its type's `max_hp`). Above 0 the wall
stands. **At 0**: the hp entry goes, whatever hangs on the wall goes with it (cause removed), the cell
clears exactly as a removal does — so its neighbours redraw as ends and posts, and its building is queued
for room detection, which finds the rooms again (a broken split wall merges two rooms; a hole in an outer
wall leaves the area open) — and **the wall type's `rubble`** (`EcsWallDef.rubble`, both types:
`&"rubble"`) is asked of lifecycle on that cell, reserved by token like any piece, so it is born at the
next lifecycle and drawn on the furniture layer. Rubble is an object with a grid position and a tile and
nothing else: it blocks building on the cell until removed (Remove takes it like furniture), and it is
not offered on the panel — the panel offers only furniture, plants and attachments. A hit on anything but
a wall (a door, a floor, off the map) does nothing. Placing or removing a wall, or setting a door in it,
forgets the cell's damage. The system counts `hits_applied` and `walls_broken` for the last run with hits.
Nothing raises hits yet but tests, as the brief asks: no brain, no tool.

**Tests:** two rooms split by a wall with a lamp on it; a hit for 40% leaves the wall standing at 60% hp
while hits on a floor and a door do nothing; the hit that takes it to 0 clears the cell and forgets its
hp, the lamp dies with it, rubble lies where it stood and is drawn, and the two rooms are one through the
gap; a damaged wall then removed forgets its damage. **The brief's "done": that test passes.**

---

## 11. Open for discussion

- **What "closed" means** (flagged 2026-11-05). `CLOSE_BUILDING` sets `EcsBuildingComponent.closed`,
  one way; the only thing that reads it is the overlay (dashed outline open, solid with a fill closed),
  and building defs and saves keep it. Nothing else changes: a closed building can still be edited, and
  it is unrelated to rooms or `sealed`. The brief gives it no purpose — it lists the field and the
  command and says only "no room required" — and `owner_id`, `quality` and `builder_id` beside it are
  likewise unused. The author has a plan for it, to be discussed. Mind the brief's limits for this phase
  when it is: placement is instant with no construction by workers, and no ownership, economy or
  workers (§1, §2). Until then the tool stays as it is.

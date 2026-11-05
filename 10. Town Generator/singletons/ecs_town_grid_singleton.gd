class_name EcsTownGridSingleton
extends EcsSingleton

## The town's cell grid: one value per cell per layer, indexed `y * width + x`.
## Only EcsBuildCommandSystem writes cells; EcsTileSyncSystem draws them.

## What stands on a cell, in `structure`.
const NONE: int = 0
const WALL: int = 1
const DOOR: int = 2

## "No building" or "no object" in `building_id` and `object_id`. Not EcsWorld.NO_ENTITY, which is 0.
const NO_ID: int = -1

## What changed on a cell, as bits in `dirty`.
const CHANGED_TERRAIN: int = 1
const CHANGED_FLOOR: int = 2
const CHANGED_STRUCTURE: int = 4
## Only the object on the cell changed state (a door opened): redraw that cell alone.
const CHANGED_OBJECT: int = 8
const CHANGED_ROOF: int = 16

var width: int = 0
var height: int = 0
## Terrain catalog id per cell; 0 = none.
var terrain: PackedInt32Array = PackedInt32Array()
## Floor catalog id per cell; 0 = none.
var floor: PackedInt32Array = PackedInt32Array()
## NONE, WALL or DOOR.
var structure: PackedInt32Array = PackedInt32Array()
## WallDef id of a WALL cell, DoorDef id of a DOOR cell.
var wall_type: PackedInt32Array = PackedInt32Array()
## Owning building's entity id; -1 = none. Below -1 is a footprint reserved for a building
## not yet born, a key into `pending`.
var building_id: PackedInt32Array = PackedInt32Array()
## Door, furniture or plant entity on the cell; -1 = none, below -1 a reservation token.
var object_id: PackedInt32Array = PackedInt32Array()
## Attachment in the cell's one slot — on its wall or on the furniture covering it; -1 = none,
## below -1 a reservation token.
var attachment_id: PackedInt32Array = PackedInt32Array()
## Room the cell belongs to; -1 = not in a room.
var room_id: PackedInt32Array = PackedInt32Array()
## Roof catalog id; 0 = none.
var roof: PackedInt32Array = PackedInt32Array()
## Damaged walls only: cell index -> hp. A wall missing here is at its type's `max_hp`.
var wall_hp: Dictionary = {}
## Hits on wall cells waiting for the build system, oldest first: {cell: Vector2i, amount: float}.
var wall_hits: Array[Dictionary] = []
## Pending build commands, oldest first.
var commands: Array[EcsBuildCommand] = []
## Reservations awaiting their entity — a building's footprint or a door's cell: token -> EcsSpawnRequest.
var pending: Dictionary = {}
## Buildings whose walls or doors changed, for room detection: id -> true.
var dirty_buildings: Dictionary = {}
## Buildings whose rooms changed, for the roof system: id -> true.
var dirty_roofs: Dictionary = {}
## Next room id; room ids are unique across the town.
var next_room_id: int = 1
## Bumped whenever a building's own data changes (closing it, its rooms), so views redraw without scanning.
var building_revision: int = 0
## Next reservation token; counts down from -2.
var next_token: int = -2
## Cells redrawn on the next tile sync: cell index -> CHANGED_* bits.
var dirty: Dictionary = {}

func key() -> StringName:
	return &"town_grid"

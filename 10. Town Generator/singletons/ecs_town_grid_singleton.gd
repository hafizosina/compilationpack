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

var width: int = 0
var height: int = 0
## Terrain catalog id per cell; 0 = none.
var terrain: PackedInt32Array = PackedInt32Array()
## Floor catalog id per cell; 0 = none.
var floor: PackedInt32Array = PackedInt32Array()
## NONE, WALL or DOOR.
var structure: PackedInt32Array = PackedInt32Array()
## WallDef id of a WALL cell.
var wall_type: PackedInt32Array = PackedInt32Array()
## Owning building's entity id; -1 = none. Below -1 is a footprint reserved for a building
## not yet born, a key into `pending`.
var building_id: PackedInt32Array = PackedInt32Array()
## Door, furniture or plant entity on the cell; -1 = none.
var object_id: PackedInt32Array = PackedInt32Array()
## Room the cell belongs to; -1 = not in a room.
var room_id: PackedInt32Array = PackedInt32Array()
## Roof catalog id; 0 = none.
var roof: PackedInt32Array = PackedInt32Array()
## Damaged walls only: cell index -> hp.
var wall_hp: Dictionary = {}
## Pending build commands, oldest first.
var commands: Array[EcsBuildCommand] = []
## Reserved footprints awaiting their building: token -> EcsSpawnRequest.
var pending: Dictionary = {}
## Bumped whenever a building's own data changes (closing it), so views redraw without scanning.
var building_revision: int = 0
## Next reservation token; counts down from -2.
var next_token: int = -2
## Cells redrawn on the next tile sync: cell index -> CHANGED_* bits.
var dirty: Dictionary = {}

func key() -> StringName:
	return &"town_grid"

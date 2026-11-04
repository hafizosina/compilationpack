class_name EcsBuildingComponent
extends EcsComponent

## A building: the footprint it owns on the town grid. Its walls are the wall cells
## inside the footprint; the grid's `building_id` names it on every footprint cell.

## Cells it owns, in grid coordinates. Set once, at creation.
var footprint: Rect2i = Rect2i()
## Room records from room detection (step 4).
var rooms: Array = []
## Doors, furniture and attachments that belong to it (steps 3 and 5).
var children: Array[int] = []
## Marked finished by CLOSE_BUILDING; needs no room.
var closed: bool = false
var quality: int = 0
var owner_id: int = EcsWorld.NO_ENTITY
var builder_id: int = EcsWorld.NO_ENTITY

func key() -> StringName:
	return &"building"

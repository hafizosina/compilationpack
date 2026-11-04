class_name EcsAttachedToComponent
extends EcsComponent

## Where an attachment is: on a wall cell, or on the furniture covering `host_cell`.

enum HostKind { WALL_CELL, ENTITY }

var host_kind: HostKind = HostKind.WALL_CELL
## The cell it occupies: the wall cell, or the furniture's cell it sits on (its slot).
var host_cell: Vector2i = Vector2i.ZERO
## The furniture it sits on; NO_ENTITY on a wall.
var host_id: int = EcsWorld.NO_ENTITY

func key() -> StringName:
	return &"attached_to"

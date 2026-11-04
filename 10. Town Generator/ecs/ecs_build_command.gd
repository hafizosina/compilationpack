class_name EcsBuildCommand
extends RefCounted

## One build request for EcsBuildCommandSystem. The player's tools and the
## generator both speak in these.

enum Kind { SET_TERRAIN, SET_FLOOR, CLEAR_FLOOR, PLACE_WALL, REMOVE_STRUCTURE }

var kind: Kind = Kind.SET_TERRAIN
var cell: Vector2i = Vector2i.ZERO
## Catalog id: terrain, floor or wall type.
var value: int = 0
## Set when applied: &"ok", or why it was refused.
var result: StringName = &""

static func make(kind: Kind, cell: Vector2i, value: int = 0) -> EcsBuildCommand:
	var command := EcsBuildCommand.new()
	command.kind = kind
	command.cell = cell
	command.value = value
	return command

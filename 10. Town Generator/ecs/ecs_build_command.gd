class_name EcsBuildCommand
extends RefCounted

## One build request for EcsBuildCommandSystem. The player's tools and the
## generator both speak in these.

enum Kind { SET_TERRAIN, SET_FLOOR, CLEAR_FLOOR, CREATE_BUILDING, CLOSE_BUILDING, PLACE_WALL, REMOVE_STRUCTURE }

var kind: Kind = Kind.SET_TERRAIN
var cell: Vector2i = Vector2i.ZERO
## Catalog id: terrain, floor or wall type.
var value: int = 0
## CREATE_BUILDING's footprint.
var rect: Rect2i = Rect2i()
## The building it is about: CLOSE_BUILDING's, or one PLACE_WALL must belong to. After
## CREATE_BUILDING, the reservation token for the building it asked for. -1 = none.
var building: int = -1
## Set when applied: &"ok", or why it was refused.
var result: StringName = &""

static func make(kind: Kind, cell: Vector2i, value: int = 0) -> EcsBuildCommand:
	var command := EcsBuildCommand.new()
	command.kind = kind
	command.cell = cell
	command.value = value
	return command

static func create_building(rect: Rect2i) -> EcsBuildCommand:
	var command := EcsBuildCommand.new()
	command.kind = Kind.CREATE_BUILDING
	command.rect = rect
	return command

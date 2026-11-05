class_name EcsBuildingDef
extends Resource

## A building as data: what stands in its footprint, every cell relative to the footprint's
## top-left and every type by key. EcsBuildingStamp captures one from the grid and turns
## one back into build commands, optionally rotated.

## Its name, unique among building defs.
@export var key: StringName = &""
@export var display_name: String = ""
## Footprint size in cells.
@export var size: Vector2i = Vector2i.ONE
## Marked finished.
@export var closed: bool = false
## Wall cell -> wall key.
@export var walls: Dictionary[Vector2i, StringName] = {}
## Door cell -> door key.
@export var doors: Dictionary[Vector2i, StringName] = {}
## Floor cell -> floor key.
@export var floors: Dictionary[Vector2i, StringName] = {}
## Furniture or plant: top-left cell -> blueprint.
@export var objects: Dictionary[Vector2i, StringName] = {}
## A turned piece's top-left cell -> its quarter turns clockwise; unturned ones are left out.
@export var object_turns: Dictionary[Vector2i, int] = {}
## Attachment: its slot's cell -> blueprint.
@export var attachments: Dictionary[Vector2i, StringName] = {}

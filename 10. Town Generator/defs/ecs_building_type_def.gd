class_name EcsBuildingTypeDef
extends Resource

## A kind of building the generator makes: how it splits into rooms, what the rooms are for,
## and what it is built of. The lists marked "by wealth" hold one entry per wealth level,
## poorest first; a level past the end uses the last.

## Its name, unique among building types.
@export var key: StringName = &""
@export var display_name: String = ""
## Footprint sizes the viewer and the tests draw from, walls included.
@export var min_size: Vector2i = Vector2i(7, 6)
@export var max_size: Vector2i = Vector2i(13, 10)
## The smallest room, inside its walls; no split leaves a smaller one.
@export var min_room: Vector2i = Vector2i(3, 3)
## How many rooms it aims for, by wealth; fewer when the footprint can't split that far.
@export var rooms: Array[int] = [1, 2, 3]
## Room roles, largest room first: the first is the main room; past the end, the last repeats.
@export var roles: Array[StringName] = []
## Wall, door and floor keys by wealth; an empty floor key leaves bare ground.
@export var walls: Array[StringName] = [&"wood"]
@export var doors: Array[StringName] = [&"wood"]
@export var floors: Array[StringName] = [&""]
## Chance each optional piece of a room's type is placed, by wealth.
@export var optional_chance: Array[float] = [0.0, 0.5, 1.0]
## Chance of one extra inner door, making a loop.
@export var loop_chance: float = 0.3

## The entry for `wealth` in a by-wealth list.
static func by_wealth(list: Array, wealth: int) -> Variant:
	return list[clampi(wealth, 0, list.size() - 1)]

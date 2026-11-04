extends Node2D

## Module 10 entry point: the town grid on module 9's ECS, with a debug brush.
## Left-drag paints; 1-4 pick a terrain, 5-8 a floor, 0 clears floor, W a wood wall,
## E a stone wall, X removes a wall; [ and ] change the brush size. Middle-drag pans,
## the wheel zooms. Every tile layer is in the scene under World/TilemapGroup.

@export var catalog: EcsTownCatalog
## Grid size in cells.
@export var grid_size: Vector2i = Vector2i(96, 64)
## Terrain id every cell starts as.
@export var base_terrain: int = 1

@onready var _layers_root: Node = $World/TilemapGroup
@onready var _camera: Camera2D = $Camera2D
@onready var _status: Label = $UI/Root/Status

var _world: EcsWorld
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
var _tile_sync: EcsTileSyncSystem
## What the brush sends, and the terrain, floor or wall id it paints.
var _brush_kind: EcsBuildCommand.Kind = EcsBuildCommand.Kind.SET_TERRAIN
var _brush_id: int = 2
var _brush_size: int = 1
var _painting: bool = false

func _ready() -> void:
	_world = EcsWorld.new()
	_world.add_singleton(EcsTownGrid.make(grid_size.x, grid_size.y, base_terrain))
	_build = EcsBuildCommandSystem.new(catalog)
	_tile_sync = EcsTileSyncSystem.new(_layers_root, catalog)
	_scheduler = EcsScheduler.new()
	_scheduler.add(_build).add(_tile_sync)
	_camera.position = Vector2(grid_size * EcsTownGrid.CELL) * 0.5

func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)
	_status.text = "%s   brush %d   [1-4 terrain, 5-8 floor, 0 clear, W/E wall, X remove, [ ] size]   tile sync %d tiles, %d µs" % [
		_brush_name(), _brush_size, _tile_sync.redrawn, _tile_sync.last_usec]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed
		if _painting:
			_paint()
	elif event is InputEventMouseMotion and _painting:
		_paint()
	elif event is InputEventKey and event.pressed and not event.echo:
		_pick(event.keycode)

func _pick(key: Key) -> void:
	if key >= KEY_1 and key <= KEY_4:
		_brush_kind = EcsBuildCommand.Kind.SET_TERRAIN
		_brush_id = key - KEY_0
	elif key >= KEY_5 and key <= KEY_8:
		_brush_kind = EcsBuildCommand.Kind.SET_FLOOR
		_brush_id = key - KEY_4
	elif key == KEY_0:
		_brush_kind = EcsBuildCommand.Kind.CLEAR_FLOOR
	elif key == KEY_W or key == KEY_E:
		_brush_kind = EcsBuildCommand.Kind.PLACE_WALL
		_brush_id = 1 if key == KEY_W else 2
	elif key == KEY_X:
		_brush_kind = EcsBuildCommand.Kind.REMOVE_STRUCTURE
	elif key == KEY_BRACKETLEFT:
		_brush_size = maxi(_brush_size - 1, 1)
	elif key == KEY_BRACKETRIGHT:
		_brush_size = mini(_brush_size + 1, 8)

## Asks for the brush's cells under the mouse; the build system applies them next tick.
func _paint() -> void:
	var grid := _world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	var centre := EcsTownGrid.cell_at(get_global_mouse_position())
	var half := _brush_size / 2
	for dy in _brush_size:
		for dx in _brush_size:
			grid.commands.append(EcsBuildCommand.make(_brush_kind, centre + Vector2i(dx - half, dy - half), _brush_id))

func _brush_name() -> String:
	match _brush_kind:
		EcsBuildCommand.Kind.SET_TERRAIN:
			return "terrain: %s" % catalog.terrain(_brush_id).display_name
		EcsBuildCommand.Kind.SET_FLOOR:
			return "floor: %s" % catalog.floor_def(_brush_id).display_name
		EcsBuildCommand.Kind.PLACE_WALL:
			return "wall: %s" % catalog.wall(_brush_id).display_name
		EcsBuildCommand.Kind.REMOVE_STRUCTURE:
			return "remove wall"
	return "clear floor"

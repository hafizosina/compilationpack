extends Node2D

## The building generator's viewer: pick a type, wealth, facing, size and seed and the building
## is generated, sent through the real build pipeline, drawn with its rooms, and checked
## (EcsBuildingCheck). Regenerate takes the next seed. Every input change regenerates.

## Ground around the building, in cells; the view frames the building and two of them.
const MARGIN: int = 12
const WEALTH: Array[String] = ["Poor", "Middling", "Rich"]
const FACINGS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
const FACING_NAMES: Array[String] = ["South", "North", "West", "East"]

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog

@onready var _layers_root: Node = $World/TilemapGroup
@onready var _entities_root: Node2D = $World/Entities
@onready var _overlay: EcsTownOverlay = $World/Overlay
@onready var _camera: Camera2D = $Camera2D
@onready var _panel: Control = $UI/Root/Panel
@onready var _type: OptionButton = %Type
@onready var _wealth: OptionButton = %Wealth
@onready var _facing: OptionButton = %Facing
@onready var _width: SpinBox = %Width
@onready var _height: SpinBox = %Height
@onready var _seed: SpinBox = %Seed
@onready var _info: Label = %Info

var _world: EcsWorld
var _manager: EcsEntityManager
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
var _plan: Dictionary = {}
var _plan_usec: int = 0
## Ticks left before the building has settled (entities born, rooms found) and is checked.
var _settle: int = 0
## Set while the inputs are being filled, so that doesn't regenerate.
var _filling: bool = false

func _ready() -> void:
	catalog.number()
	_manager = EcsEntityManager.new(_entities_root)
	_filling = true
	for type in catalog.building_types:
		_type.add_item(type.display_name)
	for name in WEALTH:
		_wealth.add_item(name)
	for name in FACING_NAMES:
		_facing.add_item(name)
	_wealth.select(1)
	_fit_size()
	_filling = false
	_type.item_selected.connect(func(_k: int) -> void: _fit_size(); _generate())
	for option: OptionButton in [_wealth, _facing]:
		option.item_selected.connect(func(_k: int) -> void: _generate())
	for box: SpinBox in [_width, _height, _seed]:
		box.value_changed.connect(func(_v: float) -> void: _generate())
	(%Next as Button).pressed.connect(func() -> void: _seed.value += 1)
	(%Random as Button).pressed.connect(func() -> void: _seed.value = randi() % 100000)
	# The panel eats the mouse, so a click, scroll or drag over it never reaches the camera.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouse:
			_panel.accept_event())
	_generate()

func _physics_process(delta: float) -> void:
	if _scheduler == null:
		return
	_scheduler.run_all(_world, delta)
	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_report()

## The size boxes to the chosen type's range, set to its middle.
func _fit_size() -> void:
	var type := _chosen_type()
	var was := _filling
	_filling = true
	_width.min_value = 5
	_height.min_value = 5
	_width.value = (type.min_size.x + type.max_size.x) / 2
	_height.value = (type.min_size.y + type.max_size.y) / 2
	_filling = was

func _chosen_type() -> EcsBuildingTypeDef:
	return catalog.building_types[_type.selected]

## Generates from the inputs into a new world, and checks it once it has settled.
func _generate() -> void:
	if _filling:
		return
	var size := Vector2i(int(_width.value), int(_height.value))
	var started := Time.get_ticks_usec()
	_plan = EcsBuildingGenerator.plan(_chosen_type(), size, _wealth.selected, FACINGS[_facing.selected],
		int(_seed.value), catalog, entity_catalog, Vector2i(MARGIN, MARGIN))
	_plan_usec = Time.get_ticks_usec() - started
	_manager.clear()
	_world = EcsWorld.new()
	var grid := EcsTownGrid.make(size.x + MARGIN * 2, size.y + MARGIN * 2, catalog.terrain_id(&"grass"))
	grid.commands.append_array(_plan.commands)
	_world.add_singleton(grid)
	_world.add_singleton(EcsLifecycleSingleton.new())
	_build = EcsBuildCommandSystem.new(catalog, entity_catalog)
	var tile_sync := EcsTileSyncSystem.new(_layers_root, catalog)
	tile_sync.roofs_visible = false
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, entity_catalog)) \
		.add(_build) \
		.add(EcsRoomDetectionSystem.new(catalog)) \
		.add(EcsRoofSystem.new(catalog)) \
		.add(tile_sync) \
		.add(EcsTownOverlaySystem.new(_overlay))
	_settle = 3
	_frame(Rect2i(Vector2i(MARGIN - 2, MARGIN - 2), size + Vector2i(4, 4)))
	_info.text = "Generating…"

## Zooms and centres the camera so `cells` fill the view right of the panel.
func _frame(cells: Rect2i) -> void:
	var view := get_viewport_rect().size
	var room := Vector2(view.x - _panel.get_rect().end.x, view.y)
	var span := Vector2(cells.size * EcsTownGrid.CELL)
	var zoom := clampf(minf(room.x / span.x, room.y / span.y), 0.5, 3.0)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = Vector2(cells.position * EcsTownGrid.CELL) + span * 0.5 \
		- Vector2(_panel.get_rect().end.x * 0.5 / zoom, 0)

func _report() -> void:
	var grid := _world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	var building := grid.building_id[EcsTownGrid.index(grid, Vector2i(MARGIN, MARGIN))]
	var problems := EcsBuildingCheck.problems(_world, grid, building, _plan.entrance)
	var roles: PackedStringArray = []
	for room: Dictionary in _plan.rooms:
		roles.append(String(room.role))
	var lines: PackedStringArray = [
		"%d rooms: %s" % [_plan.rooms.size(), ", ".join(roles)],
		"%d commands, %d refused" % [(_plan.commands as Array).size(), _build.refused],
		"Generated in %d µs" % _plan_usec,
	]
	if not (_plan.missing as Array).is_empty():
		lines.append("No room for: %s" % ", ".join(PackedStringArray(_plan.missing)))
	lines.append("Sound" if problems.is_empty() and _build.refused == 0 else "Problems:\n" + "\n".join(PackedStringArray(problems)))
	_info.text = "\n".join(lines)

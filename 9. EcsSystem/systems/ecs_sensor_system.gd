class_name EcsSensorSystem
extends EcsSystem

## Writes physics overlaps into `EcsSensorComponent.perceived` and
## `EcsActionComponent.reached`. Results are one physics tick old.

var _manager: EcsEntityManager

# Node lookups cached per entity. Entries for dead entities are never removed.
var _sensor_area: Dictionary = {}    # entity id -> Area2D
var _sensor_circle: Dictionary = {}  # entity id -> CircleShape2D
var _action_area: Dictionary = {}
var _action_circle: Dictionary = {}

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"sensor"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	for id in world.query([EcsPositionComponent, EcsSensorComponent]):
		var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
		_scan(id, EcsConst.NODE_SENSOR, sensor.radius, sensor.perceived,
			_sensor_area, _sensor_circle)
	for id in world.query([EcsPositionComponent, EcsActionComponent]):
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
		_scan(id, EcsConst.NODE_ACTION, action.radius, action.reached,
			_action_area, _action_circle)

## Sets the area's radius and refills `into` (in place) with the ids it
## overlaps, excluding the entity itself.
func _scan(id: int, kind: StringName, radius: float, into: Array[int],
		areas: Dictionary, circles: Dictionary) -> void:
	into.clear()

	var area: Area2D = areas.get(id)
	if area == null:
		area = _manager.node_for(id, kind) as Area2D
		if area == null:
			return
		areas[id] = area
		circles[id] = (area.get_node(^"Collider") as CollisionShape2D).shape as CircleShape2D

	var circle: CircleShape2D = circles[id]
	if not is_equal_approx(circle.radius, radius):
		circle.radius = radius

	for other: EcsEntityArea in area.get_overlapping_areas():
		if other.entity_id != id:
			into.append(other.entity_id)

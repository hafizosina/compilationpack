class_name EcsSensorSystem
extends EcsSystem

## Writes physics overlaps into `EcsSensorComponent.perceived` and
## `EcsActionComponent.reached`. Results are one physics tick old.

var _manager: EcsEntityManager

# Node lookups cached per entity, pruned when an entity leaves the view.
var _sensor_area: Dictionary = {}    # entity id -> Area2D
var _sensor_circle: Dictionary = {}  # entity id -> CircleShape2D
var _action_area: Dictionary = {}
var _action_circle: Dictionary = {}
var _sensor_view: EcsView
var _action_view: EcsView

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"sensor"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	var sensing := world.view([EcsPositionComponent, EcsSensorComponent])
	if sensing != _sensor_view:
		_sensor_view = sensing
		_prune(world, EcsSensorComponent, _sensor_area, _sensor_circle)
	var sensors := sensing.column(EcsSensorComponent)
	for k in sensing.ids.size():
		var sensor := sensors[k] as EcsSensorComponent
		_scan(sensing.ids[k], EcsConst.NODE_SENSOR, sensor.radius, sensor.perceived,
			_sensor_area, _sensor_circle)
	var acting := world.view([EcsPositionComponent, EcsActionComponent])
	if acting != _action_view:
		_action_view = acting
		_prune(world, EcsActionComponent, _action_area, _action_circle)
	var actions := acting.column(EcsActionComponent)
	for k in acting.ids.size():
		var action := actions[k] as EcsActionComponent
		_scan(acting.ids[k], EcsConst.NODE_ACTION, action.radius, action.reached,
			_action_area, _action_circle)

## Number of entities whose nodes are cached, sensor and action. For tests.
func cached() -> Vector2i:
	return Vector2i(_sensor_area.size(), _action_area.size())

## Drops cached nodes of entities that are dead or no longer have `type`.
static func _prune(world: EcsWorld, type: Script, areas: Dictionary, circles: Dictionary) -> void:
	for id: int in areas.keys():
		if not world.has(id, type):
			areas.erase(id)
			circles.erase(id)

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

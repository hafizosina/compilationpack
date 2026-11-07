class_name EcsSensorSystem
extends EcsSystem

## Writes physics overlaps into `EcsSensorComponent.perceived` and
## `EcsActionComponent.reached`. Results are one physics tick old. An area's enter/exit
## signals only mark its entity; each run rewrites the marked entities' lists, and
## everyone's after a birth, a death or an edit.

## One kind of area (sensor or action): its cached nodes, marks and view.
class Watch:
	var type: Script
	var node_kind: StringName
	var field: StringName  # the component's list of overlapped ids
	var view: EcsView
	var areas: Dictionary = {}      # entity id -> Area2D
	var circles: Dictionary = {}    # entity id -> CircleShape2D
	var colliders: Dictionary = {}  # entity id -> CollisionShape2D
	var marks: Dictionary = {}      # entity id -> Callable connected to its area's signals
	var dirty: Dictionary = {}      # entity ids whose area saw something enter or leave

	func _init(component: Script, kind: StringName, list: StringName) -> void:
		type = component
		node_kind = kind
		field = list

var _manager: EcsEntityManager
var _sensor := Watch.new(EcsSensorComponent, EcsConst.NODE_SENSOR, &"perceived")
var _action := Watch.new(EcsActionComponent, EcsConst.NODE_ACTION, &"reached")
var _edits_seen: int = -1

## Entities whose lists were rewritten. For tests.
var rescanned: int = 0

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"sensor"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	var edits := world.get_singleton(EcsEditSingleton) as EcsEditSingleton
	var edited := edits.applied if edits != null else 0
	var everyone := edited != _edits_seen
	_edits_seen = edited
	_pass(world, _sensor, everyone)
	_pass(world, _action, everyone)

## Number of entities whose nodes are cached, sensor and action. For tests.
func cached() -> Vector2i:
	return Vector2i(_sensor.areas.size(), _action.areas.size())

## Rewrites every entity's list after a change to the view or an edit, else only the marked ones'.
func _pass(world: EcsWorld, watch: Watch, everyone: bool) -> void:
	var view := world.view([EcsPositionComponent, watch.type])
	if view != watch.view:
		watch.view = view
		_prune(world, watch)
		everyone = true
	if everyone:
		var column := view.column(watch.type)
		for k in view.ids.size():
			_scan(view.ids[k], column[k], watch)
	else:
		for id: int in watch.dirty:
			var component := world.get_component(id, watch.type)
			if component != null and world.has(id, EcsPositionComponent):
				_scan(id, component, watch)
	watch.dirty.clear()

## Drops cached nodes and marks of entities that are dead or no longer have the component.
func _prune(world: EcsWorld, watch: Watch) -> void:
	for id: int in watch.areas.keys():
		if world.has(id, watch.type):
			continue
		var area = watch.areas[id]  # Untyped: a dead entity's area is already freed.
		var mark: Callable = watch.marks.get(id, Callable())
		if is_instance_valid(area) and mark.is_valid():
			if area.area_shape_entered.is_connected(mark):
				area.area_shape_entered.disconnect(mark)
			if area.area_shape_exited.is_connected(mark):
				area.area_shape_exited.disconnect(mark)
		watch.areas.erase(id)
		watch.circles.erase(id)
		watch.colliders.erase(id)
		watch.marks.erase(id)
		watch.dirty.erase(id)

# The shape signals, not area_entered/exited: only they report an area freed after it left the tree.
func _mark(_rid: RID, _other, _other_shape: int, _own_shape: int, id: int, dirty: Dictionary) -> void:
	dirty[id] = true

## Sets the area's shape (or its circle's radius) and refills the component's list (in
## place) with the ids it overlaps, excluding the entity itself.
func _scan(id: int, component: EcsComponent, watch: Watch) -> void:
	rescanned += 1
	var into: Array[int] = component.get(watch.field)
	into.clear()

	var area: Area2D = watch.areas.get(id)
	if area == null:
		area = _manager.node_for(id, watch.node_kind) as Area2D
		if area == null:
			return
		watch.areas[id] = area
		var found := area.get_node(^"Collider") as CollisionShape2D
		watch.colliders[id] = found
		watch.circles[id] = found.shape as CircleShape2D
		var mark := _mark.bind(id, watch.dirty)
		area.area_shape_entered.connect(mark)
		area.area_shape_exited.connect(mark)
		watch.marks[id] = mark

	var radius: float = component.get(&"radius")
	var shape: Shape2D = component.get(&"shape")
	var circle: CircleShape2D = watch.circles[id]
	var collider: CollisionShape2D = watch.colliders[id]
	var wanted: Shape2D = shape if shape != null else circle
	if collider.shape != wanted:
		collider.shape = wanted
	if not is_equal_approx(circle.radius, radius):
		circle.radius = radius

	for other: EcsEntityArea in area.get_overlapping_areas():
		if other.entity_id != id:
			into.append(other.entity_id)

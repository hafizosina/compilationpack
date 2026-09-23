class_name EcsSensorSystem
extends EcsSystem

## Turns physics overlaps into component data — sight into
## `EcsSensorComponent.perceived`, reach into `EcsActionComponent.reached` —
## and it is the only system besides EcsCollisionSystem that reads anything
## back off a node.
##
## Keeping it to one system is the point. EcsLowBrainSystem asks what an entity
## can see and EcsPickupSystem asks what it can touch, and neither of them ever
## looks at a node: they read a list of ids off a component like every other
## system reads its inputs. The exception to "nothing reads back off a node"
## therefore stays two files wide, and both of them say so in their header.
##
## ## Why areas and not a distance loop
##
## The brain used to measure to every berry in the world, every tick, for
## every forager — O(foragers x berries) of interpreted GDScript. Godot's
## broadphase buckets the world spatially in C++ and hands back only what
## actually overlaps, so a forager now considers a handful of neighbours no
## matter how many entities exist. Ranking those few — nearest berry — is a sort
## over three or four items and costs nothing.
##
## Only bodies carry a physics layer (EcsConst.LAYER_BODY). Sensors and action
## areas carry none, so they are never reported to each other; without that the
## n² does not disappear, it just moves somewhere you cannot see it.
##
## ## The one tick
##
## `get_overlapping_areas()` reports what the server saw at the end of the last
## step, so both lists are one tick stale, and an entity spawned this tick is in
## nobody's list until the next. Neither matters at walking speed — but a
## headless test must advance a physics frame before reading either list, or it
## will read empty and blame the areas.

var _manager: EcsEntityManager

# Resolved once per entity, then reused. Looking a node up through the manager
# and walking to its CollisionShape2D by path is cheap once and ruinous sixty
# times a second: at 4000 entities that was 8000 dictionary lookups and 8000
# NodePath resolutions per tick, and it measured as a third of this system.
#
# Entries for killed entities are never read again — an id is never reused, so
# it can never come back and match a stale node — but they are also never
# removed. Nothing in the module kills anything yet; if something does, and
# churn is high, prune here.
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

## Writes `radius` onto the area and fills `into` with the entity ids it
## overlaps. Self is dropped: an entity's own body sits inside both of its own
## areas, and every caller would otherwise have to remember to skip it.
##
## `into` is filled in place rather than replaced. The component keeps one array
## for its lifetime instead of being handed a fresh one every tick, which at
## 4000 entities is 8000 allocations a tick that the garbage collector then has
## to walk. Callers read the list within the same tick, so there is nothing
## holding the old contents.
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

	# Everything detectable in this module is a body, and every body is an
	# EcsEntityArea, so the id is a field read rather than a metadata lookup.
	# Self is dropped here: an entity's own body sits inside its own areas.
	for other: EcsEntityArea in area.get_overlapping_areas():
		if other.entity_id != id:
			into.append(other.entity_id)

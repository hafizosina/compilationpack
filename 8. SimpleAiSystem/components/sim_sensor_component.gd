class_name SimSensorComponent
extends SimComponent

## Perception: an Area2D that reports which other entities are within `radius`.
##
## It finds things and nothing else — travelling is MovementComponent's job and
## acting is ActionComponent's. It detects entities through their own physics
## body, so anything the factory spawns is visible without extra setup.
##
## Deliberately reports nothing to the entity inspector: SimSelectionMarker
## already draws this radius around the selected entity, which reads better than
## a number.

## Detection radius in pixels.
var radius: float = 360.0

var _area: Area2D

func slot() -> StringName:
	return &"sensor"

func _ready() -> void:
	super()
	_area = _build_area(radius, "SensorArea")

## Every other entity currently inside the radius. Never includes its own owner.
func get_detected() -> Array:
	var found: Array = []
	if _area == null:
		return found
	for body in _area.get_overlapping_bodies():
		if body is SimEntity and body != entity:
			found.append(body)
	return found

## The closest detected entity carrying `wanted_slot`, or null. This is how the
## brain asks for "food" without ever naming a type — it asks which components
## a candidate has.
func nearest_with(wanted_slot: StringName) -> SimEntity:
	var best: SimEntity = null
	var best_distance := INF
	for candidate in get_detected():
		if not candidate.has_component(wanted_slot):
			continue
		var distance: float = entity.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

## The closest detected entity offering `verb`. The world-side counterpart of
## SimInventoryComponent.find_with_stub(): the same "what can I do with this?"
## question, asked of what is in range rather than what is carried.
func nearest_with_stub(verb: StringName) -> SimEntity:
	var best: SimEntity = null
	var best_distance := INF
	for candidate in get_detected():
		var found: SimEntity = candidate
		if not found.offers(verb):
			continue
		var distance: float = entity.global_position.distance_squared_to(found.global_position)
		if distance < best_distance:
			best_distance = distance
			best = found
	return best

## Shared by Sensor and Action: a monitoring-only circular area on the entity.
func _build_area(area_radius: float, area_name: String) -> Area2D:
	var area := Area2D.new()
	area.name = area_name
	area.collision_layer = 0
	area.collision_mask = SimConst.ENTITY_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = area_radius
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	return area

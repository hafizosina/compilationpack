class_name SimInventoryComponent
extends SimComponent

## Somewhere to put what gets collected — and the owner of the pick-up action,
## since pick-up is the thing an inventory does.
##
## No inventory means the entity cannot pick anything up, and no action
## component means it cannot reach far enough to try. The dependency runs one
## way: inventory needs a hand, the hand knows nothing about inventories.

## Emitted whenever the contents change, carrying the new total.
signal changed(total: int)

## Carry badge: one dot per held item, floating above the entity, in the colour
## the item had in the world. Sizes are SCREEN pixels, divided by the camera
## zoom before drawing, so the badge stays readable at any zoom.
const BADGE_RADIUS := 5.0
const BADGE_GAP := 13.0
const BADGE_HEIGHT := -46.0
const BADGE_OUTLINE := Color(0.09, 0.08, 0.1, 0.9)

## How many items fit. One slot means one berry at a time — collect it, and the
## entity has nowhere to put the next one until something empties this.
var capacity: int = 1

## item id -> count.
var _items: Dictionary = {}
## item id -> the colour it had in the world, for the carry badge.
var _colours: Dictionary = {}

func slot() -> StringName:
	return &"inventory"

func _ready() -> void:
	super()
	z_index = 50

## Attempts to pick `target` up. Returns false if this entity has no action
## component to reach with, if the target is out of reach, if it does not
## advertise pick-up, or if someone else claimed it first.
func try_pick_up(target: SimEntity) -> bool:
	if is_full():
		return false
	var action := entity.get_component(&"action") as SimActionComponent
	if action == null:
		return false
	if not action.in_reach(target):
		return false
	var pickable := target.get_component(&"pickupable") as SimPickUpAbleComponent
	if pickable == null:
		return false
	return pickable.take(entity, self)

## Whether there is no room left.
func is_full() -> bool:
	return total() >= capacity

## Stores `amount` of `item_id`. Returns false, changing nothing, when it will
## not fit — the caller must not consume anything it could not hand over.
func add(item_id: StringName, amount: int = 1, colour: Color = Color.WHITE) -> bool:
	if total() + amount > capacity:
		return false
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	_colours[item_id] = colour
	changed.emit(total())
	queue_redraw()
	return true

func count_of(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))

func total() -> int:
	var sum := 0
	for key in _items:
		sum += int(_items[key])
	return sum

func describe() -> Dictionary:
	var fields := {"slots": "%d / %d" % [total(), capacity]}
	if _items.is_empty():
		fields["carrying"] = "nothing"
		return fields
	for key in _items:
		fields[String(key)] = str(_items[key])
	return fields

## One dot per carried item. Nothing held draws nothing, so an empty animal is
## visually identical to one with no inventory at all.
func _draw() -> void:
	var dots: Array[Color] = []
	for key in _items:
		for i in int(_items[key]):
			dots.append(_colours.get(key, Color.WHITE))
	if dots.is_empty():
		return
	var scale_up := 1.0 / maxf(_camera_zoom(), 0.01)
	var radius := BADGE_RADIUS * scale_up
	var gap := BADGE_GAP * scale_up
	var start := -(dots.size() - 1) * gap * 0.5
	for i in dots.size():
		var at := Vector2(start + i * gap, BADGE_HEIGHT * scale_up)
		draw_circle(at, radius + 1.5 * scale_up, BADGE_OUTLINE)
		draw_circle(at, radius, dots[i])

## Draw scale of the active camera. Falls back to 1.0 outside the tree.
func _camera_zoom() -> float:
	if not is_inside_tree():
		return 1.0
	return get_viewport_transform().get_scale().x

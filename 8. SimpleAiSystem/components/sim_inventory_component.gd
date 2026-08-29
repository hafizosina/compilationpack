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

## PROTOTYPE ONLY — REMOVE BEFORE INTEGRATING WITH OTHER SYSTEMS.
##
## Carry badge: one dot per held item, tucked into the TOP-RIGHT of the sprite's
## own area, in a darkened shade of the colour the item had in the world. Positions and sizes are
## world pixels, not screen pixels, so the badge scales with the sprite and stays
## in its corner at every zoom — it reads as part of the entity rather than as an
## overlay floating above it.
##
## A component that holds state should not also render it. This is here because
## it is the fastest way to see the pick-up loop working while the AI is being
## built, and it is deliberately self-contained so it can be deleted in one go:
## these constants, `_colours`, the `colour` parameter on add(), `_draw()`, the
## `z_index` line in _ready(), and the colour argument PickUpAbleComponent
## passes to add(). Nothing else refers to any of it.
##
## The replacement seam already exists: `changed(total)` is emitted on every
## change, so a separate indicator node or a UI layer can subscribe to it
## without this component knowing anything about drawing.
## Top-right corner of the 64px sprite box, inset so the dot sits fully inside.
const BADGE_ANCHOR := Vector2(19.0, -19.0)
const BADGE_RADIUS := 7.0
const BADGE_OUTLINE_WIDTH := 2.0
## Extra dots stack leftward from the corner.
const BADGE_GAP := 15.0
const BADGE_OUTLINE := Color(0.09, 0.08, 0.1, 0.9)
## Carried items draw darker than the same item lying in the world, so a berry
## on a rabbit's shoulder never reads as a berry on the ground behind it.
const BADGE_DARKEN := 0.32

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
## `colour` feeds the prototype carry badge only — drop the parameter with it.
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

## PROTOTYPE ONLY (see the note at the top). One dot per carried item; nothing
## held draws nothing, so an empty animal looks like one with no inventory.
func _draw() -> void:
	var dots: Array[Color] = []
	for key in _items:
		for i in int(_items[key]):
			dots.append(_colours.get(key, Color.WHITE))
	if dots.is_empty():
		return
	for i in dots.size():
		var at := BADGE_ANCHOR - Vector2(i * BADGE_GAP, 0.0)
		draw_circle(at, BADGE_RADIUS + BADGE_OUTLINE_WIDTH, BADGE_OUTLINE)
		draw_circle(at, BADGE_RADIUS, dots[i].darkened(BADGE_DARKEN))

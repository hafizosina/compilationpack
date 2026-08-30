class_name SimInventoryComponent
extends SimComponent

## Somewhere to put what gets collected — and the owner of the pick-up action,
## since pick-up is the thing an inventory does.
##
## It holds **entities**, not copies of their data. A picked-up berry is moved
## out of the world and parented here with its components intact, so what you
## can do with a carried thing is still decided by which components it has —
## the same rule as everything else. Nothing maps ids to values.
##
## No inventory means the entity cannot pick anything up, and no action
## component means it cannot reach far enough to try. The dependency runs one
## way: inventory needs a hand, the hand knows nothing about inventories.

## Emitted whenever the contents change, carrying the new count.
## No listeners in this prototype; it is the seam a real carry indicator or a
## UI layer should use instead of the badge below.
signal changed(total: int)

## How many entities fit. One slot means one berry at a time.
var capacity: int = 1

## PROTOTYPE ONLY — REMOVE BEFORE INTEGRATING WITH OTHER SYSTEMS.
##
## Carry badge: one dot per held entity, tucked into the TOP-RIGHT of the
## sprite's own area, in a darkened shade of the held entity's own colour.
## World pixels, so it scales with the sprite and stays in its corner.
##
## A component that holds state should not also render it. Self-contained so it
## can be deleted in one go: these constants, `_draw()`, and the `z_index` line
## in `_ready()`. Nothing else refers to it.
const BADGE_ANCHOR := Vector2(19.0, -19.0)
const BADGE_RADIUS := 7.0
const BADGE_OUTLINE_WIDTH := 2.0
const BADGE_GAP := 15.0
const BADGE_OUTLINE := Color(0.09, 0.08, 0.1, 0.9)
const BADGE_DARKEN := 0.32

var _held: Array[SimEntity] = []

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

func is_full() -> bool:
	return _held.size() >= capacity

func total() -> int:
	return _held.size()

## Takes `carried` out of the world and into this inventory. Returns false,
## moving nothing, when there is no room — the caller must not consider a thing
## carried that it could not hand over.
##
## The entity is detached rather than freed, hidden, taken off its collision
## layer so no sensor can still see it, and stopped from processing so its own
## components go quiet in the pocket.
func store(carried: SimEntity) -> bool:
	if carried == null or is_full():
		return false
	var parent := carried.get_parent()
	if parent != null:
		parent.remove_child(carried)
	carried.visible = false
	carried.collision_layer = 0
	carried.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(carried)
	_held.append(carried)
	changed.emit(total())
	queue_redraw()
	return true

## Hands back the first held entity carrying `wanted_slot`, still parented here.
## The caller resolves what to do with it through that component — this only
## finds it, exactly as the sensor does for things in the world.
func held_with(wanted_slot: StringName) -> SimEntity:
	for carried in _held:
		if is_instance_valid(carried) and carried.has_component(wanted_slot):
			return carried
	return null

## Drops `carried` from the ledger once something has consumed it.
func release(carried: SimEntity) -> void:
	_held.erase(carried)
	changed.emit(total())
	queue_redraw()

func describe() -> Dictionary:
	var fields := {"slots": "%d / %d" % [total(), capacity]}
	if _held.is_empty():
		fields["carrying"] = "nothing"
		return fields
	for carried in _held:
		if is_instance_valid(carried):
			fields[String(carried.def_id)] = ", ".join(_slot_names(carried))
	return fields

func _slot_names(carried: SimEntity) -> Array:
	var names: Array = []
	for key in carried.component_slots():
		if key != &"debug":
			names.append(String(key))
	return names

## PROTOTYPE ONLY (see the note at the top).
func _draw() -> void:
	if _held.is_empty():
		return
	for i in _held.size():
		if not is_instance_valid(_held[i]):
			continue
		var at := BADGE_ANCHOR - Vector2(i * BADGE_GAP, 0.0)
		draw_circle(at, BADGE_RADIUS + BADGE_OUTLINE_WIDTH, BADGE_OUTLINE)
		draw_circle(at, BADGE_RADIUS, _held[i].sprite.modulate.darkened(BADGE_DARKEN))

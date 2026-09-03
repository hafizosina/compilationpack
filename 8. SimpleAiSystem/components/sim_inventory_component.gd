class_name SimInventoryComponent
extends SimComponent

## Somewhere to put what gets collected — and the owner of the pick-up action,
## since pick-up is the thing an inventory does.
##
## It holds **blueprints**, not nodes: picking something up wins a resource
## snapshot of the entity (`SimEntity.claim_snapshot()`) and the world entity
## destroys itself in the same breath. What you can do with a carried thing is still decided by
## which component defs it carries — the same rule as everything else, asked of
## a blueprint instead of a live node. Nothing maps ids to values, and nothing
## sits hidden in the scene tree.
##
## No inventory means the entity cannot pick anything up, and no action
## component means it cannot reach far enough to try. The dependencies run one
## way in both directions: inventory needs a hand and the hand knows nothing
## about inventories, and the thing being picked up knows nothing about them
## either — it is asked only to hand itself over.

## Emitted whenever the contents change, carrying the new count.
## No listeners in this prototype; it is the seam a real carry indicator or a
## UI layer should use instead of the badge below.
signal changed(total: int)

## How many entities fit. One slot means one berry at a time.
var capacity: int = 1

## PROTOTYPE ONLY — REMOVE BEFORE INTEGRATING WITH OTHER SYSTEMS.
##
## Carry badge: one dot per held blueprint, tucked into the TOP-RIGHT of the
## sprite's own area, in a darkened shade of the held thing's own tint.
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

var _held: Array[SimEntityDef] = []

func slot() -> StringName:
	return &"inventory"

func _ready() -> void:
	super()
	z_index = 50
	# Whatever used a carried thing announces it on the entity; if it was one of
	# ours, we are the one that drops it. Nothing tells us who did the using.
	if entity != null:
		entity.thing_used.connect(_on_thing_used)

func _on_thing_used(_verb: StringName, target) -> void:
	if target is SimEntityDef and _held.has(target):
		release(target)

## Attempts to pick `target` up. Returns false if this entity has no action
## component to reach with, if the target is out of reach, if it does not
## advertise pick-up, if there is no room, or if someone else claimed it first.
##
## Every reason THIS entity might refuse is checked here, before the target is
## asked, because asking destroys it. Each side resolves only what it alone can
## know: capacity and reach are ours, availability is the target's.
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
	# store() refuses a null snapshot, which is what a lost race returns.
	return store(pickable.claim(entity))

func is_full() -> bool:
	return _held.size() >= capacity

func total() -> int:
	return _held.size()

## Stores a blueprint snapshot. Returns false, storing nothing, when there is no
## room — the caller must not destroy a thing it could not hand over.
func store(snapshot: SimEntityDef) -> bool:
	if snapshot == null or is_full():
		return false
	_held.append(snapshot)
	changed.emit(total())
	queue_redraw()
	return true

## The first held blueprint offering `verb` — `&"consume"`, `&"equip"`, and so
## on. The pocket's version of the sensor's `nearest_with()`: the same "what can
## I do with this?" question, asked of what is carried rather than what is in
## range. The inventory itself does not implement any of those verbs.
func find_with_stub(verb: StringName) -> SimEntityDef:
	for snapshot in _held:
		if snapshot != null and snapshot.offers(verb):
			return snapshot
	return null

## Drops a blueprint from the ledger once something has consumed it.
func release(snapshot: SimEntityDef) -> void:
	_held.erase(snapshot)
	changed.emit(total())
	queue_redraw()

func describe() -> Dictionary:
	var fields := {"slots": "%d / %d" % [total(), capacity]}
	if _held.is_empty():
		fields["carrying"] = "nothing"
		return fields
	for snapshot in _held:
		fields[String(snapshot.id)] = ", ".join(_slot_names(snapshot))
	return fields

func _slot_names(snapshot: SimEntityDef) -> Array:
	var names: Array = []
	for def in snapshot.components:
		if def != null:
			names.append(String(def.slot()))
	return names

## PROTOTYPE ONLY (see the note at the top).
func _draw() -> void:
	if _held.is_empty():
		return
	for i in _held.size():
		var sprite_def := _held[i].component_def(&"sprite") as SimSpriteDef
		var tint: Color = Color.WHITE if sprite_def == null else sprite_def.tint
		var at := BADGE_ANCHOR - Vector2(i * BADGE_GAP, 0.0)
		draw_circle(at, BADGE_RADIUS + BADGE_OUTLINE_WIDTH, BADGE_OUTLINE)
		draw_circle(at, BADGE_RADIUS, tint.darkened(BADGE_DARKEN))

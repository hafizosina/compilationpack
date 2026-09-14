class_name EcsInventoryComponent
extends EcsComponent

## Somewhere to put what gets collected.
##
## It holds **entity ids** — the berries stay live entities with their own
## components, they simply stop having an `EcsPositionComponent` while carried.
##
## That is the same pain case the weapon showed. Module 8's inventory could not
## hold a live entity, so picking something up took a *blueprint snapshot* of it
## and destroyed the world entity in the same breath; a carried thing was a
## recipe for itself rather than itself. Here nothing is snapshotted, nothing is
## destroyed, and what a carried thing can do is still whatever components it
## happens to carry.
##
## Having one of these is what makes an entity forage. No inventory, no
## `EcsForageSystem` query match, so a berry bush never goes looking for berries
## and nothing had to tell it not to.

## How many entities fit.
@export var capacity: int = 5

## Entity ids currently held. Runtime state — a .tres cannot know a runtime id.
var items: Array[int] = []

func key() -> StringName:
	return &"inventory"

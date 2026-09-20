class_name EcsSensorComponent
extends EcsComponent

## How far the entity can see, and what it currently sees.
##
## `radius` is authored and `perceived` is runtime state, the same shape as
## EcsSpawnerComponent's `interval` / `cooldown`. The plan's step 5 described a
## separate `Perceived{ids}` component; folding it in here halves the component
## count for one capability and matches how every other stateful component in
## the module is already written. Split them if a second system ever needs to
## write the list.
##
## Perception is **not** a distance loop. The declared area below is handed to
## Godot's broadphase, which buckets the world spatially in C++ and reports back
## only the handful actually overlapping. A prey therefore perceives in
## O(neighbours) and never walks the world — which is the whole reason this is
## an area and not the `for every entity, measure` the forage system used to do.

## Declares that an entity carrying this component needs an sensor area.
## EcsEntityManager builds it bare at spawn; EcsSensorSystem writes the radius
## into it each tick, because a radius is a value and values are updates.
const NODE_KIND: StringName = EcsConst.NODE_SENSOR
## Carries no layer, so nothing ever detects a sensor — not even another
## sensor. That is what keeps perception O(neighbours): a sensor is reported the
## handful of bodies it covers, never the other 499 sensors.
const NODE_LAYER: int = EcsConst.LAYER_NONE
## It looks for bodies, and only bodies.
const NODE_MASK: int = EcsConst.LAYER_BODY

## Sight radius in pixels, from the entity's position.
@export var radius: float = 260.0

## Entity ids inside that radius as of the last tick, written by EcsSensorSystem
## and by nothing else. Never contains the entity itself.
##
## One tick stale by construction: the physics server resolves overlaps on its
## own schedule, so this is what was true at the end of the previous step. At
## walking speed that is a couple of pixels of lag and no behaviour notices.
var perceived: Array[int] = []

func key() -> StringName:
	return &"sensor"

class_name EcsActionComponent
extends EcsComponent

## Arm's length — how close a thing must be before the entity can act on it,
## and what is currently in reach.
##
## Deliberately a second, smaller area rather than a number compared against the
## sensor's list. Reach is a different question from sight and answering it with
## the same broadphase keeps both answers in the same units: "is it touching me"
## is a real overlap of two real circles, not a distance threshold that has to
## be kept in step with the radii by hand.
##
## Make it larger than the entity's own EcsBodyComponent radius. If it is
## smaller, an entity can be blocked by the very thing it is trying to reach —
## the bodies touch and stop it before its reach ever does.

## Declares that an entity carrying this component needs an action area.
## EcsEntityManager builds it bare at spawn; EcsSensorSystem writes the radius
## into it each tick, because a radius is a value and values are updates.
const NODE_KIND: StringName = EcsConst.NODE_ACTION
## Invisible to everything, like the sensor: reach is something you have, not
## something others can detect about you.
const NODE_LAYER: int = EcsConst.LAYER_NONE
## It looks for bodies, and only bodies.
const NODE_MASK: int = EcsConst.LAYER_BODY

## Reach radius in pixels, from the entity's position.
@export var radius: float = 34.0

## Entity ids whose *body* overlaps that reach as of the last tick, written by
## EcsSensorSystem and by nothing else. Never contains the entity itself.
var reached: Array[int] = []

## Not shown in the entity detail — see inspect/hidden_inspect.gd.
const INSPECTOR := preload("res://9. EcsSystem/inspect/hidden_inspect.gd")

func key() -> StringName:
	return &"action"

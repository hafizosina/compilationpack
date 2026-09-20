class_name EcsShapeComponent
extends EcsComponent

## The entity's body — the space it occupies — as data. A circle.
##
## Deliberately NOT a CollisionShape2D under a PhysicsBody2D. A body here is one
## number in a component table, so anything that ever needs it (collision,
## perception, picking) reads it with an ordinary query, and the whole
## simulation still runs with no scene tree at all. Godot's physics server would
## put the truth back inside nodes and force every system to read it out of the
## view — the exact thing this module exists to avoid.
##
## EcsCollisionSystem is what acts on it, and the Area2D it uses to find
## overlaps is built from this component's declaration below — but the radius
## in that node is a copy, written every tick from the number here. Delete the
## nodes and this is still the entity's body.

## Declares that an entity carrying this component needs a collision area.
## EcsEntityManager builds it bare at spawn; EcsCollisionSystem writes the
## radius into it each tick, because a radius is a value and values are updates.
const NODE_KIND: StringName = EcsConst.NODE_BODY
## A body is the one thing in the world that is *detectable*: it occupies the
## body layer, and it is the only kind that does.
const NODE_LAYER: int = EcsConst.LAYER_BODY
## And it looks for other bodies, because that is what soft collision is — two
## bodies overlapping. This is the only mask in the module that is not purely a
## looker, and it cannot be LAYER_NONE: nothing else in the module detects
## bodies at a body's own radius, so with no mask here there are no collision
## pairs and EcsCollisionSystem has nothing to resolve.
const NODE_MASK: int = EcsConst.LAYER_BODY

## Radius of the body in pixels, measured from the entity's position.
@export var radius: float = 24.0

func key() -> StringName:
	return &"shape"

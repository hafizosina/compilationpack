class_name EcsBodyComponent
extends EcsComponent

## The entity's body — the space it occupies — as data. A circle, and whether
## that circle is in anyone's way.
##
## Deliberately NOT a CollisionShape2D under a PhysicsBody2D. A body here is a
## couple of fields in a component table, so anything that ever needs it
## (collision, perception, picking) reads it with an ordinary query, and the
## whole simulation still runs with no scene tree at all. Godot's physics server
## would put the truth back inside nodes and force every system to read it out
## of the view — the exact thing this module exists to avoid.
##
## EcsCollisionSystem is what acts on it, and the Area2D it uses to find
## overlaps is built from this component's declaration below — but the radius in
## that node is a copy, written every tick from the number here. Delete the
## nodes and this is still the entity's body.
##
## ## Having a body and blocking the way are two different claims
##
## They were one until a berry made the case for two. A berry needs a body for
## exactly one reason — a sensor can only see a body, and reach is the berry's
## body meeting an action area — and being shoved aside by every passing forager
## was never part of the deal: it held the forager a body's width short of the
## thing it walked over to get. So `is_solid` splits them. Clear it and the
## entity is still perceivable, still reachable, still exactly where it says it
## is; it simply is not in anyone's way. Ground items, corpses and dropped tools
## want it off.
##
## **Movable is a third question, and it stays EcsMovementComponent.** A bush is
## solid and immovable: walkers are pushed out of it and it never yields. A
## rabbit is solid and movable. A berry is neither.

## Declares that an entity carrying this component needs a collision area.
## EcsEntityManager builds it bare at spawn; EcsCollisionSystem writes the
## radius into it each tick, because a radius is a value and values are updates.
const NODE_KIND: StringName = EcsConst.NODE_BODY
## A body is the one thing in the world that is *detectable*: it occupies the
## body layer, and it is the only kind that does. This holds whether or not the
## body is solid — being seen is the reason a berry has one at all.
const NODE_LAYER: int = EcsConst.LAYER_BODY
## And it looks for other bodies, because that is what soft collision is — two
## bodies overlapping. This is the only mask in the module that is not purely a
## looker, and it cannot be LAYER_NONE: nothing else in the module detects
## bodies at a body's own radius, so with no mask here there are no collision
## pairs and EcsCollisionSystem has nothing to resolve.
const NODE_MASK: int = EcsConst.LAYER_BODY

## Radius of the body in pixels, measured from the entity's position.
@export var radius: float = 24.0
## Whether this body takes part in soft collision — whether it pushes and is
## pushed. Off means it is walked straight over, while staying every bit as
## visible to a sensor and as reachable by an action area.
##
## Defaults to true because a creature is the common case; a thing lying on the
## ground is the one that has to say so.
@export var is_solid: bool = true

func key() -> StringName:
	return &"body"

## How the inspector shows it: not at all — plumbing a person clicking an animal
## does not want to read. Display only; see EcsComponent.describe().
func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}

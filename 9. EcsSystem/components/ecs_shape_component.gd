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
## Nothing acts on it yet; the debug overlay draws it. That is the seam left for
## a later system, and adding one changes no existing file.

## Radius of the body in pixels, measured from the entity's position.
@export var radius: float = 24.0

func key() -> StringName:
	return &"shape"

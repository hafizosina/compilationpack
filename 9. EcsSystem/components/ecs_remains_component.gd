class_name EcsRemainsComponent
extends EcsComponent

## What it leaves where it dies, by how it died. EcsRemainsSystem spawns it; a death
## with no entry leaves nothing, and EcsDropSystem spills its bag instead.

## Blueprint left, keyed by EcsDyingFlag detail or cause; detail wins. An empty
## value leaves nothing, so `{&"health": &"corpse", &"starved": &""}` leaves no starved body.
@export var leaves: Dictionary[StringName, StringName] = {}
## Draws what it leaves like it, darkened by this much, at its body's size. Below 0 keeps
## the left blueprint's own look.
@export var darken: float = 0.55
## Hands its bag to what it leaves instead of spilling it.
@export var keeps_bag: bool = true

func key() -> StringName:
	return &"remains"

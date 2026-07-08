extends Node2D
class_name Entity

@export var size : int = 10
## How fast the entity moves, in pixels per second.
@export var move_speed : float = 400.0
## How fast the entity turns toward its facing direction (radians per second).
@export var turn_speed : float = 12.0
## Speed multiplier applied while the entity is sprinting.
@export var sprint_multiplier : float = 1.8

## Optional physics body. Present on entities that move via CharacterBody2D
## (e.g. the JoyStick player); null for simple entities (Boid, Selection).
@onready var character_body_2d: CharacterBody2D = get_node_or_null("CharacterBody2D")

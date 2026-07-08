extends Node2D
class_name Entity

@export var size : int = 10

## Optional physics body. Present on entities that move via CharacterBody2D
## (e.g. the JoyStick player); null for simple entities (Boid, Selection).
@onready var character_body_2d: CharacterBody2D = get_node_or_null("CharacterBody2D")

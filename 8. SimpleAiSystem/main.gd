extends Node2D

## Module 8 entry point. Builds the whole world from data on startup — every
## entity on screen comes out of world1.tres via the SimEntityFactory.

@onready var factory: SimEntityFactory = $EntityFactory

func _ready() -> void:
	factory.spawn_world()
	if Constant.DEBUG:
		print("[sim] spawned %s" % [factory.census()])

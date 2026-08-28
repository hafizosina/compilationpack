extends Node2D

## Module 8 entry point. Builds the whole world from data on startup — every
## entity on screen comes out of world1.tres via the SimEntityFactory.
##
## F1 cycles the per-entity debug overlay (off / labels / labels + wander
## leashes), F5 respawns the world (edit world1.tres, hit F5, see the change
## without touching code).

@onready var factory: SimEntityFactory = $EntityFactory

func _ready() -> void:
	EventBus.sim_respawn_requested.connect(_respawn)
	_respawn()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			SimDebugComponent.mode = ((SimDebugComponent.mode + 1)
				% SimDebugComponent.Mode.size()) as SimDebugComponent.Mode
			get_viewport().set_input_as_handled()
		KEY_F5:
			_respawn()
			get_viewport().set_input_as_handled()

func _respawn() -> void:
	factory.spawn_world()
	if Constant.DEBUG:
		factory.debug_report()

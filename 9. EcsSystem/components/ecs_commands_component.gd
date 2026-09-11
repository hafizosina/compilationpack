class_name EcsCommandsComponent
extends EcsComponent

## World singleton: the debug keys' outbox. Input handlers append a request
## here and EcsCommandSystem applies it at the top of the next frame, so the
## rule that nothing outside a system mutates component data survives contact
## with the keyboard.
##
## Each entry is `{ target_name: StringName, component: EcsComponent }` and
## means "toggle this component on that entity".

var queued: Array[Dictionary] = []

func key() -> StringName:
	return &"commands"

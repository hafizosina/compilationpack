extends Node

const QUIT_ACTION := "QuitShortcut"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _input(_event: InputEvent) -> void:
	if not Constant.DEBUG:
		return
	var has_quit_action := InputMap.has_action(QUIT_ACTION) && not InputMap.action_get_events(QUIT_ACTION).is_empty()
		
	if has_quit_action:
		if Input.is_action_just_pressed("QuitShortcut"):
			get_tree().quit()
	else :
		if _event is InputEventKey and _event.pressed and not _event.echo :
			if _event.keycode == Key.KEY_ESCAPE:
				get_tree().quit()

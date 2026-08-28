extends CanvasLayer

## Phase 1 world readout: live entity counts per blueprint, the frame rate, and
## a respawn button.
##
## It holds no reference to the factory — the census arrives on the EventBus and
## the button asks for a respawn the same way, so the panel knows nothing about
## how entities are built.

@onready var counts_label: Label = %CountsLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton

func _ready() -> void:
	EventBus.sim_world_spawned.connect(_on_world_spawned)
	respawn_button.pressed.connect(_on_respawn_pressed)

func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()

func _on_world_spawned(census: Dictionary) -> void:
	var lines: Array[String] = []
	var total := 0
	for id in census:
		var count: int = census[id]
		total += count
		lines.append("%s   %d" % [id, count])
	lines.append("total   %d" % total)
	counts_label.text = "\n".join(lines)

func _on_respawn_pressed() -> void:
	EventBus.sim_respawn_requested.emit()

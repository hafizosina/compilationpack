class_name SimHealthComponent
extends SimBarComponent

## Hit points. The target side of anything damaging: no Health component means
## the entity cannot be hurt, which is the whole of that rule.
##
## Regenerates while the entity is well fed — per COLONY_SIM_CONCEPT.md §2,
## eating is the only healing lever, so Hunger above its threshold is what pays
## for it. Reaching zero disables the brain and movement and leaves the body in
## place (§5): death is a state change, not a scene swap.

## Health regained per second while hunger is above its regen threshold.
var regen_per_second: float = 1.0

var _dead := false

func slot() -> StringName:
	return &"health"

func bar_label() -> String:
	return "health"

func _ready() -> void:
	super()
	emptied.connect(_on_emptied)

func is_dead() -> bool:
	return _dead

func _process(delta: float) -> void:
	super(delta)
	if _dead or regen_per_second <= 0.0:
		return
	var hunger := entity.get_component(&"hunger") as SimHungerComponent
	if hunger != null and hunger.is_well_fed():
		restore(regen_per_second * delta)

func _on_emptied() -> void:
	if _dead:
		return
	_dead = true
	# The body stays; it just stops deciding and stops moving.
	for key in [&"brain", &"movement"]:
		var component: Node = entity.get_component(key)
		if component != null:
			component.set_process(false)
			component.set_physics_process(false)
	var movement := entity.get_component(&"movement") as SimMovementComponent
	if movement != null:
		movement.stop()
	entity.sprite.modulate = entity.sprite.modulate.darkened(0.55)

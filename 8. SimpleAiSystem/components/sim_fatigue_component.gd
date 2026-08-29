class_name SimFatigueComponent
extends SimBarComponent

## How rested the entity is: 100 is fresh, 0 is spent. Drains slowly while idle
## and faster while travelling, so movement has a cost.
##
## Fatigue asks Movement whether it is moving rather than Movement reporting to
## Fatigue — movement stays ignorant of needs, and an entity with no movement
## component simply never pays the travel cost.
##
## **Collapse is owned here, not by the brain.** Running out of energy is not a
## decision, so nothing gets to weigh it against other goals: at zero this
## component puts the entity to sleep itself, switches the brain off, and
## watches its own value until `wake_at`, at which point it switches the brain
## back on. The brain contains no sleep code at all and never learns this
## happened — it simply stops being asked to think for a while.
##
## Voluntary sleep — the Rest *goal*, which the brain does choose — is step 6
## and is not implemented.

## Energy the entity must recover before it wakes.
var wake_at: float = 50.0
## Energy regained per second while asleep.
var recover_per_second: float = 1.0
## Extra units per second spent while the entity is travelling.
var move_drain_per_second: float = 1.5

var _collapsed := false

func slot() -> StringName:
	return &"fatigue"

func bar_label() -> String:
	return "fatigue"

func _ready() -> void:
	super()
	emptied.connect(_on_emptied)

func is_collapsed() -> bool:
	return _collapsed

func extra_drain() -> float:
	var movement := entity.get_component(&"movement") as SimMovementComponent
	if movement != null and movement.is_moving():
		return move_drain_per_second
	return 0.0

func _process(delta: float) -> void:
	if _collapsed:
		# Recovering, not draining — and checking its own condition to wake.
		restore(recover_per_second * delta)
		if value >= wake_at:
			_wake()
		return
	super(delta)

func _on_emptied() -> void:
	if _collapsed:
		return
	_collapsed = true
	entity.is_sleeping = true
	_set_brain_thinking(false)
	# Drop whatever it was walking toward, so it does not resume a stale target.
	var movement := entity.get_component(&"movement") as SimMovementComponent
	if movement != null:
		movement.stop()

func _wake() -> void:
	_collapsed = false
	entity.is_sleeping = false
	_set_brain_thinking(true)

## The brain is switched off wholesale rather than told about sleep — that keeps
## every sleep rule in this one component.
func _set_brain_thinking(thinking: bool) -> void:
	var brain: Node = entity.get_component(&"brain")
	if brain != null:
		brain.set_process(thinking)

func describe_summary() -> Dictionary:
	var reading := "%d / %d" % [roundi(value), roundi(max_value)]
	if _collapsed:
		reading += "  (collapsed, wakes at %d)" % roundi(wake_at)
	return {bar_label(): reading}

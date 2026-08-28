class_name SimMovementDef
extends SimComponentDef

## Blueprint for SimMovementComponent. An entity without this def simply cannot
## move — that is the whole of "capability = component presence" for props.

## Walk speed in px/sec. Shared across every creature type by design.
@export var walk_speed: float = SimConst.WALK_SPEED
## Run speed in px/sec. This is where the type profiles actually differ.
@export var run_speed: float = SimConst.RUN_SPEED
## Distance at which a destination counts as reached.
@export var arrive_radius: float = 8.0

func slot() -> StringName:
	return &"movement"

func build_into(entity: SimEntity) -> void:
	var component := SimMovementComponent.new()
	component.name = "MovementComponent"
	component.walk_speed = walk_speed
	component.run_speed = run_speed
	component.arrive_radius = arrive_radius
	entity.add_child(component)
	entity.register_component(slot(), component)

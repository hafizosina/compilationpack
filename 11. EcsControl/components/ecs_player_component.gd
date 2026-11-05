class_name EcsPlayerComponent
extends EcsComponent

## The player decides for this entity: EcsPlayerControlSystem turns input into its movement
## and intent flags. It stands where a brain would.

## Stick response: 1 is linear, above 1 finer near the centre.
@export var speed_curve: float = 0.9
## Speed multiplier while sprinting.
@export var sprint_multiplier: float = 1.6
## Half-angle of the attack cone around the aim, in degrees.
@export var aim_cone: float = 45.0
## Two sprint presses within this many seconds cast the dash skill.
@export var double_tap_window: float = 0.3
## Skill id per skill stick, 1 to 4; empty means the stick does nothing.
@export var skill_slots: Array[StringName] = [&"block", &"cleave", &"whirlwind", &"fireball"]
## What each skill costs it: x stamina, y mana. A skill it can't pay for doesn't start.
@export var skill_costs: Dictionary[StringName, Vector2] = {
	&"dash": Vector2(25, 0), &"block": Vector2(15, 0), &"cleave": Vector2(20, 0),
	&"whirlwind": Vector2(35, 0), &"fireball": Vector2(0, 30),
}
## Stamina per second sprinting costs; with none left it can't sprint.
@export var sprint_drain: float = 18.0
## Speed multiplier while blocking.
@export var block_move_scale: float = 0.4
## The skill a double-tap of sprint casts.
@export var dash_skill: StringName = &"dash"

## The direction it faces: the aim while aiming, else the way it moves.
var facing: Vector2 = Vector2.RIGHT
## Seconds since sprint was last pressed.
var since_sprint: float = 1000.0
## Seconds since it last swung, hit or miss; a new swing needs the attack's interval.
var since_swing: float = 1000.0

func key() -> StringName:
	return &"player"

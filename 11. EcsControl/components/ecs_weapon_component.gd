class_name EcsWeaponComponent
extends EcsComponent

## What it holds and how a swing looks. Damage stays EcsDamageComponent's.

@export var texture: Texture2D
## Uniform scale for the texture.
@export var scale_factor: float = 0.6
## Distance from the entity's centre to the hand, in px.
@export var hold: float = 14.0
## Degrees a basic attack's swing sweeps, centred on the facing.
@export var swing_arc: float = 130.0
## Seconds it takes.
@export var swing_time: float = 0.16
## Degrees off the facing it rests at between swings.
@export var rest_angle: float = 55.0
## Degrees off the facing it is held at while blocking, across the body.
@export var guard_angle: float = -80.0

## The pose, written by EcsWeaponSystem: the blade's angle in radians,
var angle: float = 0.0
## where the swing's trail starts,
var trail_from: float = 0.0
## and how far through a swing it is, 0 to 1; below 0 at rest.
var progress: float = -1.0
## While blocking, the guarded arc's centre (radians) and width (degrees); width 0 otherwise.
var guard_center: float = 0.0
var guard_arc: float = 0.0

func key() -> StringName:
	return &"weapon"

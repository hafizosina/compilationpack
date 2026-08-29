class_name SimMovementComponent
extends SimComponent

## Travels the entity toward a point at a requested gait. It decides nothing —
## something else (a wander driver now, the GOAP brain in Phase 2) picks the
## destination and calls move_to().
##
## Phase 2 adds `follow(target, gait)` for chases: re-read the target's position
## each tick, fall back to its last known position, then emit `lost_target`.
##
## Deliberately reports nothing to the entity inspector — where a thing is going
## is already visible on screen, and the brain's tab says why.

enum Gait { WALK, RUN }

## Emitted once the entity reaches within `arrive_radius` of its destination.
## No listeners in this prototype — the brain polls is_moving() instead. Kept as
## component API for whatever needs to react to arrival later.
signal arrived(target: Vector2)

## Speed in px/sec at each gait. Set from SimMovementDef.
var walk_speed: float = SimConst.WALK_SPEED
var run_speed: float = SimConst.RUN_SPEED
## How close counts as "there". Too small and the entity jitters on the spot.
var arrive_radius: float = 8.0

var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _gait: Gait = Gait.WALK

func slot() -> StringName:
	return &"movement"

## Heads for `pos` at `gait`. Replaces any destination already in progress.
func move_to(pos: Vector2, gait: Gait = Gait.WALK) -> void:
	_target = pos
	_gait = gait
	_has_target = true

## Cancels the current destination and halts.
func stop() -> void:
	_has_target = false
	if entity != null:
		entity.velocity = Vector2.ZERO

## Whether the entity is currently travelling somewhere.
func is_moving() -> bool:
	return _has_target

## The destination currently being travelled to. Meaningless when not moving.
func target() -> Vector2:
	return _target

## Speed of the gait currently in use.
func current_speed() -> float:
	return run_speed if _gait == Gait.RUN else walk_speed

func _physics_process(_delta: float) -> void:
	if entity == null:
		return
	if not _has_target:
		entity.velocity = Vector2.ZERO
		return

	var to_target := _target - entity.global_position
	if to_target.length() <= arrive_radius:
		_has_target = false
		entity.velocity = Vector2.ZERO
		arrived.emit(_target)
		return

	entity.velocity = to_target.normalized() * current_speed()
	entity.move_and_slide()
	if not is_zero_approx(entity.velocity.x):
		entity.sprite.flip_h = entity.velocity.x < 0.0

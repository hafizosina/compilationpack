class_name EcsProjectileComponent
extends EcsComponent

## Flies straight and hits the first thing with health it reaches, then is gone. Set by its
## launcher at birth.

## Unit direction of flight.
var direction: Vector2 = Vector2.RIGHT
## Who launched it; never hit, and the hit is theirs.
var owner: int = EcsWorld.NO_ENTITY
## Damage on a hit, before armour.
var damage: float = 10.0

func key() -> StringName:
	return &"projectile"

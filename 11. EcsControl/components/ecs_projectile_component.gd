class_name EcsProjectileComponent
extends EcsComponent

## Flies straight and hits the first thing with health it reaches, then is gone. Independent:
## set at birth and never refers back to whoever launched it, so its caster may die meanwhile.

## Unit direction of flight.
var direction: Vector2 = Vector2.RIGHT
## Damage on a hit, before armour, worked out at launch.
var damage: float = 10.0

func key() -> StringName:
	return &"projectile"

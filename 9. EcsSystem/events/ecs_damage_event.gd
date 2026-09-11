class_name EcsDamageEvent
extends EcsEvent

## One landed hit, in flight between systems. The attack system emits it, the
## crit system may scale it, the damage system spends it on the target's health
## and the durability system spends it on the weapon's wear — three consumers,
## each reading the part of the record only it cares about.
##
## This is where "each side resolves what it alone can know" stopped being a
## discipline and became the shape of the code: nothing here asks any system to
## restrain itself, the queries simply do not overlap.

## Who swung.
var from: int = EcsWorld.NO_ENTITY
## Who was hit.
var to: int = EcsWorld.NO_ENTITY
## The weapon that dealt it, or NO_ENTITY for an unarmed blow.
var weapon_id: int = EcsWorld.NO_ENTITY
## Damage before the defender's armour. Mutable in flight — the crit system
## scales this value in place.
var amount: float = 0.0
## Set by the crit system, read only by the HUD.
var critical: bool = false

func _init(p_from: int, p_to: int, p_weapon_id: int, p_amount: float) -> void:
	from = p_from
	to = p_to
	weapon_id = p_weapon_id
	amount = p_amount

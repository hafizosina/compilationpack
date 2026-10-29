class_name EcsHurtFlag
extends EcsFlag

## It was hit since EcsDangerSystem last ran. Raised by EcsDamageSystem.

## Who hit it.
var by: int = EcsWorld.NO_ENTITY

class_name EcsEatIntentFlag
extends EcsFlag

## The brain has decided to eat. Set exactly one field. EcsConsumeSystem eats it
## if it is still there.

## The entity on the ground to eat.
var target_id: int = EcsWorld.NO_ENTITY
## The uid of the record in its own bag to eat.
var record_uid: String = ""

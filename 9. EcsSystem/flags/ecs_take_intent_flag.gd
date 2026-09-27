class_name EcsTakeIntentFlag
extends EcsFlag

## The brain has decided to put something in its bag, and names what.
## EcsPickupSystem is the executor: it takes `target_id` if it is still on the
## ground, unclaimed and within reach, and there is room; otherwise nothing.
##
## Raised and cleared by EcsLowBrainSystem alongside its TAKE state.

## The entity to take. Named `_id` so the inspector shows it as a relationship.
var target_id: int = EcsWorld.NO_ENTITY

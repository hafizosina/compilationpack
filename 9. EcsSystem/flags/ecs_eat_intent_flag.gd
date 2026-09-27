class_name EcsEatIntentFlag
extends EcsFlag

## The brain has decided to eat, and names what — exactly one of the two
## fields: `record_uid` for something in its own bag, `target_id` for something
## on the ground within its action area. EcsConsumeSystem is the executor: it
## eats the named thing if it is still there, and otherwise does nothing,
## leaving the brain to decide again.
##
## Naming the target is what makes the brain the chooser. The executor used to
## pick the meal itself (bag first, then ground); that choice now lives in
## EcsLowBrainSystem with every other choice, and the executor only checks.
##
## Raised and cleared by EcsLowBrainSystem alongside its EAT state, never by
## anything else. Anything that raises it — a planner, a test — drives the
## executor the same way, with no brain involved.

## The entity on the ground to eat. Named `_id` so the inspector shows it as a
## relationship.
var target_id: int = EcsWorld.NO_ENTITY
## The uid of the record in its own bag to eat. A carried item is not an
## entity, so it has no id to name.
var record_uid: String = ""

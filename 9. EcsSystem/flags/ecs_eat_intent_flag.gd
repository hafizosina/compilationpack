class_name EcsEatIntentFlag
extends EcsFlag

## The brain has decided to eat, and names what. EcsConsumeSystem is the
## executor: it eats `target_id` if that is still food and still at hand — in
## its own bag, or on the ground within its action area — and otherwise does
## nothing, leaving the brain to decide again.
##
## Naming the target is what makes the brain the chooser. The executor used to
## pick the meal itself (bag first, then ground); that choice now lives in
## EcsLowBrainSystem with every other choice, and the executor only checks.
##
## Raised and cleared by EcsLowBrainSystem alongside its EAT state, never by
## anything else. Anything that raises it — a planner, a test — drives the
## executor the same way, with no brain involved.

## The entity to eat. Named `_id` so the inspector shows it as a relationship.
var target_id: int = EcsWorld.NO_ENTITY

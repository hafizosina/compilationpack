class_name EcsDyingFlag
extends EcsFlag

## This entity is to be destroyed at the top of the next tick. Carries no data.
##
## It replaces the lifecycle singleton's `kill_requests` list, and does two jobs
## that list could only do one of:
##
##   - **A death note.** EcsEntityManager destroys everything carrying it at the
##     lifecycle stage, so every death in a frame lands at one instant and every
##     system in a tick sees the same set of entities.
##   - **A claim.** It lands in the store the moment it is added, while the death
##     itself waits a tick. So between being eaten or taken and being gone, an
##     item is *claimed*, and every executor that takes or eats refuses anything
##     carrying this. That is what stops one berry being eaten by one creature
##     and pocketed by another in the same tick.
##
## Added by whatever decides something should end — consume, pickup, health.
## Never removed: the entity it is on stops existing instead.

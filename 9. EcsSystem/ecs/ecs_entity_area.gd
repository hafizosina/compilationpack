class_name EcsEntityArea
extends Area2D

## An Area2D that knows which entity it belongs to.
##
## Every area EcsEntityManager builds is one of these — body, sensor, action and
## whatever comes next. It exists for one reason: `get_overlapping_areas()` hands
## back nodes, and the systems reading it need to get from a node back to an
## entity id. That used to be `get_meta(&"entity_id")`, a hashed lookup into the
## node's metadata dictionary for every neighbour of every sensing entity, every
## tick. A typed field is a direct read.
##
## It is not a component and it holds no state. `entity_id` is set once at birth
## by the manager and never written again — it is the node saying which row it is
## a view of, which is the same back-reference the metadata held, just typed.
## Nothing reads simulation state off one of these; that rule is unchanged.

## The entity this area belongs to. Written once, by EcsEntityManager, at spawn.
var entity_id: int = EcsWorld.NO_ENTITY

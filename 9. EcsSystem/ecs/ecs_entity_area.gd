class_name EcsEntityArea
extends Area2D

## An Area2D that knows which entity it belongs to, so overlap results map back
## to entity ids. Holds no state.

## The entity this area belongs to. Set once by EcsEntityManager at spawn.
var entity_id: int = EcsWorld.NO_ENTITY

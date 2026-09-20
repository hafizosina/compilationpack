class_name EcsSpawnRequest
extends RefCounted

## One "please build me an entity" note, written by a system and fulfilled by
## EcsEntityManager at the top of the next tick.
##
## It is a two-way slip rather than a one-way message: the requester keeps its
## own reference and reads `born` back once the manager has filled it in. That
## is what lets EcsSpawnerSystem go on counting its own berries without the
## manager ever learning that a spawner exists.

## Blueprint id, resolved against the catalog.
var type_id: StringName = &""
## Where it lands, in global pixels.
var position: Vector2 = Vector2.ZERO
## Per-component overrides, keyed by component key — `{ "wander": {...} }`.
var overrides: Dictionary = {}
## Optional name. Blank means the manager numbers it after its type.
var entity_name: StringName = &""

## Set by the manager once it has dealt with this note, whatever the outcome.
## Kept separate from `born` because a blueprint that fails to resolve also
## leaves `born` at NO_ENTITY, and a requester waiting on the id alone would
## wait forever for one that is never coming.
var fulfilled: bool = false

## Filled in by the manager: the new entity id, or NO_ENTITY if the blueprint
## did not resolve.
var born: int = EcsWorld.NO_ENTITY

class_name EcsSpawnRequest
extends RefCounted

## A request to create an entity, fulfilled by EcsEntityManager at the next
## lifecycle stage. The requester keeps it and reads `born` afterwards.

## Blueprint id, resolved against the catalog.
var type_id: StringName = &""
## Where it lands, in global pixels.
var position: Vector2 = Vector2.ZERO
## Per-component overrides, keyed by component key — `{ "wander": {...} }`.
var overrides: Dictionary = {}
## Optional name. Blank means the manager numbers it after its type.
var entity_name: StringName = &""
## Set instead of `type_id` to restore a carried item from its record.
var record: EcsItemRecord = null

## True once the manager has handled this request, even if it failed.
var fulfilled: bool = false

## The new entity id, or NO_ENTITY if the blueprint did not resolve.
var born: int = EcsWorld.NO_ENTITY

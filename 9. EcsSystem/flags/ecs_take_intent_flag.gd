class_name EcsTakeIntentFlag
extends EcsFlag

## The brain has decided to pick something up: `target_id` itself, or with
## `record_uid` set, that record out of `target_id`'s bag (looting).
## EcsPickupSystem takes it if it is still there, in reach, and there is room.

## The entity to take, or to loot from.
var target_id: int = EcsWorld.NO_ENTITY
## The record to loot from `target_id`'s inventory, or "".
var record_uid: String = ""

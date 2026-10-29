class_name EcsHarvestIntentFlag
extends EcsFlag

## The brain has decided to harvest `target_id`. EcsHarvestSystem works it while
## it is in reach and drops one yield beside the harvester per `harvest_time`.

## The entity to harvest.
var target_id: int = EcsWorld.NO_ENTITY
## Seconds spent on the current unit.
var progress: float = 0.0

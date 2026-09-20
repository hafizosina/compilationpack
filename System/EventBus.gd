extends Node

signal control_dir(dir :Vector2)

signal health_change(value: float)
signal stamina_change(value: float)
signal mana_change(value: float)

## Emitted by an InventoryComponent whenever its contents change. Carries the
## slot array (entries are ItemStack or null); the inventory UI rebuilds from it.
signal inventory_changed(slots: Array)

## Emitted periodically by module 9's EcsCensusSystem with the number of
## entities alive in its EcsWorld. Pushed rather than polled, so the stats panel
## never reaches into the world.
signal ecs_world_census(count: int)

## Emitted by module 9's stats panel to ask for the world to be rebuilt from its
## EcsWorldDef. Module 9's main scene performs the respawn.
signal ecs_respawn_requested()

## Emitted by module 9's EcsInspectSystem with a snapshot of the selected
## entity, or an empty dictionary when nothing is selected. The snapshot is
## built by reflecting over whatever components the entity happens to carry, so
## a new component kind gets an inspector tab with nothing rewired.
signal ecs_entity_inspected(details: Dictionary)

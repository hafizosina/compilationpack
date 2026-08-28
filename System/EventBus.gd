extends Node

signal control_dir(dir :Vector2)

signal health_change(value: float)
signal stamina_change(value: float)
signal mana_change(value: float)

## Emitted by an InventoryComponent whenever its contents change. Carries the
## slot array (entries are ItemStack or null); the inventory UI rebuilds from it.
signal inventory_changed(slots: Array)

## Emitted by module 8's SimEntityFactory once a world has been spawned. Carries
## a blueprint-id -> live-count census; the sim stats panel rebuilds from it.
signal sim_world_spawned(census: Dictionary)

## Emitted by the sim stats panel to ask for the world to be rebuilt from its
## SimWorldDef. Module 8's main scene performs the respawn.
signal sim_respawn_requested()

## Emitted by module 8's main scene with a snapshot of the entity currently
## being inspected, or an empty dictionary when the selection is cleared. The
## inspector panel rebuilds from it and never touches the entity itself.
signal sim_entity_inspected(details: Dictionary)

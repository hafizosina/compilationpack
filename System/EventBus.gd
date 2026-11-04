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

## Emitted by module 9's main scene when the simulation pauses or resumes.
signal ecs_pause_changed(paused: bool)

## Module 9's top bar asks to toggle pause, as Space does.
signal ecs_pause_requested()

## Module 9's top bar asks to toggle the debug overlay, as F1 does.
signal ecs_overlay_toggle_requested()

## Emitted by module 9's main scene when the debug overlay is shown or hidden.
signal ecs_overlay_changed(shown: bool)

## Emitted every second by module 9's EcsCensusSystem with every entity, as
## `{id, name, type}` dictionaries, for the outliner.
signal ecs_entities_listed(entries: Array)

## Module 9's outliner asks to select entity `id`, or toggle it when `additive`.
signal ecs_entity_pick_requested(id: int, additive: bool)

## Module 9's outliner or inspector asks to centre the camera on entity `id`.
signal ecs_camera_focus_requested(id: int)

## Module 9's HUD asks for the world to be saved or loaded under a name.
signal ecs_save_requested(save_name: String)
signal ecs_load_requested(save_name: String)

## Emitted by module 9's main scene when it starts on a clean world, with the
## maps the start menu offers.
signal ecs_start_menu_opened(map_names: PackedStringArray)

## Module 9's start menu asks for a new world built from the map called `map_name`;
## an empty name asks for an empty world.
signal ecs_new_world_requested(map_name: String)

## Emitted by module 9's main scene after any change, with every save as
## `{name, time}` (time in Unix seconds), newest first.
signal ecs_saves_changed(saves: Array)

## Module 9's save manager asks for the save called `save_name` to be deleted.
signal ecs_save_delete_requested(save_name: String)

## Emitted by module 9's main scene with every blueprint it can spawn
## (Array of EcsEntityDef), built-in and composed.
signal ecs_catalog_changed(defs: Array)

## The blueprint id module 9 places on left-click; empty stops placing.
## The HUD picks it; the main scene clears it on right-click or Escape.
signal ecs_place_type_chosen(type_id: StringName)

## Emitted by module 9's composer after it saves a blueprint to `path`.
signal ecs_blueprint_saved(path: String)

## Module 9's blueprint library asks for the composed blueprint `type_id` to be
## deleted. Built-in blueprints are never deleted.
signal ecs_blueprint_delete_requested(type_id: StringName)

## Emitted by module 9's EcsInspectSystem with a snapshot of the selected
## entity, or an empty dictionary when nothing is selected. The snapshot is
## built by reflecting over whatever components the entity happens to carry, so
## a new component kind gets an inspector tab with nothing rewired.
signal ecs_entity_inspected(details: Dictionary)

## Emitted by module 9's inspector to set `field` of component `component` on
## each of `ids`; main.gd hands it to EcsEditSystem.
signal ecs_entity_edit_requested(ids: Array, component: StringName, field: StringName, value: Variant)

## Emitted by module 9's inspector (or the Delete key) to remove each of `ids`.
signal ecs_entity_remove_requested(ids: Array)

extends Node

signal control_dir(dir :Vector2)

signal health_change(value: float)
signal stamina_change(value: float)
signal mana_change(value: float)

## Emitted by an InventoryComponent whenever its contents change. Carries the
## slot array (entries are ItemStack or null); the inventory UI rebuilds from it.
signal inventory_changed(slots: Array)

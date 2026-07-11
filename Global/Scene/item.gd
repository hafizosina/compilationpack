class_name Item
extends Resource

## Data-only definition of an item. Concrete items are .tres resources that fill
## these fields in the inspector; the InventoryComponent stores references to them.

## Stable identifier (handy for lookups / saving later).
@export var id: StringName
## Human-readable name shown in the UI.
@export var display_name: String
## Icon drawn in inventory slots.
@export var icon: Texture2D
## How many of this item fit in a single stack/slot.
@export var max_stack: int = 99
@export_multiline var description: String

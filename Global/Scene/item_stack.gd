class_name ItemStack
extends RefCounted

## One occupied inventory slot: an item plus how many of it are stacked there.
## Runtime-only (not a Resource) — the InventoryComponent owns these.

var item: Item
var count: int = 0

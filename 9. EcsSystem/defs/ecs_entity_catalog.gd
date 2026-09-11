class_name EcsEntityCatalog
extends Resource

## The blueprint book: id -> EcsEntityDef. Kept separate from the placement list
## so thirty rabbits do not each repeat their component block.

## Every blueprint this world can spawn.
@export var defs: Array[EcsEntityDef] = []:
	set(value):
		defs = value
		_index_built = false

var _index: Dictionary = {}
var _index_built: bool = false

## The blueprint registered under `id`, or null with an error pushed. Never
## crashes the spawn loop.
func get_def(wanted: StringName) -> EcsEntityDef:
	if not _index_built:
		_rebuild_index()
	var def: EcsEntityDef = _index.get(wanted)
	if def == null:
		push_error("EcsEntityCatalog: no blueprint with id '%s'" % wanted)
	return def

func has_def(wanted: StringName) -> bool:
	if not _index_built:
		_rebuild_index()
	return _index.has(wanted)

func _rebuild_index() -> void:
	_index.clear()
	for def in defs:
		if def == null:
			continue
		if def.id == &"":
			push_warning("EcsEntityCatalog: blueprint with empty id skipped")
			continue
		_index[def.id] = def
	_index_built = true

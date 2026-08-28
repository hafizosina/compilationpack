class_name SimEntityCatalog
extends Resource

## The blueprint book: id -> SimEntityDef. Kept separate from the placement
## list so ten Type1s don't each repeat their component block.

## Every blueprint this world can spawn.
@export var defs: Array[SimEntityDef] = []:
	set(value):
		defs = value
		_index_built = false

## Lazily built id -> def index. Resources get no _ready(), so it is filled on
## first lookup and rebuilt whenever `defs` is reassigned.
var _index: Dictionary = {}
var _index_built: bool = false

## The blueprint registered under `id`, or null (with an error pushed) if the
## catalog has no such entry. Never crashes the spawn loop.
func get_def(id: StringName) -> SimEntityDef:
	if not _index_built:
		_rebuild_index()
	var def: SimEntityDef = _index.get(id)
	if def == null:
		push_error("SimEntityCatalog: no blueprint with id '%s'" % id)
	return def

## Every blueprint id in the catalog.
func ids() -> Array:
	if not _index_built:
		_rebuild_index()
	return _index.keys()

func _rebuild_index() -> void:
	_index.clear()
	for def in defs:
		if def == null:
			continue
		if def.id == &"":
			push_warning("SimEntityCatalog: blueprint with empty id skipped")
			continue
		_index[def.id] = def
	_index_built = true

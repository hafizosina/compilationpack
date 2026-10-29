class_name EcsView
extends RefCounted

## A cached query result: the matching ids plus one column of component
## references per included type, index-aligned. Built by `EcsWorld.view()`.
##
##   var view := world.view([EcsPositionComponent, EcsMovementComponent])
##   var moves := view.column(EcsMovementComponent)
##   for k in view.ids.size():
##       var move := moves[k] as EcsMovementComponent
##
## Read only. A rebuild makes new arrays, so a loop over an old view is safe.

## The entities that matched.
var ids: Array[int] = []
## Script -> Array of EcsComponent, index-aligned with `ids`.
var _columns: Dictionary = {}
## The table versions this view was built from.
var _types: Array[Script] = []
var _stamp := PackedInt64Array()

## The components of one included type, index-aligned with `ids`.
func column(type: Script) -> Array:
	return _columns.get(type, [])

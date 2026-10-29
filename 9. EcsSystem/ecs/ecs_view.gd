class_name EcsView
extends RefCounted

## A query's answer, kept: the ids, and beside them one column of component
## references per included type, in the same order. `EcsWorld.view()` builds it
## and hands back the same one every tick until a table it names changes.
##
##   var view := world.view([EcsPositionComponent, EcsMovementComponent])
##   var moves := view.column(EcsMovementComponent)
##   for k in view.ids.size():
##       var move := moves[k] as EcsMovementComponent
##
## Walking it is reading arrays — no call and no dictionary per entity, which
## is what get_component() costs (tests/fetch_bench.tscn: ~0.66 us per get,
## ~0.05 us per array read).
##
## **Read it; never change it.** A rebuild makes new arrays rather than
## refilling these, so a system still walking an old view is never disturbed
## by a change it made itself — adding a flag mid-loop, say. That is the same
## promise query() makes by returning a fresh array.

## The entities that matched, in the order every column follows.
var ids: Array[int] = []
## Script -> Array of EcsComponent, index-aligned with `ids`.
var _columns: Dictionary = {}
## The version of each table this was built from, in the order `_types` lists
## them; any one different means rebuild.
var _types: Array[Script] = []
var _stamp := PackedInt64Array()

## The references for one included type, index-aligned with `ids`. Only
## included types have a column; an excluded one has nothing to show.
func column(type: Script) -> Array:
	return _columns.get(type, [])

class_name EcsLifecycleSingleton
extends EcsSingleton

## The world's structural inbox — one singleton holding the spawn and kill
## notes raised this tick, drained by EcsEntityManager at the top of the next.
##
## Same shape as EcsSelectionSingleton, and for the same reason: a system
## records an intent here and a later pass resolves it, so nothing ever changes
## the shape of the world in the middle of another system's query. Every birth
## and death in a frame therefore lands at one instant, and every system after
## that instant sees the same world.

## Notes awaiting fulfilment. The requester keeps its own reference so it can
## read `born` back on a later tick.
var spawn_requests: Array[EcsSpawnRequest] = []
## Entity ids to destroy — component data and nodes together.
var kill_requests: Array[int] = []

func key() -> StringName:
	return &"lifecycle"
